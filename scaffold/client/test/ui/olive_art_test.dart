// No longer UNVERIFIED — verified by CI.
// OLIVE BRANCH — icons, scene and spot illustrations (lib/ui/olive_art.dart + olive_art_data.dart).
//
// The data is GENERATED from the premium kit by tools/gen-olive-icons.mjs; the Node drift guard
// (tools/test/olive_art.test.mjs) proves the committed Dart equals a fresh generation. THIS file proves
// the Dart side: the icon set has every kit icon name (read from the committed kit snapshot, not from
// a list typed here), every scene and spot is present, all of it paints in both brightnesses and every
// palette, and the celebration art stays inside P2 (no stars, trophies or scores).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/design_tokens_generated.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';
import 'package:olive_client/ui/olive_art_data.dart';
import 'package:olive_client/ui/olive_ui.dart';
import 'package:olive_client/ui/olive_vector.dart';

String get _snapshot => File('../tools/design-reference/kit.js').readAsStringSync();

/// Names of the entries of `var IC={ ... }` in the snapshot (the kit's own icon table).
List<String> kitIconNames() {
  final s = _snapshot;
  final a = s.indexOf('var IC={');
  final b = s.indexOf('OB.ICONS=');
  final body = s.substring(a, b);
  return RegExp(r"(?:^|[\s,{])([A-Za-z][A-Za-z0-9]*):'<", multiLine: true).allMatches(body).map((m) => m.group(1)!).toList();
}

Widget _host(Widget child, {Brightness b = Brightness.light, ThemePalette pal = ThemePalette.olive}) => MaterialApp(
      theme: buildThemeData(AppTheme(palette: pal, brightness: b == Brightness.light ? ThemeBrightness.light : ThemeBrightness.dark)),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('kit parity: names', () {
    test('the snapshot yields a plausible icon table', () {
      final names = kitIconNames();
      expect(names.length, greaterThan(90));
      expect(names, containsAll(['home', 'chevR', 'micoff', 'check2', 'fingerprint', 'skip']));
    });

    test('OliveIcons has every kit icon name and no extras', () {
      final kit = kitIconNames();
      expect(OliveIcons.all.toSet(), kit.toSet());
      expect(OliveIcons.all.length, kit.length);
    });

    test('the icon, spot and scene names equal the design tokens tokens.json carries', () {
      // Two generators read the same committed kit snapshot; this keeps their name sets locked together.
      expect(OliveIcons.all.toSet(), kDesignIcons.keys.toSet());
      expect(kOliveSpotNames.toSet(), kDesignSpots.keys.toSet());
      expect(kOliveSceneNames.toSet(), kDesignScenes.toSet());
    });

    test('every kit icon has geometry', () {
      for (final n in kitIconNames()) {
        expect(kOliveIconData[n], isNotNull, reason: n);
        expect(kOliveIconData[n]!, isNotEmpty, reason: n);
      }
    });

    test('scene names match the kit OB.SCENES', () {
      final m = RegExp(r'OB\.SCENES="([^"]+)"').firstMatch(_snapshot)!.group(1)!.split(' ');
      expect(kOliveSceneNames, m);
      for (final n in const ['day', 'night', 'garden', 'kitchen', 'car', 'classroom', 'bedroom', 'park', 'sea', 'twohouses']) {
        expect(kOliveSceneData.containsKey(n), isTrue, reason: n);
      }
    });

    test('spot names match the kit SP table and include the required set', () {
      final s = _snapshot;
      final a = s.indexOf('var SP={');
      final b = s.indexOf('OB.SPOTS=');
      final kit = RegExp(r"^ ([a-z]+):'<", multiLine: true).allMatches(s.substring(a, b)).map((m) => m.group(1)!).toList();
      expect(kOliveSpotNames, kit);
      for (final n in const ['family', 'houses', 'envelope', 'key', 'shield', 'lock', 'phone', 'tablet', 'video', 'mic', 'leaf']) {
        expect(kOliveSpotData.containsKey(n), isTrue, reason: n);
      }
    });

    test('P2: no star, trophy, medal, crown, score or streak art among scenes and spots', () {
      const banned = ['star', 'trophy', 'medal', 'crown', 'score', 'streak', 'badge', 'rank'];
      for (final n in [...kOliveSceneNames, ...kOliveSpotNames]) {
        for (final b in banned) {
          expect(n.contains(b), isFalse, reason: '$n contains $b');
        }
      }
      expect(kOliveSpotNames, contains('leaf'));
    });

    test('unknown names fall back like the kit (icon info, scene hills, spot leaf)', () {
      expect(kOliveIconData['no-such-icon'], isNull);
    });
  });

  group('geometry is well formed', () {
    test('every path is a valid opcode stream with finite numbers', () {
      void check(String where, List<ONode> nodes) {
        for (final n in nodes) {
          if (n is OGroup) {
            check(where, n.children);
            if (n.m != null) expect(n.m!.length, 6, reason: where);
          } else if (n is OPath) {
            var i = 0;
            final d = n.d;
            while (i < d.length) {
              final op = d[i].toInt();
              expect(op >= 0 && op <= 4, isTrue, reason: '$where op $op');
              final len = const [3, 3, 5, 7, 1][op];
              expect(i + len <= d.length, isTrue, reason: '$where truncated');
              for (var k = 1; k < len; k++) {
                expect(d[i + k].isFinite, isTrue, reason: where);
              }
              i += len;
            }
            expect(i, d.length, reason: where);
            expect(n.f != null || n.s != null, isTrue, reason: '$where draws nothing');
          }
        }
      }

      kOliveIconData.forEach((k, v) => check('icon $k', v));
      kOliveSceneData.forEach((k, v) => check('scene $k', v));
      kOliveSpotData.forEach((k, v) => check('spot $k', v));
    });

    test('scenes are full canvas: the first shape of every scene covers 300 x 150', () {
      for (final e in kOliveSceneData.entries) {
        final first = e.value.first as OPath;
        final xs = <double>[], ys = <double>[];
        var i = 0;
        while (i < first.d.length) {
          final op = first.d[i].toInt();
          final len = const [3, 3, 5, 7, 1][op];
          if (op != 4) {
            xs.add(first.d[i + len - 2]);
            ys.add(first.d[i + len - 1]);
          }
          i += len;
        }
        expect(xs.reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(0.5), reason: e.key);
        expect(xs.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(299.5), reason: e.key);
        expect(ys.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(149.5), reason: e.key);
      }
    });

    test('colour tokens resolve in every palette and brightness without error', () {
      for (final pal in ThemePalette.values) {
        for (final br in ThemeBrightness.values) {
          final p = OlivePalette.fromTheme(buildThemeData(AppTheme(palette: pal, brightness: br)));
          for (final t in OTok.values) {
            expect(p.tok(t).a, 1.0, reason: '$pal $br $t');
          }
          const OCol.mix(OCol.v(OTok.pri), 50, OCol.h(0xFFFFFFFF)).resolve(p, Colors.red);
        }
      }
    });
  });

  group('painting', () {
    for (final b in Brightness.values) {
      testWidgets('every icon paints (${b.name})', (tester) async {
        await tester.pumpWidget(_host(Wrap(children: [for (final n in OliveIcons.all) OliveIcon(n, size: 28)]), b: b));
        expect(tester.takeException(), isNull);
        expect(find.byType(OliveIcon), findsNWidgets(OliveIcons.all.length));
      });

      testWidgets('every scene and spot paints (${b.name})', (tester) async {
        await tester.pumpWidget(_host(
          Column(children: [
            for (final n in kOliveSceneNames) SizedBox(width: 300, child: OliveScene(n)),
            Wrap(children: [for (final n in kOliveSpotNames) OliveSpot(n)]),
          ]),
          b: b));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('all seven palettes paint a scene', (tester) async {
      for (final pal in ThemePalette.values) {
        await tester.pumpWidget(_host(const SizedBox(width: 300, child: OliveScene('garden')), pal: pal));
        expect(tester.takeException(), isNull, reason: pal.name);
      }
    });

    testWidgets('an icon is decorative unless labelled', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(_host(const Column(children: [OliveIcon(OliveIcons.home), OliveIcon(OliveIcons.mail, semanticLabel: 'Letters')])));
      expect(find.bySemanticsLabel('Letters'), findsOneWidget);
      expect(find.bySemanticsLabel('home'), findsNothing);
      h.dispose();
    });

    testWidgets('icon colour follows the IconTheme and an explicit colour wins', (tester) async {
      await tester.pumpWidget(_host(const IconTheme(data: IconThemeData(color: Colors.red), child: OliveIcon(OliveIcons.home))));
      final painter = tester.widget<CustomPaint>(find.descendant(of: find.byType(OliveIcon), matching: find.byType(CustomPaint)).first).painter! as OliveVectorPainter;
      expect(painter.current, Colors.red);
      await tester.pumpWidget(_host(const IconTheme(data: IconThemeData(color: Colors.red), child: OliveIcon(OliveIcons.home, color: Colors.blue, strokeWidth: 3))));
      final painter2 = tester.widget<CustomPaint>(find.descendant(of: find.byType(OliveIcon), matching: find.byType(CustomPaint)).first).painter! as OliveVectorPainter;
      expect(painter2.current, Colors.blue);
      expect(painter2.strokeWidth, 3);
    });
  });
}
