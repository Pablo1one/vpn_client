import 'dart:convert';
import '../models/profile.dart';

class ParseResult {
  final VpnProfile? profile;
  final String? error;

  ParseResult.success(this.profile) : error = null;
  ParseResult.failure(this.error) : profile = null;
}

class LinkParser {
  static ParseResult parse(String input) {
    final s = input.trim();
    if (s.startsWith('vless://')) return _parseVless(s);
    if (s.startsWith('tuic://')) return _parseTuic(s);
    if (s.startsWith('hysteria2://') || s.startsWith('hy2://')) {
      return _parseHysteria2(s);
    }
    if (s.contains('[Interface]') || s.contains('PrivateKey =')) {
      return _parseWireguardConf(s);
    }
    return ParseResult.failure('Unrecognized format.\nSupported: vless://, tuic://, hysteria2://, WireGuard .conf');
  }

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
