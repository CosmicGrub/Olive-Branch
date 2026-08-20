// OLIVE BRANCH — family_agreement_screen.dart tests. §5.4, §9.4, §4.1.
//
// The central invariants under test: this screen renders the REAL custody
// order it's handed (pattern in plain words, order timezone, exchange time,
// anchor date, holiday rules), a child with no order gets an honest "no
// agreement on file" state rather than a crash or a guessed schedule, and a
// real fetch failure shows a real error state — never a faked success.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_agreement_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

const populatedOrderJson = <String, dynamic>{
  'order': <String, dynamic>{
    'pattern': '2-2-3',
    'orderTz': 'America/New_York',
    'anchorLocalDate': '2026-01-05',
    'exchangeTime': '18:00',
    'holidays': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Winter Break',
        'startMonthDay': '12-20',
        'endMonthDay': '01-02',
        'evenYearSide': 'A',
        'priority': 5,
      },
    ],
    'effectiveFrom': '2020-01-01',
    'effectiveTo': null,
  },
};

const overlappingHolidayA = HolidayRuleView(
  name: 'Winter Break', startMonthDay: '12-20', endMonthDay: '01-02',
  evenYearSide: 'A', priority: 3,
);
const overlappingHolidayB = HolidayRuleView(
  name: 'Christmas Day', startMonthDay: '12-24', endMonthDay: '12-26',
  evenYearSide: 'B', priority: 10,
);

void main() {
  group('sortedByPriority — the real tie-break schedule.ts\'s holidayOn() uses', () {
    test('higher priority sorts first, regardless of wire order', () {
      final sorted = sortedByPriority([overlappingHolidayA, overlappingHolidayB]);
      expect(sorted.map((h) => h.name), ['Christmas Day', 'Winter Break']);
    });

    test('a tie on priority breaks on the later start date, matching '
        'schedule.ts exactly', () {
      const earlyStart = HolidayRuleView(
        name: 'Early', startMonthDay: '12-20', endMonthDay: '12-23',
        evenYearSide: 'A', priority: 5);
      const laterStart = HolidayRuleView(
        name: 'Later, more specific', startMonthDay: '12-24', endMonthDay: '12-26',
        evenYearSide: 'B', priority: 5);
      final sorted = sortedByPriority([earlyStart, laterStart]);
      expect(sorted.map((h) => h.name), ['Later, more specific', 'Early']);
    });

    test('does not mutate the list it was given', () {
      final original = [overlappingHolidayA, overlappingHolidayB];
      sortedByPriority(original);
      expect(original, [overlappingHolidayA, overlappingHolidayB]);
    });
  });

  group('FamilyAgreementScreen — populated state', () {
    testWidgets('shows a loading indicator before the fetch resolves', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        childName: 'Ivy',
        fetchOrder: (id) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return populatedOrderJson;
        },
      )));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('renders the real pattern in plain words, not just the raw code', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        childName: 'Ivy',
        fetchOrder: (id) async => populatedOrderJson,
      )));
      await t.pumpAndSettle();

      expect(find.textContaining('2 nights, then 2 nights, then 3 nights'), findsOneWidget);
      expect(find.textContaining('Code: 2-2-3'), findsOneWidget);
    });

    testWidgets('renders the real order timezone, exchange time, and anchor date', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async => populatedOrderJson,
      )));
      await t.pumpAndSettle();

      expect(find.text('America/New_York'), findsWidgets);
      expect(find.textContaining('6:00 PM'), findsOneWidget);
      expect(find.text('Jan 5, 2026'), findsOneWidget); // anchor date
      expect(find.text('Jan 1, 2020'), findsOneWidget); // in effect from
      expect(find.text('Open-ended'), findsOneWidget); // effectiveTo: null
    });

    testWidgets('renders the real holiday rule with its even/odd-year side', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async => populatedOrderJson,
      )));
      await t.pumpAndSettle();

      expect(find.text('Winter Break'), findsOneWidget);
      expect(find.textContaining('Dec 20'), findsOneWidget);
      expect(find.textContaining('Jan 2'), findsOneWidget);
      expect(find.textContaining('Side A in even years'), findsOneWidget);
      expect(find.textContaining('Side B in odd years'), findsOneWidget);
      // v0.49.15: priority was parsed off the wire and never shown — the
      // real tie-break schedule.ts's own holidayOn() uses when rules overlap.
      expect(find.text('Priority 5'), findsOneWidget);
    });

    testWidgets('two overlapping holidays render highest-priority first, '
        'the same order the real engine would apply them in', (t) async {
      final orderWithOverlap = <String, dynamic>{
        'order': <String, dynamic>{
          ...populatedOrderJson['order'] as Map<String, dynamic>,
          'holidays': <Map<String, dynamic>>[
            // Deliberately wire-ordered LOWER priority first, so a passing
            // "renders in wire order" implementation would fail this.
            <String, dynamic>{
              'name': 'Winter Break', 'startMonthDay': '12-20', 'endMonthDay': '01-02',
              'evenYearSide': 'A', 'priority': 3,
            },
            <String, dynamic>{
              'name': 'Christmas Day', 'startMonthDay': '12-24', 'endMonthDay': '12-26',
              'evenYearSide': 'B', 'priority': 10,
            },
          ],
        },
      };
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async => orderWithOverlap,
      )));
      await t.pumpAndSettle();

      expect(find.text('Priority 10'), findsOneWidget);
      expect(find.text('Priority 3'), findsOneWidget);
      expect(find.textContaining('highest priority first'), findsOneWidget);
      // The real order these rules would actually apply in: Christmas (10)
      // before Winter Break (3) — proved by vertical position, not just
      // presence, since both cards exist in the tree either way.
      final double christmasY = t.getTopLeft(find.text('Christmas Day')).dy;
      final double winterBreakY = t.getTopLeft(find.text('Winter Break')).dy;
      expect(christmasY, lessThan(winterBreakY));
    });

    testWidgets('is read-only — no editing affordance anywhere on the ready state', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async => populatedOrderJson,
      )));
      await t.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(find.textContaining('Read-only'), findsOneWidget);
    });

    testWidgets('is honest that side-to-guardian-name mapping is not tracked', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async => populatedOrderJson,
      )));
      await t.pumpAndSettle();

      expect(find.textContaining('does not itself record'), findsOneWidget);
    });

    testWidgets('passes the real childId through to fetchOrder, never a guess', (t) async {
      String? seen;
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'real-child-id-42',
        fetchOrder: (id) async {
          seen = id;
          return populatedOrderJson;
        },
      )));
      await t.pumpAndSettle();
      expect(seen, 'real-child-id-42');
    });
  });

  group('FamilyAgreementScreen — empty state (no custody_order row)', () {
    testWidgets('a child with no order gets an honest "no agreement on file" state, not a crash',
        (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-no-order',
        childName: 'Ivy',
        fetchOrder: (id) async => <String, dynamic>{'order': null},
      )));
      await t.pumpAndSettle();

      expect(find.text('No agreement on file'), findsOneWidget);
      expect(find.textContaining('Ivy has no custody order entered yet'), findsOneWidget);
      expect(t.takeException(), isNull);
      // Never renders schedule chrome for a schedule that does not exist.
      expect(find.text('The pattern'), findsNothing);
      expect(find.text('Schedule details'), findsNothing);
    });
  });

  group('FamilyAgreementScreen — error state', () {
    testWidgets('a real fetch failure shows a real error, never a faked success', (t) async {
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async => throw StateError('no live backend'),
      )));
      await t.pumpAndSettle();

      expect(find.text("Couldn't load the agreement"), findsOneWidget);
      expect(find.textContaining('no live backend'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('The pattern'), findsNothing);
    });

    testWidgets('retry re-runs the fetch and can recover into the ready state', (t) async {
      var attempt = 0;
      await t.pumpWidget(wrap(FamilyAgreementScreen(
        childId: 'child-a',
        fetchOrder: (id) async {
          attempt++;
          if (attempt == 1) throw StateError('boom');
          return populatedOrderJson;
        },
      )));
      await t.pumpAndSettle();
      expect(find.text("Couldn't load the agreement"), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('The pattern'), findsOneWidget);
    });
  });

  group('responsive — required audit viewports', () {
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('renders the populated state without overflow at ${entry.key}', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(FamilyAgreementScreen(
          childId: 'child-a',
          fetchOrder: (id) async => populatedOrderJson,
        )));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
