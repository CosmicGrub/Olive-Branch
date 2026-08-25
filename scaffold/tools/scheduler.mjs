#!/usr/bin/env node
/**
 * OLIVE BRANCH — scheduled-jobs runner.
 *
 * Two real, disclosed gaps this file closes, both pointing at the same root
 * cause ("no cron/scheduler exists anywhere in this repo yet"):
 *
 *   - MASTERFILE §20.2b, verbatim: "Still only a terminal/log signal: no cron
 *     job and no email/Slack/pager integration exists anywhere in this repo,
 *     and the script's own header says so" — about `tools/health-alert.mjs`.
 *     That script (real, tested, already wired into `tools/verify.sh`)
 *     detects and reports; nothing ever CALLED it on a schedule. This file is
 *     that caller, not a rewrite of its detection logic.
 *
 *   - `scaffold/README.md`'s own delivery-engine section: `materialize()`'s
 *     "future + undelivered only" invalidation guarantee
 *     (`packages/delivery-engine/src/materialize.ts`) is real and proven
 *     (`delivery.test.mjs`'s 37 probes) — but nothing in this repository ever
 *     CALLS it against real Postgres rows. This is not a cosmetic gap: every
 *     `delivery_intent` row is created `state='pending'` with `scheduled_at`
 *     left NULL (`persistCapturedMessage()`, `packages/db/src/pool.ts` —
 *     `captureMessage()` only calls `materialize()` to VALIDATE and derive
 *     retention, it never persists the result), and
 *     `db/migrations/0002_delivery_sweep.sql`'s own `invalidate_for_child()`
 *     resets an already-materialized row back to the same
 *     `pending`/`scheduled_at IS NULL` state on any zone/day-part change.
 *     `claim_due_intents()` (same migration) only ever claims `state='ready'`
 *     rows. Without something calling `materialize()` and writing the result
 *     back, a `pending` intent NEVER becomes `ready`, and NOTHING this
 *     product delivers would ever actually go out. That is the sweep below.
 *
 * WHAT THIS FILE DOES NOT DO — same honesty discipline as health-alert.mjs's
 * own header:
 *   - Does not touch `materialize.ts`'s or `health-alert.mjs`'s own logic.
 *     Both are called exactly as they already exist.
 *   - Does not call `claim_due_intents()` or `expire_stale_intents()`
 *     (`db/migrations/0002_delivery_sweep.sql`) — those are a SEPARATE,
 *     still-open gap (a real delivery/send worker that actually pushes a
 *     `ready` intent to a device, and a retention-expiry sweep), not named by
 *     either of the two disclosed gaps this file was asked to close. Wiring
 *     either in is real, scoped future work, not silently folded in here.
 *   - Does not resolve `on_event` targets. `childCtxFor()`
 *     (`packages/db/src/pool.ts`) never populates `ChildCtx.eventInstants`
 *     (no caller anywhere in this repo does), so an `on_event` intent's
 *     `materialize()` call always returns `{ok:false, reason:
 *     'unresolvable_event'}` here — same as it always has. Left `pending` for
 *     the next sweep, never expired, since that is a configuration gap, not
 *     a time-past one.
 *
 * ---------------------------------------------------------------- LOCKING --
 * Two named jobs (`rematerialize`, `health-alert`) can each run at most once
 * at a time, enforced with a real Postgres SESSION-level advisory lock
 * (`pg_try_advisory_lock`), one dedicated connection held for the whole job,
 * keyed per job name (`hashtext('olive_branch_scheduler:' || jobName)`) so
 * the two jobs never contend with each other, only with a second, concurrent
 * invocation of THE SAME job.
 *
 * Chosen over a `scheduled_job_run` table + `UNIQUE(job_name, run_date)`
 * for one concrete reason: crash safety with no separate cleanup. A session-
 * level advisory lock is tied to the physical connection that took it —
 * Postgres releases it automatically the moment that connection closes, for
 * ANY reason, clean exit or a killed process alike. A `UNIQUE` row, by
 * contrast, needs its own "this job died without ever marking itself
 * finished" recovery logic (a stale `running` row past some timeout), or a
 * crashed run permanently wedges every future run of that job. The advisory
 * lock gets that property for free, at the cost of nothing this deployment
 * needs (no cross-run history — `tools/verify.sh`'s own stdout/stderr lines
 * from cron/Docker `logs` are this project's real audit trail for a
 * self-hosted single-family deployment, the same posture `health-alert.mjs`
 * already takes for its own output).
 *
 * ------------------------------------------------------------------- CLI --
 *   node tools/scheduler.mjs run rematerialize   # one sweep, then exit
 *   node tools/scheduler.mjs run health-alert    # one health check, then exit
 *   node tools/scheduler.mjs run all             # both, in sequence
 *   node tools/scheduler.mjs loop                # runs `all` on a schedule, forever
 *
 * `loop` is what `docker-compose.dev.yml`'s new, opt-in `scheduler` service
 * runs — see that file and `scaffold/docs/scheduler.md` for how an operator
 * actually turns this on and why it defaults OFF.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { DateTime } from 'luxon';
import { createPool, withSystemSession, childCtxFor } from '../packages/db/src/pool.mjs';
import { materialize } from '../packages/delivery-engine/src/materialize.mjs';

const execFileAsync = promisify(execFile);
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const HEALTH_ALERT_SCRIPT = join(REPO_ROOT, 'tools', 'health-alert.mjs');

// -------------------------------------------------------------- logging ---
// Same flat `key=value` shape as health-alert.mjs's own ALERT lines, so both
// scripts' output greps the same way from cron/Docker `logs`. Values with
// whitespace/quotes/`=` are wrapped in quotes (only `error=` messages ever
// need this in practice).
function fmt(fields) {
  return Object.entries(fields).map(([k, v]) => {
    if (v === null || v === undefined) return `${k}=`;
    const s = String(v);
    return /[\s"=]/.test(s) ? `${k}="${s.replace(/"/g, "'")}"` : `${k}=${s}`;
  }).join(' ');
}
function logLine(fields) { console.log(fmt({ scope: 'scheduler', ...fields })); }
function errLine(fields) { console.error(fmt({ scope: 'scheduler', ...fields })); }

// -------------------------------------------------------- advisory lock ---
const LOCK_NAMESPACE = 'olive_branch_scheduler';

/**
 * Runs `fn` while holding a real session-level `pg_try_advisory_lock` keyed
 * by `jobName`, on a connection dedicated to this call for its whole
 * duration. Returns `{ locked: false }` immediately (never calls `fn`) if
 * another session already holds this job's lock. A rejection from `fn`
 * propagates to the caller AFTER the lock is released (the inner `finally`
 * below always unlocks first) — this function never swallows a job error.
 */
export async function withJobLock(pool, jobName, fn) {
  const client = await pool.connect();
  const lockKey = `${LOCK_NAMESPACE}:${jobName}`;
  try {
    const { rows } = await client.query(
      `SELECT pg_try_advisory_lock(hashtext($1)::bigint) AS locked`, [lockKey]);
    if (!rows[0].locked) return { locked: false };
    try {
      const result = await fn();
      return { locked: true, result };
    } finally {
      await client.query(`SELECT pg_advisory_unlock(hashtext($1)::bigint)`, [lockKey]);
    }
  } finally {
    client.release();
  }
}

// ------------------------------------------------------- rematerialize ----
export const DEFAULT_REMATERIALIZE_BATCH = 500;

/**
 * The nightly (or on-demand) rematerialization sweep: every `delivery_intent`
 * row still `state='pending'` — freshly created and never yet resolved, OR
 * reset there by `invalidate_for_child()`'s own zone/day-part trigger — gets
 * a real `materialize()` call against a real `ChildCtx` loaded from Postgres
 * (`childCtxFor()`, cached per child within one sweep so a batch of 50
 * siblings' intents costs one `childCtxFor()` call per CHILD, not per row).
 *
 * Per intent:
 *   - `materialize()` ok  → `state='ready'`, `scheduled_at`/`materialized_tz`/
 *     `materialized_at` written. This is the row `claim_due_intents()`
 *     (0002_delivery_sweep.sql) can finally see.
 *   - `already_expired` / `target_in_past` → `state='expired'`. Genuinely
 *     unrecoverable (COPPA §10.1's own retention window, or an explicitly
 *     dated `on_local_date`/`at_instant`/`on_event` target that's fallen
 *     more than `PAST_GRACE_MINUTES` behind `now` — see materialize.ts's own
 *     comment on why that grace window exists and what it's for).
 *   - any other skip reason (`daypart_undefined`, `no_reachable_window`,
 *     `unresolvable_event`) → left `pending`, retried next sweep. These are
 *     CONFIGURATION gaps (no day-part/availability data yet, or an
 *     unresolvable event id), not time-past ones — expiring them would
 *     permanently lose a message a guardian could still fix by adding the
 *     missing day-part.
 *
 * Every write is a compare-and-swap (`WHERE id = $1 AND state = 'pending'`),
 * mirroring `claim_due_intents()`'s own reasoning: this sweep already can't
 * overlap ITSELF (the advisory lock above), but a CAS is cheap insurance
 * against any other future writer of this table, not just this one.
 */
export async function runRematerializeSweep(pool, opts = {}) {
  const now = opts.now ?? DateTime.utc();
  const batchLimit = opts.batchLimit ?? DEFAULT_REMATERIALIZE_BATCH;

  // target_instant/expires_at are `timestamptz` — a bare `::text` cast
  // renders Postgres's default space-separated DateStyle ("2026-08-24
  // 01:44:28+00"), not ISO-8601, and materialize.ts's own `Intent` type
  // documents both fields as "ISO instant" and parses them with Luxon's
  // `DateTime.fromISO()`, which silently returns an Invalid DateTime (never
  // throws) for that format — every `<=`/`<` comparison against it is then
  // always false, so the already_expired/target_in_past guards never fire.
  // Reproduced live and fixed 2026-08-24 (round-5 engineering-systems
  // review). `to_char(... AT TIME ZONE 'UTC', ...)` is this codebase's own
  // established fix for the identical class of bug — see pool.ts's
  // `loadMessageChain()` doing the same for `message_log.at`.
  // target_local_date is a plain DATE column; DATE is unaffected by
  // DateStyle's timestamp formatting and `::text` already yields a real
  // 'YYYY-MM-DD' string, so it is left as-is.
  const pendingRows = await withSystemSession(pool, (q) => q(
    `SELECT id, child_id, policy,
            to_char(target_instant AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS target_instant,
            target_daypart, target_local_date::text AS target_local_date,
            target_event_id, batch_seq,
            to_char(expires_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS expires_at
       FROM delivery_intent
      WHERE state = 'pending'
      ORDER BY created_at
      LIMIT $1`,
    [batchLimit],
  ));

  let materialized = 0, expired = 0, stillPending = 0, skippedRows = 0;
  const ctxCache = new Map();

  for (const row of pendingRows) {
    let ctx = ctxCache.get(row.child_id);
    if (ctx === undefined) {
      ctx = await childCtxFor(pool, row.child_id);
      ctxCache.set(row.child_id, ctx);
    }
    if (!ctx) {
      // Should be unreachable — child_id is `REFERENCES child(id) ON DELETE
      // CASCADE`, so a delivery_intent row cannot outlive its child. Handled
      // defensively anyway (an honest skip + a warning line) rather than
      // letting one bad row crash the whole sweep.
      skippedRows++;
      errLine({ event: 'warn', job: 'rematerialize', reason: 'missing_child_ctx',
        intent_id: row.id, child_id: row.child_id, at: DateTime.utc().toISO() });
      continue;
    }

    const intent = {
      id: row.id, childId: row.child_id, policy: row.policy, state: 'pending',
      expiresAt: row.expires_at,
      targetInstant: row.target_instant ?? undefined,
      targetDaypart: row.target_daypart ?? undefined,
      targetLocalDate: row.target_local_date ?? undefined,
      targetEventId: row.target_event_id ?? undefined,
      batchSeq: row.batch_seq ?? undefined,
    };

    const result = materialize(intent, ctx, now);

    if (result.ok) {
      const updated = await withSystemSession(pool, (q) => q(
        `UPDATE delivery_intent
            SET state = 'ready', scheduled_at = $2::timestamptz,
                materialized_tz = $3, materialized_at = now()
          WHERE id = $1 AND state = 'pending'
          RETURNING id`,
        [row.id, result.scheduledAt.toUTC().toISO(), result.tz],
      ));
      if (updated.length) materialized++; else stillPending++;
      continue;
    }

    if (result.reason === 'already_expired' || result.reason === 'target_in_past') {
      const updated = await withSystemSession(pool, (q) => q(
        `UPDATE delivery_intent SET state = 'expired'
          WHERE id = $1 AND state = 'pending' RETURNING id`,
        [row.id],
      ));
      if (updated.length) expired++; else stillPending++;
      continue;
    }

    stillPending++;
  }

  return {
    scanned: pendingRows.length, materialized, expired, stillPending, skippedRows,
    batchLimitHit: pendingRows.length === batchLimit,
  };
}

// ----------------------------------------------------------- health-alert -
/**
 * `tools/health-alert.mjs` is a standalone top-level script — importing it
 * would run its whole body immediately (including its own `process.exit()`
 * calls) inside THIS process, not a callable function. Run as a real
 * subprocess instead, exactly the way `tools/verify.sh` and
 * `packages/db/test/health_alert.test.mjs` already invoke it — this file
 * adds a caller, not a second copy of its detection logic.
 */
export async function runHealthAlertSubprocess(databaseUrl) {
  try {
    const { stdout, stderr } = await execFileAsync(process.execPath, [HEALTH_ALERT_SCRIPT], {
      env: { ...process.env, DATABASE_URL: databaseUrl },
    });
    return { exitCode: 0, stdout, stderr };
  } catch (e) {
    return {
      exitCode: typeof e.code === 'number' ? e.code : 1,
      stdout: e.stdout ?? '',
      stderr: e.stderr ?? String(e.message ?? e),
    };
  }
}

// --------------------------------------------------------- job registry ---
export const JOB_NAMES = ['rematerialize', 'health-alert'];

/**
 * Runs one named job under its own advisory lock, with structured
 * start/end/skip/failure logging. Never throws — a job failure (a thrown
 * error, a non-zero health-alert exit, a lock already held by another
 * invocation) is reported in the return value and in the log lines, so a
 * caller running several jobs in sequence can keep going and still report an
 * honest overall exit code at the end.
 */
export async function runNamedJob(pool, databaseUrl, jobName) {
  const startedAt = DateTime.utc();
  logLine({ event: 'start', job: jobName, at: startedAt.toISO() });

  let lockResult;
  try {
    lockResult = await withJobLock(pool, jobName, async () => {
      if (jobName === 'rematerialize') return runRematerializeSweep(pool, {});
      if (jobName === 'health-alert') return runHealthAlertSubprocess(databaseUrl);
      throw new Error(`unknown job: ${jobName}`);
    });
  } catch (e) {
    const durationMs = DateTime.utc().diff(startedAt).as('milliseconds').toFixed(0);
    errLine({ event: 'end', job: jobName, status: 'failed', duration_ms: durationMs,
      error: e.message ?? String(e), at: DateTime.utc().toISO() });
    return { ok: false, skipped: false };
  }

  if (!lockResult.locked) {
    logLine({ event: 'skip_already_running', job: jobName, at: DateTime.utc().toISO() });
    // A skip is expected, benign behavior under real contention — not a
    // failure. See db/test suite below, section B, for the proof that
    // exactly one of two concurrent invocations does the real work while
    // the other lands here.
    return { ok: true, skipped: true };
  }

  const durationMs = DateTime.utc().diff(startedAt).as('milliseconds').toFixed(0);

  if (jobName === 'rematerialize') {
    const r = lockResult.result;
    logLine({
      event: 'end', job: jobName, status: 'ok', duration_ms: durationMs,
      scanned: r.scanned, materialized: r.materialized, expired: r.expired,
      still_pending: r.stillPending, skipped_rows: r.skippedRows,
      batch_limit_hit: r.batchLimitHit, at: DateTime.utc().toISO(),
    });
    return { ok: true, skipped: false };
  }

  // health-alert
  const r = lockResult.result;
  const ok = r.exitCode === 0;
  const logger = ok ? logLine : errLine;
  logger({
    event: 'end', job: jobName, status: ok ? 'ok' : 'breach', exit_code: r.exitCode,
    duration_ms: durationMs, at: DateTime.utc().toISO(),
  });
  if (!ok && r.stderr) {
    // health-alert.mjs's own real ALERT lines, passed through verbatim so
    // an operator reading `docker logs` sees exactly what it would have
    // printed running standalone — not summarized or re-worded here.
    for (const line of r.stderr.trim().split('\n')) errLine({ event: 'detail', job: jobName, line });
  }
  return { ok, skipped: false };
}

/** Runs every job in JOB_NAMES, in sequence. Non-zero-worthy if ANY job
 * failed OR reported a real breach — a health breach on a LIVE deployment's
 * database is exactly the kind of thing an operator's cron/Docker-exit-code
 * monitoring needs surfaced, unlike tools/verify.sh's own deliberately softer
 * treatment of the same script against a fresh, disposable CI database (see
 * verify.sh's own comment on why a breach there doesn't gate its exit code —
 * a different concern, a fresh database that is never expected to breach,
 * versus this file watching a real, live one). */
export async function runAll(pool, databaseUrl) {
  let allOk = true;
  for (const name of JOB_NAMES) {
    const r = await runNamedJob(pool, databaseUrl, name);
    if (!r.ok) allOk = false;
  }
  return allOk;
}

// ------------------------------------------------------------------ loop --
function msUntilNextRun(hourUtc) {
  const now = DateTime.utc();
  let next = now.set({ hour: hourUtc, minute: 0, second: 0, millisecond: 0 });
  if (next <= now) next = next.plus({ days: 1 });
  return next.diff(now).as('milliseconds');
}

// Sleeps in short chunks rather than one long setTimeout, so a SIGTERM
// (`docker compose stop`'s default ~10s grace period before SIGKILL) is
// noticed within ~2s instead of the loop blocking a real shutdown for up to
// a full day.
async function interruptibleSleep(totalMs, isStopping) {
  const CHUNK_MS = 2000;
  let remaining = totalMs;
  while (remaining > 0 && !isStopping()) {
    await new Promise((resolve) => setTimeout(resolve, Math.min(CHUNK_MS, remaining)));
    remaining -= CHUNK_MS;
  }
}

/**
 * Runs `all` on a schedule, forever, until SIGTERM/SIGINT. Real loop
 * (sleep + invoke), not a cron daemon — see this file's own header /
 * scaffold/docs/scheduler.md for why that's the simpler, genuinely-correct
 * choice for a Compose stack: no second base image, no separate mechanism
 * for getting `DATABASE_URL` into a cron job's environment (cron does not
 * inherit the container's environment by default — a well-known footgun),
 * one process, one set of logs `docker compose logs` already shows.
 *
 * Default schedule: once daily at `SCHEDULER_HOUR_UTC` (default 3, i.e.
 * 03:00 UTC — late night in every US timezone this product's own MASTERFILE
 * day-part examples use). `SCHEDULER_INTERVAL_MS`, if set, overrides the
 * daily schedule with a fixed interval instead — for an operator who wants a
 * tighter cadence, and for exercising the loop itself quickly without
 * waiting for a real UTC midnight.
 */
export async function loop(pool, databaseUrl) {
  const intervalOverrideMs = process.env.SCHEDULER_INTERVAL_MS
    ? Number(process.env.SCHEDULER_INTERVAL_MS) : null;
  const hourUtc = Number(process.env.SCHEDULER_HOUR_UTC ?? 3);

  let stopping = false;
  const stop = () => { stopping = true; };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);

  logLine({
    event: 'loop_start',
    schedule: intervalOverrideMs ? `every_${intervalOverrideMs}ms` : `daily_${hourUtc}:00_utc`,
  });

  while (!stopping) {
    const sleepMs = intervalOverrideMs ?? msUntilNextRun(hourUtc);
    await interruptibleSleep(sleepMs, () => stopping);
    if (stopping) break;
    await runAll(pool, databaseUrl);
  }
  logLine({ event: 'loop_stop' });
}

// -------------------------------------------------------------------- CLI -
function usage() {
  console.error('usage: node tools/scheduler.mjs run <rematerialize|health-alert|all>');
  console.error('       node tools/scheduler.mjs loop');
}

async function main() {
  const [, , cmd, arg] = process.argv;
  const DATABASE_URL = process.env.DATABASE_URL || process.env.ADMIN_DATABASE_URL;
  if (!DATABASE_URL) {
    console.error('DATABASE_URL (or ADMIN_DATABASE_URL) required');
    process.exit(2);
  }
  const pool = createPool(DATABASE_URL);

  if (cmd === 'run') {
    if (arg !== 'all' && !JOB_NAMES.includes(arg)) {
      usage();
      await pool.end();
      process.exit(2);
    }
    const ok = arg === 'all'
      ? await runAll(pool, DATABASE_URL)
      : (await runNamedJob(pool, DATABASE_URL, arg)).ok;
    await pool.end();
    process.exit(ok ? 0 : 1);
  } else if (cmd === 'loop') {
    await loop(pool, DATABASE_URL);
    await pool.end();
    process.exit(0);
  } else {
    usage();
    await pool.end();
    process.exit(2);
  }
}

const isMain = process.argv[1]
  ? import.meta.url === pathToFileURL(process.argv[1]).href
  : false;
if (isMain) {
  main().catch((e) => { console.error(e); process.exit(2); });
}
