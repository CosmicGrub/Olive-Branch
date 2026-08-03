#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — sweep concurrency proof
#  Eight real workers race the same queue. A non-atomic claim shows up here as
#  a delivered count greater than the number of due intents.
# ============================================================================
set -u
PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
PORT=${PORT:-5433}
DB=${DB:-olive}
Q="$PGBIN/psql -h /tmp -p $PORT -U postgres -d $DB -q -t -A -c"
WORKERS=${WORKERS:-8}

say() { printf '%s\n' "$*"; }

# A test that passes when the database is unreachable is worse than no test.
# Every assertion goes through these, and an empty value is a hard failure.
FAILED=0
num() {  # num <label> -> echoes value, aborts the suite if not numeric
  local v; v=$($Q "$2" 2>/dev/null | tr -d '[:space:]')
  case "$v" in
    ''|*[!0-9]*) say "  ABORT  $1 — query returned '$v' (database unreachable?)"
                 FAILED=1; echo "" ;;
    *) echo "$v" ;;
  esac
}
expect() {  # expect <label> <actual> <wanted>
  if [ -z "$2" ]; then say "  FAIL  $1 — no value"; FAILED=1; return; fi
  if [ "$2" = "$3" ]; then say "  PASS  $1"; else
    say "  FAIL  $1 — expected $3, got $2"; FAILED=1; fi
}

$Q "SELECT 1;" >/dev/null 2>&1 || { say "ABORT: cannot reach $DB on port $PORT"; exit 2; }

say ""
say "=== SWEEP CONCURRENCY ($WORKERS parallel workers) ==================="

due=$(num "due count" "SELECT count(*) FROM delivery_intent WHERE state='ready' AND scheduled_at<=now() AND expires_at>now();")
say "  due intents               : $due"
[ -z "$due" ] && exit 2

# Race. Each worker drains in batches of 25 until the queue is empty.
for i in $(seq 1 "$WORKERS"); do
  (
    for _ in $(seq 1 40); do
      n=$($Q "SELECT count(*) FROM claim_due_intents(25);" 2>/dev/null)
      [ "${n:-0}" = "0" ] && break
    done
  ) > "/tmp/w$i.log" 2>&1 &
done
wait

delivered=$(num "delivered" "SELECT count(*) FROM delivery_intent WHERE batch_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' AND state='delivered';")
left=$(num "left due" "SELECT count(*) FROM delivery_intent WHERE state='ready' AND scheduled_at<=now();")
future=$(num "future" "SELECT count(*) FROM delivery_intent WHERE state='ready' AND scheduled_at>now();")

say "  delivered                 : $delivered"
expect "exactly-once: delivered == due" "$delivered" "$due"
expect "queue fully drained"            "$left"      "0"
expect "future-dated intents not swept" "$future"    "50"

say ""
say "=== RETENTION EXPIRY ==============================================="
exp=$(num "expired" "SELECT expire_stale_intents();")
expect "COPPA expiry swept exactly the stale rows" "$exp" "10"

say ""
say "=== §4.5 INVALIDATION ON ZONE CHANGE ==============================="
before_del=$(num "before delivered" "SELECT count(*) FROM delivery_intent WHERE batch_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' AND state='delivered';")
before_rdy=$(num "before ready" "SELECT count(*) FROM delivery_intent WHERE state='ready';")
say "  before: delivered=$before_del ready=$before_rdy"

# The child flies to Texas. This is the trigger firing, not an app-level call.
$Q "INSERT INTO child_tz_interval (child_id, tz, valid, source)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','America/Chicago',
            '[2026-12-20,2027-01-05)','custody');" >/dev/null

after_del=$(num "after delivered" "SELECT count(*) FROM delivery_intent WHERE batch_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' AND state='delivered';")
# Scoped to THIS batch. A global count makes the assertion depend on whatever
# else is in the database — which is how it broke when run after the constraint
# suite against a shared database.
after_pending=$(num "after pending" "SELECT count(*) FROM delivery_intent WHERE batch_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' AND state='pending' AND scheduled_at IS NULL;")
after_rdy=$(num "after ready" "SELECT count(*) FROM delivery_intent WHERE batch_id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' AND state='ready';")
say "  after : delivered=$after_del pending/unmaterialized=$after_pending ready=$after_rdy"

expect "DELIVERED messages are immutable - never re-timed" "$after_del" "$before_del"
expect "all 50 future intents invalidated"                 "$after_pending" "50"
expect "no stale scheduled_at survives a zone change"      "$after_rdy" "0"

say ""
say "=== BATCH PROGRESS VIEW (parent-facing only, §8.2.8) ================"
$PGBIN/psql -h /tmp -p "$PORT" -U postgres -d "$DB" -c \
  "SELECT label, total, delivered, remaining, missed FROM batch_progress;"

say ""
if [ "$FAILED" = "0" ]; then say "ALL CONCURRENCY + INVALIDATION ASSERTIONS PASSED"; exit 0
else say "SUITE FAILED"; exit 1; fi
