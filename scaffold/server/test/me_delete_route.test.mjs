/**
 * server/routes.mjs — route contract test: POST /v1/me/delete.
 * MASTERFILE §2.10, §2.11, §9.8, P8, §21.7 ("the hardest button anyone
 * builds here"). db/migrations/0011_account_deletion.sql,
 * packages/db/src/pool.ts's deactivateAccount().
 *
 * WHY THIS FILE EXISTS, given packages/db/test/deletion.test.mjs already has
 * 20+ real-Postgres/real-RLS assertions on this exact feature: that suite
 * (rightly) never calls this route at all. It calls deactivateAccount()
 * directly (bypassing server/routes.mjs entirely) to prove the TRANSACTION —
 * what survives, what's removed, RLS — and separately spins up a real HTTP
 * server to prove a DIFFERENT route (dev-login) refuses a deactivated
 * account. Nothing anywhere exercises POST /v1/me/delete's own HANDLER: the
 * `if (!c.principal.userId) return 400` guard, or the
 * already_deactivated -> 409 / account_not_found -> 404 error-code-to-HTTP-
 * status mapping in routes.mjs's own try/catch (lines ~193-204). A bug in
 * that mapping — e.g. a typo turning `e?.code === 'already_deactivated'`
 * into always-false — would make a double-tap on the delete button fall
 * through to the catch-all `throw e` and 500, or worse, silently re-run the
 * (already-idempotent-at-the-DB-level) deactivation attempt and mask the
 * true error code from the client. deletion.test.mjs's own idempotency
 * assertion ("a second call is refused") only proves deactivateAccount()
 * itself throws the right `.code` — never that the ROUTE turns that code
 * into the right response. This file closes exactly that gap, the same way
 * routes.test.mjs already does for GET .../custody-order: the real `Api` +
 * `registerRoutes` wiring, against a hand-written fake `DbPort` and a hand-
 * written fake `pg.Pool` whose query() pattern-matches deactivateAccount()'s
 * own SQL text (packages/db/src/pool.mjs) — no real Postgres, so this runs
 * in the same fast, no-DB JS suite list verify.sh already gives
 * routes.test.mjs, not the separate real-RLS list deletion.test.mjs is in.
 *
 * Four things proven here that were NOT provable anywhere else in this repo:
 *   A. no session -> 401 (the ordinary gate, for completeness)
 *   B. a child principal (no userId of her own — §11) hits the REAL route
 *      and gets 400 no_user_identity, not just deactivateAccount()'s own
 *      internal 'child' guard (which a route bug could dodge by never
 *      calling deactivateAccount() with roleName='child' in the first place —
 *      the route's OWN, independent guard is what's under test here).
 *   C. a successful call returns 200 with the exact response shape the
 *      client (deletion_screen.dart, since v0.49.15's dead-wire fix) reads —
 *      `ok`, `userId`, and every count field — and does so using ONLY
 *      `c.principal.userId`, proving a request body naming a different
 *      target userId cannot widen the operation (routes.mjs's own header
 *      comment claims this; this is what actually proves it, over the
 *      route, not just by reading the source).
 *   D. the already_deactivated (409) and account_not_found (404) branches of
 *      the route's own try/catch, including a REAL double-tap over the real
 *      route (call it twice for the same session) — the literal scenario
 *      the audit finding named.
 *   E. bonus: an unmapped/unexpected thrown error still reaches the catch-
 *      all -> 500, not a false 200 — proving the try/catch's two `if`
 *      branches are exhaustive-as-intended, not accidentally swallowing
 *      every error into a success response.
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

const GOOD_USER    = 'guardian-deleting';       // fresh, active account -> real success path
const ALREADY_GONE = 'guardian-already-gone';   // deactivated_at already set, from the start
const UNKNOWN_USER = 'guardian-does-not-exist'; // no app_user row at all
const CRASH_USER   = 'guardian-db-explodes';    // triggers an unmapped error from the DB layer
const CHILD_ID     = 'child-of-nobody-here';

// In-memory app_user table, exactly the shape deactivateAccount()'s own
// `SELECT id, deactivated_at ... FOR UPDATE` / `UPDATE ... RETURNING id`
// queries need. Deliberately mutable: section D's "double-tap over the real
// route" scenario relies on the FIRST call actually flipping this state, the
// same way a real UPDATE would, rather than a canned always-the-same-answer
// stub that couldn't tell a first call from a second.
const accounts = new Map([
  [GOOD_USER, { deactivatedAt: null }],
  [ALREADY_GONE, { deactivatedAt: '2020-01-01T00:00:00Z' }],
  [CRASH_USER, { deactivatedAt: null }],
  // UNKNOWN_USER intentionally absent.
]);

// Fake pg.Pool — only what packages/db/src/pool.mjs's withSession() /
// deactivateAccount() touch: pool.connect() -> { query, release }. Query
// text matched verbatim against deactivateAccount()'s own SQL (pool.mjs),
// the same "pattern-match the real query strings" approach
// server/test/routes.test.mjs already uses for activeCustodyOrderFor().
const pool = {
  connect: async () => ({
    query: async (sql, params = []) => {
      if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return { rows: [] };
      if (/set_config/i.test(sql)) return { rows: [] };
      if (/SELECT id, deactivated_at FROM app_user WHERE id = \$1 FOR UPDATE/i.test(sql)) {
        const [id] = params;
        if (id === CRASH_USER) throw new Error('simulated unexpected database failure');
        const acct = accounts.get(id);
        return { rows: acct ? [{ id, deactivated_at: acct.deactivatedAt }] : [] };
      }
      if (/DELETE FROM delivery_intent/i.test(sql)) return { rows: [{ id: 'di-1' }, { id: 'di-2' }] };
      if (/DELETE FROM pin_credential/i.test(sql)) return { rows: [{ user_id: params[0] }] };
      if (/DELETE FROM webauthn_credential/i.test(sql)) return { rows: [{ credential_id: 'cred-1' }] };
      if (/DELETE FROM auth_challenge/i.test(sql)) return { rows: [{ challenge: 'chal-1' }] };
      if (/DELETE FROM device_token/i.test(sql))
        return { rows: [{ id: 'dt-1' }, { id: 'dt-2' }, { id: 'dt-3' }] };
      if (/UPDATE app_user SET deactivated_at = now\(\)/i.test(sql)) {
        const [id] = params;
        const acct = accounts.get(id);
        if (acct) acct.deactivatedAt = '2026-08-24T12:00:00Z'; // mutate, mirroring a real UPDATE
        return { rows: acct ? [{ id }] : [] };
      }
      throw new Error(`fake pool query: unexpected sql: ${sql}`);
    },
    release: () => {},
  }),
};

// Fake DbPort — the Api's own outer withSession(). POST /v1/me/delete's
// handler takes only `c` (no `q`), so this MUST never be called by it — a
// `q` that throws if invoked turns "the handler doesn't touch the outer
// caller-scoped session, it opens its own system session via `pool`
// instead" from an assumption into something this file actually checks.
const db = {
  edgesFor: async () => [],
  withSession: async (_principal, fn) => fn(async () => {
    throw new Error('POST /v1/me/delete must not use the outer caller-scoped session');
  }),
};

const api = new Api(SECRET, db, () => NOW);
registerRoutes(api, pool);

const tokFor = (userId, roleName, childId = null) =>
  issueSession(SECRET, { userId, roleName, childId, escalated: false }, NOW);
const goodTok    = tokFor(GOOD_USER, 'guardian');
const goneTok    = tokFor(ALREADY_GONE, 'guardian');
const unknownTok = tokFor(UNKNOWN_USER, 'guardian');
const crashTok   = tokFor(CRASH_USER, 'guardian');
const childTok   = tokFor(null, 'child', CHILD_ID);

const hit = (tok, body) => api.handle(
  'POST', '/v1/me/delete',
  tok ? { authorization: `Bearer ${tok}` } : {},
  body === undefined ? '' : JSON.stringify(body),
);

// ===========================================================================
// A · the ordinary gate
// ===========================================================================
{
  const res = await hit(null);
  check('A auth', 'no session -> 401', res.status, 401);
}

// ===========================================================================
// B · a child principal — the route's OWN guard, not just deactivateAccount()'s
// ===========================================================================
{
  const res = await hit(childTok);
  check('B child identity', "a child session (no userId of her own, §11) -> 400", res.status, 400);
  check('B child identity', 'reason is the real one', res.body.error, 'no_user_identity');
}

// ===========================================================================
// C · the real success path — response shape + body-tampering ignored
// ===========================================================================
{
  // A malicious/buggy client body naming a DIFFERENT userId must be ignored
  // outright — routes.mjs's own header comment claims the target comes ONLY
  // from c.principal.userId, never the body; this is what actually proves it.
  const res = await hit(goodTok, { userId: ALREADY_GONE });
  check('C success', 'a live account -> 200', res.status, 200);
  check('C success', 'ok: true', res.body.ok, 'true');
  check('C success', "userId is the SESSION's user, not the body's",
    res.body.userId, GOOD_USER);
  check('C success', 'cancelledDeliveryIntents passes through accurately',
    res.body.cancelledDeliveryIntents, 2);
  check('C success', 'removedPinCredentials passes through accurately',
    res.body.removedPinCredentials, 1);
  check('C success', 'removedWebauthnCredentials passes through accurately',
    res.body.removedWebauthnCredentials, 1);
  check('C success', 'removedWebauthnChallenges passes through accurately',
    res.body.removedWebauthnChallenges, 1);
  check('C success', 'removedDeviceTokens passes through accurately',
    res.body.removedDeviceTokens, 3);

  // And ALREADY_GONE (the body's claimed target) was untouched by this call —
  // further proof the body was never consulted.
  check('C success', "the body's named account was NOT touched",
    accounts.get(ALREADY_GONE).deactivatedAt, '2020-01-01T00:00:00Z');
}

// ===========================================================================
// D · already_deactivated -> 409 and account_not_found -> 404, over the REAL
// route -- the literal audit question: does a second delete call get refused?
// ===========================================================================
{
  // D1 · a real double-tap: the SAME session, immediately after C's own
  // successful call above, which just flipped GOOD_USER to deactivated.
  const second = await hit(goodTok);
  check('D idempotency', 'a second call over the real route is REFUSED, not silently repeated',
    second.status, 409);
  check('D idempotency', 'reason is the real one', second.body.error, 'already_deactivated');

  // D2 · isolated fixture — deactivated from the very start, order-independent.
  const gone = await hit(goneTok);
  check('D idempotency', 'an account deactivated before this test ever ran -> 409',
    gone.status, 409);
  check('D idempotency', 'reason is the real one', gone.body.error, 'already_deactivated');

  // D3 · no such account at all.
  const unknown = await hit(unknownTok);
  check('D idempotency', 'an unknown userId -> 404, not a silent no-op 200',
    unknown.status, 404);
  check('D idempotency', 'reason is the real one', unknown.body.error, 'account_not_found');
}

// ===========================================================================
// E · an unmapped error is NOT swallowed into a false success
// ===========================================================================
{
  const res = await hit(crashTok);
  check('E unmapped error', "an error with no known .code falls through to the real 500, " +
    'not a false 200', res.status, 500);
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
