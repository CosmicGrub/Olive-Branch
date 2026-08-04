/**
 * child-lock — the §5.20 state machine. MASTERFILE §5.20, §8.3.
 *
 * Previously zero assertions and not wired into verify.sh — an orphaned
 * package despite being logic-complete. Closed alongside the native bridge
 * that finally consumes this state machine for real (client/lib/kiosk_shell.dart,
 * client/lib/lock_controller.dart).
 */
import {
  initialState, isEscalated, onLockTaskExited, onBackgrounded,
  submitChildPin, escalate, breakGlass, canRender, lockAdvisory,
  ESCALATION_TTL_MS, MAX_PIN_ATTEMPTS, COOLDOWN_MS, ESCAPABLE,
} from '../src/lock.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const NOW = new Date('2026-08-04T20:00:00Z');
const T = (ms) => new Date(NOW.getTime() + ms);

// A · INITIAL STATE
{
  const s = initialState('pinned');
  check('A initial', 'starts on child_home', s.surface, 'child_home');
  check('A initial', 'zero failed attempts', s.failedAttempts, 0);
  check('A initial', 'zero defeats', s.defeatCount, 0);
  check('A initial', 'no live escalation', isEscalated(s, NOW), false);
}

// B · LOCK-TASK EXIT — ordering and severity
{
  const s = initialState('pinned');
  const { state, effects } = onLockTaskExited(s, NOW);
  check('B exit', 'lands on pin_gate', state.surface, 'pin_gate');
  check('B exit', 'defeat count increments', state.defeatCount, 1);
  check('B exit', 'first defeat does not notify (not escalated, count < 3)',
    effects.notifyOtherGuardian, false);
  check('B exit', 'audit event is the plain kiosk_defeated', effects.auditEvent, 'kiosk_defeated');

  // Escalated at the moment of defeat — the dangerous case.
  const escalated = { ...initialState('pinned'), surface: 'guardian_escalation',
    escalatedUntil: T(ESCALATION_TTL_MS).toISOString(), activeSessionId: 'sess-1' };
  const r2 = onLockTaskExited(escalated, NOW);
  check('B exit', 'escalation is dropped unconditionally', r2.state.escalatedUntil, 'null');
  check('B exit', 'never lands anywhere but pin_gate', r2.state.surface, 'pin_gate');
  check('B exit', 'session token queued for revocation', r2.effects.revokeSessionTokens, 'sess-1');
  check('B exit', 'the other guardian IS notified when escalated', r2.effects.notifyOtherGuardian, true);
  check('B exit', 'audit event names the dangerous case distinctly',
    r2.effects.auditEvent, 'kiosk_defeated_while_escalated');

  // Third defeat notifies even without live escalation.
  const thrice = { ...initialState('pinned'), defeatCount: 2 };
  const r3 = onLockTaskExited(thrice, NOW);
  check('B exit', 'third defeat notifies the other guardian', r3.effects.notifyOtherGuardian, true);
}

// C · BACKGROUNDING — same token hazard, lower severity
{
  const s = { ...initialState('pinned'), activeSessionId: 'sess-2' };
  const { state, effects } = onBackgrounded(s, NOW);
  check('C bg', 'also lands on pin_gate', state.surface, 'pin_gate');
  check('C bg', 'also revokes the session token — focus loss does not expire a JWT',
    effects.revokeSessionTokens, 'sess-2');
  check('C bg', 'never notifies on its own (not a defeat count)', effects.notifyOtherGuardian, false);
  check('C bg', 'plain audit event when not escalated', effects.auditEvent, 'backgrounded');

  const escalated = { ...s, surface: 'guardian_escalation', escalatedUntil: T(ESCALATION_TTL_MS).toISOString() };
  check('C bg', 'escalation drops here too', onBackgrounded(escalated, NOW).state.escalatedUntil, 'null');
  check('C bg', 'distinct audit event while escalated',
    onBackgrounded(escalated, NOW).effects.auditEvent, 'backgrounded_while_escalated');
}

// D · CHILD PIN RE-ENTRY, COOLDOWN
{
  let s = { ...initialState('pinned'), surface: 'pin_gate' };
  s = submitChildPin(s, true, NOW);
  check('D pin', 'correct PIN returns to child_home', s.surface, 'child_home');
  check('D pin', 'failed attempts reset on success', s.failedAttempts, 0);

  s = { ...initialState('pinned'), surface: 'pin_gate' };
  for (let i = 0; i < MAX_PIN_ATTEMPTS - 1; i++) s = submitChildPin(s, false, NOW);
  check('D pin', `stays at pin_gate before the ${MAX_PIN_ATTEMPTS}th miss`, s.surface, 'pin_gate');
  s = submitChildPin(s, false, NOW);
  check('D pin', `the ${MAX_PIN_ATTEMPTS}th miss locks out`, s.surface, 'locked_out');
  check('D pin', 'cooldown window is set', s.cooldownUntil !== null, 'true');

  const stillCoolingDown = submitChildPin(s, true, T(COOLDOWN_MS - 1000));
  check('D pin', 'a correct PIN during cooldown still refuses', stillCoolingDown.surface, 'locked_out');
}

// E · GUARDIAN ESCALATION — PIN AND biometric, shoulder-surf resistant
{
  const s = initialState('pinned');
  const wrongPin = escalate(s, false, true, NOW);
  check('E escalate', 'a wrong PIN denies for "pin", not biometric', wrongPin.denied, 'pin');
  check('E escalate', 'does not reach guardian_escalation on a bad PIN',
    wrongPin.state.surface === 'guardian_escalation', 'false');

  const pinOkBiometricNo = escalate(s, true, false, NOW);
  check('E escalate', 'PIN alone is refused — biometric required too', pinOkBiometricNo.denied, 'biometric');
  check('E escalate', 'a failed biometric does not itself count as a PIN failure',
    pinOkBiometricNo.state.failedAttempts, 0);

  const ok = escalate(s, true, true, NOW);
  check('E escalate', 'PIN + biometric reaches guardian_escalation', ok.state.surface, 'guardian_escalation');
  check('E escalate', 'escalation window is set', ok.state.escalatedUntil !== null, 'true');
  check('E escalate', 'live immediately after granting', isEscalated(ok.state, NOW), true);
  check('E escalate', 'expired after the TTL', isEscalated(ok.state, T(ESCALATION_TTL_MS + 1)), false);

  let cooling = initialState('pinned');
  for (let i = 0; i < MAX_PIN_ATTEMPTS; i++) cooling = escalate(cooling, false, true, NOW).state;
  const duringCooldown = escalate(cooling, true, true, NOW);
  check('E escalate', 'cooldown blocks escalation even with the right PIN + biometric',
    duringCooldown.denied, 'cooldown');
}

// F · BREAK-GLASS — recovers access, never escalation
{
  const lockedOut = { ...initialState('pinned'), surface: 'locked_out',
    cooldownUntil: T(COOLDOWN_MS).toISOString(), failedAttempts: MAX_PIN_ATTEMPTS };
  const { state, auditEvent } = breakGlass(lockedOut, NOW);
  check('F glass', 'recovers to child_home', state.surface, 'child_home');
  check('F glass', 'clears the cooldown', state.cooldownUntil, 'null');
  check('F glass', 'grants NO escalation', state.escalatedUntil, 'null');
  check('F glass', 'is always audited', auditEvent, 'break_glass_used');
}

// G · DENY-BY-DEFAULT RENDERING
{
  const home = initialState('pinned');
  check('G render', 'child_home renders on child_home', canRender(home, 'child_home', NOW), true);
  check('G render', 'pin_gate does NOT render while on child_home', canRender(home, 'pin_gate', NOW), false);
  check('G render', 'guardian_escalation never renders without a live escalation',
    canRender(home, 'guardian_escalation', NOW), false);

  const staleEscalation = { ...home, surface: 'guardian_escalation',
    escalatedUntil: T(-1000).toISOString() }; // already expired
  check('G render', 'a REACHED-but-expired escalation still does not render',
    canRender(staleEscalation, 'guardian_escalation', NOW), false);

  check('G render', 'an unknown surface is unreachable by construction',
    canRender(home, 'not_a_real_surface', NOW), false);
}

// H · ADVISORY — disclosed honestly, never oversold
{
  check('H advisory', 'pinned is disclosed as escapable', lockAdvisory('pinned').includes('unlocked by your child'), true);
  check('H advisory', 'locked (device-owner) is NOT disclosed as escapable',
    lockAdvisory('locked').includes('unlocked by your child'), false);
  check('H advisory', 'every ESCAPABLE mode says so',
    ESCAPABLE.every((m) => lockAdvisory(m).includes('unlocked by your child')), true);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
