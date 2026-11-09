// No longer UNVERIFIED — verified by CI.
// ignore_for_file: avoid_dynamic_calls  (this test walks decoded JSON)
// OLIVE BRANCH — design PARITY test. docs/superpowers/parity/PARITY.md: the prototype is the
// reference and Flutter must match it. This loads assets/design/tokens.json (generated from the
// prototype's kit.js + overhaul.css by tools/gen-design-tokens.mjs) and asserts that what the
// REAL theme produces (colorSchemeFor, buildThemeData, OliveTokens, AppRadius, AppSpacing,
// OliveMotion) equals it for every palette x mode, so the two can never drift again.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/design_tokens.dart';
import 'package:olive_client/design_tokens_generated.dart';
import 'package:olive_client/olive_tokens.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';

int _hex(String s) => int.parse(s.substring(1), radix: 16);
Color _col(String s) => Color(_hex(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> tokens;
  setUpAll(() async {
    tokens = jsonDecode(await rootBundle.loadString('assets/design/tokens.json')) as Map<String, dynamic>;
  });

  Map<String, dynamic> roles(ThemePalette p, ThemeBrightness b) =>
      (tokens['palettes'][p.name][b.name] as Map).cast<String, dynamic>();

  final all = [for (final p in ThemePalette.values) for (final b in ThemeBrightness.values) AppTheme(palette: p, brightness: b)];

  group('the catalogue is the prototype\'s', () {
    test('the same seven palettes, in the same order', () {
      expect((tokens['palettes'] as Map).keys.toList(), ThemePalette.values.map((p) => p.name).toList());
    });
    test('each palette seed equals the prototype seed', () {
      for (final p in ThemePalette.values) {
        expect(seedFor(p), _col(tokens['palettes'][p.name]['seed'] as String), reason: p.name);
      }
    });
    test('classic is still stock deep purple', () => expect(seedFor(ThemePalette.classic).toARGB32(), Colors.deepPurple.toARGB32()));
  });

  group('colour roles equal the prototype for every palette x mode', () {
    for (final t in all) {
      test('${t.palette.name}/${t.brightness.name}', () {
        final json = roles(t.palette, t.brightness);
        final d = buildThemeData(t);
        final ext = d.extension<OliveTokens>()!;
        // every role the generator knows is on OliveTokens, byte for byte
        expect(ext.roles.length, json.length);
        for (final e in json.entries) {
          expect(ext.roles[DesignRole.values.byName(e.key)], _col(e.value as String), reason: 'role ${e.key}');
        }
        // the Material slots are the documented roles
        Color r(String k) => _col(json[k] as String);
        final s = d.colorScheme;
        expect(s.primary, r('pri'));
        expect(s.onPrimary, r('onPri'));
        expect(s.primaryContainer, r('priC'));
        expect(s.onPrimaryContainer, r('onPriC'));
        expect(s.secondary, r('accent'));
        expect(s.secondaryContainer, r('accentC'));
        expect(s.tertiary, r('priD'));
        expect(s.tertiaryContainer, r('priC2'));
        expect(s.surface, r('bg'));
        expect(s.surfaceContainerLowest, r('surface'));
        expect(s.surfaceContainer, r('surface2'));
        expect(s.surfaceContainerHigh, r('surface3'));
        expect(s.onSurface, r('ink'));
        expect(s.onSurfaceVariant, r('ink2'));
        expect(s.outline, r('edge'));
        expect(s.outlineVariant, r('line'));
        expect(d.scaffoldBackgroundColor, r('bg'));
        expect(ext.ink3, r('ink3'));
        expect(ext.focus, r('focus'));
        expect(ext.track, r('track'));
        expect(ext.hero1, r('hero1'));
        expect(ext.hero2, r('hero2'));
        // protected colours: identical to the prototype's, and the same in every palette
        final sem = (tokens['semantic'][t.brightness.name] as Map).cast<String, dynamic>();
        final os = d.extension<OliveSemantic>()!;
        expect(os.ok, _col(sem['ok'] as String));
        expect(os.okContainer, _col(sem['okC'] as String));
        expect(os.warn, _col(sem['warn'] as String));
        expect(os.warnContainer, _col(sem['warnC'] as String));
        expect(os.info, _col(sem['info'] as String));
        expect(os.infoContainer, _col(sem['infoC'] as String));
        expect(os.dayMorning, _col(sem['dpMorning'] as String));
        expect(os.daySchool, _col(sem['dpDay'] as String));
        expect(os.dayAfternoon, _col(sem['dpAfternoon'] as String));
        expect(os.dayEvening, _col(sem['dpEvening'] as String));
        expect(os.dayBedtime, _col(sem['dpBed'] as String));
        expect(os.dayNight, _col(sem['dpNight'] as String));
        expect(s.error, _col(sem['bad'] as String));
        expect(s.errorContainer, _col(sem['badC'] as String));
      });
    }
  });

  group('elevation levels equal the prototype (non-inset layers)', () {
    for (final t in all) {
      test('${t.palette.name}/${t.brightness.name}', () {
        final ext = buildThemeData(t).extension<OliveTokens>()!;
        final json = tokens['elevation'][t.palette.name][t.brightness.name] as Map;
        for (var level = 0; level < 4; level++) {
          final layers = (json['shadow$level'] as List).cast<Map<String, dynamic>>().where((l) => l['inset'] != true).toList();
          final got = ext.elevations[level];
          expect(got.length, layers.length, reason: 'shadow$level layer count');
          for (var i = 0; i < layers.length; i++) {
            expect(got[i].color, _col(layers[i]['color'] as String));
            expect(got[i].offset, Offset((layers[i]['dx'] as num).toDouble(), (layers[i]['dy'] as num).toDouble()));
            expect(got[i].blurRadius, (layers[i]['blur'] as num).toDouble());
            expect(got[i].spreadRadius, (layers[i]['spread'] as num).toDouble());
          }
        }
      });
    }
  });

  group('type scale', () {
    Map<String, dynamic> scale() => (tokens['type']['scale'] as Map).cast<String, dynamic>();
    void expectStyle(TextStyle? got, String name) {
      final spec = scale()[name] as Map<String, dynamic>;
      expect(got, isNotNull, reason: name);
      expect(got!.fontSize, (spec['size'] as num).toDouble(), reason: '$name size');
      expect(got.height, (spec['lineHeight'] as num).toDouble(), reason: '$name line height');
      expect(got.fontWeight!.value, spec['weight'], reason: '$name weight');
      expect(got.letterSpacing! / got.fontSize!, closeTo((spec['letterSpacingEm'] as num).toDouble(), 1e-9), reason: '$name tracking');
      expect(got.fontFamily, switch (spec['family']) { 'display' => kDisplayFont, 'mono' => kMonoFont, _ => kBodyFont }, reason: '$name family');
    }

    test('every TextTheme slot is a named entry of the prototype scale', () {
      final tt = buildThemeData(defaultAppTheme).textTheme;
      expectStyle(tt.displayLarge, 'display');
      expectStyle(tt.displayMedium, 'big');
      expectStyle(tt.displaySmall, 'title');
      expectStyle(tt.headlineLarge, 'title');
      expectStyle(tt.headlineMedium, 'title');
      expectStyle(tt.headlineSmall, 'head');
      expectStyle(tt.titleLarge, 'title');
      expectStyle(tt.titleMedium, 'head');
      expectStyle(tt.titleSmall, 'cardHead');
      expectStyle(tt.bodyLarge, 'body');
      expectStyle(tt.bodyMedium, 'body');
      expectStyle(tt.bodySmall, 'cap');
      expectStyle(tt.labelLarge, 'button');
      expectStyle(tt.labelMedium, 'buttonSm');
      expectStyle(tt.labelSmall, 'pillSm');
    });
    test('the entries Material has no slot for are on OliveTokens', () {
      final x = buildThemeData(defaultAppTheme).extension<OliveTokens>()!;
      expectStyle(x.label, 'label');
      expectStyle(x.mono, 'mono');
      expectStyle(x.big, 'big');
      expectStyle(x.caption, 'cap');
      expectStyle(x.rowTitle, 'rowTitle');
      expectStyle(x.rowSub, 'rowSub');
    });
    test('the mono face is bundled (no platform stand-in) and a variable font at weight 500', () {
      final st = designTextStyle('label');
      expect(st.fontFamily, 'JetBrainsMono');
      expect(st.fontVariations!.single.value, 500);
    });
    test('the display face is a variable font asked for by exact weight', () {
      final st = designTextStyle('title');
      expect(st.fontVariations!.single.axis, 'wght');
      expect(st.fontVariations!.single.value, 800);
    });
    test('the generated Dart type table equals the JSON', () {
      expect(kDesignType.keys.toSet(), scale().keys.toSet());
      scale().forEach((k, v) {
        final g = kDesignType[k]!;
        expect(g.size, (v['size'] as num).toDouble());
        expect(g.weight, v['weight']);
        expect(g.lineHeight, (v['lineHeight'] as num).toDouble());
        expect(g.letterSpacingEm, (v['letterSpacingEm'] as num).toDouble());
      });
    });
  });

  group('radii, spacing, components', () {
    test('AppRadius equals the prototype radii r0..r5', () {
      final r = (tokens['radii'] as Map).cast<String, num>();
      expect(AppRadius.sm, r['r0']);
      expect(AppRadius.md, r['r1']);
      expect(AppRadius.lg, r['r2']);
      expect(AppRadius.xl, r['r3']);
      expect(AppRadius.sheet, r['r4']);
      expect(AppRadius.hero, r['r5']);
    });
    test('AppSpacing equals the prototype spacing sp1..sp6', () {
      final s = (tokens['spacing'] as Map).cast<String, num>();
      expect(AppSpacing.xs, s['sp1']);
      expect(AppSpacing.sm, s['sp2']);
      expect(AppSpacing.md, s['sp3']);
      expect(AppSpacing.lg, s['sp4']);
      expect(AppSpacing.xl, s['sp5']);
      expect(AppSpacing.xxl, s['sp6']);
    });
    test('the theme\'s controls use the prototype component metrics', () {
      final c = tokens['components'] as Map;
      final d = buildThemeData(defaultAppTheme);
      expect(AppRadius.field, c['field']['radius']);
      expect(AppRadius.field, c['button']['radius']);
      final shape = d.filledButtonTheme.style!.shape!.resolve({})! as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, c['button']['radius']);
      expect(d.filledButtonTheme.style!.minimumSize!.resolve({})!.height, c['button']['minHeight']);
      expect(d.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height, c['button']['minHeight']);
      final field = d.inputDecorationTheme.border! as OutlineInputBorder;
      expect(field.borderRadius.topLeft.x, c['field']['radius']);
      expect(field.borderSide.width, c['field']['borderWidth']);
      expect(field.borderSide.color, d.colorScheme.outline); // the control edge, not the hairline
      final sheet = d.bottomSheetTheme.shape! as RoundedRectangleBorder;
      expect((sheet.borderRadius as BorderRadius).topLeft.x, (tokens['radii'] as Map)['r4']);
      final card = d.cardTheme.shape! as RoundedRectangleBorder;
      expect((card.borderRadius as BorderRadius).topLeft.x, (tokens['radii'] as Map)['r3']);
      expect(card.side.color, d.extension<OliveTokens>()!.line);
      expect(d.sliderTheme.trackHeight, c['sliderTrack']['height']);
    });
  });

  group('motion and focus', () {
    test('durations equal the prototype', () {
      final m = (tokens['motion']['durationsMs'] as Map).cast<String, num>();
      expect(OliveMotion.press.inMilliseconds, m['press']);
      expect(OliveMotion.fast.inMilliseconds, m['fast']);
      expect(OliveMotion.base.inMilliseconds, m['base']);
      expect(OliveMotion.slow.inMilliseconds, m['slow']);
      expect(OliveMotion.slow.inMilliseconds, lessThan(400)); // consequence only, under 400 ms
    });
    test('easings equal the prototype cubic-beziers', () {
      final e = tokens['motion']['easings'] as Map;
      Cubic c(String n) {
        final v = (e[n] as List).cast<num>();
        return Cubic(v[0].toDouble(), v[1].toDouble(), v[2].toDouble(), v[3].toDouble());
      }
      void same(Cubic got, Cubic want, String n) {
        expect([got.a, got.b, got.c, got.d], [want.a, want.b, want.c, want.d], reason: n);
      }
      same(OliveMotion.easeOut, c('out'), 'out');
      same(OliveMotion.easeSpring, c('spring'), 'spring');
      same(OliveMotion.easeIn, c('in'), 'in');
      // overshoot under 6 percent
      expect(OliveMotion.easeSpring.transform(0.7), lessThan(1.06));
    });
    test('the focus ring is the prototype\'s: 3px in the focus role', () {
      final f = tokens['focusRing'] as Map;
      expect(kDesignFocusWidth, f['width']);
      expect(kDesignFocusOffset, f['offset']);
      expect(kDesignFocusRole.name, f['colorRole']);
      for (final t in all) {
        final ext = buildThemeData(t).extension<OliveTokens>()!;
        expect(ext.focusSide.width, f['width']);
        expect(ext.focusSide.color, ext.focus);
      }
    });
    test('a button shows the focus ring when focused, and none at rest', () {
      final d = buildThemeData(defaultAppTheme);
      final side = d.filledButtonTheme.style!.side!;
      expect(side.resolve({WidgetState.focused})!.width, kDesignFocusWidth);
      expect(side.resolve({})!.width, 0);
    });
  });

  group('the generated Dart equals the JSON (so the two outputs cannot disagree)', () {
    test('colours', () {
      for (final p in DesignPalette.values) {
        for (final m in DesignMode.values) {
          final json = (tokens['palettes'][p.name][m.name] as Map).cast<String, dynamic>();
          final dart = kDesignColors[p]![m]!;
          expect(dart.length, json.length);
          json.forEach((k, v) => expect(dart[DesignRole.values.byName(k)], _hex(v as String), reason: '${p.name}/${m.name}/$k'));
        }
      }
    });
    test('state pills, icons, spots, scenes', () {
      final pills = (tokens['statePills'] as Map).cast<String, dynamic>();
      expect(kDesignStatePills.keys.toSet(), pills.keys.toSet());
      pills.forEach((k, v) {
        expect(kDesignStatePills[k]!.label, v['label']);
        expect(kDesignStatePills[k]!.icon, v['icon']);
        expect(kDesignStatePills[k]!.shape, v['shape']);
        expect(kDesignIcons.containsKey(v['icon']), isTrue, reason: 'pill icon $k exists');
      });
      final icons = (tokens['icons']['paths'] as Map).cast<String, dynamic>();
      expect(kDesignIcons, icons);
      expect(kDesignSpots, (tokens['spots']['shapes'] as Map).cast<String, dynamic>());
      expect(kDesignScenes, (tokens['scenes'] as List).cast<String>());
      expect(icons.length, greaterThan(90));
    });
    test('every state pill is shape + icon + word, never colour alone', () {
      for (final p in kDesignStatePills.values) {
        expect(p.label, isNotEmpty);
        expect(p.icon, isNotEmpty);
      }
      expect(kDesignStatePills['queued']!.shape, 'dashed');
      expect(kDesignStatePills['failed']!.shape, 'outline');
    });
  });

  group('readable: the prototype\'s own pairs pass WCAG AA through the real theme', () {
    for (final t in all) {
      test('${t.palette.name}/${t.brightness.name}', () {
        final d = buildThemeData(t);
        final x = d.extension<OliveTokens>()!;
        final s = d.colorScheme;
        double c(Color a, Color b) => OliveTokens.contrast(a, b);
        for (final surface in [x.bg, x.surface, x.surface2, x.surface3]) {
          for (final ink in [x.ink, x.ink2, x.ink3]) {
            expect(c(ink, surface), greaterThanOrEqualTo(4.5), reason: 'text on a surface');
          }
        }
        for (final surface in [x.bg, x.surface, x.surface2]) {
          expect(c(x.edge, surface), greaterThanOrEqualTo(3.0), reason: 'control edge (WCAG 1.4.11)');
        }
        for (final surface in [x.bg, x.surface]) {
          expect(c(x.focus, surface), greaterThanOrEqualTo(3.0), reason: 'focus ring (WCAG 1.4.11)');
        }
        expect(c(s.onSecondary, s.secondary), greaterThanOrEqualTo(4.5));
        expect(c(s.onTertiary, s.tertiary), greaterThanOrEqualTo(4.5));
        expect(c(s.onErrorContainer, s.errorContainer), greaterThanOrEqualTo(4.5));
        expect(c(s.onInverseSurface, s.inverseSurface), greaterThanOrEqualTo(4.5));
      });
    }
  });
}
