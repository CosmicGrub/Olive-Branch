/**
 * packages/db — certified export: real RLS/authorization, the real annual
 * allowance, and a real tampered-chain refusal, against a real Postgres.
 * MASTERFILE §2.11, §16.1 #3, P8. db/migrations/0006_court_tier.sql,
 * 0013_court_tier_flag.sql. packages/db/src/pool.ts's
 * certifiedExportBundleFor(), server/routes.mjs's
 * GET /v1/children/:childId/export?kind=certified.
 *
 * Mirrors pool.test.mjs / custody_order.test.mjs's own pattern exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness, same "requires
 * a real Postgres, NOT part of `npm test`'s default JS-suite chain" posture —
 * see those files' own headers for why).
 *
 * Sections:
 *   A · RLS/authorization — a guardian with no live edge to a child cannot
 *       certify-export that child (the "first lock," can()+edgesFor(), the
 *       same enforcement point 0007_custody_order.sql documents this
 *       codebase already uses for cross-guardian isolation on these tables
 *       rather than a second per-edge RLS predicate).
 *   B · the real annual allowance — first certified export in a rolling
 *       12-month window is free; a second, still within that window, is
 *       denied without Court tier; setting app_user.court_tier = true makes
 *       it succeed (not free).
 *   C · a tampered chain is refused, not exported. message_log's own
 *       triggers (0006) make this structurally impossible via a normal
 *       INSERT/UPDATE — this section says so explicitly and constructs the
 *       one way to reach a broken chain at all (deliberately disabling the
 *       trigger), rather than faking a test against a state the schema
 *       cannot otherwise produce.
 *   D · route contract — a real `Api` + real `dbPort(pool)` +
 *       server/routes.mjs's actual `registerRoutes()`, hit over
 *       `api.handle()` with real sessions, no fake DbPort anywhere.
 */
import pg from 'pg';
import { createPool, dbPort, certifiedExportBundleFor } from '../src/pool.mjs';
import { append } from '../../ledger/src/ledger.mjs';
import { issueSession } from '../../auth/src/auth.mjs';
import { Api } from '../../api/src/api.mjs';
import { registerRoutes } from '../../../server/routes.mjs';

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

// Seed a minimal real family: a child (IVY) with a live DAD guardian edge
// and a real 2-entry message_log chain; a second, unrelated guardian (MOM)
// with NO edge to IVY at all; a second child (SOLO) with no message_log
// rows, for the empty-chain edge case.
const IVY  = '77777777-7777-4777-8777-777777777777';
const SOLO = '88888888-8888-4888-8888-888888888888';
const DAD  = '99999999-9999-4999-8999-999999999999';
const MOM  = 'aaaaaaaa-1111-4aaa-8aaa-aaaaaaaaaaaa';

/**
 * message_log's `at` column round-trips through pool.ts's own
 * `to_char(at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')` — this
 * fixture builds the chain with `append()` using an `at` string in EXACTLY
 * that shape so the hash `append()` computed here reproduces once read back,
 * and inserts using that same literal string cast to timestamptz.
 */
const AT0 = '2026-06-01T16:00:00.000Z';
const AT1 = '2026-06-01T16:05:00.000Z';

async function seedFamily() {
  await admin.query('BEGIN');
  await admin.query(`DELETE FROM export_record WHERE child_id IN ($1, $2)`, [IVY, SOLO]);
  await admin.query(`DELETE FROM message_log WHERE child_id IN ($1, $2)`, [IVY, SOLO]);
  await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, SOLO]);
  await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, SOLO]);
  await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
  await admin.query(
    `INSERT INTO app_user (id, display_name, home_tz, court_tier) VALUES
       ($1,'Dad','America/Chicago', false), ($2,'Mom','America/New_York', false)`,
    [DAD, MOM]);
  await admin.query(
    `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
       ($1,'Ivy','2016-04-02','America/New_York'),
       ($2,'Solo','2018-01-01','America/New_York')`,
    [IVY, SOLO]);
  // Only DAD guardians IVY. MOM has no edge to her at all.
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
     VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
    [IVY, DAD]);

  const chain = [];
  chain.push(append(chain, { childId: IVY, authorId: DAD, at: AT0, body: 'Pickup moved to 4:30.' }));
  chain.push(append(chain, { childId: IVY, authorId: DAD, at: AT1, body: 'Got it, thanks.' }));
  for (const e of chain) {
    await admin.query(
      `INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [e.childId, e.seq, e.authorId, e.at, e.body, e.prevHash, e.hash]);
  }
  await admin.query('COMMIT');
  return chain;
}

const chain = await seedFamily();

// A · RLS/authorization — the "first lock," real edges, real can().
{

  const nonGuardian = await certifiedExportBundleFor(pool, MOM, IVY, new Date());
  check('A auth', 'a user with NO edge to this child is refused, not served',
    nonGuardian.ok, 'false');
  check('A auth', 'and the real reason is no_edge', nonGuardian.ok ? '' : nonGuardian.reason,
    'no_edge');

  const guardianFirst = await certifiedExportBundleFor(pool, DAD, IVY, new Date());
  check('A auth', "IVY's own guardian CAN certify-export her", guardianFirst.ok, 'true');
  check('A auth', 'the real chain round-trips — 2 entries, not a fixture count',
    guardianFirst.ok ? guardianFirst.chain.length : -1, 2);
  check('A auth', 'entry bodies round-trip verbatim',
    guardianFirst.ok ? guardianFirst.chain[0].body : '', 'Pickup moved to 4:30.');
  check('A auth', 'the head hash matches the in-memory chain built with the SAME entryHash()',
    guardianFirst.ok ? guardianFirst.attestation.headHash : '', chain[1].hash);
  check('A auth', 'chainVerified is true for a real, untampered chain',
    guardianFirst.ok ? guardianFirst.attestation.chainVerified : false, 'true');
  check('A auth', 'the first certified export this year is free',
    guardianFirst.ok ? guardianFirst.free : null, 'true');

  // A child with a real edge but zero message_log rows: an honest empty
  // chain, still verified (verifyChain([]) === ok per ledger.ts), never an
  // error.
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
     VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
    [SOLO, DAD]);
  const emptyChain = await certifiedExportBundleFor(pool, DAD, SOLO, new Date());
  check('A auth', 'a guardian of a child with NO log entries still gets a real (empty) export',
    emptyChain.ok, 'true');
  check('A auth', 'entryCount is honestly 0, not fabricated',
    emptyChain.ok ? emptyChain.attestation.entryCount : -1, 0);
  await admin.query(`DELETE FROM export_record WHERE child_id = $1`, [SOLO]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1 AND user_id = $2`, [SOLO, DAD]);
}

// B · the real annual allowance — authorizeExport()'s real rule, queried,
// not estimated. Depends on A's guardianFirst having already spent IVY/DAD's
// free credit for this rolling 12 months.
{

  const second = await certifiedExportBundleFor(pool, DAD, IVY, new Date());
  check('B allowance', 'a second certified export in the same window is denied',
    second.ok, 'false');
  check('B allowance', 'and the real reason is annual_allowance_used, not a generic error',
    second.ok ? '' : second.reason, 'annual_allowance_used');

  await admin.query(`UPDATE app_user SET court_tier = true WHERE id = $1`, [DAD]);
  const third = await certifiedExportBundleFor(pool, DAD, IVY, new Date());
  check('B allowance', 'the SAME request succeeds once Court tier is set (by hand, as designed)',
    third.ok, 'true');
  check('B allowance', 'and this one is correctly reported as NOT free',
    third.ok ? third.free : null, 'false');

  const recordCount = await admin.query(
    `SELECT count(*)::int AS n, count(*) FILTER (WHERE was_free) AS free_n
       FROM export_record WHERE requested_by = $1 AND child_id = $2 AND kind = 'certified'`,
    [DAD, IVY]);
  check('B allowance', 'exactly 2 certified export_record rows exist (the denial inserted none)',
    recordCount.rows[0].n, 2);
  check('B allowance', 'exactly 1 of them is was_free — the first, never the second',
    recordCount.rows[0].free_n, 1);

  await admin.query(`UPDATE app_user SET court_tier = false WHERE id = $1`, [DAD]);
}

// C · a tampered chain is refused, not exported. STRUCTURALLY UNREACHABLE
// via a normal write — 0006_court_tier.sql's message_log_chain/
// message_log_no_update triggers fire on every role, including the admin
// connection here, so the ONLY way to construct a broken chain at all is to
// deliberately disable them first. Said so explicitly rather than silently
// pretending this state arises from ordinary use.
{

  await admin.query(`DELETE FROM export_record WHERE child_id = $1`, [IVY]);
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_update');
  await admin.query(
    `UPDATE message_log SET body = 'REWRITTEN AFTER THE FACT' WHERE child_id = $1 AND seq = 0`,
    [IVY]);
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_update');

  const tampered = await certifiedExportBundleFor(pool, DAD, IVY, new Date());
  check('C tamper', 'a chain whose content no longer matches its own hash is refused',
    tampered.ok, 'false');
  check('C tamper', 'the real reason is chain_broken, not a crash or a silent export',
    tampered.ok ? '' : tampered.reason, 'chain_broken');
  check('C tamper', 'the real fault (content_altered) is reported, not swallowed',
    tampered.ok ? '' : (tampered.faults ?? []).some(f => f.kind === 'content_altered'), 'true');
  const noRecord = await admin.query(
    `SELECT count(*)::int AS n FROM export_record WHERE child_id = $1`, [IVY]);
  check('C tamper', 'no export_record row was inserted for the refused export',
    noRecord.rows[0].n, 0);

  // Repair the row so later sections (and any re-run of this file) see a
  // real, valid chain again rather than leaving the fixture corrupted.
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_update');
  await admin.query(
    `UPDATE message_log SET body = $2 WHERE child_id = $1 AND seq = 0`,
    [IVY, chain[0].body]);
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_update');
}

// D · route contract — the REAL Api, REAL dbPort(pool), REAL registerRoutes()
// from server/routes.mjs, hit over api.handle() with real signed sessions.
// No fake DbPort anywhere in this section.
{
  await admin.query(`DELETE FROM export_record WHERE child_id = $1`, [IVY]);
  const secret = Buffer.from('test-secret-32-bytes-minimum-ok', 'utf8');
  const api = new Api(secret, dbPort(pool));
  registerRoutes(api, pool);
  const NOW = Date.now();
  const dadTok = issueSession(secret, { userId: DAD, roleName: 'guardian', childId: null,
    escalated: false }, NOW);
  const momTok = issueSession(secret, { userId: MOM, roleName: 'guardian', childId: null,
    escalated: false }, NOW);
  const childTok = issueSession(secret, { userId: null, roleName: 'child', childId: IVY,
    escalated: false }, NOW);
  const hit = (method, path, tok) =>
    api.handle(method, path, tok ? { authorization: `Bearer ${tok}` } : {}, '');

  const missingKind = await hit('GET', `/v1/children/${IVY}/export`, dadTok);
  check('D route', 'no kind= query param -> 400, not a silent 404', missingKind.status, 400);
  check('D route', 'and names the real reason', missingKind.body.error, 'unsupported_kind');

  const rawKind = await hit('GET', `/v1/children/${IVY}/export?kind=raw`, dadTok);
  check('D route', 'kind=raw -> 400 (this build only serves certified here)', rawKind.status, 400);

  const childCall = await hit('GET', `/v1/children/${IVY}/export?kind=certified`, childTok);
  check('D route', 'a child principal is refused -- guardian_only, not a crash',
    childCall.status, 403);
  check('D route', 'and the reason names it plainly', childCall.body.error, 'guardian_only');

  const notAGuardian = await hit('GET', `/v1/children/${IVY}/export?kind=certified`, momTok);
  check('D route', 'a real guardian of a DIFFERENT child is refused over the real route too',
    notAGuardian.status, 403);
  check('D route', 'reason is no_edge end to end', notAGuardian.body.error, 'no_edge');

  const ok = await hit('GET', `/v1/children/${IVY}/export?kind=certified`, dadTok);
  check('D route', 'a real guardian of IVY -> 200 over the real route', ok.status, 200);
  check('D route', 'body carries a real attestation', ok.body.attestation?.entryCount, 2);
  check('D route', 'body carries the real bundle hash', typeof ok.body.bundleHash, 'string');
  check('D route', 'this one is free (the annual credit was reset for this section)',
    ok.body.free, 'true');

  const denied = await hit('GET', `/v1/children/${IVY}/export?kind=certified`, dadTok);
  check('D route', 'a second call this window -> 403 over the real route',
    denied.status, 403);
  check('D route', 'reason is annual_allowance_used, with a plain-language message',
    denied.body.error, 'annual_allowance_used');
  check('D route', 'the denial message never claims a payment flow exists in this build',
    /no payment flow/i.test(denied.body.message ?? ''), 'true');
}

await admin.query(`DELETE FROM export_record WHERE child_id IN ($1, $2)`, [IVY, SOLO]);
await admin.query(`DELETE FROM message_log WHERE child_id IN ($1, $2)`, [IVY, SOLO]);
await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1, $2)`, [IVY, SOLO]);
await admin.query(`DELETE FROM child WHERE id IN ($1, $2)`, [IVY, SOLO]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
