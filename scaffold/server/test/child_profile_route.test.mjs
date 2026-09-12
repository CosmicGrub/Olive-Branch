/**
 * server/routes.mjs — route contract test: PUT /v1/children/:childId/profile.
 * Onboarding & Guardian Access sub-project 1 (docs/superpowers/specs/
 * 2026-09-12-onboarding-identity-pin-design.md).
 * db/migrations/0031_child_profile.sql, packages/db/src/pool.ts's
 * setChildGender(), routes.mjs's own invalidProfileBody().
 *
 * Mirrors theme_route.test.mjs's own fake-DbPort + fake-pg.Pool harness
 * exactly (no real Postgres — that RLS ground truth is
 * packages/db/test/child_profile.test.mjs's job, not this file's): this
 * file's job is the route itself — path, A3, the real can() authorizer,
 * invalidProfileBody(), the child-only posture, and the response shape.
 *
 * This file is also where the design spec's own open question gets answered
 * and recorded, not merely assumed: "a guardian request 404s or is simply
 * unrouted — confirm which, document it." Section F below proves it directly
 * — a GET to this exact path is simply UNROUTED (no GET handler is
 * registered here at all), falling through to api.ts's own generic 404
 * `not_found`, the same as any other path this server has never heard of.
 * A guardian's PUT, by contrast, IS routed (the same `action: 'settings'`
 * capability that admits her reaches the handler) and is rejected
 * IN-HANDLER with a specific 403 `child_only` — a materially different
 * outcome from the GET case, confirmed in section D3.
 */
import { randomBytes } from 'node:crypto';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-09-12T12:00:00Z');
const DAD = 'dad-1';
const OBSERVER = 'observer-1';
const CHILD_A = 'child-with-live-edge';   // DAD (full edge) + OBSERVER (observer-only edge)
const CHILD_C = 'child-stranger';         // neither DAD nor OBSERVER has any edge to this child

const edge = (childId, opts = {}) => ({
  childId, userId: opts.userId ?? DAD, role: 'guardian', scope: {},
  observerOnly: opts.observerOnly ?? false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null, closedAt: null,
  ladderStep: null,
});

// In-memory stand-in for child_profile — one upsert-replace row per child,
// mirroring 0031's own PK/upsert shape closely enough for the route contract
// (the real upsert semantics, and the real CHECK constraint, are pool.mjs's
// job, proven for real against Postgres by child_profile.test.mjs).
const profileStore = new Map();

// Fake DbPort — the Api's own authz layer (edgesFor -> can()). withSession is
// called by the A2 wrapper for every route including this one, but the
// profile handler never touches the injected `q` (it calls
// setChildGender(pool, ...) directly against its own session) — matches
// routes.mjs's own skipOuterSession doc comment on that exact shape
// (theme/game-favorites routes take the identical posture), so the stub
// throwing if ever invoked is a real safety net, not a formality.
const db = {
  edgesFor: async (uid) => {
    if (uid === DAD) return [edge(CHILD_A, { userId: DAD })];
    if (uid === OBSERVER) return [edge(CHILD_A, { userId: OBSERVER, observerOnly: true })];
    return [];
  },
  withSession: async (_p, fn) => fn(async () => {
    throw new Error('the profile route must not use the outer q — it opens its own pool session');
  }),
};

// Fake pg.Pool — only what setChildGender() touches via pool.connect() ->
// { query, release }. No real Postgres anywhere in this file.
const pool = {
  connect: async () => ({
    query: async (sql, params = []) => {
      if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return { rows: [] };
      if (/set_config/i.test(sql)) return { rows: [] };
      if (/^\s*INSERT INTO child_profile/i.test(sql)) {
        const [childId, gender] = params;
        profileStore.set(childId, gender);
        return { rows: [] };
      }
      throw new Error(`fake pool: unexpected sql: ${sql}`);
    },
    release: () => {},
  }),
};

const api = new Api(SECRET, db, () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const observerTok = issueSession(SECRET, { userId: OBSERVER, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD_A, escalated: false }, NOW);

const hit = (m, p, tok, rawBody = '') =>
  api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {}, rawBody);
const path = (childId) => `/v1/children/${childId}/profile`;
const body = (o) => JSON.stringify(o);

// A · no session at all -> 401, same baseline gate every other child-scoped
// route already gets.
{
  check('A auth', 'no session -> PUT 401',
    (await hit('PUT', path(CHILD_A), null, body({ gender: 'girl' }))).status, 401);
}

// B · the child role — the real round trip through the route.
{
  const put = await hit('PUT', path(CHILD_A), childTok, body({ gender: 'girl' }));
  check('B round trip', 'a real tap, child session -> 200', put.status, 200);
  check('B round trip', 'PUT acks ok', put.body.ok, 'true');
  check('B round trip', 'setChildGender() really receives the tapped value',
    profileStore.get(CHILD_A), 'girl');

  // A2/A3 still applies to this route like every other child-scoped one —
  // a child token can't reach a DIFFERENT child's profile by path alone.
  const wrongChild = await hit('PUT', path(CHILD_C), childTok, body({ gender: 'boy' }));
  check('B round trip', "a child token can't reach another child's profile -> 403",
    wrongChild.status, 403);
  check('B round trip', 'reason is wrong_child', wrongChild.body.error, 'wrong_child');
}

// C · invalidProfileBody() — a specific 400, no write happens.
{
  const nonObject = await hit('PUT', path(CHILD_A), childTok, body('girl'));
  check('C validation', 'a bare string body -> 400', nonObject.status, 400);
  check('C validation', 'reason is body_must_be_object', nonObject.body.error, 'body_must_be_object');

  const missingField = await hit('PUT', path(CHILD_A), childTok, body({}));
  check('C validation', 'missing gender -> 400', missingField.status, 400);
  check('C validation', 'reason is bad_gender', missingField.body.error, 'bad_gender');

  const badValue = await hit('PUT', path(CHILD_A), childTok, body({ gender: 'other' }));
  check('C validation', 'a gender outside boy/girl -> 400', badValue.status, 400);
  check('C validation', 'reason is bad_gender (again)', badValue.body.error, 'bad_gender');

  // None of the three rejected PUTs above may have touched the row — still
  // exactly what B's last successful write left it as.
  check('C validation', 'an invalid PUT never reaches setChildGender() — row is untouched',
    profileStore.get(CHILD_A), 'girl');
}

// D · authorization — three materially different guardian outcomes on the
// SAME path, none of them a successful write.
{
  // D1 — a guardian with NO live edge to the child at all: denied at the
  // OUTER A3 gate, the same as every other 'settings' route.
  const strangerPut = await hit('PUT', path(CHILD_C), dadTok, body({ gender: 'boy' }));
  check('D authz', 'guardian with NO edge -> PUT 403', strangerPut.status, 403);
  check('D authz', 'reason is no_edge', strangerPut.body.error, 'no_edge');

  // D2 — an observer-only guardian: 'settings' is in authorize.ts's WRITES
  // list, so she is denied at the SAME outer gate, never reaching this
  // route's own in-handler check at all — the identical posture
  // theme_route.test.mjs's/game_favorites_route.test.mjs's own section D
  // already proves for the sibling preference routes.
  const observerPut = await hit('PUT', path(CHILD_A), observerTok, body({ gender: 'boy' }));
  check('D authz', 'observer-only guardian -> PUT 403', observerPut.status, 403);
  check('D authz', 'reason is observer_readonly', observerPut.body.error, 'observer_readonly');

  // D3 — a FULL guardian with a live edge: 'settings' admits her at the
  // outer gate (the same capability that admits her to theme/game-favorites),
  // so she genuinely REACHES this route's handler — and is rejected there,
  // specifically, with the literal inverse of guardian_only: `child_only`.
  // This is the one case that answers the design spec's own open question
  // for the PUT verb: a guardian's PUT here is ROUTED, not unrouted, and
  // fails for a documented, in-handler reason.
  const dadPut = await hit('PUT', path(CHILD_A), dadTok, body({ gender: 'boy' }));
  check('D authz', 'a full guardian with a live edge reaches the handler and is '
    + 'rejected there -> 403', dadPut.status, 403);
  check('D authz', 'reason is child_only — the literal inverse of guardian_only',
    dadPut.body.error, 'child_only');
  check('D authz', "the guardian's rejected PUT never touched the row",
    profileStore.get(CHILD_A), 'girl');
}

// E · a second, DIFFERENT real tap replaces the first — upsert, matching
// setChildGender()'s own "overwritten, never a log" contract at the route
// level too, not only at pool.ts's.
{
  const put = await hit('PUT', path(CHILD_A), childTok, body({ gender: 'boy' }));
  check('E replace', 'a second, different tap -> 200', put.status, 200);
  check('E replace', 'the value really replaces the first', profileStore.get(CHILD_A), 'boy');
}

// F · no guardian-facing read route exists for this data in this pass — the
// design spec's own open question, answered directly: a GET to this exact
// path is simply UNROUTED (no GET handler registered here at all), not
// merely refused for a role reason. Proven for BOTH a guardian and the
// child herself, since neither principal has any way to reach a route that
// was never registered.
{
  const guardianGet = await hit('GET', path(CHILD_A), dadTok);
  check('F no read route', 'a guardian GET to this path is simply unrouted -> 404',
    guardianGet.status, 404);
  check('F no read route', "reason is api.ts's own generic not_found, not a role-specific "
    + 'denial', guardianGet.body.error, 'not_found');

  const childGet = await hit('GET', path(CHILD_A), childTok);
  check('F no read route', 'the CHILD herself gets the identical unrouted 404 -- there is '
    + 'no read surface for anyone, not even her own session', childGet.status, 404);
  check('F no read route', 'reason is the same generic not_found', childGet.body.error, 'not_found');

  const noSessionGet = await hit('GET', path(CHILD_A), null);
  check('F no read route', 'even with no session at all, the route is unrouted before auth '
    + 'is ever checked -> 404, not 401', noSessionGet.status, 404);
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
