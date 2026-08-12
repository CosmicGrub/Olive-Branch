/**
 * server/routes.mjs — GET /v1/children/:childId/availability and
 * PUT /v1/me/availability, real route CONTRACT test.
 *
 * Unlike stack.test.mjs's own "F api" section (which registers ad hoc routes
 * directly on a bare `Api` with a hand-written fake `DbPort`), this suite
 * drives the REAL `registerRoutes()` from server/routes.mjs — the actual
 * file wired into server/index.mjs — through a REAL `Api` instance. What's
 * faked is one layer deeper: a minimal `pg.Pool`-shaped object (`.connect()`
 * returning a client with `.query()`), because routes.mjs's availability
 * handlers call packages/db/src/pool.mjs's availabilityFor()/
 * setAvailabilityWindows() directly with the raw pool (mirroring
 * activeCustodyOrderFor()'s own established shape), not through the
 * Api-level DbPort abstraction.
 *
 * This proves: real route registration (method/path/action), the real A1
 * action requirement, the real can()/edgesFor() authorization path, the real
 * request-body validation, and the real SQL text + parameter order
 * pool.mjs's new functions issue (asserted against a query log) — end to
 * end, without a live Postgres.
 *
 * What this suite CANNOT prove — and does not claim to — is that Postgres's
 * own RLS on guardian_availability_window actually enforces "a guardian
 * writes only her own rows" / "co-guardian or her child can read". That is
 * db/migrations/0010_availability.sql's job, and packages/db/test/
 * availability.test.mjs (requires a real DATABASE_URL, same gate as
 * pool.test.mjs/custody_order.test.mjs) is what proves it.
 */
import { randomBytes } from 'node:crypto';
import { Api } from '../src/api.mjs';
import { dbPort } from '../../db/src/pool.mjs';
import { issueSession } from '../../auth/src/auth.mjs';
import { registerRoutes } from '../../../server/routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => {
  const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) });
};

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-08-11T18:00:00Z');

const CHILD = 'child-shared-1111';
const OTHER_CHILD = 'child-other-2222';
const DAD = 'guardian-dad-aaaa';
const MOM = 'guardian-mom-bbbb';
const STRANGER = 'guardian-stranger-cccc';

const liveEdge = (userId, childId) => ({
  child_id: childId, user_id: userId, role: 'guardian', scope: {},
  observer_only: false, restricted: false,
  valid_from: '2020-01-01T00:00:00Z', valid_to: null,
  expires_at: null, closed_at: null, ladder_step: 'open',
});

// ---------------------------------------------------------------------------
// A minimal fake pg.Pool. Every query pool.mjs's withSession()/
// withSystemSession() issues is routed through here; anything unrecognised
// throws rather than silently returning an empty result, so a real wiring
// mistake (e.g. a typo'd table/column name) fails the test loudly instead of
// masquerading as "zero rows".
// ---------------------------------------------------------------------------
function makeFakePool() {
  const writes = []; // { kind: 'DELETE'|'INSERT', params }

  const query = async (sql, params = []) => {
    const s = sql.trim();
    if (s === 'BEGIN' || s === 'COMMIT' || s.startsWith('ROLLBACK')) return { rows: [] };
    if (s.includes('set_config')) return { rows: [] };

    // edgesFor() — packages/db/src/pool.mjs, verbatim query shape.
    if (s.includes('FROM guardianship g')) {
      const userId = params[0];
      if (userId === DAD) return { rows: [liveEdge(DAD, CHILD)] };
      if (userId === MOM) return { rows: [liveEdge(MOM, CHILD)] };
      return { rows: [] }; // STRANGER — no edges anywhere
    }

    // guardiansOfChild() — every live guardian of `childId`.
    if (s.includes('DISTINCT user_id FROM effective_guardianship')) {
      const childId = params[0];
      if (childId === CHILD) return { rows: [{ user_id: DAD }, { user_id: MOM }] };
      return { rows: [] };
    }

    // availabilityFor()'s own SELECT (joined against app_user for guardian_name).
    if (s.includes('w.guardian_id, w.weekday') && s.includes('FROM guardian_availability_window w')) {
      return { rows: [
        { guardian_id: DAD, guardian_name: 'Dad', weekday: 1, start_local: '09:00', end_local: '12:00', note: 'mornings' },
        { guardian_id: MOM, guardian_name: 'Mom', weekday: 2, start_local: '13:00', end_local: '15:00', note: null },
      ] };
    }

    // setAvailabilityWindows()'s DELETE-then-INSERT replace-all.
    if (s.startsWith('DELETE FROM guardian_availability_window')) {
      writes.push({ kind: 'DELETE', params });
      return { rows: [] };
    }
    if (s.startsWith('INSERT INTO guardian_availability_window')) {
      writes.push({ kind: 'INSERT', params });
      return { rows: [] };
    }

    throw new Error(`fake pool: unrecognised query: ${s}`);
  };

  return { pool: { connect: async () => ({ query, release: () => {} }) }, writes };
}

// ===========================================================================
// A · GET /v1/children/:childId/availability
// ===========================================================================
{
  const { pool, writes } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);

  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const strangerTok = issueSession(SECRET, { userId: STRANGER, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const childTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

  const hit = (m, p, tok, body = '') =>
    api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {}, body);

  const ok = await hit('GET', `/v1/children/${CHILD}/availability`, dadTok);
  check('A GET', 'a live co-guardian gets 200', ok.status, 200);
  check('A GET', 'windows array round-trips from availabilityFor()', ok.body.windows.length, 2);
  check('A GET', 'includes the calling guardian\'s own row', ok.body.windows.some(w => w.guardianId === DAD), 'true');
  check('A GET', 'includes the co-guardian\'s row too', ok.body.windows.some(w => w.guardianId === MOM), 'true');
  check('A GET', 'weekday/startLocal/endLocal/note/guardianName all present',
    JSON.stringify(ok.body.windows[0]),
    JSON.stringify({ guardianId: DAD, guardianName: 'Dad', weekday: 1, startLocal: '09:00', endLocal: '12:00', note: 'mornings' }));

  const denied = await hit('GET', `/v1/children/${OTHER_CHILD}/availability`, strangerTok);
  check('A GET', 'a guardian with NO edge to the child is refused before the handler runs', denied.status, 403);
  check('A GET', 'denial names the real can() reason', denied.body.error, 'no_edge');

  const asChild = await hit('GET', `/v1/children/${CHILD}/availability`, childTok);
  check('A GET', 'the child of that same family reaches the handler (route-level; RLS itself is proven in availability.test.mjs)',
    asChild.status, 200);
  check('A GET', 'and sees the same windows the route returns', asChild.body.windows.length, 2);

  check('A GET', 'reading never touched the write path', writes.length, 0);
}

// ===========================================================================
// B · PUT /v1/me/availability
// ===========================================================================
{
  const { pool, writes } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);

  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const childTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);
  const hit = (m, p, tok, body = '') =>
    api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {}, body);

  const goodBody = JSON.stringify([
    { weekday: 1, startLocal: '09:00', endLocal: '12:00', note: 'mornings' },
    { weekday: 3, startLocal: '17:00', endLocal: '20:00' },
  ]);
  const put = await hit('PUT', '/v1/me/availability', dadTok, goodBody);
  check('B PUT', 'a valid replace-all set → 200', put.status, 200);
  check('B PUT', 'ok:true in the body', put.body.ok, 'true');
  check('B PUT', 'DELETE ran, scoped to the caller\'s own userId', writes[0]?.kind + ':' + writes[0]?.params[0], `DELETE:${DAD}`);
  check('B PUT', 'exactly 2 INSERTs followed the DELETE (replace-all, not append)',
    writes.filter(w => w.kind === 'INSERT').length, 2);
  check('B PUT', 'first INSERT carries the caller\'s guardianId, never from the body',
    writes[1].params[0], DAD);
  check('B PUT', 'first INSERT\'s weekday/times/note round-trip in order',
    writes[1].params.slice(1).join(','), '1,09:00,12:00,mornings');
  check('B PUT', 'a window with no note stores null, not the string "undefined"',
    writes[2].params[4], 'null');

  // ---- validation, before any DB call --------------------------------------
  const badWeekday = await hit('PUT', '/v1/me/availability', dadTok,
    JSON.stringify([{ weekday: 7, startLocal: '09:00', endLocal: '10:00' }]));
  check('B validate', 'weekday out of 0-6 → 400', badWeekday.status, 400);
  check('B validate', 'reason is specific', badWeekday.body.error, 'bad_weekday');

  const backwards = await hit('PUT', '/v1/me/availability', dadTok,
    JSON.stringify([{ weekday: 1, startLocal: '12:00', endLocal: '09:00' }]));
  check('B validate', 'end before start → 400', backwards.status, 400);
  check('B validate', 'reason is specific', backwards.body.error, 'endLocal_before_startLocal');

  const notArray = await hit('PUT', '/v1/me/availability', dadTok, JSON.stringify({ weekday: 1 }));
  check('B validate', 'a non-array body → 400', notArray.status, 400);
  check('B validate', 'reason is specific', notArray.body.error, 'body_must_be_array');

  // ---- role guard -----------------------------------------------------------
  const asChild = await hit('PUT', '/v1/me/availability', childTok, goodBody);
  check('B guard', 'a child session cannot write availability → 403', asChild.status, 403);
  check('B guard', 'reason names the guard', asChild.body.error, 'guardian_only');

  check('B guard', 'none of the 4 rejected requests above reached the write path (still just 1 DELETE + 2 INSERTs)',
    writes.length, 3);
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` +
    (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
