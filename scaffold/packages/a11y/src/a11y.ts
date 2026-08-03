/**
 * MASTERFILE §8.8 — accessibility.
 *
 * Two audiences needing opposite things. A deaf father needs captions on a call;
 * a five-year-old who cannot read needs the interface to stop depending on words
 * at all. Treating "accessibility" as one setting would have served neither.
 */

export type CaptionMode = 'off' | 'live' | 'live_and_saved';

/**
 * §8.8.1 — captions.
 *
 * A caption track is a TRANSCRIPT of a child's call, which is exactly what §13
 * and P8 exist to be careful about. So a saved caption is treated as call media:
 * it inherits the call's retention rather than getting its own longer clock.
 *
 * Live captions never leave the device. That is not a performance choice — an
 * on-device track is the only version a subpoena cannot reach.
 */
export interface CaptionPolicy {
  mode: CaptionMode;
  onDevice: true;
  retentionFollowsCall: true;
  /** Both parties are told, because a transcript is not obvious. */
  disclosedToBoth: true;
}

export function captionPolicy(mode: CaptionMode): CaptionPolicy {
  return { mode, onDevice: true, retentionFollowsCall: true, disclosedToBoth: true };
}

/** A caption outlives the call only where the call itself was recorded. */
export function captionsSurviveCall(p: CaptionPolicy, recorded: boolean): boolean {
  return p.mode === 'live_and_saved' && recorded;
}

/** §8.8.2 — motion. Vestibular triggers are not a preference. */
export interface MotionPolicy {
  reduced: boolean;
  transitionMs: number;
  parallax: boolean;
  autoplayVideo: boolean;
  /** A page turn still animates: it is the affordance, not decoration. */
  essentialMotionKept: true;
}

export const MOTION_FULL: MotionPolicy = { reduced: false, transitionMs: 220,
  parallax: true, autoplayVideo: true, essentialMotionKept: true };
/** Not zero — a hard cut is disorienting too. */
export const MOTION_REDUCED: MotionPolicy = { reduced: true, transitionMs: 90,
  parallax: false, autoplayVideo: false, essentialMotionKept: true };

export const motionPolicy = (prefersReduced: boolean) =>
  prefersReduced ? MOTION_REDUCED : MOTION_FULL;

/**
 * §8.8.3 — text scale.
 *
 * The upper bound matters more than the lower. At 200% on the Fold's 344 px cover
 * screen a two-column layout leaves 172 px per column and nothing fits — so scale
 * and layout are decided together rather than independently.
 */
export const TEXT_SCALES = [0.85, 1.0, 1.15, 1.3, 1.6, 2.0] as const;
export const COLLAPSE_TO_ONE_COLUMN_ABOVE = 1.3;
export const BASE_TAP_PX = 64;

export function layoutFor(scale: number, viewportWidth: number): {
  columns: 1 | 2; minTapPx: number; scale: number;
} {
  const lo = TEXT_SCALES[0], hi = TEXT_SCALES[TEXT_SCALES.length - 1];
  const s = Math.max(lo, Math.min(scale, hi));
  const two = viewportWidth >= 600 && s <= COLLAPSE_TO_ONE_COLUMN_ABOVE;
  // §8.4's 64 dp floor scales UP with text but never down.
  return { columns: two ? 2 : 1, minTapPx: Math.round(BASE_TAP_PX * Math.max(1, s)),
    scale: s };
}

/**
 * §8.8.4 — screen-reader labels.
 *
 * The rule: a label says what a control DOES, not what it looks like. "Star" is a
 * shape; "keep this story" is an action, and it is the only one of the two a
 * blind parent can act on.
 */
export const LABEL_BANNED = [
  'icon', 'button', 'image', 'graphic', 'click', 'tap here', 'arrow',
  'chevron', 'the blue one', 'above', 'below', 'left', 'right',
] as const;

export function auditLabel(label: string): { ok: true } | { ok: false; found: string[] } {
  const t = label.toLowerCase();
  const found = (LABEL_BANNED as readonly string[]).filter(w =>
    new RegExp('\\b' + w.replace(/ /g, '\\s') + '\\b').test(t));
  return found.length ? { ok: false, found } : { ok: true };
}

export const LABELS: Record<string, string> = {
  star: 'Keep this story',
  bookmark: 'Save your place in this story',
  turn_page: 'Next page',
  back_page: 'Previous page',
  colour_region: 'Colour this part of the picture',
  send_show: 'Send this to Daddy',
  end_call: 'Finish the call',
  pin_digit: 'Enter one digit of your PIN',
  hide_work: 'Put this picture away',
  find_target: 'Tap the thing you are looking for',
};

/**
 * §8.8.5 — read-aloud for pre-readers. New v0.39.0.
 *
 * §8.8b's baseline spoken form covers the sixteen come-back-signal
 * applications. It does not cover general navigation: a five-year-old still
 * cannot tell what "My weeks" says on an ordinary screen.
 *
 * On-device only, always — the same posture already settled for captions
 * (§8.8.1). A child's voice browsing her own calendar never leaves the device
 * for a cloud text-to-speech API. And unlike §8.8.1's caption pipeline,
 * nothing here is retained, transcribed, or treated as call media.
 */
export const READ_ALOUD_ON_DEVICE_ONLY = true;
export const READ_ALOUD_NEVER_LOGGED = true;

/**
 * Reads the accessibility label, not a second copy of it — the same string a
 * screen reader already gets (§8.8.4's LABELS) wherever one exists, falling
 * back to visible text only where no label has been written yet. Two
 * hand-maintained strings for the same control is a drift bug waiting to
 * happen; this makes drift structurally impossible for anything with a label.
 */
export function speakableText(controlId: string, visibleText: string): string {
  return LABELS[controlId] ?? visibleText;
}

export type SpeechTrigger = 'tap' | 'autonomous';
export type SpeechRefusal = 'autonomous';

/**
 * Never autonomous. Speech that starts itself, rather than in response to a
 * tap, is §8.13's slot-machine mechanic wearing a voice.
 */
export function admitSpeech(
  trigger: SpeechTrigger,
): { ok: true } | { ok: false; reason: SpeechRefusal; note: string } {
  if (trigger === 'autonomous') {
    return { ok: false, reason: 'autonomous',
      note: 'Speech that starts itself, rather than in response to a tap, is '
          + '§8.13\'s slot-machine mechanic wearing a voice.' };
  }
  return { ok: true };
}

/**
 * Default-on below age 8, opt-in above it — mirrors the birthday-hint fade
 * already used at §8.5.2's HINT_FADES_AT_AGE: a scaffolding aid that quietly
 * stops being necessary, rather than a setting a child has to go find and
 * switch off.
 */
export const READ_ALOUD_DEFAULT_BELOW_AGE = 8;

export function readAloudDefaultOn(age: number | null): boolean {
  return age === null || age < READ_ALOUD_DEFAULT_BELOW_AGE;
}
