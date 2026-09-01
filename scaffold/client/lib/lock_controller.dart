// OLIVE BRANCH — child lock state machine. No longer UNVERIFIED — verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// CHANGELOG v0.49.61). MASTERFILE §5.20, §8.3.
//
// A 1:1 semantic port of packages/child-lock/src/lock.ts, kept deliberately
// close to the TS original (same function names, same shapes, same ordering)
// so the two stay auditable side by side — the same discipline this codebase
// already applies to the cross-language kiosk-channel contract (see
// kiosk_channel.dart / KioskBridge.kt / kiosk_bridge.cpp).
//
// One intentional adaptation: `escalatedUntil`/`cooldownUntil` are DateTime?
// here rather than ISO-string-or-null. The TS version stores strings because
// that state can travel over a wire; this controller is purely local to one
// running app, so there's no serialization boundary forcing string form, and
// DateTime avoids a parse on every read. Semantics are unchanged.
//
// The platform primitives are unreliable by design:
//
//  Android  `startLockTask()` in PINNED mode (no device-owner) can be exited by
//           the child holding Back + Recents. Only LOCK_TASK_MODE_LOCKED, which
//           needs device-owner provisioning, is actually escape-proof. Most
//           installs will be PINNED.
//  Windows  Assigned Access can be exited with Ctrl+Alt+Del.
//  iOS      Guided Access requires a passcode to exit, but can be disabled if
//           the child knows the device passcode.
//
// So defeat is not an exception — it is an expected event. The question this
// class answers is what the child is looking at one frame after it happens.
// The answer is never "the guardian surface".

enum LockMode {
  locked, // Android device-owner LOCK_TASK_MODE_LOCKED, escape-proof
  pinned, // Android PINNED, escapable
  assigned, // Windows Assigned Access
  guided, // iOS Guided Access
  none; // no OS enforcement available

  /// Mirrors kiosk_channel.dart's string wire format ('locked'/'pinned'/'none').
  static LockMode fromWire(String s) => switch (s) {
    'locked' => LockMode.locked,
    'pinned' => LockMode.pinned,
    'assigned' => LockMode.assigned,
    'guided' => LockMode.guided,
    _ => LockMode.none,
  };
}

enum Surface {
  childHome,
  childSession,
  pinGate, // re-entry: child PIN
  guardianEscalation,
  lockedOut, // cooldown after repeated failures
}

/// Modes a child can escape without an adult. Drives how loudly we react.
const escapable = [LockMode.pinned, LockMode.assigned, LockMode.guided, LockMode.none];

const escalationTtl = Duration(minutes: 15);
const maxPinAttempts = 5;
const cooldownDuration = Duration(minutes: 5);

class LockState {
  const LockState({
    required this.mode,
    required this.surface,
    this.escalatedUntil,
    this.failedAttempts = 0,
    this.cooldownUntil,
    this.activeSessionId,
    this.defeatCount = 0,
  });

  final LockMode mode;
  final Surface surface;
  /// Guardian scope, granted by PIN + biometric. Expires.
  final DateTime? escalatedUntil;
  final int failedAttempts;
  final DateTime? cooldownUntil;
  final String? activeSessionId;
  final int defeatCount;

  LockState copyWith({
    LockMode? mode,
    Surface? surface,
    DateTime? escalatedUntil,
    bool clearEscalatedUntil = false,
    int? failedAttempts,
    DateTime? cooldownUntil,
    bool clearCooldownUntil = false,
    String? activeSessionId,
    bool clearActiveSessionId = false,
    int? defeatCount,
  }) => LockState(
    mode: mode ?? this.mode,
    surface: surface ?? this.surface,
    escalatedUntil: clearEscalatedUntil ? null : (escalatedUntil ?? this.escalatedUntil),
    failedAttempts: failedAttempts ?? this.failedAttempts,
    cooldownUntil: clearCooldownUntil ? null : (cooldownUntil ?? this.cooldownUntil),
    activeSessionId: clearActiveSessionId ? null : (activeSessionId ?? this.activeSessionId),
    defeatCount: defeatCount ?? this.defeatCount,
  );
}

class DefeatEffects {
  const DefeatEffects({
    required this.revokeSessionTokens,
    required this.notifyOtherGuardian,
    required this.auditEvent,
  });

  /// Server-side revocation. A leaked call token outlives the app otherwise.
  final String? revokeSessionTokens;
  /// §8.3 — repeated failures notify the OTHER guardian, not the one present.
  final bool notifyOtherGuardian;
  final String auditEvent;
}

class Transition {
  const Transition(this.state, this.effects);
  final LockState state;
  final DefeatEffects effects;
}

LockState initialState(LockMode mode) => LockState(mode: mode, surface: Surface.childHome);

bool isEscalated(LockState s, DateTime now) =>
    s.escalatedUntil != null && s.escalatedUntil!.isAfter(now);

/// The lock task was exited — the child got out, or the OS dropped it.
///
/// Three things must happen, and the ORDER matters:
///   1. Drop any escalation. Otherwise a parent who escalated, handed the
///      device back, and had the kiosk defeated leaves guardian scope live in
///      a child's hands. This is the actual failure mode, not the child
///      seeing a menu.
///   2. Revoke session tokens server-side. The app losing focus does not
///      invalidate a JWT.
///   3. Land on the PIN gate — never the guardian surface, never mid-session.
Transition onLockTaskExited(LockState s, DateTime now) {
  final wasEscalated = isEscalated(s, now);
  final defeatCount = s.defeatCount + 1;
  return Transition(
    s.copyWith(
      surface: Surface.pinGate,
      clearEscalatedUntil: true, // (1) always, unconditionally
      clearActiveSessionId: true,
      defeatCount: defeatCount,
    ),
    DefeatEffects(
      revokeSessionTokens: s.activeSessionId, // (2)
      // A defeat while guardian scope was live is a different severity than a
      // child poking at Recents.
      notifyOtherGuardian: wasEscalated || defeatCount >= 3,
      auditEvent: wasEscalated ? 'kiosk_defeated_while_escalated' : 'kiosk_defeated',
    ),
  );
}

/// App backgrounded — same token hazard, lower severity.
Transition onBackgrounded(LockState s, DateTime now) {
  final wasEscalated = isEscalated(s, now);
  return Transition(
    s.copyWith(
      surface: Surface.pinGate,
      clearEscalatedUntil: true,
      clearActiveSessionId: true,
    ),
    DefeatEffects(
      revokeSessionTokens: s.activeSessionId,
      notifyOtherGuardian: false,
      auditEvent: wasEscalated ? 'backgrounded_while_escalated' : 'backgrounded',
    ),
  );
}

LockState submitChildPin(LockState s, bool correct, DateTime now) {
  if (s.cooldownUntil != null && s.cooldownUntil!.isAfter(now)) {
    return s.copyWith(surface: Surface.lockedOut);
  }
  if (correct) {
    return s.copyWith(surface: Surface.childHome, failedAttempts: 0, clearCooldownUntil: true);
  }
  final failed = s.failedAttempts + 1;
  return failed >= maxPinAttempts
      ? s.copyWith(
          surface: Surface.lockedOut,
          failedAttempts: failed,
          cooldownUntil: now.add(cooldownDuration),
        )
      : s.copyWith(surface: Surface.pinGate, failedAttempts: failed);
}

class EscalationResult {
  const EscalationResult(this.state, [this.denied]);
  final LockState state;
  /// 'pin' | 'biometric' | 'cooldown', or null on success.
  final String? denied;
}

/// Guardian escalation. §8.3 requires PIN **and** biometric — a PIN alone is
/// shoulder-surfable by the child sitting right there, which is also why the
/// keypad is shuffled at the UI layer (pin_gate.dart).
EscalationResult escalate(LockState s, bool pinOk, bool biometricOk, DateTime now) {
  if (s.cooldownUntil != null && s.cooldownUntil!.isAfter(now)) {
    return EscalationResult(s.copyWith(surface: Surface.lockedOut), 'cooldown');
  }
  if (!pinOk) {
    final failed = s.failedAttempts + 1;
    return EscalationResult(
      failed >= maxPinAttempts
          ? s.copyWith(
              surface: Surface.lockedOut,
              failedAttempts: failed,
              cooldownUntil: now.add(cooldownDuration),
            )
          : s.copyWith(failedAttempts: failed),
      'pin',
    );
  }
  if (!biometricOk) return EscalationResult(s.copyWith(failedAttempts: 0), 'biometric');
  return EscalationResult(
    s.copyWith(
      surface: Surface.guardianEscalation,
      escalatedUntil: now.add(escalationTtl),
      failedAttempts: 0,
    ),
  );
}

class BreakGlassResult {
  const BreakGlassResult(this.state, this.auditEvent);
  final LockState state;
  final String auditEvent;
}

/// §8.3 break-glass. A parent locked out at 9 p.m. must not lose a scheduled
/// call. Grants a session, never settings, and is always audited.
BreakGlassResult breakGlass(LockState s, DateTime now) => BreakGlassResult(
  s.copyWith(surface: Surface.childHome, clearCooldownUntil: true, failedAttempts: 0),
  'break_glass_used',
);

/// What may be rendered right now. Called on every navigation.
/// Deny-by-default: an unknown/unlisted surface is not reachable.
bool canRender(LockState s, Surface surface, DateTime now) => switch (surface) {
  Surface.childHome || Surface.childSession =>
    s.surface == Surface.childHome || s.surface == Surface.childSession,
  Surface.pinGate => s.surface == Surface.pinGate,
  Surface.lockedOut => s.surface == Surface.lockedOut,
  // Requires LIVE escalation, not merely having reached the surface once.
  Surface.guardianEscalation => s.surface == Surface.guardianEscalation && isEscalated(s, now),
};

/// Advisory shown at setup. An escapable mode is a supported configuration.
String lockAdvisory(LockMode mode) => escapable.contains(mode)
    ? 'This device can be unlocked by your child. The app will ask for their PIN '
          'again if that happens, and no adult settings will be reachable.'
    : 'This device is fully locked to the app.';
