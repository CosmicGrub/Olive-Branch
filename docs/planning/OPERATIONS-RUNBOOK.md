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

- The dev stack is the compose project `olive-fresh` (`scaffold/docker-compose.dev.yml`): database, migrate (one-shot), server and the `delivery` worker. `docker compose -p olive-fresh -f docker-compose.dev.yml up -d --build db migrate server delivery` rebuilds it from the current checkout and applies new migrations. Name `delivery`: it is the one delivery worker (nothing moves a banked message into a child's inbox without it) and, left out of a named `up`, it keeps running the OLD image. Settings come from `scaffold/.env` (git-ignored; `SESSION_SECRET` and `MEDIA_SIGNING_SECRET` are required, copy `.env.example`). `callroom` (the LiveKit-era room coordinator) is behind the `callroom` profile and is not part of the stack unless you pass `--profile callroom`.
- Rebuilt on 2026-11-15 from main at PR #225: 51 migration files (0001 to 0052; there is no 0019) applied in order by `migrate`, `delivery` enabled with `DELIVERY_IN_SERVER=0`, `/readyz` as the healthcheck, `npm run smoke:stack` 25 passed, 0 failed, 1 skipped. The old volume had been migrated from a feature branch (its `0049_identity_signup` is main's 0050), so the migrator correctly refused and the disposable dev volume was recreated (`down -v`; a `pg_dump` was taken first). A device paired against the old volume has to pair again.
- **Device path.** `scaffold/tools/device-sync.sh` expects the server on `127.0.0.1:8123` and runs `adb reverse tcp:8123 tcp:8123`; the stack publishes exactly that port on loopback, so nothing about it changed. Check from a device without installing anything: `adb -s <serial> reverse tcp:8123 tcp:8123`, then `adb -s <serial> shell "(printf 'GET /readyz HTTP/1.0\r\n\r\n'; sleep 2) | toybox nc 127.0.0.1 8123"` answers `200` and `{"status":"ready",...}`. The guardian shell built by `device-sync.sh` signs in with the dev login, which needs `DEV_LOGIN=1` in `scaffold/.env` and `node server/seed-dev.mjs` (off by default); a locally paired child tablet needs neither.
- **Server suites against the dev stack.** `tools/verify.sh` needs the Postgres 16 client tools and a Linux node, so run it in a throwaway container from the stack's own image, sharing the database container's network: `docker run --rm -u root --network container:olive-fresh-db-1 -v <checkout>:/src:ro --entrypoint bash olive-fresh-server -c 'unset NODE_ENV; mkdir /work && cd /src && tar --exclude=node_modules --exclude=.git --exclude=scaffold/.env -cf - . | tar -xf - -C /work && cd /work/scaffold && PORT=5432 DB=verify_run bash tools/verify.sh'`. It creates and drops its own `verify_run` database, so `olive_devicetest` is untouched, and it exits non-zero here only because the Dart, Gradle and LiveKit sections have no toolchain in the container; read the per-suite lines. The two homework suites also want `imagemagick tesseract-ocr python3 python3-pil fonts-dejavu-core` installed in the container. **It rewrites the cluster-wide role passwords** (`app_owner`, `app_runtime`, `backup_reader`) to its own, so the running server and delivery worker lose their database login until you put them back, and then drop its database: `docker exec olive-fresh-db-1 psql -U postgres -c "ALTER ROLE app_owner PASSWORD 'app_owner'" -c "ALTER ROLE app_runtime PASSWORD 'app_runtime'" -c "ALTER ROLE backup_reader PASSWORD 'backup_reader'" -c "DROP DATABASE verify_run"` (the values `tools/docker-dev/init-db.sql` creates them with; the delivery worker recovers on its next tick). Never point it at a stack you cannot afford to have briefly unable to log in to its database.
- If a database was migrated with older (CRLF) checksums the migrator refuses; the dev database is disposable (`down -v`, then up).
- Docker Desktop updates itself and the engine is unavailable while that happens; wait, do not kill it. If it genuinely wedges, see the documented recovery steps in the Docker notes (stuck socket vs stuck WSL disk).
- Never expose the dev stack to the internet: it has a credential-free dev login.
- **Readiness.** `GET /healthz` is liveness only. `GET /readyz` (the compose healthcheck) is 200 only when the database answers, the schema is at or past the newest migration baked into the image, the media volume accepts a write and the process is not draining; a 503 body names a category (`db`, `schema`, `media`, `draining`) and nothing else (probes are not access-logged unless `ACCESS_LOG_HEALTHZ=1`; results are shared for `READYZ_CACHE_MS`, default 2000). A `degraded: ["delivery"]` entry means the delivery worker has failed three passes in a row or has not succeeded for six intervals: the app still serves, but a banked message is not reaching the inbox, so read the server log for `delivery: tick failed`.
- **Sign-up.** Invite-only: see "First family on a fresh server" below. There is no shared setup code and no `POST /v1/families`. `/internal/metrics` is loopback-only; from the host use `docker exec olive-fresh-server-1 node -e "fetch('http://127.0.0.1:8123/internal/metrics').then(r=>r.text()).then(console.log)"` (it shows the delivery host's status and counters when the server hosts the worker, and the push state).
- **Whole-chain smoke test.** After rebuilding the stack: `npm run smoke:stack -- --db-container olive-fresh-db-1 --server-container olive-fresh-server-1` (from `scaffold/`). It issues its own sign-up allowances by running `provision-signup.mjs` inside the server container, makes a throwaway family, invites a second guardian (asserting she has an account and no access until the inviter confirms), pairs a child, banks a message, and checks the worker delivered it to the child's inbox and another family cannot see any of it; it prints one PASS/FAIL line per link, exits non-zero on a FAIL and deletes only its own rows. Its one cheat (moving the throwaway message's scheduled instant into the past, because a bedtime message is hours away) is printed. Before sending anything it asks Docker which container publishes the `--base` port and refuses the long-lived stacks (`olive-live-*`, `olive-sim-*` and the rest) whether or not they were named; `--server-container` must be that container and `--db-container` must be in its compose project. If Docker cannot be read it refuses (override: `--i-know-this-is-not-a-test-stack`). It consumes one unit of the sign-up cap per family it makes.

## First family on a fresh server (identity lane, migration 0050)

- A fresh server has no accounts and refuses `DEV_LOGIN` in production. Mint one single-use sign-up token: `docker exec <server-container> node tools/provision-signup.mjs issue --label "family 1"`. It prints the token once; hand it over in person. `status`, `disable`, `enable` and `cap <n|none>` are the kill switch and the account cap (same tool). Never put a token, a name or an email in a ticket or a commit.
- The grown-up signs up in the app (name, time zone, PIN), creates the child (`POST /v1/children`, own PIN), and invites the second grown-up (`POST /v1/children/:childId/guardianships`). The invitee accepts, bootstraps (or, with an existing account, claims), and the inviter confirms with their PIN: that confirm is the only step that grants access. There is no mailer; the invite id travels out of band.
- Passkeys need a real domain: set `WEBAUTHN_RP_ID` (and the Android signing-key hash in `WEBAUTHN_ANDROID_ORIGINS`) and the server serves `/.well-known/assetlinks.json`. With no domain, sign-in is the device credential from sign-up; there is no account recovery yet, so a grown-up who loses every enrolled device needs the other grown-up or the operator.
- Migration order on main: 0049 delivery receipts, 0050 identity (this section), 0051 schema level (`/readyz`), 0052 call end reasons. They apply in order; the runner refuses a gap.

## Moving main onto your own olive-live stack (runbook, NOT executed by anyone)

Written 2026-11-15 from read-only facts about the stack (container metadata, the migrate log and the compose files); never run against it. Every step has its undo beside it. Read it once end to end before you start; none of it needs the dev stack. Placeholders: `<live>` is the directory you run the live compose from today, `<main>` a new directory for the main checkout, `<sha>` the short commit of main you build.

**What is different on main (why this is more than a rebuild).**

- The live database is at migration 0046 (45 files applied; there is no 0019). Main's 0001 to 0046 are byte-identical to yours (compared with line endings normalised), so the migrator will not refuse; it applies six additive files: 0047 (health views under row-level security), 0048 (a step-up challenge purpose), 0049 (delivery receipts), 0050 (sign-up allowances and the confirmed guardian edge, with a backfill), 0051 (the schema level `/readyz` reads), 0052 (call end reasons). Final state: 51 applied, 51 total. Migrations are forward-only; there is no down.
- The server, the scheduler and the new `delivery` worker now connect as the `app_runtime` role, not `app_owner`. Compose refuses to start without `APP_RUNTIME_PASSWORD`, and your database has no such role (the init script only runs on an empty volume). Step 7 creates it.
- There is a new `delivery` service (the one delivery worker), the server healthcheck is `/readyz`, `callroom` is behind the `callroom` profile (and its LiveKit variables are no longer required just to parse the file), and calls default to Jitsi. Your existing `callroom` container is not part of the new default definition and is left running on the old image until you decide (step 11).
- Your session and media signing secrets are unchanged by all of this: do not change them, or every signed-in device and every outstanding media link stops working.

**Steps (bash; define the compose once).**

```
cd <live>/scaffold    # for steps 1 to 3
LIVE="docker compose -p olive-live --env-file .env.live -f docker-compose.prod.yml -f docker-compose.live.override.yml"
```

1. **Read-only look.** `$LIVE ps`, `docker image ls olive-live`, and confirm free disk space for an image build and a database dump. Nothing changes. Undo: none needed.
2. **Back up the database and the media, and prove the dump reads.** `$LIVE --profile ops run --rm backup` (database and media, as `backup_reader`; see `scaffold/docs/backup-and-restore.md`), then `pg_restore -l <the new .dump>` lists its contents. Keep the two files outside the project. This is your guaranteed way back. Undo: delete the files.
3. **Freeze the way back.** `docker tag olive-live:local olive-live:before-main` (use your current tag if it is not `local`), and `cp .env.live .env.live.before-main`. Undo: `docker rmi olive-live:before-main`, delete the copy.
4. **A clean checkout of main in its own directory** (do not reuse the checkout you run today; leave it exactly as it is, it is your rollback): `git fetch origin && git worktree add <main> origin/main`. Copy `.env.live` and, if you keep it, `docker-compose.live.override.yml` into `<main>/scaffold/` (the override only blanks LiveKit values on the server, which main already defaults to empty, so it is now redundant). Undo: `git worktree remove <main>`.
5. **Edit only the copy of the env file in `<main>/scaffold/`.** Add `APP_RUNTIME_PASSWORD=<openssl rand -hex 24>` (hex, because it goes inside a URL). Set `IMAGE_REPO=olive-live` and `IMAGE_TAG=main-<sha>` so the new image has its own tag. Leave `SESSION_SECRET`, `MEDIA_SIGNING_SECRET`, the Postgres, owner and backup-reader passwords, `PUBLIC_BASE_URL`, `BACKUP_DIR` and the host ports exactly as they are. Optional and off by default: `DELIVERY_PUSH`, `FCM_SERVICE_ACCOUNT_FILE` (see "Server lane" below), `INTERNAL_METRICS_TOKEN`. Then `cd <main>/scaffold`, run the same `LIVE=...` line there, and `$LIVE config --quiet`: it must print nothing; otherwise it names the variable you forgot. Undo: delete the copy.
6. **Build the new image** (a heavy job: Docker build, nothing else running): `docker build -t olive-live:main-<sha> .` from `<main>/scaffold`. This starts nothing and replaces nothing; the running containers keep their image. Undo: `docker rmi olive-live:main-<sha>`.
7. **The window begins.** Stop only the two services that talk to the database as the old owner role: `docker stop olive-live-server-1 olive-live-scheduler-1` (the database and `callroom` stay up; devices keep working offline, the app is built for it). Create the runtime role (idempotent, safe to repeat), taking the password from your env file rather than typing it: `set -a; . ./.env.live; set +a; docker exec -i olive-live-db-1 psql -U postgres -v runtime_password="$APP_RUNTIME_PASSWORD" -f - < tools/docker-dev/create-runtime-role.sql`. Undo: `docker start olive-live-server-1 olive-live-scheduler-1` (nothing else has changed yet); the extra role is harmless.
8. **Migrate.** From `<main>/scaffold`: `$LIVE run --rm --no-deps migrate`. Expect `applied 0047_...` through `applied 0052_...` and a final `done` line reading 6 applied, 51 total. It also applies `db/runtime_grants.sql` to the new role. If it prints `REFUSING`, stop: read the message, change nothing else, and use step 12 (R1). Undo: not possible in place; use step 12 (R2 or R3).
9. **Start the new services, by name, with `--no-deps`.** `$LIVE up -d --no-deps server delivery scheduler`. Never run a bare `up -d` here: it would also recreate `db` (its init-script bind mount path changed with the new directory), restarting Postgres for no reason. Undo: step 12.
10. **Check it.** `curl -fsS http://127.0.0.1:<SERVER_HOST_PORT>/readyz` answers `200` and `{"status":"ready","failing":[],"degraded":[]}`. `docker logs olive-live-server-1` shows `delivery worker: not hosted in this process`; `docker logs olive-live-delivery-1` shows `deliver_loop_start` and then `status=ok` lines every 30 s. Sign in on a device as before and send yourself a message. Do not run `tools/smoke-stack.mjs` against this stack: it refuses to (it recognises the long-lived stacks), and it creates families. Then take a fresh backup (step 2 again) so the first post-migration state is also safe.
11. **`callroom`.** It still runs the old image. Calls go through Jitsi, so you probably want it gone, but that is your call: to keep it on the new image, `$LIVE --profile callroom up -d --no-deps callroom` (needs `LIVEKIT_*` in the env file); to retire it, `docker stop olive-live-callroom-1` (undo: `docker start`).
12. **Rollback, by how far you got.**
    - **R1, only if step 8 never started, or printed `REFUSING` before it applied anything** (the `applied ...` lines are absent). `docker start olive-live-server-1 olive-live-scheduler-1`. The database is untouched. If step 8 printed `FAILED: <file>` or `Schema left at the last successfully applied migration`, some of the six files have already committed and the database is NOT untouched: use R2 (the migrations only add), or R3.
    - **R2, after migrating; quick, and unproven for every route.** The six migrations only add; the old image boots on the migrated schema and answers `/healthz` (checked on the dev stack on 2026-11-15; full route behaviour was not exercised). Stop the new services (`docker stop olive-live-server-1 olive-live-delivery-1 olive-live-scheduler-1`), then from `<live>/scaffold` (the OLD env file and compose) recreate with `--no-deps` (essential: the old compose's `migrate` would refuse the six files it does not know and block the server): `$LIVE up -d --no-deps server scheduler`. Remove the new worker: `docker rm -f olive-live-delivery-1`.
    - **R3, back to the step-2 dump; the way back that does not depend on the new schema, but not yet rehearsed.** `pg_restore --clean` only drops objects that are in the dump, so restoring over the migrated database leaves the new ones behind (`signup_allowance`, `signup_policy`, `schema_level()`, the new columns and constraints) and fails on the dependency from `signup_allowance` to `app_user`: a half-restored database that is not the backup. So restore into a freshly created database. (1) Stop everything that connects: `docker stop olive-live-server-1 olive-live-delivery-1 olive-live-scheduler-1`. (2) As `postgres`, recreate the database (`<db>` is `POSTGRES_DB_NAME` from your env file; the `olive_prod` default if unset): `docker exec -i olive-live-db-1 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '<db>' AND pid <> pg_backend_pid()" -c 'DROP DATABASE "<db>"' -c 'CREATE DATABASE "<db>" OWNER app_owner'`. That is all `init-db.prod.sh` sets on the database itself; the roles are cluster-wide and stay (the extra `app_runtime` role is harmless). (3) Restore the step-2 dump into it with `tools/restore-db.sh` (see `scaffold/docs/backup-and-restore.md`, "Restore from a backup") and the media with `tools/restore-media.sh`. (4) Check, do not assume: `docker exec -i olive-live-db-1 psql -U postgres -d <db> -c '\dt'` must list none of `signup_allowance` or `signup_policy`, and `\df schema_level` must list nothing. Do NOT run the main `migrate` now: the dump already carries the old grants, and the old image runs as it did before. (5) Start the old image from `<live>` as in R2. Anything written after the dump is lost. If you later retry the move, repeat steps 7 and 8 from the start, and expect `applied` for all six files again.
13. **After a few quiet days.** `docker rmi olive-live:before-main`, remove `.env.live.before-main`, and remove the old checkout directory when you no longer need it.

**What could not be checked from here.** Whether your live database holds data that a main migration rejects (the files are additive and the 0050 backfill is covered by a test, but your data was never run through them: the step-2 dump is why that is acceptable); the old image against every route on the new schema (R2); how long the migration takes on your data (the dev database was tiny). Only the names of your live env file's variables were read, never its values.

## Memory limits (important)

- The development PC has limited RAM. Running several Flutter and Gradle processes at once exhausted it (git and Docker failed to fork). Keep at most two or three heavy jobs at a time; run Gradle with `--no-daemon` and a 1 GB heap or run `./gradlew --stop` after builds; run `flutter test` with at most two jobs; push early.
- On low memory, `git push` can fail with an out-of-memory error; use `-c http.postBuffer=52428800 -c core.compression=0`.

## Heavy-job slots (`scaffold/tools/slot.sh`)

At most two heavy jobs (a `flutter test`, a full node suite run, a build) run at once on the shared machine. A slot is a directory `slot1` or `slot2` under the shared lock directory (`OLIVE_LOCK_DIR`, default `/z/wt-locks` in Git Bash) holding two files: `stamp` (UTC time taken or last renewed) and `owner` (a label you choose, never a login). `mkdir` is the atomic take. Use the script, not hand-made directories:

```
bash scaffold/tools/slot.sh acquire any --owner my-task [--wait 600]   # takes the first free slot
bash scaffold/tools/slot.sh renew   1   --owner my-task                # a job that runs longer than the window
bash scaffold/tools/slot.sh release 1   --owner my-task                # always, also on failure (use a trap)
bash scaffold/tools/slot.sh status                                     # slot1 FREE | HELD | UNSTAMPED | STALE
```

- `acquire` never takes over a held slot and never removes anything. When both are busy it exits 1 and says who holds them.
- **Stale** means the stamp is older than 90 minutes (`SLOT_STALE_MIN`) **and** no flutter, dart or node test process is running. A stale lock is **reported** in the `status` output and in your report; it is **not** removed by anyone but its owner. An old stamp with a test still running is a long job, not a stale lock: the owner should `renew`.
- `release` and `renew` refuse (exit 3) unless `--owner` matches the lock's `owner` file, stale or not. A lock without an `owner` file (hand-made) cannot be released with the script; its creator removes it.
- A lock whose directory exists but has no readable stamp is `UNSTAMPED` and counts as held.
- Always release in a `trap ... EXIT` so a failed test run does not strand the slot. Heavy Gradle builds belong to the device lane only; run `flutter test -j 1`.

## Privacy gate (`scaffold/tools/privacy-gate.mjs`)

The repository is public. The gate reads the lines a change **adds** and exits non-zero (1) on any hit; exit 2 means it could not read the diff, which also fails (it does not say clean when it cannot look). It catches:

| rule | what |
| --- | --- |
| `identity` | the current OS/git user name, host name and e-mail local part, plus anything in `PRIVACY_GATE_EXTRA` (comma list), read at run time so the names never have to be written in the repo; a public `github.com/owner/repo` or `ghcr.io/owner` path is not counted |
| `path` | drive-letter paths, `/Users/x`, `/home/x`, `/mnt/c/...`, git-bash `/c/Users/...`, UNC shares; a placeholder segment (`<name>`, `...`, `you`, `runner`) is fine |
| `email` | e-mail addresses; `example.*`, `.test`/`.invalid`, `noreply@...` and `git@github.com` are fine |
| `ip` | IPv4/IPv6/MAC addresses; loopback, `0.0.0.0`, the emulator alias `10.0.2.x`, the RFC 5737 and RFC 3849 documentation ranges and netmasks are fine |
| `secret` | cloud/API keys and tokens, private-key blocks, JWTs, URL credentials, quoted password/token assignments with a high-entropy value |
| `private-link` | claude.ai artifact/chat/share links, shared Google/Notion/Dropbox/OneDrive documents, tunnel hosts, webhook URLs |
| `sensitive-file` | `google-services.json`, `GoogleService-Info.plist`, keystores, `key.properties`, `local.properties`, `.env` (not `.env.example`), `*.pem`/`*.p12` |
| `device` | a literal `adb -s <serial>` / `ANDROID_SERIAL=<serial>`, default Windows machine names (pass serials at run time through the environment, never commit them) |

```
node scaffold/tools/privacy-gate.mjs                       # what is STAGED (run before every commit)
node scaffold/tools/privacy-gate.mjs --range origin/main...HEAD   # everything the branch adds
node scaffold/tools/privacy-gate.mjs --text msg.txt        # a commit message or PR body
git diff --cached | node scaffold/tools/privacy-gate.mjs --stdin
```

It also runs inside `tools/verify.sh` (the "Privacy gate" block, branch against `origin/main` plus anything staged; override the base with `PRIVACY_BASE`), so CI runs it on every pull request (the verify job checks out full history for this). Hits print a redacted excerpt, never the full value.

- A genuine placeholder is waived for **one line and one rule** with a comment such as `privacy-gate: allow ip`. There is no file-level or wildcard waiver, and a sensitive file name cannot be waived at all (rename the fixture instead, for example `google-services.sample.json`).
- It folds zero-width and full-width characters and percent-encoding before matching, and long lines are scanned in windows so a hostile 1 MB line cannot hang it.
- What it cannot do: recognise a secret with no known shape, or a name it was never told. Read your own diff as well.

## Windows: `npm run test:stack` aborting after "126 passed, 0 failed"

`packages/api/test/stack.test.mjs` is the only suite that opens real sockets. Calling `process.exit()` (even from `setImmediate`) while those TCP handles are still closing races the exit-time teardown against a thread still posting to the event loop, and libuv aborts the process with `Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 76`; npm then reports exit code 127 on a fully green run. Delaying the exit narrows the window but does not close it (measured: 1 to 5 ms crashed every run, 20 ms one in five, 50 ms and more none, which is a timing window, not a leak in the suite). The suite now sets `process.exitCode` and lets the event loop drain, which never races. Any new suite that opens sockets should do the same: **never `process.exit()` after real sockets on Windows**. It is a Node/libuv Windows teardown race, not a defect in the code under test; Linux CI never shows it.

## Reading a failed widget run

`tools/verify.sh` names the failing Dart tests through `scaffold/tools/list-test-failures.sh`. The `flutter test --reporter compact` log has no "Failing tests" section; each failing test is a progress frame such as `00:04 +1 -1: group name of the test [E]`, and the script prints one `FAILED: <name>` per such frame (a test file that cannot load shows as `FAILED: loading <path>`). Use it on any saved log: `bash scaffold/tools/list-test-failures.sh run.log` (or pipe the log in). Exit 3 means the counter shows failures but no name was found, so read the raw log.

## Pausing and resuming

- "Pause" means only PRs and CI continue; no new work. Record the resume order in the roadmap and decisions files.
- Before any pause: push every branch (committed or WIP), never commit secrets (the live-server env file is gitignored), and list open PRs and their state in `ANDROID-ROADMAP.md`.
- Branch map of work kept for later is in `ANDROID-ROADMAP.md`.

## Releasing

See `docs/RELEASING.md`. Versions are spec versions; the app version is `X.Y.Z+(major*10000+minor*100+patch)`. The release tool dry-runs by default. Preview cuts are debug-signed with no server address; the repository is public, so a published release is public.

## Server lane: delivery, push and calls (operator steps)

Everything here is opt-in and degrades honestly: the app is offline-first and the server enables the live experience, it never gates the local one. Nothing in this section is needed to run the app on a device.

**1. The first real family (no dev-login).** See "First family on a fresh server" above: the operator issues a single-use sign-up allowance with `provision-signup.mjs issue`, the grown-up signs up, creates the child and invites the second grown-up, whose access starts only when the inviter confirms with their PIN.

**2. Delivery.** A message sent to a child who has a bedtime is stored `ready` with its delivery time (otherwise `pending`, re-timed when a bedtime is saved). There is ONE delivery worker (`node tools/scheduler.mjs deliver-loop`, the Compose `delivery` service, not profile-gated, every `DELIVERY_TICK_MS`, default 30 s): it expires stale messages, re-times pending ones, moves due ones to `delivered` (visible in the child's inbox), then sends one content-free wake-up push per child. A message that comes due inside the child's quiet hours is delivered silently. `DELIVERY_PUSH=off` keeps delivery and sends no push. For a single-container deployment set `DELIVERY_IN_SERVER=1` on the server and drop the `delivery` service; running both is safe (one advisory lock) but wasted. `/readyz` shows `degraded: ["delivery"]` when a due message has sat unclaimed for ten minutes, whichever process should have delivered it. The nightly `scheduler` profile also runs the worker once and ends abandoned calls (`end-stale-calls`).

**3. Push (needs the owner's Firebase project).** The code is real and tested against an HTTP stand-in for Google; it has never run against Google because no Firebase project exists yet.

1. In the Firebase console create a project, add an Android app with the app's package id, and download `google-services.json` for the app (see the client note below).
2. Project settings, Service accounts, "Generate new private key". Save that JSON in `scaffold/secrets/` (git-ignored; never commit it, never paste it into chat).
3. Put `FCM_SERVICE_ACCOUNT_FILE=/run/olive-secrets/<file name>` in `scaffold/.env` and recreate only the server and the delivery service (the one that sends the wake-ups): `docker compose -p olive-fresh -f docker-compose.dev.yml up -d --no-deps server delivery` (the compose files mount `scaffold/secrets` read-only at `/run/olive-secrets`; add `scheduler` if you run that profile). A key in an environment variable shows in `docker inspect`; a file does not. `FCM_SERVICE_ACCOUNT_JSON` is still accepted.
4. Check: the server logs `push: {"androidRing":"ready",...}` at boot (a set but malformed key stops the server booting, deliberately) and the loopback `GET /internal/metrics` carries `push.androidRing`. Names and booleans only, never the key.
5. Client: see "Client lane" below. The app takes its Firebase settings from build values, not from a Gradle plugin, so `google-services.json` is never put in `client/android`; until a build carries those values no device obtains an FCM token and the server has nothing to push to.

**Client lane: Firebase settings, alerts and the knock (Android).** The full list of what the owner provides is in `HOSTING-AND-CALLS.md` ("What the owner must provide for push and calls"). In short:

1. Download `google-services.json` from the Firebase console (outside the repository) and run `node tools/fcm-defines.mjs <that file>` from `scaffold/`. It writes `scaffold/secrets/fcm.defines.json` (git-ignored), prints only how many settings it wrote, refuses a file for a different application id, a malformed value, an output outside `scaffold/secrets/` and an existing output unless `--force`.
2. Build with those values: `bash tools/device-sync.sh` picks the file up by itself; for a hand build add `--dart-define-from-file=scaffold/secrets/fcm.defines.json` to `flutter build apk`. A build without them is a normal build with push off (no log line, no screen, no change).
3. On each child tablet, once, a grown-up opens Guardian mode (PIN and biometric) and uses "Alerts on this tablet": Allow (the Android 13 notification box) and, on Android 14 and later, Open settings for full-screen notifications. A child never sees either box.
4. Where it is not working, in this order: the server's `push:` boot line and `/internal/metrics`; a `device_token` row for the child; the tablet's notifications allowed; the system banner with the app closed; the knock with the screen off. A killed-app banner that does not draw while the knock does points at the missing Gradle plugin path (MASTERFILE 7.20): the fallback is to apply the Google services plugin and put the file in `client/android/app` (git-ignored), a client change that needs a Gradle run.
5. CI compiles the Kotlin (`:app:compileDebugKotlin`) and the advisory release-smoke build installs it on an emulator; a local Gradle run follows the memory rules above.


**4. Calls.** `GET /v1/children/:id/calls/availability` tells the app whether calls are on and whether they only work on the home network. Turning calls on is still `tools/jitsi-selfhost/calls-on.sh`; the server reads its environment at start, so after changing the values recreate only the server: `docker compose -p olive-fresh -f docker-compose.dev.yml up -d --no-deps server`. Never touch the `olive-live-*` containers. A call session is joinable for `CALL_MAX_AGE_MINUTES` (default 240) at most.
