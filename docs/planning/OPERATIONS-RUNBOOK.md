# Operations runbook (how to resume work)

Practical notes learned while building. Nothing here contains credentials.

## CI rules and gotchas

- **Two required checks:** `verify` (about 16 to 19 minutes) and `image`. The advisory `ios-compile` job never blocks.
- **Runner pin:** CI is pinned to `ubuntu-24.04`. `ubuntu-latest` moved to 26.04 in November 2026, whose apt installs `postgresql-client` 18; `tools/verify.sh` expects `/usr/lib/postgresql/16/bin`, so every database suite aborted with "Postgres unreachable". Move the pin deliberately and update `PGBIN` when ready for 26.04.
- **Assertion totals:** `MARKUP.html` line 20, `scaffold/demo/shell.html` ("assertions") and `scaffold/package.json` (`check:markup`) must equal CI's `COMPUTED TOTAL`. Never compute it by hand. The totals check fails once on purpose after you add tests: push, read the number from the verify job log (`gh api --allow-escape-sequences repos/<owner>/<repo>/actions/jobs/<id>/logs`), set it in all three places, push again. Squash merges can leave main off by a small amount; fix from CI's number.
- **After any rebase** run `git grep -n -E '^(<<<<<<<|>>>>>>>)'` and fix any marker. Most files are CRLF on Windows: edit with a tool that preserves line endings.
- **Transient failures:** the postgresql.org key download (the Dockerfile now retries), GitHub download outages and Maven 504s. Rerun only that job. Anything else: read the log and fix the root cause.
- **Rerunning a PR's checks** reuses the old merge commit; to test against a newer main, close and reopen the PR or push a commit.
- **Every client Dart file** carries the "UNVERIFIED" header convention (the transport contract test enforces it).
- **Migrations** run as the unprivileged `app_owner`: next free number from main, trusted extensions only, no function-level `SET` of custom parameters (`scaffold/tools/test/migrate_nonsuper.test.mjs` guards this).

## Merge procedure

1. Branch from the latest main in its own worktree.
2. Build, run `flutter analyze` and the full `flutter test` once, plus node and database suites you touched.
3. Push, wait once for `verify`, set the total from CI, push again.
4. Merge only when `verify` and `image` are green and the PR is clean; squash.
5. Pull main before the next item. If main moved, rebase and recompute the total (up to three rounds).

## Devices (Android)

- Test devices: a Galaxy Z Fold 5 and a Galaxy Tab S9 FE. The Fold may appear over USB or wireless; wireless ports change, so list devices with `adb devices` and `adb mdns services`.
- Push the unified live build in place (never uninstall, so data stays): build `lib/main_live.dart` release for arm64 with `--dart-define=OLIVE_API_BASE_URL=<server address>` and `--android-project-arg=olive.allowDebugSignedRelease=true`, then `adb -s <serial> install -r app-release.apk` and `adb -s <serial> reverse tcp:<port> tcp:<port>`. A helper script is `scaffold/tools/device-sync.sh`.
- Installing is not exercising: record device checks only when someone actually ran the app.

## Release launch smoke test

- **What it is:** `.github/workflows/release-smoke.yml`, advisory (`continue-on-error`, not a required check). For the child (`lib/main_live.dart`) and guardian (`lib/main_live_guardian.dart`) entry points it builds a debug-signed RELEASE APK for x86_64, installs it on an API 34 emulator, launches `MainActivity`, watches it for 20 seconds and fails on a crash. It exists because a release-only crash (resource shrinking removed strings the Jitsi SDK reads) passed every other check. The cheap half, `tools/check-release-shrink.mjs`, runs inside `verify`.
- **Where to look:** the run's summary page shows the verdict per variant; the artifacts `release-smoke-child` and `release-smoke-guardian` (kept 14 days) hold the evidence.
- **`verdict.txt`:** PASS/FAIL lines from `tools/release-smoke-eval.mjs`. FAIL reasons: a crash of the app process (a `FATAL EXCEPTION` block naming it, an ANR, a native fatal signal), the process missing at any second or its pid changing (a silent restart hides a crash), `am start -W` reporting anything but `Status: ok` (a bare `Status: timeout` is tolerated when the Displayed line exists, because a cold start on the software-rendered emulator can pass `am`'s ~10 s wait), or no `Displayed com.olivebranch.olive_client/.MainActivity` line (no window was ever drawn). INFO lines (engine-start evidence, whether MainActivity was resumed at the end, crashes of OTHER processes) never fail the run.
- **`logcat.txt`:** the whole log of the run from just before launch (all buffers, threadtime format). For a crash search `FATAL EXCEPTION` and read the `Caused by:` lines; the original defect read `Resources$NotFoundException: String resource ID #0x0`. `alive.txt` is one `<second> <pid>` line per second (an empty pid means the process was gone). `am-start.txt`, `activities.txt` and `install.txt` are the raw command output. `screenshot.png` is the screen at the end of the window: a blank or system-dialog screenshot with a PASS verdict deserves a look.
- **Reproduce by hand** (an emulator or a spare device, never the family devices): build as the workflow does, then `bash scaffold/tools/release-smoke.sh <apk> <outdir>` with adb on the path.
- **Honest limits:** the emulator has no server behind it (the API base is the emulator's host alias, nothing listens), so this proves the release build starts and stays up, not that sign-in or any flow works. It does not replace a run on the real devices. The workflow was written without being able to run an emulator locally, so treat the first runs as calibration and fix the workflow, not the symptom, if it is red without a crash in `logcat.txt`. Before making it required, it needs a run of consecutive green results on main.

## Docker stack

- The dev stack is the compose project `olive-fresh` (`scaffold/docker-compose.dev.yml`): database, migrate, server. `docker compose -p olive-fresh -f docker-compose.dev.yml up -d --build db migrate server` rebuilds it from the current checkout and applies new migrations.
- If a database was migrated with older (CRLF) checksums the migrator refuses; the dev database is disposable (`down -v`, then up).
- Docker Desktop updates itself and the engine is unavailable while that happens; wait, do not kill it. If it genuinely wedges, see the documented recovery steps in the Docker notes (stuck socket vs stuck WSL disk).
- Never expose the dev stack to the internet: it has a credential-free dev login.

## Memory limits (important)

- The development PC has limited RAM. Running several Flutter and Gradle processes at once exhausted it (git and Docker failed to fork). Keep at most two or three heavy jobs at a time; run Gradle with `--no-daemon` and a 1 GB heap or run `./gradlew --stop` after builds; run `flutter test` with at most two jobs; push early.
- On low memory, `git push` can fail with an out-of-memory error; use `-c http.postBuffer=52428800 -c core.compression=0`.

## Pausing and resuming

- "Pause" means only PRs and CI continue; no new work. Record the resume order in the roadmap and decisions files.
- Before any pause: push every branch (committed or WIP), never commit secrets (the live-server env file is gitignored), and list open PRs and their state in `ANDROID-ROADMAP.md`.
- Branch map of work kept for later is in `ANDROID-ROADMAP.md`.

## Releasing

See `docs/RELEASING.md`. Versions are spec versions; the app version is `X.Y.Z+(major*10000+minor*100+patch)`. The release tool dry-runs by default. Preview cuts are debug-signed with no server address; the repository is public, so a published release is public.

## Server lane: first family, delivery, push and calls (operator steps)

Everything here is opt-in and degrades honestly: the app is offline-first and the server enables the live experience, it never gates the local one. Nothing in this section is needed to run the app on a device.

**1. The first real family (no dev-login).** A production server has no dev-login, so the operator mints a single-use code and gives it to the family out of band:

- `docker compose -p olive-fresh -f docker-compose.dev.yml exec server node tools/enrol-family.mjs create --label "name"` prints the code once (only its hash is stored; it expires in 7 days, `--days 1-90`). `list` shows state without codes; `revoke <id>` kills an unused code.
- The family redeems it once in the app (or `POST /v1/families`): that creates the guardian, the child, the guardianship edge and a paired guardian device in one transaction and returns a session plus the device credential. She then sets her PIN and pairs the child's device with the ordinary pairing flow.
- Switches on the server environment: `FAMILY_ENROLMENT=off` is a kill switch (403 `enrolment_closed`), `FAMILY_ENROLMENT_MAX=N` caps how many families it will ever enrol, `ENROL_MISS_BUDGET_PER_MIN` (default 10) caps unknown-code guesses per source address and `ENROL_MISS_BUDGET_GLOBAL_PER_MIN` (default 300) across all callers, so one caller cannot lock the others out. A new family starts with placeholder day-parts (bedtime 19:30, night not reachable); there is no guardian-facing editor for them yet.

**2. Delivery.** A sent message is `pending`; the scheduler's fast lane (`rematerialize`, `deliver-due`, `end-stale-calls`, every `SCHEDULER_FAST_INTERVAL_MS`, default 60 000) moves it to `ready`, then `delivered` (visible in the child's inbox), then sends one content-free wake-up push per child. In the dev compose the scheduler is profile-gated: `docker compose -p olive-fresh -f docker-compose.dev.yml --profile scheduler up -d scheduler`. `SCHEDULER_FAST_LANE=off` returns the loop to its daily schedule; `DELIVERY_PUSH=off` keeps delivery and sends no push. A message that comes due inside the child's quiet hours is delivered silently.

**3. Push (needs the owner's Firebase project).** The code is real and tested against an HTTP stand-in for Google; it has never run against Google because no Firebase project exists yet.

1. In the Firebase console create a project, add an Android app with the app's package id, and download `google-services.json` for the app (see the client note below).
2. Project settings, Service accounts, "Generate new private key". Save that JSON in `scaffold/secrets/` (git-ignored; never commit it, never paste it into chat).
3. Put `FCM_SERVICE_ACCOUNT_FILE=/run/olive-secrets/<file name>` in `scaffold/.env` and recreate only the server and scheduler: `docker compose -p olive-fresh -f docker-compose.dev.yml up -d server scheduler` (the compose files mount `scaffold/secrets` read-only at `/run/olive-secrets`). A key in an environment variable shows in `docker inspect`; a file does not. `FCM_SERVICE_ACCOUNT_JSON` is still accepted.
4. Check: the server logs `push: {"androidRing":"ready",...}` at boot and the loopback `GET /internal/metrics` carries `push.androidRing`. Names and booleans only, never the key.
5. Client: `client/android` builds without `google-services.json` today (no Google plugin is applied). Adding the file and the Google services Gradle plugin is a client change that is not in this lane (no Gradle runs here); until then no device can obtain an FCM token, so the server has nothing to push to.

**4. Calls.** `GET /v1/children/:id/calls/availability` tells the app whether calls are on and whether they only work on the home network. Turning calls on is still `tools/jitsi-selfhost/calls-on.sh`; the server reads its environment at start, so after changing the values recreate only the server: `docker compose -p olive-fresh -f docker-compose.dev.yml up -d --no-deps server`. Never touch the `olive-live-*` containers. A call session is joinable for `CALL_MAX_AGE_MINUTES` (default 240) at most.
