/**
 * UNVERIFIED (this is a Node/JS test file, not a Dart one — see this repo's
 * own "I contract" marker discipline, packages/transport/test/transport
 * .test.mjs; that discipline only requires the marker on client .dart
 * files, and this file names it anyway for the same honest reason every
 * other route-contract file in this repo carries: exercised against a
 * hand-written fake `pg.Pool`, never a real device or a real Postgres.
 *
 * server/routes.mjs — route contract tests for the six device-pairing &
 * provisioning routes. docs/superpowers/specs/2026-09-12-device-pairing
 * -provisioning-design.md.
 *
 * Same technique as kiosk_pin_route.test.mjs/child_profile_route.test.mjs:
 * the REAL `Api` + `registerRoutes` wiring, driven through `api.handle()`,
 * against a hand-written fake `pg.Pool` — no real Postgres (that RLS ground
 * truth is packages/db/test/device_pairing.test.mjs's job). Every route
 * here is `identityScopedByHandler`/`noSessionRequired` +
 * `skipOuterSession: true`, so this file's fake pool has to answer the REAL
 * SQL packages/db/src/pool.mjs's createDevicePairingCode()/
 * cancelDevicePairingCode()/redeemDevicePairingCode()/
 * pairedDevicesForChild()/revokePairedDevice()/attemptPinFor()/edgesFor()
 * emit, imported here unmodified — the same "prove the real production code
 * path, not a fake's opinion of it" posture kiosk_pin_route.test.mjs's own
 * header already states.
 *
 * Section G (Automatic First-Run Detection, docs/superpowers/specs/
 * 2026-09-14-automatic-first-run-detection-design.md) extends this beyond
 * this file's own feature: GET /v1/me is registered on the SAME shared
 * `api` instance (registerRoutes(api, pool) registers every route in
 * routes.mjs, not only this feature's six), and this file already owned
 * every fixture that handler needs (DAD's own real PIN from section A,
 * CHILD_A/CHILD_B). `db.withSession`'s own stub and the `children`/
 * `appUsers`/`childProfiles` fake state exist to make that call genuinely
 * work, not merely compile — see those additions' own comments for the
 * fuller account, including a real, confirmed gap this section closes:
 * `hasPin` had zero test coverage anywhere in this repo before it.
 */
import { randomBytes } from 'node:crypto';
import { issueSession, hashPin, readSession } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { isPairedDeviceRevoked } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-09-12T12:00:00Z');

const DAD = 'dad-1';          // live guardian of CHILD_A
const MOM = 'mom-1';          // ALSO a live guardian of CHILD_A (co-guardian)
const STRANGER = 'stranger-1'; // no edge to CHILD_A at all
const CHILD_A = 'child-alpha';
const CHILD_B = 'child-beta'; // DAD has no edge here

// ---- fake "Postgres" state, keyed exactly like the real tables -----------
const credentials = new Map(); // userId -> { pin_hash, failed_attempts, locked_until }
const setCred = (userId, pin) => credentials.set(userId, { pin_hash: hashPin(pin), failed_attempts: 0, locked_until: null });
setCred(DAD, '1357');
setCred(MOM, '2468');

// child.display_name / app_user.display_name — just enough for GET /v1/me's
// real handler (section G below), never modeled anywhere else in this file
// before now. Automatic First-Run Detection (docs/superpowers/specs/
// 2026-09-14-automatic-first-run-detection-design.md).
const children = new Map([[CHILD_A, 'Ivy'], [CHILD_B, 'Eli']]);
const appUsers = new Map([[DAD, 'Dad'], [MOM, 'Mom']]);
// child_profile row EXISTENCE only (child_id -> true) — the real column
// shape (gender/set_at) is irrelevant to hasOnboarded, which only ever
// checks row existence (routes.mjs's own GET /v1/me handler).
const childProfiles = new Set();

// userId -> [{ child_id, role }] -- just enough of guardianship+
// effective_guardianship for the REAL edgesFor()/the paired_device family
// subqueries to answer correctly.
const guardianshipRows = [
  { user_id: DAD, child_id: CHILD_A, role: 'guardian' },
  { user_id: MOM, child_id: CHILD_A, role: 'guardian' },
];
const guardianIdsForChild = (childId) =>
  guardianshipRows.filter((r) => r.child_id === childId).map((r) => r.user_id);

const codes = new Map();   // id -> device_pairing_code row (snake_case fields)
const devices = new Map(); // id -> paired_device row (snake_case fields)
let nextCodeN = 1, nextDeviceN = 1;

function fakeQuery(sql, params = []) {
  if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return [];
  if (/set_config/i.test(sql)) return [];

  // -------------------------------------------------------- edgesFor() ----
  if (/FROM guardianship g/i.test(sql)) {
    const [userId] = params;
    return guardianshipRows.filter((r) => r.user_id === userId).map((r) => ({
      child_id: r.child_id, user_id: r.user_id, role: r.role, scope: {},
      observer_only: false, restricted: false, valid_from: '2020-01-01T00:00:00Z',
      valid_to: null, expires_at: null, closed_at: null, ladder_step: null,
    }));
  }

  // ----------------------------------------------- pin_credential (reused
  // verbatim from kiosk_pin_route.test.mjs's own fake -- same real SQL). ---
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

  // --------------------------------------------- device_pairing_code ------
  if (/SELECT 1 FROM device_pairing_code\s+WHERE numeric_code = \$1/i.test(sql)) {
    const [candidate] = params;
    const clash = [...codes.values()].some((c) =>
      c.numeric_code === candidate && !c.redeemed_at && !c.revoked_at && c.expires_at > new Date());
    return clash ? [{ '?column?': 1 }] : [];
  }
  if (/INSERT INTO device_pairing_code/i.test(sql)) {
    const [role, numericCode, targetId, createdBy] = params;
    const id = `code-${nextCodeN++}`;
    const row = { id, numeric_code: numericCode, role, target_id: targetId, created_by: createdBy,
      created_at: new Date(), expires_at: new Date(Date.now() + 10 * 60 * 1000),
      redeemed_at: null, revoked_at: null, failed_attempts: 0 };
    codes.set(id, row);
    return [{ id: row.id, numeric_code: row.numeric_code, role: row.role,
               target_id: row.target_id, expires_at: row.expires_at.toISOString() }];
  }
  if (/SELECT \* FROM device_pairing_code WHERE id = \$1 FOR UPDATE/i.test(sql)) {
    const [id] = params;
    const row = codes.get(id);
    return row ? [row] : [];
  }
  if (/SELECT \* FROM device_pairing_code WHERE id::text = \$1 OR numeric_code = \$1 FOR UPDATE/i.test(sql)) {
    const [code] = params;
    const row = [...codes.values()].find((c) => c.id === code || c.numeric_code === code);
    return row ? [row] : [];
  }
  if (/UPDATE device_pairing_code SET failed_attempts = failed_attempts \+ 1/i.test(sql)) {
    const [id] = params;
    const row = codes.get(id);
    if (row) row.failed_attempts += 1;
    return [];
  }
  if (/UPDATE device_pairing_code SET redeemed_at = now\(\)/i.test(sql)) {
    const [id] = params;
    const row = codes.get(id);
    if (row) row.redeemed_at = new Date();
    return [];
  }
  if (/UPDATE device_pairing_code SET revoked_at/i.test(sql)) {
    const [id, iso] = params;
    const row = codes.get(id);
    if (row) row.revoked_at = new Date(iso);
    return [];
  }

  // -------------------------------------------------------- paired_device -
  if (/INSERT INTO paired_device/i.test(sql)) {
    const [role, targetId, label, pairedVia] = params;
    const id = `device-${nextDeviceN++}`;
    devices.set(id, { id, role, target_id: targetId, label, paired_via: pairedVia,
      paired_at: new Date(), revoked_at: null, last_seen_at: null });
    return [{ id }];
  }
  if (/SELECT \* FROM paired_device\s+WHERE \(role = 'child'/i.test(sql)) {
    const [childId] = params;
    const coGuardians = new Set(guardianIdsForChild(childId));
    return [...devices.values()].filter((d) =>
      (d.role === 'child' && d.target_id === childId) ||
      (d.role === 'guardian' && coGuardians.has(d.target_id)));
  }
  // isPairedDeviceRevoked()'s own plain-by-id lookup -- distinct SQL text
  // from revokePairedDevice()'s family-scoped one just below (no leading
  // "id," column list), used by the DbPort.isDeviceRevoked() check
  // packages/api/src/api.ts's handle() runs on every deviceId-bearing
  // session.
  if (/^\s*SELECT revoked_at FROM paired_device WHERE id = \$1\s*$/i.test(sql)) {
    const [id] = params;
    const d = devices.get(id);
    return d ? [{ revoked_at: d.revoked_at }] : [];
  }
  if (/SELECT id, revoked_at FROM paired_device/i.test(sql)) {
    const [deviceId, childId] = params;
    const d = devices.get(deviceId);
    if (!d) return [];
    const coGuardians = new Set(guardianIdsForChild(childId));
    const inScope = (d.role === 'child' && d.target_id === childId) ||
      (d.role === 'guardian' && coGuardians.has(d.target_id));
    return inScope ? [{ id: d.id, revoked_at: d.revoked_at }] : [];
  }
  if (/UPDATE paired_device SET revoked_at/i.test(sql)) {
    const [deviceId, iso] = params;
    const d = devices.get(deviceId);
    if (d) d.revoked_at = new Date(iso);
    return [];
  }

  // --------------------------- GET /v1/me — section G below (Automatic
  // First-Run Detection). Three plain SELECTs that routes.mjs's own GET
  // /v1/me handler issues through the OUTER session `q`, not through
  // `pool` directly (unlike pinCredentialFor() above, which the fake
  // `pool` already answered before this file ever tested /v1/me at all).
  if (/^\s*SELECT display_name FROM child WHERE id = \$1\s*$/i.test(sql)) {
    const [childId] = params;
    return children.has(childId) ? [{ display_name: children.get(childId) }] : [];
  }
  if (/^\s*SELECT display_name FROM app_user WHERE id = \$1\s*$/i.test(sql)) {
    const [userId] = params;
    return appUsers.has(userId) ? [{ display_name: appUsers.get(userId) }] : [];
  }
  if (/^\s*SELECT 1 FROM child_profile WHERE child_id = \$1\s*$/i.test(sql)) {
    const [childId] = params;
    return childProfiles.has(childId) ? [{ '?column?': 1 }] : [];
  }

  throw new Error(`fake query: unexpected sql: ${sql}`);
}

const pool = {
  connect: async () => ({
    query: async (sql, params = []) => ({ rows: fakeQuery(sql, params) }),
    release: () => {},
  }),
};

// Fake DbPort for the Api itself -- every route THIS FILE'S OWN device-
// pairing sections exercise is identityScopedByHandler/skipOuterSession, so
// `withSession` was never actually consulted for any of them; GET /v1/me
// (section G below, Automatic First-Run Detection) is the one route
// registered on this SAME shared `api` instance that genuinely needs it —
// `withSession`'s own `q` now routes through the identical `fakeQuery()`
// `pool` above already uses, rather than a bare `async () => []` stub that
// would make `hasOnboarded`/`displayName` silently resolve to nothing no
// matter what fake state exists.
const db = { edgesFor: async () => [], withSession: async (_p, fn) => fn(fakeQuery),
  isDeviceRevoked: (id) => isPairedDeviceRevoked(pool, id) };

const api = new Api(SECRET, db, () => NOW);
registerRoutes(api, pool);

const guardianTok = (userId) => issueSession(SECRET, { userId, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = (childId) => issueSession(SECRET, { userId: null, roleName: 'child', childId, escalated: false }, NOW);

const hit = (method, path, tok, body) => api.handle(
  method, path, tok ? { authorization: `Bearer ${tok}` } : {},
  body === undefined ? '' : JSON.stringify(body),
);

// ===========================================================================
// A · generate — POST .../device-pairing-codes (child-role) and
// POST /v1/me/device-pairing-codes (guardian-role).
// ===========================================================================
let childCodeId, childCodeNumeric;
{
  const noSession = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, null, { pin: '1357' });
  check('A generate', 'no session -> 401', noSession.status, 401);

  const asChild = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, childTok(CHILD_A), { pin: '1357' });
  check('A generate', 'a child session -> 403 child_cannot_pair_devices', asChild.status, 403);
  check('A generate', 'reason', asChild.body.error, 'child_cannot_pair_devices');

  const noEdge = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, guardianTok(STRANGER), { pin: '0000' });
  check('A generate', 'a guardian with no edge to the child -> 403', noEdge.status, 403);
  check('A generate', 'reason', noEdge.body.error, 'not_a_guardian_of_child');

  const wrongPin = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, guardianTok(DAD), { pin: '0000' });
  check('A generate', "DAD's own WRONG pin -> 403 pin_incorrect", wrongPin.status, 403);
  check('A generate', 'reason', wrongPin.body.error, 'pin_incorrect');

  const childRole = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, guardianTok(DAD), { pin: '1357' });
  check('A generate', "DAD's real pin, live edge to CHILD_A -> 201", childRole.status, 201);
  check('A generate', 'a real 6-digit numericCode comes back', /^\d{6}$/.test(childRole.body.numericCode), true);
  check('A generate', 'a real id comes back', typeof childRole.body.id, 'string');
  check('A generate', 'expiresAt comes back', typeof childRole.body.expiresAt === 'string', true);
  childCodeId = childRole.body.id; childCodeNumeric = childRole.body.numericCode;

  const guardianRole = await hit('POST', '/v1/me/device-pairing-codes', guardianTok(MOM), { pin: '2468' });
  check('A generate', "MOM's own device-pairing-codes (guardian-role) -> 201", guardianRole.status, 201);
  check('A generate', 'bound to a real code, distinct from the child-role one',
    guardianRole.body.id !== childCodeId, true);

  const malformed = await hit('POST', '/v1/me/device-pairing-codes', guardianTok(MOM), { pin: 2468 });
  check('A generate', '400 on a non-string pin (malformed body)', malformed.status, 400);
  check('A generate', 'reason', malformed.body.error, 'pin_required');
}

// ===========================================================================
// B · cancel — POST .../device-pairing-codes/:codeId/cancel.
// ===========================================================================
{
  const guardianRole2 = await hit('POST', '/v1/me/device-pairing-codes', guardianTok(DAD), { pin: '1357' });
  const cancelled = await hit('POST', `/v1/device-pairing-codes/${guardianRole2.body.id}/cancel`, guardianTok(DAD));
  check('B cancel', "DAD cancels his own code -> 200", cancelled.status, 200);
  check('B cancel', 'body ok', cancelled.body.ok, 'true');

  const again = await hit('POST', `/v1/device-pairing-codes/${guardianRole2.body.id}/cancel`, guardianTok(DAD));
  check('B cancel', 'cancelling an already-revoked code again is idempotent -> 200', again.status, 200);

  const notFound = await hit('POST', '/v1/device-pairing-codes/no-such-code/cancel', guardianTok(DAD));
  check('B cancel', 'a nonexistent codeId -> 404', notFound.status, 404);
  check('B cancel', 'reason', notFound.body.error, 'not_found');
}

// ===========================================================================
// C · redeem — POST /v1/device-pairing/redeem. NO SESSION.
// ===========================================================================
let redeemedDeviceId;
{
  const malformedNoCode = await hit('POST', '/v1/device-pairing/redeem', null, { role: 'child' });
  check('C redeem', 'missing code -> 400', malformedNoCode.status, 400);
  check('C redeem', 'reason', malformedNoCode.body.error, 'code_required');

  const malformedBadRole = await hit('POST', '/v1/device-pairing/redeem', null, { code: childCodeNumeric, role: 'parent' });
  check('C redeem', 'an invalid role -> 400', malformedBadRole.status, 400);
  check('C redeem', 'reason', malformedBadRole.body.error, 'invalid_role');

  const notFound = await hit('POST', '/v1/device-pairing/redeem', null, { code: '000000', role: 'child' });
  check('C redeem', 'a code matching nothing -> 404', notFound.status, 404);
  check('C redeem', 'reason', notFound.body.error, 'not_found');

  const roleMismatch = await hit('POST', '/v1/device-pairing/redeem', null, { code: childCodeNumeric, role: 'guardian' });
  check('C redeem', 'the right code, wrong role -> 403 role_mismatch', roleMismatch.status, 403);
  check('C redeem', 'reason', roleMismatch.body.error, 'role_mismatch');

  const success = await hit('POST', '/v1/device-pairing/redeem', null, { code: childCodeNumeric, role: 'child' });
  check('C redeem', 'the right code, right role -> 201', success.status, 201);
  check('C redeem', 'a real sessionToken comes back', typeof success.body.sessionToken, 'string');
  check('C redeem', 'a real deviceId comes back', typeof success.body.deviceId, 'string');
  redeemedDeviceId = success.body.deviceId;

  const decoded = readSession(SECRET, success.body.sessionToken, NOW);
  check('C redeem', 'the minted session really carries roleName child', decoded.principal.roleName, 'child');
  check('C redeem', 'the minted session really carries childId = CHILD_A', decoded.principal.childId, CHILD_A);
  check('C redeem', 'the minted session really carries the new deviceId claim',
    decoded.principal.deviceId, redeemedDeviceId);

  const alreadyRedeemed = await hit('POST', '/v1/device-pairing/redeem', null, { code: childCodeNumeric, role: 'child' });
  check('C redeem', 'the same code again -> 409 already_redeemed', alreadyRedeemed.status, 409);
  check('C redeem', 'reason', alreadyRedeemed.body.error, 'already_redeemed');

  // A revoked (cancelled-before-use) code.
  const revokedFixture = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, guardianTok(DAD), { pin: '1357' });
  await hit('POST', `/v1/device-pairing-codes/${revokedFixture.body.id}/cancel`, guardianTok(DAD));
  const revokedAttempt = await hit('POST', '/v1/device-pairing/redeem', null,
    { code: revokedFixture.body.numericCode, role: 'child' });
  check('C redeem', 'a cancelled code -> 409 revoked', revokedAttempt.status, 409);
  check('C redeem', 'reason', revokedAttempt.body.error, 'revoked');

  // An expired code -- backdate expires_at directly on the fixture, same
  // "reach into the fake table" technique auth_credentials-style tests use.
  const expiredFixture = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, guardianTok(DAD), { pin: '1357' });
  codes.get(expiredFixture.body.id).expires_at = new Date(Date.now() - 1000);
  const expiredAttempt = await hit('POST', '/v1/device-pairing/redeem', null,
    { code: expiredFixture.body.numericCode, role: 'child' });
  check('C redeem', 'an expired code -> 410 expired', expiredAttempt.status, 410);
  check('C redeem', 'reason', expiredAttempt.body.error, 'expired');
}

// ===========================================================================
// C2 · numeric lockout after DEVICE_CODE_MAX_ATTEMPTS (5) failed attempts --
// role-mismatch attempts against a real, still-live code.
// ===========================================================================
{
  const fixture = await hit('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, guardianTok(DAD), { pin: '1357' });
  const { numericCode } = fixture.body;
  let lastStatus, lastError;
  for (let i = 0; i < 5; i++) {
    const attempt = await hit('POST', '/v1/device-pairing/redeem', null, { code: numericCode, role: 'guardian' });
    lastStatus = attempt.status; lastError = attempt.body.error;
  }
  check('C2 lockout', 'the 5th consecutive role-mismatch is still role_mismatch, not yet locked',
    `${lastStatus} ${lastError}`, '403 role_mismatch');

  const sixth = await hit('POST', '/v1/device-pairing/redeem', null, { code: numericCode, role: 'child' });
  check('C2 lockout', 'the 6th attempt is LOCKED even with the CORRECT role', sixth.status, 423);
  check('C2 lockout', 'reason', sixth.body.error, 'locked');
}

// ===========================================================================
// D · list — GET .../paired-devices.
// ===========================================================================
{
  const noEdge = await hit('GET', `/v1/children/${CHILD_A}/paired-devices`, guardianTok(STRANGER));
  check('D list', 'a guardian with no edge -> 403', noEdge.status, 403);

  const asChild = await hit('GET', `/v1/children/${CHILD_A}/paired-devices`, childTok(CHILD_A));
  check('D list', 'a child session -> 403 child_cannot_view_paired_devices', asChild.status, 403);

  const list = await hit('GET', `/v1/children/${CHILD_A}/paired-devices`, guardianTok(DAD));
  check('D list', "DAD (live guardian of CHILD_A) -> 200", list.status, 200);
  const ids = list.body.devices.map((d) => d.id);
  check('D list', "the redeemed child device shows up", ids.includes(redeemedDeviceId), true);

  const noEdgeToOtherChild = await hit('GET', `/v1/children/${CHILD_B}/paired-devices`, guardianTok(DAD));
  check('D list', "DAD has no edge to CHILD_B -> 403", noEdgeToOtherChild.status, 403);
}

// ===========================================================================
// E · revoke — POST .../paired-devices/:deviceId/revoke.
// ===========================================================================
{
  const notFound = await hit('POST', `/v1/children/${CHILD_A}/paired-devices/no-such-device/revoke`, guardianTok(DAD));
  check('E revoke', 'a nonexistent deviceId -> 404', notFound.status, 404);

  const revoke = await hit('POST', `/v1/children/${CHILD_A}/paired-devices/${redeemedDeviceId}/revoke`, guardianTok(DAD));
  check('E revoke', "DAD revokes the redeemed device -> 200", revoke.status, 200);
  check('E revoke', 'the revocation is really visible via isPairedDeviceRevoked()',
    await isPairedDeviceRevoked(pool, redeemedDeviceId), true);

  // The device's OWN next authenticated request must now be refused with
  // device_revoked -- packages/api/src/api.ts's handle(), proven end to end
  // through the real route dispatch, not just the pool-level check above.
  const staleSessionAttempt = await hit('GET', '/v1/me', (() => {
    // Mint a fresh session carrying the now-revoked deviceId, the same shape
    // redeem's own real handler mints.
    return issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD_A,
      escalated: false, deviceId: redeemedDeviceId }, NOW);
  })());
  check('E revoke', "a session carrying the revoked deviceId is refused everywhere, "
    + 'not just on this feature\'s own routes -> 401', staleSessionAttempt.status, 401);
  check('E revoke', 'reason is device_revoked, distinct from a generic auth failure',
    staleSessionAttempt.body.error, 'device_revoked');

  const otherGuardianCanStillRevoke = await hit(
    'POST', `/v1/children/${CHILD_A}/paired-devices/${redeemedDeviceId}/revoke`, guardianTok(MOM));
  check('E revoke', "a CO-guardian (MOM, also live on CHILD_A) can revoke it too (idempotent) -> 200",
    otherGuardianCanStillRevoke.status, 200);
}

// ===========================================================================
// F · a session with NO deviceId claim at all (DEV_LOGIN/every pre-existing
// path) is completely unaffected by any of this -- the spec's own "sessions
// from DEV_LOGIN carry no deviceId and are unaffected" line. Reuses this
// file's own already-registered list route rather than /v1/me (this file's
// device-pairing sections deliberately stay scoped to that feature's own
// routes; GET /v1/me gets its own dedicated section, G below, added for
// Automatic First-Run Detection rather than folded in here) -- proves the
// identical point: an ordinary guardian session (guardianTok() below never
// sets deviceId) is never even checked against isPairedDeviceRevoked(), and
// section D's own DAD list call above already succeeded (200) on exactly
// such a session, so this section asserts the same fact a second, more
// explicit way.
// ===========================================================================
{
  const ordinary = await hit('GET', `/v1/children/${CHILD_A}/paired-devices`, guardianTok(MOM));
  check('F unaffected', 'an ordinary session with no deviceId claim is never blocked as '
    + 'device_revoked, regardless of what paired_device rows exist', ordinary.status, 200);
}

// ===========================================================================
// G · GET /v1/me — `hasPin` (guardian) and `hasOnboarded` (child), Automatic
// First-Run Detection (docs/superpowers/specs/2026-09-14-automatic-first-run
// -detection-design.md). This is the file the design spec's own research
// named as `hasPin`'s existing test coverage — direct inspection while
// implementing this spec found that claim did not hold: `hasPin` had NO
// test coverage anywhere in this repo's JS/TS suite before this section
// (confirmed by grep, not assumed), and this file's own `db.withSession`
// stub could not have exercised a real GET /v1/me call at all until the
// fake-state additions above (`children`/`appUsers`/`childProfiles`,
// `db.withSession` routed through `fakeQuery`) — see those additions' own
// comments. Both fields land together here rather than splitting `hasPin`
// into its own separate correction: they are the SAME response, resolved by
// the SAME handler, and every fixture this section needs (DAD's real PIN
// from section A's own `setCred`, CHILD_A/CHILD_B's real display names) was
// already sitting in this file, unused by any GET /v1/me call until now.
// ===========================================================================
{
  const dadMe = await hit('GET', '/v1/me', guardianTok(DAD));
  check('G me', "a guardian with a PIN (DAD, set by section A's own setCred) -> hasPin true",
    dadMe.body.hasPin, true);
  check('G me', "hasOnboarded is really null (never undefined, never the string \"null\") "
    + 'for a guardian caller -- a per-CHILD signal, symmetric with hasPin being null for a '
    + 'child caller', dadMe.body.hasOnboarded === null, true);

  const strangerMe = await hit('GET', '/v1/me', guardianTok(STRANGER));
  check('G me', 'a guardian with NO pin_credential row (STRANGER) -> hasPin false, never '
    + 'null/undefined for a real guardian caller', strangerMe.body.hasPin, false);

  const childAMeBefore = await hit('GET', '/v1/me', childTok(CHILD_A));
  check('G me', 'a child with no child_profile row yet -> hasOnboarded false',
    childAMeBefore.body.hasOnboarded, false);
  check('G me', 'hasPin is really null for a child caller -- unchanged, symmetric behaviour',
    childAMeBefore.body.hasPin === null, true);

  // A real child_profile row (any shape -- hasOnboarded only ever checks
  // EXISTENCE, never the gender value, matching routes.mjs's own comment).
  childProfiles.add(CHILD_A);
  const childAMeAfter = await hit('GET', '/v1/me', childTok(CHILD_A));
  check('G me', 'the SAME child, now with a child_profile row -> hasOnboarded true, '
    + 're-resolved fresh on this fresh GET /v1/me call', childAMeAfter.body.hasOnboarded, true);

  // A DIFFERENT child (CHILD_B), still with no row of her own -- proves this
  // is scoped per-child, not a global flag CHILD_A's own write flipped.
  const childBMe = await hit('GET', '/v1/me', childTok(CHILD_B));
  check('G me', "CHILD_B's own hasOnboarded is unaffected by CHILD_A's row -- per-child, "
    + 'not global', childBMe.body.hasOnboarded, false);
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
