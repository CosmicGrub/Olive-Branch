/**
 * Unauthenticated /v1/auth/* hardening (audit P-08), the parts that need a
 * real Postgres. (The rate-limit/body-cap/uniform-malformed-id cases that do
 * not need one are in server/test/http_hardening.test.mjs.)
 *
 *   A. purgeExpiredChallenges(): removes exactly the rows that can never be
 *      used again (consumed or expired past the grace), keeps live ones, is
 *      idempotent, and never breaks a ceremony in flight.
 *   B. The scheduler's `purge-challenges` job does it through the real runner.
 *   C. The login-challenge endpoint reveals nothing about which userIds are
 *      real: an existing user and an unknown uuid get the SAME status, body
 *      shape and challenge format; only the real one is stored; the follow-up
 *      verify for both is the SAME 401 challenge_expired.
 *   D. The endpoint cannot be used to fill the table: per-identifier rate
 *      limiting caps the rows one identifier can mint.
 */
import pg from 'pg';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createPool, purgeExpiredChallenges, createChallenge, consumeChallenge, CHALLENGE_TTL_MS }
  from '../src/pool.mjs';
import { runNamedJob } from '../../../tools/scheduler.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const USER = '11111111-1111-4111-9111-0000000000d1';
const USER2 = '22222222-2222-4222-9222-0000000000d1';
const GHOST = '99999999-9999-4999-9999-0000000000d1'; // never inserted
await admin.query(`DELETE FROM auth_challenge WHERE user_id = $1`, [USER]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [USER]);
await admin.query(`DELETE FROM auth_challenge WHERE user_id = $1`, [USER2]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [USER2]);
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Challenge Test','UTC'), ($2,'Flood Test','UTC')`, [USER, USER2]);

const count = async () => (await admin.query(
  `SELECT count(*)::int AS n FROM auth_challenge WHERE user_id = $1`, [USER])).rows[0].n;
const seed = (label, ageMs, consumed) => admin.query(
  `INSERT INTO auth_challenge (user_id, challenge, purpose, issued_at, consumed_at)
   VALUES ($1, $2, 'login', now() - ($3 || ' milliseconds')::interval,
           CASE WHEN $4::boolean THEN now() ELSE NULL END)`,
  [USER, label, ageMs, consumed]);

try {
  // ---- A · purge --------------------------------------------------------------
  {
    const MIN = 60_000, H = 60 * MIN;
    await seed('fresh-unconsumed', 30_000, false);          // live: must survive
    await seed('fresh-consumed', 30_000, true);             // spent but recent: within grace
    await seed('expired-10min', 10 * MIN, false);           // past TTL, inside the 1 h grace
    await seed('old-3h-unconsumed', 3 * H, false);          // dead
    await seed('old-3h-consumed', 3 * H, true);             // dead
    await seed('old-2d', 48 * H, false);                    // dead
    check('A purge', 'setup: 6 challenge rows of mixed age/state', await count(), 6);

    const n = await purgeExpiredChallenges(pool);
    check('A purge', 'the default purge removes exactly the 3 rows older than TTL + 1 h grace', n, 3);
    const left = (await admin.query(`SELECT challenge FROM auth_challenge WHERE user_id = $1 ORDER BY challenge`, [USER]))
      .rows.map((r) => r.challenge).join(',');
    check('A purge', 'and keeps the live one, the recently-spent one and the just-expired one',
      left, 'expired-10min,fresh-consumed,fresh-unconsumed');
    check('A purge', 'a second run is a no-op (idempotent)', await purgeExpiredChallenges(pool), 0);

    const strict = await purgeExpiredChallenges(pool, 0);
    check('A purge', 'with no grace, anything past the 5-minute TTL goes (the 10-minute row)', strict, 1);
    check('A purge', 'the TTL constant the purge is derived from is the 5 minutes consumeChallenge enforces',
      CHALLENGE_TTL_MS, 300_000);

    // A ceremony in flight survives a purge and still verifies.
    const live = await createChallenge(pool, USER, 'login');
    await purgeExpiredChallenges(pool, 0);
    check('A purge', 'a challenge issued just before a purge is still consumable afterwards',
      await consumeChallenge(pool, USER, 'login', live), true);
    check('A purge', '...and is single-use as always', await consumeChallenge(pool, USER, 'login', live), false);

  }

  // ---- B · the scheduler job ---------------------------------------------------------
  {
    await admin.query(`DELETE FROM auth_challenge WHERE user_id = $1`, [USER]);
    await seed('job-dead-1', 5 * 60 * 60_000, false);
    await seed('job-dead-2', 9 * 60 * 60_000, true);
    await seed('job-live', 10_000, false);
    const r = await runNamedJob(pool, DATABASE_URL, 'purge-challenges');
    check('B scheduler job', 'runNamedJob(purge-challenges) succeeds', `${r.ok}/${r.skipped}`, 'true/false');
    check('B scheduler job', 'and removed the two dead rows, kept the live one', await count(), 1);
  }

  // ---- C/D · through the REAL server -------------------------------------------------------
  {
    const here = dirname(fileURLToPath(import.meta.url));
    const serverEntry = join(here, '..', '..', '..', 'server', 'index.mjs');
    const port = 27000 + (process.pid % 3000);
    const child = spawn(process.execPath, [serverEntry], {
      env: { ...process.env, DATABASE_URL, SESSION_SECRET: 'auth-hardening-secret-not-for-prod-use',
        PORT: String(port), DEV_LOGIN: '0', NODE_ENV: 'development' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let out = '';
    child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { out += d; });
    const deadline = Date.now() + 60_000;
    while (!out.includes('listening on') && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
    const base = `http://127.0.0.1:${port}`;
    const post = (path, body) => fetch(base + path, { method: 'POST',
      headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    try {
      await admin.query(`DELETE FROM auth_challenge WHERE user_id = $1`, [USER]);
      const real = await post('/v1/auth/webauthn/login/challenge', { userId: USER });
      const ghost = await post('/v1/auth/webauthn/login/challenge', { userId: GHOST });
      const rj = await real.json(), gj = await ghost.json();
      check('C no account oracle', 'a real user and an unknown uuid get the SAME status', `${real.status}/${ghost.status}`, '200/200');
      check('C no account oracle', '...the same body keys', Object.keys(rj).join(','), Object.keys(gj).join(','));
      check('C no account oracle', '...and the same challenge format (43-char base64url) and rpId',
        `${rj.challenge.length}/${gj.challenge.length}/${rj.rpId === gj.rpId}/${/^[A-Za-z0-9_-]{43}$/.test(gj.challenge)}`,
        '43/43/true/true');
      check('C no account oracle', 'the unknown user\'s decoy challenge is NOT stored (nothing to fill the table with)',
        (await admin.query(`SELECT count(*)::int AS n FROM auth_challenge WHERE challenge = $1`, [gj.challenge])).rows[0].n, 0);
      check('C no account oracle', 'the real user\'s challenge IS stored (the ceremony still works)',
        (await admin.query(`SELECT count(*)::int AS n FROM auth_challenge WHERE challenge = $1`, [rj.challenge])).rows[0].n, 1);

      const verify = (userId, challenge) => post('/v1/auth/webauthn/login/verify', {
        userId, credentialId: 'x', authenticatorData: 'AAAA', signature: 'AAAA',
        clientDataJSON: Buffer.from(JSON.stringify({ challenge })).toString('base64url'),
      });
      const vGhost = await verify(GHOST, gj.challenge);
      const vReal = await verify(USER, 'a-challenge-that-was-never-issued');
      const bGhost = await vGhost.json(), bReal = await vReal.json();
      check('C no account oracle', 'verify for an unknown user and for a real user with a wrong challenge are the SAME 401 + error',
        `${vGhost.status}/${bGhost.error}`, `${vReal.status}/${bReal.error}`);
      check('C no account oracle', '...and that shared answer is challenge_expired', bReal.error, 'challenge_expired');

      // D · filling the table through one identifier is capped.
      const statuses = [];
      for (let i = 0; i < 14; i++) statuses.push((await post('/v1/auth/webauthn/login/challenge', { userId: USER2 })).status);
      const ok = statuses.filter((s) => s === 200).length, limited = statuses.filter((s) => s === 429).length;
      check('D flood bound', '14 rapid challenge requests for ONE user: the per-identifier bucket (10) stops the rest',
        `${ok}/${limited}`, '10/4');
      check('D flood bound', 'so one identifier can mint at most 10 rows, not unbounded',
        (await admin.query(`SELECT count(*)::int AS n FROM auth_challenge WHERE user_id = $1`, [USER2])).rows[0].n, 10);
    } finally {
      child.kill();
      await new Promise((r) => setTimeout(r, 150));
    }
  }
} finally {
  await admin.query(`DELETE FROM auth_challenge WHERE user_id = $1`, [USER]);
  await admin.query(`DELETE FROM auth_challenge WHERE user_id = $1`, [USER2]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[USER, USER2]]);
  await admin.end();
  await pool.end();
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
