import 'dart:convert';
import '../models/profile.dart';

class XrayConfigBuilder {
  static const int socks5Port = 10808;

  static Map<String, dynamic> build(VpnProfile profile) {
    assert(profile.protocol == VpnProtocol.vless);
    final c = profile.config;

    return {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'tag': 'socks-in',
          'protocol': 'socks',
          'listen': '127.0.0.1',
          'port': socks5Port,
          'settings': {'auth': 'noauth', 'udp': true},
        },
      ],
      'outbounds': [
        _vless(c),
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
        ],
      },
    };
  }

  static String toJson(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  static Map<String, dynamic> _vless(Map<String, dynamic> c) {
    final transport = c['transport'] as String;
    final security = c['security'] as String;

    final vnext = <String, dynamic>{
      'address': c['server'],
      'port': c['port'],
      'users': [
        {
          'id': c['uuid'],
          'encryption': 'none',
          if ((c['flow'] as String? ?? '').isNotEmpty) 'flow': c['flow'],
        },
      ],
    };

    final streamSettings = <String, dynamic>{
      'network': _xrayNetwork(transport),
      'security': security,
    };

    if (security == 'tls') {
      streamSettings['tlsSettings'] = {
        'serverName': c['sni'],
        'fingerprint': c['fp'] ?? 'chrome',
        'allowInsecure': false,
      };
    } else if (security == 'reality') {
      streamSettings['realitySettings'] = {
        'serverName': c['sni'],
        'fingerprint': c['fp'] ?? 'chrome',
        'publicKey': c['pbk'],
        'shortId': c['sid'] ?? '',
        'spiderX': c['spx'] ?? '',
      };
    }

    _applyTransport(streamSettings, transport, c);

    return {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [vnext],
      },
      'streamSettings': streamSettings,
    };
  }

  static String _xrayNetwork(String transport) => switch (transport) {
        'grpc' => 'grpc',
        'ws' => 'ws',
        'httpupgrade' || 'http' => 'httpupgrade',
        'xhttp' => 'xhttp',
        _ => 'tcp',
      };

  static void _applyTransport(
    Map<String, dynamic> ss,
    String transport,
    Map<String, dynamic> c,
  ) {
    switch (transport) {
      case 'grpc':
        ss['grpcSettings'] = {
          'serviceName': c['serviceName'] ?? '',
          'multiMode': false,
        };
      case 'ws':
        ss['wsSettings'] = {
          'path': c['path'] ?? '/',
          'headers': {'Host': c['host'] ?? c['sni'] ?? ''},
        };
      case 'httpupgrade' || 'http':
        ss['httpupgradeSettings'] = {
          'path': c['path'] ?? '/',
          'host': c['sni'] ?? c['server'],
        };
      case 'xhttp':
        ss['xhttpSettings'] = {
          'path': c['path'] ?? '/',
          'host': c['sni'] ?? c['server'],
          'mode': c['mode'] ?? 'auto',
        };
    }
  }
}
