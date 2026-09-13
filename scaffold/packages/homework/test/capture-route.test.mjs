/**
 * capture-route.ts — the homework OCR pipeline end to end. MASTERFILE §9.1,
 * §20.2b: "OCR: Homework capture specified, not built." This is what closes
 * that gap: a real photo in, real recognized text out, real rule-based
 * hints (NOT an AI model — see hints.ts's own header), all run through the
 * existing guardHint().
 *
 * Fixtures come from gen_ocr_fixture.py (Pillow + a real TrueType font) --
 * NOT gen-fixtures.mjs's pure-JS hand-rolled bitmap font, which measure.
 * test.mjs already proves is good enough for sharpness/skew CLASSIFICATION
 * but is measurably worse at producing text Tesseract can actually read
 * (an earlier draft of this suite found the hand-rolled font recognised
 * WORSE than a heavily-blurred version of itself). This is a REAL, DECLARED
 * toolchain dependency (Python 3 + Pillow), the same posture homework.
 * test.mjs's own K group already takes for ImageMagick + the tesseract
 * CLI: MISSING TOOLCHAIN is reported as a failure, never a silent skip.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runHomeworkCapture, terminateSharedWorker } from '../src/capture-route.mjs';
import { splitProblems } from '../src/split.mjs';
import { generateHint, FALLBACK_HINT } from '../src/hints.mjs';
import { guardHint, forbiddenFor } from '../src/capture.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => {
  const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) });
};
const checkTrue = (g, n, cond) => check(g, n, cond, 'true');

const resolveCmd = (candidates) => {
  for (const c of candidates) {
    try { execFileSync(c, ['--version'], { stdio: 'ignore' }); return c; } catch {}
  }
  return null;
};
const PYTHON = resolveCmd([process.env.HW_PYTHON, 'python', 'python3',
  'C:\\Python314\\python.exe'].filter(Boolean));

const GEN_SCRIPT = fileURLToPath(new URL('./gen_ocr_fixture.py', import.meta.url));
const FIXTURE_DIR = mkdtempSync(join(tmpdir(), 'hw-ocr-route-'));

async function main() {
  // ---------------------------------------------------------- toolchain ---
  if (!PYTHON) {
    check('P toolchain', 'python 3 + Pillow available to generate a real OCR fixture',
      'MISSING', 'python found');
    finish();
    return;
  }
  try {
    execFileSync(PYTHON, [GEN_SCRIPT, FIXTURE_DIR], { stdio: 'pipe' });
  } catch (e) {
    check('P toolchain', 'gen_ocr_fixture.py ran successfully (Pillow importable)',
      `FAILED: ${e.stderr?.toString().slice(0, 200) ?? e.message}`, 'ran successfully');
    finish();
    return;
  }
  for (const f of ['hw_clean.png', 'hw_blur.png', 'hw_skew.png']) {
    check('P toolchain', `fixture generated: ${f}`, existsSync(join(FIXTURE_DIR, f)), 'true');
  }

  const bytes = (name) => readFileSync(join(FIXTURE_DIR, name));

  // -------------------------------------------------- Q · real OCR route ---
  const clean = await runHomeworkCapture(bytes('hw_clean.png'));
  check('Q route', 'a real clean worksheet photo passes the gate', clean.ok, 'true');
  if (clean.ok) {
    checkTrue('Q route', 'real OCR recovered the addition problem\'s digits',
      /12/.test(clean.rawText) && /27/.test(clean.rawText));
    checkTrue('Q route', 'real OCR recovered the subtraction problem\'s digits',
      /4/.test(clean.rawText) && /9/.test(clean.rawText));
    checkTrue('Q route', 'real OCR recovered the multiplication problem\'s digits',
      /6/.test(clean.rawText) && /7/.test(clean.rawText));
    check('Q route', 'the numbered-list heuristic split the OCR text into 3 problems',
      clean.problems.length, 3);
    checkTrue('Q route', 'every returned problem carries a non-empty guarded hint',
      clean.problems.every((p) => typeof p.hint === 'string' && p.hint.length > 0));
    checkTrue('Q route', 'not one returned hint leaks a digit answer',
      clean.problems.every((p) => forbiddenFor(p.text).every((ans) =>
        !new RegExp(`(^|[^\\w/])${ans.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^\\w/]|$)`).test(p.hint))));
    // Pattern-matched by shape, per hints.ts: the "27+27"-style addition and
    // "4-9"-style subtraction problems should NOT both get the identical
    // canned hint — proves generateHint() is actually branching on the text,
    // not returning one fixed string regardless of input.
    const distinctHints = new Set(clean.problems.map((p) => p.hint));
    checkTrue('Q route', 'different problem shapes get different hint templates',
      distinctHints.size > 1);
  }

  const blurred = await runHomeworkCapture(bytes('hw_blur.png'));
  check('Q route', 'a real deliberately-blurred photo is refused, not OCR\'d',
    blurred.ok, 'false');
  if (!blurred.ok) {
    check('Q route', 'the blurred refusal reason is the gate\'s own', blurred.reason, 'too_blurred');
    check('Q route', 'the blurred refusal advice is the gate\'s own, unchanged',
      blurred.advice, 'Hold still and try again.');
  }

  const skewed = await runHomeworkCapture(bytes('hw_skew.png'));
  check('Q route', 'a real deliberately-skewed photo is refused, not OCR\'d', skewed.ok, 'false');
  if (!skewed.ok) {
    check('Q route', 'the skewed refusal reason is the gate\'s own', skewed.reason, 'too_skewed');
    check('Q route', 'the skewed refusal advice is the gate\'s own, unchanged',
      skewed.advice, 'Line the page up straight.');
  }

  // ------------------------------------------------- R · split heuristic ---
  {
    const numbered = '1. 12 + 27 = ____\n2. 4 - 9 = ____\n3. 6 x 7 = ____';
    const split = splitProblems(numbered);
    check('R split', 'a clean numbered list splits into 3 problems', split.length, 3);
    check('R split', 'the first problem drops its own "1." list marker',
      split[0], '12 + 27 = ____');
    check('R split', 'the second problem drops its own "2." list marker',
      split[1], '4 - 9 = ____');

    const noList = 'just some recognized text with no numbering at all';
    check('R split', 'text with no numbered-list pattern falls back to one whole problem',
      splitProblems(noList).length, 1);
    check('R split', 'the fallback problem is the whole text, unchanged',
      splitProblems(noList)[0], noList);

    check('R split', 'empty OCR text splits into zero problems, not one empty string',
      splitProblems('').length, 0);
  }

  // --------------------------------------------- S · rule-based hints ---
  {
    check('S hints', 'a fraction addition/subtraction problem gets the common-denominator hint',
      generateHint('2/3 + 1/5 = ____').includes('common denominator'), 'true');
    check('S hints', 'a multiplication problem gets the skip-counting hint',
      generateHint('6 x 7 = ____').includes('skip-count'), 'true');
    check('S hints', 'a subtraction problem gets the counting-back hint',
      generateHint('12 - 5 = ____').includes('backward'), 'true');
    check('S hints', 'an addition problem gets the counting-on hint',
      generateHint('12 + 27 = ____').includes('count on'), 'true');
    check('S hints', 'an unrecognised shape gets the generic fallback, unchanged',
      generateHint('draw a picture of your favourite animal'), FALLBACK_HINT);
    checkTrue('S hints', 'the generic fallback never contains a digit',
      !/\d/.test(FALLBACK_HINT));
    // A fraction's own operator (+/-) would also match the plain add/subtract
    // patterns if checked in the wrong order — proves fractions are matched
    // FIRST, per hints.ts's own comment on why order matters.
    check('S hints', 'a fraction subtraction is NOT misclassified as plain subtraction',
      generateHint('3/8 - 1/2 = ____').includes('common denominator'), 'true');
  }

  // ------------------------------- T · guardHint still intercepts a leak ---
  // Not testing capture.ts's guard logic itself again (homework.test.mjs's
  // own L group already does that exhaustively) -- this proves the ROUTE's
  // specific integration point: a hint generator that leaked (hypothetically
  // — hints.ts's own templates never do, by construction) would still be
  // caught before ever reaching the response, using a real problem this
  // suite's own OCR pipeline actually produced.
  {
    const p = { text: '12 + 27 = ____', forbiddenAnswers: forbiddenFor('12 + 27 = ____') };
    checkTrue('T guard', 'forbiddenFor derived the real answer (39) from this real problem',
      p.forbiddenAnswers.includes('39'));
    const deliberatelyLeaky = 'The answer is 39, just write that down.';
    const verdict = guardHint(deliberatelyLeaky, p);
    check('T guard', 'a deliberately-leaky hint text is refused by the existing guard',
      verdict.ok, 'false');
    checkTrue('T guard', 'the refusal carries a non-empty safe fallback',
      verdict.safeFallback.length > 10);
    check('T guard', 'the leaked answer never appears in what the refusal actually returns',
      new RegExp('(^|[^\\w/])39([^\\w/]|$)').test(verdict.safeFallback), 'false');
  }

  await terminateSharedWorker();
  finish();
}

function finish() {
  let g = '';
  for (const r of rows) {
    if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
    console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
  }
  console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
