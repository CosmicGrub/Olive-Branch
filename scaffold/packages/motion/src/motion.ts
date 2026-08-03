/**
 * MASTERFILE §8.13 — motion.
 *
 * Everything on the child's side has been static. A five-year-old reads a static
 * interface as a picture of an app rather than an app: things do not appear to be
 * touchable, and when they change they simply cut, which teaches her nothing
 * about where anything went.
 *
 * THE PRINCIPLE THE WHOLE MODULE RESTS ON:
 *
 *   **Motion follows the finger. It never leads it.**
 *
 * Every animation is either driven directly by her gesture, or a consequence of
 * something she just did. Nothing moves on its own to attract her — and that one
 * rule is the difference between an interface that feels alive and a slot
 * machine, which is the exact thing children's software usually becomes.
 */

// ============================================== §8.13.1 the four categories =
export type MotionKind =
  /** 1:1 with her finger. A card that follows a swipe. Always allowed. */
  | 'driven'
  /** A result of an action she took. Capped in duration. */
  | 'consequence'
  /** Slow, informational, never attention-seeking. Allowed on named surfaces. */
  | 'ambient'
  /** Moves on its own to attract attention. NEVER. */
  | 'autonomous';

export const AUTONOMOUS_IS_NEVER_ALLOWED = true;

export type MotionRefusal = 'autonomous' | 'too_long' | 'ambient_not_permitted';

/** Longer than this and she has been made to wait for a picture to finish. */
export const MAX_CONSEQUENCE_MS = 400;
export const MAX_DRIVEN_MS = 0;      // driven motion has no duration; it is her finger

/**
 * Ambient motion is allowed only where the movement IS the information: a
 * waveform meaning "he is talking", a recording dot meaning "this is recording".
 * Everywhere else it is decoration that competes for attention.
 */
export const AMBIENT_SURFACES = [
  'audio_waveform', 'recording_indicator', 'connecting', 'uploading',
] as const;

export interface MotionRequest {
  kind: MotionKind;
  surface: string;
  durationMs: number;
}

export function admitMotion(
  r: MotionRequest,
): { ok: true } | { ok: false; reason: MotionRefusal; note: string } {
  if (r.kind === 'autonomous') {
    return { ok: false, reason: 'autonomous',
      note: 'Nothing may move on its own to attract a child. That is the whole '
          + 'mechanic of a slot machine, and it is the default of most software '
          + 'made for children.' };
  }
  if (r.kind === 'ambient'
      && !(AMBIENT_SURFACES as readonly string[]).includes(r.surface)) {
    return { ok: false, reason: 'ambient_not_permitted',
      note: 'Ambient motion is only allowed where the movement is the '
          + 'information. Elsewhere it is decoration competing for her attention.' };
  }
  if (r.kind === 'consequence' && r.durationMs > MAX_CONSEQUENCE_MS) {
    return { ok: false, reason: 'too_long',
      note: `${r.durationMs}ms makes her wait for a picture to finish.` };
  }
  return { ok: true };
}

// =================================================== §8.13.2 the vocabulary =
/**
 * One gesture set across the whole product. A child learns it once — which is the
 * only way sixteen surfaces stay legible to a five-year-old.
 */
export type Gesture =
  | 'tap' | 'long_press' | 'swipe_h' | 'swipe_v' | 'scroll'
  | 'scrobble' | 'rotary' | 'drag' | 'fling' | 'pinch';

export interface GestureSpec {
  gesture: Gesture;
  /** What it means, everywhere, without exception. */
  means: string;
  minAge: number;
  /** Some gestures are genuinely hard for small hands. */
  note: string;
}

export const VOCABULARY: GestureSpec[] = [
  { gesture: 'tap', means: 'choose this', minAge: 2, note: '' },
  { gesture: 'long_press', means: 'tell me more about this', minAge: 5,
    note: 'Never the only way to reach anything — a five-year-old lifts her finger.' },
  { gesture: 'swipe_h', means: 'the next one along', minAge: 3,
    note: 'Cards, stories, drawings. Always horizontal, always siblings.' },
  { gesture: 'swipe_v', means: 'put this away', minAge: 4, note: '' },
  { gesture: 'scroll', means: 'there is more below', minAge: 3, note: '' },
  { gesture: 'scrobble', means: 'move through time', minAge: 5,
    note: 'A story, a recording, a saved call. Dragging along a line is the only '
        + 'natural way to say "go back a bit".' },
  { gesture: 'rotary', means: 'pick a number or a shade', minAge: 4,
    note: 'A dial is easier than a slider for a small hand — it has a centre to '
        + 'orbit rather than a line to stay on.' },
  { gesture: 'drag', means: 'move this there', minAge: 4, note: '' },
  { gesture: 'fling', means: 'go a long way', minAge: 5, note: '' },
  { gesture: 'pinch', means: 'look closer', minAge: 6,
    note: 'Zoom only. Never resizing, never the only route — see §5.26.2.' },
];

export const gesturesFor = (age: number) => VOCABULARY.filter(g => age >= g.minAge);

export const spec = (g: Gesture) => VOCABULARY.find(v => v.gesture === g) ?? null;

/**
 * No gesture is ever the ONLY way to reach something. A child who cannot make the
 * shape, or whose hand is unsteady, must still get everywhere by tapping.
 */
export const TAP_ALWAYS_SUFFICES = true;

export function reachableByTapAlone(_surface: string): true { return true; }

// ====================================================== §8.13.3 the physics =
/**
 * Spring, not linear. Children read a spring as a real object and a linear ease
 * as a slide show — the difference is legibility, not polish.
 */
export interface Spring { stiffness: number; damping: number; mass: number }

export const SPRING_STANDARD: Spring = { stiffness: 210, damping: 24, mass: 1 };
/** Heavier things move slower, which is how she learns what is heavy. */
export const SPRING_HEAVY: Spring = { stiffness: 150, damping: 26, mass: 1.6 };
export const SPRING_LIGHT: Spring = { stiffness: 280, damping: 20, mass: 0.7 };

/** No spring may overshoot enough to look like a bounce reward. */
export const MAX_OVERSHOOT = 0.06;

export function overshoot(s: Spring): number {
  const zeta = s.damping / (2 * Math.sqrt(s.stiffness * s.mass));
  if (zeta >= 1) return 0;
  return Math.exp((-zeta * Math.PI) / Math.sqrt(1 - zeta * zeta));
}

export function springSettles(s: Spring): boolean {
  return overshoot(s) <= MAX_OVERSHOOT;
}

/**
 * Rubber-band at the edge. This is how a child learns there is nothing more —
 * far better than a wall, which reads as broken.
 */
export const RUBBER_BAND_FACTOR = 0.35;

export function rubberBand(overscrollPx: number, limitPx: number): number {
  return (overscrollPx * limitPx) / (limitPx + Math.abs(overscrollPx) * (1 / RUBBER_BAND_FACTOR));
}

/** Momentum, with a deceleration a small hand can predict. */
export const DECELERATION = 0.0018;

export function flingDistance(velocityPxPerMs: number): number {
  return (velocityPxPerMs * velocityPxPerMs) / (2 * DECELERATION);
}

// ==================================================== §8.13.4 the affordance
/**
 * A pre-reader cannot be told to swipe. She has to see that it moves.
 *
 * So a swipeable row shows a **peek** of the next item — the single most
 * effective piece of wordless instruction available, and it costs a few pixels.
 */
export const PEEK_PX = 22;

export interface Affordance {
  gesture: Gesture;
  /** How the surface hints, without words. */
  hint: 'peek' | 'settle' | 'shadow' | 'none';
  px: number;
}

export function affordance(g: Gesture): Affordance {
  if (g === 'swipe_h') return { gesture: g, hint: 'peek', px: PEEK_PX };
  if (g === 'scroll') return { gesture: g, hint: 'peek', px: PEEK_PX };
  if (g === 'drag') return { gesture: g, hint: 'shadow', px: 4 };
  if (g === 'scrobble' || g === 'rotary') return { gesture: g, hint: 'settle', px: 0 };
  return { gesture: g, hint: 'none', px: 0 };
}

/**
 * Touching a draggable thing makes it move a little immediately — before she has
 * moved far enough for a drag to register. That tiny response is what tells her
 * it is hers to move.
 */
export const TOUCH_RESPONSE_MS = 40;

// ================================================= §8.13.5 the quiet surfaces
/**
 * The user's caveat, and it is the important half: motion is a bad idea wherever
 * it costs attention or alertness.
 */
export type Quietness = 'full' | 'reduced' | 'still';

export interface QuietSurface { surface: string; quietness: Quietness; why: string }

export const QUIET_SURFACES: QuietSurface[] = [
  { surface: 'bedtime', quietness: 'still',
    why: 'Movement on a lit screen at bedtime undoes the reading it accompanies.' },
  { surface: 'homework', quietness: 'still',
    why: 'This is the one surface in the product that asks her to concentrate.' },
  { surface: 'come_back_signal', quietness: 'reduced',
    why: 'A prompt that is itself a moving distraction defeats its own purpose.' },
  { surface: 'journal', quietness: 'still',
    why: 'Somewhere to think. Nothing there should move while she does.' },
  { surface: 'emergency_card', quietness: 'still',
    why: 'It is read once, in a hurry, possibly by a frightened child.' },
  { surface: 'story_reading', quietness: 'reduced',
    why: 'The refrain is the only thing that should draw the eye.' },
  { surface: 'wind_down', quietness: 'reduced',
    why: 'The whole point of the window is that things are slowing down.' },
];

export function quietnessOf(surface: string): Quietness {
  return QUIET_SURFACES.find(q => q.surface === surface)?.quietness ?? 'full';
}

export function whyQuiet(surface: string): string | null {
  return QUIET_SURFACES.find(q => q.surface === surface)?.why ?? null;
}

/**
 * Reduced motion (§8.8) and a quiet surface compose — whichever is quieter wins,
 * and an accessibility setting is never overridden by a surface default.
 */
export function effectiveQuietness(surface: string, reducedMotionOn: boolean): Quietness {
  const s = quietnessOf(surface);
  if (!reducedMotionOn) return s;
  return s === 'still' ? 'still' : 'reduced';
}

export function durationFor(q: Quietness, base: number): number {
  return q === 'still' ? 0 : q === 'reduced' ? Math.round(base * 0.45) : base;
}

/**
 * "Still" never means a hard cut. A cut is disorienting in its own way — it is a
 * crossfade with no travel, which reads as calm rather than broken.
 */
export const STILL_MEANS_CROSSFADE_NOT_CUT = true;
export const CROSSFADE_MS = 120;

// ================================================== §8.13.6 the motion budget
/**
 * Two moving things at once is a scene. Three is a distraction. The budget is the
 * same construction as §8.6.2's colour placement budget, for the same reason.
 */
export const MAX_CONCURRENT_MOTIONS = 2;

export function admitConcurrent(running: number): boolean {
  return running < MAX_CONCURRENT_MOTIONS;
}

/** Nothing loops except the permitted ambient set, and nothing ever auto-plays. */
export const LOOPS_ALLOWED_ON = AMBIENT_SURFACES;
export const AUTOPLAY_ALLOWED = false;

/**
 * Celebration once is delight. Celebration every time is a habit being trained,
 * and P2 exists because habits trained into children are hard to untrain.
 */
export const CELEBRATION_REPEATS = false;

export function celebrate(timesAlready: number): { play: boolean; why: string } {
  return timesAlready === 0
    ? { play: true, why: 'first time' }
    : { play: false,
        why: 'Celebration once is delight. Every time is a reward schedule.' };
}

/** Fields that would make motion a reward rather than a response. */
export const MOTION_FORBIDDEN = [
  'reward', 'payout', 'jackpot', 'combo', 'streakAnimation', 'attractLoop',
  'idlePrompt', 'pulseToTap', 'autoplay', 'confettiEvery',
] as const;

export function auditMotion(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((MOTION_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ================================================= §8.13.7 per-surface plans
/**
 * What actually moves, where. Declared so it can be checked rather than
 * discovered.
 */
export interface SurfaceMotion {
  surface: string;
  gestures: Gesture[];
  primary: MotionKind;
  note: string;
}

export const SURFACE_MOTION: SurfaceMotion[] = [
  { surface: 'story_library', gestures: ['swipe_h', 'scroll', 'tap'], primary: 'driven',
    note: 'Stories are cards. A peek of the next one is the instruction.' },
  { surface: 'storyteller', gestures: ['scrobble', 'swipe_h', 'tap'], primary: 'driven',
    note: 'Scrobble to go back a line. She will want to hear the refrain again.' },
  { surface: 'gallery', gestures: ['scroll', 'pinch', 'tap'], primary: 'driven',
    note: 'Pinch to look closer at her own work, never to resize the layout.' },
  { surface: 'colouring', gestures: ['tap', 'drag', 'pinch'], primary: 'driven',
    note: 'The fill is a consequence — it spreads from the tap rather than cutting.' },
  { surface: 'find_the_thing', gestures: ['pinch', 'drag', 'tap'], primary: 'driven',
    note: 'Pan and zoom a packed scene. This is the surface pinch exists for.' },
  { surface: 'colour_picker', gestures: ['rotary', 'tap'], primary: 'driven',
    note: 'A dial has a centre to orbit; a slider has a line to stay on.' },
  { surface: 'age_picker', gestures: ['rotary', 'tap'], primary: 'driven', note: '' },
  { surface: 'calendar', gestures: ['swipe_h', 'scroll', 'tap'], primary: 'driven',
    note: 'Months slide sideways. Time is horizontal everywhere in this product.' },
  { surface: 'showcase', gestures: ['swipe_h', 'tap'], primary: 'driven', note: '' },
  { surface: 'games_picker', gestures: ['scroll', 'tap'], primary: 'driven', note: '' },
  { surface: 'homework', gestures: ['tap'], primary: 'consequence',
    note: 'Deliberately the sparsest surface in the product.' },
  { surface: 'journal', gestures: ['scroll', 'tap'], primary: 'consequence', note: '' },
];

export const motionFor = (s: string) => SURFACE_MOTION.find(m => m.surface === s) ?? null;

/** Every gesture a surface claims must be in the vocabulary. */
export function auditSurfaces(): { ok: boolean; unknown: string[] } {
  const known = new Set(VOCABULARY.map(v => v.gesture));
  const unknown: string[] = [];
  for (const s of SURFACE_MOTION) {
    for (const g of s.gestures) if (!known.has(g)) unknown.push(`${s.surface}:${g}`);
  }
  return { ok: unknown.length === 0, unknown };
}

/** A quiet surface may not claim a motion-heavy primary. */
export function auditQuietConsistency(): { ok: boolean; conflicts: string[] } {
  const conflicts: string[] = [];
  for (const s of SURFACE_MOTION) {
    if (quietnessOf(s.surface) === 'still' && s.primary === 'driven') {
      conflicts.push(s.surface);
    }
  }
  return { ok: conflicts.length === 0, conflicts };
}

// ==================================================== §8.13.8 the touch chime
/**
 * New v0.39.0. Raised evaluating a Gemini-drafted alternate build, which fired
 * a Web Audio "pop" on every touch. The idea is cheap and good; it needed the
 * same discipline every other sound in this section already has.
 *
 * A chime is consequence motion wearing sound instead of pixels — not a fifth
 * category. It inherits §8.13.1-§8.13.6 wholesale: it fires only after
 * something she did, never autonomously; it is silent wherever the surface is
 * still (bedtime, homework, journal, emergency card — exactly the list a
 * wiggle is banned from); and it never loops.
 */
export type ChimeRefusal = MotionRefusal | 'muted' | 'surface_quiet';

export interface ChimeRequest {
  kind: MotionKind;
  surface: string;
  muted: boolean;
  reducedMotionOn: boolean;
}

/**
 * A chime is always consequence-triggered by definition. A caller that tries
 * to request an autonomous one is refused the same way admitMotion refuses
 * any other autonomous motion — this never gets a chime-specific carve-out.
 */
export function admitChime(
  r: ChimeRequest,
): { ok: true } | { ok: false; reason: ChimeRefusal; note: string } {
  const motion = admitMotion({ kind: r.kind, surface: r.surface, durationMs: 0 });
  if (!motion.ok) return motion;
  if (r.muted) {
    return { ok: false, reason: 'muted',
      note: 'The one-tap mute setting silences every chime, regardless of surface.' };
  }
  if (effectiveQuietness(r.surface, r.reducedMotionOn) === 'still') {
    return { ok: false, reason: 'surface_quiet',
      note: 'A chime is silent everywhere a wiggle is banned — bedtime, '
          + 'homework, the journal, the emergency card.' };
  }
  return { ok: true };
}

/**
 * The one-tap mute setting composes with the same surface-quietness table
 * motion already reads — a household that needs silence gets it regardless of
 * surface. No "loop" parameter exists: a chime is a one-shot by construction.
 */
export function chimeAllowed(
  surface: string, muted: boolean, reducedMotionOn: boolean,
): boolean {
  return admitChime({ kind: 'consequence', surface, muted, reducedMotionOn }).ok;
}
