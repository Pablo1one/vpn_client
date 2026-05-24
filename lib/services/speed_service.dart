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

/// Connects to sing-box Clash API (:9090) for real-time traffic,
/// and measures TCP ping to 1.1.1.1:53 every 5 seconds.
class SpeedService {
  static const _apiBase = 'http://127.0.0.1:9090';

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
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _updatePing());
    _updatePing();
  }

  void stop() {
    _active = false;
    _client?.close();
    _client = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    if (!_controller.isClosed) {
      _controller.add(SpeedData.empty);
    }
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
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        '1.1.1.1', 53,
        timeout: const Duration(seconds: 3),
      );
      sw.stop();
      socket.destroy();
      _pingMs = sw.elapsedMilliseconds;
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
