/**
 * MASTERFILE §11 — push and call transport.
 *
 * THE RULE THIS MODULE EXISTS TO ENFORCE: a push notification carries NO
 * content. Not the message body, not the sender's name, not the activity.
 *
 * A lock-screen banner reading "Goodnight video from Dad" discloses, to anyone
 * holding the tablet, that this child has a parent who lives elsewhere and what
 * time she goes to bed. On a child's device — frequently shared, frequently left
 * on a kitchen table — that is a disclosure of family structure to whoever picks
 * it up. Under the amended COPPA Rule the routine itself is regulated
 * information about a child.
 *
 * So the payload is a pointer. The client fetches content after unlock, through
 * the authenticated API, under the RLS session context.
 */

export type Platform = 'android' | 'ios';
export type PushKind = 'call_incoming' | 'message_ready' | 'turn_ready'
                     | 'exchange_reminder' | 'dose_due';

export interface PushInput {
  kind: PushKind;
  platform: Platform;
  deviceToken: string;
  /** Opaque handle the client exchanges for content, post-unlock. */
  ref: string;
  /** Present ONLY for call_incoming, which must ring rather than notify. */
  callRoomHandle?: string;
  collapseKey?: string;
}

export interface PushPayload {
  token: string;
  /** Content-free by construction. */
  data: Record<string, string>;
  /** Non-null only where the OS requires visible text; then it is generic. */
  notification: { title: string; body: string } | null;
  android?: {
    priority: 'high' | 'normal';
    fullScreenIntent: boolean;
    channelId: string;
    collapseKey?: string;
  };
  apns?: {
    pushType: 'voip' | 'alert' | 'background';
    priority: 10 | 5;
    topicSuffix?: string;
    contentAvailable?: boolean;
    interruptionLevel?: 'active' | 'time-sensitive' | 'critical';
  };
}

/**
 * Generic strings. Deliberately say nothing about who, what, or when. "Someone"
 * rather than a name; no activity noun.
 */
export const GENERIC: Record<PushKind, { title: string; body: string } | null> = {
  // A call must RING, not notify — CallKit / full-screen intent supply their own
  // UI, so there is no banner text at all.
  call_incoming: null,
  message_ready: { title: 'Olive', body: 'Something new is waiting for you.' },
  turn_ready: { title: 'Olive', body: "It's your turn." },
  exchange_reminder: { title: 'Olive', body: 'A reminder is ready.' },
  dose_due: { title: 'Olive', body: 'A reminder is ready.' },
};

/** Keys that must never appear in a push payload. Asserted in tests. */
export const FORBIDDEN_DATA_KEYS = [
  'childName', 'child_name', 'senderName', 'sender_name', 'body', 'text',
  'message', 'transcript', 'caption', 'storageKey', 'storage_key', 'url',
  'signedUrl', 'signed_url', 'dayPart', 'day_part', 'medication', 'amount',
  'latitude', 'longitude',
] as const;

export function buildPush(input: PushInput): PushPayload {
  const data: Record<string, string> = {
    kind: input.kind,
    ref: input.ref,        // opaque; resolves only for an authenticated session
    v: '1',
  };
  if (input.kind === 'call_incoming') {
    if (!input.callRoomHandle) throw new Error('call_incoming requires a room handle');
    data.callHandle = input.callRoomHandle;
  }

  const notification = GENERIC[input.kind];

  if (input.platform === 'android') {
    return {
      token: input.deviceToken, data, notification,
      android: {
        priority: 'high',
        // §11 — a call from Dad arriving as a silent notification is a broken
        // product. Full-screen intent is what makes it ring.
        fullScreenIntent: input.kind === 'call_incoming',
        channelId: input.kind === 'call_incoming' ? 'calls' : 'reminders',
        collapseKey: input.collapseKey,
      },
    };
  }
  return {
    token: input.deviceToken, data, notification,
    apns: input.kind === 'call_incoming'
      ? { pushType: 'voip', priority: 10, topicSuffix: '.voip' }
      : { pushType: 'alert', priority: 5, interruptionLevel: 'active',
          contentAvailable: true },
  };
}

/**
 * Structural audit. Runs in tests AND as a runtime assertion before send, so a
 * future contributor adding a "helpful" name to the payload fails immediately
 * rather than shipping a lock-screen disclosure.
 */
export function auditPush(p: PushPayload): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  for (const k of Object.keys(p.data)) {
    if ((FORBIDDEN_DATA_KEYS as readonly string[]).includes(k)) leaks.push(`data.${k}`);
  }
  // A uuid-looking value in data is very likely a child id.
  for (const [k, v] of Object.entries(p.data)) {
    if (k !== 'ref' && k !== 'callHandle' &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)) {
      leaks.push(`data.${k} looks like an id`);
    }
  }
  if (p.notification) {
    // ALLOWLIST, not heuristic detection.
    //
    // A first attempt looked for capitalised words that might be names. It
    // flagged "Something" — a sentence-initial capital — and would equally have
    // missed a lowercase name. Guessing at the shape of a leak is the wrong
    // instrument: the approved strings are a fixed, small set, so the audit
    // asserts the text IS one of them. That makes shipping ANY custom banner
    // impossible rather than merely difficult, which is the property we want.
    const approved = Object.values(GENERIC).filter(Boolean) as
      { title: string; body: string }[];
    const match = approved.some(a =>
      a.title === p.notification!.title && a.body === p.notification!.body);
    if (!match) leaks.push('notification text is not an approved constant');
  }
  return leaks.length ? { ok: false, leaks } : { ok: true };
}

export function sendGuard(p: PushPayload): PushPayload {
  const a = auditPush(p);
  if (!a.ok) throw new Error(`push audit failed: ${a.leaks.join('; ')}`);
  return p;
}

// ------------------------------------------------------- room lifecycle -----
/**
 * Server-side room lifecycle. NOT EXERCISED against a live LiveKit server in
 * this repository — see MASTERFILE §20.2. The shapes and the ordering rules are
 * specified and unit-tested; the network calls are not.
 */
export interface RoomLifecyclePort {
  createRoom(name: string, opts: { emptyTimeoutSec: number; maxParticipants: number }): Promise<void>;
  removeParticipant(room: string, identity: string): Promise<void>;
  deleteRoom(name: string): Promise<void>;
}

export const ROOM_EMPTY_TIMEOUT_SEC = 60;
/** A 1:1 session plus at most one supervising professional (§5.15). */
export const ROOM_MAX_PARTICIPANTS = 3;

/**
 * §8.3 — on kiosk defeat or backgrounding, revoking the token is not enough: an
 * already-joined participant stays connected until the media server evicts them.
 *
 * MEASURED against livekit-server 1.8.0: the server accepts a token up to
 * roughly 60–95 seconds PAST its `exp`, so the effective window is TTL plus a
 * clock-skew leeway we do not control. Expiry is therefore not a revocation
 * mechanism at all — eviction is. See MASTERFILE §5.19 I5.
 *
 * BOTH calls must tolerate "not found". Kiosk defeat fires eviction
 * unconditionally and cannot depend on join state: the participant may have
 * already left, or never joined. A throw here would abort the rest of the defeat
 * handling — which includes dropping guardian escalation, the severe case.
 * Verified against the real server, which throws on both.
 */
const tolerateMissing = async (fn: () => Promise<void>): Promise<'done' | 'absent'> => {
  try { await fn(); return 'done'; }
  catch (e: any) {
    const m = String(e?.message ?? e).toLowerCase();
    if (m.includes('not found') || m.includes('notfound') ||
        m.includes('does not exist') || e?.code === 5) return 'absent';
    throw e;                      // a real failure must still surface
  }
};

export async function revokeLiveAccess(
  port: RoomLifecyclePort, room: string, identity: string,
): Promise<'done' | 'absent'> {
  return tolerateMissing(() => port.removeParticipant(room, identity));
}

/**
 * Both parties hanging up simultaneously produces two `endSession` calls for one
 * room. The second must be a no-op, not an error.
 */
export async function endSession(
  port: RoomLifecyclePort, room: string,
): Promise<'done' | 'absent'> {
  return tolerateMissing(() => port.deleteRoom(room));
}
