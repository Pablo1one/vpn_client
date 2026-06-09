import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/profile.dart';
import '../models/route_rule.dart';

enum RoutingMode { fullVpn, russiaBypass, custom }

class ConfigBuilder {
  // Секрет для clash_api (порт 9090): без него любое локальное приложение могло бы
  // рулить sing-box. Генерится раз на запуск, шарится со SpeedService.
  static final String clashApiSecret = _genHex(16);

  // Креды для локального socks 10808: иначе любое приложение ходило бы через наш
  // VPN как через открытый прокси. Inbound и TUN-форвардер берут их отсюда.
  static final String socksUser = 'lm_${_genHex(4)}';
  static final String socksPass = _genHex(12);

  static String _genHex(int bytes) {
    final r = Random.secure();
    return List.generate(
        bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // мобильный: полный singbox конфиг (tun + аутбаунд протокола)
  static Map<String, dynamic> build(
    VpnProfile profile, {
    RoutingMode routingMode = RoutingMode.fullVpn,
    bool killSwitch = false,
    List<String> bypassDomains = const [],
    List<String> ruCidrs = const [],
    bool mux = false,
    String dns = '8.8.8.8',
    bool allowInsecure = false,
    bool tfo = false,
    bool fragment = false, // tls-фрагментация ClientHello (анти-dpi), только vless+tls
    bool fragmentRecord = false, // дробить по tls-записям (стойче, но не для всех серверов)
    Map<String, dynamic>? warp, // warp-каскад: выход через cloudflare поверх сервера
    List<String> bypassApps = const [], // split-tunnel: эти процессы идут напрямую
    List<String> excludeApps = const [], // android: пакеты мимо VPN (tun exclude_package)
    String? adsRuleSet, // путь к geosite-ads .srs (блокировка рекламы), null = выкл
    String tunName = 'tun0', // имя tun-адаптера; на windows ротируем чтобы не упираться
                             // в wintun-призрак от прошлой сессии (15с делей на коннекте)
    List<RouteRule> customRules = const [], // свои правила (приоритет над режимом)
  }) {
    final dnsAddr = dns.trim().isEmpty ? '8.8.8.8' : dns.trim();
    // android: правило "напрямую + приложение" уводим на TUN-уровень (exclude_package),
    // чтобы трафик приложения ВООБЩЕ не входил в туннель - иначе vpn-детект (банки и пр)
    // видит наш адрес на входе. остальные правила идут обычным route.
    final excludePkgs = <String>[...excludeApps];
    final effectiveCustom = <RouteRule>[];
    for (final r in customRules) {
      if (Platform.isAndroid &&
          r.action == RuleAction.direct &&
          r.match == RuleMatch.process &&
          r.value.trim().isNotEmpty) {
        excludePkgs.add(r.value.trim());
      } else {
        effectiveCustom.add(r);
      }
    }
    // AmneziaWG идёт endpoint'ом (форк amnezia-box), у остальных - обычный outbound
    final isAwg = profile.protocol == VpnProtocol.amnezia;
    final Map<String, dynamic>? outbound = isAwg
        ? null
        : switch (profile.protocol) {
            // dns-direct: резолв адреса сервера напрямую, без петли через proxy
            VpnProtocol.vless => _singboxVless(profile.config,
                allowInsecure: allowInsecure, tfo: tfo, fragment: fragment,
                fragmentRecord: fragmentRecord)
              ..['domain_resolver'] = {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
            VpnProtocol.tuic => _tuic(profile.config, allowInsecure: allowInsecure),
            VpnProtocol.hysteria2 =>
              _hysteria2(profile.config, allowInsecure: allowInsecure),
            _ => throw ArgumentError('build: unsupported protocol ${profile.protocol}'),
          };
    // mux только для vless: tuic/hysteria2 поверх quic не мультиплексируются
    if (mux && outbound != null && profile.protocol == VpnProtocol.vless) {
      outbound['multiplex'] = _singboxMux();
    }

    final serverAddress = profile.config['server'] as String? ?? '';
    // sniff и hijack-dns - ПЕРВЫМИ: иначе dns-пакеты на приватный адрес туннеля
    // матчатся на ip_is_private - direct раньше перехвата - dns не резолвится
    final rules = <Map<String, dynamic>>[
      {'action': 'sniff'},
      {'action': 'hijack-dns', 'protocol': 'dns'},
    ];
    // блокировка рекламы: режем домены из geosite-ads (после sniff - домен известен)
    if (adsRuleSet != null) {
      rules.add({'rule_set': ['geosite-ads'], 'action': 'reject'});
    }
    rules.add({'ip_is_private': true, 'outbound': 'direct'});
    if (serverAddress.isNotEmpty) {
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(serverAddress);
      rules.add({
        if (isIp) 'ip_cidr': [serverAddress] else 'domain': [serverAddress],
        'outbound': 'direct',
      });
    }
    // свои правила (shadowrocket-подобные): приоритет над режимом и split-tunnel.
    // порядок блок -> напрямую -> через vpn: блок бьёт всё, а proxy перебивает
    // "россия напрямую" для конкретного домена/ip
    if (effectiveCustom.isNotEmpty) {
      final proxyTag = warp != null ? 'warp' : 'proxy';
      // приложение: на android матчим по package_name, на windows - по process_name
      String fieldFor(RouteRule r) => r.match == RuleMatch.process
          ? (Platform.isAndroid ? 'package_name' : 'process_name')
          : r.singboxField;
      void addByAction(RuleAction a, Map<String, dynamic> Function(RouteRule) make) {
        for (final r in effectiveCustom.where((r) => r.action == a)) {
          if (r.value.trim().isEmpty) continue;
          rules.add(make(r));
        }
      }
      addByAction(RuleAction.block,
          (r) => {fieldFor(r): [r.value.trim()], 'action': 'reject'});
      addByAction(RuleAction.direct,
          (r) => {fieldFor(r): [r.value.trim()], 'outbound': 'direct'});
      addByAction(RuleAction.proxy,
          (r) => {fieldFor(r): [r.value.trim()], 'outbound': proxyTag});
    }
    // split-tunnel: выбранные приложения мимо VPN (напрямую)
    if (bypassApps.isNotEmpty) {
      rules.add({'process_name': bypassApps, 'outbound': 'direct'});
    }
    if (routingMode == RoutingMode.russiaBypass && ruCidrs.isNotEmpty) {
      rules.add({'ip_cidr': ruCidrs, 'outbound': 'direct'});
    }
    // custom: пользовательские домены мимо VPN (напрямую)
    if (bypassDomains.isNotEmpty) {
      rules.add({'domain_suffix': bypassDomains, 'outbound': 'direct'});
    }

    return {
      'log': {'level': 'info'},
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:9090',
          'secret': clashApiSecret,
        },
      },
      'dns': {
        'servers': [
          {
            'address': dnsAddr,
            'detour': routingMode == RoutingMode.fullVpn ? 'proxy' : 'direct',
            'tag': 'dns',
          },
          {
            'address': '1.1.1.1',
            'detour': 'direct',
            'tag': 'dns-direct',
          },
        ],
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': tunName,
          // Только ipv4: захват ipv6 в TUN без реального ipv6-егресса (частое на
          // Windows) ломает AAAA - "network is unreachable". ipv6 идёт мимо.
          'address': ['172.19.0.1/30'],
          // в warp-каскаде mtu ниже: app-пакеты должны влезать в WG warp (1280)
          // без фрагментации, иначе download проседает
          'mtu': warp != null ? 1280 : 1400,
          'auto_route': true,
          'strict_route': killSwitch,
          'stack': 'mixed',
          // ведроид split-tunnel: выбранные пакеты идут мимо VPN (включая правила
          // "напрямую + приложение" - они тут, вне туннеля, не светят наш ip)
          if (excludePkgs.isNotEmpty) 'exclude_package': excludePkgs,
        },
      ],
      'outbounds': [
        if (outbound != null) outbound,
        {
          'type': 'direct',
          'tag': 'direct',
        },
      ],
      // endpoints: warp-каскад (дозвон до cloudflare через proxy) и/или AmneziaWG.
      // у awg endpoint tag 'proxy' - финал маршрута на него.
      if (warp != null || isAwg)
        'endpoints': [
          if (warp != null) _warpEndpoint(warp, detour: 'proxy'),
          if (isAwg) _awgEndpoint(profile.config),
        ],
      'route': {
        'auto_detect_interface': true,
        'final': warp != null ? 'warp' : 'proxy',
        'default_domain_resolver': {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
        if (adsRuleSet != null)
          'rule_set': [
            {
              'type': 'local',
              'tag': 'geosite-ads',
              'format': 'binary',
              'path': adsRuleSet,
            },
          ],
        'rules': rules,
      },
    };
  }





  static String toJson(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);



  // warp как wireguard-endpoint (sing-box 1.12). detour - через какой outbound
  // дозваниваться до эндпоинта cloudflare (в каскаде = наш сервер).
  // Только ipv4 (v6 у нас отключён), чтобы не ловить "network unreachable".
  static Map<String, dynamic> _warpEndpoint(
    Map<String, dynamic> w, {
    required String detour,
  }) {
    final ep = (w['endpoint'] as String? ?? '').trim();
    final ci = ep.lastIndexOf(':');
    final host = ci >= 0 ? ep.substring(0, ci) : ep;
    var port = ci >= 0 ? (int.tryParse(ep.substring(ci + 1)) ?? 2408) : 2408;
    // warp api отдаёт v4-эндпоинт с портом-заглушкой :0 - реальный порт 2408
    if (port <= 0) port = 2408;
    return {
      'type': 'wireguard',
      'tag': 'warp',
      'mtu': 1280,
      'address': [w['address']], // v4/32 из warp-конфига
      'private_key': w['privateKey'],
      'peers': [
        {
          'address': host,
          'port': port,
          'public_key': w['publicKey'],
          'allowed_ips': ['0.0.0.0/0'],
          'persistent_keepalive_interval': 25,
          // reserved (client_id) - критично: без него cloudflare не маршрутизирует
          // обратный трафик (download ≈ 0 при живом хендшейке)
          if (w['reserved'] != null) 'reserved': w['reserved'],
        },
      ],
      'detour': detour,
    };
  }

  // AmneziaWG endpoint (форк amnezia-box, type=awg). Маршрутизацию решает sing-box
  // (route rules), поэтому allowed_ips = 0.0.0.0/0; obfuscation-параметры из профиля.
  static Map<String, dynamic> _awgEndpoint(Map<String, dynamic> c) {
    int? asInt(String k) => int.tryParse('${c[k] ?? ''}');
    String? asStr(String k) {
      final v = c[k]?.toString();
      return (v != null && v.isNotEmpty) ? v : null;
    }

    final psk = (c['presharedKey'] as String? ?? '').trim();
    final ep = <String, dynamic>{
      'type': 'awg',
      'tag': 'proxy',
      'private_key': c['privateKey'],
      'address': (c['address'] as String? ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'mtu': asInt('mtu') ?? 1280,
      'peers': [
        {
          'address': c['server'],
          'port': asInt('port') ?? 0,
          'public_key': c['publicKey'],
          if (psk.isNotEmpty) 'preshared_key': psk,
          'allowed_ips': ['0.0.0.0/0'],
          'persistent_keepalive_interval':
              asInt('persistentKeepalive') ?? asInt('keepalive') ?? 25,
        },
      ],
    };
    // обфускация: только присутствующие параметры (omitempty на стороне sing-box)
    for (final k in ['jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4']) {
      final v = asInt(k);
      if (v != null && v != 0) ep[k] = v;
    }
    for (final k in ['h1', 'h2', 'h3', 'h4', 'i1', 'i2', 'i3', 'i4', 'i5']) {
      final v = asStr(k);
      if (v != null) ep[k] = v;
    }
    return ep;
  }

  // sing-box multiplex (требует поддержки на сервере)
  static Map<String, dynamic> _singboxMux() => {
        'enabled': true,
        'protocol': 'h2mux',
        'max_streams': 8,
      };

  static Map<String, dynamic> _singboxVless(
    Map<String, dynamic> c, {
    bool allowInsecure = false,
    bool tfo = false,
    bool fragment = false,
    bool fragmentRecord = false,
  }) {
    final transport = c['transport'] as String? ?? 'tcp';
    final security = c['security'] as String? ?? 'none';
    final rawFlow = (c['flow'] as String? ?? '').trim();
    final flow = (transport == 'grpc') ? '' : rawFlow;
    final insecure = c['insecure'] == true || allowInsecure;

    final out = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': c['server'],
      'server_port': c['port'],
      'uuid': c['uuid'],
      if (tfo) 'tcp_fast_open': true,
    };

    if (flow.isNotEmpty) out['flow'] = flow;

    if (security == 'reality') {
      out['tls'] = {
        'enabled': true,
        'server_name': c['sni'],
        'reality': {'enabled': true, 'public_key': c['pbk'], 'short_id': c['sid']},
        'utls': {'enabled': true, 'fingerprint': c['fp'] ?? 'chrome'},
      };
    } else if (security == 'tls') {
      out['tls'] = {
        'enabled': true,
        'server_name': c['sni'],
        'insecure': insecure,
        'utls': {'enabled': true, 'fingerprint': c['fp'] ?? 'chrome'},
      };
    }

    // tls-фрагментация ClientHello (анти-dpi). по умолчанию по tcp-сегментам.
    // record_fragment (по tls-записям) - стойче против reassembly-dpi, НО ломает
    // sni-роутинг на haproxy (sni размазан по tls-записям) - поэтому off by default.
    if (fragment && out['tls'] is Map) {
      (out['tls'] as Map)[fragmentRecord ? 'record_fragment' : 'fragment'] = true;
    }

    switch (transport) {
      case 'ws':
        out['transport'] = {
          'type': 'ws',
          'path': c['path'] ?? '/',
          'headers': {'Host': c['host'] ?? c['sni']},
        };
      case 'grpc':
        out['transport'] = {
          'type': 'grpc',
          'service_name': c['serviceName'] ?? '',
        };
      case 'xhttp':
        // формат как в sing-box (форк amnezia-box с портом xhttp): mode/host/path
        out['transport'] = {
          'type': 'xhttp',
          'mode': c['mode'] ?? 'auto',
          'host': c['host'] ?? c['sni'] ?? c['server'],
          'path': c['path'] ?? '/',
        };
      case 'httpupgrade':
      case 'http':
        out['transport'] = {
          'type': 'http',
          'host': [c['sni'] ?? c['server']],
          'path': c['path'] ?? '/',
        };
    }

    return out;
  }

  static Map<String, dynamic> _tuic(
    Map<String, dynamic> c, {
    bool allowInsecure = false,
  }) =>
      {
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
          'insecure': c['insecure'] == true || allowInsecure,
        },
        // адрес сервера резолвим НАПРЯМУЮ (иначе петля: резолв через сам прокси)
        'domain_resolver': {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
      };

  static Map<String, dynamic> _hysteria2(
    Map<String, dynamic> c, {
    bool allowInsecure = false,
  }) {
    final out = <String, dynamic>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': c['server'],
      'server_port': c['port'],
      'password': c['password'],
      'tls': {
        'enabled': true,
        'server_name': c['sni'],
        'insecure': c['insecure'] == true || allowInsecure,
      },
    };
    final obfs = c['obfs'] as String? ?? '';
    if (obfs.isNotEmpty) {
      out['obfs'] = {'type': obfs, 'password': c['obfsPassword'] ?? ''};
    }
    // адрес сервера резолвим НАПРЯМУЮ (иначе петля через сам прокси)
    out['domain_resolver'] = {'server': 'dns-direct', 'strategy': 'prefer_ipv4'};
    return out;
  }
}
