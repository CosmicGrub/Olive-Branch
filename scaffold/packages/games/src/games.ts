/**
 * MASTERFILE §9.2 — the game runtime.
 *
 * §9.2 says co-op beats competitive here, and the reason is specific: a parent
 * who plays properly against a seven-year-old is running a weekly demonstration
 * that they are better. That is not a reason to skip competitive games — it is a
 * reason to build them differently. Three mechanics carry that weight:
 *
 *   HANDICAP IS SET BY THE CHILD. Not a difficulty slider. She chooses what the
 *   parent gives up. Same material effect, opposite power dynamic: she is
 *   granting a condition rather than receiving charity.
 *
 *   TAKEBACKS ARE FREE AND UNLIMITED. This is not a tournament. A physical board
 *   lets you hover a piece and change your mind; removing that makes the digital
 *   version worse than the analog one for no gain.
 *
 *   A MOVE CAN CARRY A VOICE NOTE. You cannot see someone think across a
 *   timezone. "I saw what you did there" attached to a move is the difference
 *   between a chess app and this product.
 *
 * Prohibition P2 governs the whole file: no ELO, no ranking, no win-loss record
 * shown to a child. Records are kept internally only to know when to OFFER a
 * handicap, and `childView()` is audited to prove none of it leaks.
 */

export type Side = 'A' | 'B';           // A = child, B = parent, always.
export type GameKind = 'tictactoe' | 'dotsboxes' | 'memory' | 'story';

export interface GameMeta {
  kind: GameKind;
  title: string;
  minAge: number;
  competitive: boolean;
  /** Handicaps the CHILD may impose on the parent. */
  handicaps: { id: string; label: string }[];
  blurb: string;
}

export const CATALOGUE: GameMeta[] = [
  { kind: 'tictactoe', title: 'Three in a row', minAge: 4, competitive: true,
    handicaps: [
      { id: 'no_centre', label: "Dad can't use the middle square" },
      { id: 'child_first', label: 'I always go first' },
    ],
    blurb: 'A five-year-old can genuinely win this one.' },
  { kind: 'dotsboxes', title: 'Dots and boxes', minAge: 5, competitive: true,
    handicaps: [
      { id: 'start_behind', label: 'Dad starts two boxes behind' },
      { id: 'child_first', label: 'I always go first' },
    ],
    blurb: 'Simplest rules of any deep game.' },
  { kind: 'memory', title: 'Our photos', minAge: 4, competitive: true,
    handicaps: [
      { id: 'extra_pairs', label: 'Dad needs two more pairs than me' },
    ],
    blurb: 'Made from your own photos, not stock pictures.' },
  // Co-op. No handicap, because there is nothing to be behind at.
  { kind: 'story', title: 'Make up a story', minAge: 5, competitive: false,
    handicaps: [], blurb: 'One line each. Nobody wins.' },
];

export const forAge = (age: number) => CATALOGUE.filter(g => age >= g.minAge);

// ------------------------------------------------------------------- moves --
export interface VoiceNote { artifactId: string; durationMs: number; }

export interface Move {
  side: Side;
  /** Move payload, game-specific. */
  at: number | [number, number] | string;
  /** §9.2 — a move may carry a voice note. This is the whole point. */
  voice?: VoiceNote;
  seq: number;
}

export interface GameState {
  kind: GameKind;
  id: string;
  turn: Side;
  moves: Move[];
  /** null while playing, 'draw' or a side when finished, 'done' for co-op. */
  outcome: Side | 'draw' | 'done' | null;
  handicap: string | null;
  /** Board or content, shape depends on kind. */
  board: any;
  scores: Record<Side, number>;
  /** Reachable-hours budget, §4.7 — never wall hours. */
  turnBudgetHours: number;
}

export type MoveError =
  | 'not_your_turn' | 'game_over' | 'occupied' | 'out_of_range'
  | 'handicap_forbids' | 'nothing_to_take_back' | 'empty_contribution';

type Result = { ok: true; state: GameState } | { ok: false; reason: MoveError };

export const DEFAULT_TURN_BUDGET_REACHABLE_HOURS = 8;

/**
 * §9.2 — only the child may set a handicap, and only on the parent. A parent
 * quietly handicapping themselves is charity; the child imposing a condition is
 * a different transaction, and the type refuses the first.
 */
export function setHandicap(
  g: GameState, bySide: Side, handicapId: string | null,
): { ok: true; state: GameState } | { ok: false; reason: 'child_only' | 'unknown' } {
  if (bySide !== 'A') return { ok: false, reason: 'child_only' };
  const meta = CATALOGUE.find(m => m.kind === g.kind)!;
  if (handicapId !== null && !meta.handicaps.some(h => h.id === handicapId)) {
    return { ok: false, reason: 'unknown' };
  }
  let state = { ...g, handicap: handicapId };
  if (handicapId === 'start_behind') state = { ...state, scores: { A: 2, B: 0 } };
  if (handicapId === 'child_first') state = { ...state, turn: 'A' };
  return { ok: true, state };
}

/** Shown to both. Never "Dad is worse"; always "Dad is playing the hard way". */
export function handicapBanner(g: GameState): string | null {
  if (!g.handicap) return null;
  const meta = CATALOGUE.find(m => m.kind === g.kind)!;
  const h = meta.handicaps.find(x => x.id === g.handicap);
  return h ? `Dad's playing the hard way — ${h.label.toLowerCase()}` : null;
}

// ------------------------------------------------------------- new games ----
export function newGame(kind: GameKind, id: string, seed?: any): GameState {
  const base = { kind, id, turn: 'A' as Side, moves: [], outcome: null,
    handicap: null, scores: { A: 0, B: 0 },
    turnBudgetHours: DEFAULT_TURN_BUDGET_REACHABLE_HOURS };
  if (kind === 'tictactoe') return { ...base, board: Array(9).fill(null) };
  if (kind === 'dotsboxes') {
    const n = 4;   // 4x4 dots → 3x3 boxes
    return { ...base, board: { n, h: mat(n, n - 1), v: mat(n - 1, n),
      owner: mat(n - 1, n - 1) } };
  }
  if (kind === 'memory') {
    // seed = array of photo ids; each appears twice.
    const photos: string[] = seed ?? ['dog', 'house', 'beach', 'drawing', 'cake', 'bike'];
    const deck = [...photos, ...photos];
    return { ...base, board: { deck, revealed: [] as number[],
      matched: [] as number[], owner: {} as Record<number, Side> } };
  }
  return { ...base, board: { lines: [] as { side: Side; text: string }[] } };
}
const mat = (r: number, c: number) => Array.from({ length: r }, () => Array(c).fill(null));

// -------------------------------------------------------------- play -------
export function play(g: GameState, side: Side, at: any, voice?: VoiceNote): Result {
  if (g.outcome !== null) return { ok: false, reason: 'game_over' };
  if (side !== g.turn) return { ok: false, reason: 'not_your_turn' };
  const rec = (s: GameState, keepTurn = false): Result => ({ ok: true, state: {
    ...s,
    moves: [...g.moves, { side, at, voice, seq: g.moves.length }],
    turn: keepTurn ? side : (side === 'A' ? 'B' : 'A'),
  }});

  if (g.kind === 'tictactoe') {
    const i = at as number;
    if (i < 0 || i > 8) return { ok: false, reason: 'out_of_range' };
    if (g.board[i]) return { ok: false, reason: 'occupied' };
    // The child's handicap binds the parent, and the engine enforces it rather
    // than trusting the UI to hide the square.
    if (g.handicap === 'no_centre' && side === 'B' && i === 4) {
      return { ok: false, reason: 'handicap_forbids' };
    }
    const board = [...g.board]; board[i] = side;
    return rec({ ...g, board, outcome: tttOutcome(board) });
  }

  if (g.kind === 'dotsboxes') {
    const [kind0, r, c] = at as any;
    const b = g.board;
    const grid = kind0 === 'h' ? b.h : b.v;
    if (!grid[r] || grid[r][c] === undefined) return { ok: false, reason: 'out_of_range' };
    if (grid[r][c]) return { ok: false, reason: 'occupied' };
    const nb = { ...b, h: b.h.map((x: any) => [...x]), v: b.v.map((x: any) => [...x]),
                 owner: b.owner.map((x: any) => [...x]) };
    (kind0 === 'h' ? nb.h : nb.v)[r][c] = side;
    // THE rule that makes this game deep: completing a box gives another turn,
    // so a single move can cascade into a long chain.
    const claimed = claimBoxes(nb, side);
    const scores = { ...g.scores, [side]: g.scores[side] + claimed };
    const full = nb.owner.every((row: any[]) => row.every(x => x !== null));
    const outcome = full
      ? (scores.A === scores.B ? 'draw' : scores.A > scores.B ? 'A' : 'B') : null;
    return rec({ ...g, board: nb, scores, outcome }, claimed > 0 && !full);
  }

  if (g.kind === 'memory') {
    const i = at as number;
    const b = g.board;
    if (i < 0 || i >= b.deck.length) return { ok: false, reason: 'out_of_range' };
    if (b.matched.includes(i) || b.revealed.includes(i)) {
      return { ok: false, reason: 'occupied' };
    }
    const revealed = [...b.revealed, i];
    if (revealed.length < 2) {
      return rec({ ...g, board: { ...b, revealed } }, true);   // same turn
    }
    const [x, y] = revealed;
    const hit = b.deck[x] === b.deck[y];
    const nb = hit
      ? { ...b, revealed: [], matched: [...b.matched, x, y],
          owner: { ...b.owner, [x]: side, [y]: side } }
      : { ...b, revealed: [] };
    const scores = hit ? { ...g.scores, [side]: g.scores[side] + 1 } : g.scores;
    const done = nb.matched.length === b.deck.length;
    // The child's handicap: the parent needs two more pairs to win.
    const target = g.handicap === 'extra_pairs' ? 2 : 0;
    const outcome = done
      ? (scores.A === scores.B - target ? 'draw'
        : scores.A > scores.B - target ? 'A' : 'B') : null;
    return rec({ ...g, board: nb, scores, outcome }, hit && !done);
  }

  // story — co-op, no winner, ever.
  const text = String(at).trim();
  if (!text) return { ok: false, reason: 'empty_contribution' };
  const lines = [...g.board.lines, { side, text }];
  return rec({ ...g, board: { lines },
    outcome: lines.length >= 20 ? 'done' : null });
}

function tttOutcome(b: (Side | null)[]): Side | 'draw' | null {
  const L = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
  for (const [a, c, d] of L) if (b[a] && b[a] === b[c] && b[c] === b[d]) return b[a]!;
  return b.every(x => x) ? 'draw' : null;
}

function claimBoxes(b: any, side: Side): number {
  let n = 0;
  for (let r = 0; r < b.n - 1; r++) for (let c = 0; c < b.n - 1; c++) {
    if (b.owner[r][c]) continue;
    if (b.h[r][c] && b.h[r + 1][c] && b.v[r][c] && b.v[r][c + 1]) {
      b.owner[r][c] = side; n++;
    }
  }
  return n;
}

// ---------------------------------------------------------- takebacks ------
/**
 * Free, unlimited, no penalty, either side, any time. A physical board lets you
 * hover a piece and change your mind; a digital one that refuses is worse than
 * the analog version for no gain.
 *
 * Implemented by replaying from the start rather than by inverting the last
 * move — inversion is where takeback bugs live, especially with the
 * extra-turn rules in dots-and-boxes and memory.
 */
export function takeBack(g: GameState, seed?: any): Result {
  if (!g.moves.length) return { ok: false, reason: 'nothing_to_take_back' };
  const keep = g.moves.slice(0, -1);
  let s = newGame(g.kind, g.id, seed ?? (g.kind === 'memory' ? dedupe(g.board.deck) : undefined));
  if (g.handicap) s = setHandicap(s, 'A', g.handicap).state ?? s;
  for (const m of keep) {
    const r = play(s, m.side, m.at, m.voice);
    if (r.ok) s = r.state;
  }
  return { ok: true, state: s };
}
const dedupe = (d: string[]) => [...new Set(d)];

// ------------------------------------------------------------- P2 ----------
export interface ChildGameView {
  title: string;
  yourTurn: boolean;
  handicapBanner: string | null;
  /** Present only while a game is live, and only as an in-game tally. */
  boxesEach?: { yours: number; theirs: number };
  finished: boolean;
  /** "Good game" — never "you lost". */
  closing: string | null;
}

export function childView(g: GameState): ChildGameView {
  const meta = CATALOGUE.find(m => m.kind === g.kind)!;
  return {
    title: meta.title,
    yourTurn: g.turn === 'A' && g.outcome === null,
    handicapBanner: handicapBanner(g),
    ...(meta.competitive && g.outcome === null
      ? { boxesEach: { yours: g.scores.A, theirs: g.scores.B } } : {}),
    finished: g.outcome !== null,
    // P2 — no "you lost" screen. A child does not need a product to tell her
    // she is worse at something than an adult.
    closing: g.outcome === null ? null
      : g.kind === 'story' ? 'What a story.'
      : 'Good game.',
  };
}

/** Fields that must never reach a child. Asserted in the suite. */
export const CHILD_FORBIDDEN = [
  'elo', 'rating', 'rank', 'wins', 'losses', 'record', 'streak',
  'winRate', 'win_rate', 'skill', 'level', 'leaderboard',
] as const;

export function auditChildView(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((CHILD_FORBIDDEN as readonly string[]).some(f => k.toLowerCase() === f)) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks } : { ok: true };
}

// -------------------------------------------------- the losing streak ------
/**
 * A parent who always wins is a harm the product created, so the handicap
 * prompt SURFACES ITSELF rather than waiting to be found.
 *
 * The record exists only to decide when to offer. It is never rendered, never
 * returned by `childView()`, and the offer is phrased as the child choosing a
 * condition — not as the product noticing she keeps losing.
 */
export const STREAK_BEFORE_OFFER = 3;

export function shouldOfferHandicap(
  recentOutcomes: (Side | 'draw' | 'done' | null)[], kind: GameKind,
): boolean {
  const meta = CATALOGUE.find(m => m.kind === kind);
  if (!meta?.competitive) return false;
  const last = recentOutcomes.filter(o => o === 'A' || o === 'B').slice(-STREAK_BEFORE_OFFER);
  return last.length === STREAK_BEFORE_OFFER && last.every(o => o === 'B');
}

export function handicapOffer(kind: GameKind): { prompt: string; options: { id: string; label: string }[] } {
  const meta = CATALOGUE.find(m => m.kind === kind)!;
  return {
    // Her choice, her framing. Not "you keep losing".
    prompt: 'Want to make it harder for Dad?',
    options: meta.handicaps,
  };
}

/** §4.7 — turn clocks tick in reachable hours, never wall hours. */
export function turnExpired(g: GameState, reachableHoursElapsed: number): boolean {
  return reachableHoursElapsed >= g.turnBudgetHours;
}

/** §9.8 — a finished story is worth keeping. */
export function storyArtifact(g: GameState): { title: string; body: string } | null {
  if (g.kind !== 'story' || !g.board.lines.length) return null;
  return { title: 'A story we made up',
           body: g.board.lines.map((l: any) => l.text).join(' ') };
}
