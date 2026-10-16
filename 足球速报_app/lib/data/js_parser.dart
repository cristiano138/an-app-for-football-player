import 'dart:convert';

/// 把 `window.REPORTS = [...]` 这种 JS 变量声明剥壳，取出 JSON 主体再解码。
/// 兼容 `var xxx = [...]` / `window.xxx = [...]` / 末尾分号 / BOM。
class JsParser {
  /// 返回解析出的原始 JSON 数组（`List<dynamic>`），失败抛 FormatException。
  static dynamic extractArray(String raw) {
    var s = raw;
    // 去掉 BOM 与零宽字符
    if (s.isNotEmpty) {
      final first = s.codeUnitAt(0);
      if (first == 0xFEFF || first == 0x200B || first == 0x200E) {
        s = s.substring(1);
      }
    }
    // 定位 '=' 之后的第一个 '['
    final eq = s.indexOf('=');
    final start = s.indexOf('[', eq < 0 ? 0 : eq);
    if (start < 0) {
      throw const FormatException('未找到数组起始符 [');
    }
    // 定位最后一个 ']'（末尾可能是 `];` 或 `]`）
    final end = s.lastIndexOf(']');
    if (end <= start) {
      throw const FormatException('未找到数组结束符 ]');
    }
    final body = s.substring(start, end + 1);
    return jsonDecode(body);
  }
}
