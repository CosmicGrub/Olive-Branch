/**
 * server/routes.mjs — GET/POST /v1/children/:childId/handover-notes. The
 * parent-to-parent handover log, real for the first time — found and
 * closed by this project's own post-tier audit.
 *
 * message_log (db/migrations/0006_court_tier.sql) has had real FORCE RLS
 * (log_no_child), a real append-only trigger, and a real chain-linkage
 * trigger since it was first migrated, and certifiedExportBundleFor()
 * has been able to READ and verify it since v0.14.0 — but nothing
 * anywhere ever WROTE a row. handover_notes.dart's own client UI was pure
 * in-memory local state with zero network calls. Court export's own
 * "backed by the message log" claim had no real production data behind it.
 *
 * Mirrors inbox_route.test.mjs's/presence_route.test.mjs's own pattern —
 * same DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness, same
 * real Api instance — for the identical reason those files' own headers
 * give: a fake q/pool can only prove the route's SHAPE, never whether the
 * real hash-chain trigger (which computes nothing for you, only REJECTS a
 * wrong seq/prevHash) and the real advisory-lock concurrency guard
 * (appendHandoverNote(), packages/db/src/pool.ts) actually do what their
 * own doc comments claim against a real Postgres.
 *
 * Proves:
 *   (a) a real guardian can post a note; the real row lands with a
 *       correctly-computed hash (independently recomputed here via
 *       entryHash(), not just trusted).
 *   (b) a second note correctly chains off the first (prevHash/seq).
 *   (c) GET returns the real chain in order.
 *   (d) a child session is refused for BOTH routes — the real bug this
 *       route's own first draft had for GET, caught before ever shipping.
 *   (e) a guardian with no live edge to this child is refused.
 *   (f) an empty body is refused, never silently accepted as a blank entry.
 *   (g) real concurrency: two near-simultaneous posts for the SAME child
 *       do not corrupt the chain — the advisory lock actually serializes
 *       them, proven by verifyChain() passing on the real result, not by
 *       merely observing no crash.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { entryHash, verifyChain } from '../../packages/ledger/src/ledger.mjs';

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

const DAD = '11111111-1111-4111-9111-000000000001';
const MOM = '22222222-2222-4222-9222-000000000001';
const STRANGER = '33333333-3333-4333-9333-000000000001';
const CHILD = '55555555-5555-4555-9555-000000000001';
const CHILD_STRANGER = '66666666-6666-4666-9666-000000000001';

async function cleanup() {
  // message_log_no_delete (0006_court_tier.sql) rejects EVERY delete
  // unconditionally, P8, no exceptions, not even for the table owner or a
  // superuser — the exact same real constraint court_export.test.mjs's own
  // cleanup already had to work around. `admin` here is the real Postgres
  // superuser (ADMIN_DATABASE_URL), so it can disable/re-enable the
  // trigger for this file's own test-only rows, matching that precedent
  // exactly rather than inventing a second way to do the same thing.
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM message_log WHERE child_id = ANY($1::uuid[])`,
    [[CHILD, CHILD_STRANGER]]);
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`,
    [[CHILD, CHILD_STRANGER]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, CHILD_STRANGER]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, MOM, STRANGER]]);
}
await cleanup();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'Stranger','America/New_York')`,
  [DAD, MOM, STRANGER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/Los_Angeles'),
     ($2,'OtherKid','2016-04-02','America/Los_Angeles')`,
  [CHILD, CHILD_STRANGER]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM]);
await admin.query('COMMIT');

const SECRET = Buffer.from('h'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const momTok = issueSession(SECRET,
  { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
const strangerTok = issueSession(SECRET,
  { userId: STRANGER, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const get = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/handover-notes`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const post = (childId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/handover-notes`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);

// ===========================================================================
// A · a real guardian posts the FIRST note — genesis linkage, a real,
//     independently-recomputed hash.
// ===========================================================================
{
  const res = await post(CHILD, dadTok, { body: 'Running 15 minutes late for pickup.' });
  check('A first note', 'authorized guardian -> 201', res.status, 201);
  check('A first note', 'seq starts at 0', res.body.seq, 0);
  check('A first note', 'authorId is the real caller, not a placeholder',
    res.body.authorId, DAD);
  check('A first note', 'body round-trips verbatim',
    res.body.body, 'Running 15 minutes late for pickup.');
  // POST computes its own whenLabel too (not just GET) -- see that
  // handler's own comment for why a caller that just posted shouldn't have
  // to re-fetch the whole list just to get a real display label for the
  // entry it immediately renders.
  check('A first note', 'POST itself returns a real server-computed whenLabel, '
    + "not left for the caller to somehow format without a timezone package",
    res.body.whenLabel,
    DateTime.fromISO(res.body.at, { zone: 'utc' })
      .setZone('America/Los_Angeles').toFormat('MMM d, h:mm a'));

  const row = (await admin.query(
    `SELECT prev_hash, hash FROM message_log WHERE child_id = $1 AND seq = 0`,
    [CHILD])).rows[0];
  const genesis = '0'.repeat(64);
  check('A first note', 'the real DB row links to genesis, not a guessed value',
    row.prev_hash, genesis);
  // Independently recompute the hash the exact way ledger.ts's own
  // entryHash() does — proves the SERVER computed a real, correct hash,
  // not something this test merely trusts because the route said 201.
  const expectedHash = entryHash({
    seq: 0, childId: CHILD, authorId: DAD, at: res.body.at,
    body: 'Running 15 minutes late for pickup.', prevHash: genesis,
  });
  check('A first note', 'the real stored hash matches an independent recomputation',
    row.hash, expectedHash);
}

// ===========================================================================
// B · a second note from a DIFFERENT guardian correctly chains off the
//     first — real seq/prevHash linkage, not just "didn't error."
// ===========================================================================
{
  const res = await post(CHILD, momTok, { body: "She's got her coat and backpack ready." });
  check('B second note', 'a different guardian can also post -> 201', res.status, 201);
  check('B second note', 'seq advances to 1', res.body.seq, 1);

  const first = (await admin.query(
    `SELECT hash FROM message_log WHERE child_id = $1 AND seq = 0`, [CHILD])).rows[0];
  const second = (await admin.query(
    `SELECT prev_hash FROM message_log WHERE child_id = $1 AND seq = 1`, [CHILD])).rows[0];
  check('B second note', "the second row's prev_hash is the first row's real hash, "
    + 'not recomputed or guessed', second.prev_hash, first.hash);
}

// ===========================================================================
// C · GET returns the real chain, in order, and a real independent
//     verifyChain() pass proves the two entries above genuinely link.
// ===========================================================================
{
  const res = await get(CHILD, dadTok);
  check('C read', 'authorized guardian -> 200', res.status, 200);
  check('C read', 'both entries present, in seq order',
    res.body.entries.map(e => e.seq).join(','), '0,1');
  check('C read', 'the second entry\'s own body round-trips',
    res.body.entries[1].body, "She's got her coat and backpack ready.");
  check('C read', 'authorName is the real joined app_user.display_name, not a bare '
    + 'UUID the client would have no way to render as "Sarah" or "You"',
    res.body.entries[1].authorName, 'Mom');

  // whenLabel: server-computed display label (no timezone package exists in
  // client/pubspec.yaml), resolved in the CHILD's own zone (America/Los_Angeles,
  // this fixture's child.home_tz -- no child_tz_interval row exists for her,
  // so this also exercises the home_tz fallback leg, not just the interval
  // leg). Independently recomputed here via the same Luxon format token
  // string, matching handover_notes.dart's own pre-existing demo fixture
  // shape ("Jul 28, 4:12 PM") -- a real calendar date is correct here (unlike
  // relativeInboxLabel's "sleeps, not dates" wording), since this route's
  // own child-refusal guard above already proves this content never reaches
  // a child's screen in the first place.
  check('C read', "whenLabel is a real server-computed label in the child's own "
    + 'resolved zone, not a raw ISO string left for a client with no timezone '
    + 'package to somehow format itself',
    res.body.entries[1].whenLabel,
    DateTime.fromISO(res.body.entries[1].at, { zone: 'utc' })
      .setZone('America/Los_Angeles').toFormat('MMM d, h:mm a'));

  // to_char(... AT TIME ZONE 'UTC', ...), not a bare ::text cast — this
  // test's own first draft used ::text here and got a real, self-inflicted
  // FAIL: a bare cast renders Postgres's space-separated DateStyle, not
  // ISO-8601, so entryHash()'s own recomputed hash silently disagreed with
  // the real stored one — the exact DateStyle bug class this project has
  // now found and fixed four separate times, this time in a TEST's own
  // verification query rather than production code. loadMessageChain()
  // (packages/db/src/pool.ts) already gets this right; this query has to
  // match it exactly for entryHash() to reproduce the same hash.
  const chainRows = (await admin.query(
    `SELECT seq, author_id AS "authorId",
            to_char(at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS at, body,
            prev_hash AS "prevHash", hash
       FROM message_log WHERE child_id = $1 ORDER BY seq ASC`, [CHILD])).rows
    .map(r => ({ ...r, seq: Number(r.seq), childId: CHILD }));
  const verified = verifyChain(chainRows);
  check('C read', 'a real, independent verifyChain() pass over the real DB rows '
    + 'confirms the chain is genuinely intact, not just "no error was thrown"',
    verified.ok, true);
}

// ===========================================================================
// D · a child session is refused for BOTH routes — the real bug this
//     route's own GET handler had in its first draft (a system-scoped read
//     bypasses log_no_child's RLS, so only an explicit route-level guard
//     stops her), caught before ever shipping.
// ===========================================================================
{
  const getRes = await get(CHILD, childTok);
  check('D child refused', "the child cannot read her parents' own channel -- GET",
    getRes.status, 403);
  check('D child refused', 'no entries leak alongside the refusal',
    getRes.body?.entries, undefined);

  const postRes = await post(CHILD, childTok, { body: 'trying to post anyway' });
  check('D child refused', 'the child cannot post to it either -- POST',
    postRes.status, 403);

  const stillTwo = (await admin.query(
    `SELECT count(*) AS n FROM message_log WHERE child_id = $1`, [CHILD])).rows[0].n;
  check('D child refused', "the refused POST left no trace -- still exactly the two "
    + 'real entries from sections A/B', stillTwo, '2');
}

// ===========================================================================
// E · a guardian with no live edge to this child is refused by the outer
//     action:'message' gate, same as every other route in this file.
// ===========================================================================
{
  const res = await post(CHILD, strangerTok, { body: 'not my child' });
  check('E no edge', 'a guardian with no edge to this child is refused', res.status, 403);
}

// ===========================================================================
// F · an empty body is refused, never silently accepted as a blank entry
//     in a court-tier append-only log.
// ===========================================================================
{
  const res = await post(CHILD, dadTok, { body: '   ' });
  check('F empty body', 'whitespace-only body is refused, not silently trimmed to '
    + 'empty and accepted', res.status, 400);
  const stillTwo = (await admin.query(
    `SELECT count(*) AS n FROM message_log WHERE child_id = $1`, [CHILD])).rows[0].n;
  check('F empty body', 'no row was created for the refused post', stillTwo, '2');
}

// ===========================================================================
// G · real concurrency — two near-simultaneous posts for the SAME child
//     must not corrupt the chain. Proven by a real verifyChain() pass over
//     the real post-concurrency DB state, not by merely observing neither
//     request crashed.
// ===========================================================================
{
  const [r1, r2] = await Promise.all([
    post(CHILD, dadTok, { body: 'concurrent note one' }),
    post(CHILD, momTok, { body: 'concurrent note two' }),
  ]);
  check('G concurrency', 'both concurrent posts succeed -- the advisory lock '
    + 'serializes them rather than one failing outright', `${r1.status},${r2.status}`,
    '201,201');
  check('G concurrency', 'they land on two DISTINCT, contiguous seqs, not the same '
    + 'one twice', new Set([r1.body.seq, r2.body.seq]).size, 2);

  const chainRows = (await admin.query(
    `SELECT seq, author_id AS "authorId",
            to_char(at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS at, body,
            prev_hash AS "prevHash", hash
       FROM message_log WHERE child_id = $1 ORDER BY seq ASC`, [CHILD])).rows
    .map(r => ({ ...r, seq: Number(r.seq), childId: CHILD }));
  check('G concurrency', 'the full chain (4 real entries now) is still genuinely '
    + 'intact after real concurrent writers', verifyChain(chainRows).ok, true);
  check('G concurrency', 'seq is truly contiguous 0..3, no gap the race could have left',
    chainRows.map(r => r.seq).join(','), '0,1,2,3');
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
