// OLIVE BRANCH — the delivery worker's heartbeat (audit AUD-SRV-3, ISS-069).
//
// A worker that is stopped, wedged or failing every tick used to be indistinguishable from an idle
// healthy one: a quiet tick logs nothing, /readyz "degraded" never fails a healthcheck, and nothing
// restarted a worker that was alive but stuck. Three pieces close that, all in this file so the
// worker, the compose healthcheck and the tests share one definition of "stale":
//
//   1. HEARTBEAT FILE. Every loop iteration the worker writes a tiny JSON file (atomic rename):
//      when it started, when it last ticked, when a tick last SUCCEEDED, its tick interval and its
//      failure streak. No family data, no ids. `tools/delivery-healthcheck.mjs` (the compose
//      healthcheck) reads it, so a stopped worker, or one that fails every tick, turns the
//      container `unhealthy`. The file is per container on purpose: it needs no database, so it
//      still answers when Postgres is the thing that is down.
//   2. WATCHDOG. Docker never restarts an unhealthy container, only an exited one. A worker that
//      has failed N ticks in a row, or whose loop has not come round for far longer than any
//      tick takes (a hung query), exits non-zero so `restart: always` brings back a fresh process
//      with a fresh connection pool. See watchdogVerdict().
//   3. HEARTBEAT LOG. An idle worker logs nothing per tick (a line every 30 s would bury the log),
//      which made "is it alive?" unanswerable from `docker logs`. A periodic `deliver_heartbeat`
//      line (default every 10 minutes) says so, with counts and no content.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';

export const HEARTBEAT_STALE_FLOOR_MS = 90_000;
export const DEFAULT_HEARTBEAT_LOG_MS = 600_000;
export const WATCHDOG_FAILURE_STREAK = 20;

export function heartbeatFileFromEnv(env = process.env) {
  return env.DELIVERY_HEARTBEAT_FILE || join(tmpdir(), 'olive-delivery-heartbeat.json');
}

/** How old a heartbeat may be before it counts as stale: four tick intervals, never under 90 s. */
export function staleAfterMs(tickMs) {
  const t = Number.isFinite(Number(tickMs)) && Number(tickMs) > 0 ? Number(tickMs) : 30_000;
  return Math.max(HEARTBEAT_STALE_FLOOR_MS, 4 * t);
}

export function heartbeatLogMsFromEnv(env = process.env) {
  const raw = Number(env.DELIVERY_HEARTBEAT_LOG_MS ?? DEFAULT_HEARTBEAT_LOG_MS);
  return Number.isFinite(raw) && raw >= 1000 ? raw : DEFAULT_HEARTBEAT_LOG_MS;
}

/** Atomic write: a reader never sees a half-written file. */
export function writeHeartbeatFile(path, data) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(data));
  renameSync(tmp, path);
}

export function readHeartbeatFile(path) {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; }
}

/**
 * The healthcheck's verdict. `data` is what writeHeartbeatFile stored (or null when the file is
 * missing/unreadable). Healthy = the loop ticked recently AND a tick succeeded recently; a worker
 * that has not yet had a successful tick is judged from when it started.
 * @returns {{ healthy: boolean, reason: string }}
 */
export function evaluateHeartbeat(data, nowMs = Date.now()) {
  if (!data || typeof data !== 'object') return { healthy: false, reason: 'no heartbeat file: the worker has not started' };
  const limit = staleAfterMs(data.tickMs);
  const lastTick = Number(data.lastTickAt ?? data.startedAt);
  if (!Number.isFinite(lastTick)) return { healthy: false, reason: 'heartbeat file is unreadable' };
  const tickAge = nowMs - lastTick;
  if (tickAge > limit) return { healthy: false, reason: `worker stopped ticking ${Math.round(tickAge / 1000)}s ago (limit ${Math.round(limit / 1000)}s)` };
  const okRef = Number(data.lastOkAt ?? data.startedAt);
  const okAge = nowMs - okRef;
  if (!Number.isFinite(okRef) || okAge > limit) {
    return { healthy: false, reason: `no successful tick for ${Math.round(okAge / 1000)}s (limit ${Math.round(limit / 1000)}s), ${data.consecutiveFailures ?? 0} failures in a row` };
  }
  return { healthy: true, reason: 'ok' };
}

/**
 * Whether the worker process should kill itself so the orchestrator restarts it.
 * Failure streak: the worker is alive but every tick fails (a dead connection pool that never
 * recovers). Hang: the loop has not come round for max(10 min, 20 ticks), far past any tick.
 * @returns {{ exit: boolean, reason: string }}
 */
export function watchdogVerdict(snap, nowMs = Date.now(), { streak = WATCHDOG_FAILURE_STREAK } = {}) {
  if (snap.consecutiveFailures >= streak) {
    return { exit: true, reason: `${snap.consecutiveFailures} consecutive failed ticks` };
  }
  const hangMs = Math.max(600_000, 20 * (snap.tickMs > 0 ? snap.tickMs : 30_000));
  const since = nowMs - (snap.lastTickAt ?? snap.startedAt);
  if (since > hangMs) return { exit: true, reason: `no tick completed for ${Math.round(since / 1000)}s (hung)` };
  return { exit: false, reason: 'ok' };
}

/**
 * Tracks the worker's own state and mirrors it to the heartbeat file.
 * @param {{ tickMs: number, file?: string|null, now?: () => number, write?: typeof writeHeartbeatFile }} o
 */
export function createWorkerHeartbeat({ tickMs, file = heartbeatFileFromEnv(), now = Date.now, write = writeHeartbeatFile }) {
  const startedAt = now();
  const st = { startedAt, lastTickAt: null, lastOkAt: null, tickMs, ticks: 0, failures: 0, consecutiveFailures: 0 };
  const persist = () => {
    if (!file) return;
    try { write(file, st); } catch { /* an unwritable /tmp must not stop deliveries; the healthcheck will say so */ }
  };
  persist();   // written at start so a healthcheck right after boot has something to read
  return {
    /** Record one finished loop iteration. `ok` = the tick succeeded (a lock-held skip counts as ok). */
    beat(ok) {
      st.ticks++; st.lastTickAt = now();
      if (ok) { st.lastOkAt = st.lastTickAt; st.consecutiveFailures = 0; } else { st.failures++; st.consecutiveFailures++; }
      persist();
      return { ...st };
    },
    snapshot: () => ({ ...st }),
  };
}

/** The one-line periodic log body (key=value fields; the caller adds scope/event). */
export function heartbeatLogFields(snap, nowMs = Date.now()) {
  return {
    ticks: snap.ticks, failures: snap.failures, consecutive_failures: snap.consecutiveFailures,
    last_ok_age_s: snap.lastOkAt === null ? '' : Math.round((nowMs - snap.lastOkAt) / 1000),
    uptime_s: Math.round((nowMs - snap.startedAt) / 1000), tick_ms: snap.tickMs,
  };
}
