// Call grant golden vectors: the exact JSON bodies server/call_grant.mjs puts on the wire for a call,
// generated with a fixed secret, fixed clock and fixed session so they are byte-stable. The Dart client
// (client/lib/call_provider.dart, CallGrant.fromJson) parses these in client/test/call_grant_vectors_test.dart,
// so the two languages cannot drift on the contract. tools/test/call_grant_vectors.test.mjs is the drift guard.
import { writeFileSync } from 'node:fs';
import { mintToken } from '../packages/session-runtime/src/rooms.mjs';
import { resolveCallConfig } from '../server/call_config.mjs';
import { buildCallGrant, callUnavailable } from '../server/call_grant.mjs';

const SECRET_HEX = '9f3a61c07be24d58a1c9e0374bd62f85d7013ac9e86b4f520c1d3e5f7a9b2d4f';
const NOW = new Date('2026-11-09T20:00:00Z');
const NOW_S = Math.floor(NOW.getTime() / 1000);
const CHILD = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', DAD = '11111111-1111-1111-1111-111111111111';
const session = { id: 'sess-golden', childId: CHILD, roomName: 's_goldenroomnameforvectorsonly', kind: 'call',
  createdBy: DAD, authorizedUserIds: [DAD, CHILD], ladderStep: 'open', recorded: false,
  createdAt: NOW.toISOString(), endedAt: null };
const edge = { childId: CHILD, userId: DAD, role: 'guardian', scope: {}, observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null, closedAt: null, ladderStep: null };
const mint = (p) => { const m = mintToken(session, p, [edge], NOW); if (!m.ok) throw new Error(m.reason); return m; };

export async function generate() {
  const jcfg = resolveCallConfig({ CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
    JITSI_APP_SECRET: SECRET_HEX, JITSI_SERVER_URL: 'https://192.168.1.50:8443' });
  const dad = mint({ userId: DAD, observerOnly: false, isChild: false, roleName: 'guardian' });
  const kid = mint({ userId: CHILD, observerOnly: false, isChild: true, roleName: 'child' });
  const g = (cfg, m, o) => buildCallGrant(cfg, m, { ...o, nowSeconds: NOW_S });
  const lk = await g(resolveCallConfig({ CALL_PROVIDER: 'livekit', LIVEKIT_URL: 'wss://x.invalid',
    LIVEKIT_API_KEY: 'devkey', LIVEKIT_API_SECRET: 'devsecret_at_least_32_chars_long_xx' }), dad,
    { displayName: 'Dad', isChild: false, observerOnly: false });
  return {
    appSecretHex: SECRET_HEX,
    vectors: [
      { label: 'jitsi, guardian starts (moderator)', body: { ...(await g(jcfg, dad, { displayName: 'Dad', isChild: false, observerOnly: false })), rang: false, sessionId: 'sess-golden' } },
      { label: 'jitsi, child joins (not moderator)', body: await g(jcfg, kid, { displayName: 'Ivy', isChild: true, observerOnly: false }) },
      { label: 'jitsi, observer-only guardian', body: { ...(await g(jcfg, dad, { displayName: 'Dad', isChild: false, observerOnly: true })), rang: false, sessionId: 'sess-golden' } },
      // The LiveKit token embeds the wall clock; only its shape is a vector.
      { label: 'livekit, guardian starts (token redacted)', body: { ...lk, token: 'redacted', rang: false, sessionId: 'sess-golden' } },
      { label: 'jitsi unavailable', status: callUnavailable({ provider: 'jitsi' }).status, body: callUnavailable({ provider: 'jitsi' }).body },
    ],
  };
}
if (process.argv[1]?.endsWith('gen-call-grant-vectors.mjs')) {
  const out = JSON.stringify({ generatedBy: 'tools/gen-call-grant-vectors.mjs', ...(await generate()) }, null, 1) + String.fromCharCode(10);
  if (process.argv.includes('--print')) process.stdout.write(out);
  else writeFileSync(new URL('../client/test/vectors/call_grant_vectors.json', import.meta.url), out);
}
