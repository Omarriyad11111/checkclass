import 'package:flutter/material.dart';

/// Zentrale Design-Definition. Farben sind auf ausreichenden Kontrast
/// (WCAG AA) ausgelegt und werden zusätzlich immer mit Icon/Text kombiniert,
/// nie nur über die Farbe vermittelt.
class AppTheme {
  AppTheme._();

  static const Color understood = Color(0xFF1B7F3B);
  static const Color notUnderstood = Color(0xFFC62828);
  static const Color _seed = Color(0xFF3A5BD9);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: scheme.onSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
