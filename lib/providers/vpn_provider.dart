import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
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
  String? _error;

  bool _warpActive = false;

  final _countryCache = <String, String>{};
  String? _activeCountryCode;
  final _refreshing = <String>{};  // urls currently being refreshed

  VpnStatus get status => _status;
  VpnProfile? get activeProfile => _activeProfile;
  List<VpnProfile> get profiles => List.from(_profiles);
  bool get killSwitch => _killSwitch;
  RoutingMode get routingMode => _routingMode;
  List<String> get bypassDomains => List.from(_bypassDomains);
  List<String> get excludedApps => List.from(_excludedApps);
  String? get error => _error;
  DateTime? get connectedAt => _connectedAt;
  bool get isConnected => _status == VpnStatus.connected;
  bool get warpActive => _warpActive;
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
        _status = s;
        if (s == VpnStatus.connected) {
          _connectedAt ??= DateTime.now();
          _speed.start();
        } else {
          _connectedAt = null;
          _speed.stop();
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
  }

  Future<void> connect() async {
    if (_activeProfile == null) return;
    _error = null;
    _warpActive = false;
    _status = VpnStatus.connecting;
    notifyListeners();
    try {
      final profile = _activeProfile!;

      if (profile.protocol == VpnProtocol.amnezia && Platform.isWindows) {
        // AWG — unchanged
        List<String>? bypassIps;
        if (_routingMode == RoutingMode.russiaBypass) {
          bypassIps = await _loadBypassAllowedIps();
        }
        final conf = ConfigBuilder.buildAwgConf(
          profile,
          bypassAllowedIps: bypassIps,
        );
        await _vpn.connectAwg(conf);
      } else if (Platform.isWindows && profile.protocol == VpnProtocol.vless) {
        // VLESS — Xray router on :10808 + TUN sing-box forwarder
        final ruCidrs = _routingMode == RoutingMode.russiaBypass
            ? await _loadRuCidrs()
            : <String>[];
        final xrayJson = ConfigBuilder.buildXrayVless(
          profile,
          routingMode: _routingMode,
          ruCidrs: ruCidrs,
        );
        final tunConfig = ConfigBuilder.buildTun();
        await _vpn.connectProxy(
          xrayConfigJson: xrayJson,
          tunConfigJson: ConfigBuilder.toJson(tunConfig),
        );
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
        );
        final tunConfig = ConfigBuilder.buildTun();
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
        );
        await _vpn.connect(
          ConfigBuilder.toJson(config),
          excludedApps: _excludedApps,
        );
      }
    } catch (e) {
      _status = VpnStatus.error;
      _error = e.toString().replaceFirst('UnimplementedError: ', '');
      notifyListeners();
    }
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

  Future<void> disconnect() async {
    _warpActive = false;
    _status = VpnStatus.disconnecting;
    notifyListeners();
    await _vpn.disconnect();
  }

  Future<void> addProfile(VpnProfile profile) async {
    await _repo.add(profile);
    _profiles = _repo.getAll().toList();
    notifyListeners();
  }

  Future<void> addProfiles(List<VpnProfile> list) async {
    for (final p in list) {
      await _repo.add(p);
    }
    _profiles = _repo.getAll().toList();
    notifyListeners();
  }

  Future<void> removeProfile(String id) async {
    if (_activeProfile?.id == id) await disconnect();
    await _repo.remove(id);
    _profiles = _repo.getAll().toList();
    if (_activeProfile?.id == id) _activeProfile = null;
    notifyListeners();
  }

  Future<void> selectProfile(VpnProfile profile) async {
    final wasConnected = isConnected;
    _activeProfile = profile;
    _activeCountryCode = _countryCache[profile.serverHost];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastProfileId', profile.id);
    notifyListeners();
    _fetchCountry(profile.serverHost);
    if (wasConnected) await connect();
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

  void _fetchCountry(String host) {
    if (host.isEmpty) return;
    if (_countryCache.containsKey(host)) {
      if (_activeCountryCode != _countryCache[host]) {
        _activeCountryCode = _countryCache[host];
        notifyListeners();
      }
      return;
    }
    _doFetchCountry(host);
  }

  Future<void> _doFetchCountry(String host) async {
    try {
      final resp = await http
          .get(Uri.parse('http://ip-api.com/json/$host?fields=countryCode'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final code = data['countryCode'] as String?;
        if (code != null && code.isNotEmpty) {
          _countryCache[host] = code;
          if (_activeProfile?.serverHost == host) {
            _activeCountryCode = code;
            notifyListeners();
          }
        }
      }
    } catch (_) {}
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

  Future<List<String>> _loadRuCidrs() async {
    try {
      final data = await rootBundle.loadString('assets/data/iplist_ru.txt');
      return data
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
    } catch (e) {
      debugPrint('iplist_ru load error: $e');
      return [];
    }
  }

  Future<List<String>> _loadBypassAllowedIps() async {
    try {
      final data =
          await rootBundle.loadString('assets/data/allowed_ips_bypass.txt');
      return data
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
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
    _speed.dispose();
    _vpn.dispose();
    super.dispose();
  }
}
