import { DateTime } from 'luxon';

/**
 * MASTERFILE §9.2 games · §8.4 accessibility · §8.4/§10.8 SMS bridge.
 */

// ========================================================== turn-based games =
export type Cell = 'A' | 'B' | null;
export interface GameState {
  id: string;
  /** 7x6 connect-four, column-major. Co-op is preferred (§9.2) but a simple
   *  turn-based game is the cheapest way to prove the RUNTIME. */
  board: Cell[][];
  turn: 'A' | 'B';
  winner: Cell | 'draw';
  /** Reachable-hours remaining, NOT wall hours. See §4.7. */
  turnBudgetHours: number;
  turnStartedAt: string;
}

export const COLS = 7, ROWS = 6;
export const DEFAULT_TURN_BUDGET_REACHABLE_HOURS = 8;

export function newGame(id: string, at: DateTime): GameState {
  return {
    id,
    board: Array.from({ length: COLS }, () => Array<Cell>(ROWS).fill(null)),
    turn: 'A', winner: null,
    turnBudgetHours: DEFAULT_TURN_BUDGET_REACHABLE_HOURS,
    turnStartedAt: at.toISO()!,
  };
}

export type MoveError = 'not_your_turn' | 'column_full' | 'out_of_range' | 'game_over';

export function drop(
  g: GameState, side: 'A' | 'B', col: number, at: DateTime,
): { ok: true; state: GameState } | { ok: false; reason: MoveError } {
  if (g.winner !== null) return { ok: false, reason: 'game_over' };
  if (side !== g.turn) return { ok: false, reason: 'not_your_turn' };
  if (col < 0 || col >= COLS) return { ok: false, reason: 'out_of_range' };
  const column = g.board[col];
  const row = column.findIndex(c => c === null);
  if (row === -1) return { ok: false, reason: 'column_full' };

  const board = g.board.map(c => [...c]);
  board[col][row] = side;
  const winner = detectWin(board) ?? (isFull(board) ? 'draw' : null);
  return {
    ok: true,
    state: { ...g, board, winner, turn: side === 'A' ? 'B' : 'A',
             turnStartedAt: at.toISO()! },
  };
}

const isFull = (b: Cell[][]) => b.every(c => c[ROWS - 1] !== null);

function detectWin(b: Cell[][]): Cell {
  const at = (c: number, r: number): Cell =>
    c >= 0 && c < COLS && r >= 0 && r < ROWS ? b[c][r] : null;
  const dirs: [number, number][] = [[1, 0], [0, 1], [1, 1], [1, -1]];
  for (let c = 0; c < COLS; c++) for (let r = 0; r < ROWS; r++) {
    const v = at(c, r); if (!v) continue;
    for (const [dc, dr] of dirs) {
      if ([1, 2, 3].every(k => at(c + dc * k, r + dr * k) === v)) return v;
    }
  }
  return null;
}

/**
 * §4.7 — a turn clock ticks in the child's REACHABLE hours, not wall hours.
 *
 * A 24-hour timer that burns down while she is asleep and at school is not a
 * 24-hour timer; it is roughly a 9-hour one, and it expires games that nobody
 * abandoned. Callers supply the reachable hours elapsed, computed from her
 * day-parts.
 */
export function turnExpired(g: GameState, reachableHoursElapsed: number): boolean {
  return reachableHoursElapsed >= g.turnBudgetHours;
}

// ======================================================= visual schedule strip
export interface DayPartLite {
  kind: string; startsLocal: string; endsLocal: string; reachable: boolean;
}
export interface StripSegment {
  kind: string; label: string; icon: string; startsLocal: string; endsLocal: string;
  current: boolean; next: boolean;
}

interface DayPartMeta { label: string; glyph: string }

/**
 * §8.2.2 (v0.39.0) — label and glyph live in the same row so the Day Ribbon's
 * text and icon can never drift apart into contradicting each other; there is
 * no second lookup to fall out of sync with this one.
 *
 * The glyph is static. No pulse, no spin, no "breathing" scale — §8.13's
 * autonomous-motion ban gets no icon exception here.
 */
const DAY_PART_META: Record<string, DayPartMeta> = {
  wake: { label: 'wake up', glyph: '🌅' },
  before_school: { label: 'get ready', glyph: '☀️' },
  school: { label: 'school', glyph: '☀️' },
  after_school: { label: 'home time', glyph: '☀️' },
  activity: { label: 'activity', glyph: '☀️' },
  dinner: { label: 'dinner', glyph: '🌆' },
  wind_down: { label: 'quiet time', glyph: '🌆' },
  bedtime: { label: 'bedtime', glyph: '🌙' },
  asleep: { label: 'sleep', glyph: '🌙' },
  free: { label: 'free time', glyph: '☀️' },
};

const FALLBACK_GLYPH = '•';

/**
 * §8.4 — the architecture is already a visual-schedule tool. Day-parts, ordered,
 * with "what happens next" marked, is close to what occupational therapists
 * build by hand for autistic children, so the marginal cost is near zero.
 */
export function scheduleStrip(parts: DayPartLite[], nowLocal: string): StripSegment[] {
  const sorted = [...parts].sort((a, b) => a.startsLocal.localeCompare(b.startsLocal));
  const curIdx = sorted.findIndex(p =>
    p.startsLocal <= p.endsLocal
      ? nowLocal >= p.startsLocal && nowLocal < p.endsLocal
      : nowLocal >= p.startsLocal || nowLocal < p.endsLocal);
  return sorted.map((p, i) => {
    const meta = DAY_PART_META[p.kind];
    return {
      kind: p.kind,
      label: meta?.label ?? p.kind.replace(/_/g, ' '),
      icon: meta?.glyph ?? FALLBACK_GLYPH,
      startsLocal: p.startsLocal, endsLocal: p.endsLocal,
      current: i === curIdx,
      next: curIdx !== -1 && i === (curIdx + 1) % sorted.length,
    };
  });
}

// ================================================================= SMS bridge
export type SmsKind = 'message_waiting' | 'exchange_reminder' | 'call_missed'
                    | 'dose_reminder' | 'schedule_change';

export interface SmsOut { to: string; body: string; }

/**
 * §8.4, §10.8 — the bridge exists because if the away parent cannot participate,
 * the product has failed at its only job. Incarcerated, elderly, device-
 * restricted, or simply poor.
 *
 * It carries an unencrypted carrier channel, so: summaries and notifications
 * ONLY. Never media, never the journal, never the emergency card. And, as with
 * push (§11), never a name — the recipient's own phone is not necessarily
 * private either.
 */
const SMS_TEMPLATES: Record<SmsKind, string> = {
  message_waiting: 'Olive: something new is waiting. Reply OPEN for details.',
  exchange_reminder: 'Olive: you have a scheduled handover coming up.',
  call_missed: 'Olive: you missed a call. Reply CALL to try back.',
  dose_reminder: 'Olive: a medication reminder is due.',
  schedule_change: 'Olive: a schedule change needs your response.',
};

export const SMS_FORBIDDEN = [
  'journal', 'allerg', 'blood', 'medication name', 'diagnosis', 'photo',
  'video', 'http', 'https', 'address', 'insurance', 'amount', '$',
] as const;

export function buildSms(kind: SmsKind, to: string): SmsOut {
  return { to, body: SMS_TEMPLATES[kind] };
}

export function auditSms(s: SmsOut): { ok: true } | { ok: false; leaks: string[] } {
  const body = s.body.toLowerCase();
  const leaks = (SMS_FORBIDDEN as readonly string[]).filter(k => body.includes(k));
  // Any capitalised word that is not the product name suggests a person's name.
  const caps = (s.body.match(/\b[A-Z][a-z]{2,}\b/g) ?? [])
    .filter(w => w !== 'Olive' && !['Reply', 'OPEN', 'CALL'].includes(w));
  if (caps.length) leaks.push(`name: ${caps.join(',')}`);
  // Template allowlist, same reasoning as the push audit — a heuristic is the
  // wrong instrument when the approved set is small and fixed.
  if (!Object.values(SMS_TEMPLATES).includes(s.body)) leaks.push('not an approved template');
  return leaks.length ? { ok: false, leaks } : { ok: true };
}

export function sendSmsGuard(s: SmsOut): SmsOut {
  const a = auditSms(s);
  if (!a.ok) throw new Error(`sms audit failed: ${a.leaks.join('; ')}`);
  return s;
}
