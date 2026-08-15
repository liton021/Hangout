import 'package:flutter/material.dart';

/// Visual language for Hangout: calm indigo, warm surfaces and high-contrast
/// typography. All colours have light and dark counterparts through the
/// generated Material 3 colour schemes.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF5B5CE2);
  static const Color primaryDark = Color(0xFF4546C8);
  static const Color accent = Color(0xFF7C6CF2);
  static const Color coral = Color(0xFFFF7A6E);
  static const Color danger = Color(0xFFE84D5B);
  static const Color success = Color(0xFF24A77B);
  static const Color ink = Color(0xFF171725);
  static const Color canvas = Color(0xFFF7F7FB);
  static const Color darkCanvas = Color(0xFF0F1018);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5B5CE2), Color(0xFF7C6CF2)],
  );

  static const LinearGradient callGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF29284D), Color(0xFF11121D)],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: dark ? const Color(0xFF181923) : Colors.white,
    ).copyWith(
      primary: dark ? const Color(0xFFB9B5FF) : AppColors.primary,
      secondary: dark ? const Color(0xFFC9C5FF) : AppColors.accent,
      error: AppColors.danger,
      surfaceContainerLowest:
          dark ? const Color(0xFF12131C) : const Color(0xFFFCFCFE),
      surfaceContainerLow:
          dark ? const Color(0xFF1C1D28) : const Color(0xFFF2F2F8),
      surfaceContainer:
          dark ? const Color(0xFF22232F) : const Color(0xFFECECF4),
      surfaceContainerHigh:
          dark ? const Color(0xFF292A37) : const Color(0xFFE6E6EF),
    );

    final textTheme = ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: dark ? const Color(0xFFF4F2FA) : AppColors.ink,
          displayColor: dark ? Colors.white : AppColors.ink,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.35),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.35),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.darkCanvas : AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: dark ? Colors.white : AppColors.ink,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: dark ? Colors.white : AppColors.ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1C1D28) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: dark ? Colors.white.withOpacity(.06) : const Color(0xFFE8E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withOpacity(.4),
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: const CircleBorder()),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF171821) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(dark ? .22 : .12),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            )),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white.withOpacity(.06) : const Color(0xFFECECF2),
        thickness: 1,
      ),
      cardTheme: CardTheme(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFEEEEF7) : AppColors.ink,
        contentTextStyle: TextStyle(color: dark ? AppColors.ink : Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );
  }
}
