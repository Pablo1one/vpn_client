import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'log_service.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnService {
  Stream<VpnStatus> get statusStream;
  Future<void> connect(String singboxConfigJson,
      {List<String> excludedApps = const []});
  Future<void> connectProxy({
    String? singboxConfigJson,
    String? xrayConfigJson,
    String? tunConfigJson,
  });
  Future<void> connectAwg(String confContent);
  Future<void> disconnect();
  Future<void> cleanup();
  void dispose();

  factory VpnService.create() {
    if (Platform.isAndroid) return _MobileVpnService();
    if (Platform.isIOS) return _MobileVpnService();
    if (Platform.isWindows) return _WindowsVpnService();
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

// мобильный (android + ios)
class _MobileVpnService implements VpnService {
  static const _method = MethodChannel('com.example.vpn_client/vpn');
  static const _events = EventChannel('com.example.vpn_client/vpn_events');

  final _controller = StreamController<VpnStatus>.broadcast();
  late final StreamSubscription _sub;

  _MobileVpnService() {
    _sub = _events.receiveBroadcastStream().listen(
      (event) => _controller.add(_parse(event as String)),
      onError: (_) => _controller.add(VpnStatus.error),
    );
  }

  VpnStatus _parse(String s) => switch (s) {
        'connected' => VpnStatus.connected,
        'connecting' => VpnStatus.connecting,
        'disconnecting' => VpnStatus.disconnecting,
        'disconnected' => VpnStatus.disconnected,
        _ => VpnStatus.error,
      };

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  Future<void> connect(String config,
          {List<String> excludedApps = const []}) =>
      _method.invokeMethod(
          'connect', {'config': config, 'excludedApps': excludedApps});

  @override
  Future<void> connectProxy({
    String? singboxConfigJson,
    String? xrayConfigJson,
    String? tunConfigJson,
  }) =>
      throw UnsupportedError('Proxy mode not supported on mobile');

  @override
  Future<void> connectAwg(String confContent) =>
      throw UnsupportedError('AWG not yet supported on mobile');

  @override
  Future<void> disconnect() => _method.invokeMethod('disconnect');

  @override
  Future<void> cleanup() async {}

  @override
  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

// windows — прокси (xray или singbox) на порту 10808 плюс tun форвардер
class _WindowsVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();

  Process? _process;         // tun singbox
  StreamSubscription? _outSub;
  StreamSubscription? _errSub;
  File? _configFile;

  Process? _proxyProcess;    // xray или singbox прокси
  File? _proxyConfigFile;

  bool _awgActive = false;
  static const _awgTunnelName = 'vpnclient_awg';
  static const _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin';
  }

  String get _exePath => '$_binDir\\sing-box.exe';

  Future<void> _ensureWintun() async {
    final src = File('$_binDir\\wintun.dll');
    final dst = File('${File(_exePath).parent.path}\\wintun.dll');
    if (src.existsSync() && !dst.existsSync()) {
      await src.copy(dst.path);
    }
  }

  Future<void> _killProxy() async {
    final old = _proxyProcess;
    _proxyProcess = null;
    if (old != null) {
      old.kill(ProcessSignal.sigterm);
      await old.exitCode
          .timeout(const Duration(seconds: 3), onTimeout: () {
            old.kill();
            return -1;
          })
          .catchError((_) => -1);
    }
    try { await _proxyConfigFile?.delete(); } catch (_) {}
    _proxyConfigFile = null;
  }

  // sing-box не удаляет tun0 при падении — следующий запуск упадёт с "file already exists"
  Future<void> _removeTunAdapter() async {
    await Process.run(
      'powershell',
      ['-Command', 'Remove-NetAdapter -Name "tun0" -Confirm:\$false -ErrorAction SilentlyContinue'],
      runInShell: false,
    );
  }

  Future<void> _killExistingProcess() async {
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false);
    await _removeTunAdapter();

    await _killProxy();
    if (_process == null) {
      await Future.delayed(const Duration(milliseconds: 1000));
      return;
    }
    await _outSub?.cancel();
    _outSub = null;
    await _errSub?.cancel();
    _errSub = null;
    final old = _process!;
    _process = null;
    old.kill(ProcessSignal.sigterm);
    await old.exitCode
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            old.kill();
            return -1;
          },
        )
        .catchError((_) => -1);
    await Future.delayed(const Duration(milliseconds: 1000));
    try { await _configFile?.delete(); } catch (_) {}
    _configFile = null;
  }

  Future<void> _startProxy(String configJson, {required bool isXray}) async {
    final exePath = isXray ? '$_binDir\\xray.exe' : _exePath;
    final exe = File(exePath);
    if (!exe.existsSync()) {
      throw Exception(
        '${isXray ? "xray" : "sing-box"}.exe не найден\nОжидается: $exePath',
      );
    }

    _proxyConfigFile = File(
      '${Directory.systemTemp.path}\\vpn_client_proxy_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await _proxyConfigFile!.writeAsString(configJson);

    _proxyProcess = await Process.start(
      exe.path,
      ['run', '-c', _proxyConfigFile!.path],
      runInShell: false,
    );
    final proc = _proxyProcess!;
    final errLines = <String>[];
    bool exited = false;

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      errLines.add(l);
      LogService().add('[proxy] $l');
    });
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      errLines.add(l);
      LogService().add('[proxy] $l');
    });
    proc.exitCode.then((_) => exited = true);

    // ждём открытия порта 10808 до 8 с
    for (var i = 0; i < 16; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (exited) {
        final log = errLines.isNotEmpty ? errLines.take(10).join('\n') : '(нет вывода)';
        throw Exception(
          '${isXray ? "xray" : "sing-box"} завершился до открытия порта:\n$log',
        );
      }
      try {
        final s = await Socket.connect('127.0.0.1', 10808,
            timeout: const Duration(milliseconds: 300));
        await s.close();
        return;
      } catch (_) {}
    }
    final log = errLines.isNotEmpty ? errLines.take(10).join('\n') : '(нет вывода)';
    throw Exception(
      '${isXray ? "xray" : "sing-box"} не открыл порт 10808 за 8 с:\n$log',
    );
  }

  Future<void> _launchTun(String configJson) async {
    _configFile = File(
      '${Directory.systemTemp.path}\\vpn_client_tun_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await _configFile!.writeAsString(configJson);

    _process = await Process.start(
      _exePath,
      ['run', '-c', _configFile!.path],
      runInShell: false,
    );
    final proc = _process!;

    bool started = false;
    final ready = Completer<void>();
    final allLines = <String>[];

    void checkLine(String line) {
      if (line.isEmpty) return;
      allLines.add(line.trim());
      if (!started &&
          (line.contains('sing-box started') ||
              (line.contains('started') && line.contains('inbound/')))) {
        started = true;
        if (!ready.isCompleted) ready.complete();
      }
    }

    _outSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          checkLine(line);
          LogService().add('[tun] $line');
        });

    _errSub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          checkLine(line);
          LogService().add('[tun] $line');
        });

    proc.exitCode.then((code) {
      if (_process != proc) return;
      _controller.add(VpnStatus.disconnected);
      if (!started && !ready.isCompleted) {
        final log = allLines.isNotEmpty
            ? allLines.take(10).join('\n')
            : '(нет вывода)';
        ready.completeError(
            Exception('sing-box (TUN) завершился (код $code):\n$log'));
      }
    });

    // первый холодный старт wintun занимает до 20 с
    Future.delayed(const Duration(seconds: 25), () {
      if (!started && !ready.isCompleted) {
        final log = allLines.isNotEmpty
            ? allLines.take(10).join('\n')
            : '(нет вывода — нет прав администратора?)';
        _controller.add(VpnStatus.error);
        ready.completeError(
            Exception('sing-box не запустился за 25 с:\n$log'));
      }
    });

    await ready.future;
  }

  @override
  Future<void> connectProxy({
    String? singboxConfigJson,
    String? xrayConfigJson,
    String? tunConfigJson,
  }) async {
    _controller.add(VpnStatus.connecting);
    try {
      await _ensureWintun();
      await _killExistingProcess();

      if (xrayConfigJson != null) {
        await _startProxy(xrayConfigJson, isXray: true);
      } else if (singboxConfigJson != null) {
        await _startProxy(singboxConfigJson, isXray: false);
      } else {
        throw ArgumentError('singboxConfigJson or xrayConfigJson required');
      }

      if (tunConfigJson != null) {
        await _launchTun(tunConfigJson);
      }

      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> connect(String configJson,
      {List<String> excludedApps = const []}) async {
    _controller.add(VpnStatus.connecting);
    try {
      final exe = File(_exePath);
      if (!exe.existsSync()) {
        throw Exception('sing-box.exe не найден\nОжидается: ${exe.path}');
      }
      await _ensureWintun();
      await _killExistingProcess();
      await _launchTun(configJson);
      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> connectAwg(String confContent) async {
    _controller.add(VpnStatus.connecting);
    try {
      final awgExe = File('$_binDir\\amneziawg.exe');
      if (!awgExe.existsSync()) {
        throw Exception('amneziawg.exe не найден\nОжидается: ${awgExe.path}');
      }

      await _uninstallAwgTunnel();

      final confFile = File('${Directory.systemTemp.path}\\$_awgTunnelName.conf');
      await confFile.writeAsString(confContent);

      final result = await Process.run(
        awgExe.path,
        ['/installtunnelservice', confFile.path],
        runInShell: false,
      );

      if (result.exitCode != 0) {
        throw Exception(
          'amneziawg: ошибка установки туннеля (код ${result.exitCode}): ${result.stderr}',
        );
      }

      await _waitForAwgHandshake();
      _awgActive = true;
      _controller.add(VpnStatus.connected);
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  Future<void> _waitForAwgHandshake() async {
    final awgCtl = File('$_binDir\\awg.exe');
    if (!awgCtl.existsSync()) {
      await Future.delayed(const Duration(seconds: 10));
      return;
    }
    const maxAttempts = 60;
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final r = await Process.run(
        awgCtl.path,
        ['show', _awgTunnelName],
        runInShell: false,
      );
      if ((r.stdout as String).contains('latest handshake:')) return;
    }
  }

  Future<void> _uninstallAwgTunnel() async {
    if (!_awgActive) return;
    _awgActive = false;
    final awgExe = '$_binDir\\amneziawg.exe';
    await Process.run(awgExe, ['/uninstalltunnelservice', _awgTunnelName],
        runInShell: false);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _clearSystemProxy() async {
    await Process.run('reg', [
      'add', _regPath, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f',
    ]);
  }

  @override
  Future<void> cleanup() async {
    await _clearSystemProxy();
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false);
  }

  @override
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    if (_awgActive) {
      await _uninstallAwgTunnel();
    } else {
      await _killExistingProcess();
    }
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    if (_awgActive) _uninstallAwgTunnel();
    _proxyProcess?.kill();
    _process?.kill();
    _controller.close();
  }
}
