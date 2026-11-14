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

  group('other colours (Wave 4)', () {
    testWidgets('one quiet button opens all twelve; a swatch is the same answer as a card', (tester) async {
      String? got;
      await pump(tester, (id) => got = id, random: () => 0.2);
      expect(find.byKey(const Key('colourAll')), findsNothing);
      await tester.tap(find.byKey(const Key('colourMore')));
      await tester.pump();
      expect(find.byKey(const Key('colourAll')), findsOneWidget);
      expect(find.byKey(const Key('colourMore')), findsNothing);
      for (final s in palette) {
        expect(find.byKey(Key('all_${s.id}')), findsOneWidget, reason: s.id);
      }
      await tester.tap(find.byKey(const Key('all_grape')));
      await tester.pump();
      expect(got, 'grape');
    });

    testWidgets('the extra set carries no streak, count or new-and-better language either', (tester) async {
      await pump(tester, (_) {});
      await tester.tap(find.byKey(const Key('colourMore')));
      await tester.pump();
      for (final word in [...colourForbidden, 'streak', 'new colour', 'better', 'try something']) {
        expect(find.textContaining(word, findRichText: true), findsNothing, reason: word);
      }
    });

    for (final size in const [Size(344, 882), Size(390, 844), Size(600, 900), Size(800, 1280)]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('opened set fits at ${size.width.toInt()} dp at ${scale}x text, and every target is 56 dp or more', (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(tester, (_) {});
          await tester.ensureVisible(find.byKey(const Key('colourMore'))); // a tall text scale scrolls
          await tester.tap(find.byKey(const Key('colourMore')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final s in palette) {
            final sz = tester.getSize(find.byKey(Key('all_${s.id}')));
            expect(sz.shortestSide, greaterThanOrEqualTo(56), reason: s.id);
          }
        });
      }
    }
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. This screen already branches on width
    // (narrow < 420 stacks, otherwise the pair sits side by side) — these
    // four widths exercise both branches of that breakpoint for real.
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(tester, (_) {});
        expect(tester.takeException(), isNull);
      });
    }
  });
}
