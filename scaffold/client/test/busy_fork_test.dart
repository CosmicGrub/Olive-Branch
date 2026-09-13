// OLIVE BRANCH — busy fork tests. MASTERFILE §9.13.4. Asserts the same
// properties packages/live/src/around.ts's own suite asserts, plus what
// actually renders in the widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/busy_fork.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/message_banking.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('busy fork — pure logic', () {
    test('every reason produces a plain, non-blaming line', () {
      for (final u in Unavailable.values) {
        final f = busyFork(u, 'later');
        expect(f.line, isNotEmpty);
        expect(f.offerBanking, isTrue);
      }
    });

    test('an attempt is never a failure: banking is always offered', () {
      final f = busyFork(Unavailable.asleep, '7:00 AM her time');
      expect(f.offerBanking, isTrue);
      expect(f.nextWindow, '7:00 AM her time');
    });

    test('urgent path only appears when the situation genuinely warrants it', () {
      final normal = busyFork(Unavailable.school, 'later');
      expect(normal.urgentPath, isNull);
      final emergency = busyFork(Unavailable.school, 'later', emergency: true);
      expect(emergency.urgentPath, isNotNull);
    });

    test('nothing in any fork reads as refusal, rejection, or her decision', () {
      for (final u in Unavailable.values) {
        expect(auditBusyFork(busyFork(u, 'later', emergency: true)), isTrue,
          reason: 'reason=$u must never contain a banned word');
      }
    });

    test('a deliberately bad line fails the audit — proves the check is live', () {
      const bad = BusyFork(reason: Unavailable.school,
        line: 'She declined your call.', nextWindow: null);
      expect(auditBusyFork(bad), isFalse);
    });

    test('she is never shown a missed call', () {
      expect(attemptVisibleToChild(), isFalse);
    });
  });

  group('BusyForkScreen — guardian-facing render', () {
    testWidgets('states the fact plainly and offers banking, never a failure', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(
        childName: 'Ivy', initialReason: Unavailable.school)));
      expect(find.text('She is at school.'), findsOneWidget);
      expect(find.text('Bank a message instead'), findsOneWidget);
      for (final word in busyBanned) {
        expect(find.textContaining(word), findsNothing, reason: 'banned word "$word" leaked');
      }
    });

    testWidgets('banking button reaches the real message banking screen', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(
        childName: 'Ivy', initialReason: Unavailable.asleep)));
      await t.tap(find.text('Bank a message instead'));
      await t.pumpAndSettle();
      expect(find.byType(MessageBankingScreen), findsOneWidget);
    });

    testWidgets('the emergency path is offered when the situation warrants it', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(
        childName: 'Ivy', initialReason: Unavailable.school, emergencyPathOffered: true)));
      expect(find.text('Open the emergency card'), findsOneWidget);
      await t.tap(find.text('Open the emergency card'));
      await t.pumpAndSettle();
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
    });

    testWidgets('the emergency path is absent when it was not offered', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(
        childName: 'Ivy', initialReason: Unavailable.school, emergencyPathOffered: false)));
      expect(find.text('Open the emergency card'), findsNothing);
    });

    testWidgets('switching the demo reason updates the stated fact and stays clean', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(
        childName: 'Ivy', initialReason: Unavailable.school)));
      await t.tap(find.text('Asleep'));
      await t.pumpAndSettle();
      expect(find.text('She is asleep.'), findsOneWidget);
      for (final word in busyBanned) {
        expect(find.textContaining(word), findsNothing);
      }
    });

    testWidgets('P6 — no financial figure anywhere on this surface', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(childName: 'Ivy')));
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('touch targets are at least 48dp', (t) async {
      await t.pumpWidget(wrap(const BusyForkScreen(childName: 'Ivy')));
      final Size bank = t.getSize(find.byType(FilledButton).first);
      expect(bank.height, greaterThanOrEqualTo(48.0));
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
      testWidgets('renders the fork, the emergency path, and the reason chips '
          'without overflow at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(wrap(const BusyForkScreen(
          childName: 'Ivy', initialReason: Unavailable.withOtherParent)));
        expect(t.takeException(), isNull);

        final withOtherParent = find.text('At her other house');
        await t.ensureVisible(withOtherParent);
        await t.pumpAndSettle();
        await t.tap(withOtherParent);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
