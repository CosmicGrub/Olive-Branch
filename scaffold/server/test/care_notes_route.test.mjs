/**
 * server/routes.mjs — GET/POST /v1/children/:childId/care-notes. Real for
 * the first time — found and closed by this project's own coordination-layer
 * audit (MASTERFILE §20.2b), same pass that closed the handover log,
 * expenses, medications/emergency-card, and the exchange.
 *
 * `care_note` (db/migrations/0028_care_note_letter.sql) has real FORCE RLS
 * (`care_note_no_child`) — but nothing anywhere ever wrote or read a row.
 * care_note.dart's own client UI was pure in-memory local state with zero
 * network calls.
 *
 * Proves:
 *   (a) GET returns the real seeded (not-yet-expired) notes, newest first.
 *   (b) POST records a real note; GET reflects it, with a real joined
 *       fromUserName and a real, server-computed expiresAt (createdAt + 7
 *       real days) — never a client-supplied one.
 *   (c) the real tone guard (packages/guardian/src/guardian.ts's
 *       CARE_NOTE_BANNED) runs server-side, before the row is ever
 *       written — a real 400, naming the real phrase found, and the
 *       refused note leaves no trace in the database.
 *   (d) an empty note is refused the same way.
 *   (e) role distinctions: a sitter can write; a step_parent can view but
 *       not write; a coordinator cannot even view (deliberately outside
 *       the court-tier record — care_note.dart's own file header).
 *   (f) an EXPIRED note (seeded directly, past its own real expires_at) is
 *       excluded from GET — the real 7-day TTL, not just a client-side
 *       filter.
 *   (g) a child session is refused for every route.
 */
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
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

const DAD = '11111111-1111-4111-9111-000000000007';
const MOM = '22222222-2222-4222-9222-000000000007';
const SITTER = '77777777-7777-4777-9777-000000000007';
const STEP = '88888888-8888-4888-9888-000000000007';
const COORDINATOR = '44444444-4444-4444-9444-000000000007';
const CHILD = '55555555-5555-4555-9555-000000000007';

async function cleanup() {
  await admin.query(`DELETE FROM care_note WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`,
    [[DAD, MOM, SITTER, STEP, COORDINATOR]]);
}
await cleanup();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'Sitter Sue','America/New_York'), ($4,'Stepdad Sam','America/New_York'),
     ($5,'Coordinator Cara','America/New_York')`,
  [DAD, MOM, SITTER, STEP, COORDINATOR]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/Los_Angeles')`, [CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $4, 'sitter', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $5, 'step_parent', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $6, 'coordinator', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, SITTER, STEP, COORDINATOR]);
// An already-expired note, seeded directly — proves the real TTL filter,
// not just something this suite's own writes happen to satisfy.
await admin.query(
  `INSERT INTO care_note (child_id, from_user_id, items, created_at, expires_at)
   VALUES ($1, $2, '[{"kind":"mood","note":"old news"}]'::jsonb,
           now() - interval '10 days', now() - interval '3 days')`,
  [CHILD, DAD]);
await admin.query('COMMIT');

const SECRET = Buffer.from('d'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const sitterTok = issueSession(SECRET,
  { userId: SITTER, roleName: 'sitter', childId: null, escalated: false }, NOW);
const stepTok = issueSession(SECRET,
  { userId: STEP, roleName: 'step_parent', childId: null, escalated: false }, NOW);
const coordinatorTok = issueSession(SECRET,
  { userId: COORDINATOR, roleName: 'coordinator', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const getNotes = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/care-notes`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const postNote = (childId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/care-notes`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);

// ===========================================================================
// A · GET returns only the real, not-yet-expired note(s) — the seeded
//     expired one is excluded (real TTL filter, section F re-confirms this).
// ===========================================================================
{
  const res = await getNotes(CHILD, dadTok);
  check('A list', 'authorized guardian -> 200', res.status, 200);
  check('A list', 'the already-expired seeded note is excluded', res.body.entries.length, 0);
}

// ===========================================================================
// B · a real note is recorded; GET reflects it with a real joined name and
//     a real, server-computed expiresAt.
// ===========================================================================
{
  const res = await postNote(CHILD, dadTok,
    { items: [{ kind: 'mood', note: 'She had a rough morning but perked up by lunch.' }] });
  check('B write', 'authorized guardian -> 201', res.status, 201);
  check('B write', 'items round-trip', res.body.items[0].note,
    'She had a rough morning but perked up by lunch.');
  check('B write', 'a real expiresAt is present', /^\d{4}-\d{2}-\d{2}T/.test(res.body.expiresAt), true);

  const list = await getNotes(CHILD, dadTok);
  check('B write', 'the real note now appears in GET', list.body.entries.length, 1);
  check('B write', "the real note's joined fromUserName is real",
    list.body.entries[0].fromUserName, 'Dad');
}

// ===========================================================================
// C · the real tone guard — an accusatory phrase is refused server-side,
//     before the row is ever written, naming the real phrase found.
// ===========================================================================
{
  const res = await postNote(CHILD, dadTok,
    { items: [{ kind: 'mood', note: 'You always do this, as usual.' }] });
  check('C tone guard', 'an accusatory note is refused', res.status, 400);
  check('C tone guard', 'names the real reason', res.body.error, 'accusatory');
  check('C tone guard', 'names a real phrase found', res.body.found.includes('you always'), true);

  const dbCount = (await admin.query(
    `SELECT count(*) AS n FROM care_note WHERE child_id = $1`, [CHILD])).rows[0].n;
  check('C tone guard', 'the refused note left no trace — still exactly the two real rows '
    + '(the expired seed + section B\'s real write)', dbCount, '2');
}

// ===========================================================================
// D · an empty note is refused the same way.
// ===========================================================================
{
  const res = await postNote(CHILD, dadTok, { items: [{ kind: 'mood', note: '   ' }] });
  check('D empty', 'a whitespace-only note is refused', res.status, 400);
  check('D empty', 'names the real reason', res.body.error, 'empty');
}

// ===========================================================================
// E · role distinctions — a sitter can write; a step_parent can view but
//     not write; a coordinator cannot even view.
// ===========================================================================
{
  const sitterRes = await postNote(CHILD, sitterTok,
    { items: [{ kind: 'sleep', note: 'Skipped her nap today.' }] });
  check('E roles', 'a sitter can write a real note', sitterRes.status, 201);

  const stepGetRes = await getNotes(CHILD, stepTok);
  check('E roles', 'a step_parent CAN view notes', stepGetRes.status, 200);
  const stepPostRes = await postNote(CHILD, stepTok,
    { items: [{ kind: 'mood', note: 'A real attempt.' }] });
  check('E roles', 'a step_parent CANNOT write a note', stepPostRes.status, 403);

  const coordGetRes = await getNotes(CHILD, coordinatorTok);
  check('E roles', 'a coordinator CANNOT even view notes — deliberately outside '
    + 'the court-tier record', coordGetRes.status, 403);
}

// ===========================================================================
// F · the real 7-day TTL — the seeded expired note is still excluded even
//     now that real notes exist alongside it.
// ===========================================================================
{
  const res = await getNotes(CHILD, dadTok);
  check('F ttl', 'exactly the two real, not-yet-expired notes '
    + '(section B + section E\'s sitter note)', res.body.entries.length, 2);
  check('F ttl', 'the expired seeded note never appears', res.body.entries.some(
    (e) => e.items.some((i) => i.note === 'old news')), false);
}

// ===========================================================================
// G · a child session is refused for every route.
// ===========================================================================
{
  const getRes = await getNotes(CHILD, childTok);
  check('G child refused', 'GET .../care-notes refused', getRes.status, 403);
  const postRes = await postNote(CHILD, childTok,
    { items: [{ kind: 'mood', note: 'should never land' }] });
  check('G child refused', 'POST .../care-notes refused', postRes.status, 403);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
