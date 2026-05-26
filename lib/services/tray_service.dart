import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'vpn_service.dart';
import 'tray_icon_painter.dart';

class TrayService with TrayListener {
  VoidCallback? _onDisconnect;
  VoidCallback? _onExit;
  bool _ready = false;

  // Pre-generated icon paths, keyed by variant
  final _icons = <TrayIconVariant, String>{};
  TrayIconVariant _current = TrayIconVariant.none;

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> init({
    required VoidCallback onDisconnect,
    required VoidCallback onExit,
  }) async {
    if (!isSupported) return;
    _onDisconnect = onDisconnect;
    _onExit = onExit;

    trayManager.addListener(this);

    // Pre-generate all 3 icon variants
    final dir = (await getTemporaryDirectory()).path;
    for (final v in TrayIconVariant.values) {
      _icons[v] = await TrayIconPainter.buildAndSave(v, dir);
    }

    await _apply(VpnStatus.disconnected);
    _ready = true;
  }

  Future<void> updateStatus(VpnStatus status) async {
    if (!_ready) return;
    await _apply(status);
  }

  Future<void> _apply(VpnStatus status) async {
    final variant = _variantFor(status);
    final connected = status == VpnStatus.connected;
    final busy =
        status == VpnStatus.connecting || status == VpnStatus.disconnecting;

    // Only swap icon when variant actually changes
    if (variant != _current || !_ready) {
      _current = variant;
      final path = _icons[variant];
      if (path != null) await trayManager.setIcon(path);
    }

    final tooltip = connected ? 'McQueen VPN — Подключено' : 'McQueen VPN — Отключено';
    await trayManager.setToolTip(tooltip);

    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
        label: 'Открыть',
        onClick: (_) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'Отключить',
        disabled: !connected || busy,
        onClick: (_) => _onDisconnect?.call(),
      ),
      MenuItem.separator(),
      MenuItem(
        label: 'Выход',
        onClick: (_) => _onExit?.call(),
      ),
    ]));
  }

  TrayIconVariant _variantFor(VpnStatus s) => switch (s) {
        VpnStatus.connected => TrayIconVariant.connected,
        VpnStatus.error => TrayIconVariant.error,
        VpnStatus.disconnecting => _current, // keep current while animating
        _ => TrayIconVariant.none,
      };

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
}
