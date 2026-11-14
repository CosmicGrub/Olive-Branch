// OLIVE BRANCH — the provider-specific half of a call response (MASTERFILE
// §16.2 #6, third reversal). Split out of routes.mjs so the golden-vector
// generator (tools/gen-call-grant-vectors.mjs) and the route share ONE shape.
import { mintLiveKitToken } from '../packages/session-runtime/src/livekit-token.mjs';
import { mintJitsiToken, jitsiModeratorFor } from '../packages/session-runtime/src/jitsi-token.mjs';

/**
 * The provider-specific half of a call response. Jitsi: a short-lived,
 * per-participant HS256 JWT scoped to one derived room; the app secret never
 * leaves the process. LiveKit: unchanged token + wsURL. `provider` is added
 * to both so a client picks its engine from the grant, not from a build flag.
 */
export async function buildCallGrant(cfg, minted, { displayName, isChild, observerOnly, nowSeconds }) {
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
export const callUnavailable = (cfg) => cfg.provider === 'jitsi'
  ? { status: 503, body: { error: 'call_provider_unavailable', provider: 'jitsi' } }
  : { status: 500, body: { error: 'call_backend_unconfigured' } };
