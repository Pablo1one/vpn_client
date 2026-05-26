import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeName { jacksonStorm, lightningMcQueen }

class ThemeProvider extends ChangeNotifier {
  AppThemeName _theme = AppThemeName.lightningMcQueen;

  AppThemeName get themeName => _theme;
  bool get isDark => _theme == AppThemeName.jacksonStorm;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('appTheme') ?? 'mcqueen';
    _theme = stored == 'jackson'
        ? AppThemeName.jacksonStorm
        : AppThemeName.lightningMcQueen;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeName t) async {
    if (_theme == t) return;
    _theme = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appTheme', t == AppThemeName.jacksonStorm ? 'jackson' : 'mcqueen');
    notifyListeners();
  }
}
