/**
 * server/routes.mjs — GET /v1/children/:childId/ribbon. MASTERFILE §20.2b's
 * oldest open gap, closed: "GuardianHome has no live-data screen" (first
 * confirmed v0.49.15, still true at v0.49.57). guardian_home.dart's own
 * header has said since it was written, "All times arrive pre-rendered from
 * /now and /ribbon so the client does no zone maths" — /now has existed and
 * been real all along (now_route.test.mjs); this route is the second,
 * previously-only-declared half (api_client.dart's own `OliveApi.childRibbon`
 * path constant existed with zero server route or client fetch method
 * behind it).
 *
 * Mirrors now_route.test.mjs's/presence_route.test.mjs's own pattern exactly
 * (same DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness, same
 * frozen-NOW Api instance, same "compute the expected answer the SAME way
 * the route does" discipline) for the identical reason those files' own
 * headers give: a fake `q`/`pool` can only prove the ROUTE shape, never
 * whether the real SQL against real day_part/guardian_availability_window
 * rows returns what childCtxFor()/availabilityFor() and this route's own
 * weekday filtering assume it does.
 *
 * A SEPARATE guardian pair per availability scenario, deliberately — same
 * reason presence_route.test.mjs's own header gives: guardian_availability_
 * window (0010_availability.sql) has no child_id column at all, so reusing
 * one guardian across scenarios would leak one scenario's windows into
 * another's assertions.
 *
 * Proves, against a real Postgres:
 *   (A) today's real day-parts (matching weekday) come back, mapped
 *       correctly; a day-part scoped to a DIFFERENT weekday is excluded.
 *   (B) the caller's OWN availability windows for today come back; a
 *       DIFFERENT weekday window is excluded; a CO-GUARDIAN's window (same
 *       weekday, different guardian) is excluded too — this is "you", not
 *       "every guardian".
 *   (C) the child's real display_name is returned, sourced correctly for a
 *       GUARDIAN caller (GET /v1/me has no analog here — it returns the
 *       CALLER's own name).
 *   (D) overlapLabel is always absent/null — a deliberate, disclosed
 *       omission (see routes.mjs's own comment at this route), not a bug.
 *   (E) authorization: a real parent guardian -> 200; a real sitter with a
 *       genuine live edge to this exact child (calendar.view, not a parent)
 *       -> 403 not_a_parent_of_child; a guardian with edges to OTHER
 *       children but not this one -> 403 no_edge (the ordinary can() gate);
 *       a child session for this exact child -> 403 not_a_parent_of_child
 *       (no child-self branch exists on this route at all — GuardianHome
 *       has no child-facing caller); no session -> 401.
 *
 * NOT separately tested: a genuinely nonexistent child_id reaching this
 * route's own `child_not_found` 404. Every real path to this handler first
 * passes through parentGuardiansOfChild()'s edge check, and `guardianship
 * .child_id` is FK-constrained to a real `child` row — the same reason
 * now_route.test.mjs, this route's own sibling, never tests that branch
 * either. The 404 return exists as defensive code (matching /now's/
 * /presence's own identical fallback shape), not as a reachable-in-practice
 * branch this suite can construct without weakening referential integrity.
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

const DAD = '11111111-2222-4111-9111-000000000001';
const MOM = '22222222-2222-4222-9222-000000000001'; // co-guardian; her own window must never leak into DAD's "you" ribbon
const STRANGER_DAD = '11111111-2222-4111-9111-000000000002'; // real edges to OTHER children, none to CHILD
const SITTER = '44444444-2222-4444-9444-000000000001'; // real edge to CHILD, calendar.view, NOT a parent
const ALL_USERS = [DAD, MOM, STRANGER_DAD, SITTER];

const CHILD = '55555555-2222-4555-9555-000000000001';
const CHILD_OTHER = '66666666-2222-4666-9666-000000000001'; // STRANGER_DAD's real, unrelated child
const ALL_CHILDREN = [CHILD, CHILD_OTHER];

// No child_tz_interval row for CHILD -- pure home_tz fallback, same posture
// now_route.test.mjs's own "B fallback" section already established; this
// suite doesn't need to re-prove that branch, only that /ribbon's own
// tz-resolution block (and therefore its weekday computation) lands on the
// same zone /now would.
const CHILD_ZONE = 'America/Los_Angeles';

async function cleanup() {
  await admin.query(`DELETE FROM guardian_availability_window WHERE guardian_id = ANY($1::uuid[])`, [ALL_USERS]);
  await admin.query(`DELETE FROM day_part WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM custody_order WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ALL_USERS]);
}

await cleanup();

const SECRET = Buffer.from('r'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

// Computed from the SAME frozen NOW the Api instance uses, in the SAME zone
// the route will resolve for CHILD (no child_tz_interval row -> home_tz
// fallback = CHILD_ZONE) -- now_route.test.mjs's/presence_route.test.mjs's
// own "independently compute the expected answer the SAME way the route
// does" discipline, not a hardcoded wall-clock guess.
const local = DateTime.fromMillis(NOW, { zone: 'utc' }).setZone(CHILD_ZONE);
const nowWeekday = local.weekday % 7; // Sun=0..Sat=6
// A day-part/window scoped to this weekday can never coincide with
// nowWeekday, for any real `local` value -- no clock-time arithmetic
// involved, nothing to wrap past midnight (same technique presence_route
// .test.mjs's own section D uses, for the identical reason).
const farWeekday = (nowWeekday + 3) % 7;

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'StrangerDad','America/Chicago'), ($4,'Sitter','America/Chicago')`,
  [DAD, MOM, STRANGER_DAD, SITTER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'RibbonChild','2016-04-02',$3),
     ($2,'OtherChild','2016-04-02',$3)`,
  [CHILD, CHILD_OTHER, CHILD_ZONE]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $4, 'sitter',   '{}', tstzrange(now() - interval '1 year', null)),
     ($5, $6, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, SITTER, CHILD_OTHER, STRANGER_DAD]);
// day_part.days_of_week is always an explicit, fully-populated array in real
// use (db/test/0002_seed.sql's own convention) -- '{0..6}' for every day, a
// single-element array to scope one to a specific weekday.
await admin.query(
  `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
   VALUES
     ($1,'school','08:00','15:00',$2,true,'[2020-01-01,2099-12-31)'),
     ($1,'dinner','18:00','18:30',$2,true,'[2020-01-01,2099-12-31)'),
     ($1,'activity','17:00','18:00',$3,true,'[2020-01-01,2099-12-31)')`,
  [CHILD, [nowWeekday], [farWeekday]]);
await admin.query(
  `INSERT INTO guardian_availability_window (guardian_id, weekday, start_local, end_local, note) VALUES
     ($1, $2, '17:00', '20:00', 'evenings'),
     ($1, $3, '09:00', '10:00', 'wrong weekday, must not appear'),
     ($4, $2, '17:00', '20:00', 'co-guardian, must not leak into DAD''s ribbon')`,
  [DAD, nowWeekday, farWeekday, MOM]);
await admin.query('COMMIT');

const tok = (userId, roleName) =>
  issueSession(SECRET, { userId, roleName, childId: null, escalated: false }, NOW);
const dadTok = tok(DAD, 'guardian');
const strangerTok = tok(STRANGER_DAD, 'guardian');
const sitterTok = tok(SITTER, 'sitter');
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const get = (childId, tokv) => api.handle(
  'GET', `/v1/children/${childId}/ribbon`,
  tokv ? { authorization: `Bearer ${tokv}` } : {}, '',
);

// ===========================================================================
// A · day-parts — today's real weekday-scoped parts come back; a part
//     scoped to a different weekday is excluded. Proves this route's own
//     weekday filter, not just childCtxFor()'s pre-existing effective-date
//     filter (already proven elsewhere).
// ===========================================================================
{
  const res = await get(CHILD, dadTok);
  check('A day-parts', 'authorized guardian -> 200', res.status, 200);
  const kinds = (res.body.dayParts ?? []).map((p) => p.kind).sort();
  check('A day-parts', "today's two real day-parts (school, dinner) both appear",
    kinds.join(','), 'dinner,school');
  check('A day-parts', "the far-weekday day-part (activity) is excluded",
    kinds.includes('activity'), 'false');
  const school = res.body.dayParts.find((p) => p.kind === 'school');
  check('A day-parts', 'a returned day-part carries the real starts_local/ends_local',
    `${school.startsLocal}-${school.endsLocal}`, '08:00-15:00');
  check('A day-parts', 'a returned day-part carries the real reachable flag',
    school.reachable, 'true');
}

// ===========================================================================
// B · availability windows — the CALLER's own window for today comes back;
//     her own window for a different weekday is excluded; MOM's window
//     (same weekday, different guardian) never leaks into DAD's "you" ribbon.
// ===========================================================================
{
  const res = await get(CHILD, dadTok);
  check('B actor windows', 'exactly one window comes back (not MOM\'s, not the far-weekday one)',
    (res.body.actorWindows ?? []).length, 1);
  const w = res.body.actorWindows[0];
  check('B actor windows', 'it is DAD\'s own today window, with the real start/end/note',
    `${w.startLocal}-${w.endLocal}-${w.note}`, '17:00-20:00-evenings');

  // MOM has a real, live edge to CHILD too -- her own ribbon must show HER
  // window, not DAD's, proving the filter keys off the caller, not the
  // child.
  const momTok = tok(MOM, 'guardian');
  const momRes = await get(CHILD, momTok);
  check('B actor windows', "MOM's own /ribbon call sees zero windows (she has none seeded for herself)",
    (momRes.body.actorWindows ?? []).length, 0);
}

// ===========================================================================
// C · childName — real, sourced from child.display_name for a GUARDIAN
//     caller (GET /v1/me has no analog: that route returns the CALLER's own
//     name, never the child's, for a guardian principal).
// ===========================================================================
{
  const res = await get(CHILD, dadTok);
  check('C childName', 'the real child display_name comes back', res.body.childName, 'RibbonChild');
}

// ===========================================================================
// D · overlapLabel — deliberately, always absent. See routes.mjs's own
//     comment at this route for why: an honest "child free" definition for
//     this sentence has no confirmed answer yet, and a wrong invented one is
//     worse than an honest absence GuardianHome's own nullable field already
//     renders as nothing.
// ===========================================================================
{
  const res = await get(CHILD, dadTok);
  check('D overlapLabel', 'overlapLabel is never present on the wire',
    Object.prototype.hasOwnProperty.call(res.body, 'overlapLabel'), 'false');
}

// ===========================================================================
// E · authorization — the real, narrow "parent guardian only" gate, same
//     shape presence_route.test.mjs's own section (f) already proved for
//     /presence, plus the ordinary can() denial and the no-child-self-branch
//     case unique to this route.
// ===========================================================================
{
  const stranger = await get(CHILD, strangerTok);
  check('E auth', 'a guardian with real edges to OTHER children but none to this one is refused',
    stranger.status, 403);
  check('E auth', 'the reason is the real can() denial, not an invented string',
    stranger.body.error, 'no_edge');

  const sitter = await get(CHILD, sitterTok);
  check('E auth', 'a real sitter, with a genuine live edge to this exact child, is still '
    + 'refused — not a parent, regardless of calendar.view', sitter.status, 403);
  check('E auth', 'the real reason is named, not a generic denial',
    sitter.body.error, 'not_a_parent_of_child');
  check('E auth', 'no ribbon data of any kind leaks alongside the refusal',
    sitter.body.dayParts, undefined);

  // This route has no child-self branch at all (GuardianHome has no
  // child-facing caller anywhere in this client) -- the child's own session
  // for THIS exact child must still be refused, unlike /now and /presence
  // above it, which both deliberately admit her.
  const child = await get(CHILD, childTok);
  check('E auth', "the child's own session for her own child_id is refused too "
    + '— this route has no child-self branch, unlike /now and /presence',
    child.status, 403);
  check('E auth', 'reason is the same not_a_parent_of_child, not a different code path',
    child.body.error, 'not_a_parent_of_child');

  const noSession = await get(CHILD, null);
  check('E auth', 'no session at all -> 401', noSession.status, 401);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
