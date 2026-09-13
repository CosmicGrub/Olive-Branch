/**
 * server/routes.mjs — GET /v1/children/:childId/now. MASTERFILE §6.1's
 * childZoneAt() (prose only -- see routes.mjs's own header comment: the
 * real resolution logic is hand-inlined in this route's handler, not a
 * shared function, because packages/time-engine/src/time.ts's exports are
 * all pure/no-DB). A 2026-08-23 audit (§6.1, Tier-3) flagged this route's
 * coverage as thin/missing. It was worse than thin -- it was ZERO:
 *
 *   - packages/time-engine/test/golden.test.mjs proves resolveZone(), the
 *     PURE function, against hand-fabricated interval arrays. This route
 *     never calls resolveZone() -- it hand-rolls the identical "does an
 *     interval cover `now`, else fall back to home_tz" logic as a live SQL
 *     query (`valid @> $2::timestamptz` + a second SELECT), so proving the
 *     pure function proves nothing about whether THIS query is correct.
 *   - server/test/routes.test.mjs proves this route's own sibling,
 *     /custody-order, end-to-end -- but only /custody-order. It does not
 *     import, path-match, or assert on /now at all.
 *   - No suite anywhere (grep for `/now`, `childLocalTime`,
 *     `sleepsUntilHandover` across server/test and packages/*\/test turns
 *     up nothing but this file) ever sent an HTTP request through this
 *     route, real or faked, before this suite existed.
 *
 * So both real branches of the route's own zone resolution (a genuine
 * active child_tz_interval row vs. the child.home_tz fallback when none
 * exists) and its authz gate (a guardian with edges to OTHER children but
 * not this one) had never been exercised against a real Postgres row.
 * Mirrors server/test/calls_route.test.mjs's own pattern for exactly that
 * reason: a fake `q`/`pool` can only prove the ROUTE shape, never whether
 * the real SQL against the real child_tz_interval table returns what the
 * route assumes it does.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
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

const DAD = 'aaaaaaaa-1111-4a1a-9a1a-aaaaaaaaaaaa';
// CHILD_REAL_TZ — a real, currently-active child_tz_interval row. Her
// home_tz is a real, DIFFERENT zone (America/New_York), so a route that
// silently fell through to the fallback instead of reading the interval
// would be caught, not accidentally right by coincidence.
const CHILD_REAL_TZ = 'bbbbbbbb-2222-4b1b-9b1b-bbbbbbbbbbbb';
// CHILD_FALLBACK — a real child row with ZERO child_tz_interval rows at
// all (genuinely none, not an empty/expired one) -- the pure-fallback path.
const CHILD_FALLBACK = 'cccccccc-3333-4c1c-9c1c-cccccccccccc';
// CHILD_STRANGER — DAD has no edge to this child at all, despite having
// real, live edges to the two children above. The exact shape the audit
// asked be proven: "does a guardian of a DIFFERENT child get refused?"
const CHILD_STRANGER = 'dddddddd-4444-4d1d-9d1d-dddddddddddd';

const ALL_CHILDREN = [CHILD_REAL_TZ, CHILD_FALLBACK, CHILD_STRANGER];

const cleanup = async () => {
  await admin.query(`DELETE FROM child_tz_interval WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM custody_order WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
};

await cleanup();
await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'RealTzChild','2016-04-02','America/New_York'),
     ($2,'FallbackChild','2018-01-01','America/Denver'),
     ($3,'StrangerChild','2016-04-02','America/New_York')`,
  [CHILD_REAL_TZ, CHILD_FALLBACK, CHILD_STRANGER]);
// DAD has real, live edges to the first two children -- NOT to the third.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($3, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_REAL_TZ, DAD, CHILD_FALLBACK]);
// CHILD_REAL_TZ's home_tz says America/New_York; her REAL, currently-active
// interval says America/Los_Angeles -- a 3-hour gap, deliberately far
// enough apart that "wrong zone" can never read as an accidental pass.
await admin.query(
  `INSERT INTO child_tz_interval (child_id, tz, valid, source, confidence)
   VALUES ($1, 'America/Los_Angeles', tstzrange(now() - interval '1 day', null), 'manual', 100)`,
  [CHILD_REAL_TZ]);
await admin.query('COMMIT');

const SECRET = Buffer.from('n'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD_REAL_TZ, escalated: false }, NOW);

const get = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/now`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);

// ===========================================================================
// A · child_tz_interval branch — a real, active interval row must win over
//     a real, DIFFERENT home_tz. The half of §6.1's childZoneAt() no suite
//     had ever exercised against an actual Postgres row before this one.
// ===========================================================================
{
  const res = await get(CHILD_REAL_TZ, dadTok);
  check('A real interval', 'authorized guardian -> 200', res.status, 200);
  check('A real interval', 'zone is the REAL interval tz, not home_tz',
    res.body.zone, 'America/Los_Angeles');
  check('A real interval', 'zone is NOT the (different, real) home_tz fallback value',
    res.body.zone === 'America/New_York', 'false');

  // Independently compute the expected wall-clock answer the SAME way the
  // route does, from the SAME frozen `now` the route's Api instance uses --
  // proving the full pipeline (real row -> zone -> childLocalTime/zoneAbbr),
  // not just that some non-home_tz string happened to come back.
  const expected = DateTime.fromMillis(NOW, { zone: 'utc' }).setZone('America/Los_Angeles');
  check('A real interval', 'childLocalTime matches independently-computed LA wall clock',
    res.body.childLocalTime, expected.toFormat('h:mm a'));
  check('A real interval', 'zoneAbbr matches independently-computed LA abbreviation',
    res.body.zoneAbbr, expected.toFormat('ZZZZ'));

  // The owning child herself can also read it, and must get the identical,
  // real interval-derived answer -- not some child-safe stand-in.
  const asChild = await get(CHILD_REAL_TZ, childTok);
  check('A real interval', 'the owning child can read her own /now too -> 200', asChild.status, 200);
  check('A real interval', 'and gets the same real interval zone', asChild.body.zone, 'America/Los_Angeles');
}

// ===========================================================================
// B · home_tz fallback branch — a real child with ZERO child_tz_interval
//     rows falls back to the real child.home_tz (`interval[0]?.tz`
//     genuinely undefined against the real query), not a fabricated array.
// ===========================================================================
{
  const res = await get(CHILD_FALLBACK, dadTok);
  check('B fallback', 'authorized guardian -> 200', res.status, 200);
  check('B fallback', 'zone falls back to the real child.home_tz', res.body.zone, 'America/Denver');

  const expected = DateTime.fromMillis(NOW, { zone: 'utc' }).setZone('America/Denver');
  check('B fallback', 'childLocalTime matches independently-computed Denver wall clock',
    res.body.childLocalTime, expected.toFormat('h:mm a'));

  // Honest absence downstream too: no custody_order row for this child, so
  // sleepsUntilHandover must be null, never a guessed countdown -- proven
  // here through the REAL route + REAL DB, not just schedule.mjs's own
  // already-passing, DB-free unit test.
  check('B fallback', 'sleepsUntilHandover is null -- no custody order exists for this child',
    res.body.sleepsUntilHandover, 'null');
}

// ===========================================================================
// C · authorization — the exact gap the audit named: does a guardian with
//     real, live edges to OTHER children get refused for one she has none
//     to? Runs through the ordinary generic gate (action: 'calendar.view'),
//     so the denial is authorize.ts's own can()/'no_edge', not a hand-
//     rolled check in this route.
// ===========================================================================
{
  const res = await get(CHILD_STRANGER, dadTok);
  check('C auth', 'a guardian with real edges to OTHER children but none to this one is refused',
    res.status, 403);
  check('C auth', 'the reason is the real can() denial, not an invented string',
    res.body.error, 'no_edge');

  const noSession = await get(CHILD_REAL_TZ, null);
  check('C auth', 'no session at all -> 401', noSession.status, 401);

  const wrongChild = await get(CHILD_FALLBACK, childTok);
  check('C auth', "a child token can't reach another child's /now -> 403", wrongChild.status, 403);
  check('C auth', 'reason is wrong_child', wrongChild.body.error, 'wrong_child');
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
