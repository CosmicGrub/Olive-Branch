import { AccessToken } from "livekit-server-sdk";
async function mintLiveKitToken(token, apiKey, apiSecret) {
  const at = new AccessToken(apiKey, apiSecret, {
    identity: token.identity,
    ttl: token.ttlSeconds
  });
  at.addGrant({
    roomJoin: token.grant.roomJoin,
    room: token.grant.room,
    canPublish: token.grant.canPublish,
    canSubscribe: token.grant.canSubscribe,
    canPublishData: token.grant.canPublishData,
    canUpdateOwnMetadata: token.grant.canUpdateOwnMetadata,
    hidden: token.grant.hidden
  });
  return at.toJwt();
}
export {
  mintLiveKitToken
};
