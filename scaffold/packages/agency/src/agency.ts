import { DateTime } from 'luxon';

/**
 * MASTERFILE §9.9, §9.3 — child agency and the wants/needs list.
 *
 * Everything here is governed by a prohibition. P2 forbids scoring shown to a
 * child; P4 forbids purchase mechanics; §2.1 forbids the child seeing parental
 * conflict. The types below are shaped so that violating one requires adding a
 * field, not merely changing a value.
 */

// ================================================================== the ping =
/**
 * §16.2 #4, SETTLED v0.23.0 — the limit scales with age, and then stops existing.
 *
 * A uniform 3/day treated a five-year-old and a fifteen-year-old as the same
 * case. They are not: the younger child needs the limit as a gentle boundary
 * around a habit she cannot yet self-regulate; the older one experiences the
 * same limit as a cap on contacting her own parent, which is a different and
 * worse thing.
 *
 * §21.5 governs the top of the table: the limit is **scaffolding**, and
 * scaffolding fades. From 13 there is no limit at all.
 */
export const PING_BANDS: { upToAge: number; perDay: number | null }[] = [
  { upToAge: 7,  perDay: 3 },
  { upToAge: 9,  perDay: 5 },
  { upToAge: 12, perDay: 8 },
  { upToAge: 999, perDay: null },   // 13+ — no limit, per §21.5
];

export function pingLimitForAge(age: number): number | null {
  return PING_BANDS.find(b => age <= b.upToAge)!.perDay;
}

/** Retained for callers that predate the age scale. Equals the youngest band. */
export const PING_LIMIT_PER_DAY = 3;

export interface PingRecord { childId: string; toUserId: string; localDate: string; }

export type PingOutcome =
  | { sent: true; policy: 'when_reachable' }
  /**
   * Over the limit. `silent` is the point: a child is NEVER told they have used
   * up contact with their parent. There is no message, no counter, no greyed
   * button — the tap simply does nothing visible.
   */
  | { sent: false; silent: true };

export function ping(
  history: PingRecord[], childId: string, toUserId: string,
  now: DateTime, childZone: string, childAge?: number,
): PingOutcome {
  const limit = childAge === undefined ? PING_LIMIT_PER_DAY : pingLimitForAge(childAge);
  // No limit at all from 13. Not a large number — the absence of one.
  if (limit === null) return { sent: true, policy: 'when_reachable' };
  const localDate = now.setZone(childZone).toISODate()!;
  const used = history.filter(p =>
    p.childId === childId && p.toUserId === toUserId && p.localDate === localDate).length;
  if (used >= limit) return { sent: false, silent: true };
  // A ping is a request, never an override: it respects the RECIPIENT's
  // day-parts exactly as any other delivery does.
  return { sent: true, policy: 'when_reachable' };
}

// ================================================================= the journal
export interface JournalEntry { id: string; childId: string; body: string;
  createdAt: string; }

/**
 * P7 — there is no guardian read path, at any tier, including escalation.
 * This function takes the reader's role precisely so the refusal is explicit in
 * the type system rather than implied by an absent route.
 */
export function readJournal(
  entries: JournalEntry[], readerRole: string, readerChildId: string | null,
  childId: string,
): { ok: true; entries: JournalEntry[] } | { ok: false; reason: 'P7_journal_never' } {
  if (readerRole !== 'child' || readerChildId !== childId) {
    return { ok: false, reason: 'P7_journal_never' };
  }
  return { ok: true, entries: entries.filter(e => e.childId === childId) };
}

// ================================================================== rituals ==
export interface Ritual {
  id: string; childId: string; withUserId: string; label: string;
  daypart: string; daysOfWeek: number[]; active: boolean;
}

/**
 * P2 — rituals are never scored. The child-facing shape carries no count, no
 * streak, no completion ratio, and no "missed" flag. A missed pancake call
 * produces nothing visible.
 */
export interface RitualChildView { label: string; whenLabel: string; }

export function ritualsForChild(rs: Ritual[], dayNames: string[]): RitualChildView[] {
  return rs.filter(r => r.active).map(r => ({
    label: r.label,
    whenLabel: r.daysOfWeek.length === 7
      ? `every day at ${r.daypart.replace('_', ' ')}`
      : `${r.daysOfWeek.map(d => dayNames[d]).join(', ')} at ${r.daypart.replace('_', ' ')}`,
  }));
}

/** Keys that must never reach a child-facing payload. Asserted in tests. */
export const CHILD_FORBIDDEN_KEYS = [
  'streak', 'count', 'completed', 'missed', 'score', 'ratio', 'total',
  'claimedBy', 'claimed_by', 'declinedBy', 'price', 'amount', 'cost', 'url',
] as const;

export function auditChildPayload(o: unknown):
  { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (v: unknown) => {
    if (Array.isArray(v)) return v.forEach(walk);
    if (v && typeof v === 'object') {
      for (const [k, val] of Object.entries(v)) {
        if ((CHILD_FORBIDDEN_KEYS as readonly string[])
              .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
        walk(val);
      }
    }
  };
  walk(o);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ============================================================ wants and needs =
export type ListKind = 'want' | 'need';

export interface ListItem {
  id: string; childId: string; kind: ListKind; title: string;
  note?: string;
  /** Guardian-only. NEVER surfaced to the child — §2.1. */
  claimedBy?: string | null;
  claimedAt?: string | null;
  fulfilledAt?: string | null;
}

/** What the child sees. Deliberately has no field for who did what. */
export interface ListItemChildView {
  title: string; kind: ListKind;
  /** 'handled' or 'on the list'. Never who, never why not. */
  status: 'handled' | 'on the list';
}

export function childListView(items: ListItem[]): ListItemChildView[] {
  return items.map(i => ({
    title: i.title, kind: i.kind,
    status: (i.fulfilledAt || i.claimedBy) ? 'handled' : 'on the list',
  }));
}

/**
 * §9.3 — a need is claimable by ONE guardian, which is what prevents both-buy
 * and neither-buy. A second claim fails rather than overwriting, so the first
 * claimant is not silently displaced.
 */
export function claimNeed(
  item: ListItem, byUserId: string,
): { ok: true; item: ListItem } | { ok: false; reason: 'wants_are_not_claimable' | 'already_claimed' } {
  // P4 — wants carry no price and no purchase action, so there is nothing to
  // claim. Allowing it would reintroduce the bidding dynamic through the back
  // door.
  if (item.kind === 'want') return { ok: false, reason: 'wants_are_not_claimable' };
  if (item.claimedBy) return { ok: false, reason: 'already_claimed' };
  return { ok: true, item: { ...item, claimedBy: byUserId,
                             claimedAt: new Date().toISOString() } };
}
