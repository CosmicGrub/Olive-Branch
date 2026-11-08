/**
 * MASTERFILE §8.6.5 — colour of the day: the sync rule, the art-style settings
 * and the play window, as one pure module.
 *
 * Why a module of its own rather than more of palette.ts: palette.ts answers
 * "which colours exist and where may one appear". This file answers "what is
 * today's colour, who may change it, and how do two devices agree". It is the
 * one place those rules are written; the server (server/routes.mjs) calls it
 * before every write, migration 0042 re-states the same rules as a trigger so a
 * second writer cannot bypass them, and client/lib/colour_day_logic.dart is a
 * line-by-line port held to golden vectors (tools/gen-colour-vectors.mjs).
 *
 * THE SYNC RULE, in one paragraph. She is asked one question a day: "which do
 * you like more today?". The answer is one row per (child, her-local-date), so
 * the question cannot be asked twice for the same day. If two of her devices
 * answer close together the LATER answer wins on both (compared by server-
 * clamped answer time, ties go to the incoming write so replays are stable).
 * A guardian may set a "colour day" for today, which is flagged as an override
 * and which her own later taps do not replace; clearing it hands the question
 * back to her. Everything is a fact about which colour was chosen — there is no
 * field for why (§8.6.4, P2).
 */
import { PALETTE, swatch, parentView, type ColourChoice, type ParentColourView } from './palette.ts';

// ============================================================ art styles ====
export const ART_STYLES = ['paper', 'sticker', 'crayon', 'watercolour', 'felt', 'line', 'pixel'] as const;
export type ArtStyle = typeof ART_STYLES[number];

/** Pixel pairs with the coding activities and unlocks at 8 (§21). */
export const PIXEL_MIN_AGE = 8;
export const DEFAULT_ART_STYLE: ArtStyle = 'paper';

export const isArtStyle = (s: unknown): s is ArtStyle =>
  typeof s === 'string' && (ART_STYLES as readonly string[]).includes(s);

/** Styles a child of this age may be given. Unknown age is treated as young. */
export function stylesForAge(ageYears: number | null): ArtStyle[] {
  const grown = typeof ageYears === 'number' && ageYears >= PIXEL_MIN_AGE;
  return ART_STYLES.filter((s) => s !== 'pixel' || grown);
}

export interface ArtSettings {
  /** The style drawings default to. Always one of `allowedStyles`. */
  artStyle: ArtStyle;
  /** The styles she may pick between while colouring. */
  allowedStyles: ArtStyle[];
  /** Whether the daily "which do you like more?" question is asked at all. */
  dailyQuestion: boolean;
  /** Path code and Pixel garden (the two coding activities). */
  codeActivities: boolean;
}

export const DEFAULT_ART_SETTINGS: ArtSettings = {
  artStyle: DEFAULT_ART_STYLE,
  allowedStyles: ['paper', 'sticker', 'crayon', 'watercolour', 'felt', 'line'],
  dailyQuestion: true,
  codeActivities: true,
};

const ART_KEYS = ['artStyle', 'allowedStyles', 'dailyQuestion', 'codeActivities'] as const;

export type ArtPatchResult =
  | { ok: true; settings: ArtSettings }
  | { ok: false; reason: 'body_must_be_object' | 'unknown_field' | 'empty_body' | 'bad_artStyle'
      | 'bad_allowedStyles' | 'bad_dailyQuestion' | 'bad_codeActivities'
      | 'style_not_for_age' | 'style_not_allowed' };

/**
 * Apply a guardian's partial update to the stored settings. Unknown keys are
 * refused, not ignored, and the result is only ever a state the table's CHECKs
 * also admit — so a bad body is a specific 400, never a Postgres error.
 */
export function mergeArtSettings(
  current: ArtSettings, patch: unknown, ageYears: number | null,
): ArtPatchResult {
  if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return { ok: false, reason: 'body_must_be_object' };
  const keys = Object.keys(patch);
  if (keys.some((k) => !(ART_KEYS as readonly string[]).includes(k))) return { ok: false, reason: 'unknown_field' };
  if (!keys.length) return { ok: false, reason: 'empty_body' };
  const p = patch as Record<string, unknown>;
  const next: ArtSettings = { ...current, allowedStyles: [...current.allowedStyles] };
  if ('artStyle' in p) {
    if (!isArtStyle(p.artStyle)) return { ok: false, reason: 'bad_artStyle' };
    next.artStyle = p.artStyle;
  }
  if ('allowedStyles' in p) {
    const a = p.allowedStyles;
    if (!Array.isArray(a) || a.length < 1 || a.length > ART_STYLES.length || !a.every(isArtStyle)
        || new Set(a).size !== a.length) return { ok: false, reason: 'bad_allowedStyles' };
    // Canonical order, so two guardians saving the same set agree byte for byte.
    next.allowedStyles = ART_STYLES.filter((s) => (a as string[]).includes(s));
  }
  if ('dailyQuestion' in p) {
    if (typeof p.dailyQuestion !== 'boolean') return { ok: false, reason: 'bad_dailyQuestion' };
    next.dailyQuestion = p.dailyQuestion;
  }
  if ('codeActivities' in p) {
    if (typeof p.codeActivities !== 'boolean') return { ok: false, reason: 'bad_codeActivities' };
    next.codeActivities = p.codeActivities;
  }
  const ok = stylesForAge(ageYears);
  if (next.allowedStyles.some((s) => !ok.includes(s)) || !ok.includes(next.artStyle)) {
    return { ok: false, reason: 'style_not_for_age' };
  }
  if (!next.allowedStyles.includes(next.artStyle)) return { ok: false, reason: 'style_not_allowed' };
  return { ok: true, settings: next };
}

// ============================================================ the day row ===
export type ColourChosenBy = 'child' | 'guardian';

export interface DayColour {
  /** yyyy-mm-dd in HER home zone at the moment of choosing. */
  localDate: string;
  colourId: string;
  chosenBy: ColourChosenBy;
  /** A guardian's colour day. Her own taps do not replace it. */
  override: boolean;
  /** Epoch ms. For a child's answer this is the clamped time she answered. */
  chosenAtMs: number;
}

/** A device may report an answer it made offline, but not an old or future one. */
export const MAX_ANSWER_AGE_MS = 12 * 3600 * 1000;
export const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;

/**
 * The time a child's answer counts as having been given. A device clock is not
 * trusted: a missing, non-numeric, future or very old time collapses to "now",
 * and an offline answer keeps its own time only within the last 12 hours.
 */
export function clampAnsweredAt(answeredAtMs: unknown, nowMs: number): number {
  if (typeof answeredAtMs !== 'number' || !Number.isFinite(answeredAtMs)) return nowMs;
  if (answeredAtMs > nowMs + MAX_CLOCK_SKEW_MS) return nowMs;
  if (answeredAtMs > nowMs) return nowMs;
  if (answeredAtMs < nowMs - MAX_ANSWER_AGE_MS) return nowMs;
  return Math.floor(answeredAtMs);
}

export const isLocalDate = (s: unknown): s is string => {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
};

export type MergeOutcome =
  | { ok: true; row: DayColour; changed: boolean; kept: 'incoming' | 'existing' }
  | { ok: false; reason: 'unknown_colour' | 'bad_shape' | 'wrong_day' | 'override_holds' };

/**
 * The whole rule, for one (child, date). `existing` is the stored row for the
 * incoming write's date, or null when nobody has answered that day yet.
 *
 *  - A child's answer never replaces a guardian's colour day.
 *  - A guardian's colour day replaces her answer, whichever is later (it is a
 *    deliberate act made online), but only the later of two colour days wins.
 *  - Otherwise the later answer wins; an older answer that arrives late is
 *    acknowledged, not applied ("kept: existing") so a slow device converges.
 */
export function mergeDay(existing: DayColour | null, incoming: DayColour): MergeOutcome {
  if (!swatch(incoming.colourId)) return { ok: false, reason: 'unknown_colour' };
  if (!isLocalDate(incoming.localDate) || !Number.isFinite(incoming.chosenAtMs)) return { ok: false, reason: 'bad_shape' };
  if ((incoming.chosenBy === 'guardian') !== incoming.override) return { ok: false, reason: 'bad_shape' };
  if (incoming.chosenBy !== 'child' && incoming.chosenBy !== 'guardian') return { ok: false, reason: 'bad_shape' };
  if (!existing) return { ok: true, row: incoming, changed: true, kept: 'incoming' };
  if (existing.localDate !== incoming.localDate) return { ok: false, reason: 'wrong_day' };
  if (incoming.chosenBy === 'child' && existing.override) return { ok: false, reason: 'override_holds' };
  const replaces = incoming.chosenBy === 'guardian' && !existing.override
    ? true
    : incoming.chosenAtMs >= existing.chosenAtMs;
  if (!replaces) return { ok: true, row: existing, changed: false, kept: 'existing' };
  const changed = existing.colourId !== incoming.colourId || existing.override !== incoming.override
    || existing.chosenBy !== incoming.chosenBy;
  return { ok: true, row: incoming, changed, kept: 'incoming' };
}

/** The most recent day's row, or null if she has never answered. */
export function currentDay(days: DayColour[]): DayColour | null {
  let best: DayColour | null = null;
  for (const d of days) {
    if (!best || d.localDate > best.localDate
        || (d.localDate === best.localDate && d.chosenAtMs > best.chosenAtMs)) best = d;
  }
  return best;
}

/** The colour she is wearing today: today's row, else the last one she had. */
export function colourToday(days: DayColour[], localDate: string): DayColour | null {
  const today = currentDay(days.filter((d) => d.localDate === localDate));
  return today ?? currentDay(days.filter((d) => d.localDate < localDate));
}

/**
 * One question a day. Asked only if the guardian has not switched it off, no
 * row exists for today (so an answer on any of her devices ends the question on
 * all of them) and no colour day is in force.
 */
export function needsQuestion(days: DayColour[], localDate: string, dailyQuestion: boolean): boolean {
  if (!dailyQuestion) return false;
  return !days.some((d) => d.localDate === localDate);
}

/** Does this device already show today's answer? Drives the "Matches" chip. */
export function deviceMatches(
  days: DayColour[], localDate: string, seen: { localDate: string; colourId: string } | null,
): boolean {
  const today = colourToday(days, localDate);
  if (!today || !seen) return false;
  return seen.colourId === today.colourId;
}

/**
 * The guardian's view, via the existing parentView(): one neutral sentence.
 * Each day becomes one ColourChoice dated at local noon UTC, so the date part
 * parentView() compares is her LOCAL date, not a UTC accident.
 */
export function toChoices(days: DayColour[]): ColourChoice[] {
  return [...days]
    .sort((a, b) => (a.localDate < b.localDate ? -1 : a.localDate > b.localDate ? 1 : a.chosenAtMs - b.chosenAtMs))
    .map((d) => ({ colourId: d.colourId, chosenAt: `${d.localDate}T12:00:00.000Z`, via: 'daily' as const }));
}

export function guardianView(days: DayColour[], localDate: string): ParentColourView | null {
  return parentView(toChoices(days), `${localDate}T12:00:00.000Z`);
}

/** The twelve ids, in palette order. Migration 0042's CHECK is generated from this. */
export const COLOUR_IDS: string[] = PALETTE.map((s) => s.id);

// ========================================================= the play window ==
/**
 * §8.6.6 — the play window. A guardian sets when games are open on her device.
 * The ending is a goodnight in her own frame, not a limit she can run into:
 * during the wind-down a game in progress may finish; after it, games rest
 * until the window opens again. Calls and family messages are never gated here
 * (§5.19, §8.1) — this module has no input that could gate them.
 */
export interface PlayWindow {
  /** Minutes after local midnight, 0..1439. */
  opensMin: number;
  /** Minutes after local midnight, opensMin < restsMin <= 1439. */
  restsMin: number;
  /** 0, 15 or 30: the gentle tail before restsMin. */
  windDownMin: number;
}

export const WIND_DOWN_CHOICES = [0, 15, 30] as const;

export type PlayWindowState = 'open' | 'winding_down' | 'resting';

export type PlayWindowCheck =
  | { ok: true; window: PlayWindow }
  | { ok: false; reason: 'body_must_be_object' | 'unknown_field' | 'bad_opensMin' | 'bad_restsMin'
      | 'bad_windDownMin' | 'window_too_short' };

const isMinute = (n: unknown): n is number => typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= 1439;

export function checkPlayWindow(input: unknown): PlayWindowCheck {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { ok: false, reason: 'body_must_be_object' };
  const i = input as Record<string, unknown>;
  if (Object.keys(i).some((k) => !['opensMin', 'restsMin', 'windDownMin'].includes(k))) return { ok: false, reason: 'unknown_field' };
  if (!isMinute(i.opensMin)) return { ok: false, reason: 'bad_opensMin' };
  if (!isMinute(i.restsMin) || i.restsMin <= i.opensMin) return { ok: false, reason: 'bad_restsMin' };
  if (!(WIND_DOWN_CHOICES as readonly unknown[]).includes(i.windDownMin)) return { ok: false, reason: 'bad_windDownMin' };
  if (i.restsMin - i.opensMin < (i.windDownMin as number) + 15) return { ok: false, reason: 'window_too_short' };
  return { ok: true, window: { opensMin: i.opensMin, restsMin: i.restsMin, windDownMin: i.windDownMin as number } };
}

/** `minuteOfDay` is HER local minute, 0..1439. */
export function playWindowState(w: PlayWindow | null, minuteOfDay: number): PlayWindowState {
  if (!w) return 'open';
  if (minuteOfDay < w.opensMin || minuteOfDay >= w.restsMin) return 'resting';
  if (w.windDownMin > 0 && minuteOfDay >= w.restsMin - w.windDownMin) return 'winding_down';
  return 'open';
}

/** Minutes games stay open each day. */
export const windowLength = (w: PlayWindow) => w.restsMin - w.opensMin;

/**
 * "If you make the window longer, the other guardian is told. Shorter is never
 * reported." A new window is longer if it opens earlier or rests later.
 */
export function isLonger(prev: PlayWindow | null, next: PlayWindow): boolean {
  if (!prev) return false;
  return next.opensMin < prev.opensMin || next.restsMin > prev.restsMin;
}

/** Copy for the three states. One calm sentence, no number, nothing taken away. */
export function playWindowLine(state: PlayWindowState): string | null {
  if (state === 'winding_down') return 'It’s getting sleepy. One more, then goodnight.';
  if (state === 'resting') return 'Games are resting now. They’ll be back tomorrow.';
  return null;
}

/** Keys that must never ride along with a colour or a window. Asserted. */
export const DAY_FORBIDDEN_KEYS = ['mood', 'sentiment', 'feeling', 'emotion', 'trend', 'why', 'reason', 'streak', 'score'] as const;
