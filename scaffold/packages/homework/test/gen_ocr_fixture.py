#!/usr/bin/env python3
"""OLIVE BRANCH -- realistic OCR test-fixture generator. MASTERFILE Sec 9.1, Sec 20.2b.

Companion to gen-fixtures.mjs (pure JS, hand-rolled bitmap font): that
generator is good enough for measure.test.mjs's numeric sharpness/skew
classification (clean vs. deliberately-blurred vs. deliberately-skewed
differ by orders of magnitude either way), but its hard-edged dot-matrix
font recognises noticeably worse than a real, properly-hinted, anti-aliased
TrueType font -- Tesseract is trained on ordinary font rendering, not
blocky pixel fonts, and a real font is what the OCR-route test needs to
prove "a real photo in, real recognizable text out" convincingly rather
than marginally.

This is a REAL, DECLARED toolchain dependency (Python 3 + Pillow), the same
posture packages/homework/test/make-fixtures.sh already takes for
ImageMagick + the tesseract CLI, and tools/verify.sh already takes for
Flutter/the Android SDK/LiveKit: "MISSING TOOLCHAIN -- not a skip, a gap"
rather than silently avoiding the dependency. If this script can't import
PIL or find a usable TrueType font, it exits non-zero with a plain message
instead of pretending to produce a fixture.

Background/ink are deliberately off-white/near-black, not pure
(255,255,255)/(0,0,0) -- see gen-fixtures.mjs's own header for why a
digitally-pure-white background makes measure.ts's clippingFraction()
(correctly) flag the image as 99%+ "clipped", which is a property of a real
photo's pure-digital-white synthetic images, not a bug in the measurement.
"""
import sys

try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
except ImportError:
    print("MISSING TOOLCHAIN: Python Pillow (PIL) not importable -- "
          "gen_ocr_fixture.py cannot run. Not a skip, a gap.", file=sys.stderr)
    sys.exit(2)

BG = (236, 234, 230)
INK = (12, 12, 16)

FONT_CANDIDATES = [
    "arial.ttf",
    "C:\\Windows\\Fonts\\arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "DejaVuSans-Bold.ttf",
]


def _font(size):
    for candidate in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(candidate, size)
        except Exception:
            continue
    print("MISSING TOOLCHAIN: no usable TrueType font found among "
          f"{FONT_CANDIDATES} -- gen_ocr_fixture.py cannot run.", file=sys.stderr)
    sys.exit(2)


WORKSHEET_LINES = [
    "1. 12 + 27 = ____",
    "2. 4 - 9 = ____",
    "3. 6 x 7 = ____",
]


def render(lines, size=72):
    f = _font(size)
    line_h = int(size * 1.7)
    img = Image.new("RGB", (1400, line_h * len(lines) + 100), BG)
    d = ImageDraw.Draw(img)
    y = 60
    for line in lines:
        d.text((60, y), line, fill=INK, font=f)
        y += line_h
    return img


def write_fixtures(out_dir):
    clean = render(WORKSHEET_LINES)
    clean.save(f"{out_dir}/hw_clean.png")

    blurred = clean.filter(ImageFilter.GaussianBlur(radius=10))
    blurred.save(f"{out_dir}/hw_blur.png")

    # 8deg -- the exact angle capture.ts's own calibration table measures at
    # "already loses two thirds of tokens".
    skewed = clean.rotate(8, expand=True, fillcolor=BG, resample=Image.BICUBIC)
    skewed.save(f"{out_dir}/hw_skew.png")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: gen_ocr_fixture.py <output-dir>", file=sys.stderr)
        sys.exit(1)
    write_fixtures(sys.argv[1])
    print("wrote fixtures to", sys.argv[1])
