/**
 * MASTERFILE §9.1 / §20.2b — splits one OCR'd block of text into per-problem
 * strings.
 *
 * A HEURISTIC, not a parser: real worksheets are numbered lists ("1. ...",
 * "2. ...") often enough that matching a leading "N." / "N)" / "N:" per line
 * is a real, useful signal, but it is not guaranteed — OCR can drop the
 * numbering entirely, misread a digit, or the sheet may not be numbered at
 * all. When no line matches the pattern anywhere in the text, this falls
 * back to treating the WHOLE recognized block as a single problem, which is
 * always a safe (if coarser) answer: capture-route.ts still runs it through
 * forbiddenFor()/generateHint()/guardHint() exactly the same as a correctly
 * split one, just as one bigger unit instead of several.
 */

/** A line starting with a small number followed by '.', ')' or ':'. The digit run is capped at 3 to avoid a stray "1234" mid-sentence reading as a list marker. */
const NUMBERED_LINE_RE = /^\s*(\d{1,3})[.):]\s*(.*)$/;

export function splitProblems(ocrText: string): string[] {
  const lines = (ocrText ?? '').split(/\r?\n/);
  const starts: number[] = [];
  lines.forEach((line, i) => { if (NUMBERED_LINE_RE.test(line)) starts.push(i); });

  if (starts.length === 0) {
    const whole = (ocrText ?? '').trim();
    return whole ? [whole] : [];
  }

  const problems: string[] = [];
  for (let i = 0; i < starts.length; i++) {
    const from = starts[i];
    const to = i + 1 < starts.length ? starts[i + 1] : lines.length;
    const block = lines.slice(from, to);
    const m = block[0].match(NUMBERED_LINE_RE)!;
    const text = [m[2], ...block.slice(1)].join(' ').replace(/\s+/g, ' ').trim();
    if (text) problems.push(text);
  }
  return problems;
}
