import 'package:flutter/material.dart';

// ── Semantic color tokens, доступны через context.ac ─────────────────────────

class AppColors extends ThemeExtension<AppColors> {
  final Color primary;       // главный акцент
  final Color secondary;     // вторичный акцент (подключено / glow)
  final Color upload;        // цвет стрелки upload в скорости
  final Color bg;
  final Color surface;
  final Color card;
  final Color navBar;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderFaint;
  final Color btnInactive;
  final Color btnActive;
  final Color avatarBg;

  const AppColors({
    required this.primary,
    required this.secondary,
    required this.upload,
    required this.bg,
    required this.surface,
    required this.card,
    required this.navBar,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderFaint,
    required this.btnInactive,
    required this.btnActive,
    required this.avatarBg,
  });

  @override
  AppColors copyWith({
    Color? primary, Color? secondary, Color? upload,
    Color? bg, Color? surface, Color? card, Color? navBar,
    Color? textPrimary, Color? textSecondary, Color? textMuted,
    Color? border, Color? borderFaint, Color? btnInactive,
    Color? btnActive, Color? avatarBg,
  }) =>
      AppColors(
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        upload: upload ?? this.upload,
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        card: card ?? this.card,
        navBar: navBar ?? this.navBar,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        border: border ?? this.border,
        borderFaint: borderFaint ?? this.borderFaint,
        btnInactive: btnInactive ?? this.btnInactive,
        btnActive: btnActive ?? this.btnActive,
        avatarBg: avatarBg ?? this.avatarBg,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      upload: Color.lerp(upload, other.upload, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFaint: Color.lerp(borderFaint, other.borderFaint, t)!,
      btnInactive: Color.lerp(btnInactive, other.btnInactive, t)!,
      btnActive: Color.lerp(btnActive, other.btnActive, t)!,
      avatarBg: Color.lerp(avatarBg, other.avatarBg, t)!,
    );
  }
}

// Удобный доступ из любого виджета
extension AppColorsX on BuildContext {
  AppColors get ac => Theme.of(this).extension<AppColors>()!;
}

// ── Jackson Storm (тёмная тема) ───────────────────────────────────────────────

const _jsColors = AppColors(
  primary:       Color(0xFF00D4FF),  // неоновый cyan
  secondary:     Color(0xFF9B4DFF),  // неоновый фиолетовый
  upload:        Color(0xFF7ECFFF),  // светлый cyan (нет жёлтого)
  bg:            Color(0xFF07081A),  // почти чёрный синий
  surface:       Color(0xFF0C0D20),
  card:          Color(0xFF101124),
  navBar:        Color(0xFF090A1C),
  textPrimary:   Color(0xFFE4EEF8),
  textSecondary: Color(0xFF7A90A8),
  textMuted:     Color(0xFF3E4E62),
  border:        Color(0xFF1C1E3A),
  borderFaint:   Color(0xFF141526),
  btnInactive:   Color(0xFF131628),
  btnActive:     Color(0xFF243040),
  avatarBg:      Color(0xFF0E1020),
);

// ── Lightning McQueen (светлая тема) ─────────────────────────────────────────

const _mcColors = AppColors(
  primary:       Color(0xFFCC1100),  // красный McQueen #95
  secondary:     Color(0xFFFF2200),  // неоновый красный = цвет подключено + свечение
  upload:        Color(0xFFFFCC00),  // жёлтый для upload
  bg:            Color(0xFFF9F5F4),  // тёплый белый
  surface:       Color(0xFFFFFFFF),
  card:          Color(0xFFFFFFFF),
  navBar:        Color(0xFFFFEEEC),
  textPrimary:   Color(0xFF1A1A1A),
  textSecondary: Color(0xFF5A5A5A),
  textMuted:     Color(0xFF9A9A9A),
  border:        Color(0xFFEED8D6),
  borderFaint:   Color(0xFFF4E8E6),
  btnInactive:   Color(0xFFE8DCA8),  // бледно-жёлтый = нет профиля
  btnActive:     Color(0xFFFFCC00),  // McQueen-жёлтый = есть профиль, не подключено
  avatarBg:      Color(0xFFFFF0EE),
);

// ── AppTheme ──────────────────────────────────────────────────────────────────

class AppTheme {
  // Jackson Storm - статические константы (для обратной совместимости)
  static const cyan   = Color(0xFF00D4FF);
  static const purple = Color(0xFF9B4DFF);

  static ThemeData jacksonStorm() => _buildDark(_jsColors);
  static ThemeData lightningMcQueen() => _buildLight(_mcColors);

  static ThemeData _buildDark(AppColors c) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        extensions: [c],
        colorScheme: ColorScheme.dark(
          primary: c.primary,
          onPrimary: Colors.black,
          secondary: c.secondary,
          surface: c.surface,
          onSurface: c.textPrimary,
          error: const Color(0xFFFF4560),
          outline: c.border,
        ),
        scaffoldBackgroundColor: c.bg,
        cardTheme: CardThemeData(
          color: c.card,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: c.navBar,
          elevation: 0,
          indicatorColor: c.primary.withValues(alpha: 0.15),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: c.primary);
            }
            return IconThemeData(color: c.textMuted);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(
                  color: c.primary, fontSize: 11, fontWeight: FontWeight.w600);
            }
            return TextStyle(color: c.textMuted, fontSize: 11);
          }),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: c.bg,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: c.primary),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.primary : null),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? c.primary.withValues(alpha: 0.3)
                  : null),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        textButtonTheme:
            TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.primary)),
        dividerTheme: DividerThemeData(color: c.border, thickness: 1),
        listTileTheme: ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: c.textPrimary,
          subtitleTextStyle: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: c.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.primary, width: 1.5),
          ),
          hintStyle: TextStyle(color: c.textMuted),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: c.surface,
          selectedColor: c.primary.withValues(alpha: 0.15),
          side: BorderSide(color: c.border),
          labelStyle: const TextStyle(fontSize: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: c.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: c.primary,
          foregroundColor: Colors.black,
        ),
      );

  static ThemeData _buildLight(AppColors c) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        extensions: [c],
        colorScheme: ColorScheme.light(
          primary: c.primary,
          onPrimary: Colors.white,
          secondary: c.secondary,
          surface: c.surface,
          onSurface: c.textPrimary,
          error: const Color(0xFFCC0000),
          outline: c.border,
        ),
        scaffoldBackgroundColor: c.bg,
        cardTheme: CardThemeData(
          color: c.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shadowColor: c.primary.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.border),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: c.navBar,
          elevation: 0,
          indicatorColor: c.primary.withValues(alpha: 0.12),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: c.primary);
            }
            return IconThemeData(color: c.textMuted);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(
                  color: c.primary, fontSize: 11, fontWeight: FontWeight.w600);
            }
            return TextStyle(color: c.textMuted, fontSize: 11);
          }),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: c.navBar,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: c.primary),
          surfaceTintColor: Colors.transparent,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.primary : null),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? c.primary.withValues(alpha: 0.3)
                  : null),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        textButtonTheme:
            TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.primary)),
        dividerTheme: DividerThemeData(color: c.border, thickness: 1),
        listTileTheme: ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: c.textPrimary,
          subtitleTextStyle: TextStyle(color: c.textSecondary, fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: c.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: c.primary, width: 1.5),
          ),
          hintStyle: TextStyle(color: c.textMuted),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: c.surface,
          selectedColor: c.primary.withValues(alpha: 0.12),
          side: BorderSide(color: c.border),
          labelStyle: const TextStyle(fontSize: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: c.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
        ),
      );
}
