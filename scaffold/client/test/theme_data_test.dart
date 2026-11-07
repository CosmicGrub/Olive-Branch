// OLIVE BRANCH — the refined ThemeData (theme_data.dart). Asserts the
// overhaul's measurable promises: every palette x brightness is readable
// (WCAG AA on the pairs text actually uses), shapes and type are the refined
// ones, and the protected colours that carry meaning never come from a palette.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/design_tokens.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double _ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  final all = [for (final p in ThemePalette.values) for (final b in ThemeBrightness.values) AppTheme(palette: p, brightness: b)];

  group('buildThemeData — readable in every palette and brightness (WCAG AA 4.5:1)', () {
    for (final t in all) {
      test('${t.palette.name}/${t.brightness.name}', () {
        final d = buildThemeData(t);
        final s = d.colorScheme;
        final sem = d.extension<OliveSemantic>()!;
        final pairs = <String, double>{
          'body text on page': _ratio(s.onSurface, s.surface),
          'secondary text on page': _ratio(s.onSurfaceVariant, s.surface),
          'secondary text on card': _ratio(s.onSurfaceVariant, s.surfaceContainerLowest),
          'text on primary': _ratio(s.onPrimary, s.primary),
          'text on primary container': _ratio(s.onPrimaryContainer, s.primaryContainer),
          'text on secondary container': _ratio(s.onSecondaryContainer, s.secondaryContainer),
          'text on error': _ratio(s.onError, s.error),
          'success on its tint': _ratio(sem.ok, sem.okContainer),
          'warning on its tint': _ratio(sem.warn, sem.warnContainer),
          'info on its tint': _ratio(sem.info, sem.infoContainer),
        };
        pairs.forEach((name, r) => expect(r, greaterThanOrEqualTo(4.5), reason: '$name is ${r.toStringAsFixed(2)}:1'));
      });
    }
  });

  group('buildThemeData — the refined shape and type', () {
    final d = buildThemeData(defaultAppTheme);
    test('is Material 3 with the brand palette', () {
      expect(d.useMaterial3, isTrue);
      expect(d.colorScheme.primary, colorSchemeFor(defaultAppTheme).primary);
    });
    test('cards use the larger radius and a hairline edge', () {
      final shape = d.cardTheme.shape! as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, AppRadius.xl);
      expect(shape.side.width, greaterThan(0));
    });
    test('buttons are at least 46 high and share one corner radius', () {
      final f = d.filledButtonTheme.style!;
      expect(f.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(46));
      final shape = f.shape!.resolve({})! as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, 15);
    });
    test('sheets and dialogs use the sheet radius', () {
      final sheet = d.bottomSheetTheme.shape! as RoundedRectangleBorder;
      expect((sheet.borderRadius as BorderRadius).topLeft.x, AppRadius.sheet);
      expect(((d.dialogTheme.shape! as RoundedRectangleBorder).borderRadius as BorderRadius).topLeft.x, AppRadius.sheet);
    });
    test('headings use the display face, sentences the body face', () {
      expect(d.textTheme.titleLarge!.fontFamily, kDisplayFont);
      expect(d.textTheme.bodyMedium!.fontFamily, kBodyFont);
    });
    test('the page transition is a crossfade, not a travel', () {
      expect(d.pageTransitionsTheme.builders[TargetPlatform.android], isA<FadeForwardsPageTransitionsBuilder>());
    });
    test('is a pure function: the same AppTheme gives equal results', () {
      expect(buildThemeData(defaultAppTheme).colorScheme, buildThemeData(defaultAppTheme).colorScheme);
    });
  });

  group('OliveSemantic — colours that mean something never come from a palette', () {
    test('the same semantic set is returned for every palette in a given brightness', () {
      for (final b in ThemeBrightness.values) {
        final sets = [for (final p in ThemePalette.values) buildThemeData(AppTheme(palette: p, brightness: b)).extension<OliveSemantic>()!];
        for (final s in sets) {
          expect(s.ok, sets.first.ok);
          expect(s.dayBedtime, sets.first.dayBedtime);
          expect(s.overlap, sets.first.overlap);
        }
      }
    });
    test('light and dark sets differ', () {
      expect(OliveSemantic.light.ok, isNot(OliveSemantic.dark.ok));
    });
    test('a theme swap does not interpolate the semantic colours', () {
      final mid = OliveSemantic.light.lerp(OliveSemantic.dark, 0.5);
      expect(mid.ok == OliveSemantic.light.ok || mid.ok == OliveSemantic.dark.ok, isTrue);
    });
    test('no semantic colour equals any palette primary (so a palette can never impersonate one)', () {
      final sem = OliveSemantic.light;
      for (final t in all.where((a) => a.brightness == ThemeBrightness.light)) {
        final primary = colorSchemeFor(t).primary;
        for (final c in [sem.ok, sem.warn, sem.info, sem.dayMorning, sem.dayBedtime, sem.overlap]) {
          expect(c, isNot(primary), reason: '${t.palette.name}.primary collides with a protected colour');
        }
      }
    });
  });

  group('the seven palettes', () {
    test('olive is first, the default, and a real seed', () {
      expect(ThemePalette.values.first, ThemePalette.olive);
      expect(defaultAppTheme.palette, ThemePalette.olive);
    });
    test('classic is still available as an explicit option', () {
      expect(ThemePalette.values, contains(ThemePalette.classic));
    });
    test('the wire name round-trips for olive', () {
      const t = AppTheme(palette: ThemePalette.olive, brightness: ThemeBrightness.dark);
      expect(AppTheme.fromWire(t.toWire()), t);
    });
  });
}
