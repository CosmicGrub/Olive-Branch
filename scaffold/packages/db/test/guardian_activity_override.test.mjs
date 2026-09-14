/**
 * packages/db — guardian_activity_override: real RLS, and the real
 * activityOverridesFor()/setActivityOverride()/deleteActivityOverride()
 * loaders. docs/superpowers/specs/2026-09-13-parental-controls-pacing-
 * design.md. db/migrations/0033_guardian_activity_override.sql.
 *
 * Mirrors theme_preference.test.mjs exactly (same DATABASE_URL/
 * ADMIN_DATABASE_URL split, same check() harness): requires a real Postgres
 * with 0033 applied, and is NOT part of `npm test`'s default JS-suite chain
 * for the same reason theme_preference.test.mjs isn't — a suite that
 * measures RLS run as `postgres` measures nothing (db/DEPLOYMENT.md).
 *
 * The one deliberate divergence from theme_preference.test.mjs's own proof:
 * this table has NO system-role read policy at all (0033's own migration
 * header explains why), so activityOverridesFor() is exercised here as BOTH
 * a guardian AND a child principal — proving RLS really is the only lock
 * on the read path, not merely a comment claiming it is.
 */
import pg from 'pg';
import { createPool, withSession, activityOverridesFor, setActivityOverride, deleteActivityOverride }
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
const CHILD_A = 'cccccccc-cccc-cccc-cccc-cccccccccc01';
const CHILD_B = 'cccccccc-cccc-cccc-cccc-cccccccccc02';
const DAD = 'dddddddd-dddd-dddd-dddd-dddddddddd01';
const MOM = 'dddddddd-dddd-dddd-dddd-dddddddddd02';
const STRANGER = 'dddddddd-dddd-dddd-dddd-dddddddddd03';

async function reset() {
  await admin.query(`DELETE FROM guardian_activity_override WHERE child_id IN ($1,$2)`,
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

const dadPrincipal = { roleName: 'guardian', userId: DAD, childId: null };
const momPrincipal = { roleName: 'guardian', userId: MOM, childId: null };
const strangerPrincipal = { roleName: 'guardian', userId: STRANGER, childId: null };
const childAPrincipal = { roleName: 'child', userId: null, childId: CHILD_A };
const childBPrincipal = { roleName: 'child', userId: null, childId: CHILD_B };

// ===========================================================================
// A · activityOverridesFor / setActivityOverride / deleteActivityOverride —
// the real loaders, real partial-upsert, real absence, real precedence-
// relevant round-trips (visible, minAgeOverride, reveal/unreveal).
// ===========================================================================
{
  const neverSet = await activityOverridesFor(pool, dadPrincipal, CHILD_A);
  check('A loaders', 'a child with no rows at all reads back a clean, honest empty list',
    neverSet.length, 0);

  await setActivityOverride(pool, DAD, CHILD_A, 'tile:storyteller', { visible: false });
  const afterHideTile = await activityOverridesFor(pool, dadPrincipal, CHILD_A);
  check('A loaders', 'exactly one row exists after one write', afterHideTile.length, 1);
  check('A loaders', 'activityKey round-trips', afterHideTile[0].activityKey, 'tile:storyteller');
  check('A loaders', 'visible round-trips', afterHideTile[0].visible, 'false');
  check('A loaders', 'minAgeOverride stays null (never mentioned)', afterHideTile[0].minAgeOverride, 'null');
  check('A loaders', 'setBy records the real writer', afterHideTile[0].setBy, DAD);

  // Partial upsert: MOM (a co-guardian) sets minAgeOverride on a DIFFERENT
  // key, then later DAD adds a reveal to the SAME key without disturbing
  // minAgeOverride — proving column-level partial writes, not a full
  // replace, and that ANY live co-guardian can write the SAME child's rows
  // (child_theme_preference's own "any live guardian, not row ownership"
  // shape, reused here per 0033's own header).
  await setActivityOverride(pool, MOM, CHILD_A, 'game:wordsearch', { minAgeOverride: 6 });
  const afterPace = await activityOverridesFor(pool, momPrincipal, CHILD_A);
  const wordsearchRow = afterPace.find((o) => o.activityKey === 'game:wordsearch');
  check('A loaders', "MOM's minAgeOverride round-trips", wordsearchRow?.minAgeOverride, 6);
  check('A loaders', 'MOM is recorded as setBy for HER OWN write', wordsearchRow?.setBy, MOM);

  await setActivityOverride(pool, DAD, CHILD_A, 'game:wordsearch', { reveal: true });
  const afterReveal = await activityOverridesFor(pool, dadPrincipal, CHILD_A);
  const wordsearchRow2 = afterReveal.find((o) => o.activityKey === 'game:wordsearch');
  check('A loaders', "DAD's later reveal does not clobber MOM's earlier minAgeOverride",
    wordsearchRow2?.minAgeOverride, 6);
  check('A loaders', 'revealedAt is now set', wordsearchRow2?.revealedAt !== null, 'true');
  check('A loaders', 'setBy now reflects the MOST RECENT writer (DAD)', wordsearchRow2?.setBy, DAD);

  await setActivityOverride(pool, DAD, CHILD_A, 'game:wordsearch', { unreveal: true });
  const afterUnreveal = await activityOverridesFor(pool, dadPrincipal, CHILD_A);
  const wordsearchRow3 = afterUnreveal.find((o) => o.activityKey === 'game:wordsearch');
  check('A loaders', 'unreveal clears revealedAt back to null', wordsearchRow3?.revealedAt, 'null');
  check('A loaders', 'minAgeOverride still survives an unreveal-only write', wordsearchRow3?.minAgeOverride, 6);

  // A different, never-touched child stays empty — writes for one child must
  // never leak into another's rows.
  const stillEmptyB = await activityOverridesFor(pool, dadPrincipal, CHILD_B);
  check('A loaders', "CHILD_B's overrides are untouched by CHILD_A's writes", stillEmptyB.length, 0);

  // Delete clears the row entirely — back to catalogue default in every column.
  await deleteActivityOverride(pool, DAD, CHILD_A, 'tile:storyteller');
  const afterDelete = await activityOverridesFor(pool, dadPrincipal, CHILD_A);
  check('A loaders', 'DELETE really removes the row, not just clears visible',
    afterDelete.some((o) => o.activityKey === 'tile:storyteller'), 'false');
  check('A loaders', "the OTHER key's row is untouched by an unrelated DELETE",
    afterDelete.some((o) => o.activityKey === 'game:wordsearch'), 'true');
}

// ===========================================================================
// B · RLS — guardian read/write via a live edge, child read-ONLY her own
// row, no cross-child leakage, and (the real, disclosed divergence from
// child_theme_preference) NO system-role backstop at all: this table has no
// system-role read policy, so a stranger session gets ZERO rows back with
// no error, exactly the "RLS alone decides" design.
// ===========================================================================
{
  const asDad = (fn) => withSession(pool, dadPrincipal, fn);
  const asMom = (fn) => withSession(pool, momPrincipal, fn);
  const asStranger = (fn) => withSession(pool, strangerPrincipal, fn);
  const asChildA = (fn) => withSession(pool, childAPrincipal, fn);
  const asChildB = (fn) => withSession(pool, childBPrincipal, fn);

  // Seed a known row directly (bypassing the app-layer functions) so this
  // section tests RLS in isolation.
  await admin.query(
    `INSERT INTO guardian_activity_override (child_id, activity_key, visible, set_by)
     VALUES ($1, 'game:chess', false, $2)
     ON CONFLICT (child_id, activity_key) DO UPDATE SET visible = false`,
    [CHILD_A, DAD]);

  // ---- both co-guardians READ the SAME row -------------------------------
  const dadReads = await asDad(q => q(
    `SELECT visible FROM guardian_activity_override WHERE child_id = $1 AND activity_key = 'game:chess'`, [CHILD_A]));
  check('B RLS', 'DAD (live edge) reads CHILD_A\'s row', dadReads[0]?.visible, 'false');
  const momReads = await asMom(q => q(
    `SELECT visible FROM guardian_activity_override WHERE child_id = $1 AND activity_key = 'game:chess'`, [CHILD_A]));
  check('B RLS', 'MOM (live edge, same child) ALSO reads the SAME row', momReads[0]?.visible, 'false');

  // ---- both co-guardians WRITE the SAME row ------------------------------
  const dadWrite = await asDad(q => q(
    `UPDATE guardian_activity_override SET visible = true WHERE child_id = $1 AND activity_key = 'game:chess'
     RETURNING visible`, [CHILD_A]));
  check('B RLS', "DAD's UPDATE succeeds — a live edge, not row ownership, gates this table",
    dadWrite[0]?.visible, 'true');
  const momWrite = await asMom(q => q(
    `UPDATE guardian_activity_override SET visible = false WHERE child_id = $1 AND activity_key = 'game:chess'
     RETURNING visible`, [CHILD_A]));
  check('B RLS', "MOM's UPDATE ALSO succeeds on the SAME row DAD just wrote — symmetric",
    momWrite[0]?.visible, 'false');

  // ---- the NEGATIVE case: no live edge reads and writes NOTHING, and — the
  // real divergence from child_theme_preference — there is no system-role
  // fallback that could still leak it either. ---------------------------
  const strangerReads = await asStranger(q => q(
    `SELECT visible FROM guardian_activity_override WHERE child_id = $1 AND activity_key = 'game:chess'`, [CHILD_A]));
  check('B RLS', 'STRANGER (no edge to CHILD_A) reads ZERO rows', strangerReads.length, 0);
  const strangerWrite = await asStranger(q => q(
    `UPDATE guardian_activity_override SET visible = true WHERE child_id = $1 AND activity_key = 'game:chess'
     RETURNING child_id`, [CHILD_A]));
  check('B RLS', "STRANGER's UPDATE affects ZERO rows (no error — just invisible)", strangerWrite.length, 0);
  const stillFalse = await asDad(q => q(
    `SELECT visible FROM guardian_activity_override WHERE child_id = $1 AND activity_key = 'game:chess'`, [CHILD_A]));
  check('B RLS', "CHILD_A's row is provably untouched by STRANGER's attempted UPDATE",
    stillFalse[0]?.visible, 'false');

  // Also proven through the real activityOverridesFor() loader itself
  // (principal-scoped session, no system role involved at all):
  const strangerViaLoader = await activityOverridesFor(pool, strangerPrincipal, CHILD_A);
  check('B RLS', "activityOverridesFor() for a no-edge guardian returns an empty list, not an error",
    strangerViaLoader.length, 0);

  // ---- WITH CHECK on a clean INSERT: DAD has no edge to CHILD_B at all ---
  let dadInsertForUnrelatedChildThrew = false;
  try {
    await asDad(q => q(
      `INSERT INTO guardian_activity_override (child_id, activity_key, visible, set_by)
       VALUES ($1, 'tile:homework', false, $2)`, [CHILD_B, DAD]));
  } catch { dadInsertForUnrelatedChildThrew = true; }
  check('B RLS', "DAD's INSERT for CHILD_B (a child he has NO edge to) is REJECTED by WITH CHECK",
    dadInsertForUnrelatedChildThrew, 'true');
  const childBStillEmpty = await admin.query(
    `SELECT count(*)::int AS n FROM guardian_activity_override WHERE child_id = $1`, [CHILD_B]);
  check('B RLS', "...and CHILD_B genuinely has no row afterward — the rejected INSERT left nothing behind",
    childBStillEmpty.rows[0].n, 0);

  let strangerInsertThrew = false;
  try {
    await asStranger(q => q(
      `INSERT INTO guardian_activity_override (child_id, activity_key, visible, set_by)
       VALUES ($1, 'tile:homework', true, $2)`, [CHILD_B, STRANGER]));
  } catch { strangerInsertThrew = true; }
  check('B RLS', "STRANGER's INSERT for CHILD_B (a child he genuinely guards) is allowed by the same policy",
    strangerInsertThrew, 'false');

  // ---- the child reads her OWN row, never someone else's -----------------
  const childAReads = await asChildA(q => q(
    `SELECT visible FROM guardian_activity_override WHERE child_id = $1 AND activity_key = 'game:chess'`, [CHILD_A]));
  check('B RLS', 'CHILD_A reads her own row', childAReads[0]?.visible, 'false');
  const childBReadsA = await asChildB(q => q(
    `SELECT visible FROM guardian_activity_override WHERE child_id = $1 AND activity_key = 'game:chess'`, [CHILD_A]));
  check('B RLS', "CHILD_B (a different child) reads ZERO of CHILD_A's row", childBReadsA.length, 0);

  // Also proven through the real activityOverridesFor() loader: a child
  // principal really does see her own family's overrides via the exact same
  // function a guardian uses, no separate child-only codepath.
  const childAViaLoader = await activityOverridesFor(pool, childAPrincipal, CHILD_A);
  check('B RLS', "activityOverridesFor() for the child herself really returns her own row",
    childAViaLoader.some((o) => o.activityKey === 'game:chess'), 'true');

  // ---- the child can NEVER write, even her own row — guardian-only by
  // design (no child write policy exists at all, 0033's own header). -------
  const childUpdateAttempt = await asChildA(q => q(
    `UPDATE guardian_activity_override SET visible = true WHERE child_id = $1 AND activity_key = 'game:chess'
     RETURNING child_id`, [CHILD_A]));
  check('B RLS', "CHILD_A's own UPDATE of her own row affects ZERO rows — guardian-only",
    childUpdateAttempt.length, 0);
  let childInsertThrew = false;
  try {
    await asChildB(q => q(
      `INSERT INTO guardian_activity_override (child_id, activity_key, visible, set_by)
       VALUES ($1, 'tile:homework', false, $2)`, [CHILD_B, STRANGER]));
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
