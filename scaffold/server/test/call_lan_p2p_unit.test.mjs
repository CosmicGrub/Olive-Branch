/**
 * The 'lan-p2p' call provider's pure halves: the signalling mailbox (server/call_signal.mjs), the ICE list
 * (server/call_ice.mjs), the provider switch (call_config.mjs) and the grant (call_grant.mjs). No database.
 * 2026-11-21, MASTERFILE 16.2 #6. The route-level proof against a real Postgres is calls_lan_p2p_route.test.mjs.
 */
import { createHmac } from 'node:crypto';
import { createSignalHub } from '../call_signal.mjs';
import { resolveIceConfig, iceGrantFor, mintTurnCredentials, describeIceConfig } from '../call_ice.mjs';
import { resolveCallConfig, describeCallConfig } from '../call_config.mjs';
import { buildCallGrant, callUnavailable } from '../call_grant.mjs';
import { createSession, mintToken } from '../../packages/session-runtime/src/rooms.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// ---------------------------------------------------------------- mailbox
{
  let t = 1_000_000; const hub = createSignalHub({ now: () => t, maxPerSession: 5, maxBytes: 200, maxSessions: 2, ttlMs: 60_000, presenceTtlMs: 10_000 });
  const S = 'sess-1';
  check('hub', 'post returns a rising sequence', [hub.post(S, 'caller', 'offer', { sdp: 'a' }).seq, hub.post(S, 'callee', 'answer', { sdp: 'b' }).seq].join(), '1,2');
  check('hub', 'each side reads only the other side', `${(await hub.read(S, 'callee', 0)).messages.length} ${(await hub.read(S, 'caller', 0)).messages.length}`, '1 1');
  check('hub', 'after skips what was already read', (await hub.read(S, 'caller', 2)).messages.length, 0);
  check('hub', 'bad role refused', hub.post(S, 'admin', 'offer', {}).error, 'bad_role');
  check('hub', 'bad kind refused', hub.post(S, 'caller', 'record', {}).error, 'bad_kind');
  for (const bad of [null, 'x', 7, [1], undefined]) check('hub', `payload ${JSON.stringify(bad)} refused`, hub.post(S, 'caller', 'ice', bad).error, 'bad_payload');
  const cyc = {}; cyc.self = cyc;
  check('hub', 'a cyclic payload is refused, not thrown', hub.post(S, 'caller', 'ice', cyc).error, 'bad_payload');
  check('hub', 'oversized refused', hub.post(S, 'caller', 'offer', { sdp: 'x'.repeat(300) }).error, 'too_large');
  hub.post(S, 'caller', 'ice', { c: 1 }); hub.post(S, 'caller', 'ice', { c: 2 }); hub.post(S, 'caller', 'ice', { c: 3 });
  check('hub', 'a per-call cap holds', hub.post(S, 'caller', 'ice', { c: 4 }).error, 'too_many');
  check('hub', 'sessions never mix', (await hub.read('sess-other', 'callee', 0)).messages.length, 0);
  hub.post('s2', 'caller', 'offer', {});
  check('hub', 'a third live session is refused while two exist (bounded)', hub.post('s3', 'caller', 'offer', {}).error, 'busy');
  t += 61_000;
  check('hub', 'an old session is swept and room is made', hub.post('s3', 'caller', 'offer', {}).ok, true);
  check('hub', 'a swept session is gone', (await hub.read(S, 'callee', 0)).messages.length, 0);

  // bye closes; waiting poll wakes
  const h2 = createSignalHub();
  const waiting = h2.read('w', 'callee', 0, 5000);
  setTimeout(() => h2.post('w', 'caller', 'offer', { sdp: 'late' }), 20);
  const got = await waiting;
  check('hub', 'a waiting read wakes when a message arrives', got.messages[0]?.payload.sdp, 'late');
  const w2 = h2.read('w', 'callee', 1, 5000);
  setTimeout(() => h2.close('w'), 20);
  check('hub', 'a waiting read wakes when the call closes', (await w2).closed, true);
  check('hub', 'a closed call refuses more posts', h2.post('w', 'caller', 'ice', { c: 1 }).error, 'closed');
  const t0 = Date.now(); await h2.read('idle', 'callee', 0, 40);
  check('hub', 'an idle wait returns after its wait, empty', Date.now() - t0 >= 35, true);
  const byeHub = createSignalHub(); byeHub.post('b', 'caller', 'bye', {});
  check('hub', 'a bye closes the mailbox for the other side to see', (await byeHub.read('b', 'callee', 0)).closed, true);

  // presence
  const p = createSignalHub({ now: () => t, presenceTtlMs: 10_000 });
  check('hub', 'a tablet never seen is not reachable', p.childRecentlySeen('c'), false);
  p.touchChild('c'); check('hub', 'just seen is reachable', p.childRecentlySeen('c'), true);
  t += 11_000; check('hub', 'not seen for a while is not reachable', p.childRecentlySeen('c'), false);
  check('hub', 'another child is never reachable by this one\'s poll', (p.touchChild('c'), p.childRecentlySeen('d')), false);
}

// ---------------------------------------------------------------- ICE config
{
  const none = resolveIceConfig({});
  check('ice', 'default is empty: no STUN, no TURN, not relay-only, no problems', JSON.stringify([none.stun, none.turn, none.relayOnly, none.problems]), '[[],[],false,[]]');
  check('ice', 'the default grant list is empty and the policy is all', JSON.stringify(iceGrantFor(none, { nowSeconds: 1, label: 'x' })), '{"iceServers":[],"iceTransportPolicy":"all"}');
  const full = resolveIceConfig({ CALL_ICE_STUN_URLS: 'stun:192.0.2.1:3478, stuns:stun.example.invalid:5349', CALL_ICE_TURN_URLS: 'turn:192.0.2.1:3478?transport=udp,turns:192.0.2.1:5349',
    CALL_ICE_TURN_SECRET: 'sixteen-chars-min-secret', CALL_ICE_RELAY_ONLY: 'true', CALL_ICE_TTL_SECONDS: '300' });
  check('ice', 'full config parses with no problems', `${full.stun.length} ${full.turn.length} ${full.relayOnly} ${full.ttlSeconds} ${full.problems.length}`, '2 2 true 300 0');
  const g = iceGrantFor(full, { nowSeconds: 1000, label: 'tag' });
  check('ice', 'relay-only reaches the grant', g.iceTransportPolicy, 'relay');
  const turn = g.iceServers.find((s) => s.username);
  check('ice', 'the TURN username carries the expiry', turn.username, '1300:tag');
  check('ice', 'the credential is the TURN REST HMAC', turn.credential, createHmac('sha1', 'sixteen-chars-min-secret').update('1300:tag').digest('base64'));
  // a coturn-style verifier: recompute from the shared secret, check the expiry
  const verify = (secret, u, cred, nowS) => { const [exp] = u.split(':'); return Number(exp) > nowS && cred === createHmac('sha1', secret).update(u).digest('base64'); };
  check('ice', 'a coturn-style verifier accepts a fresh credential', verify('sixteen-chars-min-secret', turn.username, turn.credential, 1100), true);
  check('ice', 'and refuses it once it has expired', verify('sixteen-chars-min-secret', turn.username, turn.credential, 1400), false);
  check('ice', 'and refuses a forged one', verify('sixteen-chars-min-secret', turn.username, turn.credential.replace(/.$/, 'A'), 1100) && turn.credential.slice(-1) !== 'A', false);
  check('ice', 'the label is sanitised and capped', mintTurnCredentials('s'.repeat(16), '../a b' + 'z'.repeat(40), 0, 10).username.split(':')[1].length <= 24, true);
  check('ice', 'each grant gets its own credential when the label differs', iceGrantFor(full, { nowSeconds: 1, label: 'a' }).iceServers[1].credential !== iceGrantFor(full, { nowSeconds: 1, label: 'b' }).iceServers[1].credential, true);
  check('ice', 'describeIceConfig is counts and booleans only', JSON.stringify(describeIceConfig(full)).includes('sixteen'), false);
  const fixed = resolveIceConfig({ CALL_ICE_TURN_URLS: 'turn:192.0.2.1:3478', CALL_ICE_TURN_USERNAME: 'u', CALL_ICE_TURN_CREDENTIAL: 'p' });
  check('ice', 'a fixed pair is used as is when there is no secret', JSON.stringify(iceGrantFor(fixed, { nowSeconds: 1, label: 'x' }).iceServers), '[{"urls":["turn:192.0.2.1:3478"],"username":"u","credential":"p"}]');
  const both = resolveIceConfig({ CALL_ICE_TURN_URLS: 'turn:192.0.2.1:3478', CALL_ICE_TURN_SECRET: 'sixteen-chars-min-secret', CALL_ICE_TURN_USERNAME: 'u', CALL_ICE_TURN_CREDENTIAL: 'p' });
  check('ice', 'a secret wins over a fixed pair', both.staticPair, null);
  for (const [name, env, frag] of [
    ['a non-ICE url', { CALL_ICE_STUN_URLS: 'http://x.invalid' }, 'CALL_ICE_STUN_URLS'],
    ['a stun url in the TURN list', { CALL_ICE_TURN_URLS: 'stun:192.0.2.1', CALL_ICE_TURN_SECRET: 'sixteen-chars-min-secret' }, 'CALL_ICE_TURN_URLS'],
    ['a url with a credential in it', { CALL_ICE_TURN_URLS: 'turn:user:pw@192.0.2.1', CALL_ICE_TURN_SECRET: 'sixteen-chars-min-secret' }, 'CALL_ICE_TURN_URLS'],
    ['a short secret', { CALL_ICE_TURN_URLS: 'turn:192.0.2.1', CALL_ICE_TURN_SECRET: 'short' }, 'at least 16'],
    ['TURN urls with no credentials', { CALL_ICE_TURN_URLS: 'turn:192.0.2.1' }, 'needs CALL_ICE_TURN_SECRET'],
    ['a secret with no urls', { CALL_ICE_TURN_SECRET: 'sixteen-chars-min-secret' }, 'TURN urls'.toLowerCase() === '' ? '' : 'is empty'],
    ['relay-only with no TURN', { CALL_ICE_RELAY_ONLY: '1' }, 'CALL_ICE_RELAY_ONLY'],
  ]) check('ice', `${name} is a plain problem`, resolveIceConfig(env).problems.some((p) => p.includes(frag)), true);
  check('ice', 'an out-of-range TTL falls back to the default', resolveIceConfig({ CALL_ICE_TTL_SECONDS: '999999' }).ttlSeconds, 600);
  check('ice', 'relay-only without TURN is not honoured (never a silent no-media call)', resolveIceConfig({ CALL_ICE_RELAY_ONLY: '1' }).relayOnly, false);
}

// ---------------------------------------------------------------- provider switch + grant
{
  const lan = resolveCallConfig({ CALL_PROVIDER: 'lan-p2p' });
  check('switch', 'lan-p2p is a selectable provider', lan.provider, 'lan-p2p');
  check('switch', 'it needs no secret and no server address: available with an empty env', `${lan.unavailable.length} ${lan.problems.length}`, '0 0');
  check('switch', 'the default is still jitsi (this change moves nothing)', resolveCallConfig({}).provider, 'jitsi');
  check('switch', 'livekit and jitsi still resolve as before', `${resolveCallConfig({ CALL_PROVIDER: 'livekit' }).provider} ${resolveCallConfig({ CALL_PROVIDER: 'jitsi' }).provider}`, 'livekit jitsi');
  check('switch', 'a bad ICE setting is a boot problem for lan-p2p', resolveCallConfig({ CALL_PROVIDER: 'lan-p2p', CALL_ICE_TURN_URLS: 'turn:192.0.2.1' }).problems.length > 0, true);
  check('switch', 'but ICE settings never affect the other providers', resolveCallConfig({ CALL_ICE_TURN_URLS: 'bogus' }).problems.length, 0);
  check('switch', 'describe is safe to log', JSON.stringify(describeCallConfig(resolveCallConfig({ CALL_PROVIDER: 'lan-p2p', CALL_ICE_STUN_URLS: 'stun:192.0.2.1' }))), '{"provider":"lan-p2p","configured":true,"missing":[],"ice":{"stunUrls":1,"turnUrls":0,"mintsCredentials":false,"relayOnly":false}}');
  check('switch', 'the 503 body names the provider', JSON.stringify(callUnavailable(lan).body), '{"error":"call_provider_unavailable","provider":"lan-p2p"}');

  const session = createSession({ childId: 'c1c1c1c1-1234-4234-8234-c1c1c1c1c1c1', kind: 'call', createdBy: 'u1', authorizedUserIds: ['u1', 'c1'], ladderStep: 'supervised' });
  const minted = { token: { identity: 'u1', ttlSeconds: 600, recorded: session.recorded } };
  const grant = await buildCallGrant(lan, minted, { displayName: 'Dad', isChild: false, observerOnly: false, nowSeconds: 5000, role: 'caller', sessionId: session.id });
  check('grant', 'a supervised session is flagged recorded by the ladder...', session.recorded, true);
  check('grant', '...yet a lan-p2p grant says recorded:false (nothing here can record)', grant.recorded, false);
  check('grant', 'shape: provider, role, identity, ice, expiry, session', JSON.stringify(Object.keys(grant).sort()), JSON.stringify(['displayName', 'expiresAt', 'iceServers', 'iceTransportPolicy', 'identity', 'observerOnly', 'provider', 'recorded', 'role', 'sessionId']));
  check('grant', 'it carries no secret-shaped key', ['token', 'jwt', 'secret', 'password', 'key', 'room', 'wsURL', 'serverURL'].some((k) => k in grant), false);
  check('grant', 'expiry is the minted ttl', grant.expiresAt, 5600);
  const m = mintToken(session, { userId: 'c1', observerOnly: false, isChild: true, roleName: 'child' }, [], new Date());
  check('grant', 'a child participant is minted for the same session', m.ok, true);
}

let gname = '';
for (const r of rows) { if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
