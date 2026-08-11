/**
 * measure.ts — real ImageStats from real photo bytes. MASTERFILE §9.1, §20.2b.
 *
 * Two layers, deliberately kept separate:
 *   N. unit-level checks of laplacianVariance/clippingFraction/skew against
 *      small, hand-built pixel arrays, where the "right answer" is known
 *      exactly and doesn't depend on any rendering choice.
 *   O. end-to-end checks against REAL generated worksheet images (this
 *      package's own gen-fixtures.mjs — pure JS, no ImageMagick/Tesseract
 *      dependency; see that file's header for why) — a known-blurred and a
 *      known-skewed image must earn the SAME gateImage() verdict a real
 *      photo with those properties would.
 */
import { mkdtempSync } from 'node:fs';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  computeImageStats, laplacianVariance, clippingFraction, estimateSkewDegrees,
  decodeImage, encodePNG, rotateImage, deskewToPng,
} from '../src/measure.mjs';
import { gateImage, MIN_SHARPNESS, MAX_SKEW_DEG, MAX_CLIPPING } from '../src/capture.mjs';
import { writeFixtures } from './gen-fixtures.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => {
  const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) });
};
const checkTrue = (g, n, cond) => check(g, n, cond, 'true');

// ---------------------------------------------------------------------- N -
// Unit-level: known pixel data, known answer.
{
  // A perfectly uniform 5x5 grey field has zero Laplacian everywhere -> 0 variance.
  const flat = new Float64Array(5 * 5).fill(128);
  check('N unit', 'a flat field has zero sharpness', laplacianVariance(flat, 5, 5), 0);

  // A single bright pixel in an otherwise-flat field creates real Laplacian
  // energy at its neighbours -> strictly positive variance.
  const spike = new Float64Array(5 * 5).fill(0);
  spike[2 * 5 + 2] = 255; // centre pixel
  checkTrue('N unit', 'a single spike produces positive sharpness',
    laplacianVariance(spike, 5, 5) > 0);
  checkTrue('N unit', 'a spike is measurably sharper than a flat field',
    laplacianVariance(spike, 5, 5) > laplacianVariance(flat, 5, 5));

  // Clipping: half the pixels pinned to the extremes, half mid-grey -> exactly 0.5.
  const half = new Float64Array([0, 0, 255, 255, 128, 128, 128, 128]);
  check('N unit', 'clippingFraction counts exact 0/255 pixels', clippingFraction(half, 0), 0.5);
  // A value just inside the tolerance band still counts; just outside does not.
  const nearWhite = new Float64Array([252, 252, 128, 128]);
  check('N unit', 'tolerance band catches near-white, not mid-grey',
    clippingFraction(nearWhite, 4), 0.5);
  check('N unit', 'an empty channel has zero clipping (no divide-by-zero)',
    clippingFraction(new Float64Array(0)), 0);

  // decodeImage: real magic-byte sniffing, not filename/extension trust.
  check('N unit', 'garbage bytes are refused, not silently misread',
    (() => { try { decodeImage(Buffer.from([1, 2, 3, 4])); return 'decoded'; }
             catch { return 'refused'; } })(), 'refused');

  // encodePNG/decodeImage round-trip on a tiny synthetic image.
  const tiny = { width: 2, height: 2,
    data: Uint8ClampedArray.from([10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 100, 110, 120, 255]) };
  const roundTripped = decodeImage(encodePNG(tiny));
  check('N unit', 'PNG round-trip preserves width', roundTripped.width, 2);
  check('N unit', 'PNG round-trip preserves height', roundTripped.height, 2);
  check('N unit', 'PNG round-trip preserves pixel data', roundTripped.data[0], 10);

  // rotateImage by 0deg is a no-op (used by deskewToPng's own fast path).
  const same = rotateImage(tiny, 0);
  check('N unit', 'a 0deg rotation leaves the first pixel unchanged', same.data[0], 10);
}

// ---------------------------------------------------------------------- O -
// End-to-end: real generated images, real gateImage() verdicts.
{
  const dir = mkdtempSync(join(tmpdir(), 'hw-measure-'));
  writeFixtures(dir);
  const bytes = (name) => readFileSync(join(dir, name));

  const cleanStats = computeImageStats(bytes('hw_clean.png'));
  const blurStats = computeImageStats(bytes('hw_blur.png'));
  const skewStats = computeImageStats(bytes('hw_skew.png'));

  check('O real', 'a real generated clean worksheet passes the gate',
    gateImage(cleanStats).ok, 'true');
  checkTrue('O real', `clean sharpness (${cleanStats.sharpness.toFixed(1)}) clears MIN_SHARPNESS`,
    cleanStats.sharpness >= MIN_SHARPNESS);
  checkTrue('O real', 'clean clipping stays under MAX_CLIPPING (off-white bg, not digital-pure)',
    cleanStats.clipping <= MAX_CLIPPING);

  check('O real', 'a real deliberately-blurred worksheet is refused',
    gateImage(blurStats).reason, 'too_blurred');
  checkTrue('O real', `blurred sharpness (${blurStats.sharpness.toFixed(2)}) is far below clean`,
    blurStats.sharpness < cleanStats.sharpness / 10);

  check('O real', 'a real deliberately-8deg-skewed worksheet is refused',
    gateImage(skewStats).reason, 'too_skewed');
  checkTrue('O real', `measured skew magnitude (${skewStats.skewDegrees}deg) exceeds MAX_SKEW_DEG`,
    Math.abs(skewStats.skewDegrees) > MAX_SKEW_DEG);
  checkTrue('O real', 'measured skew is in the right ballpark of the real 8deg rotation applied',
    Math.abs(Math.abs(skewStats.skewDegrees) - 8) <= 3);

  // gateImage() only returns `deskewBy` on an ok:true verdict (capture.ts),
  // so a refused (too_skewed) verdict has none to read — but its formula
  // (`deskewBy = -skewDegrees`) is exactly what it WOULD have been, and
  // that's what capture-route.ts's own pipeline applies pre-OCR once the
  // photo would otherwise pass. Applying that same correction here and
  // re-measuring proves it actually straightens the page, not just that the
  // formula is copied correctly: a crooked page's edges are still real
  // edges, just misaligned with the row/column grid the Laplacian samples
  // on, and straightening is what recovers gate-passing sharpness (and, in
  // the real pipeline, OCR token recovery — see capture-route.test.mjs).
  const straightened = deskewToPng(bytes('hw_skew.png'), -skewStats.skewDegrees);
  const straightStats = computeImageStats(straightened);
  check('O real', 'deskewing the skewed fixture by its own measured correction passes the gate',
    gateImage(straightStats).ok, 'true');
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
