import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF01060B);
  static const Color surface = Color(0xFF071018);
  static const Color surface2 = Color(0xFF0C1720);
  static const Color border = Color(0xFF172631);
  static const Color red = Color(0xFFFF262B);
  static const Color darkRed = Color(0xFF5B0A0D);
  static const Color green = Color(0xFF35D34A);
  static const Color amber = Color(0xFFFFB000);
  static const Color gray = Color(0xFF8C99A3);
  static const Color textSecondary = Color(0xFFA5AFB7);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: red,
          brightness: Brightness.dark,
          primary: red,
          surface: surface,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: surface2,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: gray),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: red, width: 1.4),
          ),
        ),
      );
}
