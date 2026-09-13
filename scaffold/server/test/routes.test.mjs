/**
 * server/routes.mjs — route contract test: GET /v1/children/:childId/custody-order.
 * MASTERFILE §5.4, §9.4. db/migrations/0007_custody_order.sql,
 * packages/db/src/pool.ts's activeCustodyOrderFor().
 *
 * Exercises the REAL Api + registerRoutes wiring (auth, A3 childId-from-path,
 * the real `can()` authorizer) the same way packages/api/test/stack.test.mjs's
 * "F · API" section does, against a hand-written fake `DbPort` AND a
 * hand-written fake `pg.Pool` — registerRoutes takes both (see its own header
 * comment: `pool` is raw, independent of the Api's own caller-scoped DbPort,
 * because activeCustodyOrderFor() opens its own system session). No real
 * Postgres involved here; packages/db/test/custody_order.test.mjs already
 * proves activeCustodyOrderFor() itself against a real one, RLS included —
 * this file's job is proving the ROUTE (path, action, auth gates, response
 * shape), not the query.
 */
import { randomBytes } from 'node:crypto';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-08-11T12:00:00Z');
const DAD = 'dad-1';
const CHILD_A = 'child-with-order';       // DAD has an edge; has a real custody_order row
const CHILD_B = 'child-no-order-row';     // DAD has an edge; NO custody_order row (empty state)
const CHILD_C = 'child-stranger';         // DAD has NO edge (authz must deny)
const CHILD_GHOST = 'child-not-in-db';    // DAD has an edge, but the child row itself doesn't exist

const edge = (childId) => ({ childId, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false, validFrom: '2020-01-01T00:00:00Z',
  validTo: null, expiresAt: null, closedAt: null, ladderStep: null });

// Fixture data + query logic shared by BOTH fakes below. The route handler
// under test runs some queries through the Api's caller-scoped `q` (child_tz_
// interval, child.home_tz) and one through activeCustodyOrderFor(pool, ...)'s
// OWN system session (custody_order) — see routes.mjs's own header comment on
// why those are two separate connections in the real server. Sharing this
// function is what makes both fakes agree on "does this child exist / have an
// order" instead of two independently-hand-maintained fixtures drifting.
const ORDER_ROW = {
  pattern: '2-2-3', order_tz: 'America/New_York',
  anchor_local_date: '2026-01-05', exchange_time: '18:00',
  holiday_rules: [{ name: 'Winter Break', startMonthDay: '12-20', endMonthDay: '01-02',
    evenYearSide: 'A', priority: 5 }],
  effective_from: '2020-01-01', effective_to: null,
};
async function fakeQuery(sql, params = []) {
  if (/FROM child_tz_interval/i.test(sql)) return []; // no interval fixture -> falls back to home_tz
  if (/FROM child WHERE id/i.test(sql)) {
    const [childId] = params;
    return childId === CHILD_GHOST ? [] : [{ home_tz: 'America/New_York' }];
  }
  if (/FROM custody_order/i.test(sql)) {
    const [childId] = params;
    return childId === CHILD_A ? [ORDER_ROW] : [];
  }
  throw new Error(`fake query: unexpected sql: ${sql}`);
}

// Fake DbPort — the Api's OWN authz layer + the caller-scoped `q` the handler
// runs child_tz_interval/child.home_tz through.
const db = {
  edgesFor: async (uid) => uid === DAD
    ? [edge(CHILD_A), edge(CHILD_B), edge(CHILD_GHOST)]
    : [],
  withSession: async (p, fn) => fn(fakeQuery),
};

// Fake pg.Pool — only what withSession()/activeCustodyOrderFor() touch:
// pool.connect() -> { query, release }. No real Postgres anywhere in this file.
const pool = {
  connect: async () => ({
    query: async (sql, params = []) => {
      if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return { rows: [] };
      if (/set_config/i.test(sql)) return { rows: [] };
      return { rows: await fakeQuery(sql, params) };
    },
    release: () => {},
  }),
};

const api = new Api(SECRET, db, () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD_A, escalated: false }, NOW);
const hit = (m, p, tok) => api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {}, '');
const path = (childId) => `/v1/children/${childId}/custody-order`;

// A · auth/authz — the same gates every other child-scoped route gets for free
{
  check('A auth', 'no session -> 401', (await hit('GET', path(CHILD_A), null)).status, 401);
  const stranger = await hit('GET', path(CHILD_C), dadTok);
  check('A auth', 'guardian with no edge to the child -> 403', stranger.status, 403);
  check('A auth', 'denial names the real reason', stranger.body.error, 'no_edge');
  const wrongChild = await hit('GET', path(CHILD_B), childTok);
  check('A auth', "a child token can't reach another child's order -> 403", wrongChild.status, 403);
  check('A auth', 'reason is wrong_child', wrongChild.body.error, 'wrong_child');
}

// B · a real order round-trips through the route in the exact Order shape
{
  const res = await hit('GET', path(CHILD_A), dadTok);
  check('B populated', 'authorized guardian -> 200', res.status, 200);
  check('B populated', 'pattern', res.body.order?.pattern, '2-2-3');
  check('B populated', 'orderTz', res.body.order?.orderTz, 'America/New_York');
  check('B populated', 'anchorLocalDate', res.body.order?.anchorLocalDate, '2026-01-05');
  check('B populated', 'exchangeTime', res.body.order?.exchangeTime, '18:00');
  check('B populated', 'holidays round-trip', res.body.order?.holidays?.[0]?.name, 'Winter Break');
  check('B populated', 'effectiveFrom', res.body.order?.effectiveFrom, '2020-01-01');
  check('B populated', 'effectiveTo is null, not a fabricated date', res.body.order?.effectiveTo, 'null');

  const asChild = await hit('GET', path(CHILD_A), childTok);
  check('B populated', 'the owning child can read her own order too -> 200', asChild.status, 200);
  check('B populated', 'and gets the same pattern', asChild.body.order?.pattern, '2-2-3');
}

// C · honest absence — a real child with no custody_order row
{
  const res = await hit('GET', path(CHILD_B), dadTok);
  check('C empty', 'a child with no order still -> 200, not an error', res.status, 200);
  check('C empty', 'order is null, never guessed at', res.body.order, 'null');
}

// D · a child that does not exist at all is a real 404, distinct from "no order yet"
{
  const res = await hit('GET', path(CHILD_GHOST), dadTok);
  check('D ghost', 'child_not_found -> 404', res.status, 404);
  check('D ghost', 'reason surfaces', res.body.error, 'child_not_found');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
