/**
 * packages/db — auth_credentials: real RLS on pin_credential/webauthn_
 * credential/auth_challenge, real lockout behavior, real single-use
 * challenges. MASTERFILE §7.1, §8.1, §8.3. db/migrations/0008_auth_credentials.sql.
 *
 * Mirrors pool.test.mjs / custody_order.test.mjs's own pattern exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres with the 0008 migration applied, and is NOT part of `npm
 * test`'s default JS-suite chain for the same reason those two aren't — a
 * suite that measures RLS run as `postgres` measures nothing (see
 * pool.test.mjs's own header), so DATABASE_URL here MUST be a NOSUPERUSER
 * NOBYPASSRLS role (db/DEPLOYMENT.md's app_owner).
 *
 * Four things this file proves that no earlier suite could:
 *   A) pin_credential/webauthn_credential RLS — a CHILD session gets a real
 *      negative result on BOTH read and write (a query ERROR on INSERT, not
 *      merely an empty SELECT), and a GUARDIAN session can touch only her
 *      OWN row, never another guardian's.
 *   B) recordPinAttempt()'s lockout actually locks after PIN_MAX_ATTEMPTS
 *      consecutive failures and actually clears on the next success.
 *   C) consumeChallenge() cannot be used twice — including the real
 *      concurrency shape the task calls for: two consumeChallenge() calls
 *      for the same challenge fired at the same time, and only one may
 *      report success.
 *   D) auth_challenge is system-role-only — neither a guardian nor a child
 *      session can read or write it at all.
 *   G/H) SEC-01 follow-up (round-2 audit's adversarial verify) —
 *      setPinCredential()/storeWebauthnCredential() refuse a deactivated
 *      guardian, and webauthnLoginVerify()'s own gate (server/index.mjs)
 *      refuses one too, over a real HTTP server.
 *
 * Added by a Tier-3 test-coverage audit finding ("WebAuthn registration" —
 * thin coverage, not a known bug): sections I/J/K below close the specific
 * gaps that finding named, none of which any earlier section (here or in
 * attestation.test.mjs/contract.test.mjs) actually proved:
 *   I) storeWebauthnCredential()'s v0.49.3 atomic `FOR UPDATE` fix, under a
 *      REAL concurrent race against deactivateAccount() — G above only
 *      proves the sequential case (already deactivated, then refused);
 *      this proves the actual property the row lock exists for.
 *   J) registering a SECOND credential for the same user (multi-device) —
 *      never exercised anywhere before, at the pool level, plus the one
 *      real uniqueness constraint (credential_id) that IS enforced.
 *   K) the real HTTP registration routes themselves (POST .../register/
 *      challenge + verify, server/routes.mjs, through the real Api +
 *      registerRoutes wiring) end to end — a malformed/truncated
 *      attestationObject, a replayed challenge, a challenge minted for the
 *      wrong purpose or the wrong user, a second device, and a child
 *      session — none of which contract.test.mjs's route-shape check or
 *      attestation.test.mjs's pure-parser check actually drives over a
 *      request/response cycle.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createHash, generateKeyPairSync } from 'node:crypto';
import {
  createPool, withSession, guardiansOfChild, pinCredentialFor, setPinCredential,
  recordPinAttempt, attemptPinFor, PIN_MAX_ATTEMPTS, createChallenge, consumeChallenge,
  storeWebauthnCredential, webauthnCredentialsForUser, webauthnCredentialById,
  updateWebauthnSignCount, deactivateAccount, dbPort,
} from '../src/pool.mjs';
import { hashPin, verifyPin, issueSession } from '../../auth/src/auth.mjs';
import { Api } from '../../api/src/api.mjs';
import { registerRoutes, RP_ID, RP_ORIGIN } from '../../../server/routes.mjs';

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

// Seed a minimal real family: a child with TWO guardians (DAD, MOM — so
// cross-guardian isolation has a real second row to fail to reach), and a
// third, unrelated guardian (STRANGER) who is nobody's guardian at all.
const CHILD = 'c1111111-1111-1111-1111-111111111111';
const DAD = 'd2222222-2222-2222-2222-222222222222';
const MOM = 'd3333333-3333-3333-3333-333333333333';
const STRANGER = 'd4444444-4444-4444-4444-444444444444';

await admin.query('BEGIN');
await admin.query(`DELETE FROM auth_challenge WHERE user_id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(`DELETE FROM webauthn_credential WHERE user_id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(`DELETE FROM pin_credential WHERE user_id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/New_York'),
     ($3,'Stranger','America/Denver')`, [DAD, MOM, STRANGER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York')`, [CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM]);
await admin.query('COMMIT');

// ===========================================================================
// A · RLS — pin_credential and webauthn_credential
// ===========================================================================
{
  const dadHash = hashPin('1234');
  await setPinCredential(pool, DAD, dadHash);
  await storeWebauthnCredential(pool, DAD, 'a-cred-' + DAD, '-----BEGIN PUBLIC KEY-----\nX\n-----END PUBLIC KEY-----');

  // --- a CHILD session: zero access, on BOTH tables, on BOTH read and write ---
  const childReadPin = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
    async (q) => q(`SELECT * FROM pin_credential WHERE user_id = $1`, [DAD]));
  check('A RLS', 'a child session reads ZERO pin_credential rows (not a query error)',
    childReadPin.length, 0);

  const childReadWebauthn = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
    async (q) => q(`SELECT * FROM webauthn_credential WHERE user_id = $1`, [DAD]));
  check('A RLS', 'a child session reads ZERO webauthn_credential rows',
    childReadWebauthn.length, 0);

  // A real negative test, not just "absence of a policy" assumed sufficient:
  // FORCE + no child policy must make an INSERT actually ERROR, not silently
  // no-op or silently succeed.
  let childInsertThrew = false, childInsertMsg = '';
  try {
    await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
      async (q) => q(`INSERT INTO pin_credential (user_id, pin_hash) VALUES ($1, $2)`,
        [MOM, hashPin('9999')]));
  } catch (e) { childInsertThrew = true; childInsertMsg = String(e.message ?? e); }
  check('A RLS', 'a child session cannot INSERT into pin_credential (real DB error)',
    childInsertThrew, 'true');
  check('A RLS', 'the error is a real row-level-security denial, not something else',
    /row-level security/i.test(childInsertMsg), 'true');

  let childUpdateThrew = false;
  try {
    await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
      async (q) => q(`UPDATE pin_credential SET pin_hash = $2 WHERE user_id = $1`,
        [DAD, hashPin('0000')]));
  } catch { childUpdateThrew = true; }
  // UPDATE on a table with zero visible rows to this role affects zero rows
  // rather than erroring (there is nothing to violate a CHECK on) — the real
  // guarantee is that the row is UNCHANGED, verified below via the admin
  // connection, not that the statement itself throws.
  const stillDadsHash = await admin.query(`SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [DAD]);
  check('A RLS', "a child session's UPDATE does not change the guardian's real row",
    stillDadsHash.rows[0]?.pin_hash, dadHash);

  let childWebauthnInsertThrew = false;
  try {
    await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
      async (q) => q(`INSERT INTO webauthn_credential (user_id, credential_id, public_key_pem)
                        VALUES ($1, $2, $3)`, [MOM, 'child-planted-cred', 'x']));
  } catch { childWebauthnInsertThrew = true; }
  check('A RLS', 'a child session cannot INSERT into webauthn_credential either',
    childWebauthnInsertThrew, 'true');

  // --- a GUARDIAN touches only her OWN row, never another guardian's ---
  const momReadingDad = await withSession(pool, { roleName: 'guardian', userId: MOM, childId: null },
    async (q) => q(`SELECT * FROM pin_credential WHERE user_id = $1`, [DAD]));
  check('A RLS', "MOM's session reads ZERO of DAD's pin_credential rows",
    momReadingDad.length, 0);

  const momReadingDadWebauthn = await withSession(pool, { roleName: 'guardian', userId: MOM, childId: null },
    async (q) => q(`SELECT * FROM webauthn_credential WHERE user_id = $1`, [DAD]));
  check('A RLS', "MOM's session reads ZERO of DAD's webauthn_credential rows",
    momReadingDadWebauthn.length, 0);

  const dadReadingOwn = await pinCredentialFor(pool, DAD);
  check('A RLS', 'DAD reading his OWN pin_credential via pinCredentialFor works',
    dadReadingOwn !== null, 'true');
  check('A RLS', 'and the hash round-trips', dadReadingOwn?.pinHash, dadHash);

  let momUpdateDadThrew = false;
  try {
    await withSession(pool, { roleName: 'guardian', userId: MOM, childId: null },
      async (q) => q(`UPDATE pin_credential SET pin_hash = $2 WHERE user_id = $1`,
        [DAD, hashPin('5555')]));
  } catch { momUpdateDadThrew = true; }
  const dadHashAfterMomAttempt = await admin.query(
    `SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [DAD]);
  check('A RLS', "MOM's UPDATE attempt on DAD's row leaves it unchanged",
    dadHashAfterMomAttempt.rows[0]?.pin_hash, dadHash);

  // A STRANGER (nobody's guardian, but a real app_user with a real
  // guardian-role session) also cannot see DAD's row — RLS is per-USER, not
  // per-guardianship-edge, which is the correct, narrower guarantee (even a
  // guardian on a DIFFERENT child cannot read this one's PIN).
  const strangerReading = await withSession(pool, { roleName: 'guardian', userId: STRANGER, childId: null },
    async (q) => q(`SELECT * FROM pin_credential WHERE user_id = $1`, [DAD]));
  check('A RLS', "an unrelated guardian's session reads ZERO of DAD's pin_credential rows",
    strangerReading.length, 0);
}

// ===========================================================================
// D · RLS — auth_challenge is system-role-only, full stop
// ===========================================================================
{
  const ch = await createChallenge(pool, DAD, 'register');
  check('D RLS', 'createChallenge (system-scoped) succeeds', typeof ch, 'string');

  const guardianRead = await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
    async (q) => q(`SELECT * FROM auth_challenge WHERE user_id = $1`, [DAD]));
  check('D RLS', 'a GUARDIAN session — even the challenge\'s own owner — reads ZERO auth_challenge rows',
    guardianRead.length, 0);

  const childRead = await withSession(pool, { roleName: 'child', userId: null, childId: CHILD },
    async (q) => q(`SELECT * FROM auth_challenge WHERE user_id = $1`, [DAD]));
  check('D RLS', 'a CHILD session reads ZERO auth_challenge rows', childRead.length, 0);

  let guardianInsertThrew = false;
  try {
    await withSession(pool, { roleName: 'guardian', userId: DAD, childId: null },
      async (q) => q(`INSERT INTO auth_challenge (user_id, challenge, purpose)
                        VALUES ($1, 'forged', 'login')`, [DAD]));
  } catch { guardianInsertThrew = true; }
  check('D RLS', 'a guardian session cannot forge its own auth_challenge row',
    guardianInsertThrew, 'true');

  // consumeChallenge() itself (system-scoped) still works normally — RLS
  // blocks non-system SESSIONS, not the system-scoped accessor functions.
  const consumed = await consumeChallenge(pool, DAD, 'register', ch);
  check('D RLS', 'the real consumeChallenge() accessor (system-scoped) still works', consumed, 'true');
}

// ===========================================================================
// B · lockout — real numbers, real behavior
// ===========================================================================
{
  await admin.query(`DELETE FROM pin_credential WHERE user_id = $1`, [MOM]);
  const hash = hashPin('4242');
  await setPinCredential(pool, MOM, hash);

  for (let i = 1; i < PIN_MAX_ATTEMPTS; i++) {
    const r = await recordPinAttempt(pool, MOM, false);
    check('B lockout', `failure ${i}/${PIN_MAX_ATTEMPTS - 1} does not lock yet`,
      r.lockedUntil, 'null');
  }
  const cred = await pinCredentialFor(pool, MOM);
  check('B lockout', `failedAttempts sits at ${PIN_MAX_ATTEMPTS - 1} just before the lock`,
    cred.failedAttempts, PIN_MAX_ATTEMPTS - 1);

  const lockResult = await recordPinAttempt(pool, MOM, false);
  check('B lockout', `the ${PIN_MAX_ATTEMPTS}th consecutive failure locks the account`,
    lockResult.lockedUntil !== null, 'true');
  check('B lockout', 'lockedUntil is in the future',
    lockResult.lockedUntil.getTime() > Date.now(), 'true');

  const lockedCred = await pinCredentialFor(pool, MOM);
  check('B lockout', 'the counter resets to 0 the moment the lock is imposed (no stacking)',
    lockedCred.failedAttempts, 0);
  check('B lockout', 'verifyPin against the real hash still works (lock is enforced by the caller, not the hash)',
    verifyPin('4242', lockedCred.pinHash), 'true');

  // A success clears BOTH the counter and the lock.
  const successResult = await recordPinAttempt(pool, MOM, true);
  check('B lockout', 'a success clears the lock', successResult.lockedUntil, 'null');
  const clearedCred = await pinCredentialFor(pool, MOM);
  check('B lockout', 'and resets the counter', clearedCred.failedAttempts, 0);

  // Full ceremony proof: guardiansOfChild() -> pinCredentialFor() -> lockout
  // skip, the exact shape kiosk-pin/verify uses.
  await admin.query(`DELETE FROM pin_credential WHERE user_id = $1`, [DAD]);
  await setPinCredential(pool, DAD, hashPin('1357'));
  for (let i = 0; i < PIN_MAX_ATTEMPTS; i++) await recordPinAttempt(pool, DAD, false);
  const guardians = await guardiansOfChild(pool, CHILD);
  check('B lockout', 'guardiansOfChild finds both real guardians', guardians.length, 2);
  let anyMatchedWhileLocked = false;
  for (const g of guardians) {
    const c = await pinCredentialFor(pool, g.userId);
    if (!c) continue;
    if (c.lockedUntil && c.lockedUntil.getTime() > Date.now()) continue; // DAD is skipped here
    if (verifyPin('1357', c.pinHash)) anyMatchedWhileLocked = true;
  }
  check('B lockout', "a locked guardian's correct PIN is never matched while locked",
    anyMatchedWhileLocked, 'false');
}

// ===========================================================================
// C · consumeChallenge — single-use, including a real concurrent race
// ===========================================================================
{
  const ch = await createChallenge(pool, DAD, 'login');
  const first = await consumeChallenge(pool, DAD, 'login', ch);
  const second = await consumeChallenge(pool, DAD, 'login', ch);
  check('C single-use', 'the first consumeChallenge() call succeeds', first, 'true');
  check('C single-use', 'a second call with the SAME challenge fails', second, 'false');

  // Wrong purpose must not match even if everything else is identical.
  const ch2 = await createChallenge(pool, DAD, 'register');
  const wrongPurpose = await consumeChallenge(pool, DAD, 'login', ch2);
  check('C single-use', 'a challenge minted for "register" cannot be consumed as "login"',
    wrongPurpose, 'false');
  const rightPurpose = await consumeChallenge(pool, DAD, 'register', ch2);
  check('C single-use', 'the same challenge DOES consume under its real purpose',
    rightPurpose, 'true');

  // Wrong user must not match.
  const ch3 = await createChallenge(pool, DAD, 'login');
  const wrongUser = await consumeChallenge(pool, MOM, 'login', ch3);
  check('C single-use', "a challenge minted for DAD cannot be consumed as MOM's",
    wrongUser, 'false');

  // The REAL concurrency shape the task calls for: two consumeChallenge()
  // calls for the SAME challenge, fired at the same time (not sequentially
  // awaited), racing against Postgres's own row lock. Exactly one may
  // report true.
  const ch4 = await createChallenge(pool, DAD, 'login');
  const [raceA, raceB] = await Promise.all([
    consumeChallenge(pool, DAD, 'login', ch4),
    consumeChallenge(pool, DAD, 'login', ch4),
  ]);
  check('C concurrency', 'exactly one of two SIMULTANEOUS consumeChallenge() calls succeeds',
    [raceA, raceB].filter(Boolean).length, 1);

  // Expiry: a challenge older than the TTL cannot be consumed, even if it was
  // never touched. Simulated by back-dating issued_at directly (real time
  // travel, not mocking the clock) — proves the DB-side TTL predicate is
  // real, not merely present in the SQL text.
  const ch5 = await createChallenge(pool, DAD, 'login');
  await admin.query(
    `UPDATE auth_challenge SET issued_at = now() - interval '10 minutes' WHERE challenge = $1`,
    [ch5]);
  const expired = await consumeChallenge(pool, DAD, 'login', ch5);
  check('C expiry', 'a challenge older than the 5-minute TTL cannot be consumed', expired, 'false');
}

// ===========================================================================
// E · webauthn credential accessors — real round trip through the real tables
// ===========================================================================
{
  await admin.query(`DELETE FROM webauthn_credential WHERE user_id = $1`, [MOM]);
  await storeWebauthnCredential(pool, MOM, 'mom-cred-1', '-----BEGIN PUBLIC KEY-----\nMOM\n-----END PUBLIC KEY-----');
  const list = await webauthnCredentialsForUser(pool, MOM);
  check('E webauthn', 'webauthnCredentialsForUser finds the real stored row', list.length, 1);
  check('E webauthn', 'signCount starts at 0', list[0]?.signCount, 0);

  const byId = await webauthnCredentialById(pool, 'mom-cred-1');
  check('E webauthn', 'webauthnCredentialById (system-scoped identity lookup) finds it too',
    byId?.userId, MOM);
  const byIdUnknown = await webauthnCredentialById(pool, 'no-such-credential');
  check('E webauthn', 'an unknown credentialId returns null, not a throw', byIdUnknown, 'null');

  const advanced1 = await updateWebauthnSignCount(pool, 'mom-cred-1', 7);
  check('E webauthn', 'updateWebauthnSignCount reports success on a real advance', advanced1, 'true');
  const afterUpdate = await webauthnCredentialById(pool, 'mom-cred-1');
  check('E webauthn', 'updateWebauthnSignCount persists the new count', afterUpdate?.signCount, 7);

  // Real fix for a real TOCTOU: the write is now a compare-and-swap, not an
  // unconditional UPDATE. A stale/non-increasing write must be REFUSED and
  // must NOT touch the stored row.
  const staleWrite = await updateWebauthnSignCount(pool, 'mom-cred-1', 5);
  check('E webauthn CAS', 'a write with a LOWER signCount than stored is refused',
    staleWrite, 'false');
  const afterStale = await webauthnCredentialById(pool, 'mom-cred-1');
  check('E webauthn CAS', "and the stored count is UNCHANGED", afterStale?.signCount, 7);

  const equalWrite = await updateWebauthnSignCount(pool, 'mom-cred-1', 7);
  check('E webauthn CAS', 'a write with an EQUAL signCount to stored is also refused',
    equalWrite, 'false');

  // The real concurrency shape from the review's own reproduction: two
  // truly simultaneous writes claiming the SAME next signCount (exactly what
  // a cloned authenticator used at the same moment as the real one would
  // produce). Before this fix, BOTH succeeded — a session would have been
  // issued off each. Now exactly one may.
  await admin.query(`UPDATE webauthn_credential SET sign_count = 10 WHERE credential_id = 'mom-cred-1'`);
  const [raceA, raceB] = await Promise.all([
    updateWebauthnSignCount(pool, 'mom-cred-1', 11),
    updateWebauthnSignCount(pool, 'mom-cred-1', 11),
  ]);
  check('E webauthn CAS', 'exactly one of two SIMULTANEOUS same-target writes succeeds',
    [raceA, raceB].filter(Boolean).length, 1);
  const afterRace = await webauthnCredentialById(pool, 'mom-cred-1');
  check('E webauthn CAS', 'the stored count reflects the winner, not a torn write',
    afterRace?.signCount, 11);

  // The real, common Android case this fix must not break: an authenticator
  // that has ALWAYS reported 0 keeps being able to "advance" to 0 forever —
  // this is the deliberate `$2 = 0` bypass, not an oversight.
  await admin.query(`DELETE FROM webauthn_credential WHERE user_id = $1`, [DAD]);
  await storeWebauthnCredential(pool, DAD, 'dad-cred-zero', '-----BEGIN PUBLIC KEY-----\nDAD0\n-----END PUBLIC KEY-----');
  const zero1 = await updateWebauthnSignCount(pool, 'dad-cred-zero', 0);
  const zero2 = await updateWebauthnSignCount(pool, 'dad-cred-zero', 0);
  check('E webauthn CAS', 'an always-0 authenticator writing 0 repeatedly always succeeds (1st)',
    zero1, 'true');
  check('E webauthn CAS', 'and again (2nd) — the common real Android case must never regress',
    zero2, 'true');
}

// ===========================================================================
// F · concurrency — the real fix for the PIN lockout's concurrent-burst hole
// ===========================================================================
// Real, live-reproduced bug (adversarial review): pinCredentialFor()'s read
// and recordPinAttempt()'s write were two separate, unsynchronized round
// trips, so N simultaneous guesses against one guardian all read "not locked"
// before any of them observed a lock a sibling was in the middle of
// imposing — every guess ran a real scrypt verification regardless of
// PIN_MAX_ATTEMPTS. attemptPinFor() fixes this with a single `SELECT ... FOR
// UPDATE` transaction per attempt; this proves it under the exact concurrent
// shape the review used to break the old code.
{
  await admin.query(`DELETE FROM pin_credential WHERE user_id = $1`, [MOM]);
  const realPin = '4821';
  await setPinCredential(pool, MOM, hashPin(realPin));

  // 20 concurrent WRONG guesses, fired with Promise.all (not sequentially
  // awaited) so they genuinely race at the database, the same shape
  // Promise.all([...200 guesses...]) used in the original finding's
  // reproduction.
  const wrongGuesses = Array.from({ length: 20 }, (_, i) => String(1000 + i).padStart(4, '0'))
    .filter((g) => g !== realPin);
  const results = await Promise.all(wrongGuesses.map((g) => attemptPinFor(pool, MOM, g)));

  const ranVerify = results.filter((r) => !r.locked).length;   // reached verifyPin()
  const skippedLocked = results.filter((r) => r.locked).length; // saw the lock, skipped
  check('F concurrency', `AT MOST ${PIN_MAX_ATTEMPTS} of ${wrongGuesses.length} concurrent guesses ever reach verifyPin()`,
    ranVerify <= PIN_MAX_ATTEMPTS, 'true');
  check('F concurrency', 'every guess accounted for (ran verify OR observed the lock, never neither)',
    ranVerify + skippedLocked, wrongGuesses.length);
  check('F concurrency', 'none of the wrong guesses matched', results.some((r) => r.matched), 'false');

  const lockedCred = await pinCredentialFor(pool, MOM);
  check('F concurrency', 'the account ends up locked — the burst did not evade the lockout',
    lockedCred.lockedUntil !== null, 'true');
  check('F concurrency', 'failed_attempts sits at the post-lock reset value (0), no lost/duplicated increments',
    lockedCred.failedAttempts, 0);

  // The real PIN, tried WHILE the account is still locked from the burst
  // above, must still be refused — this is the actual property that was
  // broken: the lockout must hold even when the correct value is known.
  const stillLocked = await attemptPinFor(pool, MOM, realPin);
  check('F concurrency', "the REAL pin is refused while the account is locked (locked:true, no verify run)",
    `${stillLocked.matched}/${stillLocked.locked}`, 'false/true');

  // Sanity: verifyPin against the real hash still works once unlocked — the
  // lockout is enforced by the caller/attemptPinFor, not by breaking the hash.
  await admin.query(`UPDATE pin_credential SET locked_until = NULL, failed_attempts = 0 WHERE user_id = $1`, [MOM]);
  const nowMatches = await attemptPinFor(pool, MOM, realPin);
  check('F concurrency', 'once unlocked, the real PIN matches normally',
    `${nowMatches.matched}/${nowMatches.locked}`, 'true/false');
}

// ===========================================================================
// G · SEC-01 follow-up (round-2 audit's adversarial verify) — a deactivated
// guardian cannot register a NEW pin_credential or webauthn_credential.
// STRANGER, deliberately: no other section gives this account credentials,
// so a refusal here can only be this gate, nothing left over from earlier.
// ===========================================================================
{
  await admin.query(`UPDATE app_user SET deactivated_at = now() WHERE id = $1`, [STRANGER]);

  let pinDenied = null;
  try { await setPinCredential(pool, STRANGER, hashPin('4321')); }
  catch (e) { pinDenied = e.code; }
  check('G deactivation', 'setPinCredential refuses a deactivated guardian',
    pinDenied, 'account_deactivated');

  let webauthnDenied = null;
  try {
    await storeWebauthnCredential(pool, STRANGER, 'stranger-cred-denied',
      '-----BEGIN PUBLIC KEY-----\nX\n-----END PUBLIC KEY-----');
  } catch (e) { webauthnDenied = e.code; }
  check('G deactivation', 'storeWebauthnCredential refuses a deactivated guardian',
    webauthnDenied, 'account_deactivated');

  const strangerPins = await admin.query(
    `SELECT user_id FROM pin_credential WHERE user_id = $1`, [STRANGER]);
  check('G deactivation', 'the refused PIN write created no row', strangerPins.rows.length, 0);
  const strangerCreds = await admin.query(
    `SELECT credential_id FROM webauthn_credential WHERE user_id = $1`, [STRANGER]);
  check('G deactivation', 'the refused webauthn write created no row', strangerCreds.rows.length, 0);

  await admin.query(`UPDATE app_user SET deactivated_at = NULL WHERE id = $1`, [STRANGER]);
}

// ===========================================================================
// H · SEC-01 follow-up — webauthnLoginVerify()'s own deactivated_at gate
// (server/index.mjs), over a REAL HTTP server spawned as a real child
// process, the same pattern deletion.test.mjs section D uses for devLogin's
// gate. Deliberately minimal, well-formed-enough-to-pass-input-validation
// garbage for the credential fields — the point is proving the gate fires
// BEFORE any challenge/signature work runs, not re-exercising the crypto
// itself (stack.test.mjs's own "B WebAuthn" section already does that
// directly against the pure auth.ts functions).
// ===========================================================================
{
  const here = dirname(fileURLToPath(import.meta.url));
  const serverEntry = join(here, '..', '..', '..', 'server', 'index.mjs');
  const port = 23000 + (process.pid % 4000);
  const secret = 'auth-credentials-test-session-secret-not-for-production-use';

  const child = spawn(process.execPath, [serverEntry], {
    env: { ...process.env, DATABASE_URL, SESSION_SECRET: secret, DEV_LOGIN: '1', PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d.toString(); });
  child.stderr.on('data', (d) => { out += d.toString(); });
  const deadline = Date.now() + 8000;
  while (!out.includes('listening on') && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 50));
  }
  const booted = out.includes('listening on');
  check('H webauthn login gate', 'server/index.mjs actually boots against this database', booted, 'true');

  if (booted) {
    const base = `http://127.0.0.1:${port}`;
    await admin.query(`UPDATE app_user SET deactivated_at = now() WHERE id = $1`, [STRANGER]);

    const res = await fetch(`${base}/v1/auth/webauthn/login/verify`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        userId: STRANGER, credentialId: 'whatever',
        clientDataJSON: Buffer.from(JSON.stringify({ challenge: 'x' })).toString('base64url'),
        authenticatorData: 'AAAA', signature: 'AAAA',
      }),
    });
    const body = await res.json();
    check('H webauthn login gate', 'a deactivated account is refused BEFORE any crypto runs',
      res.status, 403);
    check('H webauthn login gate', 'refused with the real reason', body.error, 'account_deactivated');

    // Sanity control — the SAME malformed body against a NEVER-deactivated
    // account must NOT be refused by this gate (it will still fail later,
    // for an unrelated reason: no real challenge was ever issued). Proves
    // the 403 above is really about deactivation, not a body-shape reject
    // that would fire for anyone.
    await admin.query(`UPDATE app_user SET deactivated_at = NULL WHERE id = $1`, [STRANGER]);
    const control = await fetch(`${base}/v1/auth/webauthn/login/verify`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        userId: STRANGER, credentialId: 'whatever',
        clientDataJSON: Buffer.from(JSON.stringify({ challenge: 'x' })).toString('base64url'),
        authenticatorData: 'AAAA', signature: 'AAAA',
      }),
    });
    check('H webauthn login gate', 'the SAME request against an active account never gets THIS 403',
      control.status !== 403, 'true');
  }

  child.kill();
  await new Promise((r) => setTimeout(r, 200));
}

// ===========================================================================
// I · storeWebauthnCredential() atomicity — a REAL concurrent race against
// deactivateAccount() (CHANGELOG v0.49.3's SEC-01 follow-up, "worse than the
// device-token case"). Section G above only proves the SEQUENTIAL case
// (already deactivated, then a register attempt is refused) — real, but not
// the property the `FOR UPDATE` lock actually exists for. Both functions
// take that lock on the SAME `app_user` row (pool.ts's own comment on
// storeWebauthnCredential() says so explicitly), so a genuinely concurrent
// pair must serialize: whichever transaction acquires the row lock first
// runs to completion before the other is even allowed to read
// deactivated_at. Two orderings are possible and BOTH are legitimate:
//   (a) deactivateAccount() gets the lock first -> sets deactivated_at,
//       deletes any (zero, here) existing webauthn_credential rows, commits.
//       storeWebauthnCredential() then sees deactivated_at set and throws.
//   (b) storeWebauthnCredential() gets the lock first -> inserts, commits
//       (deactivated_at was still null). deactivateAccount() then runs its
//       own `DELETE FROM webauthn_credential WHERE user_id = $1`, which now
//       matches the row just inserted, and removes it on its way to setting
//       deactivated_at.
// What must be true under EITHER ordering — the actual invariant this fix
// protects — is that the process never ends with a deactivated account that
// still has a live, usable credential. Fired with Promise.allSettled (not
// sequentially awaited), the same real-race shape sections C/E/F above use
// to prove their own atomicity claims.
// ===========================================================================
{
  const RACER = 'e5555555-5555-5555-5555-555555555555';
  await admin.query(`DELETE FROM webauthn_credential WHERE user_id = $1`, [RACER]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [RACER]);
  await admin.query(
    `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1, 'Racer', 'America/Chicago')`,
    [RACER]);

  const [storeOutcome, deactivateOutcome] = await Promise.allSettled([
    storeWebauthnCredential(pool, RACER, 'racer-cred-1',
      '-----BEGIN PUBLIC KEY-----\nRACER\n-----END PUBLIC KEY-----'),
    deactivateAccount(pool, RACER),
  ]);

  check('I atomic race', 'deactivateAccount() always succeeds regardless of who wins the row lock',
    deactivateOutcome.status, 'fulfilled');

  const finalUser = await admin.query(`SELECT deactivated_at FROM app_user WHERE id = $1`, [RACER]);
  check('I atomic race', 'the account ends up deactivated no matter which side won the race',
    finalUser.rows[0]?.deactivated_at !== null, 'true');

  const finalCreds = await admin.query(
    `SELECT credential_id FROM webauthn_credential WHERE user_id = $1`, [RACER]);
  check('I atomic race',
    'THE REAL INVARIANT: a deactivated account NEVER ends up with a live credential, ' +
    'whichever transaction actually won the FOR UPDATE lock',
    finalCreds.rows.length, 0);

  // Names which real ordering happened, so a future regression that flips
  // WHICH branch fires is visible, not just silently absorbed by the two
  // invariant checks above.
  if (storeOutcome.status === 'rejected') {
    check('I atomic race', 'ordering (a): deactivateAccount() won — storeWebauthnCredential() ' +
      'is refused with the real reason', storeOutcome.reason?.code, 'account_deactivated');
  } else {
    check('I atomic race', 'ordering (b): storeWebauthnCredential() won the lock first, but its ' +
      'row is gone by the time deactivateAccount() commits (proven above: 0 live credentials)',
      finalCreds.rows.length, 0);
  }

  await admin.query(`DELETE FROM webauthn_credential WHERE user_id = $1`, [RACER]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [RACER]);
}

// ===========================================================================
// J · registering a SECOND credential for the same user — real multi-device
// support, never exercised anywhere in this suite (or any other) before.
// Nothing in the schema (0008_auth_credentials.sql: webauthn_credential's
// PRIMARY KEY is its own uuid `id`; `user_id` is merely INDEXed, not UNIQUE)
// or in storeWebauthnCredential() itself restricts a guardian to one
// credential — this proves that's REAL, not just schema-permitted-but-
// untested, and that the one uniqueness constraint that DOES exist
// (credential_id, globally UNIQUE) is enforced.
// ===========================================================================
{
  // A self-contained, known baseline — deliberately NOT relying on section
  // A's own DAD credential surviving untouched: section E's own always-0
  // case (real, deliberate) DELETEs every webauthn_credential row for DAD
  // and replaces it with 'dad-cred-zero', so by this point in the file
  // "DAD's section-A credential" is no longer what's actually there. Setting
  // up fresh, named fixtures here — the same discipline section B/F use for
  // MOM's PIN state — keeps this section correct regardless of what earlier
  // sections leave behind.
  await admin.query(`DELETE FROM webauthn_credential WHERE user_id = $1`, [DAD]);
  await storeWebauthnCredential(pool, DAD, 'j-first-device-' + DAD,
    '-----BEGIN PUBLIC KEY-----\nJ1\n-----END PUBLIC KEY-----');
  const before = await webauthnCredentialsForUser(pool, DAD);
  check('J multi-device', 'DAD starts this section with exactly one known credential',
    before.length, 1);

  await storeWebauthnCredential(pool, DAD, 'j-second-device-' + DAD,
    '-----BEGIN PUBLIC KEY-----\nJ2\n-----END PUBLIC KEY-----');
  const after = await webauthnCredentialsForUser(pool, DAD);
  check('J multi-device', 'a SECOND credential for the same user is accepted, not refused',
    after.length, 2);
  const ids = after.map((c) => c.credentialId).sort();
  check('J multi-device', 'both credential rows are real and distinct',
    ids.join(','), ['j-first-device-' + DAD, 'j-second-device-' + DAD].sort().join(','));

  // The one real uniqueness constraint that DOES exist: credential_id is
  // globally UNIQUE. A DIFFERENT user must not be able to register a
  // credential_id someone else already owns (this would only ever happen
  // from a corrupted/malicious client) — must be a real DB error, not a
  // silent overwrite of the original owner's row.
  let collided = false, collisionMsg = '';
  try {
    await storeWebauthnCredential(pool, MOM, 'j-first-device-' + DAD,
      '-----BEGIN PUBLIC KEY-----\nMOM-STEAL\n-----END PUBLIC KEY-----');
  } catch (e) { collided = true; collisionMsg = String(e.message ?? e); }
  check('J multi-device', 'a DIFFERENT user cannot register a credential_id already owned by someone else',
    collided, 'true');
  check('J multi-device', 'and it is a real uniqueness violation, not the deactivation gate',
    /duplicate key|unique/i.test(collisionMsg), 'true');
  const dadCredStillDads = await webauthnCredentialById(pool, 'j-first-device-' + DAD);
  check('J multi-device', "DAD's original row is untouched by the rejected collision attempt",
    dadCredStillDads?.userId, DAD);
}

// ===========================================================================
// K · the REAL HTTP registration routes end to end — POST .../register/
// challenge + POST .../register/verify (server/routes.mjs), through the real
// Api + registerRoutes wiring, in-process against api.handle() (no spawn
// needed — unlike section H's LOGIN routes, these run through api.register()
// so a Bearer session token authenticates them the ordinary way; see
// routes.mjs's own header for why LOGIN cannot). Nothing before this section
// has ever driven these two routes over an actual request/response cycle:
// section G proves the pool-level deactivation gate directly,
// attestation.test.mjs proves the pure CBOR/COSE parser directly, and
// contract.test.mjs proves the route EXISTS with the right action/session
// shape — none of them prove what happens when a real (or malformed) request
// actually reaches the handler in routes.mjs.
// ===========================================================================
{
  const SECRET = Buffer.from('k-section-webauthn-route-test-secret-32', 'utf8');
  const NOW = Date.now();
  const api = new Api(SECRET, dbPort(pool));
  registerRoutes(api, pool);

  const stTok = issueSession(SECRET,
    { userId: STRANGER, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const momTok = issueSession(SECRET,
    { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const childTok = issueSession(SECRET,
    { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

  const post = (path, tok, body) => api.handle('POST', path,
    tok ? { authorization: `Bearer ${tok}` } : {}, body ? JSON.stringify(body) : '');

  // A tiny, standalone CBOR encoder — the same deliberately-independent
  // shape attestation.test.mjs's own header explains (built only to
  // construct synthetic registration material, never derived from
  // attestation.ts's own decoder).
  const cborUint = (n) => (n < 24 ? Buffer.from([n]) : Buffer.from([24, n]));
  const cborNegint = (n) => { const a = n - 1; return a < 24 ? Buffer.from([0x20 | a]) : Buffer.from([0x38, a]); };
  const cborBytes = (buf) => (buf.length < 24
    ? Buffer.concat([Buffer.from([0x40 | buf.length]), buf])
    : Buffer.concat([Buffer.from([0x58, buf.length]), buf]));
  const cborText = (s) => { const b = Buffer.from(s, 'utf8');
    return b.length < 24 ? Buffer.concat([Buffer.from([0x60 | b.length]), b])
                         : Buffer.concat([Buffer.from([0x78, b.length]), b]); };
  const cborMapHeader = (n) => Buffer.from([0xa0 | n]);
  const encodeCoseKeyEc2 = (x, y) => Buffer.concat([
    cborMapHeader(5),
    cborUint(1), cborUint(2),     // kty: EC2
    cborUint(3), cborNegint(7),   // alg: ES256
    cborNegint(1), cborUint(1),   // crv: P-256
    cborNegint(2), cborBytes(x),
    cborNegint(3), cborBytes(y),
  ]);
  const rpIdHash = createHash('sha256').update(RP_ID, 'utf8').digest();
  const buildAuthData = (credentialIdBuf, coseKeyBuf) => {
    const flags = Buffer.from([0x41]); // UP + AT
    const signCount = Buffer.alloc(4);
    const aaguid = Buffer.alloc(16, 0);
    const credIdLen = Buffer.alloc(2); credIdLen.writeUInt16BE(credentialIdBuf.length);
    return Buffer.concat([rpIdHash, flags, signCount, aaguid, credIdLen, credentialIdBuf, coseKeyBuf]);
  };
  // rawCredentialId is a plain test-chosen string; the route stores the
  // credential_id extractCredentialPublicKey() produces, which is the
  // base64url of these RAW BYTES — credIdB64u() below computes the same
  // transform so assertions can look the row up correctly.
  const credIdB64u = (raw) => Buffer.from(raw, 'utf8').toString('base64url');
  const buildAttestationObjectB64u = (rawCredentialId) => {
    const { publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const jwk = publicKey.export({ format: 'jwk' });
    const x = Buffer.from(jwk.x, 'base64url');
    const y = Buffer.from(jwk.y, 'base64url');
    const authData = buildAuthData(Buffer.from(rawCredentialId, 'utf8'), encodeCoseKeyEc2(x, y));
    const obj = Buffer.concat([
      cborMapHeader(3),
      cborText('fmt'), cborText('none'),
      cborText('attStmt'), cborMapHeader(0),
      cborText('authData'), cborBytes(authData),
    ]);
    return obj.toString('base64url');
  };
  const clientDataFor = (challenge, type = 'webauthn.create') =>
    Buffer.from(JSON.stringify({ type, challenge, origin: RP_ORIGIN }), 'utf8').toString('base64url');

  // --- K1 sanity: a full, real, valid registration round trip ------------
  {
    const chal = await post('/v1/auth/webauthn/register/challenge', stTok, null);
    check('K1 route success', 'challenge route returns 200 for a real guardian session', chal.status, 200);
    check('K1 route success', 'challenge names the real RP_ID', chal.body.rpId, RP_ID);

    const attestationObject = buildAttestationObjectB64u('k1-stranger-device-1');
    const verify = await post('/v1/auth/webauthn/register/verify', stTok, {
      clientDataJSON: clientDataFor(chal.body.challenge), attestationObject,
    });
    check('K1 route success', 'a real, well-formed registration is accepted end to end', verify.status, 200);
    check('K1 route success', 'and reports ok:true', verify.body.ok, 'true');

    const stored = await webauthnCredentialById(pool, credIdB64u('k1-stranger-device-1'));
    check('K1 route success', 'the credential the ROUTE actually persisted belongs to the real caller',
      stored?.userId, STRANGER);
  }

  // --- K2 malformed/truncated attestationObject over the real route ------
  {
    const chal = await post('/v1/auth/webauthn/register/challenge', stTok, null);
    const verify = await post('/v1/auth/webauthn/register/verify', stTok, {
      clientDataJSON: clientDataFor(chal.body.challenge),
      attestationObject: Buffer.from([0xff, 0xff, 0xff, 0xff]).toString('base64url'),
    });
    check('K2 malformed', 'a garbage attestationObject is refused with 400, not a 500 crash',
      verify.status, 400);
    check('K2 malformed', 'and names the real reason', verify.body.error, 'bad_attestation_object');

    // consumeChallenge runs BEFORE attestation parsing (routes.mjs's own
    // ordering) — the challenge above was already burned reaching this far.
    // Retrying with a WELL-FORMED attestation on the same challenge must
    // still fail, proving the burn is real even on a failed attempt.
    const retry = await post('/v1/auth/webauthn/register/verify', stTok, {
      clientDataJSON: clientDataFor(chal.body.challenge),
      attestationObject: buildAttestationObjectB64u('k2-should-never-be-stored'),
    });
    check('K2 malformed', 'the SAME challenge cannot be retried after the malformed attempt burned it',
      retry.status, 400);
    check('K2 malformed', 'and it fails as a spent challenge, not a second parse error',
      retry.body.error, 'challenge_mismatch');
    const neverStored = await webauthnCredentialById(pool, credIdB64u('k2-should-never-be-stored'));
    check('K2 malformed', 'and no credential was ever stored from either attempt', neverStored, 'null');
  }

  // --- K3 challenge replay — reusing an already-CONSUMED challenge --------
  {
    const chal = await post('/v1/auth/webauthn/register/challenge', stTok, null);
    const body = { clientDataJSON: clientDataFor(chal.body.challenge),
      attestationObject: buildAttestationObjectB64u('k3-first-use') };
    const first = await post('/v1/auth/webauthn/register/verify', stTok, body);
    check('K3 replay', 'the first use of a fresh challenge succeeds', first.status, 200);

    const second = await post('/v1/auth/webauthn/register/verify', stTok, body);
    check('K3 replay', 'reusing the SAME already-consumed challenge is refused, not accepted again',
      second.status, 400);
    check('K3 replay', 'named as a challenge failure, not a duplicate-credential failure',
      second.body.error, 'challenge_mismatch');
  }

  // --- K4 a challenge minted for the WRONG PURPOSE (login, not register) --
  {
    const loginChallenge = await createChallenge(pool, STRANGER, 'login');
    const verify = await post('/v1/auth/webauthn/register/verify', stTok, {
      clientDataJSON: clientDataFor(loginChallenge),
      attestationObject: buildAttestationObjectB64u('k4-should-never-be-stored'),
    });
    check('K4 wrong purpose', 'a real LOGIN challenge cannot be spent as a REGISTER one over the real route',
      verify.status, 400);
    check('K4 wrong purpose', 'named as a challenge failure', verify.body.error, 'challenge_mismatch');
    const neverStored = await webauthnCredentialById(pool, credIdB64u('k4-should-never-be-stored'));
    check('K4 wrong purpose', 'and nothing was stored', neverStored, 'null');

    // The failed register/verify attempt must not have consumed the LOGIN
    // challenge either (purposes don't match, so consumeChallenge's WHERE
    // never touched that row) — it is still spendable under its real purpose.
    const stillGoodAsLogin = await consumeChallenge(pool, STRANGER, 'login', loginChallenge);
    check('K4 wrong purpose', 'the login challenge itself is untouched and still consumable as a login',
      stillGoodAsLogin, 'true');
  }

  // --- K5 a challenge minted for the WRONG USER ---------------------------
  {
    const chalForStranger = await post('/v1/auth/webauthn/register/challenge', stTok, null);
    // MOM tries to spend STRANGER's own challenge under HER OWN session.
    const verify = await post('/v1/auth/webauthn/register/verify', momTok, {
      clientDataJSON: clientDataFor(chalForStranger.body.challenge),
      attestationObject: buildAttestationObjectB64u('k5-should-never-be-stored'),
    });
    check('K5 wrong user', "a challenge minted for STRANGER cannot be spent under MOM's session",
      verify.status, 400);
    check('K5 wrong user', 'named as a challenge failure', verify.body.error, 'challenge_mismatch');
    const neverStored = await webauthnCredentialById(pool, credIdB64u('k5-should-never-be-stored'));
    check('K5 wrong user', 'and nothing was stored under either identity', neverStored, 'null');

    // STRANGER's own challenge is still live — MOM's attempt never touched
    // it (wrong-user is scoped entirely by consumeChallenge's own WHERE
    // user_id = $1, not a shared burn) — she can still use it herself.
    const strangerNowUses = await post('/v1/auth/webauthn/register/verify', stTok, {
      clientDataJSON: clientDataFor(chalForStranger.body.challenge),
      attestationObject: buildAttestationObjectB64u('k5-strangers-real-device'),
    });
    check('K5 wrong user', "the real owner's challenge still works after a wrong-user attempt on it",
      strangerNowUses.status, 200);
  }

  // --- K6 a SECOND device registered for the same user, over the real route
  {
    const chal = await post('/v1/auth/webauthn/register/challenge', momTok, null);
    const verify = await post('/v1/auth/webauthn/register/verify', momTok, {
      clientDataJSON: clientDataFor(chal.body.challenge),
      attestationObject: buildAttestationObjectB64u('k6-moms-second-device'),
    });
    check('K6 multi-device route', "a SECOND device registration for MOM (who already has 'mom-cred-1' " +
      'from section E) succeeds through the real route', verify.status, 200);
    const momCreds = await webauthnCredentialsForUser(pool, MOM);
    check('K6 multi-device route', "MOM now has BOTH her section-E device and this new one",
      momCreds.length, 2);
  }

  // --- K7 a CHILD session is refused before any body work is even done ---
  {
    const chal = await post('/v1/auth/webauthn/register/challenge', childTok, null);
    check('K7 child session', 'a child session cannot mint a registration challenge', chal.status, 403);
    check('K7 child session', 'named the real reason', chal.body.error, 'guardian_session_required');

    const verify = await post('/v1/auth/webauthn/register/verify', childTok, {
      clientDataJSON: clientDataFor('irrelevant'), attestationObject: buildAttestationObjectB64u('nope'),
    });
    check('K7 child session', 'a child session cannot verify a registration either', verify.status, 403);
    const neverStored = await webauthnCredentialById(pool, credIdB64u('nope'));
    check('K7 child session', 'and nothing was ever stored on its behalf', neverStored, 'null');
  }
}

await admin.query(`DELETE FROM auth_challenge WHERE user_id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(`DELETE FROM webauthn_credential WHERE user_id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(`DELETE FROM pin_credential WHERE user_id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1,$2,$3)`, [DAD, MOM, STRANGER]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
