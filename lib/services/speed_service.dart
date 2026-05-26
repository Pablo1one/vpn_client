import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SpeedData {
  final int uploadBps;
  final int downloadBps;
  final int pingMs;
  const SpeedData({this.uploadBps = 0, this.downloadBps = 0, this.pingMs = -1});
  static const empty = SpeedData();
}

/// Подключается к Clash API sing-box (:9090) для трафика и пинга.
/// Пинг измеряется через /proxies/proxy/delay — реальная задержка через VPN.
class SpeedService {
  static const _apiBase = 'http://127.0.0.1:9090';
  static const _pingUrl = 'http://cp.cloudflare.com/generate_204';

  final _controller = StreamController<SpeedData>.broadcast();
  http.Client? _client;
  Timer? _pingTimer;
  int _pingMs = -1;
  bool _active = false;

  Stream<SpeedData> get stream => _controller.stream;

  void start() {
    if (_active) return;
    _active = true;
    _connectTrafficStream();
    _updatePing();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updatePing());
  }

  void stop() {
    _active = false;
    _client?.close();
    _client = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pingMs = -1;
    if (!_controller.isClosed) _controller.add(SpeedData.empty);
  }

  Future<void> _connectTrafficStream() async {
    while (_active) {
      try {
        _client = http.Client();
        final req = http.Request('GET', Uri.parse('$_apiBase/traffic'));
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
            .get(Uri.parse(
                '$_apiBase/proxies/proxy/delay?timeout=5000&url=$_pingUrl'))
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
}
