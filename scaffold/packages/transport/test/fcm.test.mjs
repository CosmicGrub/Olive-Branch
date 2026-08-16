/**
 * packages/transport/src/fcm.ts — real JWT-bearer OAuth2 flow and real FCM v1
 * request shape, proven against a MOCKED fetch. MASTERFILE §11.
 *
 * NEVER HITS A REAL GOOGLE ENDPOINT. Every network call in this file is a
 * hand-written fake `fetchImpl` that records what it was asked to send and
 * returns a canned response — see fcm.ts's own header for why nothing else
 * is possible in this environment. What IS proven for real: the JWT this
 * code signs verifies against the matching RSA public key with node:crypto,
 * the OAuth token-request body/headers are the real RFC 7523 shape, the
 * FCM v1 messages:send URL/headers/body are the real shape, and a missing
 * FCM_SERVICE_ACCOUNT_JSON throws rather than silently no-op'ing.
 *
 * Same local check()/pass/fail convention as transport.test.mjs, the sibling
 * this file extends the package's test coverage alongside (not a shared
 * record() helper — this package's own convention, matched as found).
 */
import { generateKeyPairSync, createVerify } from 'node:crypto';
import {
  sendFcm, toFcmRequestBody, _resetFcmTokenCacheForTests,
} from '../src/fcm.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e);
  ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const b64urlDecode = (s) => Buffer.from(s, 'base64url').toString('utf8');

const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const PRIVATE_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });

const SERVICE_ACCOUNT = {
  client_email: 'olive-push@example-project.iam.gserviceaccount.com',
  private_key: PRIVATE_PEM,
  project_id: 'example-project',
};

const CALL_PAYLOAD = {
  token: 'device-tok-1', data: { kind: 'call_incoming', ref: 'r_abc', v: '1', callHandle: 'h_1' },
  notification: null,
  android: { priority: 'high', fullScreenIntent: true, channelId: 'calls' },
};
const MSG_PAYLOAD = {
  token: 'device-tok-2', data: { kind: 'message_ready', ref: 'r_def', v: '1' },
  notification: { title: 'Olive', body: 'Something new is waiting for you.' },
  android: { priority: 'high', fullScreenIntent: false, channelId: 'reminders', collapseKey: 'c1' },
};

// ===========================================================================
// A · CONFIG — missing/invalid FCM_SERVICE_ACCOUNT_JSON fails loudly
// ===========================================================================
{
  delete process.env.FCM_SERVICE_ACCOUNT_JSON;
  let threw = null;
  try { await sendFcm(MSG_PAYLOAD); } catch (e) { threw = e; }
  check('A config', 'missing env var throws, does not silently no-op', threw !== null, 'true');
  check('A config', 'thrown error has a specific code', threw?.code, 'fcm_config_missing');
  check('A config', 'thrown error names the exact env var', /FCM_SERVICE_ACCOUNT_JSON/.test(threw?.message), 'true');

  process.env.FCM_SERVICE_ACCOUNT_JSON = 'not json{{{';
  let threw2 = null;
  try { await sendFcm(MSG_PAYLOAD); } catch (e) { threw2 = e; }
  check('A config', 'invalid JSON throws a distinct code', threw2?.code, 'fcm_config_invalid');

  process.env.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify({ client_email: 'x@example.com' });
  let threw3 = null;
  try { await sendFcm(MSG_PAYLOAD); } catch (e) { threw3 = e; }
  check('A config', 'JSON missing required fields throws fcm_config_invalid', threw3?.code, 'fcm_config_invalid');

  delete process.env.FCM_SERVICE_ACCOUNT_JSON;
}

// ===========================================================================
// B · OAUTH2 JWT-BEARER FLOW — real RS256 signature, real request shape
// ===========================================================================
{
  process.env.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify(SERVICE_ACCOUNT);
  _resetFcmTokenCacheForTests();

  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (url === 'https://oauth2.googleapis.com/token') {
      return { ok: true, status: 200, json: async () => ({ access_token: 'fake-bearer-1', expires_in: 3600 }),
        text: async () => '' };
    }
    return { ok: true, status: 200, json: async () => ({ name: 'projects/example-project/messages/1' }),
      text: async () => '' };
  };

  const result = await sendFcm(CALL_PAYLOAD, { fetchImpl, now: Date.parse('2026-01-01T00:00:00Z') });
  check('B oauth', 'sendFcm resolves ok:true on a clean mocked send', result.ok, 'true');
  check('B oauth', 'exactly two HTTP calls made (token, then send)', calls.length, 2);

  const tokenCall = calls[0];
  check('B oauth', 'first call hits the real Google token endpoint', tokenCall.url, 'https://oauth2.googleapis.com/token');
  check('B oauth', 'token request is form-urlencoded',
    tokenCall.init.headers['content-type'], 'application/x-www-form-urlencoded');
  const form = new URLSearchParams(tokenCall.init.body);
  check('B oauth', 'grant_type is the real RFC 7523 JWT-bearer grant',
    form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');

  const assertion = form.get('assertion');
  const [h64, c64, s64] = assertion.split('.');
  const header = JSON.parse(b64urlDecode(h64));
  const claims = JSON.parse(b64urlDecode(c64));
  check('B oauth', 'JWT header alg is RS256', header.alg, 'RS256');
  check('B oauth', 'JWT header typ is JWT', header.typ, 'JWT');
  check('B oauth', 'JWT iss is the service account email', claims.iss, SERVICE_ACCOUNT.client_email);
  check('B oauth', 'JWT scope is the real firebase.messaging scope',
    claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  check('B oauth', 'JWT aud is the token endpoint', claims.aud, 'https://oauth2.googleapis.com/token');
  check('B oauth', 'JWT exp is iat + 1 hour (Google\'s real maximum)', claims.exp - claims.iat, 3600);

  // The signature must ACTUALLY verify against the matching public key —
  // proves this is a real signed JWT, not a plausible-looking fake string.
  const verifier = createVerify('RSA-SHA256');
  verifier.update(`${h64}.${c64}`);
  verifier.end();
  const sigValid = verifier.verify(publicKey, Buffer.from(s64, 'base64url'));
  check('B oauth', 'JWT signature verifies against the real RSA public key', sigValid, 'true');

  const sendCall = calls[1];
  check('B oauth', 'send hits the real FCM v1 messages:send URL for this project',
    sendCall.url, 'https://fcm.googleapis.com/v1/projects/example-project/messages:send');
  check('B oauth', 'send carries the minted bearer token',
    sendCall.init.headers.authorization, 'Bearer fake-bearer-1');
  check('B oauth', 'send content-type is application/json',
    sendCall.init.headers['content-type'], 'application/json');

  // Second call within TTL must reuse the cached token — only ONE more HTTP
  // call (the send), not a second OAuth round trip.
  calls.length = 0;
  await sendFcm(MSG_PAYLOAD, { fetchImpl, now: Date.parse('2026-01-01T00:05:00Z') });
  check('B oauth', 'a second send within TTL reuses the cached token (no second OAuth call)',
    calls.length, 1);
  check('B oauth', 'the reused call is the send, not another token request',
    calls[0].url.includes('messages:send'), 'true');
}

// ===========================================================================
// B2 · CONCURRENT MINT COALESCING
//
// Regression test for an adversarial-review finding: without coalescing, two
// sendFcm() calls landing at the same moment the cache is empty/expired both
// read the same stale cache (there's a real network `await` between the
// cache check and the cache write in mintAccessToken), so each independently
// signs an RS256 JWT and POSTs to Google's OAuth endpoint — redundant work
// that scales with concurrent send volume and could trip Google's own
// rate limits during a broadcast burst. Fixed via a module-level in-flight
// promise a second racing caller joins instead of starting its own mint.
// ===========================================================================
{
  process.env.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify(SERVICE_ACCOUNT);
  _resetFcmTokenCacheForTests();

  let tokenCalls = 0;
  let releaseToken;
  const tokenGate = new Promise((res) => { releaseToken = res; });
  const calls2 = [];
  const fetchImpl = async (url, init) => {
    calls2.push({ url, init });
    if (url === 'https://oauth2.googleapis.com/token') {
      tokenCalls++;
      await tokenGate; // held open until the test explicitly releases it
      return { ok: true, status: 200,
        json: async () => ({ access_token: 'coalesced-token', expires_in: 3600 }), text: async () => '' };
    }
    return { ok: true, status: 200, json: async () => ({ name: 'projects/example-project/messages/2' }),
      text: async () => '' };
  };

  // Fire two sends WITHOUT awaiting the first — both must observe the same
  // empty/expired cache and race to mint.
  const p1 = sendFcm(CALL_PAYLOAD, { fetchImpl, now: Date.parse('2026-02-01T00:00:00Z') });
  const p2 = sendFcm(MSG_PAYLOAD, { fetchImpl, now: Date.parse('2026-02-01T00:00:00Z') });

  // A few microtask ticks so anything either send needed to do before
  // reaching its own network await has genuinely run, while the OAuth
  // response is still deliberately held open below.
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  check('B2 coalesce', 'exactly ONE OAuth token request is in flight for two concurrent sends',
    tokenCalls, 1);

  releaseToken();
  const [r1, r2] = await Promise.all([p1, p2]);
  check('B2 coalesce', 'both concurrent sends still resolve ok:true', Boolean(r1.ok && r2.ok), 'true');

  const tokenRequests = calls2.filter(c => c.url.includes('oauth2.googleapis.com'));
  check('B2 coalesce', 'still exactly one OAuth request total once both sends finished',
    tokenRequests.length, 1);
  const sendRequests = calls2.filter(c => c.url.includes('messages:send'));
  check('B2 coalesce', 'both real sends still went out separately (2 messages:send calls)',
    sendRequests.length, 2);
  check('B2 coalesce', 'both sends carry the SAME coalesced bearer token',
    sendRequests.every(c => c.init.headers.authorization === 'Bearer coalesced-token'), 'true');

  _resetFcmTokenCacheForTests();
}

// ===========================================================================
// C · REQUEST SHAPE — PushPayload -> real FCM v1 body, call vs message
// ===========================================================================
{
  const callBody = toFcmRequestBody(CALL_PAYLOAD);
  check('C shape', 'call_incoming is DATA-ONLY (no notification block at all)',
    'notification' in callBody.message, 'false');
  check('C shape', 'call_incoming data carries the opaque callHandle, nothing else',
    Object.keys(callBody.message.data).sort().join(','), 'callHandle,kind,ref,v');
  check('C shape', 'call_incoming android priority is HIGH', callBody.message.android.priority, 'HIGH');
  check('C shape', 'call_incoming has no android.notification (nothing to display)',
    'notification' in callBody.message.android, 'false');

  const msgBody = toFcmRequestBody(MSG_PAYLOAD);
  check('C shape', 'message_ready carries the real approved banner text',
    msgBody.message.notification.body, 'Something new is waiting for you.');
  check('C shape', 'message_ready sets android.notification.channel_id',
    msgBody.message.android.notification.channel_id, 'reminders');
  check('C shape', 'collapse_key passes through when present',
    msgBody.message.android.collapse_key, 'c1');
  check('C shape', 'message_ready data is content-free (kind/ref/v only)',
    Object.keys(msgBody.message.data).sort().join(','), 'kind,ref,v');
}

// ===========================================================================
// D · SEND FAILURES — real error shape, deviceGone on FCM's real dead-token signal
// ===========================================================================
{
  process.env.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify(SERVICE_ACCOUNT);
  _resetFcmTokenCacheForTests();
  const okToken = async () => ({ ok: true, status: 200,
    json: async () => ({ access_token: 'tok', expires_in: 3600 }), text: async () => '' });

  const deadTokenFetch = async (url) => {
    if (url.includes('oauth2')) return okToken();
    return { ok: false, status: 404,
      json: async () => ({ error: { status: 'NOT_FOUND',
        details: [{ errorCode: 'UNREGISTERED' }] } }),
      text: async () => 'not found' };
  };
  let deadErr = null;
  try { await sendFcm(MSG_PAYLOAD, { fetchImpl: deadTokenFetch, now: 1 }); }
  catch (e) { deadErr = e; }
  check('D failures', 'FCM UNREGISTERED throws fcm_send_failed', deadErr?.code, 'fcm_send_failed');
  check('D failures', 'FCM UNREGISTERED sets deviceGone:true (notify.ts prunes on this)',
    deadErr?.deviceGone, 'true');

  _resetFcmTokenCacheForTests();
  const serverErrFetch = async (url) => {
    if (url.includes('oauth2')) return okToken();
    return { ok: false, status: 500, json: async () => ({ error: { status: 'INTERNAL' } }),
      text: async () => 'internal' };
  };
  let serverErr = null;
  try { await sendFcm(MSG_PAYLOAD, { fetchImpl: serverErrFetch, now: 1 }); }
  catch (e) { serverErr = e; }
  check('D failures', 'a real server error throws fcm_send_failed too', serverErr?.code, 'fcm_send_failed');
  check('D failures', 'a transient server error does NOT set deviceGone (token might be fine)',
    Boolean(serverErr?.deviceGone), 'false');
}

delete process.env.FCM_SERVICE_ACCOUNT_JSON;
_resetFcmTokenCacheForTests();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
