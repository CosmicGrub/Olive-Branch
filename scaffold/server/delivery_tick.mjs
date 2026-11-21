// OLIVE BRANCH — the server's in-process host for the delivery worker.
// MASTERFILE section 9.8, audit G1 (host half), delivery lane (the worker).
//
// THERE IS ONE DELIVERY WORKER and it is `runDeliverSweep` in tools/scheduler.mjs:
// expire stale intents, re-time pending ones, claim the due ones (`ready` ->
// `delivered`, a compare-and-swap in SQL) and send one content-free `message_ready`
// push per child that just received something. This file adds no delivery logic of
// its own. It is only a HOST that lets the server process run that same function:
//
//   - a timer, so a one-container deployment (no separate `delivery` service, no
//     scheduler profile) still delivers;
//   - kick(), called right after a message is banked, so something already due does
//     not wait for the next tick;
//   - status() / backlog(), which /readyz and /internal/metrics read.
//
// WHEN TO TURN THIS HOST OFF. A deployment that runs the dedicated worker
// (`node tools/scheduler.mjs deliver-loop`, the compose `delivery` service) should set
// DELIVERY_IN_SERVER=0 on the server so the same job is not run from two places. Running
// both is SAFE (they take the same session advisory lock, `deliver`, so one skips while the
// other works, and every write underneath is a compare-and-swap) but it is wasted work, so the
// compose files turn this host off where the dedicated service exists.
//
// CHILD SAFETY (P1-P11). The push carries an opaque intent id and the kind, nothing else;
// see runDeliverSweep. A push failure never undoes a delivery.
//
// FAILURE POSTURE. A tick that throws is counted, logged as one line and tried again at the
// next interval; it never takes the server down. A sweep that reports step errors (it keeps
// going past a failed step on purpose) counts as a failure here too, so /readyz shows
// `degraded` instead of a worker that looks fine while it delivers nothing.
import { runDeliverSweep, withJobLock, deliverTickMsFromEnv } from '../tools/scheduler.mjs';
import { notifyDevices } from '../packages/transport/src/notify.mjs';
import { deliveryBacklog, recordWorkerHeartbeat } from '../packages/db/src/pool.mjs';
import { errorLine } from './safe_log.mjs';

export const DELIVERY_LOCK_NAME = 'deliver';
// The heartbeat row this host writes (migration 0057). The dedicated worker writes 'delivery'; either
// one alive is enough for delivery_health(), so a one-container deployment is not reported as worker-less.
export const IN_SERVER_WORKER_NAME = 'delivery-in-server';
// A burst of POSTs (a batch of 30 messages) should cost one extra tick, not 30.
const KICK_DEBOUNCE_MS = 400;

/**
 * The interval the in-server host runs at, or 0 for "do not host the worker here".
 * DELIVERY_IN_SERVER=0 turns it off (a dedicated worker runs elsewhere); otherwise
 * DELIVERY_TICK_MS is read exactly as the dedicated worker reads it (default 30 s,
 * floor 5 s) so the two hosts can never disagree about cadence.
 */
export function hostIntervalFromEnv(env = process.env) {
  if (env.DELIVERY_IN_SERVER === '0') return 0;
  return deliverTickMsFromEnv(env);
}

/**
 * @param {{ pool: import('pg').Pool,
 *           intervalMs?: number,
 *           notify?: typeof notifyDevices,
 *           metrics?: { inc: (name: string, by?: number) => void },
 *           log?: (line: string) => void,
 *           now?: () => number,
 *           sweep?: typeof runDeliverSweep,
 *           heartbeat?: (o: { worker: string, tickMs: number, ok: boolean, consecutiveFailures: number }) => Promise<void> }} o
 */
export function createDeliveryTick({
  pool, intervalMs = 30_000, notify = notifyDevices,
  metrics = { inc() {} }, log = (l) => console.log(l), now = () => Date.now(),
  sweep = runDeliverSweep,
  heartbeat = (o) => recordWorkerHeartbeat(pool, o),
}) {
  let timer = null;
  let kickTimer = null;
  let running = null;      // the in-flight tick's promise, if any
  let stopped = false;
  const state = {
    enabled: intervalMs > 0, ticks: 0, failures: 0, consecutiveFailures: 0,
    lastOkAt: null, lastError: null, last: null,
  };

  // Best effort: a heartbeat that cannot be written must never turn a good tick into a bad one.
  async function beat(ok) {
    if (intervalMs <= 0) return;
    try {
      await heartbeat({ worker: IN_SERVER_WORKER_NAME, tickMs: intervalMs, ok, consecutiveFailures: state.consecutiveFailures });
    } catch { /* the readiness/health checks report a silent worker; this is not the place to be loud every tick */ }
  }

  /** One full pass. Resolves to the counts, or { locked: true } if another worker holds the lock. */
  function runOnce() {
    if (running) return running;      // never two passes in this process at once
    running = (async () => {
      state.ticks++;
      try {
        const out = await withJobLock(pool, DELIVERY_LOCK_NAME, () => sweep(pool, { notify }));
        if (!out.locked) return { locked: true };
        const r = out.result;
        if (r.errors?.length) {
          // runDeliverSweep carries on past a failed step on purpose; the host must still say so.
          throw Object.assign(new Error(r.errors.join('; ')), { code: 'sweep_step_failed' });
        }
        state.last = r; state.lastOkAt = now(); state.consecutiveFailures = 0; state.lastError = null;
        await beat(true);
        if (r.delivered) metrics.inc('delivery_claimed_total', r.delivered);
        if (r.expired) metrics.inc('delivery_expired_total', r.expired);
        if (r.pushed) metrics.inc('delivery_push_sent_total', r.pushed);
        if (r.pushFailed) metrics.inc('delivery_push_failed_total', r.pushFailed);
        if (r.rematerialized?.errored) metrics.inc('delivery_row_errors_total', r.rematerialized.errored);
        // Silent when idle: a heartbeat line per tick would bury the access log.
        if (r.delivered || r.expired || r.rematerialized?.materialized || r.rematerialized?.errored) {
          log(`delivery_tick materialized=${r.rematerialized?.materialized ?? 0} delivered=${r.delivered} ` +
              `children=${r.children.length} expired=${r.expired} pushed=${r.pushed} ` +
              `push_failed=${r.pushFailed} row_errors=${r.rematerialized?.errored ?? 0}`);
        }
        return r;
      } catch (e) {
        state.failures++; state.consecutiveFailures++;
        state.lastError = String(e?.code ?? e?.message ?? e).slice(0, 120);
        metrics.inc('delivery_tick_errors_total');
        log(errorLine(e, { msg: 'delivery: tick failed' }));
        await beat(false);
        return { error: true };
      } finally {
        running = null;
      }
    })();
    return running;
  }

  function schedule() {
    if (stopped || intervalMs <= 0) return;
    timer = setTimeout(async () => {
      await runOnce();
      schedule();
    }, intervalMs);
    timer.unref?.();
  }

  return {
    runOnce,
    start() {
      if (intervalMs <= 0 || timer || stopped) return;
      // First pass shortly after boot so a restart does not leave a due message
      // waiting a full interval.
      timer = setTimeout(async () => { await runOnce(); schedule(); }, 1500);
      timer.unref?.();
    },
    /** Called after a message is banked: deliver anything already due without waiting for the interval. */
    kick() {
      if (stopped || intervalMs <= 0 || kickTimer) return;
      kickTimer = setTimeout(() => { kickTimer = null; runOnce(); }, KICK_DEBOUNCE_MS);
      kickTimer.unref?.();
    },
    /** Stops scheduling and waits for the in-flight pass, so shutdown never cuts a claim mid-way. */
    async stop() {
      stopped = true;
      if (timer) clearTimeout(timer);
      if (kickTimer) clearTimeout(kickTimer);
      timer = kickTimer = null;
      if (running) { try { await running; } catch { /* already counted */ } }
    },
    /** For /readyz and ops: no secrets, no family data. */
    status() {
      return {
        enabled: state.enabled, intervalMs, ticks: state.ticks, failures: state.failures,
        consecutiveFailures: state.consecutiveFailures, lastError: state.lastError,
        lastOkAgeSec: state.lastOkAt === null ? null : Math.round((now() - state.lastOkAt) / 1000),
      };
    },
    backlog: () => deliveryBacklog(pool),
  };
}
