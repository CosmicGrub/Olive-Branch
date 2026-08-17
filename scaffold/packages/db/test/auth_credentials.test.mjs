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
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  createPool, withSession, guardiansOfChild, pinCredentialFor, setPinCredential,
  recordPinAttempt, attemptPinFor, PIN_MAX_ATTEMPTS, createChallenge, consumeChallenge,
  storeWebauthnCredential, webauthnCredentialsForUser, webauthnCredentialById,
  updateWebauthnSignCount,
} from '../src/pool.mjs';
import { hashPin, verifyPin } from '../../auth/src/auth.mjs';

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
