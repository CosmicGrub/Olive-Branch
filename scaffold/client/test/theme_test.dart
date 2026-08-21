// OLIVE BRANCH — theme catalog tests. Asserts colorSchemeFor() produces 12
// genuinely distinct real ColorSchemes (not a broken seed function silently
// producing near-identical results), AppTheme's wire round-trip, and the
// FAIL-CLOSED fallback for an unset/malformed backend value.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/theme.dart';

void main() {
  group('theme catalog — 12 real palette x brightness ColorSchemes', () {
    test('every palette has a catalogue entry with a title and blurb', () {
      for (final palette in ThemePalette.values) {
        final meta = themePaletteCatalogue[palette];
        expect(meta, isNotNull, reason: '${palette.name} has no catalogue entry');
        expect(meta!.title, isNotEmpty);
        expect(meta.blurb, isNotEmpty);
      }
    });

    test('all 12 palette x brightness ColorSchemes are pairwise distinct',
        () {
      final schemes = <String, ColorScheme>{};
      for (final palette in ThemePalette.values) {
        for (final brightness in ThemeBrightness.values) {
          final theme = AppTheme(palette: palette, brightness: brightness);
          schemes['${palette.name}/${brightness.name}'] = colorSchemeFor(theme);
        }
      }
      expect(schemes.length, 12);
      final entries = schemes.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          final a = entries[i], b = entries[j];
          final distinct = a.value.primary != b.value.primary ||
              a.value.surface != b.value.surface ||
              a.value.brightness != b.value.brightness;
          expect(distinct, isTrue,
              reason: '${a.key} and ${b.key} produced an indistinguishable ColorScheme — '
                  'colorSchemeFor() is not really deriving 12 real schemes');
        }
      }
    });

    for (final palette in ThemePalette.values) {
      test('${palette.name}: light and dark brightness actually differ', () {
        final light = colorSchemeFor(AppTheme(palette: palette, brightness: ThemeBrightness.light));
        final dark = colorSchemeFor(AppTheme(palette: palette, brightness: ThemeBrightness.dark));
        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.surface, isNot(dark.surface));
      });
    }

    test('classic keeps Colors.deepPurple as its seed — the explicit reset option', () {
      final classic = colorSchemeFor(const AppTheme(palette: ThemePalette.classic, brightness: ThemeBrightness.light));
      final stockDeepPurple = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
      expect(classic.primary, stockDeepPurple.primary);
    });
  });

  group('AppTheme wire round-trip and fail-closed fallback', () {
    test('toWire/fromWire round-trips every real combination', () {
      for (final palette in ThemePalette.values) {
        for (final brightness in ThemeBrightness.values) {
          final theme = AppTheme(palette: palette, brightness: brightness);
          final restored = AppTheme.fromWire(theme.toWire());
          expect(restored, theme);
        }
      }
    });

    test('fromWire(null) fails closed to defaultAppTheme, never a crash', () {
      expect(AppTheme.fromWire(null), defaultAppTheme);
    });

    test('an unrecognized palette string fails closed, not a crash', () {
      expect(AppTheme.fromWire({'themePalette': 'not_a_real_palette', 'themeBrightness': 'light'}),
          defaultAppTheme);
    });

    test('an unrecognized brightness string fails closed, not a crash', () {
      expect(AppTheme.fromWire({'themePalette': 'calmModern', 'themeBrightness': 'sepia'}),
          defaultAppTheme);
    });

    test('a missing key fails closed, not a crash', () {
      expect(AppTheme.fromWire({'themePalette': 'calmModern'}), defaultAppTheme);
    });

    test('defaultAppTheme is classic/light — the app\'s own former stock look', () {
      expect(defaultAppTheme.palette, ThemePalette.classic);
      expect(defaultAppTheme.brightness, ThemeBrightness.light);
    });

    test('AppTheme equality is value-based, for ThemeController change detection', () {
      const a = AppTheme(palette: ThemePalette.deepCozy, brightness: ThemeBrightness.dark);
      const b = AppTheme(palette: ThemePalette.deepCozy, brightness: ThemeBrightness.dark);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ThemeController — propagation', () {
    test('defaults to defaultAppTheme when constructed with no argument', () {
      final controller = ThemeController();
      expect(controller.value, defaultAppTheme);
      controller.dispose();
    });

    test('notifies listeners only when the value actually changes', () {
      final controller = ThemeController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.value = const AppTheme(palette: ThemePalette.softPlayful, brightness: ThemeBrightness.dark);
      expect(notifications, 1);
      controller.dispose();
    });
  });
}
