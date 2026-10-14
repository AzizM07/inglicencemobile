import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens repris directement du :root de style.css
class AppColors {
  static const navy = Color(0xFF16193A);
  static const navySoft = Color(0xFF1D2148);
  static const ink = Color(0xFF20234A);
  static const blue = Color(0xFF3F5BF6);
  static const blueSoft = Color(0xFFE7EBFD);
  static const gray = Color(0xFF6B7194);
  static const graySoft = Color(0xFF8A90AD);
  static const line = Color(0xFFE9ECF7);
  static const field = Color(0xFFF5F7FC);
  static const white = Color(0xFFFFFFFF);

  static const ok = Color(0xFF0F9D63);
  static const warn = Color(0xFFB8860B);
  static const bad = Color(0xFFD0453B);

  // Teintes violettes (page score-e)
  static const violetTint = Color(0xFFEEF2FD);
  static const violetTint2 = Color(0xFFF5F7FC);
  static const violetBorder = Color(0xFFE6E9F5);
}

/// Rayons (--rxl / --rlg / --rmd)
class AppRadius {
  static const xl = 24.0;
  static const lg = 18.0;
  static const md = 12.0;
}

/// Dégradé du CTA principal (boutons bleus du site)
const kBlueButtonGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF5A74FF), AppColors.blue],
);

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        primary: AppColors.blue,
        surface: AppColors.white,
        onSurface: AppColors.ink,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

    return base.copyWith(
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.field,
        hintStyle: const TextStyle(color: AppColors.graySoft, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _border(AppColors.line),
        enabledBorder: _border(AppColors.line),
        focusedBorder: _border(AppColors.blue, width: 1.6),
      ),
    );
  }

  static OutlineInputBorder _border(Color c, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: c, width: width),
      );

  /// Police monospace pour les chiffres (Space Mono du site).
  static TextStyle mono({
    double size = 18,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
  }) =>
      GoogleFonts.spaceMono(fontSize: size, fontWeight: weight, color: color);
}