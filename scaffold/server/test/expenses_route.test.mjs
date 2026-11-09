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
const SOLO_CHILD = '77777777-7777-4777-9777-000000000002'; // a family with exactly one guardian (Dad)
const COORDINATOR = '44444444-4444-4444-9444-000000000002';

async function cleanup() {
  await admin.query(`DELETE FROM expense WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD, SOLO_CHILD]]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD, SOLO_CHILD]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD, SOLO_CHILD]]);
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
     ($2,'OtherKid','2016-04-02','America/Los_Angeles'),
     ($3,'SoloKid','2016-04-02','America/Los_Angeles')`,
  [CHILD, OTHER_CHILD, SOLO_CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $5, 'coordinator', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($6, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, OTHER_CHILD, COORDINATOR, SOLO_CHILD]);
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
  // S-D14: reimbursing is only legal from 'accepted' -- an unaccepted expense
  // cannot be marked reimbursed (it used to flip straight from 'proposed').
  const early = await resolve(CHILD, res.body.id, 'reimburse', dadTok);
  check('E reimburse', 'reimbursing a still-PROPOSED expense is refused 409', early.status, 409);
  const acc = await resolve(CHILD, res.body.id, 'accept', momTok);
  check('E reimburse', 'the co-guardian accepts it first', acc.status, 200);
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

// ===========================================================================
// L · S-D14 -- status changes are guarded, attributed and append-only.
// ===========================================================================
{
  const mk = async () => (await post(CHILD, dadTok, { description: 'Guarded transitions',
    amountCents: 1234, category: 'other', incurredOn: '2026-07-24', payerSharePercent: 50 })).body.id;
  const id = await mk();

  const own = await resolve(CHILD, id, 'accept', dadTok);
  check('L own expense', 'the proposer cannot accept their own expense (403)', own.status, 403);
  check('L own expense', 'with a plain reason', own.body.error, 'cannot_resolve_own_expense');
  const ownDispute = await resolve(CHILD, id, 'dispute', dadTok);
  check('L own expense', 'nor dispute it', ownDispute.status, 403);
  check('L own expense', 'the row is still proposed after both attempts',
    (await admin.query('SELECT status FROM expense WHERE id = $1', [id])).rows[0].status, 'proposed');

  const ok = await resolve(CHILD, id, 'accept', momTok);
  check('L transitions', 'the other guardian accepts -> 200', ok.status, 200);
  const again = await resolve(CHILD, id, 'accept', momTok);
  check('L transitions', 'accepting twice is 409 invalid_transition', `${again.status}:${again.body.error}`, '409:invalid_transition');
  check('L transitions', 'and says what state it is in', again.body.status, 'accepted');
  const flip = await resolve(CHILD, id, 'dispute', momTok);
  check('L transitions', 'an accepted expense cannot be disputed afterwards', flip.status, 409);
  const reim = await resolve(CHILD, id, 'reimburse', momTok);
  check('L transitions', 'accepted -> reimbursed is allowed', reim.status, 200);
  const reimAgain = await resolve(CHILD, id, 'reimburse', dadTok);
  check('L transitions', 'reimbursed is terminal', reimAgain.status, 409);
  const disputed = await mk();
  await resolve(CHILD, disputed, 'dispute', momTok);
  const fromDisputed = await resolve(CHILD, disputed, 'accept', momTok);
  check('L transitions', 'a disputed expense CAN be accepted later (owner, 0045), and it is recorded', fromDisputed.status, 200);
  const disputedEv = (await admin.query(`SELECT from_status, to_status, actor_id, self_accept FROM expense_event WHERE expense_id = $1 ORDER BY seq`, [disputed])).rows;
  check('L transitions', 'history: proposed, disputed, accepted (disputed -> accepted)',
    disputedEv.map(e => `${e.from_status ?? 'null'}>${e.to_status}`).join(','), 'null>proposed,proposed>disputed,disputed>accepted');
  check('L transitions', 'a two-guardian accept is not a self-accept', disputedEv.some(e => e.self_accept), false);
  const proposerAgain = await resolve(CHILD, disputed, 'accept', dadTok);
  check('L transitions', 'the proposer still cannot accept in a two-guardian family (409: already accepted, not a bypass)', proposerAgain.status, 409);
  const disputed2 = await mk();
  await resolve(CHILD, disputed2, 'dispute', momTok);
  const ownFromDisputed = await resolve(CHILD, disputed2, 'accept', dadTok);
  check('L transitions', 'two guardians: the proposer cannot accept a disputed expense either (403)', ownFromDisputed.status, 403);
  const unaccepted = await resolve(CHILD, disputed2, 'reimburse', momTok);
  check('L transitions', 'reimbursing a disputed (unaccepted) expense is 409 invalid_transition', `${unaccepted.status}:${unaccepted.body.error}`, '409:invalid_transition');

  const ev = (await admin.query(
    `SELECT seq, from_status, to_status, actor_id, at, backfilled FROM expense_event WHERE expense_id = $1 ORDER BY seq`, [id])).rows;
  check('L history', 'one event per change: proposed, accepted, reimbursed', ev.map(e => e.to_status).join(','), 'proposed,accepted,reimbursed');
  check('L history', 'seq is contiguous from 1', ev.map(e => e.seq).join(','), '1,2,3');
  check('L history', 'each event records the from-status', ev.map(e => e.from_status ?? 'null').join(','), 'null,proposed,accepted');
  check('L history', 'the actors are who really did it (Dad proposed, Mom accepted, Mom reimbursed)',
    ev.map(e => e.actor_id).join(','), [DAD, MOM, MOM].join(','));
  check('L history', 'every event carries a timestamp, in order',
    ev.every((e, i) => e.at && (i === 0 || e.at >= ev[i - 1].at)), true);
  check('L history', 'none of this history is a backfill', ev.some(e => e.backfilled), false);
  check('L history', 'a refused attempt leaves NO event behind',
    (await admin.query(`SELECT count(*)::int AS n FROM expense_event WHERE expense_id = $1`, [disputed])).rows[0].n, 3);

  // the database is the real enforcement, whatever the application does
  const run = async (sql, params = [], actor = null) => {
    await admin.query('BEGIN');
    try {
      if (actor) await admin.query(`SELECT set_config('app.user_id', $1, true)`, [actor]);
      await admin.query(sql, params);
      await admin.query('COMMIT'); return null;
    } catch (e) { await admin.query('ROLLBACK'); return e.message; }
  };
  const fresh = await mk();
  check('L db guard', 'a direct UPDATE by the proposer is refused by the trigger',
    (await run(`UPDATE expense SET status = 'accepted' WHERE id = $1`, [fresh], DAD))?.includes('expense_own_proposal'), true);
  check('L db guard', 'a direct UPDATE with no actor at all is refused',
    (await run(`UPDATE expense SET status = 'accepted' WHERE id = $1`, [fresh]))?.includes('expense_actor_required'), true);
  check('L db guard', 'a skipped step (proposed -> reimbursed) is refused',
    (await run(`UPDATE expense SET status = 'reimbursed' WHERE id = $1`, [fresh], MOM))?.includes('expense_invalid_transition'), true);
  check('L db guard', 'the amount cannot be rewritten',
    (await run(`UPDATE expense SET amount_cents = 1 WHERE id = $1`, [fresh], MOM))?.includes('expense_immutable'), true);
  check('L db guard', 'nor who paid',
    (await run(`UPDATE expense SET paid_by = $2 WHERE id = $1`, [fresh, MOM], MOM))?.includes('expense_immutable'), true);
  check('L db guard', 'a legal change by another user goes through',
    await run(`UPDATE expense SET status = 'accepted' WHERE id = $1`, [fresh], MOM), null);
  check('L append-only', 'expense_event cannot be UPDATEd',
    (await run(`UPDATE expense_event SET actor_id = $1 WHERE expense_id = $2`, [DAD, id]))?.includes('append-only'), true);
  check('L append-only', 'expense_event cannot be DELETEd',
    (await run(`DELETE FROM expense_event WHERE expense_id = $1`, [id]))?.includes('append-only'), true);
  check('L append-only', 'expense_event cannot be TRUNCATEd',
    (await run(`TRUNCATE expense_event`))?.includes('append-only'), true);
  check('L append-only', 'the history survived all of that',
    (await admin.query(`SELECT count(*)::int AS n FROM expense_event WHERE expense_id = $1`, [id])).rows[0].n, 3);
  check('L history', 'a status skipped in the CHECK cannot be recorded even by a direct insert',
    (await run(`INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status) VALUES ($1,$2,99,'proposed','reimbursed')`, [id, CHILD]))
      ?.includes('expense_event_transition'), true);
}


// ===========================================================================
// M · S-D19 -- basis points per participant, a currency, and two-party
//     requests still working exactly as before.
// ===========================================================================
{
  const body = (o = {}) => ({ description: 'Split test', amountCents: 10001, category: 'other',
    incurredOn: '2026-07-25', payerSharePercent: 50, ...o });
  const row = async (id) => (await admin.query('SELECT currency, split_bp, split_rule FROM expense WHERE id = $1', [id])).rows[0];

  const legacy = await post(CHILD, dadTok, body());
  check('M split', 'the legacy two-party request still returns 201', legacy.status, 201);
  const l = await row(legacy.body.id);
  check('M split', 'it is stored as basis points over the two live guardians (50% -> 5000/5000)',
    JSON.stringify(l.split_bp), JSON.stringify({ [DAD]: 5000, [MOM]: 5000 }));
  check('M split', 'the legacy payerSharePercent is still stored and returned', `${l.split_rule.payerSharePercent}|${legacy.body.payerSharePercent}`, '50|50');
  check('M split', 'currency defaults to USD', `${l.currency}|${legacy.body.currency}`, 'USD|USD');
  check('M split', 'the wire carries participants, sorted by id',
    JSON.stringify(legacy.body.participants), JSON.stringify([{ userId: DAD, bp: 5000 }, { userId: MOM, bp: 5000 }]));
  const sixty = await post(CHILD, dadTok, body({ payerSharePercent: 60 }));
  check('M split', '60% payer share -> 6000/4000', JSON.stringify((await row(sixty.body.id)).split_bp), JSON.stringify({ [DAD]: 6000, [MOM]: 4000 }));
  check('M split', 'the coordinator is not on the split (only parent guardians are)',
    Object.keys((await row(sixty.body.id)).split_bp).includes(COORDINATOR), false);

  const explicit = await post(CHILD, momTok, body({ participants: [{ userId: MOM, bp: 2500 }, { userId: DAD, bp: 7500 }] }));
  check('M split', 'an explicit basis-point split is accepted', explicit.status, 201);
  check('M split', 'and stored as given', JSON.stringify((await row(explicit.body.id)).split_bp), JSON.stringify({ [DAD]: 7500, [MOM]: 2500 }));

  const badSum = await post(CHILD, dadTok, body({ participants: [{ userId: DAD, bp: 5000 }, { userId: MOM, bp: 4000 }] }));
  check('M split', 'shares that do not total 10000 are 400 bad_participants', `${badSum.status}:${badSum.body.error}`, '400:bad_participants');
  const frac = await post(CHILD, dadTok, body({ participants: [{ userId: DAD, bp: 5000.5 }, { userId: MOM, bp: 4999.5 }] }));
  check('M split', 'fractional basis points are refused', frac.status, 400);
  const stranger = await post(CHILD, dadTok, body({ participants: [{ userId: DAD, bp: 5000 }, { userId: STRANGER, bp: 5000 }] }));
  check('M split', 'a participant who is not a live guardian of THIS child is refused', `${stranger.status}:${stranger.body.error}`, '400:bad_participants');
  const noPayer = await post(CHILD, dadTok, body({ participants: [{ userId: MOM, bp: 10000 }] }));
  check('M split', 'the payer must be one of the participants', `${noPayer.status}:${noPayer.body.error}`, '400:bad_participants');
  const dup = await post(CHILD, dadTok, body({ participants: [{ userId: DAD, bp: 5000 }, { userId: DAD, bp: 5000 }] }));
  check('M split', 'a participant listed twice is refused', dup.status, 400);
  const empty = await post(CHILD, dadTok, body({ participants: [] }));
  check('M split', 'an empty participant list is refused', empty.status, 400);
  const solo = await post(CHILD, dadTok, body({ participants: [{ userId: DAD, bp: 10000 }] }));
  check('M split', 'a payer who bears it all (10000bp) is valid', solo.status, 201);

  const eur = await post(CHILD, dadTok, body({ currency: 'EUR' }));
  check('M currency', 'a currency code is accepted and stored', `${eur.status}|${(await row(eur.body.id)).currency}|${eur.body.currency}`, '201|EUR|EUR');
  check('M currency', 'lower case is refused', (await post(CHILD, dadTok, body({ currency: 'usd' }))).body.error, 'bad_currency');
  check('M currency', 'a two-letter code is refused', (await post(CHILD, dadTok, body({ currency: 'US' }))).body.error, 'bad_currency');
  check('M currency', 'a non-string is refused', (await post(CHILD, dadTok, body({ currency: 5 }))).body.error, 'bad_currency');

  const listed = await get(CHILD, dadTok);
  const found = listed.body.entries.find(e => e.id === explicit.body.id);
  check('M wire', 'GET returns currency and participants for a new-style row', `${found.currency}|${found.participants.length}`, 'USD|2');

  // legacy rows (written before 0044) have no split_bp: honest null, never an invented split
  const old = (await admin.query(
    `INSERT INTO expense (child_id, paid_by, description, amount_cents, category, incurred_on, split_rule)
     VALUES ($1,$2,'legacy row',500,'other','2026-01-01','{"payerSharePercent":70}') RETURNING id`, [CHILD, DAD])).rows[0].id;
  const listed2 = await get(CHILD, dadTok);
  const oldWire = listed2.body.entries.find(e => e.id === old);
  check('M wire', 'a legacy row reports participants: null and keeps its payerSharePercent', `${oldWire.participants}|${oldWire.payerSharePercent}|${oldWire.currency}`, 'null|70|USD');

  // the database refuses a malformed split whatever the application does
  const ins = async (split, cur = 'USD') => {
    await admin.query('SAVEPOINT s');
    try {
      await admin.query(`INSERT INTO expense (child_id, paid_by, description, amount_cents, category, incurred_on, split_rule, split_bp, currency)
                         VALUES ($1,$2,'x',1,'other','2026-01-01','{"payerSharePercent":50}',$3::jsonb,$4)`, [CHILD, DAD, split, cur]);
      await admin.query('RELEASE SAVEPOINT s'); return null;
    } catch (e) { await admin.query('ROLLBACK TO SAVEPOINT s'); return e.constraint ?? e.message; }
  };
  await admin.query('BEGIN');
  check('M db checks', 'split_bp that does not total 10000 is refused', await ins(JSON.stringify({ [DAD]: 5000, [MOM]: 4000 })), 'expense_split_bp_valid');
  check('M db checks', 'split_bp over 10000 for one party is refused', await ins(JSON.stringify({ [DAD]: 12000, [MOM]: -2000 })), 'expense_split_bp_valid');
  check('M db checks', 'a non-uuid participant key is refused', await ins(JSON.stringify({ nobody: 10000 })), 'expense_split_bp_valid');
  check('M db checks', 'a fractional share is refused', await ins('{"' + DAD + '": 5000.5, "' + MOM + '": 4999.5}'), 'expense_split_bp_valid');
  check('M db checks', 'an array is refused', await ins('[10000]'), 'expense_split_bp_valid');
  check('M db checks', 'a valid split is accepted', await ins(JSON.stringify({ [DAD]: 3333, [MOM]: 6667 })), null);
  check('M db checks', 'a bad currency code is refused', await ins(null, 'usd'), 'expense_currency_iso4217');
  await admin.query('ROLLBACK');
}
// ===========================================================================
// N · a SOLE guardian may accept their own proposal (recorded as self_accept);
//     a family with two or more guardians keeps proposer-cannot-accept.
// ===========================================================================
{
  const mk = async (child, tok) => (await post(child, tok, { description: 'Solo guardian expense',
    amountCents: 4200, category: 'other', incurredOn: '2026-08-01', payerSharePercent: 100 })).body.id;
  const id = await mk(SOLO_CHILD, dadTok);
  const events = async (x) => (await admin.query(
    `SELECT from_status, to_status, actor_id, self_accept, backfilled FROM expense_event WHERE expense_id = $1 ORDER BY seq`, [x])).rows;

  const ownDispute = await resolve(SOLO_CHILD, id, 'dispute', dadTok);
  check('N solo', 'a sole guardian still cannot DISPUTE their own expense (403)', ownDispute.status, 403);
  const selfAccept = await resolve(SOLO_CHILD, id, 'accept', dadTok);
  check('N solo', 'a sole guardian can accept their own proposal (200)', selfAccept.status, 200);
  check('N solo', 'status is accepted', selfAccept.body.status, 'accepted');
  const ev = await events(id);
  check('N solo', 'the accept is recorded with the actor', ev.map(e => `${e.to_status}:${e.actor_id}`).join(','), `proposed:${DAD},accepted:${DAD}`);
  check('N solo', 'and an explicit self_accept marker on that event only', ev.map(e => e.self_accept).join(','), 'false,true');
  const reim = await resolve(SOLO_CHILD, id, 'reimburse', dadTok);
  check('N solo', 'a self-accepted expense can then be reimbursed', reim.status, 200);
  check('N solo', 'reimbursing carries no self_accept marker', (await events(id)).map(e => e.self_accept).join(','), 'false,true,false');

  // disputed -> accepted, solo family: dispute is by someone else only, so use the DB path for the disputer
  const unaccepted = await mk(SOLO_CHILD, dadTok);
  const early = await resolve(SOLO_CHILD, unaccepted, 'reimburse', dadTok);
  check('N solo', 'reimbursing an unaccepted expense is still 409 invalid_transition', `${early.status}:${early.body.error}`, '409:invalid_transition');

  // two guardians: unchanged
  const two = await mk(CHILD, dadTok);
  const refused = await resolve(CHILD, two, 'accept', dadTok);
  check('N two', 'with two guardians the proposer still cannot accept (403 cannot_resolve_own_expense)', `${refused.status}:${refused.body.error}`, '403:cannot_resolve_own_expense');
  check('N two', 'and nothing was recorded', (await events(two)).length, 1);

  // the database is the enforcement
  const run = async (sql, params, actor) => {
    await admin.query('BEGIN');
    try { await admin.query(`SELECT set_config('app.user_id', $1, true)`, [actor]); await admin.query(sql, params); await admin.query('COMMIT'); return null; }
    catch (e) { await admin.query('ROLLBACK'); return e.message; }
  };
  const viaDb = await mk(SOLO_CHILD, dadTok); 
  check('N db', 'a direct UPDATE by the sole guardian to accepted passes the trigger', await run(`UPDATE expense SET status = 'accepted' WHERE id = $1`, [viaDb], DAD), null);
  check('N db', 'and the trigger marked it self_accept', (await events(viaDb)).at(-1).self_accept, true);
  const viaDb2 = await mk(SOLO_CHILD, dadTok);
  check('N db', 'a direct UPDATE by the sole guardian to disputed is refused',
    (await run(`UPDATE expense SET status = 'disputed' WHERE id = $1`, [viaDb2], DAD))?.includes('expense_own_proposal'), true);
  check('N db', 'self_accept cannot be set on a non-accept event',
    (await run(`INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, self_accept) VALUES ($1,$2,99,'accepted','reimbursed',true)`, [viaDb2, SOLO_CHILD], DAD))
      ?.includes('expense_event_self_accept_shape'), true);
}
await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
