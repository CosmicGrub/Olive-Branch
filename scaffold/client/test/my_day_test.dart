// OLIVE BRANCH — my_day.dart tests. §8.2, §8.2.2, §8.4.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/calendar_day_logic.dart';
import 'package:olive_client/my_day.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('My day — §8.2', () {
    testWidgets('renders the child by name, not by id', (tester) async {
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      expect(find.textContaining("Ivy's day"), findsOneWidget);
    });

    testWidgets('names the current day-part in a plain sentence', (tester) async {
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      expect(find.textContaining('Right now: get ready'), findsOneWidget);
    });

    testWidgets('every day-part in the schedule renders somewhere on screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      for (final DayPartLite p in demoDayParts) {
        expect(find.text(dayPartLabel(p.kind)), findsOneWidget,
          reason: '${p.kind} should render exactly once');
      }
    });

    testWidgets('NO settings affordance exists at any depth', (tester) async {
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('never shows an hours-based countdown', (tester) async {
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      expect(find.textContaining('hours until'), findsNothing);
      expect(find.textContaining('hour until'), findsNothing);
    });

    testWidgets('no error copy is ever shown on this screen', (tester) async {
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets('tapping a day-part card is a real interaction: it reveals detail',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));

      const String blurb = 'Breakfast, teeth, backpack — almost go time.';
      expect(find.text(blurb), findsNothing);
      // Exact match on the card's own label — "Right now: get ready" also
      // contains the substring "get ready" but is not the tappable card.
      await tester.tap(find.text('get ready'));
      await tester.pumpAndSettle();
      expect(find.text(blurb), findsOneWidget);

      // Tapping again collapses it back.
      await tester.tap(find.text('get ready'));
      await tester.pumpAndSettle();
      expect(find.text(blurb), findsNothing);
    });

    testWidgets('day-part cards meet the 48dp+ touch target minimum', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MyDayScreen(
        childName: 'Ivy', parts: demoDayParts, nowLocal: '07:15')));
      final int count = find.byType(InkWell).evaluate().length;
      expect(count, greaterThan(0));
      for (int i = 0; i < count; i++) {
        final Size size = tester.getSize(find.byType(InkWell).at(i));
        expect(size.height, greaterThanOrEqualTo(48.0));
      }
    });
  });
}
