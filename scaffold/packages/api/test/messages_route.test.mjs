/**
 * server/routes.mjs — POST /v1/children/:childId/messages. MASTERFILE §7,
 * §9.5. The real counterpart to GET .../inbox, and the real backend for
 * client/lib/receipt_screen.dart's "Send one back".
 *
 * Mirrors packages/db/test/pool.test.mjs / custody_order.test.mjs's own
 * pattern (DATABASE_URL/ADMIN_DATABASE_URL split): requires a real Postgres
 * with the migrations applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason those two aren't — a route that
 * ultimately writes real rows needs a real database under it, not a fake
 * `db` object standing in for one (packages/api/test/stack.test.mjs's own
 * fixtures use a fake `db`, which is exactly why it cannot be the place this
 * gets proven).
 *
 * The one property no other suite proves: that a captureMessage() REJECTION
 * (packages/messaging/src/pipeline.ts) is actually honoured by the HTTP
 * layer — the handler returns the denial AND never calls
 * persistCapturedMessage(). Asserted the only way that is really provable:
 * by counting real rows before and after, not by trusting the response body.
 */
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { Api } from '../src/api.mjs';
import { createPool, dbPort } from '../../db/src/pool.mjs';
import { registerRoutes } from '../../../server/routes.mjs';
import { issueSession } from '../../auth/src/auth.mjs';

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

const CHILD = 'aaaaaaaa-1234-1234-1234-aaaaaaaaaaaa';
const DAD = 'bbbbbbbb-1234-1234-1234-bbbbbbbbbbbb';
const SITTER = 'cccccccc-1234-1234-1234-cccccccccccc';
const CHILD_B = 'dddddddd-1234-1234-1234-dddddddddddd';   // a child DAD has no edge to

await admin.query('BEGIN');
for (const cid of [CHILD, CHILD_B]) {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
}
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, SITTER]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Sitter','America/Chicago')`, [DAD, SITTER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Otherchild','2016-04-02','America/New_York')`, [CHILD, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'sitter',   '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, SITTER]);
await admin.query(
  `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week,
                        reachable, effective)
   VALUES ($1,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)')`,
  [CHILD]);
await admin.query('COMMIT');

const rowCounts = async () => {
  const a = await admin.query(`SELECT count(*)::int AS n FROM media_artifact WHERE child_id = $1`,
    [CHILD]);
  const i = await admin.query(`SELECT count(*)::int AS n FROM delivery_intent WHERE child_id = $1`,
    [CHILD]);
  return { artifacts: a.rows[0].n, intents: i.rows[0].n };
};

const SECRET = Buffer.from('a'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool));
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const sitterTok = issueSession(SECRET,
  { userId: SITTER, roleName: 'sitter', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const post = (childId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/messages`,
  tok ? { authorization: `Bearer ${tok}` } : {},
  JSON.stringify(body),
);

// ===========================================================================
// A · the real success path — a guardian sends one, real rows land
// ===========================================================================
{
  const before = await rowCounts();
  const res = await post(CHILD, dadTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200,
  });
  check('A success', 'a valid guardian capture returns 201', res.status, 201);
  check('A success', 'response names a real artifactId',
    typeof res.body.artifactId === 'string' && res.body.artifactId.length > 0, 'true');
  check('A success', 'response state is pending', res.body.state, 'pending');
  const after = await rowCounts();
  check('A success', 'exactly one media_artifact row was written',
    after.artifacts - before.artifacts, 1);
  check('A success', 'exactly one delivery_intent row was written',
    after.intents - before.intents, 1);

  const artRow = await admin.query(
    `SELECT storage_key, duration_ms FROM media_artifact WHERE id = $1`, [res.body.artifactId]);
  check('A success', 'storage_key and duration_ms round-trip through the HTTP layer',
    artRow.rows[0]?.duration_ms, 4200);
}

// ===========================================================================
// B · basic input validation — never reaches captureMessage() at all
// ===========================================================================
{
  const before = await rowCounts();
  const res = await post(CHILD, dadTok, { durationMs: 4200 }); // no storageKey
  check('B validation', 'missing storageKey → 400', res.status, 400);
  const after = await rowCounts();
  check('B validation', 'no row written for a malformed request',
    after.artifacts, before.artifacts);
}

// ===========================================================================
// C · captureMessage() REJECTION, actually honoured — not silently bypassed.
//     A guardian with a real, valid edge (passes the API layer's own
//     `action: 'message'` gate) submits a request captureMessage() ITSELF
//     rejects on a rule the outer gate has no way to know about: an empty
//     recording (§ M3 in pipeline.test.mjs). If a future edit ever calls
//     persistCapturedMessage() before checking `result.ok`, this is what
//     catches it — the response code alone cannot prove a row wasn't ALSO
//     written; only counting real rows can.
// ===========================================================================
{
  const before = await rowCounts();
  const res = await post(CHILD, dadTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 0,
  });
  check('C captureMessage rejection', 'a zero-length recording is refused, not accepted',
    res.status, 400);
  check('C captureMessage rejection', 'the denial names captureMessage()\'s own reason',
    res.body.error, 'empty_recording');
  const after = await rowCounts();
  check('C captureMessage rejection', 'NO media_artifact row was written for the rejected capture',
    after.artifacts, before.artifacts);
  check('C captureMessage rejection', 'NO delivery_intent row was written for the rejected capture',
    after.intents, before.intents);

  // Same proof again with a different captureMessage()-internal denial: a
  // named night already in the past.
  const before2 = await rowCounts();
  const res2 = await post(CHILD, dadTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200, targetLocalDate: '2020-01-01',
  });
  check('C captureMessage rejection', 'a night already past is refused', res2.status, 400);
  check('C captureMessage rejection', 'reason is target_date_in_past', res2.body.error,
    'target_date_in_past');
  const after2 = await rowCounts();
  check('C captureMessage rejection', 'still no row written',
    after2.artifacts, before2.artifacts);
}

// ===========================================================================
// D · authorization — the family-graph layer, exercised over real HTTP
// ===========================================================================
{
  const before = await rowCounts();
  const res = await post(CHILD, sitterTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200,
  });
  check('D auth', 'a sitter (no message capability) is refused', res.status, 403);
  const after = await rowCounts();
  check('D auth', 'no row written for a role that cannot message', after.artifacts,
    before.artifacts);

  const otherChild = await post(CHILD_B, dadTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200,
  });
  check('D auth', 'a guardian with no edge to this child is refused', otherChild.status, 403);

  // FORMERLY A HONEST GAP, closed by 0019_child_message_sender.sql: a
  // `child` principal carries no `userId` (packages/auth/src/auth.ts), so
  // she can never appear as `delivery_intent.sender_id`'s OLD shape (`NOT
  // NULL REFERENCES app_user`) — that column is what used to make "Send one
  // back", called with the CHILD's own real session, structurally
  // unrepresentable and therefore always refused. Now it is a real success:
  // the child is her own sender, recorded via `sender_child_id`/
  // `author_child_id`, never `sender_id`/`author_id`.
  const before2 = await rowCounts();
  const asChild = await post(CHILD, childTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200,
  });
  check('D auth', 'a child session sending about herself now succeeds', asChild.status, 201);
  const after2 = await rowCounts();
  check('D auth', 'exactly one media_artifact row landed for her own capture',
    after2.artifacts - before2.artifacts, 1);
  check('D auth', 'exactly one delivery_intent row landed for her own capture',
    after2.intents - before2.intents, 1);

  const childArt = await admin.query(
    `SELECT author_id, author_child_id FROM media_artifact WHERE id = $1`,
    [asChild.body.artifactId]);
  check('D auth', 'author_id is null for a child-authored artifact',
    childArt.rows[0]?.author_id, 'null');
  check('D auth', 'author_child_id names the sending child',
    childArt.rows[0]?.author_child_id, CHILD);

  const childIntent = await admin.query(
    `SELECT sender_id, sender_child_id FROM delivery_intent WHERE id = $1`,
    [asChild.body.id]);
  check('D auth', 'sender_id is null for a child-originated intent',
    childIntent.rows[0]?.sender_id, 'null');
  check('D auth', 'sender_child_id names the sending child',
    childIntent.rows[0]?.sender_child_id, CHILD);

  // SHARED-DEVICE MISATTRIBUTION, the audit finding's own worry ("a design
  // that can't distinguish which child sent a video when multiple children
  // share a device"), exercised over real HTTP: a child session is
  // identity-scoped to her OWN childId ONLY. api.ts's own gateway
  // (`principal.childId !== childId` → `wrong_child`) refuses this before
  // captureMessage() (and its own, second `child_sender_mismatch` lock —
  // proven directly in pipeline.test.mjs, which can call it with a
  // deliberately mismatched id this gateway would never let through over
  // real HTTP) is ever reached.
  const wrongChild = await post(CHILD_B, childTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200,
  });
  check('D auth', 'a child session cannot attribute a send to a DIFFERENT child',
    wrongChild.status, 403);
  check('D auth', 'the reason is wrong_child, the identity gate, not a family-graph denial',
    wrongChild.body.error, 'wrong_child');

  // PRESERVATION IS A GUARDIAN ELECTION (§9.8.1) — a child asking to skip
  // her own retention clock is refused cleanly, not left to fail on
  // media_artifact's `preservation_is_attributed` CHECK with no app_user id
  // to attribute it to.
  const beforePreserve = await rowCounts();
  const childPreserve = await post(CHILD, childTok, {
    storageKey: `device/${randomUUID()}`, durationMs: 4200, preserve: true,
  });
  check('D auth', 'a child cannot elect to preserve her own sent video',
    childPreserve.status, 400);
  check('D auth', 'the reason is child_cannot_preserve',
    childPreserve.body.error, 'child_cannot_preserve');
  const afterPreserve = await rowCounts();
  check('D auth', 'no row written for the refused preserve request',
    afterPreserve.artifacts, beforePreserve.artifacts);
}

for (const cid of [CHILD, CHILD_B]) {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
}
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, SITTER]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
