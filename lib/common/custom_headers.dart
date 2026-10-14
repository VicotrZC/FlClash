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

  /// 逐行校验编辑框内容，返回第一条格式不对的行号（从 1 开始），没有则返回 null。
  ///
  /// 与 [parse] 的容错规则必须一致：parse 会跳过空行，这里也跳过，
  /// 否则用户只是多敲了个回车就会被拦下。
  ///
  /// 之所以要校验而不是像 parse 那样静默跳过：编辑已有配置时，被跳过的那行
  /// 会在下次保存时无声消失，用户不会知道自己写错了。
  static int? firstInvalidLine(String? text) {
    final value = text ?? '';
    if (value.trim().isEmpty) {
      return null;
    }
    final lines = value.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0 ||
          line.substring(0, separator).replaceAll(RegExp(r'\s'), '').isEmpty) {
        return index + 1;
      }
    }
    return null;
  }
}
