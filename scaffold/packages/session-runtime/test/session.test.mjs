/**
 * session-runtime + child-lock — adversarial suite.
 * MASTERFILE §3.1, §5.15, §8.3, §17.3, §10.5.
 *
 * Tokens are minted with the REAL livekit-server-sdk and decoded from the wire
 * so the assertions are about what LiveKit actually receives, not about our
 * intermediate objects.
 */
import { AccessToken } from 'livekit-server-sdk';
import {
  createSession, mintToken, deriveGrant, newRoomName, roomNameLeaks,
  TOKEN_TTL_SECONDS, FORBIDDEN_GRANTS,
} from '../src/rooms.mjs';
import {
  initialState, onLockTaskExited, onBackgrounded, submitChildPin, escalate,
  breakGlass, canRender, isEscalated, lockAdvisory,
  MAX_PIN_ATTEMPTS, ESCAPABLE,
} from '../../child-lock/src/lock.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}

const NOW = new Date('2026-07-26T20:00:00Z');
const CHILD_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const CHILD_B = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const DAD = '11111111-1111-1111-1111-111111111111';
const MOM = '22222222-2222-2222-2222-222222222222';

const edge = (o = {}) => ({
  childId: CHILD_A, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null,
  expiresAt: null, closedAt: null, ladderStep: null, ...o,
});

const session = (o = {}) => createSession({
  childId: CHILD_A, kind: 'call', createdBy: DAD,
  authorizedUserIds: [DAD, CHILD_A], ladderStep: 'open', ...o,
});

/** Mint through the real SDK and read back what LiveKit will see. */
async function onWire(token) {
  const at = new AccessToken('devkey', 'devsecret_at_least_32_chars_long_xx',
    { identity: token.identity, ttl: token.ttlSeconds });
  at.addGrant(token.grant);
  const jwt = await at.toJwt();
  return JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
}

// ---------------------------------------------------------------------------
// I1 — room names must not be guessable or leak identifiers.
// ---------------------------------------------------------------------------
{
  const names = new Set();
  for (let i = 0; i < 2000; i++) names.add(newRoomName());
  check('I1 room naming', '2000 names, zero collisions', names.size, 2000);

  const s = session();
  check('I1 room naming', 'room name does not contain the child id',
    roomNameLeaks(s.roomName, [CHILD_A]), 'false');
  check('I1 room naming', 'room name does not contain the creator id',
    roomNameLeaks(s.roomName, [DAD]), 'false');
  check('I1 room naming', 'leak detector catches an embedded id',
    roomNameLeaks(`child:${CHILD_A}`, [CHILD_A]), 'true');
  check('I1 room naming', 'leak detector catches a de-hyphenated id',
    roomNameLeaks(`room_${CHILD_A.replace(/-/g,'')}`, [CHILD_A]), 'true');
  check('I1 room naming', 'two sessions for the same child differ',
    session().roomName === session().roomName, 'false');
}

// ---------------------------------------------------------------------------
// I2/I3 — what LiveKit actually receives on the wire.
// ---------------------------------------------------------------------------
{
  const s = session();
  const r = mintToken(s, { userId: DAD, observerOnly: false, isChild: false,
                           roleName: 'guardian' }, [edge()], NOW);
  check('I2 wire claims', 'mint succeeds for an authorized guardian', r.ok, 'true');

  const c = await onWire(r.token);
  check('I2 wire claims', 'roomJoin present', c.video.roomJoin, 'true');
  check('I2 wire claims', 'scoped to exactly this room', c.video.room, s.roomName);
  check('I2 wire claims', 'identity is the authenticated principal', c.sub, DAD);
  check('I2 wire claims', 'canUpdateOwnMetadata is false — no self-renaming',
    c.video.canUpdateOwnMetadata, 'false');
  check('I2 wire claims', 'no admin grant of any kind reaches the wire',
    FORBIDDEN_GRANTS.filter(g => c.video[g]).length, 0);
  check('I2 wire claims', `TTL is ${TOKEN_TTL_SECONDS}s, not hours`,
    c.exp - c.nbf, TOKEN_TTL_SECONDS);
  check('I2 wire claims', 'only expected video keys are set',
    Object.keys(c.video).sort().join(','),
    'canPublish,canPublishData,canSubscribe,canUpdateOwnMetadata,room,roomJoin');
}

// ---------------------------------------------------------------------------
// I4 — CROSS-FAMILY. A guardian of one child must not obtain a token for
//      another child's room, even holding the room name.
// ---------------------------------------------------------------------------
{
  const bSession = createSession({
    childId: CHILD_B, kind: 'call', createdBy: MOM,
    authorizedUserIds: [MOM, CHILD_B], ladderStep: 'open',
  });

  // Dad guards only child A. He has somehow learned B's room name.
  const r1 = mintToken(bSession, { userId: DAD, observerOnly: false, isChild: false,
                                   roleName: 'guardian' }, [edge({ childId: CHILD_A })], NOW);
  check('I4 cross-family', "Dad cannot mint into another child's room",
    r1.ok === false && r1.reason, 'not_authorized');

  // Even if someone wrongly added him to the participant list, the edge check
  // runs first — membership is not authorization.
  const poisoned = { ...bSession, authorizedUserIds: [MOM, CHILD_B, DAD] };
  const r2 = mintToken(poisoned, { userId: DAD, observerOnly: false, isChild: false,
                                   roleName: 'guardian' }, [edge({ childId: CHILD_A })], NOW);
  check('I4 cross-family', 'a poisoned participant list does not grant access',
    r2.ok === false && r2.reason, 'not_authorized');

  // Authorized for the child but not listed on this session.
  const r3 = mintToken(bSession, { userId: MOM, observerOnly: false, isChild: false,
                                   roleName: 'guardian' },
                       [edge({ childId: CHILD_B, userId: MOM })], NOW);
  check('I4 cross-family', 'listed + authorized mints fine', r3.ok, 'true');

  const notListed = { ...bSession, authorizedUserIds: [CHILD_B] };
  const r4 = mintToken(notListed, { userId: MOM, observerOnly: false, isChild: false,
                                    roleName: 'guardian' },
                       [edge({ childId: CHILD_B, userId: MOM })], NOW);
  check('I4 cross-family', 'authorized but not a participant is refused',
    r4.ok === false && r4.reason, 'not_a_participant');
}

// ---------------------------------------------------------------------------
// I4b — edges are re-evaluated at MINT time. A stale participant list must not
//       let a revoked or restricted parent back into a room.
// ---------------------------------------------------------------------------
{
  const s = session();
  const cases = [
    ['closed edge (deceased/revoked)', { closedAt: '2026-07-01T00:00:00Z' }],
    ['protective order',               { restricted: true }],
    ['expired sitter token',           { role: 'sitter', expiresAt: '2026-07-01T00:00:00Z' }],
    ['ladder step none',               { ladderStep: 'none' }],
    ['validity window ended',          { validTo: '2026-07-01T00:00:00Z' }],
  ];
  for (const [label, mod] of cases) {
    const r = mintToken(s, { userId: DAD, observerOnly: false, isChild: false,
                             roleName: 'guardian' }, [edge(mod)], NOW);
    check('I4b mint-time recheck', `${label} cannot mint`,
      r.ok === false && r.reason, 'not_authorized');
  }
  const ended = { ...s, endedAt: NOW.toISOString() };
  const re = mintToken(ended, { userId: DAD, observerOnly: false, isChild: false,
                                roleName: 'guardian' }, [edge()], NOW);
  check('I4b mint-time recheck', 'ended session cannot mint',
    re.ok === false && re.reason, 'session_ended');
}

// ---------------------------------------------------------------------------
// §17.3 — the observer tier must not become live participation.
// ---------------------------------------------------------------------------
{
  const s = session();
  const g = deriveGrant(s, { userId: MOM, observerOnly: true, isChild: false });
  check('§17.3 observer', 'observer cannot publish video/audio', g.canPublish, 'false');
  check('§17.3 observer', 'observer cannot publish data', g.canPublishData, 'false');
  check('§17.3 observer', 'observer can still subscribe', g.canSubscribe, 'true');

  const c = await onWire({ identity: MOM, room: s.roomName, grant: g,
                           ttlSeconds: TOKEN_TTL_SECONDS });
  check('§17.3 observer', 'subscribe-only survives to the wire',
    `${c.video.canPublish}/${c.video.canSubscribe}`, 'false/true');

  const full = deriveGrant(s, { userId: DAD, observerOnly: false, isChild: false });
  check('§17.3 observer', 'a participating guardian can publish', full.canPublish, 'true');
}

// ---------------------------------------------------------------------------
// §5.15 / §10.5 — the ladder drives recording, and recording is disclosed.
// ---------------------------------------------------------------------------
{
  check('§5.15 recording', 'supervised is recorded',
    session({ ladderStep: 'supervised' }).recorded, 'true');
  check('§5.15 recording', 'monitored is NOT recorded',
    session({ ladderStep: 'monitored' }).recorded, 'false');
  check('§5.15 recording', 'open is NOT recorded',
    session({ ladderStep: 'open' }).recorded, 'false');
  check('§5.15 recording', 'time_limited is NOT recorded',
    session({ ladderStep: 'time_limited' }).recorded, 'false');

  let threw = false;
  try { session({ ladderStep: 'none' }); } catch { threw = true; }
  check('§5.15 recording', 'step none cannot create a session at all', threw, 'true');

  const sup = mintToken(session({ ladderStep: 'supervised' }),
    { userId: DAD, observerOnly: false, isChild: false, roleName: 'guardian' },
    [edge({ ladderStep: 'supervised' })], NOW);
  check('§10.5 disclosure', 'recorded session carries a disclosure',
    sup.token.disclosure !== null, 'true');
  check('§10.5 disclosure', 'disclosure is child-readable, not legalese',
    /watched later/.test(sup.token.disclosure), 'true');

  const open = mintToken(session(), { userId: DAD, observerOnly: false, isChild: false,
                                      roleName: 'guardian' }, [edge()], NOW);
  check('§10.5 disclosure', 'unrecorded session has no disclosure',
    open.token.disclosure, 'null');
}

// ---------------------------------------------------------------------------
// §8.3 — kiosk defeat. What is on screen one frame later.
// ---------------------------------------------------------------------------
{
  check('§8.3 modes', 'pinned is escapable', ESCAPABLE.includes('pinned'), 'true');
  check('§8.3 modes', 'device-owner locked is not', ESCAPABLE.includes('locked'), 'false');
  check('§8.3 modes', 'escapable mode is disclosed at setup',
    /can be unlocked by your child/.test(lockAdvisory('pinned')), 'true');

  // THE failure mode: parent escalates, hands the device back, kiosk defeated.
  let st = initialState('pinned');
  const esc = escalate(st, true, true, NOW);
  st = esc.state;
  check('§8.3 defeat', 'escalation reached', st.surface, 'guardian_escalation');
  check('§8.3 defeat', 'escalation is live', isEscalated(st, NOW), 'true');

  const d = onLockTaskExited(st, NOW);
  check('§8.3 defeat', 'escalation is DROPPED on defeat',
    isEscalated(d.state, NOW), 'false');
  check('§8.3 defeat', 'child lands on the PIN gate, not guardian settings',
    d.state.surface, 'pin_gate');
  check('§8.3 defeat', 'guardian surface is unrenderable after defeat',
    canRender(d.state, 'guardian_escalation', NOW), 'false');
  check('§8.3 defeat', 'defeat while escalated notifies the other guardian',
    d.effects.notifyOtherGuardian, 'true');
  check('§8.3 defeat', 'audit distinguishes the severe case',
    d.effects.auditEvent, 'kiosk_defeated_while_escalated');

  // Token revocation: the app losing focus does not invalidate a JWT.
  let mid = { ...initialState('pinned'), surface: 'child_session', activeSessionId: 'sess-1' };
  const d2 = onLockTaskExited(mid, NOW);
  check('§8.3 defeat', 'active session tokens are revoked server-side',
    d2.effects.revokeSessionTokens, 'sess-1');
  check('§8.3 defeat', 'session is cleared from state',
    d2.state.activeSessionId, 'null');
  check('§8.3 defeat', 'backgrounding also revokes tokens',
    onBackgrounded(mid, NOW).effects.revokeSessionTokens, 'sess-1');
  check('§8.3 defeat', 'backgrounding also drops escalation',
    isEscalated(onBackgrounded(esc.state, NOW).state, NOW), 'false');

  // Repeated defeats escalate in severity even without escalation.
  let rep = initialState('pinned');
  for (let i = 0; i < 2; i++) rep = onLockTaskExited(rep, NOW).state;
  check('§8.3 defeat', 'third defeat notifies the other guardian',
    onLockTaskExited(rep, NOW).effects.notifyOtherGuardian, 'true');
}

// ---------------------------------------------------------------------------
// §8.3 — PIN, escalation, cooldown, break-glass.
// ---------------------------------------------------------------------------
{
  let st = { ...initialState('pinned'), surface: 'pin_gate' };
  for (let i = 0; i < MAX_PIN_ATTEMPTS; i++) st = submitChildPin(st, false, NOW);
  check('§8.3 pin', `locked out after ${MAX_PIN_ATTEMPTS} failures`, st.surface, 'locked_out');
  check('§8.3 pin', 'cooldown is set', st.cooldownUntil !== null, 'true');
  check('§8.3 pin', 'correct PIN during cooldown still refused',
    submitChildPin(st, true, NOW).surface, 'locked_out');
  check('§8.3 pin', 'works after the cooldown elapses',
    submitChildPin(st, true, new Date(NOW.getTime() + 6 * 60 * 1000)).surface, 'child_home');

  // Escalation needs BOTH factors. PIN alone is shoulder-surfable by the child
  // sitting right there.
  const base = initialState('pinned');
  check('§8.3 escalate', 'PIN alone does not escalate',
    escalate(base, true, false, NOW).denied, 'biometric');
  check('§8.3 escalate', 'biometric alone does not escalate',
    escalate(base, false, true, NOW).denied, 'pin');
  check('§8.3 escalate', 'both factors escalate',
    escalate(base, true, true, NOW).state.surface, 'guardian_escalation');
  check('§8.3 escalate', 'escalation expires after 15 minutes',
    isEscalated(escalate(base, true, true, NOW).state,
                new Date(NOW.getTime() + 16 * 60 * 1000)), 'false');
  check('§8.3 escalate', 'expired escalation cannot render guardian surface',
    canRender(escalate(base, true, true, NOW).state, 'guardian_escalation',
              new Date(NOW.getTime() + 16 * 60 * 1000)), 'false');

  // Break-glass clears cooldown so a 9pm call is not lost — but grants no settings.
  const bg = breakGlass(st, NOW);
  check('§8.3 break-glass', 'clears the cooldown', bg.state.cooldownUntil, 'null');
  check('§8.3 break-glass', 'lands on child home, NOT guardian scope',
    bg.state.surface, 'child_home');
  check('§8.3 break-glass', 'grants no escalation',
    isEscalated(bg.state, NOW), 'false');
  check('§8.3 break-glass', 'is audited', bg.auditEvent, 'break_glass_used');

  check('§8.3 render', 'unknown surface is denied by default',
    canRender(base, 'settings_root', NOW), 'false');
  check('§8.3 render', 'child cannot render the PIN gate from child_home',
    canRender(base, 'pin_gate', NOW), 'false');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.group !== g) { g = r.group; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
