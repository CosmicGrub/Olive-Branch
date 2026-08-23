# The dev stack, containerized

`docker-compose.dev.yml` (repo root of `scaffold/`) runs this project's own
server (`server/index.mjs`) and local call-room-coordination tool
(`tools/local-call-room-server.mjs`) as Docker containers, alongside a
dedicated Postgres, instead of as plain `node` processes launched by hand.

## Why this exists

Live two-device testing this session ran the server as a bare
`node server/index.mjs` process (via WSL, or a background shell) — this
worked, until it silently didn't: the process was launched inside a
one-shot `wsl.exe -- bash -c "... & disown"` invocation, and died the
moment that specific invocation exited, taking `nohup`/`disown` down with
it. Both physical test devices kept running against a dead backend for a
real stretch of time before this was caught, purely because there was no
signal that the server had stopped — no crash log, no obvious symptom
beyond "the app can't reach the server."

A container doesn't have this failure mode: `docker compose up -d` detaches
properly, `restart: unless-stopped` brings the process back if it does
crash, and `docker compose ps`/`docker logs` give an honest, checkable
answer to "is this actually running" instead of trusting that a background
shell command is still alive somewhere.

## What this replaces, and what it doesn't

Replaces: the ad hoc `PORT=8123 DATABASE_URL=... node server/index.mjs` /
`node tools/local-call-room-server.mjs` invocations this session ran
directly against a WSL-native Postgres instance.

Does NOT replace:
- **`tools/verify.sh`'s own CI-parity Postgres** (the separate
  `olive-verify-pg` container, if you see one running) — different
  purpose, different lifecycle, left alone. This stack's own `db` service
  runs on a different host port (`5434`, not `5433`) specifically so the
  two never collide.
- **`tools/jitsi-selfhost/`'s own compose stack** — a separate, larger,
  independently-documented piece of infrastructure (see that directory's
  own README). This stack's `callroom` service can point at it
  (`JITSI_SERVER_URL` in `docker-compose.dev.yml`) but doesn't start or
  manage it.
- **Production deployment.** This is a single-stage dev image (see the
  `Dockerfile`'s own header) that ships the whole repo plus
  `node_modules`, runs `npm run build` inside the image, and has no
  concept of secrets management, horizontal scaling, or a real domain —
  none of that is in scope here.

## Use

**First time only** — this stack needs a real, local `SESSION_SECRET`
before it will start at all, and `DEV_LOGIN` (needed for physical-device
testing) is opt-in, not on by default:

```bash
cd scaffold
cp .env.example .env
# then edit .env: paste the output of `openssl rand -hex 32` into
# SESSION_SECRET, and set DEV_LOGIN=1 if you're testing against a real
# device. Never commit this file — it's already gitignored.
```

```bash
docker compose -f docker-compose.dev.yml up -d --build
```

`--build` is the normal way to run this, not an occasional flag — every
time `scaffold/` changes (a new PR merges, a local edit is made), rerunning
this picks it up. The first run also creates the `app_owner` role/database
and applies every migration (`tools/docker-dev/init-db.sql` +
the `migrate` one-shot service) before `server` ever starts — see
`init-db.sql`'s own header for why `app_owner` specifically, not
`postgres`.

```bash
docker compose -f docker-compose.dev.yml logs -f server callroom   # tail both
docker compose -f docker-compose.dev.yml ps                        # health
docker compose -f docker-compose.dev.yml down                      # stop
docker compose -f docker-compose.dev.yml down -v                   # stop + wipe the DB volume
```

Physical devices reach this stack exactly the same way they always have —
`adb reverse tcp:8123 tcp:8123` and `adb reverse tcp:8787 tcp:8787` per
device, since the container publishes those same host ports. Nothing about
how `call_screen.dart`/`api_client.dart` reach the backend changes; only
how the backend itself is launched and kept alive changed.

Both ports publish to `127.0.0.1` only, not every host interface — a
device on the same WiFi network can't reach either port directly, only
through `adb reverse`'s own tunnel to host loopback. This is deliberate:
both `DEV_LOGIN=1` (server) and the call-room coordinator's own
`who=dad|ivy` endpoint issue real, valid credentials with no password of
any kind, so this stack should never be reachable by anything but the host
machine itself.

## A new migration lands — what to do

Nothing manual. `docker compose ... up -d --build` reruns the `migrate`
one-shot service against the existing `db` volume before `server` starts,
and `tools/migrate.mjs`'s own M1/M2 guarantees (ordered, idempotent — see
that file's header) mean re-running it against an already-migrated
database is a safe no-op for everything already applied. This is the
exact gap that used to require a manual `GRANT`/`ALTER TABLE ... OWNER TO
app_owner` pass by hand every time a new migration added a table against
the WSL-native database — connecting as `app_owner` from the start (see
`docker-compose.dev.yml`'s `migrate` service) means every table is
correctly owned the moment it's created, not after a follow-up fix.
