import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// App 更新站点基础地址（与数据源同一站点）
const String kUpdateSiteBase = 'https://football-daily-brief-22553.app.workbuddy.host';

// ==================== 纯函数（可单测，不依赖任何 Flutter 插件） ====================

/// 版本比较：远端 versionCode 大于本地才算有新版
bool hasNewVersion({required int remoteCode, required int localCode}) =>
    remoteCode > localCode;

/// 是否需要强制更新：远端 minVersionCode 大于本地 versionCode
bool needForceUpdate({required int minVersionCode, required int localCode}) =>
    minVersionCode > localCode;

/// 按设备 ABI 挑选下载地址：arm64 机型优先用小体积包（约 20MB），其余用通用包
String pickApkUrl({required String universalUrl, required String arm64Url, required List<String> deviceAbis}) {
  if (arm64Url.isNotEmpty && deviceAbis.contains('arm64-v8a')) return arm64Url;
  return universalUrl;
}

/// 远端 update.json 的解析结果
class UpdateInfo {
  final String version;
  final int versionCode;

  /// 最低可用版本：本地低于它时强制更新（不允许「以后再说」）；缺省 0 = 不强制
  final int minVersionCode;

  /// arm64 专属小体积包（可选；为空或机型不支持时用 apkUrl 通用包）
  final String apkUrlArm64;
  final String apkUrl;
  final String notes;
  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    this.minVersionCode = 0,
    this.apkUrlArm64 = '',
    this.notes = '',
  });
}

/// 解析 update.json 文本；任何解析失败/缺关键字段都返回 null（调用方按"已是最新"处理）
UpdateInfo? parseUpdateJson(String body) {
  try {
    final dynamic j = jsonDecode(body);
    if (j is! Map<String, dynamic>) return null;
    final v = j['version'];
    final c = j['versionCode'];
    final u = j['apkUrl'];
    if (v is! String || v.isEmpty) return null;
    if (c is! int) return null;
    if (u is! String || u.isEmpty) return null;
    return UpdateInfo(
      version: v,
      versionCode: c,
      apkUrl: u,
      minVersionCode: j['minVersionCode'] is int ? j['minVersionCode'] as int : 0,
      apkUrlArm64: j['apkUrlArm64'] is String ? j['apkUrlArm64'] as String : '',
      notes: j['notes'] is String ? j['notes'] as String : '',
    );
  } catch (_) {
    return null;
  }
}

/// 检查结果：info 非 null = 有新版；upToDate = 已最新；networkError = 网络问题
class UpdateCheckOutcome {
  final UpdateInfo? info;
  final bool networkError;
  const UpdateCheckOutcome._(this.info, this.networkError);
  const UpdateCheckOutcome.found(UpdateInfo i) : this._(i, false);
  const UpdateCheckOutcome.upToDate() : this._(null, false);
  const UpdateCheckOutcome.network() : this._(null, true);
}

// ==================== 服务 ====================

/// App 手动更新：检查（?t= 防CDN缓存）→ 下载（分块+进度）→ 调起安装
class AppUpdateService {
  final http.Client _client = http.Client();

  /// 清理临时 apk：每次点「检查 App 更新」时先删旧文件
  Future<void> cleanTemp() async {
    try {
      final dir = await _updateDir();
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 检查更新。404/解析失败/字段缺失 → upToDate；网络异常 → networkError
  Future<UpdateCheckOutcome> checkUpdate({required int localCode}) async {
    try {
      final uri = Uri.parse(
          '$kUpdateSiteBase/update.json?t=${DateTime.now().millisecondsSinceEpoch}');
      final resp = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return const UpdateCheckOutcome.upToDate();
      final info = parseUpdateJson(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (info == null) return const UpdateCheckOutcome.upToDate();
      if (!hasNewVersion(remoteCode: info.versionCode, localCode: localCode)) {
        return const UpdateCheckOutcome.upToDate();
      }
      return UpdateCheckOutcome.found(info);
    } catch (_) {
      return const UpdateCheckOutcome.network();
    }
  }

  /// 下载 apk 到 临时目录/update/`football-<versionCode>.apk`
  /// [downloadUrl] 缺省用 info.apkUrl（arm64 机型可传专属小包地址）。
  /// [onProgress] received/total 字节；total 为 null 表示服务器未告知总长（不确定进度）。
  /// [isCancelled] 每块检查一次，返回 true 则中止并删除半成品、抛 _Cancelled。
  Future<String> downloadApk(
    UpdateInfo info, {
    String? downloadUrl,
    required void Function(int received, int? total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final dir = await _updateDir();
    await dir.create(recursive: true);
    final savePath = '${dir.path}${Platform.pathSeparator}football-${info.versionCode}.apk';
    final tmpPath = '$savePath.part';

    final uri = Uri.parse(downloadUrl ?? info.apkUrl);
    final req = http.Request('GET', uri);
    final resp = await _client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw const _DlException('下载失败，请重试');
    }
    final total = resp.contentLength;
    final sink = File(tmpPath).openWrite();
    var received = 0;
    try {
      await for (final chunk in resp.stream) {
        if (isCancelled()) {
          throw const _Cancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close().catchError((_) {});
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      rethrow;
    }
    // 下载完成：改名就位
    final f = File(tmpPath);
    try {
      await f.rename(savePath);
    } catch (_) {
      // 个别场景 rename 跨不了权限时退化为复制
      await f.copy(savePath);
      try {
        await f.delete();
      } catch (_) {}
    }
    return savePath;
  }

  Future<Directory> _updateDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}${Platform.pathSeparator}update');
  }

  void dispose() => _client.close();
}

class _DlException implements Exception {
  final String message;
  const _DlException(this.message);
  @override
  String toString() => message;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// 供 UI 判断取消/失败异常的类型
bool isDownloadCancelled(Object e) => e is _Cancelled;
String downloadErrorMessage(Object e) =>
    e is _DlException ? e.message : '下载失败，请重试';
