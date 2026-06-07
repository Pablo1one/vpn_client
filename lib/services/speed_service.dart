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
  Timer? _pingTimer;
  Timer? _awgPollTimer;
  int _pingMs = -1;
  bool _active = false;
  String _serverHost = ''; // хост сервера, пинг бьём по нему (tcp 443)
  String _serverIp = '';   // его IP, резолвим 1 раз (чтоб пинг не дрейфовал)

  // awg mode state
  String? _awgInterface;
  int? _prevRx;
  int? _prevTx;
  DateTime? _prevSample;

  Stream<SpeedData> get stream => _controller.stream;

  // ── Clash api (sing-box / xray) mode ──────────────────────────────────────

  void start({String serverHost = ''}) {
    if (_active) return;
    _active = true;
    _awgInterface = null;
    _serverHost = serverHost;
    _serverIp = '';
    _resolveServerIp();
    _connectTrafficStream();
    _measureInitialPing(); // замер один раз при подключении (без перезамера - иначе дрейф)
  }

  // ── awg mode (interface byte counters + icmp ping) ────────────────────────

  void startAwg({required String interfaceName, String serverHost = ''}) {
    if (_active) return;
    _active = true;
    _awgInterface = interfaceName;
    _serverHost = serverHost;
    _serverIp = '';
    _resolveServerIp();
    _prevRx = null;
    _prevTx = null;
    _prevSample = null;
    _awgPollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollAwgStats());
    _measureInitialPing();
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

  // Пинг до САМОГО сервера (tcp-хендшейк к host:443). При активном коннекте IP
  // сервера маршрутизируется direct (мимо туннеля), поэтому меряется реальная
  // задержка до сервера, а не круг через туннель до внешней цели (раньше так и
  // было - запредельные 200-500мс на главной). На нашем сервере 443 слушает
  // haproxy, поэтому tcp отвечает для всех протоколов (vless/tuic/hysteria2/awg).
  // Замер пинга ОДИН раз при подключении (с ретраями на прогрев туннеля). Первый
  // успешный замер - настоящий хендшейк до сервера (~реальный rtt); дальше НЕ
  // перезамеряем, иначе значение «дрейфует» вниз из-за переиспользования сессии
  // к серверу (MUX/пул) - отдаёт быстрый поток без реального круга.
  Future<void> _measureInitialPing() async {
    for (var i = 0; i < 5; i++) {
      if (!_active) return;
      await _updatePing();
      if (_pingMs > 0) return; // зафиксировали первый успешный замер
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _updatePing() async {
    if (!_active) return;
    // Основной метод: tcp-хендшейк к САМОМУ серверу (IP:443). SYN-ACK приходит
    // от реального сервера, подделать локально нельзя - настоящий rtt до сервера
    // (как в «Ключах»). Бьём по запиненному IP, а не по домену - иначе значение
    // дрейфует (домен со временем переразрешается в ближний cdn-узел - ~10мс).
    // icmp нельзя - его перехватывает локальный tun-стек.
    final host = _serverIp.isNotEmpty ? _serverIp : _serverHost;
    if (host.isNotEmpty) {
      final ms = await _tcpHandshakeMs(host, 443);
      if (ms != null) {
        _pingMs = ms;
        return;
      }
    }
    // Фолбэк для awg (сервер без открытого tcp 443): tcp к cdn 1.1.1.1:443 ЧЕРЕЗ
    // туннель. Путь клиент-сервер-cdn, а cdn (anycast) вплотную к серверу, поэтому
    // значение ≈ реальный rtt до сервера.
    _pingMs = await _tcpHandshakeMs('1.1.1.1', 443) ?? -1;
  }

  // Резолвим хост сервера в ipv4 один раз и пинуем - чтобы пинг бил всегда в один
  // и тот же origin, а не дрейфовал при переразрешении домена.
  Future<void> _resolveServerIp() async {
    final host = _serverHost;
    if (host.isEmpty) return;
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      _serverIp = host; // уже IP
      return;
    }
    try {
      final addrs =
          await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      final v4 = addrs.where((a) => a.type == InternetAddressType.IPv4);
      if (v4.isNotEmpty && _active) _serverIp = v4.first.address;
    } catch (_) {}
  }

  // rtt tcp-хендшейка до host:port (мс), либо null при ошибке/таймауте.
  Future<int?> _tcpHandshakeMs(String host, int port) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
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

  static String formatSpeed(int bps) {
    if (bps <= 0) return '0 B/s';
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
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
