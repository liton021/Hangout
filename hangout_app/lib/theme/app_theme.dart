import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hangout visual language — "Telegram-inspired".
///
/// A faithful re-skin of Telegram's current look:
///   * Dark  : chat bg #17212B · panel bg #17212B · secondary #232E3C
///             incoming bubble #232E3C · outgoing bubble #2B5278
///             text #F5F5F5 · hint #708499 · link/accent #6AB3F3
///   * Light : canvas #FFFFFF · incoming #FFFFFF / #F1F1F1 · outgoing
///             #EFFDDE (Telegram green) · accent #3390EC
///   * The famous Telegram violet #8774E1 accents highlights.
///
/// Widgets should never reference the raw dark constants for surfaces or
/// text — always resolve them through [HangoutPalette] (`context.colors`)
/// so both themes render correctly.
class AppColors {
  AppColors._();

  // ── Telegram dark canvas & surfaces ─────────────────────────────────────
  static const Color canvas = Color(0xFF17212B); // window/chats bg
  static const Color canvasElevated = Color(0xFF17212B); // header/nav bg
  static const Color surface = Color(0xFF232E3C); // cards, groups, incoming
  static const Color surfaceAlt = Color(0xFF232E3C); // search field, chips
  static const Color surfaceMuted = Color(0xFF2B3A4A); // idle buttons, avatars
  static const Color divider = Color(0xFF101921); // hairlines
  static const Color chatOutBubble = Color(0xFF2B5278); // outgoing bubble

  // ── Accent ramp (Telegram) ──────────────────────────────────────────────
  static const Color accent = Color(0xFF3390EC); // primary blue
  static const Color accentDeep = Color(0xFF2E7FD9); // pressed
  static const Color accentSoft = Color(0xFF6AB3F3); // links, titles
  static const Color onAccentSoft = Color(0xFF0B1F33); // text on accentSoft
  static const Color accentSurface = Color(0xFF1E3A5F); // tinted container
  static const Color telegramViolet = Color(0xFF8774E1); // signature violet

  // ── Text (Telegram) ─────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFF708499); // hint
  static const Color textTertiary = Color(0xFF5F738C);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF5BDC8B); // presence / online
  static const Color danger = Color(0xFFE5634C); // end call / decline

  // ── Light canvas & surfaces (Telegram) ──────────────────────────────────
  static const Color lightCanvas = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F1F1);
  static const Color lightSurfaceMuted = Color(0xFFE9E9E9); // idle buttons
  static const Color lightDivider = Color(0xFFDADCE0);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF707579);
  static const Color lightTextTertiary = Color(0xFF9AA0A6);
  static const Color lightAccentSurface = Color(0xFFE3F2FD); // tinted
  static const Color lightChatOutBubble = Color(0xFFEFFDDE); // outgoing green

  // ── Gradients ────────────────────────────────────────────────────────────
  /// Brand accent: blue -> deep blue (135deg) for FABs, send, avatars.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F8DF8), Color(0xFF2563EB)],
  );

  /// Signature blue→violet sweep (Telegram's accent + violet).
  static const LinearGradient vividGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3390EC), Color(0xFF8774E1)],
  );

  /// Outgoing message bubbles: solid Telegram blue in dark, solid green in
  /// light (Telegram does NOT use gradient bubbles by default).
  static const LinearGradient chatBubbleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B5278), Color(0xFF2B5278)],
  );

  /// Call screens: near-black with a faint blue lift.
  static const LinearGradient callGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF12182B), Color(0xFF07070A)],
  );

  /// Canvas (dark): flat Telegram window bg.
  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF17212B), Color(0xFF17212B)],
  );

  /// Canvas (light fallback).
  static const LinearGradient lightCanvasGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  /// Chat canvas (dark): Telegram's flat #17212B.
  static const LinearGradient chatBackgroundDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF17212B), Color(0xFF17212B)],
  );

  /// Chat canvas (light): Telegram's white chat.
  static const LinearGradient chatBackgroundLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  // ── Avatar gradients ────────────────────────────────────────────────────
  /// Deterministic per-contact gradient set (Telegram-style color avatars).
  /// Picked by hashing the name so the same person always gets the same
  /// color, on every device.
  static const List<LinearGradient> avatarGradients = [
    LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3390EC), Color(0xFF2E7FD9)]), // blue
    LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8774E1), Color(0xFF6D5CE8)]), // violet
    LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE56590), Color(0xFFC94E7D)]), // pink
    LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF7A62B), Color(0xFFEA8A13)]), // amber
    LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3BCA6E), Color(0xFF2BA651)]), // green
    LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF40B9CE), Color(0xFF2E97AD)]), // cyan
  ];

  /// Picks a stable avatar gradient for [seed] (usually the user's name).
  /// Summing code units keeps the choice identical across devices and runs.
  static LinearGradient avatarGradientFor(String seed) {
    final sum = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return avatarGradients[sum % avatarGradients.length];
  }

  // ── Elevation ────────────────────────────────────────────────────────────
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> floatingShadow = [
    BoxShadow(
      color: Color(0x8A000000),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  /// Glow under the blue FAB / send button.
  static const List<BoxShadow> accentGlow = [
    BoxShadow(
      color: Color(0x593B82F6),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

}

/// Corner radii used across the design.
class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// Theme-aware semantic palette for surfaces, text and tinted accents.
///
/// Everything that flips between the dark and light designs lives here.
/// Resolve it once per build with `context.colors` — brand constants that
/// look identical on both canvases (`AppColors.accent`, `success`, `danger`,
/// `brandGradient`…) can still be used directly.
class HangoutPalette extends ThemeExtension<HangoutPalette> {
  const HangoutPalette({
    required this.canvas,
    required this.canvasElevated,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceMuted,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.accentSurface,
    required this.canvasGradient,
    required this.chatBackground,
  });

  final Color canvas; // screen background
  final Color canvasElevated; // nav bar, composer bar
  final Color surface; // cards, list groups, incoming bubbles
  final Color surfaceAlt; // search field, chips, inset fill
  final Color surfaceMuted; // idle buttons, avatar placeholders
  final Color divider; // hairlines
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Periwinkle headlines/links in dark; a deeper readable blue (#2563EB)
  /// in light, where periwinkle would wash out on the bright canvas.
  final Color accentSoft;

  /// Content drawn on top of [accentSoft] (e.g. the Connect button label).
  final Color onAccentSoft;

  /// Softly tinted blue container behind accent icons in sheets.
  final Color accentSurface;

  /// Full-screen backdrop behind splash / auth screens.
  final Gradient canvasGradient;

  /// Conversation backdrop behind the message list.
  final Gradient chatBackground;

  static const HangoutPalette dark = HangoutPalette(
    canvas: AppColors.canvas,
    canvasElevated: AppColors.canvasElevated,
    surface: AppColors.surface,
    surfaceAlt: AppColors.surfaceAlt,
    surfaceMuted: AppColors.surfaceMuted,
    divider: AppColors.divider,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    accentSoft: AppColors.accentSoft,
    onAccentSoft: AppColors.onAccentSoft,
    accentSurface: AppColors.accentSurface,
    canvasGradient: AppColors.canvasGradient,
    chatBackground: AppColors.chatBackgroundDark,
  );

  static const HangoutPalette light = HangoutPalette(
    canvas: AppColors.lightCanvas,
    canvasElevated: AppColors.lightSurface,
    surface: AppColors.lightSurface,
    surfaceAlt: AppColors.lightSurfaceAlt,
    surfaceMuted: AppColors.lightSurfaceMuted,
    divider: AppColors.lightDivider,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    accentSoft: AppColors.accentDeep,
    onAccentSoft: Colors.white,
    accentSurface: AppColors.lightAccentSurface,
    canvasGradient: AppColors.lightCanvasGradient,
    chatBackground: AppColors.chatBackgroundLight,
  );

  @override
  HangoutPalette copyWith({
    Color? canvas,
    Color? canvasElevated,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceMuted,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accentSoft,
    Color? onAccentSoft,
    Color? accentSurface,
    Gradient? canvasGradient,
    Gradient? chatBackground,
  }) {
    return HangoutPalette(
      canvas: canvas ?? this.canvas,
      canvasElevated: canvasElevated ?? this.canvasElevated,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccentSoft: onAccentSoft ?? this.onAccentSoft,
      accentSurface: accentSurface ?? this.accentSurface,
      canvasGradient: canvasGradient ?? this.canvasGradient,
      chatBackground: chatBackground ?? this.chatBackground,
    );
  }

  @override
  HangoutPalette lerp(ThemeExtension<HangoutPalette>? other, double t) {
    if (other is! HangoutPalette) return this;
    return HangoutPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasElevated: Color.lerp(canvasElevated, other.canvasElevated, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccentSoft: Color.lerp(onAccentSoft, other.onAccentSoft, t)!,
      accentSurface: Color.lerp(accentSurface, other.accentSurface, t)!,
      canvasGradient:
          Gradient.lerp(canvasGradient, other.canvasGradient, t)!,
      chatBackground:
          Gradient.lerp(chatBackground, other.chatBackground, t)!,
    );
  }
}

/// Convenient, rebuild-safe access to the active [HangoutPalette].
extension HangoutThemeX on BuildContext {
  HangoutPalette get colors =>
      Theme.of(this).extension<HangoutPalette>() ?? HangoutPalette.dark;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    final canvas = dark ? AppColors.canvas : AppColors.lightCanvas;
    final surface = dark ? AppColors.surface : AppColors.lightSurface;
    final surfaceAlt = dark ? AppColors.surfaceAlt : AppColors.lightSurfaceAlt;
    final divider = dark ? AppColors.divider : AppColors.lightDivider;
    final textPrimary =
        dark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        dark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    final titleColor = dark ? AppColors.accentSoft : AppColors.accentDeep;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentSoft,
      onSecondary: AppColors.onAccentSoft,
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: canvas,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerHighest:
          dark ? AppColors.surfaceMuted : AppColors.lightSurfaceMuted,
      primaryContainer: dark ? AppColors.accentSurface : AppColors.lightAccentSurface,
      onPrimaryContainer: dark ? AppColors.accentSoft : AppColors.accentDeep,
      secondaryContainer: dark ? AppColors.surfaceAlt : surfaceAlt,
      onSecondaryContainer: textPrimary,
      errorContainer: dark ? const Color(0xFF3A1414) : const Color(0xFFFDE2E2),
      onErrorContainer: AppColors.danger,
      outline: divider,
      outlineVariant: divider,
    );

    final base = ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: textPrimary,
          displayColor: textPrimary,
        );

    final textTheme = base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 27,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.35,
        color: textSecondary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.3,
        color: textSecondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: textSecondary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[
        dark ? HangoutPalette.dark : HangoutPalette.light,
      ],
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: textPrimary, size: 24),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: titleColor,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        hintStyle: TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w400,
          fontSize: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accent.withOpacity(.4),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // Periwinkle reads well on charcoal; on the light canvas we need
          // the deeper blue to stay legible.
          foregroundColor: dark ? AppColors.accentSoft : AppColors.accentDeep,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: divider),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimary,
          shape: const CircleBorder(),
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      cardTheme: CardTheme(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        subtitleTextStyle: TextStyle(color: textSecondary, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : surfaceMutedOf(dark)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.accent
                : textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? AppColors.surfaceAlt : AppColors.lightTextPrimary,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.accentSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        showDragHandle: true,
        dragHandleColor:
            dark ? AppColors.surfaceMuted : const Color(0xFFC9CFD9),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? AppColors.surfaceMuted : const Color(0xFF1F2430),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: TextStyle(
          color: dark ? AppColors.textPrimary : Colors.white,
          fontSize: 12,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );
  }

  static Color surfaceMutedOf(bool dark) =>
      dark ? AppColors.surfaceMuted : AppColors.lightDivider;
}
