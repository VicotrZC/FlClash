/// 自定义订阅请求头的解析与格式化。
///
/// 在 UI 里以「每行一个 `名称: 值`」的多行文本编辑，存库时转成 Map。
abstract final class CustomHeaders {
  /// HTTP 头名只允许 RFC 7230 的 tchar。
  ///
  /// 允许范围之外的字符（`(`、`@`、`/`、`?`、非 ASCII 等）是非法头名，
  /// 交给 Dio 只会在发请求时抛一个看不出原因的错误，所以这里直接判为无效。
  static final _headerName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  /// 头值不允许任何控制字符，含 CR / LF。
  ///
  /// `dart:io` 的 HttpClient 遇到 CR/LF 会抛 HttpException，而界面上只会
  /// 显示「订阅更新失败」——用户无法知道是自己粘进来的换行符导致的。
  static final _controlChar = RegExp(r'[\x00-\x1F\x7F]');

  /// 解析多行文本；忽略空行、格式不对的行，以及头名/头值非法的行。
  ///
  /// 名称中的空白会被移除（HTTP 头名不允许空格），名称与值都会 trim。
  /// 同名时后者覆盖前者。
  static Map<String, String> parse(String? text) {
    final result = <String, String>{};
    if (text == null || text.trim().isEmpty) return result;
    for (final rawLine in text.split('\n')) {
      final entry = _parseLine(rawLine);
      if (entry == null) continue;
      result[entry.$1] = entry.$2;
    }
    return result;
  }

  /// 把 Map 还原成多行文本，供编辑框回显。
  static String format(Map<String, String> headers) {
    return headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

  /// 逐行校验编辑框内容，返回第一条格式不对的行号（从 1 开始），没有则返回 null。
  ///
  /// 与 [parse] 的容错规则必须一致：两者都走 [_parseLine]，空行也一起跳过，
  /// 否则用户只是多敲了个回车就会被拦下。
  ///
  /// 之所以要校验而不是像 [parse] 那样静默跳过：编辑已有配置时，被跳过的那行
  /// 会在下次保存时无声消失，用户不会知道自己写错了。
  static int? firstInvalidLine(String? text) {
    final value = text ?? '';
    if (value.trim().isEmpty) {
      return null;
    }
    final lines = value.split('\n');
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim().isEmpty) {
        continue;
      }
      if (_parseLine(lines[index]) == null) {
        return index + 1;
      }
    }
    return null;
  }

  /// 解析一行，返回 `(头名, 头值)`；空行或非法行返回 null。
  ///
  /// [parse] 与 [firstInvalidLine] 共用这一处判定，保证「能存下来的」
  /// 与「校验通过的」永远一致。
  static (String, String)? _parseLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;
    final separator = line.indexOf(':');
    if (separator <= 0) return null;
    final name = line.substring(0, separator).replaceAll(RegExp(r'\s'), '');
    if (!_headerName.hasMatch(name)) return null;
    final value = line.substring(separator + 1).trim();
    if (_controlChar.hasMatch(value)) return null;
    return (name, value);
  }
}
