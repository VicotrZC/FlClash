import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/common/singbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// 把 sing-box 订阅转成 Clash 配置。这里锁住两类曾经出错的点：
///   1. transport（ws/grpc）必须从 `transport` 对象读，而不是顶层 network/ws_path；
///   2. 无法表达的传输方式或协议必须**跳过**，不能降级成能校验但连不上的节点。
Uint8List _json(Map<String, dynamic> value) =>
    Uint8List.fromList(utf8.encode(json.encode(value)));

Map<String, dynamic> _convert(Map<String, dynamic> value) {
  final out = singBoxJsonToClashYaml(_json(value));
  expect(out, isNotNull, reason: '应能转换');
  final doc = loadYaml(utf8.decode(out!)) as YamlMap;
  return json.decode(json.encode(doc)) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _proxies(Map<String, dynamic> config) =>
    (config['proxies'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _withNodes(List<Map<String, dynamic>> nodes) => {
  'outbounds': [
    {
      'type': 'selector',
      'tag': 'Proxy',
      'outbounds': ['direct'],
    },
    ...nodes,
    {'type': 'direct', 'tag': 'direct'},
  ],
};

void main() {
  group('singBoxJsonToClashYaml', () {
    test('非 JSON 或缺少 outbounds 时返回 null', () {
      expect(
        singBoxJsonToClashYaml(Uint8List.fromList(utf8.encode('not json'))),
        isNull,
      );
      expect(singBoxJsonToClashYaml(_json({'log': {}})), isNull);
      expect(singBoxJsonToClashYaml(_json({'outbounds': 'nope'})), isNull);
    });

    test('hysteria2 节点保留密码与 sni', () {
      final config = _convert(
        _withNodes([
          {
            'type': 'hysteria2',
            'tag': 'HY2',
            'server': '192.0.2.1',
            'server_port': 443,
            'password': 'pw',
            'tls': {'enabled': true, 'server_name': 'a.example.invalid'},
          },
        ]),
      );

      final node = _proxies(config).single;
      expect(node['type'], 'hysteria2');
      expect(node['server'], '192.0.2.1');
      expect(node['port'], 443);
      expect(node['password'], 'pw');
      expect(node['sni'], 'a.example.invalid');
    });

    test('WebSocket 传输被转成 ws + ws-opts（含 Host）', () {
      // 这是修复的核心：sing-box 用 transport 对象，没有顶层 network/ws_path。
      final config = _convert(
        _withNodes([
          {
            'type': 'vmess',
            'tag': 'WS',
            'server': '203.0.113.1',
            'server_port': 443,
            'uuid': '00000000-0000-4000-8000-000000000001',
            'transport': {
              'type': 'ws',
              'path': '/ws-path',
              'headers': {'Host': 'ws.example.invalid'},
            },
            'tls': {'enabled': true, 'server_name': 'ws.example.invalid'},
          },
        ]),
      );

      final node = _proxies(config).single;
      expect(node['network'], 'ws', reason: '不能退化成 tcp');
      expect(node['ws-opts'], {
        'path': '/ws-path',
        'headers': {'Host': 'ws.example.invalid'},
      });
      expect(node['tls'], isTrue);
      expect(node['servername'], 'ws.example.invalid');
    });

    test('顶层 network/ws_path 不再被当作传输方式', () {
      // 旧实现读的是这两个键；它们不是 sing-box 的字段，
      // 出现时也不该影响结果（节点应为纯 tcp，且不带 ws-opts）。
      final config = _convert(
        _withNodes([
          {
            'type': 'vless',
            'tag': 'LEGACY',
            'server': '203.0.113.2',
            'server_port': 443,
            'uuid': '00000000-0000-4000-8000-000000000002',
            'network': 'ws',
            'ws_path': '/ignored',
          },
        ]),
      );

      final node = _proxies(config).single;
      expect(node['network'], 'tcp');
      expect(node.containsKey('ws-opts'), isFalse);
    });

    test('gRPC 传输被转成 grpc + grpc-opts', () {
      final config = _convert(
        _withNodes([
          {
            'type': 'vless',
            'tag': 'GRPC',
            'server': '203.0.113.3',
            'server_port': 443,
            'uuid': '00000000-0000-4000-8000-000000000003',
            'transport': {'type': 'grpc', 'service_name': 'gsvc'},
          },
        ]),
      );

      final node = _proxies(config).single;
      expect(node['network'], 'grpc');
      expect(node['grpc-opts'], {'grpc-service-name': 'gsvc'});
    });

    test('无法表达的传输方式跳过节点而不是降级', () {
      // quic 传输与 hysteria v1 都无法表达成 Clash 节点；
      // 两个都被跳过 -> 没有可用代理 -> 返回 null（而不是产出假节点）。
      final config = singBoxJsonToClashYaml(
        _json(
          _withNodes([
            {
              'type': 'vmess',
              'tag': 'QUIC',
              'server': '203.0.113.4',
              'server_port': 443,
              'uuid': '00000000-0000-4000-8000-000000000004',
              'transport': {'type': 'quic'},
            },
            {
              'type': 'hysteria',
              'tag': 'HY1',
              'server': '203.0.113.5',
              'server_port': 443,
              'auth_str': 'legacy',
            },
          ]),
        ),
      );

      expect(config, isNull);
    });

    test('不可转换的节点被跳过，可转换的保留', () {
      final config = _convert(
        _withNodes([
          {
            'type': 'vmess',
            'tag': 'QUIC',
            'server': '203.0.113.4',
            'server_port': 443,
            'uuid': '00000000-0000-4000-8000-000000000004',
            'transport': {'type': 'quic'},
          },
          {
            'type': 'hysteria2',
            'tag': 'OK',
            'server': '192.0.2.9',
            'server_port': 443,
            'password': 'pw',
          },
        ]),
      );

      final names = _proxies(config).map((p) => p['name']).toList();
      expect(names, ['OK'], reason: '不可转换的 QUIC 节点应被丢弃');
    });

    test('hysteria v1 不被写成 hysteria2', () {
      final config = singBoxJsonToClashYaml(
        _json(
          _withNodes([
            {
              'type': 'hysteria',
              'tag': 'HY1',
              'server': '203.0.113.5',
              'server_port': 443,
              'auth_str': 'legacy',
            },
          ]),
        ),
      );
      // 唯一的节点不可转换 -> 没有可用代理 -> 返回 null，而不是产出一个假 hysteria2
      expect(config, isNull);
    });

    test('anytls 保留 alpn', () {
      final config = _convert(
        _withNodes([
          {
            'type': 'anytls',
            'tag': 'AT',
            'server': '198.51.100.1',
            'server_port': 8443,
            'password': 'pw',
            'tls': {
              'enabled': true,
              'server_name': 'at.example.invalid',
              'alpn': ['h2', 'http/1.1'],
            },
          },
        ]),
      );

      final node = _proxies(config).single;
      expect(node['type'], 'anytls');
      expect(node['alpn'], ['h2', 'http/1.1']);
    });

    test('生成的配置带 url-test 与 select 组，且规则指向 Proxy', () {
      final config = _convert(
        _withNodes([
          {
            'type': 'hysteria2',
            'tag': 'A',
            'server': '192.0.2.1',
            'server_port': 443,
            'password': 'pw',
          },
        ]),
      );

      final groups = (config['proxy-groups'] as List).cast<Map>();
      expect(groups.map((g) => g['type']), containsAll(['url-test', 'select']));
      expect(config['rules'], ['MATCH,Proxy']);
    });

    test('没有可转换节点时返回 null 而不是空配置', () {
      expect(
        singBoxJsonToClashYaml(
          _json({
            'outbounds': [
              {
                'type': 'selector',
                'tag': 'Proxy',
                'outbounds': ['direct'],
              },
              {'type': 'direct', 'tag': 'direct'},
            ],
          }),
        ),
        isNull,
      );
    });
  });
}
