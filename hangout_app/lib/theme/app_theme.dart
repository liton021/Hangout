import 'package:flutter/material.dart';

/// Hangout visual language — "Flat & Colorful" (Messenger vibe).
///
/// Teal & aqua on a clean white canvas, per the UI/UX design system report:
///  * Teal ramp  : Deep Lagoon -> Dark Teal -> Teal -> Aqua Teal ->
///                  Bright Teal -> Aqua (brand primary)
///  * Light ramp : Soft Aqua, Pale Mint, Glass Mint, Pure White,
///                  Sage Gray, Deep Ink
///  * Depth      : soft teal-tinted shadows only — no heavy blur/glass
///  * Radii      : xs 8 · sm 12 · md 16 · lg 24 · full (pills, avatars, FAB)
class AppColors {
  AppColors._();

  // ── Teal ramp (brand primary) ────────────────────────────────────────────
  static const Color deepLagoon = Color(0xFF0B3D3A); // headlines, emphasis
  static const Color darkTeal = Color(0xFF075E54); // header text
  static const Color teal = Color(0xFF0D8A7D); // primary CTA
  static const Color aquaTeal = Color(0xFF12A897); // accents
  static const Color brightTeal = Color(0xFF18BFAC); // gradient start / FAB
  static const Color aqua = Color(0xFF43D8C5); // gradient pop

  // ── Aqua / light ramp (surfaces & tints) ─────────────────────────────────
  static const Color softAqua = Color(0xFF86ECE0); // highlights, tints
  static const Color paleMint = Color(0xFFE4FBF7); // selected states, outgoing
  static const Color glassMint = Color(0xFFF2FDFB); // canvas top
  static const Color pureWhite = Color(0xFFFFFFFF); // bubbles, cards, base
  static const Color sageGray = Color(0xFF6F8A85); // secondary text
  static const Color deepInk = Color(0xFF0C2F2B); // primary text

  // ── Dark-mode surfaces ───────────────────────────────────────────────────
  static const Color darkCanvas = Color(0xFF07211E); // deep lagoon canvas
  static const Color darkSurface = Color(0xFF123A34); // cards, bars
  static const Color darkBubbleIn = Color(0xFF1A3A35); // incoming bubble
  static const Color darkBubbleOut = Color(0xFF0E4A42); // outgoing (teal tint)

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF25D366); // presence / online
  static const Color danger = Color(0xFFFF4757); // end call / decline / error

  // ── Gradients ────────────────────────────────────────────────────────────
  /// Brand accent: teal -> aqua (135deg), used on buttons, avatars, FAB.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF18BFAC), Color(0xFF12A897)],
  );

  /// Call screens: deep lagoon canvas.
  static const LinearGradient callGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B3D3A), Color(0xFF07211E)],
  );

  /// Canvas (light): pale mint -> white.
  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF2FDFB), Color(0xFFFFFFFF)],
  );

  /// Canvas (dark): deep lagoon -> darker.
  static const LinearGradient darkCanvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B3D3A), Color(0xFF07211E)],
  );

  // ── Elevation (soft teal shadows, no blur) ───────────────────────────────
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x14075E54), // rgba(7,94,84,.08)
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> floatingShadow = [
    BoxShadow(
      color: Color(0x24075E54), // rgba(7,94,84,.14)
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      brightness: brightness,
      surface: dark ? AppColors.darkSurface : Colors.white,
    ).copyWith(
      primary: AppColors.teal,
      onPrimary: Colors.white,
      secondary: AppColors.aquaTeal,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: dark ? AppColors.darkSurface : Colors.white,
      onSurface: dark ? const Color(0xFFF0FBF9) : AppColors.deepInk,
      onSurfaceVariant: AppColors.sageGray,
      surfaceContainerLowest:
          dark ? const Color(0xFF06201D) : Colors.white,
      surfaceContainerLow:
          dark ? const Color(0xFF0F332E) : AppColors.glassMint,
      surfaceContainer:
          dark ? const Color(0xFF123A34) : const Color(0xFFEAF9F6),
      surfaceContainerHigh:
          dark ? const Color(0xFF16443D) : const Color(0xFFE0F5F1),
      primaryContainer:
          dark ? const Color(0xFF0F3D37) : AppColors.paleMint,
      onPrimaryContainer: dark ? AppColors.softAqua : AppColors.darkTeal,
      secondaryContainer:
          dark ? const Color(0xFF123A34) : AppColors.paleMint,
      onSecondaryContainer: dark ? AppColors.softAqua : AppColors.darkTeal,
      outlineVariant:
          dark ? const Color(0xFF1E4A44) : const Color(0xFFD9EFEA),
    );

    final textTheme = ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: dark ? const Color(0xFFEFFBF9) : AppColors.deepInk,
          displayColor: dark ? Colors.white : AppColors.deepLagoon,
        );

    final headlineColor = dark ? Colors.white : AppColors.deepLagoon;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.darkCanvas : AppColors.glassMint,
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: headlineColor,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: headlineColor,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: headlineColor,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.35),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: dark ? Colors.white : AppColors.deepInk,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: dark ? Colors.white : AppColors.deepInk,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkSurface : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: TextStyle(
          color: dark ? Colors.white38 : AppColors.sageGray.withOpacity(.85),
          fontWeight: FontWeight.w500,
        ),
        // Pill-shaped fields with a light teal hairline (report §6.4).
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(
            color: dark
                ? Colors.white.withOpacity(.12)
                : AppColors.teal.withOpacity(.22),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        prefixIconColor: scheme.primary,
        suffixIconColor: AppColors.sageGray,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.primary.withOpacity(.45),
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: const CircleBorder()),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.paleMint,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? AppColors.teal
                  : AppColors.sageGray,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? AppColors.teal
                  : AppColors.sageGray,
            )),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white.withOpacity(.07) : const Color(0xFFE8F4F1),
        thickness: 1,
      ),
      cardTheme: CardTheme(
        margin: EdgeInsets.zero,
        elevation: 1.5,
        color: dark ? AppColors.darkSurface : Colors.white,
        shadowColor: const Color(0x26075E54),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFEAF9F6) : AppColors.deepInk,
        contentTextStyle: TextStyle(color: dark ? AppColors.deepInk : Colors.white),
        actionTextColor: AppColors.softAqua,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: AppColors.softAqua,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );
  }
}
