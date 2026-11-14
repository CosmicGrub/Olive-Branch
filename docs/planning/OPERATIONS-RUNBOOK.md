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
