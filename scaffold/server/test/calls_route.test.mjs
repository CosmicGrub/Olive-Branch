/**
 * server/routes.mjs — POST /v1/children/:childId/calls. MASTERFILE §5.19,
 * §5.21, §5.25.2. The real replacement for tools/local-call-room-server.mjs's
 * own two-hardcoded-principal /room endpoint, and the first real caller
 * packages/transport/src/notify.ts's notifyDevices() has ever had — see this
 * route's own comment in routes.mjs for the fuller account of the gap it
 * closes.
 *
 * Mirrors packages/api/test/messages_route.test.mjs's own pattern (DATABASE_
 * URL/ADMIN_DATABASE_URL split, real Postgres, real HTTP through api.mjs) —
 * a route that mints a real session and calls a real, DB-reading
 * notifyDevices() needs a real database under it, not a fake `db`/`pool`
 * object standing in for one.
 */
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { roomNameLeaks } from '../../packages/session-runtime/src/rooms.mjs';

/**
 * MASTERFILE §16.2 #6 REVERSED AGAIN — the route now returns a real, signed
 * LiveKit `token` instead of a bare `room` string; the room name lives
 * inside the JWT's own `video.room` claim. Decoded exactly the way
 * session.test.mjs's own onWire() decodes any minted token — reading what a
 * real LiveKit server actually receives, not re-parsing our own response
 * shape as if that were the thing under test.
 */
function roomFromToken(jwt) {
  return JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString()).video?.room;
}

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CHILD = 'eeeeeeee-1234-1234-1234-eeeeeeeeeeee';
const DAD = 'ffffffff-1234-1234-1234-ffffffffffff';
const CHILD_B = '11111111-2222-1234-1234-333333333333';   // DAD has no edge to this one
// F's own fixture — a real contact_ladder row, not just the null/'open'
// default every other case above exercises. See section F's own comment.
const CHILD_C = '22222222-3333-1234-1234-444444444444';
// H's own fixture — DAD's edge to this child is real, live, and
// observer_only=true. See section H's own comment for what this proves.
const CHILD_D = '33333333-4444-1234-1234-555555555555';

// I's own fixture — a SECOND real guardian of CHILD, with a real,
// unrestricted edge (so can('call', ...) genuinely passes for her), who was
// never a party to any specific call. Distinguishes the join route's two
// real refusal reasons: no edge at all (not_authorized, already covered by
// section C) vs a real edge but never invited to THIS session
// (not_a_participant) — the actual new authorization boundary this route
// introduces, per this file's own established discipline of testing the
// real boundary, not just "some denial happened."
const MOM = 'cccccccc-1234-1234-1234-cccccccccccc';

const cleanup = async () => {
  await admin.query(`DELETE FROM call_log WHERE child_id IN ($1, $2, $3, $4)`,
    [CHILD, CHILD_B, CHILD_C, CHILD_D]);
  await admin.query(`DELETE FROM device_token WHERE owner_child_id IN ($1, $2)`, [CHILD, CHILD_B]);
  for (const cid of [CHILD, CHILD_B, CHILD_C, CHILD_D]) {
    await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
    await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
  }
  await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
};

await cleanup();
await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Chicago')`, [DAD, MOM]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Otherchild','2016-04-02','America/New_York'),
     ($3,'Supervisedchild','2016-04-02','America/New_York'),
     ($4,'Observedchild','2016-04-02','America/New_York')`, [CHILD, CHILD_B, CHILD_C, CHILD_D]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`, [CHILD, MOM]);
const supervisedGship = await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)) RETURNING id`,
  [CHILD_C, DAD]);
await admin.query(
  `INSERT INTO contact_ladder (guardianship_id, step, effective) VALUES
     ($1, 'supervised', tstzrange(now() - interval '1 day', null))`,
  [supervisedGship.rows[0].id]);
// H's own fixture — DAD's edge to CHILD_D is real and observer_only=true,
// the §17.3 "watch without obligation" tier. Every other edge above relies
// on observer_only's own column DEFAULT false; this is the one live edge in
// this suite where that default does NOT apply.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, observer_only, valid) VALUES
     ($1, $2, 'guardian', '{}', true, tstzrange(now() - interval '1 year', null))`, [CHILD_D, DAD]);
await admin.query('COMMIT');

const SECRET = Buffer.from('b'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool));
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);
const momTok = issueSession(SECRET,
  { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);

const post = (childId, tok) => api.handle(
  'POST', `/v1/children/${childId}/calls`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const join = (childId, sessionId, tok) => api.handle(
  'POST', `/v1/children/${childId}/calls/${sessionId}/join`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);

// ===========================================================================
// A · the real success path — a live guardian mints a real session
// ===========================================================================
{
  const res = await post(CHILD, dadTok);
  check('A success', 'a valid guardian call-start returns 201', res.status, 201);
  check('A success', 'response carries a real signed token',
    typeof res.body.token === 'string' && res.body.token.split('.').length === 3, 'true');
  const room = roomFromToken(res.body.token);
  check('A success', 'the token\'s own video.room claim names a real room string',
    typeof room === 'string' && room.length > 0, 'true');
  check('A success', 'room name does not leak the child or guardian id (I1)',
    roomNameLeaks(room, [CHILD, DAD]), 'false');
  check('A success', 'identity is the caller\'s own userId (I3), never client-supplied',
    res.body.identity, DAD);
  check('A success', 'wsURL is present', typeof res.body.wsURL === 'string', 'true');
  check('A success', 'rang is a real boolean, not a placeholder',
    typeof res.body.rang, 'boolean');

  // I1 again, differently: two calls in a row must mint two DIFFERENT rooms
  // — proving this isn't a single fixed/cached session reused across calls
  // the way tools/local-call-room-server.mjs's own dev-only design is.
  const res2 = await post(CHILD, dadTok);
  check('A success', 'a second call mints a genuinely different room',
    room === roomFromToken(res2.body.token), 'false');
}

// ===========================================================================
// B · a child principal cannot start a call
// ===========================================================================
{
  const res = await post(CHILD, childTok);
  check('B child', 'a child session is refused', res.status, 403);
  check('B child', 'the reason names exactly what was refused',
    res.body.error, 'child_cannot_start_call');
}

// ===========================================================================
// C · authorization — a guardian with no live edge to this child. Runs
//     through the ordinary generic gate now (action: 'call'), not a
//     hand-rolled check in the route itself -- so the denial reason is
//     authorize.ts's own can()/'no_edge', the same reason every other
//     action-gated route surfaces for the identical underlying situation.
// ===========================================================================
{
  const res = await post(CHILD_B, dadTok);
  check('C auth', 'a guardian with no edge to this child is refused', res.status, 403);
  check('C auth', 'the reason is the real can() denial, not an invented string',
    res.body.error, 'no_edge');
}

// ===========================================================================
// D · no session at all — the outer gate, before this route's own handler
// ===========================================================================
{
  const res = await post(CHILD, null);
  check('D no session', 'an unauthenticated request is refused', res.status, 401);
}

// ===========================================================================
// E · a real device_token row exists — notifyDevices() genuinely reads it,
//     not a fixture the route never actually queries. No real FCM/APNs
//     credential exists in this environment (see MASTERFILE §11's own
//     status note), so the actual SEND still fails and rang stays false —
//     that is the honest, already-established limitation of this whole test
//     environment, not a defect in this route. What this proves is narrower
//     and real: a channel-capable device row is looked up and reaches the
//     send attempt at all, rather than the route silently never querying
//     device_token in the first place.
// ===========================================================================
{
  await admin.query(
    `INSERT INTO device_token (owner_child_id, platform, token, channel)
     VALUES ($1, 'android', 'fake-token-for-test', 'android_play')`, [CHILD]);
  const res = await post(CHILD, dadTok);
  check('E device token', 'still 201 — a push attempt failing must never fail the call itself',
    res.status, 201);
  check('E device token', 'rang is false — no real FCM credential exists in this test environment',
    res.body.rang, false);
}

// ===========================================================================
// F · call_log — the real backing for security.ts's own RESIDUAL_RISKS
//     claim ("Retained, because §14 court export needs it"), which a
//     2026-08-23 audit found had no implementation anywhere. Two real
//     things proven here, not one: a row genuinely gets written at all,
//     and it carries the REAL per-edge ladder step -- not the literal
//     'open' this route hardcoded until the same audit found and fixed it.
// ===========================================================================
{
  const before = await post(CHILD, dadTok);
  const row = await admin.query(`SELECT * FROM call_log WHERE id = $1`, [before.body.sessionId]);
  check('F call_log', 'a real row is written for an ordinary open-ladder call', row.rowCount, 1);
  check('F call_log', 'child_id matches the real call', row.rows[0]?.child_id, CHILD);
  check('F call_log', 'started_by is the real calling guardian', row.rows[0]?.started_by, DAD);
  check('F call_log', 'room_name matches the real minted room', row.rows[0]?.room_name, roomFromToken(before.body.token));
  check('F call_log', 'ladder_step is the real edge value, open by default', row.rows[0]?.ladder_step, 'open');
  check('F call_log', 'recorded is false for an open-ladder call', row.rows[0]?.recorded, false);
  check('F call_log', 'ended_at is null — the call has not ended yet', row.rows[0]?.ended_at, null);

  // The actual fix: a guardian with a real, live 'supervised' edge to
  // CHILD_C must see that ladder step land in call_log, not the literal
  // 'open' this route hardcoded before this pass. rooms.ts's own
  // recorded: input.ladderStep === 'supervised' is what this proves is
  // finally reachable through the real route, not just in a unit test.
  const supervised = await post(CHILD_C, dadTok);
  check('F call_log', 'a supervised call is accepted', supervised.status, 201);
  const supRow = await admin.query(`SELECT * FROM call_log WHERE id = $1`, [supervised.body.sessionId]);
  check('F call_log', 'the REAL supervised ladder step reaches call_log — not the old hardcoded open',
    supRow.rows[0]?.ladder_step, 'supervised');
  check('F call_log', 'recorded is true — rooms.ts\'s own tested rule, finally reachable',
    supRow.rows[0]?.recorded, true);
}

// ===========================================================================
// G · call end — marks call_log's own row ended. Deliberately does NOT
//     assert anything about server-side media revocation (see the route's
//     own comment in routes.mjs for why that half is a real, disclosed,
//     separately-scoped gap, not built here).
// ===========================================================================
{
  const started = await post(CHILD, dadTok);
  const sessionId = started.body.sessionId;
  const end = (childId, sid, tok) => api.handle(
    'POST', `/v1/children/${childId}/calls/${sid}/end`,
    tok ? { authorization: `Bearer ${tok}` } : {}, '',
  );

  const res1 = await end(CHILD, sessionId, dadTok);
  check('G call end', 'ending a real, unended call returns 200', res1.status, 200);
  check('G call end', 'ended is true the first time', res1.body.ended, true);

  const row = await admin.query(`SELECT ended_at FROM call_log WHERE id = $1`, [sessionId]);
  check('G call end', 'ended_at is now genuinely set', row.rows[0]?.ended_at != null, 'true');

  // Idempotent by design (recordCallEnd()'s own doc comment) — both parties
  // hanging up at once must be a real, honest no-op, never an error.
  const res2 = await end(CHILD, sessionId, dadTok);
  check('G call end', 'ending an already-ended call is a real 200, not an error', res2.status, 200);
  check('G call end', 'ended is false the second time — a genuine no-op, not a re-write',
    res2.body.ended, false);

  // A child answering her own call must be able to end it too — the
  // generic gate's own P6/P7-only child restriction permits this by
  // design; no extra child_cannot_end_call check exists in this route.
  const started2 = await post(CHILD, dadTok);
  const res3 = await end(CHILD, started2.body.sessionId, childTok);
  check('G call end', 'a child ending a real call she was a party to is allowed', res3.status, 200);
  check('G call end', 'ended is true for the child-initiated end too', res3.body.ended, true);
}

// ===========================================================================
// H · observer-only guardian — §17.3/I4. rooms.ts's deriveGrant() computes
//     `canPublish: !principal.observerOnly`, but this route minted
//     `observerOnly: false` as a literal constant regardless of the
//     caller's real edge (routes.mjs:446, found by a 2026-08-24 audit) — the
//     exact hardcode bug ladderStep already had and was fixed for six lines
//     away in v0.49.35 (see section F above), just never caught here. No
//     test anywhere exercised an observer-only caller of this route before
//     this section.
//
//     H1 proves the easy half: authorize.ts's WRITES list does not include
//     'call', so an observer-only guardian's call-start must still succeed
//     — this bug was never a wrongful DENIAL, only a wrongly-permissive
//     GRANT, and this guards against a fix that overcorrects into blocking
//     a real §17.3 "watch without obligation" guardian from calling at all.
//
//     H2 proves the actual regression: the minted grant's `canPublish`
//     value is not itself in the HTTP response (routes.mjs's response body
//     omits `minted.token.grant` entirely — deliberately not changed by
//     this fix, see that route's own reasoning) and nothing in call_log
//     persists it either, so — unlike ladderStep, which reaches a real,
//     readable call_log column — there is no black-box HTTP observation
//     that distinguishes "wired correctly" from "hardcoded false" for this
//     specific field. session.test.mjs's own "§17.3 observer" section
//     already proves deriveGrant()/mintToken() compute canPublish correctly
//     GIVEN a correct `observerOnly` input; what was never proven anywhere
//     is that ROUTES.MJS actually passes that input in. H2 closes that gap
//     the same way packages/api/test/contract.test.mjs's own "REAL,
//     ACTUALLY-REGISTERED server route table" section already does for a
//     different silent-drift class: reading this route's own real source
//     rather than re-deriving its logic in the test, so a future revert to
//     a literal `observerOnly: false` (or `true`) fails here even though it
//     would be invisible to every response/DB assertion above.
// ===========================================================================
{
  const res = await post(CHILD_D, dadTok);
  check('H1 observer-only', 'an observer-only guardian can still start a call — §17.3 is read-only, ' +
    'not no-access; \'call\' is absent from authorize.ts\'s WRITES list', res.status, 201);
  check('H1 observer-only', 'the call is genuinely accepted, not silently downgraded to a denial',
    typeof roomFromToken(res.body.token) === 'string' && roomFromToken(res.body.token).length > 0, 'true');

  const routesSrc = readFileSync(new URL('../routes.mjs', import.meta.url), 'utf8');
  const callStartAt = routesSrc.indexOf(`path: '/v1/children/:childId/calls'`);
  const callEndAt = routesSrc.indexOf(`path: '/v1/children/:childId/calls/:sessionId/end'`);
  check('H2 wiring', 'both the call-start and call-end route registrations were found in routes.mjs',
    callStartAt >= 0 && callEndAt > callStartAt, 'true');
  const handlerSrc = routesSrc.slice(callStartAt, callEndAt);

  check('H2 wiring', 'mintToken is no longer called with a hardcoded observerOnly boolean literal — ' +
    'the exact regression this section exists to catch',
    /observerOnly:\s*(?:true|false)\s*,/.test(handlerSrc), 'false');
  check('H2 wiring', 'mintToken\'s principal instead reads observerOnly from a real identifier',
    /mintToken\(\s*session,\s*\{[^}]*observerOnly:\s*[A-Za-z_$][\w$]*\b/.test(handlerSrc), 'true');
  check('H2 wiring', 'that identifier is sourced from this caller\'s real per-edge observerOnly — ' +
    'not a fresh literal or an unrelated variable',
    /edges\.find\(.*?\)\??\.observerOnly/.test(handlerSrc), 'true');
}

// ===========================================================================
// I · the real join route — MASTERFILE §16.2 #6 REVERSED AGAIN, Option B.
//     LiveKit requires a real per-identity token to join at all, unlike
//     Jitsi's bare-room-name join — so the callee (almost always the child
//     answering a real call_incoming push) needs her own real mint of an
//     EXISTING session, not a fresh one. See routes.mjs's own comment on
//     this route for the fuller account.
// ===========================================================================
{
  const started = await post(CHILD, dadTok);
  const startedRoom = roomFromToken(started.body.token);

  // The child answering — the actual case this route exists for.
  const childJoin = await join(CHILD, started.body.sessionId, childTok);
  check('I join', 'the child can join the call she was rung for', childJoin.status, 200);
  check('I join', 'she lands in the SAME room the guardian already started',
    roomFromToken(childJoin.body.token), startedRoom);
  check('I join', 'her identity is her own childId (I3), never client-supplied',
    childJoin.body.identity, CHILD);
  check('I join', 'her display name is real, not the caller\'s',
    childJoin.body.displayName, 'Ivy');

  // The original caller re-minting her own token (e.g. after a dropped
  // connection) — the same session, the same real authorization she always
  // had.
  const dadRejoin = await join(CHILD, started.body.sessionId, dadTok);
  check('I join', 'the original caller can also re-mint her own token', dadRejoin.status, 200);
  check('I join', 'she lands in the same room too',
    roomFromToken(dadRejoin.body.token), startedRoom);

  // A real, authorized-in-general guardian who was never part of THIS call.
  const momJoin = await join(CHILD, started.body.sessionId, momTok);
  check('I join', 'a real guardian never invited to this session is refused', momJoin.status, 403);
  check('I join', 'the reason is the real not_a_participant, not a generic denial',
    momJoin.body.error, 'not_a_participant');

  check('I join', 'a nonexistent session is a real 404',
    (await join(CHILD, 'not-a-real-session-id', dadTok)).status, 404);

  const ended = await api.handle('POST', `/v1/children/${CHILD}/calls/${started.body.sessionId}/end`,
    { authorization: `Bearer ${dadTok}` }, '');
  check('I join', 'ending the call first is a real 200', ended.status, 200);
  const joinAfterEnd = await join(CHILD, started.body.sessionId, childTok);
  check('I join', 'joining an already-ended call is refused, not silently allowed',
    joinAfterEnd.status, 404);

  check('I join', 'an unauthenticated join attempt is refused',
    (await join(CHILD, started.body.sessionId, null)).status, 401);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
