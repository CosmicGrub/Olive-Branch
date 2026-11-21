// OLIVE BRANCH — readiness, as distinct from liveness. Audit G7.
//
//   GET /healthz  "the process is up and can reach Postgres"   (liveness; unchanged)
//   GET /readyz   "this process should be handed traffic NOW"  (readiness; here)
//
// They answer different questions, and conflating them hid real faults:
//   - an image that expects a newer migration against a database at 0047 served
//     /healthz 200 and then failed inside a route, in front of a person;
//   - an unmounted or read-only media volume only showed up as 500s on upload;
//   - a delivery worker stuck in a failure loop looked exactly like a healthy one;
//   - during a deploy there was no way to say "stop sending me requests" before
//     the listener closed.
//
// The body names WHICH check failed (db / schema / media / delivery / draining)
// and nothing else: no row counts, no ids, no versions, no paths. An
// unauthenticated caller learns "ready" or a category, the same posture /healthz
// already takes. The compose healthcheck points here.
import { readdirSync, mkdirSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';

/** Newest migration filename baked into this image, or null if the directory is unreadable. */
export function newestShippedMigration(dir) {
  try {
    const files = readdirSync(dir).filter((f) => /^\d{4}_.+\.sql$/.test(f)).sort();
    return files.length ? files[files.length - 1] : null;
  } catch { return null; }
}

/**
 * 'ok' when the database is at (or past) what the image expects, 'behind' when the
 * image expects a migration the database has not applied, 'unknown' when either
 * side cannot be read. Filenames start with a zero-padded number, so a plain
 * string compare orders them.
 */
export function compareSchemaLevel(dbLevel, shipped) {
  if (!dbLevel || !shipped) return 'unknown';
  return dbLevel >= shipped ? 'ok' : 'behind';
}

/** A temp-file round trip: proves the media root exists (or can be made) AND is writable. */
export function mediaRootWritable(root) {
  try {
    mkdirSync(root, { recursive: true });
    const probe = join(root, `.ready-${randomBytes(6).toString('hex')}`);
    writeFileSync(probe, 'ok');
    unlinkSync(probe);
    return true;
  } catch { return false; }
}

// The timer is cleared when the work settles (no stray timer per probe) and is NOT unref'd:
// an unref'd timer lets a process whose only pending work is a hung query exit silently
// instead of reporting the timeout.
const withTimeout = (p, ms, label) => {
  let timer;
  const timeout = new Promise((_, rej) => { timer = setTimeout(() => rej(new Error(`${label} timeout`)), ms); });
  return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
};

/**
 * Shares one readiness check between callers. A probe arriving while a check is running
 * waits for that one; a probe arriving within `ttlMs` of the last finished check gets its
 * result. Draining is answered fresh every time (it is an in-memory flag, and a cached
 * "ready" must never outlive SIGTERM). ttlMs <= 0 turns the cache off.
 */
export function createReadinessCache({ check, isDraining = () => false, ttlMs = 2000, now = () => Date.now() }) {
  let last = null;      // { at, value }
  let inflight = null;
  return async function readiness() {
    if (isDraining()) return check();
    const t = now();
    if (ttlMs > 0 && last && t - last.at >= 0 && t - last.at < ttlMs) return last.value;
    if (ttlMs > 0 && inflight) return inflight;
    const run = (async () => {
      try {
        const value = await check();
        last = { at: now(), value };
        return value;
      } finally { inflight = null; }
    })();
    if (ttlMs > 0) inflight = run;
    return run;
  };
}

/**
 * @param {{ pool: { query: Function },
 *           migrationsDir: string, mediaRoot: string,
 *           delivery?: { status: () => any } | null,
 *           isDraining?: () => boolean,
 *           deliveryStaleAfterMs?: number, backlogStaleAfterSec?: number }} o
 * @returns {Promise<{ ready: boolean, failing: string[], degraded: string[] }>}
 */
export async function checkReadiness({
  pool, migrationsDir, mediaRoot, delivery = null, isDraining = () => false,
  deliveryStaleAfterMs, backlogStaleAfterSec = 600,
}) {
  const failing = [];
  // `degraded` is reported but does not make the process unready: a stalled delivery
  // worker must be visible, yet the app (sign in, read, pair, the local experience
  // the server exists to ENABLE) must keep being served while someone fixes it.
  const degraded = [];
  // Draining is checked FIRST and short-circuits: once SIGTERM has arrived the
  // answer is "not ready" whatever the database says, so the orchestrator stops
  // routing here before the listener closes.
  if (isDraining()) return { ready: false, failing: ['draining'], degraded };

  let dbLevel = null;
  try {
    const r = await withTimeout(pool.query('SELECT schema_migration_level() AS level'), 3000, 'readyz db');
    dbLevel = r.rows?.[0]?.level ?? null;
  } catch { failing.push('db'); }

  if (!failing.includes('db')) {
    if (compareSchemaLevel(dbLevel, newestShippedMigration(migrationsDir)) !== 'ok') failing.push('schema');
  }
  if (!mediaRootWritable(mediaRoot)) failing.push('media');

  if (delivery) {
    const s = delivery.status();
    if (s.enabled) {
      const staleAfterSec = Math.max(60, Math.ceil((deliveryStaleAfterMs ?? s.intervalMs * 6) / 1000));
      // Not-yet-run (just booted) is fine; a worker that has FAILED repeatedly,
      // or that last succeeded long ago, is not.
      const stuck = s.consecutiveFailures >= 3
        || (s.lastOkAgeSec !== null && s.lastOkAgeSec > staleAfterSec);
      if (stuck) degraded.push('delivery');
    }
    // Host-independent: the worker may run in this process OR as the dedicated
    // `delivery` service (DELIVERY_IN_SERVER=0), where status() can say nothing. A `ready`
    // row whose delivery instant passed long ago and that nobody has claimed means the
    // worker, wherever it runs, is not working.
    if (typeof delivery.backlog === 'function' && !degraded.includes('delivery') && !failing.includes('db')) {
      try {
        const b = await withTimeout(delivery.backlog(), 3000, 'readyz backlog');
        if (b?.oldestReadyAgeSec !== null && b?.oldestReadyAgeSec !== undefined
            && b.oldestReadyAgeSec > backlogStaleAfterSec) degraded.push('delivery');
        // ISS-070: the rematerialize sweep is round-robin (0057), so under a working worker no pending
        // row goes unlooked-at for long. A pending row the sweep has not touched for this long means
        // the sweep itself is not running or cannot reach it (a pending row that is merely WAITING,
        // for a bedtime that is not defined yet, is looked at every pass and does not trip this).
        if (!degraded.includes('delivery') && b?.oldestUnsweptSec !== null && b?.oldestUnsweptSec !== undefined
            && b.oldestUnsweptSec > backlogStaleAfterSec) degraded.push('delivery');
      } catch { /* the database going away is reported by the db check, not here */ }
    }
  }
  return { ready: failing.length === 0, failing, degraded };
}
