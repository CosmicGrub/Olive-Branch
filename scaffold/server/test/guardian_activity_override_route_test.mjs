/**
 * UNVERIFIED (this is a Node/JS test file, not a Dart one — see this repo's
 * own "I contract" marker discipline; that discipline only requires the
 * marker on client .dart files, and this file names it anyway for the same
 * honest reason every other route-contract file in this repo carries:
 * exercised against a hand-written fake `pg.Pool`, never a real device or a
 * real Postgres.
 *
 * server/routes.mjs — route contract tests for the parental-controls
 * visibility & pacing routes. docs/superpowers/specs/2026-09-13-parental-
 * controls-pacing-design.md. db/migrations/0033_guardian_activity_override
 * .sql, packages/db/src/pool.ts's activityOverridesFor()/
 * setActivityOverride()/deleteActivityOverride(), routes.mjs's own
 * invalidActivityOverrideBody() and POST /v1/me/verify-controls-pin.
 *
 * Same technique as theme_route.test.mjs/device_pairing_route_test.mjs: the
 * REAL `Api` + `registerRoutes` wiring, driven through `api.handle()`,
 * against a hand-written fake `pg.Pool` — no real Postgres (that RLS ground
 * truth is packages/db/test/guardian_activity_override.test.mjs's job).
 *
 * The real gap this file specifically has to prove, because it's the one
 * deliberate divergence from theme_route.test.mjs's own established shape:
 * GET here does NOT run as `system` (unlike themeFor()) — activityOverridesFor()
 * opens its session as the REAL calling principal, so this file's fake pool
 * must answer queries under BOTH a guardian's own connection AND a child's
 * own connection, and the fake has to actually respect `app.role`/
 * `app.child_id`/`app.user_id` the way real RLS would, or this test would
 * prove nothing about the "RLS alone decides scope" design.
 */
import { randomBytes } from 'node:crypto';
import { issueSession, hashPin } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-09-13T12:00:00Z');
const DAD = 'dad-1';           // live guardian of CHILD_A
const OBSERVER = 'observer-1'; // observer-only guardian of CHILD_A
const STRANGER = 'stranger-1'; // no edge to CHILD_A at all
const CHILD_A = 'child-alpha';
const CHILD_C = 'child-stranger'; // nobody above has any edge to this child

const edge = (childId, opts = {}) => ({
  childId, userId: opts.userId ?? DAD, role: 'guardian', scope: {},
  observerOnly: opts.observerOnly ?? false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null, closedAt: null,
  ladderStep: null,
});

// pin_credential fake, reused verbatim from kiosk_pin_route.test.mjs's own
// shape — DAD has a real PIN, OBSERVER does not.
const credentials = new Map();
credentials.set(DAD, { pin_hash: hashPin('1357'), failed_attempts: 0, locked_until: null });

// In-memory stand-in for guardian_activity_override — a real RLS engine
// would key visibility on the connection's own role/actor; this fake
// approximates that by keying every query off the session GUCs the pool.ts
// functions actually set via `set_config`, captured per-connection below.
const overrideStore = new Map(); // `${childId}::${activityKey}` -> row

function fakeQuery(session, sql, params = []) {
  if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return [];
  const m = /set_config\('(app\.\w+)', \$1, true\)/.exec(sql);
  if (m) { session[m[1]] = params[0] === '' ? null : params[0]; return []; }

  // ---------------------------------------------------- pin_credential ----
  if (/SELECT pin_hash, failed_attempts, locked_until\s+FROM pin_credential WHERE user_id = \$1/i.test(sql)) {
    const [userId] = params;
    const c = credentials.get(userId);
    return c ? [{ pin_hash: c.pin_hash, failed_attempts: c.failed_attempts, locked_until: c.locked_until }] : [];
  }
  if (/UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL/i.test(sql) && !/CASE/i.test(sql)) {
    const [userId] = params;
    const c = credentials.get(userId);
    if (c) { c.failed_attempts = 0; c.locked_until = null; }
    return [];
  }
  if (/UPDATE pin_credential[\s\S]*CASE WHEN failed_attempts/i.test(sql)) {
    const [userId, maxAttempts, lockoutMs] = params;
    const c = credentials.get(userId);
    if (c) {
      if (c.failed_attempts + 1 >= maxAttempts) { c.failed_attempts = 0; c.locked_until = new Date(Date.now() + Number(lockoutMs)); }
      else { c.failed_attempts += 1; }
    }
    return [];
  }

  // --------------------------------------------- guardian_activity_override
  if (/^\s*SELECT activity_key, visible, min_age_override, revealed_at, set_by, set_at\s+FROM guardian_activity_override/i.test(sql)) {
    const [childId] = params;
    // RLS approximation: a 'guardian' role sees every row for a child it has
    // a live edge to (mirrors actor_has_edge()); a 'child' role sees only
    // her own child_id, and only if it matches current_child(). Neither
    // check is re-derived from the edge list here (this file's fake pool has
    // no edge table) — the ROUTE's own A3 action:'settings' gate has already
    // refused a no-edge guardian before this query ever runs (proven in
    // section D below), so by the time this fires, a 'guardian' session is
    // always a real one; this fake's own job is just to prove the query
    // shape/session-scoping, not re-litigate authorize.ts.
    if (session['app.role'] === 'child' && session['app.child_id'] !== childId) return [];
    if (session['app.role'] !== 'guardian' && session['app.role'] !== 'child') return [];
    return [...overrideStore.values()]
      .filter((r) => r.child_id === childId)
      .sort((a, b) => a.activity_key.localeCompare(b.activity_key));
  }
  if (/^\s*INSERT INTO guardian_activity_override/i.test(sql)) {
    if (session['app.role'] !== 'guardian') throw new Error('write attempted under a non-guardian session');
    const [childId, activityKey, visible, minAge, revealedAt, setBy,
           hasVisible, hasMinAge, touchesRevealedAt] = params;
    const key = `${childId}::${activityKey}`;
    const existing = overrideStore.get(key);
    const row = {
      child_id: childId, activity_key: activityKey,
      visible: existing && !hasVisible ? existing.visible : visible,
      min_age_override: existing && !hasMinAge ? existing.min_age_override : minAge,
      revealed_at: existing && !touchesRevealedAt ? existing.revealed_at : revealedAt,
      set_by: setBy, set_at: new Date().toISOString(),
    };
    overrideStore.set(key, row);
    return [];
  }
  if (/^\s*DELETE FROM guardian_activity_override WHERE child_id = \$1 AND activity_key = \$2/i.test(sql)) {
    if (session['app.role'] !== 'guardian') throw new Error('delete attempted under a non-guardian session');
    const [childId, activityKey] = params;
    overrideStore.delete(`${childId}::${activityKey}`);
    return [];
  }

  throw new Error(`fake query: unexpected sql: ${sql}`);
}

const pool = {
  connect: async () => {
    const session = {};
    return {
      query: async (sql, params = []) => ({ rows: fakeQuery(session, sql, params) }),
      release: () => {},
    };
  },
};

// Fake DbPort for the Api itself — GET/PUT/DELETE here are ALL
// `action: 'settings'` (not identityScopedByHandler), so the outer
// db.withSession() wrapper genuinely runs for every one of them, same as
// theme_route.test.mjs's own fake — the handlers never touch the injected
// `q` (activityOverridesFor()/setActivityOverride()/deleteActivityOverride()
// each open their own real session against `pool` directly), so the stub
// throwing if ever invoked is a real safety net, not a formality.
const db = {
  edgesFor: async (uid) => {
    if (uid === DAD) return [edge(CHILD_A, { userId: DAD })];
    if (uid === OBSERVER) return [edge(CHILD_A, { userId: OBSERVER, observerOnly: true })];
    return [];
  },
  withSession: async (_p, fn) => fn(async () => {
    throw new Error('activity-override routes must not use the outer q — they open their own pool sessions');
  }),
};

const api = new Api(SECRET, db, () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const observerTok = issueSession(SECRET, { userId: OBSERVER, roleName: 'guardian', childId: null, escalated: false }, NOW);
const strangerTok = issueSession(SECRET, { userId: STRANGER, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD_A, escalated: false }, NOW);

const hit = (m, p, tok, rawBody) =>
  api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {},
    rawBody === undefined ? '' : JSON.stringify(rawBody));
const overridesPath = (childId) => `/v1/children/${childId}/activity-overrides`;
const overridePath = (childId, key) => `/v1/children/${childId}/activity-overrides/${key}`;

// ===========================================================================
// A · POST /v1/me/verify-controls-pin — the screen-entry gate.
// ===========================================================================
{
  const noSession = await hit('POST', '/v1/me/verify-controls-pin', null, { pin: '1357' });
  check('A pin gate', 'no session -> 401', noSession.status, 401);

  const asChild = await hit('POST', '/v1/me/verify-controls-pin', childTok, { pin: '1357' });
  check('A pin gate', 'a child session -> 403 guardian_session_required', asChild.status, 403);
  check('A pin gate', 'reason', asChild.body.error, 'guardian_session_required');

  const wrongPin = await hit('POST', '/v1/me/verify-controls-pin', dadTok, { pin: '0000' });
  check('A pin gate', "DAD's own WRONG pin -> 403 pin_incorrect", wrongPin.status, 403);
  check('A pin gate', 'reason', wrongPin.body.error, 'pin_incorrect');

  const noCred = await hit('POST', '/v1/me/verify-controls-pin', strangerTok, { pin: '1357' });
  check('A pin gate', 'a guardian with no PIN set at all -> 403 pin_not_set', noCred.status, 403);
  check('A pin gate', 'reason', noCred.body.error, 'pin_not_set');

  const malformed = await hit('POST', '/v1/me/verify-controls-pin', dadTok, { pin: 1357 });
  check('A pin gate', '400 on a non-string pin (malformed body)', malformed.status, 400);
  check('A pin gate', 'reason', malformed.body.error, 'pin_required');

  const success = await hit('POST', '/v1/me/verify-controls-pin', dadTok, { pin: '1357' });
  check('A pin gate', "DAD's real pin -> 200", success.status, 200);
  check('A pin gate', 'body ok', success.body.ok, 'true');
}

// ===========================================================================
// B · GET — dual-purpose, both roles, and the no-edge/observer denials.
// ===========================================================================
{
  const beforeAnything = await hit('GET', overridesPath(CHILD_A), dadTok);
  check('B get', 'GET before any override exists -> 200', beforeAnything.status, 200);
  check('B get', 'an honest empty list, never fabricated rows',
    beforeAnything.body.overrides.length, 0);

  const noEdge = await hit('GET', overridesPath(CHILD_A), strangerTok);
  check('B get', 'a guardian with NO edge -> 403 no_edge (never reaches the handler)', noEdge.status, 403);
  check('B get', 'reason', noEdge.body.error, 'no_edge');

  // Observer-only guardian: 'settings' is a WRITES action (§17.3), so the
  // read is ALSO denied at the app layer, same as theme_route.test.mjs's
  // own section D2 proves for PUT .../theme.
  const observerGet = await hit('GET', overridesPath(CHILD_A), observerTok);
  check('B get', 'observer-only guardian -> 403 observer_readonly (not just PUT)', observerGet.status, 403);
  check('B get', 'reason', observerGet.body.error, 'observer_readonly');

  const childWrongChild = await hit('GET', overridesPath(CHILD_C), childTok);
  check('B get', "a child token can't reach another child's overrides -> 403 wrong_child",
    childWrongChild.status, 403);
}

// ===========================================================================
// C · PUT — visible / minAgeOverride / reveal / unreveal, and every 400.
// ===========================================================================
{
  const childPut = await hit('PUT', overridePath(CHILD_A, 'game:chess'), childTok, { visible: false });
  check('C put', 'a child session can never write -> 403 guardian_only', childPut.status, 403);

  const emptyBody = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, {});
  check('C put', 'a fully-empty body -> 400 empty_body', emptyBody.status, 400);
  check('C put', 'reason', emptyBody.body.error, 'empty_body');

  const nonObject = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, 'nope');
  check('C put', 'a bare string body -> 400 body_must_be_object', nonObject.status, 400);
  check('C put', 'reason', nonObject.body.error, 'body_must_be_object');

  const badVisible = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { visible: 'no' });
  check('C put', 'a non-boolean visible -> 400 bad_visible', badVisible.status, 400);
  check('C put', 'reason', badVisible.body.error, 'bad_visible');

  const badMinAge = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { minAgeOverride: -1 });
  check('C put', 'a negative minAgeOverride -> 400 bad_minAgeOverride', badMinAge.status, 400);
  check('C put', 'reason', badMinAge.body.error, 'bad_minAgeOverride');

  const badMinAgeType = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { minAgeOverride: '8' });
  check('C put', 'a non-integer minAgeOverride -> 400 bad_minAgeOverride', badMinAgeType.status, 400);

  const bothRevealFlags = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok,
    { reveal: true, unreveal: true });
  check('C put', 'reveal AND unreveal both present -> 400 reveal_unreveal_conflict',
    bothRevealFlags.status, 400);
  check('C put', 'reason', bothRevealFlags.body.error, 'reveal_unreveal_conflict');

  const badReveal = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { reveal: false });
  check('C put', 'reveal present but not true -> 400 bad_reveal', badReveal.status, 400);

  // -------- real writes, and the precedence-relevant fields round-trip ----
  const hideIt = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { visible: false });
  check('C put', 'DAD hides game:chess -> 200', hideIt.status, 200);
  const afterHide = await hit('GET', overridesPath(CHILD_A), dadTok);
  const chessRow = afterHide.body.overrides.find((o) => o.activityKey === 'game:chess');
  check('C put', 'visible:false round-trips through the real route', chessRow?.visible, 'false');
  check('C put', 'minAgeOverride is untouched (still null) by a visible-only PUT',
    chessRow?.minAgeOverride, 'null');

  // A second PUT on the SAME key changes only minAgeOverride — the earlier
  // visible:false must survive untouched (partial-upsert proof).
  const paceIt = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { minAgeOverride: 9 });
  check('C put', 'a second PUT setting only minAgeOverride -> 200', paceIt.status, 200);
  const afterPace = await hit('GET', overridesPath(CHILD_A), dadTok);
  const chessRow2 = afterPace.body.overrides.find((o) => o.activityKey === 'game:chess');
  check('C put', 'minAgeOverride now set', chessRow2?.minAgeOverride, '9');
  check('C put', "the earlier visible:false is UNCHANGED by a PUT that never mentioned visible",
    chessRow2?.visible, 'false');

  const revealIt = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { reveal: true });
  check('C put', 'reveal:true -> 200', revealIt.status, 200);
  const afterReveal = await hit('GET', overridesPath(CHILD_A), dadTok);
  const chessRow3 = afterReveal.body.overrides.find((o) => o.activityKey === 'game:chess');
  check('C put', 'revealedAt is now set (not null)', chessRow3?.revealedAt !== null, 'true');

  const unrevealIt = await hit('PUT', overridePath(CHILD_A, 'game:chess'), dadTok, { unreveal: true });
  check('C put', 'unreveal:true -> 200', unrevealIt.status, 200);
  const afterUnreveal = await hit('GET', overridesPath(CHILD_A), dadTok);
  const chessRow4 = afterUnreveal.body.overrides.find((o) => o.activityKey === 'game:chess');
  check('C put', 'revealedAt is back to null', chessRow4?.revealedAt, 'null');

  const noEdgePut = await hit('PUT', overridePath(CHILD_A, 'game:chess'), strangerTok, { visible: true });
  check('C put', 'a guardian with NO edge -> 403 no_edge', noEdgePut.status, 403);
}

// ===========================================================================
// D · DELETE — clears the row entirely, idempotent on a double-delete.
// ===========================================================================
{
  const del = await hit('DELETE', overridePath(CHILD_A, 'game:chess'), dadTok);
  check('D delete', 'DAD deletes his own override -> 200', del.status, 200);
  const afterDelete = await hit('GET', overridesPath(CHILD_A), dadTok);
  check('D delete', 'the row is really gone',
    afterDelete.body.overrides.some((o) => o.activityKey === 'game:chess'), 'false');

  const again = await hit('DELETE', overridePath(CHILD_A, 'game:chess'), dadTok);
  check('D delete', 'deleting an already-gone override again is idempotent -> 200', again.status, 200);

  const childDelete = await hit('DELETE', overridePath(CHILD_A, 'game:chess'), childTok);
  check('D delete', 'a child session can never delete -> 403 guardian_only', childDelete.status, 403);
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
