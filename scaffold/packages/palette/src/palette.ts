/**
 * MASTERFILE §8.6 — her colour.
 *
 * She picks a colour. It is hers, it appears in the app, and her father can see
 * it. Three problems have to be solved for that to be worth building rather than
 * decorative.
 *
 *  1. IT MUST NOT OVERSATURATE. The naive implementation sets one accent
 *     variable and the whole app turns hot pink. Worse, it collides with the
 *     SEMANTIC colours the Day Ribbon depends on — school blue, dinner purple,
 *     overlap green, prohibition red. A child who picks red must not thereby
 *     recolour every warning in the product.
 *
 *  2. IT MUST STAY LEGIBLE. A five-year-old picks yellow; yellow text on white
 *     is unreadable. The answer is not to refuse her choice — it is to derive an
 *     accessible variant for text and use the pure hue for fills.
 *
 *  3. IT MUST NOT BECOME MOOD SURVEILLANCE. "She picked grey today, is she
 *     sad?" is the product making a psychological claim about a child from a
 *     tap. See §8.6.4 — this file refuses to draw that inference and provides no
 *     field in which one could be recorded.
 */

// ================================================================= palette ==
export interface Swatch {
  id: string;
  /** Her word for it, not a designer's. */
  label: string;
  hex: string;
  /** Derived, WCAG-AA-safe against the light surface. Used for text. */
  inkHex: string;
}

/**
 * A curated set, not a colour picker. A free picker hands a five-year-old the
 * ability to choose #FEFEFE and then wonder why nothing changed.
 *
 * Hues are chosen to sit away from the semantic set (§8.6.2) so that even a
 * near-collision reads as different. There is deliberately no pure red.
 */
export const PALETTE: Swatch[] = [
  { id: 'sunny',    label: 'sunny yellow',  hex: '#F2B705', inkHex: '#7A5C00' },
  { id: 'tangerine',label: 'orange',        hex: '#E8730C', inkHex: '#8A4207' },
  { id: 'coral',    label: 'coral pink',    hex: '#F0757E', inkHex: '#8F2C34' },
  { id: 'bubblegum',label: 'bright pink',   hex: '#E056A8', inkHex: '#8A1F62' },
  { id: 'grape',    label: 'purple',        hex: '#8B6BB1', inkHex: '#4F3670' },
  { id: 'sea',      label: 'sea blue',      hex: '#2F8FC4', inkHex: '#14536F' },
  { id: 'sky',      label: 'sky blue',      hex: '#6BB8E8', inkHex: '#175A80' },
  { id: 'mint',     label: 'mint',          hex: '#5FC9A8', inkHex: '#186853' },
  { id: 'grass',    label: 'grass green',   hex: '#5AA84A', inkHex: '#2A5722' },
  { id: 'chocolate',label: 'chocolate',     hex: '#8A6244', inkHex: '#4E3524' },
  { id: 'storm',    label: 'storm grey',    hex: '#7C8698', inkHex: '#3E4653' },
  { id: 'midnight', label: 'midnight',      hex: '#2B3358', inkHex: '#1B2138' },
];

export const swatch = (id: string) => PALETTE.find(s => s.id === id) ?? null;

// ====================================================== the placement budget =
/**
 * §8.6.2 — where her colour may and may not appear.
 *
 * The forbidden list is the important half. Every entry there is a colour that
 * MEANS something: a ribbon band encodes what she is doing, red encodes a
 * prohibition, the overlap green encodes "you can both talk right now". If her
 * colour could land in any of those, the Day Ribbon stops being readable and a
 * warning stops looking like a warning.
 */
export const ALLOWED_PLACEMENTS = [
  'accent_stripe',    // a thin rule under the header
  'avatar_ring',      // the ring around her face on his screen
  'sleeps_number',    // the big numeral in the countdown
  'game_piece',       // her side in tic-tac-toe, checkers, dots and boxes
  'header_flourish',  // one decorative mark
  'loading_dots',
  'collection_tile',  // the tile behind a collection entry
  'show_frame',       // the border on something she showed him
] as const;

export const FORBIDDEN_PLACEMENTS = [
  'prohibition', 'error', 'warning', 'destructive',
  'ribbon_band', 'day_part', 'overlap_band', 'now_line',
  'medication_block', 'expiry_digest', 'court_export',
  'body_text', 'background', 'surface',
] as const;

export type Placement = typeof ALLOWED_PLACEMENTS[number];

/**
 * At most this many of her colour on one screen. Beyond it the colour stops
 * reading as *hers* and starts reading as a theme, which is the failure mode
 * the user asked to avoid.
 */
export const MAX_PLACEMENTS_PER_SCREEN = 3;

export function applyColour(
  colourId: string, requested: string[],
): { ok: true; placements: Placement[]; dropped: string[] }
 | { ok: false; reason: 'unknown_colour' | 'forbidden_placement'; offending?: string } {
  if (!swatch(colourId)) return { ok: false, reason: 'unknown_colour' };
  const bad = requested.find(p =>
    (FORBIDDEN_PLACEMENTS as readonly string[]).includes(p));
  if (bad) return { ok: false, reason: 'forbidden_placement', offending: bad };
  const valid = requested.filter(p =>
    (ALLOWED_PLACEMENTS as readonly string[]).includes(p)) as Placement[];
  return { ok: true,
    placements: valid.slice(0, MAX_PLACEMENTS_PER_SCREEN),
    dropped: valid.slice(MAX_PLACEMENTS_PER_SCREEN) };
}

// ================================================================ contrast ==
const srgb = (c: number) => {
  const x = c / 255;
  return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
};

export function luminance(hex: string): number {
  const h = hex.replace('#', '');
  const r = parseInt(h.slice(0, 2), 16), g = parseInt(h.slice(2, 4), 16),
        b = parseInt(h.slice(4, 6), 16);
  return 0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b);
}

export function contrastRatio(a: string, b: string): number {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

export const AA_TEXT = 4.5, AA_LARGE = 3.0;

/**
 * §8.4 — she picks yellow, and yellow text on white is unreadable.
 *
 * The answer is NOT to refuse her choice. The pure hue is used for fills, where
 * legibility is not at stake, and a pre-derived `inkHex` is used wherever the
 * colour has to carry text. She never learns that her favourite colour was a
 * problem, because it was not one.
 */
export function textColourFor(s: Swatch, surface = '#FFFFFF'): {
  hex: string; usedInk: boolean; ratio: number;
} {
  const direct = contrastRatio(s.hex, surface);
  if (direct >= AA_TEXT) return { hex: s.hex, usedInk: false, ratio: direct };
  return { hex: s.inkHex, usedInk: true, ratio: contrastRatio(s.inkHex, surface) };
}

/** Every palette entry must be usable. Asserted, not assumed. */
export function auditPalette(surface = '#FFFFFF'): {
  ok: boolean; failures: { id: string; ratio: number }[];
} {
  const failures = PALETTE
    .map(s => ({ id: s.id, ratio: contrastRatio(s.inkHex, surface) }))
    .filter(x => x.ratio < AA_TEXT);
  return { ok: failures.length === 0, failures };
}

// ============================================================== the choice ==
export interface ColourChoice {
  colourId: string;
  chosenAt: string;
  /** 'first_run' | 'daily' — how it was picked, not why. */
  via: 'first_run' | 'daily';
}

/**
 * §8.6.3 — "What colour do you like more today?"
 *
 * A two-up A/B rather than the full palette. Lower effort than twelve choices,
 * it plays like a game rather than a settings screen, and it produces a history
 * worth keeping. One of the pair is always her current colour, so keeping it is
 * as easy as changing it — a daily prompt that nudges toward change would be
 * manufacturing churn.
 */
export function dailyPair(
  current: string, rand: () => number = Math.random,
): [Swatch, Swatch] {
  const cur = swatch(current) ?? PALETTE[0];
  const others = PALETTE.filter(s => s.id !== cur.id);
  const challenger = others[Math.floor(rand() * others.length)];
  // Randomise the side so the current one is not always on the left.
  return rand() < 0.5 ? [cur, challenger] : [challenger, cur];
}

export function choose(
  history: ColourChoice[], colourId: string, at: string,
  via: ColourChoice['via'] = 'daily',
): { ok: true; history: ColourChoice[] } | { ok: false; reason: 'unknown_colour' } {
  if (!swatch(colourId)) return { ok: false, reason: 'unknown_colour' };
  return { ok: true, history: [...history, { colourId, chosenAt: at, via }] };
}

export const currentColour = (history: ColourChoice[]) =>
  history.length ? swatch(history[history.length - 1].colourId) : null;

// ============================================================ the parent ====
export interface ParentColourView {
  label: string;
  hex: string;
  /** True only when today's choice differs from yesterday's. */
  changedToday: boolean;
  /** One neutral sentence. Never an interpretation. */
  line: string;
}

/**
 * §8.6.4 — THE PROHIBITION THIS MODULE EXISTS TO HOLD.
 *
 * A colour is a fact, not a mood. "She picked grey today — is she sad?" is the
 * product making a psychological claim about a child from a tap, and a parent
 * acting on that claim will get it wrong in a way that costs them the exchange.
 *
 * So the parent is told WHAT she picked and nothing else. There is no sentiment
 * field, no trend, no "her colours have been darker this week", and no field in
 * which such a thing could be recorded. The interpretation, if there is one,
 * belongs to the parent who knows her — reached by asking her, which is the
 * point.
 */
export function parentView(history: ColourChoice[], today: string): ParentColourView | null {
  const cur = currentColour(history);
  if (!cur) return null;
  const todays = history.filter(h => h.chosenAt.slice(0, 10) === today.slice(0, 10));
  const prior = history.filter(h => h.chosenAt.slice(0, 10) < today.slice(0, 10));
  const changed = todays.length > 0 &&
    (prior.length === 0 || prior[prior.length - 1].colourId !== cur.id);
  return { label: cur.label, hex: cur.hex, changedToday: changed,
    line: changed ? `Today her colour is ${cur.label}.`
                  : `Her colour is ${cur.label}.` };
}

/** Fields that must never appear alongside a colour. Asserted. */
export const COLOUR_FORBIDDEN = [
  'mood', 'sentiment', 'feeling', 'emotion', 'trend', 'darker', 'lighter',
  'concern', 'flag', 'alert', 'score', 'streak', 'stability', 'volatility',
] as const;

export function auditColourPayload(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((COLOUR_FORBIDDEN as readonly string[]).some(f => k.toLowerCase() === f.toLowerCase())) {
        leaks.push(k);
      }
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ================================================================ year book =
/**
 * §9.8.2 — a year of colours is a page worth printing, and it is the cheapest
 * Year Book section in the product: twelve swatches and a count.
 */
export function coloursForYearBook(history: ColourChoice[], year: number): {
  section: string; swatches: { label: string; hex: string; days: number }[];
} {
  const counts = new Map<string, number>();
  for (const h of history) {
    if (new Date(h.chosenAt).getUTCFullYear() !== year) continue;
    counts.set(h.colourId, (counts.get(h.colourId) ?? 0) + 1);
  }
  return {
    section: 'Your colours',
    swatches: [...counts.entries()]
      .map(([id, days]) => ({ label: swatch(id)!.label, hex: swatch(id)!.hex, days }))
      .sort((a, b) => b.days - a.days),
  };
}
