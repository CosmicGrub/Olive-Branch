/**
 * MASTERFILE §12.8–§12.11 — four surfaces that have sat in MARKUP's
 * "cannot be drawn yet" panel across several increments.
 *
 * Each was blocked on something. Three of those things are now settled.
 */

export type Side = 'A' | 'B';

// ======================================= §12.8 the sibling group call =======
/**
 * Two children, one parent, one call. It was unbuildable until §17.6 gave
 * siblings a real model.
 *
 * THE DESIGN PROBLEM, and it is not technical: **a group call silences the
 * younger child.** A five-year-old and a twelve-year-old on one call is a call
 * with a twelve-year-old in it, and the five-year-old learns that faster than
 * anyone admits.
 */
export interface GroupCall {
  parentId: string;
  childIds: string[];
  /** Whose turn it is to have him to themselves. Rotates. */
  soloTurn: string | null;
  soloSecondsEach: number;
  startedAt: string;
}

/** Each child gets this long alone before or after the group part. */
export const SOLO_SECONDS_EACH = 240;
export const MAX_CHILDREN_ON_A_CALL = 4;

export type GroupError = 'too_many' | 'need_two';

export function startGroupCall(
  parentId: string, childIds: string[], at: string,
): { ok: true; call: GroupCall } | { ok: false; reason: GroupError } {
  if (childIds.length < 2) return { ok: false, reason: 'need_two' };
  if (childIds.length > MAX_CHILDREN_ON_A_CALL) return { ok: false, reason: 'too_many' };
  return { ok: true, call: { parentId, childIds, soloTurn: null,
    soloSecondsEach: SOLO_SECONDS_EACH, startedAt: at } };
}

/**
 * The youngest goes first, and that is the whole mechanic.
 *
 * By the time an older sibling has been on for ten minutes, a five-year-old has
 * left the room. Giving her the first solo turn is the only ordering that
 * survives contact with an actual family.
 */
export function soloOrder(
  children: { id: string; age: number | null }[],
): string[] {
  return [...children]
    .sort((a, b) => (a.age ?? 99) - (b.age ?? 99))
    .map(c => c.id);
}

export function nextSolo(call: GroupCall, order: string[]): GroupCall {
  const i = call.soloTurn === null ? -1 : order.indexOf(call.soloTurn);
  const next = order[i + 1] ?? null;
  return { ...call, soloTurn: next };
}

/** What the waiting sibling sees. Never a countdown — that is a queue. */
export function waitingView(childName: string): { line: string; canLeave: true } {
  return { line: `${childName} is having a turn. Go and do something — we will `
                + 'call you back.', canLeave: true };
}

export const GROUP_FORBIDDEN = [
  'queue', 'position', 'waiting', 'countdown', 'remaining', 'next up', 'turn 2 of 3',
] as const;

export function auditGroup(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((GROUP_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ========================================== §12.9 the therapist's view ======
/**
 * §16.2 #11 is still open on whether a therapist sees session metadata. The
 * **ladder-only** scope is settled, so the view can be built to that and widened
 * later if the answer changes.
 *
 * The contact ladder is: who reached out, to whom, and whether it landed. Not
 * what was said, not for how long, not how often.
 */
export interface LadderEntry {
  date: string;
  direction: 'child_to_parent' | 'parent_to_child';
  otherParty: string;
  landed: boolean;
}

export interface TherapistView {
  childName: string;
  entries: LadderEntry[];
  /** Stated on the surface, not buried in settings. */
  scopeNote: string;
  /** What they cannot see, named, so nobody assumes otherwise. */
  notVisible: string[];
}

export function therapistView(childName: string, entries: LadderEntry[]): TherapistView {
  return { childName, entries,
    scopeNote: 'You can see who reached out and whether it landed. Nothing else.',
    notVisible: ['what was said', 'how long a call lasted', 'her journal',
      'her sealed letters', 'anything her parents wrote to each other'] };
}

/** A therapist view containing any of these is a scope breach. */
export const THERAPIST_FORBIDDEN = [
  'body', 'text', 'transcript', 'duration', 'seconds', 'minutes', 'frequency',
  'journal', 'letter', 'sentiment', 'mood', 'concern',
] as const;

export function auditTherapist(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((THERAPIST_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ======================================= §12.10 the preservation prompt =====
/**
 * §10.1b made preservation a standing rule with a 14-day expiry digest for
 * incidental material. The digest existed; **the moment of asking did not.**
 *
 * This is the in-the-moment version: she has just drawn something, or a call has
 * just produced a clip worth keeping, and the question is asked once, warmly,
 * and never again for that item.
 */
export interface PreservationPrompt {
  artifactId: string;
  kind: string;
  /** Asked at most once per artifact, ever. */
  asked: boolean;
  keep: boolean | null;
}

/**
 * Only for things that are NOT already covered by the standing rule. Asking about
 * something already kept forever would train her to dismiss the prompt.
 */
export const PROMPTABLE_KINDS = ['call_clip', 'screen_frame', 'session_media'] as const;

export function shouldPrompt(kind: string, alreadyAsked: boolean): boolean {
  return !alreadyAsked && (PROMPTABLE_KINDS as readonly string[]).includes(kind);
}

export function promptCopy(kind: string): string {
  return kind === 'call_clip'
    ? 'Keep this bit of the call?'
    : 'Keep this?';
}

/** No is a real answer and is not asked twice. */
export function answerPrompt(p: PreservationPrompt, keep: boolean): PreservationPrompt {
  return { ...p, asked: true, keep };
}

export const PROMPT_BANNED = [
  'are you sure', 'last chance', 'it will be deleted', 'gone forever',
  'you will lose', 'permanently',
] as const;

export function auditPrompt(text: string): { ok: true } | { ok: false; found: string[] } {
  const t = text.toLowerCase();
  const found = (PROMPT_BANNED as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

// ================================ §12.11 "call me when you can", at the limit
/**
 * §9.9 caps pings by age (3/day to 7, 5 to 9, 8 to 12, none from 13). The refusal
 * is **silent** — she taps and nothing happens, which was chosen deliberately so
 * she is never told off.
 *
 * But silence is only right if she has another way to say it. This is that way:
 * at the limit, the tap becomes a **banked** "call me when you can" rather than
 * nothing at all.
 */
export interface AtLimitOutcome {
  pinged: boolean;
  banked: boolean;
  /** What she sees. Identical whether it pinged or banked — she cannot tell. */
  line: string;
}

/**
 * The line is the same either way, and that is the point. A child who can tell
 * she has hit a limit has been told off by a counter.
 */
export const SAME_LINE = 'He will know you were thinking of him.';

export function tapPing(withinLimit: boolean): AtLimitOutcome {
  return withinLimit
    ? { pinged: true, banked: false, line: SAME_LINE }
    : { pinged: false, banked: true, line: SAME_LINE };
}

/** The guardian side sees the truth, because he needs it to respond well. */
export function guardianPingView(pinged: number, banked: number): string {
  if (banked === 0) return '';
  return banked === 1
    ? 'She reached for you once more after that.'
    : `She reached for you ${banked} more times after that.`;
}

export function auditAtLimit(o: AtLimitOutcome): { ok: true } | { ok: false; reason: string } {
  return o.line === SAME_LINE
    ? { ok: true }
    : { ok: false, reason: 'the child can tell which branch she got' };
}
