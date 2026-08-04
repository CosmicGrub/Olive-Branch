// OLIVE BRANCH — shared reading widget tests. MASTERFILE §9.13.2.
//
// Same posture as invariants_test.dart. The two load-bearing properties,
// straight from the masterfile section this screen renders:
//   - Page turning belongs to HER screen only — his screen has no arrows.
//   - No page count or percentage ever reaches her screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/shared_reading.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> useNarrowSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('her screen — she turns the pages, §9.13.2', () {
    testWidgets('opens on her screen by default, with turn controls', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      expect(find.byKey(const Key('herScreen')), findsOneWidget);
      expect(find.text('Turn the page'), findsOneWidget);
    });

    testWidgets('P2 — no page count or percentage digit reaches her screen', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      final herScreen = find.byKey(const Key('herScreen'));
      final texts = tester.widgetList<Text>(find.descendant(of: herScreen, matching: find.byType(Text)));
      for (final t in texts) {
        final data = t.data ?? '';
        // A real "N of M" position readout (as her line-count-showing sibling
        // widget in the "his screen" group below legitimately renders) —
        // not simply the ordinary word "of" appearing in generated prose.
        expect(data, isNot(matches(RegExp(r'\d+\s*(/|of)\s*\d+'))),
          reason: '"$data" looks like a page count');
        expect(data, isNot(contains('%')));
      }
    });

    testWidgets('Back is disabled on line one; turning back later is allowed, not an error',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      final back = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'));
      expect(back.onPressed, isNull);

      await tester.tap(find.text('Turn the page'));
      await tester.pumpAndSettle();
      final backAfter = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'));
      expect(backAfter.onPressed, isNotNull);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
    });

    testWidgets('reaching the last line offers reading another one together, not a score',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      // The grammar always emits exactly 12 lines regardless of seed.
      for (int i = 0; i < 11; i++) {
        await tester.tap(find.text('Turn the page'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Read another one together'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('§8.4 the turn-page control is at least 48dp', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      final size = tester.getSize(find.widgetWithText(FilledButton, 'Turn the page'));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('his screen — read-only, §9.13.2', () {
    testWidgets('flipping to his screen removes every turn control — structurally, not disabled',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      await tester.tap(find.text('His screen'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hisScreen')), findsOneWidget);
      expect(find.text('Turn the page'), findsNothing);
      expect(find.text('Back'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('his screen may plainly show a line count — the rule protects her, not him',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      await tester.tap(find.text('His screen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('line 1 of 12'), findsOneWidget);
    });
  });

  group('roles swap — some nights she reads, §9.13.2', () {
    testWidgets('swapping changes the reader label on both screens', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      expect(find.text('Dad is reading tonight'), findsOneWidget);

      await tester.tap(find.text('Swap: let Ivy read'));
      await tester.pump();
      expect(find.text('Ivy is reading tonight'), findsOneWidget);

      await tester.tap(find.text('His screen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ivy reads aloud'), findsOneWidget);
    });
  });

  group('no settings affordance', () {
    testWidgets('none at any depth, on either screen', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const SharedReadingScreen(childName: 'Ivy', readerName: 'Dad')));
      expect(find.byIcon(Icons.settings), findsNothing);
      await tester.tap(find.text('His screen'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsNothing);
    });
  });
}
