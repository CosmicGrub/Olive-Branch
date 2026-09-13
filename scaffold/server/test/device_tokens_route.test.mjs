/**
 * server/routes.mjs — POST /v1/me/device-tokens and DELETE /v1/me/device-tokens,
 * real route CONTRACT test. MASTERFILE §8.11.4, §11.
 *
 * A recent audit (Tier-3) flagged thin coverage for the device-tokens
 * routes. Reading what already exists first: packages/db/test/
 * device_token.test.mjs is a genuinely thorough suite AGAINST A REAL
 * POSTGRES for packages/db/src/pool.ts's registerDeviceToken()/
 * unregisterDeviceToken() themselves — RLS-enforced cross-owner isolation
 * (section A), real upsert/dedupe/COALESCE-channel behaviour (sections B/F),
 * the device_token_has_exactly_one_owner and platform CHECK constraints and
 * the token unique index (section D), and the CHANGELOG v0.49.3 SEC-01 fix
 * — a deactivated guardian refused a NEW registration (section E). None of
 * that is re-proven here; duplicating it against a hand-written fake would
 * be *weaker* evidence than the real-Postgres/real-RLS suite that already
 * exists, not stronger.
 *
 * What genuinely had ZERO coverage anywhere (grep for "v1/me/device-tokens"
 * across every .mjs test in this repo before this file existed — nothing
 * matched): server/routes.mjs's OWN handler code for these two routes —
 * the DEVICE_PLATFORMS / DEVICE_CHANNELS request-body validation (the 400s,
 * with their specific reason strings), the channel-omitted-vs-channel-
 * invalid distinction the route's own comment calls out, the success
 * response shapes, and — the one piece that matters most — whether the
 * route's `catch` block actually maps pool.ts's thrown `account_deactivated`
 * error to a 403 the way CHANGELOG v0.49.3 says it does, and, just as
 * importantly, that it does NOT swallow any OTHER thrown error into that
 * same 403 (routes.mjs's own `if (e?.code === 'account_deactivated') ...;
 * throw e;` — the `throw e` half was never exercised by anything).
 *
 * Mirrors packages/api/test/availability_contract.test.mjs's own pattern
 * exactly: the REAL `registerRoutes()` from server/routes.mjs through a REAL
 * `Api` instance, with one layer faked — a minimal `pg.Pool`-shaped object
 * (`.connect()` -> `{query, release}`) that pool.ts's real registerDeviceToken()/
 * unregisterDeviceToken() run their real SQL text against. No real Postgres,
 * so this suite runs in the ordinary JS-suite loop, not the DATABASE_URL-gated
 * one device_token.test.mjs needs.
 */
import { randomBytes } from 'node:crypto';
import { Api } from '../../packages/api/src/api.mjs';
import { dbPort } from '../../packages/db/src/pool.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { registerRoutes } from '../routes.mjs';
import { CHANNELS } from '../../packages/devices/src/devices.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => {
  const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) });
};

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-08-11T18:00:00Z');

const DAD = 'guardian-dad-device-1111';
const IVY = 'child-ivy-device-2222';

// A DB error whose code is deliberately NOT 'account_deactivated' — proves
// routes.mjs's catch block re-throws anything else instead of misreporting
// it as a 403. A real, distinct SQLSTATE-shaped code, not a fabricated one.
const UNRELATED_DB_ERROR_TOKEN = 'tok-triggers-unrelated-db-error';

/**
 * A minimal fake pg.Pool. Every query pool.ts's withSession()/
 * withSystemSession()/registerDeviceToken()/unregisterDeviceToken() issues
 * for these two routes is routed through here; anything unrecognised throws
 * rather than silently returning zero rows, so a real wiring mistake fails
 * loud instead of masquerading as an empty result (same discipline
 * availability_contract.test.mjs's own fake already established).
 *
 * `deactivated` stands in for `app_user.deactivated_at` — registerDeviceToken()'s
 * own SELECT reads it before the upsert, exactly as it would against a real
 * app_user row.
 */
function makeFakePool() {
  const store = new Map();      // token -> row
  const deactivated = new Set(); // userIds
  const writes = [];             // { kind: 'INSERT'|'DELETE', params }
  const reads = [];              // kinds of SELECT issued, for "was this even queried" checks
  let nextId = 1;

  const query = async (sql, params = []) => {
    const s = sql.trim();
    if (s === 'BEGIN' || s === 'COMMIT' || s.startsWith('ROLLBACK')) return { rows: [] };
    if (s.includes('set_config')) return { rows: [] };

    // registerDeviceToken()'s deactivated_at gate (SEC-01, CHANGELOG v0.49.3).
    if (s.includes('SELECT deactivated_at FROM app_user')) {
      reads.push('deactivated_check');
      const [userId] = params;
      return { rows: [{ deactivated_at: deactivated.has(userId) ? '2026-01-01T00:00:00Z' : null }] };
    }

    // registerDeviceToken()'s real UPSERT — verbatim query shape from pool.ts.
    if (s.startsWith('INSERT INTO device_token')) {
      const [ownerUserId, ownerChildId, platform, token, channel] = params;
      if (token === UNRELATED_DB_ERROR_TOKEN) {
        // Simulates a real, unrelated Postgres failure (NOT the deactivation
        // gate) — routes.mjs must not mistake this for account_deactivated.
        throw Object.assign(new Error('simulated_connection_reset'), { code: '08006' });
      }
      writes.push({ kind: 'INSERT', params });
      const existing = store.get(token);
      const row = existing
        ? { ...existing, owner_user_id: ownerUserId, owner_child_id: ownerChildId,
            platform, channel: channel ?? existing.channel }
        : { id: `fake-device-${nextId++}`, owner_user_id: ownerUserId,
            owner_child_id: ownerChildId, platform, token, channel: channel ?? null };
      store.set(token, row);
      return { rows: [{ id: row.id }] };
    }

    // unregisterDeviceToken()'s real DELETE — verbatim query shape from pool.ts.
    if (s.startsWith('DELETE FROM device_token WHERE token = $1')) {
      const [token] = params;
      const existing = store.get(token);
      if (!existing) return { rows: [] };
      store.delete(token);
      return { rows: [{ id: existing.id }] };
    }

    throw new Error(`fake pool: unrecognised query: ${s}`);
  };

  return {
    pool: { connect: async () => ({ query, release: () => {} }) },
    store, deactivated, writes, reads,
  };
}

const post = (api, tok, body) => api.handle(
  'POST', '/v1/me/device-tokens', tok ? { authorization: `Bearer ${tok}` } : {},
  body === undefined ? '' : JSON.stringify(body),
);
const del = (api, tok, body) => api.handle(
  'DELETE', '/v1/me/device-tokens', tok ? { authorization: `Bearer ${tok}` } : {},
  body === undefined ? '' : JSON.stringify(body),
);

// ===========================================================================
// A · POST validation — every 400, with its specific reason, before the
// handler ever calls registerDeviceToken(). Table-driven so every bad-input
// shape server/routes.mjs actually checks for gets one real assertion.
// ===========================================================================
{
  const { pool, writes } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);
  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);

  const cases = [
    { name: 'missing platform', body: { token: 'tok-a1' }, reason: 'platform_must_be_android_or_ios' },
    { name: 'unrecognised platform string', body: { platform: 'windows_phone', token: 'tok-a2' }, reason: 'platform_must_be_android_or_ios' },
    { name: 'platform is a number, not a string', body: { platform: 42, token: 'tok-a3' }, reason: 'platform_must_be_android_or_ios' },
    { name: 'missing token', body: { platform: 'ios' }, reason: 'token_required' },
    { name: 'empty-string token', body: { platform: 'ios', token: '' }, reason: 'token_required' },
    { name: 'token is a number, not a string', body: { platform: 'ios', token: 12345 }, reason: 'token_required' },
    { name: 'channel present but unrecognised', body: { platform: 'ios', token: 'tok-a7', channel: 'bogus_channel' }, reason: 'channel_not_recognized' },
    { name: 'channel is a number, not a string', body: { platform: 'ios', token: 'tok-a8', channel: 7 }, reason: 'channel_not_recognized' },
  ];
  for (const c of cases) {
    const res = await post(api, dadTok, c.body);
    check('A validate', `${c.name} -> 400`, res.status, 400);
    check('A validate', `${c.name} -> reason ${c.reason}`, res.body.error, c.reason);
  }
  check('A validate', 'none of the 8 rejected requests reached registerDeviceToken at all', writes.length, 0);
}

// ===========================================================================
// B · channel is genuinely OPTIONAL — omitted entirely (undefined) and
// explicit null are BOTH valid, distinct from a present-but-invalid value
// (section A above). routes.mjs's own comment: omission means "this client
// doesn't know its real channel yet" and must never be treated as an error.
// ===========================================================================
{
  const { pool, writes } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);
  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);

  const omitted = await post(api, dadTok, { platform: 'ios', token: 'tok-b-omitted' });
  check('B optional channel', 'channel omitted entirely -> 200, not 400', omitted.status, 200);
  check('B optional channel', 'the upsert receives NULL for channel, never a guess',
    writes[0]?.params[4], 'null');

  const explicitNull = await post(api, dadTok, { platform: 'ios', token: 'tok-b-null', channel: null });
  check('B optional channel', 'channel explicitly null -> 200, not 400', explicitNull.status, 200);
  check('B optional channel', 'null channel also reaches the upsert as NULL',
    writes[1]?.params[4], 'null');

  // Every real §8.11.4 channel value is accepted — derived from devices.ts's
  // own CHANNELS (the route validates against this list, not a second
  // hand-typed copy — see routes.mjs's own comment on why).
  for (const c of CHANNELS) {
    const res = await post(api, dadTok, { platform: 'android', token: `tok-b-${c.channel}`, channel: c.channel });
    check('B optional channel', `a real channel value (${c.channel}) is accepted`, res.status, 200);
  }
}

// ===========================================================================
// C · POST success path — response shape, and the write actually carries
// the CALLER's own identity, never anything client-supplied.
// ===========================================================================
{
  const { pool, writes } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);
  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const ivyTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: IVY, escalated: false }, NOW);

  const res = await post(api, dadTok, { platform: 'ios', token: 'tok-c-dad', channel: 'ios' });
  check('C success', 'a valid guardian registration -> 200', res.status, 200);
  check('C success', 'response carries a real id', typeof res.body.id === 'string' && res.body.id.length > 0, 'true');
  check('C success', 'the write is owned by the CALLING guardian', writes[0]?.params[0], DAD);
  check('C success', 'owner_child_id is null for a guardian-owned row', writes[0]?.params[1], 'null');
  check('C success', 'platform/token/channel round-trip in the write, in the documented param order',
    writes[0]?.params.slice(2).join(','), 'ios,tok-c-dad,ios');

  // §11's own header on this route: identity-only, no A1/A3 child-scope
  // action — a CHILD principal must be able to register her own device too.
  const childRes = await post(api, ivyTok, { platform: 'android', token: 'tok-c-ivy' });
  check('C success', "a child principal registering her OWN device -> 200", childRes.status, 200);
  check('C success', 'the write is owned by owner_child_id, not owner_user_id', writes[1]?.params[1], IVY);
  check('C success', 'owner_user_id is null for a child-owned row', writes[1]?.params[0], 'null');
}

// ===========================================================================
// D · CHANGELOG v0.49.3 (SEC-01) — the specific gap the audit named:
// registerDeviceToken() refuses a deactivated guardian/coordinator trying to
// register a NEW device, and routes.mjs must map that thrown error to a real
// 403, not a 500 or a silent 200. Nothing anywhere previously drove this
// through the actual HTTP route — device_token.test.mjs's own section E
// calls registerDeviceToken() directly and never touches routes.mjs's catch
// block at all.
// ===========================================================================
{
  const { pool, writes, deactivated } = makeFakePool();
  deactivated.add(DAD);
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);
  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const ivyTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: IVY, escalated: false }, NOW);

  const res = await post(api, dadTok, { platform: 'ios', token: 'tok-d-refused' });
  check('D deactivated (SEC-01)', 'a deactivated guardian is refused -> 403, not 500 or 200', res.status, 403);
  check('D deactivated (SEC-01)', 'the real error code surfaces, matching server/index.mjs\'s devLogin gate',
    res.body.error, 'account_deactivated');
  check('D deactivated (SEC-01)', 'no row was written for the refused attempt', writes.length, 0);

  // The gate is adult-only (registerDeviceToken()'s own documented reasoning:
  // children have no deactivated_at concept) — a child registering her own
  // device is completely unaffected by DAD's deactivated state.
  const childRes = await post(api, ivyTok, { platform: 'android', token: 'tok-d-child-unaffected' });
  check('D deactivated (SEC-01)', "a child's own registration is unaffected by an unrelated guardian's deactivation",
    childRes.status, 200);
}

// ===========================================================================
// E · the deactivation check is NARROW — routes.mjs's own
// `if (e?.code === 'account_deactivated') { 403 } throw e;` must re-throw
// any OTHER error rather than mapping it to the same 403. Nothing previously
// exercised the `throw e` half of that branch at all.
// ===========================================================================
{
  const { pool } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);
  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);

  const res = await post(api, dadTok, { platform: 'ios', token: UNRELATED_DB_ERROR_TOKEN });
  check('E error mapping', 'an unrelated DB failure is NOT reported as account_deactivated', res.status === 403, 'false');
  check('E error mapping', 'it surfaces as a real 500 via Api.handle\'s own catch-all', res.status, 500);
  check('E error mapping', 'the 500 body does not fabricate an account_deactivated reason',
    res.body.error === 'account_deactivated', 'false');
}

// ===========================================================================
// F · DELETE /v1/me/device-tokens — validation, and the honest
// true/false shape (never an error either way: an unmatched token is a
// successful no-op, per unregisterDeviceToken()'s own documented RLS
// reasoning — "silently, safely, not an error").
// ===========================================================================
{
  const { pool } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);
  const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);

  const missing = await del(api, dadTok, {});
  check('F delete validate', 'missing token -> 400', missing.status, 400);
  check('F delete validate', 'reason is specific', missing.body.error, 'token_required');

  const empty = await del(api, dadTok, { token: '' });
  check('F delete validate', 'empty-string token -> 400', empty.status, 400);

  const notString = await del(api, dadTok, { token: 999 });
  check('F delete validate', 'non-string token -> 400', notString.status, 400);

  // Register one first (through the route, so this is the same live row a
  // real client would have), then unregister it -> deleted:true.
  await post(api, dadTok, { platform: 'ios', token: 'tok-f-real' });
  const hit = await del(api, dadTok, { token: 'tok-f-real' });
  check('F delete success', 'unregistering a real, existing token -> 200', hit.status, 200);
  check('F delete success', 'deleted:true for a real match', hit.body.deleted, 'true');

  const again = await del(api, dadTok, { token: 'tok-f-real' });
  check('F delete success', 'unregistering it a second time -> still 200, not an error', again.status, 200);
  check('F delete success', 'deleted:false — already gone, an honest no-op', again.body.deleted, 'false');

  const neverExisted = await del(api, dadTok, { token: 'tok-f-never-registered' });
  check('F delete success', 'a token that never existed at all -> 200, not an error', neverExisted.status, 200);
  check('F delete success', 'deleted:false for a token nobody ever registered', neverExisted.body.deleted, 'false');
}

// ===========================================================================
// G · the ordinary outer gate — no session at all, for both verbs. Cheap,
// but genuinely unproven before this file: nothing previously drove ANY
// request through these two routes, authenticated or not.
// ===========================================================================
{
  const { pool } = makeFakePool();
  const api = new Api(SECRET, dbPort(pool), () => NOW);
  registerRoutes(api, pool);

  const p = await post(api, null, { platform: 'ios', token: 'tok-g' });
  check('G no session', 'POST with no session -> 401', p.status, 401);
  const d = await del(api, null, { token: 'tok-g' });
  check('G no session', 'DELETE with no session -> 401', d.status, 401);
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
