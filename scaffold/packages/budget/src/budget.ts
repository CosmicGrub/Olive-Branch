/**
 * MASTERFILE §8.14 — the capability budget.
 *
 * THE GAP THIS CLOSES: the device matrix declares three performance tiers, and
 * exactly **one** thing consumed them — the call. Games, colouring, the gallery,
 * the storyteller and the pane each made independent assumptions about what the
 * hardware could do, and none of them checked.
 *
 * Concretely: a 2 GB Fire tablet running the pane, a checkers board and an
 * ambient waveform has three concurrent claims that were each individually
 * reasonable. Nothing computed the total, because there was no budget to compute
 * against.
 *
 * The budget is **binding, not advisory.** An advisory budget is the same class
 * of thing as a declaration with nothing behind it, which is exactly what the
 * F-series exists to catch.
 */

export type Tier = 'low' | 'mid' | 'high';

// ================================================== §8.14.1 what a tier has =
export interface Capacity {
  tier: Tier;
  memoryMb: number;
  /** Arbitrary units, but consistently applied. A 720p decode is 100. */
  decode: number;
  /** Independently composited surfaces the compositor will hold without tearing. */
  surfaces: number;
  cameras: number;
  sockets: number;
}

export const CAPACITY: Capacity[] = [
  { tier: 'low',  memoryMb: 180, decode: 120, surfaces: 3, cameras: 1, sockets: 1 },
  { tier: 'mid',  memoryMb: 420, decode: 300, surfaces: 5, cameras: 1, sockets: 2 },
  { tier: 'high', memoryMb: 900, decode: 700, surfaces: 8, cameras: 2, sockets: 3 },
];

export const capacityOf = (t: Tier) => CAPACITY.find(c => c.tier === t)!;

// ================================================= §8.14.2 what things cost =
export interface Cost {
  feature: string;
  memoryMb: number;
  decode: number;
  surfaces: number;
  cameras: number;
  sockets: number;
  /** Lower sheds first. The call is deliberately the highest number here. */
  priority: number;
  note: string;
}

/**
 * Priority is the resolution order made explicit. **The call is last**, always —
 * everything else in this product exists to support it.
 */
export const COSTS: Cost[] = [
  { feature: 'call_audio', memoryMb: 24, decode: 10, surfaces: 0, cameras: 0, sockets: 1,
    priority: 100, note: 'The voice IS the call. Nothing sheds this.' },
  { feature: 'call_video_720', memoryMb: 110, decode: 100, surfaces: 1, cameras: 1, sockets: 0,
    priority: 70, note: '' },
  { feature: 'call_video_360', memoryMb: 60, decode: 45, surfaces: 1, cameras: 1, sockets: 0,
    priority: 70, note: '' },
  { feature: 'call_video_180', memoryMb: 34, decode: 20, surfaces: 1, cameras: 1, sockets: 0,
    priority: 70, note: 'A recognisable face. §8.11.5.' },
  { feature: 'pane_video', memoryMb: 42, decode: 30, surfaces: 1, cameras: 0, sockets: 0,
    priority: 50, note: '' },
  { feature: 'pane_still', memoryMb: 6, decode: 0, surfaces: 1, cameras: 0, sockets: 0,
    priority: 50, note: '§5.26.7 — a photograph and his voice beats a frozen call.' },
  { feature: 'shared_canvas', memoryMb: 48, decode: 25, surfaces: 1, cameras: 0, sockets: 1,
    priority: 40, note: '' },
  { feature: 'game_board', memoryMb: 30, decode: 8, surfaces: 1, cameras: 0, sockets: 1,
    priority: 40, note: '' },
  { feature: 'colouring', memoryMb: 36, decode: 6, surfaces: 1, cameras: 0, sockets: 0,
    priority: 40, note: 'Vector. Cheap for what it is.' },
  { feature: 'find_the_thing', memoryMb: 52, decode: 14, surfaces: 1, cameras: 0, sockets: 0,
    priority: 40, note: 'A packed, zoomable scene is the heaviest activity.' },
  { feature: 'gallery', memoryMb: 46, decode: 12, surfaces: 1, cameras: 0, sockets: 0,
    priority: 30, note: '' },
  { feature: 'storyteller', memoryMb: 12, decode: 2, surfaces: 1, cameras: 0, sockets: 0,
    priority: 30, note: 'Text. Nearly free — which is why she can always have it.' },
  { feature: 'homework_camera', memoryMb: 70, decode: 40, surfaces: 1, cameras: 1, sockets: 0,
    priority: 60, note: '' },
  { feature: 'ambient_motion', memoryMb: 4, decode: 6, surfaces: 0, cameras: 0, sockets: 0,
    priority: 10, note: 'Sheds first. It is the least load-bearing thing here.' },
  { feature: 'driven_motion', memoryMb: 2, decode: 3, surfaces: 0, cameras: 0, sockets: 0,
    priority: 90, note: 'Her finger. Removing this makes the app feel broken.' },
];

export const costOf = (f: string) => COSTS.find(c => c.feature === f) ?? null;

// ==================================================== §8.14.3 the resolution
export interface Total {
  memoryMb: number; decode: number; surfaces: number; cameras: number; sockets: number;
}

export function total(features: string[]): Total {
  const t: Total = { memoryMb: 0, decode: 0, surfaces: 0, cameras: 0, sockets: 0 };
  for (const f of features) {
    const c = costOf(f); if (!c) continue;
    t.memoryMb += c.memoryMb; t.decode += c.decode; t.surfaces += c.surfaces;
    t.cameras += c.cameras; t.sockets += c.sockets;
  }
  return t;
}

export function fits(t: Total, cap: Capacity): boolean {
  return t.memoryMb <= cap.memoryMb && t.decode <= cap.decode
    && t.surfaces <= cap.surfaces && t.cameras <= cap.cameras
    && t.sockets <= cap.sockets;
}

export type Substitution = { from: string; to: string };

/**
 * Some things degrade rather than disappearing. Substitution is tried before
 * removal, because a smaller picture is better than no picture.
 */
export const SUBSTITUTIONS: Substitution[] = [
  { from: 'call_video_720', to: 'call_video_360' },
  { from: 'call_video_360', to: 'call_video_180' },
  { from: 'pane_video', to: 'pane_still' },
];

export interface Resolution {
  admitted: string[];
  dropped: string[];
  substituted: Substitution[];
  fits: boolean;
  /** In order, what the budget did and why. */
  trace: string[];
}

/**
 * The resolution order, applied until it fits:
 *   1. ambient motion
 *   2. video quality (by substitution)
 *   3. the pane, to a still frame
 *   4. concurrent activity
 *   5. video entirely
 *
 * **The call audio is never a candidate.** It has the highest priority and the
 * loop refuses to consider it, which is a stronger guarantee than merely sorting
 * it last.
 */
export const NEVER_SHED = ['call_audio'] as const;

export function resolve(requested: string[], tier: Tier): Resolution {
  const cap = capacityOf(tier);
  let live = [...requested];
  const dropped: string[] = [];
  const substituted: Substitution[] = [];
  const trace: string[] = [];

  const check = () => fits(total(live), cap);
  if (check()) {
    return { admitted: live, dropped, substituted, fits: true,
      trace: ['fits as requested'] };
  }

  // 1 & 2 — substitute before removing anything.
  for (const sub of SUBSTITUTIONS) {
    if (check()) break;
    const i = live.indexOf(sub.from);
    if (i >= 0) {
      live[i] = sub.to; substituted.push(sub);
      trace.push(`${sub.from} → ${sub.to}`);
    }
  }

  // 3, 4 & 5 — shed by priority, lowest first, never touching the audio.
  while (!check()) {
    const candidates = live
      .filter(f => !(NEVER_SHED as readonly string[]).includes(f))
      .map(f => costOf(f)!)
      .filter(Boolean)
      .sort((a, b) => a.priority - b.priority);
    if (!candidates.length) break;   // only the untouchable remains
    const shed = candidates[0].feature;
    live = live.filter(f => f !== shed);
    dropped.push(shed);
    trace.push(`dropped ${shed}`);
  }

  return { admitted: live, dropped, substituted, fits: check(), trace };
}

/**
 * Binding. A feature that does not fit is not started — it is not warned about
 * and then started anyway.
 *
 * A first version returned a bare `{ ok: true }` when the feature fitted only
 * because something else had been SUBSTITUTED — the caller was told it succeeded
 * and not that the video had dropped to 360 to make room. Admitting without
 * disclosing the cost is a quieter version of the advisory budget this module
 * exists to avoid, so the substitutions come back with the verdict.
 */
export function admit(
  feature: string, running: string[], tier: Tier,
):
  | { ok: true; substituted: Substitution[]; free: boolean }
  | { ok: false; reason: 'no_capacity'; wouldDrop: string[]; substituted: Substitution[] } {
  const r = resolve([...running, feature], tier);
  if (r.admitted.includes(feature) && !r.dropped.length) {
    return { ok: true, substituted: r.substituted, free: r.substituted.length === 0 };
  }
  return { ok: false, reason: 'no_capacity', wouldDrop: r.dropped,
    substituted: r.substituted };
}

// ============================================ §8.14.4 the combinatorial cases
/**
 * The cases that were never enumerated. Each was individually reasonable.
 */
export const SCENARIOS = [
  { name: 'call + pane + game + waveform, low tier', tier: 'low' as Tier,
    features: ['call_audio', 'call_video_720', 'pane_video', 'game_board',
      'ambient_motion', 'driven_motion'] },
  { name: 'group call + game, low tier', tier: 'low' as Tier,
    features: ['call_audio', 'call_video_360', 'call_video_360', 'game_board',
      'driven_motion'] },
  { name: 'call + homework camera, low tier', tier: 'low' as Tier,
    features: ['call_audio', 'call_video_360', 'homework_camera', 'driven_motion'] },
  { name: 'call + find-the-thing + pane, mid tier', tier: 'mid' as Tier,
    features: ['call_audio', 'call_video_720', 'find_the_thing', 'pane_video',
      'driven_motion'] },
  { name: 'everything, high tier', tier: 'high' as Tier,
    features: ['call_audio', 'call_video_720', 'pane_video', 'shared_canvas',
      'gallery', 'driven_motion', 'ambient_motion'] },
] as const;

export function runScenarios() {
  return SCENARIOS.map(s => ({ name: s.name, tier: s.tier,
    result: resolve([...s.features], s.tier) }));
}

/** In every scenario, on every tier, the voice survives. */
export function audioAlwaysSurvives(): boolean {
  return SCENARIOS.every(s =>
    resolve([...s.features], s.tier).admitted.includes('call_audio'));
}

// ==================================================== §8.14.5 module ceilings
/**
 * Nothing declared its own limits. These are the points past which a feature
 * stops being usable rather than stops working.
 */
export interface Ceiling { module: string; limit: number; unit: string; why: string }

export const CEILINGS: Ceiling[] = [
  { module: 'group_call', limit: 4, unit: 'children',
    why: 'Beyond four, the solo rotation is longer than a child will wait.' },
  { module: 'story_library', limit: 300, unit: 'stories',
    why: 'Past this a shelf stops being browsable and becomes a search problem, '
       + 'which a five-year-old cannot use.' },
  { module: 'gallery', limit: 2000, unit: 'works',
    why: 'A year-grouped gallery holds a childhood. Past this, paginate by era.' },
  { module: 'archive_export', limit: 2048, unit: 'MB per chunk',
    why: 'A single transfer larger than this fails on a poor connection and has '
       + 'to restart from nothing.' },
  { module: 'find_the_thing', limit: 320, unit: 'decoys',
    why: 'The fiendish level. More is not harder, only slower to render.' },
  { module: 'pending_asks', limit: 3, unit: 'asks',
    why: '§9.10.7 — beyond three it is a backlog of disappointment.' },
  { module: 'concurrent_motions', limit: 2, unit: 'animations',
    why: '§8.13.6 — three is a distraction.' },
];

export const ceilingOf = (m: string) => CEILINGS.find(c => c.module === m) ?? null;

export function withinCeiling(m: string, n: number): boolean {
  const c = ceilingOf(m);
  return c ? n <= c.limit : true;
}

/** Every ceiling explains itself, or it is a magic number. */
export function auditCeilings(): { ok: boolean; unexplained: string[] } {
  const unexplained = CEILINGS.filter(c => c.why.length < 30).map(c => c.module);
  return { ok: unexplained.length === 0, unexplained };
}

/** Every cost entry must justify its priority relative to the call. */
export function auditCosts(): { ok: boolean; problems: string[] } {
  const problems: string[] = [];
  const audio = costOf('call_audio')!;
  for (const c of COSTS) {
    if (c.feature === 'call_audio') continue;
    if (c.priority >= audio.priority) problems.push(`${c.feature} outranks the voice`);
  }
  if (COSTS.some(c => c.memoryMb <= 0)) problems.push('a feature declares no cost');
  return { ok: problems.length === 0, problems };
}
