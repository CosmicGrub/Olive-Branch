/**
 * UNVERIFIED (this is a Node/JS test file, not a Dart one — see this repo's own
 * "I contract" marker discipline, packages/transport/test/transport.test.mjs;
 * the marker is only REQUIRED on client .dart files, and this file names it for
 * the same honest reason server/test/device_pairing_route_test.mjs does:
 * exercised against a hand-written fake `pg.Pool`, never a real Postgres —
 * packages/db/test/device_credential.test.mjs is the real-RLS counterpart).
 *
 * Audit G-02 / G-06 / C-03 / G-13 — the real authenticated session:
 *   POST /v1/device-pairing/redeem   now also returns a long-lived deviceCredential
 *   POST /v1/auth/session/refresh    device credential -> fresh 1-hour session
 *   POST /v1/auth/session/sign-out   a guardian's device revokes itself
 *   POST /v1/me/pin                  changing a PIN needs the current PIN
 *
 * Same technique as device_pairing_route_test.mjs: the REAL Api + registerRoutes
 * wiring driven through api.handle(), the REAL pool.mjs SQL, a fake pg.Pool that
 * answers exactly that SQL.
 */
import { randomBytes, createHash } from 'node:crypto';
import { issueSession, hashPin, readSession } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { isPairedDeviceRevoked } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { readFileSync } from 'node:fs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const T0 = Date.parse('2026-11-07T12:00:00Z');
let clock = T0;
const HOUR = 60 * 60 * 1000;

const DAD = 'dad-1';
const MOM = 'mom-1';
const NOPIN = 'nopin-1';   // a guardian who has never set a PIN
const CHILD_A = 'child-alpha';

// ---- fake "Postgres" state ------------------------------------------------
const credentials = new Map();
const setCred = (userId, pin) => credentials.set(userId,
  { pin_hash: hashPin(pin), failed_attempts: 0, locked_until: null });
setCred(DAD, '1357');
setCred(MOM, '2468');
const appUsers = new Map([[DAD, { deactivated_at: null }], [MOM, { deactivated_at: null }],
  [NOPIN, { deactivated_at: null }]]);
const codes = new Map();
const devices = new Map();
let nextDeviceN = 1;
const seedCode = (id, role, targetId) => codes.set(id, { id, numeric_code: String(100000 + codes.size),
  role, target_id: targetId, created_by: DAD, expires_at: new Date(Date.now() + 600000),
  redeemed_at: null, revoked_at: null, failed_attempts: 0 });

const securityEventInserts = [];
function fakeQuery(sql, params = []) {
  if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return [];
  if (/set_config/i.test(sql)) return [];
  // S-B3: redeem now writes a security_event row (same transaction). Recorded
  // here so a test can assert the trail exists; one row per call is enough.
  if (/INSERT INTO security_event/i.test(sql)) {
    securityEventInserts.push({ sql, params });
    return [{ seq: securityEventInserts.length }];
  }

  // pin_credential — same shapes as kiosk_pin_route.test.mjs's fake.
  if (/SELECT pin_hash, failed_attempts, locked_until\s+FROM pin_credential WHERE user_id = \$1/i.test(sql)) {
    const c = credentials.get(params[0]);
    return c ? [{ pin_hash: c.pin_hash, failed_attempts: c.failed_attempts, locked_until: c.locked_until }] : [];
  }
  if (/UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL/i.test(sql) && !/CASE/i.test(sql)) {
    const c = credentials.get(params[0]);
    if (c) { c.failed_attempts = 0; c.locked_until = null; }
    return [];
  }
  if (/UPDATE pin_credential[\s\S]*CASE WHEN failed_attempts/i.test(sql)) {
    const [userId, maxAttempts, lockoutMs] = params;
    const c = credentials.get(userId);
    if (c) {
      if (c.failed_attempts + 1 >= maxAttempts) { c.failed_attempts = 0; c.locked_until = new Date(Date.now() + Number(lockoutMs)); }
      else c.failed_attempts += 1;
    }
    return [];
  }
  if (/SELECT deactivated_at FROM app_user WHERE id = \$1 FOR UPDATE/i.test(sql)) {
    const u = appUsers.get(params[0]);
    return u ? [{ deactivated_at: u.deactivated_at }] : [];
  }
  if (/SELECT deactivated_at FROM app_user WHERE id = \$1\s*$/i.test(sql)) {
    const u = appUsers.get(params[0]);
    return u ? [{ deactivated_at: u.deactivated_at }] : [];
  }
  if (/INSERT INTO pin_credential[\s\S]*ON CONFLICT \(user_id\) DO NOTHING/i.test(sql)) {
    const [userId, pinHash] = params;
    if (credentials.has(userId)) return [];
    credentials.set(userId, { pin_hash: pinHash, failed_attempts: 0, locked_until: null });
    return [{ user_id: userId }];
  }
  if (/INSERT INTO pin_credential[\s\S]*ON CONFLICT \(user_id\) DO UPDATE/i.test(sql)) {
    const [userId, pinHash] = params;
    credentials.set(userId, { pin_hash: pinHash, failed_attempts: 0, locked_until: null });
    return [];
  }

  // device_pairing_code redeem
  if (/SELECT \* FROM device_pairing_code WHERE id::text = \$1 OR numeric_code = \$1 FOR UPDATE/i.test(sql)) {
    const row = [...codes.values()].find((c) => c.id === params[0] || c.numeric_code === params[0]);
    return row ? [row] : [];
  }
  if (/UPDATE device_pairing_code SET redeemed_at = now\(\)/i.test(sql)) {
    const row = codes.get(params[0]); if (row) row.redeemed_at = new Date(); return [];
  }

  // paired_device
  if (/INSERT INTO paired_device/i.test(sql)) {
    const [role, targetId, label, pairedVia, credentialHash] = params;
    const id = `device-${nextDeviceN++}`;
    devices.set(id, { id, role, target_id: targetId, label, paired_via: pairedVia,
      paired_at: new Date(), revoked_at: null, last_seen_at: null, credential_hash: credentialHash });
    return [{ id }];
  }
  if (/SELECT id, role, target_id, revoked_at, credential_hash\s+FROM paired_device WHERE id::text = \$1/i.test(sql)) {
    const d = [...devices.values()].find((x) => x.id === params[0]);
    return d ? [{ id: d.id, role: d.role, target_id: d.target_id, revoked_at: d.revoked_at,
                  credential_hash: d.credential_hash }] : [];
  }
  if (/UPDATE paired_device SET last_seen_at = \$2 WHERE id = \$1/i.test(sql)) {
    const d = devices.get(params[0]); if (d) d.last_seen_at = new Date(params[1]); return [];
  }
  if (/UPDATE paired_device SET revoked_at = COALESCE\(revoked_at, \$2\)\s+WHERE id = \$1 RETURNING id/i.test(sql)) {
    const d = devices.get(params[0]);
    if (!d) return [];
    d.revoked_at = d.revoked_at ?? new Date(params[1]);
    return [{ id: d.id }];
  }
  if (/^\s*SELECT revoked_at FROM paired_device WHERE id = \$1\s*$/i.test(sql)) {
    const d = devices.get(params[0]);
    return d ? [{ revoked_at: d.revoked_at }] : [];
  }
  throw new Error(`fake query: unexpected sql: ${sql}`);
}

const pool = {
  connect: async () => ({
    query: async (sql, params = []) => ({ rows: fakeQuery(sql, params) }),
    release: () => {},
  }),
};
const db = { edgesFor: async () => [], withSession: async (_p, fn) => fn(fakeQuery),
  isDeviceRevoked: (id) => isPairedDeviceRevoked(pool, id) };
const api = new Api(SECRET, db, () => clock);
registerRoutes(api, pool);

const guardianTok = (userId) => issueSession(SECRET,
  { userId, roleName: 'guardian', childId: null, escalated: false }, clock);
const childTok = (childId) => issueSession(SECRET,
  { userId: null, roleName: 'child', childId, escalated: false }, clock);
const hit = (method, path, tok, body) => api.handle(method, path,
  tok ? { authorization: `Bearer ${tok}` } : {}, body === undefined ? '' : JSON.stringify(body));
const redeem = (code, role) => hit('POST', '/v1/device-pairing/redeem', null, { code, role });
const refresh = (deviceId, deviceCredential) =>
  hit('POST', '/v1/auth/session/refresh', null, { deviceId, deviceCredential });

// ===========================================================================
// A · redeem now hands the device a credential, once.
// ===========================================================================
seedCode('code-g1', 'guardian', DAD);
seedCode('code-g2', 'guardian', MOM);
seedCode('code-c1', 'child', CHILD_A);
const dadDev = await redeem('code-g1', 'guardian');
const momDev = await redeem('code-g2', 'guardian');
const kidDev = await redeem('code-c1', 'child');
{
  check('A redeem', 'guardian redeem -> 201', dadDev.status, 201);
  check('A redeem', 'a deviceCredential comes back', typeof dadDev.body.deviceCredential, 'string');
  check('A redeem', 'the credential is 256 bits (43 base64url chars)', dadDev.body.deviceCredential.length, 43);
  check('A redeem', 'two devices never share a credential',
    dadDev.body.deviceCredential !== momDev.body.deviceCredential, true);
  check('A redeem', 'expiresAt = now + 1h (the session TTL the token itself carries)',
    dadDev.body.expiresAt, clock + HOUR);
  const s = readSession(SECRET, dadDev.body.sessionToken, clock);
  check('A redeem', 'the redeem session carries expiresAt as its exp', s.principal.expiresAt, dadDev.body.expiresAt);
  const stored = devices.get(dadDev.body.deviceId);
  check('A redeem', 'only the SHA-256 digest is stored, never the credential',
    stored.credential_hash, createHash('sha256').update(dadDev.body.deviceCredential).digest('hex'));
  check('A redeem', 'the stored value is not the credential itself',
    stored.credential_hash !== dadDev.body.deviceCredential, true);
  check('A redeem', 'a child redeem also gets a credential', typeof kidDev.body.deviceCredential, 'string');

  // Replay of the PAIRING code: no second device, no second credential.
  const replay = await redeem('code-g1', 'guardian');
  check('A redeem', 'replaying a redeemed pairing code -> 409 already_redeemed', replay.status, 409);
  check('A redeem', 'a replay gets no credential', replay.body.deviceCredential, undefined);
  check('A redeem', 'a replay mints no extra device', devices.size, 3);
}

// ===========================================================================
// B · refresh — the happy path and its principal.
// ===========================================================================
{
  clock = T0 + 2 * HOUR;   // the redeem session (1h) is long expired
  const stale = await hit('POST', '/v1/auth/session/sign-out', dadDev.body.sessionToken);
  check('B refresh', 'the 1h redeem session is expired after 2h -> 401', stale.status, 401);
  check('B refresh', 'reason is expired', stale.body.error, 'expired');

  const r = await refresh(dadDev.body.deviceId, dadDev.body.deviceCredential);
  check('B refresh', 'device credential -> 200', r.status, 200);
  check('B refresh', 'expiresAt = now + 1h', r.body.expiresAt, clock + HOUR);
  const s = readSession(SECRET, r.body.sessionToken, clock);
  check('B refresh', 'guardian device -> a guardian session', s.principal.roleName, 'guardian');
  check('B refresh', 'bound to the device row\'s target (DAD)', s.principal.userId, DAD);
  check('B refresh', 'no childId on a guardian session', s.principal.childId, null);
  check('B refresh', 'carries the SAME deviceId claim (so revoke still cuts it off)',
    s.principal.deviceId, dadDev.body.deviceId);
  check('B refresh', 'never escalated', s.principal.escalated, false);
  check('B refresh', 'last_seen_at stamped', devices.get(dadDev.body.deviceId).last_seen_at !== null, true);
  check('B refresh', 'the response names role/targetId for the client', `${r.body.role}/${r.body.targetId}`, `guardian/${DAD}`);

  const k = await refresh(kidDev.body.deviceId, kidDev.body.deviceCredential);
  const ks = readSession(SECRET, k.body.sessionToken, clock);
  check('B refresh', 'child device -> a child session', ks.principal.roleName, 'child');
  check('B refresh', 'bound to the device row\'s child', ks.principal.childId, CHILD_A);
  check('B refresh', 'no userId on a child session', ks.principal.userId, null);

  // The new session really is accepted by the router (and by the device check).
  const ok = await hit('POST', '/v1/auth/session/sign-out', k.body.sessionToken);
  check('B refresh', 'the refreshed child session is authenticated by the router (403 is a ROLE answer, not 401)',
    ok.status, 403);

  // Identity comes from the row, never from the body: extra fields are ignored.
  const forged = await hit('POST', '/v1/auth/session/refresh', null, {
    deviceId: kidDev.body.deviceId, deviceCredential: kidDev.body.deviceCredential,
    role: 'guardian', targetId: DAD, userId: DAD, childId: 'child-beta' });
  const fs = readSession(SECRET, forged.body.sessionToken, clock);
  check('B refresh', 'body-supplied role/targetId/userId are ignored (still the child device\'s own identity)',
    `${fs.principal.roleName}/${fs.principal.childId}/${fs.principal.userId}`, `child/${CHILD_A}/null`);

  // Refresh can be repeated (credential is long-lived, not single-use).
  const again = await refresh(dadDev.body.deviceId, dadDev.body.deviceCredential);
  check('B refresh', 'the credential is long-lived: a second refresh also succeeds', again.status, 200);
}

// ===========================================================================
// C · refresh — every way it must fail.
// ===========================================================================
{
  const bad = (r, status, error, label) => {
    check('C refresh failures', `${label} -> ${status}`, r.status, status);
    check('C refresh failures', `${label}: reason`, r.body.error, error);
    check('C refresh failures', `${label}: no session leaked`, r.body.sessionToken, undefined);
  };
  bad(await hit('POST', '/v1/auth/session/refresh', null, {}), 400, 'device_credential_required', 'empty body');
  bad(await hit('POST', '/v1/auth/session/refresh', null, { deviceId: dadDev.body.deviceId }),
    400, 'device_credential_required', 'missing credential');
  bad(await hit('POST', '/v1/auth/session/refresh', null, { deviceId: 5, deviceCredential: 'x' }),
    400, 'device_credential_required', 'non-string deviceId');
  bad(await refresh(dadDev.body.deviceId, 'not-the-credential'),
    401, 'invalid_device_credential', 'wrong credential');
  bad(await refresh('no-such-device', dadDev.body.deviceCredential),
    401, 'invalid_device_credential', 'unknown device id');
  bad(await refresh(dadDev.body.deviceId, momDev.body.deviceCredential),
    401, 'invalid_device_credential', "WRONG DEVICE (DAD's id with MOM's credential)");
  bad(await refresh(momDev.body.deviceId, dadDev.body.deviceCredential),
    401, 'invalid_device_credential', "WRONG DEVICE (MOM's id with DAD's credential)");
  // A captured SESSION TOKEN is not a credential — it cannot be traded for a new session.
  bad(await refresh(dadDev.body.deviceId, dadDev.body.sessionToken),
    401, 'invalid_device_credential', 'a session token presented as the credential');
  // Unknown and wrong-credential are indistinguishable (no device-id oracle).
  const unknown = await refresh('no-such-device', 'x');
  const wrong = await refresh(dadDev.body.deviceId, 'x');
  check('C refresh failures', 'unknown id and wrong credential give identical bodies',
    JSON.stringify(unknown.body), JSON.stringify(wrong.body));

  // A device paired BEFORE migration 0038 has no stored hash: it can never refresh.
  devices.set('legacy-1', { id: 'legacy-1', role: 'guardian', target_id: DAD, revoked_at: null,
    credential_hash: null, last_seen_at: null });
  bad(await refresh('legacy-1', ''), 400, 'device_credential_required', 'legacy device, empty credential');
  bad(await refresh('legacy-1', 'null'), 401, 'invalid_device_credential', 'legacy device (NULL hash) cannot refresh');
}

// ===========================================================================
// D · revocation, sign-out, deactivation.
// ===========================================================================
{
  // MOM's device signs itself out: needs a live session, revokes exactly that device.
  const momSession = (await refresh(momDev.body.deviceId, momDev.body.deviceCredential)).body.sessionToken;
  const out = await hit('POST', '/v1/auth/session/sign-out', momSession);
  check('D revoke', 'sign-out -> 200', out.status, 200);
  check('D revoke', 'revoked: true', out.body.revoked, true);
  check('D revoke', 'the device row is revoked server-side', devices.get(momDev.body.deviceId).revoked_at !== null, true);
  const revokedAt = devices.get(momDev.body.deviceId).revoked_at;

  const afterRevoke = await hit('POST', '/v1/auth/session/sign-out', momSession);
  check('D revoke', 'the SAME session is cut off on its next request -> 401', afterRevoke.status, 401);
  check('D revoke', 'reason device_revoked', afterRevoke.body.error, 'device_revoked');

  const r = await refresh(momDev.body.deviceId, momDev.body.deviceCredential);
  check('D revoke', 'a revoked device cannot refresh -> 401', r.status, 401);
  check('D revoke', 'reason device_revoked (credential was proved, device is cut off)', r.body.error, 'device_revoked');
  check('D revoke', 'no session leaked', r.body.sessionToken, undefined);
  check('D revoke', 'refresh never clears revoked_at', devices.get(momDev.body.deviceId).revoked_at === revokedAt, true);

  // Sign-out only ever revokes the caller's OWN device, never another guardian's.
  check('D revoke', "DAD's device is untouched by MOM's sign-out", devices.get(dadDev.body.deviceId).revoked_at, null);
  const dadStill = await refresh(dadDev.body.deviceId, dadDev.body.deviceCredential);
  check('D revoke', "DAD's device still refreshes", dadStill.status, 200);

  // Sign-out with a session that has no device (dev-login / WebAuthn): nothing to revoke.
  const noDev = await hit('POST', '/v1/auth/session/sign-out', guardianTok(DAD));
  check('D revoke', 'a deviceless guardian session -> 200 revoked:false', `${noDev.status}/${noDev.body.revoked}`, '200/false');
  check('D revoke', 'sign-out with no session -> 401', (await hit('POST', '/v1/auth/session/sign-out')).status, 401);
  const kid = await hit('POST', '/v1/auth/session/sign-out', childTok(CHILD_A));
  check('D revoke', 'a CHILD session cannot sign the kiosk out -> 403', kid.status, 403);
  check('D revoke', 'reason', kid.body.error, 'guardian_session_required');

  // A guardian revoking the device from elsewhere cuts a live session off too.
  const kidSession = (await refresh(kidDev.body.deviceId, kidDev.body.deviceCredential)).body.sessionToken;
  devices.get(kidDev.body.deviceId).revoked_at = new Date(clock);
  const kidCut = await hit('POST', '/v1/auth/session/sign-out', kidSession);
  check('D revoke', 'a guardian-revoked child device\'s live session -> 401 device_revoked',
    `${kidCut.status}/${kidCut.body.error}`, '401/device_revoked');

  // Deactivated guardian (MASTERFILE 2.10): the device must stop minting sessions.
  seedCode('code-g3', 'guardian', MOM);
  appUsers.set('gone-1', { deactivated_at: null });
  seedCode('code-g4', 'guardian', 'gone-1');
  const goneDev = await redeem('code-g4', 'guardian');
  appUsers.get('gone-1').deactivated_at = new Date(clock);
  const gone = await refresh(goneDev.body.deviceId, goneDev.body.deviceCredential);
  check('D revoke', 'a deactivated guardian\'s device -> 403 account_deactivated',
    `${gone.status}/${gone.body.error}`, '403/account_deactivated');
}

// ===========================================================================
// E · POST /v1/me/pin — changing a PIN needs the current PIN (audit G-13).
// ===========================================================================
{
  const noPinTok = guardianTok(NOPIN);
  const first = await hit('POST', '/v1/me/pin', noPinTok, { pin: '4821' });
  check('E pin', 'no PIN yet: the FIRST PIN needs no proof -> 200', first.status, 200);
  check('E pin', 'the first PIN is stored', credentials.has(NOPIN), true);

  const bareChange = await hit('POST', '/v1/me/pin', noPinTok, { pin: '9999' });
  check('E pin', 'a PIN now exists: setting another with no currentPin -> 403', bareChange.status, 403);
  check('E pin', 'reason current_pin_required', bareChange.body.error, 'current_pin_required');

  const wrong = await hit('POST', '/v1/me/pin', noPinTok, { pin: '9999', currentPin: '0000' });
  check('E pin', 'wrong currentPin -> 403 pin_incorrect', `${wrong.status}/${wrong.body.error}`, '403/pin_incorrect');

  const stillOld = await hit('POST', '/v1/me/pin', noPinTok, { pin: '5555', currentPin: '4821' });
  check('E pin', 'correct currentPin -> 200', stillOld.status, 200);
  const nowNew = await hit('POST', '/v1/me/pin', noPinTok, { pin: '6666', currentPin: '5555' });
  check('E pin', 'the PIN really changed: the NEW pin is now the proof', nowNew.status, 200);
  const oldDead = await hit('POST', '/v1/me/pin', noPinTok, { pin: '7777', currentPin: '4821' });
  check('E pin', 'the OLD pin no longer works as proof', oldDead.status, 403);

  const nonString = await hit('POST', '/v1/me/pin', noPinTok, { pin: '7777', currentPin: 6666 });
  check('E pin', 'non-string currentPin -> 403 current_pin_required', `${nonString.status}/${nonString.body.error}`, '403/current_pin_required');

  const badFormat = await hit('POST', '/v1/me/pin', guardianTok(DAD), { pin: 'abcd', currentPin: '1357' });
  check('E pin', 'malformed new PIN is still a 400 before any proof', `${badFormat.status}/${badFormat.body.error}`, '400/invalid_pin_format');
  const noPinField = await hit('POST', '/v1/me/pin', guardianTok(DAD), { currentPin: '1357' });
  check('E pin', 'missing pin -> 400 pin_required', `${noPinField.status}/${noPinField.body.error}`, '400/pin_required');

  const child = await hit('POST', '/v1/me/pin', childTok(CHILD_A), { pin: '1234' });
  check('E pin', 'a child session -> 403 guardian_session_required', `${child.status}/${child.body.error}`, '403/guardian_session_required');
  check('E pin', 'no session -> 401', (await hit('POST', '/v1/me/pin', null, { pin: '1234' })).status, 401);

  // The proof shares the 5-attempt lockout every other PIN check uses: a thief with an
  // unlocked phone cannot guess the current PIN by hammering this route.
  const dadTok = guardianTok(DAD);
  let last;
  for (let i = 0; i < 5; i++) last = await hit('POST', '/v1/me/pin', dadTok, { pin: '8888', currentPin: '0001' });
  const locked = await hit('POST', '/v1/me/pin', dadTok, { pin: '8888', currentPin: '1357' });
  check('E pin', 'five wrong proofs lock the account: even the RIGHT PIN is then refused -> 403 pin_locked',
    `${locked.status}/${locked.body.error}`, '403/pin_locked');
  check('E pin', "DAD's real PIN was NOT replaced by the guesses", credentials.get(DAD).pin_hash !== undefined &&
    (await import('../../packages/auth/src/auth.mjs')).verifyPin('1357', credentials.get(DAD).pin_hash), true);

  // Concurrent first-PIN race: only the insert-if-absent winner proceeds.
  const racer = 'racer-1';
  appUsers.set(racer, { deactivated_at: null });
  const [r1, r2] = await Promise.all([
    hit('POST', '/v1/me/pin', guardianTok(racer), { pin: '1111' }),
    hit('POST', '/v1/me/pin', guardianTok(racer), { pin: '2222' }),
  ]);
  const statuses = [r1.status, r2.status].sort().join(',');
  check('E pin', 'two racing first-PIN calls: at most one wins (200,200 would mean an overwrite)',
    statuses === '200,200', false);
}

// ===========================================================================
// F · dev-login stays fenced (index.mjs source-level guard — the file starts
// a server on import, so it cannot be imported here).
// ===========================================================================
{
  const idx = readFileSync(new URL('../index.mjs', import.meta.url), 'utf8');
  check('F dev-login', 'dev-login still 404s unless DEV_LOGIN=1', /if \(!DEV_LOGIN\) return \{ status: 404/.test(idx), true);
  check('F dev-login', 'DEV_LOGIN=1 under NODE_ENV=production refuses to boot',
    /DEV_LOGIN && process\.env\.NODE_ENV === 'production'[\s\S]{0,200}process\.exit\(2\)/.test(idx), true);
  const prod = readFileSync(new URL('../../docker-compose.prod.yml', import.meta.url), 'utf8');
  check('F dev-login', 'prod compose pins DEV_LOGIN to the literal "0"', /DEV_LOGIN: "0"/.test(prod), true);
  check('F dev-login', 'prod compose sets NODE_ENV=production', /NODE_ENV: production/.test(prod), true);
}

for (const r of rows) if (!r.ok) console.log(`FAIL [${r.g}] ${r.n}: got ${r.a}, want ${r.e}`);
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
