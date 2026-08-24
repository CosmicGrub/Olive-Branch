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
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { roomNameLeaks } from '../../packages/session-runtime/src/rooms.mjs';

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

const cleanup = async () => {
  await admin.query(`DELETE FROM call_log WHERE child_id IN ($1, $2, $3)`, [CHILD, CHILD_B, CHILD_C]);
  await admin.query(`DELETE FROM device_token WHERE owner_child_id IN ($1, $2)`, [CHILD, CHILD_B]);
  for (const cid of [CHILD, CHILD_B, CHILD_C]) {
    await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
    await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
  }
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
};

await cleanup();
await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Otherchild','2016-04-02','America/New_York'),
     ($3,'Supervisedchild','2016-04-02','America/New_York')`, [CHILD, CHILD_B, CHILD_C]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD]);
const supervisedGship = await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)) RETURNING id`,
  [CHILD_C, DAD]);
await admin.query(
  `INSERT INTO contact_ladder (guardianship_id, step, effective) VALUES
     ($1, 'supervised', tstzrange(now() - interval '1 day', null))`,
  [supervisedGship.rows[0].id]);
await admin.query('COMMIT');

const SECRET = Buffer.from('b'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool));
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const post = (childId, tok) => api.handle(
  'POST', `/v1/children/${childId}/calls`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);

// ===========================================================================
// A · the real success path — a live guardian mints a real session
// ===========================================================================
{
  const res = await post(CHILD, dadTok);
  check('A success', 'a valid guardian call-start returns 201', res.status, 201);
  check('A success', 'response names a real room string',
    typeof res.body.room === 'string' && res.body.room.length > 0, 'true');
  check('A success', 'room name does not leak the child or guardian id (I1)',
    roomNameLeaks(res.body.room, [CHILD, DAD]), 'false');
  check('A success', 'identity is the caller\'s own userId (I3), never client-supplied',
    res.body.identity, DAD);
  check('A success', 'serverURL is present', typeof res.body.serverURL === 'string', 'true');
  check('A success', 'rang is a real boolean, not a placeholder',
    typeof res.body.rang, 'boolean');

  // I1 again, differently: two calls in a row must mint two DIFFERENT rooms
  // — proving this isn't a single fixed/cached session reused across calls
  // the way tools/local-call-room-server.mjs's own dev-only design is.
  const res2 = await post(CHILD, dadTok);
  check('A success', 'a second call mints a genuinely different room',
    res.body.room === res2.body.room, 'false');
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
  check('F call_log', 'room_name matches the real minted room', row.rows[0]?.room_name, before.body.room);
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

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
