// OLIVE BRANCH — call security tests. MASTERFILE §5.19, §5.23. Asserts the
// same invariants packages/session-runtime/src/rooms.ts's own suite
// asserts (I1-I5), plus what actually renders in the widget tree.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_security_info.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('token invariants — pure logic', () {
    test('I1 — a room name never embeds a real identifier', () {
      expect(roomNameLeaks('child-a1c9e2fa-room', ['child-a1c9e2fa']), isTrue);
      expect(roomNameLeaks('s_9fQwErTy1234567890AbCdEf', ['child-a1c9e2fa', 'guardian-9f2e']),
        isFalse);
    });

    test('I1 — short secrets (under 6 chars) are never treated as leaks', () {
      expect(roomNameLeaks('s_abcxyz', ['Ivy']), isFalse);
    });

    test('I1 — two generated room names are not the same (real randomness)', () {
      final rng = Random.secure();
      final a = newOpaqueRoomName(rng);
      final b = newOpaqueRoomName(rng);
      expect(a, isNot(b));
      expect(a.startsWith('s_'), isTrue);
    });

    test('I5 — the TTL is exactly 600 seconds, not merely "short"', () {
      expect(tokenTtlSeconds, 600);
    });

    test('every check passes for a freshly generated demo room', () {
      final checks = runSecurityChecks(
        rng: Random(20260804),
        childId: 'child-a1c9e2fa-0000',
        guardianId: 'guardian-9f2e0000',
      );
      expect(checks.length, 5);
      expect(checks.map((c) => c.id), ['I1', 'I2', 'I3', 'I4', 'I5']);
      for (final c in checks) {
        expect(c.passed, isTrue, reason: '${c.id} (${c.title}) failed: ${c.detail}');
      }
    });
  });

  group('CallSecurityInfoScreen — guardian-facing render', () {
    testWidgets('shows all five invariants, all passing', (t) async {
      await t.pumpWidget(wrap(const CallSecurityInfoScreen()));
      expect(find.byIcon(Icons.check_circle), findsNWidgets(5));
      expect(find.byIcon(Icons.error), findsNothing);
      expect(find.textContaining('I1'), findsOneWidget);
      expect(find.textContaining('I5'), findsOneWidget);
      expect(find.textContaining('10 minutes'), findsOneWidget);
    });

    testWidgets('honestly labelled as a local demonstration, not a live wire capture',
        (t) async {
      await t.pumpWidget(wrap(const CallSecurityInfoScreen()));
      expect(find.textContaining('local demonstration'), findsOneWidget);
    });

    testWidgets('running the check again still passes and stays rendered', (t) async {
      await t.pumpWidget(wrap(const CallSecurityInfoScreen()));
      final runAgain = find.text('Run the check again');
      await t.ensureVisible(runAgain);
      await t.pumpAndSettle();
      await t.tap(runAgain);
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNWidgets(5));
    });

    testWidgets('touch targets are at least 48dp', (t) async {
      await t.pumpWidget(wrap(const CallSecurityInfoScreen()));
      final Size button = t.getSize(find.byType(OutlinedButton).first);
      expect(button.height, greaterThanOrEqualTo(48.0));
    });
  });
}
