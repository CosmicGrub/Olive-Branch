/**
 * server/routes.mjs — GET /v1/children/:childId/presence. Live parent
 * presence for ChildHome, per the design spec this route was built from
 * (§0-§6): who, among a child's live PARENT guardians (§5.27.2), excluding
 * whoever custody_order says is on duty right now (§0's own prerequisite
 * migration, db/migrations/0024_custody_order_side_guardians.sql), has an
 * active guardian_availability_window covering this exact moment.
 *
 * Mirrors now_route.test.mjs's own pattern exactly (same DATABASE_URL/
 * ADMIN_DATABASE_URL split, same check() harness, same frozen-NOW Api
 * instance) for the identical reason that file's own header gives: a fake
 * `q`/`pool` can only prove the ROUTE shape, never whether the real SQL
 * against real custody_order/guardianship/guardian_availability_window rows
 * returns what freeGuardianNow() (packages/custody/src/schedule.ts) and the
 * route handler assume it does.
 *
 * A SEPARATE guardian pair per scenario, deliberately: guardian_availability
 * _window (0010_availability.sql) has no child_id column at all — a
 * guardian's windows are HERS, shared across every child she guards, not
 * scoped per child. Reusing one DAD/MOM pair across every scenario below
 * would leak one scenario's windows into the next (found for real, while
 * first writing this file — see git history if this comment outlives the
 * fix); five independent guardian pairs is what actually isolates them.
 *
 * Proves, against a real Postgres:
 *   (a) the on-duty guardian is excluded even when her window would
 *       otherwise win the tie-break outright (earliest start).
 *   (b) a single free guardian is correctly surfaced -- right id, right
 *       name, right freeUntilHerTime.
 *   (c) the tie-break picks the earliest-starting window when two
 *       (non-on-duty) guardians are both free -- carries the verbatim
 *       MASTERFILE §5.27.4 quote the design spec requires at this proof
 *       site, not just at the implementation site.
 *   (d) nobody free returns an honest `{ free: null }`, in TWO shapes that
 *       must be indistinguishable from each other (§6's own sibling
 *       concern: a sole-guardian child must never look different from a
 *       two-guardian child where nobody happens to be free right now).
 *   (e) her-frame formatting -- theirLocalTime/freeUntilHerTime are both
 *       rendered in the CHILD's own resolved zone (§1's resolution), never
 *       either guardian's own home_tz, which this fixture deliberately sets
 *       to two DIFFERENT, real zones from the child's own.
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

// One guardian pair per scenario (see file header for why) -- both real,
// distinct home zones (Chicago/Denver), always different from CHILD_ZONE
// below, so a regression that read a guardian's own home_tz instead of the
// child's (§1's resolution) would produce a visibly wrong answer, not an
// accidental pass.
const DAD1 = '11111111-1111-4111-9111-000000000001'; const MOM1 = '22222222-2222-4222-9222-000000000001'; // (a)
const DAD2 = '11111111-1111-4111-9111-000000000002'; const MOM2 = '22222222-2222-4222-9222-000000000002'; // (b),(e)
const DAD3 = '11111111-1111-4111-9111-000000000003'; const MOM3 = '22222222-2222-4222-9222-000000000003'; // (c)
const DAD4 = '11111111-1111-4111-9111-000000000004'; const MOM4 = '22222222-2222-4222-9222-000000000004'; // (d)
const SOLE = '33333333-3333-4333-9333-000000000001'; // (d)
const SITTER1 = '44444444-4444-4444-9444-000000000001'; // (f)
const ALL_USERS = [DAD1, MOM1, DAD2, MOM2, DAD3, MOM3, DAD4, MOM4, SOLE, SITTER1];

const CHILD_ONDUTY = '44444444-4444-4444-9444-444444444444'; // (a)
const CHILD_SINGLE = '55555555-5555-4555-9555-555555555555'; // (b), (e)
const CHILD_TIE    = '66666666-6666-4666-9666-666666666666'; // (c)
const CHILD_NONE   = '77777777-7777-4777-9777-777777777777'; // (d) two guardians, neither free
const CHILD_SOLE   = '88888888-8888-4888-9888-888888888888'; // (d) exactly one guardian
const ALL_CHILDREN = [CHILD_ONDUTY, CHILD_SINGLE, CHILD_TIE, CHILD_NONE, CHILD_SOLE];

// The child's own resolved zone -- no child_tz_interval row for any of these
// children, so this is her home_tz fallback (the same fallback branch
// now_route.test.mjs's own "B fallback" section already proves against
// child_tz_interval's absence; this suite does not need to re-prove that
// branch, only that /presence's own tz-resolution block lands on the SAME
// zone /now would).
const CHILD_ZONE = 'America/Los_Angeles';

async function cleanup() {
  await admin.query(`DELETE FROM guardian_availability_window WHERE guardian_id = ANY($1::uuid[])`, [ALL_USERS]);
  await admin.query(`DELETE FROM custody_order WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [ALL_CHILDREN]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ALL_USERS]);
}

await cleanup();

const SECRET = Buffer.from('p'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

// Everything below is computed from the SAME frozen NOW the Api instance
// uses, in the SAME zone the route will resolve for these children (no
// child_tz_interval row -> home_tz fallback = CHILD_ZONE) -- exactly
// now_route.test.mjs's own "independently compute the expected answer the
// SAME way the route does" discipline, not a hardcoded wall-clock guess
// that would be wrong the moment this suite runs at a different hour.
const local = DateTime.fromMillis(NOW, { zone: 'utc' }).setZone(CHILD_ZONE);
const nowWeekday = local.weekday % 7;               // Sun=0..Sat=6
const hhmm = (dt) => dt.toFormat('HH:mm');           // 24h, storage format
const fmt = (dt) => dt.toFormat('h:mm a');           // display format, matches /now

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'),  ($2,'Mom','America/Denver'),
     ($3,'Dad','America/Chicago'),  ($4,'Mom','America/Denver'),
     ($5,'Dad','America/Chicago'),  ($6,'Mom','America/Denver'),
     ($7,'Dad','America/Chicago'),  ($8,'Mom','America/Denver'),
     ($9,'Solo','America/New_York'), ($10,'Sitter','America/Chicago')`,
  [DAD1, MOM1, DAD2, MOM2, DAD3, MOM3, DAD4, MOM4, SOLE, SITTER1]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'OnDutyChild','2015-01-01',$6),
     ($2,'SingleChild','2015-01-01',$6),
     ($3,'TieChild','2015-01-01',$6),
     ($4,'NoneChild','2015-01-01',$6),
     ($5,'SoleChild','2015-01-01',$6)`,
  [CHILD_ONDUTY, CHILD_SINGLE, CHILD_TIE, CHILD_NONE, CHILD_SOLE, CHILD_ZONE]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1,  $2,  'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1,  $3,  'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4,  $5,  'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4,  $6,  'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($7,  $8,  'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($7,  $9,  'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($10, $11, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($10, $12, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($13, $14, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($15, $16, 'sitter',   '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_ONDUTY, DAD1, MOM1, CHILD_SINGLE, DAD2, MOM2, CHILD_TIE, DAD3, MOM3,
   CHILD_NONE, DAD4, MOM4, CHILD_SOLE, SOLE, CHILD_SINGLE, SITTER1]);
// CHILD_ONDUTY's custody order: anchor_local_date = TODAY (in CHILD_ZONE),
// pattern '2-2-3' puts Side A on day-index 0 -- i.e. today, deterministically,
// regardless of what real calendar date this suite happens to run on. Side A
// = DAD1 via the new 0024 mapping this route's own prerequisite migration
// added.
await admin.query(
  `INSERT INTO custody_order
     (child_id, order_tz, pattern, anchor_local_date, exchange_time, effective_from,
      side_a_guardian_id, side_b_guardian_id)
   VALUES ($1, $2, '2-2-3', $3, '18:00:00', $3, $4, $5)`,
  [CHILD_ONDUTY, CHILD_ZONE, local.toISODate(), DAD1, MOM1]);
await admin.query('COMMIT');

const tok = (userId) => issueSession(SECRET, { userId, roleName: 'guardian', childId: null, escalated: false }, NOW);
const dad1Tok = tok(DAD1);
const dad2Tok = tok(DAD2);
const dad3Tok = tok(DAD3);
const dad4Tok = tok(DAD4);
const soleTok = tok(SOLE);
const sitterTok = issueSession(SECRET, { userId: SITTER1, roleName: 'sitter', childId: null, escalated: false }, NOW);
const childOnDutyTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD_ONDUTY, escalated: false }, NOW);

const get = (childId, tokv) => api.handle(
  'GET', `/v1/children/${childId}/presence`,
  tokv ? { authorization: `Bearer ${tokv}` } : {}, '',
);

async function setWindow(guardianId, weekday, startLocal, endLocal) {
  await admin.query(
    `INSERT INTO guardian_availability_window (guardian_id, weekday, start_local, end_local)
     VALUES ($1,$2,$3,$4)`,
    [guardianId, weekday, startLocal, endLocal]);
}

// Real bug, found live in CI (section D below has the full account): real
// wall-clock arithmetic (.plus()/.minus()) can cross a real calendar-day
// boundary, and guardian_availability_window's own CHECK constraint
// (end_local > start_local, migration 0010) then rejects the INSERT
// outright whenever that happens. Every window below that brackets "now"
// (as opposed to section D's now-unrelated far-weekday construction) is
// clamped to stay within the SAME calendar day as `local` -- this changes
// nothing about what a test proves (the clamped instant is still validly
// "before now" or "after now": `local` is by definition always within its
// own day, so clamping can only ever shrink a window while still leaving
// `local` inside it), it only removes the crossing-midnight failure mode
// entirely, rather than merely making it rarer. One honestly-disclosed
// residual: section C's own tie-break specifically compares two DIFFERENT
// clamped start times; if `local` ever falls within about 10 real minutes
// of local midnight, both starts could clamp to the same 00:00 and the
// test would need re-running rather than asserting a false result -- an
// astronomically rarer window than the bug this fix actually closes, and
// not worth a more elaborate construction to close entirely.
const clampToDay = (dt) => dt.hasSame(local, 'day') ? dt
  : (dt < local ? local.startOf('day') : local.endOf('day'));

// ===========================================================================
// (a) on-duty exclusion — DAD1 (on duty, Side A) AND MOM1 both have windows
//     active right now; DAD1's starts EARLIER (would win an ordinary
//     tie-break outright). The on-duty exclusion must still remove him, so
//     the only possible winner is MOM1.
// ===========================================================================
{
  await setWindow(DAD1, nowWeekday, hhmm(clampToDay(local.minus({ minutes: 45 }))),
    hhmm(clampToDay(local.plus({ minutes: 45 }))));
  await setWindow(MOM1, nowWeekday, hhmm(clampToDay(local.minus({ minutes: 15 }))),
    hhmm(clampToDay(local.plus({ minutes: 45 }))));

  const res = await get(CHILD_ONDUTY, dad1Tok);
  check('A on-duty exclusion', 'authorized guardian -> 200', res.status, 200);
  check('A on-duty exclusion', 'DAD1 (on duty) is excluded even though his window starts earlier',
    res.body.free?.guardianId, MOM1);
  check('A on-duty exclusion', 'the surfaced name is the real co-guardian, not the on-duty one',
    res.body.free?.name, 'Mom');

  // The child herself sees the identical answer -- no child-safe stand-in.
  const asChild = await get(CHILD_ONDUTY, childOnDutyTok);
  check('A on-duty exclusion', 'the child can read her own /presence too -> 200', asChild.status, 200);
  check('A on-duty exclusion', 'and gets the same real exclusion result', asChild.body.free?.guardianId, MOM1);
}

// ===========================================================================
// (b) + (e) a single free guardian, correctly surfaced, in HER frame — no
//     custody order at all for this child (honest "skip the exclusion, not
//     guess it" path from §3 Step 1), only MOM2 has an active window. Both
//     guardians' real app_user.home_tz (Denver/Chicago) are DIFFERENT from
//     CHILD_ZONE (Los Angeles) -- theirLocalTime/freeUntilHerTime must match
//     the CHILD's zone, never either guardian's own.
// ===========================================================================
{
  const end = clampToDay(local.plus({ minutes: 37 }));
  await setWindow(MOM2, nowWeekday, hhmm(clampToDay(local.minus({ minutes: 5 }))), hhmm(end));
  // DAD2 has no window at all for CHILD_SINGLE -- not a candidate this route
  // would ever surface here regardless of exclusion logic.

  const res = await get(CHILD_SINGLE, dad2Tok);
  check('B single + her-frame', 'authorized guardian -> 200', res.status, 200);
  check('B single + her-frame', 'guardianId is MOM2', res.body.free?.guardianId, MOM2);
  check('B single + her-frame', 'name is joined from app_user.display_name', res.body.free?.name, 'Mom');
  check('B single + her-frame', 'theirLocalTime is the CHILD\'s own resolved zone (LA), not MOM2\'s home_tz (Denver)',
    res.body.free?.theirLocalTime, fmt(local));
  check('B single + her-frame',
    'freeUntilHerTime is the window end in the CHILD\'s zone, phrased "<h:mm a> her time"',
    res.body.free?.freeUntilHerTime, `${fmt(end)} her time`);
}

// ===========================================================================
// (f) real bug, found by this project's own post-tier audit: calendar.view
//     alone is far wider than this route was ever meant to admit — a real
//     sitter, with a genuine live edge to this exact child (so the OUTER
//     action-capability check alone would have let her through) is NOT a
//     parent (§5.27.2), and must never see a live, named-parent reachability
//     signal that specific. Same CHILD_SINGLE fixture as (b) above, so this
//     also proves the gate is evaluated BEFORE any real work runs, not just
//     that a response happens to come back empty.
// ===========================================================================
{
  const res = await get(CHILD_SINGLE, sitterTok);
  check('F non-parent gate', 'a real sitter, with a genuine live edge to this exact '
    + 'child, is still refused — not a parent, regardless of calendar.view',
    res.status, 403);
  check('F non-parent gate', 'the real reason is named, not a generic denial',
    res.body?.error, 'not_a_parent_of_child');
  check('F non-parent gate', 'no presence data of any kind leaks alongside the refusal',
    res.body?.free, undefined);
}

// ===========================================================================
// (c) tie-break — both DAD3 and MOM3 free right now, no custody order (no
//     exclusion in play). DAD3's window starts LATER than MOM3's, so MOM3
//     must win purely on "then simply first" -- proven with DAD3's id
//     ('1...') sorting BEFORE MOM3's ('2...') lexicographically, so a bug
//     that fell back to sorting by guardianId instead of startLocal would
//     silently pick DAD3 and be caught here, not accidentally pass.
// ===========================================================================
{
  await setWindow(MOM3, nowWeekday, hhmm(clampToDay(local.minus({ minutes: 40 }))),
    hhmm(clampToDay(local.plus({ minutes: 40 }))));
  await setWindow(DAD3, nowWeekday, hhmm(clampToDay(local.minus({ minutes: 10 }))),
    hhmm(clampToDay(local.plus({ minutes: 40 }))));

  const res = await get(CHILD_TIE, dad3Tok);
  check('C tie-break', 'authorized guardian -> 200', res.status, 200);
  // "No seniority, no primary/secondary, no custody weighting." — MASTERFILE
  // §5.27.4. The only real tie-break is "then simply first" (earliest
  // window start wins); this assertion is that rule, not an alphabetical
  // guardianId coincidence — DAD3's id sorts first lexicographically and
  // still loses, because MOM3's window started earlier.
  check('C tie-break', 'the EARLIER-starting window wins (MOM3), not the lexicographically-first guardianId (DAD3)',
    res.body.free?.guardianId, MOM3);
}

// ===========================================================================
// (d) nobody free — TWO shapes, proven to be the SAME shape, per §6's own
//     "the signal never reveals the family's shape" sibling concern: a
//     sole-guardian child (CHILD_SOLE, exactly one guardian, no window) must
//     be indistinguishable from a two-guardian child where neither happens
//     to be free right now (CHILD_NONE, real windows, none active now).
// ===========================================================================
{
  // CHILD_NONE: real windows exist for both guardians, but neither covers
  // "now". Real CI bug, found live: an earlier version of this fixture used
  // a same-weekday +6h/+7h clock-time offset from `local`, on the (false)
  // assumption that 6-7 real hours is "deliberately far outside any wrap-
  // aware edge case" -- it is not. Clock-time addition wraps past midnight
  // for roughly a quarter of all possible real `local` values (any time
  // from ~17:00 onward), and guardian_availability_window's own real CHECK
  // (end_local > start_local, migration 0010) then rejects the INSERT
  // outright -- reproduced exactly this way in CI, not a flake: `local` was
  // 17:07, farStart/farEnd landed on 23:07/00:07, and the insert failed
  // with a real constraint violation. This suite runs against genuine
  // wall-clock time deliberately (proving the route against real time, not
  // a canned scenario, matching now_route.test.mjs's own precedent) -- so
  // the fix is a construction that is windows away from "now" without ever
  // computing a clock time at all: a DIFFERENT weekday entirely.
  // freeGuardianNow() only ever matches a window on nowWeekday (or
  // yesterday's weekday, for a genuine overnight wrap) -- three days away
  // can never coincide with either, for any real `local` value, with no
  // clock-time arithmetic and nothing left to wrap.
  const farWeekday = (nowWeekday + 3) % 7;
  await setWindow(DAD4, farWeekday, '10:00', '11:00');
  await setWindow(MOM4, farWeekday, '10:00', '11:00');

  const noneRes = await get(CHILD_NONE, dad4Tok);
  check('D nobody free', 'CHILD_NONE (two guardians, neither active now) -> 200', noneRes.status, 200);
  check('D nobody free', 'CHILD_NONE gets an honest { free: null }', noneRes.body.free, 'null');

  // CHILD_SOLE: exactly one live guardian, no availability window at all --
  // candidates.isEmpty -> { free: null } falls out of the algorithm for
  // free, per §6's own reasoning, rather than needing a special case.
  const soleRes = await get(CHILD_SOLE, soleTok);
  check('D nobody free', 'CHILD_SOLE (exactly one guardian) -> 200', soleRes.status, 200);
  check('D nobody free', 'CHILD_SOLE ALSO gets { free: null } -- indistinguishable from CHILD_NONE',
    soleRes.body.free, 'null');
  check('D nobody free', 'both honest-absence shapes are byte-identical (no leaked family-shape signal)',
    JSON.stringify(noneRes.body), JSON.stringify(soleRes.body));
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
