/// 自定义订阅请求头的解析与格式化。
///
/// 在 UI 里以「每行一个 `名称: 值`」的多行文本编辑，存库时转成 Map。
abstract final class CustomHeaders {
  /// 解析多行文本；忽略空行与不含 `:` 的行。
  ///
  /// 名称与值都会被 trim，名称中的空白会被移除（HTTP 头名不允许空格）。
  /// 同名时后者覆盖前者。
  static Map<String, String> parse(String? text) {
    final result = <String, String>{};
    if (text == null || text.trim().isEmpty) return result;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final name = line.substring(0, separator).replaceAll(RegExp(r'\s'), '');
      final value = line.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      result[name] = value;
    }
    return result;
  }

  /// 把 Map 还原成多行文本，供编辑框回显。
  static String format(Map<String, String> headers) {
    return headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}
