import { DateTime } from 'luxon';
import { resolveZone, resolveWallClock, type TzInterval } from '../../time-engine/src/time.ts';

/**
 * MASTERFILE §9.4, §5.4 — the custody schedule engine.
 *
 * The hard part is not the rotation. It is that three different clocks meet
 * here and none of them may be conflated (§4.1):
 *
 *   order-time   the decree says "Friday 6:00 PM". In WHICH zone is settled by
 *                `custody_order.order_tz` and rendered verbatim, so neither
 *                parent can claim confusion.
 *   child-local  "3 sleeps until Dad's week" counts HER day boundaries.
 *   instant      what the scheduler actually fires on.
 *
 * A holiday rule OVERRIDES the base pattern. Getting that precedence backwards
 * is the failure that puts a child in the wrong house on Christmas.
 */

export type Pattern = '2-2-3' | '2-2-5-5' | 'alternating_weeks' | 'week_on_week_off';
export type Side = 'A' | 'B';

export interface HolidayRule {
  name: string;
  /** Child-local dates the rule covers, inclusive. */
  startMonthDay: string;      // 'MM-DD'
  endMonthDay: string;        // 'MM-DD'
  /** Which side holds it in an EVEN year; the other holds odd years. */
  evenYearSide: Side;
  /** Higher wins when two rules overlap. */
  priority: number;
}

export interface Order {
  pattern: Pattern;
  /** Zone the decree's clock times are expressed in. Never the server's. */
  orderTz: string;
  /** Child-local date the rotation is anchored to. Side A holds day 0. */
  anchorLocalDate: string;
  /** Wall clock, order-time. */
  exchangeTime: string;       // 'HH:mm'
  holidays: HolidayRule[];
  effectiveFrom: string;      // 'YYYY-MM-DD', child-local
  effectiveTo?: string | null;
  /**
   * db/migrations/0024_custody_order_side_guardians.sql — which real
   * app_user.id holds Side A/B. Both nullable, and NULL on every row that
   * existed before that migration (no way to retroactively know); a NULL
   * here is an honest "unmapped", never a guess. See that migration's own
   * header for why this mapping did not exist anywhere in the schema before
   * it, and freeGuardianNow()'s caller (server/routes.mjs's GET
   * .../presence) for how a NULL is handled — the on-duty exclusion is
   * skipped, not faked.
   */
  sideAGuardianId?: string | null;
  sideBGuardianId?: string | null;
}

export interface Block {
  side: Side;
  startLocalDate: string;
  endLocalDate: string;       // inclusive
  source: 'pattern' | 'holiday';
  holidayName?: string;
}

/** Day-by-day rotation templates over a 14-day cycle. Index 0 = anchor date. */
const CYCLES: Record<Pattern, Side[]> = {
  // A A B B A A A | B B A A B B B
  '2-2-3': ['A','A','B','B','A','A','A', 'B','B','A','A','B','B','B'],
  // A A B B A A A A A | B B A A B B B B B  → 2-2-5-5 over 14 days
  '2-2-5-5': ['A','A','B','B','A','A','A','A','A','B','B','B','B','B'],
  'alternating_weeks': ['A','A','A','A','A','A','A','B','B','B','B','B','B','B'],
  'week_on_week_off': ['A','A','A','A','A','A','A','B','B','B','B','B','B','B'],
};

const dayIndex = (order: Order, localDate: string): number => {
  const a = DateTime.fromISO(order.anchorLocalDate, { zone: 'utc' });
  const d = DateTime.fromISO(localDate, { zone: 'utc' });
  // Modulo that stays positive for dates BEFORE the anchor — a plain % returns
  // a negative index and silently reads off the end of the cycle array.
  const diff = Math.floor(d.diff(a, 'days').days);
  return ((diff % 14) + 14) % 14;
};

/** Which side holds a given child-local date under the BASE pattern only. */
export function patternSideOn(order: Order, localDate: string): Side {
  return CYCLES[order.pattern][dayIndex(order, localDate)];
}

/**
 * Holiday rules override the pattern. Ties break on `priority`, then on the
 * later start — a rule that begins inside another is the more specific one.
 */
export function holidayOn(order: Order, localDate: string): { rule: HolidayRule; side: Side } | null {
  const d = DateTime.fromISO(localDate, { zone: 'utc' });
  const md = d.toFormat('MM-dd');
  const year = d.year;

  const matches = order.holidays.filter(h => {
    // A window that wraps the new year (e.g. 12-24 → 01-02).
    return h.startMonthDay <= h.endMonthDay
      ? md >= h.startMonthDay && md <= h.endMonthDay
      : md >= h.startMonthDay || md <= h.endMonthDay;
  });
  if (!matches.length) return null;

  matches.sort((x, y) =>
    y.priority - x.priority || y.startMonthDay.localeCompare(x.startMonthDay));
  const rule = matches[0];
  // Even/odd is on the child-local year of the date itself.
  const side = year % 2 === 0
    ? rule.evenYearSide
    : (rule.evenYearSide === 'A' ? 'B' : 'A');
  return { rule, side };
}

export function sideOn(order: Order, localDate: string): { side: Side; source: 'pattern' | 'holiday'; holidayName?: string } {
  const h = holidayOn(order, localDate);
  if (h) return { side: h.side, source: 'holiday', holidayName: h.rule.name };
  return { side: patternSideOn(order, localDate), source: 'pattern' };
}

/** Contiguous blocks across a child-local date range. */
export function blocks(order: Order, fromLocal: string, toLocal: string): Block[] {
  const out: Block[] = [];
  let cur: Block | null = null;
  let d = DateTime.fromISO(fromLocal, { zone: 'utc' });
  const end = DateTime.fromISO(toLocal, { zone: 'utc' });

  while (d <= end) {
    const iso = d.toISODate()!;
    if (iso < order.effectiveFrom || (order.effectiveTo && iso > order.effectiveTo)) {
      d = d.plus({ days: 1 }); continue;
    }
    const s = sideOn(order, iso);
    if (cur && cur.side === s.side && cur.source === s.source &&
        cur.holidayName === s.holidayName) {
      cur.endLocalDate = iso;
    } else {
      if (cur) out.push(cur);
      cur = { side: s.side, startLocalDate: iso, endLocalDate: iso,
              source: s.source, holidayName: s.holidayName };
    }
    d = d.plus({ days: 1 });
  }
  if (cur) out.push(cur);
  return out;
}

export interface Exchange {
  localDate: string;
  from: Side;
  to: Side;
  /** Wall clock in ORDER time, for verbatim display. */
  orderTimeLabel: string;
  /** The absolute instant, resolved through the order's zone. */
  instant: DateTime;
  /** True when the child's zone differs either side — §4.2. */
  zoneFlips: boolean;
}

/**
 * Exchanges between blocks. The instant is resolved in `order_tz`, NOT in the
 * child's zone: a decree that says 6:00 PM Eastern means 6:00 PM Eastern even
 * during the six weeks she spends in Texas.
 */
export function exchanges(
  order: Order, fromLocal: string, toLocal: string, tz: TzInterval[], homeTz: string,
): Exchange[] {
  const bs = blocks(order, fromLocal, toLocal);
  const out: Exchange[] = [];
  for (let i = 1; i < bs.length; i++) {
    const date = bs[i].startLocalDate;
    const r = resolveWallClock(date, order.exchangeTime, order.orderTz);
    const before = resolveZone(tz, r.instant.minus({ hours: 1 }), homeTz);
    const after = resolveZone(tz, r.instant.plus({ hours: 1 }), homeTz);
    out.push({
      localDate: date,
      from: bs[i - 1].side,
      to: bs[i].side,
      orderTimeLabel: r.instant.setZone(order.orderTz).toFormat("h:mm a ZZZZ"),
      instant: r.instant,
      zoneFlips: before !== after,
    });
  }
  return out;
}

/**
 * §8.2.5 — "3 sleeps until Dad's week."
 *
 * Counts CHILD-LOCAL day boundaries, not 24-hour periods. A parent asking at
 * 11pm and at 1am the same night gets different answers in hours and the same
 * answer in sleeps, which is what a child understands.
 */
export function sleepsUntilSideChange(
  order: Order, nowLocalDate: string, maxLookahead = 60,
): { sleeps: number; nextSide: Side; onLocalDate: string } | null {
  const today = sideOn(order, nowLocalDate).side;
  let d = DateTime.fromISO(nowLocalDate, { zone: 'utc' });
  for (let i = 1; i <= maxLookahead; i++) {
    d = d.plus({ days: 1 });
    const iso = d.toISODate()!;
    const s = sideOn(order, iso).side;
    if (s !== today) return { sleeps: i, nextSide: s, onLocalDate: iso };
  }
  return null;
}

/** §9.4 child view — friendly language, never legal terms. */
export function childCalendarLabel(
  block: Block, sideNames: Record<Side, string>,
): string {
  if (block.source === 'holiday') {
    return `${block.holidayName} with ${sideNames[block.side]}`;
  }
  return `${sideNames[block.side]}'s time`;
}

// ================================================= live parent presence =====
// GET /v1/children/:childId/presence (server/routes.mjs). Who, among her
// PARENTS ONLY (§5.27.2 — "Only a parent. Not a grandparent, a stepparent,
// a caregiver, a therapist or a coordinator"; server/routes.mjs's caller
// pre-filters to role='guardian' via pool.ts's parentGuardiansOfChild(),
// same principle the come-back signal already applies, adopted here for a
// different, non-signal card), is currently free to be shown on ChildHome.
// Pure, no DB — same "no side effects, unit-testable in isolation" shape as
// prioritise() in packages/signal/src/signal.ts, which this deliberately
// mirrors, not a coincidence.

export interface FreeCandidate {
  userId: string;
  name: string;
}

/** Structurally compatible with pool.ts's AvailabilityWindow — this module
 *  does not import that type (schedule.ts has no DB dependency anywhere
 *  else and this function should not be the first to add one). */
export interface FreeWindow {
  guardianId: string;
  guardianName: string;
  weekday: number;
  startLocal: string;   // 'HH:mm'
  endLocal: string;     // 'HH:mm'
}

export interface FreeGuardian {
  guardianId: string;
  guardianName: string;
  startLocal: string;   // 'HH:mm'
  endLocal: string;     // 'HH:mm'
}

/**
 * scheduleStrip()'s own wrap-aware comparison (client/lib/calendar_day_logic
 * .dart / packages/custody's own phase3.ts equivalent): an overnight window
 * (end < start) is active either from start through midnight, or from
 * midnight through end — never neither, never both halves double-counted.
 *
 * NOT reachable via real data today: guardian_availability_window's own
 * CHECK (end_local > start_local) constraint (db/migrations/0010_
 * availability.sql) makes storing end < start impossible, so startLocal <=
 * endLocal holds for every real row today and only the first branch below
 * ever actually runs. Kept correct anyway — see freeGuardianNow()'s own
 * yesterday-wrap handling just below — rather than left half-ported, so a
 * future relaxation of that constraint doesn't also need someone to
 * remember this file. A guardian cannot express an overnight availability
 * window at all today; that is a real, disclosed, PRE-EXISTING gap in the
 * availability feature itself (this constraint predates this presence
 * feature), not something introduced or silently left broken here.
 */
function isWindowActiveNow(startLocal: string, endLocal: string, nowLocalHHMM: string): boolean {
  return startLocal <= endLocal
    ? (nowLocalHHMM >= startLocal && nowLocalHHMM < endLocal)
    : (nowLocalHHMM >= startLocal || nowLocalHHMM < endLocal);
}

/**
 * §3 of the presence design spec, Steps 3-4. `candidates` MUST already have
 * the on-duty guardian excluded by the caller (server/routes.mjs) — this
 * function has no custody-order concept at all, deliberately: "who is on
 * duty" and "who is free" are two different questions answered by two
 * different pieces of state (custody_order vs. guardian_availability_window),
 * and folding both into one function would make the on-duty exclusion
 * untestable in isolation from the availability-window logic.
 *
 * "No seniority, no primary/secondary, no custody weighting." — MASTERFILE
 * §5.27.4. The only real tie-break below is "then simply first" (earliest
 * window start wins); the guardianId secondary sort exists purely to make
 * an exact-start-time tie deterministic and carries no product meaning.
 */
export function freeGuardianNow(
  candidates: FreeCandidate[],
  windows: FreeWindow[],
  nowWeekday: number,
  nowLocalHHMM: string,
): FreeGuardian | null {
  const candidateIds = new Set(candidates.map(c => c.userId));
  // A window is "active now" if it starts on TODAY's weekday (the ordinary
  // case, and today the only one guardian_availability_window's own CHECK
  // constraint permits — see isWindowActiveNow()'s own comment), OR it
  // started YESTERDAY and is an overnight window (startLocal > endLocal)
  // still running past midnight into today. The two cases use different
  // comparisons deliberately: reusing isWindowActiveNow() unmodified for a
  // yesterday-dated window would also match its ordinary same-day range a
  // second time (e.g. a plain 08:00-09:00 window from yesterday would
  // wrongly read as active at 08:30 again today) — only the post-midnight
  // half of a genuine overnight window carries over to today.
  const yesterday = (nowWeekday + 6) % 7;
  const active = windows.filter(w => {
    if (!candidateIds.has(w.guardianId)) return false;
    if (w.weekday === nowWeekday) {
      return isWindowActiveNow(w.startLocal, w.endLocal, nowLocalHHMM);
    }
    if (w.weekday === yesterday && w.startLocal > w.endLocal) {
      return nowLocalHHMM < w.endLocal;
    }
    return false;
  });
  if (!active.length) return null;

  const winner = [...active].sort((a, b) =>
    a.startLocal.localeCompare(b.startLocal) ||
    a.guardianId.localeCompare(b.guardianId))[0];

  return {
    guardianId: winner.guardianId,
    guardianName: winner.guardianName,
    startLocal: winner.startLocal,
    endLocal: winner.endLocal,
  };
}
