import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/profile.dart';

class ParseResult {
  final VpnProfile? profile;
  final List<VpnProfile>? batch;
  final String? error;

  ParseResult.success(this.profile)
      : batch = null,
        error = null;
  ParseResult.batch(this.batch)
      : profile = null,
        error = null;
  ParseResult.failure(this.error)
      : profile = null,
        batch = null;

  bool get isSubscription => batch != null;
}

class LinkParser {
  static ParseResult parse(String input) {
    final s = input.trim();
    if (s.startsWith('vless://')) return _parseVless(s);
    if (s.startsWith('tuic://')) return _parseTuic(s);
    if (s.startsWith('hysteria2://') || s.startsWith('hy2://')) {
      return _parseHysteria2(s);
    }
    if (s.startsWith('vpn://')) return _parseAmnezia(s);
    if (s.contains('[Interface]') || s.contains('PrivateKey =')) {
      return _parseWireguardConf(s);
    }
    if (s.startsWith('http://') || s.startsWith('https://')) {
      // Async — caller should use parseSubscriptionUrl()
      return ParseResult.failure('subscription_url');
    }
    return ParseResult.failure(
      'Unrecognized format.\nSupported: vless://, tuic://, hysteria2://, vpn:// (Amnezia), WireGuard .conf, subscription URL (http/https)',
    );
  }

  static bool isSubscriptionUrl(String s) {
    final t = s.trim();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  static Future<ParseResult> parseSubscriptionUrl(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url.trim()))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return ParseResult.failure('HTTP ${response.statusCode}');
      }
      String content = response.body.trim();
      // Try base64 decode (standard V2Ray/Hiddify subscription format)
      try {
        final decoded = utf8.decode(base64.decode(base64.normalize(content)));
        if (decoded.contains('://') || decoded.contains('[Interface]')) {
          content = decoded;
        }
      } catch (_) {}

      final lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final profiles = <VpnProfile>[];
      for (final line in lines) {
        final r = parse(line);
        if (r.profile != null) profiles.add(r.profile!);
      }

      if (profiles.isEmpty) {
        return ParseResult.failure('No valid profiles found in subscription');
      }
      return ParseResult.batch(profiles);
    } catch (e) {
      return ParseResult.failure('Fetch error: $e');
    }
  }

  // ── VLESS ──────────────────────────────────────────────────────────────────

  static ParseResult _parseVless(String url) {
    try {
      final uri = Uri.parse(url);
      final q = uri.queryParameters;
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '${uri.host}:${uri.port}';
      final transport = q['type'] ?? 'tcp';

      return ParseResult.success(VpnProfile(
        id: VpnProfile.generateId(),
        name: name,
        protocol: VpnProtocol.vless,
        config: {
          'uuid': uri.userInfo,
          'server': uri.host,
          'port': uri.port,
          'security': q['security'] ?? 'none',
          'transport': transport,
          'sni': q['sni'] ?? uri.host,
          'fp': q['fp'] ?? 'chrome',
          'pbk': q['pbk'] ?? '',
          'sid': q['sid'] ?? '',
          if (transport == 'grpc')
            'serviceName': q['serviceName'] ?? q['grpcServiceName'] ?? '',
          if (transport == 'httpupgrade' || transport == 'http')
            'path': q['path'] ?? '/',
          if (transport == 'ws') ...{
            'path': q['path'] ?? '/',
            'host': q['host'] ?? uri.host,
          },
        },
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      return ParseResult.failure('VLESS parse error: $e');
    }
  }

  // ── TUIC ───────────────────────────────────────────────────────────────────

  static ParseResult _parseTuic(String url) {
    try {
      final uri = Uri.parse(url);
      final info = uri.userInfo;
      final colon = info.indexOf(':');
      final q = uri.queryParameters;
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '${uri.host}:${uri.port}';

      return ParseResult.success(VpnProfile(
        id: VpnProfile.generateId(),
        name: name,
        protocol: VpnProtocol.tuic,
        config: {
          'uuid': colon >= 0 ? info.substring(0, colon) : info,
          'password': colon >= 0 ? info.substring(colon + 1) : '',
          'server': uri.host,
          'port': uri.port,
          'sni': q['sni'] ?? uri.host,
          'alpn': q['alpn'] ?? 'h3',
          'congestion': q['congestion_control'] ?? 'bbr',
          'insecure': q['allow_insecure'] == '1',
        },
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      return ParseResult.failure('TUIC parse error: $e');
    }
  }

  // ── Hysteria2 ──────────────────────────────────────────────────────────────

  static ParseResult _parseHysteria2(String url) {
    try {
      final uri = Uri.parse(url.replaceFirst('hy2://', 'hysteria2://'));
      final q = uri.queryParameters;
      final name = uri.fragment.isNotEmpty
          ? Uri.decodeComponent(uri.fragment)
          : '${uri.host}:${uri.port}';

      return ParseResult.success(VpnProfile(
        id: VpnProfile.generateId(),
        name: name,
        protocol: VpnProtocol.hysteria2,
        config: {
          'password': uri.userInfo,
          'server': uri.host,
          'port': uri.port,
          'sni': q['sni'] ?? uri.host,
          'insecure': q['insecure'] == '1',
          'obfs': q['obfs'] ?? '',
          'obfsPassword': q['obfs-password'] ?? '',
        },
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      return ParseResult.failure('Hysteria2 parse error: $e');
    }
  }

  // ── Amnezia (vpn://<base64url>) ────────────────────────────────────────────

  static ParseResult _parseAmnezia(String url) {
    try {
      final encoded = url.substring('vpn://'.length);
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      final jsonStr = utf8.decode(bytes);
      final root = jsonDecode(jsonStr) as Map<String, dynamic>;

      final containers = root['containers'] as List<dynamic>? ?? [];
      if (containers.isEmpty) {
        return ParseResult.failure('Amnezia: no containers found');
      }

      final container = containers.first as Map<String, dynamic>;
      final containerType = container['container'] as String? ?? '';

      String clientConf;
      if (containerType == 'amnezia-awg' && container['awg'] != null) {
        clientConf = (container['awg'] as Map)['client'] as String? ?? '';
      } else if (container['wireguard'] != null) {
        clientConf = (container['wireguard'] as Map)['client'] as String? ?? '';
      } else {
        return ParseResult.failure('Amnezia: unsupported container "$containerType"');
      }

      final wgResult = _parseWireguardConf(clientConf);
      if (wgResult.profile == null) return wgResult;

      // Promote to amnezia protocol with original config
      final cfg = Map<String, dynamic>.from(wgResult.profile!.config);
      // Extract AmneziaWG obfuscation params if present
      if (containerType == 'amnezia-awg') {
        _extractAmneziaPairs(clientConf, cfg);
      }

      return ParseResult.success(VpnProfile(
        id: VpnProfile.generateId(),
        name: wgResult.profile!.name,
        protocol: VpnProtocol.amnezia,
        config: cfg,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      return ParseResult.failure('Amnezia parse error: $e');
    }
  }

  static void _extractAmneziaPairs(String conf, Map<String, dynamic> out) {
    for (final line in conf.split('\n')) {
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      final val = line.substring(eq + 1).trim();
      if ({'jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4'}
          .contains(key)) {
        out[key] = int.tryParse(val) ?? val;
      }
    }
  }

  // ── WireGuard .conf ────────────────────────────────────────────────────────

  static ParseResult _parseWireguardConf(String conf) {
    try {
      final data = <String, String>{};
      String? section;

      for (final raw in conf.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith('[') && line.endsWith(']')) {
          section = line.substring(1, line.length - 1).toLowerCase();
          continue;
        }
        final eq = line.indexOf('=');
        if (eq < 0 || section == null) continue;
        final key = '${section}_${line.substring(0, eq).trim().toLowerCase()}';
        data[key] = line.substring(eq + 1).trim();
      }

      final endpoint = data['peer_endpoint'] ?? '';
      final colon = endpoint.lastIndexOf(':');
      final server = colon >= 0 ? endpoint.substring(0, colon) : endpoint;
      final port = colon >= 0
          ? int.tryParse(endpoint.substring(colon + 1)) ?? 51820
          : 51820;

      return ParseResult.success(VpnProfile(
        id: VpnProfile.generateId(),
        name: server.isNotEmpty ? server : 'WireGuard',
        protocol: VpnProtocol.wireguard,
        config: {
          'privateKey': data['interface_privatekey'] ?? '',
          'publicKey': data['peer_publickey'] ?? '',
          'presharedKey': data['peer_presharedkey'] ?? '',
          'server': server,
          'port': port,
          'address': data['interface_address'] ?? '10.0.0.1/32',
          'dns': data['interface_dns'] ?? '1.1.1.1',
          'allowedIPs': data['peer_allowedips'] ?? '0.0.0.0/0',
        },
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      return ParseResult.failure('WireGuard parse error: $e');
    }
  }
}
