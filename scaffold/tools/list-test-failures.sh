#!/usr/bin/env bash
# ============================================================================
#  list-test-failures.sh -- name every failing test in a `flutter test
#  --reporter compact` log.
#
#  Why this exists: verify.sh used to print the tests after a line reading
#  "Failing tests:" -- a section the compact reporter NEVER emits. The sed
#  matched nothing, so a red CI run said "2 failed" and named neither, which
#  nobody can root-cause from a log. What the reporter really prints is one
#  progress line per state change, each prefixed "<mm:ss> +<passed> -<failed>:",
#  and a failing test's line ends in " [E]":
#
#      00:04 +1 -1: grp this one fails -2 odd name [E]
#
#  (progress lines overwrite each other with a bare \r on a terminal; captured
#  they are still \r-separated, so \r is turned into \n first.)
#
#  Usage:   list-test-failures.sh [LOGFILE]        (reads stdin if no file)
#  Output:  one "FAILED: <test name>" line per failing test, de-duplicated, in
#           first-seen order. A file that fails to even load/compile shows up
#           as "FAILED: loading <path>".
#  Exit:    0  names listed, or the log shows no failures at all
#           3  the log's final counter says tests failed but NO name could be
#              extracted (the caller must fall back to the raw log -- never
#              report a bare count)
#           2  usage / unreadable file
#  Only anchored, reporter-generated structure is parsed (the "mm:ss +P -F:"
#  prefix and the trailing " [E]"), never a bare "-N" or "[E]" anywhere in a
#  line, so a test whose own NAME contains "-2" or "[E]" cannot confuse it.
# ============================================================================
set -u
if [ "$#" -gt 1 ]; then echo "usage: $0 [LOGFILE]" >&2; exit 2; fi
if [ "$#" -eq 1 ]; then
  [ -r "$1" ] || { echo "list-test-failures: cannot read $1" >&2; exit 2; }
  src=$(cat "$1")
else
  src=$(cat)
fi
lines=$(printf '%s' "$src" | tr '\r' '\n')

names=$(printf '%s\n' "$lines" \
  | sed -n -E 's/^[0-9]+:[0-9]+ \+[0-9]+ -[0-9]+: (.*[^ ]) +\[E\] *$/\1/p' \
  | awk '!seen[$0]++')

if [ -n "$names" ]; then
  printf '%s\n' "$names" | sed 's/^/FAILED: /'
  exit 0
fi

# No named failure. Is the reporter's final counter still showing failures?
last=$(printf '%s\n' "$lines" | grep -E '^[0-9]+:[0-9]+ \+[0-9]+( -[0-9]+)?:' | tail -1)
if printf '%s' "$last" | grep -qE '^[0-9]+:[0-9]+ \+[0-9]+ -[1-9][0-9]*:'; then
  exit 3
fi
exit 0
