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

  // тот же секрет, что вшит в конфиг clash_api - иначе api ответит 401
  Map<String, String> get _authHeaders =>
      {'Authorization': 'Bearer ${ConfigBuilder.clashApiSecret}'};

  final _controller = StreamController<SpeedData>.broadcast();
  http.Client? _client;
  Timer? _awgPollTimer;
  int _pingMs = -1;
  bool _active = false;

  // awg mode state
  String? _awgInterface;
  int? _prevRx;
  int? _prevTx;
  DateTime? _prevSample;

  Stream<SpeedData> get stream => _controller.stream;

  // ── Clash api (sing-box / xray) mode ──────────────────────────────────────

  // initialPing - реальный rtt до сервера, измеренный ДО подъёма туннеля (в
  // vpn_provider). Внутри туннеля мерить нельзя: sing-box перехватывает connect к
  // ip сервера и отдаёт заниженное (дрейф вниз 2-50мс), а clash-api /delay меряет
  // установку соединения СКВОЗЬ прокси и раздувает. Держим статичный честный
  // замер - rtt до фиксированного сервера за сессию стабилен.
  void start({int initialPing = -1}) {
    if (_active) return;
    _active = true;
    _awgInterface = null;
    _pingMs = initialPing;
    _connectTrafficStream();
  }

  // ── awg mode (interface byte counters + icmp ping) ────────────────────────

  void startAwg({required String interfaceName, int initialPing = -1}) {
    if (_active) return;
    _active = true;
    _awgInterface = interfaceName;
    _pingMs = initialPing;
    _prevRx = null;
    _prevTx = null;
    _prevSample = null;
    _awgPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollAwgStats());
  }

  void stop() {
    _active = false;
    _client?.close();
    _client = null;
    _awgPollTimer?.cancel();
    _awgPollTimer = null;
    _pingMs = -1;
    _awgInterface = null;
    _prevRx = null;
    _prevTx = null;
    _prevSample = null;
    if (!_controller.isClosed) _controller.add(SpeedData.empty);
  }

  String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin';
  }

  Future<void> _pollAwgStats() async {
    if (!_active) return;
    try {
      // Счётчики берём у самого WireGuard через awg.exe (лёгкий свой процесс),
      // а не powershell Get-NetAdapterStatistics каждую секунду.
      // `awg show <iface> transfer` - "<pubkey>\t<rx>\t<tx>" по пиру.
      final result = await Process.run(
        '$_binDir\\awg.exe',
        ['show', _awgInterface ?? '', 'transfer'],
        runInShell: false,
      );
      if (result.exitCode != 0) return;
      final line = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) return;
      final rx = int.tryParse(parts[parts.length - 2]) ?? 0; // received = download
      final tx = int.tryParse(parts[parts.length - 1]) ?? 0; // sent = upload
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

  // ── Clash api helpers ──────────────────────────────────────────────────────

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

  void dispose() {
    stop();
    _controller.close();
  }

  // bps - байт/с. Показываем в БИТАХ (Mbit/s), как speedtest и привычно юзеру -
  // раньше было MB/s (байты), отсюда расхождение в разы при сравнении со speedtest.
  static String formatSpeed(int bps) {
    if (bps <= 0) return '0 Mbps';
    final bits = bps * 8;
    if (bits < 1000000) return '${(bits / 1000).toStringAsFixed(0)} Kbps';
    return '${(bits / 1000000).toStringAsFixed(1)} Mbps';
  }

  // icmp-пинг (для awg/WG, где tcp к серверу не отвечает). Флаги ping и формат
  // вывода разные на win и linux/ведроид.
  static Future<int?> icmpPing(String host) async {
    try {
      final args = Platform.isWindows
          ? ['-n', '1', '-w', '3000', host]
          : ['-c', '1', '-W', '3', host];
      final result = await Process.run('ping', args, runInShell: false);
      final out = (result.stdout as String).toLowerCase();
      final match = RegExp(r'time[<=]\s*([\d.]+)\s*ms').firstMatch(out) ??
          RegExp(r'время[<=]\s*([\d.]+)\s*мс').firstMatch(out);
      if (match != null) return double.parse(match.group(1)!).round();
      if (out.contains('time<1ms') || out.contains('время<1мс')) return 1;
      return null;
    } catch (_) {
      return null;
    }
  }
}
