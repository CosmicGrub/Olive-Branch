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
  daysOfWeek: number[];         // 0 = Sunday
  reachable: boolean;
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

function dayPartFor(ctx: ChildCtx, kind: string, localDate: string): DayPart | null {
  const dow = DateTime.fromISO(localDate, { zone: 'utc' }).weekday % 7;   // Sun=0
  return ctx.dayParts.find(p => p.kind === kind && p.daysOfWeek.includes(dow)) ?? null;
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
        const zone = resolveZone(
          ctx.tzIntervals, DateTime.fromISO(`${date}T12:00`, { zone: 'utc' }), ctx.homeTz);
        const part = dayPartFor(ctx, intent.targetDaypart!, date);

        if (part) {
          const r = resolveWallClock(date, part.startsLocal, zone);
          if (r.instant >= graceFloor) {
            return { ok: true, scheduledAt: r.instant, tz: zone,
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
      const zone = resolveZone(
        ctx.tzIntervals, DateTime.fromISO(`${date}T12:00`, { zone: 'utc' }), ctx.homeTz);
      const part = dayPartFor(ctx, intent.targetDaypart ?? 'bedtime', date);
      const wall = part?.startsLocal ?? '20:30';
      const r = resolveWallClock(date, wall, zone);
      if (r.instant < graceFloor) return { ok: false, reason: 'target_in_past' };
      return { ok: true, scheduledAt: r.instant, tz: zone,
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

/** First reachable day-part starting at or after `from`, searching `maxDays`. */
export function nextReachableWindow(
  ctx: ChildCtx, from: DateTime, maxDays = 14
): { start: DateTime; tz: string; anomaly: 'none' | 'nonexistent' | 'ambiguous' } | null {
  for (let i = 0; i < maxDays; i++) {
    const probe = from.plus({ days: i });
    const date = probe.toISODate()!;
    const zone = resolveZone(
      ctx.tzIntervals, DateTime.fromISO(`${date}T12:00`, { zone: 'utc' }), ctx.homeTz);
    const dow = DateTime.fromISO(date, { zone: 'utc' }).weekday % 7;

    const candidates = ctx.dayParts
      .filter(p => p.reachable && p.daysOfWeek.includes(dow))
      .map(p => ({ p, r: resolveWallClock(date, p.startsLocal, zone) }))
      .filter(x => x.r.instant >= from)
      .sort((a, b) => a.r.instant.toMillis() - b.r.instant.toMillis());

    if (candidates.length) {
      const c = candidates[0];
      return { start: c.r.instant, tz: zone, anomaly: c.r.anomaly };
    }
  }
  return null;
}
