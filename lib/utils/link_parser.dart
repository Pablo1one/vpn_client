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
      final uri = _normalizeSubscriptionUri(url.trim());

      final response = await http.get(uri, headers: {
        'User-Agent': 'Hiddify/2.0.5+462',
        'Accept': 'application/json, text/plain, */*',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ParseResult.failure('HTTP ${response.statusCode}');
      }

      final body = response.body.trim();

      // Reject HTML pages (e.g. Hiddify web UI returned due to ?home=true)
      if (body.startsWith('<!') || body.startsWith('<html')) {
        return ParseResult.failure(
            'Сервер вернул HTML-страницу вместо подписки.\n'
            'Убедитесь, что URL — ссылка на подписку, а не на веб-панель.');
      }

      // 1. Try JSON (Hiddify JSON with "configs", or sing-box JSON with "outbounds")
      try {
        final json = jsonDecode(body);
        final profiles = _parseJsonSubscription(json);
        if (profiles.isNotEmpty) return ParseResult.batch(profiles);
      } catch (_) {}

      // 2. Try base64 decode → line-by-line URIs
      String content = body;
      try {
        final decoded =
            utf8.decode(base64.decode(base64.normalize(content)));
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

  /// Removes Hiddify web-UI query params (?home=true, ?base64=...) that
  /// cause the server to return an HTML page instead of subscription content.
  static Uri _normalizeSubscriptionUri(String url) {
    final uri = Uri.parse(url);
    final paramsToRemove = {'home', 'base64', 'clash', 'singbox'};
    final cleaned = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((k, _) => paramsToRemove.contains(k.toLowerCase()));
    return uri.replace(queryParameters: cleaned.isEmpty ? null : cleaned);
  }

  /// Parses Hiddify JSON (`configs` array) or sing-box JSON (`outbounds` array).
  static List<VpnProfile> _parseJsonSubscription(dynamic json) {
    final profiles = <VpnProfile>[];

    List<dynamic>? items;
    if (json is Map) {
      items = (json['configs'] ?? json['outbounds']) as List<dynamic>?;
    } else if (json is List) {
      items = json;
    }
    if (items == null) return profiles;

    for (final item in items) {
      if (item is! Map) continue;
      final p = _profileFromJsonOutbound(item);
      if (p != null) profiles.add(p);
    }
    return profiles;
  }

  static VpnProfile? _profileFromJsonOutbound(Map item) {
    final type = (item['type'] as String? ?? '').toLowerCase();
    final name = (item['tag'] ?? item['name'] ?? item['type'] ?? 'profile')
        as String;
    final server = (item['server'] as String?) ?? '';
    final port = (item['server_port'] ?? item['port'] ?? 0) as int;

    try {
      switch (type) {
        case 'vless':
          final tls = item['tls'] as Map? ?? {};
          final transport = item['transport'] as Map? ?? {};
          final transportType = (transport['type'] as String? ?? 'tcp');
          return VpnProfile(
            id: VpnProfile.generateId(),
            name: name,
            protocol: VpnProtocol.vless,
            config: {
              'uuid': item['uuid'] ?? '',
              'server': server,
              'port': port,
              'security': tls['enabled'] == true ? 'tls' : 'none',
              'transport': transportType,
              'sni': tls['server_name'] ?? server,
              'fp': (tls['utls'] as Map?)?['fingerprint'] ?? 'chrome',
              'pbk': (tls['reality'] as Map?)?['public_key'] ?? '',
              'sid': (tls['reality'] as Map?)?['short_id'] ?? '',
              'flow': item['flow'] ?? '',
              'path': transport['path'] ?? '/',
              'host': (transport['headers'] as Map?)?['Host'] ?? server,
              if (transportType == 'grpc')
                'serviceName': transport['service_name'] ?? '',
            },
            createdAt: DateTime.now(),
          );
        case 'tuic':
          final tls = item['tls'] as Map? ?? {};
          return VpnProfile(
            id: VpnProfile.generateId(),
            name: name,
            protocol: VpnProtocol.tuic,
            config: {
              'uuid': item['uuid'] ?? '',
              'password': item['password'] ?? '',
              'server': server,
              'port': port,
              'sni': tls['server_name'] ?? server,
              'alpn': ((tls['alpn'] as List?)?.first ?? 'h3').toString(),
              'congestion': item['congestion_control'] ?? 'bbr',
              'insecure': tls['insecure'] ?? false,
            },
            createdAt: DateTime.now(),
          );
        case 'hysteria2':
        case 'hysteria':
          final tls = item['tls'] as Map? ?? {};
          final obfs = item['obfs'] as Map? ?? {};
          return VpnProfile(
            id: VpnProfile.generateId(),
            name: name,
            protocol: VpnProtocol.hysteria2,
            config: {
              'password': item['password'] ?? '',
              'server': server,
              'port': port,
              'sni': tls['server_name'] ?? server,
              'insecure': tls['insecure'] ?? false,
              'obfs': obfs['type'] ?? '',
              'obfsPassword': (obfs['salamander'] as Map?)?['password'] ?? '',
            },
            createdAt: DateTime.now(),
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
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

  // ── WireGuard / AmneziaWG .conf ──────────────────────────────────────────

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

      // AmneziaWG obfuscation params (Jc, Jmin, Jmax, S1, S2, H1–H4)
      const awgKeys = {'jc', 'jmin', 'jmax', 's1', 's2', 'h1', 'h2', 'h3', 'h4'};
      final awgParams = <String, dynamic>{};
      for (final k in awgKeys) {
        final v = data['interface_$k'];
        if (v != null) awgParams[k] = int.tryParse(v) ?? v;
      }
      final isAmnezia = awgParams.isNotEmpty;

      final cfg = <String, dynamic>{
        'privateKey': data['interface_privatekey'] ?? '',
        'publicKey': data['peer_publickey'] ?? '',
        'presharedKey': data['peer_presharedkey'] ?? '',
        'server': server,
        'port': port,
        'address': data['interface_address'] ?? '10.0.0.1/32',
        'dns': data['interface_dns'] ?? '1.1.1.1',
        'allowedIPs': data['peer_allowedips'] ?? '0.0.0.0/0',
        ...awgParams,
      };

      return ParseResult.success(VpnProfile(
        id: VpnProfile.generateId(),
        name: server.isNotEmpty ? server : (isAmnezia ? 'AmneziaWG' : 'WireGuard'),
        protocol: isAmnezia ? VpnProtocol.amnezia : VpnProtocol.wireguard,
        config: cfg,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      return ParseResult.failure('WireGuard parse error: $e');
    }
  }
}
