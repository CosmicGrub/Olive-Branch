/**
 * packages/db — guardian_game_favorite, child_game_picker_state: real RLS,
 * and the real gameFavoritesFor()/setGameFavoriteKinds()/
 * recordGamePickerOpen() loaders. MASTERFILE §9.2,
 * docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-
 * design.md. db/migrations/0030_game_favorites.sql.
 *
 * Mirrors theme_preference.test.mjs exactly (same DATABASE_URL/
 * ADMIN_DATABASE_URL split, same check() harness): requires a real Postgres
 * with 0030 applied, and is NOT part of `npm test`'s default JS-suite chain
 * for the same reason theme_preference.test.mjs isn't — a suite that
 * measures RLS run as `postgres` measures nothing (pool.test.mjs's own
 * header / db/DEPLOYMENT.md).
 *
 * Three things this file proves that a fake-pool contract test cannot:
 *   A) gameFavoritesFor()/setGameFavoriteKinds()/recordGamePickerOpen()
 *      really round-trip through a live database — full-replace semantics
 *      on the favourites side, real server-side age computation from a
 *      real birth_date on the age-unlock side, and a never-visited child
 *      reads back a clean, honest empty list / null, never a fabricated
 *      default.
 *   B) guardian_game_favorite's RLS — the `..._no_child` shape: ANY
 *      guardian-role session can read/write ANY row (the coarse "second
 *      lock" 0026/0028's own tables already document), a child session can
 *      touch NONE of it, ever.
 *   C) child_game_picker_state's RLS — the INVERSE: the owning child reads
 *      and writes her own row, a DIFFERENT child cannot touch it, and no
 *      guardian policy exists on this table at all (mirrors letter_owner_
 *      only's own "guardian-excluded" shape, 0028) — the system role
 *      still reads it (gameFavoritesFor()'s own combined read).
 */
import pg from 'pg';
import { createPool, withSession, guardiansOfChild,
  gameFavoritesFor, setGameFavoriteKinds, recordGamePickerOpen }
  from '../src/pool.mjs';

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

// Two families, the identical shape theme_preference.test.mjs already uses:
// CHILD_A has two live co-guardians (DAD, MOM); CHILD_B has one unrelated
// guardian (STRANGER) who shares nothing with either.
const CHILD_A = '77777777-7777-7777-7777-777777777730';
const CHILD_B = '88888888-8888-8888-8888-888888888831';
const DAD = '99999999-9999-9999-9999-999999999930';
const MOM = 'aaaaaaaa-1111-1111-1111-111111111130';
const STRANGER = 'bbbbbbbb-2222-2222-2222-222222222230';

async function reset() {
  await admin.query(`DELETE FROM guardian_game_favorite WHERE guardian_id IN ($1,$2,$3)`,
    [DAD, MOM, STRANGER]);
  await admin.query(`DELETE FROM child_game_picker_state WHERE child_id IN ($1,$2)`,
    [CHILD_A, CHILD_B]);
  await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1,$2)`, [CHILD_A, CHILD_B]);
  await admin.query(`DELETE FROM child WHERE id IN ($1,$2)`, [CHILD_A, CHILD_B]);
  await admin.query(`DELETE FROM app_user WHERE id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
}

await admin.query('BEGIN');
await reset();
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/New_York'), ($3,'Stranger','America/Denver')`,
  [DAD, MOM, STRANGER]);
// CHILD_A turns 9 on the fixed local date this suite writes against below —
// birth_date chosen so `age(2026-09-12, birth_date)` is a real, checkable 9.
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2017-04-02','America/New_York'), ($2,'Eli','2018-01-01','America/Denver')`,
  [CHILD_A, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $5, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, DAD, MOM, CHILD_B, STRANGER]);
await admin.query('COMMIT');

// ===========================================================================
// A · gameFavoritesFor / setGameFavoriteKinds / recordGamePickerOpen — the
// real loaders, real round-trip, real absence, real full-replace, real
// server-side age computation.
// ===========================================================================
{
  const neverSet = await gameFavoritesFor(pool, CHILD_A);
  check('A loaders', 'a never-visited child reads back an honest empty favourites list',
    neverSet.favoriteKinds.length, 0);
  check('A loaders', '...and a clean, honest null ageAtLastOpen', neverSet.ageAtLastOpen, 'null');

  await setGameFavoriteKinds(pool, DAD, ['tictactoe', 'chess']);
  const afterDad = await gameFavoritesFor(pool, CHILD_A);
  check('A loaders', "DAD's favourites resolve for CHILD_A (guardiansOfChild() join)",
    afterDad.favoriteKinds.sort().join(','), 'chess,tictactoe');

  // A co-guardian's (MOM's) OWN favourites union with DAD's, rather than
  // replacing them — this table has no child_id at all (0030's own header:
  // "a favourite is the GUARDIAN'S OWN preference"), so DAD and MOM are
  // two independent rows-owners, not one shared row the way
  // child_theme_preference is.
  await setGameFavoriteKinds(pool, MOM, ['memory']);
  const afterMom = await gameFavoritesFor(pool, CHILD_A);
  check('A loaders', "MOM's favourites UNION with DAD's — both guardians' picks resolve for the same child",
    afterMom.favoriteKinds.sort().join(','), 'chess,memory,tictactoe');

  // Full-replace, not merge, for the SAME guardian's own second write.
  await setGameFavoriteKinds(pool, DAD, ['story']);
  const afterReplace = await gameFavoritesFor(pool, CHILD_A);
  check('A loaders', "DAD's second write fully REPLACES his own list (his earlier picks are gone)",
    afterReplace.favoriteKinds.sort().join(','), 'memory,story');
  const dadRowCount = (await admin.query(
    `SELECT count(*)::int AS n FROM guardian_game_favorite WHERE guardian_id = $1`, [DAD])).rows[0].n;
  check('A loaders', "exactly one row per kind for DAD's new list, not a leftover from the old one",
    dadRowCount, 1);

  // A different, never-touched child stays untouched by CHILD_A's guardians'
  // writes — favorites are guardian-scoped, but gameFavoritesFor()'s own
  // guardiansOfChild() join must never leak across children with unrelated
  // guardians.
  const stillUnset = await gameFavoritesFor(pool, CHILD_B);
  check('A loaders', "CHILD_B's favourites are untouched by CHILD_A's guardians' writes",
    stillUnset.favoriteKinds.length, 0);

  // recordGamePickerOpen() — real server-side age arithmetic against the
  // real birth_date, never trusted from a caller-supplied number (there is
  // no such parameter at all).
  const age = await recordGamePickerOpen(pool, CHILD_A, '2026-09-12');
  check('A loaders', "recordGamePickerOpen() computes CHILD_A's real age from her real birth_date",
    age, 9);
  const afterOpen = await gameFavoritesFor(pool, CHILD_A);
  check('A loaders', 'ageAtLastOpen round-trips through the combined read', afterOpen.ageAtLastOpen, 9);

  // Upsert — a second open overwrites, never logs a second row.
  const secondOpenAge = await recordGamePickerOpen(pool, CHILD_A, '2027-09-12');
  check('A loaders', 'a later visit overwrites with her new real age', secondOpenAge, 10);
  const stateRowCount = (await admin.query(
    `SELECT count(*)::int AS n FROM child_game_picker_state WHERE child_id = $1`, [CHILD_A])).rows[0].n;
  check('A loaders', 'exactly one row exists for CHILD_A — overwritten, never logged', stateRowCount, 1);
}

// ===========================================================================
// B · guardian_game_favorite RLS — the `..._no_child` shape: ANY guardian
// session reads/writes ANY row; a child session touches NONE of it.
// ===========================================================================
{
  const asDad = (fn) => withSession(pool, { roleName: 'guardian', userId: DAD, childId: null }, fn);
  const asStranger = (fn) => withSession(pool, { roleName: 'guardian', userId: STRANGER, childId: null }, fn);
  const asChildA = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A }, fn);

  await admin.query(
    `INSERT INTO guardian_game_favorite (guardian_id, kind) VALUES ($1, 'dotsboxes')
     ON CONFLICT (guardian_id, kind) DO NOTHING`, [STRANGER]);

  // ---- ANY guardian reads/writes ANY row — the coarse "second lock" ------
  const dadReadsStrangers = await asDad(q =>
    q(`SELECT kind FROM guardian_game_favorite WHERE guardian_id = $1`, [STRANGER]));
  check('B RLS', "DAD (a live guardian session, unrelated to STRANGER) can still READ STRANGER's row — "
    + 'the coarse `..._no_child` shape, fine-grained scoping is the route\'s own job',
    dadReadsStrangers[0]?.kind, 'dotsboxes');
  const strangerDeletesOwn = await asStranger(q =>
    q(`DELETE FROM guardian_game_favorite WHERE guardian_id = $1 RETURNING kind`, [STRANGER]));
  check('B RLS', 'STRANGER can delete his own row', strangerDeletesOwn[0]?.kind, 'dotsboxes');

  // ---- the NEGATIVE case: a child session touches NONE of this table -----
  const childReads = await asChildA(q =>
    q(`SELECT kind FROM guardian_game_favorite WHERE guardian_id = $1`, [DAD]));
  check('B RLS', 'a child session reads ZERO rows from guardian_game_favorite, even a real one', childReads.length, 0);
  let childInsertThrew = false;
  try {
    await asChildA(q => q(
      `INSERT INTO guardian_game_favorite (guardian_id, kind) VALUES ($1, 'chess')`, [DAD]));
  } catch { childInsertThrew = true; }
  check('B RLS', 'a child session can never INSERT into guardian_game_favorite at all', childInsertThrew, 'true');
}

// ===========================================================================
// C · child_game_picker_state RLS — the INVERSE: the owning child reads and
// writes her own row; a different child cannot; no guardian policy exists
// at all; the system role still reads it (gameFavoritesFor()'s own job).
// ===========================================================================
{
  const asChildA = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A }, fn);
  const asChildB = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_B }, fn);
  const asDad = (fn) => withSession(pool, { roleName: 'guardian', userId: DAD, childId: null }, fn);

  const childAReadsOwn = await asChildA(q =>
    q(`SELECT age_at_last_open FROM child_game_picker_state WHERE child_id = $1`, [CHILD_A]));
  check('C RLS', 'CHILD_A reads her own row', childAReadsOwn[0]?.age_at_last_open, 10);

  const childBReadsA = await asChildB(q =>
    q(`SELECT age_at_last_open FROM child_game_picker_state WHERE child_id = $1`, [CHILD_A]));
  check('C RLS', "CHILD_B (a different child) reads ZERO of CHILD_A's row", childBReadsA.length, 0);

  const childAUpdatesOwn = await asChildA(q => q(
    `UPDATE child_game_picker_state SET age_at_last_open = 11 WHERE child_id = $1 RETURNING age_at_last_open`,
    [CHILD_A]));
  check('C RLS', 'CHILD_A can update her own row', childAUpdatesOwn[0]?.age_at_last_open, 11);

  const childBUpdateAttempt = await asChildB(q => q(
    `UPDATE child_game_picker_state SET age_at_last_open = 5 WHERE child_id = $1 RETURNING child_id`,
    [CHILD_A]));
  check('C RLS', "CHILD_B's attempted UPDATE of CHILD_A's row affects ZERO rows", childBUpdateAttempt.length, 0);

  // ---- no guardian policy exists on this table at all — guardian-excluded,
  // the literal inverse of guardian_game_favorite above (mirrors
  // letter_owner_only's own "guardian-excluded" shape, 0028). ---------------
  const dadReads = await asDad(q =>
    q(`SELECT age_at_last_open FROM child_game_picker_state WHERE child_id = $1`, [CHILD_A]));
  check('C RLS', 'a guardian session (DAD, a REAL live edge to CHILD_A) still reads ZERO rows here — '
    + 'this table is child-owned, guardian-excluded, no exception for a live edge',
    dadReads.length, 0);
  let dadUpdateThrew = false;
  let dadUpdateAffected = -1;
  try {
    const r = await asDad(q => q(
      `UPDATE child_game_picker_state SET age_at_last_open = 99 WHERE child_id = $1 RETURNING child_id`,
      [CHILD_A]));
    dadUpdateAffected = r.length;
  } catch { dadUpdateThrew = true; }
  check('C RLS', "a guardian's UPDATE either throws or affects zero rows — never actually changes it",
    dadUpdateThrew || dadUpdateAffected === 0, 'true');
  const stillEleven = await admin.query(
    `SELECT age_at_last_open FROM child_game_picker_state WHERE child_id = $1`, [CHILD_A]);
  check('C RLS', "CHILD_A's row is provably untouched by DAD's attempted UPDATE",
    stillEleven.rows[0]?.age_at_last_open, 11);

  // ---- system role reads it — gameFavoritesFor()'s own combined read -----
  const asSystem = (fn) => withSession(pool, { roleName: 'system', userId: null, childId: null }, fn);
  const systemReads = await asSystem(q =>
    q(`SELECT age_at_last_open FROM child_game_picker_state WHERE child_id = $1`, [CHILD_A]));
  check('C RLS', "the system role (gameFavoritesFor()'s own session) reads the real row",
    systemReads[0]?.age_at_last_open, 11);
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
