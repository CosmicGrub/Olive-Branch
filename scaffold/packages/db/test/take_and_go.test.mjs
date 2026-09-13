/**
 * packages/db — child-initiated take-and-go (export + majority handover):
 * real Postgres, real RLS, real server.
 * MASTERFILE §2.10, §2.11, §9.8/§9.8.4, §21.2 rung 17, §21.7, P6/P7/P8.
 *
 * A genuine mirror of deletion.test.mjs's own structure and depth — same
 * posture (requires a real Postgres with every migration applied, DATABASE_URL
 * MUST be a NOSUPERUSER NOBYPASSRLS role — db/DEPLOYMENT.md's app_owner — a
 * probe run as `postgres` measures nothing), not part of `npm test`'s default
 * JS-suite chain for the identical reason.
 *
 * Sections:
 *   A. RLS — export_record_no_child still refuses a 'child'-role session
 *      entirely (read AND write); journal_owner_only admits ONLY the exact
 *      matching child, not 'system' and not a different child.
 *   B. takeAndGo() denials — not_yet_of_age, child_deceased, and (via a
 *      real double-call) already_handed_over — none of them touch anything.
 *   C. takeAndGo() success — the real transaction: her journal/message_log/
 *      delivered messages are all really in the bundle, every guardianship
 *      edge closes with reason 'majority', child.handed_over_at is set,
 *      export_record carries requested_by_child_id (never requested_by),
 *      and the bundle's hash verifies against its own serialized bytes.
 *   D. what does NOT move — a bystander guardian's OWN account is untouched,
 *      and this child's own device_token rows (her tablet's push
 *      registration) survive, unlike a guardian's on deactivation.
 *   E. a real HTTP server (server/index.mjs) — the wrong-child / guardian-
 *      caller / genuinely-successful call, all over real dev-login sessions.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createPool, withSession, withSystemSession, takeAndGo } from '../src/pool.mjs';

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

// Random ids, deliberately — same reasoning deletion.test.mjs's own header
// already gives: a message_log row this suite writes can never be deleted by
// anyone, including its own teardown (P8, the hash-chain trigger), so reused
// fixed ids would either collide or accumulate residue tied to a name every
// future run also tries to claim.
const GUARDIAN_A = randomUUID(); // CHILD_READY's guardian
const GUARDIAN_B = randomUUID(); // CHILD_READY's co-parent
const GUARDIAN_C = randomUUID(); // bystander — never touched by anything below
const CHILD_READY   = randomUUID(); // 19, never handed over — the success path
const CHILD_YOUNG    = randomUUID(); // 10 — not_yet_of_age
const CHILD_DECEASED = randomUUID(); // 30, deceased_at set
const CHILD_RLS      = randomUUID(); // section A's own fixture, untouched otherwise
const CHILD_HTTP     = randomUUID(); // section E's own fixture

const GENESIS = '0'.repeat(64);
const fakeHash = (n) => n.toString(16).padStart(64, '0');

/** ISO date string for someone `years` old today, safely inside the year
 * (July 1) so this suite is never flaky around a real run's own calendar
 * date the way a birthday-adjacent fixture would be. */
const bornYearsAgo = (years) => {
  const d = new Date();
  d.setUTCFullYear(d.getUTCFullYear() - years, 6, 1);
  return d.toISOString().slice(0, 10);
};

async function insertFixtures() {
  await admin.query('BEGIN');
  await admin.query(
    `INSERT INTO app_user (id, display_name, home_tz) VALUES
       ($1,'Guardian A','America/Chicago'),
       ($2,'Guardian B (co-parent)','America/New_York'),
       ($3,'Guardian C (bystander)','America/Denver')`,
    [GUARDIAN_A, GUARDIAN_B, GUARDIAN_C]);

  await admin.query(
    `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
       ($1, 'Wren (ready)', $2, 'America/New_York'),
       ($3, 'Ivy (young)', $4, 'America/New_York'),
       ($5, 'Sam (deceased)', $6, 'America/New_York'),
       ($7, 'Rls-only', $8, 'America/New_York'),
       ($9, 'Http-only', $10, 'America/New_York')`,
    [CHILD_READY, bornYearsAgo(19), CHILD_YOUNG, bornYearsAgo(10),
     CHILD_DECEASED, bornYearsAgo(30), CHILD_RLS, bornYearsAgo(19),
     CHILD_HTTP, bornYearsAgo(19)]);

  await admin.query(`UPDATE child SET deceased_at = now() - interval '1 day' WHERE id = $1`,
    [CHILD_DECEASED]);

  // Two live guardianship edges on CHILD_READY, closed_at IS NULL — both
  // must close when she takes-and-goes. GUARDIAN_C never guards any of these
  // children — the RLS/bystander control.
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
       ($1, $2, 'guardian', '{}', tstzrange(now() - interval '2 years', null)),
       ($1, $3, 'guardian', '{}', tstzrange(now() - interval '2 years', null))`,
    [CHILD_READY, GUARDIAN_A, GUARDIAN_B]);
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
       ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
    [CHILD_HTTP, GUARDIAN_A]);

  // §2.10 — her journal, real and non-empty. journal_owner_only (0001)
  // is the one policy this suite's section A exists to prove admits ONLY an
  // actual matching 'child'-role session.
  await admin.query(
    `INSERT INTO child_journal_entry (child_id, body) VALUES
       ($1, 'a private thought, mine alone'),
       ($1, 'a second one')`,
    [CHILD_READY]);
  await admin.query(
    `INSERT INTO child_journal_entry (child_id, body) VALUES ($1, 'not yours to read')`,
    [CHILD_RLS]);

  // §9.8 — her preserved archive. One preserved, one NOT preserved (with a
  // real expires_at, satisfying the retention-invariant CHECK) — only the
  // preserved one should count toward `artifactsTransferred`.
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, preserved_by, preserved_at)
     VALUES (uuid_generate_v4(), $1, $2, 'drawing', 'archive/goodnight.jpg', now(),
             'America/Chicago', true, $2, now())`,
    [CHILD_READY, GUARDIAN_A]);
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz,
        preserved, expires_at)
     VALUES (uuid_generate_v4(), $1, $2, 'photo', 'ephemeral/one.jpg', now(),
             'America/Chicago', false, now() + interval '30 days')`,
    [CHILD_READY, GUARDIAN_A]);

  // §16.1 #3 / P8 — the parent-to-parent log, real, hash-chained. She can
  // have a COPY (this suite's own C section asserts it lands in her
  // bundle); nothing here or in takeAndGo() ever writes to it.
  await admin.query(
    `INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
     VALUES ($1, 0, $2, 'exchange confirmed for Friday', $3, $4)`,
    [CHILD_READY, GUARDIAN_A, GENESIS, fakeHash(1)]);

  // Delivered/opened content — must appear in her bundle exactly like a
  // guardian's own raw-export pull already asserts (raw_export.test.mjs).
  const di = async (childId, state) => admin.query(
    `INSERT INTO delivery_intent
       (id, child_id, sender_id, payload_kind, payload_ref, policy, state, expires_at)
     VALUES (uuid_generate_v4(), $1, $2, 'video_msg', uuid_generate_v4(), 'immediate', $3,
             now() + interval '30 days')`,
    [childId, GUARDIAN_A, state]);
  await di(CHILD_READY, 'delivered');
  await di(CHILD_READY, 'pending'); // must NOT appear — never delivered

  // Her OWN device — owner_child_id, not owner_user_id. takeAndGo() must
  // leave this untouched (unlike a guardian's device_token on deactivation).
  await admin.query(
    `INSERT INTO device_token (owner_child_id, platform, token) VALUES ($1, 'android', $2)`,
    [CHILD_READY, `tok-${CHILD_READY}`]);

  await admin.query('COMMIT');
}

await insertFixtures();

// ===========================================================================
// A · RLS FIRST — export_record_no_child and journal_owner_only, proven
// against real Postgres before takeAndGo() itself ever runs.
// ===========================================================================
{
  // Real rows exist by now (CHILD_READY hasn't been processed yet at this
  // point in the file, but export_record starts empty regardless — the
  // point here is the ROW-SECURITY FILTER, not row count, so this positive-
  // control insert (as 'system', which passes the policy) proves the table
  // is not simply empty before asserting a child session sees nothing in it.
  await withSystemSession(pool, (q) => q(
    `INSERT INTO export_record (child_id, requested_by, kind, was_free, bundle_hash)
     VALUES ($1, $2, 'raw', true, 'seed') RETURNING id`, [CHILD_RLS, GUARDIAN_A]));

  // A SELECT under a denied USING clause is FILTERED, not an error — see
  // 0012_push_device_token.sql's own empirically-verified comment on exactly
  // this Postgres behavior (RLS filters SELECT; only WITH CHECK on a write
  // actually throws). Asserting zero rows here, not a thrown exception, is
  // the honest shape of what export_record_no_child actually does for reads.
  const childSelect = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD_RLS },
    (q) => q(`SELECT id FROM export_record WHERE child_id = $1`, [CHILD_RLS]));
  check('A rls', 'export_record_no_child filters a plain SELECT under a child-role session '
    + 'to zero rows, even though a real row for this exact child now exists', childSelect.length, 0);

  let insertErrorCode = null;
  try {
    await withSession(pool, { roleName: 'child', userId: null, childId: CHILD_RLS },
      (q) => q(
        `INSERT INTO export_record (child_id, requested_by_child_id, kind, was_free, bundle_hash)
         VALUES ($1, $1, 'raw', true, 'x') RETURNING id`, [CHILD_RLS]));
  } catch (e) { insertErrorCode = e?.code; }
  check('A rls', 'export_record_no_child also refuses a direct INSERT under a child-role session '
    + '(a real 42501, not a silent no-op)', insertErrorCode, '42501');

  const own = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD_RLS },
    (q) => q(`SELECT body FROM child_journal_entry WHERE child_id = $1`, [CHILD_RLS]));
  check('A rls', 'journal_owner_only admits the EXACT matching child (1 row)', own.length, 1);

  const wrongChild = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD_YOUNG },
    (q) => q(`SELECT body FROM child_journal_entry WHERE child_id = $1`, [CHILD_RLS]));
  check('A rls', 'journal_owner_only refuses a DIFFERENT child (0 rows, not an error)',
    wrongChild.length, 0);

  const systemRead = await withSystemSession(pool,
    (q) => q(`SELECT body FROM child_journal_entry WHERE child_id = $1`, [CHILD_RLS]));
  check('A rls', "journal_owner_only refuses 'system' too — it checks role='child' literally, "
    + 'not "any non-guardian role" (this is WHY takeAndGo() opens a real child-role session '
    + 'for this one table)', systemRead.length, 0);
}

// ===========================================================================
// B · takeAndGo() denials — real business-rule refusals, nothing touched.
// ===========================================================================
{
  const young = await takeAndGo(pool, CHILD_YOUNG);
  check('B denials', 'a 10-year-old is refused not_yet_of_age',
    young.ok ? 'ok' : young.reason, 'not_yet_of_age');

  const deceased = await takeAndGo(pool, CHILD_DECEASED);
  check('B denials', 'a deceased child (§18.3) is refused child_deceased, even though '
    + 'she is well past majority age', deceased.ok ? 'ok' : deceased.reason, 'child_deceased');

  const stillOpen = await admin.query(
    `SELECT handed_over_at FROM child WHERE id = ANY($1)`, [[CHILD_YOUNG, CHILD_DECEASED]]);
  check('B denials', 'neither denial touched handed_over_at (both still null)',
    stillOpen.rows.every((r) => r.handed_over_at === null), 'true');

  const unknownId = '00000000-0000-0000-0000-000000000000';
  let notFoundCode = null;
  try { await takeAndGo(pool, unknownId); } catch (e) { notFoundCode = e.code; }
  check('B denials', 'an unknown childId is refused loudly, not silently a no-op',
    notFoundCode, 'child_not_found');
}

// ===========================================================================
// C · takeAndGo() SUCCESS — the real transaction, real assertions.
// ===========================================================================
{
  const result = await takeAndGo(pool, CHILD_READY);
  check('C success', 'ok: true on a real, eligible, never-handed-over adult child',
    result.ok, 'true');

  if (result.ok) {
    const r = result.result;
    check('C success', 'guardianshipsClosed counts both real edges', r.guardianshipsClosed, 2);
    check('C success', 'artifactsTransferred counts only the PRESERVED artifact (1, not 2)',
      r.artifactsTransferred, 1);
    check('C success', 'journalEntriesTransferred counts her real journal (2 entries)',
      r.journalEntriesTransferred, 2);
    check('C success', 'handedOverAt is a real timestamp, not null', r.handedOverAt !== null, 'true');

    // The bundle itself — reused machinery, same shape a guardian's own raw
    // pull gets (raw_export.test.mjs), now attributed to the CHILD.
    check('C success', 'bundle.requestedByUserId is null (never a fabricated guardian id)',
      r.bundle.requestedByUserId, 'null');
    check('C success', 'bundle.requestedByChildId is her own id', r.bundle.requestedByChildId, CHILD_READY);
    check('C success', 'delivered content is in her bundle (1 delivered, the pending one excluded)',
      r.bundle.delivered.length, 1);
    check('C success', 'her journal is REAL in her own bundle (2 entries, not the always-[] '
      + 'a guardian caller of the same machinery gets)', r.bundle.journalEntries.length, 2);
    check('C success', 'the parent-to-parent log is a real copy in her bundle (1 entry) — '
      + '"she can have a copy of everything" (rungs.ts NOT_HERS_TO_DELETE)',
      r.bundle.messageLog.length, 1);
    check('C success', 'the log entry is untouched/authentic', r.bundle.messageLog[0]?.hash, fakeHash(1));

    // Hash integrity — the same "verify from the file alone" contract every
    // other export in this codebase promises.
    const { sha256Hex } = await import('../../ledger/src/sha256.ts');
    check('C success', 'bundleHash verifies against the exact serialized bytes',
      sha256Hex(r.serialized), r.bundleHash);
    check('C success', 're-parsing serialized reproduces the same requestedByChildId',
      JSON.parse(r.serialized).requestedByChildId, CHILD_READY);

    // The database, independently — never just trusting the function's own
    // return value.
    const child = await admin.query(
      `SELECT handed_over_at, deceased_at FROM child WHERE id = $1`, [CHILD_READY]);
    check('C success', 'child.handed_over_at is really set', child.rows[0].handed_over_at !== null, 'true');

    const edges = await admin.query(
      `SELECT closed_at, closed_reason FROM guardianship WHERE child_id = $1`, [CHILD_READY]);
    check('C success', 'every real guardianship row is closed', edges.rows.length, 2);
    check('C success', 'every closed edge carries reason \'majority\'',
      edges.rows.every((e) => e.closed_reason === 'majority'), 'true');
    check('C success', 'every closed edge actually has closed_at set (not just the reason)',
      edges.rows.every((e) => e.closed_at !== null), 'true');

    const rec = await admin.query(
      `SELECT requested_by, requested_by_child_id, kind, was_free, bundle_hash
         FROM export_record WHERE id = $1`, [r.exportRecordId]);
    check('C success', 'export_record.requested_by is NULL for a child-initiated row',
      rec.rows[0].requested_by, 'null');
    check('C success', 'export_record.requested_by_child_id names her, honestly',
      rec.rows[0].requested_by_child_id, CHILD_READY);
    check('C success', "export_record.kind is 'raw' — certified export's own tier/allowance "
      + 'rule is a guardian concept, deliberately not reused here', rec.rows[0].kind, 'raw');
    check('C success', 'export_record.was_free is true — free, same as a guardian raw pull',
      rec.rows[0].was_free, 'true');
    check('C success', 'export_record.bundle_hash matches the returned hash',
      rec.rows[0].bundle_hash, r.bundleHash);
  }

  // Idempotency — a double-tap must fail loudly, not silently repeat (which
  // would close nothing a second time, since closed_at IS NULL already
  // matches zero rows — but must still be reported as a real denial, not a
  // silent "0 closed, 0 transferred, ok:true").
  const second = await takeAndGo(pool, CHILD_READY);
  check('C success', 'a second call is refused, not silently repeated',
    second.ok ? 'ok' : second.reason, 'already_handed_over');
}

// ===========================================================================
// D · what does NOT move.
// ===========================================================================
{
  const bystander = await admin.query(`SELECT deactivated_at FROM app_user WHERE id = $1`,
    [GUARDIAN_C]);
  check('D untouched', "GUARDIAN_C (never her guardian) is entirely untouched",
    bystander.rows[0]?.deactivated_at, 'null');

  const guardianAUntouched = await admin.query(`SELECT deactivated_at FROM app_user WHERE id = $1`,
    [GUARDIAN_A]);
  check('D untouched', "her closed-out guardian's OWN app_user row is untouched — "
    + 'the edge closes, the guardian\'s account does not', guardianAUntouched.rows[0]?.deactivated_at,
    'null');

  const herDevice = await admin.query(
    `SELECT token FROM device_token WHERE owner_child_id = $1`, [CHILD_READY]);
  check('D untouched', "her OWN device_token row survives — it is her tablet's push "
    + 'registration, not a login credential (unlike a guardian on deactivateAccount())',
    herDevice.rows[0]?.token, `tok-${CHILD_READY}`);
}

// ===========================================================================
// E · a real HTTP server, spawned as a real child process running the real
// server/index.mjs + server/routes.mjs against this same database.
// ===========================================================================
{
  const here = dirname(fileURLToPath(import.meta.url));
  const serverEntry = join(here, '..', '..', '..', 'server', 'index.mjs');
  const port = 22000 + (process.pid % 3000);
  const secret = 'take-and-go-test-session-secret-not-for-production-use';

  const child = spawn(process.execPath, [serverEntry], {
    env: { ...process.env, DATABASE_URL, SESSION_SECRET: secret, DEV_LOGIN: '1', PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d.toString(); });
  child.stderr.on('data', (d) => { out += d.toString(); });

  const deadline = Date.now() + 8000;
  while (!out.includes('listening on') && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 50));
  }
  const booted = out.includes('listening on');
  check('E real server', 'server/index.mjs actually boots against this database', booted, 'true');

  if (booted) {
    const base = `http://127.0.0.1:${port}`;
    const postJson = async (path, token, body) => {
      const res = await fetch(`${base}${path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body ?? {}),
      });
      return { status: res.status, body: await res.json() };
    };

    const childLogin = await postJson('/v1/auth/dev-login', null, { childId: CHILD_HTTP });
    check('E real server', 'a real child session can be minted', childLogin.status, 200);
    const childToken = childLogin.body.token;

    const wrongChildLogin = await postJson('/v1/auth/dev-login', null, { childId: CHILD_YOUNG });
    const wrongChildToken = wrongChildLogin.body.token;
    const wrongChildAttempt = await postJson(
      `/v1/children/${CHILD_HTTP}/handover`, wrongChildToken, {});
    check('E real server', 'a DIFFERENT child\'s session cannot take-and-go on this childId',
      wrongChildAttempt.status, 403);
    check('E real server', 'refused with the real reason', wrongChildAttempt.body.error,
      'not_this_child');

    const guardianLogin = await postJson('/v1/auth/dev-login', null, { userId: GUARDIAN_A });
    const guardianToken = guardianLogin.body.token;
    const guardianAttempt = await postJson(
      `/v1/children/${CHILD_HTTP}/handover`, guardianToken, {});
    check('E real server', 'a GUARDIAN session cannot call her child\'s own take-and-go route',
      guardianAttempt.status, 403);
    check('E real server', 'refused with the real reason', guardianAttempt.body.error,
      'not_this_child');

    const noSession = await fetch(`${base}/v1/children/${CHILD_HTTP}/handover`,
      { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    check('E real server', 'no Authorization header at all is refused', noSession.status, 401);

    const real = await postJson(`/v1/children/${CHILD_HTTP}/handover`, childToken, {});
    check('E real server', 'her OWN real session, calling her OWN childId, succeeds',
      real.status, 200);
    check('E real server', 'the real route returns the real bundle', real.body.bundle?.childId,
      CHILD_HTTP);
    check('E real server', 'her guardianship really closed over the real HTTP path',
      real.body.guardianshipsClosed, 1);

    const replay = await postJson(`/v1/children/${CHILD_HTTP}/handover`, childToken, {});
    check('E real server', 'a replay over the real route is refused, not silently repeated',
      replay.status, 403);
    check('E real server', 'refused with the real reason', replay.body.error, 'already_handed_over');
  }

  child.kill();
  await new Promise((r) => setTimeout(r, 200));
}

// ---------------------------------------------------------------------------
// No teardown DELETE — deletion.test.mjs's own header explains why: this
// suite's own message_log row (and everything that now references it — the
// child row, the guardian row) is permanently undeletable by design, in this
// suite's own database same as production.
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
