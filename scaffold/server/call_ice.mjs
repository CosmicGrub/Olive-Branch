// OLIVE BRANCH - the ICE server list for the 'lan-p2p' call provider (MASTERFILE 16.2 #6, 5.21).
//
// The list is CONFIGURATION, not code, and it rides inside the authenticated call grant so a client never
// carries one in its build. On the home Wi-Fi the default is an EMPTY list: the two devices find each other with
// host candidates and no outside service is contacted. Across networks (a grown-up on cellular, a tablet on
// home Wi-Fi) the operator adds, in the server's environment or its gitignored .env, any of:
//
//   CALL_ICE_STUN_URLS        comma list of stun:/stuns: urls   (a public or self-hosted STUN)
//   CALL_ICE_TURN_URLS        comma list of turn:/turns: urls   (self-hosted coturn, a TURN service)
//   CALL_ICE_TURN_SECRET      shared secret of a TURN server run with `use-auth-secret` (coturn's
//                             static-auth-secret). The server then mints a SHORT-LIVED username and credential
//                             per participant (the TURN REST API shape), so no long-lived relay password ever
//                             reaches a device. THIS IS THE HOOK for a managed TURN: a provider that hands out
//                             credentials over its own API replaces mintTurnCredentials() below and nothing else.
//   CALL_ICE_TURN_USERNAME / CALL_ICE_TURN_CREDENTIAL
//                             a fixed pair, for a throwaway test TURN only (never used when a secret is set)
//   CALL_ICE_RELAY_ONLY=1     force every call through the TURN relay (hides each device's address from the other
//                             and is how the relay path is proven; needs TURN urls)
//   CALL_ICE_TTL_SECONDS      lifetime of a minted credential (default 600, 60..3600)
//
// Nothing here logs or returns a secret: describeIceConfig() gives counts and booleans only.
import { createHmac } from 'node:crypto';

const URL_RE = /^(stun|stuns|turn|turns):[A-Za-z0-9.\-\[\]:%]+(\?transport=(udp|tcp))?$/;
const MAX_URLS = 8;

function urlList(raw, kinds, name, problems) {
  if (!raw || !String(raw).trim()) return [];
  const out = [];
  for (const u of String(raw).split(',').map((x) => x.trim()).filter(Boolean)) {
    if (!URL_RE.test(u) || !kinds.includes(u.split(':')[0])) {
      problems.push(`${name} has an entry that is not a ${kinds.join('/')}: url`);
      continue;
    }
    out.push(u);
  }
  if (out.length > MAX_URLS) { problems.push(`${name} lists more than ${MAX_URLS} urls`); return out.slice(0, MAX_URLS); }
  return out;
}

/** Pure: env in, { stun, turn, secret, staticPair, relayOnly, ttlSeconds, problems }. */
export function resolveIceConfig(env = process.env) {
  const problems = [];
  const stun = urlList(env.CALL_ICE_STUN_URLS, ['stun', 'stuns'], 'CALL_ICE_STUN_URLS', problems);
  const turn = urlList(env.CALL_ICE_TURN_URLS, ['turn', 'turns'], 'CALL_ICE_TURN_URLS', problems);
  const secret = env.CALL_ICE_TURN_SECRET ? String(env.CALL_ICE_TURN_SECRET) : null;
  if (secret && secret.length < 16) problems.push('CALL_ICE_TURN_SECRET must be at least 16 characters');
  const user = env.CALL_ICE_TURN_USERNAME, cred = env.CALL_ICE_TURN_CREDENTIAL;
  const staticPair = !secret && user && cred ? { username: String(user), credential: String(cred) } : null;
  if (turn.length && !secret && !staticPair) problems.push('CALL_ICE_TURN_URLS needs CALL_ICE_TURN_SECRET (or a fixed username and credential)');
  if (!turn.length && (secret || staticPair)) problems.push('a TURN secret is set but CALL_ICE_TURN_URLS is empty');
  const relayOnly = /^(1|true|yes)$/i.test(String(env.CALL_ICE_RELAY_ONLY ?? ''));
  if (relayOnly && !turn.length) problems.push('CALL_ICE_RELAY_ONLY needs CALL_ICE_TURN_URLS');
  const t = Number(env.CALL_ICE_TTL_SECONDS);
  const ttlSeconds = Number.isFinite(t) && t >= 60 && t <= 3600 ? Math.floor(t) : 600;
  return {
    stun, turn, secret: secret && secret.length >= 16 ? secret : null, staticPair,
    relayOnly: relayOnly && turn.length > 0, ttlSeconds, problems,
  };
}

/** TURN REST API credentials: username "<expiry>:<label>", credential base64(HMAC-SHA1(secret, username)). */
export function mintTurnCredentials(secret, label, nowSeconds, ttlSeconds) {
  const username = `${nowSeconds + ttlSeconds}:${String(label).replace(/[^A-Za-z0-9_-]/g, '').slice(0, 24) || 'olive'}`;
  const credential = createHmac('sha1', secret).update(username).digest('base64');
  return { username, credential };
}

/**
 * What one participant gets inside the grant: { iceServers, iceTransportPolicy }. Empty on the LAN default. The
 * label identifies nobody (a random per-grant tag), so a TURN server's own log says nothing about a child.
 */
export function iceGrantFor(ice, { nowSeconds, label }) {
  const iceServers = [];
  if (ice.stun.length) iceServers.push({ urls: [...ice.stun] });
  if (ice.turn.length) {
    const pair = ice.secret ? mintTurnCredentials(ice.secret, label, nowSeconds, ice.ttlSeconds) : ice.staticPair;
    if (pair) iceServers.push({ urls: [...ice.turn], username: pair.username, credential: pair.credential });
  }
  return { iceServers, iceTransportPolicy: ice.relayOnly ? 'relay' : 'all' };
}

/** Safe to log and to return: counts and booleans only. */
export function describeIceConfig(ice) {
  return { stunUrls: ice.stun.length, turnUrls: ice.turn.length, mintsCredentials: !!ice.secret, relayOnly: ice.relayOnly };
}
