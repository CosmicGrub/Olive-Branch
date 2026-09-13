/**
 * packages/db — device_token: real RLS, real dedupe-by-token, real
 * system-only visibility. MASTERFILE §11. db/migrations/0012_push_device_token.sql.
 *
 * Mirrors pool.test.mjs / custody_order.test.mjs's own pattern exactly (same
 * DATABASE_URL/ADMIN_DATABASE_URL split, same check() harness): requires a
 * real Postgres with 0008 applied, and is NOT part of `npm test`'s default
 * JS-suite chain for the same reason those two aren't — a suite that
 * measures RLS run as `postgres` measures nothing (see pool.test.mjs's own
 * header), so DATABASE_URL here MUST be a NOSUPERUSER NOBYPASSRLS role
 * (db/DEPLOYMENT.md's app_owner).
 *
 * What this proves that no other suite could:
 *   A) a principal can register/re-register/unregister only their OWN device
 *      rows — never another principal's, never across the child/guardian
 *      owner-column split;
 *   B) re-registration with the SAME token is a real UPSERT (one row, stable
 *      id), and re-registration with the same token under a DIFFERENT owner
 *      re-attributes the row (0008's own documented dedupe policy);
 *   C) deviceTokensFor()/removeDeviceTokenSystem() are reachable under the
 *      system role and ONLY the system role;
 *   D) the table's own CHECK constraints (exactly one owner, platform
 *      allowlist) and unique index (token) reject what they should;
 *   E) deactivateAccount() cascades to device_token, and a deactivated
 *      guardian/coordinator cannot register a NEW device afterward — the
 *      round-2 audit's SEC-01, closed in packages/db/src/pool.ts.
 *
 * 0008's own migration header documents a real defect this suite's earlier
 * drafts caught: a first design shipped with NO SELECT policy at all for
 * child/guardian, on the assumption an UPDATE/DELETE policy's own USING
 * clause was sufficient to locate a caller's own rows. It is not — Postgres
 * requires a SELECT policy too, or UPDATE/DELETE match nothing, silently.
 * Section A below is what actually caught that (every assertion in it
 * failed until device_token_select_own was added).
 */
import pg from 'pg';
import {
  createPool, registerDeviceToken, unregisterDeviceToken,
  deviceTokensFor, removeDeviceTokenSystem, deactivateAccount,
} from '../src/pool.mjs';

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

const DAD = 'a1111111-1111-1111-1111-111111111111';
const MOM = 'a2222222-2222-2222-2222-222222222222';
const IVY = 'a3333333-3333-3333-3333-333333333333';
const ELI = 'a4444444-4444-4444-4444-444444444444';

await admin.query('BEGIN');
await admin.query(`DELETE FROM device_token WHERE owner_user_id IN ($1,$2) OR owner_child_id IN ($3,$4)`,
  [DAD, MOM, IVY, ELI]);
await admin.query(`DELETE FROM child WHERE id IN ($1,$2)`, [IVY, ELI]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1,$2)`, [DAD, MOM]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/New_York')`, [DAD, MOM]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Eli','2019-09-11','America/New_York')`, [IVY, ELI]);
await admin.query('COMMIT');

const dadP = { roleName: 'guardian', userId: DAD, childId: null };
const momP = { roleName: 'guardian', userId: MOM, childId: null };
const ivyP = { roleName: 'child', userId: null, childId: IVY };
const eliP = { roleName: 'child', userId: null, childId: ELI };

// ===========================================================================
// A · RLS — a principal can only write (and see) their own device rows
// ===========================================================================
{
  const dadId = await registerDeviceToken(pool, dadP, 'ios', 'tok-dad-A');
  check('A rls', 'guardian can register their own device', typeof dadId, 'string');

  const ivyId = await registerDeviceToken(pool, ivyP, 'android', 'tok-ivy-A');
  check('A rls', 'child can register her own device', typeof ivyId, 'string');
  check('A rls', 'guardian and child rows get different ids', ivyId === dadId, 'false');

  const momDeletesDads = await unregisterDeviceToken(pool, momP, 'tok-dad-A');
  check('A rls', "a DIFFERENT guardian cannot delete Dad's token", momDeletesDads, 'false');

  const eliDeletesIvys = await unregisterDeviceToken(pool, eliP, 'tok-ivy-A');
  check('A rls', "a DIFFERENT child cannot delete Ivy's token", eliDeletesIvys, 'false');

  const dadDeletesIvys = await unregisterDeviceToken(pool, dadP, 'tok-ivy-A');
  check('A rls', "a guardian cannot delete a CHILD's token", dadDeletesIvys, 'false');

  const ivyDeletesDads = await unregisterDeviceToken(pool, ivyP, 'tok-dad-A');
  check('A rls', "a child cannot delete a GUARDIAN's token", ivyDeletesDads, 'false');

  // Both rows must still exist — every cross-owner delete attempt above was
  // a genuine no-op, not a partial success.
  const dadDevices = await deviceTokensFor(pool, { userId: DAD });
  check('A rls', "Dad's token survived every cross-owner delete attempt",
    dadDevices.some(d => d.token === 'tok-dad-A'), 'true');
  const ivyDevices = await deviceTokensFor(pool, { childId: IVY });
  check('A rls', "Ivy's token survived every cross-owner delete attempt",
    ivyDevices.some(d => d.token === 'tok-ivy-A'), 'true');

  // Now the OWNING principal deletes their own — must succeed.
  const dadDeletesOwn = await unregisterDeviceToken(pool, dadP, 'tok-dad-A');
  check('A rls', 'a guardian CAN delete their own token', dadDeletesOwn, 'true');
  const ivyDeletesOwn = await unregisterDeviceToken(pool, ivyP, 'tok-ivy-A');
  check('A rls', 'a child CAN delete her own token', ivyDeletesOwn, 'true');

  const dadDevicesAfter = await deviceTokensFor(pool, { userId: DAD });
  check('A rls', "Dad's device list is empty after his own delete", dadDevicesAfter.length, 0);
}

// ===========================================================================
// B · DEDUPE — same token twice is one row; a re-registered token
// re-attributes to whoever registers it now (0008's own documented policy)
// ===========================================================================
{
  const id1 = await registerDeviceToken(pool, dadP, 'ios', 'tok-dedupe-B');
  const id2 = await registerDeviceToken(pool, dadP, 'ios', 'tok-dedupe-B');
  check('B dedupe', 're-registering the SAME token returns the SAME id (real upsert)', id2, id1);

  const dadListBefore = await deviceTokensFor(pool, { userId: DAD });
  check('B dedupe', 're-registering the same token does not create a second row',
    dadListBefore.filter(d => d.token === 'tok-dedupe-B').length, 1);

  // Re-register the SAME token under a DIFFERENT owner (Mom) — simulates a
  // shared device changing hands. registerDeviceToken's own header explains
  // why this is a fresh row (new id) rather than an in-place UPDATE: RLS
  // correctly refuses to let Mom's session directly UPDATE a row Dad still
  // owns, so the fallback frees it (system-scoped) and re-inserts — the
  // CONTENT re-attributes even though the id does not.
  const id3 = await registerDeviceToken(pool, momP, 'ios', 'tok-dedupe-B');
  check('B dedupe', 're-registration under a different owner succeeds', typeof id3, 'string');
  check('B dedupe', '...as a genuinely new row (old id does not survive an owner change)',
    id3 === id1, 'false');

  const dadListAfter = await deviceTokensFor(pool, { userId: DAD });
  check('B dedupe', "the token no longer appears under Dad's list after re-attribution",
    dadListAfter.some(d => d.token === 'tok-dedupe-B'), 'false');
  const momList = await deviceTokensFor(pool, { userId: MOM });
  check('B dedupe', 'the token now appears under the new owner (Mom)',
    momList.some(d => d.token === 'tok-dedupe-B'), 'true');

  await unregisterDeviceToken(pool, momP, 'tok-dedupe-B');
}

// ===========================================================================
// C · SYSTEM-ONLY VISIBILITY — deviceTokensFor/removeDeviceTokenSystem
// ===========================================================================
{
  const id = await registerDeviceToken(pool, dadP, 'android', 'tok-dad-C');
  const beforePrune = await deviceTokensFor(pool, { userId: DAD });
  check('C system', "system sees Dad's real device row", beforePrune.some(d => d.id === id), 'true');

  const pruned = await removeDeviceTokenSystem(pool, id);
  check('C system', 'removeDeviceTokenSystem reaps the row', pruned, 'true');

  const afterPrune = await deviceTokensFor(pool, { userId: DAD });
  check('C system', 'the reaped row is really gone', afterPrune.some(d => d.id === id), 'false');

  const prunedAgain = await removeDeviceTokenSystem(pool, id);
  check('C system', 'pruning an already-gone id is a safe no-op, not an error', prunedAgain, 'false');

  // system role itself cannot own a device.
  let systemRegisterThrew = false;
  try {
    await registerDeviceToken(pool, { roleName: 'system', userId: null, childId: null }, 'ios', 'tok-system-C');
  } catch { systemRegisterThrew = true; }
  check('C system', 'registerDeviceToken refuses a system principal', systemRegisterThrew, 'true');
}

// ===========================================================================
// D · TABLE CONSTRAINTS — the migration's own CHECK/UNIQUE, hit directly
// ===========================================================================
{
  let neitherOwnerFailed = false;
  try {
    await admin.query(
      `INSERT INTO device_token (platform, token) VALUES ('ios','tok-neither-D')`);
  } catch { neitherOwnerFailed = true; }
  check('D constraints', 'a row with NEITHER owner column set is rejected', neitherOwnerFailed, 'true');

  let bothOwnersFailed = false;
  try {
    await admin.query(
      `INSERT INTO device_token (owner_user_id, owner_child_id, platform, token)
       VALUES ($1, $2, 'ios', 'tok-both-D')`, [DAD, IVY]);
  } catch { bothOwnersFailed = true; }
  check('D constraints', 'a row with BOTH owner columns set is rejected', bothOwnersFailed, 'true');

  let badPlatformFailed = false;
  try {
    await admin.query(
      `INSERT INTO device_token (owner_user_id, platform, token)
       VALUES ($1, 'windows_phone', 'tok-badplat-D')`, [DAD]);
  } catch { badPlatformFailed = true; }
  check('D constraints', 'an unrecognised platform is rejected', badPlatformFailed, 'true');

  await admin.query(
    `INSERT INTO device_token (owner_user_id, platform, token) VALUES ($1,'ios','tok-unique-D')`, [DAD]);
  let dupTokenFailed = false;
  try {
    await admin.query(
      `INSERT INTO device_token (owner_user_id, platform, token) VALUES ($1,'ios','tok-unique-D')`, [MOM]);
  } catch { dupTokenFailed = true; }
  check('D constraints', 'a raw duplicate token (no ON CONFLICT) violates the unique index',
    dupTokenFailed, 'true');
  await admin.query(`DELETE FROM device_token WHERE token = 'tok-unique-D'`);
}

// ===========================================================================
// E · SEC-01 — deactivation cascades to device_token, and refuses to let a
// still-valid session token register a NEW device afterward. Placed last:
// this section deactivates DAD, so nothing after it may assume he's live.
// ===========================================================================
{
  const beforeId = await registerDeviceToken(pool, dadP, 'ios', 'tok-dad-E-before');
  check('E deactivation', 'Dad can register before deactivation', typeof beforeId, 'string');

  // A BYSTANDER row, registered before Dad's deactivation: Mom's own device,
  // still very much active. Without this, Dad's row would be the ONLY row on
  // the whole table at deactivation time, and the assertions below could not
  // tell a correctly-scoped `WHERE owner_user_id = $1` apart from an unscoped
  // full-table wipe (device_token's RLS gives 'system' unrestricted DELETE —
  // db/migrations/0012_push_device_token.sql's device_token_system_prune has
  // no owner predicate — so the app-layer WHERE clause is the only thing
  // preventing that, and this is what actually proves it holds).
  const bystanderId = await registerDeviceToken(pool, momP, 'android', 'tok-mom-E-bystander');
  check('E deactivation', "Mom's bystander device registers fine", typeof bystanderId, 'string');

  const result = await deactivateAccount(pool, DAD);
  check('E deactivation', "deactivateAccount cascades to Dad's device_token rows",
    result.removedDeviceTokens, 1);

  const bystanderSurvives = await deviceTokensFor(pool, { userId: MOM });
  check('E deactivation', "Mom's bystander row survives Dad's deactivation untouched",
    bystanderSurvives.some((d) => d.token === 'tok-mom-E-bystander'), 'true');
  await unregisterDeviceToken(pool, momP, 'tok-mom-E-bystander');

  const survivors = await deviceTokensFor(pool, { userId: DAD });
  check('E deactivation', "Dad's pre-deactivation device row is really gone",
    survivors.length, 0);

  let deniedCode = null;
  try {
    await registerDeviceToken(pool, dadP, 'ios', 'tok-dad-E-after');
  } catch (e) { deniedCode = e.code; }
  check('E deactivation', 'a NEW registration attempt is refused, not silently accepted',
    deniedCode, 'account_deactivated');

  const afterAttempt = await deviceTokensFor(pool, { userId: DAD });
  check('E deactivation', 'the refused attempt created no row', afterAttempt.length, 0);

  // The gate is per-user, not a global kill switch — a DIFFERENT, still-active
  // guardian (Mom) is completely unaffected by Dad's deactivation.
  const momId = await registerDeviceToken(pool, momP, 'android', 'tok-mom-E');
  check('E deactivation', 'a still-active guardian (Mom) can still register', typeof momId, 'string');
  await unregisterDeviceToken(pool, momP, 'tok-mom-E');

  // The gate only runs for non-child principals (registerDeviceToken's own
  // header: children have no deactivated_at concept) — an unrelated child's
  // own registration is untouched by Dad's deactivation.
  const ivyId = await registerDeviceToken(pool, ivyP, 'android', 'tok-ivy-E');
  check('E deactivation', "a child's (Ivy) own registration is unaffected", typeof ivyId, 'string');
  await unregisterDeviceToken(pool, ivyP, 'tok-ivy-E');
}

// ===========================================================================
// F · §8.11.4 channel column (0015/v0.49.11) — real INSERT/UPSERT/SELECT,
// not just the CHECK constraint's shape (that's covered structurally by
// migration application itself; this proves the actual read/write path).
//
// Uses Mom, not Dad — section E above deactivates Dad's account, and this
// section needs a still-active guardian, not a re-test of deactivation.
// ===========================================================================
{
  const id = await registerDeviceToken(pool, momP, 'android', 'tok-mom-F', 'android_amazon');
  const [row] = await deviceTokensFor(pool, { userId: MOM });
  check('F channel column', 'a channel passed at registration is really stored',
    row?.channel, 'android_amazon');

  // Re-registering the SAME token WITHOUT a channel must not erase the one
  // already on file (pool.ts's own COALESCE fix, proven end to end here).
  const id2 = await registerDeviceToken(pool, momP, 'android', 'tok-mom-F');
  check('F channel column', 're-registration reuses the same row (still an upsert)', id2, id);
  const [row2] = await deviceTokensFor(pool, { userId: MOM });
  check('F channel column', 'a channel-less re-registration does NOT clobber the known channel',
    row2?.channel, 'android_amazon');

  // A genuinely new channel value DOES overwrite — this is an update, not a
  // one-way ratchet.
  await registerDeviceToken(pool, momP, 'android', 'tok-mom-F', 'android_bare');
  const [row3] = await deviceTokensFor(pool, { userId: MOM });
  check('F channel column', 'a real new channel value does overwrite the old one',
    row3?.channel, 'android_bare');

  await unregisterDeviceToken(pool, momP, 'tok-mom-F');

  // No channel supplied at all -> stored as NULL, never guessed.
  const id4 = await registerDeviceToken(pool, momP, 'ios', 'tok-mom-F-ios');
  const [row4] = (await deviceTokensFor(pool, { userId: MOM })).filter(r => r.id === id4);
  check('F channel column', 'omitting channel entirely stores NULL, not a guessed default',
    row4?.channel, 'null');
  await unregisterDeviceToken(pool, momP, 'tok-mom-F-ios');
}

await admin.query(`DELETE FROM device_token WHERE owner_user_id IN ($1,$2) OR owner_child_id IN ($3,$4)`,
  [DAD, MOM, IVY, ELI]);
await admin.query(`DELETE FROM child WHERE id IN ($1,$2)`, [IVY, ELI]);
await admin.query(`DELETE FROM app_user WHERE id IN ($1,$2)`, [DAD, MOM]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
