import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnService {
  Stream<VpnStatus> get statusStream;
  Future<void> connect(String singboxConfigJson);
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
  Future<void> connect(String config) =>
      _method.invokeMethod('connect', {'config': config});

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

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  String get _exePath {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    return '$appDir\\data\\flutter_assets\\assets\\bin\\sing-box.exe';
  }

  @override
  Future<void> connect(String configJson) async {
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

      _configFile = File(
        '${Directory.systemTemp.path}\\vpn_client_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await _configFile!.writeAsString(configJson);

      _process = await Process.start(
        exe.path,
        ['run', '-c', _configFile!.path],
        runInShell: false,
      );

      bool started = false;
      final ready = Completer<void>();

      void checkLine(String line) {
        if (!started &&
            (line.contains('sing-box started') ||
                (line.contains('started') && line.contains('inbound/')))) {
          started = true;
          _controller.add(VpnStatus.connected);
          if (!ready.isCompleted) ready.complete();
        }
      }

      _outSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(checkLine);

      _errSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(checkLine);

      _process!.exitCode.then((code) {
        _controller.add(VpnStatus.disconnected);
        if (!started && !ready.isCompleted) {
          ready.completeError(
            Exception('sing-box exited (code $code) before connecting'),
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
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    await _outSub?.cancel();
    await _errSub?.cancel();
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    await _configFile?.delete().catchError((_) {});
    _configFile = null;
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    _process?.kill();
    _controller.close();
  }
}
