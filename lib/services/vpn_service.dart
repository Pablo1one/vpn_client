import 'dart:async';
import 'dart:io';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnService {
  Stream<VpnStatus> get statusStream;
  Future<void> connect(String singboxConfigJson);
  Future<void> disconnect();
  void dispose();

  factory VpnService.create() {
    if (Platform.isAndroid) return _AndroidVpnService();
    if (Platform.isIOS) return _IosVpnService();
    if (Platform.isWindows) return _WindowsVpnService();
    throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
  }
}

// ─── Android ────────────────────────────────────────────────────────────────
// Uses a MethodChannel to communicate with a Kotlin VpnService that runs
// sing-box via JNI (libbox.aar). See android/app/src/main/kotlin/VpnPlugin.kt.
class _AndroidVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  Future<void> connect(String singboxConfigJson) async {
    _controller.add(VpnStatus.connecting);
    // TODO: call platform channel 'vpn/connect' with singboxConfigJson
    // await const MethodChannel('vpn_client/vpn').invokeMethod('connect', singboxConfigJson);
    throw UnimplementedError('Android VPN: implement platform channel in VpnPlugin.kt');
  }

  @override
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    // TODO: call platform channel 'vpn/disconnect'
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() => _controller.close();
}

// ─── iOS ─────────────────────────────────────────────────────────────────────
// Uses a MethodChannel to start a NetworkExtension PacketTunnelProvider that
// runs sing-box. See ios/Runner/VpnPlugin.swift + ios/TunnelExtension/*.swift.
class _IosVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  Future<void> connect(String singboxConfigJson) async {
    _controller.add(VpnStatus.connecting);
    // TODO: call platform channel 'vpn_client/vpn' → 'connect'
    throw UnimplementedError('iOS VPN: implement NetworkExtension in VpnPlugin.swift');
  }

  @override
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() => _controller.close();
}

// ─── Windows ─────────────────────────────────────────────────────────────────
// Writes sing-box config to a temp file and spawns sing-box.exe as a subprocess.
// Requires: sing-box.exe placed in assets/bin/sing-box.exe (not committed).
// WinTun driver must be installed for TUN support.
class _WindowsVpnService implements VpnService {
  final _controller = StreamController<VpnStatus>.broadcast();
  Process? _process;

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  Future<void> connect(String singboxConfigJson) async {
    _controller.add(VpnStatus.connecting);
    try {
      // TODO: locate sing-box.exe from app bundle assets
      // final exePath = '${Directory.current.path}/data/flutter_assets/assets/bin/sing-box.exe';
      // final configFile = File('${Directory.systemTemp.path}/sbconfig.json');
      // await configFile.writeAsString(singboxConfigJson);
      // _process = await Process.start(exePath, ['run', '-c', configFile.path]);
      // _process!.exitCode.then((_) => _controller.add(VpnStatus.disconnected));
      // _controller.add(VpnStatus.connected);
      throw UnimplementedError('Windows VPN: place sing-box.exe in assets/bin/ and uncomment code above');
    } catch (e) {
      _controller.add(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _controller.add(VpnStatus.disconnecting);
    _process?.kill();
    _process = null;
    _controller.add(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    _process?.kill();
    _controller.close();
  }
}
