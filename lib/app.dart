import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/vpn_provider.dart';
import 'screens/home_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VpnProvider()..init(),
      child: MaterialApp(
        title: 'VPN Client',
        theme: AppTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: const _Shell(),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    ProfilesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.vpn_lock_outlined),
            selectedIcon: Icon(Icons.vpn_lock_rounded),
            label: 'VPN',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt_rounded),
            label: 'Profiles',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
