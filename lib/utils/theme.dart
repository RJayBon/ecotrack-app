import 'package:flutter/material.dart';

/// EcoTrack brand palette and shared theming.
///
/// Every value below was checked against the WCAG 2.1 contrast minimums
/// (4.5:1 for normal text, 3:1 for large text and meaningful graphics).
/// Use the ratio comments to pick the right token - in particular, never put
/// text on [primaryLight] or use the "decorative" tokens as a text colour.
class AppColors {
  const AppColors._();

  /// Primary brand green. White text on it: 5.13:1.
  static const primary = Color(0xFF2E7D32);

  /// Darker brand green, for gradient ends and emphasised text.
  /// White text on it: 7.87:1.
  static const primaryDark = Color(0xFF1B5E20);

  /// DECORATIVE ONLY - avatars, icon washes, gradient art.
  /// White text on it is only 2.36:1, so it must never sit behind text.
  static const primaryLight = Color(0xFF66BB6A);

  /// Teal accent, used for icons and small status pills.
  /// On white: 6.61:1. On its own 8% tint: 5.87:1.
  ///
  /// Was `0xFF00BFA5`, which measured 2.33:1 on white - a clear AA failure
  /// everywhere it was used as a foreground colour.
  static const accent = Color(0xFF00695C);

  /// Amber, used for icons and markers (never as text).
  /// On white: 4.24:1, on its own 12% tint: 3.65:1 - comfortably above the
  /// 3:1 non-text threshold.
  ///
  /// Was `0xFFF9A825`, which measured 1.97:1 on white - invisible to many
  /// users, and below even the non-text minimum.
  static const warning = Color(0xFFB26A00);

  /// Error red. On white: 5.62:1, on its own 8% tint: 4.96:1.
  static const danger = Color(0xFFC62828);

  static const background = Color(0xFFF4F8F4);
  static const surface = Color(0xFFFFFFFF);

  /// Body copy. On white: 14.03:1.
  static const textDark = Color(0xFF1B2A1D);

  /// Secondary copy. On white: 5.34:1, on [background]: 4.98:1.
  static const textMuted = Color(0xFF5F6F60);

  /// Hairline border used by [EcoCard] and list separators.
  static const cardBorder = Color(0xFFE3ECE4);

  /// Fill for inputs and neutral containers.
  static const fieldFill = Color(0xFFF0F5F0);

  /// Wash behind avatar initials and list leading icons.
  static const avatarTint = Color(0xFFE3F2E4);

  /// Standard gradient for hero cards and banners.
  ///
  /// Both stops are dark enough for white body text (5.13:1 and 7.87:1).
  /// The old gradient ended on [primaryLight], where 12-15px white labels
  /// measured 2.36:1.
  static const heroGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        secondary: AppColors.accent,
      ),
      scaffoldBackgroundColor: AppColors.background,
      // NOTE: no `fontFamily` here on purpose. The previous code pinned
      // 'Roboto' while declaring no font asset, so the app silently rendered
      // a different typeface on every platform (system font on Android,
      // something else on iOS/web). Leaving it unset means each platform uses
      // its own carefully tuned default. Declare assets/fonts and a `fonts:`
      // block in pubspec.yaml if you want true cross-platform Roboto.
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.textDark,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: AppColors.primary.withValues(alpha: 0.14),
        backgroundColor: AppColors.fieldFill,
        labelStyle: const TextStyle(color: AppColors.textDark),
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.cardBorder),
    );
  }
}
