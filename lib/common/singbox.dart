import 'dart:convert';
import 'dart:typed_data';

import 'package:yaml_writer/yaml_writer.dart';

const _groupTypes = {'direct', 'block', 'dns', 'selector', 'urltest'};

const _groupName = 'Proxy';
const _autoGroupName = 'Auto';
const _testUrl = 'http://www.gstatic.com/generate_204';

/// sing-box 把传输方式放在 `transport` 对象里：
///   {"transport":{"type":"ws","path":"/x","headers":{"Host":"h"}}}
/// 顶层**没有** network / ws_path 这类键。早期实现读的是顶层键，导致
/// 所有 WebSocket 节点都被当成纯 TCP 写出去（连不上，且没有任何提示）。
Map<String, dynamic> _transportOf(Map<String, dynamic> node) {
  final transport = node['transport'];
  return transport is Map<String, dynamic> ? transport : const {};
}

/// 把 sing-box 的 transport 映射成 Clash 的 network + 传输选项。
///
/// 返回 null 表示这种传输方式无法表达——调用方应**跳过该节点**，
/// 而不是降级成 TCP（那会产出一个能通过校验但连不上的节点）。
Map<String, dynamic>? _clashTransport(Map<String, dynamic> node) {
  final transport = _transportOf(node);
  final type = transport['type'] as String? ?? '';
  switch (type) {
    case '':
      return const {'network': 'tcp'};
    case 'ws':
      final opts = <String, dynamic>{};
      final path = transport['path'] as String? ?? '';
      if (path.isNotEmpty) opts['path'] = path;
      final headers = transport['headers'];
      if (headers is Map) {
        final host = headers['Host'] ?? headers['host'];
        if (host is String && host.isNotEmpty) {
          opts['headers'] = {'Host': host};
        }
      }
      return {'network': 'ws', if (opts.isNotEmpty) 'ws-opts': opts};
    case 'grpc':
      final serviceName = transport['service_name'] as String? ?? '';
      return {
        'network': 'grpc',
        if (serviceName.isNotEmpty)
          'grpc-opts': {'grpc-service-name': serviceName},
      };
    case 'http':
    case 'httpupgrade':
      final opts = <String, dynamic>{};
      final path = transport['path'] as String? ?? '';
      if (path.isNotEmpty) opts['path'] = path;
      final host = transport['host'] as String? ?? '';
      if (host.isNotEmpty) opts['headers'] = {'Host': host};
      return {'network': 'http', if (opts.isNotEmpty) 'http-opts': opts};
  }
  return null;
}

Map<String, dynamic>? _nodeToClashProxy(Map<String, dynamic> node) {
  final type = node['type'] as String? ?? '';
  final name = node['tag'] as String? ?? '';
  final server = node['server'] as String? ?? '';
  final port = node['server_port'];
  final password = node['password'] as String? ?? '';
  final tls = node['tls'] is Map<String, dynamic>
      ? node['tls'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final serverName = tls['server_name'] as String? ?? '';
  final insecure = tls['insecure'] == true;

  switch (type) {
    case 'hysteria2':
      final proxy = <String, dynamic>{
        'name': name,
        'type': 'hysteria2',
        'server': server,
        'port': port,
        'password': password,
      };
      if (serverName.isNotEmpty) proxy['sni'] = serverName;
      if (insecure) proxy['skip-cert-verify'] = true;
      final obfs = node['obfs'];
      if (obfs is Map<String, dynamic> && obfs['type'] == 'salamander') {
        proxy['obfs'] = 'salamander';
        final obfsPassword = obfs['password'] as String? ?? '';
        if (obfsPassword.isNotEmpty) proxy['obfs-password'] = obfsPassword;
      }
      return proxy;
    case 'hysteria':
      // sing-box 的 hysteria 是 v1（auth_str / up / down），与 hysteria2
      // 的 password 字段不兼容。写成 hysteria2 会产出一个能通过校验、
      // 但永远连不上的节点，所以宁可不转换。
      return null;
    case 'anytls':
      final proxy = <String, dynamic>{
        'name': name,
        'type': 'anytls',
        'server': server,
        'port': port,
        'password': password,
      };
      if (serverName.isNotEmpty) proxy['sni'] = serverName;
      final alpn = tls['alpn'];
      if (alpn is List && alpn.isNotEmpty) {
        proxy['alpn'] = alpn.whereType<String>().toList();
      }
      return proxy;
    case 'vmess':
      final transport = _clashTransport(node);
      if (transport == null) return null;
      final proxy = <String, dynamic>{
        'name': name,
        'type': 'vmess',
        'server': server,
        'port': port,
        'uuid': node['uuid'] as String? ?? '',
        'alterId': 0,
        'cipher': 'auto',
        'udp': true,
        ...transport,
      };
      if (tls['enabled'] == true) {
        proxy['tls'] = true;
        if (serverName.isNotEmpty) proxy['servername'] = serverName;
      }
      return proxy;
    case 'vless':
      final transport = _clashTransport(node);
      if (transport == null) return null;
      final proxy = <String, dynamic>{
        'name': name,
        'type': 'vless',
        'server': server,
        'port': port,
        'uuid': node['uuid'] as String? ?? '',
        'udp': true,
        ...transport,
      };
      final flow = node['flow'] as String? ?? '';
      if (flow.isNotEmpty) proxy['flow'] = flow;
      if (tls['enabled'] == true) {
        proxy['tls'] = true;
        if (serverName.isNotEmpty) proxy['servername'] = serverName;
      }
      return proxy;
    case 'trojan':
      final transport = _clashTransport(node);
      if (transport == null) return null;
      final proxy = <String, dynamic>{
        'name': name,
        'type': 'trojan',
        'server': server,
        'port': port,
        'password': password,
        'udp': true,
        ...transport,
      };
      if (tls['enabled'] == true && serverName.isNotEmpty) {
        proxy['sni'] = serverName;
      }
      return proxy;
    case 'shadowsocks':
      return <String, dynamic>{
        'name': name,
        'type': 'ss',
        'server': server,
        'port': port,
        'cipher': node['method'] as String? ?? 'aes-256-gcm',
        'password': password,
        'udp': true,
      };
  }
  return null;
}

Uint8List? singBoxJsonToClashYaml(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (!text.startsWith('{')) return null;
  final Object? decoded;
  try {
    decoded = json.decode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final outbounds = decoded['outbounds'];
  if (outbounds is! List) return null;

  final proxies = <Map<String, dynamic>>[];
  for (final raw in outbounds) {
    if (raw is! Map<String, dynamic>) continue;
    final type = raw['type'] as String? ?? '';
    final tag = raw['tag'] as String? ?? '';
    if (_groupTypes.contains(type)) continue;
    if (tag.isEmpty) continue;
    final proxy = _nodeToClashProxy(raw);
    if (proxy != null) proxies.add(proxy);
  }
  if (proxies.isEmpty) return null;

  final proxyNames = proxies.map((p) => p['name'] as String).toList();
  final clashConfig = <String, dynamic>{
    'proxies': proxies,
    'proxy-groups': [
      {
        'name': _autoGroupName,
        'type': 'url-test',
        'url': _testUrl,
        'interval': 300,
        'proxies': proxyNames,
      },
      {
        'name': _groupName,
        'type': 'select',
        'proxies': [_autoGroupName, 'DIRECT', ...proxyNames],
      },
    ],
    'rules': ['MATCH,$_groupName'],
  };
  final yamlText = YamlWriter().convert(clashConfig);
  return Uint8List.fromList(utf8.encode(yamlText));
}
