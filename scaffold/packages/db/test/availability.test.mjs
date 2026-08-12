/**
 * packages/db — guardian_availability_window: real RLS, and the real
 * setAvailabilityWindows()/availabilityFor()/guardiansOfChild() loaders.
 * MASTERFILE §9 (MARKUP screen 'availability'). db/migrations/0010_availability.sql.
 *
 * Mirrors pool.test.mjs / custody_order.test.mjs exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres with 0009 applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason those two aren't — a suite that
 * measures RLS run as `postgres` measures nothing (see pool.test.mjs's own
 * header / db/DEPLOYMENT.md).
 *
 * Two things this file proves that availability_contract.test.mjs (fake
 * pool, no Postgres) cannot:
 *   A) setAvailabilityWindows()/availabilityFor()/guardiansOfChild() really
 *      round-trip through a live database — replace-all semantics included.
 *   B) guardian_availability_window's RLS — a guardian writes only her own
 *      rows (INSERT/UPDATE/DELETE all independently probed, not just
 *      SELECT), a co-guardian and the shared child can read, and an
 *      unrelated guardian/child in a different family read NOTHING — the
 *      exact negative case the task asked for.
 */
import pg from 'pg';
import { createPool, withSession, setAvailabilityWindows, availabilityFor, guardiansOfChild }
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
const CHILD_A = '77777777-7777-7777-7777-777777777777';
const CHILD_B = '88888888-8888-8888-8888-888888888888';
const DAD = '99999999-9999-9999-9999-999999999999';
const MOM = 'aaaaaaaa-1111-1111-1111-111111111111';
const STRANGER = 'bbbbbbbb-2222-2222-2222-222222222222';

async function reset() {
  await admin.query(`DELETE FROM guardian_availability_window WHERE guardian_id IN ($1,$2,$3)`,
    [DAD, MOM, STRANGER]);
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
// A · setAvailabilityWindows / availabilityFor / guardiansOfChild — the real
// loaders, real round-trip, replace-all semantics.
// ===========================================================================
{
  await setAvailabilityWindows(pool, DAD, [
    { weekday: 1, startLocal: '09:00', endLocal: '12:00', note: 'mornings' },
    { weekday: 3, startLocal: '17:00', endLocal: '20:00', note: null },
  ]);
  await setAvailabilityWindows(pool, MOM, [
    { weekday: 2, startLocal: '13:00', endLocal: '15:00' },
  ]);
  await setAvailabilityWindows(pool, STRANGER, [
    { weekday: 5, startLocal: '10:00', endLocal: '11:00' },
  ]);

  const guardianIds = (await guardiansOfChild(pool, CHILD_A)).sort();
  check('A loaders', 'guardiansOfChild finds exactly DAD and MOM', guardianIds.join(','),
    [DAD, MOM].sort().join(','));

  const avail = await availabilityFor(pool, CHILD_A);
  check('A loaders', 'availabilityFor returns DAD (2) + MOM (1) = 3 windows', avail.length, 3);
  check('A loaders', "never includes STRANGER's window — different family",
    avail.some(w => w.guardianId === STRANGER), 'false');
  const dadWindow = avail.find(w => w.weekday === 1 && w.guardianId === DAD);
  check('A loaders', 'weekday/startLocal/endLocal/note round-trip',
    `${dadWindow?.startLocal}-${dadWindow?.endLocal}/${dadWindow?.note}`, '09:00-12:00/mornings');
  check('A loaders', 'guardianName is joined from app_user.display_name', dadWindow?.guardianName, 'Dad');
  const nullNote = avail.find(w => w.weekday === 3 && w.guardianId === DAD);
  check('A loaders', 'a null note round-trips as null, not the string "null"',
    nullNote?.note === null, 'true');

  // Replace-all: a second call with FEWER windows must leave exactly that
  // many, not append to the first set.
  await setAvailabilityWindows(pool, DAD, [
    { weekday: 6, startLocal: '08:00', endLocal: '09:00' },
  ]);
  const afterReplace = await availabilityFor(pool, CHILD_A);
  const dadAfter = afterReplace.filter(w => w.guardianId === DAD);
  check('A loaders', 'replace-all leaves exactly the new set, not old+new', dadAfter.length, 1);
  check('A loaders', 'and it is the new window, not a stale one', dadAfter[0]?.weekday, 6);

  // A child with no guardians at all (defensive: honest empty array, not a crash).
  const none = await availabilityFor(pool, '00000000-0000-0000-0000-000000000000');
  check('A loaders', 'a child with no live guardians gets an empty array, never a crash', none.length, 0);
}

// ===========================================================================
// B · RLS — the task's own requirement: writes are own-only; reads are
// co-guardian/shared-child-only; a different family reads and writes NOTHING.
// ===========================================================================
{
  const asDad = (fn) => withSession(pool, { roleName: 'guardian', userId: DAD, childId: null }, fn);
  const asMom = (fn) => withSession(pool, { roleName: 'guardian', userId: MOM, childId: null }, fn);
  const asStranger = (fn) => withSession(pool, { roleName: 'guardian', userId: STRANGER, childId: null }, fn);
  const asChildA = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A }, fn);
  const asChildB = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CHILD_B }, fn);

  // ---- own read/write --------------------------------------------------
  const dadOwn = await asDad(q => q(`SELECT weekday FROM guardian_availability_window WHERE guardian_id = $1`, [DAD]));
  check('B RLS', 'DAD reads his own row(s)', dadOwn.length, 1);

  // ---- co-guardian READ --------------------------------------------------
  const dadReadsMom = await asDad(q => q(`SELECT weekday FROM guardian_availability_window WHERE guardian_id = $1`, [MOM]));
  check('B RLS', 'DAD (co-guardian of CHILD_A) CAN read MOM\'s windows', dadReadsMom.length, 1);
  const momReadsDad = await asMom(q => q(`SELECT weekday FROM guardian_availability_window WHERE guardian_id = $1`, [DAD]));
  check('B RLS', 'MOM (co-guardian) CAN read DAD\'s windows too — symmetric', momReadsDad.length, 1);

  // ---- the NEGATIVE case the task specifically asked for: a different
  // family reads NOTHING. ---------------------------------------------------
  const strangerReadsDad = await asStranger(q => q(`SELECT weekday FROM guardian_availability_window WHERE guardian_id = $1`, [DAD]));
  check('B RLS', 'STRANGER (no shared child with DAD) reads ZERO of DAD\'s windows', strangerReadsDad.length, 0);
  const dadReadsStranger = await asDad(q => q(`SELECT weekday FROM guardian_availability_window WHERE guardian_id = $1`, [STRANGER]));
  check('B RLS', 'and the reverse — DAD reads ZERO of STRANGER\'s windows', dadReadsStranger.length, 0);

  // ---- child of a shared child READS; an unrelated child does not --------
  const childAReadsBoth = await asChildA(q => q(`SELECT guardian_id FROM guardian_availability_window WHERE guardian_id IN ($1,$2)`, [DAD, MOM]));
  check('B RLS', 'CHILD_A (their shared child) CAN read both her guardians\' windows', childAReadsBoth.length, 2);
  const childBReadsDad = await asChildB(q => q(`SELECT guardian_id FROM guardian_availability_window WHERE guardian_id = $1`, [DAD]));
  check('B RLS', 'CHILD_B (unrelated to DAD) reads ZERO of DAD\'s windows', childBReadsDad.length, 0);

  // ---- the task's own headline negative: a guardian CANNOT WRITE another
  // guardian's rows. UPDATE and DELETE both silently affect zero rows under
  // RLS (no error — the row is simply not visible to the writer for that
  // command); INSERT is rejected outright because WITH CHECK fails. All
  // three independently probed, not just SELECT. -------------------------
  const updateAttempt = await asDad(q => q(
    `UPDATE guardian_availability_window SET note = 'hijacked' WHERE guardian_id = $1 RETURNING id`, [MOM]));
  check('B RLS', "DAD's UPDATE against MOM's row affects ZERO rows", updateAttempt.length, 0);
  const momNoteAfter = await asMom(q => q(`SELECT note FROM guardian_availability_window WHERE guardian_id = $1`, [MOM]));
  check('B RLS', "MOM's own row is provably untouched by DAD's attempted UPDATE",
    momNoteAfter[0]?.note === 'hijacked', 'false');

  const deleteAttempt = await asDad(q => q(
    `DELETE FROM guardian_availability_window WHERE guardian_id = $1 RETURNING id`, [MOM]));
  check('B RLS', "DAD's DELETE against MOM's row affects ZERO rows", deleteAttempt.length, 0);
  const momStillThere = await asMom(q => q(`SELECT id FROM guardian_availability_window WHERE guardian_id = $1`, [MOM]));
  check('B RLS', "MOM's row SURVIVES DAD's attempted DELETE", momStillThere.length, 1);

  let insertThrew = false;
  try {
    await asDad(q => q(
      `INSERT INTO guardian_availability_window (guardian_id, weekday, start_local, end_local)
       VALUES ($1, 0, '01:00', '02:00')`, [MOM]));
  } catch { insertThrew = true; }
  check('B RLS', "DAD's INSERT impersonating MOM's guardian_id is REJECTED (WITH CHECK), not silently dropped",
    insertThrew, 'true');

  // ---- a child can never write, even her own family's rows ---------------
  let childInsertThrew = false;
  try {
    await asChildA(q => q(
      `INSERT INTO guardian_availability_window (guardian_id, weekday, start_local, end_local)
       VALUES ($1, 0, '01:00', '02:00')`, [DAD]));
  } catch { childInsertThrew = true; }
  check('B RLS', 'a child session can never INSERT into this table at all', childInsertThrew, 'true');
  const childUpdateAttempt = await asChildA(q => q(
    `UPDATE guardian_availability_window SET note = 'nope' WHERE guardian_id = $1 RETURNING id`, [DAD]));
  check('B RLS', "a child session's UPDATE affects ZERO rows too", childUpdateAttempt.length, 0);
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
