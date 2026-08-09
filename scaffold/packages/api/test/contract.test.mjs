/**
 * packages/api — client/server path contract.
 *
 * transport.test.mjs's own "I · CLIENT CONTRACT" section already checks Dart
 * endpoint strings for SHAPE (well-formed, child-scoped paths use :childId,
 * exactly one journal route) and cross-references them loosely against
 * MASTERFILE §7's prose. What it does NOT do is compare a Dart-declared path
 * against the REAL, ACTUALLY-REGISTERED server route table — its own
 * "unspecified" check reduces to `mf.includes(stem.split('/')[0])`, which for
 * every child-scoped path (`stem` starts with '/', so `stem.split('/')[0]`
 * is the empty string, and `String.includes('')` is always true) never
 * actually rejects anything. This suite closes that gap with an exact,
 * unambiguous comparison: every path server/routes.mjs registers via
 * api.register(), plus every raw pre-session path server/index.mjs handles
 * directly (dev-login, the two WebAuthn login routes — see that file's own
 * header for why those can't go through api.register()), must appear
 * word-for-word in client/lib/api_client.dart's declared path constants. A
 * server route with no matching Dart constant is a route the client
 * literally cannot address by name — exactly the silent-drift class this
 * suite exists to catch before it ships.
 *
 * The reverse is NOT required: api_client.dart intentionally declares paths
 * (ribbon, overlap, messages, batches, ping, journal, medications,
 * emergency-card, settings) with no server implementation yet — see that
 * file's own header comment — so this suite does not fail on a Dart
 * constant the server hasn't grown into yet, only on a server route the
 * Dart contract has no name for.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Api } from '../src/api.mjs';
import { registerRoutes } from '../../../server/routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const root = fileURLToPath(new URL('../../../', import.meta.url));

// ---- the REAL, registered server surface ----------------------------------
// A fake DbPort/pool: registerRoutes() only stores `pool` in handler closures
// and Api.register() only validates route SHAPE (A1's own checks) — neither
// runs a query or opens a session at registration time, so a structural
// stand-in is sufficient and no real Postgres is needed for this suite.
const fakeDb = { edgesFor: async () => [], withSession: async (_p, fn) => fn(async () => []) };
const api = new Api(Buffer.from('contract-test-secret'), fakeDb, () => Date.now());
const fakePool = {};
registerRoutes(api, fakePool);

const apiRegisteredPaths = [...new Set(api.routes.map((r) => r.path))];
check('setup', 'registerRoutes() registered at least the pre-existing 3 + new 4 routes',
  apiRegisteredPaths.length >= 7, 'true');

// server/index.mjs's own raw (pre-session) routes — never go through
// api.register(), so they must be found by reading its source directly, the
// same technique packages/transport/test/transport.test.mjs already uses for
// the native-bridge contract sections.
const indexSrc = readFileSync(root + 'server/index.mjs', 'utf8');
const rawRoutePaths = [...indexSrc.matchAll(/req\.url === '(\/v1\/[^']+)'/g)].map((m) => m[1]);
check('setup', 'server/index.mjs declares its raw pre-session routes',
  rawRoutePaths.length >= 3, 'true');

const serverPaths = new Set([...apiRegisteredPaths, ...rawRoutePaths]);

// ---- the DECLARED client contract -----------------------------------------
const dartSrc = readFileSync(root + 'client/lib/api_client.dart', 'utf8');
const dartPaths = new Set([...dartSrc.matchAll(/'(\/v1\/[^']+)'/g)].map((m) => m[1]));
check('setup', 'api_client.dart declares at least one path constant', dartPaths.size > 5, 'true');

// ---- A · every real server route has a name in the Dart contract ----------
{
  const missing = [...serverPaths].filter((p) => !dartPaths.has(p));
  check('A drift', 'every registered/raw server path has a matching Dart constant',
    missing.join(','), '');
}

// ---- B · this pass's specific new routes exist on BOTH sides --------------
{
  const newRoutes = [
    '/v1/children/:childId/kiosk-pin/verify',
    '/v1/me/pin',
    '/v1/auth/webauthn/register/challenge',
    '/v1/auth/webauthn/register/verify',
    '/v1/auth/webauthn/login/challenge',
    '/v1/auth/webauthn/login/verify',
  ];
  for (const p of newRoutes) {
    check('B new routes', `${p} is a real server route`, serverPaths.has(p), 'true');
    check('B new routes', `${p} is declared in api_client.dart`, dartPaths.has(p), 'true');
  }
  // The two WebAuthn LOGIN routes specifically must be raw index.mjs routes,
  // NOT api.register() routes — they establish identity and must run before
  // any session exists (server/index.mjs's own header explains why).
  check('B new routes', 'login/challenge is a RAW route, not an api.register() one',
    rawRoutePaths.includes('/v1/auth/webauthn/login/challenge'), 'true');
  check('B new routes', 'login/verify is a RAW route, not an api.register() one',
    rawRoutePaths.includes('/v1/auth/webauthn/login/verify'), 'true');
  check('B new routes', 'login/challenge is NOT also registered on the Api instance',
    apiRegisteredPaths.includes('/v1/auth/webauthn/login/challenge'), 'false');
  // The register/* and me/pin routes DO require a session, so they must be
  // real api.register() routes, not raw ones.
  check('B new routes', 'register/verify IS an api.register() route (needs a session)',
    apiRegisteredPaths.includes('/v1/auth/webauthn/register/verify'), 'true');
  check('B new routes', 'me/pin IS an api.register() route (needs a session)',
    apiRegisteredPaths.includes('/v1/me/pin'), 'true');
}

// ---- C · A1's own invariant survives the identityScopedByHandler exception -
{
  const kioskRoute = api.routes.find((r) => r.path === '/v1/children/:childId/kiosk-pin/verify');
  check('C A1', 'kiosk-pin/verify declares action:null', kioskRoute?.action, 'null');
  check('C A1', 'kiosk-pin/verify explicitly opts into identityScopedByHandler',
    kioskRoute?.identityScopedByHandler, 'true');
  // The exception is narrow: no OTHER :childId route in this repo may use it
  // silently. now/inbox both declare a real Action, not null.
  const otherChildRoutes = api.routes.filter((r) =>
    r.path.includes(':childId') && r.path !== '/v1/children/:childId/kiosk-pin/verify');
  check('C A1', 'every OTHER :childId route still declares a real (non-null) action',
    otherChildRoutes.every((r) => r.action !== null), 'true');
  // And the underlying registration guard still refuses an undeclared
  // exception — mirrors stack.test.mjs's own A1 test, re-asserted here so a
  // regression in api.ts's guard is caught by this suite too, not only that
  // one.
  let refused = false;
  try {
    api.register({ method: 'GET', path: '/v1/children/:childId/unguarded',
      action: null, handler: async () => ({}) });
  } catch { refused = true; }
  check('C A1', 'a :childId route with action:null and NO identityScopedByHandler still throws',
    refused, 'true');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
