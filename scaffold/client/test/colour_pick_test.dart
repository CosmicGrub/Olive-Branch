// OLIVE BRANCH — colour_pick.dart / palette_logic.dart tests. §8.6.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_pick.dart';
import 'package:olive_client/palette_logic.dart';

void main() {
  // Twelve swatches plus the continue button run taller than the default
  // 800x600 test surface — a tall surface avoids simulating a scroll gesture
  // before every tap, the same approach emergency_card_test.dart already uses.
  Future<void> pump(WidgetTester tester, ValueChanged<String?> onContinue) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ColourPickScreen(
      childName: 'Ivy', onContinue: onContinue)));
  }

  group('palette_logic — pure logic', () {
    test('there are twelve curated swatches, each with her word for it', () {
      expect(palette.length, 12);
      expect(palette.map((s) => s.label), contains('sunny yellow'));
    });

    test('there is deliberately no pure red', () {
      expect(palette.any((s) => s.hex.toUpperCase() == '#FF0000'), isFalse);
    });

    test('every swatch is WCAG-AA legible as ink text', () {
      for (final s in palette) {
        final result = textColourFor(s);
        expect(result.ratio, greaterThanOrEqualTo(aaText - 0.01),
          reason: '${s.id} must be legible as text');
      }
    });

    test('applyColour refuses a forbidden placement outright', () {
      final outcome = applyColour('sunny', ['ribbon_band']);
      expect(outcome.ok, isFalse);
      expect(outcome.reason, 'forbidden_placement');
    });

    test('applyColour silently drops placements past the budget of three', () {
      final outcome = applyColour('sunny', [
        'accent_stripe', 'avatar_ring', 'sleeps_number', 'game_piece']);
      expect(outcome.ok, isTrue);
      expect(outcome.placements.length, maxPlacementsPerScreen);
      expect(outcome.dropped, ['game_piece']);
    });

    test('an unknown colour id is refused', () {
      expect(applyColour('neon', ['accent_stripe']).ok, isFalse);
    });
  });

  testWidgets('renders all twelve swatches as tappable choices', (tester) async {
    await pump(tester, (_) {});
    final swatchTiles = find.descendant(
      of: find.byType(GridView), matching: find.byType(InkWell));
    expect(swatchTiles, findsNWidgets(12));
  });

  testWidgets('picking a swatch and continuing reports its id', (tester) async {
    String? got;
    await pump(tester, (id) => got = id);
    await tester.tap(find.bySemanticsLabel('sunny yellow'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got, 'sunny');
  });

  testWidgets('skipping reports null — a child with no colour is a supported state', (tester) async {
    String? got = 'not-null-sentinel';
    await pump(tester, (id) => got = id);
    await tester.tap(find.text('Skip for now'));
    await tester.pump();
    expect(got, isNull);
  });

  testWidgets('picking a colour shows a live preview using only allowed placements', (tester) async {
    await pump(tester, (_) {});
    await tester.tap(find.bySemanticsLabel('coral pink'));
    await tester.pumpAndSettle();
    expect(find.text('Ivy'), findsOneWidget);
    expect(find.text('Coral pink'), findsOneWidget);
  });

  testWidgets('no settings affordance, and no price or mood language anywhere', (tester) async {
    await pump(tester, (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.textContaining(RegExp(r'\$')), findsNothing);
    for (final word in colourForbidden) {
      expect(find.textContaining(word, findRichText: true), findsNothing);
    }
  });
}
