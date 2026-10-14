import 'package:fl_clash/common/custom_headers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomHeaders.parse', () {
    test('空输入返回空 Map', () {
      expect(CustomHeaders.parse(null), isEmpty);
      expect(CustomHeaders.parse(''), isEmpty);
      expect(CustomHeaders.parse('   \n  \n'), isEmpty);
    });

    test('解析多行并忽略空行', () {
      expect(
        CustomHeaders.parse('X-Client-Encrypt: v1\n\nX-Client: android\n'),
        {'X-Client-Encrypt': 'v1', 'X-Client': 'android'},
      );
    });

    test('值中允许出现冒号', () {
      expect(CustomHeaders.parse('Referer: https://a.test/x'), {
        'Referer': 'https://a.test/x',
      });
    });

    test('头名中的空白被移除，值与首尾空白被 trim', () {
      expect(CustomHeaders.parse('  X-Client-Encrypt :  v1  '), {
        'X-Client-Encrypt': 'v1',
      });
    });

    test('同名后者覆盖前者', () {
      expect(CustomHeaders.parse('A: 1\nA: 2'), {'A': '2'});
    });

    test('没有冒号的行被忽略', () {
      expect(CustomHeaders.parse('X-Client-Encrypt: v1\nnot-a-header'), {
        'X-Client-Encrypt': 'v1',
      });
    });

    test('冒号开头（头名为空）的行被忽略', () {
      expect(CustomHeaders.parse(': v1'), isEmpty);
    });
  });

  group('CustomHeaders.format', () {
    test('还原成多行文本', () {
      expect(CustomHeaders.format({'A': '1', 'B': '2'}), 'A: 1\nB: 2');
    });

    test('空 Map 得到空字符串', () {
      expect(CustomHeaders.format({}), '');
    });

    test('与 parse 往返一致', () {
      const source = {'X-Client-Encrypt': 'v1', 'X-Client': 'android'};
      expect(CustomHeaders.parse(CustomHeaders.format(source)), source);
    });
  });

  group('CustomHeaders.firstInvalidLine', () {
    test('全部合法时返回 null', () {
      expect(CustomHeaders.firstInvalidLine('A: 1\nB: 2'), isNull);
    });

    test('空输入合法', () {
      expect(CustomHeaders.firstInvalidLine(null), isNull);
      expect(CustomHeaders.firstInvalidLine(''), isNull);
      expect(CustomHeaders.firstInvalidLine('  \n \n'), isNull);
    });

    test('空行被跳过，不算错误', () {
      // 必须与 parse 一致：parse 忽略空行，校验也不该拦下它。
      expect(CustomHeaders.firstInvalidLine('A: 1\n\n\nB: 2'), isNull);
    });

    test('返回第一条出错的行号（从 1 开始）', () {
      expect(CustomHeaders.firstInvalidLine('A: 1\nbroken\nB: 2'), 2);
      expect(CustomHeaders.firstInvalidLine('broken\nA: 1\nbad'), 1);
    });

    test('空行不占行号', () {
      expect(CustomHeaders.firstInvalidLine('A: 1\n\nbroken'), 3);
    });

    test('冒号开头（头名为空）算错误', () {
      expect(CustomHeaders.firstInvalidLine(': v1'), 1);
      expect(CustomHeaders.firstInvalidLine('  : v1'), 1);
    });

    test('头名只有空白算错误', () {
      expect(CustomHeaders.firstInvalidLine('   : v1'), 1);
    });

    test('值可以为空', () {
      expect(CustomHeaders.firstInvalidLine('A:'), isNull);
      expect(CustomHeaders.firstInvalidLine('A: '), isNull);
    });

    test('校验通过的内容 parse 后不会丢行', () {
      // 这是校验存在的理由：校验放行的内容，parse 必须一行不落地收下。
      const text =
          'X-Client-Encrypt: v1\nX-Client: android\nReferer: https://a.test/x';
      expect(CustomHeaders.firstInvalidLine(text), isNull);
      expect(CustomHeaders.parse(text), hasLength(3));
    });
  });
}
