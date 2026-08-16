/**
 * packages/db — account deletion: real Postgres, real RLS, real server.
 * MASTERFILE §2.10, §2.11, §9.8, prohibition P8.
 * client/lib/deletion_screen.dart's `whatDeletionKeeps` / `whatDeletionRemoves`
 * constants are the spec; db/migrations/0011_account_deletion.sql and
 * packages/db/src/pool.ts's deactivateAccount() are what make it real. This
 * suite is the only thing that proves that transaction actually keeps what
 * it says it keeps and removes what it says it removes.
 *
 * Same posture as pool.test.mjs / custody_order.test.mjs, which this suite
 * mirrors exactly: requires a real Postgres with 0008 applied, DATABASE_URL
 * MUST be a NOSUPERUSER NOBYPASSRLS role (db/DEPLOYMENT.md's app_owner) — a
 * probe of RLS run as `postgres` measures nothing — and it is NOT part of
 * `npm test`'s default JS-suite chain for the same reason those two aren't.
 *
 * Four sections, matching the task's four required proofs:
 *   A. a delivered message and its message_log entry survive untouched
 *   B. queued/undelivered content (delivery_intent, credentials) is removed
 *   C. RLS — a guardian cannot deactivate someone else's account
 *   D. a deactivated user's subsequent login attempt fails, over a REAL
 *      HTTP server (server/index.mjs spawned as a real child process) —
 *      the one real login/session-issuing path this codebase has today.
 *      Honest gap, stated once here rather than re-argued at every site:
 *      no PIN/WebAuthn login endpoint exists ANYWHERE in this codebase yet
 *      (packages/auth/src/auth.ts's own header says so), so "PIN/WebAuthn
 *      login fails" cannot be tested against a route that does not exist.
 *      What CAN be proven, and is proven twice over: (1) this section D —
 *      the one real login path server/index.mjs has DOES refuse a
 *      deactivated account, and (2) section B — deactivateAccount() removes
 *      every pin_credential/webauthn_credential row for that user, so the
 *      moment a real PIN/WebAuthn login endpoint is built, it has nothing
 *      left to verify a deactivated user's credential against either.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createPool, withSession, deactivateAccount } from '../src/pool.mjs';

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

// Fresh, random UUIDs every run — deliberately, not merely for hygiene.
// message_log.author_id and delivery_intent.sender_id both reference
// app_user with no cascading delete, and message_log itself is triggered
// append-only (P8, 0006_court_tier.sql's reject_log_mutation() — fires for
// EVERY role, including postgres superuser, there is no bypass). Once this
// suite inserts a message_log row for a child/author pair, NEITHER the
// message_log row NOR the child row NOR that author's app_user row can ever
// be deleted again by anyone, including this suite's own teardown. Reusing
// fixed ids across runs would therefore either collide (message_log's own
// (child_id, seq) PRIMARY KEY / hash-chain trigger) or silently accumulate
// undeletable rows tied to a name every future run also tries to claim.
// Random ids sidestep both: harmless, permanent residue in this suite's own
// disposable database, never colliding, and thematically the correct shape
// for a table whose entire point is that it cannot be cleaned up.
const CHILD          = randomUUID();
const GUARDIAN_A      = randomUUID(); // the one deleting
const GUARDIAN_B      = randomUUID(); // the co-parent / attacker
const GUARDIAN_C      = randomUUID(); // RLS positive-control only
const LOGIN_GUARDIAN  = randomUUID(); // section D, real server
const LOGIN_CONTROL   = randomUUID(); // section D, never deactivated

const GENESIS = '0'.repeat(64);
const fakeHash = (n) => n.toString(16).padStart(64, '0');

async function insertFixtures() {
  await admin.query('BEGIN');
  await admin.query(
    `INSERT INTO app_user (id, display_name, home_tz) VALUES
       ($1,'Guardian A (deleting)','America/Chicago'),
       ($2,'Guardian B (co-parent)','America/New_York'),
       ($3,'Guardian C (rls control)','America/Denver'),
       ($4,'Login Guardian','America/Chicago'),
       ($5,'Login Control','America/Chicago')`,
    [GUARDIAN_A, GUARDIAN_B, GUARDIAN_C, LOGIN_GUARDIAN, LOGIN_CONTROL]);
  await admin.query(
    `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
       ($1,'Ivy','2016-04-02','America/New_York')`, [CHILD]);
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
       ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
       ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
    [CHILD, GUARDIAN_A, GUARDIAN_B]);

  // §2.10/P8 — the parent-to-parent log. A real (though not cryptographically
  // meaningful) genesis-linked entry authored by GUARDIAN_A.
  await admin.query(
    `INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
     VALUES ($1, 0, $2, 'exchange confirmed for Friday', $3, $4)`,
    [CHILD, GUARDIAN_A, GENESIS, fakeHash(1)]);

  // §9.8 — her preserved archive: a media_artifact authored by GUARDIAN_A but
  // owned by the CHILD, and a child_journal_entry that belongs to no guardian
  // at all (P7 — journal has no author column, ever).
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, captured_at, captured_tz, preserved, preserved_by, preserved_at)
     VALUES (uuid_generate_v4(), $1, $2, 'drawing', 'archive/goodnight.jpg', now(), 'America/Chicago',
             true, $2, now())`,
    [CHILD, GUARDIAN_A]);
  await admin.query(
    `INSERT INTO child_journal_entry (child_id, body) VALUES ($1, 'a private thought')`, [CHILD]);

  // §2.10 — delivered content survives; queued/banked content does not.
  // Two DELIVERED-class rows (delivered, opened) and four NOT-YET-DELIVERED
  // rows covering every other state in the real enum
  // (db/migrations/0001_phase0_init.sql's own CHECK).
  const di = async (state) => admin.query(
    `INSERT INTO delivery_intent
       (id, child_id, sender_id, payload_kind, payload_ref, policy, state, expires_at)
     VALUES (uuid_generate_v4(), $1, $2, 'video_msg', uuid_generate_v4(), 'immediate', $3,
             now() + interval '30 days')`,
    [CHILD, GUARDIAN_A, state]);
  await di('delivered');
  await di('opened');
  await di('pending');
  await di('ready');
  await di('expired');
  await di('revoked');

  await admin.query(
    `INSERT INTO pin_credential (user_id, pin_hash) VALUES
       ($1, 'scrypt$32768$8$1$c2FsdA$a2V5')`, [GUARDIAN_A]);
  await admin.query(
    `INSERT INTO webauthn_credential (credential_id, user_id, public_key_pem) VALUES
       ($1, $2, 'not-a-real-pem')`, [`cred-${GUARDIAN_A}`, GUARDIAN_A]);
  await admin.query(
    `INSERT INTO auth_challenge (user_id, challenge, purpose) VALUES ($1, $2, 'login')`,
    [GUARDIAN_A, `chal-${GUARDIAN_A}`]);

  await admin.query('COMMIT');
}

await insertFixtures();

// ===========================================================================
// C · RLS FIRST — before anything is actually deactivated, prove a guardian
// cannot touch another guardian's row, and that the policy isn't just
// blocking everything (a guardian CAN touch their own).
// ===========================================================================
{
  const attack = await withSession(pool, { roleName: 'guardian', userId: GUARDIAN_B, childId: null },
    async (q) => q(`UPDATE app_user SET deactivated_at = now() WHERE id = $1 RETURNING id`,
      [GUARDIAN_A]));
  check('C rls', 'GUARDIAN_B cannot deactivate GUARDIAN_A via a direct UPDATE (0 rows)',
    attack.length, 0);

  const stillLive = await admin.query(
    `SELECT deactivated_at FROM app_user WHERE id = $1`, [GUARDIAN_A]);
  check('C rls', 'GUARDIAN_A is untouched by the attempted attack',
    stillLive.rows[0].deactivated_at, 'null');

  const self = await withSession(pool, { roleName: 'guardian', userId: GUARDIAN_C, childId: null },
    async (q) => q(`UPDATE app_user SET deactivated_at = now() WHERE id = $1 RETURNING id`,
      [GUARDIAN_C]));
  check('C rls', 'positive control — GUARDIAN_C CAN deactivate their OWN row (1 row)',
    self.length, 1);

  // Also exercise deactivateAccount() itself end-to-end with a mismatched
  // caller: the function has no separate "target" parameter — the only way
  // to call it AT ALL is with the id that becomes both app.user_id and the
  // WHERE target, exactly mirroring how server/routes.mjs's handler only
  // ever passes c.principal.userId. Simulating "someone else" therefore
  // means the raw-SQL attack above, which is the actual attack surface (a
  // hypothetical future caller bypassing deactivateAccount() and hand-
  // rolling the UPDATE) — already covered. Nothing further to add here.
}

// ===========================================================================
// A + B · deactivateAccount() — the real transaction, real assertions.
// ===========================================================================
{
  const result = await deactivateAccount(pool, GUARDIAN_A);
  check('AB deactivate', 'cancels exactly the 4 non-delivered delivery_intent rows',
    result.cancelledDeliveryIntents, 4);
  check('AB deactivate', 'removes the 1 pin_credential row', result.removedPinCredentials, 1);
  check('AB deactivate', 'removes the 1 webauthn_credential row', result.removedWebauthnCredentials, 1);
  check('AB deactivate', 'removes the 1 webauthn_challenge row', result.removedWebauthnChallenges, 1);

  const user = await admin.query(`SELECT deactivated_at FROM app_user WHERE id = $1`, [GUARDIAN_A]);
  check('AB deactivate', 'the app_user ROW still exists (never deleted)', user.rows.length, 1);
  check('AB deactivate', 'deactivated_at is now set',
    user.rows[0].deactivated_at !== null, 'true');

  // A · what survives, byte for byte.
  const log = await admin.query(
    `SELECT seq, author_id, body, prev_hash, hash FROM message_log WHERE child_id = $1`, [CHILD]);
  check('A survives', 'the message_log entry still exists', log.rows.length, 1);
  check('A survives', 'authored by GUARDIAN_A, untouched', log.rows[0].author_id, GUARDIAN_A);
  check('A survives', 'body untouched', log.rows[0].body, 'exchange confirmed for Friday');
  check('A survives', 'hash chain untouched', log.rows[0].hash, fakeHash(1));

  const delivered = await admin.query(
    `SELECT state FROM delivery_intent WHERE child_id = $1 AND state IN ('delivered','opened')
      ORDER BY state`, [CHILD]);
  check('A survives', 'both delivered-class delivery_intent rows survive', delivered.rows.length, 2);

  const archive = await admin.query(
    `SELECT id FROM media_artifact WHERE child_id = $1`, [CHILD]);
  check('A survives', "her preserved archive (media_artifact) survives", archive.rows.length, 1);

  const journal = await admin.query(
    `SELECT id FROM child_journal_entry WHERE child_id = $1`, [CHILD]);
  check('A survives', 'her journal entry survives (P7 — no author to even delete by)',
    journal.rows.length, 1);

  // B · what goes.
  const gone = await admin.query(
    `SELECT state FROM delivery_intent WHERE child_id = $1 AND sender_id = $2
      AND state NOT IN ('delivered','opened')`, [CHILD, GUARDIAN_A]);
  check('B removed', 'every non-delivered delivery_intent row is actually gone', gone.rows.length, 0);

  const pins = await admin.query(`SELECT user_id FROM pin_credential WHERE user_id = $1`, [GUARDIAN_A]);
  check('B removed', 'pin_credential is gone', pins.rows.length, 0);
  const wa = await admin.query(`SELECT credential_id FROM webauthn_credential WHERE user_id = $1`,
    [GUARDIAN_A]);
  check('B removed', 'webauthn_credential is gone', wa.rows.length, 0);
  const ch = await admin.query(`SELECT challenge FROM auth_challenge WHERE user_id = $1`,
    [GUARDIAN_A]);
  check('B removed', 'auth_challenge is gone', ch.rows.length, 0);

  // Idempotency — a double-tap on the confirm button must fail loudly, not
  // silently "succeed" a second time or double-count.
  let code = null;
  try { await deactivateAccount(pool, GUARDIAN_A); }
  catch (e) { code = e.code; }
  check('AB deactivate', 'a second call is refused, not silently repeated',
    code, 'already_deactivated');

  let notFoundCode = null;
  try { await deactivateAccount(pool, '00000000-0000-0000-0000-000000000000'); }
  catch (e) { notFoundCode = e.code; }
  check('AB deactivate', 'an unknown userId is refused, not silently a no-op',
    notFoundCode, 'account_not_found');
}

// ===========================================================================
// D · a deactivated user's subsequent LOGIN attempt fails — over a REAL
// HTTP server, spawned as a real child process running the real
// server/index.mjs + server/routes.mjs against this same database.
// ===========================================================================
{
  const here = dirname(fileURLToPath(import.meta.url));
  const serverEntry = join(here, '..', '..', '..', 'server', 'index.mjs');
  // Port derived from this process's own pid to reduce collision with any
  // other suite/agent's server bound to a fixed port on the same machine.
  const port = 21000 + (process.pid % 4000);
  const secret = 'deletion-test-session-secret-not-for-production-use';

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
  check('D real server', 'server/index.mjs actually boots against this database', booted, 'true');

  if (booted) {
    const base = `http://127.0.0.1:${port}`;
    const postJson = async (path, body) => {
      const res = await fetch(`${base}${path}`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body ?? {}),
      });
      return { status: res.status, body: await res.json() };
    };

    const control = await postJson('/v1/auth/dev-login', { userId: LOGIN_CONTROL });
    check('D real server', 'a NEVER-deactivated user can dev-login (positive control)',
      control.status, 200);

    const before = await postJson('/v1/auth/dev-login', { userId: LOGIN_GUARDIAN });
    check('D real server', 'LOGIN_GUARDIAN can log in before deletion', before.status, 200);

    const del = await deactivateAccount(pool, LOGIN_GUARDIAN);
    check('D real server', 'deletion via the real function succeeds', del.userId, LOGIN_GUARDIAN);

    const after = await postJson('/v1/auth/dev-login', { userId: LOGIN_GUARDIAN });
    check('D real server', 'the SAME user\'s next login attempt is refused', after.status, 403);
    check('D real server', 'refused with the real reason', after.body.error, 'account_deactivated');

    // The one honest limitation this pass does not close: sessions are
    // signed, not stored (auth.ts's own header) — a token issued by the
    // BEFORE call above remains cryptographically valid until its own TTL,
    // even though the account behind it is now deactivated. Documented, not
    // silently assumed: assert it explicitly rather than leave it untested.
    const meRes = await fetch(`${base}/v1/me`,
      { headers: { authorization: `Bearer ${before.body.token}` } });
    check('D real server',
      'KNOWN GAP, asserted not assumed — a pre-deletion token still authenticates ' +
      'until its own 1h TTL (no server-side session store exists to revoke early)',
      meRes.status, 200);
  }

  child.kill();
  await new Promise((r) => setTimeout(r, 200));
}

// ---------------------------------------------------------------------------
// No teardown DELETE — see the fixture-id comment above: message_log rows
// (and the child/app_user rows they now reference) are permanently
// undeletable by design, in this suite's own database same as production.
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
