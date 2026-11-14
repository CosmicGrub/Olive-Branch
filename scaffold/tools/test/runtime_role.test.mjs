/**
 * The connection role split (S-B11): migrations and ops as `app_owner`, the RUNNING
 * server as the least-privilege `app_runtime`. Real Postgres, real roles, real server boot.
 *
 *   A  the runtime role is genuinely unprivileged and owns nothing
 *   B  the runner applies the grants (idempotent; also when the role is created AFTER
 *      the schema; a table a later migration creates is covered automatically)
 *   C  what the runtime role CANNOT do: DDL, DISABLE RLS, DROP POLICY / TRIGGER,
 *      TRUNCATE, rewriting the migration ledger, SET ROLE to the owner
 *   D  what it CAN do: ordinary DML under RLS (bound by every policy, FORCE-ed or not)
 *   E  the pure verdict functions (server/db_role.mjs)
 *   F  the real server boot: production refuses an owner/superuser role unless
 *      ALLOW_OWNER_DB_ROLE=1; development warns; the runtime role boots in production
 *
 * Needs a real Postgres: ADMIN_DATABASE_URL = a superuser URL (any database); it creates
 * and drops its own databases and (re)creates the two roles.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { randomBytes } from 'node:crypto';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { privilegeProblems, runtimeRoleVerdict } from '../../server/db_role.mjs';

const ADMIN = process.env.ADMIN_DATABASE_URL;
if (!ADMIN) { console.error('ADMIN_DATABASE_URL required (superuser)'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const scaffold = join(here, '..', '..');
const migrator = join(scaffold, 'tools', 'migrate.mjs');
const INDEX = join(scaffold, 'server', 'index.mjs');
const FILES = readdirSync(join(scaffold, 'db', 'migrations')).filter((f) => f.endsWith('.sql')).length;

const withDb = (url, db, user, pw) => {
  const u = new URL(url); u.pathname = `/${db}`;
  if (user) { u.username = user; u.password = pw; }
  return u.toString();
};
const admin = new pg.Client({ connectionString: ADMIN });
await admin.connect();

const OWNER = 'app_owner', OPW = process.env.APP_OWNER_PASSWORD ?? 'app_owner';
const RUNTIME = 'app_runtime', RPW = process.env.APP_RUNTIME_PASSWORD ?? 'app_runtime';
const DB = `olive_runtime_role_${process.pid}`, DB_LATE = `olive_runtime_role_late_${process.pid}`;
const cleanup = async () => {
  for (const d of [DB, DB_LATE]) await admin.query(`DROP DATABASE IF EXISTS ${d} WITH (FORCE)`).catch(() => {});
};
await cleanup();
// backup_reader: migration 0022 grants onto it (provisioned exactly as init-db.sql does).
await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='backup_reader') THEN
    CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS LOGIN PASSWORD 'backup_reader'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${OWNER}') THEN
    CREATE ROLE ${OWNER} NOSUPERUSER NOBYPASSRLS LOGIN; END IF;
END $$`);
await admin.query(`ALTER ROLE ${OWNER} NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB LOGIN PASSWORD '${OPW}'`);
// The same attributes init-db.sql / init-db.prod.sh give the runtime role.
await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${RUNTIME}') THEN
    CREATE ROLE ${RUNTIME} NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT LOGIN; END IF; END $$`);
await admin.query(`ALTER ROLE ${RUNTIME} NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT LOGIN PASSWORD '${RPW}'`);
await admin.query(`CREATE DATABASE ${DB} OWNER ${OWNER}`);

function migrate(url) {
  const child = spawn(process.execPath, [migrator], {
    cwd: scaffold, env: { ...process.env, DATABASE_URL: url, PSQL_CMD: '' }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
  return new Promise((resolve) => child.on('exit', (code) => resolve({ code, out, err })));
}
const ownerUrl = withDb(ADMIN, DB, OWNER, OPW);
const runtimeUrl = withDb(ADMIN, DB, RUNTIME, RPW);
const denied = async (c, sql) => {
  try { await c.query(sql); return 'allowed'; } catch (e) { return e.code === '42501' ? 'denied' : `error:${e.code}:${e.message.split('\n')[0]}`; }
};

try {
  // ---- A · the runtime role is unprivileged -------------------------------
  {
    const g = 'A runtime role shape';
    const r = (await admin.query(
      `SELECT rolsuper, rolcreaterole, rolcreatedb, rolbypassrls, rolcanlogin,
              (SELECT count(*)::int FROM pg_auth_members m WHERE m.member = r.oid) AS memberships
         FROM pg_roles r WHERE rolname = $1`, [RUNTIME])).rows[0];
    check(g, 'not a superuser', r.rolsuper, false);
    check(g, 'no CREATEROLE', r.rolcreaterole, false);
    check(g, 'no CREATEDB', r.rolcreatedb, false);
    check(g, 'no BYPASSRLS', r.rolbypassrls, false);
    check(g, 'member of no role', r.memberships, 0);
    check(g, 'can log in', r.rolcanlogin, true);
  }

  // ---- B · grants applied by the runner ----------------------------------
  {
    const g = 'B grants';
    const first = await migrate(ownerUrl);
    check(g, `the migrator applies every file as app_owner${first.code === 0 ? '' : ' -- ' + (first.err || first.out).trim().split('\n').slice(-2).join(' | ')}`, first.code, 0);
    check(g, '...and every file is applied', (first.out.match(/^applied /gm) ?? []).length, FILES);
    const second = await migrate(ownerUrl);
    check(g, 'a second run is a clean no-op that re-applies the grants', `${second.code}/${(second.out.match(/^applied /gm) ?? []).length}`, '0/0');

    const owner = new pg.Client({ connectionString: ownerUrl }); await owner.connect();
    try {
      await owner.query(`CREATE TABLE zz_later_table (id int PRIMARY KEY)`);
      await owner.query(`CREATE SEQUENCE zz_later_seq`);
    } finally { await owner.end(); }
    const rt = new pg.Client({ connectionString: runtimeUrl }); await rt.connect();
    try {
      check(g, 'a table created by a LATER migration is usable by the runtime role with no manual grant (default privileges)',
        await rt.query(`INSERT INTO zz_later_table VALUES (1)`).then(() => 'ok', (e) => e.code), 'ok');
      check(g, '...and so is its sequence', await rt.query(`SELECT nextval('zz_later_seq')`).then(() => 'ok', (e) => e.code), 'ok');
    } finally { await rt.end(); }

    // a role that arrives AFTER the schema (an existing deployment adopting the split): the
    // database holds the schema but the role holds no grants yet. Re-running the runner
    // (which has nothing to migrate) is what hands them over.
    await admin.query(`CREATE DATABASE ${DB_LATE} OWNER ${OWNER}`);
    const lateOwner = withDb(ADMIN, DB_LATE, OWNER, OPW);
    const lateFirst = await migrate(lateOwner);
    check(g, 'a second database migrates the same way', lateFirst.code, 0);
    const lateAdmin = new pg.Client({ connectionString: withDb(ADMIN, DB_LATE) }); await lateAdmin.connect();
    try {
      await lateAdmin.query(`REVOKE ALL ON ALL TABLES IN SCHEMA public FROM ${RUNTIME}`);
      await lateAdmin.query(`REVOKE ALL ON SCHEMA public FROM ${RUNTIME}`);
    } finally { await lateAdmin.end(); }
    const lateUrl = withDb(ADMIN, DB_LATE, RUNTIME, RPW);
    const probe = async () => { const c = new pg.Client({ connectionString: lateUrl }); await c.connect();
      try { return await c.query(`SELECT count(*) FROM guardianship`).then(() => 'ok', (e) => e.code); } finally { await c.end(); } };
    check(g, 'before the grants arrive the role can read nothing (42501)', await probe(), '42501');
    const regrant = await migrate(lateOwner);
    check(g, 'the runner with nothing to migrate re-applies them', `${regrant.code}/${await probe()}`, '0/ok');
  }

  // ---- C/D · what it cannot, and can, do ---------------------------------
  {
    const rt = new pg.Client({ connectionString: runtimeUrl }); await rt.connect();
    try {
      const g = 'C the runtime role cannot do DDL';
      check(g, 'CREATE TABLE', await denied(rt, `CREATE TABLE zz_evil (id int)`), 'denied');
      check(g, 'ALTER TABLE ... DISABLE ROW LEVEL SECURITY (the S-B11 attack)', await denied(rt, `ALTER TABLE message_log DISABLE ROW LEVEL SECURITY`), 'denied');
      check(g, 'ALTER TABLE ... NO FORCE ROW LEVEL SECURITY', await denied(rt, `ALTER TABLE guardianship NO FORCE ROW LEVEL SECURITY`), 'denied');
      check(g, 'DROP POLICY', await denied(rt, `DROP POLICY IF EXISTS auth_challenge_system_only ON auth_challenge`), 'denied');
      check(g, 'DROP TRIGGER on the append-only evidence table', await denied(rt, `DROP TRIGGER message_log_no_delete ON message_log`), 'denied');
      check(g, 'DROP TABLE', await denied(rt, `DROP TABLE child CASCADE`), 'denied');
      check(g, 'CREATE FUNCTION', await denied(rt, `CREATE FUNCTION zz_f() RETURNS int AS 'SELECT 1' LANGUAGE sql`), 'denied');
      check(g, 'CREATE INDEX', await denied(rt, `CREATE INDEX zz_i ON guardianship (child_id)`), 'denied');
      check(g, 'TRUNCATE', await denied(rt, `TRUNCATE message_log`), 'denied');
      check(g, 'ALTER ROLE (even itself)', await denied(rt, `ALTER ROLE ${RUNTIME} BYPASSRLS`), 'denied');
      check(g, 'SET ROLE app_owner', await denied(rt, `SET ROLE ${OWNER}`), 'denied');
      check(g, 'rewriting the migration ledger (UPDATE schema_migration)', await denied(rt, `UPDATE schema_migration SET checksum = 'x'`), 'denied');
      check(g, 'reading the migration ledger', await denied(rt, `SELECT * FROM schema_migration`), 'denied');
      check(g, 'COPY ... TO PROGRAM', await denied(rt, `COPY (SELECT 1) TO PROGRAM 'true'`), 'denied');

      const d = 'D what it can do';
      const owned = (await admin.query(
        `SELECT count(*)::int AS n FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
           WHERE ns.nspname = 'public' AND c.relkind IN ('r','v','S','f','p') AND c.relowner = (SELECT oid FROM pg_roles WHERE rolname = $1)`, [RUNTIME])).rows[0].n;
      check(d, 'it owns no relation at all, so every row security policy binds it (including tables that are not FORCE-ed)', owned, 0);
      const nonOwner = (await admin.query(
        `SELECT count(*)::int AS n FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'zz_later_table' AND tableowner <> $1`, [OWNER])).rows[0].n;
      check(d, 'app_owner owns every table', nonOwner, 0);
      // identity the way the server sets it
      await rt.query('BEGIN');
      await rt.query(`SELECT set_config('app.role','system',true)`);
      const n = (await rt.query(`SELECT count(*)::int AS n FROM app_user`)).rows[0].n;
      check(d, 'a system session reads a table under RLS', typeof n, 'number');
      await rt.query(`INSERT INTO app_user (display_name, home_tz) VALUES ('Zed','UTC')`);
      check(d, 'and writes one (DML works)', (await rt.query(`SELECT count(*)::int AS n FROM app_user WHERE display_name = 'Zed'`)).rows[0].n, 1);
      await rt.query('ROLLBACK');
      // no identity at all: fail closed
      await rt.query('BEGIN');
      const none = (await rt.query(`SELECT count(*)::int AS n FROM message_log`)).rows[0].n;
      await rt.query('ROLLBACK');
      check(d, 'with no identity set a family-private table shows nothing (RLS fails closed)', none, 0);
      const threw = await rt.query(`INSERT INTO message_log (child_id, sender_id, body) VALUES (gen_random_uuid(), gen_random_uuid(), 'x')`)
        .then(() => 'allowed', (e) => e.code);
      check(d, 'and an INSERT with no identity is refused (RLS or a constraint, never accepted)', threw !== 'allowed', true);
    } finally { await rt.end(); }
  }

  // ---- E · the verdict functions -----------------------------------------
  {
    const g = 'E verdicts';
    const clean = { name: 'app_runtime', rolsuper: false, rolbypassrls: false, rolcreaterole: false, rolcreatedb: false, owned_tables: 0 };
    check(g, 'a clean runtime role has no problems', privilegeProblems(clean).length, 0);
    check(g, 'a superuser is a problem', privilegeProblems({ ...clean, rolsuper: true }).length, 1);
    check(g, 'BYPASSRLS is a problem', privilegeProblems({ ...clean, rolbypassrls: true }).length, 1);
    check(g, 'owning tables is a problem', privilegeProblems({ ...clean, owned_tables: 46 }).length, 1);
    check(g, 'CREATEROLE and CREATEDB are each a problem', privilegeProblems({ ...clean, rolcreaterole: true, rolcreatedb: true }).length, 2);
    check(g, 'an unreadable role row is a problem, not a pass', privilegeProblems(undefined).length, 1);
    const bad = privilegeProblems({ ...clean, owned_tables: 3 });
    check(g, 'production + a bad role refuses', runtimeRoleVerdict(bad, { NODE_ENV: 'production' }).problems.length, 1);
    check(g, 'production + ALLOW_OWNER_DB_ROLE=1 warns instead', `${runtimeRoleVerdict(bad, { NODE_ENV: 'production', ALLOW_OWNER_DB_ROLE: '1' }).problems.length}/${runtimeRoleVerdict(bad, { NODE_ENV: 'production', ALLOW_OWNER_DB_ROLE: '1' }).warnings.length}`, '0/1');
    check(g, 'only the exact value 1 overrides', runtimeRoleVerdict(bad, { NODE_ENV: 'production', ALLOW_OWNER_DB_ROLE: 'true' }).problems.length, 1);
    check(g, 'development warns', `${runtimeRoleVerdict(bad, { NODE_ENV: 'development' }).problems.length}/${runtimeRoleVerdict(bad, { NODE_ENV: 'development' }).warnings.length}`, '0/1');
    check(g, 'test warns', runtimeRoleVerdict(bad, { NODE_ENV: 'test' }).problems.length, 0);
    check(g, 'an unset NODE_ENV is treated as production (strict)', runtimeRoleVerdict(bad, {}).problems.length, 1);
    check(g, 'a clean role in production is silent', `${runtimeRoleVerdict([], { NODE_ENV: 'production' }).problems.length}/${runtimeRoleVerdict([], { NODE_ENV: 'production' }).warnings.length}`, '0/0');
  }

  // ---- F · the real server boot ------------------------------------------
  {
    const g = 'F server boot';
    const hex = () => randomBytes(32).toString('hex');
    const freePort = async () => { const s = createServer(); s.listen(0, '127.0.0.1'); await once(s, 'listening');
      const p = s.address().port; s.close(); await once(s, 'close'); return p; };
    async function boot(databaseUrl, extraEnv) {
      const port = await freePort();
      const env = {
        PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, PORT: String(port), DATABASE_URL: databaseUrl,
        SESSION_SECRET: hex(), MEDIA_SIGNING_SECRET: hex(),
        LIVEKIT_URL: 'wss://x.invalid', LIVEKIT_API_KEY: 'devkey', LIVEKIT_API_SECRET: 'devsecret_at_least_32_chars_long_xx',
        ...extraEnv,
      };
      const child = spawn(process.execPath, [INDEX], { env, stdio: ['ignore', 'pipe', 'pipe'] });
      let out = '', err = '';
      child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
      const ready = await new Promise((resolve) => {
        const iv = setInterval(() => { if (/listening on/.test(out)) { clearInterval(iv); resolve('up'); } }, 25);
        child.on('exit', (code) => { clearInterval(iv); resolve(`exit:${code}`); });
        setTimeout(() => { clearInterval(iv); resolve('timeout'); }, 15000);
      });
      const stop = async () => { if (child.exitCode === null) { child.kill('SIGTERM');
        await Promise.race([once(child, 'exit'), new Promise((r) => setTimeout(r, 3000))]);
        if (child.exitCode === null) child.kill('SIGKILL'); } };
      return { ready, err: () => err, port, stop };
    }
    const PROD = { NODE_ENV: 'production', PUBLIC_BASE_URL: 'https://api.example.com', TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1' };

    const asOwner = await boot(ownerUrl, PROD);
    check(g, 'production as app_owner (owns the tables) refuses to start (exit 2)', asOwner.ready, 'exit:2');
    check(g, '...and says why and how to fix it', /database role check failed: .*OWNS .* table\(s\).*app_runtime/.test(asOwner.err()), 'true');
    await asOwner.stop();

    const asSuper = await boot(withDb(ADMIN, DB), PROD);
    check(g, 'production as a SUPERUSER refuses to start (exit 2)', asSuper.ready, 'exit:2');
    check(g, '...naming the superuser problem', /SUPERUSER/.test(asSuper.err()), 'true');
    await asSuper.stop();

    const override = await boot(ownerUrl, { ...PROD, ALLOW_OWNER_DB_ROLE: '1' });
    check(g, 'production as app_owner with ALLOW_OWNER_DB_ROLE=1 starts', override.ready, 'up');
    check(g, '...but still warns on stderr', /WARNING: database role:/.test(override.err()), 'true');
    await override.stop();

    const dev = await boot(ownerUrl, { NODE_ENV: 'development' });
    check(g, 'development as app_owner starts (with a warning)', `${dev.ready}/${/WARNING: database role:/.test(dev.err())}`, 'up/true');
    await dev.stop();

    const runtime = await boot(runtimeUrl, PROD);
    check(g, 'production as app_runtime starts, silently', `${runtime.ready}/${/database role/.test(runtime.err())}`, 'up/false');
    if (runtime.ready === 'up') {
      const hz = await fetch(`http://127.0.0.1:${runtime.port}/healthz`).then((r) => r.status, () => 0);
      check(g, '...and /healthz (a real SELECT 1 as that role) answers 200', hz, 200);
    }
    await runtime.stop();
  }
} catch (e) {
  check('suite ran to completion', e && e.stack, 'no exception');
} finally {
  await cleanup();
  await admin.end();
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
