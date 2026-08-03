/**
 * MASTERFILE §5.22 — offline.
 *
 * THE CASE THIS EXISTS FOR: she is in the back of a car with no signal, and she
 * has just drawn something for her father. Every previous increment assumed a
 * network — without this the drawing is lost at exactly the moment she most
 * wanted to send it.
 */

export type OutboxKind =
  | 'show' | 'drawing' | 'message' | 'voice' | 'colouring' | 'journal'
  | 'list_item' | 'story_star' | 'ping';

export interface OutboxItem {
  id: string;
  kind: OutboxKind;
  createdAt: string;
  payload: unknown;
  attempts: number;
  lastError: string | null;
}

/**
 * Some things are meaningless late and must NOT be queued.
 *
 * A ping means "I am thinking of you right now." Delivering it four hours later,
 * out of a tunnel, is a small lie — so it is dropped rather than banked, and she
 * is never told it failed.
 */
export const NOT_QUEUEABLE: OutboxKind[] = ['ping'];
export const MAX_ATTEMPTS = 8;

export function enqueue(
  outbox: OutboxItem[], item: Omit<OutboxItem, 'attempts' | 'lastError'>,
): { outbox: OutboxItem[]; dropped: boolean } {
  if (NOT_QUEUEABLE.includes(item.kind)) return { outbox, dropped: true };
  return { outbox: [...outbox, { ...item, attempts: 0, lastError: null }], dropped: false };
}

/** Oldest first — what she made first should arrive first. */
export function nextToSend(outbox: OutboxItem[]): OutboxItem | null {
  return [...outbox].filter(i => i.attempts < MAX_ATTEMPTS)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))[0] ?? null;
}

export function recordFailure(outbox: OutboxItem[], id: string, error: string): OutboxItem[] {
  return outbox.map(i => i.id === id ? { ...i, attempts: i.attempts + 1, lastError: error } : i);
}

export const backoffMs = (attempts: number) =>
  Math.min(60_000 * Math.pow(2, attempts), 6 * 60 * 60_000);

export const sent = (outbox: OutboxItem[], id: string) => outbox.filter(i => i.id !== id);

/**
 * What SHE sees while offline. Deliberately not a queue.
 *
 * A five-year-old shown "3 pending, 2 failed" has been handed an engineering
 * problem she cannot solve. She is told her drawing is safe, and nothing else.
 */
export function offlineChildView(outbox: OutboxItem[]): {
  line: string; anythingWaiting: boolean;
} {
  return { anythingWaiting: outbox.length > 0,
    line: outbox.length === 0 ? ''
      : 'It will go when you have internet again. It is safe.' };
}

/** The guardian side may see the mechanics, because he can act on them. */
export function offlineGuardianView(outbox: OutboxItem[]): {
  waiting: number; stuck: OutboxItem[]; oldest: string | null;
} {
  const oldest = [...outbox].sort((a, b) => a.createdAt.localeCompare(b.createdAt))[0];
  return { waiting: outbox.length,
    stuck: outbox.filter(i => i.attempts >= MAX_ATTEMPTS),
    oldest: oldest ? oldest.createdAt : null };
}

/**
 * §5.22.2 — conflicts.
 *
 * Two houses edit the same list while both are offline. The resolution is NOT
 * last-write-wins: **the child's edit beats a guardian's**, because it is her
 * list (§9.6), and a guardian silently overwriting it is precisely the failure
 * this rule prevents. Between two guardians, later wins and the earlier is kept.
 */
export type Actor = 'child' | 'guardian';
export interface Edit<T> { actor: Actor; at: string; value: T; by: string }

export function resolve<T>(a: Edit<T>, b: Edit<T>): {
  winner: Edit<T>; loser: Edit<T>; reason: string;
} {
  if (a.actor !== b.actor) {
    const child = a.actor === 'child' ? a : b;
    const guardian = a.actor === 'child' ? b : a;
    return { winner: child, loser: guardian,
      reason: 'it is her list — a guardian edit never silently overwrites hers' };
  }
  const later = a.at >= b.at ? a : b;
  const earlier = a.at >= b.at ? b : a;
  return { winner: later, loser: earlier,
    reason: 'later edit wins; the earlier one is kept' };
}

/** A losing edit is never destroyed. It is retained and shown to its author. */
export function conflictNotice<T>(loser: Edit<T>): string {
  return loser.actor === 'guardian'
    ? 'She changed this while you were both offline, so hers is showing. Yours is kept.'
    : 'This was changed in two places. Both are kept.';
}

export const OFFLINE_FORBIDDEN = [
  'pending', 'queue', 'failed', 'retry', 'attempts', 'error', 'stuck',
  'unsent', 'count',
] as const;
