// OLIVE BRANCH — the server's watch on a delivery worker it does not host (ISS-069).
//
// With DELIVERY_IN_SERVER=0 the server delegates delivery to the dedicated `delivery` service. If that
// service is not running (never started, a `--profile` forgotten, crash-looping) nothing delivers, the
// child's inbox stays empty and, until now, NOTHING SAID SO: the server booted clean, /readyz stayed
// ready and the only trace was a pending row getting older. This watch is the loud half of the fix:
//
//   - one minute after boot (the worker ticks every 30 s by default, so a healthy worker has beaten by
//     then) it reads the worker heartbeat through delivery_health() (migration 0056, aggregate-only)
//     and, if there is none or it is stale, logs a WARNING line that names the cause and the two fixes;
//   - it keeps checking every few minutes, so a worker that dies later is also called out and a worker
//     that appears is acknowledged once.
//
// It never changes behaviour (no exit, no readiness flip): the app must keep serving sign-in, reading
// and the offline-first local experience while an operator fixes the worker. It is a log line and
// nothing more; tools/health-alert.mjs and /readyz carry the same fact for monitors.
import { deliveryHealth } from '../packages/db/src/pool.mjs';

export const WATCH_FIRST_CHECK_MS = 60_000;
export const WATCH_RECHECK_MS = 5 * 60_000;
const STALE_FLOOR_SEC = 90;

/** Heartbeat older than this counts as missing: three ticks of the worker's own cadence, never under 90 s. */
export function heartbeatStaleAfterSec(tickMs) {
  const t = Number.isFinite(Number(tickMs)) && Number(tickMs) > 0 ? Number(tickMs) : 30_000;
  return Math.max(STALE_FLOOR_SEC, Math.ceil((3 * t) / 1000));
}

/**
 * @param {{ beatAgeSec: number|null, tickMs: number|null }} h
 * @returns {{ ok: boolean, reason: string }}
 */
export function judgeWorkerHeartbeat(h) {
  if (h.beatAgeSec === null || h.beatAgeSec === undefined) return { ok: false, reason: 'no_heartbeat' };
  if (h.beatAgeSec > heartbeatStaleAfterSec(h.tickMs)) return { ok: false, reason: `stale_${h.beatAgeSec}s` };
  return { ok: true, reason: 'ok' };
}

/** The exact text logged when the worker is missing. Greppable: it starts with WARNING delivery_worker_missing. */
export function missingWorkerWarning(reason) {
  return `WARNING delivery_worker_missing reason=${reason}: DELIVERY_IN_SERVER=0 so this server does NOT deliver messages, `
    + 'and no delivery worker heartbeat has been seen. Nothing will reach a child\'s inbox until one runs. '
    + 'Start the `delivery` service (docker compose up -d delivery) or set DELIVERY_IN_SERVER=1 to host the worker in this process.';
}

/**
 * @param {{ pool: any, enabled: boolean,
 *           firstCheckMs?: number, recheckMs?: number,
 *           log?: (line: string) => void,
 *           read?: (pool: any) => Promise<{ workerBeatAgeSec: number|null, workerTickMs: number|null }>,
 *           setTimer?: typeof setTimeout, clearTimer?: typeof clearTimeout }} o
 *   `enabled` is true when the server does NOT host the worker (hostIntervalFromEnv() === 0).
 */
export function createWorkerWatch({
  pool, enabled, firstCheckMs = WATCH_FIRST_CHECK_MS, recheckMs = WATCH_RECHECK_MS,
  log = (l) => console.warn(l), read = deliveryHealth,
  setTimer = setTimeout, clearTimer = clearTimeout,
}) {
  let timer = null;
  let stopped = false;
  let lastOk = null;     // null = never judged
  let checks = 0;

  async function check() {
    checks++;
    let verdict;
    try {
      const h = await read(pool);
      verdict = judgeWorkerHeartbeat({ beatAgeSec: h.workerBeatAgeSec, tickMs: h.workerTickMs });
    } catch {
      // The database being unreachable is the db check's to report; do not claim the worker is missing.
      return { skipped: true };
    }
    if (!verdict.ok) log(missingWorkerWarning(verdict.reason));
    else if (lastOk === false) log('delivery worker heartbeat seen: delivery is running again');
    lastOk = verdict.ok;
    return verdict;
  }

  function schedule(ms) {
    if (stopped) return;
    timer = setTimer(async () => { await check(); schedule(recheckMs); }, ms);
    timer.unref?.();
  }

  return {
    start() { if (enabled && !timer && !stopped) schedule(firstCheckMs); },
    /** One check now (for tests and for ops). */
    check,
    stop() { stopped = true; if (timer) clearTimer(timer); timer = null; },
    status: () => ({ enabled, checks, lastOk }),
  };
}
