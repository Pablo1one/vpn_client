import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../models/profile.dart';

// Профили (содержат креды: uuid, reality-ключи, пароли) храним в зашифрованном
// хранилище ОС: Android Keystore (EncryptedSharedPreferences), Windows DPAPI,
// iOS/macOS Keychain. Старый плейнтекст-файл vpn_profiles.json мигрируем один раз.
class ProfileRepository {
  static const _key = 'profiles';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  List<VpnProfile> _profiles = [];

  Future<void> load() async {
    String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (_) {
      raw = null; // хранилище недоступно — пробуем миграцию/старый файл ниже
    }
    // первый запуск после обновления: переносим старый плейнтекст-файл
    raw ??= await _migrateFromPlaintext();
    if (raw == null) {
      _profiles = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
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
    final raw = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    try {
      await _storage.write(key: _key, value: raw);
    } catch (_) {
      // фолбэк: если шифрованное хранилище недоступно — пишем в файл, чтобы
      // не потерять профили (лучше плейнтекст, чем потеря данных)
      try {
        await (await _legacyFile()).writeAsString(raw);
      } catch (_) {}
    }
  }

  // Переносит старый vpn_profiles.json в шифрованное хранилище и удаляет файл.
  // Возвращает перенесённый JSON, либо null (файла нет / некорректен).
  Future<String?> _migrateFromPlaintext() async {
    try {
      final file = await _legacyFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      jsonDecode(raw) as List; // валидируем, что это список профилей
      await _storage.write(key: _key, value: raw); // пишем зашифрованно
      try {
        await file.delete(); // плейнтекст удаляем только после успешной записи
      } catch (_) {}
      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<File> _legacyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/vpn_profiles.json');
  }
}
