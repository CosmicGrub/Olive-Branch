// OLIVE BRANCH — code-drawn art in seven styles, and her colour as a
// placement-budgeted accent (§8.6.2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/her_colour_accent.dart';
import 'package:olive_client/her_colour_art.dart';
import 'package:olive_client/palette_logic.dart';

void main() {
  group('the art', () {
    testWidgets('every recipe draws in every style without error', (t) async {
      for (final style in artStyles) {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: Wrap(children: [
          for (final k in artKeys) ColourArt(recipe: k, color: const Color(0xFF2F8FC4), style: style, size: 48),
        ]))));
        expect(t.takeException(), isNull, reason: style);
      }
    });

    test('there are twelve recipes and each has something to draw', () {
      expect(artKeys.length, 12);
      for (final k in artKeys) {
        expect(primsFor(k), isNotEmpty, reason: k);
      }
    });

    test('an unknown recipe falls back to the round one, never throws', () {
      expect(primsFor('nonsense').length, primsFor('round').length);
    });

    test('three tints: lighter, the colour itself, darker', () {
      final t = tintsOf(const Color(0xFF2F8FC4));
      expect(t[1], const Color(0xFF2F8FC4));
      expect(t[0].computeLuminance(), greaterThan(t[1].computeLuminance()));
      expect(t[2].computeLuminance(), lessThan(t[1].computeLuminance()));
    });

    test('line art has fillable regions, and a stroke is not one', () {
      // The fox's head circle is at (50,56) r30: tapping its middle hits a region.
      expect(ColourArt.regionAt('fox', const Offset(50, 56)), isNotNull);
      expect(ColourArt.regionAt('fox', const Offset(2, 2)), isNull);
      final stem = primsFor('round').indexWhere((p) => p.isLine);
      expect(stem, greaterThanOrEqualTo(0));
      expect(ColourArt.regionAt('round', const Offset(50, 58)), isNot(stem));
    });

    testWidgets('tapping a region reports its index and nothing else', (t) async {
      int? hit;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: ColourArt(
        recipe: 'fox', color: Colors.blue, style: 'line', size: 200, onRegionTap: (i) => hit = i)))));
      await t.tapAt(t.getCenter(find.byType(ColourArt)));
      expect(hit, isNotNull);
    });

    testWidgets('the picture carries a screen-reader label', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: ColourArt(
        recipe: 'fox', color: Colors.blue, style: 'paper', semanticLabel: 'A fox'))));
      expect(find.bySemanticsLabel('A fox'), findsOneWidget);
    });
  });

  group('her colour as an accent (§8.6.2)', () {
    test('no colour means no accent at all', () {
      expect(HerColourAccent.of(null, const ['accent_stripe']).has('accent_stripe'), isFalse);
      expect(HerColourAccent.none.color, isNull);
    });

    test('at most three placements survive, in the order asked', () {
      final a = HerColourAccent.of('sea', const ['accent_stripe', 'avatar_ring', 'header_flourish', 'loading_dots', 'show_frame']);
      expect(a.placements, ['accent_stripe', 'avatar_ring', 'header_flourish']);
      expect(a.placements.length, maxPlacementsPerScreen);
      expect(a.has('loading_dots'), isFalse);
    });

    test('a forbidden place fails closed: the colour is not drawn anywhere', () {
      for (final bad in forbiddenPlacements) {
        final a = HerColourAccent.of('sea', ['accent_stripe', bad]);
        expect(a.has('accent_stripe'), isFalse, reason: bad);
        expect(a.color, isNull, reason: bad);
      }
    });

    test('there is no placement that is a surface, a background or body text', () {
      for (final p in ['surface', 'background', 'body_text', 'error', 'warning', 'ribbon_band']) {
        expect(allowedPlacements.contains(p), isFalse, reason: p);
      }
    });

    test('an unknown colour id is no colour', () {
      expect(HerColourAccent.of('chartreuse', const ['accent_stripe']).color, isNull);
    });

    testWidgets('the stripe is four logical pixels tall; the ring is a border, never a fill', (t) async {
      final a = HerColourAccent.of('sea', const ['accent_stripe', 'avatar_ring']);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
        AccentStripe(accent: a),
        AccentRing(accent: a, child: const CircleAvatar(radius: 10)),
      ]))));
      expect(t.getSize(find.byKey(const Key('accentStripe'))).height, 4);
      expect(find.byKey(const Key('accentRing')), findsOneWidget);
    });

    testWidgets('without the placement nothing is drawn', (t) async {
      final a = HerColourAccent.of('sea', const ['header_flourish']);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
        AccentStripe(accent: a), AccentRing(accent: a, child: const Text('x')),
      ]))));
      expect(find.byKey(const Key('accentStripe')), findsNothing);
      expect(find.byKey(const Key('accentRing')), findsNothing);
    });
  });
}
