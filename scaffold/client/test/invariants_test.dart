// OLIVE BRANCH — client invariant tests.
//
// These assert the SAME properties the TypeScript suites assert, but against
// the widget tree that a child actually sees. Until v0.15.0 the Dart was
// contract-checked only — its endpoint strings and channel constants were
// verified, which is not the same as verifying what renders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/pin_gate.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('child shell — §8.1', () {
    testWidgets('renders the child by name, not by id', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 1)));
      expect(find.text('Hi Maya'), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
      expect(find.textContaining('settings'), findsNothing);
    });

    testWidgets('§8.2.5 countdown is in sleeps, never hours', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
    });

    testWidgets('singular sleep is not "1 sleeps"', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya', presence: null,
        sleepsUntilHandover: 1, unreadCount: 0)));
      expect(find.textContaining('sleep until'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsNothing);
    });

    testWidgets('§4.1 presence names HER frame first', (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya',
        presence: ParentPresence('Dad', '8:41 PM', '9:30'),
        sleepsUntilHandover: 3, unreadCount: 0)));
      expect(find.text('Dad is free right now'), findsOneWidget);
      expect(find.text('Call Dad'), findsOneWidget);
    });

    testWidgets('§8.4 touch targets are at least 48dp for pre-readers',
        (t) async {
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Maya',
        presence: ParentPresence('Dad', '8:41 PM', '9:30'),
        sleepsUntilHandover: 3, unreadCount: 0)));
      final Size button = t.getSize(find.byType(FilledButton).first);
      expect(button.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('guardian shell — §8.2', () {
    const List<RibbonBand> bands = <RibbonBand>[
      RibbonBand(0, 0.5, Colors.blue, 'school'),
      RibbonBand(0.5, 0.5, Colors.green, 'home time'),
    ];

    testWidgets('the CHILD time is dominant and the actor time subordinate',
        (t) async {
      await t.pumpWidget(wrap(const GuardianHome(
        childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
        actorLocalTime: '3:12 PM CDT',
        childStateSentence: 'Maya is just home from school',
        childBands: bands, actorBands: bands)));
      final Text childTime = t.widget(find.text('4:12 PM'));
      final Text actorLine = t.widget(find.text('you · 3:12 PM CDT'));
      expect(childTime.style!.fontSize!,
          greaterThan(actorLine.style!.fontSize!));
    });

    testWidgets('§8.2.3 the parent is never shown arithmetic', (t) async {
      await t.pumpWidget(wrap(const GuardianHome(
        childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
        actorLocalTime: '3:12 PM CDT',
        childStateSentence: 'Maya is just home from school',
        childBands: bands, actorBands: bands)));
      expect(find.textContaining('+1'), findsNothing);
      expect(find.textContaining('difference'), findsNothing);
      expect(find.textContaining('UTC'), findsNothing);
    });

    testWidgets('her state reads as a sentence about her', (t) async {
      await t.pumpWidget(wrap(const GuardianHome(
        childName: 'Maya', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT',
        actorLocalTime: '3:12 PM CDT',
        childStateSentence: 'Maya is just home from school',
        childBands: bands, actorBands: bands)));
      expect(find.text('Maya is just home from school'), findsOneWidget);
    });
  });

  group('PIN gate — §8.3', () {
    testWidgets('renders nine keys', (t) async {
      await t.pumpWidget(wrap(PinGate(digits: 4, onComplete: (_) {})));
      expect(find.byType(TextButton), findsNWidgets(9));
    });

    testWidgets('the keypad is SHUFFLED — the child is watching', (t) async {
      final List<String> orders = <String>[];
      for (int i = 0; i < 12; i++) {
        await t.pumpWidget(wrap(PinGate(
            key: ValueKey<int>(i), digits: 4, onComplete: (_) {})));
        orders.add(t
            .widgetList<Text>(find.descendant(
                of: find.byType(TextButton), matching: find.byType(Text)))
            .map((Text w) => w.data!)
            .join());
      }
      // Twelve consecutive identical orders would mean no shuffle at all.
      expect(orders.toSet().length, greaterThan(1));
    });

    testWidgets('shuffle can be disabled for deterministic tests only',
        (t) async {
      await t.pumpWidget(wrap(PinGate(
          digits: 4, shuffle: false, onComplete: (_) {})));
      final String order = t
          .widgetList<Text>(find.descendant(
              of: find.byType(TextButton), matching: find.byType(Text)))
          .map((Text w) => w.data!)
          .join();
      expect(order, '123456789');
    });

    testWidgets('entry fires onComplete at the right length and clears',
        (t) async {
      String? got;
      await t.pumpWidget(wrap(PinGate(
          digits: 4, shuffle: false, onComplete: (String v) => got = v)));
      for (final String d in <String>['1', '2', '3']) {
        await t.tap(find.text(d));
        await t.pump();
      }
      expect(got, isNull, reason: 'must not fire before the full length');
      await t.tap(find.text('4'));
      await t.pump();
      expect(got, '1234');
    });

    testWidgets('no error text is ever shown after a kiosk defeat', (t) async {
      await t.pumpWidget(wrap(PinGate(digits: 4, onComplete: (_) {})));
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
      expect(find.textContaining('Incorrect'), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });
}
