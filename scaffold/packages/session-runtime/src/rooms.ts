import { randomBytes } from 'node:crypto';
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
 */

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
  hidden?: boolean;
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
    id: randomBytes(16).toString('hex'),
    childId: input.childId,
    roomName,
    kind: input.kind,
    createdBy: input.createdBy,
    authorizedUserIds: [...new Set(input.authorizedUserIds)],
    ladderStep: input.ladderStep,
    // §5.15 — `supervised` means the advancing professional reviews the session.
    // `monitored` is explicitly NOT recorded; they may join unannounced instead.
    recorded: input.ladderStep === 'supervised',
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
