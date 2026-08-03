/**
 * MASTERFILE §9.13 — four things missing from a live call.
 *
 * The call itself worked. What surrounded it did not: it began without
 * preparation, ended badly, had no way to include the parent standing in the room,
 * and failed rudely when she was busy.
 */

export type Side = 'A' | 'B';

// ============================================ §9.13.1 the closing ritual ====
/**
 * Calls end with "ok, bye" and a black screen. For an adult that is fine. For a
 * child it is the moment the absence starts again, at full volume, with no
 * warning.
 *
 * Thirty seconds of structure turns an ending into a bridge. Three beats, in this
 * order, because the order is what does the work: something forward-looking, then
 * something certain, then a goodbye that is not the word "bye".
 *
 * **It is skippable at every beat.** Forcing a ritual on a child who wants to go
 * and play is worse than a bad ending — and a ritual she cannot escape stops being
 * a comfort within a week.
 */
export type ClosingBeat = 'one_thing' | 'when_next' | 'the_goodbye';

export interface Closing {
  beat: ClosingBeat | 'done';
  /** Something she will show him next time. Becomes an §9.10.7 ask. */
  oneThing: string | null;
  /** The next certain time, from the custody engine. Never invented. */
  nextTime: string | null;
  /** Their own word, chosen once and kept. */
  goodbye: string | null;
  skipped: boolean;
}

/** Offered when the call has been going a while, never at the start. */
export const RITUAL_OFFER_AFTER_SECONDS = 180;

export const GOODBYES = [
  'See you in the morning',
  'Sleep well, small one',
  'Same time tomorrow',
  'Over and out',
  'Big squeeze',
  'Catch you later, alligator',
] as const;

export function beginClosing(): Closing {
  return { beat: 'one_thing', oneThing: null, nextTime: null, goodbye: null,
    skipped: false };
}

export function shouldOfferClosing(elapsedSeconds: number, alreadyOffered: boolean):
  boolean {
  return !alreadyOffered && elapsedSeconds >= RITUAL_OFFER_AFTER_SECONDS;
}

export function closingNext(
  c: Closing, input: { oneThing?: string; nextTime?: string | null; goodbye?: string },
): Closing {
  if (c.beat === 'one_thing') {
    return { ...c, oneThing: input.oneThing?.trim() || null, beat: 'when_next' };
  }
  if (c.beat === 'when_next') {
    // Never invented. If the schedule does not know, the beat says so and moves on.
    return { ...c, nextTime: input.nextTime ?? null, beat: 'the_goodbye' };
  }
  if (c.beat === 'the_goodbye') {
    return { ...c, goodbye: input.goodbye?.trim() || null, beat: 'done' };
  }
  return c;
}

export function skipClosing(c: Closing): Closing {
  return { ...c, beat: 'done', skipped: true };
}

export function closingLines(c: Closing): { prompt: string; sub: string } {
  if (c.beat === 'one_thing') {
    return { prompt: 'What will you show me next time?',
      sub: 'Anything. He will be asked about it.' };
  }
  if (c.beat === 'when_next') {
    return { prompt: c.nextTime ? `Next time is ${c.nextTime}.` : 'We will sort out when.',
      sub: c.nextTime ? 'It is on your calendar.' : 'Nobody is pretending to know yet.' };
  }
  if (c.beat === 'the_goodbye') {
    return { prompt: 'How shall we say goodbye?', sub: 'Pick one and keep it.' };
  }
  return { prompt: '', sub: '' };
}

/**
 * The forward-looking beat produces a real ask (§9.10.7), so "I'll show you my
 * tooth" is waiting for her tomorrow rather than evaporating when the call ends.
 */
export function closingToAsk(
  c: Closing, fromUserId: string, fromLabel: string, at: string,
): { prompt: string; fromUserId: string; fromLabel: string; askedAt: string } | null {
  return c.oneThing
    ? { prompt: `Show me ${c.oneThing}`, fromUserId, fromLabel, askedAt: at } : null;
}

// ============================================== §9.13.2 shared reading =====
/**
 * The activity with the best evidence behind it for a parent at distance, and the
 * one I recommended two increments ago and did not build.
 *
 * THE DESIGN CHOICE THAT MATTERS: **she turns the pages.** He reads, but the
 * pacing is hers. A parent-controlled page turn makes her a spectator to her own
 * bedtime story; giving her the button keeps her hands and attention in it, and
 * she will turn back to look at a picture, which is the whole point of reading with
 * a small child.
 */
export interface ReadingSession {
  bookTitle: string;
  totalPages: number;
  page: number;
  /** 'B' reads aloud; 'A' turns. Swappable — some nights she wants to read. */
  reader: Side;
  turner: Side;
  /** Her line, if the book has one. Same idea as the storyteller's refrain. */
  herLine: string | null;
  /** Where they stopped, so tomorrow resumes. */
  bookmarkedAt: number | null;
}

export function beginReading(
  bookTitle: string, totalPages: number, reader: Side = 'B',
  startAt = 1, herLine: string | null = null,
): ReadingSession {
  return { bookTitle, totalPages, page: Math.max(1, Math.min(startAt, totalPages)),
    reader, turner: reader === 'B' ? 'A' : 'B', herLine, bookmarkedAt: null };
}

export type TurnError = 'not_your_page_to_turn' | 'at_the_start' | 'at_the_end';

export function turnPage(
  s: ReadingSession, by: Side, dir: 1 | -1,
): { ok: true; session: ReadingSession } | { ok: false; reason: TurnError } {
  if (by !== s.turner) return { ok: false, reason: 'not_your_page_to_turn' };
  const next = s.page + dir;
  if (next < 1) return { ok: false, reason: 'at_the_start' };
  if (next > s.totalPages) return { ok: false, reason: 'at_the_end' };
  return { ok: true, session: { ...s, page: next } };
}

/** Turning BACK is always allowed and is not an error. Children do it constantly. */
export const canGoBack = (s: ReadingSession) => s.page > 1;

export function swapReader(s: ReadingSession): ReadingSession {
  return { ...s, reader: s.reader === 'A' ? 'B' : 'A',
    turner: s.turner === 'A' ? 'B' : 'A' };
}

export function bookmarkReading(s: ReadingSession): ReadingSession {
  return { ...s, bookmarkedAt: s.page };
}

/** No page count read aloud to her, no percentage, no "nearly finished". */
export function readingChildView(s: ReadingSession): {
  title: string; herLine: string | null; canTurn: boolean; canGoBack: boolean;
} {
  return { title: s.bookTitle, herLine: s.herLine,
    canTurn: s.page < s.totalPages, canGoBack: canGoBack(s) };
}

// ============================================ §9.13.3 the mid-call handoff ==
/**
 * She is on a call with her father. Her mother walks through the room.
 *
 * There was no way to include her for thirty seconds, and the absence of one is
 * conspicuous — it makes the product feel like it is keeping the adults apart.
 *
 * THE RULE, AND IT IS NOT NEGOTIABLE: **a handoff can only be initiated by the
 * child or by the parent who is physically present.** The remote parent can never
 * request one.
 *
 * Otherwise the feature becomes a way to summon your ex through your child, which
 * is using her as a conduit — §2.4, and the thing this whole product exists to
 * avoid.
 */
export type HandoffInitiator = 'child' | 'present_parent';

export interface Handoff {
  initiatedBy: HandoffInitiator;
  /** Announced to the remote parent before it happens. No ambush. */
  announced: true;
  startedAt: string;
  /** Time-boxed. It is a hello, not a meeting. */
  maxSeconds: number;
  endedAt: string | null;
}

export const HANDOFF_MAX_SECONDS = 120;

export function requestHandoff(
  by: 'child' | 'present_parent' | 'remote_parent', at: string,
): { ok: true; handoff: Handoff } | { ok: false; reason: 'remote_cannot_request'; note: string } {
  if (by === 'remote_parent') {
    return { ok: false, reason: 'remote_cannot_request',
      note: 'You cannot ask to be handed over. If you need to speak to her other '
          + 'parent, use the coordination layer — not the child.' };
  }
  return { ok: true, handoff: { initiatedBy: by, announced: true, startedAt: at,
    maxSeconds: HANDOFF_MAX_SECONDS, endedAt: null } };
}

export function handoffExpired(h: Handoff, nowIso: string): boolean {
  return (Date.parse(nowIso) - Date.parse(h.startedAt)) / 1000 > h.maxSeconds;
}

/**
 * A handoff does NOT become a parent-to-parent record. It is a hello in a hallway,
 * and minuting it would stop anybody ever doing it.
 */
export const HANDOFF_IN_COURT_LOG = false;

// ======================================== §9.13.4 she is busy, so bank it ===
/**
 * He rings during school. The ribbon warned him, but the call attempt itself had
 * nowhere to go — and a failed call is the worst possible output, because it reads
 * to him as rejection and to her, later, as a missed call she caused.
 *
 * So an attempt at a blocked time is never a failure. It is a fork, and both
 * branches are good.
 */
export type Unavailable = 'school' | 'asleep' | 'wind_down' | 'with_other_parent' | 'quiet_hours';

export interface BusyFork {
  reason: Unavailable;
  /** Plain, and it never suggests she chose it. */
  line: string;
  /** Always offered. Reuses §9.5 message banking unchanged. */
  offerBanking: true;
  /** The next window the schedule actually knows about. */
  nextWindow: string | null;
  /** Present only where the situation genuinely warrants it. */
  urgentPath: string | null;
}

export function busyFork(
  reason: Unavailable, nextWindow: string | null, emergency = false,
): BusyFork {
  const lines: Record<Unavailable, string> = {
    school:            'She is at school.',
    asleep:            'She is asleep.',
    wind_down:         'She is winding down for bed.',
    with_other_parent: 'She is in the middle of something at her other house.',
    quiet_hours:       'It is quiet hours there.',
  };
  return { reason, line: lines[reason], offerBanking: true, nextWindow,
    urgentPath: emergency
      ? 'If this cannot wait, the emergency card has the numbers.' : null };
}

/** Nothing in this fork may imply refusal, rejection, or a decision by her. */
export const BUSY_BANNED = [
  'declined', 'rejected', 'refused', 'unavailable to you', 'she did not answer',
  'missed call', 'no answer', 'blocked', 'not allowed', 'denied',
] as const;

export function auditBusyFork(f: BusyFork): { ok: true } | { ok: false; found: string[] } {
  const text = (f.line + ' ' + (f.urgentPath ?? '')).toLowerCase();
  const found = (BUSY_BANNED as readonly string[]).filter(w => text.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

/**
 * And the other half, which matters just as much: **she is never shown a missed
 * call.** A five-year-old who sees "Dad tried to call you at 10:40" has been handed
 * a small guilt she did nothing to earn. She sees the banked message, whenever she
 * next looks, and nothing about the attempt.
 */
export function attemptVisibleToChild(): false { return false; }
