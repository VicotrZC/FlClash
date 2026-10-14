import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 处理带 `X-Encrypted: 1` 响应头的订阅内容解密。
///
/// 复现自 vpncheap 2.3.23 客户端 `P0.e.o(String)`：
///   data  = base64url(input)                 // 容忍缺失 padding，支持 - 与 _
///   iv    = data[0..16]
///   ct    = data[16..]
///   key   = SHA-256(AES_SEED)                // 32 字节 -> AES-256
///   plain = AES/CBC/PKCS5Padding.decrypt(key, iv, ct)
///
/// 注意：密钥是客户端硬编码常量，服务端加密只提供混淆，不提供机密性。
abstract final class SubscriptionCrypto {
  /// 响应头 `X-Encrypted` 的值为该字符串时表示正文已加密。
  static const encryptedHeaderKey = 'X-Encrypted';
  static const encryptedHeaderValue = '1';

  static const _aesSeed =
      '7f96f0cd9b99abedaa93f9292adcd9dbf1968e6ebba39667e8e9846203c75136';

  static Uint8List? _key;

  static Uint8List get _aesKey =>
      _key ??= Uint8List.fromList(sha256.convert(utf8.encode(_aesSeed)).bytes);

  /// 判断响应是否标记为已加密。
  static bool isEncrypted(String? headerValue) =>
      headerValue?.trim() == encryptedHeaderValue;

  /// 解密订阅正文；失败时抛出 [FormatException]。
  static Uint8List decrypt(Uint8List body) {
    final raw = _decodeBase64Url(
      utf8.decode(body, allowMalformed: true).trim(),
    );
    if (raw.length <= 16) {
      throw const FormatException('encrypted payload is truncated');
    }
    final iv = raw.sublist(0, 16);
    final cipherText = raw.sublist(16);

    // 必须先验长度：processBlock 对非 16 倍数的输入会越界读取并抛 RangeError，
    // 那不是本方法承诺的 FormatException，会以「RangeError: Invalid value」这种
    // 无从诊断的提示冒到 UI。截断下载、被劫持到强制门户都会走到这里。
    if (cipherText.isEmpty || cipherText.length % 16 != 0) {
      throw const FormatException('ciphertext length must be a multiple of 16');
    }

    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(_aesKey), iv));

    final padded = Uint8List(cipherText.length);
    for (var offset = 0; offset < cipherText.length; offset += 16) {
      cipher.processBlock(cipherText, offset, padded, offset);
    }

    final plain = _stripPkcs5Padding(padded);
    // 严格 UTF-8：与客户端一致，非法字节视为解密失败
    final text = utf8.decode(plain);
    return Uint8List.fromList(utf8.encode(text));
  }

  /// 若正文标记为加密则解密，否则原样返回。
  static Uint8List decryptIfNeeded(Uint8List body, String? encryptedHeader) {
    if (!isEncrypted(encryptedHeader)) return body;
    return decrypt(body);
  }

  static Uint8List _decodeBase64Url(String input) {
    if (input.isEmpty) {
      throw const FormatException('invalid base64');
    }
    final normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    final padding = (4 - normalized.length % 4) % 4;
    try {
      return base64.decode(normalized + '=' * padding);
    } on FormatException {
      throw const FormatException('invalid base64');
    }
  }

  static Uint8List _stripPkcs5Padding(Uint8List data) {
    if (data.isEmpty) {
      throw const FormatException('empty plaintext');
    }
    final pad = data.last;
    if (pad < 1 || pad > 16 || pad > data.length) {
      throw const FormatException('bad PKCS5 padding');
    }
    for (var i = data.length - pad; i < data.length; i++) {
      if (data[i] != pad) {
        throw const FormatException('bad PKCS5 padding');
      }
    }
    return Uint8List.sublistView(data, 0, data.length - pad);
  }
}
