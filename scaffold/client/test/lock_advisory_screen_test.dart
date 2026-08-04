// OLIVE BRANCH — kiosk advisory screen tests. MASTERFILE §5.20, §8.3. This
// screen must call the real lock_controller.dart lockAdvisory() rather than
// reinvent its copy — these tests assert the rendered text is IDENTICAL to
// what that already-tested function returns, for every mode.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/lock_advisory_screen.dart';
import 'package:olive_client/lock_controller.dart' as lock;

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('LockAdvisoryScreen — calls the real lockAdvisory()', () {
    for (final mode in lock.LockMode.values) {
      testWidgets('renders lockAdvisory(${mode.name}) verbatim, not reinvented copy',
          (t) async {
        await t.pumpWidget(wrap(LockAdvisoryScreen(initialMode: mode)));
        expect(find.text(lock.lockAdvisory(mode)), findsOneWidget);
      });
    }

    testWidgets('an escapable mode surfaces the re-entry PIN and cooldown story', (t) async {
      await t.pumpWidget(wrap(const LockAdvisoryScreen(initialMode: lock.LockMode.pinned)));
      expect(find.textContaining('shuffled PIN screen'), findsOneWidget);
      expect(find.textContaining('${lock.maxPinAttempts} wrong PINs'), findsOneWidget);
      expect(find.textContaining('${lock.cooldownDuration.inMinutes} minutes'), findsOneWidget);
      expect(find.textContaining('break-glass'), findsOneWidget);
    });

    testWidgets('the fully-locked mode does not claim an escape story it does not have',
        (t) async {
      await t.pumpWidget(wrap(const LockAdvisoryScreen(initialMode: lock.LockMode.locked)));
      expect(find.textContaining('shuffled PIN screen'), findsNothing);
      expect(find.textContaining('wrong PINs'), findsNothing);
      expect(find.text(lock.lockAdvisory(lock.LockMode.locked)), findsOneWidget);
    });

    testWidgets('switching platforms swaps the advisory text live, correctly each time',
        (t) async {
      await t.pumpWidget(wrap(const LockAdvisoryScreen(initialMode: lock.LockMode.pinned)));
      final assignedChip = find.text('Windows, Assigned Access');
      await t.ensureVisible(assignedChip);
      await t.pumpAndSettle();
      await t.tap(assignedChip);
      await t.pumpAndSettle();
      expect(find.text(lock.lockAdvisory(lock.LockMode.assigned)), findsOneWidget);
      // The header label is the discriminating proof the tap actually landed —
      // the advisory body text alone is shared across every escapable mode.
      expect(find.text('Windows, Assigned Access'), findsNWidgets(2));

      final noneChip = find.text('No kiosk support detected');
      await t.ensureVisible(noneChip);
      await t.pumpAndSettle();
      await t.tap(noneChip);
      await t.pumpAndSettle();
      expect(find.text(lock.lockAdvisory(lock.LockMode.none)), findsOneWidget);
      expect(find.text('No kiosk support detected'), findsNWidgets(2));
      // "none" is escapable — the PIN/cooldown story must reappear.
      expect(find.textContaining('shuffled PIN screen'), findsOneWidget);
    });

    testWidgets('no error copy and no settings affordance on this advisory surface',
        (t) async {
      await t.pumpWidget(wrap(const LockAdvisoryScreen()));
      expect(find.textContaining('error'), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
    });
  });
}
