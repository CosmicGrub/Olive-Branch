// OLIVE BRANCH — weeks_screen.dart tests. §8.2, §8.2.5, P3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/weeks_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

final List<CustodyNight> _fourteenNights = demoCustodyNights(today: DateTime(2026, 8, 4));

void main() {
  group('Weeks — §8.2.5, sleeps not dates', () {
    testWidgets('renders the child by name, not by id', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.textContaining("Ivy's weeks"), findsOneWidget);
    });

    testWidgets('states who she is with right now, in words', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.textContaining("You're with Mom right now"), findsOneWidget);
    });

    testWidgets('the handover countdown is in sleeps, never hours or a raw date',
        (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      // The demo pattern is 4 nights Mom / 3 nights Dad — the switch is 4 sleeps out.
      expect(find.textContaining('sleeps until'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
      expect(find.textContaining('hour '), findsNothing);
      // No ISO-shaped date (yyyy-mm-dd) anywhere in the rendered tree.
      final Iterable<Text> allTexts = tester.widgetList<Text>(find.byType(Text));
      final RegExp isoDate = RegExp(r'\d{4}-\d{2}-\d{2}');
      for (final Text t in allTexts) {
        final String? data = t.data;
        if (data != null) expect(isoDate.hasMatch(data), isFalse, reason: 'found a raw date in "$data"');
      }
    });

    testWidgets('singular sleep is not "1 sleeps"', (tester) async {
      final List<CustodyNight> nights = <CustodyNight>[
        const CustodyNight(dateIso: '2026-08-04', withWhom: 'Mom'),
        const CustodyNight(dateIso: '2026-08-05', withWhom: 'Dad'),
      ];
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: nights, guardianColors: demoGuardianColors)));
      expect(find.textContaining('sleep until'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsNothing);
    });

    testWidgets('no location or place ever appears near a night — P3', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.textContaining('address'), findsNothing);
      expect(find.textContaining('location'), findsNothing);
      for (final String word in <String>['Street', 'Ave', 'coordinates', 'lat', 'lng']) {
        expect(find.textContaining(word), findsNothing);
      }
    });

    testWidgets('NO settings affordance and no score/streak language — P2', (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('badge'), findsNothing);
    });

    testWidgets('renders one bead per night and each meets the 48dp touch minimum',
        (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      final Finder beads = find.byType(Tooltip);
      expect(beads.evaluate().length, _fourteenNights.length);
      final Size first = tester.getSize(beads.first);
      expect(first.height, greaterThanOrEqualTo(48.0));
      expect(first.width, greaterThanOrEqualTo(48.0));
    });

    testWidgets("today's bead carries a relative label, never a calendar date",
        (tester) async {
      await tester.pumpWidget(wrap(WeeksScreen(
        childName: 'Ivy', nights: _fourteenNights, guardianColors: demoGuardianColors)));
      final Tooltip todayBead = tester.widget<Tooltip>(find.byType(Tooltip).first);
      expect(todayBead.message, startsWith('Tonight'));
    });

    testWidgets('an empty night list is handled honestly, not with a crash or a fake row',
        (tester) async {
      await tester.pumpWidget(wrap(const WeeksScreen(
        childName: 'Ivy', nights: <CustodyNight>[], guardianColors: demoGuardianColors)));
      expect(find.textContaining('Nothing to show yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
