/**
 * MASTERFILE §9.12 — quiet activities.
 *
 * Three things a five-year-old will do for twenty minutes without a parent
 * present, which matters: not every minute in this product can require the other
 * house to be awake.
 *
 * All three share one rule. **Nothing here has a timer, a score, or a wrong
 * answer.** P2 forbids scoring shown to a child, and these are the features
 * where the temptation is strongest — a colouring book with a completion
 * percentage is a worksheet.
 */
import { type ActorKind, type Stroke } from '../../annotation/src/canvas.ts';

export type Side = 'A' | 'B';

// ============================================================== colouring ===
export interface Region {
  id: string;
  /** SVG path. The drawing is vector, so it scales to the Fold's main screen. */
  d: string;
  /** Paint-by-numbers hint. Present on every region, shown only in that mode. */
  suggested: string;
  /** The small numeral drawn inside the region in numbered mode. */
  number: number;
}

export interface Drawing {
  id: string;
  title: string;
  /** Child-facing description, for a pre-reader choosing from a shelf. */
  about: string;
  minAge: number;
  regions: Region[];
  /** Ordered palette for this drawing; numbers index into it. */
  swatches: { hex: string; label: string }[];
}

export type ColourMode = 'free' | 'numbered';

export interface ColouringState {
  drawingId: string;
  mode: ColourMode;
  /** regionId → hex. Absent means uncoloured. */
  filled: Record<string, string>;
  /** Every fill, in order, so undo is exact rather than inferred. */
  history: { regionId: string; hex: string; previous: string | null }[];
}

export function newColouring(d: Drawing, mode: ColourMode = 'free'): ColouringState {
  return { drawingId: d.id, mode, filled: {}, history: [] };
}

/**
 * Tap a region, it fills. That is the whole interaction, and it is the right one
 * for a five-year-old: no brush size, no pressure, no staying inside the lines.
 *
 * **In numbered mode a "wrong" colour still fills.** The number is a suggestion,
 * not a test — a child who wants a purple elephant gets a purple elephant, and
 * the product does not correct her. `matchedSuggestion` is recorded because it is
 * mildly interesting to a parent, and is never shown to her.
 */
export function fill(
  s: ColouringState, d: Drawing, regionId: string, hex: string,
): { ok: true; state: ColouringState; matchedSuggestion: boolean }
 | { ok: false; reason: 'no_such_region' | 'not_a_palette_colour' } {
  const region = d.regions.find(r => r.id === regionId);
  if (!region) return { ok: false, reason: 'no_such_region' };
  if (!d.swatches.some(sw => sw.hex.toUpperCase() === hex.toUpperCase())) {
    return { ok: false, reason: 'not_a_palette_colour' };
  }
  return { ok: true,
    matchedSuggestion: region.suggested.toUpperCase() === hex.toUpperCase(),
    state: { ...s, filled: { ...s.filled, [regionId]: hex },
      history: [...s.history, { regionId, hex, previous: s.filled[regionId] ?? null }] } };
}

/** Free and unlimited, like every other undo in this product (§9.2). */
export function undoFill(s: ColouringState): ColouringState {
  const last = s.history[s.history.length - 1];
  if (!last) return s;
  const filled = { ...s.filled };
  if (last.previous === null) delete filled[last.regionId];
  else filled[last.regionId] = last.previous;
  return { ...s, filled, history: s.history.slice(0, -1) };
}

/**
 * What she sees. Deliberately no percentage, no "12 of 30 left", no completion
 * bar — a colouring book with a progress metric is a worksheet.
 */
export interface ColouringChildView {
  title: string;
  coloured: number;
  line: string;
  /** True when every region has a colour. Stated warmly, once. */
  finished: boolean;
}

export function colouringChildView(s: ColouringState, d: Drawing): ColouringChildView {
  const n = Object.keys(s.filled).length;
  const done = n === d.regions.length;
  return { title: d.title, coloured: n, finished: done,
    line: done ? 'All finished. Shall we send it to Dad?'
      : n === 0 ? 'Pick a colour and tap a bit of the picture.'
      : 'Keep going.' };
}

/** §9.8.1 — a finished picture is preserved, like anything she made. */
export function colouringArtifact(s: ColouringState, d: Drawing):
  { title: string; preserved: true } | null {
  return Object.keys(s.filled).length === d.regions.length
    ? { title: d.title, preserved: true } : null;
}

// ========================================================= find the thing ===
/**
 * §9.12.2 — a where's-Wally, except the **parent chooses what is hidden.**
 *
 * That is the whole difference. A stock puzzle is a stock puzzle; a picture with
 * *her* dinosaur hidden in it, chosen by her father that morning, is a message.
 * It reuses §9.10.3 interests directly, so what gets hidden follows what she is
 * into now.
 */
export interface FindTarget { label: string; glyph: string }

export interface FindScene {
  id: string;
  target: FindTarget;
  /** Every item, target included. Positions are fractions of the canvas. */
  items: { id: string; glyph: string; x: number; y: number; scale: number;
           isTarget: boolean }[];
  /** How far she can zoom. A packed scene needs it. */
  maxZoom: number;
  difficulty: FindDifficulty;
}

export type FindDifficulty = 'gentle' | 'normal' | 'tricky' | 'fiendish';

/**
 * Difficulty is decoy COUNT and decoy SIMILARITY, never a timer.
 *
 * A clock turns a hunt into a test, and the child who is slower is not worse at
 * looking — she is five.
 */
export const FIND_LEVELS: Record<FindDifficulty,
  { decoys: number; similarGlyphs: number; maxZoom: number }> = {
  gentle:   { decoys: 24,  similarGlyphs: 2, maxZoom: 2 },
  normal:   { decoys: 80,  similarGlyphs: 5, maxZoom: 3 },
  tricky:   { decoys: 180, similarGlyphs: 9, maxZoom: 4 },
  fiendish: { decoys: 320, similarGlyphs: 14, maxZoom: 5 },
};

export function buildFindScene(
  id: string, target: FindTarget, decoyGlyphs: string[],
  difficulty: FindDifficulty, rand: () => number = Math.random,
): { ok: true; scene: FindScene } | { ok: false; reason: 'no_decoys' } {
  if (!decoyGlyphs.length) return { ok: false, reason: 'no_decoys' };
  const level = FIND_LEVELS[difficulty];
  const items: FindScene['items'] = [];
  const place = (glyph: string, isTarget: boolean, i: number) => {
    items.push({ id: `${id}-${i}`, glyph,
      x: 0.03 + rand() * 0.94, y: 0.03 + rand() * 0.94,
      scale: 0.7 + rand() * 0.6, isTarget });
  };
  // Similar decoys first — they are what makes it hard, rather than sheer volume.
  const similar = decoyGlyphs.slice(0, level.similarGlyphs);
  for (let i = 0; i < level.decoys; i++) {
    const pool = i < level.similarGlyphs * 4 && similar.length ? similar : decoyGlyphs;
    place(pool[Math.floor(rand() * pool.length)], false, i);
  }
  // The target goes in last, at a random index, so it is not always on top.
  const at = Math.floor(rand() * items.length);
  const t: FindScene['items'][number] = { id: `${id}-target`, glyph: target.glyph,
    x: 0.05 + rand() * 0.9, y: 0.05 + rand() * 0.9, scale: 1, isTarget: true };
  items.splice(at, 0, t);
  return { ok: true, scene: { id, target, items, maxZoom: level.maxZoom, difficulty } };
}

/**
 * A tap. A miss does nothing at all — no buzz, no shake, no counter. She simply
 * keeps looking, which is what she would do with a paper puzzle.
 */
export function tapFind(scene: FindScene, itemId: string):
  { found: boolean; nudge: string | null } {
  const item = scene.items.find(i => i.id === itemId);
  if (item?.isTarget) return { found: true, nudge: null };
  return { found: false, nudge: null };
}

/** A hint, if she asks. Quadrant only — never the answer. */
export function findHint(scene: FindScene): string {
  const t = scene.items.find(i => i.isTarget)!;
  const vert = t.y < 0.5 ? 'top' : 'bottom';
  const horiz = t.x < 0.5 ? 'left' : 'right';
  return `Try the ${vert} ${horiz}.`;
}

// ==================================================== spot the difference ===
export type SpotDifficulty = 'gentle' | 'normal' | 'tricky' | 'fiendish';

/**
 * §9.12.3 — difficulty is the NUMBER of differences and how subtle they are.
 *
 * `subtlety` is a fraction: 1.0 is an object present or absent, 0.15 is a shade
 * change of one small thing. Scaling subtlety rather than adding a countdown is
 * what makes this pleasant at five and still interesting at ten.
 */
export const SPOT_LEVELS: Record<SpotDifficulty,
  { count: number; minSubtlety: number; maxSubtlety: number }> = {
  gentle:   { count: 3, minSubtlety: 0.80, maxSubtlety: 1.00 },
  normal:   { count: 5, minSubtlety: 0.50, maxSubtlety: 0.85 },
  tricky:   { count: 7, minSubtlety: 0.30, maxSubtlety: 0.55 },
  fiendish: { count: 10, minSubtlety: 0.15, maxSubtlety: 0.35 },
};

export interface Difference {
  id: string;
  x: number; y: number; radius: number;
  /** 1.0 obvious, 0.15 barely there. */
  subtlety: number;
  kind: 'added' | 'removed' | 'moved' | 'recoloured' | 'resized';
  found: boolean;
}

export interface SpotScene {
  id: string;
  difficulty: SpotDifficulty;
  differences: Difference[];
}

export function buildSpotScene(
  id: string, difficulty: SpotDifficulty, rand: () => number = Math.random,
): SpotScene {
  const level = SPOT_LEVELS[difficulty];
  const kinds: Difference['kind'][] = ['added','removed','moved','recoloured','resized'];
  const differences: Difference[] = [];
  for (let i = 0; i < level.count; i++) {
    differences.push({ id: `${id}-d${i}`,
      x: 0.08 + rand() * 0.84, y: 0.08 + rand() * 0.84,
      // A generous tap radius. A five-year-old aims with a whole finger.
      radius: 0.09,
      subtlety: level.minSubtlety + rand() * (level.maxSubtlety - level.minSubtlety),
      kind: kinds[Math.floor(rand() * kinds.length)], found: false });
  }
  return { id, difficulty, differences };
}

export function tapSpot(
  s: SpotScene, x: number, y: number,
): { scene: SpotScene; found: Difference | null } {
  const hit = s.differences.find(d => !d.found &&
    Math.hypot(d.x - x, d.y - y) <= d.radius);
  if (!hit) return { scene: s, found: null };
  return { found: hit,
    scene: { ...s, differences: s.differences.map(d =>
      d.id === hit.id ? { ...d, found: true } : d) } };
}

export const spotRemaining = (s: SpotScene) => s.differences.filter(d => !d.found).length;
export const spotComplete = (s: SpotScene) => spotRemaining(s) === 0;

/**
 * She sees how many are left to find — which is a *goal*, not a score. The
 * distinction: a goal is the shape of the puzzle, a score compares her to
 * somebody. There is no time, no accuracy, and no record between scenes.
 */
export function spotChildView(s: SpotScene): { line: string; left: number } {
  const left = spotRemaining(s);
  return { left,
    line: left === 0 ? 'You found them all.'
      : left === 1 ? 'One more to find.'
      : `${left} more to find.` };
}

/** Escalates only when she has finished the level, and never automatically. */
export function nextDifficulty(d: SpotDifficulty): SpotDifficulty {
  const order: SpotDifficulty[] = ['gentle','normal','tricky','fiendish'];
  return order[Math.min(order.indexOf(d) + 1, order.length - 1)];
}

// ================================================================== doodle ===
/**
 * §9.12.4 — new v0.39.0. §9.12.1's colouring engine is deliberately constrained
 * — tap a region, it fills, no brush, no staying inside lines — which is right
 * for a pre-drawn picture and wrong for a child who wants to draw her own
 * thing. This is a genuinely separate mode, not a replacement: free strokes on
 * a blank canvas, plus six fixed stamps. Everything else in this section still
 * applies without exception.
 */
export type DoodleStamp = 'heart' | 'star' | 'smiley' | 'rainbow' | 'sun' | 'moon';

/** The whole stamp set. Fixed — not configurable, not extendable per drawing. */
export const DOODLE_STAMPS: DoodleStamp[] =
  ['heart', 'star', 'smiley', 'rainbow', 'sun', 'moon'];

export interface DoodleStroke {
  id: string;
  points: [number, number][];
  color: string;
  widthPx: number;
}

export interface DoodleStampMark {
  id: string;
  stamp: DoodleStamp;
  x: number;
  y: number;
  scale: number;
}

export type DoodleMark =
  | { kind: 'stroke'; stroke: DoodleStroke }
  | { kind: 'stamp'; mark: DoodleStampMark };

/**
 * `marks` is the entire state AND the entire history — every stroke and every
 * stamp is appended, never mutated, so undo is exact: pop the last one off.
 */
export interface DoodleState {
  marks: DoodleMark[];
}

export function newDoodle(): DoodleState {
  return { marks: [] };
}

/** A free stroke. No brush size limit, no staying inside lines — there are no lines. */
export function stroke(
  s: DoodleState, id: string, points: [number, number][], color: string, widthPx: number,
): { ok: true; state: DoodleState } | { ok: false; reason: 'empty' } {
  if (!points.length) return { ok: false, reason: 'empty' };
  return { ok: true,
    state: { marks: [...s.marks, { kind: 'stroke', stroke: { id, points, color, widthPx } }] } };
}

/** One of the six fixed stamps. Nothing else is a stamp. */
export function addStamp(
  s: DoodleState, id: string, stamp: DoodleStamp, x: number, y: number, scale = 1,
): { ok: true; state: DoodleState } | { ok: false; reason: 'not_a_stamp' } {
  if (!DOODLE_STAMPS.includes(stamp)) return { ok: false, reason: 'not_a_stamp' };
  return { ok: true,
    state: { marks: [...s.marks, { kind: 'stamp', mark: { id, stamp, x, y, scale } }] } };
}

/** Free and unlimited, the same exact-history pattern as everywhere else in §9.2. */
export function undoDoodle(s: DoodleState): DoodleState {
  if (!s.marks.length) return s;
  return { marks: s.marks.slice(0, -1) };
}

/**
 * A blank page has no finish line, so unlike numbered colouring there is
 * nothing for a "finished" state to mean. The child view is a standing
 * invitation — never a count, never a completion percentage.
 */
export interface DoodleChildView { line: string }

export function doodleChildView(s: DoodleState): DoodleChildView {
  return { line: s.marks.length === 0
    ? 'Draw anything you want.'
    : 'Keep going, or send it when you like.' };
}

/** §9.8.1 — preservable the moment it has anything on it at all. */
export function doodleArtifact(s: DoodleState, title = 'Her doodle'):
  { title: string; preserved: true } | null {
  return s.marks.length > 0 ? { title, preserved: true } : null;
}

/**
 * Live pairing, added v0.42.0 (§8.15). The doodle desk had no synchronous
 * counterpart — a gap the sync/async pairing audit found. Rather than build a
 * new live-drawing engine, the live form reuses the shared annotation canvas
 * (annotation/canvas.ts) outright: its per-actor undo scoping already solves
 * the one hard problem a live shared doodle would otherwise reintroduce — a
 * parent's undo must never erase the child's stroke. What follows is a naming
 * and a demo surface, not new logic.
 */
export const LIVE_DOODLE_REUSES_SHARED_CANVAS = true;

export type LiveDoodleStroke = Stroke;
export type LiveDoodleActor = ActorKind;

export const DOODLE_PAIRING = {
  async: {
    form: 'doodle desk',
    mode: 'solo',
    engine: 'activities.ts DoodleState (this file)',
    hasTimerScoreOrCompletion: false,
  },
  sync: {
    form: 'live doodle',
    mode: 'paired',
    engine: 'annotation/canvas.ts Canvas — reused outright, not reimplemented',
    undoScoping: "per-actor, via Canvas.undo — a parent cannot erase the child's stroke",
  },
} as const;

// ================================================================ the guard =
/** Nothing in these three may carry a score, a timer, or a wrong answer. */
export const ACTIVITY_FORBIDDEN = [
  'score', 'points', 'percent', 'percentComplete', 'completion', 'accuracy',
  'timeLeft', 'countdown', 'elapsed', 'seconds', 'attempts', 'misses',
  'wrong', 'incorrect', 'streak', 'rank', 'best', 'stars', 'grade',
] as const;

export function auditActivity(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((ACTIVITY_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
