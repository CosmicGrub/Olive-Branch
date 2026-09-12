/**
 * packages/db — child_profile: real RLS, and the real setChildGender()
 * writer. Onboarding & Guardian Access sub-project 1 (docs/superpowers/
 * specs/2026-09-12-onboarding-identity-pin-design.md).
 * db/migrations/0031_child_profile.sql.
 *
 * Mirrors theme_preference.test.mjs/game_favorites.test.mjs exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres with 0031 applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason those two aren't — a suite that
 * measures RLS run as `postgres` measures nothing (pool.test.mjs's own
 * header / db/DEPLOYMENT.md).
 *
 * Three things this file proves that a fake-pool contract test cannot:
 *   A) setChildGender() really round-trips through a live database — a
 *      never-set child reads back a clean, honest absence (no row at all,
 *      never a fabricated NULL-gender row), a real write upserts once, and
 *      a later, DIFFERENT real answer replaces the first rather than
 *      accumulating a second row.
 *   B) child_profile's RLS — the owning child reads and writes her own row,
 *      a DIFFERENT child cannot touch it, and NO guardian policy exists on
 *      this table at all (mirrors child_game_picker_state_owner_only's own
 *      "guardian-excluded" shape, 0030).
 *   C) UNLIKE child_game_picker_state, this table carries NO system-role
 *      read policy either — nothing in this pass ever reads it back, so the
 *      system role gets zero rows too, proving that absence is real and not
 *      merely undocumented.
 */
import pg from 'pg';
import { createPool, withSession, setChildGender } from '../src/pool.mjs';

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

// Two children, the identical shape game_favorites.test.mjs already uses:
// CHILD_A is the one this suite writes against; CHILD_B exists only to
// prove no cross-child leak.
const CHILD_A = 'cccccccc-7777-7777-7777-777777777740';
const CHILD_B = 'dddddddd-8888-8888-8888-888888888841';
const DAD = 'eeeeeeee-9999-9999-9999-999999999940';

async function reset() {
  await admin.query(`DELETE FROM child_profile WHERE child_id IN ($1,$2)`, [CHILD_A, CHILD_B]);
  await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1,$2)`, [CHILD_A, CHILD_B]);
  await admin.query(`DELETE FROM child WHERE id IN ($1,$2)`, [CHILD_A, CHILD_B]);
  await admin.query(`DELETE FROM app_user WHERE id IN ($1)`, [DAD]);
}

await admin.query('BEGIN');
await reset();
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`,
  [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2017-04-02','America/New_York'), ($2,'Eli','2018-01-01','America/Denver')`,
  [CHILD_A, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, DAD]);
await admin.query('COMMIT');

// ===========================================================================
// A · setChildGender() — the real loader, real round-trip, real absence,
// real replace-not-accumulate.
// ===========================================================================
{
  const neverSet = await admin.query(
    `SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]);
  check('A loader', 'a never-visited child has NO ROW at all — a clean, honest '
    + 'absence, never a fabricated NULL-gender row', neverSet.rows.length, 0);

  await setChildGender(pool, CHILD_A, 'girl');
  const afterFirst = await admin.query(
    `SELECT gender, set_at FROM child_profile WHERE child_id = $1`, [CHILD_A]);
  check('A loader', 'a real write really persists', afterFirst.rows[0]?.gender, 'girl');
  check('A loader', 'set_at is really written, not left null',
    afterFirst.rows[0]?.set_at != null, 'true');

  // A later, DIFFERENT real answer replaces the first — upsert, never a
  // second row (the migration's own "overwritten, never a log" shape).
  await setChildGender(pool, CHILD_A, 'boy');
  const afterSecond = await admin.query(
    `SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]);
  check('A loader', 'a second, different write REPLACES the first',
    afterSecond.rows[0]?.gender, 'boy');
  const rowCount = (await admin.query(
    `SELECT count(*)::int AS n FROM child_profile WHERE child_id = $1`, [CHILD_A])).rows[0].n;
  check('A loader', 'exactly one row exists for CHILD_A — overwritten, never logged', rowCount, 1);

  // A different, never-touched child stays untouched by CHILD_A's own write.
  const stillUnset = await admin.query(
    `SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_B]);
  check('A loader', "CHILD_B's row is untouched by CHILD_A's write", stillUnset.rows.length, 0);
}

// ===========================================================================
// B · child_profile RLS — the owning child reads/writes her own row; a
// different child cannot; NO guardian policy exists at all (mirrors
// child_game_picker_state_owner_only's own "guardian-excluded" shape, 0030).
// ===========================================================================
{
  const asChildA = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A }, fn);
  const asChildB = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_B }, fn);
  const asDad = (fn) => withSession(pool, { roleName: 'guardian', userId: DAD, childId: null }, fn);

  const childAReadsOwn = await asChildA(q =>
    q(`SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', 'CHILD_A reads her own row', childAReadsOwn[0]?.gender, 'boy');

  const childBReadsA = await asChildB(q =>
    q(`SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', "CHILD_B (a different child) reads ZERO of CHILD_A's row", childBReadsA.length, 0);

  const childAUpdatesOwn = await asChildA(q => q(
    `UPDATE child_profile SET gender = 'girl' WHERE child_id = $1 RETURNING gender`,
    [CHILD_A]));
  check('B RLS', 'CHILD_A can update her own row directly', childAUpdatesOwn[0]?.gender, 'girl');

  const childBUpdateAttempt = await asChildB(q => q(
    `UPDATE child_profile SET gender = 'boy' WHERE child_id = $1 RETURNING child_id`,
    [CHILD_A]));
  check('B RLS', "CHILD_B's attempted UPDATE of CHILD_A's row affects ZERO rows",
    childBUpdateAttempt.length, 0);

  let childBInsertThrew = false;
  try {
    await asChildB(q => q(
      `INSERT INTO child_profile (child_id, gender, set_at) VALUES ($1, 'boy', now())`,
      [CHILD_A]));
  } catch { childBInsertThrew = true; }
  check('B RLS', 'CHILD_B can never INSERT a row scoped to CHILD_A at all', childBInsertThrew, 'true');

  // A NULL/CHECK-constraint gender is never coerced — a skip never reaches
  // this table at all, so proving the CHECK constraint itself still rejects
  // anything else confirms setChildGender()'s own caller (routes.mjs) is not
  // the only thing standing between a bad value and this table.
  let badGenderThrew = false;
  try {
    await asChildA(q => q(
      `INSERT INTO child_profile (child_id, gender, set_at) VALUES ($1, 'other', now())
       ON CONFLICT (child_id) DO UPDATE SET gender = EXCLUDED.gender`,
      [CHILD_A]));
  } catch { badGenderThrew = true; }
  check('B RLS', 'a gender outside boy/girl is rejected by the real CHECK constraint, '
    + 'not just by the route', badGenderThrew, 'true');

  // ---- no guardian policy exists on this table at all — guardian-excluded,
  // mirroring child_game_picker_state_owner_only's own shape (0030). --------
  const dadReads = await asDad(q =>
    q(`SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', 'a guardian session (DAD, a REAL live edge to CHILD_A) still reads ZERO '
    + 'rows here — this table is child-owned, guardian-excluded, no exception for a live edge',
    dadReads.length, 0);
  let dadUpdateThrew = false;
  let dadUpdateAffected = -1;
  try {
    const r = await asDad(q => q(
      `UPDATE child_profile SET gender = 'boy' WHERE child_id = $1 RETURNING child_id`,
      [CHILD_A]));
    dadUpdateAffected = r.length;
  } catch { dadUpdateThrew = true; }
  check('B RLS', "a guardian's UPDATE either throws or affects zero rows — never actually changes it",
    dadUpdateThrew || dadUpdateAffected === 0, 'true');
  const stillGirl = await admin.query(
    `SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]);
  check('B RLS', "CHILD_A's row is provably untouched by DAD's attempted UPDATE",
    stillGirl.rows[0]?.gender, 'girl');
}

// ===========================================================================
// C · UNLIKE child_game_picker_state (0030), this table has NO system-role
// read policy either — nothing in this pass reads it back, so the trusted
// backend role gets zero rows too, proving that absence is real.
// ===========================================================================
{
  const asSystem = (fn) => withSession(pool, { roleName: 'system', userId: null, childId: null }, fn);
  const systemReads = await asSystem(q =>
    q(`SELECT gender FROM child_profile WHERE child_id = $1`, [CHILD_A]));
  check('C RLS', 'the system role reads ZERO rows here — no system-role policy exists on '
    + 'this table at all, unlike child_game_picker_state', systemReads.length, 0);
}

await admin.query('BEGIN');
await reset();
await admin.query('COMMIT');
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
