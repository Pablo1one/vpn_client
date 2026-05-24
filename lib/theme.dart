import 'package:flutter/material.dart';

class AppTheme {
  static const _green = Color(0xFF00E676);

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: _green,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        cardTheme: const CardTheme(
          color: Color(0xFF1C1C1C),
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF161616),
          elevation: 0,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F0F),
          elevation: 0,
          centerTitle: true,
        ),
      );
}
