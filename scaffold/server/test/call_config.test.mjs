/**
 * server/call_config.mjs + server/call_grant.mjs — the call provider switch.
 * MASTERFILE §16.2 #6 (third reversal). No database needed: the grant is a
 * pure function of an already-authorized mint.
 */
import { resolveCallConfig, describeCallConfig } from '../call_config.mjs';
import { buildCallGrant, callUnavailable } from '../call_grant.mjs';
import { createSession, mintToken } from '../../packages/session-runtime/src/rooms.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET_HEX = '9f3a61c07be24d58a1c9e0374bd62f85d7013ac9e86b4f52' + '0c1d3e5f7a9b2d4f';
const JITSI = { JITSI_APP_ID: 'olive-calls', JITSI_APP_SECRET: SECRET_HEX, JITSI_SERVER_URL: 'https://192.168.1.50:8443' };
const LK = { LIVEKIT_URL: 'wss://x.invalid', LIVEKIT_API_KEY: 'devkey', LIVEKIT_API_SECRET: 'devsecret_at_least_32_chars_long_xx' };

// --- provider switch --------------------------------------------------------
check('switch', 'default provider is jitsi', resolveCallConfig({}).provider, 'jitsi');
check('switch', 'explicit jitsi', resolveCallConfig({ CALL_PROVIDER: 'jitsi' }).provider, 'jitsi');
check('switch', 'explicit livekit', resolveCallConfig({ CALL_PROVIDER: 'livekit' }).provider, 'livekit');
check('switch', 'case and whitespace tolerated', resolveCallConfig({ CALL_PROVIDER: ' LiveKit ' }).provider, 'livekit');
check('switch', 'an unknown provider is a boot problem, never a silent fallback',
  resolveCallConfig({ CALL_PROVIDER: 'zoom' }).problems.length, 1);

// --- availability, honestly -------------------------------------------------
{
  const none = resolveCallConfig({});
  check('unavailable', 'jitsi with no env is unavailable, and names what is missing',
    none.unavailable.join(','), 'JITSI_APP_SECRET,JITSI_APP_ID,JITSI_SERVER_URL');
  check('unavailable', 'unset env is NOT a boot problem (calls are switched on on demand)', none.problems.length, 0);
  const partial = resolveCallConfig({ ...JITSI, JITSI_APP_SECRET: undefined });
  check('unavailable', 'one missing jitsi var is still unavailable', partial.jitsi, null);
  check('unavailable', 'configured jitsi is available', resolveCallConfig(JITSI).unavailable.length, 0);
  check('unavailable', 'livekit with no env is unavailable', resolveCallConfig({ CALL_PROVIDER: 'livekit' }).unavailable.length, 3);
  check('unavailable', 'livekit env does not make the DEFAULT (jitsi) provider available',
    resolveCallConfig(LK).unavailable.length > 0, true);
  check('unavailable', 'livekit configured is available', resolveCallConfig({ CALL_PROVIDER: 'livekit', ...LK }).unavailable.length, 0);
  check('unavailable', 'jitsi 503 body names the provider', JSON.stringify(callUnavailable(none).body),
    JSON.stringify({ error: 'call_provider_unavailable', provider: 'jitsi' }));
  check('unavailable', 'jitsi unavailable status is 503', callUnavailable(none).status, 503);
  check('unavailable', 'livekit unavailable keeps its historical 500 call_backend_unconfigured',
    `${callUnavailable({ provider: 'livekit' }).status} ${callUnavailable({ provider: 'livekit' }).body.error}`, '500 call_backend_unconfigured');
}

// --- secret validation, like secrets.mjs ------------------------------------
{
  const bad = (over, env = {}) => resolveCallConfig({ ...JITSI, ...env, ...over }).problems.join('|');
  check('validation', 'non-hex secret refused (would be an empty HMAC key)', /hex/.test(bad({ JITSI_APP_SECRET: 'not-hex-value' })), true);
  check('validation', 'short secret refused', /at least 32 bytes/.test(bad({ JITSI_APP_SECRET: 'ab'.repeat(8) })), true);
  check('validation', 'placeholder secret refused in production', /placeholder/.test(bad({ JITSI_APP_SECRET: '00'.repeat(32) }, { NODE_ENV: 'production' })), true);
  check('validation', 'placeholder tolerated in development', bad({ JITSI_APP_SECRET: '00'.repeat(32) }, { NODE_ENV: 'development' }), '');
  check('validation', 'malformed secret is refused even in development', /hex/.test(bad({ JITSI_APP_SECRET: 'zz' }, { NODE_ENV: 'development' })), true);
  check('validation', 'http server URL refused in production', /https/.test(bad({ JITSI_SERVER_URL: 'http://192.168.1.50:8443' }, { NODE_ENV: 'production' })), true);
  check('validation', 'http server URL refused when NODE_ENV is unset', /https/.test(bad({ JITSI_SERVER_URL: 'http://192.168.1.50:8443' })), true);
  check('validation', 'server URL with a path is refused', /origin only/.test(bad({ JITSI_SERVER_URL: 'https://h:8443/room' })), true);
  check('validation', 'server URL with credentials is refused', /origin only/.test(bad({ JITSI_SERVER_URL: 'https://u:p@h:8443' })), true);
  check('validation', 'garbage server URL is refused', /valid URL/.test(bad({ JITSI_SERVER_URL: 'not a url' })), true);
  check('validation', 'app id with spaces refused', /JITSI_APP_ID/.test(bad({ JITSI_APP_ID: 'a b' })), true);
  check('validation', 'xmpp domain default is meet.jitsi', resolveCallConfig(JITSI).jitsi.xmppDomain, 'meet.jitsi');
  check('validation', 'server URL is normalised to its origin', resolveCallConfig({ ...JITSI, JITSI_SERVER_URL: 'https://H.local:8443/' }).jitsi.serverURL, 'https://h.local:8443');
  check('validation', 'the problem text never contains the secret value', bad({ JITSI_APP_SECRET: 'not-hex-SECRETVALUE' }).includes('SECRETVALUE'), false);
}

// --- no secret leakage ------------------------------------------------------
{
  const cfg = resolveCallConfig(JITSI);
  const shown = JSON.stringify(describeCallConfig(cfg));
  check('leakage', 'describeCallConfig (the only loggable view) never contains the secret', shown.includes(SECRET_HEX), false);
  check('leakage', '... nor the app id or URL', shown.includes('olive-calls') || shown.includes('192.168'), false);
}

// --- grant shape, both providers ---------------------------------------------
{
  const CHILD = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', DAD = '11111111-1111-1111-1111-111111111111';
  const edge = { childId: CHILD, userId: DAD, role: 'guardian', scope: {}, observerOnly: false, restricted: false,
    validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null, closedAt: null, ladderStep: null };
  const session = createSession({ childId: CHILD, kind: 'call', createdBy: DAD, authorizedUserIds: [DAD, CHILD], ladderStep: 'open' });
  const m = mintToken(session, { userId: DAD, observerOnly: false, isChild: false, roleName: 'guardian' }, [edge], new Date());
  const jcfg = resolveCallConfig(JITSI);
  const g = await buildCallGrant(jcfg, m, { displayName: 'Dad', isChild: false, observerOnly: false });
  check('grant', 'jitsi grant says provider jitsi', g.provider, 'jitsi');
  check('grant', 'jitsi grant carries jwt, room, serverURL', ['jwt', 'room', 'serverURL'].every((k) => typeof g[k] === 'string'), true);
  check('grant', 'jitsi grant has NO livekit fields', 'token' in g || 'wsURL' in g, false);
  check('grant', 'the app secret is nowhere in the grant', JSON.stringify(g).includes(SECRET_HEX), false);
  check('grant', 'the raw session room name is not returned', JSON.stringify(g).includes(session.roomName), false);
  check('grant', 'adult caller is a moderator', g.moderator, true);
  const gc = await buildCallGrant(jcfg, m, { displayName: 'Ivy', isChild: true, observerOnly: false });
  check('grant', 'child is not a moderator', gc.moderator, false);
  const go = await buildCallGrant(jcfg, m, { displayName: 'Dad', isChild: false, observerOnly: true });
  check('grant', 'observer-only adult is not a moderator and is flagged', `${go.moderator} ${go.observerOnly}`, 'false true');
  const lk = await buildCallGrant(resolveCallConfig({ CALL_PROVIDER: 'livekit', ...LK }), m, { displayName: 'Dad', isChild: false, observerOnly: false });
  check('grant', 'livekit grant says provider livekit and keeps token + wsURL', `${lk.provider} ${typeof lk.token} ${lk.wsURL}`, 'livekit string wss://x.invalid');
  check('grant', 'livekit grant has NO jitsi fields', 'jwt' in lk || 'serverURL' in lk, false);
  const banned = /"(age|birth|dob|email)/i;
  check('grant', 'child payload sweep: no banned keys in either grant', banned.test(JSON.stringify(g)) || banned.test(JSON.stringify(gc)), false);
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
