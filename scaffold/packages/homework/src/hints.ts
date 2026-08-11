/**
 * MASTERFILE §9.1 / §20.2b — a RULE-BASED hint generator.
 *
 * This is NOT an AI model, and nothing in this file should ever be described
 * as one. There is no LLM wired into this repository anywhere — no API key
 * is configured for one in any config file, env var, or secret store this
 * project has — so §20.2b's "OCR: Homework capture specified, not built" gap
 * is closed here with plain pattern-matching over the OCR'd problem text: a
 * small, fixed set of canned hint TEMPLATES, chosen by regex shape (a
 * fraction addition/subtraction, a multiplication, a subtraction, an
 * addition, or none of the above), never by anything that has "read" or
 * "understood" the problem. If a real model is ever wired in later, its
 * output still has to pass through guardHint() (capture.ts) exactly like
 * this one does — this file does not replace that guard, it is just one
 * more producer feeding it.
 *
 * Every template below is written to be safe by construction — none names a
 * number the guard would need to catch — but they still go through
 * guardHint() before ever reaching a parent (see capture-route.ts), because
 * per capture.ts's own header, "the fraction that matters is not zero" and
 * an output guard beats trusting a producer to always behave, including this
 * one.
 */

/** Fraction addition/subtraction: a/b (+|-) c/d. Checked FIRST — its own operator (+/-) would otherwise also match the plainer addition/subtraction patterns below. */
const FRACTION_RE = /\d+\s*\/\s*\d+\s*[+\-]\s*\d+\s*\/\s*\d+/;
/** Multiplication: a (x|×|*) b. */
const MULTIPLY_RE = /-?\d+\s*[x×*]\s*-?\d+/i;
/** Subtraction: a - b (checked after fractions and multiplication so it doesn't steal their operands). */
const SUBTRACT_RE = /-?\d+\s*-\s*-?\d+/;
/** Addition: a + b. */
const ADD_RE = /-?\d+\s*\+\s*-?\d+/;

/**
 * A generic fallback that NEVER leaks a number, a fraction, or an operator's
 * result — this is what a problem the other patterns don't recognise gets,
 * rather than silence or a guess at what it might be.
 */
export const FALLBACK_HINT = 'Break the problem into smaller steps and try the first one on its own.';

/**
 * Rule-based, deterministic, and — see file header — not an AI model. Same
 * input always produces the same output; there is nothing here that reads
 * context, remembers a prior problem, or varies its phrasing.
 */
export function generateHint(problemText: string): string {
  const t = (problemText ?? '').trim();
  if (FRACTION_RE.test(t)) {
    return 'Before adding or subtracting, find a number both bottom numbers '
      + 'divide into evenly — that becomes your common denominator.';
  }
  if (MULTIPLY_RE.test(t)) {
    return 'Try skip-counting by the smaller number — count up in equal jumps that many times.';
  }
  if (SUBTRACT_RE.test(t)) {
    return 'Start at the bigger number and count backward the smaller number of steps.';
  }
  if (ADD_RE.test(t)) {
    return 'Start at the first number and count on from there, one group at a time.';
  }
  return FALLBACK_HINT;
}
