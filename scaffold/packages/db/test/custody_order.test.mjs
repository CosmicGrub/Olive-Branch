/**
 * packages/db — custody_order: real RLS, and the real end-to-end loader.
 * MASTERFILE §5.4, §9.4, §4.1, §8.2.5. db/migrations/0007_custody_order.sql.
 *
 * Mirrors pool.test.mjs's own pattern exactly (same DATABASE_URL/
 * ADMIN_DATABASE_URL split, same check() harness): requires a real Postgres
 * with the 0007 migration applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason pool.test.mjs isn't — a suite that
 * measures RLS run as `postgres` measures nothing (see pool.test.mjs's own
 * header), so DATABASE_URL here MUST be a NOSUPERUSER NOBYPASSRLS role
 * (db/DEPLOYMENT.md's app_owner).
 *
 * Two things this file proves that no earlier suite could:
 *   A) custody_order's RLS — a child reads her OWN order and nothing else,
 *      exactly the guarantee the task asked to be tested.
 *   B) activeCustodyOrderFor() (packages/db/src/pool.mjs) really round-trips
 *      a DB row into the exact `Order` shape schedule.mjs's real,
 *      independently-unit-tested sleepsUntilSideChange() consumes — the
 *      other half of the gap the audit found (a tested pure function nothing
 *      in the server ever called).
 */
import pg from 'pg';
import { createPool, withSession, activeCustodyOrderFor } from '../src/pool.mjs';
import { sleepsUntilSideChange } from '../../custody/src/schedule.mjs';

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

// Seed a minimal real family: a child WITH an order (IVY, the same fixture
// shape custody.test.mjs's own unit tests use, so the expected sleeps/side/
// date below are the exact values that suite already independently proves),
// a second child with NO order at all (honest-absence case), and a guardian
// with a live edge to IVY.
const IVY = '44444444-4444-4444-4444-444444444444';
const NOORDER = '55555555-5555-5555-5555-555555555555';
const DAD = '66666666-6666-6666-6666-666666666666';

await admin.query('BEGIN');
await admin.query(`DELETE FROM custody_order WHERE child_id IN ($1, $2)`, [IVY, NOORDER]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, NOORDER]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, NOORDER]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'NoOrder','2018-01-01','America/New_York')`, [IVY, NOORDER]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{"calendar.view":true}', tstzrange(now() - interval '1 year', null))`,
  [IVY, DAD]);
// Exactly custody.test.mjs's own order() fixture: pattern 2-2-3, anchored
// 2026-01-05 (a Monday), 6:00 PM America/New_York exchanges, open-ended.
await admin.query(
  `INSERT INTO custody_order
     (child_id, order_tz, pattern, anchor_local_date, exchange_time,
      holiday_rules, effective_from, effective_to)
   VALUES ($1, 'America/New_York', '2-2-3', '2026-01-05', '18:00',
           '[]', '2020-01-01', null)`, [IVY]);
await admin.query('COMMIT');

// A · RLS — the task's own requirement: a child reads her OWN order only.
{
  const ownRows = await withSession(pool, { roleName: 'child', userId: null, childId: IVY },
    async (q) => q(`SELECT pattern FROM custody_order WHERE child_id = $1`, [IVY]));
  check('A RLS', 'the owning child CAN read her own custody order', ownRows.length, 1);

  // DAD's id is not a real child id, but exercises "a session scoped to some
  // OTHER child_id" — the policy compares against current_child(), so this
  // must be 0 regardless of whether the id exists. Same technique
  // pool.test.mjs already uses for child_journal_entry.
  const otherChildRows = await withSession(pool, { roleName: 'child', userId: null, childId: DAD },
    async (q) => q(`SELECT pattern FROM custody_order WHERE child_id = $1`, [IVY]));
  check('A RLS', 'a different child_id context reads zero rows of IVY\'s order',
    otherChildRows.length, 0);

  const noOrderRows = await withSession(pool, { roleName: 'child', userId: null, childId: IVY },
    async (q) => q(`SELECT pattern FROM custody_order WHERE child_id = $1`, [NOORDER]));
  check('A RLS', 'IVY\'s own session still reads zero rows for a DIFFERENT real child',
    noOrderRows.length, 0);

  // Unlike P6/P7's expense/journal tables, custody_order is not child-blocked
  // outright — a guardian with a live edge to IVY can read it too (§9.4's
  // guardian calendar view, exchanges/holiday rotation in order-time).
  const guardianRows = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(`SELECT pattern FROM custody_order WHERE child_id = $1`, [IVY]));
  check('A RLS', 'a guardian is NOT blocked from custody_order (unlike P6/P7 tables)',
    guardianRows.length, 1);
}

// B · activeCustodyOrderFor — the real loader, real row shape, feeding the
// real pure function. This is the other half of the gap the audit found.
{
  const order = await activeCustodyOrderFor(pool, IVY, '2026-01-05');
  check('B loader', 'order is found for a date inside its effective window',
    order !== null, 'true');
  check('B loader', 'pattern round-trips', order?.pattern, '2-2-3');
  check('B loader', 'orderTz round-trips', order?.orderTz, 'America/New_York');
  check('B loader', 'anchorLocalDate round-trips as YYYY-MM-DD', order?.anchorLocalDate, '2026-01-05');
  check('B loader', 'exchangeTime round-trips as HH:mm (not HH:mm:ss)', order?.exchangeTime, '18:00');
  check('B loader', 'holidays defaults to an empty array, not null', Array.isArray(order?.holidays), 'true');
  check('B loader', 'effectiveFrom round-trips', order?.effectiveFrom, '2020-01-01');
  check('B loader', 'effectiveTo is null (open-ended), not a fabricated date', order?.effectiveTo, 'null');

  // Fed straight into the SAME pure function custody.test.mjs unit-tests —
  // identical fixture, so this must match that suite's own known-good values.
  const change = sleepsUntilSideChange(order, '2026-01-05');
  check('B loader', 'sleepsUntilSideChange computes a real answer from the loaded row',
    change.sleeps, 2);
  check('B loader', 'and the next side', change.nextSide, 'B');
  check('B loader', 'and the date it changes on', change.onLocalDate, '2026-01-07');

  // Honest absence: a real child with no custody_order at all.
  const missing = await activeCustodyOrderFor(pool, NOORDER, '2026-01-05');
  check('B loader', 'a child with no custody order gets null, never a guess', missing, 'null');
}

await admin.query(`DELETE FROM custody_order WHERE child_id IN ($1, $2)`, [IVY, NOORDER]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, NOORDER]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, NOORDER]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
