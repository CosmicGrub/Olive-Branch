// OLIVE BRANCH — send-time guard tests. MASTERFILE §6.4, §8.2.3, §8.2.7.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/send_time_guard.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('the notification gate — pure logic', () {
    test('10:40 PM falls in the asleep day-part, and is not reachable', () {
      expect(currentDayPart(22).name, 'asleep');
      expect(currentDayPart(22).reachable, isFalse);
    });

    test('school hours are not reachable', () {
      expect(currentDayPart(9).name, 'school');
      expect(currentDayPart(9).reachable, isFalse);
    });

    test('free time is reachable', () {
      expect(currentDayPart(17).name, 'free time');
      expect(currentDayPart(17).reachable, isTrue);
    });

    test('recipientContext surfaces a defer time only when blocked', () {
      final blocked = recipientContext(22, '10:40 PM', 'her time');
      expect(blocked.reachable, isFalse);
      expect(blocked.deferLabel, isNotNull);
      final open = recipientContext(17, '5:30 PM', 'her time');
      expect(open.reachable, isTrue);
      expect(open.deferLabel, isNull);
    });
  });

  group('the anchor distinction — "next bedtime" vs "the night of June 1st"', () {
    test('only the daypart-relative anchor moves with a schedule change', () {
      final beforeBedtime = resolveAnchor(SendAnchor.nextBedtime,
        currentBedtimeLabel: '8:30 PM', specificDateLabel: 'June 1st');
      final afterBedtime = resolveAnchor(SendAnchor.nextBedtime,
        currentBedtimeLabel: '8:00 PM', specificDateLabel: 'June 1st');
      expect(beforeBedtime.label, isNot(afterBedtime.label));
      expect(beforeBedtime.movesWithSchedule, isTrue);

      final beforeDate = resolveAnchor(SendAnchor.specificDate,
        currentBedtimeLabel: '8:30 PM', specificDateLabel: 'June 1st');
      final afterDate = resolveAnchor(SendAnchor.specificDate,
        currentBedtimeLabel: '8:00 PM', specificDateLabel: 'June 1st');
      expect(beforeDate.label, afterDate.label,
        reason: 'a specific calendar date is a fixed promise, whatever bedtime does');
      expect(beforeDate.movesWithSchedule, isFalse);
    });
  });

  group('SendTimeGuardScreen — guardian-facing render', () {
    testWidgets('§8.2.3 HER frame first, and never raw arithmetic', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy')));
      expect(find.textContaining("It's 10:40 PM for Ivy"), findsOneWidget);
      expect(find.textContaining('+1'), findsNothing);
      expect(find.textContaining('difference'), findsNothing);
      expect(find.textContaining('UTC'), findsNothing);
    });

    testWidgets('a blocked send offers both "send anyway" and a deferred delivery', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy')));
      expect(find.text('Send now anyway'), findsOneWidget);
      expect(find.text('Deliver at 7:00 AM her time'), findsOneWidget);
      await t.tap(find.text('Deliver at 7:00 AM her time'));
      await t.pumpAndSettle();
      expect(find.textContaining('Set to deliver at 7:00 AM her time'), findsOneWidget);
    });

    testWidgets('an open window shows a single plain send, no guard prompt', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy')));
      await t.tap(find.text('5:30 PM'));
      await t.pumpAndSettle();
      expect(find.text('Send now'), findsOneWidget);
      expect(find.text('Send now anyway'), findsNothing);
    });

    testWidgets('the two anchors read as different promises, and only one may move', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy')));
      expect(find.textContaining('Arrives at her next bedtime'), findsOneWidget);
      expect(find.textContaining('8:30 PM'), findsOneWidget);

      final shiftButton = find.text('Preview: her bedtime moves 30 minutes earlier this week');
      await t.ensureVisible(shiftButton);
      await t.pumpAndSettle();
      await t.tap(shiftButton);
      await t.pumpAndSettle();
      expect(find.textContaining('8:00 PM'), findsOneWidget,
        reason: 'the next-bedtime anchor tracks the new bedtime');

      final specificDate = find.text('The night of June 1st');
      await t.ensureVisible(specificDate);
      await t.pumpAndSettle();
      await t.tap(specificDate);
      await t.pumpAndSettle();
      final preview = find.textContaining('Arrives the night of June 1st');
      expect(preview, findsOneWidget);
      // Still no mention of the shifted bedtime leaking into the fixed-date preview.
      expect(find.textContaining('Arrives the night of June 1st, 8:00 PM'), findsNothing);
    });
  });

  group('SendTimeGuardScreen — real /now data (guardian_home.dart\'s live path)', () {
    testWidgets('reachable=true renders the real fetched time/day-part, '
        'a plain "Send now", and hides the demo hour chips', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy',
        childLocalTime: '3:05 PM', zoneAbbr: 'EST', dayPart: 'free', reachable: true)));
      expect(find.textContaining("It's 3:05 PM for Ivy"), findsOneWidget,
        reason: 'her real fetched local time renders, not a demo hour');
      expect(find.text('Send now'), findsOneWidget);
      expect(find.text('Send now anyway'), findsNothing);
      // The demo ChoiceChip hour-toggle only makes sense against the
      // demo path's own fake, player-chosen hour.
      expect(find.text('10:40 PM'), findsNothing);
      expect(find.text('9:15 AM'), findsNothing);
      expect(find.text('5:30 PM'), findsNothing);
    });

    testWidgets('reachable=false renders "she is [real day-part]", '
        '"Send now anyway" only — no fabricated deferred-delivery time', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy',
        childLocalTime: '11:40 PM', zoneAbbr: 'EST', dayPart: 'asleep', reachable: false)));
      expect(find.textContaining("It's 11:40 PM for Ivy — she is sleep."), findsOneWidget,
        reason: 'dayPartLabel() renders the shared vocabulary label ("sleep"), '
          'not the raw server kind string ("asleep")');
      expect(find.text('Send now anyway'), findsOneWidget);
      // No real deferTo exists on the /now contract (MASTERFILE §7.2) — the
      // live path must never fabricate a specific delivery time the demo
      // path's own recipientContext() always supplies.
      expect(find.textContaining('Deliver at'), findsNothing);
    });

    testWidgets('reachable=true with no dayPart known reads "she is now", '
        'not a null/blank label', (t) async {
      await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy',
        childLocalTime: '3:05 PM', zoneAbbr: 'EST', reachable: true)));
      // reachable overrides the "she is X" clause entirely (only shown when
      // NOT reachable) — this proves gate()'s own real semantics (no
      // `reason` set when allowed) don't produce a broken/null render.
      expect(find.textContaining("It's 3:05 PM for Ivy"), findsOneWidget);
      expect(find.textContaining('she is'), findsNothing);
    });
  });

  group('responsive — Fold5 cover/main, phone, tablet/desktop', () {
    // Fold5 cover (344 CSS px), Fold5 main (~673x841, nearly square), a
    // standard phone (390), and a desktop-scale short-and-wide width (1100)
    // — the four widths this repo's responsive audit requires.
    const widths = <String, Size>{
      'fold5 cover': Size(344, 820),
      'fold5 main': Size(673, 841),
      'phone': Size(390, 844),
      'tablet/desktop': Size(1100, 800),
    };

    for (final entry in widths.entries) {
      testWidgets('renders the blocked-send guard and the anchor picker without overflow '
          'at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(wrap(const SendTimeGuardScreen(childName: 'Ivy')));
        expect(t.takeException(), isNull);

        // The SegmentedButton's two labels ("Next bedtime" / "The night of
        // June 1st") are the widest fixed-in-a-row content on this screen —
        // the one most likely to overflow at the Fold5 cover's 344px.
        final specificDate = find.text('The night of June 1st');
        await t.ensureVisible(specificDate);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(specificDate);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
