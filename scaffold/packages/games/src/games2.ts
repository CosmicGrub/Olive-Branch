import { Chess } from 'chess.js';
import type { Side, Move, VoiceNote } from './games.ts';

/**
 * MASTERFILE §9.2 — the remaining titles.
 *
 * Same three mechanics as the first four: the handicap is the child's to set,
 * takebacks are free, a move may carry a voice note. What changes here is that
 * several of these games have a SETUP phase (placing ships, hiding words,
 * choosing a secret word), and setup is where the parent can hand the child an
 * advantage without it looking like charity — because hiding words she can
 * actually find is just being a good parent.
 */

export type Kind2 = 'checkers' | 'battleship' | 'wordsearch' | 'hangman' | 'chess';

// ============================================================== CHECKERS ====
export interface CheckersState {
  /** 8x8, null | {side, king}. Only dark squares used. */
  board: ({ side: Side; king: boolean } | null)[][];
  turn: Side;
  outcome: Side | 'draw' | null;
  /** Set when a multi-jump is in progress; that piece must keep jumping. */
  mustContinueFrom: [number, number] | null;
}

export function newCheckers(): CheckersState {
  const b: CheckersState['board'] = Array.from({ length: 8 }, () => Array(8).fill(null));
  for (let r = 0; r < 3; r++) for (let c = 0; c < 8; c++)
    if ((r + c) % 2 === 1) b[r][c] = { side: 'B', king: false };   // parent at top
  for (let r = 5; r < 8; r++) for (let c = 0; c < 8; c++)
    if ((r + c) % 2 === 1) b[r][c] = { side: 'A', king: false };   // child at bottom
  return { board: b, turn: 'A', outcome: null, mustContinueFrom: null };
}

const inB = (r: number, c: number) => r >= 0 && r < 8 && c >= 0 && c < 8;
const dirs = (p: { side: Side; king: boolean }) =>
  p.king ? [[-1,-1],[-1,1],[1,-1],[1,1]]
         : p.side === 'A' ? [[-1,-1],[-1,1]] : [[1,-1],[1,1]];

export interface CheckersMove { from: [number, number]; to: [number, number]; jumps: [number, number][] }

/** All legal moves. Captures are MANDATORY in standard draughts. */
export function checkersMoves(s: CheckersState, side: Side): CheckersMove[] {
  const jumps: CheckersMove[] = [], plain: CheckersMove[] = [];
  const scan = (r: number, c: number) => {
    const p = s.board[r][c]; if (!p || p.side !== side) return;
    for (const [dr, dc] of dirs(p)) {
      const mr = r + dr, mc = c + dc, jr = r + 2*dr, jc = c + 2*dc;
      if (inB(jr, jc) && s.board[mr]?.[mc] && s.board[mr][mc]!.side !== side && !s.board[jr][jc]) {
        jumps.push({ from: [r,c], to: [jr,jc], jumps: [[mr,mc]] });
      } else if (inB(mr, mc) && !s.board[mr][mc]) {
        plain.push({ from: [r,c], to: [mr,mc], jumps: [] });
      }
    }
  };
  if (s.mustContinueFrom) { scan(...s.mustContinueFrom); return jumps; }
  for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) scan(r, c);
  // Mandatory capture: if any jump exists, only jumps are legal.
  return jumps.length ? jumps : plain;
}

export function playCheckers(
  s: CheckersState, side: Side, from: [number,number], to: [number,number],
): { ok: true; state: CheckersState } | { ok: false; reason: string } {
  if (s.outcome) return { ok: false, reason: 'game_over' };
  if (side !== s.turn) return { ok: false, reason: 'not_your_turn' };
  const legal = checkersMoves(s, side).find(m =>
    m.from[0]===from[0] && m.from[1]===from[1] && m.to[0]===to[0] && m.to[1]===to[1]);
  if (!legal) {
    const anyJump = checkersMoves(s, side).some(m => m.jumps.length);
    return { ok: false, reason: anyJump ? 'must_capture' : 'illegal_move' };
  }
  const board = s.board.map(r => r.map(x => x ? { ...x } : null));
  const p = board[from[0]][from[1]]!;
  board[from[0]][from[1]] = null;
  for (const [jr, jc] of legal.jumps) board[jr][jc] = null;
  // Crowning. A piece that reaches the far rank becomes a king and its multi-
  // jump ends there — a detail hand-rolled implementations routinely miss.
  const crowned = !p.king && ((side === 'A' && to[0] === 0) || (side === 'B' && to[0] === 7));
  board[to[0]][to[1]] = { side, king: p.king || crowned };

  let mustContinue: [number,number] | null = null;
  if (legal.jumps.length && !crowned) {
    const probe = { ...s, board, mustContinueFrom: to as [number,number] };
    if (checkersMoves(probe, side).some(m => m.jumps.length)) mustContinue = to;
  }
  const next = mustContinue ? side : (side === 'A' ? 'B' : 'A');
  const state: CheckersState = { board, turn: next, outcome: null,
    mustContinueFrom: mustContinue };
  // A player with no pieces or no legal move loses.
  if (!checkersMoves(state, next).length) state.outcome = next === 'A' ? 'B' : 'A';
  return { ok: true, state };
}

export const checkersCount = (s: CheckersState, side: Side) =>
  s.board.flat().filter(p => p?.side === side).length;

// ============================================================ BATTLESHIP ====
export const FLEET = [
  { name: 'Carrier', len: 5 }, { name: 'Battleship', len: 4 },
  { name: 'Cruiser', len: 3 }, { name: 'Submarine', len: 3 },
  { name: 'Destroyer', len: 2 },
];
export const BS_SIZE = 8;

export interface Ship { name: string; cells: number[]; hits: number[] }
export interface BattleshipState {
  ships: Record<Side, Ship[]>;
  shots: Record<Side, number[]>;
  turn: Side;
  outcome: Side | null;
  phase: 'placing' | 'playing';
}

export function newBattleship(): BattleshipState {
  return { ships: { A: [], B: [] }, shots: { A: [], B: [] },
           turn: 'A', outcome: null, phase: 'placing' };
}

export function placeShip(
  s: BattleshipState, side: Side, name: string, start: number, horizontal: boolean,
): { ok: true; state: BattleshipState } | { ok: false; reason: string } {
  const spec = FLEET.find(f => f.name === name);
  if (!spec) return { ok: false, reason: 'unknown_ship' };
  if (s.ships[side].some(x => x.name === name)) return { ok: false, reason: 'already_placed' };
  const r = Math.floor(start / BS_SIZE), c = start % BS_SIZE;
  const cells: number[] = [];
  for (let i = 0; i < spec.len; i++) {
    const rr = horizontal ? r : r + i, cc = horizontal ? c + i : c;
    if (rr >= BS_SIZE || cc >= BS_SIZE) return { ok: false, reason: 'off_board' };
    cells.push(rr * BS_SIZE + cc);
  }
  const taken = new Set(s.ships[side].flatMap(x => x.cells));
  if (cells.some(x => taken.has(x))) return { ok: false, reason: 'overlaps' };
  const ships = { ...s.ships, [side]: [...s.ships[side], { name, cells, hits: [] }] };
  const ready = ships.A.length === FLEET.length && ships.B.length === FLEET.length;
  return { ok: true, state: { ...s, ships, phase: ready ? 'playing' : 'placing' } };
}

export function fire(
  s: BattleshipState, side: Side, cell: number,
): { ok: true; state: BattleshipState; hit: boolean; sunk: string | null } | { ok: false; reason: string } {
  if (s.phase !== 'playing') return { ok: false, reason: 'still_placing' };
  if (s.outcome) return { ok: false, reason: 'game_over' };
  if (side !== s.turn) return { ok: false, reason: 'not_your_turn' };
  if (s.shots[side].includes(cell)) return { ok: false, reason: 'already_fired' };
  if (cell < 0 || cell >= BS_SIZE * BS_SIZE) return { ok: false, reason: 'off_board' };

  const foe: Side = side === 'A' ? 'B' : 'A';
  const ships = { ...s.ships, [foe]: s.ships[foe].map(x => ({ ...x, hits: [...x.hits] })) };
  const target = ships[foe].find(x => x.cells.includes(cell));
  let sunk: string | null = null;
  if (target) {
    target.hits.push(cell);
    if (target.hits.length === target.cells.length) sunk = target.name;
  }
  const shots = { ...s.shots, [side]: [...s.shots[side], cell] };
  const allSunk = ships[foe].every(x => x.hits.length === x.cells.length);
  return { ok: true, hit: Boolean(target), sunk,
    state: { ...s, ships, shots, outcome: allSunk ? side : null,
             // A hit grants another shot — the rule that gives the game its rhythm.
             turn: target && !allSunk ? side : foe } };
}

// ============================================================ WORD SEARCH ===
export interface WordSearch {
  grid: string[][];
  size: number;
  /** Placed by the PARENT, and they are personal words. */
  words: { word: string; cells: number[]; found: boolean }[];
}

const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const WS_DIRS: [number, number][] = [[0,1],[1,0],[1,1],[1,-1]];

/**
 * §9.2 — word search is a poor two-player game as normally played. What makes it
 * work here is that the PARENT hides the words, and the words are personal: her
 * name, the dog, her street, the thing she is excited about this week. It
 * becomes a message disguised as a puzzle.
 */
export function buildWordSearch(
  words: string[], size = 10, rand: () => number = Math.random,
): { ok: true; puzzle: WordSearch } | { ok: false; reason: string; word?: string } {
  const clean = words.map(w => w.toUpperCase().replace(/[^A-Z]/g, '')).filter(Boolean);
  if (!clean.length) return { ok: false, reason: 'no_words' };
  const tooLong = clean.find(w => w.length > size);
  if (tooLong) return { ok: false, reason: 'word_too_long', word: tooLong };

  const grid: (string | null)[][] = Array.from({ length: size }, () => Array(size).fill(null));
  const placed: WordSearch['words'] = [];

  for (const w of clean) {
    let done = false;
    for (let attempt = 0; attempt < 400 && !done; attempt++) {
      const [dr, dc] = WS_DIRS[Math.floor(rand() * WS_DIRS.length)];
      const r0 = Math.floor(rand() * size), c0 = Math.floor(rand() * size);
      const cells: number[] = [];
      let fits = true;
      for (let i = 0; i < w.length; i++) {
        const r = r0 + dr * i, c = c0 + dc * i;
        if (r < 0 || r >= size || c < 0 || c >= size) { fits = false; break; }
        const cur = grid[r][c];
        if (cur !== null && cur !== w[i]) { fits = false; break; }
        cells.push(r * size + c);
      }
      if (!fits) continue;
      cells.forEach((cell, i) => { grid[Math.floor(cell / size)][cell % size] = w[i]; });
      placed.push({ word: w, cells, found: false });
      done = true;
    }
    if (!done) return { ok: false, reason: 'could_not_place', word: w };
  }
  const full = grid.map(row => row.map(x =>
    x ?? LETTERS[Math.floor(rand() * 26)]));
  return { ok: true, puzzle: { grid: full, size, words: placed } };
}

export function findWord(p: WordSearch, cells: number[]): { found: string | null; puzzle: WordSearch } {
  const key = [...cells].sort((a, b) => a - b).join(',');
  const hit = p.words.find(w => !w.found && [...w.cells].sort((a,b)=>a-b).join(',') === key);
  if (!hit) return { found: null, puzzle: p };
  return { found: hit.word,
    puzzle: { ...p, words: p.words.map(w => w === hit ? { ...w, found: true } : w) } };
}

export const wordSearchComplete = (p: WordSearch) => p.words.every(w => w.found);

// ================================================================ HANGMAN ===
export interface Hangman {
  /** Chosen by the parent, and personal. */
  word: string;
  guessed: string[];
  /** Generous by default; this is not a game about a child failing. */
  livesLeft: number;
  hint: string | null;
}

export const HANGMAN_LIVES = 8;

export function newHangman(word: string, hint?: string): Hangman {
  return { word: word.toUpperCase().replace(/[^A-Z]/g, ''), guessed: [],
           livesLeft: HANGMAN_LIVES, hint: hint ?? null };
}

export function guessLetter(h: Hangman, letter: string):
  { ok: true; state: Hangman; hit: boolean } | { ok: false; reason: string } {
  const L = letter.toUpperCase();
  if (!/^[A-Z]$/.test(L)) return { ok: false, reason: 'not_a_letter' };
  if (h.guessed.includes(L)) return { ok: false, reason: 'already_guessed' };
  if (hangmanOutcome(h) !== null) return { ok: false, reason: 'game_over' };
  const hit = h.word.includes(L);
  return { ok: true, hit,
    state: { ...h, guessed: [...h.guessed, L],
             livesLeft: hit ? h.livesLeft : h.livesLeft - 1 } };
}

export function hangmanMask(h: Hangman): string {
  return h.word.split('').map(c => h.guessed.includes(c) ? c : '_').join(' ');
}
export function hangmanOutcome(h: Hangman): 'won' | 'lost' | null {
  if (h.word.split('').every(c => h.guessed.includes(c))) return 'won';
  return h.livesLeft <= 0 ? 'lost' : null;
}

// ================================================================== CHESS ===
/**
 * Real rules via chess.js. Castling, en passant, promotion, stalemate,
 * threefold repetition and the fifty-move rule are a classic underestimate, and
 * a family product getting them wrong would be worse than not shipping chess.
 */
export interface ChessState { fen: string; history: string[]; outcome: string | null }

/** Handicaps the child may impose — material, which is the honest lever. */
export const CHESS_HANDICAPS = [
  { id: 'no_queen', label: 'Dad plays without his queen',
    fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1' },
  { id: 'no_rooks', label: 'Dad plays without both rooks',
    fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NBQKBN1 w KQkq - 0 1' },
  { id: 'no_queen_rooks', label: 'Dad plays without his queen and rooks',
    fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NB1KBN1 w KQkq - 0 1' },
];

export function newChess(handicapId?: string | null): ChessState {
  const h = CHESS_HANDICAPS.find(x => x.id === handicapId);
  // The child plays white and moves first; the parent gives up material.
  const c = h ? new Chess(h.fen) : new Chess();
  return { fen: c.fen(), history: [], outcome: null };
}

export function chessMove(s: ChessState, san: string):
  { ok: true; state: ChessState } | { ok: false; reason: string } {
  const c = new Chess(s.fen);
  let mv;
  try { mv = c.move(san); } catch { return { ok: false, reason: 'illegal_move' }; }
  if (!mv) return { ok: false, reason: 'illegal_move' };
  return { ok: true, state: { fen: c.fen(), history: [...s.history, mv.san],
    outcome: chessOutcome(c) } };
}

export function chessLegalMoves(s: ChessState): string[] {
  return new Chess(s.fen).moves();
}

function chessOutcome(c: Chess): string | null {
  if (c.isCheckmate()) return c.turn() === 'w' ? 'B' : 'A';
  if (c.isStalemate()) return 'draw_stalemate';
  if (c.isThreefoldRepetition()) return 'draw_repetition';
  if (c.isInsufficientMaterial()) return 'draw_material';
  if (c.isDraw()) return 'draw';
  return null;
}

/** §9.1's reasoning applied to chess: coach the PARENT, never give the move. */
export function chessCoach(s: ChessState): string {
  const c = new Chess(s.fen);
  if (c.isCheck()) return 'She is in check. Ask her which pieces can block, and whether the king has anywhere to go.';
  const moves = c.moves({ verbose: true });
  const hanging = moves.filter(m => m.captured);
  if (hanging.length) return 'Something of yours can be taken. Ask her what she can see that is undefended.';
  if (s.history.length < 6) return 'Ask her which of her pieces still cannot move, and why that matters.';
  return 'Ask her what her last move was defending, before she moves again.';
}
