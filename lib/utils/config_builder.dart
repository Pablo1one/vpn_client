import 'dart:convert';
import '../models/profile.dart';

enum RoutingMode { fullVpn, russiaBypass, custom }

class ConfigBuilder {
  static const _geositeRuUrl =
      'https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite-ru.srs';
  static const _geoipRuUrl =
      'https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip-ru.srs';

  static Map<String, dynamic> build(
    VpnProfile profile, {
    RoutingMode routingMode = RoutingMode.fullVpn,
    List<String> bypassDomains = const [],
    bool killSwitch = false,
  }) {
    final ruMode = routingMode == RoutingMode.russiaBypass;
    return {
      'log': {'level': 'warn'},
      'dns': _dns(russiaBypass: ruMode),
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

    final out = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': c['server'],
      'server_port': c['port'],
      'uuid': c['uuid'],
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

    return {
      'type': 'wireguard',
      'tag': 'proxy',
      'server': c['server'],
      'server_port': c['port'],
      'private_key': c['privateKey'],
      'peer_public_key': c['publicKey'],
      if ((c['presharedKey'] as String? ?? '').isNotEmpty)
        'pre_shared_key': c['presharedKey'],
      'local_address': addresses,
    };
  }

  static Map<String, dynamic> _amnezia(Map<String, dynamic> c) {
    final base = _wireguard(c);
    // AmneziaWG obfuscation params (supported in patched sing-box builds)
    final amneziaFields = <String, dynamic>{};
    for (final k in ['jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4']) {
      if (c.containsKey(k)) amneziaFields[k] = c[k];
    }
    if (amneziaFields.isNotEmpty) {
      return {...base, 'amnezia': amneziaFields};
    }
    return base;
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
        'inet4_address': '172.19.0.1/30',
        'inet6_address': 'fdfe:dcba:9876::1/126',
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'stack': 'system',
        'sniff': true,
        'sniff_override_destination': true,
      };

  // ── DNS ─────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _dns({bool russiaBypass = false}) => {
        'servers': [
          {'tag': 'remote', 'address': 'tls://1.1.1.1', 'detour': 'proxy'},
          {'tag': 'local', 'address': 'tls://8.8.8.8', 'detour': 'direct'},
        ],
        'rules': [
          {'outbound': 'any', 'server': 'local'},
          if (russiaBypass) {'rule_set': ['geosite-ru'], 'server': 'local'},
        ],
        'final': 'remote',
      };

  // ── Route ────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _route({
    required RoutingMode routingMode,
    required List<String> bypassDomains,
    required bool killSwitch,
  }) {
    final ruleSets = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[
      {'protocol': 'dns', 'outbound': 'dns-out'},
    ];

    switch (routingMode) {
      case RoutingMode.russiaBypass:
        ruleSets.addAll([
          {
            'type': 'remote',
            'tag': 'geosite-ru',
            'format': 'binary',
            'url': _geositeRuUrl,
            'download_detour': 'direct',
          },
          {
            'type': 'remote',
            'tag': 'geoip-ru',
            'format': 'binary',
            'url': _geoipRuUrl,
            'download_detour': 'direct',
          },
        ]);
        rules.add({
          'rule_set': ['geosite-ru', 'geoip-ru'],
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
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
      'rules': rules,
      'final': 'proxy',
      'auto_detect_interface': true,
      if (killSwitch) 'default_mark': 666,
    };
  }
}
