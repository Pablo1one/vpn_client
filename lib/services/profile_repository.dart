import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/profile.dart';

class ProfileRepository {
  List<VpnProfile> _profiles = [];

  Future<void> load() async {
    final file = await _file();
    if (!await file.exists()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      _profiles =
          list.map((e) => VpnProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      _profiles = [];
    }
  }

  List<VpnProfile> getAll() => List.unmodifiable(_profiles);

  Future<void> add(VpnProfile profile) async {
    _profiles.add(profile);
    await _save();
  }

  Future<void> remove(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    await _save();
  }

  Future<void> update(VpnProfile profile) async {
    final i = _profiles.indexWhere((p) => p.id == profile.id);
    if (i >= 0) {
      _profiles[i] = profile;
      await _save();
    }
  }

  Future<void> _save() async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/vpn_profiles.json');
  }
}
