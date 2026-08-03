import { DateTime } from 'luxon';
import { resolveZone } from '../../time-engine/src/time.ts';
import { nextReachableWindow, type ChildCtx } from './materialize.ts';

export type Priority = 'normal' | 'emergency';

export interface GateResult {
  allow: boolean;
  reason?: string;                 // day-part kind that blocked it
  deferTo?: DateTime;
  deferCount?: number;
}

/**
 * A gate may postpone a delivery, but a postponement that can postpone itself
 * forever is an outage that looks like silence. If a delivery has been deferred
 * this many times, it goes out anyway and the anomaly is logged — a message
 * arriving at an imperfect hour beats a message that never arrives.
 */
export const MAX_DEFERS = 3;

/**
 * MASTERFILE §6.4, recipient side. Blocks arrivals during `asleep` and
 * `school`. Emergency priority is never gated.
 */
export function gate(
  ctx: ChildCtx,
  now: DateTime,
  priority: Priority = 'normal',
  deferCount = 0
): GateResult {
  if (priority === 'emergency') return { allow: true };

  if (deferCount >= MAX_DEFERS) {
    // Fail OPEN, deliberately, and loudly.
    return { allow: true, reason: 'max_defers_exceeded', deferCount };
  }

  const zone = resolveZone(ctx.tzIntervals, now, ctx.homeTz);
  const local = now.setZone(zone);
  const dow = local.weekday % 7;
  const hhmm = local.toFormat('HH:mm');

  const current = ctx.dayParts.find(p => {
    if (!p.daysOfWeek.includes(dow)) return false;
    // A day-part may wrap midnight (asleep 21:00 → 06:30).
    return p.startsLocal <= p.endsLocal
      ? hhmm >= p.startsLocal && hhmm < p.endsLocal
      : hhmm >= p.startsLocal || hhmm < p.endsLocal;
  });

  if (current && !current.reachable) {
    const win = nextReachableWindow(ctx, now);
    return {
      allow: false,
      reason: current.kind,
      deferTo: win?.start,
      deferCount: deferCount + 1,
    };
  }
  return { allow: true };
}

/**
 * MASTERFILE §6.4, sender side. Powers the send-time guard so a parent is
 * warned before creating a 2 a.m. arrival rather than after.
 */
export function recipientContext(ctx: ChildCtx, now: DateTime, actorTz: string) {
  const zone = resolveZone(ctx.tzIntervals, now, ctx.homeTz);
  const local = now.setZone(zone);
  const g = gate(ctx, now);
  return {
    localTime: local.toFormat('h:mm a'),
    zoneAbbr: local.toFormat('ZZZZ'),
    zone,
    reachable: g.allow,
    dayPart: g.reason,
    deferTo: g.deferTo?.setZone(zone).toFormat('h:mm a'),
    skewHours: (local.offset - now.setZone(actorTz).offset) / 60,
  };
}
