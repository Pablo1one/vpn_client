import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnService {
  Stream<VpnStatus> get statusStream;
  Future<void> connect(String singboxConfigJson,
      {List<String> excludedApps = const []});
  Future<void> connectAwg(String confContent);
  Future<void> disconnect();
  void dispose();

  factory VpnService.create() {
    if (Platform.isAndroid) return _MobileVpnService();
    if (Platform.isIOS) return _MobileVpnService();
    if (Platform.isWindows) return _WindowsVpnService();
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

// ─── Mobile (Android + iOS) ──────────────────────────────────────────────────
// Both platforms share the same MethodChannel/EventChannel protocol.
// Android: implemented in VpnPlugin.kt + SingBoxVpnService.kt
// iOS:     implemented in VpnPlugin.swift + PacketTunnelProvider.swift
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
  Future<void> connectAwg(String confContent) =>
      throw UnsupportedError('AWG not yet supported on mobile');

  @override
  Future<void> disconnect() => _method.invokeMethod('disconnect');

  @override
  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

// ─── Windows ─────────────────────────────────────────────────────────────────
// Launches sing-box.exe as a subprocess with the generated config.
// Requires sing-box.exe at: <app_dir>\data\flutter_assets\assets\bin\sing-box.exe
// WinTun driver must be installed: https://www.wintun.net/
// Run the app as Administrator for TUN interface creation.
class _WindowsVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();
  Process? _process;
  StreamSubscription? _outSub;
  StreamSubscription? _errSub;
  File? _configFile;
  bool _awgActive = false;
  static const _awgTunnelName = 'vpnclient_awg';

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  String get _binDir {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin';
  }

  String get _exePath => '$_binDir\\sing-box.exe';

  // Ensure wintun.dll is in the same directory as sing-box.exe.
  // sing-box loads it at startup — it must be a sibling of the exe.
  Future<void> _ensureWintun() async {
    final src = File('$_binDir\\wintun.dll');
    final dst = File('${File(_exePath).parent.path}\\wintun.dll');
    if (src.existsSync() && !dst.existsSync()) {
      await src.copy(dst.path);
    }
  }

  Future<void> _killExistingProcess() async {
    if (_process == null) return;
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
    // Let WinTun release the TUN interface before we recreate it.
    await Future.delayed(const Duration(milliseconds: 500));
    await _configFile?.delete().catchError((_) {});
    _configFile = null;
  }

  @override
  Future<void> connect(String configJson,
      {List<String> excludedApps = const []}) async {
    _controller.add(VpnStatus.connecting);
    try {
      final exe = File(_exePath);
      if (!exe.existsSync()) {
        throw Exception(
          'sing-box.exe not found.\n'
          'Expected: ${exe.path}\n'
          'Download from https://github.com/SagerNet/sing-box/releases '
          'and place at assets/bin/sing-box.exe, then rebuild.',
        );
      }

      await _ensureWintun();
      await _killExistingProcess();

      _configFile = File(
        '${Directory.systemTemp.path}\\vpn_client_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await _configFile!.writeAsString(configJson);

      _process = await Process.start(
        exe.path,
        ['run', '-c', _configFile!.path],
        runInShell: false,
      );
      // Capture local ref so the exitCode closure tracks only this process.
      final proc = _process!;

      bool started = false;
      final ready = Completer<void>();
      final errorLines = <String>[];

      void checkLine(String line) {
        if (line.isEmpty) return;
        final lower = line.toLowerCase();
        if (lower.contains('error') ||
            lower.contains('fatal') ||
            lower.contains('failed') ||
            lower.contains('invalid')) {
          errorLines.add(line.trim());
        }
        if (!started &&
            (line.contains('sing-box started') ||
                (line.contains('started') && line.contains('inbound/')))) {
          started = true;
          _controller.add(VpnStatus.connected);
          if (!ready.isCompleted) ready.complete();
        }
      }

      _outSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(checkLine);

      _errSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(checkLine);

      proc.exitCode.then((code) {
        // Ignore exit of a process that was already replaced by a newer connect().
        if (_process != proc) return;
        _controller.add(VpnStatus.disconnected);
        if (!started && !ready.isCompleted) {
          final detail = errorLines.isNotEmpty
              ? '\n${errorLines.take(3).join('\n')}'
              : '';
          ready.completeError(
            Exception(
                'sing-box exited (code $code) before connecting$detail'),
          );
        }
      });

      // Fall back to "connected" after 5 s if no matching log line appears.
      Future.delayed(const Duration(seconds: 5), () {
        if (!started && !ready.isCompleted) {
          started = true;
          _controller.add(VpnStatus.connected);
          ready.complete();
        }
      });

      await ready.future;
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
        throw Exception(
          'amneziawg.exe not found.\n'
          'Expected: ${awgExe.path}\n'
          'Download from https://github.com/amnezia-vpn/amneziawg-windows-client/releases',
        );
      }

      // Uninstall any leftover tunnel from a previous session.
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
          'amneziawg install failed (code ${result.exitCode}): ${result.stderr}',
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

  // Polls `awg show <tunnel>` every 500 ms until the first WireGuard handshake
  // appears, which confirms that routes are applied and traffic flows.
  // Falls back to a plain delay if awg.exe is unavailable (timeout = 30 s).
  Future<void> _waitForAwgHandshake() async {
    final awgCtl = File('$_binDir\\awg.exe');
    if (!awgCtl.existsSync()) {
      await Future.delayed(const Duration(seconds: 10));
      return;
    }
    const maxAttempts = 60; // 30 s
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final r = await Process.run(
        awgCtl.path,
        ['show', _awgTunnelName],
        runInShell: false,
      );
      if ((r.stdout as String).contains('latest handshake:')) return;
    }
    // Timeout — proceed anyway rather than leaving the user stuck.
  }

  Future<void> _uninstallAwgTunnel() async {
    if (!_awgActive) return;
    _awgActive = false;
    final awgExe = '$_binDir\\amneziawg.exe';
    await Process.run(awgExe, ['/uninstalltunnelservice', _awgTunnelName],
        runInShell: false);
    await Future.delayed(const Duration(milliseconds: 500));
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
    _process?.kill();
    _controller.close();
  }
}
