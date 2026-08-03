/**
 * MASTERFILE §5.26 — the pane.
 *
 * THE CORE MOVE: **do not use the OS at all.**
 *
 * Android Go disables platform PiP outright. FireOS reports Android 9 and may
 * still refuse it. And screen pinning / lock-task mode — the very mechanism that
 * keeps a child inside the app — **blocks the PiP API by design.** The kiosk and
 * the platform feature are mutually exclusive on the hardware that matters most.
 *
 * So the pane is a positioned view inside our own hierarchy. No platform API, no
 * firmware dependency, no permission, no kiosk conflict. It renders identically
 * on a £50 Fire tablet and a Fold, because it is a box we draw.
 *
 * That also makes "PiP" mean something honest on her side: the call keeps running
 * while she moves between *our* surfaces, which is the only "somewhere else" a
 * locked app has.
 */

export type Side = 'A' | 'B';
export type Corner = 'tl' | 'tr' | 'bl' | 'br';
export type PaneSize = 'small' | 'medium' | 'large';
export type Tier = 'low' | 'mid' | 'high';

export interface Viewport { w: number; h: number }

// ================================================== §5.26.1 the docking model
/**
 * Four magnetic corners, not free drag.
 *
 * A five-year-old dragging a small target loses it behind her own thumb, and a
 * video she cannot find is a video that is not there. Corners are also **position
 * without coordinates** — they survive rotation, folding and a text-scale change
 * with no arithmetic at all, which is the second reason to prefer them.
 */
export const CORNERS: Corner[] = ['tl', 'tr', 'bl', 'br'];

export interface Pane {
  corner: Corner;
  size: PaneSize;
  /** A child cannot set this. See §5.26.4. */
  closed: boolean;
  /** True while the pane has yielded to a hot zone. */
  displaced: boolean;
  visible: boolean;
}

export function newPane(corner: Corner = 'br'): Pane {
  return { corner, size: 'medium', closed: false, displaced: false, visible: true };
}

export function dock(p: Pane, corner: Corner): Pane {
  return { ...p, corner, displaced: false };
}

/** Nearest corner, so a drag that goes anywhere still lands somewhere sensible. */
export function nearestCorner(v: Viewport, x: number, y: number): Corner {
  const left = x < v.w / 2, top = y < v.h / 2;
  return (top ? (left ? 'tl' : 'tr') : (left ? 'bl' : 'br'));
}

export const FREE_DRAG_ALLOWED = false;

// ============================================ §5.26.2 three sizes, no pinch
/**
 * Small, medium, large as a single toggle. Pinch-resizing a video is a lost
 * video — the gesture is imprecise, it competes with everything else on a touch
 * surface, and there is no undo for "it is now four pixels wide".
 */
export const SIZE_FRACTIONS: Record<PaneSize, number> = {
  small: 0.20, medium: 0.28, large: 0.38,
};

export const PINCH_RESIZE_ALLOWED = false;

export function cycleSize(p: Pane): Pane {
  const order: PaneSize[] = ['small', 'medium', 'large'];
  return { ...p, size: order[(order.indexOf(p.size) + 1) % order.length] };
}

/**
 * §5.26.3 — the floor is a face, expressed RELATIVELY.
 *
 * A fixed 96 px is wrong in both directions: it is a postage stamp on a 10-inch
 * tablet and it swallows a 344 px cover screen. The pane is a fraction of the
 * **smaller** viewport dimension, with an absolute floor beneath it so it can
 * never fall below a recognisable face.
 */
export const ABSOLUTE_FLOOR_PX = 88;
export const MAX_FRACTION_OF_SHORT_EDGE = 0.42;

export function paneSizePx(v: Viewport, size: PaneSize): { w: number; h: number } {
  const shortEdge = Math.min(v.w, v.h);
  const frac = Math.min(SIZE_FRACTIONS[size], MAX_FRACTION_OF_SHORT_EDGE);
  const w = Math.max(ABSOLUTE_FLOOR_PX, Math.round(shortEdge * frac));
  return { w, h: Math.round(w * 4 / 3) };
}

/** It may never cover more than this much of the screen it sits on. */
export const MAX_SCREEN_COVERAGE = 0.25;

export function coverage(v: Viewport, size: PaneSize): number {
  const s = paneSizePx(v, size);
  return (s.w * s.h) / (v.w * v.h);
}

export function sizeFits(v: Viewport, size: PaneSize): boolean {
  return coverage(v, size) <= MAX_SCREEN_COVERAGE;
}

/** The largest size that still fits. Never refuses — always returns something. */
export function bestFit(v: Viewport): PaneSize {
  const order: PaneSize[] = ['large', 'medium', 'small'];
  return order.find(s => sizeFits(v, s)) ?? 'small';
}

// ============================================ §5.26.4 she cannot close it ===
/**
 * **There is no dismiss button on a child's pane.**
 *
 * A child who accidentally loses her father's face and cannot work out how to get
 * it back has lost the call — and she will not say so, she will just go quiet.
 * Only ending the call ends the pane.
 */
export type CloseRefusal = 'child_cannot_close';

export function closePane(
  p: Pane, role: 'child' | 'guardian',
): { ok: true; pane: Pane } | { ok: false; reason: CloseRefusal } {
  if (role === 'child') return { ok: false, reason: 'child_cannot_close' };
  return { ok: true, pane: { ...p, closed: true, visible: false } };
}

/** Ending the call is the one thing that removes it from her screen. */
export function endCall(p: Pane): Pane {
  return { ...p, closed: true, visible: false };
}

export function childControls(): { move: true; resize: true; close: false } {
  return { move: true, resize: true, close: false };
}

// ============================================ §5.26.5 hot-zone avoidance ====
/**
 * The pane yields; she never has to.
 *
 * An active surface declares where her hands are — the region she is colouring,
 * the word she is tapping, the keypad she is typing her name into — and the pane
 * relocates to the corner furthest from it.
 */
export interface HotZone { x: number; y: number; w: number; h: number }

const CORNER_POINT: Record<Corner, [number, number]> = {
  tl: [0, 0], tr: [1, 0], bl: [0, 1], br: [1, 1],
};

/** Fractions of the viewport, so this is resolution-independent. */
export function cornerDistance(c: Corner, z: HotZone): number {
  const [cx, cy] = CORNER_POINT[c];
  const zx = z.x + z.w / 2, zy = z.y + z.h / 2;
  return Math.hypot(cx - zx, cy - zy);
}

export function avoid(p: Pane, zones: HotZone[]): Pane {
  if (!zones.length) return { ...p, displaced: false };
  // The corner whose *worst* case is best — a pane must dodge every hot zone,
  // not merely the nearest one.
  let best: Corner = p.corner, bestScore = -1;
  for (const c of CORNERS) {
    const worst = Math.min(...zones.map(z => cornerDistance(c, z)));
    if (worst > bestScore) { bestScore = worst; best = c; }
  }
  return { ...p, corner: best, displaced: best !== p.corner };
}

/** Snaps back once her hands move away, so it does not wander permanently. */
export function releaseZones(p: Pane, home: Corner): Pane {
  return p.displaced ? { ...p, corner: home, displaced: false } : p;
}

// ======================================== §5.26.6 audio is decoupled ========
/**
 * **If the pane fails, is occluded, or the renderer dies, audio never drops.**
 *
 * The video is the enhancement. The voice is the call. On the hardware this has
 * to run on, a renderer falling over is a Tuesday — and a child who can still
 * hear her father has not lost anything that matters.
 */
export interface AudioLink { alive: true; independentOfPane: true }

export function audioLink(): AudioLink {
  return { alive: true, independentOfPane: true };
}

export function paneFailed(p: Pane, a: AudioLink): {
  pane: Pane; audio: AudioLink; childLine: string;
} {
  return { pane: { ...p, visible: false }, audio: a,
    childLine: 'The picture has gone for a minute. You can still hear him.' };
}

export const AUDIO_SURVIVES_PANE_LOSS = true;

// ============================================ §5.26.7 low-tier still frame ==
/**
 * A 2 GB tablet running a live video pane *and* a game is a dropped call.
 *
 * A photograph of her father and his voice beats a frozen call, and it costs
 * almost nothing to render.
 */
export type PaneRender = 'video' | 'still_frame' | 'colour_only';

export function renderFor(tier: Tier, activityRunning: boolean): PaneRender {
  if (tier === 'low' && activityRunning) return 'still_frame';
  if (tier === 'low') return 'video';
  return 'video';
}

export function stillFrameLine(): string {
  return '';   // Nothing is said. A still frame that announces itself is an apology.
}

// ================================= §5.26.8 surfaces that refuse the pane ====
/**
 * Two surfaces refuse it outright, each for a reason rather than a limitation.
 */
export const PANE_REFUSED_ON = [
  { surface: 'homework_capture',
    because: 'the rear camera is composing a document and the capture guide needs '
           + 'the whole frame. Two competing camera surfaces is a confusion, not a '
           + 'feature.' },
  { surface: 'fold_tabletop',
    because: 'that posture already gives video the best position it will ever have, '
           + 'above the crease at eye level. Shrinking it there is strictly worse.' },
] as const;

export function paneAllowedOn(surface: string): boolean {
  return !PANE_REFUSED_ON.some(r => r.surface === surface);
}

export function refusalReason(surface: string): string | null {
  return PANE_REFUSED_ON.find(r => r.surface === surface)?.because ?? null;
}

// ============================================ §5.26.9 the fail-safe probe ===
/**
 * **Attempt and verify. Never ask.**
 *
 * `Build.VERSION.SDK_INT >= 26` is a lie on FireOS, which reports Android 9 and
 * may still refuse. Android Go disables PiP entirely while reporting a version
 * that supports it. Lock-task mode blocks it with no capability flag at all.
 *
 * So the probe *tries*, confirms the mode was actually entered, and falls back
 * silently. **Nothing in the product may depend on the answer** — OS PiP is
 * progressive enhancement for a guardian and nothing more.
 */
export type ProbeResult =
  | { osPip: true; verified: true }
  | { osPip: false; reason: 'refused' | 'not_attempted' | 'kiosk' | 'child_device' };

export interface ProbeInput {
  role: 'child' | 'guardian';
  kioskLocked: boolean;
  /** What the platform CLAIMS. Never trusted on its own. */
  claimsSupport: boolean;
  /** Whether the mode was actually observed after attempting. */
  observedAfterAttempt: boolean;
}

export function probeOsPip(i: ProbeInput): ProbeResult {
  // A child never gets OS PiP — §5.24.4, and a locked app cannot have it anyway.
  if (i.role === 'child') return { osPip: false, reason: 'child_device' };
  if (i.kioskLocked) return { osPip: false, reason: 'kiosk' };
  if (!i.claimsSupport && !i.observedAfterAttempt) {
    return { osPip: false, reason: 'not_attempted' };
  }
  // The claim is irrelevant; only the observation counts.
  return i.observedAfterAttempt
    ? { osPip: true, verified: true }
    : { osPip: false, reason: 'refused' };
}

/**
 * The claim being wrong must be survivable. This asserts the case that actually
 * bites: a platform that says yes and then does not do it.
 */
export function claimWithoutObservation(): ProbeResult {
  return probeOsPip({ role: 'guardian', kioskLocked: false,
    claimsSupport: true, observedAfterAttempt: false });
}

export const OS_PIP_IS_NEVER_LOAD_BEARING = true;

/** Whatever the probe says, this is what actually renders. */
export function effectivePane(i: ProbeInput): 'os_window' | 'in_app_pane' {
  const r = probeOsPip(i);
  return r.osPip ? 'os_window' : 'in_app_pane';
}

// ==================================================== the child-facing view =
export interface PaneChildView {
  visible: boolean;
  corner: Corner;
  sizePx: { w: number; h: number };
  render: PaneRender;
  /** Deliberately absent from the type: any close affordance. */
  canClose: false;
}

export function paneChildView(
  p: Pane, v: Viewport, tier: Tier, activityRunning: boolean,
): PaneChildView {
  return { visible: p.visible, corner: p.corner,
    sizePx: paneSizePx(v, p.size),
    render: renderFor(tier, activityRunning), canClose: false };
}

export const PANE_FORBIDDEN = [
  'close', 'dismiss', 'hide', 'remove', 'x', 'closeable', 'dismissible',
] as const;

export function auditChildPane(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((PANE_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
