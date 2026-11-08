/**
 * tools/migrate.mjs takes a Postgres advisory lock for the whole run
 * (audit P-18). Needs a real Postgres (ADMIN_DATABASE_URL: a superuser, it
 * creates and drops two scratch databases of its own).
 *
 *   A. DATABASE_URL (pg) mode: two migrators started at the same instant
 *      against an EMPTY database -> both exit 0, exactly one applies the
 *      migrations and the other reports "up to date" after waiting, and the
 *      schema_migration table has exactly one row per file (no collision).
 *   B. PSQL_CMD (psql) mode, same race, same expectations.
 *   C. A migrator started while ANOTHER session holds the lock BLOCKS (does
 *      not race ahead), then proceeds once it is released.
 *   D. No advisory lock is left behind once the runners exit (released with
 *      the connection, so a killed migrator can never wedge the next one).
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { readdirSync } from 'node:fs';
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

const withDb = (url, db) => { const u = new URL(url); u.pathname = `/${db}`; return u.toString(); };
const admin = new pg.Client({ connectionString: ADMIN });
await admin.connect();
// db/migrations/0022 GRANTs to roles it cannot create (cluster-level objects).
await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_owner') THEN
    CREATE ROLE app_owner NOSUPERUSER NOBYPASSRLS LOGIN PASSWORD 'app_owner'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='backup_reader') THEN
    CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS LOGIN PASSWORD 'backup_reader'; END IF;
END $$`);

const suffix = `${process.pid}`;
const DB_A = `olive_mig_lock_a_${suffix}`, DB_B = `olive_mig_lock_b_${suffix}`, DB_C = `olive_mig_lock_c_${suffix}`;
for (const d of [DB_A, DB_B, DB_C]) {
  await admin.query(`DROP DATABASE IF EXISTS ${d}`);
  await admin.query(`CREATE DATABASE ${d}`);
}

function run(env) {
  const child = spawn(process.execPath, [migrator], {
    cwd: scaffold, env: { ...process.env, DATABASE_URL: '', PSQL_CMD: '', ...env }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
  const done = new Promise((resolve) => child.on('exit', (code) => resolve({ code, out, err })));
  return { child, done, output: () => out };
}
const applied = (out) => (out.match(/^applied /gm) ?? []).length;
const count = async (db) => {
  const c = new pg.Client({ connectionString: withDb(ADMIN, db) });
  await c.connect();
  try {
    const r = await c.query(`SELECT count(*)::int AS n, count(DISTINCT filename)::int AS d FROM schema_migration`);
    return r.rows[0];
  } finally { await c.end(); }
};

try {
  // ---- A · pg mode race -------------------------------------------------
  {
    const env = { DATABASE_URL: withDb(ADMIN, DB_A) };
    const [r1, r2] = await Promise.all([run(env).done, run(env).done]);
    check('A pg-mode race', 'both concurrent migrators exit 0 (neither crashes on the other\'s DDL)',
      `${r1.code}/${r2.code}`, '0/0');
    check('A pg-mode race', 'exactly one of them applied the migrations',
      [applied(r1.out), applied(r2.out)].sort((a, b) => a - b).join(','), `0,${FILES}`);
    const loser = applied(r1.out) === 0 ? r1 : r2;
    check('A pg-mode race', 'the other waited its turn and reported "up to date"', /up to date/.test(loser.out), true);
    const c = await count(DB_A);
    check('A pg-mode race', 'schema_migration has exactly one row per migration file',
      `${c.n}/${c.d}`, `${FILES}/${FILES}`);
  }

  // ---- B · psql mode race ----------------------------------------------
  {
    const bin = process.env.PGBIN ? join(process.env.PGBIN, 'psql') : 'psql';
    const env = { PSQL_CMD: `${bin} ${withDb(ADMIN, DB_B)}` };
    const [r1, r2] = await Promise.all([run(env).done, run(env).done]);
    check('B psql-mode race', 'both concurrent migrators exit 0', `${r1.code}/${r2.code}`, '0/0');
    check('B psql-mode race', 'exactly one of them applied the migrations',
      [applied(r1.out), applied(r2.out)].sort((a, b) => a - b).join(','), `0,${FILES}`);
    const c = await count(DB_B);
    check('B psql-mode race', 'schema_migration has exactly one row per migration file',
      `${c.n}/${c.d}`, `${FILES}/${FILES}`);
  }

  // ---- C · blocks while another session holds the lock -------------------
  {
    const holder = new pg.Client({ connectionString: withDb(ADMIN, DB_C) });
    await holder.connect();
    await holder.query(`SELECT pg_advisory_lock(hashtext('olive_branch_migrate')::bigint)`);
    const m = run({ DATABASE_URL: withDb(ADMIN, DB_C) });
    let finished = false;
    m.done.then(() => { finished = true; });
    await new Promise((r) => setTimeout(r, 2500));
    check('C blocks on a held lock', 'a migrator started while the lock is held does NOT proceed',
      `${finished}/${applied(m.output())}`, 'false/0');
    await holder.query(`SELECT pg_advisory_unlock(hashtext('olive_branch_migrate')::bigint)`);
    const res = await Promise.race([m.done, new Promise((r) => setTimeout(() => r({ code: 'TIMEOUT' }), 90_000))]);
    check('C blocks on a held lock', 'once the lock is released it runs to completion', res.code, 0);
    check('C blocks on a held lock', 'and applies every migration', applied(res.out), FILES);
    await holder.end();
  }

  // ---- D · nothing left locked -----------------------------------------
  {
    await new Promise((r) => setTimeout(r, 300));
    const leftover = await admin.query(
      `SELECT count(*)::int AS n FROM pg_locks WHERE locktype = 'advisory'
          AND objid::bigint = (hashtext('olive_branch_migrate')::bigint & 4294967295)`);
    check('D lock released', 'no migrator advisory lock remains once every runner has exited', leftover.rows[0].n, 0);
  }
} finally {
  for (const d of [DB_A, DB_B, DB_C]) await admin.query(`DROP DATABASE IF EXISTS ${d} WITH (FORCE)`).catch(() => {});
  await admin.end();
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
