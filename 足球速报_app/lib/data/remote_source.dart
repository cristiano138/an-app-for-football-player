import 'dart:convert';

import 'package:http/http.dart' as http;

/// 远端数据源：WorkBuddy 定时任务每天 07:10 发布的最新 data.js
class RemoteSource {
  static const url =
      'https://football-daily-brief-22553.app.workbuddy.host/data.js';

  /// 拉取远端 data.js；失败返回空串
  static Future<String> fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        // data.js 为 UTF-8 编码
        return utf8.decode(resp.bodyBytes, allowMalformed: true);
      }
    } catch (_) {
      // 网络失败由上层统一降级处理
    }
    return '';
  }
}
