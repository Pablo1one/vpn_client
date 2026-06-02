import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../services/log_service.dart';
import '../services/profile_repository.dart';
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
  bool _mux = false;        // мультиплексирование
  bool _fragment = false;   // TLS-фрагментация (обход DPI)
  // параметры фрагментации (дефолты — текущие зашитые значения)
  String _fragPackets = 'tlshello';
  int _fragLenMin = 100, _fragLenMax = 200;
  int _fragIntMin = 10, _fragIntMax = 20;
  String _dns = '';         // кастомный DNS (пусто = дефолт 8.8.8.8)
  bool _allowInsecure = false; // принимать недоверенные TLS-сертификаты
  bool _tfo = false;           // TCP Fast Open
  bool _warpCascade = false;   // выход через Cloudflare WARP поверх нашего сервера
  String? _error;

  bool _warpActive = false;
  bool _awgMode = false;    // текущее подключение — AWG
  bool _cancelRequested = false;  // пользователь прервал подключение
  bool _switching = false;        // идёт смена сервера/протокола (disconnect→connect)
  bool _userWantsConnected = false; // юзер хочет быть на связи (для авто-реконнекта)
  int _subRefreshHours = 12;      // период авто-обновления подписки (0 = выкл)
  Timer? _subTimer;
  bool _launchOnStartup = false;  // автозапуск с Windows (+ автоконнект при старте)
  String _awgServerHost = '';

  final _pingResults = <String, int?>{};  // profileId → ms, null = недоступен
  bool _pinging = false;

  final _countryCache = <String, String>{};
  final _countryFetching = <String>{};
  String? _activeCountryCode;
  final _refreshing = <String>{};  // urls currently being refreshed

  List<String>? _cachedRuCidrs;
  List<String>? _cachedBypassAllowedIps;

  VpnStatus get status => _status;
  VpnProfile? get activeProfile => _activeProfile;
  List<VpnProfile> get profiles => List.from(_profiles);
  bool get killSwitch => _killSwitch;
  RoutingMode get routingMode => _routingMode;
  List<String> get bypassDomains => List.from(_bypassDomains);
  List<String> get excludedApps => List.from(_excludedApps);
  bool get mux => _mux;
  bool get fragment => _fragment;
  String get fragPackets => _fragPackets;
  int get fragLenMin => _fragLenMin;
  int get fragLenMax => _fragLenMax;
  int get fragIntMin => _fragIntMin;
  int get fragIntMax => _fragIntMax;
  String get dns => _dns;
  bool get allowInsecure => _allowInsecure;
  bool get tfo => _tfo;
  bool get warpCascade => _warpCascade;
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

  Future<void> init() async {
    try {
      _vpn = VpnService.create();
      if (Platform.isWindows) await _vpn.cleanup();
      _vpn.statusStream.listen((s) {
        // при смене сервера/протокола не мигаем серым промежуточным статусом —
        // держим "подключение", но скорость останавливаем (новый коннект её поднимет)
        if (_switching &&
            (s == VpnStatus.disconnecting || s == VpnStatus.disconnected)) {
          _connectedAt = null;
          _speed.stop();
          _status = VpnStatus.connecting;
          notifyListeners();
          return;
        }
        // неожиданный обрыв (был connected → стал disconnected, а юзер хочет связь)
        // → авто-переподключение
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
            _speed.start();
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
    _mux = prefs.getBool('mux') ?? false;
    _fragment = prefs.getBool('fragment') ?? false;
    _fragPackets = prefs.getString('fragPackets') ?? 'tlshello';
    _fragLenMin = prefs.getInt('fragLenMin') ?? 100;
    _fragLenMax = prefs.getInt('fragLenMax') ?? 200;
    _fragIntMin = prefs.getInt('fragIntMin') ?? 10;
    _fragIntMax = prefs.getInt('fragIntMax') ?? 20;
    _dns = prefs.getString('dns') ?? '';
    _allowInsecure = prefs.getBool('allowInsecure') ?? false;
    _tfo = prefs.getBool('tfo') ?? false;
    _warpCascade = prefs.getBool('warpCascade') ?? false;
    _subRefreshHours = prefs.getInt('subRefreshHours') ?? 12;
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
      } else {
        await Process.run(
          'reg', ['delete', _runKey, '/v', _runValue, '/f'],
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

      // WARP-каскад (opt-in): выход через Cloudflare поверх нашего сервера.
      // Для AWG не поддерживается (системный WG). Когда выключен — обычный коннект.
      Map<String, dynamic>? warpJson;
      bool twoPhase = false;
      final wantWarp = _warpCascade &&
          Platform.isWindows &&
          profile.protocol != VpnProtocol.amnezia;
      if (wantWarp) {
        var warp = await WarpService.loadSaved();
        // нет конфига ИЛИ старый без reserved (client_id) — нужна регистрация
        if (warp == null || warp.reserved == null) {
          // Cloudflare API в РФ заблокирован → регистрируемся ЧЕРЕЗ туннель:
          // фаза 1 — поднять сервер без WARP, затем register по живому туннелю.
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
    } catch (e) {
      _switching = false;
      // отмена пользователем в процессе подключения — не показываем ошибку
      if (_cancelRequested) {
        _cancelRequested = false;
        return;
      }
      _status = VpnStatus.error;
      _error = e.toString().replaceFirst('UnimplementedError: ', '');
      notifyListeners();
    }
  }

  // Собственно подключение по протоколу. warpJson != null → WARP-каскад.
  Future<void> _connectInternal(
    VpnProfile profile, {
    Map<String, dynamic>? warpJson,
  }) async {
    if (profile.protocol == VpnProtocol.amnezia && Platform.isWindows) {
      _awgMode = true;
      _awgServerHost = profile.serverHost;
      List<String>? bypassIps;
      if (_routingMode == RoutingMode.russiaBypass) {
        bypassIps = await _loadBypassAllowedIps();
      }
      final conf = ConfigBuilder.buildAwgConf(profile, bypassAllowedIps: bypassIps);
      await _vpn.connectAwg(conf);
    } else if (Platform.isWindows && profile.protocol == VpnProtocol.vless) {
      final transport = (profile.config['transport'] as String? ?? 'tcp').trim();
      final ruCidrs = _routingMode == RoutingMode.russiaBypass
          ? await _loadRuCidrs()
          : <String>[];
      if (transport == 'grpc') {
        // gRPC через sing-box TUN: xray 26.x deprecated gRPC — REFUSED_STREAM
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
          warp: warpJson,
        );
        await _vpn.connect(ConfigBuilder.toJson(config));
      } else {
        // tcp, ws, xhttp, httpupgrade через xray
        final xrayJson = ConfigBuilder.buildXrayVless(
          profile,
          routingMode: _routingMode,
          ruCidrs: ruCidrs,
          mux: _mux,
          fragment: _fragment,
          fragPackets: _fragPackets,
          fragLength: '$_fragLenMin-$_fragLenMax',
          fragInterval: '$_fragIntMin-$_fragIntMax',
          allowInsecure: _allowInsecure,
          tfo: _tfo,
        );
        final tunConfig = ConfigBuilder.buildTun(
          killSwitch: _killSwitch,
          routingMode: _routingMode,
          dns: _dns,
          ruCidrs: ruCidrs,
          warp: warpJson,
        );
        await _vpn.connectProxy(
          xrayConfigJson: xrayJson,
          tunConfigJson: ConfigBuilder.toJson(tunConfig),
        );
      }
    } else if (Platform.isWindows &&
        (profile.protocol == VpnProtocol.tuic ||
            profile.protocol == VpnProtocol.hysteria2)) {
      // TUIC / H2 — sing-box proxy on :10808 + TUN sing-box forwarder
      final ruCidrs = _routingMode == RoutingMode.russiaBypass
          ? await _loadRuCidrs()
          : <String>[];
      final proxyConfig = ConfigBuilder.buildSingboxProxy(
        profile,
        routingMode: _routingMode,
        ruCidrs: ruCidrs,
        mux: _mux,
        dns: _dns,
        allowInsecure: _allowInsecure,
        tfo: _tfo,
      );
      final tunConfig = ConfigBuilder.buildTun(
        killSwitch: _killSwitch,
        routingMode: _routingMode,
        dns: _dns,
        ruCidrs: ruCidrs,
        warp: warpJson,
      );
      await _vpn.connectProxy(
        singboxConfigJson: ConfigBuilder.toJson(proxyConfig),
        tunConfigJson: ConfigBuilder.toJson(tunConfig),
      );
    } else {
      // Mobile (and any other platform): single sing-box with full config
      final config = ConfigBuilder.build(
        profile,
        routingMode: _routingMode,
        killSwitch: _killSwitch,
        bypassDomains: _bypassDomains,
        mux: _mux,
        dns: _dns,
        allowInsecure: _allowInsecure,
        tfo: _tfo,
        warp: warpJson,
      );
      await _vpn.connect(
        ConfigBuilder.toJson(config),
        excludedApps: _excludedApps,
      );
    }
  }

  // Прерывание подключения в процессе (пользователь нажал отмену)
  Future<void> cancelConnect() async {
    _cancelRequested = true;
    _userWantsConnected = false; // отмена пользователем — не реконнектим
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

  Future<void> connectWarp() async {
    _error = null;
    _warpActive = true;  // устанавливаем до подключения — CDN показывает спиннер
    _status = VpnStatus.connecting;
    notifyListeners();
    try {
      var config = await WarpService.loadSaved();
      config ??= await WarpService.register();
      await _vpn.connectAwg(config.toWgConf());
    } catch (e) {
      _warpActive = false;
      _status = VpnStatus.error;
      _error = e.toString();
      notifyListeners();
    }
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
        // UDP/QUIC-протоколы: их порты не принимают TCP — пингуем ICMP + фоллбэк TCP 443
        final isUdp = p.protocol == VpnProtocol.amnezia ||
            p.protocol == VpnProtocol.wireguard ||
            p.protocol == VpnProtocol.tuic ||
            p.protocol == VpnProtocol.hysteria2;
        if (isUdp) {
          var ms = await SpeedService.icmpPing(host);
          if (ms == null) {
            // ICMP часто блокируется на VPN-серверах — пробуем TCP 443
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

  Future<void> disconnect() async {
    if (!_switching) _userWantsConnected = false; // ручной дисконнект — не реконнектим
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
        // (иначе QUIC-протоколы — tuic/hysteria — могут не поднять трафик с первого раза)
        await Future.delayed(const Duration(milliseconds: 1200));
        await connect();
      } finally {
        _switching = false;
      }
    }
  }

  Future<void> refreshSubscription(String url) async {
    if (_refreshing.contains(url)) return;
    _refreshing.add(url);
    notifyListeners();
    try {
      final result = await LinkParser.parseSubscriptionUrl(url);
      if (result.batch != null && result.batch!.isNotEmpty) {
        final toRemove = _profiles.where((p) => p.subscriptionUrl == url).map((p) => p.id).toList();
        final activeRemoved = toRemove.contains(_activeProfile?.id);
        for (final id in toRemove) {
          await _repo.remove(id);
        }
        if (activeRemoved) _activeProfile = null;
        for (final p in result.batch!) {
          await _repo.add(p);
        }
        _profiles = _repo.getAll().toList();
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

  Future<List<String>> _loadBypassAllowedIps() async {
    if (_cachedBypassAllowedIps != null) return _cachedBypassAllowedIps!;
    try {
      final data =
          await rootBundle.loadString('assets/data/allowed_ips_bypass.txt');
      _cachedBypassAllowedIps = data
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      return _cachedBypassAllowedIps!;
    } catch (e) {
      debugPrint('allowed_ips_bypass load error: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getInstalledApps() async {
    if (!Platform.isAndroid) return [];
    try {
      const ch = MethodChannel('com.example.vpn_client/vpn');
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

  @override
  void dispose() {
    _subTimer?.cancel();
    _speed.dispose();
    _vpn.dispose();
    super.dispose();
  }
}
