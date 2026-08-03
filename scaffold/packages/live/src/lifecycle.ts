/**
 * MASTERFILE §5.25 — the shape of a call before and after it exists.
 *
 * The Fold items here were declared in v0.32.0 and never built —
 * `TABLETOP_KEEPS_CALL_ALIVE` had exactly one reference, its own declaration.
 */

export type Side = 'A' | 'B';
export type Posture =
  | 'fold_cover' | 'fold_main' | 'fold_tabletop' | 'phone'
  | 'tablet_small' | 'tablet_medium' | 'tablet_large' | 'desktop' | 'dex';

// ================================================ §5.25.1 the Fold, live ====
/**
 * A hinge is not a lifecycle event. Folding, unfolding and standing the phone up
 * are things she does *while* talking to her father, and every one of them
 * destroyed the call until now.
 */
export interface PostureChange {
  from: Posture;
  to: Posture;
  /** The call is never torn down by a hinge. */
  callSurvives: true;
  /** What changes on screen. */
  relayout: 'stacked' | 'side_by_side' | 'tabletop';
  announce: string | null;
}

export function onPostureChange(from: Posture, to: Posture): PostureChange {
  const relayout: PostureChange['relayout'] =
    to === 'fold_tabletop' ? 'tabletop'
    : to === 'fold_main' || to === 'tablet_large' || to === 'desktop' || to === 'dex'
      ? 'side_by_side' : 'stacked';
  return { from, to, callSurvives: true, relayout,
    // Announced only for the posture that changes what she can do with her hands.
    announce: to === 'fold_tabletop'
      ? 'You can put it down now — he can still see you.' : null };
}

/** Detected from the viewport, so it works without a vendor hinge API. */
export function detectPosture(w: number, h: number): Posture {
  const landscape = w > h;
  if (w >= 1280 && landscape) return 'dex';
  if (w >= 1024) return 'desktop';
  if (w >= 600 && landscape && h <= 480) return 'fold_tabletop';
  if (w >= 800) return 'tablet_large';
  if (w >= 660 && h < 900) return 'fold_main';
  if (w >= 600) return 'tablet_small';
  if (w <= 400 && h >= 800) return 'fold_cover';
  return 'phone';
}

export const HINGE_NEVER_ENDS_CALL = true;

/** A call begun folded expands on opening. Same room, same session. */
export function expandsOnUnfold(from: Posture, to: Posture): boolean {
  return from === 'fold_cover' && (to === 'fold_main' || to === 'fold_tabletop');
}

// =============================================== §5.25.2 knocking ===========
/**
 * A ring demands answering. For a child that is a small obligation arriving
 * without warning, and the honest version of "can we talk" does not do that.
 *
 * A knock waits. If she does not come, nothing has failed and nobody is told she
 * refused.
 */
export type Arrival = 'knock' | 'ring';

export interface Knock {
  from: string;
  at: string;
  /** How long it waits before quietly becoming a banked message. */
  waitsSeconds: number;
  /** Nothing is escalated, ever. */
  escalates: false;
}

export const KNOCK_WAITS_SECONDS = 90;

export function knock(from: string, at: string): Knock {
  return { from, at, waitsSeconds: KNOCK_WAITS_SECONDS, escalates: false };
}

/**
 * A knock unanswered becomes a banked message. It is never reported as missed,
 * declined or ignored — §9.13.4 already settled that she is not shown a missed
 * call, and this is the same rule at the other end of the wire.
 */
export function knockUnanswered(): { becomes: 'banked_message'; toldToSender: string } {
  return { becomes: 'banked_message',
    toldToSender: 'She did not come to it. It is saved for her — she will see it '
                + 'when she next opens Olive.' };
}

/** "Not now" is a real answer and it is not a decline. */
export const ANSWER_WORDS = ['Answer', 'Just talking', 'Not now'] as const;

export const ANSWER_BANNED = ['decline', 'reject', 'refuse', 'dismiss', 'ignore'] as const;

export function auditAnswerWords(words: readonly string[]): { ok: true } | { ok: false; found: string[] } {
  const found = words.filter(w =>
    (ANSWER_BANNED as readonly string[]).some(b => w.toLowerCase().includes(b)));
  return found.length ? { ok: false, found } : { ok: true };
}

export function notNowOutcome(): { line: string; senderTold: string } {
  return { line: 'Alright. He knows you are busy.',
    senderTold: 'She is busy just now. Record her something?' };
}

// =============================================== §5.25.3 device handoff =====
/**
 * Start on the tablet, carry on with the phone. She walks out of the room and the
 * call should walk with her.
 */
export interface Handoff {
  fromDevice: string;
  toDevice: string;
  /** The same room — not a new call. */
  sameSession: true;
  /** Media pauses for at most this long. */
  maxGapSeconds: number;
}

export const HANDOFF_MAX_GAP_SECONDS = 6;

export type HandoffError = 'same_device' | 'not_her_device';

export function handOff(
  from: string, to: string, herDevices: string[],
): { ok: true; handoff: Handoff } | { ok: false; reason: HandoffError } {
  if (from === to) return { ok: false, reason: 'same_device' };
  if (!herDevices.includes(to)) return { ok: false, reason: 'not_her_device' };
  return { ok: true, handoff: { fromDevice: from, toDevice: to,
    sameSession: true, maxGapSeconds: HANDOFF_MAX_GAP_SECONDS } };
}

/** The old device stops capturing the instant the new one takes over. */
export const OLD_DEVICE_RELEASES_CAPTURE = true;

// ============================================== §5.25.4 both-free windows ===
/**
 * The Day Ribbon already knows when they are both free. It has never offered to
 * start a call, which is a strange gap — the whole point of computing the overlap
 * is to use it.
 */
export interface FreeWindow { startMinute: number; endMinute: number; dow: number }

export interface CallSuggestion {
  window: FreeWindow;
  /** Offered to the GUARDIAN only. She is not prompted to summon a parent. */
  audience: 'guardian';
  line: string;
}

export function suggestFromOverlap(w: FreeWindow, childName: string): CallSuggestion {
  return { window: w, audience: 'guardian',
    line: `${childName} is free then, and so are you.` };
}

/**
 * Never suggested to the child. A prompt telling a five-year-old that now would
 * be a good time to call her father makes his availability her responsibility.
 */
export function suggestionVisibleTo(role: string): boolean {
  return role === 'guardian';
}

// ================================================ §5.25.5 the waiting room ==
/**
 * Supervised calls (§5.15) need somewhere for the supervisor to admit people
 * from — and the child should not be sitting in it.
 *
 * She is admitted first and waits nowhere; the supervised party is the one who
 * waits. That ordering is the difference between a waiting room and a holding
 * pen.
 */
export interface WaitingRoom {
  roomId: string;
  /** Admitted immediately, before anyone else. */
  childAdmittedFirst: true;
  waiting: { userId: string; since: string }[];
  supervisorId: string;
}

export function waitingRoom(roomId: string, supervisorId: string): WaitingRoom {
  return { roomId, childAdmittedFirst: true, waiting: [], supervisorId };
}

export function joinWaiting(r: WaitingRoom, userId: string, at: string): WaitingRoom {
  return { ...r, waiting: [...r.waiting, { userId, since: at }] };
}

export function admit(r: WaitingRoom, userId: string): WaitingRoom {
  return { ...r, waiting: r.waiting.filter(w => w.userId !== userId) };
}

/** She is never shown who is waiting, or that anybody is. */
export function waitingVisibleTo(role: string): boolean {
  return role === 'supervisor' || role === 'guardian';
}

export function childWaitingView(): { line: string } {
  return { line: 'Nearly ready.' };
}
