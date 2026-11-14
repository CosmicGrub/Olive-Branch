import { createHmac } from 'node:crypto';
import type { MintedToken } from './rooms.ts';

/**
 * MASTERFILE §16.2 #6 REVERSED a third time (2026-11-09): self-hosted Jitsi
 * is the default call provider again; LiveKit stays selectable
 * (CALL_PROVIDER=livekit, see livekit-token.ts).
 *
 * Like mintLiveKitToken(), this is pure serialization of a decision rooms.ts
 * already made. mintToken() ran I1-I5 (authorization, membership, TTL); this
 * only turns that outcome into the JWT a Jitsi prosody (mod_token_verification)
 * accepts. It makes no authorization decision and must never gain one.
 *
 * What a Jitsi token can and cannot carry, stated honestly:
 *  - It CAN scope one room (`room` claim, never '*'), expire (I5), name a
 *    moderator, and switch off features (recording, livestreaming,
 *    screen-sharing, outbound calls, transcription).
 *  - It CANNOT express LiveKit's canPublish:false. An observer-only guardian
 *    (§17.3) therefore gets `moderator:false` plus `observerOnly:true` in the
 *    route response, and the client joins muted with a hang-up-only toolbar.
 *    That is advisory on Jitsi, enforced on LiveKit. Disclosed in MASTERFILE.
 *
 * The Jitsi room name is NOT the session room name. Jitsi lowercases room
 * names, and base64url room names are mixed-case. It is derived as
 * HMAC-SHA256(appSecret, sessionRoomName), lowercase hex, so it is (a)
 * lowercase-safe, (b) unguessable even to someone who has seen the session
 * room name (the call_incoming push carries that handle), and (c)
 * deterministic, so the join route re-derives the same room.
 */

export interface JitsiConfig {
  appId: string;
  /** Raw secret bytes (hex-decoded) or the utf8 string; never logged. */
  appSecret: Buffer | string;
  /** XMPP domain of the stack (docker-jitsi-meet default "meet.jitsi"). */
  xmppDomain: string;
}

export interface JitsiGrantInput {
  displayName: string;
  /** Adults who participate are moderators; the child and observers are not. */
  moderator: boolean;
}

/** Audience the self-hosted stack is configured to accept (JWT_ACCEPTED_AUDIENCES). */
export const JITSI_AUDIENCE = 'jitsi';

const b64u = (b: Buffer | string) => Buffer.from(b).toString('base64url');

export function jitsiRoomFor(sessionRoomName: string, appSecret: Buffer | string): string {
  return 'o' + createHmac('sha256', appSecret).update(`olive-jitsi-room:${sessionRoomName}`).digest('hex').slice(0, 40);
}

/**
 * Moderator rule for a child call: an adult who can publish moderates; a
 * child never does; an observer-only guardian never does.
 */
export function jitsiModeratorFor(p: { isChild: boolean; observerOnly: boolean }): boolean {
  return !p.isChild && !p.observerOnly;
}

export function mintJitsiToken(
  token: MintedToken,
  cfg: JitsiConfig,
  input: JitsiGrantInput,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): { jwt: string; room: string; expiresAt: number } {
  const room = jitsiRoomFor(token.room, cfg.appSecret);
  const exp = nowSeconds + token.ttlSeconds;            // I5
  const claims = {
    iss: cfg.appId,
    aud: JITSI_AUDIENCE,
    sub: cfg.xmppDomain,
    room,                                               // I2 — exactly one room
    nbf: nowSeconds - 10,
    iat: nowSeconds,
    exp,
    context: {
      user: {
        id: token.identity,                             // I3 — never client-supplied
        name: input.displayName,
        moderator: input.moderator,
      },
      features: {
        recording: false,
        livestreaming: false,
        'screen-sharing': false,
        'outbound-call': false,
        'sip-outbound-call': false,
        transcription: false,
      },
    },
  };
  const head = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64u(JSON.stringify(claims));
  const sig = createHmac('sha256', cfg.appSecret).update(`${head}.${body}`).digest('base64url');
  return { jwt: `${head}.${body}.${sig}`, room, expiresAt: exp };
}
