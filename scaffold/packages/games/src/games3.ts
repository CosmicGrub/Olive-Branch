/**
 * MASTERFILE §9.2, §9.8 — sequence, observation, and the one that gets her out
 * of the chair.
 *
 * All three share a property the first nine did not: the PARENT is the content.
 * Classic Simon is a machine testing a child against a high score, which
 * collides with P2 head-on. The campfire version — "I went to the market and
 * bought a banana" — is cooperative, has a perfect one-step-per-turn async
 * cadence, and when the steps are recordings of his voice, the memory game is
 * built out of the parent. That is the product thesis compressed into one
 * mechanic.
 */

export type Side = 'A' | 'B';   // A = child, B = parent

// ================================================================== SIMON ===
export interface ChainStep {
  side: Side;
  /** Label shown/spoken. In the product this is a recording. */
  label: string;
  /** media_artifact id of the parent's voice, when present. */
  voiceArtifactId?: string;
}

export interface ChainGame {
  steps: ChainStep[];
  turn: Side;
  /** 'building' while adding, 'recalling' while repeating it back. */
  phase: 'building' | 'recalling';
  /** How far through the recall the current player has got. */
  recallIndex: number;
  /** Set when the chain is dropped. Cooperative: it ends, nobody loses. */
  ended: { atStep: number; by: Side } | null;
}

export function newChain(): ChainGame {
  return { steps: [], turn: 'B', phase: 'building', recallIndex: 0, ended: null };
}

export type ChainError =
  | 'not_your_turn' | 'game_over' | 'wrong_phase' | 'empty_step';

/**
 * Add a step. The chain is built one item per turn, which is exactly a day
 * apart — the cadence the async model wants.
 */
export function addStep(
  g: ChainGame, side: Side, label: string, voiceArtifactId?: string,
): { ok: true; state: ChainGame } | { ok: false; reason: ChainError } {
  if (g.ended) return { ok: false, reason: 'game_over' };
  if (side !== g.turn) return { ok: false, reason: 'not_your_turn' };
  if (g.phase !== 'building') return { ok: false, reason: 'wrong_phase' };
  if (!label.trim()) return { ok: false, reason: 'empty_step' };
  return { ok: true, state: {
    ...g,
    steps: [...g.steps, { side, label: label.trim(), voiceArtifactId }],
    turn: side === 'A' ? 'B' : 'A',
    phase: 'recalling', recallIndex: 0,
  }};
}

/**
 * Repeat the chain back, one step at a time.
 *
 * A wrong step ends the game COOPERATIVELY. There is no "you failed" — the
 * chain simply stops, and what is recorded is how far the two of them got
 * together. `ended.by` exists for the transcript, never for a scoreboard.
 */
export function recallStep(
  g: ChainGame, side: Side, label: string,
): { ok: true; state: ChainGame; correct: boolean } | { ok: false; reason: ChainError } {
  if (g.ended) return { ok: false, reason: 'game_over' };
  if (side !== g.turn) return { ok: false, reason: 'not_your_turn' };
  if (g.phase !== 'recalling') return { ok: false, reason: 'wrong_phase' };

  const want = g.steps[g.recallIndex];
  if (!want || want.label.toLowerCase() !== label.trim().toLowerCase()) {
    return { ok: true, correct: false,
      state: { ...g, ended: { atStep: g.recallIndex, by: side } } };
  }
  const next = g.recallIndex + 1;
  if (next < g.steps.length) {
    return { ok: true, correct: true, state: { ...g, recallIndex: next } };
  }
  // Whole chain repeated — now this player adds one.
  return { ok: true, correct: true,
    state: { ...g, phase: 'building', recallIndex: 0 } };
}

/** What the child sees. Cooperative language throughout. */
export function chainView(g: ChainGame): {
  length: number; whoseTurn: Side; phase: string;
  prompt: string; visibleSteps: string[]; closing: string | null;
} {
  return {
    length: g.steps.length,
    whoseTurn: g.turn,
    phase: g.phase,
    prompt: g.ended ? 'The chain stopped there.'
      : g.phase === 'building' ? 'Add one more thing.'
      : `Say them back — ${g.recallIndex + 1} of ${g.steps.length}.`,
    // During recall the list is hidden; that IS the game.
    visibleSteps: g.phase === 'building' || g.ended
      ? g.steps.map(s => s.label) : [],
    closing: g.ended
      // Shared, never comparative. "You got to eleven" — not who dropped it.
      ? `You two got to ${g.ended.atStep} together.` : null,
  };
}

/** §9.8 — a long chain is worth keeping. */
export function chainArtifact(g: ChainGame): { title: string; body: string } | null {
  if (g.steps.length < 5) return null;
  return { title: `A chain of ${g.steps.length}`,
           body: g.steps.map(s => s.label).join(', ') };
}

// ============================================================== KIM'S GAME ==
export interface KimRound {
  /** Objects the parent photographed on a real table. */
  objects: string[];
  /** Seconds the child may look. Generous — this is not a reflex test. */
  lookSeconds: number;
  /** Index removed for the second photo. */
  removedIndex: number;
  guess: number | null;
  revealed: boolean;
}

export const KIM_LOOK_SECONDS = 20;

/**
 * §9.2 — the best of the memory family and nobody builds it. Dad photographs
 * his kitchen table, removes one thing, photographs it again. Real photos, real
 * rooms, no art assets — and it quietly teaches her what his house looks like,
 * which matters more than the game.
 */
export function newKim(
  objects: string[], rand: () => number = Math.random,
): { ok: true; round: KimRound } | { ok: false; reason: 'too_few' } {
  // Below five it is not a memory test, it is a spot-the-obvious.
  if (objects.length < 5) return { ok: false, reason: 'too_few' };
  return { ok: true, round: {
    objects: [...objects],
    lookSeconds: KIM_LOOK_SECONDS,
    removedIndex: Math.floor(rand() * objects.length),
    guess: null, revealed: false,
  }};
}

/** The second photo: everything except the removed object. */
export function kimSecondPhoto(r: KimRound): string[] {
  return r.objects.filter((_, i) => i !== r.removedIndex);
}

export function kimGuess(
  r: KimRound, index: number,
): { ok: true; round: KimRound; correct: boolean } | { ok: false; reason: string } {
  if (r.revealed) return { ok: false, reason: 'already_answered' };
  if (index < 0 || index >= r.objects.length) return { ok: false, reason: 'out_of_range' };
  const correct = index === r.removedIndex;
  return { ok: true, correct, round: { ...r, guess: index, revealed: true } };
}

export function kimClosing(r: KimRound): string | null {
  if (!r.revealed) return null;
  // Getting it wrong is not a failure state. She still looked at his kitchen.
  return r.guess === r.removedIndex
    ? `Yes — the ${r.objects[r.removedIndex]}.`
    : `It was the ${r.objects[r.removedIndex]}. Tricky one.`;
}

// =========================================================== SCAVENGER HUNT =
export interface HuntPrompt {
  id: string;
  /** Written by the parent. The good ones are personal. */
  text: string;
  /** media_artifact id once she photographs it. */
  artifactId: string | null;
  foundAt: string | null;
}

export interface Hunt {
  id: string;
  setBy: Side;
  prompts: HuntPrompt[];
  /** Deliberately absent: any timer. See below. */
  createdAt: string;
}

export const SUGGESTED_PROMPTS = [
  'Something round',
  'Something blue',
  'Something that was mine when I was your age',
  'The oldest thing in the house',
  'Something that makes a noise',
  'Something you made',
  'Somewhere you like to sit',
];

/**
 * §9.2, §9.8 — the only game on any list that gets her OFF the screen and
 * around her house. For a product whose thesis is presence rather than
 * engagement, that is not a minor point.
 *
 * There is no timer and no scoring. A hunt is finished when it is finished; a
 * countdown would turn wandering around the house into a test.
 */
export function newHunt(
  id: string, prompts: string[], setBy: Side, at: string,
): { ok: true; hunt: Hunt } | { ok: false; reason: 'no_prompts' | 'too_many' } {
  const clean = prompts.map(p => p.trim()).filter(Boolean);
  if (!clean.length) return { ok: false, reason: 'no_prompts' };
  // More than eight stops being a game and becomes a chore.
  if (clean.length > 8) return { ok: false, reason: 'too_many' };
  return { ok: true, hunt: {
    id, setBy, createdAt: at,
    prompts: clean.map((text, i) => ({ id: `${id}-${i}`, text,
      artifactId: null, foundAt: null })),
  }};
}

export function submitFind(
  h: Hunt, promptId: string, artifactId: string, at: string,
): { ok: true; hunt: Hunt } | { ok: false; reason: 'unknown_prompt' | 'already_found' } {
  const p = h.prompts.find(x => x.id === promptId);
  if (!p) return { ok: false, reason: 'unknown_prompt' };
  if (p.artifactId) return { ok: false, reason: 'already_found' };
  return { ok: true, hunt: { ...h, prompts: h.prompts.map(x =>
    x.id === promptId ? { ...x, artifactId, foundAt: at } : x) }};
}

export const huntProgress = (h: Hunt) => ({
  found: h.prompts.filter(p => p.artifactId).length,
  total: h.prompts.length,
});

export const huntComplete = (h: Hunt) => h.prompts.every(p => p.artifactId);

/**
 * §9.8.1 — everything she photographs on a hunt is preserved by default.
 *
 * A photograph of the oldest thing in her mother's house, taken because her
 * father asked, is exactly the material the Year Book and the majority handover
 * exist for. Putting it on a 90-day retention clock would be a mistake we could
 * not undo later.
 */
export function huntArtifacts(h: Hunt): {
  artifactId: string; caption: string; preserved: true;
}[] {
  return h.prompts.filter(p => p.artifactId).map(p => ({
    artifactId: p.artifactId!, caption: p.text, preserved: true as const,
  }));
}

/** Fields that must never appear in any of these three. Asserted. */
export const NO_SCORE_KEYS = [
  'score', 'highScore', 'high_score', 'best', 'record', 'streak', 'rank',
  'timeLeft', 'time_left', 'countdown', 'seconds', 'elapsed', 'wpm',
] as const;

export function auditNoScore(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((NO_SCORE_KEYS as readonly string[]).some(f => k.toLowerCase() === f.toLowerCase())) {
        leaks.push(k);
      }
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
