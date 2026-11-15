// OLIVE BRANCH — the delivery worker: the process that finally moves a banked
// message from "sent" to "in the child's inbox". MASTERFILE section 9.8, audit G1.
//
// THE GAP THIS CLOSES. A guardian's POST .../messages stores a `delivery_intent`
// in state `pending`. Two things have to happen before the child can read it:
//   1. materialize()  -- pending -> ready, with a real scheduled_at
//      (tools/scheduler.mjs runRematerializeSweep, which ran once a day at 03:00 UTC)
//   2. claim_due_intents() -- ready -> delivered once scheduled_at has passed
//      (db/migrations/0002_delivery_sweep.sql), which NOTHING in the repository
//      called. tools/family-sim/lib/world.mjs even had its harness do this step
//      by hand and said so ("NOT counted as a pass of the product").
// GET .../inbox returns only `delivered`/`opened`, so a message sent through the
// product never reached a child. This module is the missing caller.
//
// WHAT ONE TICK DOES, in order, under ONE session advisory lock (job name `deliver`),
// which serialises replicas OF THE TICK only; the correctness of everything below does not
// depend on it, it rests on the compare-and-swap writes:
//   - rematerialize pending intents      (reuses the scheduler's own sweep)
//   - expire intents past their retention window (COPPA 10.1: nothing lingers)
//   - claim due intents -> delivered     (compare-and-swap in SQL)
//   - one content-free `message_ready` push per child that just received something
//
// IT RUNS IN THE SERVER PROCESS, not only in the scheduler container, so the stack
// the owner actually tests on (olive-fresh runs no scheduler) delivers too. The
// nightly scheduler loop is unchanged and stays safe alongside it, but NOT because they
// share a lock: the scheduler's `rematerialize` job locks under its own job name, so it
// and this tick can run runRematerializeSweep at the same moment. What makes that safe is
// that every write is a compare-and-swap (a loser's UPDATE matches no row).
//
// CHILD SAFETY (P1-P11). The push carries an opaque intent id and the kind, and
// nothing else: no sender, no count, no caption, no time. notify.mjs runs
// sendGuard() on every payload and also applies the asleep/school gate, so a
// delivered message never lights a sleeping child's lock screen; the message is
// still in her inbox when she wakes. A push failure NEVER undoes a delivery.
//
// FAILURE POSTURE. A tick that throws is counted, logged as one line, and tried
// again at the next interval; it never takes the server down and never leaves a
// half-state, because each SQL step is its own atomic statement.
import { DateTime } from 'luxon';
import { claimDueIntents, expireStaleIntents, deliveryBacklog } from '../packages/db/src/pool.mjs';
import { notifyDevices } from '../packages/transport/src/notify.mjs';
import { runRematerializeSweep, withJobLock } from '../tools/scheduler.mjs';
import { errorLine } from './safe_log.mjs';

export const DEFAULT_DELIVERY_TICK_MS = 15_000;
export const DELIVERY_LOCK_NAME = 'deliver';
const CLAIM_BATCH = 100;
// A burst of POSTs (a batch of 30 messages) should cost one extra tick, not 30.
const KICK_DEBOUNCE_MS = 400;

/** DELIVERY_TICK_MS: unset -> 15 s; 0 -> off; garbage or negative -> the default. */
export function tickIntervalFromEnv(env = process.env) {
  const raw = env.DELIVERY_TICK_MS;
  if (raw === undefined || raw === '') return DEFAULT_DELIVERY_TICK_MS;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return DEFAULT_DELIVERY_TICK_MS;
  return n === 0 ? 0 : Math.max(1000, Math.floor(n));
}

/**
 * @param {{ pool: import('pg').Pool,
 *           intervalMs?: number,
 *           notify?: typeof notifyDevices,
 *           metrics?: { inc: (name: string, by?: number) => void },
 *           log?: (line: string) => void,
 *           now?: () => number,
 *           claimBatch?: number }} o
 */
export function createDeliveryTick({
  pool, intervalMs = DEFAULT_DELIVERY_TICK_MS, notify = notifyDevices,
  metrics = { inc() {} }, log = (l) => console.log(l), now = () => Date.now(),
  claimBatch = CLAIM_BATCH,
}) {
  let timer = null;
  let kickTimer = null;
  let running = null;      // the in-flight tick's promise, if any
  let stopped = false;
  const state = {
    enabled: intervalMs > 0, ticks: 0, failures: 0, consecutiveFailures: 0,
    lastOkAt: null, lastError: null, last: null,
  };

  async function tickBody() {
    const sweep = await runRematerializeSweep(pool, { now: DateTime.utc() });
    const expired = await expireStaleIntents(pool);
    const claimed = await claimDueIntents(pool, claimBatch);

    // One push per child, however many messages landed. The ref is the newest
    // intent id: an opaque handle the client resolves after unlock.
    const byChild = new Map();
    for (const c of claimed) byChild.set(c.childId, c.id);
    let pushed = 0, pushFailed = 0;
    for (const [childId, intentId] of byChild) {
      try {
        const results = await notify(pool, { childId }, {
          kind: 'message_ready', ref: intentId, collapseKey: 'message_ready' });
        if (results.some((r) => r.ok)) pushed++;
      } catch (e) {
        // Best effort by design: the message is already delivered.
        pushFailed++;
        log(errorLine(e, { msg: 'delivery: push failed', kind: 'message_ready' }));
      }
    }
    return {
      materialized: sweep.materialized, expiredOnSweep: sweep.expired, stillPending: sweep.stillPending,
      rowErrors: sweep.errored, expired, claimed: claimed.length, children: byChild.size,
      pushed, pushFailed,
    };
  }

  /** One full pass. Resolves to the counts, or { locked: true } if another worker holds the lock. */
  function runOnce() {
    if (running) return running;      // never two passes in this process at once
    running = (async () => {
      state.ticks++;
      try {
        const out = await withJobLock(pool, DELIVERY_LOCK_NAME, tickBody);
        if (!out.locked) return { locked: true };
        const r = out.result;
        state.last = r; state.lastOkAt = now(); state.consecutiveFailures = 0; state.lastError = null;
        if (r.claimed) metrics.inc('delivery_claimed_total', r.claimed);
        if (r.expired) metrics.inc('delivery_expired_total', r.expired);
        if (r.pushed) metrics.inc('delivery_push_sent_total', r.pushed);
        if (r.pushFailed) metrics.inc('delivery_push_failed_total', r.pushFailed);
        if (r.rowErrors) metrics.inc('delivery_row_errors_total', r.rowErrors);
        // Silent when idle: a 15 s heartbeat line per tick would bury the access log.
        if (r.claimed || r.expired || r.materialized || r.rowErrors) {
          log(`delivery_tick materialized=${r.materialized} claimed=${r.claimed} children=${r.children} ` +
              `expired=${r.expired} pushed=${r.pushed} push_failed=${r.pushFailed} row_errors=${r.rowErrors}`);
        }
        return r;
      } catch (e) {
        state.failures++; state.consecutiveFailures++;
        state.lastError = String(e?.code ?? e?.message ?? e).slice(0, 120);
        metrics.inc('delivery_tick_errors_total');
        log(errorLine(e, { msg: 'delivery: tick failed' }));
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
