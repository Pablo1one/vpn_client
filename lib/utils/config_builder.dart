import 'dart:convert';
import '../models/profile.dart';

enum RoutingMode { fullVpn, russiaBypass, custom }

class ConfigBuilder {

  static Map<String, dynamic> build(
    VpnProfile profile, {
    RoutingMode routingMode = RoutingMode.fullVpn,
    List<String> bypassDomains = const [],
    bool killSwitch = false,
  }) {
    return {
      'log': {'level': 'info'},
      'dns': _dns(),
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:9090',
          'secret': '',
        },
      },
      'inbounds': [_tun()],
      'outbounds': [
        _outbound(profile),
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'},
      ],
      'route': _route(
        routingMode: routingMode,
        bypassDomains: bypassDomains,
        killSwitch: killSwitch,
      ),
    };
  }

  static String toJson(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  /// Generates a WireGuard .conf for amneziawg.exe (AWG 1.x and 2.0).
  static String buildAwgConf(VpnProfile profile) {
    final c = profile.config;
    final buf = StringBuffer();

    buf.writeln('[Interface]');
    buf.writeln('PrivateKey = ${c['privateKey']}');
    buf.writeln('Address = ${c['address']}');
    buf.writeln('DNS = 1.1.1.1, 8.8.8.8');

    const awgParamKeys = [
      'Jc', 'Jmin', 'Jmax', 'S1', 'S2', 'S3', 'S4',
      'H1', 'H2', 'H3', 'H4',
    ];
    for (final k in awgParamKeys) {
      final v = c[k.toLowerCase()];
      if (v != null) buf.writeln('$k = $v');
    }

    buf.writeln('');
    buf.writeln('[Peer]');
    buf.writeln('PublicKey = ${c['publicKey']}');
    final psk = c['presharedKey'] as String? ?? '';
    if (psk.isNotEmpty) buf.writeln('PresharedKey = $psk');
    buf.writeln('Endpoint = ${c['server']}:${c['port']}');
    buf.writeln('AllowedIPs = 0.0.0.0/0, ::/0');
    buf.writeln('PersistentKeepalive = 25');

    return buf.toString();
  }

  // ── Outbound ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _outbound(VpnProfile p) => switch (p.protocol) {
        VpnProtocol.vless => _vless(p.config),
        VpnProtocol.wireguard => _wireguard(p.config),
        VpnProtocol.amnezia => _amnezia(p.config),
        VpnProtocol.tuic => _tuic(p.config),
        VpnProtocol.hysteria2 => _hysteria2(p.config),
      };

  static Map<String, dynamic> _vless(Map<String, dynamic> c) {
    final transport = c['transport'] as String;
    final security = c['security'] as String;

    final tls = <String, dynamic>{
      'enabled': security == 'tls' || security == 'reality',
      'server_name': c['sni'],
      'utls': {'enabled': true, 'fingerprint': c['fp'] ?? 'chrome'},
    };
    if (security == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': c['pbk'],
        'short_id': c['sid'],
      };
    }

    final flow = (c['flow'] as String? ?? '').trim();
    final out = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': c['server'],
      'server_port': c['port'],
      'uuid': c['uuid'],
      if (flow.isNotEmpty) 'flow': flow,
      'tls': tls,
    };

    switch (transport) {
      case 'grpc':
        out['transport'] = {
          'type': 'grpc',
          'service_name': c['serviceName'] ?? '',
        };
      case 'httpupgrade' || 'http':
        out['transport'] = {
          'type': 'httpupgrade',
          'host': c['sni'],
          'path': c['path'] ?? '/',
        };
      case 'ws':
        out['transport'] = {
          'type': 'ws',
          'path': c['path'] ?? '/',
          'headers': {'Host': c['host'] ?? c['sni']},
        };
      case 'xhttp':
        out['transport'] = {
          'type': 'http',
          'host': [c['sni']],
          'path': c['path'] ?? '/',
        };
    }

    return out;
  }

  static Map<String, dynamic> _wireguard(Map<String, dynamic> c) {
    final addresses = (c['address'] as String)
        .split(',')
        .map((a) => a.trim())
        .toList();

    final peer = <String, dynamic>{
      'server': c['server'],
      'server_port': c['port'],
      'public_key': c['publicKey'],
      if ((c['presharedKey'] as String? ?? '').isNotEmpty)
        'pre_shared_key': c['presharedKey'],
      'allowed_ips': ['0.0.0.0/0', '::/0'],
    };

    return {
      'type': 'wireguard',
      'tag': 'proxy',
      'local_address': addresses,
      'private_key': c['privateKey'],
      'peers': [peer],
      'mtu': 1408,
    };
  }

  static Map<String, dynamic> _amnezia(Map<String, dynamic> c) {
    // Standard sing-box doesn't support AmneziaWG obfuscation fields.
    // Fall back to plain WireGuard — the tunnel will still work without obfuscation.
    return _wireguard(c);
  }

  static Map<String, dynamic> _tuic(Map<String, dynamic> c) => {
        'type': 'tuic',
        'tag': 'proxy',
        'server': c['server'],
        'server_port': c['port'],
        'uuid': c['uuid'],
        'password': c['password'],
        'congestion_control': c['congestion'] ?? 'bbr',
        'tls': {
          'enabled': true,
          'server_name': c['sni'],
          'alpn': [(c['alpn'] as String?) ?? 'h3'],
          'insecure': c['insecure'] ?? false,
        },
      };

  static Map<String, dynamic> _hysteria2(Map<String, dynamic> c) {
    final out = <String, dynamic>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': c['server'],
      'server_port': c['port'],
      'password': c['password'],
      'tls': {
        'enabled': true,
        'server_name': c['sni'],
        'insecure': c['insecure'] ?? false,
      },
    };
    final obfs = c['obfs'] as String? ?? '';
    if (obfs.isNotEmpty) {
      out['obfs'] = {'type': obfs, 'password': c['obfsPassword'] ?? ''};
    }
    return out;
  }

  // ── TUN inbound ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _tun() => {
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'tun0',
        'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'stack': 'mixed',
        'sniff': true,
      };

  // ── DNS ─────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _dns() => {
        'servers': [
          {'tag': 'remote', 'address': 'tls://1.1.1.1', 'detour': 'proxy'},
          {'tag': 'local', 'address': 'https://8.8.8.8/dns-query', 'detour': 'direct'},
        ],
        'rules': [
          {'outbound': 'any', 'server': 'local'},
        ],
        'final': 'remote',
        'independent_cache': true,
      };

  // ── Route ────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _route({
    required RoutingMode routingMode,
    required List<String> bypassDomains,
    required bool killSwitch,
  }) {
    final rules = <Map<String, dynamic>>[
      {'protocol': 'dns', 'outbound': 'dns-out'},
    ];

    switch (routingMode) {
      case RoutingMode.russiaBypass:
        // Route .ru / .рф / .su domains directly, no remote rule-set download needed
        rules.add({'domain_suffix': ['.ru', '.рф', '.su'], 'outbound': 'direct'});
        rules.add({
          'domain_suffix': ['yandex.com', 'yandex.net', 'ya.ru', 'yastatic.net'],
          'outbound': 'direct',
        });
      case RoutingMode.custom:
        if (bypassDomains.isNotEmpty) {
          rules.add({'domain_suffix': bypassDomains, 'outbound': 'direct'});
        }
      case RoutingMode.fullVpn:
        break;
    }

    rules.add({'ip_is_private': true, 'outbound': 'direct'});

    return {
      'rules': rules,
      'final': 'proxy',
      'auto_detect_interface': true,
      if (killSwitch) 'default_mark': 666,
    };
  }
}
