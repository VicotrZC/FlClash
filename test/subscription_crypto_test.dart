import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/custom_headers.dart';
import 'package:fl_clash/common/subscription_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// 用服务端同一套算法做加密，用于生成测试向量。
/// 注意：这里只是测试夹具，生产代码只做解密。
Uint8List _encryptForTest(String plainText, {required Uint8List iv}) {
  const seed =
      '7f96f0cd9b99abedaa93f9292adcd9dbf1968e6ebba39667e8e9846203c75136';
  final key = Uint8List.fromList(sha256.convert(utf8.encode(seed)).bytes);

  final plain = Uint8List.fromList(utf8.encode(plainText));
  final padLength = 16 - plain.length % 16;
  final padded = Uint8List(plain.length + padLength)
    ..setRange(0, plain.length, plain)
    ..fillRange(plain.length, plain.length + padLength, padLength);

  final cipher = CBCBlockCipher(AESEngine())
    ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
  final out = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += 16) {
    cipher.processBlock(padded, offset, out, offset);
  }
  return out;
}

String _toBase64Url(Uint8List ivAndCipher) {
  return base64Url.encode(ivAndCipher).replaceAll('=', '');
}

void main() {
  group('SubscriptionCrypto', () {
    test('解密服务端格式: base64url(IV[16] || AES-256-CBC)', () {
      const plainText = '{"outbounds":[{"type":"hysteria2","tag":"HK-1"}]}';
      final iv = Uint8List.fromList(List.generate(16, (i) => i));
      final cipherText = _encryptForTest(plainText, iv: iv);

      final payload = Uint8List.fromList([...iv, ...cipherText]);
      final decoded = SubscriptionCrypto.decrypt(
        Uint8List.fromList(utf8.encode(_toBase64Url(payload))),
      );

      expect(utf8.decode(decoded), plainText);
    });

    test('支持 URL-safe 字符 - 与 _', () {
      // 构造能产生 - 或 _ 的载荷，确保字母表被正确归一化
      const plainText = '{"a":"??????????????????????????????"}';
      for (var seedByte = 0; seedByte < 256; seedByte += 17) {
        final iv = Uint8List.fromList(List.filled(16, seedByte));
        final cipherText = _encryptForTest(plainText, iv: iv);
        final payload = Uint8List.fromList([...iv, ...cipherText]);
        final encoded = _toBase64Url(payload);
        final decoded = SubscriptionCrypto.decrypt(
          Uint8List.fromList(utf8.encode(encoded)),
        );
        expect(utf8.decode(decoded), plainText, reason: 'seedByte=$seedByte');
      }
    });

    test('补齐缺失的 padding', () {
      const plainText = 'hello vpncheap';
      final iv = Uint8List(16);
      final cipherText = _encryptForTest(plainText, iv: iv);
      final payload = Uint8List.fromList([...iv, ...cipherText]);
      // 显式去掉所有 '='
      final encoded = base64Url.encode(payload).replaceAll('=', '');
      expect(encoded.contains('='), isFalse);
      final decoded = SubscriptionCrypto.decrypt(
        Uint8List.fromList(utf8.encode(encoded)),
      );
      expect(utf8.decode(decoded), plainText);
    });

    test('截断载荷抛 FormatException', () {
      expect(
        () => SubscriptionCrypto.decrypt(
          Uint8List.fromList(utf8.encode(base64Url.encode(Uint8List(10)))),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('密文长度非 16 倍数时抛 FormatException 而不是 RangeError', () {
      // 覆盖：IV 完整但密文被截断（下载中断、强制门户）。
      // 修复前这里会走到 processBlock 越界读，抛 RangeError。
      for (final extra in [1, 7, 15, 17, 31]) {
        final payload = Uint8List.fromList([
          ...Uint8List(16),
          ...Uint8List(extra),
        ]);
        expect(
          () => SubscriptionCrypto.decrypt(
            Uint8List.fromList(utf8.encode(base64Url.encode(payload))),
          ),
          throwsA(isA<FormatException>()),
          reason: 'IV(16)+密文($extra) 应被拒绝',
        );
      }
    });

    test('恰好只有 IV 没有密文时抛 FormatException', () {
      final payload = Uint8List(16);
      expect(
        () => SubscriptionCrypto.decrypt(
          Uint8List.fromList(utf8.encode(base64Url.encode(payload))),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('非法 base64 抛 FormatException', () {
      expect(
        () => SubscriptionCrypto.decrypt(
          Uint8List.fromList(utf8.encode('!!!not-base64!!!')),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('错误密钥/篡改密文抛 FormatException（padding 校验）', () {
      final iv = Uint8List(16);
      final cipherText = _encryptForTest('{"x":1}', iv: iv);
      // 翻转密文最后一个字节，破坏 PKCS5 padding
      cipherText[cipherText.length - 1] ^= 0xFF;
      final payload = Uint8List.fromList([...iv, ...cipherText]);
      expect(
        () => SubscriptionCrypto.decrypt(
          Uint8List.fromList(utf8.encode(base64Url.encode(payload))),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    group('isEncrypted / decryptIfNeeded', () {
      test('识别 X-Encrypted: 1', () {
        expect(SubscriptionCrypto.isEncrypted('1'), isTrue);
        expect(SubscriptionCrypto.isEncrypted(' 1 '), isTrue);
        expect(SubscriptionCrypto.isEncrypted('0'), isFalse);
        expect(SubscriptionCrypto.isEncrypted(null), isFalse);
        expect(SubscriptionCrypto.isEncrypted(''), isFalse);
      });

      test('未标记加密时原样返回', () {
        final body = Uint8List.fromList(utf8.encode('{"plain":true}'));
        expect(SubscriptionCrypto.decryptIfNeeded(body, null), same(body));
        expect(SubscriptionCrypto.decryptIfNeeded(body, '0'), same(body));
      });

      test('标记加密时解密', () {
        const plainText = '{"encrypted":true}';
        final iv = Uint8List(16);
        final cipherText = _encryptForTest(plainText, iv: iv);
        final payload = Uint8List.fromList([...iv, ...cipherText]);
        final body = Uint8List.fromList(utf8.encode(base64Url.encode(payload)));
        final result = SubscriptionCrypto.decryptIfNeeded(body, '1');
        expect(utf8.decode(result), plainText);
      });
    });
  });

  group('CustomHeaders.parse', () {
    test('解析单行', () {
      expect(CustomHeaders.parse('X-Client-Encrypt: v1'), {
        'X-Client-Encrypt': 'v1',
      });
    });

    test('解析多行并忽略空行', () {
      expect(
        CustomHeaders.parse('X-Client-Encrypt: v1\n\nX-Client: android\n'),
        {'X-Client-Encrypt': 'v1', 'X-Client': 'android'},
      );
    });

    test('值中允许出现冒号', () {
      expect(CustomHeaders.parse('Referer: https://a.b/c?d=1'), {
        'Referer': 'https://a.b/c?d=1',
      });
    });

    test('忽略无冒号的行', () {
      expect(CustomHeaders.parse('garbage\nA: b'), {'A': 'b'});
    });

    test('头名中的空白被移除', () {
      expect(CustomHeaders.parse('X Client Encrypt: v1'), {
        'XClientEncrypt': 'v1',
      });
    });

    test('空输入返回空 Map', () {
      expect(CustomHeaders.parse(null), isEmpty);
      expect(CustomHeaders.parse(''), isEmpty);
      expect(CustomHeaders.parse('   \n  '), isEmpty);
    });

    test('同名后者覆盖前者', () {
      expect(CustomHeaders.parse('A: 1\nA: 2'), {'A': '2'});
    });

    test('format 与 parse 往返一致', () {
      final headers = {'X-Client-Encrypt': 'v1', 'X-Client': 'android'};
      expect(CustomHeaders.parse(CustomHeaders.format(headers)), headers);
    });
  });

  group('固定密文向量（合成，结构与真实下发一致）', () {
    // 这个向量是**合成**的：同样的 sing-box 结构、同样的 hysteria2/anytls
    // 协议类型，但服务器地址用保留段、凭据用占位符。
    //
    // 不放真实抓包的原因：解密密钥硬编码在 lib/common/subscription_crypto.dart，
    // 提交真实密文等于公开账号的服务器地址与 UUID/密码。
    // 生成脚本见 E:\安全\analysis\make_synthetic_fixture.py。
    test('解密后是含连接参数的 sing-box JSON', () {
      final file = File('test/fixtures/vpncheap_sub_encrypted.b64');
      expect(file.existsSync(), isTrue, reason: '缺少测试向量 ${file.path}');

      final decoded = SubscriptionCrypto.decrypt(
        Uint8List.fromList(utf8.encode(file.readAsStringSync().trim())),
      );
      final text = utf8.decode(decoded);

      expect(text.trimLeft().startsWith('{'), isTrue);
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final outbounds = parsed['outbounds'] as List;
      expect(outbounds, isNotEmpty);

      const groupTypes = {'direct', 'block', 'dns', 'selector', 'urltest'};
      final nodes = outbounds
          .where((o) => o is Map && !groupTypes.contains(o['type']))
          .cast<Map>()
          .toList();
      expect(nodes, isNotEmpty, reason: '应有真实节点');

      // 关键：节点必须带连接参数，否则等于没拿到配置
      expect(nodes.any((n) => n['server'] != null), isTrue);
      expect(nodes.any((n) => n['server_port'] != null), isTrue);
      expect(
        nodes.any((n) => n['password'] != null || n['uuid'] != null),
        isTrue,
        reason: '节点应带凭据',
      );

      // 该账号实际下发的协议类型
      final types = nodes.map((n) => n['type']).toSet();
      expect(types, contains('hysteria2'));
      expect(types, contains('anytls'));
    });
  });
}
