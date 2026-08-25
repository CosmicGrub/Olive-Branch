#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — verify everything.
#
#  Written because the previous ad-hoc verification printed a HARDCODED total
#  ("280 passing, 0 failing") while every database suite had silently returned
#  zero, the server having died. That is false-green #7 on this project, and the
#  first one in the reporting rather than in a test.
#
#  Rules this script follows:
#    - Totals are COMPUTED by summing what each suite reported. Never asserted.
#    - A suite that reports zero assertions is a FAILURE, not a pass.
#    - Database unreachable is a hard abort, not a skip.
#    - Exit code is non-zero if anything failed or produced no assertions.
# ============================================================================
set -u
PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
PORT=${PORT:-5433}
DB=${DB:-verify_run}
# TCP connections (see the -h localhost fix below) hit Postgres's default
# host-auth method, which needs a password even for a throwaway dev/CI
# database -- unlike the Unix-socket path this replaced, which used peer/trust
# auth and never needed one. Matches the same "postgres" password both this
# session's local olive-postgres container and .github/workflows/verify.yml's
# own `POSTGRES_PASSWORD: postgres` already use; override for any setup that
# picks a different one.
export PGPASSWORD=${PGPASSWORD:-postgres}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TOTAL_PASS=0; TOTAL_FAIL=0; PROBLEMS=0
row() { printf "  %-26s %5s passed  %5s failed  %s\n" "$1" "$2" "$3" "$4"; }

record() { # name pass fail
  local n="$1" p="${2:-0}" f="${3:-0}" note=""
  if [ "$p" = "0" ] && [ "$f" = "0" ]; then note="◀ NO ASSERTIONS RAN"; PROBLEMS=$((PROBLEMS+1));
  elif [ "$f" != "0" ]; then note="◀ FAILURES"; PROBLEMS=$((PROBLEMS+1)); fi
  TOTAL_PASS=$((TOTAL_PASS+p)); TOTAL_FAIL=$((TOTAL_FAIL+f))
  row "$n" "$p" "$f" "$note"
}

echo ""
echo "── JavaScript suites ──────────────────────────────────────────"
npm i --silent >/dev/null 2>&1
npm run --silent build >/dev/null 2>&1 || { echo "  BUILD FAILED"; exit 2; }
for spec in \
  "time engine|packages/time-engine/test/golden.test.mjs" \
  "delivery engine|packages/delivery-engine/test/delivery.test.mjs" \
  "family graph|packages/family-graph/test/graph.test.mjs" \
  "session + child lock|packages/session-runtime/test/session.test.mjs" \
  "messaging|packages/messaging/test/pipeline.test.mjs" \
  "auth+storage+api|packages/api/test/stack.test.mjs" \
  "route contract: custody-order|server/test/routes.test.mjs" \
  "route contract: kiosk-pin/verify|server/test/kiosk_pin_route.test.mjs" \
  "route contract: theme|server/test/theme_route.test.mjs" \
  "device-tokens route contract|server/test/device_tokens_route.test.mjs" \
  "route contract: me/delete|server/test/me_delete_route.test.mjs" \
  "transport+contract|packages/transport/test/transport.test.mjs" \
  "push: fcm sender (mocked)|packages/transport/test/fcm.test.mjs" \
  "push: apns sender (mocked)|packages/transport/test/apns.test.mjs" \
  "push: device-channel routing (§8.11.4)|packages/transport/test/channels.test.mjs" \
  "homework + real OCR|packages/homework/test/homework.test.mjs" \
  "capture button + screenshot scope|packages/homework/test/snapshot.test.mjs" \
  "homework ImageStats measurement|packages/homework/test/measure.test.mjs" \
  "homework capture route (real OCR + hints)|packages/homework/test/capture-route.test.mjs" \
  "custody schedule|packages/custody/test/custody.test.mjs" \
  "phase 1-2 features|packages/agency/test/phase12.test.mjs" \
  "phase 3 court + archive|packages/ledger/test/phase3.test.mjs" \
  "showcase|packages/showcase/test/showcase.test.mjs" \
  "onboarding|packages/onboarding/test/onboarding.test.mjs" \
  "palette|packages/palette/test/palette.test.mjs" \
  "calendar + birthday|packages/calendar/test/calendar.test.mjs" \
  "storyteller|packages/storyteller/test/storyteller.test.mjs" \
  "activities + library + calls|packages/activities/test/activities.test.mjs" \
  "exchange + guardian + around|packages/guardian/test/gaps.test.mjs" \
  "device matrix|packages/devices/test/devices.test.mjs" \
  "channels + postures + pending|packages/devices/test/postures.test.mjs" \
  "call: modes camera lifecycle|packages/live/test/call.test.mjs" \
  "the pane|packages/live/test/pane.test.mjs" \
  "motion|packages/motion/test/motion.test.mjs" \
  "stream + budget|packages/budget/test/budget.test.mjs" \
  "signal + a11y matrix|packages/signal/test/signal.test.mjs" \
  "a11y read-aloud|packages/a11y/test/a11y.test.mjs" \
  "i18n bilingual/translation (§8.4)|packages/i18n/test/i18n.test.mjs" \
  "maturation ladder|packages/maturation/test/maturation.test.mjs" \
  "games|packages/games/test/games.test.mjs" \
  "games (checkers, battleship, hangman, chess)|packages/games/test/games2.test.mjs" \
  "games (kim's game, scavenger hunt, the chain)|packages/games/test/games3.test.mjs" \
  "live (latency floor, pictionary)|packages/live/test/live.test.mjs" \
  "webauthn attestation (CBOR/COSE parsing)|packages/auth/test/attestation.test.mjs" \
  "route contract (client/server drift)|packages/api/test/contract.test.mjs" \
  "availability route contract|packages/api/test/availability_contract.test.mjs" \
  "child lock state machine|packages/child-lock/test/lock.test.mjs" \
  "school layer|packages/school/test/school.test.mjs" \
  "print fulfilment|packages/print/test/print.test.mjs" \
  "filesystem storage adapter|packages/storage/test/storage.test.mjs" \
  "emergency card|packages/emergency/test/emergency.test.mjs" \
  "annotation canvas engine (undo/redo/erase)|packages/annotation/test/canvas.test.mjs" \
  "docker dev-stack compose bindings|tools/docker-dev/test/compose.test.mjs" ; do
  name="${spec%%|*}"; file="${spec##*|}"
  out=$(node "$file" 2>&1 || true)
  p=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\1/p' | tail -1)
  f=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\2/p' | tail -1)
  record "$name" "${p:-0}" "${f:-0}"
done

echo ""
echo "── Demo ───────────────────────────────────────────────────────"
node demo/build.mjs >/dev/null 2>&1 || { echo "  demo build FAILED"; PROBLEMS=$((PROBLEMS+1)); }
out=$(node demo/test/drive.test.mjs 2>&1)
p=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\1/p' | tail -1)
f=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\2/p' | tail -1)
record "demo drive (19 screens)" "${p:-0}" "${f:-0}"

echo ""
echo "── Dart client ────────────────────────────────────────────────"
# /tmp/flutter is only a guess for a locally-installed toolchain. CI's own
# flutter-action installs it under FLUTTER_ROOT (e.g.
# /opt/hostedtoolcache/flutter/...) and never sets FLUTTER_BIN at all, so the
# old default silently reported MISSING TOOLCHAIN even with a real, working
# Flutter install sitting right there under a different path -- never caught
# because, like everything else in this section, this workflow never actually
# ran until it was moved to the true repo root.
FLUTTER_BIN="${FLUTTER_BIN:-${FLUTTER_ROOT:-/tmp/flutter}/bin/flutter}"
if [ -x "$FLUTTER_BIN" ]; then
  export FLUTTER_ROOT="${FLUTTER_ROOT:-/tmp/flutter}"
  (cd client && "$FLUTTER_BIN" analyze >/tmp/da.out 2>&1)
  if grep -q "No issues found" /tmp/da.out; then
    echo "  dart analyze                clean"
  else
    grep -E "error|warning" /tmp/da.out | head -5 | sed 's/^/  /'
    echo "  DART ANALYZE FAILED"; PROBLEMS=$((PROBLEMS+1))
  fi
  out=$(cd client && "$FLUTTER_BIN" test --reporter compact 2>&1)
  # p/f must come from the compact reporter's own progress-counter PREFIX at
  # the very START of a line (e.g. "03:29 +1291 -2: ..."), never from a bare
  # "-[0-9]+" search anywhere in the captured blob. That is what this block
  # used to do, and it produced a real false failure on CI (Linux only,
  # never reproducible locally, because it isn't a test bug at all): every
  # dart test genuinely passes, but api_client_test.dart's own test name --
  # "...a non-2xx response (e.g. 403 not_this_child) returns false, never
  # throws" -- contains the substring "-2", and because a fully-passing run
  # never emits a real "-N" counter to begin with, that incidental text in
  # the test's own DESCRIPTION was the only thing matching `grep -oE
  # '\-[0-9]+' | tail -1`, so the script confidently reported "2 failed"
  # against a suite with zero real failures. CI's own false-red, the same
  # class of bug this file's own header exists to catch, just pointed the
  # other direction. Anchoring with ^ to the reporter's own
  # "<elapsed> +passed[ -failed]:" prefix -- structured data the reporter
  # itself emits, never test-author-controlled text -- makes this immune to
  # what any individual test happens to be named. The reporter uses \r to
  # overwrite its own line in a real terminal; piped/captured raw those
  # bytes are still literal \r, so they're normalized to \n first so ^ can
  # anchor each update correctly.
  lines=$(printf '%s' "$out" | tr '\r' '\n')
  p=$(printf '%s' "$lines" | grep -oE '^[0-9]+:[0-9]+ \+[0-9]+' | tail -1 | grep -oE '[0-9]+$')
  f=$(printf '%s' "$lines" | grep -oE '^[0-9]+:[0-9]+ \+[0-9]+ -[0-9]+' | tail -1 | grep -oE '\-[0-9]+$' | tr -d '-')
  record "dart widget invariants" "${p:-0}" "${f:-0}"
else
  # Not a skip. The toolchain is a declared dependency of this suite.
  echo "  dart widget invariants     MISSING TOOLCHAIN — not a skip, a gap"
  PROBLEMS=$((PROBLEMS+1))
fi

echo ""
echo "── Android native (kiosk bridge, §5.20) ─────────────────────────"
# The Dart block above only compiles/tests Dart — it cannot catch a native
# Kotlin error (KioskBridge.kt, MainActivity.kt), which was true even before
# this file was real: there was previously no Android-toolchain check here at
# all. Same "gap, not skip" posture as the Dart and LiveKit gates.
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
GRADLEW="client/android/gradlew"
if [ -n "$ANDROID_SDK" ] && [ -d "$ANDROID_SDK" ] && [ -x "$GRADLEW" ]; then
  if (cd client/android && ./gradlew -q :app:compileDebugKotlin >/tmp/gradle.out 2>&1); then
    echo "  android kotlin compile      clean"
  else
    tail -15 /tmp/gradle.out | sed 's/^/  /'
    echo "  ANDROID KOTLIN COMPILE FAILED"; PROBLEMS=$((PROBLEMS+1))
  fi
  # Galaxy Watch6 Classic companion (§21.5) — a separate Gradle module, native
  # Wear Compose rather than Flutter (see client/android/wear/build.gradle.kts
  # for why). Same gate, same posture: a real compile check, not a skip.
  if (cd client/android && ./gradlew -q :wear:assembleDebug >/tmp/gradle-wear.out 2>&1); then
    echo "  wear os compile             clean"
  else
    tail -15 /tmp/gradle-wear.out | sed 's/^/  /'
    echo "  WEAR OS COMPILE FAILED"; PROBLEMS=$((PROBLEMS+1))
  fi
else
  # Not a skip. The SDK is a declared dependency of this suite.
  echo "  android kotlin compile      MISSING TOOLCHAIN — not a skip, a gap"
  echo "  wear os compile             MISSING TOOLCHAIN — not a skip, a gap"
  PROBLEMS=$((PROBLEMS+2))
fi

echo ""
echo "── Live LiveKit ───────────────────────────────────────────────"
if [ -x "${LIVEKIT_BIN:-/tmp/livekit-server}" ]; then
  out=$(bash tools/with-livekit.sh node packages/session-runtime/test/live.test.mjs 2>&1)
  p=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\1/p' | tail -1)
  f=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\2/p' | tail -1)
  record "livekit (live server)" "${p:-0}" "${f:-0}"
else
  # Not a skip. The binary is a declared dependency of this suite.
  echo "  livekit (live server)      MISSING BINARY — not a skip, a gap"
  PROBLEMS=$((PROBLEMS+1))
fi

echo ""
echo "── Database suites ────────────────────────────────────────────"
# -h localhost, not /tmp: a Unix socket in /tmp only exists for a Postgres
# started natively via pg_ctl on this same host. Every environment that
# actually runs this script points at a Postgres reached over TCP instead --
# the Docker container this session's local dev uses (olive-postgres), and
# CI's own postgres: service container (see .github/workflows/verify.yml) --
# neither of which puts a socket file on the runner's/host's filesystem.
# -h /tmp silently looked for a socket that was never going to exist, so this
# ABORT was unreachable-by-design until the CI workflow file was corrected to
# actually run (it lived at the wrong path, non-functional, until now) -- the
# very first real CI run is what surfaced it.
PSQL="$PGBIN/psql -h localhost -p $PORT -U postgres"
if ! $PSQL -c 'select 1' >/dev/null 2>&1; then
  echo "  ABORT: Postgres unreachable on port $PORT. Not a skip — a failure."
  exit 2
fi
# These previously omitted -U and failed silently, leaving every suite to run
# against the previous run's data. Redirecting stderr hid it completely.
$PGBIN/dropdb   -h localhost -p "$PORT" -U postgres --if-exists "$DB" \
  || { echo "  ABORT: cannot drop $DB"; exit 2; }
$PGBIN/createdb -h localhost -p "$PORT" -U postgres "$DB" \
  || { echo "  ABORT: cannot create $DB"; exit 2; }
# db/migrations/0022_backup_reader_role.sql GRANTs onto this role but
# deliberately cannot CREATE it (app_owner, the identity migrate.mjs
# connects as once role provisioning below hands off, has no CREATEROLE
# privilege — see that migration's own header for the full reasoning).
# docker-compose.dev.yml's real Docker flow creates it via
# tools/docker-dev/init-db.sql, mounted as docker-entrypoint-initdb.d —
# this script has no equivalent bootstrap step, so migration 0022 failed
# outright the first time this branch's own migrations ran here
# ("role \"backup_reader\" does not exist"), and would have failed
# identically in CI (.github/workflows/verify.yml runs this exact script
# against its own Postgres service container, which never touches
# init-db.sql either). Created here, as postgres superuser, before
# migrations run — the same ordering docker-dev/init-db.sql establishes.
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'backup_reader') THEN
    CREATE ROLE backup_reader LOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END
\$\$;
ALTER ROLE backup_reader NOSUPERUSER BYPASSRLS LOGIN PASSWORD 'verify_run_backup_reader_pw';
SQL
if [ $? -ne 0 ]; then
  echo "  ABORT: could not provision backup_reader before migrations"
  exit 2
fi
# Applied through the runner, so ordering, checksums, and idempotency are
# exercised on every verification rather than only when someone remembers.
PSQL_CMD="$PSQL -d $DB" node tools/migrate.mjs >/tmp/mig.out 2>&1 \
  || { echo "  ABORT: migrations failed"; cat /tmp/mig.out; exit 2; }
MIG_APPLIED=$(grep -c '^applied' /tmp/mig.out)
MIG_TOTAL=$(ls db/migrations/*.sql | wc -l | tr -d ' ')
echo "  migrations                 $MIG_APPLIED applied, $MIG_TOTAL total"
if [ "$MIG_APPLIED" != "$MIG_TOTAL" ]; then
  echo "  ABORT: a freshly created database applied $MIG_APPLIED of $MIG_TOTAL"
  echo "         migrations — the reset did not happen and every suite below"
  echo "         would run against stale data."
  exit 2
fi

out=$($PSQL -d "$DB" -q -t -A -f db/test/0001_constraints.test.sql 2>&1)
record "db constraints" "$(printf '%s' "$out" | grep -c 'PASS')" "$(printf '%s' "$out" | grep -c 'FAIL')"

out=$($PSQL -d "$DB" -q -t -A -f db/test/0005_court.test.sql 2>&1)
record "db court tier (P8)" "$(printf '%s' "$out" | grep -c 'PASS')" "$(printf '%s' "$out" | grep -c 'FAIL')"

$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f db/test/0002_seed.sql >/dev/null 2>&1
out=$(PGBIN="$PGBIN" DB="$DB" PORT="$PORT" bash db/test/run_concurrency.sh 2>&1)
record "db concurrency" "$(printf '%s' "$out" | grep -c '  PASS')" "$(printf '%s' "$out" | grep -c '  FAIL')"

for spec in "db isolation|db/test/0003_session.test.sql" \
            "db e2e message chain|db/test/0004_e2e_message.test.sql" ; do
  name="${spec%%|*}"; file="${spec##*|}"
  out=$($PSQL -d "$DB" -f "$file" 2>&1)
  record "$name" "$(printf '%s' "$out" | grep -c 'NOTICE:  PASS')" \
                 "$(printf '%s' "$out" | grep -c 'WARNING:  FAIL')"
done

echo ""
echo "── DB suites requiring a real NOSUPERUSER NOBYPASSRLS role ──────"
# These suites prove RLS actually denies a child/guardian session (not just
# that application code doesn't expose it) — they need a real, connectable
# role that OWNS every table (db/DEPLOYMENT.md's app_owner; "any test of RLS
# run as `postgres` measures nothing" — that doc, quoting a real incident),
# which nothing in this repo's automation provisioned until pool/custody_
# order/auth_credentials were fixed here originally. Not by adding a new
# role (0001_constraints.test.sql above and 0003_session.test.sql below
# already create/extend app_owner for their own narrower purposes) but by
# finishing the job: a real password so it is reachable over the same TCP
# connection style everything else in this script uses, and ownership of
# EVERY table, not just child_journal_entry.
#
# availability/deletion/raw_export/message_capture were each written and
# passing locally by their own PRs, but never actually added to this list —
# a real, silent gap across four already-merged PRs, closed here rather than
# left for a future rebase to notice by accident. device_token is this PR's
# own addition, following the identical pattern. health_alert/messages_route
# were the same gap again, caught by a round-2 post-merge audit
# ("Merge Aftermath") rather than by this list ever being re-checked against
# the actual `test/` directories on disk — TEST-01/TEST-02 in that report.
# guardian invite bootstrap route is this pass's own addition, added here
# alongside the new test file itself rather than left for a future audit to
# find missing, same lesson as the paragraph above.
APP_OWNER_PW="verify_run_app_owner_pw"
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') THEN
    CREATE ROLE app_owner LOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END
\$\$;
ALTER ROLE app_owner NOSUPERUSER NOBYPASSRLS LOGIN PASSWORD '$APP_OWNER_PW';
GRANT USAGE ON SCHEMA public TO app_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_owner;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_owner;
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE %I OWNER TO app_owner', r.tablename);
  END LOOP;
END
\$\$;
SQL
if [ $? -ne 0 ]; then
  echo "  ABORT: could not provision app_owner for the RLS-role DB suites"
  exit 2
fi
DB_URL="postgresql://app_owner:${APP_OWNER_PW}@localhost:${PORT}/${DB}"
ADMIN_URL="postgresql://postgres:postgres@localhost:${PORT}/${DB}"
for spec in "db pool (real RLS)|packages/db/test/pool.test.mjs" \
            "db custody order (real RLS)|packages/db/test/custody_order.test.mjs" \
            "db auth credentials (real RLS)|packages/db/test/auth_credentials.test.mjs" \
            "db availability (real RLS)|packages/db/test/availability.test.mjs" \
            "db account deletion (real RLS)|packages/db/test/deletion.test.mjs" \
            "db raw export (real RLS)|packages/db/test/raw_export.test.mjs" \
            "db take-and-go (real RLS)|packages/db/test/take_and_go.test.mjs" \
            "db message capture (real RLS)|packages/db/test/message_capture.test.mjs" \
            "db device token (real RLS)|packages/db/test/device_token.test.mjs" \
            "db guardian invite (real RLS)|packages/db/test/guardian_invite.test.mjs" \
            "db theme preference (real RLS)|packages/db/test/theme_preference.test.mjs" \
            "push: notify dispatch (real DB)|packages/transport/test/notify.test.mjs" \
            "db certified export (real RLS)|packages/db/test/court_export.test.mjs" \
            "db health alert (real DB)|packages/db/test/health_alert.test.mjs" \
            "messages route (real DB)|packages/api/test/messages_route.test.mjs" \
            "guardian invite bootstrap route (real DB)|packages/api/test/guardian_bootstrap_route.test.mjs" \
            "guardian invite creation route (real DB)|packages/api/test/guardian_invite_create_route.test.mjs" \
            "calls route (real DB)|server/test/calls_route.test.mjs" \
            "now route: real tz-interval + home_tz fallback (real DB)|server/test/now_route.test.mjs" \
            "scheduler: rematerialize sweep + lock contention (real DB)|packages/db/test/scheduler.test.mjs" \
            "media upload/download route (real DB + real filesystem)|packages/api/test/media_route.test.mjs" ; do
  name="${spec%%|*}"; file="${spec##*|}"
  out=$(DATABASE_URL="$DB_URL" ADMIN_DATABASE_URL="$ADMIN_URL" node "$file" 2>&1 || true)
  p=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\1/p' | tail -1)
  f=$(printf '%s' "$out" | sed -n 's/^\([0-9]\+\) passed, \([0-9]\+\) failed$/\2/p' | tail -1)
  record "$name" "${p:-0}" "${f:-0}"
  if [ "${f:-0}" != "0" ] || [ -z "$p" ]; then printf '%s\n' "$out" | tail -40 | sed 's/^/    /'; fi
done

echo ""
echo "── Health ─────────────────────────────────────────────────────"
if PSQL_CMD="$PSQL -d $DB" node tools/healthcheck.mjs >/tmp/hc.out 2>&1; then
  echo "  health checks              $(grep -c '  ok  ' /tmp/hc.out) ok      0 breaches"
else
  grep -E 'BREACH' /tmp/hc.out | sed 's/^/  /'
  echo "  HEALTH BREACH"; PROBLEMS=$((PROBLEMS+1))
fi

echo ""
echo "── Health alert (tools/health-alert.mjs) ────────────────────────"
# A second, complementary path into the SAME health_check view queried just
# above -- DATABASE_URL/pg-driver based instead of the psql binary, structured
# stderr lines instead of a table, meant to be invoked by a real cron/monitor
# LATER (see the script's own header for exactly what is and is not wired up
# today). $DB here is the same freshly migrated, trivially healthy database
# the "Health" step above already found clean, so this step is not expected
# to breach in normal operation -- it exists to prove the script itself runs
# and reports correctly against a real database, not to re-litigate the
# Health section above. Only a hard ABORT (exit 2 -- the script itself is
# broken, e.g. cannot connect or health_check is missing) counts against
# PROBLEMS; an unexpected breach (exit 1) is reported but does not gate the
# suite's exit code, per this task's own instructions.
HA_URL="postgres://postgres:$PGPASSWORD@localhost:$PORT/$DB"
DATABASE_URL="$HA_URL" node tools/health-alert.mjs >/tmp/ha.out 2>/tmp/ha.err
HA_CODE=$?
if [ "$HA_CODE" = "0" ]; then
  echo "  health-alert                $(cat /tmp/ha.out)"
elif [ "$HA_CODE" = "1" ]; then
  echo "  health-alert                UNEXPECTED BREACH on a fresh DB (reported, not gating):"
  sed 's/^/    /' /tmp/ha.err
else
  echo "  health-alert                ABORT (exit $HA_CODE)"
  sed 's/^/    /' /tmp/ha.err
  PROBLEMS=$((PROBLEMS+1))
fi

echo ""
echo "── MARKUP ↔ CHANGELOG ↔ DEMO correspondence ──────────────────"
# Standing rule: the visual MARKUP amends in step with the CHANGELOG. The total
# is passed in so C7 compares MARKUP's quoted figure against what was actually
# computed above, rather than against a number typed into a document.
if node tools/check-markup.mjs --total "$TOTAL_PASS" >/tmp/mk.out 2>&1; then
  echo "  markup correspondence      $(grep -c 'PASS' /tmp/mk.out) passed      0 failed"
else
  grep -E '^  (PASS|FAIL)' /tmp/mk.out | sed 's/^/  /'
  echo "  MARKUP DRIFT — see above"; PROBLEMS=$((PROBLEMS+1))
fi

echo ""
echo "──────────────────────────────────────────────────────────────"
printf "  %-26s %5s passed  %5s failed\n" "COMPUTED TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL"
if [ "$PROBLEMS" = "0" ] && [ "$TOTAL_FAIL" = "0" ]; then
  echo "  ALL GREEN"; exit 0
else
  echo "  NOT GREEN — $PROBLEMS suite(s) failed or ran nothing"; exit 1
fi
