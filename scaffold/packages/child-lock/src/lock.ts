/**
 * MASTERFILE §8.3 — child lock.
 *
 * The platform primitives are unreliable by design:
 *
 *  Android  `startLockTask()` in PINNED mode (no device-owner) can be exited by
 *           the child holding Back + Recents. Only LOCK_TASK_MODE_LOCKED, which
 *           needs device-owner provisioning, is actually escape-proof. Most
 *           installs will be PINNED.
 *  Windows  Assigned Access can be exited with Ctrl+Alt+Del.
 *  iOS      Guided Access requires a passcode to exit, but can be disabled if
 *           the child knows the device passcode.
 *
 * So defeat is not an exception — it is an expected event. The question this
 * module answers is what the child is looking at one frame after it happens.
 *
 * The answer is never "the guardian surface".
 */

export type LockMode =
  | 'locked'      // Android device-owner LOCK_TASK_MODE_LOCKED, escape-proof
  | 'pinned'      // Android PINNED, escapable
  | 'assigned'    // Windows Assigned Access
  | 'guided'      // iOS Guided Access
  | 'none';       // no OS enforcement available

export type Surface =
  | 'child_home'
  | 'child_session'
  | 'pin_gate'        // re-entry: child PIN
  | 'guardian_escalation'
  | 'locked_out';     // cooldown after repeated failures

export interface LockState {
  mode: LockMode;
  surface: Surface;
  /** Guardian scope, granted by PIN + biometric. Expires. */
  escalatedUntil: string | null;
  failedAttempts: number;
  cooldownUntil: string | null;
  activeSessionId: string | null;
  defeatCount: number;
}

export interface DefeatEffects {
  /** Server-side revocation. A leaked LiveKit token outlives the app otherwise. */
  revokeSessionTokens: string | null;
  /** §8.3 — repeated failures notify the OTHER guardian, not the one present. */
  notifyOtherGuardian: boolean;
  auditEvent: string;
}

export const ESCALATION_TTL_MS = 15 * 60 * 1000;
export const MAX_PIN_ATTEMPTS = 5;
export const COOLDOWN_MS = 5 * 60 * 1000;

/** Modes a child can escape without an adult. Drives how loudly we react. */
export const ESCAPABLE: LockMode[] = ['pinned', 'assigned', 'guided', 'none'];

export function initialState(mode: LockMode): LockState {
  return {
    mode,
    surface: 'child_home',
    escalatedUntil: null,
    failedAttempts: 0,
    cooldownUntil: null,
    activeSessionId: null,
    defeatCount: 0,
  };
}

export function isEscalated(s: LockState, now: Date): boolean {
  return s.escalatedUntil !== null && new Date(s.escalatedUntil) > now;
}

/**
 * The lock task was exited — the child got out, or the OS dropped it.
 *
 * Three things must happen, and the ORDER matters:
 *   1. Drop any escalation. Otherwise a parent who escalated, handed the device
 *      back, and had the kiosk defeated leaves guardian scope live in a child's
 *      hands. This is the actual failure mode, not the child seeing a menu.
 *   2. Revoke session tokens server-side. The app losing focus does not
 *      invalidate a JWT.
 *   3. Land on the PIN gate — never the guardian surface, never mid-session.
 */
export function onLockTaskExited(
  s: LockState, now: Date,
): { state: LockState; effects: DefeatEffects } {
  const wasEscalated = isEscalated(s, now);
  return {
    state: {
      ...s,
      surface: 'pin_gate',
      escalatedUntil: null,          // (1) always, unconditionally
      activeSessionId: null,
      defeatCount: s.defeatCount + 1,
    },
    effects: {
      revokeSessionTokens: s.activeSessionId,             // (2)
      // A defeat while guardian scope was live is a different severity than a
      // child poking at Recents.
      notifyOtherGuardian: wasEscalated || s.defeatCount + 1 >= 3,
      auditEvent: wasEscalated
        ? 'kiosk_defeated_while_escalated'
        : 'kiosk_defeated',
    },
  };
}

/** App backgrounded — same token hazard, lower severity. */
export function onBackgrounded(s: LockState, now: Date): { state: LockState; effects: DefeatEffects } {
  const wasEscalated = isEscalated(s, now);
  return {
    state: { ...s, surface: 'pin_gate', escalatedUntil: null, activeSessionId: null },
    effects: {
      revokeSessionTokens: s.activeSessionId,
      notifyOtherGuardian: false,
      auditEvent: wasEscalated ? 'backgrounded_while_escalated' : 'backgrounded',
    },
  };
}

export function submitChildPin(s: LockState, correct: boolean, now: Date): LockState {
  if (s.cooldownUntil && new Date(s.cooldownUntil) > now) {
    return { ...s, surface: 'locked_out' };
  }
  if (correct) {
    return { ...s, surface: 'child_home', failedAttempts: 0, cooldownUntil: null };
  }
  const failed = s.failedAttempts + 1;
  return failed >= MAX_PIN_ATTEMPTS
    ? { ...s, surface: 'locked_out', failedAttempts: failed,
        cooldownUntil: new Date(now.getTime() + COOLDOWN_MS).toISOString() }
    : { ...s, surface: 'pin_gate', failedAttempts: failed };
}

/**
 * Guardian escalation. §8.3 requires PIN **and** biometric — a PIN alone is
 * shoulder-surfable by the child sitting right there, which is also why the
 * keypad is shuffled at the UI layer.
 */
export function escalate(
  s: LockState, pinOk: boolean, biometricOk: boolean, now: Date,
): { state: LockState; denied?: 'pin' | 'biometric' | 'cooldown' } {
  if (s.cooldownUntil && new Date(s.cooldownUntil) > now) {
    return { state: { ...s, surface: 'locked_out' }, denied: 'cooldown' };
  }
  if (!pinOk) {
    const failed = s.failedAttempts + 1;
    return {
      state: failed >= MAX_PIN_ATTEMPTS
        ? { ...s, surface: 'locked_out', failedAttempts: failed,
            cooldownUntil: new Date(now.getTime() + COOLDOWN_MS).toISOString() }
        : { ...s, failedAttempts: failed },
      denied: 'pin',
    };
  }
  if (!biometricOk) return { state: { ...s, failedAttempts: 0 }, denied: 'biometric' };
  return {
    state: {
      ...s,
      surface: 'guardian_escalation',
      escalatedUntil: new Date(now.getTime() + ESCALATION_TTL_MS).toISOString(),
      failedAttempts: 0,
    },
  };
}

/**
 * §8.3 break-glass. A parent locked out at 9 p.m. must not lose a scheduled
 * call. Grants a session, never settings, and is always audited.
 */
export function breakGlass(s: LockState, now: Date): { state: LockState; auditEvent: string } {
  return {
    state: { ...s, surface: 'child_home', cooldownUntil: null, failedAttempts: 0 },
    auditEvent: 'break_glass_used',
  };
}

/**
 * What may be rendered right now. Called on every navigation.
 * Deny-by-default: an unknown surface is not reachable.
 */
export function canRender(s: LockState, surface: Surface, now: Date): boolean {
  switch (surface) {
    case 'child_home':
    case 'child_session':
      return s.surface === 'child_home' || s.surface === 'child_session';
    case 'pin_gate':
      return s.surface === 'pin_gate';
    case 'locked_out':
      return s.surface === 'locked_out';
    // Requires LIVE escalation, not merely having reached the surface once.
    case 'guardian_escalation':
      return s.surface === 'guardian_escalation' && isEscalated(s, now);
    default:
      return false;
  }
}

/** Advisory shown at setup. An escapable mode is a supported configuration. */
export function lockAdvisory(mode: LockMode): string {
  return ESCAPABLE.includes(mode)
    ? 'This device can be unlocked by your child. The app will ask for their PIN '
      + 'again if that happens, and no adult settings will be reachable.'
    : 'This device is fully locked to the app.';
}
