/**
 * MASTERFILE §9.1 — homework capture.
 *
 * Two independent concerns, deliberately not merged:
 *
 *  1. IMAGE. A quality gate before OCR, because a blurred or clipped photo
 *     produces confident nonsense, and a parent acting on nonsense is worse than
 *     a parent asked to retake the photo.
 *
 *  2. THE TUTOR. §9.1's defensible core is "hint, don't solve". That is a
 *     safety property with a specific failure mode — a model that answers the
 *     question destroys the thing the feature exists to protect, which is the
 *     authority of a parent who forgot fractions fifteen years ago. It is
 *     enforced here by an output guard, not by prompt wording.
 */

export interface ImageStats {
  widthPx: number;
  heightPx: number;
  /** Variance of Laplacian; low means blurred. */
  sharpness: number;
  /** 0..1 fraction of pixels at the extremes. */
  clipping: number;
  /** Detected page rotation in degrees, -45..45. */
  skewDegrees: number;
}

export type QualityVerdict =
  | { ok: true; deskewBy: number }
  | { ok: false; reason: QualityFailure; advice: string };

export type QualityFailure =
  | 'too_small' | 'too_blurred' | 'too_clipped' | 'too_skewed';

/**
 * MEASURED, not guessed. Swept against real tesseract 5.3.4 on generated
 * worksheets, scoring the fraction of expected tokens recovered:
 *
 *   skew    0°=100%  2°=100%  4°=83%  6°=67%  8°=33%  10°=0%
 *   blur σ  0=100%   1=100%   2=100%  3=50%   4=33%   6=0%
 *   size    800px=100%  480px=100%  400px=100%  320px=100%  240px=67%
 *
 * The first draft of this file set MAX_SKEW_DEG = 25 and MIN_EDGE_PX = 640 from
 * intuition. Both were wrong in opposite directions: 25° passes images that
 * recover NOTHING, and 640px rejects images that recover everything. Deskew
 * happens before OCR, so the gate only needs to reject what deskew cannot save.
 */
export const MIN_EDGE_PX = 320;      // 240px is the first measured degradation
export const MIN_SHARPNESS = 100;    // proxy for σ≈3, where recovery halves
export const MAX_CLIPPING = 0.35;
export const MAX_SKEW_DEG = 6;       // 8° already loses two thirds of tokens

/**
 * Advice is written for a child holding a tablet, not for a developer. "Move a
 * bit closer" is actionable; "resolution below threshold" is not.
 */
export function gateImage(s: ImageStats): QualityVerdict {
  if (Math.min(s.widthPx, s.heightPx) < MIN_EDGE_PX) {
    return { ok: false, reason: 'too_small', advice: 'Move a bit closer to the page.' };
  }
  if (s.sharpness < MIN_SHARPNESS) {
    return { ok: false, reason: 'too_blurred', advice: 'Hold still and try again.' };
  }
  if (s.clipping > MAX_CLIPPING) {
    return { ok: false, reason: 'too_clipped',
             advice: 'Try moving away from the bright light.' };
  }
  if (Math.abs(s.skewDegrees) > MAX_SKEW_DEG) {
    return { ok: false, reason: 'too_skewed', advice: 'Line the page up straight.' };
  }
  return { ok: true, deskewBy: -s.skewDegrees };
}

// ------------------------------------------------------- the tutor guard -----
export interface Problem {
  /** OCR'd text of one problem. */
  text: string;
  /** Values the guard must never see emitted. Derived, not supplied by a model. */
  forbiddenAnswers: string[];
}

export type HintVerdict =
  | { ok: true; hint: string }
  | { ok: false; reason: HintRefusal; safeFallback: string };

export type HintRefusal =
  | 'contains_answer' | 'contains_equals_result' | 'too_directive' | 'empty';

/**
 * Phrases that hand over the answer rather than pointing at it. These are the
 * shapes a helpful model reaches for under pressure.
 */
const DIRECTIVE_PATTERNS = [
  /\bthe answer is\b/i,
  /\bit(?:'s| is)\s+\d/i,
  /\bequals\s+\d/i,
  /\bjust write\b/i,
  /\btype\s+\d/i,
  /\bso\s+the\s+result\b/i,
  /\bwhich gives you\b/i,
];

/**
 * Enforce "hint, don't solve" on the OUTPUT, whatever the model produced.
 *
 * Prompt instructions are a request; an output guard is a control. A model told
 * not to answer will still answer some fraction of the time, and the fraction
 * that matters here is not zero — it is the case where a tired parent at 8pm
 * reads it out loud.
 */
export function guardHint(hint: string, p: Problem): HintVerdict {
  const fallback = 'Ask what the bottom numbers have in common.';
  const h = (hint ?? '').trim();
  if (!h) return { ok: false, reason: 'empty', safeFallback: fallback };

  // A bare answer anywhere in the text, as a standalone token.
  for (const a of p.forbiddenAnswers) {
    const tok = a.trim();
    if (!tok) continue;
    const re = new RegExp(`(^|[^\\w/])${escapeRe(tok)}([^\\w/]|$)`);
    if (re.test(h)) return { ok: false, reason: 'contains_answer', safeFallback: fallback };
  }
  // "= 15" or "is 15" following the problem's own operands.
  if (/=\s*-?\d+(\s*\/\s*\d+)?/.test(h)) {
    return { ok: false, reason: 'contains_equals_result', safeFallback: fallback };
  }
  for (const re of DIRECTIVE_PATTERNS) {
    if (re.test(h)) return { ok: false, reason: 'too_directive', safeFallback: fallback };
  }
  return { ok: true, hint: h };
}

const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Derive the values a hint must not contain, from the problem itself. Computed
 * server-side so the guard does not depend on a model self-reporting what the
 * answer was.
 */
export function forbiddenFor(text: string): string[] {
  const out = new Set<string>();
  // Simple arithmetic: a op b
  const m = text.match(/(-?\d+)\s*([+\-x*×÷/])\s*(-?\d+)/);
  if (m) {
    const [, a, op, b] = m;
    const x = Number(a), y = Number(b);
    const r = op === '+' ? x + y
            : op === '-' ? x - y
            : (op === 'x' || op === '*' || op === '×') ? x * y
            : y !== 0 ? x / y : NaN;
    if (Number.isFinite(r)) {
      out.add(String(r));
      if (Number.isInteger(r * 100)) out.add(String(Math.round(r * 100) / 100));
    }
  }
  // Fractions: a/b op c/d — the common denominator is also a giveaway.
  const f = text.match(/(\d+)\s*\/\s*(\d+)\s*([+\-])\s*(\d+)\s*\/\s*(\d+)/);
  if (f) {
    const [, , b, , , d] = f;
    const B = Number(b), D = Number(d);
    const lcm = (B * D) / gcd(B, D);
    out.add(String(lcm));
  }
  return [...out];
}

function gcd(a: number, b: number): number { return b ? gcd(b, a % b) : a; }

/** §9.1 — AI assistance is logged and visible, never silent. */
export interface HintAudit {
  problemText: string;
  emitted: string;
  refused: HintRefusal | null;
  shownToParentOnly: true;
  at: string;
}
