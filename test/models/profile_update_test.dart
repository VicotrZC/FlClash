import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pointycastle/export.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// 按固定正文 + 固定响应头应答，不碰网络。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.body, required this.headers});

  final Uint8List body;
  final Map<String, List<String>> headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(body, 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

/// 服务端同款加密：base64url(IV[16] || AES-256-CBC/PKCS5)。
Uint8List _encrypt(String plainText) {
  const seed =
      '7f96f0cd9b99abedaa93f9292adcd9dbf1968e6ebba39667e8e9846203c75136';
  final key = Uint8List.fromList(sha256.convert(utf8.encode(seed)).bytes);
  final iv = Uint8List.fromList(List.generate(16, (i) => i));
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
  final payload = Uint8List.fromList([...iv, ...out]);
  return Uint8List.fromList(
    utf8.encode(base64Url.encode(payload).replaceAll('=', '')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('profile_update_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Profile.update 读取加密标记', () {
    // 回归：这里曾经写成 headers.value(encryptedHeaderValue)，
    // 传的是头的**值** '1' 而不是头的**名字**，于是永远取到 null，
    // 解密从不执行，原始 base64 被当成 YAML 交给 mihomo，报
    // "cannot unmarshal !!str `...` into config.RawConfig"。
    test('响应头 X-Encrypted: 1 时正文被解密后再校验', () async {
      const yamlText = 'proxies:\n  - name: "HK"\n    type: "hysteria2"\n';
      request.clashAdapter = _StubAdapter(
        body: _encrypt(yamlText),
        headers: {
          SubscriptionCrypto.encryptedHeaderKey: ['1'],
        },
      );

      Uint8List? seen;
      final profile = Profile.normal(
        label: 'p',
        url: 'https://example.test/sub',
      );
      await profile.update(
        validate: (path, _) async {
          seen = File(path).readAsBytesSync();
          return '';
        },
      );

      expect(seen, isNotNull);
      expect(
        utf8.decode(seen!),
        yamlText,
        reason: '交给校验（进而交给 mihomo）的必须是解密后的正文',
      );
    });

    test('没有加密标记时正文原样通过', () async {
      const yamlText = 'proxies: []\n';
      request.clashAdapter = _StubAdapter(
        body: Uint8List.fromList(utf8.encode(yamlText)),
        headers: const {},
      );

      Uint8List? seen;
      final profile = Profile.normal(
        label: 'p',
        url: 'https://example.test/sub',
      );
      await profile.update(
        validate: (path, _) async {
          seen = File(path).readAsBytesSync();
          return '';
        },
      );

      expect(utf8.decode(seen!), yamlText);
    });

    test('sing-box JSON 订阅被转成 Clash YAML', () async {
      const jsonText =
          '{"outbounds":[{"type":"hysteria2","tag":"HK","server":"192.0.2.1",'
          '"server_port":443,"password":"pw"}]}';
      request.clashAdapter = _StubAdapter(
        body: Uint8List.fromList(utf8.encode(jsonText)),
        headers: const {},
      );

      Uint8List? seen;
      final profile = Profile.normal(
        label: 'p',
        url: 'https://example.test/sub',
      );
      await profile.update(
        validate: (path, _) async {
          seen = File(path).readAsBytesSync();
          return '';
        },
      );

      final text = utf8.decode(seen!);
      expect(text, contains('proxies:'));
      expect(text, contains('hysteria2'));
      expect(text, isNot(contains('"outbounds"')));
    });
  });
}
