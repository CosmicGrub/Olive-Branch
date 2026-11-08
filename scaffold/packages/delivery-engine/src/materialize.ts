import { DateTime } from 'luxon';
import { resolveZone, resolveWallClock, type TzInterval } from '../../time-engine/src/time.ts';

export type Policy =
  | 'immediate' | 'at_instant' | 'at_daypart'
  | 'on_local_date' | 'when_reachable' | 'on_event';

export type State =
  | 'pending' | 'ready' | 'delivered' | 'opened' | 'expired' | 'revoked';

export interface DayPart {
  kind: string;
  startsLocal: string;          // 'HH:mm' wall clock
  endsLocal: string;
  /**
   * 0 = Sunday. The day the part STARTS on (S-D11): a part that wraps midnight
   * (asleep 21:00 -> 06:30) with days [Fri] covers Friday 21:00 through
   * Saturday 06:30, so at Saturday 02:00 it is Friday's part that is running.
   */
  daysOfWeek: number[];
  reachable: boolean;
  /**
   * Child-local dates the part is in force, INCLUSIVE; null/undefined = open
   * (S-D10). day_part.effective is a daterange; childCtxFor() now hands the
   * engine every row with these bounds and the engine resolves by the TARGET
   * date, instead of one context frozen at the database's CURRENT_DATE.
   */
  effectiveFrom?: string | null;
  effectiveTo?: string | null;
}

export interface Intent {
  id: string;
  childId: string;
  policy: Policy;
  state: State;
  expiresAt: string;            // ISO instant
  targetInstant?: string;
  targetDaypart?: string;
  targetLocalDate?: string;     // 'YYYY-MM-DD' child-local
  targetEventId?: string;
  batchSeq?: number;
}

export interface ChildCtx {
  homeTz: string;
  tzIntervals: TzInterval[];
  dayParts: DayPart[];
  eventInstants?: Record<string, string>;
}

export type Skip =
  | 'daypart_undefined'
  | 'no_reachable_window'
  | 'target_in_past'
  | 'already_expired'
  | 'unresolvable_event'
  | 'terminal_state';

export type Result =
  | { ok: true; scheduledAt: DateTime; tz: string;
      anomaly: 'none' | 'nonexistent' | 'ambiguous'; rolled: boolean }
  | { ok: false; reason: Skip };

/**
 * How late a delivery may be and still go out.
 *
 * Sized to absorb a sweep outage, a DST shift (max 60 min), and brief
 * downtime — but NOT to retroactively dump a week of bedtime videos at 3 a.m.
 * when the system comes back up. That is the failure this constant prevents.
 */
export const PAST_GRACE_MINUTES = 120;

const TERMINAL: State[] = ['delivered', 'opened', 'expired', 'revoked'];

/** The day-parts in force on a child-local date (S-D10). */
export function partsOn(ctx: ChildCtx, localDate: string): DayPart[] {
  return ctx.dayParts.filter(p =>
    (!p.effectiveFrom || localDate >= p.effectiveFrom) &&
    (!p.effectiveTo || localDate <= p.effectiveTo));
}

const wraps = (p: DayPart) => p.startsLocal > p.endsLocal;

/**
 * The part of a given kind that STARTS on `localDate`, resolved by that
 * date's effective range. If two rows still overlap (the database now forbids
 * it; legacy data may not), the earliest start wins, deterministically — never
 * "whichever row Postgres returned first".
 */
function dayPartFor(ctx: ChildCtx, kind: string, localDate: string): DayPart | null {
  const dow = DateTime.fromISO(localDate, { zone: 'utc' }).weekday % 7;   // Sun=0
  return partsOn(ctx, localDate)
    .filter(p => p.kind === kind && p.daysOfWeek.includes(dow))
    .sort((a, b) => a.startsLocal.localeCompare(b.startsLocal))[0] ?? null;
}

/**
 * S-D11 — the day-part running at a child-LOCAL moment, with start-day
 * semantics: a part is active if it started today and has not ended, or it
 * wraps midnight, STARTED YESTERDAY, and has not ended yet today. Overlapping
 * rows (legacy data) resolve conservatively: an unreachable part wins over a
 * reachable one, then the kind name, so the result never depends on row order.
 */
export function activeDayPart(ctx: ChildCtx, local: DateTime): DayPart | null {
  const today = local.toISODate()!;
  const yesterday = local.minus({ days: 1 }).toISODate()!;
  const dow = local.weekday % 7;
  const yDow = (dow + 6) % 7;
  const hhmm = local.toFormat('HH:mm');

  const hits: DayPart[] = [];
  for (const p of partsOn(ctx, today)) {
    if (!p.daysOfWeek.includes(dow)) continue;
    const on = wraps(p) ? hhmm >= p.startsLocal
      : hhmm >= p.startsLocal && hhmm < p.endsLocal;
    if (on) hits.push(p);
  }
  for (const p of partsOn(ctx, yesterday)) {
    if (wraps(p) && p.daysOfWeek.includes(yDow) && hhmm < p.endsLocal) hits.push(p);
  }
  hits.sort((a, b) => Number(a.reachable) - Number(b.reachable) || a.kind.localeCompare(b.kind));
  return hits[0] ?? null;
}

/**
 * S-D10 — resolve a child-local wall clock to an instant in the zone she is
 * ACTUALLY in at that instant. The zone used to be read at 12:00 UTC of the
 * date, so a same-day flight (Austin -> Charlotte at 14:00) timed the evening
 * in the morning's zone. Iterates to a fixed point: wall clock in zone Z gives
 * an instant, the zone at that instant must be Z. If a travel boundary falls
 * between the candidates and no consistent answer exists, the later instant
 * and the zone she is in at that instant are used.
 */
export function zonedWallClock(ctx: ChildCtx, date: string, wall: string):
  { instant: DateTime; tz: string; anomaly: 'none' | 'nonexistent' | 'ambiguous' } {
  const zone0 = resolveZone(
    ctx.tzIntervals, DateTime.fromISO(`${date}T12:00`, { zone: 'utc' }), ctx.homeTz);
  const c1 = resolveWallClock(date, wall, zone0);
  const zone1 = resolveZone(ctx.tzIntervals, c1.instant, ctx.homeTz);
  if (zone1 === zone0) return { instant: c1.instant, tz: zone0, anomaly: c1.anomaly };
  const c2 = resolveWallClock(date, wall, zone1);
  if (resolveZone(ctx.tzIntervals, c2.instant, ctx.homeTz) === zone1) {
    return { instant: c2.instant, tz: zone1, anomaly: c2.anomaly };
  }
  // No consistent answer: travel made this wall clock not exist (she crossed a
  // boundary that skipped it). Like a DST gap, take the LATER instant, in the
  // zone she is in then.
  const later = c1.instant >= c2.instant ? c1 : c2;
  return { instant: later.instant,
    tz: resolveZone(ctx.tzIntervals, later.instant, ctx.homeTz), anomaly: later.anomaly };
}

/**
 * MASTERFILE §6.3 — resolve a delivery policy to an absolute instant.
 *
 * Pure. Takes the child's timezone timeline and day-parts as data so the whole
 * decision surface is testable without a database.
 */
export function materialize(intent: Intent, ctx: ChildCtx, now: DateTime): Result {
  if (TERMINAL.includes(intent.state)) return { ok: false, reason: 'terminal_state' };

  const expiry = DateTime.fromISO(intent.expiresAt, { zone: 'utc' });
  if (expiry <= now) return { ok: false, reason: 'already_expired' };

  const zoneNow = resolveZone(ctx.tzIntervals, now, ctx.homeTz);
  const graceFloor = now.minus({ minutes: PAST_GRACE_MINUTES });

  switch (intent.policy) {
    // Deliberately does NOT consult gate.ts's own asleep/school day-part
    // block — a settled product decision (owner-confirmed 2026-08-31,
    // v0.49.59), not an oversight. §6.4's gate is a CLIENT-side live warning
    // shown to the sender before she sends (server/routes.mjs's GET /now ->
    // send_time_guard.dart's GuardPrompt) — advisory, not an enforced hold.
    // An explicit send genuinely means "send now": a guardian who taps "Send
    // now anyway" past the warning, or any caller that resolves a policy to
    // 'immediate' at all, gets exactly that — no silent server-side defer to
    // the next reachable window. Making this case ALSO check gate() would
    // turn an advisory prompt into a hard block with no corresponding UX for
    // "your message was queued instead of delivered," which nothing in this
    // codebase has ever specified. If that changes, it belongs here.
    case 'immediate':
      return { ok: true, scheduledAt: now, tz: zoneNow, anomaly: 'none', rolled: false };

    case 'at_instant': {
      const t = DateTime.fromISO(intent.targetInstant!, { zone: 'utc' });
      if (t < graceFloor) return { ok: false, reason: 'target_in_past' };
      return { ok: true, scheduledAt: t, tz: zoneNow, anomaly: 'none', rolled: false };
    }

    /**
     * at_daypart with NO explicit date is an open-ended intent ("next bedtime").
     * If today's slot has already passed, ROLL FORWARD to the next matching day.
     * Contrast on_local_date below — that one names a specific night and must
     * NOT be silently moved.
     */
    case 'at_daypart': {
      const explicit = intent.targetLocalDate;
      let probe = DateTime.fromISO(explicit ?? now.setZone(zoneNow).toISODate()!,
                                  { zone: 'utc' });
      let rolled = false;

      for (let i = 0; i < 14; i++) {
        const date = probe.toISODate()!;
        const part = dayPartFor(ctx, intent.targetDaypart!, date);

        if (part) {
          const r = zonedWallClock(ctx, date, part.startsLocal);
          if (r.instant >= graceFloor) {
            return { ok: true, scheduledAt: r.instant, tz: r.tz,
                     anomaly: r.anomaly, rolled };
          }
          // Past the grace window. An explicitly dated at_daypart does not roll.
          if (explicit) return { ok: false, reason: 'target_in_past' };
        }
        probe = probe.plus({ days: 1 });
        rolled = true;
      }
      return { ok: false, reason: 'daypart_undefined' };
    }

    /**
     * on_local_date names a specific child-local night — a banked message, a
     * time capsule. The zone is resolved for THAT date, which is how a batch
     * survives a mid-flight move. If the night has passed beyond grace the
     * intent EXPIRES; delivering night 41 alongside night 60 would be worse
     * than not delivering it.
     */
    case 'on_local_date': {
      const date = intent.targetLocalDate!;
      const part = dayPartFor(ctx, intent.targetDaypart ?? 'bedtime', date);
      const wall = part?.startsLocal ?? '20:30';
      const r = zonedWallClock(ctx, date, wall);
      if (r.instant < graceFloor) return { ok: false, reason: 'target_in_past' };
      return { ok: true, scheduledAt: r.instant, tz: r.tz,
               anomaly: r.anomaly, rolled: false };
    }

    case 'when_reachable': {
      const win = nextReachableWindow(ctx, now, 14);
      if (!win) return { ok: false, reason: 'no_reachable_window' };
      return { ok: true, scheduledAt: win.start, tz: win.tz,
               anomaly: win.anomaly, rolled: false };
    }

    case 'on_event': {
      const iso = ctx.eventInstants?.[intent.targetEventId!];
      if (!iso) return { ok: false, reason: 'unresolvable_event' };
      const t = DateTime.fromISO(iso, { zone: 'utc' });
      if (t < graceFloor) return { ok: false, reason: 'target_in_past' };
      return { ok: true, scheduledAt: t, tz: zoneNow, anomaly: 'none', rolled: false };
    }
  }
}

/**
 * The first moment at or after `from` that the child is reachable, searching
 * `maxDays`.
 *
 * S-D11 — if `from` is already INSIDE a reachable window, that moment is the
 * answer ("now"): a when_reachable message sent at 16:00 during after_school
 * used to wait for the next window, because only window STARTS were candidates
 * and `start >= from` excluded the one she was already in. Dates are walked in
 * the child's own calendar, and each candidate start is resolved in the zone
 * she is in at that instant (S-D10).
 */
export function nextReachableWindow(
  ctx: ChildCtx, from: DateTime, maxDays = 14
): { start: DateTime; tz: string; anomaly: 'none' | 'nonexistent' | 'ambiguous' } | null {
  const zoneNow = resolveZone(ctx.tzIntervals, from, ctx.homeTz);
  const cur = activeDayPart(ctx, from.setZone(zoneNow));
  if (cur && cur.reachable) return { start: from, tz: zoneNow, anomaly: 'none' };

  const baseDate = DateTime.fromISO(from.setZone(zoneNow).toISODate()!, { zone: 'utc' });
  for (let i = 0; i < maxDays; i++) {
    const date = baseDate.plus({ days: i }).toISODate()!;
    const dow = baseDate.plus({ days: i }).weekday % 7;

    const candidates = partsOn(ctx, date)
      .filter(p => p.reachable && p.daysOfWeek.includes(dow))
      .map(p => ({ p, r: zonedWallClock(ctx, date, p.startsLocal) }))
      .filter(x => x.r.instant >= from)
      .sort((a, b) => a.r.instant.toMillis() - b.r.instant.toMillis());

    if (candidates.length) {
      const c = candidates[0];
      return { start: c.r.instant, tz: c.r.tz, anomaly: c.r.anomaly };
    }
  }
  return null;
}
