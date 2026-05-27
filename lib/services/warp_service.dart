import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'log_service.dart';

class WarpConfig {
  final String privateKey;
  final String address;
  final String endpoint;
  final String publicKey;

  const WarpConfig({
    required this.privateKey,
    required this.address,
    required this.endpoint,
    required this.publicKey,
  });

  Map<String, dynamic> toJson() => {
        'privateKey': privateKey,
        'address': address,
        'endpoint': endpoint,
        'publicKey': publicKey,
      };

  factory WarpConfig.fromJson(Map<String, dynamic> j) => WarpConfig(
        privateKey: j['privateKey'] as String,
        address: j['address'] as String,
        endpoint: j['endpoint'] as String,
        publicKey: j['publicKey'] as String,
      );

  String toWgConf() => '''[Interface]
PrivateKey = $privateKey
Address = $address, fd01:5ca1:ab1e:80fa:ab85:6eea:213f:f4ba/128
DNS = 1.1.1.1

[Peer]
PublicKey = $publicKey
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $endpoint
''';
}

class WarpService {
  static const _prefKey = 'warpConfig';

  // Несколько актуальных версий WARP API — пробуем по очереди
  static const _endpoints = [
    'https://api.cloudflareclient.com/v0a4005',
    'https://api.cloudflareclient.com/v0a3704',
    'https://api.cloudflareclient.com/v0a2158',
  ];

  static Future<WarpConfig?> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return null;
    try {
      return WarpConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(WarpConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(c.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // Сохраняет вручную введённый WireGuard-конфиг (для случаев когда API недоступен)
  static Future<WarpConfig> saveManual(String wgConf) async {
    final cfg = _parseWgConf(wgConf);
    await _save(cfg);
    return cfg;
  }

  static WarpConfig _parseWgConf(String conf) {
    String? privateKey, address, publicKey, endpoint;
    for (final line in conf.split('\n')) {
      final l = line.trim();
      if (l.startsWith('PrivateKey')) privateKey = l.split('=').last.trim();
      if (l.startsWith('Address')) address = l.split('=').last.trim().split(',').first.trim();
      if (l.startsWith('PublicKey')) publicKey = l.split('=').last.trim();
      if (l.startsWith('Endpoint')) endpoint = l.split('=').last.trim();
    }
    if (privateKey == null || address == null || publicKey == null || endpoint == null) {
      throw Exception('Неверный формат WireGuard конфига.\nОжидаются поля: PrivateKey, Address, PublicKey, Endpoint');
    }
    return WarpConfig(
      privateKey: privateKey,
      address: address,
      endpoint: endpoint,
      publicKey: publicKey,
    );
  }

  // Генерирует ключевую пару, регистрирует аккаунт WARP (пробует несколько эндпоинтов)
  static Future<WarpConfig> register() async {
    final binDir = _binDir;
    final awgExe = File('$binDir\\awg.exe');
    if (!awgExe.existsSync()) {
      throw Exception('awg.exe не найден: ${awgExe.path}');
    }

    final privResult = await Process.run(awgExe.path, ['genkey'], runInShell: false);
    if (privResult.exitCode != 0) {
      throw Exception('awg genkey ошибка: ${privResult.stderr}');
    }
    final privateKey = (privResult.stdout as String).trim();
    if (privateKey.length < 40) {
      throw Exception('awg genkey вернул некорректный ключ');
    }

    final pubProc = await Process.start(awgExe.path, ['pubkey'], runInShell: false);
    pubProc.stdin.writeln(privateKey);
    await pubProc.stdin.close();
    final pubOut = await pubProc.stdout.transform(utf8.decoder).join();
    final pubExit = await pubProc.exitCode;
    if (pubExit != 0) {
      throw Exception('awg pubkey ошибка');
    }
    final publicKeyLocal = pubOut.trim();

    final body = jsonEncode({
      'key': publicKeyLocal,
      'install_id': _randomHex(22),
      'fcm_token': '',
      'tos': DateTime.now().toUtc().toIso8601String(),
      'type': 'Android',
      'locale': 'en_US',
    });
    final headers = {
      'Content-Type': 'application/json',
      'User-Agent': 'okhttp/3.12.1',
      'CF-Client-Version': 'a-6.30-3596',
    };

    Object? lastError;
    for (final base in _endpoints) {
      try {
        LogService().add('[warp] trying $base/reg…');
        final resp = await http
            .post(Uri.parse('$base/reg'), headers: headers, body: body)
            .timeout(const Duration(seconds: 8));

        if (resp.statusCode != 200) {
          lastError = Exception('WARP API ошибка ${resp.statusCode}: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
          continue;
        }

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final config = data['config'] as Map<String, dynamic>;
        final iface = config['interface'] as Map<String, dynamic>;
        final peers = (config['peers'] as List).cast<Map<String, dynamic>>();
        final peer = peers.first;

        final address = (iface['addresses'] as Map<String, dynamic>)['v4'] as String;
        final peerPub = peer['public_key'] as String;
        final endpoint = (peer['endpoint'] as Map<String, dynamic>)['v4'] as String;

        final warpConfig = WarpConfig(
          privateKey: privateKey,
          address: '$address/32',
          endpoint: endpoint,
          publicKey: peerPub,
        );
        await _save(warpConfig);
        LogService().add('[warp] registered via $base, endpoint=$endpoint');
        return warpConfig;
      } catch (e) {
        lastError = e;
        LogService().add('[warp] $base failed: $e');
      }
    }

    throw Exception(
      'WARP API недоступна (все эндпоинты не ответили).\n'
      'Вероятно, api.cloudflareclient.com заблокирован в вашей сети.\n\n'
      'Используйте ручной ввод конфига (wgcf или другой генератор).',
    );
  }

  static String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin';
  }

  static String _randomHex(int len) {
    final rng = Random.secure();
    final bytes = List.generate((len / 2).ceil(), (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, len);
  }
}
