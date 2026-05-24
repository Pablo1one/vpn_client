import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../services/profile_repository.dart';
import '../services/vpn_service.dart';
import '../utils/config_builder.dart';

class VpnProvider extends ChangeNotifier {
  final _repo = ProfileRepository();
  late final VpnService _vpn;

  VpnStatus _status = VpnStatus.disconnected;
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
  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy =>
      _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  Future<void> init() async {
    try {
      _vpn = VpnService.create();
      _vpn.statusStream.listen((s) {
        _status = s;
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
      final config = ConfigBuilder.build(
        _activeProfile!,
        routingMode: _routingMode,
        killSwitch: _killSwitch,
        bypassDomains: _bypassDomains,
      );
      await _vpn.connect(
        ConfigBuilder.toJson(config),
        excludedApps: _excludedApps,
      );
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
    _activeProfile = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastProfileId', profile.id);
    notifyListeners();
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
    _vpn.dispose();
    super.dispose();
  }
}
