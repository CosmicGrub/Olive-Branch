/**
 * The FULL migration set, applied by a NON-superuser migrator (follow-up to PR #158).
 *
 * Why this exists: migration 0040 created a function with a function-level
 * `SET app.edge_lookup = 'on'`. On PostgreSQL 15+ a role that is not a
 * superuser (and holds no SET ON PARAMETER grant) gets `permission denied to
 * set parameter "app.edge_lookup"` for that, so 0040 failed on the first fresh
 * dev database -- while every CI database suite stayed green, because they all
 * migrate as the `postgres` superuser. The identity that really runs
 * tools/migrate.mjs in docker-compose.dev.yml and docker-compose.prod.yml is
 * `app_owner`: NOSUPERUSER NOBYPASSRLS, owner of the database
 * (tools/docker-dev/init-db.sql, init-db.prod.sh). Anything the migrations do
 * that app_owner cannot do is invisible to a superuser-run suite.
 *
 * This suite reproduces app_owner's exact privilege shape (the real app_owner
 * role, owning a brand-new database) and runs the real runner against it:
 *
 *   A  the role really is unprivileged (no SUPERUSER / CREATEROLE / CREATEDB /
 *      BYPASSRLS, no role memberships) -- otherwise nothing below proves anything
 *   B  every migration file applies, as that role, in one run (pg backend)
 *   C  a second run is a no-op (M2/M3 still hold under the non-superuser)
 *   D  the schema it produced: no function stores a custom GUC in proconfig
 *      (the 0040 class of bug, checked directly), pgcrypto and intarray exist
 *      (trusted extensions, created by the database owner), FORCE RLS is on for
 *      the edge tables, and actor_child_ids() leaves app.edge_lookup as found
 *   E  the psql backend (PSQL_CMD, what verify.sh and prod use) applies the same
 *      set as the same role (only when PGBIN points at a psql client)
 *
 * Needs a real Postgres: ADMIN_DATABASE_URL = a superuser URL (any database);
 * it creates and drops its own databases and (re)creates app_owner.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
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
const FILES = readdirSync(join(scaffold, 'db', 'migrations')).filter((f) => f.endsWith('.sql')).length;

const withDb = (url, db, user, pw) => {
  const u = new URL(url); u.pathname = `/${db}`;
  if (user) { u.username = user; u.password = pw; }
  return u.toString();
};
const admin = new pg.Client({ connectionString: ADMIN });
await admin.connect();

// db/migrations/0022 GRANTs to a cluster-level role it cannot create (nor can
// app_owner: no CREATEROLE). Provisioned here exactly as init-db.sql does.
await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='backup_reader') THEN
    CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS LOGIN PASSWORD 'backup_reader'; END IF;
END $$`);

// The migrator MUST be the real `app_owner`, not a lookalike: 0022 hard-codes
// `ALTER DEFAULT PRIVILEGES FOR ROLE app_owner`, which only that role (or a
// superuser) may run. app_owner is a cluster-wide role that sibling suites
// share, so it is never dropped here; its password is set to
// APP_OWNER_PASSWORD (verify.sh passes the one it provisions) or 'app_owner'.
const sfx = `${process.pid}`;
const ROLE = 'app_owner', PW = process.env.APP_OWNER_PASSWORD ?? 'app_owner';
const DB_PG = `olive_mig_ns_pg_${sfx}`, DB_PSQL = `olive_mig_ns_psql_${sfx}`;
const cleanup = async () => {
  for (const d of [DB_PG, DB_PSQL]) await admin.query(`DROP DATABASE IF EXISTS ${d} WITH (FORCE)`).catch(() => {});
};
await cleanup();
// Same attributes as init-db.sql / init-db.prod.sh give it.
await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${ROLE}') THEN
    CREATE ROLE ${ROLE} NOSUPERUSER NOBYPASSRLS LOGIN; END IF; END $$`);
await admin.query(`ALTER ROLE ${ROLE} NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB LOGIN PASSWORD '${PW}'`);
for (const d of [DB_PG, DB_PSQL]) await admin.query(`CREATE DATABASE ${d} OWNER ${ROLE}`);

function run(env) {
  const child = spawn(process.execPath, [migrator], {
    cwd: scaffold, env: { ...process.env, DATABASE_URL: '', PSQL_CMD: '', ...env }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
  return new Promise((resolve) => child.on('exit', (code) => resolve({ code, out, err })));
}
const applied = (out) => (out.match(/^applied /gm) ?? []).length;
const tail = (r) => (r.err || r.out).trim().split('\n').slice(-3).join(' | ');

try {
  // ---- A · the role is genuinely unprivileged -----------------------------
  {
    const r = (await admin.query(
      `SELECT rolsuper, rolcreaterole, rolcreatedb, rolbypassrls,
              (SELECT count(*)::int FROM pg_auth_members m WHERE m.member = r.oid) AS memberships
         FROM pg_roles r WHERE rolname = $1`, [ROLE])).rows[0];
    const g = 'A migrator role is unprivileged';
    check(g, 'not a superuser', r.rolsuper, false);
    check(g, 'no CREATEROLE', r.rolcreaterole, false);
    check(g, 'no CREATEDB', r.rolcreatedb, false);
    check(g, 'no BYPASSRLS', r.rolbypassrls, false);
    check(g, 'member of no role (no pg_* predefined roles)', r.memberships, 0);
  }

  // ---- B · full set, pg backend -------------------------------------------
  const url = withDb(ADMIN, DB_PG, ROLE, PW);
  {
    const res = await run({ DATABASE_URL: url });
    const g = 'B full migration set as the non-superuser (DATABASE_URL / pg)';
    check(g, `exits 0${res.code === 0 ? '' : ' -- ' + tail(res)}`, res.code, 0);
    check(g, 'applies every migration file', applied(res.out), FILES);
  }

  // ---- C · idempotent -----------------------------------------------------
  {
    const res = await run({ DATABASE_URL: url });
    const g = 'C second run';
    check(g, 'exits 0 (checksums unchanged, nothing refused)', res.code, 0);
    check(g, 'applies nothing', applied(res.out), 0);
  }

  // ---- D · the resulting schema ------------------------------------------
  {
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    const g = 'D resulting schema';
    try {
      const rec = (await c.query(`SELECT count(*)::int AS n FROM schema_migration`)).rows[0].n;
      check(g, 'schema_migration has one row per file', rec, FILES);

      const gucFns = (await c.query(
        `SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proconfig IS NOT NULL
             AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg WHERE split_part(cfg, '=', 1) LIKE '%.%')`)).rows;
      check(g, 'no function stores a custom (dotted) GUC in proconfig -- the 0040 failure class',
        gucFns.map((r) => r.proname).join(',') || 'none', 'none');

      const ext = (await c.query(
        `SELECT extname FROM pg_extension WHERE extname IN ('pgcrypto','intarray') ORDER BY 1`)).rows;
      check(g, 'trusted extensions pgcrypto + intarray were created by the unprivileged owner',
        ext.map((r) => r.extname).join(','), 'intarray,pgcrypto');

      const forced = (await c.query(
        `SELECT relname FROM pg_class WHERE relname IN ('guardianship','child','message_log')
            AND relrowsecurity AND relforcerowsecurity ORDER BY 1`)).rows;
      check(g, 'RLS is enabled AND forced on guardianship, child, message_log',
        forced.map((r) => r.relname).join(','), 'child,guardianship,message_log');

      const foreign = (await c.query(
        `SELECT count(*)::int AS n FROM pg_tables WHERE schemaname='public' AND tableowner <> $1`, [ROLE])).rows[0].n;
      check(g, 'the migrator owns every table it created', foreign, 0);

      // The 0040 helper, called as the real unprivileged role (who-sees-what is
      // edge_rls.test.mjs): the flag must end exactly as it started.
      await c.query('BEGIN');
      await c.query(`SELECT set_config('app.edge_lookup','',true)`);
      await c.query(`SELECT count(*) FROM actor_child_ids()`);
      const after = (await c.query(`SELECT current_setting('app.edge_lookup', true) AS v`)).rows[0].v;
      check(g, 'actor_child_ids() restores app.edge_lookup to what it found (off)', after === '' || after === null, true);
      await c.query(`SELECT set_config('app.edge_lookup','on',true)`);
      await c.query(`SELECT count(*) FROM actor_child_ids()`);
      const nested = (await c.query(`SELECT current_setting('app.edge_lookup', true) AS v`)).rows[0].v;
      check(g, 'and when called while already "on" (re-entrant) leaves it "on"', nested, 'on');
      await c.query('ROLLBACK');
    } finally { await c.end(); }
  }

  // ---- E · psql backend ----------------------------------------------------
  {
    const g = 'E full migration set as the non-superuser (PSQL_CMD / psql)';
    const pgbin = process.env.PGBIN;
    const psql = pgbin && existsSync(join(pgbin, process.platform === 'win32' ? 'psql.exe' : 'psql'))
      ? join(pgbin, 'psql') : null;
    if (!psql) {
      console.log('  note: PGBIN/psql not available -- group E (psql backend) not exercised');
    } else {
      const u = new URL(ADMIN);
      const res = await run({
        PSQL_CMD: `${psql} -h ${u.hostname} -p ${u.port || 5432} -U ${ROLE} -d ${DB_PSQL}`,
        PGPASSWORD: PW,
      });
      check(g, `exits 0${res.code === 0 ? '' : ' -- ' + tail(res)}`, res.code, 0);
      check(g, 'applies every migration file', applied(res.out), FILES);
    }
  }
} catch (e) {
  check('suite ran to completion', e && e.message, 'no exception');
} finally {
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
