/**
 * server/routes.mjs — route contract test: GET/PUT
 * /v1/children/:childId/game-favorites. MASTERFILE §9.2,
 * docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-
 * design.md. db/migrations/0030_game_favorites.sql,
 * packages/db/src/pool.ts's gameFavoritesFor()/setGameFavoriteKinds()/
 * recordGamePickerOpen(), routes.mjs's own invalidGameFavoritesBody().
 *
 * Mirrors theme_route.test.mjs's own fake-DbPort + fake-pg.Pool harness
 * exactly (no real Postgres — that RLS ground truth is
 * packages/db/test/game_favorites.test.mjs's job, not this file's): this
 * file's job is the route itself — path, A3, the real can() authorizer,
 * invalidGameFavoritesBody(), the child/guardian split on the SAME PUT
 * verb, and the response shape.
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

// In-memory stand-ins for guardian_game_favorite (guardian_id -> Set<kind>)
// and child_game_picker_state (child_id -> ageAtLastOpen) — mirrors
// theme_route.test.mjs's own single-Map stand-in, split in two because the
// real schema is two tables with two different owners.
const favoriteStore = new Map();   // guardianId -> Set<string>
const stateStore = new Map();      // childId -> ageAtLastOpen

// guardiansOfChild()'s own real behaviour, stood in for directly (the real
// effective_guardianship join is packages/db/test/game_favorites.test.mjs's
// job, not this file's) — CHILD_A's guardians are DAD and OBSERVER, exactly
// matching the edges declared above.
const GUARDIANS_OF = { [CHILD_A]: [DAD, OBSERVER], [CHILD_C]: [] };

const db = {
  edgesFor: async (uid) => {
    if (uid === DAD) return [edge(CHILD_A, { userId: DAD })];
    if (uid === OBSERVER) return [edge(CHILD_A, { userId: OBSERVER, observerOnly: true })];
    return [];
  },
  // Unlike theme_route.test.mjs's own outer-q stub (its PUT handler never
  // touches `q` at all, in either branch), this route's CHILD branch calls
  // resolveChildLocalDate(q, childId) on the OUTER session before ever
  // reaching recordGamePickerOpen() — the identical shape the real letters
  // POST route already uses (routes.mjs). The GUARDIAN branch still never
  // touches `q` (setGameFavoriteKinds() opens its own session, matching
  // setChildTheme()'s own posture), so this stub only needs to answer
  // resolveChildLocalDate()'s own two SELECTs, honestly, rather than throw.
  withSession: async (_p, fn) => fn(async (sql) => {
    if (/FROM child_tz_interval/i.test(sql)) return [];
    if (/SELECT home_tz FROM child/i.test(sql)) return [{ home_tz: 'UTC' }];
    throw new Error(
      `game-favorites routes must not use the outer q for anything but resolveChildLocalDate — unexpected sql: ${sql}`);
  }),
};

// Fake pg.Pool — only what gameFavoritesFor()/setGameFavoriteKinds()/
// recordGamePickerOpen() touch via pool.connect() -> { query, release }.
// resolveChildLocalDate()'s own two SELECTs (child_tz_interval, then
// child.home_tz) both fall through to the same honest 'UTC' default here —
// no real timezone data is needed to prove the ROUTE's own contract.
const pool = {
  connect: async () => ({
    query: async (sql, params = []) => {
      if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return { rows: [] };
      if (/set_config/i.test(sql)) return { rows: [] };
      if (/FROM child_tz_interval/i.test(sql)) return { rows: [] };
      if (/SELECT home_tz FROM child/i.test(sql)) return { rows: [{ home_tz: 'UTC' }] };
      // guardiansOfChild()'s own real query (packages/db/src/pool.ts) —
      // gameFavoritesFor() calls it before ever touching
      // guardian_game_favorite, exactly like availabilityFor() already
      // does for guardian_availability_window.
      if (/SELECT DISTINCT user_id FROM effective_guardianship/i.test(sql)) {
        const [childId] = params;
        return { rows: (GUARDIANS_OF[childId] ?? []).map((user_id) => ({ user_id })) };
      }
      if (/^\s*SELECT DISTINCT kind FROM guardian_game_favorite/i.test(sql)) {
        const [guardianIds] = params;
        const kinds = new Set();
        for (const gid of guardianIds) for (const k of (favoriteStore.get(gid) ?? [])) kinds.add(k);
        return { rows: [...kinds].sort().map((kind) => ({ kind })) };
      }
      if (/^\s*SELECT age_at_last_open FROM child_game_picker_state/i.test(sql)) {
        const [childId] = params;
        const age = stateStore.get(childId);
        return { rows: age === undefined ? [] : [{ age_at_last_open: age }] };
      }
      if (/^\s*DELETE FROM guardian_game_favorite/i.test(sql)) {
        const [guardianId] = params;
        favoriteStore.delete(guardianId);
        return { rows: [] };
      }
      if (/^\s*INSERT INTO guardian_game_favorite/i.test(sql)) {
        const [guardianId, ...kinds] = params;
        favoriteStore.set(guardianId, new Set(kinds));
        return { rows: [] };
      }
      if (/^\s*INSERT INTO child_game_picker_state/i.test(sql)) {
        const [childId] = params;
        // The route's own fixed NOW/DOB is irrelevant here — this fake
        // proves the ROUTE dispatches to recordGamePickerOpen() and returns
        // its result; the real age arithmetic is game_favorites.test.mjs's
        // job against a real Postgres `age()` call.
        const age = 9;
        stateStore.set(childId, age);
        return { rows: [{ age_at_last_open: age }] };
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
const path = (childId) => `/v1/children/${childId}/game-favorites`;
const body = (o) => JSON.stringify(o);

// A · no session at all -> 401 for both verbs, same baseline gate every
// other child-scoped route already gets.
{
  check('A auth', 'no session -> GET 401', (await hit('GET', path(CHILD_A), null)).status, 401);
  check('A auth', 'no session -> PUT 401',
    (await hit('PUT', path(CHILD_A), null, body({ favoriteKinds: [] }))).status, 401);
}

// B · a guardian with a live edge — the real round trip, GET before any
// write reads back a clean, honest empty list and a null ageAtLastOpen.
{
  const before = await hit('GET', path(CHILD_A), dadTok);
  check('B round trip', 'GET before any write -> 200', before.status, 200);
  check('B round trip', 'favoriteKinds starts empty, not fabricated', before.body.favoriteKinds.join(','), '');
  check('B round trip', 'ageAtLastOpen starts null', before.body.ageAtLastOpen, 'null');

  const put = await hit('PUT', path(CHILD_A), dadTok, body({ favoriteKinds: ['tictactoe', 'chess'] }));
  check('B round trip', 'PUT with a live edge -> 200', put.status, 200);
  check('B round trip', 'PUT acks ok', put.body.ok, 'true');

  const after = await hit('GET', path(CHILD_A), dadTok);
  check('B round trip', 'favoriteKinds round-trips through the real route',
    after.body.favoriteKinds.sort().join(','), 'chess,tictactoe');

  // Full-replace semantics, matching setChildTheme()'s own upsert-the-whole
  // -preference posture — a second PUT with a SHORTER list drops the games
  // no longer named, never merges.
  const replace = await hit('PUT', path(CHILD_A), dadTok, body({ favoriteKinds: ['memory'] }));
  check('B round trip', 'a second PUT fully replaces the list -> 200', replace.status, 200);
  const afterReplace = await hit('GET', path(CHILD_A), dadTok);
  check('B round trip', 'the old favorites are genuinely gone, not merged',
    afterReplace.body.favoriteKinds.join(','), 'memory');
}

// C · invalidGameFavoritesBody() — a specific 400, no write happens.
{
  const nonObject = await hit('PUT', path(CHILD_A), dadTok, body('classic'));
  check('C validation', 'a bare string body -> 400', nonObject.status, 400);
  check('C validation', 'reason is body_must_be_object', nonObject.body.error, 'body_must_be_object');

  const missingField = await hit('PUT', path(CHILD_A), dadTok, body({}));
  check('C validation', 'missing favoriteKinds -> 400', missingField.status, 400);
  check('C validation', 'reason is favoriteKinds_must_be_array', missingField.body.error, 'favoriteKinds_must_be_array');

  const notArray = await hit('PUT', path(CHILD_A), dadTok, body({ favoriteKinds: 'chess' }));
  check('C validation', 'a bare string favoriteKinds -> 400', notArray.status, 400);
  check('C validation', 'reason is favoriteKinds_must_be_array (again)', notArray.body.error, 'favoriteKinds_must_be_array');

  const badEntry = await hit('PUT', path(CHILD_A), dadTok, body({ favoriteKinds: ['chess', 3] }));
  check('C validation', 'a non-string entry -> 400', badEntry.status, 400);
  check('C validation', 'reason is bad_favoriteKind', badEntry.body.error, 'bad_favoriteKind');

  // None of the four rejected PUTs above may have touched the row — still
  // exactly what B's last successful replace left it as.
  const stillMemory = await hit('GET', path(CHILD_A), dadTok);
  check('C validation', "an invalid PUT never reaches setGameFavoriteKinds() — row is untouched",
    stillMemory.body.favoriteKinds.join(','), 'memory');
}

// D · authorization — the two cases that matter most because GET has no RLS
// backstop (0030's own child_game_picker_state_system_read / the guardian
// half resolves via guardiansOfChild() at the app layer): a stranger and an
// observer-only guardian must both be denied.
{
  const strangerGet = await hit('GET', path(CHILD_C), dadTok);
  check('D authz', 'guardian with NO edge -> GET 403', strangerGet.status, 403);
  check('D authz', 'reason is no_edge', strangerGet.body.error, 'no_edge');
  const strangerPut = await hit('PUT', path(CHILD_C), dadTok, body({ favoriteKinds: ['chess'] }));
  check('D authz', 'guardian with NO edge -> PUT 403', strangerPut.status, 403);
  check('D authz', 'reason is no_edge', strangerPut.body.error, 'no_edge');
  check('D authz', "CHILD_C's favorites were never created by the denied PUT",
    favoriteStore.has(DAD) && [...favoriteStore.get(DAD)].join(',') === 'chess', 'false');

  // `action: 'settings'` is in authorize.ts's WRITES list, so the SAME
  // denial applies to the read, not only the write — the identical
  // observer-only posture theme_route.test.mjs's own section D already
  // proves for PUT/GET .../theme.
  const observerGet = await hit('GET', path(CHILD_A), observerTok);
  check('D authz', 'observer-only guardian -> GET 403 (not just PUT)', observerGet.status, 403);
  check('D authz', 'reason is observer_readonly', observerGet.body.error, 'observer_readonly');
  const observerPut = await hit('PUT', path(CHILD_A), observerTok, body({ favoriteKinds: ['chess'] }));
  check('D authz', 'observer-only guardian -> PUT 403', observerPut.status, 403);
  check('D authz', 'reason is observer_readonly', observerPut.body.error, 'observer_readonly');
}

// E · the child role — the split this whole route exists for: she reads the
// SAME resolved favourites her guardian set, can never write them herself,
// but CAN record her own visit (a completely different field, no body
// needed at all) — and doing so never touches the favourites list.
{
  const childGet = await hit('GET', path(CHILD_A), childTok);
  check('E child', 'the child reads the real, guardian-set favourites -> 200', childGet.status, 200);
  check('E child', 'and sees the real value, not a stub', childGet.body.favoriteKinds.join(','), 'memory');

  const childPutFavorites = await hit('PUT', path(CHILD_A), childTok, body({ favoriteKinds: ['chess'] }));
  check('E child', 'a child sending favoriteKinds is treated as her own visit, not a favourites write',
    childPutFavorites.status, 200);
  check('E child', "her attempted favoriteKinds body is silently ignored — never reaches setGameFavoriteKinds()",
    (await hit('GET', path(CHILD_A), dadTok)).body.favoriteKinds.join(','), 'memory');

  const childPutOpen = await hit('PUT', path(CHILD_A), childTok, body({}));
  check('E child', 'recording her own visit -> 200', childPutOpen.status, 200);
  check('E child', 'the response carries her freshly-computed ageAtLastOpen',
    typeof childPutOpen.body.ageAtLastOpen, 'number');

  const afterOpen = await hit('GET', path(CHILD_A), childTok);
  check('E child', 'ageAtLastOpen now round-trips through GET', afterOpen.body.ageAtLastOpen,
    childPutOpen.body.ageAtLastOpen);

  // A2/A3 still applies to this route like every other child-scoped one.
  const childWrongChild = await hit('GET', path(CHILD_C), childTok);
  check('E child', "a child token can't reach another child's game-favorites -> 403", childWrongChild.status, 403);
  check('E child', 'reason is wrong_child', childWrongChild.body.error, 'wrong_child');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
