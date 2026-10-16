import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 本地缓存：上次成功拉取的 data.js 原文存到应用文档目录
class CacheStore {
  static const fileName = 'cached-report-data.js';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// 返回缓存的原始字符串；不存在/读失败返回空串
  static Future<String> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return '';
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> write(String raw) async {
    try {
      final f = await _file();
      await f.writeAsString(raw, flush: true);
    } catch (_) {
      // 缓存写失败不影响主流程
    }
  }
}
