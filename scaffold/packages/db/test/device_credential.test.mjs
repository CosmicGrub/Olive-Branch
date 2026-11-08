/**
 * packages/db — the paired-device long-lived credential and session refresh:
 * real Postgres, real RLS. Audit G-02 / G-06 / C-03 / G-13,
 * db/migrations/0037_paired_device_credential.sql, packages/db/src/pool.ts's
 * redeemDevicePairingCode() / refreshPairedDeviceSession() /
 * revokeOwnPairedDevice() / setPinCredential({onlyIfAbsent}).
 *
 * Requires a real Postgres with 0037 applied; DATABASE_URL MUST be a
 * NOSUPERUSER NOBYPASSRLS role (db/DEPLOYMENT.md's app_owner), exactly like
 * device_pairing.test.mjs, which this suite mirrors.
 *
 *   A. the credential is stored as a SHA-256 digest only; redeem returns it once.
 *   B. refresh against the real row: success, wrong credential, wrong device,
 *      unknown id, garbage (non-uuid) id, NULL-hash legacy row.
 *   C. revoked -> device_revoked, and revoke never un-revokes.
 *   D. principal / RLS cases: the digest never reaches any other principal
 *      (guardian of the same family, stranger, child), the paired-devices list
 *      does not return it, and sign-out (revokeOwnPairedDevice) touches exactly
 *      one row.
 *   E. deactivated guardian's device cannot refresh.
 *   F. setPinCredential({onlyIfAbsent}) is a real atomic insert-if-absent
 *      (concurrent callers: exactly one wins).
 *   G. THE REAL HTTP ROUTES through the real Api + registerRoutes against this
 *      Postgres: redeem -> refresh -> sign-out -> refresh refused, and PIN
 *      change needing the current PIN.
 */
import pg from 'pg';
import { randomUUID, createHash } from 'node:crypto';
import { createPool, createDevicePairingCode, redeemDevicePairingCode,
  refreshPairedDeviceSession, revokeOwnPairedDevice, revokePairedDevice,
  pairedDevicesForChild, setPinCredential, withSession, dbPort,
} from '../src/pool.mjs';
import { hashPin, readSession, issueSession } from '../../auth/src/auth.mjs';
import { Api } from '../../api/src/api.mjs';
import { registerRoutes } from '../../../server/routes.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CHILD_A = randomUUID();
const GUARDIAN_A = randomUUID();
const GUARDIAN_B = randomUUID();     // co-guardian of CHILD_A
const GUARDIAN_C = randomUUID();     // a stranger
const CHILD_C = randomUUID();
const GONE = randomUUID();           // a guardian who will be deactivated

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Guardian A','America/Chicago'), ($2,'Guardian B','America/Chicago'),
     ($3,'Guardian C (stranger)','America/New_York'), ($4,'Gone','America/Chicago')`,
  [GUARDIAN_A, GUARDIAN_B, GUARDIAN_C, GONE]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Wren','2017-06-11','America/Chicago'), ($2,'Other','2018-01-01','America/New_York')`,
  [CHILD_A, CHILD_C]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $5, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, GUARDIAN_A, GUARDIAN_B, CHILD_C, GUARDIAN_C]);
await admin.query('COMMIT');

const pairDevice = async (role, targetId, creator) => {
  const code = await createDevicePairingCode(pool, role, targetId, creator);
  const r = await redeemDevicePairingCode(pool, code.numericCode, role, new Date());
  if (!r.ok) throw new Error(`pairDevice failed: ${r.reason}`);
  return r;
};

// ===========================================================================
// A · the credential is returned once and stored as a digest only.
// ===========================================================================
const kid = await pairDevice('child', CHILD_A, GUARDIAN_A);
const dadDev = await pairDevice('guardian', GUARDIAN_A, GUARDIAN_A);
const momDev = await pairDevice('guardian', GUARDIAN_B, GUARDIAN_B);
{
  check('A credential', 'redeem returns a 256-bit credential', kid.deviceCredential.length, 43);
  check('A credential', 'two devices get different credentials',
    kid.deviceCredential !== dadDev.deviceCredential, 'true');
  const [row] = (await admin.query(
    `SELECT credential_hash FROM paired_device WHERE id = $1`, [kid.deviceId])).rows;
  check('A credential', 'the stored value is the SHA-256 hex digest',
    row.credential_hash, createHash('sha256').update(kid.deviceCredential).digest('hex'));
  check('A credential', 'the credential itself is stored nowhere in the row',
    JSON.stringify((await admin.query(`SELECT * FROM paired_device WHERE id = $1`, [kid.deviceId])).rows[0])
      .includes(kid.deviceCredential), 'false');
}

// ===========================================================================
// B · refresh against the real row.
// ===========================================================================
{
  const now = new Date();
  const ok = await refreshPairedDeviceSession(pool, kid.deviceId, kid.deviceCredential, now);
  check('B refresh', 'right device + credential -> ok', ok.ok, 'true');
  check('B refresh', 'identity comes from the row: role', ok.role, 'child');
  check('B refresh', 'identity comes from the row: targetId', ok.targetId, CHILD_A);
  const [seen] = (await admin.query(`SELECT last_seen_at FROM paired_device WHERE id = $1`, [kid.deviceId])).rows;
  check('B refresh', 'last_seen_at stamped', seen.last_seen_at !== null, 'true');

  const wrong = await refreshPairedDeviceSession(pool, kid.deviceId, 'nope', now);
  check('B refresh', 'wrong credential -> invalid_device_credential', wrong.reason, 'invalid_device_credential');
  const swapped = await refreshPairedDeviceSession(pool, kid.deviceId, dadDev.deviceCredential, now);
  check('B refresh', "WRONG DEVICE (kid's id, DAD's credential) -> invalid_device_credential",
    swapped.reason, 'invalid_device_credential');
  const unknown = await refreshPairedDeviceSession(pool, randomUUID(), kid.deviceCredential, now);
  check('B refresh', 'unknown (well-formed) device id -> invalid_device_credential',
    unknown.reason, 'invalid_device_credential');
  const garbage = await refreshPairedDeviceSession(pool, "'; DROP TABLE paired_device; --", kid.deviceCredential, now);
  check('B refresh', 'a non-uuid id is a clean refusal, not a Postgres cast error',
    garbage.reason, 'invalid_device_credential');
  const empty = await refreshPairedDeviceSession(pool, kid.deviceId, '', now);
  check('B refresh', 'an empty credential never matches', empty.reason, 'invalid_device_credential');

  // A device paired before 0037 has NULL credential_hash: it must never match anything.
  await admin.query(`UPDATE paired_device SET credential_hash = NULL WHERE id = $1`, [momDev.deviceId]);
  for (const probe of ['', 'null', 'NULL', momDev.deviceCredential]) {
    const r = await refreshPairedDeviceSession(pool, momDev.deviceId, probe, now);
    check('B refresh', `NULL-hash legacy device cannot refresh with ${JSON.stringify(probe.slice(0, 6))}`,
      r.reason, 'invalid_device_credential');
  }
}

// ===========================================================================
// C · revocation.
// ===========================================================================
{
  const dad2 = await pairDevice('guardian', GUARDIAN_A, GUARDIAN_A);
  // A co-guardian revokes it through the EXISTING family-scoped route function.
  const rv = await revokePairedDevice(pool, CHILD_A, dad2.deviceId, GUARDIAN_B, new Date());
  check('C revoke', 'a co-guardian can revoke (existing path)', rv.ok, 'true');
  const [{ revoked_at }] = (await admin.query(`SELECT revoked_at FROM paired_device WHERE id = $1`, [dad2.deviceId])).rows;
  const r = await refreshPairedDeviceSession(pool, dad2.deviceId, dad2.deviceCredential, new Date());
  check('C revoke', 'revoked device + right credential -> device_revoked', r.reason, 'device_revoked');
  const wrongOnRevoked = await refreshPairedDeviceSession(pool, dad2.deviceId, 'nope', new Date());
  check('C revoke', 'revoked device + WRONG credential still says invalid (no revoke oracle)',
    wrongOnRevoked.reason, 'invalid_device_credential');
  const [{ revoked_at: after }] = (await admin.query(`SELECT revoked_at FROM paired_device WHERE id = $1`, [dad2.deviceId])).rows;
  check('C revoke', 'refresh never un-revokes', String(after), String(revoked_at));
}

// ===========================================================================
// D · principal / RLS cases.
// ===========================================================================
{
  const asStranger = await withSession(pool, { roleName: 'guardian', userId: GUARDIAN_C, childId: null },
    (q) => q(`SELECT id, credential_hash FROM paired_device WHERE id = $1`, [kid.deviceId]));
  check('D principal', "a stranger's own session cannot read the device row (so not its digest)", asStranger.length, 0);

  const asChild = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A },
    (q) => q(`SELECT id FROM paired_device WHERE id = $1`, [kid.deviceId]));
  check('D principal', "the child's own session cannot read paired_device rows", asChild.length, 0);

  const list = await pairedDevicesForChild(pool, CHILD_A, GUARDIAN_A);
  check('D principal', 'the family list route function returns devices', list.length > 0, 'true');
  check('D principal', 'no listed device exposes the digest or the credential',
    list.some((d) => 'credentialHash' in d || 'credential_hash' in d ||
      JSON.stringify(d).includes(kid.deviceCredential)), 'false');

  // A non-system principal cannot rewrite a credential hash it should not be able to see.
  const strangerUpdate = await withSession(pool, { roleName: 'guardian', userId: GUARDIAN_C, childId: null },
    (q) => q(`UPDATE paired_device SET credential_hash = 'x' WHERE id = $1 RETURNING id`, [kid.deviceId]));
  check('D principal', "a stranger's session cannot UPDATE someone's credential hash (RLS)", strangerUpdate.length, 0);

  // Sign-out revokes exactly ONE row: the caller's own device.
  const out = await revokeOwnPairedDevice(pool, momDev.deviceId, new Date());
  check('D principal', 'revokeOwnPairedDevice finds the row', out.ok, 'true');
  const state = (await admin.query(
    `SELECT id, revoked_at IS NOT NULL AS revoked FROM paired_device WHERE id = ANY($1)`,
    [[kid.deviceId, dadDev.deviceId, momDev.deviceId]])).rows;
  const byId = Object.fromEntries(state.map((r) => [r.id, r.revoked]));
  check('D principal', 'only the named device is revoked',
    `${byId[kid.deviceId]}/${byId[dadDev.deviceId]}/${byId[momDev.deviceId]}`, 'false/false/true');
  const [{ revoked_at: first }] = (await admin.query(`SELECT revoked_at FROM paired_device WHERE id = $1`, [momDev.deviceId])).rows;
  await revokeOwnPairedDevice(pool, momDev.deviceId, new Date(Date.now() + 5000));
  const [{ revoked_at: second }] = (await admin.query(`SELECT revoked_at FROM paired_device WHERE id = $1`, [momDev.deviceId])).rows;
  check('D principal', 'sign-out is idempotent: the original revoked_at is kept', String(second), String(first));
  check('D principal', 'a missing device id reports not-found', (await revokeOwnPairedDevice(pool, randomUUID(), new Date())).ok, 'false');
}

// ===========================================================================
// E · deactivated guardian.
// ===========================================================================
{
  const goneDev = await pairDevice('guardian', GONE, GONE);
  const before = await refreshPairedDeviceSession(pool, goneDev.deviceId, goneDev.deviceCredential, new Date());
  check('E deactivated', 'active guardian refreshes', before.ok, 'true');
  await admin.query(`UPDATE app_user SET deactivated_at = now() WHERE id = $1`, [GONE]);
  const after = await refreshPairedDeviceSession(pool, goneDev.deviceId, goneDev.deviceCredential, new Date());
  check('E deactivated', 'deactivated guardian: account_deactivated', after.reason, 'account_deactivated');
}

// ===========================================================================
// F · setPinCredential({ onlyIfAbsent }) is a real atomic insert-if-absent.
// ===========================================================================
{
  const racer = randomUUID();
  await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Racer','UTC')`, [racer]);
  const results = await Promise.all(Array.from({ length: 8 }, (_, i) =>
    setPinCredential(pool, racer, hashPin(String(1000 + i)), { onlyIfAbsent: true })));
  check('F first pin', 'exactly one of 8 concurrent first-PIN inserts wins', results.filter(Boolean).length, 1);
  const again = await setPinCredential(pool, racer, hashPin('9999'), { onlyIfAbsent: true });
  check('F first pin', 'insert-if-absent never overwrites an existing PIN', again, 'false');
  const replaced = await setPinCredential(pool, racer, hashPin('9999'));
  check('F first pin', 'the ordinary (proved) path still replaces', replaced, 'true');
}

// ===========================================================================
// G · the real HTTP routes against this Postgres.
// ===========================================================================
{
  const SECRET = Buffer.from('device-credential-test-secret-32by');
  const api = new Api(SECRET, dbPort(pool));
  registerRoutes(api, pool);
  const hit = (m, p, tok, body) => api.handle(m, p, tok ? { authorization: `Bearer ${tok}` } : {},
    body === undefined ? '' : JSON.stringify(body));

  const code = await createDevicePairingCode(pool, 'guardian', GUARDIAN_B, GUARDIAN_B);
  const red = await hit('POST', '/v1/device-pairing/redeem', null, { code: code.numericCode, role: 'guardian' });
  check('G http', 'redeem -> 201 with a credential', `${red.status}/${typeof red.body.deviceCredential}`, '201/string');

  const rf = await hit('POST', '/v1/auth/session/refresh', null,
    { deviceId: red.body.deviceId, deviceCredential: red.body.deviceCredential });
  check('G http', 'refresh -> 200', rf.status, 200);
  const p = readSession(SECRET, rf.body.sessionToken, Date.now()).principal;
  check('G http', 'the new session is GUARDIAN_B with the device claim',
    `${p.roleName}/${p.userId === GUARDIAN_B}/${p.deviceId === red.body.deviceId}`, 'guardian/true/true');
  const noPin = await hit('POST', '/v1/me/pin', rf.body.sessionToken, { pin: '4321' });
  check('G http', 'a session from refresh is a working session: first PIN (none set) -> 200', noPin.status, 200);
  const change = await hit('POST', '/v1/me/pin', rf.body.sessionToken, { pin: '8765' });
  check('G http', 'changing it without the current PIN -> 403', `${change.status}/${change.body.error}`, '403/current_pin_required');
  const change2 = await hit('POST', '/v1/me/pin', rf.body.sessionToken, { pin: '8765', currentPin: '4321' });
  check('G http', 'changing it WITH the current PIN -> 200', change2.status, 200);

  const so = await hit('POST', '/v1/auth/session/sign-out', rf.body.sessionToken);
  check('G http', 'sign-out -> 200 revoked', `${so.status}/${so.body.revoked}`, '200/true');
  const cut = await hit('POST', '/v1/auth/session/sign-out', rf.body.sessionToken);
  check('G http', 'the session is cut off at once (real isPairedDeviceRevoked) -> 401 device_revoked',
    `${cut.status}/${cut.body.error}`, '401/device_revoked');
  const dead = await hit('POST', '/v1/auth/session/refresh', null,
    { deviceId: red.body.deviceId, deviceCredential: red.body.deviceCredential });
  check('G http', 'the signed-out device can no longer refresh', `${dead.status}/${dead.body.error}`, '401/device_revoked');
}

await admin.end();
await pool.end();
for (const r of rows) if (!r.ok) console.log(`FAIL [${r.g}] ${r.n}: got ${r.a}, want ${r.e}`);
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
