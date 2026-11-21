#!/usr/bin/env bash
# ============================================================================
#  slot.sh -- the heavy-job slot lock, as a tool instead of a convention.
#
#  Two heavy jobs (flutter test, node suites, builds) may run at once on the
#  shared build machine. A slot is a DIRECTORY under the lock root:
#
#      <root>/slot1/        <- mkdir is the atomic "take" (it fails if present)
#          stamp            <- UTC time the slot was taken / last renewed
#          owner            <- who holds it (a label you choose, never a login)
#
#  The old convention was a raw `mkdir` plus `echo` by hand, which nobody could
#  inspect, which left half-written (unstamped) locks behind, and which made
#  "is that lock dead?" a judgement call. This script makes it mechanical.
#
#  USAGE
#    slot.sh acquire [1|2|any] --owner NAME [--wait SECONDS]
#    slot.sh renew   N --owner NAME        refresh the stamp of a long job
#    slot.sh release N --owner NAME        remove YOUR lock
#    slot.sh status                        one line per slot
#
#  RULES it enforces
#    - acquire never takes over a held slot. A stale one is REPORTED, not removed.
#    - release only removes a lock whose owner matches --owner. Anything else is
#      refused (exit 3) -- including a stale one. Locks you did not create are
#      not yours to remove; report them (status shows STALE) and tell the owner.
#    - STALE means: stamp older than SLOT_STALE_MIN (default 90) AND no
#      flutter/dart/node test process is running. An old stamp with a test still
#      running is HELD (the job is just long: use `renew`). A lock with no
#      readable stamp is never "fresh": it is UNSTAMPED, held until its directory
#      is older than the stale window and nothing is running.
#
#  EXIT CODES   0 ok   1 slot(s) busy / not acquired   2 usage error   3 refused
#
#  ENVIRONMENT
#    OLIVE_LOCK_DIR        lock root shared by every worktree that takes a slot: set it to the one
#                          directory this machine agrees on. Unset, a per-user temp directory is used,
#                          so checkouts that did not agree on a root do NOT see each other.
#    SLOT_STALE_MIN        stale window, minutes (default 90)
#    SLOT_COUNT            number of slots       (default 2)
#    SLOT_PROC_LIST_FILE   test hook: file of process command lines to use
#                          instead of asking the OS
# ============================================================================
set -u
ROOT="${OLIVE_LOCK_DIR:-${TMPDIR:-/tmp}/olive-slot-locks}"
STALE_MIN="${SLOT_STALE_MIN:-90}"
COUNT="${SLOT_COUNT:-2}"

die() { echo "slot.sh: $*" >&2; exit 2; }
now_epoch() { date -u +%s; }
now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

# epoch of the stamp file's content, or empty when absent/unparseable
stamp_epoch() {
  local f="$1/stamp" raw
  [ -f "$f" ] || return 0
  raw=$(head -n1 "$f" 2>/dev/null | tr -d '\r')
  [ -n "$raw" ] || return 0
  date -u -d "$raw" +%s 2>/dev/null || true
}
# directory mtime as epoch (fallback age when the stamp is unusable)
dir_epoch() { stat -c %Y "$1" 2>/dev/null || date -u -r "$1" +%s 2>/dev/null || true; }

# Command lines of running processes that mean "a test/build job is alive".
# The OS probe costs seconds on Windows and slot_state runs in $( ) subshells, so the answer
# is cached in a temp file (created here in the parent shell, removed on exit).
PROC_CACHE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/slot-procs.$$")"
trap 'rm -f "$PROC_CACHE"' EXIT
test_running() {
  local list
  if [ -s "$PROC_CACHE" ]; then list=$(cat "$PROC_CACHE")
  elif [ -n "${SLOT_PROC_LIST_FILE:-}" ]; then
    list=$(cat "$SLOT_PROC_LIST_FILE" 2>/dev/null)
  else
    case "$(uname -s 2>/dev/null)" in
      MINGW*|MSYS*|CYGWIN*)
        list=$(powershell.exe -NoProfile -NonInteractive -Command \
          "Get-CimInstance Win32_Process | Where-Object { \$_.Name -match '^(node|dart|flutter_tester|flutter|java)(\\.exe)?\$' } | ForEach-Object { \$_.CommandLine }" \
          2>/dev/null | tr -d '\r') ;;
      *) list=$(ps -eo args 2>/dev/null) ;;
    esac
  fi
  [ -s "$PROC_CACHE" ] || { printf '#probed
%s
' "$list" > "$PROC_CACHE"; }
  printf '%s\n' "$list" \
    | grep -v -E 'Get-CimInstance|slot\.sh|grep ' \
    | grep -q -E 'flutter_tester|flutter(\.bat)?[" ]+test|flutter_tools\.snapshot.* test|dart(\.exe)?"? .*\btest\b|\.test\.mjs|node(\.exe)?"? --test|\.test\.(js|ts)\b|gradle(w)?(\.bat)?[" ]+.*(test|assemble|build)'
}

# prints: FREE | HELD <owner> <age_min> | STALE <owner> <age_min> | UNSTAMPED <owner> <age_min>
slot_state() {
  local d="$1" owner="-" ep age_min kind=HELD
  [ -d "$d" ] || { echo "FREE - 0"; return; }
  [ -f "$d/owner" ] && owner=$(head -n1 "$d/owner" | tr -d '\r')
  [ -n "$owner" ] || owner="-"
  ep=$(stamp_epoch "$d")
  if [ -z "$ep" ]; then ep=$(dir_epoch "$d"); kind=UNSTAMPED; fi
  if [ -z "$ep" ]; then echo "UNSTAMPED $owner ?"; return; fi
  age_min=$(( ( $(now_epoch) - ep ) / 60 )); [ "$age_min" -lt 0 ] && age_min=0
  if [ "$age_min" -ge "$STALE_MIN" ] && ! test_running; then echo "STALE $owner $age_min"; return; fi
  echo "$kind $owner $age_min"
}

parse_owner() { # sets OWNER from args; remaining in ARGS
  OWNER="${OLIVE_SLOT_OWNER:-}"; WAIT=0; ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --owner) [ $# -ge 2 ] || die "--owner needs a value"; OWNER="$2"; shift 2 ;;
      --wait)  [ $# -ge 2 ] || die "--wait needs seconds"; WAIT="$2"; shift 2 ;;
      *) ARGS+=("$1"); shift ;;
    esac
  done
  case "$WAIT" in ''|*[!0-9]*) die "--wait must be whole seconds" ;; esac
}
valid_owner() { # a label, not a path and not empty
  case "$1" in ''|*/*|*\\*|*..*) return 1 ;; esac
  printf '%s' "$1" | grep -q -E '^[A-Za-z0-9._-]{1,64}$'
}
valid_slot() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge 1 ] && [ "$1" -le "$COUNT" ]; }

cmd_status() {
  mkdir -p "$ROOT" 2>/dev/null || die "cannot create lock root"
  local n st
  for n in $(seq 1 "$COUNT"); do
    st=$(slot_state "$ROOT/slot$n")
    set -- $st
    case "$1" in
      FREE) echo "slot$n FREE" ;;
      HELD) echo "slot$n HELD owner=$2 age=${3}m" ;;
      UNSTAMPED) echo "slot$n UNSTAMPED owner=$2 age=${3}m (no readable stamp; treated as held)" ;;
      STALE) echo "slot$n STALE owner=$2 age=${3}m (older than ${STALE_MIN}m and no test process running; REPORT it, do not remove a lock you did not create)" ;;
    esac
  done
}

try_take() { # N -> 0 taken
  local n="$1" d="$ROOT/slot$1"
  mkdir "$d" 2>/dev/null || return 1
  now_iso > "$d/stamp"
  printf '%s\n' "$OWNER" > "$d/owner"
  return 0
}

cmd_acquire() {
  parse_owner "$@"
  valid_owner "$OWNER" || die "acquire needs --owner NAME (letters, digits, . _ -; a label, not a login)"
  local want="${ARGS[0]:-any}" deadline n st
  mkdir -p "$ROOT" 2>/dev/null || die "cannot create lock root"
  [ "$want" = any ] || valid_slot "$want" || die "slot must be 1..$COUNT or 'any'"
  deadline=$(( $(now_epoch) + WAIT ))
  while :; do
    for n in $(seq 1 "$COUNT"); do
      [ "$want" = any ] || [ "$want" = "$n" ] || continue
      if try_take "$n"; then echo "ACQUIRED slot$n owner=$OWNER stamp=$(head -n1 "$ROOT/slot$n/stamp")"; return 0; fi
    done
    [ "$(now_epoch)" -ge "$deadline" ] && break
    sleep 5
  done
  echo "BUSY: no slot acquired" >&2
  for n in $(seq 1 "$COUNT"); do
    [ "$want" = any ] || [ "$want" = "$n" ] || continue
    st=$(slot_state "$ROOT/slot$n"); set -- $st
    case "$1" in
      STALE) echo "  slot$n is STALE (owner=$2, ${3}m old, nothing running). Not removed: report it to its owner." >&2 ;;
      *)     echo "  slot$n $1 owner=$2 age=${3}m" >&2 ;;
    esac
  done
  return 1
}

cmd_renew() {
  parse_owner "$@"; local n="${ARGS[0]:-}"
  valid_slot "$n" || die "renew needs a slot number 1..$COUNT"
  valid_owner "$OWNER" || die "renew needs --owner NAME"
  local d="$ROOT/slot$n"
  [ -d "$d" ] || { echo "slot$n is not held" >&2; return 3; }
  [ "$(head -n1 "$d/owner" 2>/dev/null | tr -d '\r')" = "$OWNER" ] || { echo "REFUSED: slot$n is not owned by $OWNER" >&2; return 3; }
  now_iso > "$d/stamp"; echo "RENEWED slot$n"
}

cmd_release() {
  parse_owner "$@"; local n="${ARGS[0]:-}"
  valid_slot "$n" || die "release needs a slot number 1..$COUNT"
  valid_owner "$OWNER" || die "release needs --owner NAME (only the creator may remove a lock)"
  local d="$ROOT/slot$n" cur st
  [ -d "$d" ] || { echo "slot$n is already free"; return 0; }
  cur=$(head -n1 "$d/owner" 2>/dev/null | tr -d '\r')
  if [ "$cur" != "$OWNER" ]; then
    st=$(slot_state "$d"); set -- $st
    echo "REFUSED: slot$n is owned by '${cur:--}', not '$OWNER' ($1, ${3}m old). A lock you did not create is not yours to remove." >&2
    return 3
  fi
  rm -f "$d/stamp" "$d/owner" && rmdir "$d" && echo "RELEASED slot$n"
}

case "${1:-}" in
  acquire) shift
          [ -n "${OLIVE_LOCK_DIR:-}" ] || echo "slot.sh: OLIVE_LOCK_DIR is not set; using $ROOT, which other checkouts do not share. Set it to the machine's one agreed lock directory." >&2
          cmd_acquire "$@" ;;
  renew)   shift; cmd_renew "$@" ;;
  release) shift; cmd_release "$@" ;;
  status)  shift; cmd_status ;;
  *) sed -n '2,38p' "$0" | sed 's/^# \{0,2\}//' >&2; exit 2 ;;
esac
