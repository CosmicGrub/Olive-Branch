import { AccessToken } from 'livekit-server-sdk';
import type { MintedToken } from './rooms.ts';

/**
 * MASTERFILE §16.2 #6 REVERSED AGAIN — LiveKit Cloud replaces self-hosted
 * Jitsi. See docs/superpowers/specs/2026-08-29-livekit-call-migration-design
 * .md for the full account of why.
 *
 * Pure serialization, not a new authorization decision: `mintToken()` in
 * rooms.ts already ran every real check (I1-I5) and computed `token.grant`
 * in LiveKit's own AccessToken grant shape — confirmed directly by reading
 * both `Grant` here and `VideoGrant` in livekit-server-sdk's own
 * grants.d.ts, field for field: roomJoin, room, canPublish, canSubscribe,
 * canPublishData, canUpdateOwnMetadata, hidden all match. This function's
 * only job is turning that already-decided grant into a real, signed JWT a
 * LiveKit server will accept — it makes no decision of its own, and must
 * never gain one. If a grant ever needs to change, that change belongs in
 * rooms.ts's deriveGrant(), not here.
 *
 * `token.ttlSeconds` (I5 — minutes, not hours) is passed straight through
 * as the JWT's own `ttl`; a LiveKit AccessToken with no TTL set does not
 * expire, which would silently violate I5 for every call this mints.
 */
export async function mintLiveKitToken(
  token: MintedToken,
  apiKey: string,
  apiSecret: string,
): Promise<string> {
  const at = new AccessToken(apiKey, apiSecret, {
    identity: token.identity,
    ttl: token.ttlSeconds,
  });
  at.addGrant({
    roomJoin: token.grant.roomJoin,
    room: token.grant.room,
    canPublish: token.grant.canPublish,
    canSubscribe: token.grant.canSubscribe,
    canPublishData: token.grant.canPublishData,
    canUpdateOwnMetadata: token.grant.canUpdateOwnMetadata,
    hidden: token.grant.hidden,
  });
  return at.toJwt();
}
