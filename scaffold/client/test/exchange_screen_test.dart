// OLIVE BRANCH — exchange screen tests. §4, §9.7, P3.
//
// P3 is the load-bearing invariant: arrival is an event, never a place, and
// no coordinate may ever reach this screen's widget tree. The rest checks
// the ported schedule.ts / care.ts logic directly, and the bag manifest /
// running-late / arrival interactions actually work.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/exchange_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

// Tall surface so the whole ListView is actually laid out by its sliver —
// several assertions below (bag manifest checkboxes, running late, arrival)
// sit below the fold at the default test viewport, and a widget that is not
// built cannot be told apart from one that is genuinely absent. Same fix
// emergency_card_test.dart already applies for the same reason.
Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('schedule.ts port — pure logic', () {
    final Order order = Order(
      pattern: cycle223,
      anchorLocalDate: DateTime.utc(2026, 1, 1),
      holidays: const <HolidayRule>[
        HolidayRule(name: 'Winter break', startMonthDay: '12-20', endMonthDay: '01-02',
          evenYearSide: Side.b, priority: 5),
      ],
      orderTimeLabel: '6:00 PM Central',
    );

    test('anchor date is side A, day 0 of the 14-day cycle', () {
      expect(patternSideOn(order, DateTime.utc(2026, 1, 1)), Side.a);
    });

    test('a holiday rule overrides the base pattern', () {
      final ({Side side, String source, String? holidayName}) s =
        sideOn(order, DateTime.utc(2026, 12, 25));
      expect(s.source, 'holiday');
      expect(s.holidayName, 'Winter break');
    });

    test('sleepsUntilSideChange counts child-local day boundaries', () {
      final ({int sleeps, Side nextSide, DateTime onLocalDate})? next =
        sleepsUntilSideChange(order, DateTime.utc(2026, 1, 1));
      expect(next, isNotNull);
      expect(next!.sleeps, greaterThan(0));
    });

    test('blocks() merges contiguous same-side days into one block', () {
      // Jan 5-7 fall outside the "Winter break" holiday window (which wraps
      // Dec 20 - Jan 2) and are pattern days 4, 5, 6 of cycle223 — all side A
      // — so they should merge into a single block.
      final List<Block> bs = blocks(order, DateTime.utc(2026, 1, 5), DateTime.utc(2026, 1, 7));
      expect(bs.length, 1);
      expect(bs.first.side, Side.a);
      expect(bs.first.startLocalDate, DateTime.utc(2026, 1, 5));
      expect(bs.first.endLocalDate, DateTime.utc(2026, 1, 7));
    });
  });

  group('care.ts port — bag manifest and arrival', () {
    test('manifestOrder puts essential items first', () {
      final List<BagItem> items = <BagItem>[
        BagItem(id: 'a', label: 'Toy', essential: false),
        BagItem(id: 'b', label: 'Inhaler', essential: true),
      ];
      final List<BagItem> ordered = manifestOrder(items);
      expect(ordered.first.label, 'Inhaler');
    });

    test('recordArrival never accepts or requires a location parameter', () {
      final DateTime scheduled = DateTime.utc(2026, 8, 4, 18, 0);
      final ArrivalEvent e = recordArrival('x', scheduled, scheduled.add(const Duration(minutes: 6)));
      expect(e.delayMinutes, 6);
    });

    test('auditArrivalPayload — P3 — flags any location-shaped key', () {
      final ({bool ok, List<String> leaks}) clean = auditArrivalPayload(<String, Object?>{
        'exchangeId': 'x', 'delayMinutes': 3});
      expect(clean.ok, isTrue);
      final ({bool ok, List<String> leaks}) dirty = auditArrivalPayload(<String, Object?>{
        'exchangeId': 'x', 'latitude': 35.2});
      expect(dirty.ok, isFalse);
      expect(dirty.leaks, contains('latitude'));
    });
  });

  group('ExchangeScreen widget', () {
    testWidgets('renders the handoff in sleeps, in her frame', (t) async {
      await pump(t, const ExchangeScreen(childName: 'Ivy'));
      expect(find.textContaining('Ivy goes to'), findsOneWidget);
      expect(find.textContaining('sleep'), findsWidgets);
    });

    testWidgets('P3 — no coordinate or address text ever appears', (t) async {
      await pump(t, const ExchangeScreen());
      await t.tap(find.text('Log arrival'));
      await t.pump();
      // Deliberately whole, unambiguous terms — a naive substring like "lat"
      // would false-positive on the legitimate word "late" elsewhere on
      // this very screen ("Running late").
      for (final String forbidden in <String>[
        'latitude', 'longitude', 'coordinate', 'address', 'geohash', 'accuracy']) {
        expect(find.textContaining(forbidden), findsNothing,
          reason: 'found forbidden location term "$forbidden"');
      }
    });

    testWidgets('toggling a bag item checkbox is a real interaction', (t) async {
      await pump(t, const ExchangeScreen());
      final Finder sentBoxes = find.byType(Checkbox);
      expect(sentBoxes, findsWidgets);
      final Checkbox before = t.widget(sentBoxes.first);
      await t.tap(sentBoxes.first);
      await t.pump();
      final Checkbox after = t.widget(sentBoxes.first);
      expect(after.value, isNot(equals(before.value)));
    });

    testWidgets('running late logs an immutable, appended entry', (t) async {
      await pump(t, const ExchangeScreen());
      expect(find.textContaining('ETA +'), findsNothing);
      await t.tap(find.text('Running 10 min late'));
      await t.pump();
      expect(find.textContaining('ETA +10 min'), findsOneWidget);
      // No delete/edit affordance on the running-late log.
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('logging arrival reports it as an event, never a place', (t) async {
      await pump(t, const ExchangeScreen(childName: 'Ivy'));
      await t.tap(find.text('Log arrival'));
      await t.pump();
      expect(find.textContaining('Ivy arrived'), findsOneWidget);
    });

    testWidgets('no raw arithmetic language appears anywhere', (t) async {
      await pump(t, const ExchangeScreen());
      expect(find.textContaining('+1'), findsNothing);
      expect(find.textContaining('UTC'), findsNothing);
      expect(find.textContaining('difference'), findsNothing);
    });
  });
}
