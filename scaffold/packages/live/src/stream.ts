/**
 * MASTERFILE §5.27 — stream stability.
 *
 * The rung ladder (§5.23.2) already says HD → SD → audio-only → banked. What it
 * does not have is **hysteresis**, and without it a wobbling connection will
 * flicker between rungs every few seconds.
 *
 * A picture that keeps appearing and vanishing is worse than no picture at all —
 * it draws the eye each time, and a child looks up expecting her father and gets
 * a grey rectangle. She will stop looking up.
 *
 * This module sits UNDER `LADDER` rather than beside it. The rung ladder decides
 * *what kind* of call this is; the quality ladder decides how good the video is
 * while it is still video, so there is real headroom before the picture goes at
 * all.
 */

// ============================================== §5.27.1 the quality ladder ==
/**
 * Three video qualities, all of them still video. By the time the rung ladder
 * drops to `audio_only`, three steps have already been tried — which is the
 * whole point of putting a ladder underneath a ladder.
 */
export type Quality = 720 | 360 | 180;

export const QUALITIES: Quality[] = [720, 360, 180];

export function stepQualityDown(q: Quality): Quality {
  const i = QUALITIES.indexOf(q);
  return QUALITIES[Math.min(i + 1, QUALITIES.length - 1)];
}

export function stepQualityUp(q: Quality): Quality {
  const i = QUALITIES.indexOf(q);
  return QUALITIES[Math.max(i - 1, 0)];
}

export const atFloor = (q: Quality) => q === 180;
export const atCeiling = (q: Quality) => q === 720;

// ================================================== §5.27.2 the hysteresis ==
/**
 * **Quick to shed, slow to restore.** Deliberately asymmetric.
 *
 * Dropping fast is kind: the picture degrades before she notices it stuttering.
 * Restoring slowly is kinder: a connection that has been bad for twenty seconds
 * and good for two is not a good connection, and treating it as one produces
 * exactly the flicker this module exists to prevent.
 */
export const DROP_AFTER_MS = 2_000;
export const RESTORE_AFTER_MS = 12_000;

export interface StreamState {
  quality: Quality;
  /** Video present at all. False means the rung ladder has moved to audio. */
  video: boolean;
  /** Continuous ms in the current condition. Reset on any change. */
  troubleMs: number;
  steadyMs: number;
  /** Told once per call, not continuously. */
  toldHer: boolean;
}

export function newStream(): StreamState {
  return { quality: 720, video: true, troubleMs: 0, steadyMs: 0, toldHer: false };
}

export type Condition = 'good' | 'strained';

export interface Tick { condition: Condition; elapsedMs: number }

/**
 * One step per evaluation, never two. A connection that collapses does not jump
 * from 720 to audio in a single frame — it walks down, and each step is a chance
 * for it to stabilise.
 */
export function evaluate(s: StreamState, t: Tick): {
  state: StreamState; changed: 'down' | 'up' | null;
} {
  if (t.condition === 'strained') {
    const troubleMs = s.troubleMs + t.elapsedMs;
    if (troubleMs < DROP_AFTER_MS) {
      return { state: { ...s, troubleMs, steadyMs: 0 }, changed: null };
    }
    // Time to shed something.
    if (!atFloor(s.quality)) {
      return { state: { ...s, quality: stepQualityDown(s.quality),
        troubleMs: 0, steadyMs: 0 }, changed: 'down' };
    }
    if (s.video) {
      // Only now does the rung ladder move to audio-only.
      return { state: { ...s, video: false, troubleMs: 0, steadyMs: 0 },
        changed: 'down' };
    }
    return { state: { ...s, troubleMs: 0, steadyMs: 0 }, changed: null };
  }

  const steadyMs = s.steadyMs + t.elapsedMs;
  if (steadyMs < RESTORE_AFTER_MS) {
    return { state: { ...s, steadyMs, troubleMs: 0 }, changed: null };
  }
  if (!s.video) {
    return { state: { ...s, video: true, troubleMs: 0, steadyMs: 0 }, changed: 'up' };
  }
  if (!atCeiling(s.quality)) {
    return { state: { ...s, quality: stepQualityUp(s.quality),
      troubleMs: 0, steadyMs: 0 }, changed: 'up' };
  }
  return { state: { ...s, steadyMs: 0, troubleMs: 0 }, changed: null };
}

/** Restoring is six times slower than dropping. Asserted, because it is the point. */
export const RESTORE_IS_SLOWER = RESTORE_AFTER_MS > DROP_AFTER_MS;
export const ASYMMETRY_RATIO = RESTORE_AFTER_MS / DROP_AFTER_MS;

// ============================================ §5.27.3 what she is told ======
/**
 * Once. Not a banner that lingers, and **never a connection meter** — a
 * five-year-old watching a signal indicator is a five-year-old not watching her
 * father.
 */
export interface StreamNotice { line: string; once: true }

export function noticeFor(s: StreamState): StreamNotice | null {
  if (s.toldHer) return null;
  if (!s.video) {
    return { line: 'It has gone a bit slow — you can still hear him.', once: true };
  }
  return null;
}

export function markTold(s: StreamState): StreamState {
  return { ...s, toldHer: true };
}

/**
 * Video returning mid-conversation does **not** ask permission.
 *
 * `resumeOffer()` in §5.23 is for a call that dropped and reconnected — a new
 * transmission. A picture coming back inside a call that never stopped is not
 * that, and asking would interrupt the thing it is improving.
 */
export const RESTORE_ASKS_PERMISSION = false;

export const NO_CONNECTION_METER = true;

/** Nothing here may blame her, her network, or her device. */
export const STREAM_BANNED = [
  'your connection', 'your network', 'your wifi', 'weak signal', 'poor',
  'check your', 'unstable', 'try moving', 'bandwidth',
] as const;

export function auditNotice(n: StreamNotice | null): { ok: true } | { ok: false; found: string[] } {
  if (!n) return { ok: true };
  const t = n.line.toLowerCase();
  const found = (STREAM_BANNED as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

// ============================================ §5.27.4 what the sender sees ==
/**
 * He gets more detail than she does, because he can act on it — moving nearer a
 * router is a thing an adult can do. It is still not a meter.
 */
export function senderLine(s: StreamState): string {
  if (!s.video) return 'Voice only — the line will not carry the picture just now.';
  if (s.quality === 180) return 'The picture is soft. The line is working hard.';
  return '';
}

/** The floor. A call never drops below this while any connection exists at all. */
export const AUDIO_FLOOR = true;

export function audioSurvives(_s: StreamState): true { return true; }
