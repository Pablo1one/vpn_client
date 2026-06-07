import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'providers/vpn_provider.dart';
import 'providers/language_provider.dart';
import 'providers/theme_provider.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'services/vpn_service.dart';
import 'screens/cdn_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/settings_screen.dart';
import 'l10n/strings.dart';
import 'theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VpnProvider()..init()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()..load()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
      ],
      child: Consumer2<LanguageProvider, ThemeProvider>(
        builder: (_, lang, themeP, __) => MaterialApp(
          title: 'LightningMcQueen',
          theme: themeP.isDark
              ? AppTheme.jacksonStorm()
              : AppTheme.lightningMcQueen(),
          locale: lang.locale,
          debugShowCheckedModeBanner: false,
          home: const _Shell(),
        ),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WindowListener {
  int _index = 0;
  final _tray = TrayService();

  static const _screens = [
    HomeScreen(),
    ProfilesScreen(),
    CdnScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    if (TrayService.isSupported) {
      windowManager.addListener(this);
      _initTray();
    }
    // при старте проверяем обновления и, если есть, предлагаем поставить
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
  }

  // Попап об обновлении: «Установить» / «Отмена». Отмена - апп работает дальше.
  Future<void> _maybePromptUpdate() async {
    UpdateInfo? info;
    try {
      info = await UpdateService().check();
    } catch (_) {
      return; // нет сети / нет релизов - молча выходим
    }
    if (info == null || !mounted) return;
    final s = L10n.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.updateAvailable),
        content: Text('v${info!.version}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.install)),
        ],
      ),
    );
    if (go == true && mounted) await _installUpdate(info);
  }

  Future<void> _installUpdate(UpdateInfo info) async {
    if (Platform.isWindows) {
      // неотменяемый индикатор на время загрузки; downloadAndRun сам выйдет (exit 0)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(children: [
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('Загрузка обновления…')),
          ]),
        ),
      );
      try {
        await UpdateService().downloadAndRun(info);
        return; // приложение закрылось внутри
      } catch (_) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    }
    // ведроид / фолбэк - открыть страницу релиза (apk) в браузере
    await launchUrl(Uri.parse(info.downloadUrl),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _initTray() async {
    final vpn = context.read<VpnProvider>();
    await _tray.init(
      onDisconnect: vpn.disconnect,
      onExit: _exitApp,
    );
    vpn.addListener(_onVpnChanged);
  }

  void _onVpnChanged() {
    final vpn = context.read<VpnProvider>();
    _tray.updateStatus(vpn.status);
  }

  Future<void> _exitApp() async {
    final vpn = context.read<VpnProvider>();
    if (vpn.isConnected) {
      try {
        await vpn.disconnect();
      } catch (_) {}
    }
    await _tray.destroy();
    exit(0);
  }

  @override
  void dispose() {
    if (TrayService.isSupported) {
      windowManager.removeListener(this);
      context.read<VpnProvider>().removeListener(_onVpnChanged);
      _tray.destroy();
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Minimize to tray instead of closing
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    final s = L10n.of(context);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.vpn_lock_outlined),
            selectedIcon: const Icon(Icons.vpn_lock_rounded),
            label: s.vpnTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.vpn_key_outlined),
            selectedIcon: const Icon(Icons.vpn_key_rounded),
            label: s.profilesTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.cloud_outlined),
            selectedIcon: const Icon(Icons.cloud_rounded),
            label: s.cdnTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: s.settingsTab,
          ),
        ],
      ),
    );
  }
}
