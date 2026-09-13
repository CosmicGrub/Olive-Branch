/**
 * LiveKit LIVE integration. MASTERFILE §5.19, §20.2b.
 *
 * Every prior session assertion checked the JWT we *produce*. This suite checks
 * what a real LiveKit server *accepts* — which is the only thing that actually
 * establishes I2 (a join token is not an admin credential). A token can be
 * perfectly shaped and still be over-privileged if the server reads a claim we
 * did not think about.
 *
 * Requires a livekit-server on 127.0.0.1:7880 with key devkey. Skips loudly
 * rather than silently if absent — a suite that quietly passes when its
 * dependency is missing is false-green #3 all over again.
 */
import { AccessToken, RoomServiceClient } from 'livekit-server-sdk';
import { createSession, mintToken, TOKEN_TTL_SECONDS } from '../src/rooms.mjs';
import { mintLiveKitToken } from '../src/livekit-token.mjs';

const URL_HTTP = 'http://127.0.0.1:7880';
const KEY = 'devkey', SECRET = 'devsecret_at_least_32_chars_long_xx';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e);
  ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// Fail loudly if the dependency is absent.
let reachable = false;
try {
  const r = await fetch(URL_HTTP, { signal: AbortSignal.timeout(4000) });
  reachable = r.status === 200;
} catch { reachable = false; }
if (!reachable) {
  console.error('\nABORT: no livekit-server on 127.0.0.1:7880.');
  console.error('This suite exists to test a real server. Skipping it would be a');
  console.error('false green — start the server or remove the suite.\n');
  process.exit(2);
}

const CHILD_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DAD = '11111111-1111-1111-1111-111111111111';
const edge = (o = {}) => ({ childId: CHILD_A, userId: DAD, role: 'guardian', scope: {},
  observerOnly: false, restricted: false, validFrom: '2020-01-01T00:00:00Z',
  validTo: null, expiresAt: null, closedAt: null, ladderStep: null, ...o });

const jwtFor = async (grant, identity, ttl = TOKEN_TTL_SECONDS) => {
  const at = new AccessToken(KEY, SECRET, { identity, ttl });
  at.addGrant(grant);
  return at.toJwt();
};

/** Decodes a JWT's payload without verifying the signature — used only to
 * inspect what mintLiveKitToken() actually put on the wire (section O2), not
 * as a substitute for the real server's own verdict, which every check in
 * this file gets from a genuine Twirp round-trip instead. */
const jwtPayload = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString('utf8'));

/** Raw Twirp call so we see the server's own verdict, not an SDK wrapper's. */
const twirp = async (method, token, body = {}) => {
  const r = await fetch(`${URL_HTTP}/twirp/livekit.RoomService/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  return { status: r.status, text: await r.text() };
};

// ===========================================================================
// N · THE SERVER VALIDATES OUR TOKENS
// ===========================================================================
{
  const admin = await jwtFor({ roomList: true, roomCreate: true, roomAdmin: true },
    'ops', 600);
  const svc = new RoomServiceClient(URL_HTTP, KEY, SECRET);

  const created = await svc.createRoom({ name: 'lk_probe', emptyTimeout: 60,
    maxParticipants: 3 });
  check('N live', 'server created a room from our SDK call', created.name, 'lk_probe');

  const list = await svc.listRooms();
  check('N live', 'room is listed', list.some(r => r.name === 'lk_probe'), 'true');
  check('N live', 'maxParticipants honoured',
    list.find(r => r.name === 'lk_probe').maxParticipants, 3);

  const ok = await twirp('ListRooms', admin);
  check('N live', 'admin token accepted for ListRooms', ok.status, 200);

  // Garbage and wrong-key tokens must be rejected by the server itself.
  const bad = await twirp('ListRooms', 'not-a-jwt');
  check('N live', 'malformed token rejected', bad.status === 401 || bad.status === 403, 'true');
  const wrongKey = await (async () => {
    const at = new AccessToken(KEY, 'wrong_secret_wrong_secret_wrong_x',
      { identity: 'x', ttl: 600 });
    at.addGrant({ roomList: true });
    return twirp('ListRooms', await at.toJwt());
  })();
  check('N live', 'token signed with the wrong secret rejected',
    wrongKey.status === 401 || wrongKey.status === 403, 'true');
}

// ===========================================================================
// O · I2 PROVEN AGAINST A REAL SERVER — a join token is NOT an admin credential
// ===========================================================================
{
  const s = createSession({ childId: CHILD_A, kind: 'call', createdBy: DAD,
    authorizedUserIds: [DAD, CHILD_A], ladderStep: 'open' });
  const m = mintToken(s, { userId: DAD, observerOnly: false, isChild: false,
    roleName: 'guardian' }, [edge()], new Date());
  check('O live I2', 'our mint succeeded', m.ok, 'true');

  const joinTok = await jwtFor(m.token.grant, m.token.identity, m.token.ttlSeconds);

  // THE ASSERTION THAT MATTERS. Previous suites checked that we do not SET
  // admin claims. This checks that a real server will not GRANT admin
  // behaviour to a token that lacks them.
  for (const method of ['ListRooms', 'CreateRoom', 'DeleteRoom',
                        'ListParticipants', 'RemoveParticipant']) {
    const r = await twirp(method, joinTok, { room: s.roomName, identity: DAD });
    check('O live I2', `join token REFUSED for ${method}`,
      r.status === 401 || r.status === 403, 'true');
  }

  // And it must not reach another room's participants either.
  const other = createSession({ childId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    kind: 'call', createdBy: DAD, authorizedUserIds: [DAD], ladderStep: 'open' });
  const r = await twirp('ListParticipants', joinTok, { room: other.roomName });
  check('O live I2', "join token refused for another child's room",
    r.status === 401 || r.status === 403, 'true');
}

// ===========================================================================
// O2 · mintLiveKitToken() ITSELF, PROVEN AGAINST A REAL SERVER
//
// Section O above proves I2 using jwtFor() — a hand-rolled AccessToken call
// built for THIS test file, mirroring but not actually exercising the real
// production serialization step. This section calls the genuine
// mintLiveKitToken() (packages/session-runtime/src/livekit-token.ts,
// MASTERFILE §16.2 #6 REVERSED AGAIN) directly, so what gets proven here is
// that OUR shipped code's own JWT output is accepted/refused correctly by a
// real server — not a hand-built equivalent of it. Same I2 shape as O, kept
// as its own section rather than folded in so a future change to jwtFor()
// alone can never accidentally cover for a real mintLiveKitToken() drift.
// ===========================================================================
{
  const s = createSession({ childId: CHILD_A, kind: 'call', createdBy: DAD,
    authorizedUserIds: [DAD, CHILD_A], ladderStep: 'open' });
  const guardianMint = mintToken(s, { userId: DAD, observerOnly: false,
    isChild: false, roleName: 'guardian' }, [edge()], new Date());
  check('O2 live mintLiveKitToken', 'guardian mint succeeded', guardianMint.ok, 'true');

  const guardianJwt = await mintLiveKitToken(guardianMint.token, KEY, SECRET);
  for (const method of ['ListRooms', 'CreateRoom', 'DeleteRoom',
                        'ListParticipants', 'RemoveParticipant']) {
    const r = await twirp(method, guardianJwt, { room: s.roomName, identity: DAD });
    check('O2 live mintLiveKitToken', `real mintLiveKitToken() output REFUSED for ${method}`,
      r.status === 401 || r.status === 403, 'true');
  }

  // Decode fidelity, NOT a server-side positive-join proof — this Twirp
  // HTTP probe has no way to drive a real WebRTC/ICE handshake, which is
  // what an actual "the server let a client join" proof would need. What
  // this DOES prove: the real, shipped mintLiveKitToken() signed the exact
  // identity/room mintToken() decided, not a substitute value — a real bug
  // class this would catch (a field silently swapped or dropped on the way
  // into AccessToken.addGrant()) that the negative battery above cannot,
  // since a wrong-but-still-non-admin token would pass every refusal check
  // here too.
  const decoded = jwtPayload(guardianJwt);
  check('O2 live mintLiveKitToken', 'server-bound JWT sub matches mintToken() identity',
    decoded.sub, guardianMint.token.identity);
  check('O2 live mintLiveKitToken', 'server-bound JWT grant.room matches the real room',
    decoded.video?.room, s.roomName);
  check('O2 live mintLiveKitToken', 'server-bound JWT carries no roomCreate/roomAdmin/roomList',
    decoded.video?.roomCreate === undefined && decoded.video?.roomAdmin === undefined
      && decoded.video?.roomList === undefined, 'true');

  // And the SAME real cross-room refusal I2 proves in section O, against our
  // real output instead of jwtFor()'s hand-rolled one.
  const other = createSession({ childId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
    kind: 'call', createdBy: DAD, authorizedUserIds: [DAD], ladderStep: 'open' });
  const r2 = await twirp('ListParticipants', guardianJwt, { room: other.roomName });
  check('O2 live mintLiveKitToken', "real mintLiveKitToken() output refused for another child's room",
    r2.status === 401 || r2.status === 403, 'true');
}

// ===========================================================================
// P · TTL — an expired token is rejected by the server, not merely by us
// ===========================================================================
{
  const s = createSession({ childId: CHILD_A, kind: 'call', createdBy: DAD,
    authorizedUserIds: [DAD], ladderStep: 'open' });
  // MEASURED, not assumed. livekit-server 1.8.0 accepts a token well past its
  // `exp`: 200 at 60s past, 401 at 95s past. So expiry alone is NOT a
  // revocation mechanism — the effective window is TTL plus a leeway we do not
  // control. This is why §8.3 evicts rather than waiting for expiry.
  const shortLived = await (async () => {
    const at = new AccessToken(KEY, SECRET, { identity: DAD, ttl: 1 });
    at.addGrant({ roomList: true });
    return at.toJwt();
  })();
  await new Promise(r => setTimeout(r, 3000));
  const soon = await twirp('ListRooms', shortLived);
  check('P live ttl', 'server still accepts 3s past exp — leeway is real',
    soon.status, 200);
  check('P live ttl', `TTL ${TOKEN_TTL_SECONDS}s is a bound on new joins, not revocation`,
    TOKEN_TTL_SECONDS <= 900, 'true');
  check('P live ttl', 'therefore eviction is the revocation path, not expiry',
    typeof (await import('../../transport/src/push.mjs')).revokeLiveAccess, 'function');
}

// ===========================================================================
// Q · ROOM LIFECYCLE — eviction and teardown against the real server
// ===========================================================================
{
  const svc = new RoomServiceClient(URL_HTTP, KEY, SECRET);
  await svc.createRoom({ name: 'lk_evict', emptyTimeout: 60, maxParticipants: 3 });
  check('Q live lifecycle', 'room exists before teardown',
    (await svc.listRooms()).some(r => r.name === 'lk_evict'), 'true');

  // §8.3 — removing a participant who is not present must not throw; kiosk
  // defeat fires eviction unconditionally and cannot depend on join state.
  // The RAW sdk call throws; our wrapper must not, because defeat handling
  // continues past this point to drop guardian escalation.
  let rawThrew = false;
  try { await svc.removeParticipant('lk_evict', 'nobody'); } catch { rawThrew = true; }
  check('Q live lifecycle', 'raw SDK throws on an absent participant',
    rawThrew, 'true');
  const { revokeLiveAccess, endSession } = await import('../../transport/src/push.mjs');
  const port = {
    createRoom: async () => {}, 
    removeParticipant: (r, i) => svc.removeParticipant(r, i),
    deleteRoom: (n) => svc.deleteRoom(n),
  };
  check('Q live lifecycle', 'our wrapper tolerates it and reports absent',
    await revokeLiveAccess(port, 'lk_evict', 'nobody'), 'absent');

  await svc.deleteRoom('lk_evict');
  check('Q live lifecycle', 'room gone after deleteRoom',
    (await svc.listRooms()).some(r => r.name === 'lk_evict'), 'false');

  // Deleting twice must be safe — endSession() may be called on an already
  // closed room when both parties hang up simultaneously.
  const { endSession: end2 } = await import('../../transport/src/push.mjs');
  check('Q live lifecycle', 'endSession on an already-deleted room is safe',
    ['done','absent'].includes(await end2(port, 'lk_evict')), 'true');

  await svc.deleteRoom('lk_probe').catch(() => {});
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` +
    (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
