import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/vpn_provider.dart';
import 'providers/language_provider.dart';
import 'providers/theme_provider.dart';
import 'services/tray_service.dart';
import 'services/vpn_service.dart';
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
          title: 'McQueen',
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
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    if (TrayService.isSupported) {
      windowManager.addListener(this);
      _initTray();
    }
  }

  Future<void> _initTray() async {
    final vpn = context.read<VpnProvider>();
    await _tray.init(
      onConnect: vpn.connect,
      onDisconnect: vpn.disconnect,
    );
    vpn.addListener(_onVpnChanged);
  }

  void _onVpnChanged() {
    final vpn = context.read<VpnProvider>();
    _tray.updateStatus(vpn.status);
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
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await windowManager.hide();
    }
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
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt_rounded),
            label: s.profilesTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_outlined),
            selectedIcon: const Icon(Icons.tune_rounded),
            label: s.settingsTab,
          ),
        ],
      ),
    );
  }
}
