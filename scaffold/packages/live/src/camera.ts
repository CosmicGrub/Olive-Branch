/**
 * MASTERFILE §5.24 — the camera, the speaker, and P10.
 */

export type Side = 'A' | 'B';
export type Posture =
  | 'fold_cover' | 'fold_main' | 'fold_tabletop' | 'phone'
  | 'tablet_small' | 'tablet_medium' | 'tablet_large' | 'desktop' | 'dex';

// ================================================= §5.24.1 "show me", live ==
/**
 * The rear camera is the showcase (§9.10) happening in real time, and it is
 * probably the highest-value thing in this whole section.
 *
 * "Show me" during a call means turning the phone around. Every other product
 * treats the rear camera as an afterthought; here it is the point — a child
 * showing her father the thing she is holding is the entire product in one
 * gesture.
 */
export type Facing = 'front' | 'rear';

export interface CameraState {
  facing: Facing;
  /** Mirroring is right for a face and wrong for writing. See below. */
  mirrored: boolean;
  zoom: number;
  torch: boolean;
}

export const MAX_ZOOM = 4;

export function camera(): CameraState {
  return { facing: 'front', mirrored: true, zoom: 1, torch: false };
}

/**
 * Flipping to the rear camera turns mirroring OFF.
 *
 * A mirrored rear camera renders every word she holds up backwards, which is the
 * single most common complaint about showing a drawing on a video call — and it
 * makes the homework case useless.
 */
export function flip(c: CameraState): CameraState {
  const facing: Facing = c.facing === 'front' ? 'rear' : 'front';
  return { ...c, facing, mirrored: facing === 'front', zoom: 1 };
}

export function setZoom(c: CameraState, z: number): CameraState {
  return { ...c, zoom: Math.max(1, Math.min(MAX_ZOOM, z)) };
}

/** The torch is only useful behind. Offering it on the front is a flash in the face. */
export function canTorch(c: CameraState): boolean { return c.facing === 'rear'; }

/**
 * Auto-framing keeps her in shot while she moves, because she will not sit
 * still. It is a crop, not a subject-recognition claim, and it never follows her
 * out of frame — a camera that pans around a child's bedroom is a different
 * product.
 */
export interface Framing { autoFrame: boolean; pansBeyondFrame: false }
export function framing(on: boolean): Framing {
  return { autoFrame: on, pansBeyondFrame: false };
}

/** Lighting advice is about the room, never about her. */
export function lightingAdvice(lux: number): string | null {
  if (lux >= 40) return null;
  return 'It is very dark in there — is there a light you can put on?';
}

export const LIGHTING_BANNED = ['you look', 'we cannot see you', 'your face', 'too dark for us'] as const;

export function auditLighting(text: string | null): { ok: true } | { ok: false; found: string[] } {
  if (!text) return { ok: true };
  const t = text.toLowerCase();
  const found = (LIGHTING_BANNED as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

// ===================================================== §5.24.2 P10 ==========
/**
 * **P10 — NO APPEARANCE MODIFICATION ON A CHILD'S VIDEO.**
 *
 * No beauty filters, no smoothing, no slimming, no eye enlargement, no
 * "touch-up". Not as a default, not as an option, not as a fun sticker that
 * happens to reshape a face.
 *
 * Appearance modification aimed at a child is a self-image harm wearing a fun
 * hat. It teaches a five-year-old that the version of her face the software
 * prefers is better than the one her father sees, and it does it during the one
 * activity in this product that exists so he can see her.
 *
 * It costs nothing to prohibit today and becomes very expensive to remove later,
 * because by then it is a feature somebody likes.
 */
export const P10_NO_APPEARANCE_MODIFICATION = true;

export const BANNED_VIDEO_EFFECTS = [
  'beauty', 'smoothing', 'skin_smooth', 'slimming', 'face_slim', 'eye_enlarge',
  'touch_up', 'retouch', 'blemish', 'whitening', 'jawline', 'nose_slim',
  'makeup', 'lipstick', 'filter_pretty',
] as const;

/** Silly is fine. A dog nose is not a beauty filter. */
export const ALLOWED_VIDEO_EFFECTS = [
  'dog_ears', 'silly_hat', 'googly_eyes', 'rainbow', 'sparkles', 'dinosaur',
] as const;

export type EffectVerdict =
  | { ok: true }
  | { ok: false; reason: 'appearance_modification'; effect: string };

export function admitEffect(effect: string): EffectVerdict {
  const e = effect.toLowerCase();
  if ((BANNED_VIDEO_EFFECTS as readonly string[]).some(b => e.includes(b))) {
    return { ok: false, reason: 'appearance_modification', effect };
  }
  return { ok: true };
}

/**
 * Virtual backgrounds are a genuine tension: they hide the home, which is
 * privacy — and they hide the home, which is concealment.
 *
 * SETTLED: allowed for a **guardian**, refused for a **child**. An adult may have
 * good reason not to show a room. A child's background is the one thing that
 * tells the other parent she is somewhere safe, and it is the only signal that
 * arrives without anybody choosing to send it.
 */
export function backgroundAllowed(role: 'child' | 'guardian'): boolean {
  return role === 'guardian';
}

export const BACKGROUND_NOTE =
  'A child\'s background is the only thing in a call that tells the other parent '
  + 'she is somewhere ordinary, and it arrives without anybody deciding to send it.';

// ===================================================== §5.24.3 audio out ====
export type Route = 'speaker' | 'earpiece' | 'wired' | 'bluetooth';

/**
 * Speaker by default for a child. She is not holding it to her ear — it is
 * propped on a table, or on the floor, or she has wandered off with it.
 */
export function defaultRoute(role: 'child' | 'guardian', wired: boolean, bt: boolean): Route {
  if (wired) return 'wired';
  if (bt) return 'bluetooth';
  return role === 'child' ? 'speaker' : 'earpiece';
}

/**
 * Headphones on a child's device have a meaning beyond audio: she may be at the
 * other parent's house, and headphones may be the reason she can speak freely.
 *
 * So the other party is told they are on — not to monitor her, but because the
 * adult should know whether they are audible to a room. It is stated neutrally
 * and never as a status about her.
 */
export function headphoneNote(on: boolean): string | null {
  return on ? 'She has headphones in.' : null;
}

export const HEADPHONE_NOTE_BANNED = ['private', 'alone', 'safe to', 'nobody can hear'] as const;

export function auditHeadphoneNote(text: string | null): { ok: true } | { ok: false; found: string[] } {
  if (!text) return { ok: true };
  const t = text.toLowerCase();
  const found = (HEADPHONE_NOTE_BANNED as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

/** A hearing ceiling that a child cannot raise. */
export const MAX_CHILD_VOLUME = 0.85;

export function clampVolume(v: number, role: 'child' | 'guardian'): number {
  const hi = role === 'child' ? MAX_CHILD_VOLUME : 1;
  return Math.max(0, Math.min(hi, v));
}

/**
 * Siblings on separate devices in one room feed back into each other, and the
 * group call (§12.8) makes that certain rather than possible.
 */
export interface EchoRisk { sameRoom: boolean; devices: number; advice: string | null }

export function echoRisk(devices: number, sameRoom: boolean): EchoRisk {
  return { sameRoom, devices,
    advice: sameRoom && devices > 1
      ? 'Two of you are in the same room — one of you use headphones, or share a screen.'
      : null };
}

// ===================================================== §5.24.4 PiP ==========
/**
 * THE FINDING: **picture-in-picture conflicts with the child lock.**
 *
 * PiP exists so a call survives you leaving the app. A child in kiosk mode
 * cannot leave the app — that is what the lock is for — so on her device PiP is
 * solving a problem she does not have, and implementing it would mean punching a
 * hole in the very thing that keeps her in one place.
 *
 * So PiP is **guardian-only**, and that is a structural conclusion rather than a
 * limitation. It also means what the product has been calling "picture in
 * picture" in game layouts is a *layout*, not PiP — a distinction the F-series
 * would have caught if the word had been load-bearing.
 */
export type PipKind = 'os_native' | 'in_layout' | 'none';

export interface PipPolicy {
  kind: PipKind;
  reason: string;
}

export function pipFor(role: 'child' | 'guardian', kioskLocked: boolean): PipPolicy {
  if (role === 'child') {
    return { kind: kioskLocked ? 'none' : 'in_layout',
      reason: kioskLocked
        ? 'She cannot leave the app, so there is nothing for PiP to solve — and '
        + 'enabling it would mean a hole in the lock.'
        : 'An unlocked child device gets the in-layout pane, not an OS window.' };
  }
  return { kind: 'os_native',
    reason: 'A parent takes calls while doing other things. This is the case PiP '
          + 'is actually for.' };
}

export interface PipWindow {
  corner: 'tl' | 'tr' | 'bl' | 'br';
  /** Remembered between calls. */
  remembered: true;
  tapReturns: true;
  /** Never smaller than a recognisable face. */
  minPx: number;
}

export const PIP_MIN_PX = 96;

export function pipWindow(corner: PipWindow['corner'] = 'br'): PipWindow {
  return { corner, remembered: true, tapReturns: true, minPx: PIP_MIN_PX };
}

/**
 * The in-layout pane is what §9.13's video-never-hidden rule already guarantees.
 * Naming it separately stops "PiP" doing work it has not earned.
 */
export const IN_LAYOUT_IS_NOT_PIP = true;

// ================================================ §5.24.5 screen recording ==
export function recordingDisclosure(platform: string): string | null {
  return platform === 'ios'
    ? 'Screen recording is on at the other end.'
    : platform === 'android_play'
    ? 'Something is recording the screen at the other end.'
    : null;
}

export const RECORDING_DETECTABLE_ON = ['ios', 'android_play'] as const;
export const RECORDING_PREVENTABLE = false;
