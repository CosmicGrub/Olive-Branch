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
 * Four things proven here (a fourth, C, added when runMediaReapSweep()
 * closed the separate "reap() has no production caller" gap this file's
 * own first version missed — see tools/scheduler.mjs's own header):
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
 *   C) MEDIA REAP CORRECTNESS — five real media_artifact rows (due,
 *      preserved, not-yet-due, already-tombstoned, and a blob whose delete
 *      is made to fail) swept once against `artifacts_due_for_reaping()`
 *      and a real `reap_tombstone` table, proving: an expired row's blob
 *      AND row both go; a preserved row is excluded by the SQL WHERE
 *      clause itself (never even reaches reap()'s own belt-and-braces
 *      check — see this section's own comment on why); a future row is
 *      untouched; an already-tombstoned row is excluded by the SQL
 *      `NOT EXISTS`, not re-attempted; and a blob delete failure leaves the
 *      row in place and writes a real reap_tombstone row, per reap()'s own
 *      "blob first, then row" design.
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
  withJobLock, runRematerializeSweep, runMediaReapSweep, runNamedJob,
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

  // runRematerializeSweep() is, correctly, GLOBAL — it has no child_id scope
  // of its own, matching the real production job (tools/scheduler.mjs's own
  // header: it sweeps every pending delivery_intent row, not just one
  // child's). Inside tools/verify.sh's single shared `verify_run` database,
  // that means it also touches every OTHER suite's own leftover 'pending'
  // fixture rows (db/test/0001_constraints.test.sql's must_pass probes in
  // particular — real, permanent INSERTs, never rolled back or cleaned up,
  // because nothing had ever swept the WHOLE table before this file existed
  // to prove that sweep is real). Reproduced live: a fresh tools/verify.sh
  // run genuinely tripped health_check's own stalled_delivery breach this
  // way, sourced from other suites' rows this test's own materialize() call
  // legitimately (and correctly) advanced to 'ready'/'expired' — not a bug
  // in the sweep, a real, previously-invisible side effect of it existing
  // at all. Those other suites' own assertions already ran and passed
  // before this file ever executes (verify.sh's suite ordering), so
  // touching their leftover rows breaks nothing there; but leaving them
  // 'ready'/'expired' afterward pollutes the shared database for the
  // Health check that runs once every suite is done. Snapshot every
  // non-CHILD_R pending row now, before the real, global sweep runs it —
  // restored (deleted, not left mutated) once every sweep in this file has
  // finished, immediately below.
  const foreignPendingIds = (await admin.query(
    `SELECT id FROM delivery_intent WHERE state = 'pending' AND child_id != $1`,
    [CHILD_R],
  )).rows.map((r) => r.id);

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

  // Restore every OTHER suite's own leftover 'pending' row the sweep above
  // legitimately (and correctly) just materialized to 'ready'/'expired' —
  // see this section's own opening comment on `foreignPendingIds` for the
  // full reasoning: a real, global sweep touching real leftover fixture
  // rows from suites that already ran and already passed, not a bug in the
  // sweep itself. Deleted, not reset back to 'pending' — this codebase has
  // no way to know what state a stranger's row "should" be in, and every
  // suite that created these rows has already finished using them by this
  // point in verify.sh's own suite order. Inside this block, not after it
  // — foreignPendingIds is block-scoped to section B (a real ReferenceError
  // caught this the first time it was written outside the block).
  if (foreignPendingIds.length) {
    await admin.query(`DELETE FROM delivery_intent WHERE id = ANY($1::uuid[])`,
      [foreignPendingIds]);
  }
}

// ===========================================================================
// C · runMediaReapSweep — real media_artifact rows, real artifacts_due_
//     for_reaping()/reap_tombstone, a fake StoragePort standing in only for
//     the parts reap() actually calls (storage.delete()) — MemoryStorage/
//     FilesystemStorage's own real disk/memory behavior is already proven
//     in storage.test.mjs and stack.test.mjs; this section proves the SEAM
//     (the SQL candidate query + the tombstone write path), the same
//     division of labor section B draws for materialize().
// ===========================================================================
{
  // A real, non-fixed "now" — unlike section B's deliberately-fixed NOW
  // (chosen so materialize() is deterministic), artifacts_due_for_reaping()
  // filters on the DATABASE's own real now(), not an injectable value (see
  // tools/scheduler.mjs's own comment on dueForReaping() for why that is
  // the correct choice for a production sweep). Fixture timestamps below
  // are offset by days specifically so ordinary test latency and any
  // client/server clock skew can never flip which side of "due" they land
  // on.
  const REAL_NOW = DateTime.utc();
  const MEDIA_DUE = 'a0000000-0000-0000-0000-0000000000c1';
  const MEDIA_PRESERVED = 'a0000000-0000-0000-0000-0000000000c2';
  const MEDIA_FUTURE = 'a0000000-0000-0000-0000-0000000000c3';
  const MEDIA_TOMBSTONE_SKIP = 'a0000000-0000-0000-0000-0000000000c4';
  const MEDIA_DELETE_FAILS = 'a0000000-0000-0000-0000-0000000000c5';
  const KEY_DUE = `children/${CHILD_R}/reap-test/due.jpg`;
  const KEY_PRESERVED = `children/${CHILD_R}/reap-test/preserved.jpg`;
  const KEY_FUTURE = `children/${CHILD_R}/reap-test/future.jpg`;
  const KEY_TOMBSTONE_SKIP = `children/${CHILD_R}/reap-test/tombstone-skip.jpg`;
  const KEY_DELETE_FAILS = `children/${CHILD_R}/reap-test/delete-fails.jpg`;

  // child/app_user rows from section B are still live — clearFixture() has
  // not run yet at this point in the file.
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, expires_at)
     VALUES ($1, $2, $3, 'photo', $4, now(), 'America/New_York', false, $5::timestamptz)`,
    [MEDIA_DUE, CHILD_R, DAD, KEY_DUE, REAL_NOW.minus({ days: 1 }).toISO()]);
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, preserved_by, preserved_at, expires_at)
     VALUES ($1, $2, $3, 'photo', $4, now(), 'America/New_York', true, $3, now(), NULL)`,
    [MEDIA_PRESERVED, CHILD_R, DAD, KEY_PRESERVED]);
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, expires_at)
     VALUES ($1, $2, $3, 'photo', $4, now(), 'America/New_York', false, $5::timestamptz)`,
    [MEDIA_FUTURE, CHILD_R, DAD, KEY_FUTURE, REAL_NOW.plus({ days: 30 }).toISO()]);
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, expires_at)
     VALUES ($1, $2, $3, 'photo', $4, now(), 'America/New_York', false, $5::timestamptz)`,
    [MEDIA_TOMBSTONE_SKIP, CHILD_R, DAD, KEY_TOMBSTONE_SKIP, REAL_NOW.minus({ days: 2 }).toISO()]);
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, expires_at)
     VALUES ($1, $2, $3, 'photo', $4, now(), 'America/New_York', false, $5::timestamptz)`,
    [MEDIA_DELETE_FAILS, CHILD_R, DAD, KEY_DELETE_FAILS, REAL_NOW.minus({ days: 1 }).toISO()]);

  // A pre-existing tombstone for MEDIA_TOMBSTONE_SKIP — proves the SQL
  // function's own `NOT EXISTS (SELECT 1 FROM reap_tombstone ...)` clause
  // really excludes an already-tombstoned row from the candidate set,
  // rather than re-attempting it (and re-incrementing `attempts`) every
  // single sweep.
  await admin.query(
    `INSERT INTO reap_tombstone (artifact_id, storage_key, error, attempts)
     VALUES ($1, $2, 'pre-existing tombstone, seeded to prove exclusion', 3)`,
    [MEDIA_TOMBSTONE_SKIP, KEY_TOMBSTONE_SKIP]);

  // Same shared-database caution section B's own foreignPendingIds comment
  // documents, applied to media_artifact instead of delivery_intent: this
  // sweep is correctly GLOBAL, so if any OTHER suite's own leftover fixture
  // happens to carry a real past expires_at, it is swept too — genuinely
  // correct reaper behavior, not a bug, but worth surfacing rather than
  // silently absorbing into this suite's own counts. No other suite in
  // this repo seeds media_artifact with a deliberately past expires_at (all
  // use now()+interval future dates, matching production's own real
  // default), so this is expected to be empty in practice.
  const foreignDueIds = (await admin.query(
    `SELECT m.id FROM media_artifact m
      WHERE m.preserved = false AND m.expires_at IS NOT NULL AND m.expires_at <= now()
        AND m.child_id != $1
        AND NOT EXISTS (SELECT 1 FROM reap_tombstone t WHERE t.artifact_id = m.id)`,
    [CHILD_R])).rows.map((r) => r.id);
  if (foreignDueIds.length) {
    console.error(`C reap: note — ${foreignDueIds.length} foreign media_artifact row(s) `
      + 'are also due for reaping in this shared database; the sweep below will delete '
      + 'them for real (correct behavior, not this suite\'s bug) — informational only.');
  }

  // A minimal, fake StoragePort — reap() only ever calls storage.delete(),
  // so that is the only method this needs to implement for real. Throws for
  // exactly one key, to prove the tombstone write path without needing a
  // real, flaky I/O failure.
  const deletedKeys = [];
  const fakeStorage = {
    async delete(key) {
      if (key === KEY_DELETE_FAILS) throw new Error('simulated blob delete failure');
      deletedKeys.push(key);
      return true;
    },
  };

  const result = await runMediaReapSweep(pool, fakeStorage, { now: REAL_NOW.toJSDate(), limit: 500 });

  check('C reap', 'examined at least the 2 real due rows (>=; a shared DB may carry more)',
    result.examined >= 2, true);
  check('C reap', 'deleted at least the 1 blob that should succeed',
    result.blobsDeleted >= 1, true);
  check('C reap', 'the due row\'s blob was actually handed to storage.delete()',
    deletedKeys.includes(KEY_DUE), true);
  check('C reap', 'the delete-fails row\'s blob was attempted, not skipped',
    result.tombstoned.includes(MEDIA_DELETE_FAILS), true);

  const dueRow = (await admin.query(
    `SELECT 1 FROM media_artifact WHERE id = $1`, [MEDIA_DUE])).rows;
  check('C reap', 'the due row is actually gone from media_artifact', dueRow.length, 0);

  const preservedRow = (await admin.query(
    `SELECT 1 FROM media_artifact WHERE id = $1`, [MEDIA_PRESERVED])).rows;
  check('C reap', 'the preserved row survives untouched — excluded by the SQL WHERE '
    + 'clause itself (preserved=false), never even reaching reap()\'s own belt-and-'
    + 'braces skippedPreserved check', preservedRow.length, 1);
  check('C reap', 'a preserved row was never handed to storage.delete()',
    deletedKeys.includes(KEY_PRESERVED), false);

  const futureRow = (await admin.query(
    `SELECT 1 FROM media_artifact WHERE id = $1`, [MEDIA_FUTURE])).rows;
  check('C reap', 'the not-yet-due row survives untouched', futureRow.length, 1);
  check('C reap', 'a not-yet-due row was never handed to storage.delete()',
    deletedKeys.includes(KEY_FUTURE), false);

  const tombstoneSkipRow = (await admin.query(
    `SELECT 1 FROM media_artifact WHERE id = $1`, [MEDIA_TOMBSTONE_SKIP])).rows;
  check('C reap', 'an already-tombstoned row survives untouched — excluded by the SQL '
    + 'NOT EXISTS, not re-attempted', tombstoneSkipRow.length, 1);
  const tombstoneSkipAttempts = (await admin.query(
    `SELECT attempts FROM reap_tombstone WHERE artifact_id = $1`, [MEDIA_TOMBSTONE_SKIP])).rows[0];
  check('C reap', 'its pre-existing tombstone attempts count is unchanged, not re-incremented',
    tombstoneSkipAttempts.attempts, 3);

  const deleteFailsRow = (await admin.query(
    `SELECT 1 FROM media_artifact WHERE id = $1`, [MEDIA_DELETE_FAILS])).rows;
  check('C reap', 'a row whose blob delete failed survives — "blob first, then row" '
    + 'means a failed blob delete must never lose the row too', deleteFailsRow.length, 1);
  const tombstoneRow = (await admin.query(
    `SELECT attempts, error FROM reap_tombstone WHERE artifact_id = $1`,
    [MEDIA_DELETE_FAILS])).rows[0];
  check('C reap', 'a real reap_tombstone row was written for the failed delete',
    tombstoneRow?.attempts, 1);
  check('C reap', 'it records the real error message, not a placeholder',
    tombstoneRow?.error, 'simulated blob delete failure');

  // A second sweep must leave the surviving rows alone and not re-tombstone
  // the one already-tombstoned by the first sweep, above — proving the
  // NOT EXISTS exclusion applies to a tombstone THIS run just wrote, not
  // only to one seeded ahead of time.
  const second = await runMediaReapSweep(pool, fakeStorage, { now: REAL_NOW.toJSDate(), limit: 500 });
  const tombstoneRowAfter = (await admin.query(
    `SELECT attempts FROM reap_tombstone WHERE artifact_id = $1`, [MEDIA_DELETE_FAILS])).rows[0];
  check('C reap', 'a second sweep does not re-attempt an artifact this run already '
    + 'tombstoned', tombstoneRowAfter.attempts, 1);
  check('C reap', 'a second sweep genuinely finds fewer candidates than the first',
    second.examined < result.examined, true);

  // Clean up this section's own rows — the survivors (preserved/future/
  // tombstone-skip/delete-fails) and their tombstone row(s), since the DUE
  // row already deleted itself via the sweep. clearFixture() below only
  // ever targets delivery_intent/day_part/child_tz_interval/guardianship/
  // child/app_user, never media_artifact, so this suite is responsible for
  // its own media rows specifically.
  await admin.query(`DELETE FROM reap_tombstone WHERE artifact_id = ANY($1::uuid[])`,
    [[MEDIA_TOMBSTONE_SKIP, MEDIA_DELETE_FAILS]]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = $1`, [CHILD_R]);
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
