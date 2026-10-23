import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glowing_waffle/theme/brand_theme.dart';

/// WCAG 2.1 contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The pairs the app actually draws text with: body text, buttons, the setup
  // card, inline errors (docs/branding.md, "Contrast matters more than the
  // palette"). AA for normal text is 4.5:1.
  for (final brightness in Brightness.values) {
    group('${brightness.name} scheme', () {
      final scheme = buildBrandTheme(brightness).colorScheme;
      final pairs = <String, (Color, Color)>{
        'onSurface on surface': (scheme.onSurface, scheme.surface),
        'onSurfaceVariant on surface': (
          scheme.onSurfaceVariant,
          scheme.surface
        ),
        'onSurface on surfaceContainerLow (cards)': (
          scheme.onSurface,
          scheme.surfaceContainerLow
        ),
        'onSurfaceVariant on surfaceContainerLowest (text field hint)': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLowest
        ),
        'onPrimary on primary (filled buttons)': (
          scheme.onPrimary,
          scheme.primary
        ),
        'primary on surface (outlined buttons, tabs)': (
          scheme.primary,
          scheme.surface
        ),
        'onPrimaryContainer on primaryContainer (setup card)': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer
        ),
        'onErrorContainer on errorContainer (errors)': (
          scheme.onErrorContainer,
          scheme.errorContainer
        ),
        'onInverseSurface on inverseSurface (snack bars, tooltips)': (
          scheme.onInverseSurface,
          scheme.inverseSurface
        ),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
        test('$name passes WCAG AA', () {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5));
        });
      }

      test('matches the requested brightness', () {
        expect(scheme.brightness, brightness);
      });
    });
  }

  test('surfaces match the splash and web chrome colours', () {
    // android/app/src/main/res/values*/colors.xml, iOS LaunchBackground,
    // web/index.html theme-color: cream in light mode, night in dark mode.
    expect(brandLightScheme.surface, const Color(0xFFFFF8EF));
    expect(brandDarkScheme.surface, const Color(0xFF15111D));
  });
}
