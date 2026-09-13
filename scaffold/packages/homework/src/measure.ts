/**
 * MASTERFILE §9.1 / §20.2b — REAL ImageStats from real photo bytes.
 *
 * §20.2b's own "still missing" table named this exactly: "OCR: Homework
 * capture specified, not built." capture.ts's gateImage() has been real and
 * unit-tested from day one, but every one of its tests hand-typed an
 * ImageStats object — nothing in the repository ever computed one from an
 * actual photo. This file is that computation, for real, off real bytes.
 *
 * DECODING. PNG via `pngjs`, JPEG via `jpeg-js` — both pure JavaScript, no
 * native binary, no prebuilt-binary-per-platform risk. This was checked, not
 * assumed: `npm view sharp/canvas/pngjs/jpeg-js version` all resolved
 * against the real npm registry from this dev environment, but `sharp` and
 * `canvas` both ship a native addon that needs either a matching prebuilt
 * binary for the exact platform/Node ABI or a local C/C++ toolchain to
 * compile one — and this box has neither ImageMagick nor any other system
 * image library already on it to notice a mismatch against. pngjs + jpeg-js
 * sidestep that whole failure class and decode identically on every OS this
 * repo's own tests run on (Windows here, Linux in CI), which matters more
 * for a "run everywhere, no external service" feature than raw speed does.
 *
 * THE THREE MEASURES. All three are approximations, documented as such right
 * at each function — none claims to be exact, matching capture.ts's own
 * "measured, not guessed" posture but for the SOURCE numbers this time,
 * not the thresholds:
 *   - sharpness: variance of the Laplacian over a greyscale-downsampled
 *     copy. A standard, cheap blur estimator — crisp edges produce large
 *     Laplacian swings and a high variance; blur softens edges toward the
 *     local mean and collapses the variance toward zero. Not a real MTF
 *     measurement, but it separates "clearly blurred" from "clearly sharp"
 *     by orders of magnitude, which is all gateImage's threshold needs.
 *   - clipping: fraction of greyscale pixels within a small tolerance band
 *     of pure black or pure white. Approximate on purpose — real
 *     overexposure rarely lands on exactly 0 or 255 once JPEG compression
 *     has touched it, hence the tolerance rather than an exact-match count.
 *   - skew: a projection-profile angle search — rotate candidate angles
 *     across a bounded range, score each by the variance of its per-row
 *     "ink" sum, keep the angle that maximises it. A level page's text lines
 *     produce sharp peaks and troughs in that profile; a skewed page smears
 *     ink across many rows and flattens it. A real, well-known technique
 *     (projection-profile skew estimation), not invented here — but
 *     approximate: bounded search range, nearest-neighbour sampling, and it
 *     can be fooled by an image with no real horizontal text structure.
 */
import { PNG } from 'pngjs';
import jpeg from 'jpeg-js';
import type { ImageStats } from './capture.ts';

export interface DecodedImage {
  width: number;
  height: number;
  /** RGBA, 4 bytes per pixel, row-major. */
  data: Uint8ClampedArray;
}

/**
 * Sniffs the real magic bytes rather than trusting a filename or a
 * client-supplied content-type, either of which an attacker (or just a
 * mislabelled upload) can lie about.
 */
export function decodeImage(bytes: Buffer | Uint8Array): DecodedImage {
  const b = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) {
    const png = PNG.sync.read(b); // pngjs always normalises to RGBA
    return { width: png.width, height: png.height, data: Uint8ClampedArray.from(png.data) };
  }
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    const img = jpeg.decode(b, { useTArray: true }); // jpeg-js also always outputs RGBA
    return { width: img.width, height: img.height, data: Uint8ClampedArray.from(img.data as Uint8Array) };
  }
  throw new Error('unsupported_image_format: expected PNG or JPEG magic bytes');
}

export function encodePNG(img: DecodedImage): Buffer {
  const png = new PNG({ width: img.width, height: img.height });
  png.data = Buffer.from(img.data.buffer, img.data.byteOffset, img.data.length);
  return PNG.sync.write(png);
}

// ------------------------------------------------------------ greyscale ---
function toGreyscale(img: DecodedImage): Float64Array {
  const { width, height, data } = img;
  const out = new Float64Array(width * height);
  for (let i = 0, p = 0; i < out.length; i++, p += 4) {
    out[i] = 0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2]; // standard luma weights
  }
  return out;
}

/**
 * Nearest-neighbour downsample to at most `maxEdge` on the long side.
 * Deliberately cheap, not high-quality — these measures need coarse
 * structure (where the edges/ink roughly are), not photographic fidelity.
 */
function downsampleGrey(
  grey: Float64Array, w: number, h: number, maxEdge: number,
): { grey: Float64Array; w: number; h: number } {
  const longest = Math.max(w, h);
  if (longest <= maxEdge) return { grey, w, h };
  const scale = maxEdge / longest;
  const nw = Math.max(1, Math.round(w * scale));
  const nh = Math.max(1, Math.round(h * scale));
  const out = new Float64Array(nw * nh);
  for (let y = 0; y < nh; y++) {
    const sy = Math.min(h - 1, Math.floor(y / scale));
    for (let x = 0; x < nw; x++) {
      const sx = Math.min(w - 1, Math.floor(x / scale));
      out[y * nw + x] = grey[sy * w + sx];
    }
  }
  return { grey: out, w: nw, h: nh };
}

// ------------------------------------------------------------ sharpness ---
/**
 * Variance of the Laplacian (4-neighbour kernel [[0,1,0],[1,-4,1],[0,1,0]])
 * over the interior of a greyscale image. See file header for what this
 * approximates and why. Unnormalised 0..255 scale — capture.ts's
 * MIN_SHARPNESS is a threshold on exactly this function's output.
 */
export function laplacianVariance(grey: Float64Array, w: number, h: number): number {
  if (w < 3 || h < 3) return 0;
  let n = 0, sum = 0, sumSq = 0;
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = y * w + x;
      const lap = 4 * grey[i] - grey[i - 1] - grey[i + 1] - grey[i - w] - grey[i + w];
      sum += lap; sumSq += lap * lap; n++;
    }
  }
  if (n === 0) return 0;
  const mean = sum / n;
  return sumSq / n - mean * mean;
}

// ------------------------------------------------------------- clipping ---
/** Fraction of pixels within `tolerance` of pure black or pure white. See file header. */
export function clippingFraction(grey: Float64Array, tolerance = 4): number {
  if (grey.length === 0) return 0;
  let clipped = 0;
  for (let i = 0; i < grey.length; i++) {
    if (grey[i] <= tolerance || grey[i] >= 255 - tolerance) clipped++;
  }
  return clipped / grey.length;
}

// ----------------------------------------------------------------- skew ---
/**
 * Sum of "ink" (255 - grey, so dark pixels count and white background does
 * not) per output row, for the image conceptually rotated by `deg` around
 * its own centre and sampled by nearest-neighbour. Out-of-bounds source
 * samples (the rotated corners) are treated as background — zero ink,
 * matching the white canvas a real deskew/rotate would fill with.
 */
function rowInkSums(grey: Float64Array, w: number, h: number, deg: number): Float64Array {
  const rad = (deg * Math.PI) / 180;
  const cos = Math.cos(rad), sin = Math.sin(rad);
  const cx = w / 2, cy = h / 2;
  const sums = new Float64Array(h);
  for (let y = 0; y < h; y++) {
    const dy = y - cy;
    let sum = 0;
    for (let x = 0; x < w; x++) {
      const dx = x - cx;
      const sx = Math.round(cx + dx * cos + dy * sin);
      const sy = Math.round(cy - dx * sin + dy * cos);
      if (sx >= 0 && sx < w && sy >= 0 && sy < h) sum += 255 - grey[sy * w + sx];
    }
    sums[y] = sum;
  }
  return sums;
}

function variance(xs: Float64Array): number {
  if (xs.length === 0) return 0;
  let sum = 0; for (const x of xs) sum += x;
  const mean = sum / xs.length;
  let sq = 0; for (const x of xs) sq += (x - mean) * (x - mean);
  return sq / xs.length;
}

/**
 * Projection-profile skew estimate. Searches [-maxDeg, maxDeg] in `stepDeg`
 * increments; `bestDeg` is the angle that — when fed back into THIS FILE'S
 * OWN `rowInkSums`/`rotateImage` sampling — best straightens the page (its
 * rotated row-ink-sum profile has the highest variance, i.e. text rows read
 * as sharp peaks and troughs rather than a smear). See file header for the
 * approximation caveats.
 *
 * The return value is `-bestDeg`, not `bestDeg` — deliberately. capture.ts's
 * gateImage() defines `deskewBy = -skewDegrees` and this repo's tests
 * exercise that contract, so `skewDegrees` here has to mean "the rotation
 * that was applied to the page", i.e. the value whose OWN negation (fed to
 * `rotateImage`) straightens it — not "the rotation that straightens it"
 * directly, which is what `bestDeg` itself already is. Confirmed empirically
 * in measure.test.mjs: `rotateImage(img, gateImage(computeImageStats(img)).
 * deskewBy)` on a deliberately-skewed fixture recovers OCR tokens the raw
 * skewed image does not.
 */
export function estimateSkewDegrees(
  grey: Float64Array, w: number, h: number, maxDeg = 12, stepDeg = 0.5,
): number {
  let bestDeg = 0, bestScore = -Infinity;
  for (let deg = -maxDeg; deg <= maxDeg + 1e-9; deg += stepDeg) {
    const score = variance(rowInkSums(grey, w, h, deg));
    if (score > bestScore) { bestScore = score; bestDeg = deg; }
  }
  // One decimal place: the search step is 0.5deg, so anything finer would be
  // false precision, not a more accurate answer.
  return Math.round(-bestDeg * 10) / 10;
}

// -------------------------------------------------------- the entry point -
/**
 * Real ImageStats from a real photo's bytes — the piece §20.2b's OCR row
 * named as missing. gateImage() (capture.ts) has been real from the start;
 * this is what actually produces its input outside of a test's own literal.
 *
 * Sharpness and skew run on a greyscale-downsampled copy, per the task this
 * file exists to close ("sharpness via variance-of-Laplacian over a
 * greyscale-downsampled version"); clipping runs on the full-resolution
 * greyscale so a small bright/dark region isn't diluted away by resampling.
 */
export function computeImageStats(bytes: Buffer | Uint8Array): ImageStats {
  const img = decodeImage(bytes);
  const fullGrey = toGreyscale(img);

  const { grey: sGrey, w: sw, h: sh } = downsampleGrey(fullGrey, img.width, img.height, 700);
  const { grey: kGrey, w: kw, h: kh } = downsampleGrey(fullGrey, img.width, img.height, 300);

  return {
    widthPx: img.width,
    heightPx: img.height,
    sharpness: laplacianVariance(sGrey, sw, sh),
    clipping: clippingFraction(fullGrey),
    skewDegrees: estimateSkewDegrees(kGrey, kw, kh),
  };
}

// ------------------------------------------------------------- deskew -----
/**
 * Rotates the decoded image by `degrees` around its centre (nearest-
 * neighbour sampling, white-filled background) and re-encodes to PNG. Used
 * by the capture route to apply gateImage()'s own `deskewBy` before OCR
 * runs. Approximate for the same reason estimateSkewDegrees() is (see file
 * header) — this recovers the token loss capture.ts's own calibration table
 * documents for small angles, it is not a general-purpose image-rotation
 * utility and was not built to be one.
 */
export function deskewToPng(bytes: Buffer | Uint8Array, degrees: number): Buffer {
  const img = decodeImage(bytes);
  if (degrees === 0) return encodePNG(img);
  return encodePNG(rotateImage(img, degrees));
}

/**
 * Exported so the test fixture generator (packages/homework/test/
 * gen-fixtures.mjs) can synthesise a deliberately-skewed worksheet with the
 * exact same rotation this file itself uses to correct one — one rotation
 * implementation, not two that could drift apart.
 */
export function rotateImage(img: DecodedImage, degrees: number): DecodedImage {
  const rad = (degrees * Math.PI) / 180;
  const cos = Math.cos(rad), sin = Math.sin(rad);
  const { width: w, height: h, data } = img;
  const out = new Uint8ClampedArray(w * h * 4).fill(255); // white background, opaque
  const cx = w / 2, cy = h / 2;
  for (let y = 0; y < h; y++) {
    const dy = y - cy;
    for (let x = 0; x < w; x++) {
      const dx = x - cx;
      const sx = Math.round(cx + dx * cos + dy * sin);
      const sy = Math.round(cy - dx * sin + dy * cos);
      if (sx >= 0 && sx < w && sy >= 0 && sy < h) {
        const si = (sy * w + sx) * 4, di = (y * w + x) * 4;
        out[di] = data[si]; out[di + 1] = data[si + 1];
        out[di + 2] = data[si + 2]; out[di + 3] = data[si + 3];
      }
      // else: stays white — already filled above.
    }
  }
  return { width: w, height: h, data: out };
}
