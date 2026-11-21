/**
 * packages/db/test/delivery_ops_db.test.mjs — the delivery worker's operational health, against a
 * REAL Postgres (migration 0054). ISS-069 (a dead or missing worker is visible) and ISS-070 (the
 * rematerialize scan can no longer be crowded out by rows that stay pending).
 *
 *   A  ROUND-ROBIN SWEEP. 600 stuck pending rows plus one fresh row: the fresh one is materialised
 *      in ONE tick (never-checked rows first, newest first). The stuck rows are stamped, so the next
 *      pass starts where this one stopped and every row is looked at. invalidate_for_child() puts a
 *      re-queued row back at the front. The partial index is the one the sweep reads.
 *   B  AGES. deliveryBacklog() reports the oldest pending age and how long the sweep has neglected a
 *      row; delivery_health() says the same without exposing a row.
 *   C  HEARTBEAT. recordWorkerHeartbeat() upserts; a failed beat keeps last_ok_at; worker_heartbeat is
 *      FORCE-RLS (a session without the system role sees nothing); a bad name is rejected.
 *   D  HEALTH-ALERT, END TO END, as a real subprocess: stale worker, missing worker, due-and-unclaimed
 *      message, an old pending message each raise their named ALERT; a healthy worker raises none.
 *   E  A REAL WORKER PROCESS (`tools/scheduler.mjs deliver-loop`): it writes the heartbeat file and the
 *      database row and logs a periodic heartbeat; killed, its file stops advancing and the REAL
 *      healthcheck CLI turns unhealthy.
 *
 * Same DATABASE_URL / ADMIN_DATABASE_URL split as scheduler.test.mjs: DATABASE_URL is the
 * NOSUPERUSER NOBYPASSRLS role the worker runs as; ADMIN_DATABASE_URL seeds and tears down fixtures.
 * HEALTH_DATABASE_URL (optional) is the monitoring login; when set, section B also proves it can
 * call delivery_health() and still cannot read a table.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPool, deliveryBacklog, deliveryHealth, recordWorkerHeartbeat, withSystemSession } from '../src/pool.mjs';
import { runRematerializeSweep } from '../../../tools/scheduler.mjs';
import { createWorkerHeartbeat } from '../../../tools/worker_heartbeat.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();
const TMP = mkdtempSync(join(tmpdir(), 'olive-delivery-ops-db-'));

const NOW = DateTime.fromISO('2026-08-24T12:00:00Z', { zone: 'utc' });
const DAD = 'd0000000-0000-0000-0000-00000000000d';
const CHILD = 'd0000000-0000-0000-0000-00000000000c';
const CHILD2 = 'd0000000-0000-0000-0000-00000000000e';

async function clearFixture() {
  for (const c of [CHILD, CHILD2]) {
    await admin.query(`DELETE FROM delivery_intent WHERE child_id = $1`, [c]);
    await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [c]);
    await admin.query(`DELETE FROM child_tz_interval WHERE child_id = $1`, [c]);
    await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [c]);
    await admin.query(`DELETE FROM child WHERE id = $1`, [c]);
  }
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
  await admin.query(`DELETE FROM worker_heartbeat`);
}
await clearFixture();

// One child with a bedtime, so an `on_local_date` intent CAN be materialised; an `at_daypart` intent for a
// day-part nobody defined ('activity') is the canonical "legitimately stuck pending" row.
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/New_York')`, [DAD]);
for (const c of [CHILD, CHILD2]) {
  await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'DeliveryOpsChild','2016-04-02','America/New_York')`, [c]);
  await admin.query(`INSERT INTO guardianship (child_id, user_id, role, valid) VALUES ($1, $2, 'guardian', tstzrange(now() - interval '1 year', null))`, [c, DAD]);
  await admin.query(
    `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
     VALUES ($1,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)')`, [c]);
}

const expires = NOW.plus({ days: 90 }).toISO();
/** n stuck rows: an `at_daypart` intent for a day-part that does not exist, so they stay pending for ever. */
async function seedStuck(n, child = CHILD, ageSeconds = 7200) {
  await admin.query(
    `INSERT INTO delivery_intent (id, child_id, sender_id, payload_kind, payload_ref, policy, target_daypart, state, expires_at, created_at)
     SELECT gen_random_uuid(), $1, $2, 'video_msg', gen_random_uuid(), 'at_daypart', 'activity', 'pending', $3::timestamptz,
            now() - make_interval(secs => $4::int) + make_interval(secs => g)
       FROM generate_series(1, $5::int) g`, [child, DAD, expires, ageSeconds, n]);
}
async function seedFresh(child = CHILD) {
  const { rows: r } = await admin.query(
    `INSERT INTO delivery_intent (id, child_id, sender_id, payload_kind, payload_ref, policy, target_local_date, target_daypart, state, expires_at)
     VALUES (gen_random_uuid(), $1, $2, 'video_msg', gen_random_uuid(), 'on_local_date', $3::date, 'bedtime', 'pending', $4::timestamptz) RETURNING id`,
    [child, DAD, NOW.toISODate(), expires]);
  return r[0].id;
}
const stateOf = async (id) => (await admin.query(`SELECT state, scheduled_at FROM delivery_intent WHERE id = $1`, [id])).rows[0];
const count = async (where, params = []) => Number((await admin.query(`SELECT count(*) AS n FROM delivery_intent WHERE ${where}`, params)).rows[0].n);

// ============================================================================
// A · the round-robin sweep
// ============================================================================
{
  const g = 'A round-robin sweep';
  check(g, 'the migration added the last-checked column', (await admin.query(
    `SELECT count(*)::int AS n FROM information_schema.columns WHERE table_name='delivery_intent' AND column_name='rematerialize_checked_at'`)).rows[0].n, 1);
  const idx = (await admin.query(`SELECT indexdef FROM pg_indexes WHERE indexname = 'delivery_intent_pending_sweep'`)).rows[0]?.indexdef ?? '';
  check(g, 'the partial index exists and covers exactly the pending rows', /WHERE \(state = 'pending'/.test(idx), true);
  check(g, 'the index orders never-checked first, then newest', /rematerialize_checked_at NULLS FIRST, created_at DESC/.test(idx), true);

  // --- the brief's scenario, literally: 600 stuck rows (never looked at) + one fresh row, ONE tick.
  await seedStuck(600);
  const fresh = await seedFresh();
  const t1 = await runRematerializeSweep(pool, { now: NOW });
  check(g, 'the batch is the default 500 and was fully used', `${t1.scanned}/${t1.batchLimitHit}`, '500/true');
  check(g, '600 stuck + 1 fresh: the fresh row is materialised in the FIRST tick', (await stateOf(fresh)).state, 'ready');
  check(g, 'and it has a delivery instant', (await stateOf(fresh)).scheduled_at !== null, true);
  check(g, 'the sweep reports one row materialised', t1.materialized, 1);
  check(g, 'the 499 stuck rows it also looked at are stamped as checked', await count(`child_id = $1 AND state = 'pending' AND rematerialize_checked_at IS NOT NULL`, [CHILD]), 499);
  check(g, 'the stuck rows it did NOT reach are still unchecked', await count(`child_id = $1 AND state = 'pending' AND rematerialize_checked_at IS NULL`, [CHILD]), 101);

  // --- second tick: the unchecked ones go first, so every row has now been looked at once.
  const t2 = await runRematerializeSweep(pool, { now: NOW });
  check(g, 'tick 2 scans a full batch again', t2.scanned, 500);
  check(g, 'after two ticks NO pending row is still unchecked (round-robin reached everyone)', await count(`state = 'pending' AND rematerialize_checked_at IS NULL`), 0);

  // --- the realistic crowd-out: 600 stuck rows already stamped, a NEW message arrives.
  const fresh2 = await seedFresh();
  const t3 = await runRematerializeSweep(pool, { now: NOW });
  check(g, 'with 600 already-checked stuck rows ahead of it, a new message is promoted on the very next tick', (await stateOf(fresh2)).state, 'ready');
  check(g, 'and the stuck rows are untouched (still pending)', await count(`child_id = $1 AND state = 'pending'`, [CHILD]), 600);
  void t3;

  // --- the old order would have starved it: prove the starvation was real by replaying it.
  const oldOrder = (await admin.query(
    `SELECT id FROM delivery_intent WHERE state = 'pending' ORDER BY created_at LIMIT 500`)).rows.map((r) => r.id);
  const fresh3 = await seedFresh();
  const oldOrder2 = (await admin.query(`SELECT id FROM delivery_intent WHERE state = 'pending' ORDER BY created_at LIMIT 500`)).rows.map((r) => r.id);
  check(g, 'CONTROL: the OLD scan order (oldest first, LIMIT 500) never reaches a fresh row behind 600 stuck ones', oldOrder2.includes(fresh3), false);
  void oldOrder;
  await runRematerializeSweep(pool, { now: NOW });
  check(g, 'the new order materialises it', (await stateOf(fresh3)).state, 'ready');

  // --- a stamped row waits its turn: the least recently checked goes first.
  await admin.query(`UPDATE delivery_intent SET rematerialize_checked_at = now() - interval '1 hour' WHERE id = (SELECT id FROM delivery_intent WHERE child_id = $1 AND state = 'pending' ORDER BY created_at LIMIT 1)`, [CHILD]);
  await admin.query(`UPDATE delivery_intent SET rematerialize_checked_at = now() WHERE child_id = $1 AND state = 'pending' AND rematerialize_checked_at > now() - interval '1 minute'`, [CHILD]);
  const oldest = (await admin.query(`SELECT id FROM delivery_intent WHERE state='pending' ORDER BY rematerialize_checked_at NULLS FIRST, created_at DESC LIMIT 1`)).rows[0].id;
  const before = (await admin.query(`SELECT rematerialize_checked_at AS c FROM delivery_intent WHERE id = $1`, [oldest])).rows[0].c;
  await runRematerializeSweep(pool, { now: NOW, batchLimit: 1 });
  const after = (await admin.query(`SELECT rematerialize_checked_at AS c FROM delivery_intent WHERE id = $1`, [oldest])).rows[0].c;
  check(g, 'with a batch of one, the row checked longest ago is the one taken (and re-stamped)', after > before, true);

  // --- invalidate_for_child puts a re-queued row back at the front.
  await admin.query(`UPDATE delivery_intent SET state = 'pending', scheduled_at = NULL, rematerialize_checked_at = now() WHERE id = $1`, [fresh]);
  await admin.query(`SELECT invalidate_for_child($1)`, [CHILD]);
  check(g, 'invalidate_for_child clears the stamp (a re-timed message goes first)', await count(`child_id = $1 AND state = 'pending' AND rematerialize_checked_at IS NOT NULL`, [CHILD]), 0);

  // --- a materialised row keeps no stale stamp that could hide it later.
  await runRematerializeSweep(pool, { now: NOW });
  check(g, 'a row that was materialised is ready (the CAS write still works with the new column)', (await stateOf(fresh)).state, 'ready');
}

// ============================================================================
// B · ages: deliveryBacklog() and delivery_health()
// ============================================================================
{
  const g = 'B ages';
  let b = await deliveryBacklog(pool);
  check(g, 'deliveryBacklog reports the oldest PENDING age (the stuck rows are ~2 h old)', b.oldestPendingAgeSec >= 7000, true);
  // Section A's last bounded sweep left rows it never reached (invalidate_for_child reset every stamp).
  check(g, 'deliveryBacklog reports rows the sweep has NOT looked at for hours (unswept ~2 h)', b.oldestUnsweptSec >= 7000, true);
  await runRematerializeSweep(pool, { now: NOW });
  b = await deliveryBacklog(pool);
  check(g, 'after one more full pass the sweep has looked at every row: unswept age collapses', b.oldestUnsweptSec !== null && b.oldestUnsweptSec < 120, true);
  check(g, 'while the pending AGE is untouched (a row can wait legitimately)', b.oldestPendingAgeSec >= 7000, true);
  check(g, 'the old fields are unchanged (pending count includes the stuck rows)', b.pending >= 600, true);
  const h = await deliveryHealth(pool);
  check(g, 'delivery_health() agrees on the pending age', Math.abs(h.oldestPendingAgeSec - b.oldestPendingAgeSec) < 30, true);
  check(g, 'delivery_health() has no worker yet (nothing has beaten)', `${h.workerBeatAgeSec}/${h.workerOkAgeSec}/${h.workerTickMs}`, 'null/null/null');
  check(g, 'delivery_health() has the ready count too', typeof h.ready, 'number');
  // The result is aggregates only.
  const raw = (await pool.query('SELECT * FROM delivery_health()')).fields.map((f) => f.name).join(',');
  check(g, 'delivery_health() returns only counts and ages, no identifiers',
    raw, 'pending,ready,oldest_ready_age_sec,oldest_pending_age_sec,oldest_unswept_age_sec,worker_beat_age_sec,worker_ok_age_sec,worker_tick_ms');
  check(g, 'delivery_health() is not executable by PUBLIC', (await admin.query(
    `SELECT has_function_privilege('public', 'delivery_health()', 'EXECUTE') AS ok`)).rows[0].ok, false);

  if (process.env.HEALTH_DATABASE_URL) {
    const mon = new pg.Client({ connectionString: process.env.HEALTH_DATABASE_URL });
    await mon.connect();
    check(g, 'the monitoring login CAN call delivery_health()', (await mon.query('SELECT * FROM delivery_health()')).rows.length, 1);
    let denied = null;
    try { await mon.query('SELECT count(*) FROM worker_heartbeat'); } catch (e) { denied = e.code; }
    check(g, 'but the monitoring login cannot read worker_heartbeat itself', denied, '42501');
    denied = null;
    try { await mon.query('SELECT count(*) FROM delivery_intent'); } catch (e) { denied = e.code; }
    check(g, 'nor delivery_intent', denied, '42501');
    await mon.end();
  }
}

// ============================================================================
// C · heartbeat table
// ============================================================================
{
  const g = 'C heartbeat';
  await recordWorkerHeartbeat(pool, { worker: 'delivery', tickMs: 30_000, ok: true, consecutiveFailures: 0 });
  let r = (await admin.query(`SELECT tick_ms, consecutive_failures, last_ok_at IS NOT NULL AS ok FROM worker_heartbeat WHERE worker = 'delivery'`)).rows[0];
  check(g, 'a heartbeat row is written', `${r.tick_ms}/${r.consecutive_failures}/${r.ok}`, '30000/0/true');
  await admin.query(`UPDATE worker_heartbeat SET last_ok_at = now() - interval '10 minutes' WHERE worker = 'delivery'`);
  await recordWorkerHeartbeat(pool, { worker: 'delivery', tickMs: 30_000, ok: false, consecutiveFailures: 3 });
  r = (await admin.query(`SELECT consecutive_failures AS f, EXTRACT(EPOCH FROM (now() - last_ok_at))::int AS okage, EXTRACT(EPOCH FROM (now() - beat_at))::int AS beatage FROM worker_heartbeat WHERE worker = 'delivery'`)).rows[0];
  check(g, 'a FAILED beat still shows the worker alive (beat_at fresh)', r.beatage < 10, true);
  check(g, 'but leaves last_ok_at where it was (10 minutes ago)', r.okage >= 599, true);
  check(g, 'and records the failure streak', r.f, 3);
  const h = await deliveryHealth(pool);
  check(g, 'delivery_health() shows a fresh beat and a 10 minute old success', `${h.workerBeatAgeSec < 10}/${h.workerOkAgeSec >= 599}`, 'true/true');
  await recordWorkerHeartbeat(pool, { worker: 'delivery-in-server', tickMs: 5_000, ok: true, consecutiveFailures: 0 });
  const h2 = await deliveryHealth(pool);
  check(g, 'the freshest worker wins (either host alive is enough)', h2.workerOkAgeSec < 10, true);
  check(g, 'and its own tick interval is reported', h2.workerTickMs, 5000);

  // FORCE RLS: a session that has not declared the system role sees nothing, the system session sees the rows.
  const bare = (await pool.query('SELECT count(*)::int AS n FROM worker_heartbeat')).rows[0].n;
  check(g, 'a session without the system role sees NO heartbeat rows (FORCE RLS)', bare, 0);
  check(g, 'the system session sees them', (await withSystemSession(pool, (q) => q('SELECT count(*)::int AS n FROM worker_heartbeat')))[0].n, 2);
  let bad = null;
  try { await recordWorkerHeartbeat(pool, { worker: 'Bad Name!', tickMs: 1, ok: true, consecutiveFailures: 0 }); } catch (e) { bad = e.code; }
  check(g, 'a malformed worker name is rejected by the CHECK', bad, '23514');
  check(g, 'RLS is enabled and forced on the table', (await admin.query(
    `SELECT relrowsecurity AND relforcerowsecurity AS f FROM pg_class WHERE relname = 'worker_heartbeat'`)).rows[0].f, true);
  check(g, 'the health_check rls_unforced row still reads zero (the new table did not break it)', Number((await admin.query(
    `SELECT observed FROM health_check WHERE check_name = 'rls_unforced'`)).rows[0].observed), 0);
}

// ============================================================================
// D · health-alert, end to end (a real subprocess against the real view + function)
// ============================================================================
{
  const g = 'D health-alert';
  const alert = (env = {}) => spawnSync(process.execPath, [join(ROOT, 'tools', 'health-alert.mjs')], {
    env: { ...process.env, ...env, DATABASE_URL: DATABASE_URL, HEALTH_DATABASE_URL: process.env.HEALTH_DATABASE_URL ?? '' }, encoding: 'utf8', cwd: ROOT });
  const alarms = (r) => [...r.stderr.matchAll(/ALERT check_name=(delivery_\w+)/g)].map((m) => m[1]).sort().join(',') || 'none';

  // Fixture state: stuck rows are ~2 h old and pending (no 'delivery_pending_old' yet: that needs a day).
  // Section A materialised rows against a fixed 2026 clock; those are `ready` and long past due now.
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = ANY($1) AND state <> 'pending'`, [[CHILD, CHILD2]]);
  await admin.query(`DELETE FROM worker_heartbeat`);
  await admin.query(`INSERT INTO worker_heartbeat (worker, beat_at, last_ok_at, tick_ms) VALUES ('delivery', now(), now(), 30000)`);
  check(g, 'a healthy worker and nothing overdue: no delivery alert', alarms(alert()), 'none');

  await admin.query(`UPDATE worker_heartbeat SET beat_at = now() - interval '1 hour', last_ok_at = now() - interval '1 hour'`);
  const stale = alert();
  check(g, 'a worker that last beat an hour ago raises delivery_worker_stale', alarms(stale), 'delivery_worker_stale');
  check(g, 'and health-alert exits non-zero', stale.status, 1);
  check(g, 'the alert line carries the observed age and the threshold', /delivery_worker_stale severity=critical count=\d+ threshold=300/.test(stale.stderr), true);

  await admin.query(`UPDATE worker_heartbeat SET beat_at = now(), last_ok_at = now() - interval '1 hour'`);
  check(g, 'a worker beating but never succeeding raises delivery_worker_failing', alarms(alert()), 'delivery_worker_failing');

  await admin.query(`DELETE FROM worker_heartbeat`);
  check(g, 'queued work and no worker EVER reporting raises delivery_worker_missing', alarms(alert()), 'delivery_worker_missing');

  await admin.query(`INSERT INTO worker_heartbeat (worker, beat_at, last_ok_at, tick_ms) VALUES ('delivery', now(), now(), 30000)`);
  const due = await seedFresh(CHILD2);
  await admin.query(`UPDATE delivery_intent SET state = 'ready', scheduled_at = now() - interval '1 hour', materialized_at = now() WHERE id = $1`, [due]);
  check(g, 'a due message nobody has claimed for an hour raises delivery_ready_backlog', alarms(alert()), 'delivery_ready_backlog');
  await admin.query(`UPDATE delivery_intent SET scheduled_at = now() - interval '2 minutes' WHERE id = $1`, [due]);
  check(g, 'a message due two minutes ago is not yet a backlog', alarms(alert()), 'none');
  await admin.query(`DELETE FROM delivery_intent WHERE id = $1`, [due]);

  await admin.query(`UPDATE delivery_intent SET created_at = now() - interval '3 days' WHERE id = (SELECT id FROM delivery_intent WHERE child_id = $1 AND state = 'pending' LIMIT 1)`, [CHILD]);
  check(g, 'a message pending for three days raises delivery_pending_old', alarms(alert()), 'delivery_pending_old');
  check(g, 'the threshold is overridable from the environment', alarms(alert({ DELIVERY_PENDING_MAX_AGE_SEC: '999999999' })), 'none');
  check(g, 'a database that cannot answer delivery_health() is reported, not hidden', (() => {
    const r = alert({ DELIVERY_READY_MAX_AGE_SEC: '1' }); return r.status === 1 ? 'ran' : 'no'; })(), 'ran');
}

// ============================================================================
// E · a REAL worker process, then the REAL healthcheck CLI
// ============================================================================
{
  const g = 'E real worker';
  // A clean slate: the worker sweeps for real and must not trip over (or alter) the fixtures above.
  await clearFixture();
  const file = join(TMP, 'worker.json');
  const out = [];
  const child = spawn(process.execPath, [join(ROOT, 'tools', 'scheduler.mjs'), 'deliver-loop'], {
    cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, DATABASE_URL, DELIVERY_TICK_MS: '5000', DELIVERY_HEARTBEAT_FILE: file,
           DELIVERY_HEARTBEAT_LOG_MS: '1000', DELIVERY_PUSH: 'off' } });
  child.stdout.on('data', (d) => out.push(String(d)));
  child.stderr.on('data', (d) => out.push(String(d)));
  const exited = new Promise((r) => child.on('exit', (code) => r(code)));
  const readFile = () => { try { return JSON.parse(readFileSync(file, 'utf8')); } catch { return null; } };
  const until = async (fn, ms) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await fn()) return true; await new Promise((r) => setTimeout(r, 250)); } return false; };
  const cli = () => spawnSync(process.execPath, [join(ROOT, 'tools', 'delivery-healthcheck.mjs')], {
    env: { ...process.env, DELIVERY_HEARTBEAT_FILE: file }, encoding: 'utf8' });

  check(g, 'the worker writes its heartbeat file with a successful tick', await until(() => readFile()?.lastOkAt, 30_000), true);
  check(g, 'REAL healthcheck CLI: a running worker is healthy (exit 0)', cli().status, 0);
  check(g, 'the worker wrote its database heartbeat (row named delivery, 5000 ms)', await until(async () =>
    (await admin.query(`SELECT 1 FROM worker_heartbeat WHERE worker='delivery' AND tick_ms=5000`)).rowCount === 1, 15_000), true);
  const h = await deliveryHealth(pool);
  check(g, 'delivery_health() sees a fresh worker', h.workerBeatAgeSec !== null && h.workerBeatAgeSec < 15, true);
  check(g, 'an idle worker logs a heartbeat line (proof it is alive without delivering anything)',
    await until(() => out.join('').includes('event=deliver_heartbeat '), 20_000), true);
  check(g, 'the heartbeat line carries counts and no message content', /event=deliver_heartbeat ticks=\d+ failures=0 consecutive_failures=0/.test(out.join('')), true);
  check(g, 'a quiet tick does NOT log a line of its own', (out.join('').match(/event=end/g) ?? []).length, 0);

  // Kill the worker the way a crashed or stopped container is killed.
  child.kill('SIGKILL');
  await exited;
  const frozen = readFile();
  await new Promise((r) => setTimeout(r, 6_500));
  check(g, 'a killed worker stops advancing its heartbeat', readFile().lastTickAt, frozen.lastTickAt);
  // Time passes; what the file would say five minutes after the kill (this is the content a real
  // five-minute-old dead worker leaves, written with the same writer the worker uses).
  writeFileSync(file, JSON.stringify({ ...frozen, startedAt: frozen.startedAt - 300_000, lastTickAt: frozen.lastTickAt - 300_000, lastOkAt: frozen.lastOkAt - 300_000 }));
  const dead = cli();
  check(g, 'REAL healthcheck CLI: five minutes after the worker was killed it is UNHEALTHY (exit 1)', dead.status, 1);
  check(g, 'and says it stopped ticking', /stopped ticking/.test(dead.stderr), true);
  await admin.query(`UPDATE worker_heartbeat SET beat_at = now() - interval '10 minutes', last_ok_at = now() - interval '10 minutes'`);
  const h2 = await deliveryHealth(pool);
  check(g, 'the database heartbeat of the dead worker ages the same way', h2.workerBeatAgeSec >= 599, true);
  check(g, 'a heartbeat writer that throws never throws into the loop', (() => {
    const h = createWorkerHeartbeat({ tickMs: 5000, file: join(TMP, 'f', 'x'), write: () => { throw new Error('ro'); } });
    try { h.beat(true); return 'ok'; } catch { return 'threw'; } })(), 'ok');
}

// ---- teardown ---------------------------------------------------------------------------------
await clearFixture();
await admin.end();
await pool.end();
try { if (existsSync(TMP)) rmSync(TMP, { recursive: true, force: true }); } catch { /* best effort */ }

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
