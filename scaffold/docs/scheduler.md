# The scheduled-jobs runner

`tools/scheduler.mjs` is the real, minimal job runner this repo did not have
before now — it closes two gaps that were each already disclosed elsewhere
rather than invented here:

- MASTERFILE §20.2b, verbatim, about `tools/health-alert.mjs`: "no cron job
  and no email/Slack/pager integration exists anywhere in this repo, and the
  script's own header says so." `health-alert.mjs` itself is real, tested,
  and already wired into `tools/verify.sh` — nothing ever called it on a
  schedule.
- `scaffold/README.md`'s own delivery-engine section: `materialize()`'s
  "future + undelivered only" invalidation guarantee
  (`packages/delivery-engine/src/materialize.ts`) is real and proven — but
  "no cron or scheduler actually calls it on a nightly cadence anywhere in
  this repo." This is not cosmetic: every `delivery_intent` row is created
  `state='pending'` with `scheduled_at` left `NULL`
  (`persistCapturedMessage()`, `packages/db/src/pool.ts` — `captureMessage()`
  only calls `materialize()` to validate and derive retention, never to
  persist a schedule), and `invalidate_for_child()`
  (`db/migrations/0002_delivery_sweep.sql`) resets an already-materialized
  row back to that same state on any zone/day-part change. `claim_due_
  intents()` only ever claims `state='ready'` rows. Without something
  calling `materialize()` and writing the result back, a `pending` intent
  never becomes `ready`, and nothing this product delivers would ever
  actually go out.

Read `tools/scheduler.mjs`'s own header for the full design writeup —
locking choice, exact per-job semantics, and what this deliberately does
**not** do (it does not call `claim_due_intents()`/`expire_stale_intents()`,
and it does not resolve `on_event` targets — both real, separate, disclosed
gaps, not silently folded in here). This page is the operator-facing "how do
I turn it on" half.

## What it runs

Two named jobs:

| Job | What it does |
|---|---|
| `rematerialize` | Sweeps every `delivery_intent` row still `state='pending'`, calls the real `materialize()` against a real `ChildCtx` loaded from Postgres, and writes the result back (`ready` + `scheduled_at`, `expired`, or left `pending` for a config gap that might still get fixed). |
| `health-alert` | Runs the real `tools/health-alert.mjs` as a subprocess against the same database and reports its exit code. |

## Turning it on for the Docker Compose dev stack

`scaffold/docker-compose.dev.yml` defines a `scheduler` service that runs
`node tools/scheduler.mjs loop` forever — but it is gated behind a Compose
**profile**, so it is not part of the stack's default startup. This is
deliberate: a background job silently rewriting `delivery_intent` rows on
the exact database someone is mid-debug session against — inventing a
"tomorrow's bedtime" schedule for a fixture row a developer was about to
inspect by hand, for instance — is a real footgun, not a hypothetical one.
Turning it on is an explicit, separate choice:

```bash
cd scaffold
docker compose -f docker-compose.dev.yml --profile scheduler up -d --build
```

(Older Compose CLIs that don't support `--profile` accept the same thing via
`COMPOSE_PROFILES=scheduler docker compose -f docker-compose.dev.yml up -d --build`.)

This starts the scheduler alongside the rest of the stack (`db`, `migrate`,
`server`, `callroom`), connected the same way `server` and `migrate` already
are — as `app_owner`, against `olive_devicetest`
(`docker-compose.dev.yml`'s own comments explain why `app_owner` specifically,
not `postgres`).

```bash
docker compose -f docker-compose.dev.yml logs -f scheduler   # tail its structured log lines
docker compose -f docker-compose.dev.yml --profile scheduler down   # stop everything including it
```

Turning it back off (going back to a plain `docker compose ... up -d`
without `--profile scheduler`) simply stops starting the `scheduler`
container on future `up`s — it does not undo any `ready`/`expired` state
transitions it already wrote, the same way stopping `server` doesn't undo
rows it already wrote.

## Reading its logs

Every line is flat `key=value` (the same shape `health-alert.mjs`'s own
`ALERT` lines already use, so both scrape identically from `docker logs` or
a log aggregator):

```
scope=scheduler event=start job=rematerialize at=2026-08-25T03:00:00.010Z
scope=scheduler event=end job=rematerialize status=ok duration_ms=812 scanned=4 materialized=3 expired=1 still_pending=0 skipped_rows=0 batch_limit_hit=false at=2026-08-25T03:00:00.822Z
scope=scheduler event=start job=health-alert at=2026-08-25T03:00:00.823Z
scope=scheduler event=end job=health-alert status=ok exit_code=0 duration_ms=610 at=2026-08-25T03:00:01.433Z
```

A skipped run under real lock contention (a manual `run` invocation
overlapping the loop's own scheduled run, for instance) looks like:

```
scope=scheduler event=start job=rematerialize at=...
scope=scheduler event=skip_already_running job=rematerialize at=...
```

A `health-alert` breach re-prints the real `health-alert.mjs` `ALERT` lines
verbatim (not summarized), each as its own `event=detail` line, and the job's
own `end` line reports `status=breach exit_code=1`.

## Running it by hand (no Docker)

Useful for a one-off sweep, or to test a change to `scaffold/` before it
rebuilds the container:

```bash
cd scaffold
npm run build   # scheduler.mjs imports the compiled delivery-engine/db packages
DATABASE_URL=postgres://... node tools/scheduler.mjs run rematerialize
DATABASE_URL=postgres://... node tools/scheduler.mjs run health-alert
DATABASE_URL=postgres://... node tools/scheduler.mjs run all      # both, in sequence
```

`run` always exits after one pass — this is the mode a REAL external cron
(a host `cron`/systemd timer pointed at a bare-metal or non-Compose
deployment, rather than this repo's own Docker Compose dev stack) would
invoke on its own schedule, instead of using `loop` at all. Either mode is a
legitimate way to run this job — `loop` exists because it is the simpler,
genuinely-correct choice for THIS repo's own Compose stack specifically (see
`tools/scheduler.mjs`'s own header for why: no second base image, no
separate mechanism for getting `DATABASE_URL` into a cron job's environment
inside a container — cron does not inherit it by default, a well-known
footgun — one process, one set of logs `docker compose logs` already shows).
A deployment that already has host-level cron/systemd is free to use `run`
from there instead and skip the `scheduler` Compose service entirely.

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `DATABASE_URL` (or `ADMIN_DATABASE_URL` as a fallback) | — (required) | Same connection convention as every other tool in this repo (`health-alert.mjs`, `migrate.mjs`). |
| `SCHEDULER_HOUR_UTC` | `3` | `loop` mode only — the UTC hour the daily sweep fires at. |
| `SCHEDULER_INTERVAL_MS` | unset | `loop` mode only — if set, overrides the daily schedule with a fixed interval instead. Useful for a tighter cadence, or for exercising the loop itself quickly without waiting for a real UTC day boundary. |

## What this does not do (yet)

Named here rather than left implicit, matching this repo's own disclosure
discipline:

- **No delivery worker.** `claim_due_intents()`
  (`db/migrations/0002_delivery_sweep.sql`) — the function that actually
  claims a `ready` intent and would hand it to a real push/notification
  send — has no application-level caller anywhere in this repo, before or
  after this file. This scheduler makes intents reach `ready`; something
  else, not built here, still needs to actually deliver them.
- **No `expire_stale_intents()` wiring.** The same migration's retention-
  expiry sweep (COPPA §10.1) is real and tested at the SQL level
  (`db/test/run_concurrency.sh`) but has no application-level caller either.
  Not folded into this file's `rematerialize` job — that job's own scope is
  exactly the disclosed gap it was asked to close (materializing `pending`
  rows), not a second, undeclared one.
- **No `on_event` resolution.** `childCtxFor()`
  (`packages/db/src/pool.ts`) never populates `ChildCtx.eventInstants` — no
  caller anywhere in this repo does. An `on_event` intent's `materialize()`
  call inside the sweep always returns `unresolvable_event` today, and is
  left `pending` for a future sweep rather than expired.
