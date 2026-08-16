/**
 * packages/transport/src/apns.ts — real ES256 provider-token JWT and real
 * APNs HTTP/2 request shape, proven against a MOCKED node:http2-shaped
 * transport. MASTERFILE §11.
 *
 * NEVER OPENS A REAL HTTP/2 CONNECTION TO APPLE. The `http2Impl` here is a
 * hand-written fake session/stream pair implementing exactly the subset of
 * node:http2's surface apns.ts actually calls (`connect`, `.request(headers)`,
 * stream events) — see apns.ts's own header for why nothing else is possible
 * in this environment. What IS proven for real: the JWT this code signs
 * verifies against the matching EC public key with node:crypto (raw
 * IEEE-P1363 signature, not DER — the real JOSE ES256 shape), the real
 * `:path`/`apns-*` headers, and a missing env var throws rather than
 * silently no-op'ing.
 */
import { generateKeyPairSync, verify as cryptoVerify } from 'node:crypto';
import {
  sendApns, toApnsRequestBody, _resetApnsTokenCacheForTests,
  APNS_HOST_PRODUCTION, APNS_HOST_SANDBOX,
} from '../src/apns.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e);
  ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const b64urlDecode = (s) => Buffer.from(s, 'base64url').toString('utf8');

const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const KEY_P8 = privateKey.export({ type: 'pkcs8', format: 'pem' });

const CALL_PAYLOAD = {
  token: 'ios-device-1', data: { kind: 'call_incoming', ref: 'r_abc', v: '1', callHandle: 'h_1' },
  notification: null,
  apns: { pushType: 'voip', priority: 10, topicSuffix: '.voip' },
};
const MSG_PAYLOAD = {
  token: 'ios-device-2', data: { kind: 'message_ready', ref: 'r_def', v: '1' },
  notification: { title: 'Olive', body: 'Something new is waiting for you.' },
  apns: { pushType: 'alert', priority: 5, interruptionLevel: 'active', contentAvailable: true },
};

/** A fake node:http2 session/stream pair. `onRequest` gets the exact headers
 * passed to `.request()` and returns { status, body } to play back. */
function fakeHttp2(onRequest) {
  const requests = [];
  return {
    requests,
    impl: {
      connect(authority) {
        return {
          request(headers) {
            requests.push({ authority, headers, body: '' });
            const rec = requests[requests.length - 1];
            const listeners = {};
            const stream = {
              setEncoding() {},
              on(event, cb) { (listeners[event] ??= []).push(cb); return stream; },
              end(body) {
                rec.body = body;
                const { status, body: respBody } = onRequest(rec);
                queueMicrotask(() => {
                  (listeners.response ?? []).forEach(cb => cb({ ':status': status }));
                  (listeners.data ?? []).forEach(cb => cb(respBody));
                  (listeners.end ?? []).forEach(cb => cb());
                });
              },
            };
            return stream;
          },
          on() {},
          close() {},
        };
      },
    },
  };
}

/** Variant of fakeHttp2() above that simulates a session-level or
 * stream-level 'error' event instead of a normal response — used only by
 * section E below, to prove sendApns() closes the HTTP/2 session on BOTH
 * error paths, not just the clean 'end' path. */
function fakeHttp2Erroring(mode) {
  let closed = false;
  const impl = {
    connect() {
      const sessionListeners = {};
      const session = {
        request() {
          const streamListeners = {};
          const stream = {
            setEncoding() {},
            on(event, cb) { (streamListeners[event] ??= []).push(cb); return stream; },
            end() {
              if (mode === 'stream') {
                queueMicrotask(() =>
                  (streamListeners.error ?? []).forEach(cb => cb(new Error('stream boom'))));
              }
              // mode === 'session': the stream never completes on its own;
              // the session-level 'error' below is what settles the promise.
            },
          };
          return stream;
        },
        on(event, cb) { (sessionListeners[event] ??= []).push(cb); },
        close() { closed = true; },
      };
      if (mode === 'session') {
        queueMicrotask(() =>
          (sessionListeners.error ?? []).forEach(cb => cb(new Error('session boom'))));
      }
      return session;
    },
  };
  return { impl, isClosed: () => closed };
}

// ===========================================================================
// A · CONFIG — missing env vars fail loudly, name exactly what's missing
// ===========================================================================
{
  for (const k of ['APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC']) delete process.env[k];

  let threw = null;
  try { await sendApns(MSG_PAYLOAD); } catch (e) { threw = e; }
  check('A config', 'all vars missing throws, does not silently no-op', threw !== null, 'true');
  check('A config', 'thrown error has a specific code', threw?.code, 'apns_config_missing');
  check('A config', 'names all three missing key vars',
    ['APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID'].every(v => threw.missing.includes(v)), 'true');

  process.env.APNS_KEY_P8 = KEY_P8;
  process.env.APNS_KEY_ID = 'KEYID1234';
  process.env.APNS_TEAM_ID = 'TEAM1234AB';
  let threwTopic = null;
  try { await sendApns(MSG_PAYLOAD); } catch (e) { threwTopic = e; }
  check('A config', 'missing APNS_TOPIC alone still throws (mandatory apns-topic header)',
    threwTopic?.code, 'apns_config_missing');
  check('A config', 'names APNS_TOPIC specifically', threwTopic?.missing?.[0], 'APNS_TOPIC');

  for (const k of ['APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC']) delete process.env[k];
}

// ===========================================================================
// B · ES256 PROVIDER TOKEN — real signature, real claims, real caching
// ===========================================================================
{
  process.env.APNS_KEY_P8 = KEY_P8;
  process.env.APNS_KEY_ID = 'KEYID1234';
  process.env.APNS_TEAM_ID = 'TEAM1234AB';
  process.env.APNS_TOPIC = 'com.olivebranch.olive_client';
  _resetApnsTokenCacheForTests();

  const { impl, requests } = fakeHttp2(() => ({ status: 200, body: '' }));
  const result = await sendApns(CALL_PAYLOAD, { http2Impl: impl, now: Date.parse('2026-01-01T00:00:00Z') });
  check('B jwt', 'sendApns resolves ok:true on a clean mocked send', result.ok, 'true');
  check('B jwt', 'exactly one HTTP/2 request made', requests.length, 1);

  const req = requests[0];
  const auth = req.headers.authorization;
  check('B jwt', 'authorization header is a bearer token', auth.startsWith('bearer '), 'true');
  const jwt = auth.slice('bearer '.length);
  const [h64, c64, s64] = jwt.split('.');
  const header = JSON.parse(b64urlDecode(h64));
  const claims = JSON.parse(b64urlDecode(c64));
  check('B jwt', 'JWT header alg is ES256', header.alg, 'ES256');
  check('B jwt', 'JWT header kid is the real key id', header.kid, 'KEYID1234');
  check('B jwt', 'JWT iss is the real team id', claims.iss, 'TEAM1234AB');
  check('B jwt', 'JWT carries iat', typeof claims.iat, 'number');

  // Signature must verify with the raw IEEE-P1363 (JOSE) encoding, the real
  // wire format for ES256 -- NOT the DER encoding node:crypto defaults to.
  const sigValid = cryptoVerify('sha256', Buffer.from(`${h64}.${c64}`),
    { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s64, 'base64url'));
  check('B jwt', 'JWT signature verifies against the real EC public key (raw R||S form)', sigValid, 'true');

  // A second send within the cache TTL must reuse the same JWT string.
  const { impl: impl2, requests: requests2 } = fakeHttp2(() => ({ status: 200, body: '' }));
  await sendApns(MSG_PAYLOAD, { http2Impl: impl2, now: Date.parse('2026-01-01T00:10:00Z') });
  check('B jwt', 'a second send within TTL reuses the cached provider token',
    requests2[0].headers.authorization, auth);
}

// ===========================================================================
// C · REQUEST SHAPE — real :path/apns-* headers, call vs message
// ===========================================================================
{
  _resetApnsTokenCacheForTests();
  const { impl, requests } = fakeHttp2(() => ({ status: 200, body: '' }));
  await sendApns(CALL_PAYLOAD, { http2Impl: impl, now: 1 });
  const callReq = requests[0];
  check('C shape', 'call path names the exact device token', callReq.headers[':path'], '/3/device/ios-device-1');
  check('C shape', 'call apns-push-type is voip', callReq.headers['apns-push-type'], 'voip');
  check('C shape', 'call apns-priority is 10 (immediate)', callReq.headers['apns-priority'], '10');
  check('C shape', 'call apns-topic gets the .voip suffix',
    callReq.headers['apns-topic'], 'com.olivebranch.olive_client.voip');

  const callBody = JSON.parse(callReq.body);
  check('C shape', 'call body has an EMPTY aps (no alert -- PushKit builds the UI)',
    Object.keys(callBody.aps).length, 0);
  check('C shape', 'call body carries the opaque callHandle at the top level, outside aps',
    callBody.callHandle, 'h_1');
  check('C shape', 'call body data is content-free otherwise',
    Object.keys(callBody).sort().join(','), 'aps,callHandle,kind,ref,v');

  const { impl: impl2, requests: requests2 } = fakeHttp2(() => ({ status: 200, body: '' }));
  await sendApns(MSG_PAYLOAD, { http2Impl: impl2, now: 1 });
  const msgReq = requests2[0];
  check('C shape', 'message apns-push-type is alert', msgReq.headers['apns-push-type'], 'alert');
  check('C shape', 'message apns-priority is 5', msgReq.headers['apns-priority'], '5');
  check('C shape', 'message apns-topic has NO suffix (plain bundle id)',
    msgReq.headers['apns-topic'], 'com.olivebranch.olive_client');
  const msgBody = JSON.parse(msgReq.body);
  check('C shape', 'message body carries the real approved banner text',
    msgBody.aps.alert.body, 'Something new is waiting for you.');
  check('C shape', 'message body sets content-available:1', msgBody.aps['content-available'], 1);
  check('C shape', 'message body sets interruption-level', msgBody.aps['interruption-level'], 'active');

  // toApnsRequestBody() unit-checked directly too, independent of transport.
  const direct = toApnsRequestBody(MSG_PAYLOAD);
  check('C shape', 'toApnsRequestBody matches what actually got sent', JSON.stringify(direct), JSON.stringify(msgBody));

  check('C shape', 'sandbox host constant is the real Apple sandbox host',
    APNS_HOST_SANDBOX, 'https://api.sandbox.push.apple.com');
  check('C shape', 'production host constant is the real Apple production host',
    APNS_HOST_PRODUCTION, 'https://api.push.apple.com');
}

// ===========================================================================
// D · SEND FAILURES — real error shape, deviceGone on Apple's real dead-token signals
// ===========================================================================
{
  _resetApnsTokenCacheForTests();
  const { impl } = fakeHttp2(() => ({ status: 410, body: JSON.stringify({ reason: 'Unregistered' }) }));
  let deadErr = null;
  try { await sendApns(MSG_PAYLOAD, { http2Impl: impl, now: 1 }); } catch (e) { deadErr = e; }
  check('D failures', 'Apple Unregistered throws apns_send_failed', deadErr?.code, 'apns_send_failed');
  check('D failures', 'Apple Unregistered sets deviceGone:true', deadErr?.deviceGone, 'true');

  const { impl: impl2 } = fakeHttp2(() => ({ status: 400, body: JSON.stringify({ reason: 'BadDeviceToken' }) }));
  let badTokErr = null;
  try { await sendApns(MSG_PAYLOAD, { http2Impl: impl2, now: 1 }); } catch (e) { badTokErr = e; }
  check('D failures', 'BadDeviceToken also sets deviceGone:true', badTokErr?.deviceGone, 'true');

  const { impl: impl3 } = fakeHttp2(() => ({ status: 500, body: JSON.stringify({ reason: 'InternalServerError' }) }));
  let serverErr = null;
  try { await sendApns(MSG_PAYLOAD, { http2Impl: impl3, now: 1 }); } catch (e) { serverErr = e; }
  check('D failures', 'a real server error throws apns_send_failed too', serverErr?.code, 'apns_send_failed');
  check('D failures', 'a transient server error does NOT set deviceGone',
    Boolean(serverErr?.deviceGone), 'false');
}

// ===========================================================================
// E · RESOURCE CLEANUP — session.close() runs on BOTH error paths, not just
//     the clean 'end' path.
//
//     Regression test for an adversarial-review finding: sendApns() opens a
//     brand-new h2.connect(host) session per call with no pooling, and
//     BEFORE this fix, session.close() was only ever reached from inside the
//     stream's 'end' handler. A session-level 'error' (session.on('error'))
//     or a stream-level 'error' (req.on('error') — e.g. a mid-write
//     RST_STREAM on a flaky network path) rejected the promise correctly but
//     left that session's socket open. In a long-running Node process
//     sending a batch of pushes while a device's network path is flaky,
//     repeated failures of this kind would accumulate open HTTP/2
//     sessions/sockets, eventually risking file-descriptor/socket
//     exhaustion unrelated to the actual send outcome.
// ===========================================================================
{
  process.env.APNS_KEY_P8 = KEY_P8;
  process.env.APNS_KEY_ID = 'KEYID1234';
  process.env.APNS_TEAM_ID = 'TEAM1234AB';
  process.env.APNS_TOPIC = 'com.olivebranch.olive_client';
  _resetApnsTokenCacheForTests();

  const sessionErr = fakeHttp2Erroring('session');
  let sessErrCaught = null;
  try { await sendApns(MSG_PAYLOAD, { http2Impl: sessionErr.impl, now: 1 }); }
  catch (e) { sessErrCaught = e; }
  check('E cleanup', 'a session-level error still rejects with apns_connect_failed',
    sessErrCaught?.code, 'apns_connect_failed');
  check('E cleanup', 'a session-level error CLOSES the session (no socket leak)',
    sessionErr.isClosed(), 'true');

  _resetApnsTokenCacheForTests();
  const streamErr = fakeHttp2Erroring('stream');
  let streamErrCaught = null;
  try { await sendApns(MSG_PAYLOAD, { http2Impl: streamErr.impl, now: 1 }); }
  catch (e) { streamErrCaught = e; }
  check('E cleanup', 'a stream-level error still rejects with apns_stream_failed',
    streamErrCaught?.code, 'apns_stream_failed');
  check('E cleanup', 'a stream-level error CLOSES the session (no socket leak)',
    streamErr.isClosed(), 'true');
}

for (const k of ['APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC']) delete process.env[k];
_resetApnsTokenCacheForTests();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
