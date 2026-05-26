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
  static const _apiBase = 'https://api.cloudflareclient.com/v0a2158';

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

  // Генерирует ключевую пару curve25519, регистрирует аккаунт WARP и сохраняет конфиг.
  static Future<WarpConfig> register() async {
    final binDir = _binDir;
    final awgExe = File('$binDir\\awg.exe');
    if (!awgExe.existsSync()) {
      throw Exception('awg.exe не найден: ${awgExe.path}');
    }

    final privResult = await Process.run(awgExe.path, ['genkey'], runInShell: false);
    if (privResult.exitCode != 0) {
      throw Exception('awg genkey failed: ${privResult.stderr}');
    }
    final privateKey = (privResult.stdout as String).trim();

    final pubProc = await Process.start(awgExe.path, ['pubkey'], runInShell: false);
    pubProc.stdin.writeln(privateKey);
    await pubProc.stdin.close();
    final pubOut = await pubProc.stdout.transform(utf8.decoder).join();
    final pubErr = await pubProc.stderr.transform(utf8.decoder).join();
    final pubExit = await pubProc.exitCode;
    if (pubExit != 0) {
      throw Exception('awg pubkey failed: $pubErr');
    }
    final publicKeyLocal = pubOut.trim();

    LogService().add('[warp] registering account…');
    final resp = await http
        .post(
          Uri.parse('$_apiBase/reg'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'okhttp/3.12.1',
          },
          body: jsonEncode({
            'key': publicKeyLocal,
            'install_id': _randomHex(22),
            'fcm_token': '',
            'tos': DateTime.now().toUtc().toIso8601String(),
            'type': 'Android',
            'locale': 'en_US',
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('WARP reg failed (${resp.statusCode}): ${resp.body}');
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
    LogService().add('[warp] registered, endpoint=$endpoint');
    return warpConfig;
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
