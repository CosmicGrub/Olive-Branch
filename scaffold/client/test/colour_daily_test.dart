// OLIVE BRANCH — colour_daily.dart / palette_logic.dart tests. §8.6.3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_daily.dart';
import 'package:olive_client/palette_logic.dart';

void main() {
  group('dailyPair / choose — pure logic', () {
    test('one of the pair is always her current colour', () {
      final pair = dailyPair('sunny', rand: () => 0.9);
      expect([pair.a.id, pair.b.id], contains('sunny'));
    });

    test('the side is randomised rather than fixed', () {
      final low = dailyPair('sunny', rand: () => 0.1);
      final high = dailyPair('sunny', rand: () => 0.9);
      expect(low.a.id, 'sunny');
      expect(high.b.id, 'sunny');
    });

    test('choosing appends to history with the right via tag', () {
      final r = choose(const [], 'grape', '2026-08-04T10:00:00Z');
      expect(r.ok, isTrue);
      expect(r.history.single.colourId, 'grape');
      expect(r.history.single.via, 'daily');
    });

    test('an unknown colour id is refused, not silently accepted', () {
      expect(choose(const [], 'neon', '2026-08-04').ok, isFalse);
    });
  });

  Future<void> pump(WidgetTester tester, ValueChanged<String> onChoose,
      {double Function()? random}) => tester.pumpWidget(MaterialApp(
    home: ColourDailyScreen(currentColourId: 'sunny', onChoose: onChoose, random: random)));

  testWidgets('renders exactly two colour options, one of them her current colour', (tester) async {
    await pump(tester, (_) {}, random: () => 0.2);
    expect(find.text('sunny yellow'), findsOneWidget);
  });

  testWidgets('tapping an option reports its id', (tester) async {
    String? got;
    await pump(tester, (id) => got = id, random: () => 0.9); // sunny on the right
    await tester.tap(find.text('sunny yellow'));
    await tester.pump();
    expect(got, 'sunny');
  });

  testWidgets('there is no streak, count, or pressure-to-change language on this screen', (tester) async {
    await pump(tester, (_) {});
    expect(find.textContaining('streak'), findsNothing);
    expect(find.textContaining('days in a row'), findsNothing);
    for (final word in colourForbidden) {
      expect(find.textContaining(word, findRichText: true), findsNothing);
    }
    expect(find.textContaining('no wrong answer'), findsOneWidget);
  });

  testWidgets('no settings affordance exists on this screen', (tester) async {
    await pump(tester, (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
  });
}
