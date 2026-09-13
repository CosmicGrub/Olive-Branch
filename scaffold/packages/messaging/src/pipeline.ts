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
  | 'target_date_in_past'
  /**
   * §9.5/§9.8.1 — a CHILD-originated capture (senderRole 'child') whose
   * `senderChildId` is missing or names a DIFFERENT child than `childId`.
   * The schema (0019_child_message_sender.sql) can only ever attribute a
   * child-sent artifact/intent to the child it is FOR — see that
   * migration's own header on why this is checked here too, not only at
   * the database's CHECK constraints, and not only by the caller trusting
   * the session (packages/api/src/api.ts's A3).
   */
  | 'child_sender_mismatch'
  /**
   * §9.8.1 — preservation is a GUARDIAN election. A child-originated
   * capture that asks to skip its own retention clock is refused cleanly
   * here, rather than reaching persistCapturedMessage() and failing on
   * media_artifact's `preservation_is_attributed` CHECK with no `preserved_
   * by` value to attribute it to (a child has no app_user id to put there).
   */
  | 'child_cannot_preserve';

export interface CaptureInput {
  childId: string;
  /**
   * The app_user id of a guardian/adult sender. Required for every
   * `senderRole` except `'child'` — a child has no app_user row
   * (packages/auth/src/auth.ts's VerifiedPrincipal carries `userId: string
   * | null`, always null for a child session), so a child-originated
   * capture leaves this null/undefined and supplies `senderChildId`
   * instead. Never both, never neither — see this file's `captureMessage`
   * for the branch that enforces that.
   */
  senderId?: string | null;
  senderRole: string;
  /**
   * Set ONLY when `senderRole === 'child'`: the id of the child sending
   * this message about herself (§9.5's "she has just drawn something for
   * her father", extended to video). Must equal `childId` — a child can
   * only ever be recorded as the sender of HER OWN artifact, never another
   * child's, even on a shared/kiosk device (0019_child_message_sender.sql).
   */
  senderChildId?: string | null;
  storageKey: string;
  durationMs: number;
  captionKey?: string;
  /** null = deliver at the next bedtime; a date = a specific night. */
  targetLocalDate: string | null;
  daypart: string;
  /** Guardian election, §9.8.1. Batch payloads default true (§9.5). Never
   * true for a child-originated capture — see `child_cannot_preserve`. */
  preserve: boolean;
  batchId?: string;
  batchSeq?: number;
}

export interface ArtifactRow {
  childId: string;
  /** Exactly one of authorId/authorChildId is non-null when the sender is
   * known at all — see 0019_child_message_sender.sql's `author_is_one_kind`.
   * Both null still means "unknown/system", unchanged from before that
   * migration. */
  authorId: string | null; authorChildId: string | null; kind: 'video_msg';
  storageKey: string; durationMs: number; captionKey: string | null;
  capturedAt: string; capturedTz: string; eraTag: string | null;
  preserved: boolean; preservedBy: string | null; preservedAt: string | null;
  expiresAt: string | null;
}

export interface IntentRow {
  childId: string;
  /** Exactly one of senderId/senderChildId is non-null on every row — see
   * 0019_child_message_sender.sql's `sender_is_exactly_one_kind`. Unlike
   * ArtifactRow's author fields, a delivery_intent has never been allowed
   * an unattributed sender, and still is not. */
  senderId: string | null; senderChildId: string | null;
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

  const isChildSender = input.senderRole === 'child';

  if (isChildSender) {
    // A child holds no guardianship EDGE to herself — can()'s whole model
    // (family-graph/authorize.ts) is "does this app_user's edge grant
    // access to this child", which a child acting on her own behalf never
    // satisfies and was never meant to. Self-authorship is answered as an
    // IDENTITY question instead, the same shape server/routes.mjs's kiosk-
    // pin/verify and handover routes already use for "is this session
    // literally this child" — she may always send about herself; the only
    // thing to check is that she isn't (or a caller bug isn't) attributing
    // the send to a DIFFERENT child (0019_child_message_sender.sql).
    if (!input.senderChildId || input.senderChildId !== input.childId) {
      return { ok: false, reason: 'child_sender_mismatch' };
    }
    if (input.preserve) return { ok: false, reason: 'child_cannot_preserve' };
  } else {
    const d = can('message', edges, input.childId, now.toJSDate(), input.senderRole);
    if (!d.allow) return { ok: false, reason: 'not_authorized' };
  }

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

  // Exactly one of {authorId, authorChildId} / {senderId, senderChildId} is
  // populated — see 0019_child_message_sender.sql. `preserve` is already
  // refused above for a child sender, so `preservedBy` (which must name a
  // real app_user, media_artifact's own `preservation_is_attributed` CHECK)
  // is never asked to hold a child's id here.
  return {
    ok: true,
    artifact: {
      childId: input.childId,
      authorId: isChildSender ? null : input.senderId ?? null,
      authorChildId: isChildSender ? input.senderChildId! : null,
      kind: 'video_msg',
      storageKey: input.storageKey,
      durationMs: input.durationMs,
      captionKey: input.captionKey ?? null,
      capturedAt: now.toISO()!,
      capturedTz: zone,
      eraTag: null,
      preserved: input.preserve,
      preservedBy: input.preserve ? (input.senderId ?? null) : null,
      preservedAt: input.preserve ? now.toISO()! : null,
      expiresAt: artifactExpiry?.toISO() ?? null,
    },
    intent: {
      childId: input.childId,
      senderId: isChildSender ? null : input.senderId ?? null,
      senderChildId: isChildSender ? input.senderChildId! : null,
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
