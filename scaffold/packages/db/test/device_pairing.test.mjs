/**
 * packages/db — device pairing & provisioning: real Postgres, real RLS.
 * docs/superpowers/specs/2026-09-12-device-pairing-provisioning-design.md,
 * db/migrations/0032_device_pairing.sql, packages/db/src/pool.ts's
 * createDevicePairingCode()/cancelDevicePairingCode()/
 * redeemDevicePairingCode()/pairedDevicesForChild()/revokePairedDevice()/
 * isPairedDeviceRevoked().
 *
 * Same posture as guardian_invite.test.mjs, which this suite mirrors closely
 * — requires a real Postgres with 0032 applied, DATABASE_URL MUST be a
 * NOSUPERUSER NOBYPASSRLS role (db/DEPLOYMENT.md's app_owner).
 *
 * Seven sections:
 *   A. create — a real device_pairing_code row lands for both role shapes
 *      (child-role bound to a childId, guardian-role bound to the creating
 *      guardian's own id), correctly scoped.
 *   B. RLS ownership — device_pairing_code_owner_rw (0032's migration):
 *      only the creating guardian's own session can see/cancel a code —
 *      proven the same way guardian_invite.test.mjs's own section D proves
 *      it (querying AS the stranger and finding zero rows, not just
 *      trusting the function's return value).
 *   C. redeem — the system-role path, proven the SAME way guardian_invite's
 *      own accept-flow test proves it (this file's section C, mirrored):
 *      success, already-redeemed, expired, revoked, role-mismatch, and the
 *      numeric lockout after DEVICE_CODE_MAX_ATTEMPTS (5) failed attempts.
 *   D. list — pairedDevicesForChild()'s family scoping (child-role devices
 *      for the child, guardian-role devices for every co-guardian), AND the
 *      real "second lock": a stranger's OWN session sees zero rows even
 *      when asked for a childId that genuinely has real paired devices.
 *   E. revoke — a co-guardian (family-scoped) can revoke; a stranger's
 *      session cannot even find the row to revoke (RLS, not app logic).
 *   F. health_check's rls_unforced — both new tables genuinely FORCE RLS.
 *   G. THE REAL HTTP ROUTE — POST /v1/device-pairing/redeem, no session,
 *      driven through the real Api + registerRoutes wiring against this
 *      same real Postgres.
 */
import pg from 'pg';
import { randomUUID, randomBytes } from 'node:crypto';
import { createPool, createDevicePairingCode, cancelDevicePairingCode,
  redeemDevicePairingCode, pairedDevicesForChild, revokePairedDevice,
  isPairedDeviceRevoked, withSession, dbPort, DEVICE_CODE_MAX_ATTEMPTS,
} from '../src/pool.mjs';
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

// Fresh random ids every run — same reasoning guardian_invite.test.mjs's own
// header gives.
const CHILD_A = randomUUID();
const GUARDIAN_A = randomUUID(); // creates codes, lives with GUARDIAN_B on CHILD_A
const GUARDIAN_B = randomUUID(); // co-parent of CHILD_A
const CHILD_C = randomUUID();
const GUARDIAN_C = randomUUID(); // a total stranger — no edge to CHILD_A's family at all

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Guardian A','America/Chicago'),
     ($2,'Guardian B','America/Chicago'),
     ($3,'Guardian C (stranger)','America/New_York')`,
  [GUARDIAN_A, GUARDIAN_B, GUARDIAN_C]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Wren','2017-06-11','America/Chicago'),
     ($2,'Otherfamily Kid','2018-01-01','America/New_York')`,
  [CHILD_A, CHILD_C]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $5, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, GUARDIAN_A, GUARDIAN_B, CHILD_C, GUARDIAN_C]);
await admin.query('COMMIT');

// ===========================================================================
// A · CREATE — both role shapes, correctly scoped.
// ===========================================================================
let childCode, guardianCode;
{
  childCode = await createDevicePairingCode(pool, 'child', CHILD_A, GUARDIAN_A);
  check('A create', 'role round-trips', childCode.role, 'child');
  check('A create', 'targetId is the child', childCode.targetId, CHILD_A);
  check('A create', 'a real 6-digit numericCode', /^\d{6}$/.test(childCode.numericCode), true);
  check('A create', 'expires roughly 10 minutes out',
    Math.round((new Date(childCode.expiresAt) - Date.now()) / 60000), 10);

  guardianCode = await createDevicePairingCode(pool, 'guardian', GUARDIAN_A, GUARDIAN_A);
  check('A create', 'guardian-role code is bound to the CALLER\'S OWN id', guardianCode.targetId, GUARDIAN_A);
  check('A create', 'the two codes are genuinely distinct rows', childCode.id !== guardianCode.id, true);
}

// ===========================================================================
// B · RLS OWNERSHIP — device_pairing_code_owner_rw. Only the creating
// guardian's own session can see/cancel a code.
// ===========================================================================
{
  const stranger = await cancelDevicePairingCode(pool, childCode.id, GUARDIAN_C, new Date());
  check('B rls owner', "a total stranger's cancel attempt is refused", stranger.ok, 'false');
  check('B rls owner', 'refused as not_found — RLS hides the row, not an app-level check',
    stranger.reason, 'not_found');

  // Prove it is RLS, not cancelDevicePairingCode()'s own logic: query the row
  // directly under GUARDIAN_C's own session.
  const cRows = await withSession(pool, { roleName: 'guardian', userId: GUARDIAN_C, childId: null },
    (q) => q(`SELECT id FROM device_pairing_code WHERE id = $1`, [childCode.id]));
  check('B rls owner', "GUARDIAN_C's own session genuinely cannot see the row at all", cRows.length, 0);

  // The real owner still can — this is the SAME code redeem success (section
  // C) will use, so cancel it via a throwaway sibling code instead, to leave
  // childCode/guardianCode themselves live for section C.
  const throwaway = await createDevicePairingCode(pool, 'child', CHILD_A, GUARDIAN_A);
  const owner = await cancelDevicePairingCode(pool, throwaway.id, GUARDIAN_A, new Date());
  check('B rls owner', 'the owning guardian succeeds', owner.ok, 'true');
}

// ===========================================================================
// C · REDEEM — the system-role path. success, already-redeemed, expired,
// revoked, role-mismatch, numeric lockout.
// ===========================================================================
let redeemedDeviceId;
{
  const notFound = await redeemDevicePairingCode(pool, 'no-such-code-at-all', 'child', new Date());
  check('C redeem', 'a code matching nothing', notFound.ok, 'false');
  check('C redeem', 'reason', notFound.reason, 'not_found');

  const success = await redeemDevicePairingCode(pool, childCode.numericCode, 'child', new Date());
  check('C redeem', 'the right code, right role succeeds', success.ok, 'true');
  check('C redeem', 'targetId is the child', success.targetId, CHILD_A);
  check('C redeem', 'role round-trips', success.role, 'child');
  redeemedDeviceId = success.deviceId;

  const again = await redeemDevicePairingCode(pool, childCode.numericCode, 'child', new Date());
  check('C redeem', 'the same code again is refused', again.ok, 'false');
  check('C redeem', 'reason is already_redeemed', again.reason, 'already_redeemed');

  const toRevoke = await createDevicePairingCode(pool, 'child', CHILD_A, GUARDIAN_A);
  await cancelDevicePairingCode(pool, toRevoke.id, GUARDIAN_A, new Date());
  const revokedAttempt = await redeemDevicePairingCode(pool, toRevoke.numericCode, 'child', new Date());
  check('C redeem', 'a cancelled code is refused', revokedAttempt.ok, 'false');
  check('C redeem', 'reason is revoked', revokedAttempt.reason, 'revoked');

  const toExpire = await createDevicePairingCode(pool, 'child', CHILD_A, GUARDIAN_A);
  await admin.query(
    `UPDATE device_pairing_code SET expires_at = now() - interval '1 minute' WHERE id = $1`,
    [toExpire.id]);
  const expiredAttempt = await redeemDevicePairingCode(pool, toExpire.numericCode, 'child', new Date());
  check('C redeem', 'an expired code is refused', expiredAttempt.ok, 'false');
  check('C redeem', 'reason is expired', expiredAttempt.reason, 'expired');

  // role-mismatch + numeric lockout, DEVICE_CODE_MAX_ATTEMPTS in a row.
  const lockoutFixture = await createDevicePairingCode(pool, 'guardian', GUARDIAN_A, GUARDIAN_A);
  let lastReason;
  for (let i = 0; i < DEVICE_CODE_MAX_ATTEMPTS; i++) {
    const attempt = await redeemDevicePairingCode(pool, lockoutFixture.numericCode, 'child', new Date());
    lastReason = attempt.reason;
  }
  check('C redeem', `${DEVICE_CODE_MAX_ATTEMPTS} consecutive role-mismatches are each role_mismatch`,
    lastReason, 'role_mismatch');
  const stillLocked = await redeemDevicePairingCode(pool, lockoutFixture.numericCode, 'guardian', new Date());
  check('C redeem', 'the next attempt is LOCKED even with the now-correct role',
    stillLocked.ok, 'false');
  check('C redeem', 'reason is locked', stillLocked.reason, 'locked');
}

// ===========================================================================
// D · LIST — pairedDevicesForChild()'s family scoping, and the real
// "second lock": a stranger's own session sees zero rows regardless of the
// childId it asks about.
// ===========================================================================
let guardianDeviceId;
{
  const guardianRedeem = await redeemDevicePairingCode(pool, guardianCode.numericCode, 'guardian', new Date());
  check('D list', "GUARDIAN_A's own guardian-role code redeems", guardianRedeem.ok, 'true');
  guardianDeviceId = guardianRedeem.deviceId;

  // A guardian-role code for the CO-guardian, GUARDIAN_B.
  const bCode = await createDevicePairingCode(pool, 'guardian', GUARDIAN_B, GUARDIAN_B);
  const bRedeem = await redeemDevicePairingCode(pool, bCode.numericCode, 'guardian', new Date());
  check('D list', "GUARDIAN_B's own guardian-role code redeems too", bRedeem.ok, 'true');

  const list = await pairedDevicesForChild(pool, CHILD_A, GUARDIAN_A);
  const ids = list.map((d) => d.id);
  check('D list', 'the redeemed CHILD-role device is in the list', ids.includes(redeemedDeviceId), 'true');
  check('D list', "GUARDIAN_A's own guardian-role device is in the list (a live guardian of "
    + 'this same child)', ids.includes(guardianDeviceId), 'true');
  check('D list', "GUARDIAN_B's guardian-role device is ALSO in the list — 'every guardian "
    + "holding a live edge to that child', not just the caller", ids.includes(bRedeem.deviceId), 'true');

  // Real "second lock" — GUARDIAN_C is a total stranger to CHILD_A's family;
  // calling the SAME function with the SAME childId under HIS session must
  // return nothing, proving RLS (not just the app-layer WHERE clause) is
  // what ultimately scopes this.
  const strangerList = await pairedDevicesForChild(pool, CHILD_A, GUARDIAN_C);
  check('D list', "a stranger's OWN session sees ZERO of CHILD_A's real, existing devices "
    + '— RLS, not merely an unasked question', strangerList.length, 0);
}

// ===========================================================================
// E · REVOKE — a co-guardian (family-scoped) can revoke; a stranger's
// session cannot even find the row (RLS, not app logic).
// ===========================================================================
{
  const strangerRevoke = await revokePairedDevice(pool, CHILD_A, redeemedDeviceId, GUARDIAN_C, new Date());
  check('E revoke', "a stranger's revoke attempt is refused", strangerRevoke.ok, 'false');
  check('E revoke', 'refused as not_found — RLS hides the row', strangerRevoke.reason, 'not_found');
  check('E revoke', 'the device is genuinely still NOT revoked after the stranger\'s attempt',
    await isPairedDeviceRevoked(pool, redeemedDeviceId), false);

  // GUARDIAN_B (NOT the device's own target — DAD/GUARDIAN_A redeemed it —
  // but a real co-guardian of the SAME child) can revoke it: family scope,
  // not narrow ownership.
  const coGuardianRevoke = await revokePairedDevice(pool, CHILD_A, redeemedDeviceId, GUARDIAN_B, new Date());
  check('E revoke', 'a co-guardian of the SAME child can revoke a child-role device even '
    + "though they didn't redeem it themselves", coGuardianRevoke.ok, 'true');
  check('E revoke', 'the device is really revoked now',
    await isPairedDeviceRevoked(pool, redeemedDeviceId), true);

  const idempotent = await revokePairedDevice(pool, CHILD_A, redeemedDeviceId, GUARDIAN_A, new Date());
  check('E revoke', 'revoking an already-revoked device is idempotent (ok:true)', idempotent.ok, 'true');

  const missingId = randomUUID();
  const nonexistent = await revokePairedDevice(pool, CHILD_A, missingId, GUARDIAN_A, new Date());
  check('E revoke', 'a genuinely nonexistent deviceId is refused', nonexistent.ok, 'false');
  check('E revoke', 'reason is not_found', nonexistent.reason, 'not_found');

  // A never-redeemed deviceId asked about via isPairedDeviceRevoked() must
  // fail CLOSED (treated as revoked) — this function's own doc comment.
  check('E revoke', 'isPairedDeviceRevoked() fails CLOSED on an unresolvable id',
    await isPairedDeviceRevoked(pool, missingId), true);
}

// ===========================================================================
// F · health_check's rls_unforced — both new tables genuinely monitored.
// ===========================================================================
{
  const r = await admin.query(
    `SELECT observed FROM health_check WHERE check_name = 'rls_unforced'`);
  check('F health', 'rls_unforced reports zero unforced tables '
    + '(device_pairing_code AND paired_device both genuinely FORCE ROW LEVEL SECURITY)',
    r.rows[0]?.observed, '0');
}

// ===========================================================================
// G · THE REAL HTTP ROUTE — POST /v1/device-pairing/redeem, no session,
// driven through the real Api + registerRoutes wiring against this same
// real Postgres. Mirrors guardian_invite.test.mjs's own section G.
// ===========================================================================
{
  const api = new Api(randomBytes(32), dbPort(pool), () => Date.now());
  registerRoutes(api, pool);

  const httpFixture = await createDevicePairingCode(pool, 'child', CHILD_A, GUARDIAN_A);
  const res = await api.handle('POST', '/v1/device-pairing/redeem', {},
    JSON.stringify({ code: httpFixture.numericCode, role: 'child' }));
  check('G real route', 'a real redeem through the actual HTTP dispatch, no Authorization '
    + 'header at all, reaches the handler (not a 401)', res.status, 201);
  check('G real route', 'a real sessionToken comes back', typeof res.body?.sessionToken, 'string');
  check('G real route', 'a real deviceId comes back', typeof res.body?.deviceId, 'string');

  // That minted session, presented back to the SAME real Api instance, is
  // genuinely honored — a full round trip, not just a well-formed token.
  const meRes = await api.handle('GET', '/v1/me',
    { authorization: `Bearer ${res.body.sessionToken}` }, '');
  check('G real route', "the freshly minted session is accepted by the SAME Api instance "
    + 'on a completely different route', meRes.status !== 401, true);

  // Revoking that device through the real pool function, then replaying the
  // SAME token against the SAME Api instance, must now be refused.
  await revokePairedDevice(pool, CHILD_A, res.body.deviceId, GUARDIAN_A, new Date());
  const afterRevoke = await api.handle('GET', '/v1/me',
    { authorization: `Bearer ${res.body.sessionToken}` }, '');
  check('G real route', 'the same token, after a real revoke, is refused end to end',
    afterRevoke.status, 401);
  check('G real route', 'reason is device_revoked', afterRevoke.body.error, 'device_revoked');
}

await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
