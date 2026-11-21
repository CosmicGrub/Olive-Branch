import { randomBytes, randomUUID } from 'node:crypto';
import { can, type Edge, type LadderStep } from '../../family-graph/src/authorize.ts';

/**
 * MASTERFILE §3.1 — the session runtime. Video is one layer of a synchronized
 * session, not a feature of its own.
 *
 * Security invariants this module exists to hold:
 *
 *  I1  A room name is NEVER derived from a child id, user id, or anything else
 *      an attacker can guess or enumerate. It is random and stored server-side.
 *  I2  A token carries `roomJoin` for exactly ONE room. Never roomAdmin,
 *      roomCreate, roomList, or ingressAdmin.
 *  I3  `identity` is the authenticated principal. A client-supplied identity is
 *      an impersonation primitive.
 *  I4  A token is minted only after `can('call', ...)` passes for the specific
 *      child. Room membership is not authorization.
 *  I5  TTL is minutes, not hours. A defeated kiosk (§8.3) leaks whatever the
 *      token still allows.
 *  I6  Nobody is ever in a room unseen. No grant is ever `hidden`, no step of the
 *      ladder lets an adult (guardian, professional, observer) join without the
 *      other people in the room being able to see that they are there, and no
 *      session is marked `recorded` while there is nowhere to tell the people in
 *      it. The client shows every join and leave and a persistent count of who is
 *      present, observers included (call_roster.dart).
 */

/**
 * Whether there is a surface that tells everyone in a call it is being recorded, and a way to say no to it. There is not
 * one yet, so nothing is recorded and no session claims to be: `recorded` is forced false in [createSession]. This
 * constant is the single switch; flipping it is a deliberate change that has to arrive with the notice surface, its
 * wording and the consent step, not before.
 */
export const RECORDING_NOTICE_SURFACE_EXISTS = false;

export type SessionKind = 'call' | 'homework' | 'game' | 'canvas' | 'storybook';

export interface SessionRecord {
  id: string;
  childId: string;
  /** I1 — opaque. Not `child:<uuid>`. */
  roomName: string;
  kind: SessionKind;
  createdBy: string;
  /** Only these principals may be issued a token for this room. */
  authorizedUserIds: string[];
  /** §5.15 — drives recording and observer policy. */
  ladderStep: LadderStep;
  recorded: boolean;
  createdAt: string;
  endedAt: string | null;
}

export interface Grant {
  roomJoin: true;
  room: string;
  canPublish: boolean;
  canSubscribe: boolean;
  canPublishData: boolean;
  canUpdateOwnMetadata: false;
  /** Never true: there is no way to be present in a room unseen (I6). Absent or false only. */
  hidden?: false;
}

export interface MintedToken {
  identity: string;
  room: string;
  grant: Grant;
  ttlSeconds: number;
  recorded: boolean;
  disclosure: string | null;
}

export type MintDenial =
  | 'not_authorized'
  | 'not_a_participant'
  | 'session_ended'
  | 'ladder_none';

/** I5 — short enough that a leaked token expires before it is useful. */
export const TOKEN_TTL_SECONDS = 10 * 60;

/** I1 — 32 bytes of randomness, no embedded identifiers. */
export function newRoomName(): string {
  return `s_${randomBytes(24).toString('base64url')}`;
}

/**
 * Guard against a room name that leaks or embeds an identifier. Used in tests
 * and as a runtime assertion when creating a session.
 */
export function roomNameLeaks(roomName: string, secrets: string[]): boolean {
  const hay = roomName.toLowerCase();
  return secrets.some(s => {
    const n = s.toLowerCase().replace(/-/g, '');
    return n.length >= 6 && (hay.includes(s.toLowerCase()) || hay.includes(n));
  });
}

export function createSession(input: {
  childId: string;
  kind: SessionKind;
  createdBy: string;
  authorizedUserIds: string[];
  ladderStep: LadderStep;
}): SessionRecord {
  if (input.ladderStep === 'none') {
    throw new Error('ladder step none: no session may be created');
  }
  const roomName = newRoomName();
  // Runtime assertion, not just a test. Cheap, and the failure mode is severe.
  if (roomNameLeaks(roomName, [input.childId, input.createdBy])) {
    throw new Error('room name leaks an identifier');
  }
  return {
    // A canonical dashed uuid, NOT 32 bare hex: the id is returned to the client as
    // `sessionId` and comes back as the :sessionId path segment of .../join and
    // .../end, which the strict-ids guard (api.ts UUID_PARAMS, on in production)
    // refuses with 400 bad_path unless it is a dashed uuid. A bare-hex id made
    // every started call impossible to join or end through the real server
    // (found by tools/family-sim as gap G7). Still unguessable (122 random bits);
    // call_log.id is text, so it stores either form.
    id: randomUUID(),
    childId: input.childId,
    roomName,
    kind: input.kind,
    createdBy: input.createdBy,
    authorizedUserIds: [...new Set(input.authorizedUserIds)],
    ladderStep: input.ladderStep,
    // §5.15 — `supervised` is the step that would be recorded, but nothing records and no notice surface exists to
    // tell the people in the call, so the flag stays false until RECORDING_NOTICE_SURFACE_EXISTS is true. No step
    // lets anyone join unseen: presence is visible to everyone in the room (I6).
    recorded: RECORDING_NOTICE_SURFACE_EXISTS && input.ladderStep === 'supervised',
    createdAt: new Date().toISOString(),
    endedAt: null,
  };
}

/**
 * Derive the grant for one principal in one session.
 *
 * §17.3 — an observer-only guardian gets `canPublish: false`. The observer tier
 * is "watch your kid's drawings without obligation", and a parent whose camera
 * and microphone are live in the room IS participating. Subscribe-only is what
 * the tier actually promises.
 */
export function deriveGrant(
  session: SessionRecord,
  principal: { userId: string; observerOnly: boolean; isChild: boolean },
): Grant {
  const publish = !principal.observerOnly;
  return {
    roomJoin: true,
    room: session.roomName,                 // I2 — exactly one room
    canPublish: publish,
    canSubscribe: true,
    canPublishData: publish,                // activity-module state sync
    canUpdateOwnMetadata: false,            // no self-renaming in a child's room
    ...(principal.observerOnly ? { hidden: false } : {}),
  };
}

/**
 * I4 — authorization first, then membership, then a grant.
 * Returns a denial rather than throwing so the caller can log the reason.
 */
export function mintToken(
  session: SessionRecord,
  principal: {
    userId: string; observerOnly: boolean; isChild: boolean;
    roleName?: string;
  },
  edges: Edge[],
  now: Date,
): { ok: true; token: MintedToken } | { ok: false; reason: MintDenial } {
  if (session.endedAt) return { ok: false, reason: 'session_ended' };
  if (session.ladderStep === 'none') return { ok: false, reason: 'ladder_none' };

  // I4. Membership in `authorizedUserIds` is NOT sufficient — the edge is
  // re-evaluated at mint time, so a revoked parent cannot ride a stale list.
  if (!principal.isChild) {
    const d = can('call', edges, session.childId, now, principal.roleName);
    if (!d.allow) return { ok: false, reason: 'not_authorized' };
  }
  if (!session.authorizedUserIds.includes(principal.userId)) {
    return { ok: false, reason: 'not_a_participant' };
  }

  return {
    ok: true,
    token: {
      identity: principal.userId,           // I3 — never client-supplied
      room: session.roomName,
      grant: deriveGrant(session, principal),
      ttlSeconds: TOKEN_TTL_SECONDS,
      recorded: session.recorded,
      // §10.5 — recording is disclosed to every participant, in language the
      // child can understand. A court-ordered supervised visit is lawful to
      // record; it is never silent.
      disclosure: session.recorded
        ? 'This visit is being recorded and can be watched later by the person '
          + 'helping your family.'
        : null,
    },
  };
}

/** Claims a LiveKit token must carry, and must not. Asserted in tests. */
export const FORBIDDEN_GRANTS = [
  'roomAdmin', 'roomCreate', 'roomList', 'roomRecord',
  'ingressAdmin', 'recorder', 'agent',
] as const;
