/**
 * server/test/security_follow_ups_route.test.mjs — the database-backed half of the
 * security follow-ups to S-B3 (MASTERFILE section 7.12), driven through the REAL
 * Api + registerRoutes wiring against REAL Postgres and REAL row-level security.
 *
 *   A  FIRST-PIN passkey check: a session on an account that holds a passkey but no
 *      PIN must present a fresh, single-use, purpose-bound, user-verified assertion
 *      from ITS OWN credential before it can set the first PIN. (Closes: stolen
 *      session sets the first PIN, then adds a passkey of its own with it.)
 *   B  the challenge route (who may ask, and when there is nothing to assert)
 *   C  the bootstrap path is unchanged (no passkey, no PIN: first PIN needs no proof)
 *   D  the exports and invites still need the PIN (header / body), as shipped in #158
 */
import pg from 'pg';
import { randomBytes, createHash, createSign, generateKeyPairSync } from 'node:crypto';
import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { issueSession, hashPin } from '../../packages/auth/src/auth.mjs';
import { registerRoutes, RP_ID, RP_ORIGIN } from '../routes.mjs';

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

const CH = 'e1000000-0000-4000-8000-00000000000a';
const G_PK = 'e2000000-0000-4000-8000-000000000001';   // a passkey, no PIN (the dangerous state)
const G_PK2 = 'e2000000-0000-4000-8000-000000000002';  // a second such account (its key must not work for G_PK)
const G_NEW = 'e2000000-0000-4000-8000-000000000003';  // nothing yet (invite bootstrap)
const G_PIN = 'e2000000-0000-4000-8000-000000000004';  // has a PIN (exports / invites)
const USERS = [G_PK, G_PK2, G_NEW, G_PIN];
const PIN = '246813';

async function cleanup() {
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM message_log WHERE child_id = $1`, [CH]);
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM export_record WHERE child_id = $1`, [CH]);
  await admin.query(`DELETE FROM guardian_invite WHERE invited_by = ANY($1::uuid[])`, [USERS]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CH]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CH]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [USERS]);
}
await cleanup();
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Pk','America/Chicago'), ($2,'Pk2','America/Chicago'), ($3,'New','America/Chicago'), ($4,'Pin','America/Chicago')`, USERS);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'Ivy','2016-04-02','America/New_York')`, [CH]);
const open = `tstzrange(now() - interval '1 year', null)`;
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,'guardian','{}',${open})`, [CH, G_PIN]);
await admin.query(`INSERT INTO pin_credential (user_id, pin_hash) VALUES ($1, $2)`, [G_PIN, hashPin(PIN)]);

const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-sec3-route-'));
const SECRET = randomBytes(32);
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, new FilesystemStorage(storageRoot), {});
const NOW = Date.now();
const tok = (userId) => issueSession(SECRET, { userId, roleName: 'guardian', childId: null, escalated: false }, NOW);
const kid = issueSession(SECRET, { userId: null, roleName: 'child', childId: CH, escalated: false }, NOW);
const call = (method, p, t, body, headers = {}) => api.handle(method, p,
  { ...(t ? { authorization: `Bearer ${t}` } : {}), ...headers }, body === undefined ? '' : JSON.stringify(body));

// ---- a tiny software authenticator (ES256) ---------------------------------
const cborUint = (n) => Buffer.from([n]);
const cborNegint = (n) => Buffer.from([0x20 | (n - 1)]);
const cborBytes = (buf) => (buf.length < 24
  ? Buffer.concat([Buffer.from([0x40 | buf.length]), buf]) : Buffer.concat([Buffer.from([0x58, buf.length]), buf]));
const cborText = (s) => { const b = Buffer.from(s, 'utf8');
  return b.length < 24 ? Buffer.concat([Buffer.from([0x60 | b.length]), b]) : Buffer.concat([Buffer.from([0x78, b.length]), b]); };
const cborMap = (n) => Buffer.from([0xa0 | n]);
const rpIdHash = createHash('sha256').update(RP_ID, 'utf8').digest();
function makeAuthenticator(rawId) {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const jwk = publicKey.export({ format: 'jwk' });
  const cose = Buffer.concat([cborMap(5), cborUint(1), cborUint(2), cborUint(3), cborNegint(7), cborNegint(1), cborUint(1),
    cborNegint(2), cborBytes(Buffer.from(jwk.x, 'base64url')), cborNegint(3), cborBytes(Buffer.from(jwk.y, 'base64url'))]);
  const idBuf = Buffer.from(rawId, 'utf8');
  const idLen = Buffer.alloc(2); idLen.writeUInt16BE(idBuf.length);
  const authData = Buffer.concat([rpIdHash, Buffer.from([0x45]), Buffer.alloc(4), Buffer.alloc(16), idLen, idBuf, cose]);
  const attestationObject = Buffer.concat([cborMap(3), cborText('fmt'), cborText('none'), cborText('attStmt'), cborMap(0),
    cborText('authData'), cborBytes(authData)]).toString('base64url');
  let counter = 0;
  return {
    credentialId: idBuf.toString('base64url'), attestationObject,
    /** a get() assertion over `challenge`; flags 0x05 = UP|UV, 0x01 = UP only */
    assert(challenge, { flags = 0x05, type = 'webauthn.get', badSig = false } = {}) {
      counter += 1;
      const cd = Buffer.from(JSON.stringify({ type, challenge, origin: RP_ORIGIN }));
      const cnt = Buffer.alloc(4); cnt.writeUInt32BE(counter);
      const ad = Buffer.concat([rpIdHash, Buffer.from([flags]), cnt]);
      const s = createSign('sha256'); s.update(Buffer.concat([ad, createHash('sha256').update(cd).digest()])); s.end();
      const sig = s.sign(privateKey);
      if (badSig) sig[sig.length - 1] ^= 0xff;
      return { credentialId: idBuf.toString('base64url'), clientDataJSON: cd.toString('base64url'),
               authenticatorData: ad.toString('base64url'), signature: sig.toString('base64url') };
    },
  };
}
async function registerPasskey(userToken, auth) {
  const chal = await call('POST', '/v1/auth/webauthn/register/challenge', userToken);
  const cd = Buffer.from(JSON.stringify({ type: 'webauthn.create', challenge: chal.body.challenge, origin: RP_ORIGIN })).toString('base64url');
  return call('POST', '/v1/auth/webauthn/register/verify', userToken,
    { clientDataJSON: cd, attestationObject: auth.attestationObject });
}
const hasPin = async (u) => (await admin.query(`SELECT count(*)::int AS n FROM pin_credential WHERE user_id=$1`, [u])).rows[0].n;
const passkeys = async (u) => (await admin.query(`SELECT count(*)::int AS n FROM webauthn_credential WHERE user_id=$1`, [u])).rows[0].n;
const T = { PK: tok(G_PK), PK2: tok(G_PK2), NEW: tok(G_NEW), PIN: tok(G_PIN) };
const stepupChallenge = async (t) => (await call('POST', '/v1/me/pin/passkey-challenge', t)).body.challenge;

// ===========================================================================
// A · the first PIN on an account that already holds a passkey
// ===========================================================================
const authPk = makeAuthenticator('pk-key-1');
const authPk2 = makeAuthenticator('pk2-key-1');
check('A first PIN', 'setup: the passkey-only account registers its first passkey (bootstrap, no PIN needed)', (await registerPasskey(T.PK, authPk)).status, 200);
check('A first PIN', 'setup: a second passkey-only account does the same', (await registerPasskey(T.PK2, authPk2)).status, 200);

{
  const noProof = await call('POST', '/v1/me/pin', T.PK, { pin: '135792' });
  check('A first PIN', 'a bare session on a passkey-only account cannot set the first PIN (403 passkey_assertion_required)',
    `${noProof.status}/${noProof.body.error}`, '403/passkey_assertion_required');
  check('A first PIN', 'and no PIN was stored', await hasPin(G_PK), 0);

  // the original attack, end to end: set a PIN to then add a passkey with it
  const attackAdd = await call('POST', '/v1/auth/webauthn/register/verify', T.PK, { pin: '135792', clientDataJSON: 'x', attestationObject: 'y' });
  check('A first PIN', 'the attack chain is dead: with no PIN set, adding a passkey is refused (403 pin_not_set)',
    `${attackAdd.status}/${attackAdd.body.error}`, '403/pin_not_set');

  const bad = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: 'nope' });
  check('A first PIN', 'a non-object assertion is the same 403 passkey_assertion_required', `${bad.status}/${bad.body.error}`, '403/passkey_assertion_required');
  const malformed = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: { credentialId: 1 } });
  check('A first PIN', 'a malformed assertion is 400 bad_request', `${malformed.status}/${malformed.body.error}`, '400/bad_request');

  // wrong challenge purpose: a registration challenge cannot be replayed as step-up proof
  const regChal = (await call('POST', '/v1/auth/webauthn/register/challenge', T.PK)).body.challenge;
  const wrongPurpose = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(regChal) });
  check('A first PIN', 'a challenge minted for another purpose (register) is refused (403 passkey_assertion_failed)',
    `${wrongPurpose.status}/${wrongPurpose.body.error}`, '403/passkey_assertion_failed');

  // a made-up challenge
  const madeUp = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(randomBytes(32).toString('base64url')) });
  check('A first PIN', 'a challenge the server never issued is refused', `${madeUp.status}/${madeUp.body.error}`, '403/passkey_assertion_failed');

  // a good challenge but a bad signature
  let c = await stepupChallenge(T.PK);
  const badSig = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(c, { badSig: true }) });
  check('A first PIN', 'a corrupted signature is refused', `${badSig.status}/${badSig.body.error}`, '403/passkey_assertion_failed');
  const replayDead = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(c) });
  check('A first PIN', 'and a failed attempt SPENDS the challenge: the same challenge cannot be retried with a good signature',
    `${replayDead.status}/${replayDead.body.error}`, '403/passkey_assertion_failed');

  // user verification clear
  c = await stepupChallenge(T.PK);
  const noUv = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(c, { flags: 0x01 }) });
  check('A first PIN', 'an assertion without user verification (UV flag clear) is refused', `${noUv.status}/${noUv.body.error}`, '403/passkey_assertion_failed');

  // a registration-typed client data
  c = await stepupChallenge(T.PK);
  const wrongType = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(c, { type: 'webauthn.create' }) });
  check('A first PIN', 'client data of the wrong type is refused', `${wrongType.status}/${wrongType.body.error}`, '403/passkey_assertion_failed');

  // somebody ELSE's real passkey, over a genuine challenge for this session
  c = await stepupChallenge(T.PK);
  const foreign = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk2.assert(c) });
  check('A first PIN', "another account's real passkey cannot unlock this account's first PIN (403)", `${foreign.status}/${foreign.body.error}`, '403/passkey_assertion_failed');

  check('A first PIN', 'after every refusal there is still no PIN', await hasPin(G_PK), 0);

  // the real thing
  c = await stepupChallenge(T.PK);
  const good = await call('POST', '/v1/me/pin', T.PK, { pin: '135792', assertion: authPk.assert(c) });
  check('A first PIN', 'a fresh user-verified assertion from its own passkey sets the first PIN (200)', `${good.status}/${good.body.ok}`, '200/true');
  check('A first PIN', 'and the PIN is stored', await hasPin(G_PK), 1);

  // a PIN now exists, so the ordinary rule (prove the CURRENT pin) applies, not the assertion
  const again = await call('POST', '/v1/me/pin', T.PK, { pin: '864209', assertion: authPk.assert(await stepupChallenge(T.PK)) });
  check('A first PIN', 'once a PIN exists, a new one needs the CURRENT pin: an assertion alone is not enough (403 current_pin_required)',
    `${again.status}/${again.body.error}`, '403/current_pin_required');
  const withCurrent = await call('POST', '/v1/me/pin', T.PK, { pin: '864209', currentPin: '135792' });
  check('A first PIN', 'with the current PIN the change goes through (200)', withCurrent.status, 200);
}

// ===========================================================================
// B · the challenge route
// ===========================================================================
{
  const none = await call('POST', '/v1/me/pin/passkey-challenge', T.NEW);
  check('B challenge', 'an account with no passkey has nothing to assert: 409 no_passkey', `${none.status}/${none.body.error}`, '409/no_passkey');
  const kidTry = await call('POST', '/v1/me/pin/passkey-challenge', kid);
  check('B challenge', 'a child session cannot ask (403 guardian_session_required)', `${kidTry.status}/${kidTry.body.error}`, '403/guardian_session_required');
  const anon = await call('POST', '/v1/me/pin/passkey-challenge', null);
  check('B challenge', 'no session at all is 401', anon.status, 401);
  const ok = await call('POST', '/v1/me/pin/passkey-challenge', T.PK2);
  check('B challenge', 'a passkey holder gets a challenge and the relying-party id', `${typeof ok.body.challenge}/${ok.body.rpId}`, `string/${RP_ID}`);
  check('B challenge', 'two challenges differ', ok.body.challenge === (await stepupChallenge(T.PK2)), false);
}

// ===========================================================================
// C · bootstrap is unchanged
// ===========================================================================
{
  const first = await call('POST', '/v1/me/pin', T.NEW, { pin: '975310' });
  check('C bootstrap', 'an account with no passkey and no PIN sets its first PIN with no proof (200)', first.status, 200);
  const setAgain = await call('POST', '/v1/me/pin', T.NEW, { pin: '135792' });
  check('C bootstrap', 'and a second PIN with no proof is refused (403 current_pin_required)', `${setAgain.status}/${setAgain.body.error}`, '403/current_pin_required');
  check('C bootstrap', 'a passkey registered on an account that has only a PIN still needs that PIN', `${(await registerPasskey(T.NEW, makeAuthenticator('new-key-1'))).body.error}`, 'pin_required');
  check('C bootstrap', '...so no passkey was stored without it', await passkeys(G_NEW), 0);
}

// ===========================================================================
// D · exports and invites need the guardian PIN (the client now sends it)
// ===========================================================================
{
  const noPinExport = await call('GET', `/v1/children/${CH}/export`, T.PIN);
  check('D step-up', 'raw export without the PIN header is refused (400 pin_required)', `${noPinExport.status}/${noPinExport.body.error}`, '400/pin_required');
  const wrongPin = await call('GET', `/v1/children/${CH}/export`, T.PIN, undefined, { 'x-guardian-pin': '000000' });
  check('D step-up', 'a wrong PIN is refused (403 pin_incorrect)', `${wrongPin.status}/${wrongPin.body.error}`, '403/pin_incorrect');
  const okExport = await call('GET', `/v1/children/${CH}/export`, T.PIN, undefined, { 'x-guardian-pin': PIN });
  check('D step-up', 'the right PIN in the header returns the bundle (200)', `${okExport.status}/${typeof okExport.body.bundleJson}`, '200/string');
  const noPinInvite = await call('POST', `/v1/children/${CH}/guardianships`, T.PIN, { role: 'guardian', label: 'Dad', invitedEmail: 'dad@example.com' });
  check('D step-up', 'creating an invite without the PIN is refused (400 pin_required)', `${noPinInvite.status}/${noPinInvite.body.error}`, '400/pin_required');
  const okInvite = await call('POST', `/v1/children/${CH}/guardianships`, T.PIN, { role: 'guardian', label: 'Dad', invitedEmail: 'dad@example.com', pin: PIN });
  check('D step-up', 'with the PIN in the body the invite is created (201)', okInvite.status, 201);
}

await cleanup();
await fs.rm(storageRoot, { recursive: true, force: true });
await admin.end(); await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
