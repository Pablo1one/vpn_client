import 'dart:convert';
import 'dart:math';
import '../models/profile.dart';

enum RoutingMode { fullVpn, russiaBypass, custom }

// приватные диапазоны — всегда напрямую
const _kPrivateCidrs = [
  '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
  '127.0.0.0/8', '169.254.0.0/16', '224.0.0.0/4',
];

class ConfigBuilder {
  // Случайный секрет для clash_api: порт 9090 слушается на localhost, и с пустым
  // секретом любое локальное приложение могло бы управлять sing-box (менять прокси,
  // читать трафик). Секрет генерируется один раз на запуск и шарится со SpeedService.
  static final String clashApiSecret = _genHex(16);

  // Логин/пароль для локального socks 10808: иначе любое локальное приложение
  // могло бы бесплатно ходить через наш VPN как через открытый прокси.
  // Inbound (прокси) и outbound (TUN-форвардер) берут одни и те же креды отсюда.
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
    Map<String, dynamic>? warp, // WARP-каскад: выход через Cloudflare поверх сервера
    List<String> bypassApps = const [], // split-tunnel: эти процессы идут напрямую
    String? adsRuleSet, // путь к geosite-ads .srs (блокировка рекламы), null = выкл
  }) {
    final dnsAddr = dns.trim().isEmpty ? '8.8.8.8' : dns.trim();
    final Map<String, dynamic> outbound = switch (profile.protocol) {
      // dns-direct: резолв адреса сервера напрямую, без петли через proxy
      VpnProtocol.vless => _singboxVless(profile.config,
          allowInsecure: allowInsecure, tfo: tfo)
        ..['domain_resolver'] = {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
      VpnProtocol.tuic => _tuic(profile.config, allowInsecure: allowInsecure),
      VpnProtocol.hysteria2 =>
        _hysteria2(profile.config, allowInsecure: allowInsecure),
      _ => throw ArgumentError('build: unsupported protocol ${profile.protocol}'),
    };
    if (mux) outbound['multiplex'] = _singboxMux();

    final serverAddress = profile.config['server'] as String? ?? '';
    final rules = <Map<String, dynamic>>[
      {'ip_is_private': true, 'outbound': 'direct'},
    ];
    if (serverAddress.isNotEmpty) {
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(serverAddress);
      rules.add({
        if (isIp) 'ip_cidr': [serverAddress] else 'domain': [serverAddress],
        'outbound': 'direct',
      });
    }
    // split-tunnel: выбранные приложения мимо VPN (напрямую)
    if (bypassApps.isNotEmpty) {
      rules.add({'process_name': bypassApps, 'outbound': 'direct'});
    }
    rules.add({'action': 'sniff'});
    // блокировка рекламы: режем домены из geosite-ads (после sniff — домен известен)
    if (adsRuleSet != null) {
      rules.add({'rule_set': ['geosite-ads'], 'action': 'reject'});
    }
    rules.add({'action': 'hijack-dns', 'protocol': 'dns'});
    if (routingMode == RoutingMode.russiaBypass && ruCidrs.isNotEmpty) {
      rules.add({'ip_cidr': ruCidrs, 'outbound': 'direct'});
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
          'interface_name': 'tun0',
          // Только IPv4. Захват IPv6 в TUN при отсутствии реального IPv6-егресса
          // (частый случай на Windows: есть ULA/temporary адрес, но нет маршрута)
          // ломает всё с AAAA → "network is unreachable". Пусть IPv6 идёт мимо.
          'address': ['172.19.0.1/30'],
          // в WARP-каскаде MTU ниже: app-пакеты должны влезать в WG WARP (1280)
          // без фрагментации, иначе download проседает
          'mtu': warp != null ? 1280 : 1400,
          'auto_route': true,
          'strict_route': killSwitch,
          'stack': 'mixed',
        },
      ],
      'outbounds': [
        outbound,
        {
          'type': 'direct',
          'tag': 'direct',
        },
      ],
      // WARP-каскад: endpoint дозванивается до Cloudflare ЧЕРЕЗ proxy (наш сервер),
      // финал маршрута → warp. Когда warp == null — секции нет, всё как обычно.
      if (warp != null) 'endpoints': [_warpEndpoint(warp, detour: 'proxy')],
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

  // tun форвардер: только ipv4 tun → socks5 10808
  static Map<String, dynamic> buildTun({
    bool killSwitch = false,
    RoutingMode routingMode = RoutingMode.fullVpn,
    String dns = '8.8.8.8',
    List<String> ruCidrs = const [],
    Map<String, dynamic>? warp, // WARP-каскад поверх socks-прокси (нашего сервера)
    List<String> bypassApps = const [], // split-tunnel: эти процессы идут напрямую
    String? adsRuleSet, // путь к geosite-ads .srs (блокировка рекламы)
  }) {
    final dnsAddr = dns.trim().isEmpty ? '8.8.8.8' : dns.trim();
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
          ],
        },
        'inbounds': [
          {
            'type': 'tun',
            'tag': 'tun-in',
            'interface_name': 'tun0',
            'address': ['172.19.0.1/30'],
            // в WARP-каскаде MTU ниже (app-пакеты должны влезать в WG WARP)
            'mtu': warp != null ? 1280 : 1400,
            'auto_route': true,
            // strict_route только при kill switch: иначе на Windows он ломает
            // раздельную маршрутизацию (bypass) и обход, как заметно против Happ
            'strict_route': killSwitch,
            'stack': 'mixed',
          },
        ],
        'outbounds': [
          {
            'type': 'socks',
            'tag': 'proxy',
            'server': '127.0.0.1',
            'server_port': 10808,
            'udp_fragment': true,
            'username': socksUser,
            'password': socksPass,
            'domain_resolver': {'server': 'dns', 'strategy': 'prefer_ipv4'},
          },
          {
            'type': 'direct',
            'tag': 'direct',
            'domain_resolver': {'server': 'dns', 'strategy': 'prefer_ipv4'},
          },
        ],
        // WARP-каскад: дозвон до Cloudflare через proxy (socks → наш сервер)
        if (warp != null) 'endpoints': [_warpEndpoint(warp, detour: 'proxy')],
        'route': {
          'auto_detect_interface': true,
          'final': warp != null ? 'warp' : 'proxy',
          // sing-box 1.12: глобальный резолвер доменов (иначе первый резолв буксует → "нет интернета")
          'default_domain_resolver': {'server': 'dns', 'strategy': 'prefer_ipv4'},
          if (adsRuleSet != null)
            'rule_set': [
              {
                'type': 'local',
                'tag': 'geosite-ads',
                'format': 'binary',
                'path': adsRuleSet,
              },
            ],
          'rules': [
            // исключаем только прокси-процессы (от петли). Сам клиент НЕ исключаем —
            // иначе его трафик (в т.ч. регистрация WARP) шёл бы мимо туннеля и в РФ
            // не достучался бы до API Cloudflare.
            {
              'process_name': ['xray.exe', 'sing-box.exe'],
              'outbound': 'direct',
            },
            // split-tunnel: выбранные приложения мимо VPN (напрямую)
            if (bypassApps.isNotEmpty)
              {'process_name': bypassApps, 'outbound': 'direct'},
            // в каскаде приватное и (при bypass) российское — мимо WARP, напрямую
            if (warp != null) {'ip_is_private': true, 'outbound': 'direct'},
            if (warp != null &&
                routingMode == RoutingMode.russiaBypass &&
                ruCidrs.isNotEmpty)
              {'ip_cidr': ruCidrs, 'outbound': 'direct'},
            {'action': 'sniff'},
            // блокировка рекламы: режем домены geosite-ads (после sniff)
            if (adsRuleSet != null)
              {'rule_set': ['geosite-ads'], 'action': 'reject'},
            {'action': 'hijack-dns', 'protocol': 'dns'},
          ],
        },
      };
  }

  // xray конфиг для vless — socks5 на 10808 с ip маршрутизацией
  static String buildXrayVless(
    VpnProfile profile, {
    RoutingMode routingMode = RoutingMode.fullVpn,
    List<String> ruCidrs = const [],
    bool mux = false,
    bool fragment = false,
    String fragPackets = 'tlshello',
    String fragLength = '100-200',
    String fragInterval = '10-20',
    bool allowInsecure = false,
    bool tfo = false,
  }) {
    final c = profile.config;
    final transport = (c['transport'] as String? ?? 'tcp').trim();
    final rawFlow = (c['flow'] as String? ?? '').trim();
    // gRPC не совместим с xtls flow — xray упадёт молча
    final flow = (transport == 'grpc') ? '' : rawFlow;
    // MUX несовместим с xtls-rprx-vision flow
    final muxOk = mux && flow.isEmpty;

    final stream = _xrayStream(c, allowInsecure: allowInsecure, tfo: tfo);
    // фрагментация: проксируем диалер через fragment-outbound
    if (fragment) {
      final sockopt = (stream['sockopt'] as Map<String, dynamic>?) ?? {};
      sockopt['dialerProxy'] = 'fragment';
      stream['sockopt'] = sockopt;
    }

    final config = {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'listen': '127.0.0.1',
          'port': 10808,
          'protocol': 'socks',
          'settings': {
            'auth': 'password',
            'accounts': [
              {'user': socksUser, 'pass': socksPass},
            ],
            'udp': true,
          },
        },
      ],
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': c['server'],
                'port': c['port'],
                'users': [
                  {
                    'id': c['uuid'],
                    'encryption': 'none',
                    if (flow.isNotEmpty) 'flow': flow,
                  },
                ],
              },
            ],
          },
          'streamSettings': stream,
          if (muxOk) 'mux': {'enabled': true, 'concurrency': 8},
          'tag': 'proxy',
        },
        if (fragment)
          {
            'protocol': 'freedom',
            'settings': {
              'fragment': {
                'packets': fragPackets,
                'length': fragLength,
                'interval': fragInterval,
              },
              'domainStrategy': 'UseIP',
            },
            'tag': 'fragment',
          },
        {
          'protocol': 'freedom',
          'settings': {'domainStrategy': 'UseIPv4'},
          'tag': 'direct',
        },
      ],
      'routing': _xrayRouting(
        routingMode: routingMode,
        ruCidrs: ruCidrs,
        serverAddress: c['server'] as String?,
      ),
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  // singbox socks5 прокси для tuic/h2/vless-grpc — ip маршрутизация
  static Map<String, dynamic> buildSingboxProxy(
    VpnProfile profile, {
    RoutingMode routingMode = RoutingMode.fullVpn,
    List<String> ruCidrs = const [],
    bool mux = false,
    String dns = '8.8.8.8',
    bool allowInsecure = false,
    bool tfo = false,
  }) {
    final dnsAddr = dns.trim().isEmpty ? '8.8.8.8' : dns.trim();
    final outbound = switch (profile.protocol) {
      // dns-direct — bootstrap DNS для резолва хоста сервера без循环
      VpnProtocol.vless => _singboxVless(profile.config,
          allowInsecure: allowInsecure, tfo: tfo)
        ..['domain_resolver'] = {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
      VpnProtocol.tuic => _tuic(profile.config, allowInsecure: allowInsecure),
      VpnProtocol.hysteria2 =>
        _hysteria2(profile.config, allowInsecure: allowInsecure),
      _ => throw ArgumentError(
          'buildSingboxProxy: unsupported protocol ${profile.protocol}'),
    };
    // MUX (tuic/hysteria — QUIC, мультиплекс не применяется; только vless)
    if (mux && profile.protocol == VpnProtocol.vless) {
      outbound['multiplex'] = _singboxMux();
    }

    final serverAddress = profile.config['server'] as String? ?? '';
    final rules = <Map<String, dynamic>>[
      {'ip_is_private': true, 'outbound': 'direct'},
    ];
    if (serverAddress.isNotEmpty) {
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(serverAddress);
      rules.add({
        if (isIp) 'ip_cidr': [serverAddress] else 'domain': [serverAddress],
        'outbound': 'direct',
      });
    }
    if (routingMode == RoutingMode.russiaBypass && ruCidrs.isNotEmpty) {
      rules.add({'ip_cidr': ruCidrs, 'outbound': 'direct'});
    }

    return {
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {
            'address': dnsAddr,
            'detour': routingMode == RoutingMode.fullVpn ? 'proxy' : 'direct',
            'tag': 'dns',
          },
          // bootstrap: резолвим адрес прокси-сервера напрямую
          {
            'address': '1.1.1.1',
            'detour': 'direct',
            'tag': 'dns-direct',
          },
        ],
      },
      'inbounds': [
        {
          'type': 'socks',
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'listen_port': 10808,
          'users': [
            {'username': socksUser, 'password': socksPass},
          ],
        },
      ],
      'outbounds': [
        outbound,
        {
          'type': 'direct',
          'tag': 'direct',
          'domain_resolver': {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
        },
      ],
      'route': {
        'rules': rules,
        'final': 'proxy',
        'default_domain_resolver': {'server': 'dns-direct', 'strategy': 'prefer_ipv4'},
      },
    };
  }

  static String buildAwgConf(
    VpnProfile profile, {
    List<String>? bypassAllowedIps,
  }) {
    final c = profile.config;
    final buf = StringBuffer();
    final dns = (c['dns'] as String? ?? '1.1.1.1').trim();

    buf.writeln('[Interface]');
    buf.writeln('PrivateKey = ${c['privateKey']}');
    buf.writeln('Address = ${c['address']}');
    buf.writeln('DNS = $dns');
    // MTU строго из ключа (не повышаем): сервер может быть релеем с двойной
    // WG-инкапсуляцией, где завышенный MTU 1400 даёт фрагментацию и падение
    // скорости. AmneziaVPN тоже уважает MTU из конфига.
    final mtu = c['mtu'] ?? 1280;
    buf.writeln('MTU = $mtu');

    // AWG-параметры обфускации
    const awgParamKeys = [
      'Jc', 'Jmin', 'Jmax', 'S1', 'S2', 'S3', 'S4', 'H1', 'H2', 'H3', 'H4',
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

    if (bypassAllowedIps != null && bypassAllowedIps.isNotEmpty) {
      for (final cidr in bypassAllowedIps) {
        buf.writeln('AllowedIPs = $cidr');
      }
    } else {
      // fullVpn: всегда полный тоннель, игнорируем AllowedIPs из профиля
      // (профиль AmneziaVPN может содержать только русские CIDR из split-tunnel экспорта)
      buf.writeln('AllowedIPs = 0.0.0.0/0, ::/0');
    }

    // Keepalive из профиля или дефолт 25 (как в AmneziaVPN)
    final keepalive = c['persistentKeepalive'] ?? c['keepalive'] ?? 25;
    buf.writeln('PersistentKeepalive = $keepalive');
    return buf.toString();
  }

  static String toJson(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  static Map<String, dynamic> _xrayStream(
    Map<String, dynamic> c, {
    bool allowInsecure = false,
    bool tfo = false,
  }) {
    final transport = c['transport'] as String? ?? 'tcp';
    final security = c['security'] as String? ?? 'none';

    final s = <String, dynamic>{};
    if (tfo) {
      s['sockopt'] = {'tcpFastOpen': true};
    }

    s['network'] = switch (transport) {
      'grpc' => 'grpc',
      'ws' => 'ws',
      'xhttp' => 'xhttp',
      'httpupgrade' || 'http' => 'http',
      _ => 'tcp',
    };

    if (security == 'reality') {
      s['security'] = 'reality';
      s['realitySettings'] = {
        'fingerprint': c['fp'] ?? 'chrome',
        'serverName': c['sni'],
        'publicKey': c['pbk'],
        'shortId': c['sid'],
      };
    } else if (security == 'tls') {
      s['security'] = 'tls';
      s['tlsSettings'] = {
        'serverName': c['sni'],
        'fingerprint': c['fp'] ?? 'chrome',
        'allowInsecure': c['insecure'] == true || allowInsecure,
      };
    }

    switch (transport) {
      case 'ws':
        s['wsSettings'] = {
          'path': c['path'] ?? '/',
          'headers': {'Host': c['host'] ?? c['sni']},
        };
      case 'grpc':
        s['grpcSettings'] = {
          'serviceName': c['serviceName'] ?? '',
          'multiMode': false,
        };
      case 'xhttp':
        s['xhttpSettings'] = {
          'path': c['path'] ?? '/',
          'host': c['sni'] ?? c['server'],
        };
      case 'httpupgrade' || 'http':
        s['httpSettings'] = {
          'host': [c['sni'] ?? c['server']],
          'path': c['path'] ?? '/',
        };
    }

    return s;
  }

  static Map<String, dynamic> _xrayRouting({
    required RoutingMode routingMode,
    required List<String> ruCidrs,
    String? serverAddress,
  }) {
    final rules = <Map<String, dynamic>>[
      {'type': 'field', 'ip': _kPrivateCidrs, 'outboundTag': 'direct'},
    ];

    // Явный direct для сервера VPN — защита от петли, если process_name exclusion
    // в TUN sing-box не сработает (трафик xray.exe попадёт обратно в xray)
    if (serverAddress != null && serverAddress.isNotEmpty) {
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(serverAddress);
      rules.add({
        'type': 'field',
        if (isIp) 'ip': [serverAddress] else 'domain': [serverAddress],
        'outboundTag': 'direct',
      });
    }

    if (routingMode == RoutingMode.russiaBypass && ruCidrs.isNotEmpty) {
      rules.add({'type': 'field', 'ip': ruCidrs, 'outboundTag': 'direct'});
    }

    rules.add({'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'proxy'});

    return {'domainStrategy': 'IPIfNonMatch', 'rules': rules};
  }

  // WARP как wireguard-endpoint (sing-box 1.12). detour — через какой outbound
  // дозваниваться до эндпоинта Cloudflare (в каскаде = наш сервер).
  // Только IPv4 (v6 у нас отключён), чтобы не ловить "network unreachable".
  static Map<String, dynamic> _warpEndpoint(
    Map<String, dynamic> w, {
    required String detour,
  }) {
    final ep = (w['endpoint'] as String? ?? '').trim();
    final ci = ep.lastIndexOf(':');
    final host = ci >= 0 ? ep.substring(0, ci) : ep;
    var port = ci >= 0 ? (int.tryParse(ep.substring(ci + 1)) ?? 2408) : 2408;
    // WARP API отдаёт v4-эндпоинт с портом-заглушкой :0 — реальный порт 2408
    if (port <= 0) port = 2408;
    return {
      'type': 'wireguard',
      'tag': 'warp',
      'mtu': 1280,
      'address': [w['address']], // v4/32 из WARP-конфига
      'private_key': w['privateKey'],
      'peers': [
        {
          'address': host,
          'port': port,
          'public_key': w['publicKey'],
          'allowed_ips': ['0.0.0.0/0'],
          'persistent_keepalive_interval': 25,
          // reserved (client_id) — критично: без него Cloudflare не маршрутизирует
          // обратный трафик (download ≈ 0 при живом хендшейке)
          if (w['reserved'] != null) 'reserved': w['reserved'],
        },
      ],
      'detour': detour,
    };
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
        out['transport'] = {
          'type': 'xhttp',
          'path': c['path'] ?? '/',
          'host': c['sni'] ?? c['server'],
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
