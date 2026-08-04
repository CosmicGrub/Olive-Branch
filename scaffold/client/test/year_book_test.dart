// OLIVE BRANCH — Year Book screen tests. §2.10, §9.8.2.
//
// Widget-level checks against the actual rendered screen — the numbers shown
// must be `compileYearBook()`'s real output for the selected year, the
// unprintable state must be stated honestly rather than hidden, and no
// financial or streak-shaped language belongs on a guardian memento screen
// either.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/year_book.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  // The demo book is tall (cover, places, four sections, printable card);
  // give it room the same way emergency_card_test.dart does for its screen.
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(const YearBookScreen()));
  }

  group('YearBookScreen', () {
    testWidgets('defaults to a real, printable year and says so', (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('2025'), findsWidgets); // year chip + cover headline
      expect(find.textContaining('Ready to print'), findsOneWidget);
    });

    testWidgets('switching to a sparse year shows the honest "not a book yet" state',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '2023'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not a book yet'), findsOneWidget);
      expect(find.textContaining('Ready to print'), findsNothing);
      expect(find.textContaining('slideshow'), findsOneWidget);
    });

    testWidgets('an in-progress current-ish year with few pieces is also honest',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '2026'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not a book yet'), findsOneWidget);
    });

    testWidgets('the printable Year Book button is an honest stub, not a fake success',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Order the printed Year Book'));
      await tester.pump();
      expect(find.textContaining("isn't connected yet"), findsOneWidget);
    });

    testWidgets('sections render with their documented titles', (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.text('Things you said'), findsOneWidget);
      expect(find.text('Things you made'), findsOneWidget);
      expect(find.text('Things you learned'), findsOneWidget);
      expect(find.text('Moments'), findsOneWidget);
    });

    testWidgets('places are shown as zone + day count, never as coordinates — P3',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.textContaining("Mom's"), findsWidgets);
      expect(find.textContaining('day'), findsWidgets);
      expect(find.textContaining('°'), findsNothing);
      // No decimal-degree-shaped numbers anywhere on the surface.
      final Iterable<Text> allText = tester.widgetList<Text>(find.byType(Text));
      for (final Text t in allText) {
        final String? data = t.data;
        if (data == null) continue;
        expect(RegExp(r'-?\d{1,3}\.\d{3,}').hasMatch(data), isFalse,
            reason: 'looked like a coordinate: "$data"');
      }
    });

    testWidgets('no price, no financial language anywhere on this screen',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('\$'), findsNothing);
      expect(find.textContaining('cost'), findsNothing);
      expect(find.textContaining('price'), findsNothing);
    });

    testWidgets('no settings affordance and no streak/score language — P2 hygiene',
        (WidgetTester tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
    });
  });
}
