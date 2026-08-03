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
