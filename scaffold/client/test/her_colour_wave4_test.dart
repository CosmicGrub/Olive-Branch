// OLIVE BRANCH — Wave 4: her colour and art, end to end on the real screens. UNVERIFIED until CI runs it.
// MASTERFILE §8.6, P2. The child answers with "Other colours"; the grown-up chooses an art style from drawn
// thumbnails; the colour-day override is kept and flagged; postures hold at 344/390/600/800 dp at 2.0x text.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/her_colour_art.dart';
import 'package:olive_client/her_colour_guardian.dart';
import 'package:olive_client/her_colour_home.dart';
import 'package:olive_client/her_colour_store.dart';

void main() {
  MemoryColourStore store({int age = 6}) => MemoryColourStore(ageYears: age, now: () => DateTime(2026, 11, 9, 8, 0));
  const sizes = [Size(344, 882), Size(390, 844), Size(600, 900), Size(800, 1280)];

  testWidgets('the daily question can be answered from the other colours, and the screen then wears it', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final s = store();
    await t.pumpWidget(MaterialApp(home: HerColourScreen(childName: 'Ivy', childAge: 6, store: s, random: () => 0)));
    await t.pumpAndSettle();
    expect(find.text('Which do you like more today?'), findsOneWidget);
    await t.tap(find.byKey(const Key('colourMore')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('all_mint')));
    await t.pumpAndSettle();
    expect((await s.today()).colourId, 'mint');
    expect(t.widget<Text>(find.byKey(const Key('colourName'))).data, 'Mint');
    expect(find.byKey(const Key('colourMore')), findsNothing, reason: 'the question ends for the day once answered');
  });

  group('the grown-up chooses an art style from drawn thumbnails', () {
    testWidgets('one thumbnail per style her age allows, each drawn in that style', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: HerColourGuardianScreen(childName: 'Ivy', childAge: 9, store: store(age: 9))));
      await t.pumpAndSettle();
      final styles = stylesForAge(9);
      expect(styles, contains('pixel'));
      for (final style in styles) {
        final thumb = find.byKey(Key('artStyle_$style'));
        expect(thumb, findsOneWidget, reason: style);
        final art = t.widget<ColourArt>(find.descendant(of: thumb, matching: find.byType(ColourArt)));
        expect(art.style, style);
      }
    });

    testWidgets('tapping a thumbnail saves that style as the default', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final s = store();
      await t.pumpWidget(MaterialApp(home: HerColourGuardianScreen(childName: 'Ivy', childAge: 6, store: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('artStyle_crayon')));
      await t.pumpAndSettle();
      expect((await s.art()).artStyle, 'crayon');
      expect(find.text('Saved.'), findsOneWidget);
    });

    for (final size in sizes) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('fits at ${size.width.toInt()} dp at ${scale}x text', (t) async {
          await t.binding.setSurfaceSize(size);
          addTearDown(() => t.binding.setSurfaceSize(null));
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          await t.pumpWidget(MaterialApp(home: HerColourGuardianScreen(childName: 'Ivy', childAge: 9, store: store(age: 9))));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  test('the guardian colour-day override is kept AND flagged as an open owner decision', () {
    final src = File('lib/her_colour_guardian.dart').readAsStringSync();
    expect(src, contains('FLAGGED (owner decision'));
    expect(src, contains('A colour day'));
    final matrix = File('../../docs/superpowers/parity/matrix.json').readAsStringSync();
    expect(matrix, contains('wave45-flag'), reason: 'matrix row 82 must carry the flag');
  });

  test('her side never imports the guardian screen (the override has no door on her device)', () {
    for (final f in ['her_colour_home', 'colour_daily', 'colour_pick', 'play_window_gate']) {
      final src = File('lib/$f.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      expect(src.contains('her_colour_guardian'), isFalse, reason: f);
      expect(src.contains('GuardianColourStore'), isFalse, reason: f);
    }
  });
}
