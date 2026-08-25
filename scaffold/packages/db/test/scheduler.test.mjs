/**
 * packages/db/test/scheduler.test.mjs — tools/scheduler.mjs, exercised
 * against a REAL Postgres. MASTERFILE §20.2b (health-alert has no caller)
 * and scaffold/README.md's own delivery-engine section ("no cron or
 * scheduler actually calls [materialize()] on a nightly cadence anywhere in
 * this repo") — this proves the caller this repo was missing actually works,
 * not just that its locking code exists.
 *
 * Same DATABASE_URL/ADMIN_DATABASE_URL split as pool.test.mjs /
 * message_capture.test.mjs / health_alert.test.mjs: DATABASE_URL is the
 * NOSUPERUSER NOBYPASSRLS role the scheduler itself runs as; ADMIN_DATABASE_URL
 * (falls back to DATABASE_URL) seeds and tears down fixtures. Needs a live,
 * migrated Postgres — not part of `npm test`'s default JS-suite chain, for
 * the same reason its siblings above aren't.
 *
 * Three things proven here, matching the task's own three-part demand:
 *   A) LOCK CONTENTION, at the primitive — two genuinely concurrent
 *      `withJobLock()` calls for the SAME job name, fired with `Promise.all`
 *      (this repo's own established real-race shape — see
 *      auth_credentials.test.mjs sections C/F/I). The LOSER's job body is
 *      proven to never even start (`started.length === 1`), not merely that
 *      one of the two return values happens to say `locked:false`.
 *   B) REMATERIALIZATION CORRECTNESS — a real `on_local_date` intent in the
 *      future, one in the past beyond `PAST_GRACE_MINUTES`, and one with no
 *      matching `day_part` configured, all seeded `state='pending'` with no
 *      `scheduled_at` (exactly `persistCapturedMessage()`'s own real INSERT
 *      shape, and exactly `invalidate_for_child()`'s own reset shape) — swept
 *      once, and the resulting state/scheduled_at/materialized_tz checked
 *      against calling `materialize()` directly with the same inputs (proving
 *      the SEAM — the sweep's row-loading and write-back — not re-proving
 *      `materialize()` itself, which `delivery.test.mjs`'s 37 probes already
 *      do). A second sweep afterward proves already-resolved rows are never
 *      re-touched.
 *   D) LOCK CONTENTION, at the real job — two genuinely concurrent
 *      `runNamedJob()` calls for `health-alert` (a real subprocess spawn,
 *      naturally slow enough to race reliably — empirically ~0.5-1s per run
 *      against this suite's own Postgres), proving the actual job runner,
 *      not just the lock helper, only ever does the real work once.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
import { createPool, childCtxFor } from '../src/pool.mjs';
import { materialize } from '../../delivery-engine/src/materialize.mjs';
import {
  withJobLock, runRematerializeSweep, runNamedJob,
} from '../../../tools/scheduler.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

// Fixed "now" so future/past-beyond-grace fixtures are deterministic —
// PAST_GRACE_MINUTES (materialize.ts) is 120 minutes.
const NOW = DateTime.fromISO('2026-08-24T12:00:00Z', { zone: 'utc' });

const DAD = 'a0000000-0000-0000-0000-00000000000d';
const CHILD_R = 'a0000000-0000-0000-0000-00000000000c';
const INTENT_READY = 'a0000000-0000-0000-0000-0000000000a1';
const INTENT_EXPIRE = 'a0000000-0000-0000-0000-0000000000a2';
const INTENT_STILL_PENDING = 'a0000000-0000-0000-0000-0000000000a3';
const INTENT_ALREADY_EXPIRED = 'a0000000-0000-0000-0000-0000000000a4';
const INTENT_AT_INSTANT = 'a0000000-0000-0000-0000-0000000000a5';

async function clearFixture() {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = $1`, [CHILD_R]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [CHILD_R]);
  await admin.query(`DELETE FROM child_tz_interval WHERE child_id = $1`, [CHILD_R]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD_R]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD_R]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
}
await clearFixture();

// ===========================================================================
// A · withJobLock — real lock contention, proven, not merely asserted to
//     exist. Two genuinely concurrent calls for the SAME job name.
// ===========================================================================
{
  const started = [];
  const finished = [];
  const slow = async (tag) => {
    started.push(tag);
    await new Promise((r) => setTimeout(r, 400));
    finished.push(tag);
    return tag;
  };

  const [ra, rb] = await Promise.all([
    withJobLock(pool, 'scheduler-test-lock', () => slow('A')),
    withJobLock(pool, 'scheduler-test-lock', () => slow('B')),
  ]);

  const lockedCount = [ra.locked, rb.locked].filter(Boolean).length;
  check('A lock', 'exactly one of two concurrent invocations acquires the lock', lockedCount, 1);
  check('A lock', 'the other is told the lock is already held',
    [ra.locked, rb.locked].includes(false), true);
  // The real proof this isn't just "one return value happens to say false":
  // the LOSER's job body must never even have been invoked.
  check('A lock', 'the losing invocation never started its own job body',
    started.length, 1);
  check('A lock', 'the winning invocation actually finished its job body',
    finished.length, 1);
  check('A lock', 'the winner\'s result is the tag it was given',
    (ra.locked ? ra.result : rb.result), started[0]);

  // The lock must be released again once the job finishes, not held forever.
  const rc = await withJobLock(pool, 'scheduler-test-lock', () => slow('C'));
  check('A lock', 'the lock is released again once the job finishes', rc.locked, true);

  // A thrown job error still releases the lock, and still propagates —
  // withJobLock() must never swallow a real failure.
  let threw = null;
  try {
    await withJobLock(pool, 'scheduler-test-lock-2', async () => { throw new Error('boom'); });
  } catch (e) { threw = e.message; }
  check('A lock', 'a thrown job error propagates to the caller', threw, 'boom');
  const rd = await withJobLock(pool, 'scheduler-test-lock-2', () => 'ok');
  check('A lock', 'the lock is released even when the job throws', rd.locked, true);
}

// ===========================================================================
// B · runRematerializeSweep — real seeded rows, real Postgres, real
//     materialize() calls. Mirrors persistCapturedMessage()'s own real
//     insert shape: state='pending', scheduled_at left NULL.
// ===========================================================================
{
  await admin.query(
    `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/New_York')`,
    [DAD]);
  await admin.query(
    `INSERT INTO child (id, display_name, birth_date, home_tz)
     VALUES ($1,'SchedulerTestChild','2016-04-02','America/New_York')`, [CHILD_R]);
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, valid)
     VALUES ($1, $2, 'guardian', tstzrange(now() - interval '1 year', null))`, [CHILD_R, DAD]);
  await admin.query(
    `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week,
                          reachable, effective)
     VALUES ($1,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)')`,
    [CHILD_R]);
  // Deliberately no tz interval row — home_tz (America/New_York) is the
  // real fallback childCtxFor()/materialize() are meant to use.

  const tomorrow = NOW.toISODate();   // any real date string works as the target
  const farPast = NOW.minus({ days: 10 }).toISODate();

  // payload_ref is `uuid NOT NULL` with no REFERENCES clause (0001_phase0_
  // init.sql) — any well-formed uuid is a legal placeholder here, no
  // media_artifact row required for this suite's own purposes.
  const PAYLOAD_READY = 'a0000000-0000-0000-0000-0000000000b1';
  const PAYLOAD_EXPIRE = 'a0000000-0000-0000-0000-0000000000b2';
  const PAYLOAD_PENDING = 'a0000000-0000-0000-0000-0000000000b3';

  await admin.query(
    `INSERT INTO delivery_intent
       (id, child_id, sender_id, payload_kind, payload_ref, policy,
        target_local_date, target_daypart, state, expires_at)
     VALUES
       ($1, $6, $7, 'video_msg', $9, 'on_local_date',
        $2::date, 'bedtime', 'pending', $8::timestamptz),
       ($3, $6, $7, 'video_msg', $10, 'on_local_date',
        $4::date, 'bedtime', 'pending', $8::timestamptz),
       ($5, $6, $7, 'video_msg', $11, 'at_daypart',
        NULL, 'no_such_daypart_kind', 'pending', $8::timestamptz)`,
    [INTENT_READY, tomorrow, INTENT_EXPIRE, farPast, INTENT_STILL_PENDING, CHILD_R, DAD,
     NOW.plus({ days: 90 }).toISO(), PAYLOAD_READY, PAYLOAD_EXPIRE, PAYLOAD_PENDING],
  );

  // Two more real rows, added specifically to exercise the two branches a
  // real, live-reproduced bug in this suite's own earlier version silently
  // never touched: (1) the `already_expired` guard (materialize.ts:78) fires
  // BEFORE the policy switch, for any policy, whenever `expires_at` is
  // already in the past — INTENT_EXPIRE above only ever exercises the
  // separate `target_in_past` branch, never this one; (2) the `at_instant`
  // policy specifically, which had no fixture at all. Both require
  // `target_instant`/`expires_at` to round-trip through Postgres and back
  // into a real ISO-8601 string Luxon's `DateTime.fromISO()` can actually
  // parse — exactly the cast this suite's earlier version got wrong (see
  // tools/scheduler.mjs's own `to_char(... AT TIME ZONE 'UTC', ...)` fix).
  const PAYLOAD_ALREADY_EXPIRED = 'a0000000-0000-0000-0000-0000000000b4';
  const PAYLOAD_AT_INSTANT = 'a0000000-0000-0000-0000-0000000000b5';
  const atInstantTarget = NOW.plus({ hours: 2 }).toISO();
  await admin.query(
    `INSERT INTO delivery_intent
       (id, child_id, sender_id, payload_kind, payload_ref, policy,
        target_local_date, target_daypart, target_instant, state, expires_at)
     VALUES
       ($1, $6, $7, 'video_msg', $8, 'on_local_date',
        $2::date, 'bedtime', NULL, 'pending', $3::timestamptz),
       ($4, $6, $7, 'video_msg', $9, 'at_instant',
        NULL, NULL, $5::timestamptz, 'pending', $10::timestamptz)`,
    [INTENT_ALREADY_EXPIRED, tomorrow, NOW.minus({ days: 1 }).toISO(),
     INTENT_AT_INSTANT, atInstantTarget, CHILD_R, DAD,
     PAYLOAD_ALREADY_EXPIRED, PAYLOAD_AT_INSTANT, NOW.plus({ days: 90 }).toISO()],
  );

  const before = await runRematerializeSweep(pool, { now: NOW, batchLimit: 500 });
  check('B sweep', 'scanned exactly the 3 seeded pending rows (>=; a shared DB may carry more)',
    before.scanned >= 3, true);
  check('B sweep', 'materialized at least the 1 real future on_local_date row',
    before.materialized >= 1, true);
  check('B sweep', 'expired at least the 1 real past-beyond-grace row',
    before.expired >= 1, true);
  check('B sweep', 'left at least the 1 config-gap row pending',
    before.stillPending >= 1, true);

  // The seam proof: compare the written row against calling materialize()
  // directly with the identical inputs — never hand-derived DST/zone math.
  const ctx = await childCtxFor(pool, CHILD_R);
  const expected = materialize({
    id: 'probe', childId: CHILD_R, policy: 'on_local_date', state: 'pending',
    expiresAt: NOW.plus({ days: 90 }).toISO(), targetLocalDate: tomorrow, targetDaypart: 'bedtime',
  }, ctx, NOW);
  check('B sweep', 'the future intent really does materialize() ok (sanity)', expected.ok, true);

  const readyRow = (await admin.query(
    `SELECT state, scheduled_at, materialized_tz FROM delivery_intent WHERE id = $1`,
    [INTENT_READY])).rows[0];
  check('B sweep', 'the future intent is now ready', readyRow.state, 'ready');
  check('B sweep', 'its scheduled_at matches materialize()\'s own real answer, to the millisecond',
    expected.ok ? DateTime.fromJSDate(readyRow.scheduled_at).toMillis() : null,
    expected.ok ? expected.scheduledAt.toMillis() : null);
  check('B sweep', 'its materialized_tz matches materialize()\'s own real answer',
    readyRow.materialized_tz, expected.ok ? expected.tz : null);

  const expiredRow = (await admin.query(
    `SELECT state, scheduled_at FROM delivery_intent WHERE id = $1`, [INTENT_EXPIRE])).rows[0];
  check('B sweep', 'the far-past on_local_date intent is now expired', expiredRow.state, 'expired');
  check('B sweep', 'an expired intent is never given a scheduled_at',
    expiredRow.scheduled_at, null);

  const pendingRow = (await admin.query(
    `SELECT state, scheduled_at FROM delivery_intent WHERE id = $1`,
    [INTENT_STILL_PENDING])).rows[0];
  check('B sweep', 'the config-gap intent (no matching day_part) stays pending, not expired',
    pendingRow.state, 'pending');
  check('B sweep', 'it still has no scheduled_at (never falsely materialized)',
    pendingRow.scheduled_at, null);

  // The already_expired branch (materialize.ts:78, fires BEFORE the policy
  // switch for ANY policy) — the earlier version of this suite never
  // actually exercised this specific branch; INTENT_EXPIRE above reaches
  // 'expired' via the separate target_in_past branch instead.
  const alreadyExpiredRow = (await admin.query(
    `SELECT state, scheduled_at FROM delivery_intent WHERE id = $1`,
    [INTENT_ALREADY_EXPIRED])).rows[0];
  check('B sweep', 'a future-dated intent whose expires_at has already passed is expired',
    alreadyExpiredRow.state, 'expired');
  check('B sweep', 'an already_expired intent is never given a scheduled_at',
    alreadyExpiredRow.scheduled_at, null);

  // The at_instant policy — the earlier version of this suite had no
  // fixture for it at all. Directly proves target_instant now round-trips
  // through Postgres as a real, Luxon-parseable ISO-8601 string: before the
  // to_char() fix, this row silently ended up state='ready' with
  // scheduled_at=NULL (an Invalid DateTime's .toISO() is null) — a
  // permanently stuck, unreachable message, never a loud failure.
  const atInstantRow = (await admin.query(
    `SELECT state, scheduled_at FROM delivery_intent WHERE id = $1`,
    [INTENT_AT_INSTANT])).rows[0];
  check('B sweep', 'a real future at_instant intent is now ready', atInstantRow.state, 'ready');
  check('B sweep', 'its scheduled_at is real, non-null, and matches the target instant exactly',
    atInstantRow.scheduled_at ? DateTime.fromJSDate(atInstantRow.scheduled_at).toMillis() : null,
    DateTime.fromISO(atInstantTarget).toMillis());

  // A second sweep must leave the four already-resolved rows alone — only
  // the genuinely still-pending one should be scanned again.
  const after = await runRematerializeSweep(pool, { now: NOW.plus({ hours: 1 }), batchLimit: 500 });
  const stillThere = (await admin.query(
    `SELECT state FROM delivery_intent WHERE id IN ($1, $2, $3, $4)`,
    [INTENT_READY, INTENT_EXPIRE, INTENT_ALREADY_EXPIRED, INTENT_AT_INSTANT])).rows;
  check('B sweep', 'a second sweep never re-touches an already-ready/expired row',
    stillThere.every((r) => r.state === 'ready' || r.state === 'expired'), true);
  check('B sweep', 'the config-gap row is the one still being rescanned every sweep',
    after.scanned >= 1, true);
}

// Clean up every row this suite seeded BEFORE section D runs — D invokes the
// real tools/health-alert.mjs subprocess, which reads the health_check
// view's stalled_delivery probe against the REAL wall clock, not this
// suite's own fixed `NOW`. Section B's rows are deliberately materialized
// relative to a literal timestamp so this suite is deterministic; left in
// place, the 'ready' row's own scheduled_at inevitably falls behind real
// time (it already has, by the time you're reading this comment) and trips
// a real stalled_delivery breach on every future run — not a flake, a
// standing false failure. Reproduced live and fixed 2026-08-24 (round-5
// engineering-systems review).
await clearFixture();

// ===========================================================================
// D · runNamedJob — real job-level lock contention, real subprocess spawn.
//     Two genuinely concurrent invocations of the SAME real job
//     ('health-alert' — a real `node tools/health-alert.mjs` child process,
//     naturally slow enough versus a bare lock acquisition to race reliably).
// ===========================================================================
{
  const [ja, jb] = await Promise.all([
    runNamedJob(pool, DATABASE_URL, 'health-alert'),
    runNamedJob(pool, DATABASE_URL, 'health-alert'),
  ]);
  const skipped = [ja.skipped, jb.skipped].filter(Boolean).length;
  check('D job lock', 'exactly one of two concurrent health-alert job runs is skipped',
    skipped, 1);
  check('D job lock', 'exactly one of the two actually ran the real subprocess',
    [ja.skipped, jb.skipped].filter((s) => s === false).length, 1);
  // Deliberately NOT asserting the WINNER's own ok:true — this suite runs
  // inside tools/verify.sh's single, shared `verify_run` database, and
  // health-alert.mjs's real subprocess reads the health_check view across
  // the WHOLE database, not scoped to any one suite's own fixtures. A real
  // breach left behind by some OTHER suite that ran earlier in the same
  // verify.sh invocation (not this file's own bug, and not a locking bug —
  // reproduced live: this exact assertion failed once, harmlessly, for
  // exactly that reason) would make the winner's real ok:false a CORRECT
  // report, not a defect. `withJobLock`'s own real return-value guarantee
  // (runNamedJob's own source: a skip is unconditionally {ok:true,
  // skipped:true}, line ~324) is what the *skipped* side proves, and IS
  // asserted below, unconditionally.
  const [winner, loser] = ja.skipped ? [jb, ja] : [ja, jb];
  check('D job lock', 'the skipped invocation is always reported ok, never a failure',
    loser.ok, true);
  if (!winner.ok) {
    console.error('D job lock: the real health-alert subprocess reported a genuine '
      + 'breach in the shared verify_run database — not this suite\'s own fixture '
      + '(already cleared above), and not a locking defect. Informational only.');
  }
}

await clearFixture();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
