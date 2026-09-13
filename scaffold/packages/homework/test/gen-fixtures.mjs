#!/usr/bin/env node
// OLIVE BRANCH — self-contained OCR test-fixture generator. MASTERFILE §9.1,
// §20.2b.
//
// packages/homework/test/make-fixtures.sh (pre-existing, untouched by this
// change) shells out to ImageMagick's `magick`/`convert` and to the real
// `tesseract` binary. Neither is guaranteed to be on a given machine — this
// dev session's own box has a real Tesseract-OCR install but NO ImageMagick
// at all (`magick`/`convert` both absent; Windows' own unrelated
// system32\convert.exe would silently swallow ImageMagick-style arguments if
// naively resolved by name). Rather than add a second system-tool dependency
// this repo can't yet promise every dev/CI box has, this generator draws its
// own worksheet images in pure JS: a small hand-built 5x7 bitmap font,
// rendered directly into an RGBA buffer and encoded with `pngjs` (the same
// decoder measure.ts already depends on), blurred with a real box-blur
// convolution, and skewed with measure.ts's own `rotateImage` — so the
// skew fixture is rotated by the EXACT function gateImage's `deskewBy` is
// later asked to undo, not a second, possibly-inconsistent implementation.
//
// Background/ink colours are deliberately NOT pure (255,255,255)/(0,0,0):
// a synthetic image drawn in pure digital white is not what a real camera
// photo of a paper worksheet looks like (sensor noise and non-flash ambient
// light mean real "white" paper reads well under 255), and measure.ts's
// clippingFraction() correctly flags a flat pure-white plateau as 99%+
// "clipped" — which is CORRECT behaviour for the function, not a bug to
// paper over by loosening the tolerance band. The fix belongs in the test
// fixture, matching what a real photo would actually look like, not in the
// measurement.
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { rotateImage, encodePNG } from '../src/measure.mjs';

const BG = [236, 234, 230]; // off-white paper, not digital-pure white
const INK = [12, 12, 16]; // near-black ink, not digital-pure black

// ---------------------------------------------------------------- font ---
// 5x7 dot-matrix glyphs, '#' = ink. Only the characters this test suite's
// worksheets actually use.
const FONT = {
  '0': [' ### ', '#   #', '#  ##', '# # #', '##  #', '#   #', ' ### '],
  '1': ['  #  ', ' ##  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
  '2': [' ### ', '#   #', '    #', '   # ', '  #  ', ' #   ', '#####'],
  '3': [' ### ', '#   #', '    #', '  ## ', '    #', '#   #', ' ### '],
  '4': ['   # ', '  ## ', ' # # ', '#  # ', '#####', '   # ', '   # '],
  '5': ['#####', '#    ', '#### ', '    #', '    #', '#   #', ' ### '],
  '6': [' ### ', '#    ', '#### ', '#   #', '#   #', '#   #', ' ### '],
  '7': ['#####', '    #', '   # ', '  #  ', ' #   ', ' #   ', ' #   '],
  '8': [' ### ', '#   #', '#   #', ' ### ', '#   #', '#   #', ' ### '],
  '9': [' ### ', '#   #', '#   #', ' ####', '    #', '   # ', ' ##  '],
  '+': ['     ', '  #  ', '  #  ', '#####', '  #  ', '  #  ', '     '],
  '-': ['     ', '     ', '     ', '#####', '     ', '     ', '     '],
  '=': ['     ', '     ', '#####', '     ', '#####', '     ', '     '],
  '/': ['    #', '   # ', '  #  ', '  #  ', ' #   ', '#    ', '     '],
  '.': ['     ', '     ', '     ', '     ', '     ', '  ## ', '  ## '],
  x: ['     ', '     ', '#   #', ' # # ', '  #  ', ' # # ', '#   #'],
  _: ['     ', '     ', '     ', '     ', '     ', '     ', '#####'],
  ' ': ['     ', '     ', '     ', '     ', '     ', '     ', '     '],
};

/**
 * Renders `lines` into a fresh RGBA image at `scale` px per font dot, then
 * applies one light smoothing pass.
 *
 * The smoothing pass matters for real, not cosmetically: an earlier version
 * of this generator fed Tesseract the raw hard-edged blocky raster directly,
 * and it measurably recognised WORSE than the deliberately heavily-blurred
 * fixture derived from it — the heavy blur's own smoothing was accidentally
 * doing this step's job better than no smoothing at all, which inverted the
 * whole point of the blur fixture existing (it's supposed to recognise
 * WORSE than clean, not better). Tesseract is trained on ordinarily
 * anti-aliased font rendering; a single small-radius box-blur pass softens
 * this hand-rolled dot font's hard block edges enough to read the same way,
 * while a much heavier version of the identical pass (see `boxBlur` below)
 * is what produces the deliberately-unreadable blurred fixture. Naive
 * supersample-then-box-downsample was tried first and does NOT work here —
 * every font "dot" is a uniform flat block with no sub-dot geometry, so
 * downsampling by exactly the dot's own supersample factor just re-averages
 * each dot back to its own flat colour with zero softening at the
 * boundaries; genuine inter-dot smoothing needs a blur kernel that spans
 * pixels on both sides of a dot edge, which is exactly what a post-render
 * box blur (unlike supersampling) does.
 */
export function renderWorksheet(lines, scale = 12, marginDots = 4) {
  // Each character advances 6 dot-columns (a 5-wide glyph + 1 dot gap) — the
  // canvas width must be sized off that advance, not off the character
  // count alone, or the last few characters of the longest line get
  // clipped off the right edge of the image.
  const cols = Math.max(...lines.map((l) => l.length)) * 6 + marginDots * 2;
  const rows = lines.length * 9 + marginDots * 2; // 7 dots/glyph + 2 dots row-gap
  const width = cols * scale, height = rows * scale;
  const data = new Uint8ClampedArray(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    data[i * 4] = BG[0]; data[i * 4 + 1] = BG[1]; data[i * 4 + 2] = BG[2]; data[i * 4 + 3] = 255;
  }
  const setDot = (px, py) => {
    for (let dy = 0; dy < scale; dy++) {
      for (let dx = 0; dx < scale; dx++) {
        const x = px * scale + dx, y = py * scale + dy;
        if (x < 0 || x >= width || y < 0 || y >= height) continue;
        const i = (y * width + x) * 4;
        data[i] = INK[0]; data[i + 1] = INK[1]; data[i + 2] = INK[2]; data[i + 3] = 255;
      }
    }
  };
  lines.forEach((line, li) => {
    const baseRow = marginDots + li * 9;
    [...line].forEach((ch, ci) => {
      const glyph = FONT[ch] ?? FONT[' '];
      const baseCol = marginDots + ci * 6;
      for (let gy = 0; gy < 7; gy++) {
        for (let gx = 0; gx < 5; gx++) {
          if (glyph[gy][gx] === '#') setDot(baseCol + gx, baseRow + gy);
        }
      }
    });
  });
  return boxBlur({ width, height, data }, 1, 1); // light anti-alias, see doc comment above
}

/** Real box-blur convolution, run several passes to approximate a Gaussian — strong enough that Tesseract recovers nothing, matching capture.ts's own measured blur-degradation table. */
export function boxBlur(img, radius = 6, passes = 3) {
  let { width, height, data } = img;
  for (let p = 0; p < passes; p++) {
    data = boxBlurPass(data, width, height, radius, true);  // horizontal
    data = boxBlurPass(data, width, height, radius, false); // vertical
  }
  return { width, height, data };
}

function boxBlurPass(data, width, height, radius, horizontal) {
  const out = new Uint8ClampedArray(data.length);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let r = 0, g = 0, b = 0, n = 0;
      for (let k = -radius; k <= radius; k++) {
        const sx = horizontal ? x + k : x;
        const sy = horizontal ? y : y + k;
        if (sx < 0 || sx >= width || sy < 0 || sy >= height) continue;
        const i = (sy * width + sx) * 4;
        r += data[i]; g += data[i + 1]; b += data[i + 2]; n++;
      }
      const i = (y * width + x) * 4;
      out[i] = r / n; out[i + 1] = g / n; out[i + 2] = b / n; out[i + 3] = 255;
    }
  }
  return out;
}

const WORKSHEET_LINES = [
  '1. 12 + 27 = ____',
  '2. 4 - 9 = ____',
  '3. 6 x 7 = ____',
];

/** Writes hw_clean.png / hw_blur.png / hw_skew.png into `dir`. Mirrors make-fixtures.sh's own filenames so both fixture sources are drop-in interchangeable for anything that only reads the files. */
export function writeFixtures(dir) {
  const clean = renderWorksheet(WORKSHEET_LINES);
  writeFileSync(`${dir}/hw_clean.png`, encodePNG(clean));

  const blurred = boxBlur(clean, 6, 3);
  writeFileSync(`${dir}/hw_blur.png`, encodePNG(blurred));

  // 8deg — the exact angle capture.ts's own calibration table measures at
  // "already loses two thirds of tokens", so a real skew estimate here
  // should land close to it and gateImage should refuse it pre-deskew.
  const skewed = rotateImage(clean, 8);
  writeFileSync(`${dir}/hw_skew.png`, encodePNG(skewed));

  return { clean, blurred, skewed, lines: WORKSHEET_LINES };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const dir = process.argv[2];
  if (!dir) { console.error('usage: node gen-fixtures.mjs <output-dir>'); process.exit(1); }
  mkdirSync(dir, { recursive: true });
  writeFixtures(dir);
  console.log('wrote fixtures to', dir);
}
