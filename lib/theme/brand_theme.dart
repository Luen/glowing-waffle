import 'package:flutter/material.dart';

/// Waffle's palette (docs/branding.md).
///
/// The same values are in `COLORS` in scripts/branding/export.mjs (icons and
/// artwork), Android's `res/values/colors.xml`, iOS's `LaunchBackground`
/// colour set and `web/index.html` / `web/manifest.json`. Change them together.
abstract final class BrandColors {
  /// Icon background, top of its gradient.
  static const nightRaised = Color(0xFF2B2340);

  /// Icon background, bottom of its gradient; the dark theme's surface.
  static const nightDeep = Color(0xFF15111D);

  /// Ink: text on light surfaces.
  static const night = Color(0xFF1E1829);

  /// Unlit waffle cells.
  static const grid = Color(0xFF3A3052);

  /// Lit bars, top of their gradient.
  static const honeyLight = Color(0xFFFFD480);

  /// The glow; the dark theme's primary.
  static const honey = Color(0xFFF7A23B);

  /// Lit bars, bottom of their gradient.
  static const honeyDeep = Color(0xFFF39231);

  /// Honey darkened until white text on it passes WCAG AA; the light theme's
  /// primary.
  static const toast = Color(0xFF8A4B00);

  /// The light theme's surface.
  static const cream = Color(0xFFFFF8EF);
}

/// Light scheme: toasted honey on cream, night ink.
final ColorScheme brandLightScheme = ColorScheme.fromSeed(
  seedColor: BrandColors.honey,
  brightness: Brightness.light,
).copyWith(
  primary: BrandColors.toast,
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFFFDDB3),
  onPrimaryContainer: const Color(0xFF2C1600),
  secondary: const Color(0xFF65558A),
  onSecondary: Colors.white,
  secondaryContainer: const Color(0xFFEADDFF),
  onSecondaryContainer: const Color(0xFF221A3A),
  surface: BrandColors.cream,
  onSurface: BrandColors.night,
  onSurfaceVariant: const Color(0xFF4C4357),
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: const Color(0xFFFBF2E6),
  surfaceContainer: const Color(0xFFF6ECDF),
  surfaceContainerHigh: const Color(0xFFF1E5D6),
  surfaceContainerHighest: const Color(0xFFEBDECD),
  outline: const Color(0xFF7D7388),
  outlineVariant: const Color(0xFFD9CCBC),
  inverseSurface: BrandColors.night,
  onInverseSurface: BrandColors.cream,
  inversePrimary: BrandColors.honey,
  surfaceTint: Colors.transparent,
);

/// Dark scheme: glowing honey on night, as on the app icon.
final ColorScheme brandDarkScheme = ColorScheme.fromSeed(
  seedColor: BrandColors.honey,
  brightness: Brightness.dark,
).copyWith(
  primary: BrandColors.honey,
  onPrimary: const Color(0xFF2B1700),
  primaryContainer: const Color(0xFF6B3D00),
  onPrimaryContainer: const Color(0xFFFFDDB3),
  secondary: const Color(0xFFCFBDF0),
  onSecondary: const Color(0xFF352A4D),
  secondaryContainer: const Color(0xFF4A3E63),
  onSecondaryContainer: const Color(0xFFEADDFF),
  surface: BrandColors.nightDeep,
  onSurface: const Color(0xFFEFE7F4),
  onSurfaceVariant: const Color(0xFFCBC1D6),
  surfaceContainerLowest: const Color(0xFF100D16),
  surfaceContainerLow: BrandColors.night,
  surfaceContainer: const Color(0xFF231C2F),
  surfaceContainerHigh: BrandColors.nightRaised,
  surfaceContainerHighest: BrandColors.grid,
  outline: const Color(0xFF958AA3),
  outlineVariant: const Color(0xFF473D58),
  inverseSurface: const Color(0xFFEFE7F4),
  onInverseSurface: BrandColors.night,
  inversePrimary: BrandColors.toast,
  surfaceTint: Colors.transparent,
);

/// The app's Material 3 theme for [brightness].
///
/// Body text stays on the platform font: bundling a face would cost download
/// size and a licence (docs/branding.md). Weight and tracking carry the brand.
ThemeData buildBrandTheme(Brightness brightness) {
  final scheme =
      brightness == Brightness.light ? brandLightScheme : brandDarkScheme;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  final rounded16 = BorderRadius.circular(16);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      dividerColor: scheme.outlineVariant,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: rounded16,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: rounded16,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: rounded16,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outline),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
  );
}
