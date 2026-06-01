import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../utils/config_builder.dart';

class SpeedData {
  final int uploadBps;
  final int downloadBps;
  final int pingMs;
  const SpeedData({this.uploadBps = 0, this.downloadBps = 0, this.pingMs = -1});
  static const empty = SpeedData();
}

class SpeedService {
  static const _apiBase = 'http://127.0.0.1:9090';
  static const _pingUrl = 'http://cp.cloudflare.com/generate_204';

  // тот же секрет, что вшит в конфиг clash_api — иначе API ответит 401
  Map<String, String> get _authHeaders =>
      {'Authorization': 'Bearer ${ConfigBuilder.clashApiSecret}'};

  final _controller = StreamController<SpeedData>.broadcast();
  http.Client? _client;
  Timer? _pingTimer;
  Timer? _awgPollTimer;
  int _pingMs = -1;
  bool _active = false;

  // AWG mode state
  String? _awgInterface;
  int? _prevRx;
  int? _prevTx;
  DateTime? _prevSample;

  Stream<SpeedData> get stream => _controller.stream;

  // ── Clash API (sing-box / xray) mode ──────────────────────────────────────

  void start() {
    if (_active) return;
    _active = true;
    _awgInterface = null;
    _connectTrafficStream();
    _updatePing();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updatePing());
  }

  // ── AWG mode (interface byte counters + ICMP ping) ────────────────────────

  void startAwg({required String interfaceName, String serverHost = ''}) {
    if (_active) return;
    _active = true;
    _awgInterface = interfaceName;
    _prevRx = null;
    _prevTx = null;
    _prevSample = null;
    _awgPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollAwgStats());
    _updateAwgPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updateAwgPing());
  }

  void stop() {
    _active = false;
    _client?.close();
    _client = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _awgPollTimer?.cancel();
    _awgPollTimer = null;
    _pingMs = -1;
    _awgInterface = null;
    _prevRx = null;
    _prevTx = null;
    _prevSample = null;
    if (!_controller.isClosed) _controller.add(SpeedData.empty);
  }

  Future<void> _pollAwgStats() async {
    if (!_active) return;
    try {
      final result = await Process.run(
        'powershell',
        [
          '-Command',
          '(Get-NetAdapterStatistics -Name "$_awgInterface" -ErrorAction Stop)'
              ' | Select-Object ReceivedBytes,SentBytes | ConvertTo-Json',
        ],
        runInShell: false,
      );
      if (result.exitCode != 0) return;
      final j = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final rx = (j['ReceivedBytes'] as num).toInt();
      final tx = (j['SentBytes'] as num).toInt();
      final now = DateTime.now();

      if (_prevRx != null && _prevSample != null) {
        final elapsed = now.difference(_prevSample!).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          final rxBps = ((rx - _prevRx!) / elapsed).round().clamp(0, 999999999);
          final txBps = ((tx - _prevTx!) / elapsed).round().clamp(0, 999999999);
          if (!_controller.isClosed) {
            _controller.add(SpeedData(
              uploadBps: txBps,
              downloadBps: rxBps,
              pingMs: _pingMs,
            ));
          }
        }
      }
      _prevRx = rx;
      _prevTx = tx;
      _prevSample = now;
    } catch (_) {}
  }

  Future<void> _updateAwgPing() async {
    if (!_active) return;
    try {
      // Пингуем публичный хост ЧЕРЕЗ туннель (сам VPN-сервер часто блокирует ICMP).
      // Это измеряет реальную задержку пути и совпадает по смыслу с пингом др. протоколов.
      final result = await Process.run(
        'ping', ['-n', '1', '-w', '3000', '1.1.1.1'],
        runInShell: false,
      );
      final out = (result.stdout as String).toLowerCase();
      final match = RegExp(r'time[<=](\d+)ms').firstMatch(out)
          ?? RegExp(r'время[<=](\d+)мс').firstMatch(out);
      if (match != null) {
        _pingMs = int.parse(match.group(1)!);
      } else if (out.contains('time<1ms') || out.contains('время<1мс')) {
        _pingMs = 1;
      } else {
        _pingMs = -1;
      }
    } catch (_) {
      _pingMs = -1;
    }
  }

  // ── Clash API helpers ──────────────────────────────────────────────────────

  Future<void> _connectTrafficStream() async {
    while (_active) {
      try {
        _client = http.Client();
        final req = http.Request('GET', Uri.parse('$_apiBase/traffic'));
        req.headers.addAll(_authHeaders);
        final resp = await _client!.send(req).timeout(const Duration(seconds: 3));

        await for (final line in resp.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!_active) return;
          if (line.isEmpty) continue;
          try {
            final j = jsonDecode(line) as Map<String, dynamic>;
            if (!_controller.isClosed) {
              _controller.add(SpeedData(
                uploadBps: (j['up'] as num? ?? 0).toInt(),
                downloadBps: (j['down'] as num? ?? 0).toInt(),
                pingMs: _pingMs,
              ));
            }
          } catch (_) {}
        }
      } catch (_) {
        if (!_active) return;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _updatePing() async {
    if (!_active) return;
    try {
      final c = http.Client();
      try {
        final resp = await c
            .get(
                Uri.parse(
                    '$_apiBase/proxies/proxy/delay?timeout=5000&url=$_pingUrl'),
                headers: _authHeaders)
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final j = jsonDecode(resp.body) as Map<String, dynamic>;
          _pingMs = (j['delay'] as num? ?? -1).toInt();
        } else {
          _pingMs = -1;
        }
      } finally {
        c.close();
      }
    } catch (_) {
      _pingMs = -1;
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }

  static String formatSpeed(int bps) {
    if (bps <= 0) return '0 B/s';
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  // Статический ICMP-пинг для проверки ключей (AWG/WG — UDP, TCP не работает)
  static Future<int?> icmpPing(String host) async {
    try {
      final result = await Process.run(
        'ping', ['-n', '1', '-w', '3000', host],
        runInShell: false,
      );
      final out = (result.stdout as String).toLowerCase();
      final match = RegExp(r'time[<=](\d+)ms').firstMatch(out)
          ?? RegExp(r'время[<=](\d+)мс').firstMatch(out);
      if (match != null) return int.parse(match.group(1)!);
      if (out.contains('time<1ms') || out.contains('время<1мс')) return 1;
      return null;
    } catch (_) {
      return null;
    }
  }
}
