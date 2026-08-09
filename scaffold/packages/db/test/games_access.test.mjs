/**
 * packages/db — child_games_access: real RLS, and the real end-to-end
 * loader/setter. MASTERFILE §5.17, §5.18. db/migrations/0008_games_access.sql.
 *
 * Mirrors custody_order.test.mjs's own pattern exactly (same DATABASE_URL/
 * ADMIN_DATABASE_URL split, same check() harness): requires a real Postgres
 * with the 0008 migration applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason pool.test.mjs/custody_order.test.mjs
 * aren't — a suite that measures RLS run as `postgres` measures nothing, so
 * DATABASE_URL here MUST be a NOSUPERUSER NOBYPASSRLS role (db/DEPLOYMENT.md's
 * app_owner).
 *
 * Proves, against the real database, every guarantee the task asked for:
 *   A) a child reads only her own value, and cannot write it AT ALL — even
 *      with a raw UPDATE, bypassing the app layer entirely.
 *   B) a real guardian of that child can read AND write it.
 *   C) a guardian with NO edge to that child is rejected — both at the raw
 *      RLS layer (a real guardian of some OTHER child) and at the app layer
 *      (setGamesEnabledFor's own can()/edgesFor() check).
 *   D) a sibling's guardian (an edge to a different child only) cannot touch
 *      it either, and a total stranger (zero edges anywhere) is rejected the
 *      same way — both are the same underlying "no live edge to THIS child"
 *      case, exercised from two different real starting points.
 *   E) setGamesEnabledFor()/gamesEnabledFor() — the real loader/setter pair
 *      — round-trip a real value end to end, and honest absence (a child
 *      never toggled) reads as locked (false), never a guess.
 */
import pg from 'pg';
import { createPool, withSession, gamesEnabledFor, setGamesEnabledFor } from '../src/pool.mjs';

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

// Seed a minimal real family with FOUR actors, each exercising a distinct
// real-world case:
//   IVY      — the child under test, HAS a live guardian (DAD).
//   SIBLING  — a second real child, DAD is NOT her guardian (the "wrong
//              child" / sibling case).
//   DAD      — IVY's real, live guardian.
//   MOM      — a total stranger: zero edges to ANY child in this fixture.
const IVY = '77777777-7777-7777-7777-777777777777';
const SIBLING = '88888888-8888-8888-8888-888888888888';
const DAD = '99999999-9999-9999-9999-999999999999';
const MOM = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

await admin.query('BEGIN');
await admin.query(`DELETE FROM child_games_access WHERE child_id IN ($1, $2)`, [IVY, SIBLING]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, SIBLING]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, SIBLING]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Chicago')`, [DAD, MOM]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Sibling','2018-01-01','America/New_York')`, [IVY, SIBLING]);
// DAD is a real, live GUARDIAN of IVY only — never SIBLING, and MOM holds no
// edge to either child anywhere in this fixture.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{"settings":true}', tstzrange(now() - interval '1 year', null))`,
  [IVY, DAD]);
await admin.query('COMMIT');

// A · raw RLS — child: read her own row, and NOTHING ELSE, ever.
{
  // Seed IVY's row directly (bypassing the app layer entirely) so the read
  // test proves RLS, not the setter.
  await admin.query(
    `INSERT INTO child_games_access (child_id, games_enabled) VALUES ($1, true)
     ON CONFLICT (child_id) DO UPDATE SET games_enabled = true`, [IVY]);

  const ownRows = await withSession(pool, { roleName: 'child', userId: null, childId: IVY },
    async (q) => q(`SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [IVY]));
  check('A child read', 'the owning child CAN read her own row', ownRows.length, 1);
  check('A child read', 'and sees the real value', ownRows[0]?.games_enabled, true);

  // Same technique pool.test.mjs/custody_order.test.mjs already use: a
  // session scoped to some OTHER child_id must read zero rows of IVY's,
  // regardless of whether that id is a real child.
  const otherChildRows = await withSession(pool, { roleName: 'child', userId: null, childId: SIBLING },
    async (q) => q(`SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [IVY]));
  check('A child read', 'a different child_id context reads zero rows of IVY\'s row',
    otherChildRows.length, 0);

  // THE hard requirement: a child session cannot write her own row AT ALL,
  // not even via a raw UPDATE that bypasses the app layer completely. RLS's
  // child policy is FOR SELECT only, so no permissive policy admits this
  // UPDATE for role='child' — Postgres filters the row out before the WHERE
  // clause ever sees it, so this returns zero rows, not an error.
  const childWrite = await withSession(pool, { roleName: 'child', userId: null, childId: IVY },
    async (q) => q(
      `UPDATE child_games_access SET games_enabled = false WHERE child_id = $1
       RETURNING games_enabled`, [IVY]));
  check('A child read', 'a child session CANNOT write her own row (RETURNING is empty)',
    childWrite.length, 0);

  // Prove the attempted write really changed nothing.
  const stillTrue = (await admin.query(
    `SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [IVY])).rows[0];
  check('A child read', 'the row is unchanged after the rejected child write',
    stillTrue.games_enabled, true);

  // Reset to the production default for the rest of the suite.
  await admin.query(`UPDATE child_games_access SET games_enabled = false WHERE child_id = $1`, [IVY]);
}

// B · raw RLS — a real guardian of THIS child can read AND write.
{
  const guardianRead = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(`SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [IVY]));
  check('B guardian', 'DAD (a real live guardian of IVY) can read her row', guardianRead.length, 1);

  const guardianWrite = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(
      `UPDATE child_games_access SET games_enabled = true WHERE child_id = $1
       RETURNING games_enabled`, [IVY]));
  check('B guardian', 'DAD can write IVY\'s row (RETURNING has the new value)',
    guardianWrite[0]?.games_enabled, true);

  await admin.query(`UPDATE child_games_access SET games_enabled = false WHERE child_id = $1`, [IVY]);
}

// C · raw RLS — a guardian with NO edge to THIS child is rejected, even
// though he really is a live guardian of a different, real child.
{
  const wrongChildRead = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(`SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [SIBLING]));
  check('C wrong child', 'DAD has no edge to SIBLING, so he reads zero rows of hers',
    wrongChildRead.length, 0);

  // Seed SIBLING a row directly so the write attempt below has a real row to
  // (fail to) touch, not just an absent one.
  await admin.query(
    `INSERT INTO child_games_access (child_id, games_enabled) VALUES ($1, false)
     ON CONFLICT (child_id) DO NOTHING`, [SIBLING]);
  const wrongChildWrite = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(
      `UPDATE child_games_access SET games_enabled = true WHERE child_id = $1
       RETURNING games_enabled`, [SIBLING]));
  check('C wrong child', 'DAD cannot write SIBLING\'s row either (RETURNING is empty)',
    wrongChildWrite.length, 0);
}

// D · raw RLS — a total stranger (zero edges anywhere) is rejected the same
// way as a role that isn't even 'guardian'.
{
  const strangerRead = await withSession(pool, { roleName: 'guardian', userId: MOM, childId: null },
    async (q) => q(`SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [IVY]));
  check('D stranger', 'MOM (zero edges anywhere) reads zero rows of IVY\'s', strangerRead.length, 0);

  // A role that isn't literally 'guardian' — e.g. 'system', which every
  // other loader in this codebase legitimately uses (activeCustodyOrderFor,
  // edgesFor) — must ALSO be refused here. Unlike custody_order's lenient
  // "not_child_scope" policy, this table has no catch-all: no policy at all
  // admits role='system'.
  const systemRead = await withSession(pool, { roleName: 'system', userId: null, childId: null },
    async (q) => q(`SELECT games_enabled FROM child_games_access WHERE child_id = $1`, [IVY]));
  check('D stranger', 'even role=system (no catch-all policy exists here) reads zero rows',
    systemRead.length, 0);
}

// E · the real loader/setter pair — first lock (can()/edgesFor()) AND second
// lock (RLS) proven together, through the exact functions routes.mjs calls.
{
  const setOn = await setGamesEnabledFor(pool, IVY, DAD, true);
  check('E setter', 'a real guardian CAN enable games for her child', setOn.allow, true);
  check('E setter', 'and the returned value is the real new value', setOn.enabled, true);
  check('E setter', 'gamesEnabledFor now reads the same real value back',
    await gamesEnabledFor(pool, IVY), true);

  const setOff = await setGamesEnabledFor(pool, IVY, DAD, false);
  check('E setter', 'the same real guardian can lock it again', setOff.allow, true);
  check('E setter', 'and the returned value flips back', setOff.enabled, false);
  check('E setter', 'gamesEnabledFor reads the flip back too',
    await gamesEnabledFor(pool, IVY), false);

  // DAD has no edge to SIBLING — first lock rejects before any write session
  // ever opens.
  const wrongChild = await setGamesEnabledFor(pool, SIBLING, DAD, true);
  check('E setter', 'DAD is rejected for SIBLING (no edge to that child)', wrongChild.allow, false);
  check('E setter', 'with the real Deny reason from can()', wrongChild.reason, 'no_edge');

  // MOM has zero edges anywhere.
  const stranger = await setGamesEnabledFor(pool, IVY, MOM, true);
  check('E setter', 'MOM (zero edges anywhere) is rejected for IVY', stranger.allow, false);
  check('E setter', 'with reason no_edge', stranger.reason, 'no_edge');

  // Honest absence: a real child who was never toggled reads as locked, not
  // a guess — SIBLING never went through the setter in this block.
  await admin.query(`DELETE FROM child_games_access WHERE child_id = $1`, [SIBLING]);
  check('E setter', 'a child with no row at all reads as locked (false), never fabricated',
    await gamesEnabledFor(pool, SIBLING), false);
}

await admin.query(`DELETE FROM child_games_access WHERE child_id IN ($1, $2)`, [IVY, SIBLING]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, SIBLING]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, SIBLING]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
