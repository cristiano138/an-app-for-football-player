import 'package:flutter/services.dart' show rootBundle;

import '../models/report.dart';
import 'js_parser.dart';

/// assets 内置兜底数据：首次安装、断网、远端挂掉时都能看到内容
class BundledData {
  static const assetPath = 'assets/data/report-data.js';

  /// 返回 (报告列表, 原始字符串)。解析失败返回空列表。
  static Future<(List<Report>, String)> load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      return (parseReports(raw), raw);
    } catch (_) {
      return (<Report>[], '');
    }
  }

  static List<Report> parseReports(String raw) {
    try {
      final arr = JsParser.extractArray(raw) as List<dynamic>;
      final reports = arr.map(Report.fromJson).toList();
      reports.sort((a, b) => a.date.compareTo(b.date) * -1); // 日期倒序
      return reports;
    } catch (_) {
      return <Report>[];
    }
  }
}
