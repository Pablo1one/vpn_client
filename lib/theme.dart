import 'package:flutter/material.dart';

class AppTheme {
  // Jackson Storm palette: near-black navy + electric cyan
  static const cyan = Color(0xFF00D4FF);
  static const purple = Color(0xFF9340FF); // connected state glow
  static const bg = Color(0xFF060610);
  static const surface = Color(0xFF0E0E1E);
  static const card = Color(0xFF141428);
  static const navBar = Color(0xFF0A0A1C);

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: cyan,
          onPrimary: Colors.black,
          secondary: const Color(0xFF0090B8),
          surface: surface,
          onSurface: const Color(0xFFE0E8F0),
          error: const Color(0xFFFF4560),
          outline: const Color(0xFF2A2A4A),
        ),
        scaffoldBackgroundColor: bg,
        cardTheme: const CardThemeData(
          color: card,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: navBar,
          elevation: 0,
          indicatorColor: cyan.withOpacity(0.15),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: cyan);
            }
            return const IconThemeData(color: Color(0xFF5A6070));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  color: cyan, fontSize: 11, fontWeight: FontWeight.w600);
            }
            return const TextStyle(color: Color(0xFF5A6070), fontSize: 11);
          }),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFFE0E8F0),
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: cyan),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? cyan : null),
          trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? cyan.withOpacity(0.3)
                  : null),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: cyan,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: cyan),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF1E1E38),
          thickness: 1,
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: Color(0xFFD0D8E8),
          subtitleTextStyle: TextStyle(color: Color(0xFF5A6480), fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cyan, width: 1.5),
          ),
          hintStyle: const TextStyle(color: Color(0xFF3A4060)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surface,
          selectedColor: cyan.withOpacity(0.15),
          side: const BorderSide(color: Color(0xFF2A2A4A)),
          labelStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: cyan,
          foregroundColor: Colors.black,
        ),
      );
}
