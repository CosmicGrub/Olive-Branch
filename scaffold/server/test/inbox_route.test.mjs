/**
 * server/routes.mjs — GET /v1/children/:childId/inbox. Zero coverage
 * anywhere before this file (found by db/migrations/0023_message_media_
 * delivery_rls.sql's own pre-migration audit: "No dedicated test exercises
 * this route at all — checked packages/api/test/*, server/test/* — zero
 * hits on an actual GET .../inbox call; only comment references"). Written
 * as part of proving that migration safe, not as an unrelated add-on: this
 * route opens the caller's own OUTER session (no skipOuterSession) and
 * reads delivery_intent directly, making it the one real, currently-working
 * production surface a wrong RLS policy could break silently for an actual
 * end user — the child checking her own inbox, or a step_parent/trusted_
 * adult/foster_parent doing the same for a child they help raise.
 *
 * Mirrors server/test/now_route.test.mjs's own pattern and its own stated
 * reasoning for why: a fake `q`/`pool` can only prove the route's SHAPE,
 * never whether the real SQL against the real, RLS-forced delivery_intent
 * table returns what the route assumes it does.
 */
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';

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

// Randomly generated — this suite shares tools/verify.sh's one database with
// every other suite (see packages/api/test/media_route.test.mjs's own
// comment on a real, live id collision this pattern was adopted to remove).
const CHILD = randomUUID();
const CHILD_STRANGER = randomUUID();
const DAD = randomUUID();
const STEPMOM = randomUUID();
const SITTER = randomUUID();

const ALL_CHILDREN = [CHILD, CHILD_STRANGER];

const cleanup = async () => {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, STEPMOM, SITTER]]);
};

await cleanup();
await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'StepMom','America/Chicago'),
     ($3,'Sitter','America/Chicago')`, [DAD, STEPMOM, SITTER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Stranger','2016-04-02','America/New_York')`, [CHILD, CHILD_STRANGER]);
// Dad and StepMom both hold a real, live edge to CHILD; Sitter's role has no
// 'message' capability at all (packages/family-graph/src/authorize.ts's own
// ROLE_CAPS). Nobody here has any edge to CHILD_STRANGER.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian',    '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'step_parent', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $4, 'sitter',      '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, STEPMOM, SITTER]);

// Three real delivery_intent rows for CHILD: one 'delivered' (must appear),
// one 'opened' (must appear — the route's own WHERE already includes both),
// one still 'pending' (must NOT appear — proves RLS didn't silently widen
// the route's own pre-existing state filter into showing everything it can
// see). payload_ref needs no FK target (see 0023's own migration header —
// delivery_intent.payload_ref carries no REFERENCES clause).
const MSG_DELIVERED = randomUUID();
const MSG_OPENED = randomUUID();
const MSG_PENDING = randomUUID();
await admin.query(
  `INSERT INTO delivery_intent
     (id, child_id, sender_id, payload_kind, payload_ref, policy, state, expires_at)
   VALUES
     ($1, $5, $6, 'video_msg', $2, 'immediate', 'delivered', now() + interval '90 days'),
     ($3, $5, $6, 'video_msg', $2, 'immediate', 'opened',    now() + interval '90 days'),
     ($4, $5, $6, 'video_msg', $2, 'immediate', 'pending',   now() + interval '90 days')`,
  [MSG_DELIVERED, randomUUID(), MSG_OPENED, MSG_PENDING, CHILD, DAD]);
await admin.query('COMMIT');

const SECRET = Buffer.from('i'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const stepMomTok = issueSession(SECRET,
  { userId: STEPMOM, roleName: 'step_parent', childId: null, escalated: false }, NOW);
const sitterTok = issueSession(SECRET,
  { userId: SITTER, roleName: 'sitter', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);
const strangerChildTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD_STRANGER, escalated: false }, NOW);

const get = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/inbox`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);

// ===========================================================================
// A · a guardian with a real, live edge reads the real inbox — delivered
//     and opened messages, never a still-pending one.
// ===========================================================================
{
  const res = await get(CHILD, dadTok);
  check('A guardian read', 'authorized guardian -> 200', res.status, 200);
  const ids = res.body.entries.map((m) => m.id).sort();
  check('A guardian read', 'sees exactly the delivered + opened messages, not the pending one',
    ids.join(','), [MSG_DELIVERED, MSG_OPENED].sort().join(','));
  check('A guardian read', 'sender_name is the real joined app_user.display_name',
    res.body.entries.every((m) => m.sender_name === 'Dad'), 'true');
}

// ===========================================================================
// B · the child herself reads her OWN inbox — the real-time proof that
//     delivery_intent_child_own (0023's new RLS policy) matches exactly what
//     this route's own hand-written WHERE di.child_id = $1 already enforced.
// ===========================================================================
{
  const res = await get(CHILD, childTok);
  check('B child self-read', 'the child reading her own inbox -> 200', res.status, 200);
  const ids = res.body.entries.map((m) => m.id).sort();
  check('B child self-read', 'sees the same delivered + opened messages a guardian does',
    ids.join(','), [MSG_DELIVERED, MSG_OPENED].sort().join(','));
}

// ===========================================================================
// C · step_parent — the role-generalization RLS specifically had to get
//     right (0023's own header: copying 0017/0018's hardcoded 'guardian'
//     condition verbatim would have silently zeroed this out).
// ===========================================================================
{
  const res = await get(CHILD, stepMomTok);
  check('C step_parent read', 'a step_parent with a live edge -> 200', res.status, 200);
  const ids = res.body.entries.map((m) => m.id).sort();
  check('C step_parent read', 'sees the same real messages a guardian does',
    ids.join(','), [MSG_DELIVERED, MSG_OPENED].sort().join(','));
}

// ===========================================================================
// D · authorization — unchanged by RLS, still enforced by the outer
//     action:'message' gate before the query (or the query's own child_id
//     bind) is ever reached.
// ===========================================================================
{
  const sitterRes = await get(CHILD, sitterTok);
  check('D auth', 'sitter (no message capability) is refused', sitterRes.status, 403);

  const noEdge = await get(CHILD_STRANGER, dadTok);
  check('D auth', 'a guardian with no edge to this child is refused', noEdge.status, 403);

  const wrongChild = await get(CHILD, strangerChildTok);
  check('D auth', 'a different child cannot read this inbox', wrongChild.status, 403);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
