// OLIVE BRANCH — the provider-specific half of a call response (MASTERFILE
// §16.2 #6, third reversal). Split out of routes.mjs so the golden-vector
// generator (tools/gen-call-grant-vectors.mjs) and the route share ONE shape.
import { mintLiveKitToken } from '../packages/session-runtime/src/livekit-token.mjs';
import { randomBytes } from 'node:crypto';
import { iceGrantFor } from './call_ice.mjs';
import { mintJitsiToken, jitsiModeratorFor } from '../packages/session-runtime/src/jitsi-token.mjs';

/**
 * The provider-specific half of a call response. Jitsi: a short-lived,
 * per-participant HS256 JWT scoped to one derived room; the app secret never
 * leaves the process. LiveKit: unchanged token + wsURL. `provider` is added
 * to both so a client picks its engine from the grant, not from a build flag.
 */
export async function buildCallGrant(cfg, minted, { displayName, isChild, observerOnly, nowSeconds, role, sessionId }) {
  if (cfg.provider === 'lan-p2p') {
    // No media server and no token: the call is set up through the authenticated signalling routes. The grant
    // carries the ICE list (empty on the LAN) so a client never has one in its build. recorded is ALWAYS false:
    // nothing in this provider records, and the media never touches the server.
    const now = nowSeconds ?? Math.floor(Date.now() / 1000);
    const ice = iceGrantFor(cfg.lanP2p.ice, { nowSeconds: now, label: randomBytes(9).toString('base64url') });
    return {
      provider: 'lan-p2p', identity: minted.token.identity, displayName, role: role ?? 'caller',
      observerOnly: !!observerOnly, recorded: false, ...ice,
      expiresAt: now + minted.token.ttlSeconds,
      ...(sessionId ? { sessionId } : {}),
    };
  }
  if (cfg.provider === 'jitsi') {
    const moderator = jitsiModeratorFor({ isChild, observerOnly });
    const g = mintJitsiToken(minted.token, cfg.jitsi, { displayName, moderator }, nowSeconds);
    return {
      provider: 'jitsi', jwt: g.jwt, room: g.room, serverURL: cfg.jitsi.serverURL,
      identity: minted.token.identity, displayName, moderator, observerOnly, expiresAt: g.expiresAt,
    };
  }
  const token = await mintLiveKitToken(minted.token, cfg.livekit.apiKey, cfg.livekit.apiSecret);
  return { provider: 'livekit', token, wsURL: cfg.livekit.url, identity: minted.token.identity, displayName };
}
export const callUnavailable = (cfg) => cfg.provider === 'lan-p2p'
  ? { status: 503, body: { error: 'call_provider_unavailable', provider: 'lan-p2p' } }
  : cfg.provider === 'jitsi'
  ? { status: 503, body: { error: 'call_provider_unavailable', provider: 'jitsi' } }
  : { status: 500, body: { error: 'call_backend_unconfigured' } };
