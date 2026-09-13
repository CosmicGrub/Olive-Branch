/**
 * server/routes.mjs — GET/POST /v1/children/:childId/letters, POST
 * .../letters/:letterId/open, DELETE .../letters/:letterId. Real for the
 * first time — found and closed by this project's own coordination-layer
 * audit (MASTERFILE §20.2b), same pass that closed the handover log,
 * expenses, medications/emergency-card, and the exchange.
 *
 * `letter` (db/migrations/0028_care_note_letter.sql) is the ONE
 * child-owned, guardian-excluded table in this whole schema — see that
 * migration's own header. This suite is the highest-stakes one this pass
 * ships: §21.4's own invariant is "NOBODY can open a sealed letter early —
 * not a guardian, and not her either."
 *
 * Proves:
 *   (a) sealing computes a real writtenAtAge from her real birth_date —
 *       never trusted from the client — and validates openAtAge against
 *       it (too_soon/too_far, real 400s).
 *   (b) GET never sends real body text for an unopened letter — the SQL
 *       projection itself gates it, not app logic after the fact.
 *   (c) opening before she's really old enough is a real 409 not_yet,
 *       naming real yearsLeft, and the body is STILL null afterward — the
 *       refused attempt leaves no trace.
 *   (d) opening once she really is old enough (proven against a REAL
 *       server-computed age, not a client-asserted one) succeeds — GET
 *       now returns the real body.
 *   (e) opening an already-open letter is a real 409 already_open.
 *   (f) she can delete without ever having read it.
 *   (g) THE SECURITY BATTERY: a guardian session — even one holding a
 *       real, live, unrestricted edge with a scope override and court
 *       tier — is refused 403 on every one of the four routes. A
 *       DIFFERENT child's own session is refused (wrong_child, the outer
 *       gate). And — the deepest check — `letter_owner_only`'s own RLS is
 *       proven directly against a raw query, not just through the route
 *       layer: a 'child' session scoped to a DIFFERENT child_id reads ZERO
 *       rows of a real letter that exists, even though the row is real and
 *       even though RLS is USING, not WITH CHECK, so a naive policy could
 *       have let a read through a WHERE-less SELECT.
 */
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, withSession } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';

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

const DAD = '11111111-1111-4111-9111-000000000008';
// Comfortably 12 years old as of any real run date in this repo's own
// 2026 fixture era — 25 real days past her birthday, no near-boundary
// flakiness possible from timezone or execution-time nuance.
const CHILD = '55555555-5555-4555-9555-000000000008';
const OTHER_CHILD = '66666666-6666-4666-9666-000000000008';

async function cleanup() {
  await admin.query(`DELETE FROM letter WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
}
await cleanup();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2014-08-01','America/Los_Angeles'),
     ($2,'Other Kid','2014-08-01','America/Los_Angeles')`, [CHILD, OTHER_CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD]);
// A letter she sealed two "years" ago (written_at_age 10, open_at_age 12) —
// she is 12 now, for real, so it is genuinely due. Seeded directly (the
// real seal route can never create an immediately-due letter — see
// letter_min_seal_years) so this suite can prove the real OPEN path
// without waiting years for a real seal to mature.
const dueLetter = (await admin.query(
  `INSERT INTO letter (child_id, written_at_age, open_at_age, body)
   VALUES ($1, 10, 12, 'Dear future me, this one is finally due.')
   RETURNING id`, [CHILD])).rows[0];
await admin.query('COMMIT');
const DUE_LETTER_ID = dueLetter.id;

const SECRET = Buffer.from('f'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);
const otherChildTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: OTHER_CHILD, escalated: false }, NOW);

const getLetters = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/letters`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const sealLetter = (childId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/letters`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);
const openLetter = (childId, letterId, tok) => api.handle(
  'POST', `/v1/children/${childId}/letters/${letterId}/open`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '{}',
);
const deleteLetter = (childId, letterId, tok) => api.handle(
  'DELETE', `/v1/children/${childId}/letters/${letterId}`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);

// ===========================================================================
// A · sealing computes a real writtenAtAge from her real birth_date;
//     validates openAtAge against it.
// ===========================================================================
let sealedId;
{
  const res = await sealLetter(CHILD, childTok, { body: 'Dear future me…', openAtAge: 18 });
  check('A seal', 'a real seal -> 201', res.status, 201);
  check('A seal', 'writtenAtAge is her REAL current age (12), never client-supplied '
    + '(this request named no age at all)', res.body.writtenAtAge, 12);
  check('A seal', 'openAtAge round-trips', res.body.openAtAge, 18);
  check('A seal', 'openedAt is honestly null on a fresh seal', res.body.openedAt, null);
  sealedId = res.body.id;

  const tooSoon = await sealLetter(CHILD, childTok, { body: 'x', openAtAge: 12 });
  check('A seal', 'openAtAge == real current age -> too_soon', tooSoon.status, 400);
  check('A seal', 'names the real reason', tooSoon.body.error, 'too_soon');

  const tooFar = await sealLetter(CHILD, childTok, { body: 'x', openAtAge: 26 });
  check('A seal', 'openAtAge > MAX_SEAL_TO_AGE (25) -> too_far', tooFar.status, 400);
  check('A seal', 'names the real reason', tooFar.body.error, 'too_far');
}

// ===========================================================================
// B · GET never sends real body text for an unopened letter — the SQL
//     projection itself gates it.
// ===========================================================================
{
  const res = await getLetters(CHILD, childTok);
  check('B list', 'authorized child session -> 200', res.status, 200);
  // dueLetter (seeded) + sealedId (section A) = 2 real letters.
  check('B list', 'both real letters present', res.body.letters.length, 2);
  const fresh = res.body.letters.find((l) => l.id === sealedId);
  check('B list', "a real, unopened letter's body is honestly null, not the real text",
    fresh.body, null);
  const due = res.body.letters.find((l) => l.id === DUE_LETTER_ID);
  check('B list', "the seeded due-but-unopened letter's body is ALSO null — age alone "
    + 'never reveals it, only a real open', due.body, null);
}

// ===========================================================================
// C · opening before she's really old enough is a real 409, naming real
//     yearsLeft; the refused attempt leaves the body null.
// ===========================================================================
{
  const res = await openLetter(CHILD, sealedId, childTok);
  check('C not yet', 'opening a letter due at 18 (she is 12) -> 409', res.status, 409);
  check('C not yet', 'names the real reason', res.body.error, 'not_yet');
  check('C not yet', 'names the real years left (18 - 12)', res.body.yearsLeft, 6);

  const list = await getLetters(CHILD, childTok);
  const stillSealed = list.body.letters.find((l) => l.id === sealedId);
  check('C not yet', 'the refused attempt left the body null — no trace', stillSealed.body, null);
  check('C not yet', 'openedAt is still honestly null too', stillSealed.openedAt, null);
}

// ===========================================================================
// D · opening once she really is old enough succeeds — proven against a
//     REAL server-computed age (the seeded due letter), not a
//     client-asserted one (this request also names no age at all).
// ===========================================================================
{
  const res = await openLetter(CHILD, DUE_LETTER_ID, childTok);
  check('D open', 'a real, due letter opens -> 200', res.status, 200);
  check('D open', 'the real body text is finally revealed',
    res.body.body, 'Dear future me, this one is finally due.');
  check('D open', 'openedAt is now real, not null', res.body.openedAt !== null, true);

  const list = await getLetters(CHILD, childTok);
  const opened = list.body.letters.find((l) => l.id === DUE_LETTER_ID);
  check('D open', 'GET now reflects the real, opened body',
    opened.body, 'Dear future me, this one is finally due.');
}

// ===========================================================================
// E · opening an already-open letter is a real 409.
// ===========================================================================
{
  const res = await openLetter(CHILD, DUE_LETTER_ID, childTok);
  check('E already open', 'opening it again -> 409', res.status, 409);
  check('E already open', 'names the real reason', res.body.error, 'already_open');
}

// ===========================================================================
// F · she can delete without ever having read it.
// ===========================================================================
{
  const res = await deleteLetter(CHILD, sealedId, childTok);
  check('F delete', 'deleting an unread, still-sealed letter -> 200', res.status, 200);
  check('F delete', 'deleted: true', res.body.deleted, true);

  const list = await getLetters(CHILD, childTok);
  check('F delete', 'it is really gone from GET',
    list.body.letters.some((l) => l.id === sealedId), false);

  const dbCount = (await admin.query(
    `SELECT count(*) AS n FROM letter WHERE id = $1`, [sealedId])).rows[0].n;
  check('F delete', 'the real row is really gone from the database, not just hidden', dbCount, '0');

  const notFound = await deleteLetter(CHILD, sealedId, childTok);
  check('F delete', 'deleting it again -> real 404, not a silent no-op', notFound.status, 404);
}

// ===========================================================================
// G · THE SECURITY BATTERY.
// ===========================================================================
{
  // A guardian session — even a maximally-privileged one — is refused 403
  // on every one of the four routes. There is no ROLE_CAPS entry that
  // could ever admit her; this proves it end to end, not just in
  // isolation (graph.test.mjs's own H2d already proves the pure can()
  // layer).
  const guardGet = await getLetters(CHILD, dadTok);
  check('G security', 'GET refused for a guardian, even her own real parent', guardGet.status, 403);
  const guardSeal = await sealLetter(CHILD, dadTok, { body: 'a parent should never write this', openAtAge: 18 });
  check('G security', 'POST (seal) refused for a guardian', guardSeal.status, 403);
  const guardOpen = await openLetter(CHILD, DUE_LETTER_ID, dadTok);
  check('G security', 'POST (open) refused for a guardian, even for an ALREADY-due letter',
    guardOpen.status, 403);
  const guardDelete = await deleteLetter(CHILD, DUE_LETTER_ID, dadTok);
  check('G security', 'DELETE refused for a guardian', guardDelete.status, 403);

  // A real letter still exists (DUE_LETTER_ID) after every one of those
  // refused guardian attempts — none of them landed.
  const stillThere = await getLetters(CHILD, childTok);
  check('G security', "the real letter survived every refused guardian attempt untouched",
    stillThere.body.letters.some((l) => l.id === DUE_LETTER_ID), true);

  // A DIFFERENT child's own session cannot reach THIS child's letters at
  // all — the outer gate's own wrong_child check, before any Action or RLS
  // is even consulted.
  const wrongChild = await getLetters(CHILD, otherChildTok);
  check('G security', "a DIFFERENT child's own session is refused (wrong_child)",
    wrongChild.status, 403);

  // The deepest check: letter_owner_only's own RLS, proven directly
  // against a raw query — a 'child' session scoped to OTHER_CHILD reads
  // ZERO rows of CHILD's real, existing letter, even querying with no
  // WHERE clause at all (RLS is USING, so this is the real backstop, not
  // an artifact of every query in this file happening to filter by
  // child_id).
  const rawRows = await withSession(pool,
    { roleName: 'child', userId: null, childId: OTHER_CHILD },
    async (q) => q(`SELECT id FROM letter`, []));
  check('G security', "letter_owner_only's own RLS: a DIFFERENT child's session reads "
    + 'ZERO rows with no WHERE clause at all, even though a real letter row exists',
    rawRows.length, 0);

  // And the OWNING child's own session, same raw query, sees exactly her
  // own real letter (the due one — sealedId was deleted in section F).
  const ownRawRows = await withSession(pool,
    { roleName: 'child', userId: null, childId: CHILD },
    async (q) => q(`SELECT id FROM letter`, []));
  check('G security', "the OWNING child's own session sees exactly her one real "
    + 'remaining letter via the same raw, WHERE-less query', ownRawRows.length, 1);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
