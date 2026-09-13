/**
 * server/routes.mjs — route contract test: GET/PUT /v1/children/:childId/theme.
 * MASTERFILE §8.1, docs/superpowers/specs/2026-08-21-intuitivism-visual-
 * foundation-design.md. db/migrations/0017_child_theme_preference.sql,
 * packages/db/src/pool.ts's themeFor()/setChildTheme(), routes.mjs's own
 * invalidThemeBody().
 *
 * 2026-08-24 audit (§8.16, Tier-3) — real gap this file closes: the theme
 * routes had a real Postgres RLS suite (packages/db/test/theme_preference
 * .test.mjs) but NOTHING exercised the ROUTE itself — no test proved
 * invalidThemeBody() actually reaches the handler and returns a specific
 * 400, no test proved a guardian with NO edge to the child is denied, and
 * no test proved the child-reads/guardian-writes split routes.mjs's own
 * header describes. That gap was not cosmetic:
 *
 *   - GET's real backing, themeFor(), reads as `system` role (0017's own
 *     child_theme_system_read policy comment: "the route handler's real A3
 *     childId-from-path + can('settings', ...) check already gated this
 *     call before it runs"). That means for READS, the app-layer can()
 *     check in packages/family-graph/src/authorize.ts is not a *second*
 *     lock alongside RLS the way it is for the WRITE path — it is the ONLY
 *     lock. A route wired without it (or with the wrong Action) would leak
 *     every child's theme to every guardian session, and RLS would not
 *     catch it. That is exactly the kind of mistake only a route-level
 *     test (real Api + registerRoutes + real can(), no real Postgres
 *     needed) can catch — proven here the same way server/test/
 *     routes.test.mjs already proves it for custody-order.
 *
 *   - 0017's own migration comment documents, in so many words, that an
 *     observer-only guardian is denied even a READ of this route ("the
 *     finer-grained scope distinction enforced one layer up, at the
 *     route") — deliberately NOT enforced by RLS (any live 'guardian' edge
 *     passes the DB policy). Section D below is the first test anywhere in
 *     this repo that actually exercises that documented behavior; until
 *     now it was provable only by reading the comment.
 *
 * Uses the exact fake-DbPort + fake-pg.Pool harness routes.test.mjs already
 * established (no real Postgres — that RLS ground truth is
 * theme_preference.test.mjs's job, not this file's); this file's job is the
 * route: path, A3, the real can() authorizer, invalidThemeBody(), and the
 * response shape.
 */
import { randomBytes } from 'node:crypto';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-08-24T12:00:00Z');
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

// In-memory stand-in for child_theme_preference — one upsert-replace row per
// child, mirroring 0017's own PK/upsert shape closely enough for the route
// contract (the real upsert semantics are pool.mjs's job, proven for real
// against Postgres by theme_preference.test.mjs's "A loaders" section).
const themeStore = new Map();

// Fake DbPort — the Api's own authz layer (edgesFor -> can()). withSession is
// called by the A2 wrapper for every route including these two, but the
// theme handlers never touch the injected `q` (they call themeFor(pool,...)/
// setChildTheme(pool,...) directly against their OWN sessions) — matches
// routes.mjs's own skipOuterSession doc comment on that exact shape, so the
// stub throwing if ever invoked is a real safety net, not a formality.
const db = {
  edgesFor: async (uid) => {
    if (uid === DAD) return [edge(CHILD_A, { userId: DAD })];
    if (uid === OBSERVER) return [edge(CHILD_A, { userId: OBSERVER, observerOnly: true })];
    return [];
  },
  withSession: async (_p, fn) => fn(async () => {
    throw new Error('theme routes must not use the outer q — they open their own pool sessions');
  }),
};

// Fake pg.Pool — only what themeFor()/setChildTheme() touch via pool.connect()
// -> { query, release }. No real Postgres anywhere in this file.
const pool = {
  connect: async () => ({
    query: async (sql, params = []) => {
      if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return { rows: [] };
      if (/set_config/i.test(sql)) return { rows: [] };
      if (/^\s*SELECT/i.test(sql) && /child_theme_preference/i.test(sql)) {
        const [childId] = params;
        const row = themeStore.get(childId);
        return { rows: row ? [{ theme_palette: row.themePalette, theme_brightness: row.themeBrightness }] : [] };
      }
      if (/^\s*INSERT/i.test(sql) && /child_theme_preference/i.test(sql)) {
        const [childId, themePalette, themeBrightness] = params;
        themeStore.set(childId, { themePalette, themeBrightness });
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
const path = (childId) => `/v1/children/${childId}/theme`;
const body = (o) => JSON.stringify(o);

// A · no session at all -> 401 for both verbs, same baseline gate every
// other child-scoped route already gets.
{
  check('A auth', 'no session -> GET 401', (await hit('GET', path(CHILD_A), null)).status, 401);
  check('A auth', 'no session -> PUT 401',
    (await hit('PUT', path(CHILD_A), null, body({ themePalette: 'classic', themeBrightness: 'light' }))).status, 401);
}

// B · a guardian with a live edge — the real round trip through the route,
// GET before any Apply reads back a clean, honest null (never a fabricated
// default), matching 0017's own "unset row is the real, common case" rule.
{
  const before = await hit('GET', path(CHILD_A), dadTok);
  check('B round trip', 'GET before any Apply -> 200', before.status, 200);
  check('B round trip', 'theme is null, not a fabricated default', before.body.theme, 'null');

  const put = await hit('PUT', path(CHILD_A), dadTok, body({ themePalette: 'calmModern', themeBrightness: 'light' }));
  check('B round trip', 'PUT with a live edge -> 200', put.status, 200);
  check('B round trip', 'PUT acks ok', put.body.ok, 'true');

  const after = await hit('GET', path(CHILD_A), dadTok);
  check('B round trip', 'GET after Apply -> 200', after.status, 200);
  check('B round trip', 'themePalette round-trips through the real route', after.body.theme?.themePalette, 'calmModern');
  check('B round trip', 'themeBrightness round-trips through the real route', after.body.theme?.themeBrightness, 'light');
}

// C · invalidThemeBody() — the real gap: nothing anywhere exercised this
// function through the actual route before this file. A specific 400
// reason, not a bare Postgres CHECK-constraint 500, and no write happens.
{
  const badPalette = await hit('PUT', path(CHILD_A), dadTok,
    body({ themePalette: 'neonRetro', themeBrightness: 'dark' }));
  check('C validation', 'unknown palette -> 400', badPalette.status, 400);
  check('C validation', 'reason is bad_themePalette', badPalette.body.error, 'bad_themePalette');

  const badBrightness = await hit('PUT', path(CHILD_A), dadTok,
    body({ themePalette: 'classic', themeBrightness: 'sepia' }));
  check('C validation', 'unknown brightness -> 400', badBrightness.status, 400);
  check('C validation', 'reason is bad_themeBrightness', badBrightness.body.error, 'bad_themeBrightness');

  const missingFields = await hit('PUT', path(CHILD_A), dadTok, body({}));
  check('C validation', 'empty body -> 400', missingFields.status, 400);
  check('C validation', 'reason is bad_themePalette (checked first)', missingFields.body.error, 'bad_themePalette');

  const nonObject = await hit('PUT', path(CHILD_A), dadTok, body('classic'));
  check('C validation', 'a bare string body -> 400', nonObject.status, 400);
  check('C validation', 'reason is body_must_be_object', nonObject.body.error, 'body_must_be_object');

  // None of the four rejected PUTs above may have touched the row — still
  // exactly what B's last successful Apply left it as.
  const stillCalmModern = await hit('GET', path(CHILD_A), dadTok);
  check('C validation', "an invalid PUT never reaches setChildTheme() — row is untouched",
    stillCalmModern.body.theme?.themePalette, 'calmModern');
}

// D · authorization — the two cases that matter most because GET has no RLS
// backstop (0017's own child_theme_system_read policy: themeFor() runs as
// `system`, trusting this app-layer gate completely).
{
  // D1 — a guardian with NO live edge to the child at all. GET must be
  // denied here, at the route, or it would silently hand back another
  // family's theme (the system-role read admits it).
  const strangerGet = await hit('GET', path(CHILD_C), dadTok);
  check('D authz', 'guardian with NO edge -> GET 403', strangerGet.status, 403);
  check('D authz', 'reason is no_edge', strangerGet.body.error, 'no_edge');
  const strangerPut = await hit('PUT', path(CHILD_C), dadTok,
    body({ themePalette: 'classic', themeBrightness: 'light' }));
  check('D authz', 'guardian with NO edge -> PUT 403', strangerPut.status, 403);
  check('D authz', 'reason is no_edge', strangerPut.body.error, 'no_edge');
  check('D authz', "CHILD_C's row was never created by the denied PUT",
    themeStore.has(CHILD_C), 'false');

  // D2 — an observer-only guardian (§17.3: "a reluctant parent watching, not
  // participating"). 0017's own migration comment documents this exact
  // denial as intentional and says the enforcement is "one layer up, at the
  // route" — this is that route, and until this file nothing proved it.
  // `action: 'settings'` is reused for BOTH verbs and is in authorize.ts's
  // WRITES list, so the SAME denial applies to the read, not only the write.
  const observerGet = await hit('GET', path(CHILD_A), observerTok);
  check('D authz', 'observer-only guardian -> GET 403 (not just PUT)', observerGet.status, 403);
  check('D authz', 'reason is observer_readonly', observerGet.body.error, 'observer_readonly');
  const observerPut = await hit('PUT', path(CHILD_A), observerTok,
    body({ themePalette: 'brightBold', themeBrightness: 'dark' }));
  check('D authz', 'observer-only guardian -> PUT 403', observerPut.status, 403);
  check('D authz', 'reason is observer_readonly', observerPut.body.error, 'observer_readonly');
}

// E · child role — §8.1's "no settings affordance" for the child, confirmed
// directly: she reads the SAME real row her guardian set (not a curated or
// fabricated child-only view), but can never write it, even her own.
{
  const childGetOwn = await hit('GET', path(CHILD_A), childTok);
  check('E child', "the child reads her OWN theme -> 200", childGetOwn.status, 200);
  check('E child', 'and sees the real guardian-set value, not a stub',
    childGetOwn.body.theme?.themePalette, 'calmModern');

  const childPutOwn = await hit('PUT', path(CHILD_A), childTok,
    body({ themePalette: 'deepCozy', themeBrightness: 'dark' }));
  check('E child', 'the child cannot write even her OWN theme -> 403', childPutOwn.status, 403);
  check('E child', 'reason is guardian_only', childPutOwn.body.error, 'guardian_only');

  // Prove the denied write really left nothing behind, not just that the
  // response said 403.
  const afterChildAttempt = await hit('GET', path(CHILD_A), dadTok);
  check('E child', "the child's rejected PUT did not change the row",
    afterChildAttempt.body.theme?.themePalette, 'calmModern');

  // A2/A3 still applies to this route like every other child-scoped one —
  // a child token can't reach a DIFFERENT child's theme by path alone.
  const childWrongChild = await hit('GET', path(CHILD_C), childTok);
  check('E child', "a child token can't reach another child's theme -> 403", childWrongChild.status, 403);
  check('E child', 'reason is wrong_child', childWrongChild.body.error, 'wrong_child');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
