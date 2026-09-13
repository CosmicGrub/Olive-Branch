/**
 * server/routes.mjs — GET/POST .../exchange/bag-items, GET/POST
 * .../exchange/running-late, GET/POST .../exchange/arrival. Real for the
 * first time — found and closed by this project's own coordination-layer
 * audit (MASTERFILE §20.2b), same pass that closed the handover log,
 * expenses, and medications/emergency-card.
 *
 * `exchange_bag_item`/`exchange_running_late_log`/`exchange_arrival_event`
 * (db/migrations/0027_exchange.sql) have real FORCE RLS (`..._no_child`) —
 * but nothing anywhere ever wrote or read a row. exchange_screen.dart's bag
 * manifest/running-late/arrival sections were pure hardcoded client state
 * with zero network calls.
 *
 * Proves:
 *   (a) GET .../bag-items returns the real seeded manifest, essential-first.
 *   (b) POST .../bag-items/:itemId toggles exactly the field given, leaves
 *       the other untouched; a wrong/cross-child id is a real 404 — the
 *       real lateral-privilege guard lives in setBagItemStatus()'s own
 *       `WHERE child_id = $2` clause, not just the outer authorization gate.
 *   (c) GET/POST .../running-late round-trips, newest first, insert-only.
 *   (d) POST .../arrival computes a real `scheduled_at` from the child's
 *       real active custody_order (`order_tz`/`exchange_time`) — NOT the
 *       child's own `home_tz`, proven by using two different zones — never
 *       trusted from the client; GET reflects the most recent real event.
 *   (e) a child with no active custody order gets an honest 409
 *       `no_active_custody_order`, never a guessed/fabricated schedule.
 *   (f) role distinctions: a sitter/step_parent (real `calendar.view`
 *       holders, no `calendar.edit`) can read every GET but is refused
 *       every POST — real, pre-existing ROLE_CAPS, not invented here.
 *   (g) a child session is refused for every route.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
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
const checkClose = (g, n, a, e, tol) => { const ok = Math.abs(Number(a) - Number(e)) <= tol;
  ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: `${a} (within ${tol} of ${e})`, e: `~${e}` }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const DAD = '11111111-1111-4111-9111-000000000006';
const MOM = '22222222-2222-4222-9222-000000000006';
const SITTER = '77777777-7777-4777-9777-000000000006';
const STRANGER = '33333333-3333-4333-9333-000000000006';
const CHILD = '55555555-5555-4555-9555-000000000006';
// A second child with NO custody_order row — the real honest-absence case.
const NOORDER_CHILD = '66666666-6666-4666-9666-000000000006';

async function cleanup() {
  await admin.query(
    `DELETE FROM exchange_arrival_event WHERE child_id = ANY($1::uuid[])`, [[CHILD, NOORDER_CHILD]]);
  await admin.query(
    `DELETE FROM exchange_running_late_log WHERE child_id = ANY($1::uuid[])`, [[CHILD, NOORDER_CHILD]]);
  await admin.query(
    `DELETE FROM exchange_bag_item WHERE child_id = ANY($1::uuid[])`, [[CHILD, NOORDER_CHILD]]);
  await admin.query(`DELETE FROM custody_order WHERE child_id = ANY($1::uuid[])`, [[CHILD, NOORDER_CHILD]]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD, NOORDER_CHILD]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, NOORDER_CHILD]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, MOM, SITTER, STRANGER]]);
}
await cleanup();

// Two DELIBERATELY different zones — CHILD's own home_tz (what resolves
// "today's" local date) vs. the custody order's own order_tz (what
// exchange_time is interpreted in). Proves recordExchangeArrival() uses the
// ORDER's zone for the clock, not the child's, per pool.ts's own doc comment.
const CHILD_TZ = 'America/Los_Angeles';
const ORDER_TZ = 'America/Chicago';
const localDate = DateTime.utc().setZone(CHILD_TZ).toISODate();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'Sitter Sue','America/New_York'), ($4,'Stranger Dan','America/New_York')`,
  [DAD, MOM, SITTER, STRANGER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02',$3), ($2,'NoOrder','2018-01-01',$3)`, [CHILD, NOORDER_CHILD, CHILD_TZ]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $4, 'sitter', '{}', tstzrange(now() - interval '1 year', null)),
     ($5, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, SITTER, NOORDER_CHILD]);
// A real active custody order — exchange_time interpreted in ORDER_TZ,
// NOT CHILD_TZ. effective_from is safely in the past so it is active today
// regardless of which real calendar date this suite happens to run on.
await admin.query(
  `INSERT INTO custody_order
     (child_id, order_tz, pattern, anchor_local_date, exchange_time, effective_from, effective_to)
   VALUES ($1, $2, '2-2-3', $3, '06:00', '2020-01-01', null)`,
  [CHILD, ORDER_TZ, localDate]);
const items = (await admin.query(
  `INSERT INTO exchange_bag_item (child_id, label, essential, sent, returned) VALUES
     ($1, 'Retainer', true, false, false),
     ($1, 'Tablet charger', false, false, false)
   RETURNING id, label, essential`, [CHILD])).rows;
await admin.query('COMMIT');
const RETAINER_ID = items.find(i => i.label === 'Retainer').id;
const CHARGER_ID = items.find(i => i.label === 'Tablet charger').id;

const SECRET = Buffer.from('e'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const momTok = issueSession(SECRET,
  { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
const sitterTok = issueSession(SECRET,
  { userId: SITTER, roleName: 'sitter', childId: null, escalated: false }, NOW);
const strangerTok = issueSession(SECRET,
  { userId: STRANGER, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const getBagItems = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/exchange/bag-items`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const postBagItem = (childId, itemId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/exchange/bag-items/${itemId}`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);
const getRunningLate = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/exchange/running-late`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const postRunningLate = (childId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/exchange/running-late`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);
const getArrival = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/exchange/arrival`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const postArrival = (childId, tok) => api.handle(
  'POST', `/v1/children/${childId}/exchange/arrival`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify({}),
);

// ===========================================================================
// A · GET .../bag-items returns the real seeded manifest, essential-first.
// ===========================================================================
{
  const res = await getBagItems(CHILD, dadTok);
  check('A bag list', 'authorized guardian -> 200', res.status, 200);
  check('A bag list', 'both real seeded items present', res.body.items.length, 2);
  check('A bag list', 'essential item sorts first', res.body.items[0].label, 'Retainer');
  check('A bag list', 'neither item is sent/returned yet', res.body.items[0].sent, false);
}

// ===========================================================================
// B · POST .../bag-items/:itemId toggles exactly the field given.
// ===========================================================================
{
  const res = await postBagItem(CHILD, RETAINER_ID, dadTok, { sent: true });
  check('B toggle', 'authorized guardian -> 200', res.status, 200);
  check('B toggle', 'sent flips true', res.body.sent, true);
  check('B toggle', 'returned stays untouched (false)', res.body.returned, false);

  const res2 = await postBagItem(CHILD, RETAINER_ID, momTok, { returned: true });
  check('B toggle', 'a DIFFERENT guardian can also toggle -> 200', res2.status, 200);
  check('B toggle', 'returned flips true', res2.body.returned, true);
  check('B toggle', 'sent (set earlier by Dad) is UNCHANGED, not reset', res2.body.sent, true);

  check('B toggle', 'the OTHER item is untouched',
    (await getBagItems(CHILD, dadTok)).body.items.find(i => i.id === CHARGER_ID)?.sent, false);
}

// ===========================================================================
// C · a wrong/nonexistent item id is a real 404, not a silent no-op.
// ===========================================================================
{
  const res = await postBagItem(CHILD, '99999999-9999-4999-9999-999999999999', dadTok, { sent: true });
  check('C not found', 'a nonexistent item id -> 404', res.status, 404);
  check('C not found', 'names the real reason', res.body.error, 'bag_item_not_found');
}

// ===========================================================================
// D · a guardian with NO edge to CHILD at all (STRANGER) is refused by the
//     OUTER gate before setBagItemStatus() is ever reached.
// ===========================================================================
{
  const res = await postBagItem(CHILD, RETAINER_ID, strangerTok, { sent: false });
  check('D no edge', 'a guardian with no edge to this child is refused', res.status, 403);
  const stillTrue = await getBagItems(CHILD, dadTok);
  check('D no edge', 'the refused toggle left the real item untouched',
    stillTrue.body.items.find(i => i.id === RETAINER_ID)?.sent, true);
}

// ===========================================================================
// D2 · LATERAL PRIVILEGE — DAD has a real edge (and calendar.edit) on
//     NOORDER_CHILD too, but RETAINER_ID belongs to CHILD. The outer gate
//     allows this call through (DAD is a real guardian of NOORDER_CHILD);
//     setBagItemStatus()'s own `WHERE id = $1 AND child_id = $2` is what
//     must refuse it — the exact same guard resolveExpense() established.
// ===========================================================================
{
  const res = await postBagItem(NOORDER_CHILD, RETAINER_ID, dadTok, { sent: false });
  check('D2 lateral privilege', "CHILD's item cannot be reached via NOORDER_CHILD's path", res.status, 404);
  check('D2 lateral privilege', 'names the real reason', res.body.error, 'bag_item_not_found');
  const stillTrue = await getBagItems(CHILD, dadTok);
  check('D2 lateral privilege', "CHILD's own real item is untouched",
    stillTrue.body.items.find(i => i.id === RETAINER_ID)?.sent, true);
}

// ===========================================================================
// E · GET/POST .../running-late — insert-only, newest first.
// ===========================================================================
{
  const empty = await getRunningLate(CHILD, dadTok);
  check('E running late', 'no entries logged yet', empty.body.entries.length, 0);

  const first = await postRunningLate(CHILD, dadTok, { etaMinutes: 10 });
  check('E running late', 'first entry -> 201', first.status, 201);
  check('E running late', 'etaMinutes round-trips', first.body.etaMinutes, 10);

  const second = await postRunningLate(CHILD, momTok, { etaMinutes: 25 });
  check('E running late', 'second entry -> 201', second.status, 201);

  const list = await getRunningLate(CHILD, dadTok);
  check('E running late', 'both real entries present', list.body.entries.length, 2);
  check('E running late', 'newest first', list.body.entries[0].etaMinutes, 25);
  check('E running late', 'reportedByName is real, joined', list.body.entries[0].reportedByName, 'Mom');
}

// ===========================================================================
// F · a non-positive etaMinutes is a real 400, not silently clamped.
// ===========================================================================
{
  const res = await postRunningLate(CHILD, dadTok, { etaMinutes: 0 });
  check('F validation', 'etaMinutes: 0 is refused', res.status, 400);
  check('F validation', 'names the real reason', res.body.error, 'eta_minutes_must_be_positive');
}

// ===========================================================================
// G · GET .../arrival before any event — honest null, not a guess.
// ===========================================================================
{
  const res = await getArrival(CHILD, dadTok);
  check('G arrival empty', 'authorized guardian -> 200', res.status, 200);
  check('G arrival empty', 'no arrival logged yet -> honest null', res.body.event, null);
}

// ===========================================================================
// H · POST .../arrival computes a real scheduled_at from the custody order's
//     OWN order_tz (06:00 America/Chicago) — not CHILD_TZ.
// ===========================================================================
{
  const before = DateTime.utc();
  const res = await postArrival(CHILD, dadTok);
  const after = DateTime.utc();
  check('H arrival', 'a real active custody order -> 201', res.status, 201);

  const expectedScheduled = DateTime.fromISO(`${localDate}T06:00:00`, { zone: ORDER_TZ }).toUTC();
  // .toMillis(), not .toISO() -- DateTime.fromISO() without {setZone: true}
  // parses into the LOCAL (system default) zone regardless of the source
  // string's own 'Z'/offset, so two equal instants can print with different
  // offset notation; comparing the real instant is the honest check here.
  check('H arrival', 'scheduled_at is computed from ORDER_TZ, not CHILD_TZ',
    DateTime.fromISO(res.body.scheduledAt).toMillis(), expectedScheduled.toMillis());

  const expectedDelayLow = Math.max(0, Math.round(before.diff(expectedScheduled, 'minutes').minutes));
  const expectedDelayHigh = Math.max(0, Math.round(after.diff(expectedScheduled, 'minutes').minutes));
  checkClose('H arrival', 'delayMinutes matches the real elapsed time (within 1 min)',
    res.body.delayMinutes, (expectedDelayLow + expectedDelayHigh) / 2, 1);
}

// ===========================================================================
// I · GET .../arrival now reflects the just-created real event.
// ===========================================================================
{
  const res = await getArrival(CHILD, momTok);
  check('I arrival get', 'a DIFFERENT guardian sees the same real event', res.status, 200);
  check('I arrival get', 'event is no longer null', res.body.event === null, false);
  check('I arrival get', 'delayMinutes is a real non-negative integer',
    Number.isInteger(res.body.event.delayMinutes) && res.body.event.delayMinutes >= 0, true);
}

// ===========================================================================
// J · honest absence — a child with NO active custody order gets a real
//     409, never a guessed/fabricated schedule.
// ===========================================================================
{
  const res = await postArrival(NOORDER_CHILD, dadTok);
  check('J no order', 'no active custody order -> real 409', res.status, 409);
  check('J no order', 'names the real reason', res.body.error, 'no_active_custody_order');

  const dbCount = (await admin.query(
    `SELECT count(*) AS n FROM exchange_arrival_event WHERE child_id = $1`, [NOORDER_CHILD]))
    .rows[0].n;
  check('J no order', 'no row was ever written for the honest-absence case', dbCount, '0');
}

// ===========================================================================
// K · role distinctions — a sitter (real calendar.view, no calendar.edit)
//     can read every GET but is refused every POST.
// ===========================================================================
{
  const getBag = await getBagItems(CHILD, sitterTok);
  check('K roles', 'sitter CAN view bag items', getBag.status, 200);
  const postBag = await postBagItem(CHILD, CHARGER_ID, sitterTok, { sent: true });
  check('K roles', 'sitter CANNOT toggle a bag item', postBag.status, 403);

  const getLate = await getRunningLate(CHILD, sitterTok);
  check('K roles', 'sitter CAN view the running-late log', getLate.status, 200);
  const postLate = await postRunningLate(CHILD, sitterTok, { etaMinutes: 5 });
  check('K roles', 'sitter CANNOT log running late', postLate.status, 403);

  const getArr = await getArrival(CHILD, sitterTok);
  check('K roles', 'sitter CAN view arrival status', getArr.status, 200);
  const postArr = await postArrival(CHILD, sitterTok);
  check('K roles', 'sitter CANNOT log an arrival', postArr.status, 403);
}

// ===========================================================================
// L · a child session is refused for every route.
// ===========================================================================
{
  check('L child refused', 'GET .../bag-items refused',
    (await getBagItems(CHILD, childTok)).status, 403);
  check('L child refused', 'POST .../bag-items/:id refused',
    (await postBagItem(CHILD, RETAINER_ID, childTok, { sent: true })).status, 403);
  check('L child refused', 'GET .../running-late refused',
    (await getRunningLate(CHILD, childTok)).status, 403);
  check('L child refused', 'POST .../running-late refused',
    (await postRunningLate(CHILD, childTok, { etaMinutes: 5 })).status, 403);
  check('L child refused', 'GET .../arrival refused',
    (await getArrival(CHILD, childTok)).status, 403);
  check('L child refused', 'POST .../arrival refused',
    (await postArrival(CHILD, childTok)).status, 403);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
