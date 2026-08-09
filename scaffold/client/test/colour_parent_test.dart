// OLIVE BRANCH — colour_parent.dart / palette_logic.dart tests. §8.6.4.
//
// The central invariant under test: the guardian is told WHAT she picked and
// nothing else — no mood, no trend, no edit control.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_parent.dart';
import 'package:olive_client/palette_logic.dart';

void main() {
  const history = [
    ColourChoice(colourId: 'grape', chosenAt: '2026-08-03T09:00:00Z', via: 'daily'),
    ColourChoice(colourId: 'sunny', chosenAt: '2026-08-04T09:00:00Z', via: 'daily'),
  ];

  Future<void> pump(WidgetTester tester, {List<ColourChoice> h = history, String today = '2026-08-04'}) =>
      tester.pumpWidget(MaterialApp(home: ColourParentScreen(
        childName: 'Ivy', history: h, today: today)));

  group('parentView — pure logic', () {
    test('states what she picked and flags a same-day change', () {
      final v = parentView(history, '2026-08-04');
      expect(v!.label, 'sunny yellow');
      expect(v.changedToday, isTrue);
      expect(v.line, 'Today her colour is sunny yellow.');
    });

    test('no change today reads as a plain statement of fact', () {
      final v = parentView(history, '2026-08-05');
      expect(v!.changedToday, isFalse);
      expect(v.line, 'Her colour is sunny yellow.');
    });

    test('empty history has no view at all — not an error, just nothing yet', () {
      expect(parentView(const [], '2026-08-04'), isNull);
    });
  });

  testWidgets('renders her colour and the neutral one-line sentence', (tester) async {
    await pump(tester);
    expect(find.text('Today her colour is sunny yellow.'), findsOneWidget);
  });

  testWidgets('states explicitly that the guardian cannot change it', (tester) async {
    await pump(tester);
    expect(find.textContaining('cannot change'), findsOneWidget);
  });

  testWidgets('empty history shows an honest empty state, not an error', (tester) async {
    await pump(tester, h: const []);
    expect(find.text('No colour chosen yet.'), findsOneWidget);
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('there is no edit control of any kind — read-only by construction', (tester) async {
    await pump(tester);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('no mood, sentiment, trend, or streak language ever appears', (tester) async {
    await pump(tester);
    for (final word in colourForbidden) {
      expect(find.textContaining(word, findRichText: true), findsNothing,
        reason: '"$word" must never appear in the guardian colour view');
    }
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. A long child name stresses the AppBar
    // title, the one flexible-width element on this otherwise fixed layout.
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
        await tester.pumpWidget(const MaterialApp(home: ColourParentScreen(
          childName: 'Alexandria-Persephone-Winterbourne', history: history, today: '2026-08-04')));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
