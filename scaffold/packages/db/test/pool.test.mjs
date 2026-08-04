/**
 * packages/db — the first real Postgres connection in this repository.
 * MASTERFILE §5.17, §5.18.
 *
 * Every other suite tests withSession()/edgesFor() against a hand-written
 * fake object (packages/api/test/stack.test.mjs). This suite is the first to
 * run the real thing against a real database — requires DATABASE_URL, and is
 * NOT part of `npm test`'s default JS-suite chain for that reason (mirrors
 * how the db/test/*.sql suites are already gated on a live Postgres in
 * verify.sh rather than folded into the plain JS chain).
 */
import pg from 'pg';
import { createPool, withSession, withSystemSession, edgesFor } from '../src/pool.mjs';

// DATABASE_URL MUST be a NOSUPERUSER NOBYPASSRLS role (db/DEPLOYMENT.md's
// app_owner) — this is the whole point of the suite. "Any test of RLS run as
// `postgres` measures nothing," per that doc, quoting an actual incident.
// ADMIN_DATABASE_URL (defaults to DATABASE_URL) seeds fixtures; a real
// deployment's migration/seed role is routinely more privileged than the
// role the running application connects as.
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

// Seed a minimal real family: one child, two guardians, one guardianship edge,
// one journal entry (P7 subject) and one expense (P6 subject).
const CHILD = '11111111-1111-1111-1111-111111111111';
const DAD = '22222222-2222-2222-2222-222222222222';
const MOM = '33333333-3333-3333-3333-333333333333';
await admin.query('BEGIN');
await admin.query(`DELETE FROM child_journal_entry WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM expense WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Mom','America/New_York')`, [MOM]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'Ivy','2016-04-02','America/New_York')`,
  [CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{"calls":true}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD]);
await admin.query(
  `INSERT INTO child_journal_entry (child_id, body) VALUES ($1, 'a private thought')`, [CHILD]);
await admin.query(
  `INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule)
   VALUES ($1, $2, 500, 'school', now()::date, '{}')`, [CHILD, DAD]);
await admin.query('COMMIT');

// A · edgesFor — the actual query, against real rows
{
  const edges = await edgesFor(pool, DAD);
  check('A edgesFor', 'finds the seeded edge', edges.length, 1);
  check('A edgesFor', 'childId matches', edges[0]?.childId, CHILD);
  check('A edgesFor', 'role matches', edges[0]?.role, 'guardian');
  check('A edgesFor', 'scope survives the jsonb round-trip', edges[0]?.scope?.calls, 'true');
  check('A edgesFor', 'a user with zero edges gets an empty array',
    (await edgesFor(pool, MOM)).length, 0);
}

// B · withSession — the GUCs actually land, transaction-scoped
{
  const roleSeen = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => (await q(`SELECT current_setting('app.role', true) AS r`))[0].r);
  check('B session', 'app.role is set inside the session', roleSeen, 'guardian');

  const childSeen = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
    async (q) => (await q(`SELECT current_setting('app.child_id', true) AS c`))[0].c);
  check('B session', 'app.child_id is set for a child principal', childSeen, CHILD);

  // The next session, on whatever pooled connection this lands on, must not
  // see the previous session's context — the entire reason set_config uses
  // is_local rather than a bare SET.
  const nextRole = await withSession(pool, { roleName: 'system', userId: null, childId: null },
    async (q) => (await q(`SELECT current_setting('app.child_id', true) AS c`))[0].c);
  check('B session', 'a fresh session does not inherit the previous one\'s child_id',
    nextRole, '');

  const sysRole = await withSystemSession(pool,
    async (q) => (await q(`SELECT current_setting('app.role', true) AS r,
                                  current_setting('app.child_id', true) AS c,
                                  current_setting('app.user_id', true) AS u`))[0]);
  check('B session', 'withSystemSession sets role system', sysRole.r, 'system');
  check('B session', 'withSystemSession carries no child context', sysRole.c, '');
  check('B session', 'withSystemSession carries no user context', sysRole.u, '');
}

// C · fail-closed, not fail-crash (§5.18, v0.6.0 findings)
{
  let threw = false;
  try { await withSession(pool, { roleName: 'child', userId: null, childId: null }, async () => {}); }
  catch { threw = true; }
  check('C fail-closed', 'a child principal with no childId throws before touching the DB',
    threw, 'true');

  threw = false;
  try { await withSession(pool, { roleName: 'guardian', userId: null, childId: null }, async () => {}); }
  catch { threw = true; }
  check('C fail-closed', 'a guardian principal with no userId throws before touching the DB',
    threw, 'true');
}

// D · P7/P6 through REAL row-level security — the actual point of this file.
// Every prior test of this exercised a fake `db` object. This is the first
// time any code in this repository has asked the real database "can a
// guardian read this child's journal" and gotten Postgres's own answer.
{
  const journalRows = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(`SELECT body FROM child_journal_entry WHERE child_id = $1`, [CHILD]));
  check('D real RLS', 'P7 — a guardian session reads ZERO journal rows, not a query error',
    journalRows.length, 0);

  const ownRows = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
    async (q) => q(`SELECT body FROM child_journal_entry WHERE child_id = $1`, [CHILD]));
  check('D real RLS', 'the owning child CAN read her own journal', ownRows.length, 1);

  const otherChildRows = await withSession(pool, { roleName: 'child', userId: null, childId: DAD },
    // DAD's id is not a real child id, but exercises "some OTHER child_id" —
    // the RLS predicate compares against current_child(), so this must be 0
    // regardless of whether the id exists.
    async (q) => q(`SELECT body FROM child_journal_entry WHERE child_id = $1`, [CHILD]));
  check('D real RLS', 'a different child_id context also reads zero rows',
    otherChildRows.length, 0);

  const expenseAsChild = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
    async (q) => q(`SELECT amount_cents FROM expense WHERE child_id = $1`, [CHILD]));
  check('D real RLS', 'P6 — a child session reads ZERO expense rows', expenseAsChild.length, 0);

  // Proves the row actually exists and P6 isn't just "nobody can see anything" —
  // the RLS policy (expense_guardians_only) permits guardian/coordinator.
  const expenseAsGuardian = await withSession(pool,
    { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(`SELECT amount_cents FROM expense WHERE child_id = $1`, [CHILD]));
  check('D real RLS', 'a guardian CAN read the same expense row a child session cannot',
    expenseAsGuardian.length, 1);
}

await admin.query(`DELETE FROM expense WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM child_journal_entry WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
