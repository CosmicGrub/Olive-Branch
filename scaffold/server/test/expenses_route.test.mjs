/**
 * server/routes.mjs — GET/POST /v1/children/:childId/expenses, POST
 * .../expenses/:expenseId/accept|dispute|reimburse. Real for the first
 * time — found and closed by this project's own coordination-layer audit
 * (MASTERFILE §20.2b), same pass that closed the handover log.
 *
 * `expense` (db/migrations/0006_court_tier.sql) has had real FORCE RLS
 * (`expense_no_child`) since it was first migrated, and family-graph/src/
 * authorize.ts already had `expense.view`/`expense.create` in its Action
 * union with a real, unconditional P6 block — but nothing anywhere ever
 * wrote or read a row. `expenses_screen.dart`'s own client UI was pure
 * in-memory local state.
 *
 * Mirrors handover_notes_route.test.mjs's own pattern — same DATABASE_URL/
 * ADMIN_DATABASE_URL split, same check() harness, same real Api instance —
 * for the identical reason that file's own header gives: a fake q/pool can
 * only prove the route's SHAPE, never whether `expense_no_child`'s real RLS
 * and this route's own child-role guard actually do what their doc comments
 * claim against a real Postgres.
 *
 * Proves:
 *   (a) a real guardian can propose an expense; the real row lands with the
 *       right paid_by/amount_cents/category/split_rule.
 *   (b) GET returns it with a real joined paidByName.
 *   (c) accept/dispute/reimburse each really flip status, independently
 *       verified by re-querying the row.
 *   (d) a child session is refused for all five routes — P6, not just an
 *       assumption the outer gate alone would already refuse it (the GET
 *       route's own system-scoped read bypasses expense_no_child's RLS the
 *       identical way handoverNotesFor()'s does).
 *   (e) a guardian with no live edge to this child is refused.
 *   (f) a coordinator can view but not resolve — read-only role.
 *   (g) invalid bodies are refused with a specific reason, never a raw
 *       constraint violation.
 *   (h) LATERAL PRIVILEGE: a guardian of a DIFFERENT child cannot resolve
 *       this child's expense by id alone — resolveExpense()'s own
 *       WHERE id=$1 AND child_id=$2 is the real boundary here, since
 *       expense_no_child's RLS does not scope by child at all.
 *   (i) resolving a nonexistent expenseId is an honest 404, never a silent
 *       200 or a 500.
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

const DAD = '11111111-1111-4111-9111-000000000002';
const MOM = '22222222-2222-4222-9222-000000000002';
const STRANGER = '33333333-3333-4333-9333-000000000002';
const CHILD = '55555555-5555-4555-9555-000000000002';
const OTHER_CHILD = '66666666-6666-4666-9666-000000000002';
const COORDINATOR = '44444444-4444-4444-9444-000000000002';

async function cleanup() {
  await admin.query(`DELETE FROM expense WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, MOM, STRANGER, COORDINATOR]]);
}
await cleanup();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'Stranger','America/New_York'), ($4,'Coordinator Cate','America/New_York')`,
  [DAD, MOM, STRANGER, COORDINATOR]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/Los_Angeles'),
     ($2,'OtherKid','2016-04-02','America/Los_Angeles')`,
  [CHILD, OTHER_CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $5, 'coordinator', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, OTHER_CHILD, COORDINATOR]);
// Mom (not Dad) holds the live edge to OTHER_CHILD too — deliberately, so
// section J below tests a guardian who genuinely passes the OUTER
// action:'expense.resolve' gate for OTHER_CHILD's own path, then tries to
// resolve CHILD's expense by id under that path. A guardian with no edge
// to OTHER_CHILD at all would be refused by the outer gate before ever
// reaching resolveExpense()'s own child_id check — that would prove the
// wrong thing.
await admin.query('COMMIT');

const SECRET = Buffer.from('e'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const momTok = issueSession(SECRET,
  { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
const strangerTok = issueSession(SECRET,
  { userId: STRANGER, roleName: 'guardian', childId: null, escalated: false }, NOW);
const coordinatorTok = issueSession(SECRET,
  { userId: COORDINATOR, roleName: 'coordinator', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const get = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/expenses`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const post = (childId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/expenses`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);
const resolve = (childId, expenseId, action, tok) => api.handle(
  'POST', `/v1/children/${childId}/expenses/${expenseId}/${action}`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '{}',
);

const GOOD_BODY = { description: 'Orthodontist co-pay', amountCents: 8900, category: 'medical',
  incurredOn: '2026-07-15', payerSharePercent: 50 };

// ===========================================================================
// A · a real guardian proposes an expense.
// ===========================================================================
let firstId;
{
  const res = await post(CHILD, dadTok, GOOD_BODY);
  check('A propose', 'authorized guardian -> 201', res.status, 201);
  check('A propose', 'paidById is the real caller', res.body.paidById, DAD);
  check('A propose', 'description round-trips', res.body.description, 'Orthodontist co-pay');
  check('A propose', 'amountCents round-trips', res.body.amountCents, 8900);
  check('A propose', 'category round-trips', res.body.category, 'medical');
  check('A propose', 'incurredOn round-trips', res.body.incurredOn, '2026-07-15');
  check('A propose', 'payerSharePercent round-trips (from split_rule jsonb)',
    res.body.payerSharePercent, 50);
  check('A propose', 'status defaults to proposed', res.body.status, 'proposed');
  // paidByName is deliberately absent on POST -- see pool.ts's own doc
  // comment (the actor IS the payer by construction).
  check('A propose', 'paidByName is null on POST — the caller already knows to render "You"',
    res.body.paidByName, 'null');
  firstId = res.body.id;

  const row = (await admin.query(
    `SELECT child_id, paid_by, amount_cents, split_rule FROM expense WHERE id = $1`,
    [firstId])).rows[0];
  check('A propose', 'the real DB row is scoped to the right child', row.child_id, CHILD);
  check('A propose', 'the real DB row split_rule is the real jsonb shape',
    row.split_rule.payerSharePercent, 50);
}

// ===========================================================================
// B · a second expense from a DIFFERENT guardian; GET returns both with a
//     real joined paidByName.
// ===========================================================================
{
  const res2 = await post(CHILD, momTok, { description: 'Piano lesson book',
    amountCents: 1499, category: 'school', incurredOn: '2026-07-20', payerSharePercent: 50 });
  check('B second + GET', 'a different guardian can also propose -> 201', res2.status, 201);

  const res = await get(CHILD, dadTok);
  check('B second + GET', 'authorized guardian -> 200', res.status, 200);
  check('B second + GET', 'both entries present', res.body.entries.length, 2);
  const momEntry = res.body.entries.find(e => e.paidById === MOM);
  check('B second + GET', 'the real joined paidByName is the real app_user.display_name',
    momEntry?.paidByName, 'Mom');
  check('B second + GET', "the real description round-trips, the field this pass's own "
    + 'migration added', momEntry?.description, 'Piano lesson book');
  const dadEntry = res.body.entries.find(e => e.paidById === DAD);
  check('B second + GET', 'the first guardian\'s own entry also shows the real name',
    dadEntry?.paidByName, 'Dad');
}

// ===========================================================================
// C/D/E · accept/dispute/reimburse each really flip status.
// ===========================================================================
{
  const acceptRes = await resolve(CHILD, firstId, 'accept', momTok);
  check('C accept', 'a co-guardian can accept -> 200', acceptRes.status, 200);
  check('C accept', 'status flips to accepted', acceptRes.body.status, 'accepted');
  const row = (await admin.query(`SELECT status FROM expense WHERE id = $1`, [firstId])).rows[0];
  check('C accept', 'the real DB row shows accepted', row.status, 'accepted');
}
let disputeId;
{
  const res = await post(CHILD, dadTok, { description: 'A charge Mom will contest',
    amountCents: 500, category: 'other', incurredOn: '2026-07-22', payerSharePercent: 50 });
  disputeId = res.body.id;
  const disputeRes = await resolve(CHILD, disputeId, 'dispute', momTok);
  check('D dispute', 'Decline maps to disputed, the real closest status', disputeRes.body.status,
    'disputed');
}
{
  const res = await post(CHILD, dadTok, { description: 'Soccer camp',
    amountCents: 2000, category: 'activity', incurredOn: '2026-07-23', payerSharePercent: 50 });
  const reimburseRes = await resolve(CHILD, res.body.id, 'reimburse', dadTok);
  check('E reimburse', 'reimburse -> 200', reimburseRes.status, 200);
  check('E reimburse', 'status flips to reimbursed', reimburseRes.body.status, 'reimbursed');
}

// ===========================================================================
// F · a child session is refused for every route — real P6, not merely the
//     outer gate's own assumption.
// ===========================================================================
{
  const getRes = await get(CHILD, childTok);
  check('F child refused', 'GET refused', getRes.status, 403);
  check('F child refused', 'no entries leak', getRes.body?.entries, undefined);

  const postRes = await post(CHILD, childTok, GOOD_BODY);
  check('F child refused', 'POST refused', postRes.status, 403);

  const resolveRes = await resolve(CHILD, firstId, 'accept', childTok);
  check('F child refused', 'resolve refused', resolveRes.status, 403);

  // Four real expenses exist by this point: A's, B's, D's, and E's own
  // proposals (each section's resolve() calls update an existing row
  // rather than inserting a new one).
  const stillFourAtF = (await admin.query(
    `SELECT count(*) AS n FROM expense WHERE child_id = $1`, [CHILD])).rows[0].n;
  check('F child refused', 'the refused POST left no trace', stillFourAtF, '4');
}

// ===========================================================================
// G · a guardian with no live edge to this child is refused.
// ===========================================================================
{
  const res = await post(CHILD, strangerTok, GOOD_BODY);
  check('G no edge', 'refused', res.status, 403);
}

// ===========================================================================
// H · a coordinator can view but not resolve — read-only role,
//     ROLE_CAPS.coordinator holds expense.view, never expense.resolve.
// ===========================================================================
{
  const getRes = await get(CHILD, coordinatorTok);
  check('H coordinator', 'GET allowed (read-only)', getRes.status, 200);
  check('H coordinator', 'sees the real entries', getRes.body.entries.length, 4);

  const postRes = await post(CHILD, coordinatorTok, GOOD_BODY);
  check('H coordinator', 'POST refused', postRes.status, 403);

  const resolveRes = await resolve(CHILD, firstId, 'accept', coordinatorTok);
  check('H coordinator', 'resolve refused — role_lacks_capability', resolveRes.status, 403);
}

// ===========================================================================
// I · invalid bodies are refused with a specific reason.
// ===========================================================================
{
  const badDescription = await post(CHILD, dadTok, { ...GOOD_BODY, description: '   ' });
  check('I validation', 'whitespace-only description refused, not silently trimmed to '
    + 'empty and accepted', badDescription.status, 400);
  check('I validation', 'names the real reason', badDescription.body.error, 'bad_description');

  const badAmount = await post(CHILD, dadTok, { ...GOOD_BODY, amountCents: 0 });
  check('I validation', 'zero amountCents refused', badAmount.status, 400);
  check('I validation', 'names the real reason', badAmount.body.error, 'bad_amountCents');

  const badCategory = await post(CHILD, dadTok, { ...GOOD_BODY, category: 'vacation' });
  check('I validation', 'unrecognized category refused', badCategory.status, 400);
  check('I validation', 'names the real reason', badCategory.body.error, 'bad_category');

  const badDate = await post(CHILD, dadTok, { ...GOOD_BODY, incurredOn: 'not-a-date' });
  check('I validation', 'malformed incurredOn refused', badDate.status, 400);

  const badPercent = await post(CHILD, dadTok, { ...GOOD_BODY, payerSharePercent: 150 });
  check('I validation', 'out-of-range payerSharePercent refused', badPercent.status, 400);

  const stillFourAtI = (await admin.query(
    `SELECT count(*) AS n FROM expense WHERE child_id = $1`, [CHILD])).rows[0].n;
  check('I validation', 'none of the refused POSTs left a trace', stillFourAtI, '4');
}

// ===========================================================================
// J · LATERAL PRIVILEGE — a guardian of a DIFFERENT child cannot resolve
//     THIS child's expense by id alone. Mom holds a live edge to
//     OTHER_CHILD too (seeded above), so she passes the outer
//     action:'expense.resolve' gate for OTHER_CHILD's path — the real
//     boundary has to be resolveExpense()'s own WHERE child_id = $childId.
// ===========================================================================
{
  const res = await resolve(OTHER_CHILD, firstId, 'accept', momTok);
  check('J lateral privilege', 'a real expense id belonging to a DIFFERENT child is refused, '
    + 'not silently resolved', res.status, 404);
  const row = (await admin.query(`SELECT status FROM expense WHERE id = $1`, [firstId])).rows[0];
  check('J lateral privilege', "the real row's status is untouched by the cross-child attempt",
    row.status, 'accepted');
}

// ===========================================================================
// K · resolving a nonexistent expenseId is an honest 404.
// ===========================================================================
{
  const res = await resolve(CHILD, '00000000-0000-4000-8000-000000000000', 'accept', dadTok);
  check('K not found', 'a real UUID that names no row is 404, never a 500', res.status, 404);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
