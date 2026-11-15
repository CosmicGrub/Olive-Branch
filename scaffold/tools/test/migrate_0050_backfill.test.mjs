/**
 * Migration 0050's claimant backfill, applied by the NON-superuser migrator.
 *
 * 0050 copies guardian_invite.bootstrap_user_id into the new claimant_user_id
 * for invites that were bootstrapped before the identity lane existed.
 * guardian_invite is FORCE row level security (0014) with a policy that admits
 * only app.role = 'system' or the inviter. The migrator that really runs in
 * docker-compose.prod.yml is `app_owner` (NOSUPERUSER, NOBYPASSRLS) and sets
 * neither, so an unguarded UPDATE matched ZERO rows and raised nothing: every
 * pre-0050 bootstrapped invite lost its claimant on a real deploy (confirm then
 * answered not_claimed and bootstrap already_bootstrapped; the inviter could
 * never grant access). Every other suite migrates an EMPTY database, or as a
 * superuser (who bypasses RLS), so none of them could see it.
 *
 * This suite builds that exact situation: the real `app_owner` owns a fresh
 * database, migrations before 0050 are applied by the real runner, rows are
 * seeded the way an older deploy would hold them, and then 0050 is applied by
 * the same runner as the same role.
 *
 *   A  the premise is real: app_owner is unprivileged, the table is FORCE
 *      RLS, and an app_owner session with no role sees none of its rows (so
 *      the OLD, unguarded UPDATE could only ever match zero rows)
 *   B  the pre-0050 database is seeded (bootstrapped, merely accepted, and
 *      still-pending invites) and holds none of 0050's columns yet
 *   C  0050 applies as app_owner; the bootstrapped invite now has its
 *      claimant and claimed_at; the others are untouched
 *   D  the system role did not leak out of the migration transaction, and the
 *      table is still locked to everyone else (FORCE RLS intact)
 *
 * Needs a real Postgres: ADMIN_DATABASE_URL = a superuser URL (any database).
 * It creates and drops its own database and (re)creates app_owner.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { mkdtempSync, readdirSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ADMIN = process.env.ADMIN_DATABASE_URL;
if (!ADMIN) { console.error('ADMIN_DATABASE_URL required (superuser)'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const scaffold = join(here, '..', '..');
const migrator = join(scaffold, 'tools', 'migrate.mjs');
const allMigrations = join(scaffold, 'db', 'migrations');
const ALL = readdirSync(allMigrations).filter((f) => f.endsWith('.sql')).sort();
const BEFORE = ALL.filter((f) => f < '0050');
const AFTER = ALL.filter((f) => f >= '0050');

const withDb = (url, db, user, pw) => {
  const u = new URL(url); u.pathname = `/${db}`;
  if (user) { u.username = user; u.password = pw; }
  return u.toString();
};
const ROLE = 'app_owner', PW = process.env.APP_OWNER_PASSWORD ?? 'app_owner';
const DB = `olive_mig_0050_${process.pid}`;
const staged = mkdtempSync(join(tmpdir(), 'olive-mig-0050-'));

const admin = new pg.Client({ connectionString: ADMIN });
await admin.connect();
const cleanup = async () => {
  await admin.query(`DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`).catch(() => {});
  rmSync(staged, { recursive: true, force: true });
};
await cleanup();
await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='backup_reader') THEN
    CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS LOGIN PASSWORD 'backup_reader'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${ROLE}') THEN
    CREATE ROLE ${ROLE} NOSUPERUSER NOBYPASSRLS LOGIN; END IF; END $$`);
await admin.query(`ALTER ROLE ${ROLE} NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB LOGIN PASSWORD '${PW}'`);
await admin.query(`CREATE DATABASE ${DB} OWNER ${ROLE}`);

function run(dir) {
  const child = spawn(process.execPath, [migrator], {
    cwd: scaffold,
    env: { ...process.env, DATABASE_URL: withDb(ADMIN, DB, ROLE, PW), PSQL_CMD: '', MIGRATIONS_DIR: dir },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
  return new Promise((resolve) => child.on('exit', (code) => resolve({ code, out, err })));
}
const tail = (r) => (r.err || r.out).trim().split('\n').slice(-3).join(' | ');

let su, owner;
try {
  // Stage 1: everything before 0050, as the unprivileged owner.
  for (const f of BEFORE) copyFileSync(join(allMigrations, f), join(staged, f));
  const first = await run(staged);
  check('B pre-0050 database', `every migration before 0050 applies as app_owner${first.code === 0 ? '' : ' -- ' + tail(first)}`, first.code, 0);

  su = new pg.Client({ connectionString: withDb(ADMIN, DB) });
  owner = new pg.Client({ connectionString: withDb(ADMIN, DB, ROLE, PW) });
  await su.connect(); await owner.connect();

  // ---- A · the premise ----------------------------------------------------
  const ins = async (sql, args) => (await su.query(sql, args)).rows[0].id;
  {
    const g = 'A the premise is real';
    const r = (await admin.query(
      `SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = $1`, [ROLE])).rows[0];
    check(g, 'app_owner is neither superuser nor BYPASSRLS', `${r.rolsuper} ${r.rolbypassrls}`, 'false false');
    const t = (await su.query(
      `SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = 'guardian_invite'`)).rows[0];
    check(g, 'guardian_invite is ENABLE + FORCE row level security', `${t.relrowsecurity} ${t.relforcerowsecurity}`, 'true true');
  }

  // ---- B · seed what an older deploy holds ---------------------------------
  const inviter = await ins(`INSERT INTO app_user (email, display_name, home_tz) VALUES ('inviter@example.test','Inviter','America/Chicago') RETURNING id`);
  const booted = await ins(`INSERT INTO app_user (email, display_name, home_tz) VALUES ('booted@example.test','Booted','America/Chicago') RETURNING id`);
  const child = await ins(`INSERT INTO child (display_name, birth_date, home_tz) VALUES ('Kid','2020-01-01','America/Chicago') RETURNING id`);
  const invite = (email, extra) => ins(
    `INSERT INTO guardian_invite (child_id, invited_by, invited_email, role, label, ${extra.cols})
     VALUES ($1, $2, $3, 'guardian', 'Dad', ${extra.vals}) RETURNING id`,
    [child, inviter, email, ...(extra.args ?? [])]);
  const bootedAt = '2026-01-02T03:04:05Z';
  const iBoot = await invite('booted@example.test', {
    cols: 'accepted_at, bootstrapped_at, bootstrap_user_id', vals: `'2026-01-01T00:00:00Z', $4, $5`, args: [bootedAt, booted] });
  const iAcc = await invite('accepted@example.test', { cols: 'accepted_at', vals: `'2026-01-01T00:00:00Z'` });
  const iPend = await invite('pending@example.test', { cols: 'expires_at', vals: `now() + interval '1 day'` });
  {
    const g = 'B pre-0050 database';
    check(g, 'the bootstrapped invite is seeded', (await su.query(
      `SELECT count(*)::int n FROM guardian_invite WHERE bootstrap_user_id IS NOT NULL`)).rows[0].n, 1);
    check(g, 'and 0050 has not run yet (no claimant_user_id column)', (await su.query(
      `SELECT count(*)::int n FROM information_schema.columns WHERE table_name='guardian_invite' AND column_name='claimant_user_id'`)).rows[0].n, 0);

    // What the migration session looked like before the fix: app_owner, no role.
    const seen = (await owner.query(`SELECT count(*)::int n FROM guardian_invite`)).rows[0].n;
    check('A the premise is real',
      'app_owner with no role sees 0 of the 3 seeded rows (so an unguarded UPDATE touches none)', seen, 0);
  }

  // ---- C · apply 0050 (and anything after) as app_owner --------------------
  for (const f of AFTER) copyFileSync(join(allMigrations, f), join(staged, f));
  const second = await run(staged);
  {
    const g = 'C 0050 applied as app_owner';
    check(g, `exits 0${second.code === 0 ? '' : ' -- ' + tail(second)}`, second.code, 0);
    const r = (await su.query(
      `SELECT id, claimant_user_id, claimed_at FROM guardian_invite`)).rows
      .reduce((m, x) => ({ ...m, [x.id]: x }), {});
    check(g, 'the bootstrapped invite kept its claimant (the bug: it was NULL)', r[iBoot]?.claimant_user_id, booted);
    check(g, '...and claimed_at is the bootstrap time', new Date(r[iBoot]?.claimed_at).toISOString(), '2026-01-02T03:04:05.000Z');
    check(g, 'an accepted-only invite has no claimant', r[iAcc]?.claimant_user_id, null);
    check(g, 'a pending invite has no claimant', r[iPend]?.claimant_user_id, null);
    check(g, 'nothing was confirmed or declined by the backfill', (await su.query(
      `SELECT count(*)::int n FROM guardian_invite WHERE confirmed_at IS NOT NULL OR declined_at IS NOT NULL`)).rows[0].n, 0);
  }

  // ---- D · the grant did not leak ------------------------------------------
  {
    const g = 'D the system role stayed inside the migration';
    const c = new pg.Client({ connectionString: withDb(ADMIN, DB, ROLE, PW) });
    await c.connect();
    try {
      check(g, 'a new app_owner session has no app.role', (await c.query(
        `SELECT coalesce(current_setting('app.role', true), '') AS v`)).rows[0].v, '');
      check(g, 'and still sees 0 guardian_invite rows (FORCE RLS intact)', (await c.query(
        `SELECT count(*)::int n FROM guardian_invite`)).rows[0].n, 0);
    } finally { await c.end(); }
  }
} catch (e) {
  check('suite ran to completion', e && e.message, 'no exception');
} finally {
  await su?.end().catch(() => {}); await owner?.end().catch(() => {});
  await cleanup();
  await admin.end();
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
