import 'package:flutter/material.dart';

/// Palette e stile grafico dell'app.
///
/// [primary], [primaryDark] e [accentBg] non sono più valori fissi: vengono
/// impostati una sola volta all'avvio, a partire dal colore del cliente
/// dichiarato in assets/client_config.json (vedi [applyBrandColor], chiamato
/// da main.dart). Così ogni build per un nuovo cliente ha automaticamente
/// una palette coerente con il proprio colore aziendale, senza toccare
/// il codice.
class AppColors {
  AppColors._();

  static Color primary = const Color(0xFF185FA5);
  static Color primaryDark = const Color(0xFF0C447C);
  static Color accentBg = const Color(0xFFE6F1FB);

  static const Color success = Color(0xFF3B6D11);
  static const Color danger = Color(0xFFC0392B);
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF5F6F8);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5F5E5A);
  static const Color border = Color(0xFFE0E0E0);

  /// Deriva [primaryDark] e [accentBg] dal colore del cliente, in modo che
  /// una singola tinta hex nel JSON sia sufficiente per una palette
  /// professionale e coerente (nessun designer necessario per ogni cliente).
  static void applyBrandColor(String hex) {
    final base = _fromHex(hex);
    primary = base;

    final hsl = HSLColor.fromColor(base);
    primaryDark = hsl
        .withLightness((hsl.lightness * 0.65).clamp(0.0, 1.0))
        .toColor();
    accentBg = hsl
        .withLightness(0.94)
        .withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _fromHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
