/**
 * Delivery worker operations, pure (no database): ISS-069 (a dead or missing worker is visible),
 * ISS-071 (the heartbeat log and the runbook), ISS-074 (PORT and database URL checks at boot).
 * The real-database half (round-robin sweep, delivery_health(), a real worker process) is
 * packages/db/test/delivery_ops_db.test.mjs.
 *
 *   A  heartbeat arithmetic and the healthcheck CLI (a stopped worker is unhealthy)
 *   B  the worker loop itself: heartbeat file every tick, periodic log, watchdog exit
 *   C  delivery_health_lib alarms (what health-alert raises, and when)
 *   D  PORT and DATABASE_URL checks, and the REAL server process refusing to boot on PORT=abc
 *   E  the server's watch on a worker it does not host (the boot warning)
 *   F  readiness reports a sweep that stopped looking at waiting messages
 *   G  compose contract: a compose file can never have both delivery paths off
 *   H  the runbook no longer says things that cannot be true
 */
import { readFileSync, mkdtempSync, writeFileSync, rmSync, existsSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  staleAfterMs, evaluateHeartbeat, watchdogVerdict, createWorkerHeartbeat, writeHeartbeatFile,
  readHeartbeatFile, heartbeatFileFromEnv, heartbeatLogMsFromEnv, heartbeatLogFields,
} from '../../tools/worker_heartbeat.mjs';
import { deliveryAlarms, deliveryThresholds } from '../../tools/delivery_health_lib.mjs';
import { checkBootPort, databaseUrlProblem } from '../boot_config.mjs';
import {
  createWorkerWatch, judgeWorkerHeartbeat, heartbeatStaleAfterSec, missingWorkerWarning,
  WATCH_FIRST_CHECK_MS,
} from '../delivery_watch.mjs';
import { checkReadiness } from '../readiness.mjs';
import { deliverLoop } from '../../tools/scheduler.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const TMP = mkdtempSync(join(tmpdir(), 'olive-delivery-ops-'));
const keepAlive = setInterval(() => {}, 1000);

// ---- A · heartbeat arithmetic + the healthcheck CLI --------------------------------------------
{
  const g = 'A heartbeat';
  check(g, 'stale limit: never under 90 s', staleAfterMs(5_000), 90_000);
  check(g, 'stale limit: the default 30 s tick gives 120 s (four ticks)', staleAfterMs(30_000), 120_000);
  check(g, 'stale limit: a slow 5 minute tick scales it', staleAfterMs(300_000), 1_200_000);
  check(g, 'stale limit: garbage falls back to the 30 s default', staleAfterMs('x'), 120_000);
  const T = 1_000_000_000_000;
  const fresh = { startedAt: T - 500_000, lastTickAt: T - 10_000, lastOkAt: T - 10_000, tickMs: 30_000, consecutiveFailures: 0 };
  check(g, 'a worker that ticked 10 s ago is healthy', evaluateHeartbeat(fresh, T).healthy, true);
  check(g, 'a worker that last ticked 5 minutes ago is UNHEALTHY (stopped)',
    evaluateHeartbeat({ ...fresh, lastTickAt: T - 300_000, lastOkAt: T - 300_000 }, T).healthy, false);
  check(g, 'the reason says it stopped ticking',
    /stopped ticking/.test(evaluateHeartbeat({ ...fresh, lastTickAt: T - 300_000, lastOkAt: T - 300_000 }, T).reason), true);
  check(g, 'a worker that ticks but has not SUCCEEDED for 5 minutes is UNHEALTHY (failing)',
    evaluateHeartbeat({ ...fresh, lastOkAt: T - 300_000, consecutiveFailures: 10 }, T).healthy, false);
  check(g, 'the reason names the failure streak',
    /10 failures in a row/.test(evaluateHeartbeat({ ...fresh, lastOkAt: T - 300_000, consecutiveFailures: 10 }, T).reason), true);
  check(g, 'a worker that just started (no tick yet) is healthy',
    evaluateHeartbeat({ startedAt: T - 5_000, lastTickAt: null, lastOkAt: null, tickMs: 30_000, consecutiveFailures: 0 }, T).healthy, true);
  check(g, 'a worker that started 10 minutes ago and never ticked is UNHEALTHY',
    evaluateHeartbeat({ startedAt: T - 600_000, lastTickAt: null, lastOkAt: null, tickMs: 30_000, consecutiveFailures: 0 }, T).healthy, false);
  check(g, 'no heartbeat file at all is UNHEALTHY', evaluateHeartbeat(null, T).healthy, false);
  check(g, 'a nonsense file is UNHEALTHY', evaluateHeartbeat({ tickMs: 30_000, lastTickAt: 'x' }, T).healthy, false);

  // The watchdog turns "alive but stuck" into an exit the orchestrator restarts.
  check(g, 'watchdog: a healthy worker is left alone', watchdogVerdict({ ...fresh }, T).exit, false);
  check(g, 'watchdog: 19 failures in a row is not yet fatal', watchdogVerdict({ ...fresh, consecutiveFailures: 19 }, T).exit, false);
  check(g, 'watchdog: 20 failures in a row exits', watchdogVerdict({ ...fresh, consecutiveFailures: 20 }, T).exit, true);
  check(g, 'watchdog: a loop that has not come round for 11 minutes (hung) exits',
    watchdogVerdict({ ...fresh, lastTickAt: T - 660_000 }, T).exit, true);
  check(g, 'watchdog: a slow-cadence worker (5 min tick) is not killed at 11 minutes',
    watchdogVerdict({ ...fresh, tickMs: 300_000, lastTickAt: T - 660_000 }, T).exit, false);

  // tracker + file round trip
  const f = join(TMP, 'hb.json');
  let clock = T;
  const hb = createWorkerHeartbeat({ tickMs: 30_000, file: f, now: () => clock });
  check(g, 'the file exists at start, before any tick', existsSync(f), true);
  check(g, 'at start there has been no tick', readHeartbeatFile(f).lastTickAt, null);
  clock = T + 30_000; hb.beat(true);
  check(g, 'a successful tick is written', readHeartbeatFile(f).lastOkAt, T + 30_000);
  clock = T + 60_000; hb.beat(false);
  const afterFail = readHeartbeatFile(f);
  check(g, 'a failed tick moves lastTickAt but not lastOkAt', `${afterFail.lastTickAt - T}/${afterFail.lastOkAt - T}`, '60000/30000');
  check(g, 'a failed tick counts the streak', afterFail.consecutiveFailures, 1);
  clock = T + 90_000; hb.beat(true);
  check(g, 'a success clears the streak', readHeartbeatFile(f).consecutiveFailures, 0);
  const bad = createWorkerHeartbeat({ tickMs: 30_000, file: join(TMP, 'no', 'dir', 'hb.json'), write: () => { throw new Error('disk'); } });
  check(g, 'an unwritable heartbeat file never throws into the worker', (() => { try { bad.beat(true); return 'ok'; } catch { return 'threw'; } })(), 'ok');
  check(g, 'DELIVERY_HEARTBEAT_FILE overrides the default path', heartbeatFileFromEnv({ DELIVERY_HEARTBEAT_FILE: '/x/y.json' }), '/x/y.json');
  check(g, 'the default log interval is ten minutes', heartbeatLogMsFromEnv({}), 600_000);
  check(g, 'a silly log interval falls back to the default', heartbeatLogMsFromEnv({ DELIVERY_HEARTBEAT_LOG_MS: '3' }), 600_000);
  check(g, 'the heartbeat log carries counts and no content', Object.keys(heartbeatLogFields(hb.snapshot(), T + 100_000)).join(','),
    'ticks,failures,consecutive_failures,last_ok_age_s,uptime_s,tick_ms');

  // The REAL healthcheck CLI, against real files: this is exactly what the compose healthcheck runs.
  const cli = (file, extraEnv = {}) => spawnSync(process.execPath, [join(ROOT, 'tools', 'delivery-healthcheck.mjs')], {
    env: { ...process.env, DELIVERY_HEARTBEAT_FILE: file, ...extraEnv }, encoding: 'utf8' });
  const live = join(TMP, 'live.json');
  const nowMs = Date.now();
  writeHeartbeatFile(live, { startedAt: nowMs - 60_000, lastTickAt: nowMs - 5_000, lastOkAt: nowMs - 5_000, tickMs: 30_000, ticks: 2, failures: 0, consecutiveFailures: 0 });
  check(g, 'CLI: a worker that ticked 5 s ago exits 0', cli(live).status, 0);
  // What a worker that was killed five minutes ago leaves behind.
  const dead = join(TMP, 'dead.json');
  writeHeartbeatFile(dead, { startedAt: nowMs - 900_000, lastTickAt: nowMs - 300_000, lastOkAt: nowMs - 300_000, tickMs: 30_000, ticks: 20, failures: 0, consecutiveFailures: 0 });
  const rDead = cli(dead);
  check(g, 'CLI: a STOPPED worker makes the healthcheck exit 1 (unhealthy)', rDead.status, 1);
  check(g, 'CLI: and says why on stderr', /stopped ticking/.test(rDead.stderr), true);
  const failing = join(TMP, 'failing.json');
  writeHeartbeatFile(failing, { startedAt: nowMs - 900_000, lastTickAt: nowMs - 5_000, lastOkAt: nowMs - 400_000, tickMs: 30_000, ticks: 30, failures: 28, consecutiveFailures: 28 });
  check(g, 'CLI: a worker failing every tick is unhealthy too', cli(failing).status, 1);
  check(g, 'CLI: a missing file is unhealthy', cli(join(TMP, 'absent.json')).status, 1);
}

// ---- B · the worker loop -----------------------------------------------------------------------
{
  const g = 'B worker loop';
  const captured = [];
  const origLog = console.log, origErr = console.error;
  console.log = (...a) => captured.push(a.join(' '));
  console.error = (...a) => captured.push(a.join(' '));
  const beats = [];
  // A pool that cannot reach a database, and one whose system session works (to count the DB heartbeats).
  const fakePool = { connect: async () => { throw new Error('no db in this test'); },
                     query: async () => { throw new Error('no db in this test'); } };
  const sessionPool = {
    connect: async () => ({ query: async (sql, p) => { if (/INSERT INTO worker_heartbeat/.test(sql)) beats.push(p); return { rows: [], rowCount: 0 }; }, release() {} }),
    query: async () => ({ rows: [] }),
  };
  const file = join(TMP, 'loop.json');
  const logEverySleeps = [];
  try {
    // Every tick fails: the loop must (1) keep ticking, (2) keep the file fresh, (3) fire the watchdog at 20.
    let fatal = null;
    await deliverLoop(fakePool, 'unused', {
      tickMs: 30_000, heartbeatFile: file, workerName: 'delivery', heartbeatLogMs: 1000,
      runJob: async () => { throw new Error('db down'); },
      sleep: async () => { logEverySleeps.push(1); await new Promise((r) => setTimeout(r, 8)); },
      watchdogMs: 5, onFatal: (reason) => { fatal = fatal ?? reason; }, maxTicks: 25,
    });
    check(g, 'a loop whose every tick fails keeps running to its tick budget', logEverySleeps.length, 24);
    check(g, 'the heartbeat file records every failed tick', readHeartbeatFile(file).failures, 25);
    check(g, 'the file still carries a fresh lastTickAt after failures (alive, not succeeding)',
      Date.now() - readHeartbeatFile(file).lastTickAt < 5_000, true);
    check(g, 'the file shows NO successful tick', readHeartbeatFile(file).lastOkAt, null);
    check(g, 'the watchdog fired after the failure streak', /consecutive failed ticks/.test(fatal ?? ''), true);
    check(g, 'the watchdog says so in the log', captured.some((l) => /event=deliver_watchdog_exit/.test(l)), true);
    check(g, 'a tick error is logged', captured.some((l) => /event=deliver_tick_error/.test(l)), true);
    check(g, 'a heartbeat that cannot reach the database is logged ONCE, not every tick',
      captured.filter((l) => /event=deliver_heartbeat_write_failed/.test(l)).length, 1);

    // Healthy loop: file fresh, lastOk set, periodic log line appears, no watchdog.
    captured.length = 0; fatal = null;
    const okFile = join(TMP, 'loop-ok.json');
    await deliverLoop(sessionPool, 'unused', {
      tickMs: 30_000, heartbeatFile: okFile, heartbeatLogMs: 1000,
      runJob: async () => ({ ok: true, skipped: false }),
      sleep: async () => { await new Promise((r) => setTimeout(r, 12)); },
      watchdogMs: 5, onFatal: (r) => { fatal = r; }, maxTicks: 150,
    });
    const okData = readHeartbeatFile(okFile);
    check(g, 'a healthy loop leaves lastOkAt set', okData.lastOkAt !== null, true);
    check(g, 'a healthy loop has no failures', okData.failures, 0);
    check(g, 'a healthy loop is judged healthy by the same code the healthcheck uses', evaluateHeartbeat(okData, Date.now()).healthy, true);
    check(g, 'no watchdog exit on a healthy loop', fatal, null);
    check(g, 'the loop writes one database heartbeat per tick, named delivery', `${beats.length}/${beats[0]?.[0]}/${beats[0]?.[1]}/${beats[0]?.[2]}`, '150/delivery/30000/true');
    check(g, 'an IDLE worker still logs a periodic heartbeat line (the runbook step 10 proof)',
      captured.some((l) => /event=deliver_heartbeat( |$)/.test(l) && /ticks=\d+/.test(l)), true);
    check(g, 'the heartbeat line carries counts only', captured.filter((l) => /event=deliver_heartbeat /.test(l)).every((l) => !/child|intent|message=/.test(l)), true);
    check(g, 'a quiet tick itself logs nothing (only start, heartbeat and stop lines)',
      captured.every((l) => /event=(deliver_loop_start|deliver_heartbeat|deliver_loop_stop)/.test(l)), true);

    // A lock-held skip is a healthy tick, not a failure.
    const skipFile = join(TMP, 'loop-skip.json');
    await deliverLoop(sessionPool, 'unused', {
      tickMs: 30_000, heartbeatFile: skipFile, runJob: async () => ({ ok: true, skipped: true }),
      sleep: async () => {}, watchdogMs: 60_000, maxTicks: 3 });
    check(g, 'a skipped tick (another worker holds the lock) counts as ok', readHeartbeatFile(skipFile).consecutiveFailures, 0);
    // runJob returning ok:false is a failed tick.
    const nokFile = join(TMP, 'loop-nok.json');
    await deliverLoop(sessionPool, 'unused', {
      tickMs: 30_000, heartbeatFile: nokFile, runJob: async () => ({ ok: false }),
      sleep: async () => {}, watchdogMs: 60_000, maxTicks: 3 });
    check(g, 'a tick reporting ok:false is a failure', readHeartbeatFile(nokFile).consecutiveFailures, 3);
  } finally { console.log = origLog; console.error = origErr; }
}

// ---- C · delivery_health_lib -------------------------------------------------------------------
{
  const g = 'C alarms';
  const H = (o) => ({ pending: 0, ready: 0, oldestReadyAgeSec: null, oldestPendingAgeSec: null,
    workerBeatAgeSec: 10, workerOkAgeSec: 10, workerTickMs: 30_000, ...o });
  const names = (h, env = {}) => deliveryAlarms(h, env).map((a) => a.checkName).join(',') || 'none';
  check(g, 'a healthy idle system raises nothing', names(H({})), 'none');
  check(g, 'a fresh install (no worker ever, nothing queued) raises nothing', names(H({ workerBeatAgeSec: null, workerOkAgeSec: null })), 'none');
  check(g, 'queued work and NO worker ever is critical (worker missing)',
    names(H({ workerBeatAgeSec: null, workerOkAgeSec: null, oldestPendingAgeSec: 700 })), 'delivery_worker_missing');
  check(g, 'queued work 5 minutes old with no worker is still within grace', names(H({ workerBeatAgeSec: null, workerOkAgeSec: null, oldestPendingAgeSec: 300 })), 'none');
  check(g, 'a worker whose last beat is 20 minutes old is stale',
    names(H({ workerBeatAgeSec: 1200, workerOkAgeSec: 1200 })), 'delivery_worker_stale');
  check(g, 'a worker beating but never succeeding is failing', names(H({ workerOkAgeSec: null })), 'delivery_worker_failing');
  check(g, 'a worker beating whose last success is 20 minutes old is failing', names(H({ workerOkAgeSec: 1200 })), 'delivery_worker_failing');
  check(g, 'a due message unclaimed for 16 minutes is a backlog', names(H({ oldestReadyAgeSec: 960 })), 'delivery_ready_backlog');
  check(g, 'a due message unclaimed for 14 minutes is not yet', names(H({ oldestReadyAgeSec: 840 })), 'none');
  check(g, 'a message pending for 25 hours is old', names(H({ oldestPendingAgeSec: 90_000 })), 'delivery_pending_old');
  check(g, 'a message pending for 23 hours is not', names(H({ oldestPendingAgeSec: 82_800 })), 'none');
  check(g, 'a slow-cadence worker (5 min tick) is allowed 50 minutes between beats', names(H({ workerBeatAgeSec: 2400, workerOkAgeSec: 2400, workerTickMs: 300_000 })), 'none');
  check(g, 'thresholds are overridable by env', names(H({ oldestReadyAgeSec: 120 }), { DELIVERY_READY_MAX_AGE_SEC: '60' }), 'delivery_ready_backlog');
  check(g, 'a garbage env value falls back to the default', deliveryThresholds({ DELIVERY_READY_MAX_AGE_SEC: 'abc' }).readyMaxAgeSec, 900);
  check(g, 'no data (null) raises nothing', names(null), 'none');
  const a = deliveryAlarms(H({ oldestReadyAgeSec: 960 }), {})[0];
  check(g, 'an alarm has the shape health-alert prints', ['checkName', 'severity', 'observed', 'threshold', 'meaning'].every((k) => k in a), true);
}

// ---- D · PORT and DATABASE_URL at boot ---------------------------------------------------------
{
  const g = 'D boot checks';
  const port = (v) => { const r = checkBootPort(v === undefined ? {} : { PORT: v }); return r.ok ? r.port : 'REFUSED'; };
  check(g, 'PORT unset defaults to 8080', port(undefined), 8080);
  check(g, 'PORT=8123 is accepted', port('8123'), 8123);
  check(g, 'PORT=1 and PORT=65535 are the edges and accepted', `${port('1')}/${port('65535')}`, '1/65535');
  for (const bad of ['abc', '', '0', '65536', '-1', '80.5', ' 80', '80 ', '8e3', '0x50', 'NaN', '99999999']) {
    check(g, `PORT=${JSON.stringify(bad)} is refused`, port(bad), 'REFUSED');
  }
  check(g, 'the refusal names PORT', /PORT/.test(checkBootPort({ PORT: 'abc' }).problem), true);

  const url = (u) => databaseUrlProblem(u) ?? 'ok';
  const hex = 'deadbeef0123456789abcdef0123456789abcdef01234567';
  check(g, 'a hex-only password URL is accepted', url(`postgres://app_runtime:${hex}@db:5432/olive_prod`), 'ok');
  check(g, 'postgresql:// is accepted too', url(`postgresql://u:${hex}@localhost:5434/x`), 'ok');
  check(g, 'a percent-encoded password is accepted', url('postgres://u:p%40ss@db:5432/x'), 'ok');
  check(g, 'no credentials (trust auth) is accepted', url('postgres://db:5432/x'), 'ok');
  for (const [why, u] of [['a literal @', 'postgres://app:pa@ss@db:5432/x'], ['a slash', 'postgres://app:ab/cd@db:5432/x'],
    ['a #', 'postgres://app:abc#d@db:5432/x'], ['a space', 'postgres://app:a b@db:5432/x'], ['a ?', 'postgres://app:a?b@db:5432/x'],
    ['a raw %', 'postgres://app:a%zz@db:5432/x'], ['a colon in the password', 'postgres://app:a:b@db:5432/x'],
    ['digits then a slash', 'postgres://app_runtime:123/abc@db:5432/olive'], ['digits then a ?', 'postgres://app_runtime:12?x@db:5432/olive']]) {
    check(g, `a password with ${why} is refused`, url(u) === 'ok' ? 'ACCEPTED' : 'refused', 'refused');
  }
  check(g, 'a non-postgres URL is refused', url('mysql://u:p@db/x') === 'ok' ? 'ACCEPTED' : 'refused', 'refused');
  check(g, 'the refusal never echoes the password', !String(databaseUrlProblem('postgres://app:Sup3r s3cret@db/x')).includes('s3cret'), true);
  check(g, 'the refusal tells the operator to use hex', /hex/i.test(databaseUrlProblem('postgres://app:a b@db/x')), true);

  // The REAL server entry point. PORT is checked before anything else (no database needed to see it refuse).
  const boot = (env) => spawnSync(process.execPath, [join(ROOT, 'server', 'index.mjs')], {
    cwd: ROOT, encoding: 'utf8', timeout: 30_000,
    env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, ...env } });
  const rPort = boot({ PORT: 'abc', DATABASE_URL: 'postgres://u:p@127.0.0.1:1/x' });
  check(g, 'REAL BOOT: PORT=abc exits 2', rPort.status, 2);
  check(g, 'REAL BOOT: and the message names PORT', /PORT check failed/.test(rPort.stderr), true);
  check(g, 'REAL BOOT: it never got as far as the database', /DATABASE_URL|ECONNREFUSED|listening/.test(rPort.stderr + rPort.stdout), false);
  const rEmpty = boot({ PORT: '', DATABASE_URL: 'postgres://u:p@127.0.0.1:1/x' });
  check(g, 'REAL BOOT: an EMPTY PORT (was a random port) exits 2', `${rEmpty.status}/${/PORT check failed/.test(rEmpty.stderr)}`, '2/true');
  const rOk = boot({ PORT: '8123' });
  check(g, 'REAL BOOT: a valid PORT passes the check and reaches the next one (DATABASE_URL required)',
    `${rOk.status}/${/DATABASE_URL required/.test(rOk.stderr)}`, '2/true');
  const rUrl = boot({ PORT: '8123', DATABASE_URL: 'postgres://app:pa@ss@127.0.0.1:1/x' });
  check(g, 'REAL BOOT: a non-hex password URL exits 2 naming DATABASE_URL', `${rUrl.status}/${/DATABASE_URL check failed/.test(rUrl.stderr)}`, '2/true');
  check(g, 'REAL BOOT: and does not print the password', rUrl.stderr.includes('pa@ss'), false);
}

// ---- E · the server's watch on a worker it does not host --------------------------------------
{
  const g = 'E boot warning';
  check(g, 'a worker that beat 20 s ago is fine', judgeWorkerHeartbeat({ beatAgeSec: 20, tickMs: 30_000 }).ok, true);
  check(g, 'no heartbeat at all is missing', judgeWorkerHeartbeat({ beatAgeSec: null, tickMs: null }).reason, 'no_heartbeat');
  check(g, 'a heartbeat 10 minutes old is stale', judgeWorkerHeartbeat({ beatAgeSec: 600, tickMs: 30_000 }).ok, false);
  check(g, 'the staleness limit is three ticks, never under 90 s', `${heartbeatStaleAfterSec(5_000)}/${heartbeatStaleAfterSec(60_000)}`, '90/180');
  check(g, 'the first check is a minute after boot', WATCH_FIRST_CHECK_MS, 60_000);
  check(g, 'the warning is greppable and names both fixes', /^WARNING delivery_worker_missing/.test(missingWorkerWarning('no_heartbeat'))
    && /docker compose up -d delivery/.test(missingWorkerWarning('x')) && /DELIVERY_IN_SERVER=1/.test(missingWorkerWarning('x')), true);

  const run = async ({ enabled, health, throws = false }) => {
    const logs = []; const timers = [];
    const w = createWorkerWatch({
      pool: {}, enabled, log: (l) => logs.push(l),
      read: async () => { if (throws) throw new Error('db'); return health(); },
      setTimer: (fn, ms) => { const t = { fn, ms, unref() {} }; timers.push(t); return t; }, clearTimer: () => {},
    });
    w.start();
    return { w, logs, timers };
  };
  let r = await run({ enabled: false, health: () => ({ workerBeatAgeSec: null, workerTickMs: null }) });
  check(g, 'DELIVERY_IN_SERVER=1 (the server IS the worker): the watch never starts', r.timers.length, 0);
  r = await run({ enabled: true, health: () => ({ workerBeatAgeSec: null, workerTickMs: null }) });
  check(g, 'DELIVERY_IN_SERVER=0: a check is scheduled for one minute after boot', r.timers[0].ms, 60_000);
  check(g, 'nothing is logged before the minute is up', r.logs.length, 0);
  await r.timers[0].fn();
  check(g, 'a minute after boot with NO worker heartbeat: a loud WARNING is logged', r.logs.length === 1 && /^WARNING delivery_worker_missing reason=no_heartbeat/.test(r.logs[0]), true);
  check(g, 'it keeps checking (a second timer is set)', r.timers.length, 2);
  check(g, 'the recheck interval is five minutes', r.timers[1].ms, 300_000);
  await r.timers[1].fn();
  check(g, 'a worker that is STILL missing is called out again', r.logs.length, 2);
  r.w.stop();

  let age = null;
  r = await run({ enabled: true, health: () => ({ workerBeatAgeSec: age, workerTickMs: 30_000 }) });
  age = 12;
  await r.timers[0].fn();
  check(g, 'a worker that has reported in: no warning', r.logs.length, 0);
  age = 900; await r.timers[1].fn();
  check(g, 'a worker that goes quiet later is called out', r.logs.length, 1);
  age = 8; await r.timers[2].fn();
  check(g, 'and acknowledged once when it returns', r.logs.length === 2 && /heartbeat seen/.test(r.logs[1]), true);
  r = await run({ enabled: true, health: () => ({}), throws: true });
  await r.timers[0].fn();
  check(g, 'a database error is NOT reported as a missing worker (the db check owns that)', r.logs.length, 0);
}

// ---- F · readiness reports a sweep that stopped looking ---------------------------------------
{
  const g = 'F readiness';
  const mediaDir = join(TMP, 'media');
  const migDir = join(TMP, 'migs');
  mkdirSync(migDir, { recursive: true });
  writeFileSync(join(migDir, '0001' + '_x.sql'), '');
  const mk = (b) => checkReadiness({
    pool: { query: async () => ({ rows: [{ level: '9999' + '_x.sql' }] }) }, migrationsDir: migDir, mediaRoot: mediaDir,
    delivery: { status: () => ({ enabled: false, intervalMs: 0, consecutiveFailures: 0, lastOkAgeSec: null }), backlog: async () => b },
  });
  const base = { pending: 0, ready: 0, oldestReadyAgeSec: null, oldestPendingAgeSec: null, oldestUnsweptSec: null };
  check(g, 'an empty queue is ready with nothing degraded', JSON.stringify((await mk(base)).degraded), '[]');
  check(g, 'a waiting message the sweep looked at a minute ago is NOT degraded (legitimately pending)',
    JSON.stringify((await mk({ ...base, pending: 3, oldestPendingAgeSec: 90_000, oldestUnsweptSec: 60 })).degraded), '[]');
  check(g, 'a waiting message the sweep has not looked at for 11 minutes IS degraded',
    JSON.stringify((await mk({ ...base, pending: 1, oldestPendingAgeSec: 700, oldestUnsweptSec: 660 })).degraded), '["delivery"]');
  check(g, 'a due message unclaimed for 11 minutes is still degraded',
    JSON.stringify((await mk({ ...base, ready: 1, oldestReadyAgeSec: 660 })).degraded), '["delivery"]');
  const both = await mk({ ...base, ready: 1, oldestReadyAgeSec: 660, oldestUnsweptSec: 660 });
  check(g, 'both at once reports delivery once', both.degraded.length, 1);
  check(g, 'degraded never makes the process unready (the app keeps serving)', (await mk({ ...base, oldestUnsweptSec: 9999 })).ready, true);
  check(g, 'a backlog without the new field (an older worker) still works', JSON.stringify((await mk({ pending: 0, ready: 0, oldestReadyAgeSec: null })).degraded), '[]');
}

// ---- G · compose contract: both delivery paths can never be off --------------------------------
/** Splits a compose file into { name -> block text } for the top-level `services:` map (2-space indent). */
function composeServices(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const start = lines.findIndex((l) => /^services:\s*$/.test(l));
  const out = {};
  if (start < 0) return out;
  let cur = null;
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i];
    if (/^\S/.test(l)) break;                       // next top-level key (volumes:)
    const m = /^  ([A-Za-z0-9_-]+):\s*$/.exec(l);
    if (m) { cur = m[1]; out[cur] = []; continue; }
    if (cur) out[cur].push(l);
  }
  return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, v.join('\n')]));
}
/**
 * What a compose file does with delivery. Returns a list of violations (empty = ok).
 * The server hosts the worker unless DELIVERY_IN_SERVER resolves to "0"; when the file's default (or
 * an operator-controlled value with no default) can switch it off, a `delivery` service that runs the
 * worker must exist and be part of the default `up`.
 */
function deliveryViolations(text) {
  const svc = composeServices(text);
  const v = [];
  const server = svc.server;
  if (!server) return v;                            // not a server stack (a jitsi override): nothing to say
  const m = /^\s*DELIVERY_IN_SERVER:\s*(.+?)\s*$/m.exec(server);
  let off;
  if (!m) off = false;                              // unset: server default is to host the worker
  else {
    const raw = m[1].replace(/^["']|["']$/g, '');
    const def = /^\$\{DELIVERY_IN_SERVER:-([^}]*)\}$/.exec(raw);
    if (def) off = def[1] === '0';
    else if (/^\$\{DELIVERY_IN_SERVER[:?]/.test(raw) || raw === '${DELIVERY_IN_SERVER}') off = true;   // operator-controlled, no default
    else off = raw === '0';
  }
  if (!off) return v;
  const workers = Object.entries(svc).filter(([, b]) => /^\s*command:.*deliver-loop/m.test(b));
  if (!workers.length) { v.push('DELIVERY_IN_SERVER can be 0 but there is no service running `deliver-loop`'); return v; }
  for (const [name, b] of workers) {
    if (/^\s*profiles:/m.test(b)) v.push(`${name}: the worker is gated behind a profile, so a plain \`up\` has no delivery`);
    if (!/^\s*restart:\s*(always|unless-stopped)\s*$/m.test(b)) v.push(`${name}: the worker has no restart policy`);
    if (!/^\s*test:.*delivery-healthcheck\.mjs/m.test(b)) v.push(`${name}: the worker has no delivery healthcheck`);
    if (!/condition:\s*service_completed_successfully/.test(b)) v.push(`${name}: the worker does not wait for migrate`);
  }
  return v;
}
{
  const g = 'G compose contract';
  const read = (p) => readFileSync(join(ROOT, p), 'utf8').replace(/\r\n/g, '\n');
  for (const f of ['docker-compose.prod.yml', 'docker-compose.dev.yml']) {
    const t = read(f);
    const svc = composeServices(t);
    check(g, `${f}: the parser finds the server and the delivery services`, `${'server' in svc}/${'delivery' in svc}`, 'true/true');
    check(g, `${f}: the file never has both delivery paths off`, deliveryViolations(t).join('; ') || 'none', 'none');
    check(g, `${f}: the worker has a healthcheck that reads the heartbeat`, /^\s*test:.*delivery-healthcheck\.mjs/m.test(svc.delivery), true);
    check(g, `${f}: the server's healthcheck is not relied on for the worker`, /^\s*command:.*deliver-loop/m.test(svc.server), false);
  }
  if (existsSync(join(ROOT, 'tools', 'family-sim', 'docker-compose.sim.yml'))) {
    check(g, 'the family-sim stack never has both delivery paths off', deliveryViolations(read('tools/family-sim/docker-compose.sim.yml')).join('; ') || 'none', 'none');
  }
  // The checker itself must be able to fail, or the section above proves nothing.
  const prod = read('docker-compose.prod.yml');
  const noWorker = prod.replace(/\n  delivery:\n[\s\S]*?(?=\nvolumes:)/, '');
  check(g, 'MUTANT: prod with the delivery service deleted is caught', deliveryViolations(noWorker).length > 0, true);
  const gated = prod.replace('  delivery:\n    image: ${IMAGE_REPO:-olive-branch}:${IMAGE_TAG:-latest}\n', '  delivery:\n    profiles: ["delivery"]\n    image: ${IMAGE_REPO:-olive-branch}:${IMAGE_TAG:-latest}\n');
  check(g, 'MUTANT: prod with the delivery service profile-gated is caught', deliveryViolations(gated).some((x) => /profile/.test(x)), true);
  const noCheck = prod.replace(/    healthcheck:\n      test: \["CMD", "node", "tools\/delivery-healthcheck\.mjs"\][\s\S]*?start_period: 30s\n/, '');
  check(g, 'MUTANT: prod with the worker healthcheck removed is caught', deliveryViolations(noCheck).some((x) => /healthcheck/.test(x)), true);
  const noRestart = prod.replace(/(  delivery:\n[\s\S]*?)    restart: always\n/, '$1');
  check(g, 'MUTANT: prod with the worker restart policy removed is caught', deliveryViolations(noRestart).some((x) => /restart/.test(x)), true);
  const hostOn = prod.replace('DELIVERY_IN_SERVER: ${DELIVERY_IN_SERVER:-0}', 'DELIVERY_IN_SERVER: "1"').replace(/\n  delivery:\n[\s\S]*?(?=\nvolumes:)/, '');
  check(g, 'a single-container deployment (server hosts the worker, no delivery service) is allowed', deliveryViolations(hostOn).join('; ') || 'none', 'none');
  const literalOff = prod.replace('DELIVERY_IN_SERVER: ${DELIVERY_IN_SERVER:-0}', 'DELIVERY_IN_SERVER: "0"').replace(/\n  delivery:\n[\s\S]*?(?=\nvolumes:)/, '');
  check(g, 'MUTANT: server pinned to 0 with no worker is caught', deliveryViolations(literalOff).length > 0, true);
  const operatorOff = prod.replace('DELIVERY_IN_SERVER: ${DELIVERY_IN_SERVER:-0}', 'DELIVERY_IN_SERVER: ${DELIVERY_IN_SERVER}').replace(/\n  delivery:\n[\s\S]*?(?=\nvolumes:)/, '');
  check(g, 'MUTANT: an operator-controlled value with no default and no worker is caught', deliveryViolations(operatorOff).length > 0, true);
}

// ---- H · the runbook ---------------------------------------------------------------------------
{
  const g = 'H runbook';
  const rb = readFileSync(join(ROOT, '..', 'docs', 'planning', 'OPERATIONS-RUNBOOK.md'), 'utf8');
  const sqlNames = new Set(readFileSync(join(ROOT, 'db', 'migrations', '0051_schema_level.sql'), 'utf8').match(/schema_migration_level/g));
  check(g, 'the function the runbook names exists in the migration (schema_migration_level)', sqlNames.has('schema_migration_level'), true);
  check(g, 'the runbook no longer names the function that never existed (schema_level())', /schema_level\(\)`\s*,?\s*the new columns/.test(rb) || /`schema_level\(\)`, the new/.test(rb), false);
  check(g, 'R3 checks the tables and functions with a counting query that can fail', /to_regclass\('public\.signup_allowance'\)/.test(rb) && /to_regprocedure\('schema_migration_level\(\)'\)/.test(rb), true);
  check(g, 'R3 tells the operator to run the check on the migrated database first (it must print 6)', /must print `6`/.test(rb), true);
  check(g, 'R3 expects 0 after the restore', /must print `0`/.test(rb), true);
  check(g, 'step 10 states an idle worker logs only at start', /logs only at start/.test(rb), true);
  check(g, 'step 10 no longer promises status=ok lines every 30 s', /status=ok. lines every 30 s/.test(rb), false);
  check(g, 'step 10 names the proofs: health status, /readyz and a delivered message', /State\.Health\.Status/.test(rb) && /\/readyz/.test(rb) && /arrives in the child's inbox/.test(rb), true);
  check(g, 'step 10 names the periodic heartbeat line', /deliver_heartbeat/.test(rb), true);
  check(g, 'the runbook documents hex-only passwords and the PORT range', /HEX ONLY/.test(rb) && /1 to 65535/.test(rb), true);
  check(g, 'the runbook counts all eight migrations the move applies', /eight additive files/.test(rb) && /53 applied, 53 total/.test(rb), true);
  check(g, 'the env template documents hex-only passwords', /MUST BE HEX ONLY/.test(readFileSync(join(ROOT, '.env.prod.example'), 'utf8')), true);
  check(g, 'the prod compose header documents hex-only passwords', /OPERATOR PASSWORDS ARE HEX ONLY/.test(readFileSync(join(ROOT, 'docker-compose.prod.yml'), 'utf8')), true);
}

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
clearInterval(keepAlive);
try { rmSync(TMP, { recursive: true, force: true }); } catch { /* best effort */ }
process.exit(fail === 0 ? 0 : 1);
