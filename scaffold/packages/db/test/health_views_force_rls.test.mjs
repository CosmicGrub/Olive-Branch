/**
 * packages/db/test/health_views_force_rls.test.mjs — migration 0047.
 *
 * health_check read four FORCE-RLS tables (delivery_intent, media_artifact,
 * guardianship, message_log) THROUGH a view owned by app_owner, so under the
 * production shape (unprivileged app_owner migrates AND owns everything) six of
 * its eight counters read 0 for any session that had not declared
 * app.role='system': a monitoring blind spot. Every other database suite
 * migrates as the `postgres` superuser, whose views bypass RLS, so none of them
 * could see it. This suite builds the real production shape and asserts the
 * true, non-zero counts from every kind of caller, and that the monitoring role
 * cannot read a row.
 *
 * Setup (same as tools/test/migrate_nonsuper.test.mjs): the real `app_owner`
 * role (NOSUPERUSER NOBYPASSRLS) owns a brand-new database and runs
 * tools/migrate.mjs; `health_monitor` and `backup_reader` are provisioned by
 * the superuser first, exactly as tools/docker-dev/init-db.sql does.
 *
 * Needs a real Postgres: ADMIN_DATABASE_URL = a superuser URL (any database).
 * It creates and drops its own database and (re)creates the cluster roles
 * app_owner / backup_reader / health_monitor (sibling suites share them, so
 * they are never dropped).
 *
 *   A  the shape is real: migrator unprivileged, owns the views, FORCE RLS on
 *   B  seeded fixture: every health counter's TRUE value (raw superuser counts)
 *      is known, and five of them are non-zero
 *   C  health_check returns exactly the true values for: the superuser, the
 *      monitoring login, app_owner with NO role, app_owner as a family-scoped
 *      guardian and as a child, app_owner as system (the pre-fix reader)
 *   D  the monitoring login reads no rows (tables, row-level views, the
 *      function) and the probe flag does not widen a family-scoped session
 *   E  health_alert.test.mjs passes on this app_owner-migrated database
 *      (superuser seeding, app_owner reading), and tools/health-alert.mjs run
 *      as health_monitor with HEALTH_DATABASE_URL names the breaches
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ADMIN = process.env.ADMIN_DATABASE_URL;
if (!ADMIN) { console.error('ADMIN_DATABASE_URL required (superuser)'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const scaffold = join(here, '..', '..', '..');
const migrator = join(scaffold, 'tools', 'migrate.mjs');

const withDb = (url, db, user, pw) => {
  const u = new URL(url); u.pathname = `/${db}`;
  if (user) { u.username = user; u.password = pw; }
  return u.toString();
};

const OWNER = 'app_owner', OWNER_PW = process.env.APP_OWNER_PASSWORD ?? 'app_owner';
const MON = 'health_monitor', MON_PW = 'health_monitor_test_pw';
const DB = `olive_health_rls_${process.pid}`;

const admin = new pg.Client({ connectionString: ADMIN });
await admin.connect();
const cleanup = async () => { await admin.query(`DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`).catch(() => {}); };
await cleanup();

await admin.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='backup_reader') THEN
    CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS LOGIN PASSWORD 'backup_reader'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${OWNER}') THEN
    CREATE ROLE ${OWNER} NOSUPERUSER NOBYPASSRLS LOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${MON}') THEN
    CREATE ROLE ${MON} NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE LOGIN; END IF;
END $$`);
await admin.query(`ALTER ROLE ${OWNER} NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB LOGIN PASSWORD '${OWNER_PW}'`);
await admin.query(`ALTER ROLE ${MON} NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB LOGIN PASSWORD '${MON_PW}'`);
await admin.query(`CREATE DATABASE ${DB} OWNER ${OWNER}`);

const URL_ADMIN = withDb(ADMIN, DB);
const URL_OWNER = withDb(ADMIN, DB, OWNER, OWNER_PW);
const URL_MON = withDb(ADMIN, DB, MON, MON_PW);

function runNode(args, env) {
  const child = spawn(process.execPath, args, {
    cwd: scaffold, env: { ...process.env, DATABASE_URL: '', PSQL_CMD: '', ...env }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
  return new Promise((resolve) => child.on('exit', (code) => resolve({ code, out, err })));
}

const open = async (url) => { const c = new pg.Client({ connectionString: url }); await c.connect(); return c; };
const ids = {
  dad: '88888888-8888-8888-8888-8888000000a1', mum: '88888888-8888-8888-8888-8888000000a2',
  kidA: '77777777-7777-7777-7777-7777000000a1', kidB: '77777777-7777-7777-7777-7777000000a2',
};
const CHECKS = ['retention_breach', 'orphan_risk', 'stalled_delivery', 'unmaterialized',
  'retention_invariant_broken', 'closure_without_reason', 'rls_unforced', 'log_sequence_gap'];

const asMap = (r) => Object.fromEntries(r.rows.map((x) => [x.check_name, Number(x.observed)]));
const fmt = (m) => CHECKS.map((k) => `${k}=${m[k]}`).join(' ');

try {
  // ---- migrate as the unprivileged owner ----------------------------------
  const mig = await runNode([migrator], { DATABASE_URL: URL_OWNER });
  check('A shape', 'full migration set applies as the unprivileged app_owner', mig.code, 0);
  if (mig.code !== 0) console.log((mig.err || mig.out).trim().split('\n').slice(-6).join('\n'));

  {
    const r = (await admin.query(`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname=$1`, [OWNER])).rows[0];
    check('A shape', 'app_owner is not superuser and not BYPASSRLS', `${r.rolsuper}/${r.rolbypassrls}`, 'false/false');
    const m = (await admin.query(`SELECT rolsuper, rolbypassrls, rolcreaterole FROM pg_roles WHERE rolname=$1`, [MON])).rows[0];
    check('A shape', 'health_monitor is not superuser, not BYPASSRLS, cannot create roles',
      `${m.rolsuper}/${m.rolbypassrls}/${m.rolcreaterole}`, 'false/false/false');
    const Q = await open(URL_ADMIN);
    const o = (await Q.query(
      `SELECT string_agg(relname || ':' || pg_get_userbyid(relowner), ',' ORDER BY relname) AS s
         FROM pg_class WHERE relname IN ('health_check','orphan_risk','retention_breach','delivery_intent',
                                         'media_artifact','guardianship','message_log')`)).rows[0].s;
    check('A shape', 'app_owner owns the views AND the tables (the production shape)',
      o.split(',').every((x) => x.endsWith(':app_owner')), true);
    const f = (await Q.query(
      `SELECT count(*)::int n FROM pg_class WHERE relname IN ('delivery_intent','media_artifact','guardianship','message_log')
          AND relrowsecurity AND relforcerowsecurity`)).rows[0].n;
    await Q.end();
    check('A shape', 'ENABLE + FORCE RLS on the four tables the health checks read', f, 4);
  }

  // ---- seed the true fixture (superuser bypasses RLS) ----------------------
  const truth = {};
  const A = await open(URL_ADMIN);
  try {
    await A.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES
      ($1,'Dad','America/Chicago'), ($2,'Mum','America/Chicago')`, [ids.dad, ids.mum]);
    await A.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
      ($1,'KidA','2016-04-02','America/New_York'), ($2,'KidB','2017-05-03','America/New_York')`, [ids.kidA, ids.kidB]);
    await A.query(`INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
      ($1,$3,'guardian', tstzrange(now() - interval '1 year', null)),
      ($2,$4,'guardian', tstzrange(now() - interval '1 year', null))`, [ids.kidA, ids.kidB, ids.dad, ids.mum]);

    const art = async (n, child, author, { preserved = false, expires = "now() + interval '5 days'" } = {}) => {
      const id = `cccccccc-0000-0000-0000-0000000000${n}`;
      await A.query(
        `INSERT INTO media_artifact (id, child_id, author_id, kind, storage_key, duration_ms, captured_at,
                                     captured_tz, preserved, preserved_by, expires_at)
         VALUES ($1,$2,$3,'video_msg',$4,5000,now(),'America/New_York',$5::boolean,
                 CASE WHEN $5::boolean THEN $3::uuid END, ${preserved ? 'NULL' : expires})`,
        [id, child, author, `hv/${n}`, preserved]);
      return id;
    };
    const intent = async (n, child, sender, ref, { state = 'pending', scheduled = null, created = 'now()' } = {}) => {
      await A.query(
        `INSERT INTO delivery_intent (id, child_id, sender_id, payload_kind, payload_ref, policy,
                target_local_date, target_daypart, state, scheduled_at, created_at, expires_at)
         VALUES ($1,$2,$3,'e2e_video',$4,'on_local_date', current_date + 40,'bedtime',$5,
                 ${scheduled ?? 'NULL'}, ${created}, now() + interval '60 days')`,
        [`dddddddd-0000-0000-0000-0000000000${n}`, child, sender, ref, state]);
    };
    // orphan_risk: 2 (family A), 1 more (family B) = 3
    const a1 = await art('01', ids.kidA, ids.dad), a2 = await art('02', ids.kidA, ids.dad), a3 = await art('03', ids.kidB, ids.mum);
    await intent('01', ids.kidA, ids.dad, a1); await intent('02', ids.kidA, ids.dad, a2); await intent('03', ids.kidB, ids.mum, a3);
    // stalled_delivery: 2 ready intents scheduled 3h ago on a preserved artifact (not orphans)
    const keep = await art('04', ids.kidA, ids.dad, { preserved: true });
    await intent('04', ids.kidA, ids.dad, keep, { state: 'ready', scheduled: "now() - interval '3 hours'" });
    await intent('05', ids.kidB, ids.mum, keep, { state: 'ready', scheduled: "now() - interval '4 hours'" });
    // unmaterialized: 1 pending, no schedule, created 3h ago
    await intent('06', ids.kidA, ids.dad, keep, { state: 'pending', created: "now() - interval '3 hours'" });
    // retention_breach: 2 tombstones older than a day
    for (const [n, art_] of [['07', a1], ['08', a2]]) {
      await A.query(`INSERT INTO reap_tombstone (artifact_id, storage_key, error, first_seen)
                     VALUES ($1,$2,'boom', now() - interval '3 days')`, [art_, `hv/${n}`]);
    }
    // closure_without_reason / retention_invariant_broken are CHECK-unrepresentable (their true
    // value is 0 and must still read 0); log_sequence_gap: one gap (needs the chain trigger off).
    await A.query(`ALTER TABLE message_log DISABLE TRIGGER message_log_chain`);
    const h = (c) => c.repeat(64);
    await A.query(`INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash) VALUES
        ($1,0,$2,'one',$3,$4), ($1,2,$2,'three',$4,$5)`, [ids.kidA, ids.dad, '0'.repeat(64), h('a'), h('b')]);
    await A.query(`ALTER TABLE message_log ENABLE TRIGGER message_log_chain`);

    // ground truth: the raw predicates, run by the superuser (RLS does not apply to it)
    const raw = (sql) => A.query(sql).then((r) => Number(r.rows[0].n));
    truth.retention_breach = await raw(`SELECT count(*) n FROM reap_tombstone WHERE first_seen < now() - interval '1 day'`);
    truth.orphan_risk = await raw(
      `SELECT count(*) n FROM delivery_intent d JOIN media_artifact m ON m.id = d.payload_ref
        WHERE d.state IN ('pending','ready') AND m.preserved = false AND m.expires_at IS NOT NULL
          AND m.expires_at <= d.expires_at`);
    truth.stalled_delivery = await raw(`SELECT count(*) n FROM delivery_intent WHERE state='ready' AND scheduled_at < now() - interval '1 hour'`);
    truth.unmaterialized = await raw(`SELECT count(*) n FROM delivery_intent WHERE state='pending' AND scheduled_at IS NULL AND created_at < now() - interval '1 hour'`);
    truth.retention_invariant_broken = await raw(`SELECT count(*) n FROM media_artifact WHERE preserved=false AND expires_at IS NULL`);
    truth.closure_without_reason = await raw(`SELECT count(*) n FROM guardianship WHERE closed_at IS NOT NULL AND closed_reason IS NULL`);
    truth.rls_unforced = await raw(
      `SELECT count(*) n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind IN ('r','p') AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
          AND NOT EXISTS (SELECT 1 FROM rls_allow_list a WHERE a.table_name=c.relname)`);
    truth.log_sequence_gap = await raw(
      `SELECT count(*) n FROM (SELECT seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev FROM message_log) x
        WHERE prev IS NOT NULL AND seq <> prev + 1`);

    const expected = { retention_breach: 2, orphan_risk: 3, stalled_delivery: 2, unmaterialized: 1,
      retention_invariant_broken: 0, closure_without_reason: 0, rls_unforced: 0, log_sequence_gap: 1 };
    check('B fixture', `ground truth is the seeded known values (${fmt(truth)})`, fmt(truth), fmt(expected));
    check('B fixture', 'five counters are non-zero in the truth (a reader seeing 0 is wrong)',
      CHECKS.filter((k) => truth[k] > 0).length, 5);
  } finally { await A.end(); }

  // ---- C · every kind of caller reads the true values ----------------------
  const viewOf = async (url, setup = []) => {
    const c = await open(url);
    try {
      for (const [k, v] of setup) await c.query(`SELECT set_config($1,$2,false)`, [k, v]);
      return asMap(await c.query(`SELECT check_name, observed FROM health_check`));
    } finally { await c.end(); }
  };
  const callers = [
    ['postgres superuser, no role', URL_ADMIN, []],
    ['health_monitor (monitoring login), no role', URL_MON, []],
    ['app_owner (server login), no app.role', URL_OWNER, []],
    ['app_owner as a family-scoped guardian', URL_OWNER, [['app.role', 'guardian'], ['app.user_id', ids.dad]]],
    ['app_owner as a child', URL_OWNER, [['app.role', 'child'], ['app.child_id', ids.kidA]]],
    ['app_owner as system (how the pre-0047 scripts had to read)', URL_OWNER, [['app.role', 'system']]],
  ];
  for (const [name, url, setup] of callers) {
    const m = await viewOf(url, setup);
    check('C true counts', `${name}: every counter equals the truth`, fmt(m), fmt(truth));
  }

  // ---- D · aggregate-only: no rows for the monitor, no widening for families
  {
    const mon = await open(URL_MON);
    try {
      const denied = async (sql) => {
        try { await mon.query(sql); return 'allowed'; }
        catch (e) { return e.code === '42501' ? 'denied' : `error ${e.code}`; }
      };
      for (const t of ['delivery_intent', 'media_artifact', 'guardianship', 'message_log', 'child', 'app_user',
                       'orphan_risk', 'retention_breach']) {
        check('D monitor reads no rows', `SELECT ... FROM ${t} is denied`, await denied(`SELECT * FROM ${t} LIMIT 1`), 'denied');
      }
      const direct = await mon.query(`SELECT * FROM health_counts()`);
      check('D monitor reads no rows', 'health_counts() called directly returns only the five aggregate columns',
        direct.fields.map((f) => f.name).join(','), 'check_name,severity,observed,threshold,meaning');
      await mon.query(`SELECT set_config('app.health_probe','on',false)`);
      await mon.query(`SELECT set_config('app.role','system',false)`);
      check('D monitor reads no rows', 'raising app.health_probe / app.role does not open a table',
        await denied(`SELECT * FROM delivery_intent LIMIT 1`), 'denied');
      const w = (await mon.query(`SELECT has_table_privilege('${MON}','health_check','SELECT') AS v`)).rows[0].v;
      check('D monitor reads no rows', 'it does hold SELECT on health_check', w, true);
      const Q2 = await open(URL_ADMIN);
      const nTab = (await Q2.query(
        `SELECT count(*)::int n FROM information_schema.role_table_grants WHERE grantee=$1 AND table_catalog=$2
            AND NOT (table_name='health_check' AND privilege_type='SELECT')`, [MON, DB])).rows[0].n;
      await Q2.end();
      check('D monitor reads no rows', 'health_check SELECT is its only table grant (no base table, no row-level view)', nTab, 0);
    } finally { await mon.end(); }

    // A guardian session as app_owner: the probe flag is back to its prior value after the read,
    // and the tables are still edge-scoped (only her own family's intents).
    const g = await open(URL_OWNER);
    try {
      await g.query('BEGIN');
      await g.query(`SELECT set_config('app.role','guardian',true), set_config('app.user_id',$1,true)`, [ids.dad]);
      const before = (await g.query(`SELECT count(*)::int n FROM delivery_intent`)).rows[0].n;
      await g.query(`SELECT * FROM health_check`);
      const flag = (await g.query(`SELECT coalesce(current_setting('app.health_probe', true),'') v`)).rows[0].v;
      const after = (await g.query(`SELECT count(*)::int n FROM delivery_intent`)).rows[0].n;
      check('D family scope intact', 'app.health_probe is back to off after health_check', flag, '');
      check('D family scope intact', 'a guardian still sees only her own family (4 of 6 intents), before and after',
        `${before}/${after}`, '4/4');
      await g.query(`SELECT set_config('app.health_probe','on',true)`);
      await g.query(`SELECT * FROM health_check`);
      const nested = (await g.query(`SELECT current_setting('app.health_probe', true) v`)).rows[0].v;
      check('D family scope intact', 'called while already on (re-entrant) it leaves the flag on', nested, 'on');
      await g.query('ROLLBACK');

      const p = (await g.query(
        `SELECT proconfig FROM pg_proc WHERE proname='health_counts'`)).rows[0].proconfig;
      check('D family scope intact', 'health_counts() stores only search_path in proconfig (no custom GUC)',
        (p ?? []).every((x) => x.startsWith('search_path=')), true);
      const noRole = (await g.query(`SELECT count(*)::int n FROM delivery_intent`)).rows[0].n;
      check('D family scope intact', 'app_owner with no role still reads zero rows of delivery_intent (FORCE RLS holds)', noRole, 0);
    } finally { await g.end(); }
  }

  // ---- E · health_alert in the production shape ----------------------------
  {
    // Fixture-free database for this one: the whole-DB "all clear" case needs zero everywhere,
    // so clear what this suite seeded (log rows are append-only: triggers off, as the owner would).
    const A2 = await open(URL_ADMIN);
    try {
      await A2.query(`ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete`);
      await A2.query(`DELETE FROM message_log WHERE child_id IN ($1,$2)`, [ids.kidA, ids.kidB]);
      await A2.query(`ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete`);
      await A2.query(`DELETE FROM reap_tombstone`);
      await A2.query(`DELETE FROM delivery_intent`);
      await A2.query(`DELETE FROM media_artifact`);
      await A2.query(`DELETE FROM guardianship`);
      await A2.query(`DELETE FROM child`);
      await A2.query(`DELETE FROM app_user`);
    } finally { await A2.end(); }

    const r = await runNode([join(here, 'health_alert.test.mjs')],
      { DATABASE_URL: URL_OWNER, ADMIN_DATABASE_URL: URL_ADMIN });
    const m = /^(\d+) passed, (\d+) failed$/m.exec(r.out);
    check('E health_alert', 'health_alert.test.mjs passes on the app_owner-migrated database (superuser seeds, app_owner reads)',
      m ? `${m[1]} passed, ${m[2]} failed` : `exit ${r.code}: ${(r.err || r.out).slice(-300)}`, '10 passed, 0 failed');
    check('E health_alert', 'and it ran the all-clear case too (nothing SKIPped)', r.out.includes('SKIP'), false);

    // Breach, seen by the monitoring login alone.
    const A3 = await open(URL_ADMIN);
    try {
      await A3.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [ids.dad]);
      await A3.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'KidA','2016-04-02','America/New_York')`, [ids.kidA]);
      await A3.query(`INSERT INTO media_artifact (id, child_id, author_id, kind, storage_key, duration_ms, captured_at, captured_tz, expires_at)
                      VALUES ('cccccccc-0000-0000-0000-0000000000f1',$1,$2,'video_msg','hv/f1',5000,now(),'America/New_York', now() + interval '5 days')`, [ids.kidA, ids.dad]);
      await A3.query(`INSERT INTO delivery_intent (id, child_id, sender_id, payload_kind, payload_ref, policy,
                        target_local_date, target_daypart, state, expires_at)
                      VALUES ('dddddddd-0000-0000-0000-0000000000f1',$1,$2,'e2e_video','cccccccc-0000-0000-0000-0000000000f1',
                              'on_local_date', current_date + 40,'bedtime','pending', now() + interval '60 days')`, [ids.kidA, ids.dad]);
    } finally { await A3.end(); }
    const al = await runNode([join(scaffold, 'tools', 'health-alert.mjs')], { HEALTH_DATABASE_URL: URL_MON, DATABASE_URL: '' });
    check('E health_alert', 'health-alert.mjs as health_monitor (HEALTH_DATABASE_URL) exits non-zero on the breach', al.code !== 0 && al.code !== 2, true);
    check('E health_alert', 'and names orphan_risk with count=1', /check_name=orphan_risk[^\n]*count=1/.test(al.err) || (al.err.includes('check_name=orphan_risk') && al.err.includes('count=1')), true);
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
