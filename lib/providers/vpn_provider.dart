import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../models/route_rule.dart';
import '../data/ru_apps_preset.dart';
import '../services/log_service.dart';
import '../services/profile_repository.dart';
import '../services/route_cleanup_service.dart';
import '../services/speed_service.dart';
import '../services/vpn_service.dart';
import '../services/warp_service.dart';
import '../utils/config_builder.dart';
import '../utils/link_parser.dart';

class VpnProvider extends ChangeNotifier {
  final _repo = ProfileRepository();
  late final VpnService _vpn;
  final _speed = SpeedService();

  VpnStatus _status = VpnStatus.disconnected;
  DateTime? _connectedAt;
  VpnProfile? _activeProfile;
  List<VpnProfile> _profiles = [];
  bool _killSwitch = false;
  RoutingMode _routingMode = RoutingMode.fullVpn;
  List<String> _bypassDomains = [];
  List<String> _excludedApps = [];
  List<String> _bypassApps = []; // split-tunnel Windows: процессы мимо VPN
  List<RouteRule> _customRules = []; // свои правила (напрямую/через vpn/блок)
  bool _ruPreset = false; // готовый пресет: ru-приложения мимо vpn
  bool _mux = false;        // мультиплексирование
  bool _fragment = false;   // tls-фрагментация (обход dpi)
  bool _fragmentRecord = false; // по tls-записям (стойче, но не для всех серверов) vs сегменты
  // параметры фрагментации (дефолты - текущие зашитые значения)
  String _fragPackets = 'tlshello';
  int _fragLenMin = 100, _fragLenMax = 200;
  int _fragIntMin = 10, _fragIntMax = 20;
  String _dns = '';         // кастомный dns (пусто = дефолт 8.8.8.8)
  bool _allowInsecure = false; // принимать недоверенные tls-сертификаты
  bool _tfo = false;           // tcp Fast Open
  bool _warpCascade = false;   // выход через cloudflare warp поверх нашего сервера
  bool _blockAds = false;      // блокировка рекламы (geosite-ads reject)
  String? _error;

  bool _warpActive = false;
  bool _awgMode = false;    // текущее подключение - awg
  bool _cancelRequested = false;  // пользователь прервал подключение
  bool _switching = false;        // идёт смена сервера/протокола (disconnect-connect)
  bool _userWantsConnected = false; // юзер хочет быть на связи (для авто-реконнекта)
  int _subRefreshHours = 12;      // период авто-обновления подписки (0 = выкл)
  Timer? _subTimer;
  bool _subRefreshDeferred = false; // авто-обновление отложено до отключения (см. ниже)
  bool _launchOnStartup = false;  // автозапуск с Windows (+ автоконнект при старте)
  String _awgServerHost = '';

  final _pingResults = <String, int?>{};  // profileId - ms, null = недоступен
  bool _pinging = false;

  final _countryCache = <String, String>{};
  final _countryFetching = <String>{};
  String? _activeCountryCode;
  final _refreshing = <String>{};  // urls currently being refreshed
  final Map<String, SubUserInfo> _subInfo = {}; // трафик/срок по url подписки
  final _routeCleanup = RouteCleanupService(); // очистка чужих маршрутов в обход VPN

  List<String>? _cachedRuCidrs;

  VpnStatus get status => _status;
  VpnProfile? get activeProfile => _activeProfile;
  List<VpnProfile> get profiles => List.from(_profiles);
  bool get killSwitch => _killSwitch;
  RoutingMode get routingMode => _routingMode;
  List<String> get bypassDomains => List.from(_bypassDomains);
  List<String> get excludedApps => List.from(_excludedApps);
  List<String> get bypassApps => List.from(_bypassApps);
  List<RouteRule> get customRules => List.from(_customRules);
  bool get ruPreset => _ruPreset;

  // правила для движка: пресет ru-приложений (если включён) + свои правила.
  // пресет идёт правилами "напрямую + приложение" - на android это exclude_package
  List<RouteRule> _rulesForBuild() => [
        if (_ruPreset)
          for (final pkg in ruAppsPreset)
            RouteRule(
                action: RuleAction.direct,
                match: RuleMatch.process,
                value: pkg),
        ..._customRules,
      ];
  bool get mux => _mux;
  bool get fragment => _fragment;
  bool get fragmentRecord => _fragmentRecord;
  String get fragPackets => _fragPackets;
  int get fragLenMin => _fragLenMin;
  int get fragLenMax => _fragLenMax;
  int get fragIntMin => _fragIntMin;
  int get fragIntMax => _fragIntMax;
  String get dns => _dns;
  bool get allowInsecure => _allowInsecure;
  bool get tfo => _tfo;
  bool get warpCascade => _warpCascade;
  bool get blockAds => _blockAds;
  int get subRefreshHours => _subRefreshHours;
  bool get launchOnStartup => _launchOnStartup;
  String? get error => _error;
  DateTime? get connectedAt => _connectedAt;
  bool get isConnected => _status == VpnStatus.connected;
  bool get warpActive => _warpActive;
  Map<String, int?> get pingResults => Map.unmodifiable(_pingResults);
  bool get pinging => _pinging;
  Stream<SpeedData> get speedStream => _speed.stream;
  bool get isBusy =>
      _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;
  String? get activeCountryCode => _activeCountryCode;
  bool isRefreshing(String url) => _refreshing.contains(url);
  SubUserInfo? subInfoForUrl(String? url) =>
      url == null ? null : _subInfo[url];
  SubUserInfo? get activeSubInfo => subInfoForUrl(_activeProfile?.subscriptionUrl);

  Future<void> init() async {
    try {
      _vpn = VpnService.create();
      // кнопка «Отключить» в шторке ведроида - пользовательский дисконнект, без реконнекта
      _vpn.onUserStop = () {
        _userWantsConnected = false;
      };
      if (Platform.isWindows) await _vpn.cleanup();
      _vpn.statusStream.listen((s) {
        // при смене сервера/протокола не мигаем серым промежуточным статусом -
        // держим "подключение", но скорость останавливаем (новый коннект её поднимет)
        if (_switching &&
            (s == VpnStatus.disconnecting || s == VpnStatus.disconnected)) {
          _connectedAt = null;
          _speed.stop();
          _status = VpnStatus.connecting;
          notifyListeners();
          return;
        }
        // неожиданный обрыв (был connected - стал disconnected, а юзер хочет связь)
        // - авто-переподключение
        final wasConnected = _status == VpnStatus.connected;
        _status = s;
        if (s == VpnStatus.connected) {
          _connectedAt ??= DateTime.now();
          if (_awgMode) {
            _speed.startAwg(
              interfaceName: VpnService.kAwgTunnelName,
              serverHost: _awgServerHost,
            );
          } else {
            _speed.start(serverHost: _activeProfile?.serverHost ?? '');
          }
        } else {
          _connectedAt = null;
          _speed.stop();
          if (s == VpnStatus.disconnected &&
              wasConnected &&
              _userWantsConnected &&
              !_switching) {
            _scheduleReconnect();
            return; // _scheduleReconnect уже выставил статус и уведомил
          }
        }
        if (s != VpnStatus.error) _error = null;
        // отложенное авто-обновление подписки: выполняем только теперь, когда
        // туннель опущен (при коннекте пропускали, чтобы не просаживать скорость).
        // Стоит после early-return авто-реконнекта - при обрыве с реконнектом не
        // сработает, только при реальном отключении.
        if (s == VpnStatus.disconnected && _subRefreshDeferred) {
          _subRefreshDeferred = false;
          _refreshAllSubscriptions();
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('VpnService init failed: $e');
    }

    await _repo.load();
    _profiles = _repo.getAll().toList();

    final prefs = await SharedPreferences.getInstance();
    _killSwitch = prefs.getBool('killSwitch') ?? false;
    _bypassDomains = prefs.getStringList('bypassDomains') ?? [];
    _excludedApps = prefs.getStringList('excludedApps') ?? [];
    _bypassApps = prefs.getStringList('bypassApps') ?? [];
    _customRules = (prefs.getStringList('customRules') ?? [])
        .map((s) {
          try {
            return RouteRule.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<RouteRule>()
        .toList();
    _ruPreset = prefs.getBool('ruPreset') ?? false;
    _mux = prefs.getBool('mux') ?? false;
    _fragment = prefs.getBool('fragment') ?? false;
    _fragmentRecord = prefs.getBool('fragmentRecord') ?? false;
    _fragPackets = prefs.getString('fragPackets') ?? 'tlshello';
    _fragLenMin = prefs.getInt('fragLenMin') ?? 100;
    _fragLenMax = prefs.getInt('fragLenMax') ?? 200;
    _fragIntMin = prefs.getInt('fragIntMin') ?? 10;
    _fragIntMax = prefs.getInt('fragIntMax') ?? 20;
    _dns = prefs.getString('dns') ?? '';
    _allowInsecure = prefs.getBool('allowInsecure') ?? false;
    _tfo = prefs.getBool('tfo') ?? false;
    _warpCascade = prefs.getBool('warpCascade') ?? false;
    _blockAds = prefs.getBool('blockAds') ?? false;
    _subRefreshHours = prefs.getInt('subRefreshHours') ?? 12;
    final subInfoRaw = prefs.getString('subInfo');
    if (subInfoRaw != null) {
      try {
        final m = jsonDecode(subInfoRaw) as Map<String, dynamic>;
        m.forEach((k, v) =>
            _subInfo[k] = SubUserInfo.fromJson(v as Map<String, dynamic>));
      } catch (_) {}
    }
    if (Platform.isWindows) _launchOnStartup = await _readStartupEnabled();
    _routingMode = RoutingMode.values.firstWhere(
      (m) => m.name == (prefs.getString('routingMode') ?? 'fullVpn'),
      orElse: () => RoutingMode.fullVpn,
    );

    final lastId = prefs.getString('lastProfileId');
    if (lastId != null) {
      try {
        _activeProfile = _profiles.firstWhere((p) => p.id == lastId);
        if (_activeProfile != null) _fetchCountry(_activeProfile!.serverHost);
      } catch (_) {}
    }
    notifyListeners();

    // авто-обновление подписки: периодический таймер + догон при запуске,
    // если с прошлого обновления прошло больше интервала
    _setupSubRefresh();
    if (_subRefreshHours > 0) {
      final last = prefs.getInt('lastSubRefresh') ?? 0;
      final dueMs = _subRefreshHours * 3600 * 1000;
      if (DateTime.now().millisecondsSinceEpoch - last >= dueMs) {
        _refreshAllSubscriptions();
      }
    }

    // автоконнект при запуске, если включён автозапуск и есть активный профиль
    if (_launchOnStartup && _activeProfile != null && _status == VpnStatus.disconnected) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_status == VpnStatus.disconnected) connect();
      });
    }
  }

  // ── Автозапуск с Windows (ключ HKCU\...\Run) ──────────────────────────────
  static const _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValue = 'LightningMcQueen';
  // task manager хранит вкл/выкл автозапуска отдельно. если тут первый байт 0x03 -
  // запись в Run игнорируется (Отключено). 0x02 - включено
  static const _approvedKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  static const _approvedEnabled = '020000000000000000000000';

  Future<bool> _readStartupEnabled() async {
    try {
      final r = await Process.run(
        'reg', ['query', _runKey, '/v', _runValue],
        runInShell: false,
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLaunchOnStartup(bool value) async {
    _launchOnStartup = value;
    notifyListeners();
    if (!Platform.isWindows) return;
    try {
      if (value) {
        final exe = Platform.resolvedExecutable;
        await Process.run(
          'reg',
          ['add', _runKey, '/v', _runValue, '/t', 'REG_SZ', '/d', '"$exe"', '/f'],
          runInShell: false,
        );
        // снять возможный "Отключено" из Task Manager (иначе Run-ключ игнорируется)
        await Process.run(
          'reg',
          ['add', _approvedKey, '/v', _runValue, '/t', 'REG_BINARY',
           '/d', _approvedEnabled, '/f'],
          runInShell: false,
        );
      } else {
        await Process.run(
          'reg', ['delete', _runKey, '/v', _runValue, '/f'],
          runInShell: false,
        );
        await Process.run(
          'reg', ['delete', _approvedKey, '/v', _runValue, '/f'],
          runInShell: false,
        );
      }
    } catch (_) {}
  }

  // ── Авто-реконнект и авто-обновление подписки ─────────────────────────────

  void _scheduleReconnect() {
    _status = VpnStatus.connecting; // показываем "переподключение"
    notifyListeners();
    LogService().add('[reconnect] туннель упал — авто-переподключение через 3 с');
    Future.delayed(const Duration(seconds: 3), () {
      if (_userWantsConnected &&
          _status != VpnStatus.connected &&
          _activeProfile != null) {
        connect();
      }
    });
  }

  void _setupSubRefresh() {
    _subTimer?.cancel();
    _subTimer = null;
    if (_subRefreshHours > 0) {
      _subTimer = Timer.periodic(
        Duration(hours: _subRefreshHours),
        (_) => _refreshAllSubscriptions(),
      );
    }
  }

  Future<void> _refreshAllSubscriptions() async {
    // Не дёргаем подписку при активном коннекте: запрос к url идёт через туннель
    // и просаживает скорость. Откладываем до отключения (флаг отработает в
    // обработчике статуса). Ручное обновление (↻) при этом по-прежнему работает.
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      _subRefreshDeferred = true;
      return;
    }
    final urls = _profiles
        .map((p) => p.subscriptionUrl)
        .whereType<String>()
        .toSet();
    if (urls.isEmpty) return;
    for (final url in urls) {
      try {
        await refreshSubscription(url);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSubRefresh', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> setSubRefreshHours(int hours) async {
    _subRefreshHours = hours;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subRefreshHours', hours);
    _setupSubRefresh();
    notifyListeners();
  }

  Future<void> connect() async {
    if (_activeProfile == null) return;
    _userWantsConnected = true; // для авто-реконнекта при обрыве
    _error = null;
    _warpActive = false;
    _awgMode = false;
    _cancelRequested = false;
    _fetchCountry(_activeProfile!.serverHost);
    _status = VpnStatus.connecting;
    notifyListeners();
    try {
      final profile = _activeProfile!;

      // в режиме весь трафик через впн чистим чужие маршруты мимо туннеля
      // (сторонний split-tunnel пишет тысячи ру-подсетей на шлюз и трафик утекает)
      if (_routingMode == RoutingMode.fullVpn && Platform.isWindows) {
        await _routeCleanup.cleanBypassRoutes();
      }

      // warp-каскад (opt-in): выход через cloudflare поверх нашего сервера.
      // Для awg не поддерживается (системный WG). Когда выключен - обычный коннект.
      Map<String, dynamic>? warpJson;
      bool twoPhase = false;
      // warp-каскад на Windows и Android (движок sing-box умеет warp-endpoint).
      // awg исключаем - каскад поверх системного/awg-туннеля не делаем.
      final wantWarp = _warpCascade && profile.protocol != VpnProtocol.amnezia;
      if (wantWarp) {
        var warp = await WarpService.loadSaved();
        // нет конфига ИЛИ старый без reserved (client_id) - нужна регистрация
        if (warp == null || warp.reserved == null) {
          // cloudflare api в РФ заблокирован - регистрируемся ЧЕРЕЗ туннель:
          // фаза 1 - поднять сервер без warp, затем register по живому туннелю.
          twoPhase = true;
          _switching = true; // держим UI в "подключении" на обе фазы
          try {
            await _connectInternal(profile, warpJson: null);
            await Future.delayed(const Duration(milliseconds: 900));
            warp = await WarpService.register();
          } catch (e) {
            _switching = false;
            await disconnect(); // снести фазу 1, чтобы не висел туннель с ошибкой
            rethrow;
          }
        }
        warpJson = warp.toJson();
      }

      // фаза 2 (или обычный единственный коннект)
      await _connectInternal(profile, warpJson: warpJson);
      if (twoPhase) _switching = false;
      _warpActive = warpJson != null;
      notifyListeners();
      // android: при первом удачном коннекте просим исключить из оптимизации
      // батареи - иначе Doze со временем душит VpnService и скорость проседает
      if (Platform.isAndroid) _maybePromptBatteryExemption();
    } catch (e) {
      _switching = false;
      // отмена пользователем в процессе подключения - не показываем ошибку
      if (_cancelRequested) {
        _cancelRequested = false;
        return;
      }
      _status = VpnStatus.error;
      _error = e.toString().replaceFirst('UnimplementedError: ', '');
      notifyListeners();
    }
  }

  // Собственно подключение по протоколу. warpJson != null - warp-каскад.
  Future<void> _connectInternal(
    VpnProfile profile, {
    Map<String, dynamic>? warpJson,
  }) async {
    // ЕДИНЫЙ ДВИЖОК (windows): все прото одним процессом sing-box-форка по тому же
    // build()-конфигу, что на Android (включая awg как endpoint). откат на 3 движка - в v1.0.16.
    if (Platform.isWindows) {
      // _awgMode выкл - скорость/пинг через clash_api, как у остальных прото
      _awgMode = false;
      final ruCidrs = _routingMode == RoutingMode.russiaBypass
          ? await _loadRuCidrs()
          : <String>[];
      final config = ConfigBuilder.build(
        profile,
        routingMode: _routingMode,
        killSwitch: _killSwitch,
        bypassDomains: _bypassDomains,
        ruCidrs: ruCidrs,
        mux: _mux,
        dns: _dns,
        allowInsecure: _allowInsecure,
        tfo: _tfo,
        fragment: _fragment,
        fragmentRecord: _fragmentRecord,
        warp: warpJson,
        bypassApps: _bypassApps,
        adsRuleSet: _adsRuleSet,
        // ротируем имя tun-адаптера: иначе wintun-призрак от прошлой сессии даёт
        // ~15с делей (первая попытка sing-box падает с "already exists" и ретраит)
        tunName: 'tun${DateTime.now().millisecondsSinceEpoch % 100000}',
        customRules: _rulesForBuild(),
      );
      await _vpn.connectUnified(ConfigBuilder.toJson(config));
    } else {
      // Mobile (and any other platform): single sing-box with full config
      // в режиме «Россия напрямую» грузим российские подсети (иначе правило
      // ip_cidr-direct не добавится и режим не работает)
      final ruCidrs = _routingMode == RoutingMode.russiaBypass
          ? await _loadRuCidrs()
          : <String>[];
      final config = ConfigBuilder.build(
        profile,
        routingMode: _routingMode,
        killSwitch: _killSwitch,
        bypassDomains: _bypassDomains,
        ruCidrs: ruCidrs,
        mux: _mux,
        dns: _dns,
        allowInsecure: _allowInsecure,
        tfo: _tfo,
        fragment: _fragment, // tls-фрагментация (тумблер в настройках)
        fragmentRecord: _fragmentRecord,
        warp: warpJson,
        bypassApps: _bypassApps,
        excludeApps: _excludedApps, // android split-tunnel - tun exclude_package
        adsRuleSet: await _ensureAdsRuleSet(),
        customRules: _rulesForBuild(),
      );
      await _vpn.connect(
        ConfigBuilder.toJson(config),
        excludedApps: _excludedApps,
        protocol: profile.protocolLabel,
        country: _activeCountryCode ?? '',
      );
    }
  }

  // Прерывание подключения в процессе (пользователь нажал отмену)
  Future<void> cancelConnect() async {
    _cancelRequested = true;
    _userWantsConnected = false; // отмена пользователем - не реконнектим
    _warpActive = false;
    _awgMode = false;
    _status = VpnStatus.disconnecting;
    notifyListeners();
    try {
      await _vpn.cleanup();
    } catch (_) {}
    _status = VpnStatus.disconnected;
    _error = null;
    notifyListeners();
  }


  Future<void> resetWarp() async {
    await WarpService.clear();
    notifyListeners();
  }

  Future<void> pingAll() async {
    if (_pinging) return;
    _pinging = true;
    _pingResults.clear();
    notifyListeners();

    for (var i = 0; i < _profiles.length; i += 5) {
      final batch = _profiles.skip(i).take(5).toList();
      await Future.wait(batch.map((p) async {
        final host = p.serverHost;
        if (host.isEmpty) {
          _pingResults[p.id] = null;
          notifyListeners();
          return;
        }
        // udp/quic-протоколы: их порты не принимают tcp - пингуем icmp + фоллбэк tcp 443
        final isUdp = p.protocol == VpnProtocol.amnezia ||
            p.protocol == VpnProtocol.wireguard ||
            p.protocol == VpnProtocol.tuic ||
            p.protocol == VpnProtocol.hysteria2;
        if (isUdp) {
          var ms = await SpeedService.icmpPing(host);
          if (ms == null) {
            // icmp часто блокируется на VPN-серверах - пробуем tcp 443
            try {
              final sw = Stopwatch()..start();
              final sock = await Socket.connect(host, 443,
                  timeout: const Duration(seconds: 2));
              sw.stop();
              await sock.close();
              ms = sw.elapsedMilliseconds;
            } catch (_) {}
          }
          _pingResults[p.id] = ms;
        } else {
          try {
            final sw = Stopwatch()..start();
            final sock = await Socket.connect(
              host, p.serverPort,
              timeout: const Duration(seconds: 5),
            );
            sw.stop();
            await sock.close();
            _pingResults[p.id] = sw.elapsedMilliseconds;
          } catch (_) {
            _pingResults[p.id] = null;
          }
        }
        notifyListeners();
      }));
    }

    _pinging = false;
    notifyListeners();
  }

  // пингует все ключи и коннектится к самому быстрому. вернёт профиль или null
  Future<VpnProfile?> connectFastest() async {
    if (_profiles.isEmpty) return null;
    await pingAll();
    VpnProfile? best;
    int bestMs = 1 << 30;
    for (final p in _profiles) {
      final ms = _pingResults[p.id];
      if (ms != null && ms < bestMs) {
        bestMs = ms;
        best = p;
      }
    }
    if (best == null) return null;
    LogService().add('[fastest] выбран ${best.name} (${bestMs} мс)');
    await selectProfile(best); // selectProfile сам переподключит, если был коннект
    if (_status != VpnStatus.connected && _status != VpnStatus.connecting) {
      await connect();
    }
    return best;
  }

  // ручная чистка чужих маршрутов из настроек, вернёт сколько удалили
  Future<int> cleanBypassRoutes() => _routeCleanup.cleanBypassRoutes();

  Future<void> disconnect() async {
    if (!_switching) _userWantsConnected = false; // ручной дисконнект - не реконнектим
    _warpActive = false;
    _awgMode = false;
    // при переключении статус держим "подключение" (см. _switching), не серый
    if (!_switching) {
      _status = VpnStatus.disconnecting;
      notifyListeners();
    }
    await _vpn.disconnect();
  }

  /// Добавляет профиль. Возвращает false, если такой ключ уже есть (дубликат).
  Future<bool> addProfile(VpnProfile profile) async {
    final exists = _profiles.any((e) => e.signature == profile.signature);
    if (exists) return false;
    await _repo.add(profile);
    _profiles = _repo.getAll().toList();
    notifyListeners();
    return true;
  }

  /// Добавляет пакет профилей, пропуская дубликаты. Возвращает число добавленных.
  Future<int> addProfiles(List<VpnProfile> list) async {
    final existing = _profiles.map((e) => e.signature).toSet();
    var added = 0;
    for (final p in list) {
      if (existing.contains(p.signature)) continue;
      existing.add(p.signature);
      await _repo.add(p);
      added++;
    }
    if (added > 0) {
      _profiles = _repo.getAll().toList();
      notifyListeners();
    }
    return added;
  }

  Future<void> removeProfile(String id) async {
    if (_activeProfile?.id == id) await disconnect();
    await _repo.remove(id);
    _profiles = _repo.getAll().toList();
    if (_activeProfile?.id == id) _activeProfile = null;
    notifyListeners();
  }

  Future<void> removeSubscription(String url) async {
    final ids = _profiles
        .where((p) => p.subscriptionUrl == url)
        .map((p) => p.id)
        .toList();
    if (ids.isEmpty) return;
    if (_activeProfile != null && ids.contains(_activeProfile!.id)) {
      await disconnect();
      _activeProfile = null;
    }
    for (final id in ids) {
      await _repo.remove(id);
    }
    _profiles = _repo.getAll().toList();
    notifyListeners();
  }

  Future<void> selectProfile(VpnProfile profile) async {
    // авто-переподключение при смене активного профиля
    final wasActive = isConnected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.error && _activeProfile != null;
    _activeProfile = profile;
    _activeCountryCode = _countryCache[profile.serverHost];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastProfileId', profile.id);
    notifyListeners();
    _fetchCountry(profile.serverHost);
    if (wasActive) {
      // на время переключения держим UI в "подключении" (без серой кнопки)
      _switching = true;
      _status = VpnStatus.connecting;
      notifyListeners();
      try {
        // сначала чистое отключение старого (без гонки статусов), затем коннект к новому
        await disconnect();
        // пауза на устаканивание маршрутизации/интерфейса перед новым коннектом
        // (иначе quic-протоколы - tuic/hysteria - могут не поднять трафик с первого раза)
        await Future.delayed(const Duration(milliseconds: 1200));
        await connect();
      } finally {
        _switching = false;
      }
    }
  }

  Future<void> _saveSubInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final m = _subInfo.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString('subInfo', jsonEncode(m));
  }

  // сохранить данные подписки сразу при импорте, не ждём автообновления
  Future<void> setSubInfo(String url, SubUserInfo info) async {
    _subInfo[url] = info;
    await _saveSubInfo();
    notifyListeners();
  }

  Future<void> refreshSubscription(String url) async {
    if (_refreshing.contains(url)) return;
    _refreshing.add(url);
    notifyListeners();
    try {
      final result = await LinkParser.parseSubscriptionUrl(url);
      if (result.subInfo != null) {
        _subInfo[url] = result.subInfo!;
        await _saveSubInfo();
      }
      if (result.batch != null && result.batch!.isNotEmpty) {
        final oldActive = _activeProfile; // запоминаем активный до пересборки
        final toRemove = _profiles.where((p) => p.subscriptionUrl == url).map((p) => p.id).toList();
        final activeRemoved = toRemove.contains(oldActive?.id);
        for (final id in toRemove) {
          await _repo.remove(id);
        }
        for (final p in result.batch!) {
          await _repo.add(p);
        }
        _profiles = _repo.getAll().toList();
        // У свежих профилей новые случайные id, поэтому активный надо переназначить
        // на эквивалентный (по имени+серверу+порту) - иначе при живом туннеле на
        // главной пропадает выбранный профиль («Профиль не выбран»). Туннель не трогаем.
        if (activeRemoved && oldActive != null) {
          VpnProfile? match;
          for (final p in _profiles) {
            if (p.subscriptionUrl == url &&
                p.name == oldActive.name &&
                p.config['server'] == oldActive.config['server'] &&
                p.config['port'] == oldActive.config['port']) {
              match = p;
              break;
            }
          }
          _activeProfile = match; // null только если сервер реально исчез из подписки
          if (match != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('lastProfileId', match.id);
          }
        }
      }
    } finally {
      _refreshing.remove(url);
      notifyListeners();
    }
  }

  // Код страны для произвольного хоста (для флагов в списке ключей).
  // Возвращает кеш сразу либо null + запускает фоновую загрузку (с дедупликацией).
  String? countryCodeFor(String host) {
    if (host.isEmpty) return null;
    final cached = _countryCache[host];
    if (cached != null) return cached;
    _fetchCountry(host);
    return null;
  }

  void _fetchCountry(String host) {
    if (host.isEmpty) return;
    if (_countryCache.containsKey(host)) {
      if (_activeProfile?.serverHost == host &&
          _activeCountryCode != _countryCache[host]) {
        _activeCountryCode = _countryCache[host];
        notifyListeners();
      }
      return;
    }
    if (_countryFetching.contains(host)) return;
    _countryFetching.add(host);
    _doFetchCountry(host);
  }

  Future<void> _doFetchCountry(String host) async {
    try {
      String ip = host;
      if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host)) {
        final addrs = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        if (addrs.isEmpty) return;
        ip = addrs.first.address;
      }
      final resp = await http
          .get(Uri.parse('https://ipinfo.io/$ip/country'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final code = resp.body.trim().toUpperCase();
        if (code.length == 2) {
          _countryCache[host] = code;
          if (_activeProfile?.serverHost == host) {
            _activeCountryCode = code;
          }
          notifyListeners();
        }
      }
    } catch (_) {
    } finally {
      _countryFetching.remove(host);
    }
  }

  Future<void> setKillSwitch(bool value) async {
    _killSwitch = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('killSwitch', value);
    notifyListeners();
  }

  Future<void> setRoutingMode(RoutingMode mode) async {
    _routingMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('routingMode', mode.name);
    notifyListeners();
  }

  Future<void> setBypassDomains(List<String> domains) async {
    _bypassDomains = domains;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bypassDomains', domains);
    notifyListeners();
  }

  Future<void> setBypassApps(List<String> apps) async {
    _bypassApps = apps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bypassApps', apps);
    notifyListeners();
  }

  Future<void> setExcludedApps(List<String> apps) async {
    _excludedApps = apps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('excludedApps', apps);
    notifyListeners();
  }

  Future<void> setMux(bool value) async {
    _mux = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mux', value);
    notifyListeners();
  }

  Future<void> setFragment(bool value) async {
    _fragment = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fragment', value);
    notifyListeners();
  }

  Future<void> setFragmentRecord(bool value) async {
    _fragmentRecord = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fragmentRecord', value);
    notifyListeners();
  }

  Future<void> addCustomRule(RouteRule rule) async {
    _customRules.add(rule);
    await _saveCustomRules();
    notifyListeners();
  }

  Future<void> removeCustomRuleAt(int index) async {
    if (index < 0 || index >= _customRules.length) return;
    _customRules.removeAt(index);
    await _saveCustomRules();
    notifyListeners();
  }

  Future<void> _saveCustomRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'customRules', _customRules.map((r) => jsonEncode(r.toJson())).toList());
  }

  Future<void> setRuPreset(bool value) async {
    _ruPreset = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ruPreset', value);
    notifyListeners();
  }

  // импорт правил из json-файла (список {action,match,value}) - свой пресет
  Future<int> importRulesJson(String jsonStr) async {
    final list = jsonDecode(jsonStr) as List;
    var added = 0;
    for (final e in list) {
      try {
        _customRules.add(RouteRule.fromJson(e as Map<String, dynamic>));
        added++;
      } catch (_) {}
    }
    if (added > 0) {
      await _saveCustomRules();
      notifyListeners();
    }
    return added;
  }

  Future<void> setDns(String value) async {
    _dns = value.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dns', _dns);
    notifyListeners();
  }

  Future<void> setAllowInsecure(bool value) async {
    _allowInsecure = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allowInsecure', value);
    notifyListeners();
  }

  Future<void> setTfo(bool value) async {
    _tfo = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tfo', value);
    notifyListeners();
  }

  Future<void> setWarpCascade(bool value) async {
    _warpCascade = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('warpCascade', value);
    notifyListeners();
  }

  Future<void> setBlockAds(bool value) async {
    _blockAds = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('blockAds', value);
    notifyListeners();
  }

  // путь к бандлу geosite-ads .srs (для блокировки рекламы), null если выкл/не Windows
  String? get _adsRuleSet {
    if (!_blockAds || !Platform.isWindows) return null;
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\data\\geosite-ads.srs';
  }

  // На ведроиде ассет лежит внутри apk - sing-box нужен реальный путь, поэтому
  // распаковываем geosite-ads.srs в файлы приложения один раз и отдаём путь.
  String? _cachedAdsPathMobile;
  Future<String?> _ensureAdsRuleSet() async {
    if (Platform.isWindows) return _adsRuleSet;
    if (!_blockAds) return null;
    if (_cachedAdsPathMobile != null) return _cachedAdsPathMobile;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/geosite-ads.srs');
      final data = await rootBundle.load('assets/data/geosite-ads.srs');
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      _cachedAdsPathMobile = f.path;
      return f.path;
    } catch (e) {
      debugPrint('geosite-ads extract error: $e');
      return null;
    }
  }

  Future<void> setFragParams({
    String? packets,
    int? lenMin,
    int? lenMax,
    int? intMin,
    int? intMax,
  }) async {
    if (packets != null) _fragPackets = packets;
    if (lenMin != null) _fragLenMin = lenMin;
    if (lenMax != null) _fragLenMax = lenMax;
    if (intMin != null) _fragIntMin = intMin;
    if (intMax != null) _fragIntMax = intMax;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fragPackets', _fragPackets);
    await prefs.setInt('fragLenMin', _fragLenMin);
    await prefs.setInt('fragLenMax', _fragLenMax);
    await prefs.setInt('fragIntMin', _fragIntMin);
    await prefs.setInt('fragIntMax', _fragIntMax);
    notifyListeners();
  }

  Future<List<String>> _loadRuCidrs() async {
    if (_cachedRuCidrs != null) return _cachedRuCidrs!;
    try {
      final data = await rootBundle.loadString('assets/data/iplist_ru.txt');
      _cachedRuCidrs = data
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      return _cachedRuCidrs!;
    } catch (e) {
      debugPrint('iplist_ru load error: $e');
      return [];
    }
  }

  // Запущенные процессы Windows для split-tunnel: [{package: exe, name: ярлык}]
  // (ключ 'package' - чтобы переиспользовать существующий пикер приложений)
  Future<List<Map<String, String>>> getRunningProcesses() async {
    if (!Platform.isWindows) return [];
    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          // OutputEncoding=UTF8 + читаем сырые байты - корректная кириллица в именах
          r'[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Process | Where-Object {$_.Path} | Select-Object ProcessName,Description | ConvertTo-Json -Compress',
        ],
        runInShell: false,
        stdoutEncoding: null, // сырые байты, декодируем сами как UTF-8
      );
      if (r.exitCode != 0) return [];
      final out =
          utf8.decode(r.stdout as List<int>, allowMalformed: true).trim();
      if (out.isEmpty) return [];
      final decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      final seen = <String>{};
      final result = <Map<String, String>>[];
      for (final e in list) {
        final pn = (e['ProcessName'] as String?)?.trim() ?? '';
        if (pn.isEmpty) continue;
        final exe = '$pn.exe';
        if (!seen.add(exe.toLowerCase())) continue;
        final desc = (e['Description'] as String?)?.trim();
        result.add({
          'package': exe,
          'name': (desc != null && desc.isNotEmpty) ? desc : pn,
        });
      }
      result.sort((a, b) =>
          a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));
      return result;
    } catch (e) {
      debugPrint('getRunningProcesses error: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getInstalledApps() async {
    if (!Platform.isAndroid) return [];
    try {
      const ch = MethodChannel('lightningmcqueen.proxy/vpn');
      final raw =
          await ch.invokeListMethod<Map<Object?, Object?>>('getInstalledApps');
      return (raw ?? [])
          .map((m) => {
                'package': (m['package'] as String?) ?? '',
                'name': (m['name'] as String?) ?? '',
              })
          .where((m) => m['package']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('getInstalledApps error: $e');
      return [];
    }
  }

  // ── Исключение из оптимизации батареи (android) ───────────────────────────
  // без него Doze со временем деприоритизирует VpnService - скорость падает,
  // лечится переподключением. см. project_android_doze_speed

  static const _vpnCh = MethodChannel('lightningmcqueen.proxy/vpn');

  // true - приложение исключено из оптимизации (Doze его не трогает).
  // на не-android всегда true (там этой проблемы нет)
  Future<bool> isBatteryUnrestricted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _vpnCh.invokeMethod<bool>('isBatteryUnrestricted') ?? true;
    } catch (_) {
      return true;
    }
  }

  // открыть системный диалог запроса исключения (из настроек, вручную)
  Future<void> requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    try {
      await _vpnCh.invokeMethod('requestBatteryExemption');
    } catch (e) {
      debugPrint('requestBatteryExemption error: $e');
    }
  }

  // один раз при первом коннекте: если ещё не исключены - показываем диалог.
  // флаг persist, чтобы не дёргать при каждом коннекте (отказался - не навязываем,
  // повторно можно из настроек)
  Future<void> _maybePromptBatteryExemption() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('batteryPrompted') == true) return;
    if (await isBatteryUnrestricted()) return; // уже исключены
    await prefs.setBool('batteryPrompted', true);
    await requestBatteryExemption();
  }

  @override
  void dispose() {
    _subTimer?.cancel();
    _speed.dispose();
    _vpn.dispose();
    super.dispose();
  }
}
