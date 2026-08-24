/**
 * packages/db — childCtxFor() and persistCapturedMessage(). MASTERFILE §9.5,
 * §5.17/§5.18. db/migrations/0001_phase0_init.sql.
 *
 * Mirrors pool.test.mjs / custody_order.test.mjs's own pattern exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres, and is NOT part of `npm test`'s default JS-suite chain for
 * the same reason those two aren't.
 *
 * Two things this file proves that packages/messaging/test/pipeline.test.mjs
 * alone cannot: captureMessage() is pure and writes nothing, so nothing
 * before this file ever proved its `ok: true` output actually lands as real
 * rows, or that a real `ChildCtx` loaded from Postgres round-trips into
 * exactly the shape materialize() consumes.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
import {
  createPool, childCtxFor, persistCapturedMessage,
} from '../src/pool.mjs';
import { captureMessage } from '../../messaging/src/pipeline.mjs';

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

const CHILD = '77777777-7777-7777-7777-777777777777';
const NOCTX = '88888888-8888-8888-8888-888888888888';   // no tz/day-part rows at all
const DAD = '99999999-9999-9999-9999-999999999999';

await admin.query('BEGIN');
await admin.query(`DELETE FROM delivery_intent WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM media_artifact WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM intent_batch WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM day_part WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM child_tz_interval WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'NoCtx','2018-01-01','America/New_York')`, [CHILD, NOCTX]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD]);
await admin.query(
  `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week,
                        reachable, effective)
   VALUES ($1,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)')`,
  [CHILD]);
await admin.query(
  `INSERT INTO child_tz_interval (child_id, tz, valid, source)
   VALUES ($1, 'America/Chicago', tstzrange('2020-01-01', null), 'manual')`, [CHILD]);
await admin.query('COMMIT');

const edge = (o = {}) => ({ childId: CHILD, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false, validFrom: '2020-01-01T00:00:00Z',
  validTo: null, expiresAt: null, closedAt: null, ladderStep: null, ...o });

// ===========================================================================
// A · childCtxFor — a real ChildCtx, loaded from Postgres
// ===========================================================================
{
  const ctx = await childCtxFor(pool, CHILD);
  check('A childCtxFor', 'a real child resolves', ctx !== null, 'true');
  check('A childCtxFor', 'homeTz round-trips', ctx?.homeTz, 'America/New_York');
  check('A childCtxFor', 'her tz interval overrides home_tz', ctx?.tzIntervals[0]?.tz,
    'America/Chicago');
  check('A childCtxFor', 'an open interval has a null end', ctx?.tzIntervals[0]?.end, 'null');
  check('A childCtxFor', 'day-parts round-trip', ctx?.dayParts.length, 1);
  check('A childCtxFor', 'day-part kind round-trips', ctx?.dayParts[0]?.kind, 'bedtime');
  check('A childCtxFor', 'daysOfWeek is a real array of 7', ctx?.dayParts[0]?.daysOfWeek.length, 7);
  check('A childCtxFor', 'reachable round-trips as a real boolean', ctx?.dayParts[0]?.reachable,
    'true');

  // A real child with no tz/day-part rows at all — honest empty arrays,
  // never a crash, never a guess.
  const bare = await childCtxFor(pool, NOCTX);
  check('A childCtxFor', 'a child with no tz rows gets an empty tzIntervals array',
    bare?.tzIntervals.length, 0);
  check('A childCtxFor', 'a child with no day-parts gets an empty dayParts array',
    bare?.dayParts.length, 0);

  // Honest absence: not a real child at all.
  const missing = await childCtxFor(pool, '00000000-0000-0000-0000-000000000000');
  check('A childCtxFor', 'a nonexistent child gets null, never a guess', missing, 'null');
}

// ===========================================================================
// B · persistCapturedMessage — captureMessage()'s `ok: true` output, as real
//     rows, with the seam (M1 in pipeline.test.mjs) intact end to end.
// ===========================================================================
{
  const ctx = await childCtxFor(pool, CHILD);
  const now = DateTime.fromISO('2026-08-11T18:00:00Z');
  const capture = captureMessage({
    childId: CHILD, senderId: DAD, senderRole: 'guardian',
    storageKey: 'device/reply-1', durationMs: 5300,
    targetLocalDate: null, daypart: 'bedtime', preserve: false,
  }, [edge()], ctx, now);
  check('B persist', 'captureMessage() itself accepts the fixture', capture.ok, 'true');

  const persisted = await persistCapturedMessage(pool, capture);
  check('B persist', 'a real artifact id comes back',
    typeof persisted.artifactId === 'string' && persisted.artifactId.length > 0, 'true');
  check('B persist', 'a real intent id comes back',
    typeof persisted.intentId === 'string' && persisted.intentId.length > 0, 'true');
  check('B persist', 'no batch was requested, so batchId is null', persisted.batchId, 'null');

  const artRows = await admin.query(
    `SELECT child_id, author_id, kind, storage_key, duration_ms, preserved, expires_at
       FROM media_artifact WHERE id = $1`, [persisted.artifactId]);
  check('B persist', 'exactly one media_artifact row landed', artRows.rows.length, 1);
  check('B persist', 'storage_key round-trips', artRows.rows[0]?.storage_key, 'device/reply-1');
  check('B persist', 'kind is video_msg', artRows.rows[0]?.kind, 'video_msg');
  check('B persist', 'author_id is the real sender', artRows.rows[0]?.author_id, DAD);

  const intentRows = await admin.query(
    `SELECT child_id, sender_id, payload_kind, payload_ref, policy, state, expires_at,
            batch_id
       FROM delivery_intent WHERE id = $1`, [persisted.intentId]);
  check('B persist', 'exactly one delivery_intent row landed', intentRows.rows.length, 1);
  check('B persist', 'payload_ref points at the artifact just inserted',
    intentRows.rows[0]?.payload_ref, persisted.artifactId);
  check('B persist', 'policy is at_daypart (no explicit date)', intentRows.rows[0]?.policy,
    'at_daypart');
  check('B persist', 'state starts pending', intentRows.rows[0]?.state, 'pending');
  check('B persist', 'batch_id is null on the row too', intentRows.rows[0]?.batch_id, 'null');

  // THE SEAM, on real rows this time (pipeline.test.mjs's M1 proves the pure
  // computation; this proves it survived the round trip through Postgres).
  const aExp = DateTime.fromJSDate(artRows.rows[0].expires_at);
  const iExp = DateTime.fromJSDate(intentRows.rows[0].expires_at);
  check('B persist', 'the persisted artifact still outlives the persisted intent',
    aExp > iExp, 'true');
}

// ===========================================================================
// C · persistCapturedMessage with opts.newBatch — message banking's shape
// ===========================================================================
{
  const ctx = await childCtxFor(pool, CHILD);
  const now = DateTime.fromISO('2026-08-11T18:00:00Z');
  const capture = captureMessage({
    childId: CHILD, senderId: DAD, senderRole: 'guardian',
    storageKey: 'device/banked-1', durationMs: 4100,
    targetLocalDate: '2026-09-01', daypart: 'bedtime', preserve: true,
  }, [edge()], ctx, now);
  check('C batch', 'captureMessage() accepts the banked fixture', capture.ok, 'true');

  const persisted = await persistCapturedMessage(pool, capture, {
    newBatch: { label: 'Deployment Sep–Feb', reason: 'deployment', cadence: 'daily',
      startsLocal: '2026-09-01', endsLocal: '2027-02-28' },
  });
  check('C batch', 'a real batch id comes back', typeof persisted.batchId === 'string', 'true');

  const batchRows = await admin.query(
    `SELECT child_id, sender_id, label, reason, cadence, daypart
       FROM intent_batch WHERE id = $1`, [persisted.batchId]);
  check('C batch', 'exactly one intent_batch row landed', batchRows.rows.length, 1);
  check('C batch', 'label round-trips', batchRows.rows[0]?.label, 'Deployment Sep–Feb');
  check('C batch', 'daypart is carried from the intent, not hardcoded',
    batchRows.rows[0]?.daypart, 'bedtime');

  const intentRows = await admin.query(
    `SELECT batch_id FROM delivery_intent WHERE id = $1`, [persisted.intentId]);
  check('C batch', 'the delivery_intent row is filed under the new batch',
    intentRows.rows[0]?.batch_id, persisted.batchId);

  const artRows = await admin.query(
    `SELECT preserved, expires_at FROM media_artifact WHERE id = $1`, [persisted.artifactId]);
  check('C batch', 'a preserved artifact has no expiry, even through persistence',
    artRows.rows[0]?.expires_at, 'null');
  check('C batch', 'preserved flag round-trips true', artRows.rows[0]?.preserved, 'true');
}

// ===========================================================================
// D · a CHILD sender — db/migrations/0019_child_message_sender.sql. Proves
//     the identity is correctly RECORDED (real rows, real columns, via the
//     real NOSUPERUSER NOBYPASSRLS `pool` role — the same connection every
//     write above already used, not a superuser standing in for it) and
//     correctly ENFORCED (the CHECK constraints reject a bad row for EVERY
//     role, proven here as `admin`/superuser specifically so the assertion
//     is "even the strongest role cannot write this", not merely "the app
//     role's own queries happen not to try").
//
//     media_artifact/delivery_intent carry no row-level security at all
//     (confirmed: neither name appears in health_check's own `rls_unforced`
//     audit list built by 0008/0013/0014/0017/0018) — a real, pre-existing,
//     DEFERRED gap named in packages/db/src/pool.ts's own persistCaptured
//     Message() header, NOT something this migration or this suite closes.
//     There is no guardian-read RLS policy on these tables to test against;
//     the CHECK constraints below are the real enforcement mechanism this
//     migration actually adds, and what is tested here.
// ===========================================================================
{
  const ctx = await childCtxFor(pool, CHILD);
  const now = DateTime.fromISO('2026-08-11T18:00:00Z');
  const capture = captureMessage({
    childId: CHILD, senderRole: 'child', senderChildId: CHILD,
    storageKey: 'device/child-reply-1', durationMs: 3300,
    targetLocalDate: null, daypart: 'bedtime', preserve: false,
  }, [], ctx, now);   // empty edges — a child holds no edge to herself.
  check('D child sender', 'captureMessage() accepts her own capture', capture.ok, 'true');

  const persisted = await persistCapturedMessage(pool, capture);

  const artRows2 = await admin.query(
    `SELECT author_id, author_child_id FROM media_artifact WHERE id = $1`,
    [persisted.artifactId]);
  check('D child sender', 'author_id is null for a child-authored artifact',
    artRows2.rows[0]?.author_id, 'null');
  check('D child sender', 'author_child_id names the real sending child',
    artRows2.rows[0]?.author_child_id, CHILD);

  const intentRows2 = await admin.query(
    `SELECT sender_id, sender_child_id FROM delivery_intent WHERE id = $1`,
    [persisted.intentId]);
  check('D child sender', 'sender_id is null for a child-originated intent',
    intentRows2.rows[0]?.sender_id, 'null');
  check('D child sender', 'sender_child_id names the real sending child',
    intentRows2.rows[0]?.sender_child_id, CHILD);

  // ENFORCED, not just conventionally true — even a superuser INSERT is
  // refused by the CHECK constraints themselves, for every shape this
  // migration's header describes as unrepresentable.
  const rejects = async (sql, params) => {
    try { await admin.query(sql, params); return 'ALLOWED'; }
    catch (e) { return e.constraint ?? e.message; }
  };

  check('D child sender', 'a row naming BOTH author_id and author_child_id is refused',
    await rejects(
      `INSERT INTO media_artifact
         (child_id, author_id, author_child_id, kind, storage_key,
          captured_at, captured_tz, expires_at)
       VALUES ($1,$2,$3,'video_msg','x','2026-01-01T00:00:00Z','UTC',
               '2026-02-01T00:00:00Z')`,
      [CHILD, DAD, CHILD]),
    'author_is_one_kind');

  check('D child sender', "a row attributing a DIFFERENT child's artifact is refused",
    await rejects(
      `INSERT INTO media_artifact
         (child_id, author_child_id, kind, storage_key,
          captured_at, captured_tz, expires_at)
       VALUES ($1,$2,'video_msg','x','2026-01-01T00:00:00Z','UTC',
               '2026-02-01T00:00:00Z')`,
      [CHILD, NOCTX]),
    'child_author_is_self');

  check('D child sender', 'a delivery_intent naming NEITHER sender_id nor sender_child_id is refused',
    await rejects(
      `INSERT INTO delivery_intent
         (child_id, payload_kind, payload_ref, policy, target_daypart, expires_at)
       VALUES ($1,'video_msg',$2,'at_daypart','bedtime','2026-02-01T00:00:00Z')`,
      [CHILD, persisted.artifactId]),
    'sender_is_exactly_one_kind');

  check('D child sender', 'a delivery_intent naming BOTH sender_id and sender_child_id is refused',
    await rejects(
      `INSERT INTO delivery_intent
         (child_id, sender_id, sender_child_id, payload_kind, payload_ref,
          policy, target_daypart, expires_at)
       VALUES ($1,$2,$3,'video_msg',$4,'at_daypart','bedtime','2026-02-01T00:00:00Z')`,
      [CHILD, DAD, CHILD, persisted.artifactId]),
    'sender_is_exactly_one_kind');

  check('D child sender', "a delivery_intent attributing a DIFFERENT child's send is refused",
    await rejects(
      `INSERT INTO delivery_intent
         (child_id, sender_child_id, payload_kind, payload_ref,
          policy, target_daypart, expires_at)
       VALUES ($1,$2,'video_msg',$3,'at_daypart','bedtime','2026-02-01T00:00:00Z')`,
      [CHILD, NOCTX, persisted.artifactId]),
    'child_sender_is_self');

  // Message banking stays guardian-only (this migration's own header) —
  // persistCapturedMessage() fails loudly rather than reaching intent_
  // batch's raw NOT NULL violation when a child-originated capture is
  // (wrongly) asked to start a batch.
  let batchWithChildSender = 'ALLOWED';
  try {
    await persistCapturedMessage(pool, capture, {
      newBatch: { label: 'x', cadence: 'daily', startsLocal: '2026-09-01',
        endsLocal: '2026-09-02' },
    });
  } catch (e) { batchWithChildSender = e.message; }
  check('D child sender', 'a child-originated capture cannot start a batch',
    batchWithChildSender.includes('cannot start a batch'), 'true');
}

await admin.query(`DELETE FROM delivery_intent WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM media_artifact WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM intent_batch WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM day_part WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM child_tz_interval WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [CHILD, NOCTX]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
