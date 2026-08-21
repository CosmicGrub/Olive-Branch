/**
 * packages/db — child_theme_preference: real RLS, and the real
 * themeFor()/setChildTheme() loaders. MASTERFILE §8.1,
 * docs/superpowers/specs/2026-08-21-intuitivism-visual-foundation-design.md.
 * db/migrations/0017_child_theme_preference.sql.
 *
 * Mirrors availability.test.mjs / pool.test.mjs exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres with 0017 applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason those two aren't — a suite that
 * measures RLS run as `postgres` measures nothing (see pool.test.mjs's own
 * header / db/DEPLOYMENT.md).
 *
 * Two things this file proves that a fake-pool contract test cannot:
 *   A) themeFor()/setChildTheme() really round-trip through a live
 *      database — upsert-replace semantics included, and a never-set child
 *      reads back as a clean, honest `null`, never a fabricated default row.
 *   B) child_theme_preference's RLS — ANY guardian with a live edge to the
 *      child can read AND write (unlike guardian_availability_window's own
 *      per-guardian-owns-her-row shape, this table is per-CHILD, so DAD and
 *      MOM must both reach the same row); the child herself can read her
 *      own row but never write it; a guardian/child with NO live edge to
 *      that child reads and writes NOTHING — the exact negative case the
 *      task asked for.
 */
import pg from 'pg';
import { createPool, withSession, themeFor, setChildTheme }
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

// Two families: CHILD_A has two live co-guardians (DAD, MOM). CHILD_B has one
// unrelated guardian (STRANGER) who shares nothing with either.
const CHILD_A = '77777777-7777-7777-7777-777777777701';
const CHILD_B = '88888888-8888-8888-8888-888888888802';
const DAD = '99999999-9999-9999-9999-999999999901';
const MOM = 'aaaaaaaa-1111-1111-1111-111111111102';
const STRANGER = 'bbbbbbbb-2222-2222-2222-222222222203';

async function reset() {
  await admin.query(`DELETE FROM child_theme_preference WHERE child_id IN ($1,$2)`,
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
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'), ($2,'Eli','2018-01-01','America/Denver')`,
  [CHILD_A, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $5, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, DAD, MOM, CHILD_B, STRANGER]);
await admin.query('COMMIT');

// ===========================================================================
// A · themeFor / setChildTheme — the real loaders, real round-trip, real
// absence, real upsert-replace.
// ===========================================================================
{
  const neverSet = await themeFor(pool, CHILD_A);
  check('A loaders', 'a child with no row set reads back a clean, honest null',
    neverSet, 'null');

  await setChildTheme(pool, DAD, CHILD_A, { themePalette: 'warmGrounded', themeBrightness: 'dark' });
  const afterFirstSet = await themeFor(pool, CHILD_A);
  check('A loaders', 'themePalette round-trips', afterFirstSet?.themePalette, 'warmGrounded');
  check('A loaders', 'themeBrightness round-trips', afterFirstSet?.themeBrightness, 'dark');

  // Upsert-replace: a co-guardian (MOM) sets a DIFFERENT value for the SAME
  // child — must overwrite the one row, never create a second one.
  await setChildTheme(pool, MOM, CHILD_A, { themePalette: 'brightBold', themeBrightness: 'light' });
  const afterReplace = await themeFor(pool, CHILD_A);
  check('A loaders', "MOM's later Apply replaces DAD's earlier one, same row",
    `${afterReplace?.themePalette}/${afterReplace?.themeBrightness}`, 'brightBold/light');
  const rowCount = (await admin.query(
    `SELECT count(*)::int AS n FROM child_theme_preference WHERE child_id = $1`, [CHILD_A])).rows[0].n;
  check('A loaders', 'exactly one row exists for CHILD_A, not two', rowCount, 1);

  // A different, never-touched child stays null — setChildTheme for one
  // child must never leak into another's row.
  const stillUnset = await themeFor(pool, CHILD_B);
  check('A loaders', "CHILD_B's theme is untouched by CHILD_A's writes", stillUnset, 'null');
}

// ===========================================================================
// B · RLS — the task's own requirement: ANY guardian with a live edge to the
// child can read AND write; the child reads her own row but cannot write;
// nobody with no live edge can do either.
// ===========================================================================
{
  const asDad = (fn) => withSession(pool, { roleName: 'guardian', userId: DAD, childId: null }, fn);
  const asMom = (fn) => withSession(pool, { roleName: 'guardian', userId: MOM, childId: null }, fn);
  const asStranger = (fn) => withSession(pool, { roleName: 'guardian', userId: STRANGER, childId: null }, fn);
  const asChildA = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A }, fn);
  const asChildB = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_B }, fn);

  // Seed a known row directly (bypassing the app-layer functions above) so
  // this section tests RLS in isolation.
  await admin.query(
    `INSERT INTO child_theme_preference (child_id, theme_palette, theme_brightness)
     VALUES ($1, 'deepCozy', 'dark')
     ON CONFLICT (child_id) DO UPDATE SET theme_palette = 'deepCozy', theme_brightness = 'dark'`,
    [CHILD_A]);

  // ---- both co-guardians READ the SAME row -------------------------------
  const dadReads = await asDad(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', 'DAD (live edge) reads CHILD_A\'s row', dadReads[0]?.theme_palette, 'deepCozy');
  const momReads = await asMom(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', 'MOM (live edge, same child) ALSO reads the SAME row', momReads[0]?.theme_palette, 'deepCozy');

  // ---- both co-guardians WRITE the SAME row ------------------------------
  const dadWrite = await asDad(q => q(
    `UPDATE child_theme_preference SET theme_palette = 'softPlayful' WHERE child_id = $1 RETURNING theme_palette`,
    [CHILD_A]));
  check('B RLS', "DAD's UPDATE succeeds — a live edge, not row ownership, gates this table",
    dadWrite[0]?.theme_palette, 'softPlayful');
  const momWrite = await asMom(q => q(
    `UPDATE child_theme_preference SET theme_palette = 'calmModern' WHERE child_id = $1 RETURNING theme_palette`,
    [CHILD_A]));
  check('B RLS', "MOM's UPDATE ALSO succeeds on the SAME row DAD just wrote — symmetric",
    momWrite[0]?.theme_palette, 'calmModern');

  // ---- the NEGATIVE case the task specifically asked for: no live edge
  // reads and writes NOTHING. -----------------------------------------------
  const strangerReads = await asStranger(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', 'STRANGER (no edge to CHILD_A) reads ZERO rows', strangerReads.length, 0);
  const strangerWrite = await asStranger(q => q(
    `UPDATE child_theme_preference SET theme_palette = 'classic' WHERE child_id = $1 RETURNING id`, [CHILD_A]));
  check('B RLS', "STRANGER's UPDATE affects ZERO rows (no error — just invisible)", strangerWrite.length, 0);
  const stillCalmModern = await asDad(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', "CHILD_A's row is provably untouched by STRANGER's attempted UPDATE",
    stillCalmModern[0]?.theme_palette, 'calmModern');

  // ---- WITH CHECK on a clean INSERT (no pre-existing row for CHILD_B yet,
  // so this is a pure test of the INSERT-time check, not a PK conflict):
  // DAD has no edge to CHILD_B at all -- mirrors availability.test.mjs's own
  // "impersonating" INSERT-denial test. Deliberately BEFORE the STRANGER
  // insert below, which is what first gives CHILD_B a row.
  let dadInsertForUnrelatedChildThrew = false;
  try {
    await asDad(q => q(
      `INSERT INTO child_theme_preference (child_id, theme_palette, theme_brightness)
       VALUES ($1, 'classic', 'dark')`, [CHILD_B]));
  } catch { dadInsertForUnrelatedChildThrew = true; }
  check('B RLS', "DAD's INSERT for CHILD_B (a child he has NO edge to) is REJECTED by WITH CHECK",
    dadInsertForUnrelatedChildThrew, 'true');
  const childBStillEmpty = await admin.query(
    `SELECT count(*)::int AS n FROM child_theme_preference WHERE child_id = $1`, [CHILD_B]);
  check('B RLS', "...and CHILD_B genuinely has no row afterward — the rejected INSERT left nothing behind",
    childBStillEmpty.rows[0].n, 0);

  let strangerInsertThrew = false;
  try {
    await asStranger(q => q(
      `INSERT INTO child_theme_preference (child_id, theme_palette, theme_brightness)
       VALUES ($1, 'brightBold', 'light')`, [CHILD_B]));
  } catch { strangerInsertThrew = true; }
  check('B RLS', "STRANGER's INSERT for CHILD_B (a child he genuinely guards) is allowed by the same policy",
    strangerInsertThrew, 'false');
  const strangerOwnChildRow = await asStranger(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_B]));
  check('B RLS', "...and STRANGER genuinely reads it back — proving the earlier denials were edge-scoped, not a blanket role ban",
    strangerOwnChildRow[0]?.theme_palette, 'brightBold');

  // ---- the child reads her OWN row, never someone else's -----------------
  const childAReads = await asChildA(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', 'CHILD_A reads her own row', childAReads[0]?.theme_palette, 'calmModern');
  const childBReadsA = await asChildB(q => q(`SELECT theme_palette FROM child_theme_preference WHERE child_id = $1`, [CHILD_A]));
  check('B RLS', "CHILD_B (a different child) reads ZERO of CHILD_A's row", childBReadsA.length, 0);

  // ---- the child can NEVER write, even her own row — guardian-only by
  // design (the spec's own "resolved, confirmed directly" line). -----------
  const childUpdateAttempt = await asChildA(q => q(
    `UPDATE child_theme_preference SET theme_palette = 'brightBold' WHERE child_id = $1 RETURNING id`, [CHILD_A]));
  check('B RLS', "CHILD_A's own UPDATE of her own row affects ZERO rows — guardian-only", childUpdateAttempt.length, 0);
  let childInsertThrew = false;
  try {
    await asChildB(q => q(
      `INSERT INTO child_theme_preference (child_id, theme_palette, theme_brightness)
       VALUES ($1, 'classic', 'light')`, [CHILD_B]));
  } catch { childInsertThrew = true; }
  check('B RLS', 'a child session can never INSERT into this table at all', childInsertThrew, 'true');
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
