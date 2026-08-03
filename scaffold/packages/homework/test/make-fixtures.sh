#!/usr/bin/env bash
# Deterministic OCR fixture generator for the K · REAL OCR test group.
# Regenerated every test run — nothing here is committed as a binary.
set -euo pipefail

DIR="${1:?usage: make-fixtures.sh <output-dir>}"
mkdir -p "$DIR"

MAGICK=magick
command -v magick >/dev/null 2>&1 || MAGICK=convert

"$MAGICK" -size 1600x900 xc:white -gravity center -font Arial-Bold -pointsize 90 -fill black \
  -annotate +0-200 "2/3 + 1/5 = ____" \
  -annotate +0-50  "3/8 - 1/2 = ____" \
  -annotate +0+100 "12 + 27 = ____" \
  "$DIR/hw_clean.png"

"$MAGICK" "$DIR/hw_clean.png" -blur 0x12 "$DIR/hw_blur.png"

"$MAGICK" "$DIR/hw_clean.png" -background white -rotate 8 "$DIR/hw_skew.png"
