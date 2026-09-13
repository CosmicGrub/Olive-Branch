/**
 * packages/db — rawExportBundleFor(): the first writer of db/migrations/
 * 0006_court_tier.sql's `export_record` table, and the real backend behind
 * deletion_screen.dart's "Download raw export" button. MASTERFILE §16.1 #3,
 * §2.11.
 *
 * Mirrors pool.test.mjs / custody_order.test.mjs's own pattern exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres with 0001-0007 applied, and is NOT part of `npm test`'s
 * default JS-suite chain for the same reason those two aren't — a suite that
 * measures RLS run as `postgres` measures nothing (see pool.test.mjs's own
 * header), so DATABASE_URL here MUST be a NOSUPERUSER NOBYPASSRLS role that
 * owns the RLS-protected tables (db/DEPLOYMENT.md's `app_owner`, or an
 * equivalently-configured differently-named role — `app_owner` itself is a
 * cluster-wide role name that concurrent sessions against the same Postgres
 * instance may already be using with a password this session has no way to
 * discover, so this suite was first run against a purpose-created role
 * scoped to its own throwaway database rather than guessing at or resetting
 * shared credentials).
 *
 * Three things this file proves that nothing else in the repository does:
 *
 *   A) THE RLS/SCOPING NEGATIVE — a guardian of a DIFFERENT child gets
 *      exactly nothing back, not a query that merely filtered wrong. This is
 *      the property db/DEPLOYMENT.md's own RLS inventory does NOT cover for
 *      delivery_intent/media_artifact/message_log (see rawExportBundleFor's
 *      own header in pool.ts for why those three tables need this function's
 *      own guardianship check rather than a table policy).
 *   B) export_record IS WRITTEN FOR REAL — kind='raw', was_free=true, and a
 *      bundle_hash that is a genuine sha256 over the exact bundle returned,
 *      independently recomputed here (not merely re-reading the same value
 *      the code under test produced) using packages/ledger/src/sha256.ts,
 *      the same primitive certify() already uses for the certified-export
 *      half of this feature.
 *   C) P7 HOLDS THROUGH THE EXPORT PATH — child_journal_entry contributes
 *      zero rows to a guardian's bundle even though the fixture below seeds a
 *      real entry, proving the export can't accidentally leak the journal.
 *   D) CALL METADATA (0018_call_log.sql) IS REAL IN THE BUNDLE, AND
 *      call_log's OWN RLS (not just this function's app-level checks) IS
 *      WHAT ENFORCES SCOPING — a real gap this pass closes: call_log existed
 *      and was written to (server/routes.mjs's call-start/call-end routes)
 *      but nothing before this queried it FOR an export, despite security.ts's
 *      own compliance ledger claiming the data was "Retained, because §14
 *      court export needs it." Section D below opens raw guardian/child/
 *      system-role sessions directly (bypassing rawExportBundleFor()
 *      entirely) and queries call_log straight, proving `call_log_guardian_
 *      read`/`call_log_system_all` (0018) — not merely the fact that this
 *      file's own SQL always adds `WHERE child_id = $1` — are what a
 *      wrong-child or wrong-role caller actually collides with.
 */
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { createPool, rawExportBundleFor, withSession, withSystemSession } from '../src/pool.mjs';
import { sha256Hex } from '../../ledger/src/sha256.mjs';

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

// A minimal real family: two children (so a cross-child read has something
// real to wrongly return if the scoping check is missing), three guardians —
// MOM has a live edge to IVY only, DAD has an edge to IVY that is CLOSED (so
// group A below has a real "used to be a guardian" case, not just "never
// was one") — and a THIRD child NEO whose guardian STEVE is restricted.
//
// Freshly-generated per run, deliberately, rather than fixed constants like
// the sibling suites use: message_log is append-only under P8
// (0006_court_tier.sql's reject_log_mutation trigger — this file exercises
// that table for real, so it CANNOT clean up after itself the way every
// other fixture below does). Fresh ids make every run collision-free against
// every PRIOR run's now-undeletable log rows, rather than this suite being
// runnable exactly once per database.
const IVY = randomUUID();
const NEO = randomUUID();
const MOM = randomUUID();
const DAD = randomUUID();
const STEVE = randomUUID();
const SENDER = MOM; // messages "from" MOM, so app_user FK is satisfiable

await admin.query('BEGIN');
await admin.query(`DELETE FROM export_record WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM child_journal_entry WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM delivery_intent WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM media_artifact WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM call_log WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2, $3)`, [MOM, DAD, STEVE]);

await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Mom','America/New_York'), ($2,'Dad','America/Chicago'),
     ($3,'Steve','America/Denver')`, [MOM, DAD, STEVE]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Neo','2017-01-01','America/New_York')`, [IVY, NEO]);

// MOM: live guardian of IVY.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [IVY, MOM]);
// DAD: CLOSED guardian of IVY — used to have access, does not now.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid, closed_at, closed_reason)
   VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '2 years', now() - interval '1 month'),
           now() - interval '1 month', 'revoked')`,
  [IVY, DAD]);
// STEVE: RESTRICTED guardian of NEO — a live edge that must still be denied.
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid, restricted)
   VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null), true)`,
  [NEO, STEVE]);

// IVY's real, already-delivered content: one delivered video message backed
// by a real media_artifact, one still-pending intent (must NOT appear — the
// bundle is delivered/opened only), one journal entry (must NOT appear —
// P7), and a real two-entry message_log chain.
const ART = randomUUID();
await admin.query(
  `INSERT INTO media_artifact
     (id, child_id, author_id, kind, storage_key, duration_ms, captured_at, captured_tz, expires_at)
   VALUES ($1, $2, $3, 'video_msg', 'ivy-clip-1', 4200, now(), 'America/New_York', now() + interval '90 days')`,
  [ART, IVY, SENDER]);
await admin.query(
  `INSERT INTO delivery_intent
     (child_id, sender_id, payload_kind, payload_ref, policy, state, materialized_at, expires_at)
   VALUES ($1, $2, 'video_msg', $3, 'immediate', 'delivered', now(), now() + interval '90 days')`,
  [IVY, SENDER, ART]);
await admin.query(
  `INSERT INTO delivery_intent
     (child_id, sender_id, payload_kind, payload_ref, policy, state, expires_at)
   VALUES ($1, $2, 'video_msg', $3, 'immediate', 'pending', now() + interval '90 days')`,
  [IVY, SENDER, ART]);
await admin.query(
  `INSERT INTO child_journal_entry (child_id, body) VALUES ($1, 'a private thought only Ivy should see')`,
  [IVY]);
await admin.query(
  `INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash) VALUES
     ($1, 0, $2, 'pickup moved to 4:30', repeat('0',64), repeat('a',64))`,
  [IVY, MOM]);
await admin.query(
  `INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash) VALUES
     ($1, 1, $2, 'got it, thanks', repeat('a',64), repeat('b',64))`,
  [IVY, DAD]);

// Real call metadata (0018_call_log.sql) — two IVY calls (proving multi-row
// ordering AND field round-tripping, including a genuinely-still-open call
// with no ended_at) plus one NEO call (the cross-child scoping negative,
// section D below), so a bug that dropped the `WHERE child_id = $1` on
// either the export query or the RLS policy itself has something real to
// wrongly leak.
const CALL1 = randomUUID(); // IVY, MOM, ordinary open-ladder call, already ended
const CALL2 = randomUUID(); // IVY, DAD, supervised + recorded, still in progress
const CALL3 = randomUUID(); // NEO, STEVE — must NEVER appear in IVY's bundle
await admin.query(
  `INSERT INTO call_log
     (id, child_id, started_by, participant_ids, room_name, ladder_step, recorded, rang,
      started_at, ended_at)
   VALUES ($1, $2, $3, $4, 'room-ivy-1', 'open', false, true,
           now() - interval '2 days', now() - interval '2 days' + interval '5 minutes')`,
  [CALL1, IVY, MOM, [MOM]]);
await admin.query(
  `INSERT INTO call_log
     (id, child_id, started_by, participant_ids, room_name, ladder_step, recorded, rang,
      started_at, ended_at)
   VALUES ($1, $2, $3, $4, 'room-ivy-2', 'supervised', true, false,
           now() - interval '1 day', null)`,
  [CALL2, IVY, DAD, [MOM, DAD]]);
await admin.query(
  `INSERT INTO call_log
     (id, child_id, started_by, participant_ids, room_name, ladder_step, recorded, rang,
      started_at, ended_at)
   VALUES ($1, $2, $3, $4, 'room-neo-1', 'open', false, true, now(), null)`,
  [CALL3, NEO, STEVE, [STEVE]]);

await admin.query('COMMIT');

// A · THE RLS/SCOPING NEGATIVE
//
// Reasons below are can('export.raw', ...)'s own, real Deny values, not the
// single generic 'not_a_live_guardian' this section asserted before this
// pass: rawExportBundleFor() now runs edgesFor()+can() as a real, first-lock
// RBAC check (see that function's own header for why -- closing the
// per-edge scope['export.raw']===false gap that opened when the ROUTE
// stopped running this same check). can()'s edge-matching is more precise
// than the raw SQL query's single blanket denial ever was: it distinguishes
// "no edge exists at all" from "an edge exists but is closed" from
// "restricted" -- real, useful information the client never saw before.
// The SQL check right after (kept, not removed -- see the function's own
// header) still produces 'not_a_live_guardian' as its own fallback reason,
// but none of these four scenarios reach it now; can() denies each of them
// first.
{
  const asStranger = await rawExportBundleFor(pool, { roleName: 'guardian', userId: DAD, childId: null }, IVY);
  check('A scoping', 'a CLOSED former guardian of IVY is denied (edge_closed), not stale data',
    asStranger.ok === false && asStranger.reason, 'edge_closed');

  const asWrongFamily = await rawExportBundleFor(pool, { roleName: 'guardian', userId: MOM, childId: null }, NEO);
  check('A scoping', 'MOM (a real guardian, but not of NEO) gets no_edge for NEO',
    asWrongFamily.ok === false && asWrongFamily.reason, 'no_edge');
  check('A scoping', 'the denial carries no bundle at all',
    'bundle' in asWrongFamily, 'false');

  const asRestricted = await rawExportBundleFor(pool, { roleName: 'guardian', userId: STEVE, childId: null }, NEO);
  check('A scoping', 'a RESTRICTED (but otherwise live) guardian edge is still denied (restricted)',
    asRestricted.ok === false && asRestricted.reason, 'restricted');

  const asStrangerEntirely = await rawExportBundleFor(
    pool, { roleName: 'guardian', userId: '00000000-0000-4000-8000-000000000099', childId: null }, IVY);
  check('A scoping', 'a userId with no guardianship row at all gets no_edge',
    asStrangerEntirely.ok === false && asStrangerEntirely.reason, 'no_edge');

  let threw = false;
  try { await rawExportBundleFor(pool, { roleName: 'child', userId: null, childId: IVY }, IVY); }
  catch { threw = true; }
  check('A scoping', 'a child principal throws rather than returning a (possibly wrong) bundle',
    threw, 'true');
}

// B · a real, authorized export — MOM, IVY's actual live guardian
let bundleHashUnderTest = '';
let recordIdUnderTest = '';
{
  const result = await rawExportBundleFor(pool, { roleName: 'guardian', userId: MOM, childId: null }, IVY);
  check('B real export', 'a live guardian is authorized', result.ok, 'true');

  const bundle = result.ok ? result.bundle : null;
  check('B real export', 'exactly the one DELIVERED intent, not the pending one',
    bundle?.delivered.length, 1);
  check('B real export', 'the delivered artifact metadata round-trips (storage_key)',
    bundle?.delivered[0]?.artifact?.storageKey, 'ivy-clip-1');
  check('B real export', 'the delivered artifact metadata round-trips (duration_ms)',
    bundle?.delivered[0]?.artifact?.durationMs, 4200);
  check('B real export', 'sender name resolved from app_user',
    bundle?.delivered[0]?.senderName, 'Mom');

  check('B real export', 'P7 — journalEntries is empty despite a real seeded row',
    bundle?.journalEntries.length, 0);

  check('B real export', 'the full 2-entry message_log chain is present',
    bundle?.messageLog.length, 2);
  check('B real export', 'message_log entries are in seq order',
    bundle?.messageLog.map((m) => m.seq).join(','), '0,1');

  // Real call metadata (0018_call_log.sql) — the audit's "single biggest
  // finding" (CHANGELOG v0.49.35): both of IVY's real calls appear, NEO's
  // does not, and every field round-trips exactly.
  check('B real export', "exactly IVY's own two call_log rows appear — NEO's does not",
    bundle?.callLog.length, 2);
  check('B real export', 'call_log entries are in startedAt order (oldest first)',
    bundle?.callLog.map((c) => c.id).join(','), `${CALL1},${CALL2}`);

  check('B real export', 'call metadata: startedBy round-trips for the older call (MOM)',
    bundle?.callLog[0]?.startedBy, MOM);
  check('B real export', 'call metadata: startedByName resolves from app_user (Mom)',
    bundle?.callLog[0]?.startedByName, 'Mom');
  check('B real export', 'call metadata: participantIds round-trips as a real array',
    JSON.stringify(bundle?.callLog[0]?.participantIds), JSON.stringify([MOM]));
  check('B real export', 'call metadata: ladderStep round-trips (open)',
    bundle?.callLog[0]?.ladderStep, 'open');
  check('B real export', 'call metadata: recorded round-trips (false, open-ladder)',
    bundle?.callLog[0]?.recorded, false);
  check('B real export', 'call metadata: rang round-trips (true)',
    bundle?.callLog[0]?.rang, true);
  check('B real export', 'call metadata: endedAt is a real timestamp for a call that really ended',
    bundle?.callLog[0]?.endedAt != null, true);

  check('B real export', 'call metadata: startedBy round-trips for the newer call (DAD)',
    bundle?.callLog[1]?.startedBy, DAD);
  check('B real export', 'call metadata: startedByName resolves from app_user (Dad)',
    bundle?.callLog[1]?.startedByName, 'Dad');
  check('B real export', 'call metadata: a two-guardian participantIds round-trips in full',
    JSON.stringify([...(bundle?.callLog[1]?.participantIds ?? [])].sort()),
    JSON.stringify([MOM, DAD].sort()));
  check('B real export', 'call metadata: ladderStep round-trips (supervised)',
    bundle?.callLog[1]?.ladderStep, 'supervised');
  check('B real export', 'call metadata: recorded round-trips (true) — a supervised call is disclosed',
    bundle?.callLog[1]?.recorded, true);
  check('B real export', 'call metadata: endedAt is null for a call still genuinely in progress',
    bundle?.callLog[1]?.endedAt, 'null');
  check('B real export', "NEO's call never appears in MOM's IVY-scoped bundle",
    (bundle?.callLog ?? []).some((c) => c.id === CALL3), false);

  check('B real export', 'requestedByUserId is the real caller, not a placeholder',
    bundle?.requestedByUserId, MOM);

  if (result.ok) { bundleHashUnderTest = result.bundleHash; recordIdUnderTest = result.recordId; }

  // C · export_record really written, was_free=true, hash independently
  // verifiable — recomputed HERE from the returned bundle with the SAME
  // primitive certify() uses, not merely trusting the field the code under
  // test handed back.
  const recomputedHash = sha256Hex(JSON.stringify(bundle));
  check('C ledger', 'bundle_hash is a genuine, independently-recomputed sha256 of the bundle',
    result.ok && result.bundleHash, recomputedHash);
  check('C ledger', 'bundle_hash is well-formed lowercase hex sha256 (64 chars)',
    /^[0-9a-f]{64}$/.test(bundleHashUnderTest), 'true');
  check('C ledger', 'the exposed `serialized` string hashes to the SAME bundleHash — this is '
    + 'exactly what the client hashes and writes to disk, so it must be byte-identical',
    result.ok && sha256Hex(result.serialized), bundleHashUnderTest);
  check('C ledger', '`serialized` really is JSON — parses back to an equivalent bundle',
    result.ok && JSON.parse(result.serialized).requestedByUserId, bundle?.requestedByUserId);

  const recordRows = await admin.query(
    `SELECT child_id, requested_by, kind, was_free, bundle_hash, head_hash
       FROM export_record WHERE id = $1`, [recordIdUnderTest]);
  check('C ledger', 'export_record row actually exists', recordRows.rows.length, 1);
  check('C ledger', 'kind is raw', recordRows.rows[0]?.kind, 'raw');
  check('C ledger', 'was_free is true — §2.11, never held hostage', recordRows.rows[0]?.was_free, 'true');
  check('C ledger', 'requested_by is the real caller', recordRows.rows[0]?.requested_by, MOM);
  check('C ledger', 'child_id matches', recordRows.rows[0]?.child_id, IVY);
  check('C ledger', 'the persisted bundle_hash matches what the function returned',
    recordRows.rows[0]?.bundle_hash, bundleHashUnderTest);

  // A second export creates a SECOND row (raw is unlimited — §16.1 #3), not
  // an upsert/reuse of the first.
  const second = await rawExportBundleFor(pool, { roleName: 'guardian', userId: MOM, childId: null }, IVY);
  const countRows = await admin.query(
    `SELECT count(*)::int AS n FROM export_record WHERE child_id = $1 AND requested_by = $2`, [IVY, MOM]);
  check('C ledger', 'raw export is unlimited — a second pull writes a second row, not zero new ones',
    second.ok && countRows.rows[0].n, 2);
}

// D · call_log's OWN RLS, proven directly — bypassing rawExportBundleFor()/
// assembleRawExportBundle() entirely and querying call_log straight, under
// real sessions opened with `withSession`/`withSystemSession` (the same
// primitives pool.ts uses everywhere). This is the direct analogue of
// section C's P7 proof above: it shows `call_log_guardian_read` and
// `call_log_system_all` (0018) are what actually blocks a wrong caller, not
// merely that every query in this codebase happens to remember its own
// `WHERE child_id = $1`.
{
  const asClosedGuardian = await withSession(
    pool, { roleName: 'guardian', userId: DAD, childId: null },
    (q) => q('SELECT id FROM call_log WHERE child_id = $1', [IVY]));
  check('D call_log RLS', 'a CLOSED former guardian of IVY reading call_log directly gets zero rows, '
    + 'even though 2 real IVY rows exist — call_log_guardian_read, not just app logic, blocks this',
    asClosedGuardian.length, 0);

  const asNoEdgeAtAll = await withSession(
    pool, { roleName: 'guardian', userId: STEVE, childId: null },
    (q) => q('SELECT id FROM call_log WHERE child_id = $1', [IVY]));
  check('D call_log RLS', "STEVE (a real guardian, but of NEO — no edge to IVY at all) reading "
    + "IVY's call_log directly gets zero rows",
    asNoEdgeAtAll.length, 0);

  const asChildRole = await withSession(
    pool, { roleName: 'child', userId: null, childId: IVY },
    (q) => q('SELECT id FROM call_log WHERE child_id = $1', [IVY]));
  check('D call_log RLS', "a 'child'-role session reading her OWN call_log directly gets zero rows — "
    + '0018\'s own header: "the child never reads or writes this table directly", no policy admits it',
    asChildRole.length, 0);

  const asLiveGuardian = await withSession(
    pool, { roleName: 'guardian', userId: MOM, childId: null },
    (q) => q('SELECT id FROM call_log WHERE child_id = $1 ORDER BY started_at ASC', [IVY]));
  check('D call_log RLS', 'positive control — MOM, a real LIVE guardian of IVY, reading call_log '
    + 'directly gets both real rows (proves the negatives above are the policy, not a broken table)',
    asLiveGuardian.map((r) => r.id).join(','), `${CALL1},${CALL2}`);

  const asSystem = await withSystemSession(
    pool, (q) => q('SELECT id FROM call_log WHERE child_id = $1 ORDER BY started_at ASC', [IVY]));
  check('D call_log RLS', "system-role (takeAndGo()'s own session kind) also reads both real rows "
    + '— call_log_system_all admits it unconditionally',
    asSystem.map((r) => r.id).join(','), `${CALL1},${CALL2}`);
}

// message_log is deliberately NOT cleaned up here — see the fixture comment
// above (P8, append-only). Its two FOREIGN KEYs are both ON DELETE RESTRICT
// (child_id and author_id), which is P8 protecting itself one layer further
// than the trigger alone: even a superuser cannot delete-around the trigger
// by deleting the PARENT rows out from under a log entry either. That
// RESTRICT is real and this cleanup respects it rather than working around
// it — IVY/NEO (referenced by child_id) and MOM/DAD (referenced by
// author_id) are left in place; only STEVE (never an author) and every
// table with no such restriction are torn down.
await admin.query(`DELETE FROM export_record WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM child_journal_entry WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM delivery_intent WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM media_artifact WHERE child_id IN ($1, $2)`, [IVY, NEO]);
// call_log has no P8-style delete restriction (0018's own header: not
// append-only, not hash-chained) — cleaned up like any other table, and
// BEFORE the app_user delete below, since CALL3's started_by references
// STEVE (REFERENCES app_user(id), default RESTRICT).
await admin.query(`DELETE FROM call_log WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, NEO]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [STEVE]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
