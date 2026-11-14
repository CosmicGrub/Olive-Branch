/**
 * Jitsi token minting — MASTERFILE §16.2 #6 (third reversal), §3.1 I1-I5, §17.3.
 * The JWT is verified here with an INDEPENDENT HS256 implementation (node:crypto
 * directly), the way a Jitsi prosody would, not by re-using the minter's helpers.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { createSession, mintToken, TOKEN_TTL_SECONDS } from '../src/rooms.mjs';
import { mintJitsiToken, jitsiRoomFor, jitsiModeratorFor, JITSI_AUDIENCE } from '../src/jitsi-token.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const NOW = new Date('2026-11-09T20:00:00Z');
const NOW_S = Math.floor(NOW.getTime() / 1000);
const CHILD = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const DAD = '11111111-1111-1111-1111-111111111111';
const edge = { childId: CHILD, userId: DAD, role: 'guardian', scope: {}, observerOnly: false, restricted: false,
  validFrom: '2020-01-01T00:00:00Z', validTo: null, expiresAt: null, closedAt: null, ladderStep: null };
const SECRET = Buffer.from('c3'.repeat(16) + 'a7'.repeat(16), 'hex');
const CFG = { appId: 'olive-calls', appSecret: SECRET, xmppDomain: 'meet.jitsi' };

const session = createSession({ childId: CHILD, kind: 'call', createdBy: DAD,
  authorizedUserIds: [DAD, CHILD], ladderStep: 'open' });
const mint = (principal) => {
  const m = mintToken(session, principal, [edge], NOW);
  if (!m.ok) throw new Error(m.reason);
  return m.token;
};
const dadTok = mint({ userId: DAD, observerOnly: false, isChild: false, roleName: 'guardian' });
const childTok = mint({ userId: CHILD, observerOnly: false, isChild: true, roleName: 'child' });

function verify(jwt, secret) {
  const [h, b, s] = jwt.split('.');
  const want = createHmac('sha256', secret).update(`${h}.${b}`).digest();
  const got = Buffer.from(s, 'base64url');
  const sigOk = want.length === got.length && timingSafeEqual(want, got);
  return { sigOk, head: JSON.parse(Buffer.from(h, 'base64url')), claims: JSON.parse(Buffer.from(b, 'base64url')) };
}

{
  const g = mintJitsiToken(dadTok, CFG, { displayName: 'Dad', moderator: true }, NOW_S);
  const v = verify(g.jwt, SECRET);
  check('claims', 'signature verifies with the app secret (HS256)', v.sigOk, true);
  check('claims', 'header is exactly HS256/JWT', JSON.stringify(v.head), JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  check('claims', 'iss is the Jitsi app id', v.claims.iss, 'olive-calls');
  check('claims', 'aud is the audience the stack accepts', v.claims.aud, JITSI_AUDIENCE);
  check('claims', 'sub is the XMPP domain', v.claims.sub, 'meet.jitsi');
  check('claims', 'room claim is the derived room, never a wildcard', v.claims.room === g.room && v.claims.room !== '*', true);
  check('claims', 'user id is the authenticated identity (I3)', v.claims.context.user.id, DAD);
  check('claims', 'moderator is a real boolean', typeof v.claims.context.user.moderator, 'boolean');
  check('claims', 'no email or avatar claim', ['email', 'avatar'].some((k) => k in v.claims.context.user), false);
  check('claims', 'no age or birth key anywhere in the payload',
    /age|birth|dob/i.test(JSON.stringify(Object.keys(v.claims.context.user))), false);
  check('claims', 'recording/livestream/screen-share/outbound/transcription all off',
    Object.values(v.claims.context.features).every((x) => x === false) && Object.keys(v.claims.context.features).length >= 5, true);
  check('claims', 'no secret material appears in the token body',
    JSON.stringify(v.claims).includes(SECRET.toString('hex')), false);
}

{
  const g = mintJitsiToken(dadTok, CFG, { displayName: 'Dad', moderator: true }, NOW_S);
  const c = verify(g.jwt, SECRET).claims;
  check('expiry', 'exp is now + the I5 TTL (minutes, not hours)', c.exp - NOW_S, TOKEN_TTL_SECONDS);
  check('expiry', 'TTL is no more than 15 minutes', TOKEN_TTL_SECONDS <= 15 * 60, true);
  check('expiry', 'nbf allows a little clock skew but is not far in the past', NOW_S - c.nbf <= 30 && c.nbf < NOW_S, true);
  check('expiry', 'expiresAt in the grant matches the claim', g.expiresAt, c.exp);
}

{
  const gd = mintJitsiToken(dadTok, CFG, { displayName: 'Dad', moderator: true }, NOW_S);
  const gc = mintJitsiToken(childTok, CFG, { displayName: 'Ivy', moderator: false }, NOW_S);
  check('room', 'both participants land in the same Jitsi room', gd.room, gc.room);
  check('room', 'room is lowercase alphanumeric (Jitsi lowercases room names)', /^[a-z0-9]{20,64}$/.test(gd.room), true);
  check('room', 'room differs from the session room name', gd.room !== session.roomName, true);
  check('room', 'room does not contain the session room name, child id or user id',
    [session.roomName, session.roomName.toLowerCase(), CHILD, DAD, CHILD.replace(/-/g, '')].some((s) => gd.room.includes(s)), false);
  check('room', 'derivation is deterministic (join route re-derives the same room)',
    jitsiRoomFor(session.roomName, SECRET), gd.room);
  check('room', 'a different app secret gives a different room (capability needs the secret)',
    jitsiRoomFor(session.roomName, Buffer.alloc(32, 9)) === gd.room, false);
  const other = createSession({ childId: CHILD, kind: 'call', createdBy: DAD, authorizedUserIds: [DAD], ladderStep: 'open' });
  check('room', 'two sessions never share a room', jitsiRoomFor(other.roomName, SECRET) === gd.room, false);
}

{
  check('moderator', 'an adult who can publish moderates', jitsiModeratorFor({ isChild: false, observerOnly: false }), true);
  check('moderator', 'the child never moderates', jitsiModeratorFor({ isChild: true, observerOnly: false }), false);
  check('moderator', 'an observer-only guardian never moderates', jitsiModeratorFor({ isChild: false, observerOnly: true }), false);
  check('moderator', 'a child flagged observer is still not a moderator', jitsiModeratorFor({ isChild: true, observerOnly: true }), false);
  const gc = mintJitsiToken(childTok, CFG, { displayName: 'Ivy', moderator: jitsiModeratorFor({ isChild: true, observerOnly: false }) }, NOW_S);
  check('moderator', 'the child token carries moderator:false on the wire', verify(gc.jwt, SECRET).claims.context.user.moderator, false);
}

{
  const g = mintJitsiToken(dadTok, CFG, { displayName: 'Dad', moderator: true }, NOW_S);
  check('secrets', 'a token does not verify under a different secret', verify(g.jwt, Buffer.alloc(32, 1)).sigOk, false);
  const tampered = g.jwt.split('.');
  tampered[1] = Buffer.from(JSON.stringify({ ...verify(g.jwt, SECRET).claims, room: '*' })).toString('base64url');
  check('secrets', 'editing the room claim breaks the signature', verify(tampered.join('.'), SECRET).sigOk, false);
  check('secrets', 'the returned object exposes only jwt/room/expiresAt', Object.keys(g).sort().join(','), 'expiresAt,jwt,room');
  check('secrets', 'a utf8 string secret and the same bytes agree',
    mintJitsiToken(dadTok, { ...CFG, appSecret: 'plain-secret' }, { displayName: 'Dad', moderator: true }, NOW_S).jwt
    === mintJitsiToken(dadTok, { ...CFG, appSecret: Buffer.from('plain-secret') }, { displayName: 'Dad', moderator: true }, NOW_S).jwt, true);
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
