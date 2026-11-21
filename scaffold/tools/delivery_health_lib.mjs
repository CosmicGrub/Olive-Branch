// OLIVE BRANCH — delivery-worker alarms for tools/health-alert.mjs (ISS-069).
//
// health_check (the SQL view) already counts "stalled" and "unmaterialized" rows, but it cannot see
// WHETHER A WORKER IS RUNNING and it reports counts, not ages. delivery_health() (migration 0056)
// returns ages in seconds and the worker heartbeat; this turns that into the same
// {checkName, severity, observed, threshold, meaning} breaches health-alert already prints.
// Pure: no database, no clock, so every threshold is unit-tested.

function positiveInt(raw, fallback) {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

export function deliveryThresholds(env = process.env) {
  return {
    // a `ready` row whose delivery instant has passed and that nobody claimed
    readyMaxAgeSec: positiveInt(env.DELIVERY_READY_MAX_AGE_SEC, 900),
    // a row that has sat `pending` this long without ever becoming ready
    pendingMaxAgeSec: positiveInt(env.DELIVERY_PENDING_MAX_AGE_SEC, 86_400),
    // with no worker heartbeat at all, how long a pending row may wait before the absence is an alarm
    missingWorkerGraceSec: positiveInt(env.DELIVERY_MISSING_WORKER_GRACE_SEC, 600),
    // never below 5 minutes, otherwise ten tick intervals of the worker's own cadence
    workerFloorSec: 300,
  };
}

/**
 * @param {{ pending: number, ready: number, oldestReadyAgeSec: number|null, oldestPendingAgeSec: number|null,
 *           workerBeatAgeSec: number|null, workerOkAgeSec: number|null, workerTickMs: number|null }|null} h
 * @returns {{ checkName: string, severity: string, observed: number, threshold: number, meaning: string }[]}
 */
export function deliveryAlarms(h, env = process.env) {
  if (!h) return [];
  const t = deliveryThresholds(env);
  const out = [];
  const add = (checkName, severity, observed, threshold, meaning) =>
    out.push({ checkName, severity, observed, threshold, meaning });

  const workerLimit = Math.max(t.workerFloorSec, Math.ceil(10 * (h.workerTickMs ?? 30_000) / 1000));
  if (h.workerBeatAgeSec === null) {
    // Never beat. A fresh install with nothing queued is fine; queued work and no worker is not.
    if (h.oldestPendingAgeSec !== null && h.oldestPendingAgeSec > t.missingWorkerGraceSec) {
      add('delivery_worker_missing', 'critical', h.oldestPendingAgeSec, t.missingWorkerGraceSec,
        'Messages are queued and no delivery worker has ever reported in. Start the `delivery` service, or set DELIVERY_IN_SERVER=1.');
    }
  } else if (h.workerBeatAgeSec > workerLimit) {
    add('delivery_worker_stale', 'critical', h.workerBeatAgeSec, workerLimit,
      'No delivery worker has reported in recently: it is stopped, crash-looping or cannot reach the database.');
  } else if (h.workerOkAgeSec === null || h.workerOkAgeSec > workerLimit) {
    add('delivery_worker_failing', 'critical', h.workerOkAgeSec ?? h.workerBeatAgeSec, workerLimit,
      'The delivery worker is running but no tick has succeeded recently: every pass is failing.');
  }
  if (h.oldestReadyAgeSec !== null && h.oldestReadyAgeSec > t.readyMaxAgeSec) {
    add('delivery_ready_backlog', 'high', h.oldestReadyAgeSec, t.readyMaxAgeSec,
      'A message is due and nobody has delivered it. The delivery worker is not claiming.');
  }
  if (h.oldestPendingAgeSec !== null && h.oldestPendingAgeSec > t.pendingMaxAgeSec) {
    add('delivery_pending_old', 'high', h.oldestPendingAgeSec, t.pendingMaxAgeSec,
      'A message has waited a day or more without a delivery time (no bedtime or day-part defined, or the worker is not running).');
  }
  return out;
}
