import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/report.dart';
import 'bundled_data.dart';
import 'cache_store.dart';
import 'remote_source.dart';

/// 数据仓库：三层降级（远端 → 本地缓存 → assets 内置）
/// 启动流程：内置/缓存先秒开 → 异步拉远端 → 成功刷新+写缓存 → 失败轻提示
class DataRepository extends ChangeNotifier {
  List<Report> _reports = [];
  bool _loading = true;      // 首屏加载中
  bool _syncing = false;     // 正在检查更新
  String _notice = '';       // 轻提示（离线等），空串表示无
  DateTime? _lastSync;
  String _source = '';       // 内置 / 缓存 / 远端 / 导入

  List<Report> get reports => _reports;
  bool get loading => _loading;
  bool get syncing => _syncing;
  String get notice => _notice;
  DateTime? get lastSync => _lastSync;
  String get source => _source;

  /// 启动初始化：先取内置与缓存中较新的一份，再异步拉远端
  Future<void> init() async {
    final (bundled, _) = await BundledData.load();
    final cachedRaw = await CacheStore.read();
    final cached = cachedRaw.isEmpty ? <Report>[] : BundledData.parseReports(cachedRaw);

    final bNewest = bundled.isEmpty ? null : bundled.first;
    if (cached.isNotEmpty && (bundled.isEmpty || cached.first.isNewerThan(bNewest))) {
      _reports = cached;
      _source = '本地缓存';
    } else if (bundled.isNotEmpty) {
      _reports = bundled;
      _source = '内置数据';
    } else if (cached.isNotEmpty) {
      _reports = cached;
      _source = '本地缓存';
    }
    _loading = false;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('last_sync_ms');
    if (ms != null) _lastSync = DateTime.fromMillisecondsSinceEpoch(ms);

    // 远端拉取异步进行，不阻塞首屏
    await refresh(fromUser: false);
  }

  /// 拉取远端最新数据。成功且更新则替换并写缓存；失败则轻提示离线。
  Future<String> refresh({bool fromUser = true}) async {
    if (_syncing) return '正在检查更新…';
    _syncing = true;
    if (fromUser) notifyListeners();
    final raw = await RemoteSource.fetch();
    _syncing = false;

    if (raw.isEmpty) {
      _notice = fromUser ? '网络不可用，检查更新失败' : '离线模式，显示上次更新内容';
      notifyListeners();
      return _notice;
    }

    final parsed = BundledData.parseReports(raw);
    if (parsed.isEmpty) {
      _notice = fromUser ? '远端数据格式异常，已保留当前内容' : '离线模式，显示上次更新内容';
      notifyListeners();
      return _notice;
    }

    final newest = parsed.isEmpty ? null : parsed.first;
    final curNewest = _reports.isEmpty ? null : _reports.first;
    if (curNewest == null || newest!.isNewerThan(curNewest) || parsed.length > _reports.length) {
      _reports = parsed;
      _source = '远端数据';
      await CacheStore.write(raw);
    }
    _notice = '';
    _lastSync = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_sync_ms', _lastSync!.millisecondsSinceEpoch);
    notifyListeners();
    return '已更新至最新数据';
  }

  /// 手动导入 data.js（系统文件选择器）
  Future<String> importRaw(String raw) async {
    final parsed = BundledData.parseReports(raw);
    if (parsed.isEmpty) return '导入失败：文件格式无法解析';
    _reports = parsed;
    _source = '手动导入';
    await CacheStore.write(raw);
    _notice = '';
    _lastSync = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_sync_ms', _lastSync!.millisecondsSinceEpoch);
    notifyListeners();
    return '导入成功，共 ${parsed.length} 期速报';
  }
}

/// 文件导入用的 File 读取辅助（file_selector 返回 path 后读取）
Future<String> readFileAsString(String path) async {
  return File(path).readAsString();
}
