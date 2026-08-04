// OLIVE BRANCH — lock_controller.dart tests. §5.20, §8.3.
//
// Mirrors packages/child-lock/test/lock.test.mjs's coverage against the Dart
// port, so the two stay provably in sync rather than just visually similar.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/lock_controller.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 20);
  DateTime t(Duration d) => now.add(d);

  group('initial state', () {
    test('starts on childHome', () {
      final s = initialState(LockMode.pinned);
      expect(s.surface, Surface.childHome);
      expect(s.failedAttempts, 0);
      expect(s.defeatCount, 0);
      expect(isEscalated(s, now), isFalse);
    });
  });

  group('lock-task exit — ordering and severity', () {
    test('lands on pinGate, defeat count increments, no notify on first defeat', () {
      final r = onLockTaskExited(initialState(LockMode.pinned), now);
      expect(r.state.surface, Surface.pinGate);
      expect(r.state.defeatCount, 1);
      expect(r.effects.notifyOtherGuardian, isFalse);
      expect(r.effects.auditEvent, 'kiosk_defeated');
    });

    test('escalation is dropped unconditionally and the other guardian is notified', () {
      final escalated = initialState(LockMode.pinned).copyWith(
        surface: Surface.guardianEscalation,
        escalatedUntil: t(escalationTtl),
        activeSessionId: 'sess-1',
      );
      final r = onLockTaskExited(escalated, now);
      expect(r.state.escalatedUntil, isNull);
      expect(r.state.surface, Surface.pinGate);
      expect(r.effects.revokeSessionTokens, 'sess-1');
      expect(r.effects.notifyOtherGuardian, isTrue);
      expect(r.effects.auditEvent, 'kiosk_defeated_while_escalated');
    });

    test('third defeat notifies even without a live escalation', () {
      final thrice = initialState(LockMode.pinned).copyWith(defeatCount: 2);
      expect(onLockTaskExited(thrice, now).effects.notifyOtherGuardian, isTrue);
    });
  });

  group('backgrounding — same token hazard, lower severity', () {
    test('revokes the token but never notifies on its own', () {
      final s = initialState(LockMode.pinned).copyWith(activeSessionId: 'sess-2');
      final r = onBackgrounded(s, now);
      expect(r.state.surface, Surface.pinGate);
      expect(r.effects.revokeSessionTokens, 'sess-2');
      expect(r.effects.notifyOtherGuardian, isFalse);
      expect(r.effects.auditEvent, 'backgrounded');
    });

    test('escalation drops here too, with a distinct audit event', () {
      final escalated = initialState(LockMode.pinned)
          .copyWith(surface: Surface.guardianEscalation, escalatedUntil: t(escalationTtl));
      final r = onBackgrounded(escalated, now);
      expect(r.state.escalatedUntil, isNull);
      expect(r.effects.auditEvent, 'backgrounded_while_escalated');
    });
  });

  group('child PIN re-entry and cooldown', () {
    test('correct PIN returns to childHome and resets attempts', () {
      final s = initialState(LockMode.pinned).copyWith(surface: Surface.pinGate);
      final result = submitChildPin(s, true, now);
      expect(result.surface, Surface.childHome);
      expect(result.failedAttempts, 0);
    });

    test('the Nth miss locks out with a cooldown window', () {
      var s = initialState(LockMode.pinned).copyWith(surface: Surface.pinGate);
      for (var i = 0; i < maxPinAttempts - 1; i++) {
        s = submitChildPin(s, false, now);
        expect(s.surface, Surface.pinGate, reason: 'miss $i should not lock out yet');
      }
      s = submitChildPin(s, false, now);
      expect(s.surface, Surface.lockedOut);
      expect(s.cooldownUntil, isNotNull);
    });

    test('a correct PIN mid-cooldown still refuses', () {
      final lockedOut = initialState(LockMode.pinned)
          .copyWith(surface: Surface.lockedOut, cooldownUntil: t(cooldownDuration));
      final result = submitChildPin(lockedOut, true, t(cooldownDuration - const Duration(seconds: 1)));
      expect(result.surface, Surface.lockedOut);
    });
  });

  group('guardian escalation — PIN AND biometric', () {
    test('a wrong PIN denies for pin, not biometric', () {
      final r = escalate(initialState(LockMode.pinned), false, true, now);
      expect(r.denied, 'pin');
      expect(r.state.surface, isNot(Surface.guardianEscalation));
    });

    test('PIN alone without biometric is refused', () {
      final r = escalate(initialState(LockMode.pinned), true, false, now);
      expect(r.denied, 'biometric');
      expect(r.state.failedAttempts, 0, reason: 'a failed biometric is not a PIN failure');
    });

    test('PIN + biometric grants a live, TTL-bound escalation', () {
      final r = escalate(initialState(LockMode.pinned), true, true, now);
      expect(r.state.surface, Surface.guardianEscalation);
      expect(r.state.escalatedUntil, isNotNull);
      expect(isEscalated(r.state, now), isTrue);
      expect(isEscalated(r.state, t(escalationTtl + const Duration(seconds: 1))), isFalse);
    });

    test('cooldown blocks escalation even with the right PIN + biometric', () {
      var s = initialState(LockMode.pinned);
      for (var i = 0; i < maxPinAttempts; i++) {
        s = escalate(s, false, true, now).state;
      }
      expect(escalate(s, true, true, now).denied, 'cooldown');
    });
  });

  group('break-glass — recovers access, never escalation', () {
    test('clears cooldown, resets attempts, grants no escalation', () {
      final lockedOut = initialState(LockMode.pinned).copyWith(
        surface: Surface.lockedOut,
        cooldownUntil: t(cooldownDuration),
        failedAttempts: maxPinAttempts,
      );
      final r = breakGlass(lockedOut, now);
      expect(r.state.surface, Surface.childHome);
      expect(r.state.cooldownUntil, isNull);
      expect(r.state.escalatedUntil, isNull);
      expect(r.auditEvent, 'break_glass_used');
    });
  });

  group('deny-by-default rendering', () {
    test('guardianEscalation never renders without a LIVE escalation', () {
      final home = initialState(LockMode.pinned);
      expect(canRender(home, Surface.guardianEscalation, now), isFalse);

      final stale = home.copyWith(
        surface: Surface.guardianEscalation,
        escalatedUntil: now.subtract(const Duration(seconds: 1)),
      );
      expect(canRender(stale, Surface.guardianEscalation, now), isFalse,
          reason: 'reached-but-expired must still deny');
    });

    test('pinGate does not render while on childHome', () {
      expect(canRender(initialState(LockMode.pinned), Surface.pinGate, now), isFalse);
    });
  });

  group('advisory — disclosed honestly', () {
    test('every escapable mode discloses escapability; locked does not', () {
      for (final mode in escapable) {
        expect(lockAdvisory(mode), contains('unlocked by your child'));
      }
      expect(lockAdvisory(LockMode.locked), isNot(contains('unlocked by your child')));
    });
  });
}
