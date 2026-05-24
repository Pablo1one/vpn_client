import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'vpn_service.dart';

class TrayService with TrayListener {
  VoidCallback? _onConnect;
  VoidCallback? _onDisconnect;
  bool _ready = false;
  String? _iconPath;

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> init({
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) async {
    if (!isSupported) return;
    _onConnect = onConnect;
    _onDisconnect = onDisconnect;

    _iconPath = await _resolveIconPath();
    trayManager.addListener(this);
    await _apply(VpnStatus.disconnected);
    _ready = true;
  }

  Future<void> updateStatus(VpnStatus status) async {
    if (!_ready) return;
    await _apply(status);
  }

  Future<void> _apply(VpnStatus status) async {
    final connected = status == VpnStatus.connected;
    final busy =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;

    if (_iconPath != null) {
      await trayManager.setIcon(_iconPath!);
    }
    await trayManager.setToolTip(
        'VPN Client — ${connected ? 'Подключено' : 'Отключено'}');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
        label: connected ? 'Отключиться' : 'Подключиться',
        disabled: busy,
        onClick: (_) =>
            connected ? _onDisconnect?.call() : _onConnect?.call(),
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'Открыть',
        onClick: (_) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItem(
        label: 'Выход',
        onClick: (_) async {
          await windowManager.destroy();
        },
      ),
    ]));
  }

  Future<void> destroy() async {
    if (!_ready) return;
    trayManager.removeListener(this);
    await trayManager.destroy();
    _ready = false;
  }

  // ── TrayListener ────────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Extracts tray.ico from Flutter assets to a writable temp location.
  /// This works in both debug and release builds.
  static Future<String> _resolveIconPath() async {
    final data = await rootBundle.load('assets/icons/tray.ico');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vpn_tray.ico');
    if (!file.existsSync()) {
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }
}
