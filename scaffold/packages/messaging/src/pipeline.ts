import { DateTime } from 'luxon';
import { can, type Edge } from '../../family-graph/src/authorize.ts';
import { materialize, type Intent, type ChildCtx } from '../../delivery-engine/src/materialize.ts';

/**
 * MASTERFILE §9.5, §5.3, §5.6 — the async video message, end to end.
 *
 * This is the first module that spans packages: family-graph authorizes,
 * media_artifact holds the payload under a retention clock, delivery-engine
 * schedules it, the gate defers it, and playback writes a receipt in the
 * child's frame. The bugs live at the seams, not inside any one package.
 */

export type CaptureDenial =
  | 'not_authorized'
  | 'retention_shorter_than_delivery'
  | 'empty_recording'
  | 'target_date_in_past';

export interface CaptureInput {
  childId: string;
  senderId: string;
  senderRole: string;
  storageKey: string;
  durationMs: number;
  captionKey?: string;
  /** null = deliver at the next bedtime; a date = a specific night. */
  targetLocalDate: string | null;
  daypart: string;
  /** Guardian election, §9.8.1. Batch payloads default true (§9.5). */
  preserve: boolean;
  batchId?: string;
  batchSeq?: number;
}

export interface ArtifactRow {
  childId: string; authorId: string; kind: 'video_msg';
  storageKey: string; durationMs: number; captionKey: string | null;
  capturedAt: string; capturedTz: string; eraTag: string | null;
  preserved: boolean; preservedBy: string | null; preservedAt: string | null;
  expiresAt: string | null;
}

export interface IntentRow {
  childId: string; senderId: string;
  payloadKind: 'video_msg'; payloadRef: string;
  policy: 'at_daypart' | 'on_local_date';
  targetLocalDate: string | null; targetDaypart: string;
  batchId: string | null; batchSeq: number | null;
  expiresAt: string;
  state: 'pending';
}

/**
 * §10.1 retention, per payload kind. A video message lives 30 days after open
 * and 90 days if never opened.
 */
export const UNOPENED_RETENTION_DAYS = 90;
export const OPENED_RETENTION_DAYS = 30;

/**
 * THE SEAM BUG this constant exists to prevent.
 *
 * `media_artifact.expires_at` and `delivery_intent.expires_at` are set
 * independently, by different concerns — one is storage retention, the other is
 * delivery validity. Nothing in the schema relates them. If the artifact clock
 * is shorter, the sweep happily delivers an intent whose blob has already been
 * reaped, and the child opens a message that plays nothing.
 *
 * A delivered message pointing at a deleted object is worse than an undelivered
 * one, because the child sees it arrive.
 */
export const ARTIFACT_GRACE_DAYS = 7;

export function captureMessage(
  input: CaptureInput,
  edges: Edge[],
  ctx: ChildCtx,
  now: DateTime,
): { ok: true; artifact: ArtifactRow; intent: Omit<IntentRow, 'payloadRef'> }
 | { ok: false; reason: CaptureDenial } {

  if (input.durationMs <= 0) return { ok: false, reason: 'empty_recording' };

  const d = can('message', edges, input.childId, now.toJSDate(), input.senderRole);
  if (!d.allow) return { ok: false, reason: 'not_authorized' };

  const zone = ctxZone(ctx, now);

  // Resolve the delivery instant FIRST, so the artifact's retention can be
  // derived from it rather than guessed.
  const probe: Intent = {
    id: 'probe', childId: input.childId, state: 'pending',
    expiresAt: now.plus({ days: UNOPENED_RETENTION_DAYS }).toISO()!,
    policy: input.targetLocalDate ? 'on_local_date' : 'at_daypart',
    targetLocalDate: input.targetLocalDate ?? undefined,
    targetDaypart: input.daypart,
  };
  const m = materialize(probe, ctx, now);
  if (!m.ok) {
    return { ok: false, reason: m.reason === 'target_in_past'
      ? 'target_date_in_past' : 'not_authorized' };
  }

  const intentExpiry = m.scheduledAt.plus({ days: UNOPENED_RETENTION_DAYS });
  // The artifact must outlive the intent, with slack. Preserved artifacts have
  // no clock at all (§5.6 CHECK).
  const artifactExpiry = input.preserve
    ? null
    : intentExpiry.plus({ days: ARTIFACT_GRACE_DAYS });

  if (artifactExpiry && artifactExpiry <= intentExpiry) {
    return { ok: false, reason: 'retention_shorter_than_delivery' };
  }

  return {
    ok: true,
    artifact: {
      childId: input.childId,
      authorId: input.senderId,
      kind: 'video_msg',
      storageKey: input.storageKey,
      durationMs: input.durationMs,
      captionKey: input.captionKey ?? null,
      capturedAt: now.toISO()!,
      capturedTz: zone,
      eraTag: null,
      preserved: input.preserve,
      preservedBy: input.preserve ? input.senderId : null,
      preservedAt: input.preserve ? now.toISO()! : null,
      expiresAt: artifactExpiry?.toISO() ?? null,
    },
    intent: {
      childId: input.childId,
      senderId: input.senderId,
      payloadKind: 'video_msg',
      policy: input.targetLocalDate ? 'on_local_date' : 'at_daypart',
      targetLocalDate: input.targetLocalDate,
      targetDaypart: input.daypart,
      batchId: input.batchId ?? null,
      batchSeq: input.batchSeq ?? null,
      expiresAt: intentExpiry.toISO()!,
      state: 'pending',
    },
  };
}

function ctxZone(ctx: ChildCtx, at: DateTime): string {
  const t = at.toMillis();
  const hit = ctx.tzIntervals.find(iv => {
    const s = iv.start ? DateTime.fromISO(iv.start, { zone: 'utc' }).toMillis() : -Infinity;
    const e = iv.end ? DateTime.fromISO(iv.end, { zone: 'utc' }).toMillis() : Infinity;
    return t >= s && t < e;
  });
  return hit?.tz ?? ctx.homeTz;
}

/**
 * §8.2.4 — a receipt renders in HER frame, at the zone she was in when she
 * opened it. Not the capture zone: a message recorded while she was in Texas and
 * opened after she flew home reads in Eastern, because that is the fact the
 * parent wants.
 */
export function openReceipt(
  ctx: ChildCtx, openedAt: DateTime, dayPartKind: string | null,
): { localTime: string; zone: string; phrase: string } {
  const zone = ctxZone(ctx, openedAt);
  const local = openedAt.setZone(zone);
  const t = local.toFormat('h:mm a');
  const context: Record<string, string> = {
    wake: 'before school', before_school: 'before school',
    after_school: 'after school', dinner: 'at dinner',
    wind_down: 'winding down', bedtime: 'at bedtime',
    free: '', school: 'at school', asleep: '',
  };
  const suffix = dayPartKind ? context[dayPartKind] ?? '' : '';
  return {
    localTime: t, zone,
    phrase: suffix
      ? `Watched at ${t} her time — ${suffix}.`
      : `Watched at ${t} her time.`,
  };
}

/** Retention shortens once opened (§10.1). Never lengthens. */
export function retentionOnOpen(
  currentExpiry: string | null, openedAt: DateTime, preserved: boolean,
): string | null {
  if (preserved) return null;
  const proposed = openedAt.plus({ days: OPENED_RETENTION_DAYS });
  if (!currentExpiry) return proposed.toISO()!;
  const current = DateTime.fromISO(currentExpiry, { zone: 'utc' });
  // Opening must not extend an artifact's life beyond its unopened clock.
  return (proposed < current ? proposed : current).toISO()!;
}
