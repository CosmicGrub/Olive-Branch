/**
 * MASTERFILE §5.23 — audio-only, and what happens when a call goes wrong.
 *
 * Two halves of the same problem: a call that is not perfect is not a failure,
 * and the product has been treating it as one.
 */

export type Side = 'A' | 'B';

// ============================================ §5.23.1 audio-only as a CHOICE
/**
 * Voice-only has been a thing the network does to you. It should be a thing she
 * chooses — a self-conscious eleven-year-old, a bad hair day, a child who simply
 * does not want to be seen today.
 *
 * THE RULE: **he is told the call is voice-only. He is never told why.**
 *
 * "She chose not to be seen" is a fact a parent will overinterpret, and the
 * overinterpretation lands on her. The reason is hers.
 */
export type CallMode = 'video' | 'audio_only';
export type ModeCause = 'chosen' | 'network' | 'device' | 'bedtime';

export interface ModeState {
  mode: CallMode;
  /** Recorded for diagnostics. Never leaves the device it was chosen on. */
  cause: ModeCause;
  changedAt: string;
}

export function setMode(mode: CallMode, cause: ModeCause, at: string): ModeState {
  return { mode, cause, changedAt: at };
}

/** What the OTHER party sees. Mode only — never the cause. */
export function modeForOther(s: ModeState): { mode: CallMode; line: string } {
  return { mode: s.mode,
    line: s.mode === 'audio_only' ? 'Voice only just now.' : '' };
}

export const CAUSE_NEVER_DISCLOSED = true;

export function auditModeDisclosure(v: unknown): { ok: true } | { ok: false; leak: string } {
  const s = JSON.stringify(v).toLowerCase();
  for (const c of ['chosen', 'bedtime', 'she turned', 'declined video', 'camera off'])
    if (s.includes(c)) return { ok: false, leak: c };
  return { ok: true };
}

/**
 * Switching is instant and mid-call, both directions, from either side for
 * themselves. Nobody turns another person's camera on.
 */
export function canSwitchOwnCamera(): true { return true; }
export function canSwitchOthersCamera(): false { return false; }

// ---------------------------------------------------- the listening surface
/**
 * A black rectangle is what every other product shows on an audio call, and for
 * a child it reads as absence. She needs something to look at while she listens.
 */
export type ListeningSurface = 'her_colour' | 'waveform' | 'canvas' | 'their_photo';

export interface Listening {
  surface: ListeningSurface;
  /** Her §8.6 colour, where she has one. */
  colourHex: string | null;
  /** Slow. A fast waveform is a stimulant at bedtime. */
  waveformHz: number;
}

export const WAVEFORM_HZ_CALM = 4;

export function listening(colourHex: string | null, surface: ListeningSurface = 'her_colour'): Listening {
  return { surface, colourHex, waveformHz: WAVEFORM_HZ_CALM };
}

/** Never a black screen on a child's device during a live call. */
export const NEVER_BLANK = true;

// ------------------------------------------------------------ bedtime mode
/**
 * He reads, the screen goes almost dark, and there is no video at all. The point
 * is that a lit screen at bedtime undoes the reading.
 */
export interface Bedtime {
  mode: 'audio_only';
  screenBrightness: number;
  surface: 'her_colour';
  /** Dims further after this long without a tap. */
  dimAfterSeconds: number;
  /** The call does not end when the screen dims. */
  keepsCallAlive: true;
}

export function bedtime(colourHex: string | null): Bedtime & { colourHex: string | null } {
  return { mode: 'audio_only', screenBrightness: 0.08, surface: 'her_colour',
    dimAfterSeconds: 45, keepsCallAlive: true, colourHex };
}

// --------------------------------------------------------- push to talk ---
/**
 * Asynchronous voice. Unusually natural for a five-year-old — it is a walkie
 * talkie, and she already understands one — and it sits exactly between banked
 * messages and a live call.
 */
export interface VoiceNote {
  id: string;
  from: Side;
  seconds: number;
  at: string;
  heard: boolean;
}

/** Long enough for a thought, short enough that nobody drafts. */
export const PTT_MAX_SECONDS = 60;
export const PTT_MIN_SECONDS = 1;

export type PttError = 'too_long' | 'too_short';

export function pushToTalk(
  id: string, from: Side, seconds: number, at: string,
): { ok: true; note: VoiceNote } | { ok: false; reason: PttError } {
  if (seconds > PTT_MAX_SECONDS) return { ok: false, reason: 'too_long' };
  if (seconds < PTT_MIN_SECONDS) return { ok: false, reason: 'too_short' };
  return { ok: true, note: { id, from, seconds, at, heard: false } };
}

/** No read receipt to the child. She is not accountable for listening. */
export function pttChildView(notes: VoiceNote[]): { count: number; line: string } {
  const n = notes.filter(x => !x.heard).length;
  return { count: n, line: n === 0 ? '' : n === 1 ? 'A message from Dad' : `${n} messages from Dad` };
}

// ------------------------------------------------------- answering ---------
/**
 * The voice-only answer is the SAME SIZE as the video one. A smaller button is a
 * judgement, and she will read it as one.
 */
export interface AnswerOption { kind: 'video' | 'voice' | 'not_now'; label: string; weight: 1 }

export function answerOptions(): AnswerOption[] {
  return [
    { kind: 'video', label: 'Answer', weight: 1 },
    { kind: 'voice', label: 'Just talking', weight: 1 },
    { kind: 'not_now', label: 'Not now', weight: 1 },
  ];
}

export function optionsEquallyWeighted(o: AnswerOption[]): boolean {
  return o.every(x => x.weight === 1);
}

// ================================================= §5.23.2 when it goes wrong
/**
 * A frozen father and an ended call are the same event to a five-year-old, and
 * they are not the same thing. She needs to be told which.
 */
export type CallTrouble = 'frozen' | 'slow' | 'dropped' | 'reconnecting' | 'ended';

export interface TroubleView {
  state: CallTrouble;
  /** Child language. Short, specific, never blaming. */
  line: string;
  /** Should she wait, or is it over? */
  waiting: boolean;
}

export function troubleView(state: CallTrouble): TroubleView {
  const map: Record<CallTrouble, [string, boolean]> = {
    frozen:       ['The picture stopped. He is still there.', true],
    slow:         ['It has gone a bit slow.', true],
    reconnecting: ['Finding him again.', true],
    dropped:      ['It stopped. We are getting him back.', true],
    ended:        ['That is the end of the call.', false],
  };
  const [line, waiting] = map[state];
  return { state, line, waiting };
}

/** Never on a child's screen, in any state. */
export const TROUBLE_BANNED = [
  'failed', 'failure', 'error', 'could not connect', 'unavailable',
  'disconnected', 'lost connection', 'try again later', 'poor connection',
  'your network', 'check your',
] as const;

export function auditTrouble(v: TroubleView): { ok: true } | { ok: false; found: string[] } {
  const t = v.line.toLowerCase();
  const found = (TROUBLE_BANNED as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

// ------------------------------------------------- the degradation ladder --
/**
 * Never a failure — always a next rung. The call falls down the ladder rather
 * than off it, and the bottom rung is a banked message, which always works.
 */
export type Rung = 'hd' | 'sd' | 'audio_only' | 'banked';

export const LADDER: Rung[] = ['hd', 'sd', 'audio_only', 'banked'];

export function stepDown(r: Rung): Rung {
  const i = LADDER.indexOf(r);
  return LADDER[Math.min(i + 1, LADDER.length - 1)];
}

export function stepUp(r: Rung): Rung {
  const i = LADDER.indexOf(r);
  return LADDER[Math.max(i - 1, 0)];
}

/** The bottom rung always succeeds. That is what makes it a ladder. */
export const BOTTOM_ALWAYS_WORKS = true;

export function rungLine(r: Rung): string {
  return r === 'banked'
    ? 'The line is not good enough right now, so record him something instead.'
    : '';
}

// ------------------------------------------------- state across a reconnect
/**
 * The game in progress, the story position, the half-coloured picture. Losing
 * them is how a child learns not to bother starting anything on a call.
 */
export interface CallState {
  activity: string | null;
  activityState: unknown;
  storyLine: number | null;
  elapsedSeconds: number;
}

export function preserve(s: CallState): CallState { return { ...s }; }

export function restore(before: CallState, after: Partial<CallState>): CallState {
  return { ...before, ...after };
}

export const RECONNECT_PRESERVES_STATE = true;

/**
 * Resuming asks first. A call that reconnects itself and starts transmitting a
 * child's bedroom because the wifi came back is a privacy failure with good
 * intentions.
 */
export interface ResumeOffer { line: string; autoResumes: false }

export function resumeOffer(): ResumeOffer {
  return { line: 'Ready to carry on?', autoResumes: false };
}

/** Wi-Fi to cellular mid-call. */
export interface NetworkChange { from: string; to: string; metered: boolean }

export function networkChangeAdvice(c: NetworkChange): string | null {
  return c.metered
    ? 'You have moved off wi-fi. This will use data now.'
    : null;
}

export const SURVIVES_NETWORK_CHANGE = true;
