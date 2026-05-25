import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../services/profile_repository.dart';
import '../services/speed_service.dart';
import '../services/vpn_service.dart';
import '../utils/config_builder.dart';
import '../utils/xray_config_builder.dart';

bool _isVlessXhttp(VpnProfile p) =>
    p.protocol == VpnProtocol.vless &&
    (p.config['transport'] as String? ?? '') == 'xhttp';

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
  Stream<SpeedData> get speedStream => _speed.stream;
  bool get isBusy =>
      _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  Future<void> init() async {
    try {
      _vpn = VpnService.create();
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
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> connect() async {
    if (_activeProfile == null) return;
    _error = null;
    _status = VpnStatus.connecting;
    notifyListeners();
    try {
      final profile = _activeProfile!;

      if (profile.protocol == VpnProtocol.amnezia && Platform.isWindows) {
        List<String>? bypassIps;
        if (_routingMode == RoutingMode.russiaBypass) {
          bypassIps = await _loadBypassAllowedIps();
        }
        final conf = ConfigBuilder.buildAwgConf(
          profile,
          bypassAllowedIps: bypassIps,
        );
        await _vpn.connectAwg(conf);
      } else if (Platform.isWindows &&
          (profile.protocol == VpnProtocol.tuic ||
              profile.protocol == VpnProtocol.hysteria2)) {
        // Proxy mode: no TUN, HTTP proxy on localhost, set system proxy.
        final config = ConfigBuilder.buildProxyMode(profile);
        await _vpn.connectProxy(singboxConfigJson: ConfigBuilder.toJson(config));
      } else if (Platform.isWindows && _isVlessXhttp(profile)) {
        // xhttp is xray-only; run xray standalone with HTTP proxy.
        final xrayConfig = XrayConfigBuilder.buildStandalone(profile);
        await _vpn.connectProxy(xrayConfigJson: XrayConfigBuilder.toJson(xrayConfig));
      } else {
        // TUN mode: sing-box with full routing (VLESS reality/ws/grpc, WireGuard, mobile).
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

  Future<void> disconnect() async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastProfileId', profile.id);
    notifyListeners();
    if (wasConnected) await connect();
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

  /// Returns list of installed apps as {package, name} maps (Android only).
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
