#!/usr/bin/env bash
# ============================================================================
#  verify-finish.sh -- the last two steps of tools/verify.sh: the MARKUP/DEMO correspondence check and the totals.
#
#  verify.sh ends with `exec bash tools/verify-finish.sh <passed> <failed> <problems>` (what its suites summed to).
#  It is a separate script so the gate's decisions can be tested without booting a database, a Flutter toolchain and
#  an Android SDK (tools/test/verify_finish.test.mjs runs it with synthetic counts).
#
#  What it decides (ISS-023):
#    - When EVERY suite passed (problems = 0, failed = 0) the total is final. C7 and D2 compare the two figures that
#      quote it (MARKUP.html, the demo manifest) against it, strictly, on every branch and on main. An APPLY line is
#      printed so whoever sees the mismatch can fix the two figures with one command instead of hand-typing them:
#          APPLY  node tools/apply-total.mjs <total>
#    - When ANY suite failed or ran nothing, the total is not final (a failed suite pulls it down), so C7 and D2 are
#      SKIPPED, not failed, and no APPLY line is printed. Before this, one failing suite read as three failures (the
#      suite, then C7, then D2) and sent people to edit two figures that were fine.
#    - The run is NOT GREEN whenever anything failed. Skipping C7/D2 never turns a red run green.
# ============================================================================
set -u
cd "$(dirname "$0")/.."
TOTAL_PASS="${1:?passed}"; TOTAL_FAIL="${2:?failed}"; PROBLEMS="${3:?problems}"
case "$TOTAL_PASS$TOTAL_FAIL$PROBLEMS" in *[!0-9]*) echo "verify-finish: arguments must be integers"; exit 2;; esac

FINAL=0
[ "$PROBLEMS" = "0" ] && [ "$TOTAL_FAIL" = "0" ] && FINAL=1

echo ""
echo "── MARKUP ↔ CHANGELOG ↔ DEMO correspondence ──────────────────"
# Standing rule: the visual MARKUP amends in step with the CHANGELOG. The total is passed in so C7 compares MARKUP's
# quoted figure against what was actually computed above, rather than against a number typed into a document.
if [ "$FINAL" = "1" ]; then MK_ARGS=(--total "$TOTAL_PASS"); else MK_ARGS=(--skip-total); fi
MK_OUT="${TMPDIR:-/tmp}/mk.out"
if node tools/check-markup.mjs "${MK_ARGS[@]}" >"$MK_OUT" 2>&1; then
  echo "  markup correspondence      $(grep -c 'PASS' "$MK_OUT") passed      0 failed"
  [ "$FINAL" = "1" ] || echo "  (C7/D2, the assertion-count checks, were skipped: a suite failed, so the total is not final)"
else
  grep -E '^  (PASS|FAIL|SKIP)' "$MK_OUT" | sed 's/^/  /'
  echo "  MARKUP DRIFT — see above"; PROBLEMS=$((PROBLEMS+1))
fi

echo ""
echo "──────────────────────────────────────────────────────────────"
printf "  %-26s %5s passed  %5s failed\n" "COMPUTED TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL"
if [ "$FINAL" = "1" ]; then
  echo "  APPLY  node tools/apply-total.mjs $TOTAL_PASS"
else
  echo "  APPLY  withheld: a suite failed or ran nothing, so this total is not final"
fi
if [ "$PROBLEMS" = "0" ] && [ "$TOTAL_FAIL" = "0" ]; then
  echo "  ALL GREEN"; exit 0
else
  echo "  NOT GREEN — $PROBLEMS suite(s) failed or ran nothing"; exit 1
fi
