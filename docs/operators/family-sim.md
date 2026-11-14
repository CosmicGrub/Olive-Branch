# Family simulation (10 synthetic families, watchable)

Proves, with evidence, that the server serves several families at once with strict isolation, finds
onboarding gaps, and measures performance. Everything lives in `scaffold/tools/family-sim/`.
No real data: every name is synthetic. The simulator never touches the physical devices, nor any
container outside the `olive-sim` project.

## What it is

| Piece | File |
| --- | --- |
| Throwaway stack (project `olive-sim`: db + migrate + server, loopback-only, own volumes) | `docker-compose.sim.yml`, `up.sh`, `down.sh` |
| Simulator (10 families, scripted actors, probes, measurements) | `sim.mjs`, `lib/*.mjs` |
| Control room (live page, SSE, replay) | `control-room.mjs`, `control-room/index.html` |
| Final report page (self-contained) | `report.mjs` |
| Real-screen contact sheet | `client/test/family_sim_contact_sheet_test.dart`, `contact-sheet.mjs` |
| CI subset (3 families, isolation only) | `test/isolation_ci.test.mjs` (wired in `tools/verify.sh`, `npm run test:family-sim`) |

## Run it and watch (from `scaffold/`)

```bash
bash tools/family-sim/up.sh                 # build + migrate as app_owner + wait healthy (server 127.0.0.1:8141, db 127.0.0.1:5481)
node tools/family-sim/control-room.mjs      # then open http://127.0.0.1:8150 and press "Start run"
#   or headless:  node tools/family-sim/sim.mjs --profile full      (quick = about 3 minutes, full = about 22)
node tools/family-sim/report.mjs tools/family-sim/out/run-<stamp>   # writes report.html into the run folder
bash tools/family-sim/down.sh               # removes ONLY the olive-sim containers, network and volumes
```

Replay a saved run offline: open `http://127.0.0.1:8150/#replay` (the control room alone, no stack needed),
pick a run, scrub or play it back. Runs are `out/run-*/events.ndjson` (gitignored).

Contact sheet: `cd client && flutter test -j 2 test/family_sim_contact_sheet_test.dart`, then
`node tools/family-sim/contact-sheet.mjs`. (The pictures land in `client/build/`, gitignored.)

Flags: `--families N`, `--profile quick|full`, `--soak-secs S`, `--vhour-secs S` (real seconds per virtual hour), `--out DIR`.

## What a run does

1. **Seed** (harness SQL: the server has no sign-up, family or child route; see gaps G1 to G3).
2. **Steady**: a compressed virtual day 15:00 to 21:30. The server has no clock hook, so the families' day-part
   boundaries are placed where the *real* clock will be (`lib/seed.mjs` `dayPlan`): one virtual hour is
   `--vhour-secs` real seconds. Each family signs in, sets a PIN, pairs each child device (real pairing and redeem
   routes), banks messages, changes play settings, starts a call (token mint, no media), logs expenses, doses,
   care notes, handover notes, bag items, letters, then exports and revokes a device. One family invites a sitter,
   two families have a custody schedule, one is single-guardian, one deletes a co-guardian's account.
3. **Isolation probes**: every family attacks each of the other nine (see below).
4. **Burst**: all families act at once, five rounds. **Noisy neighbour**: family 3 hammers while the rest carry on,
   compared against their own baseline. **Soak**: random activity (85% reads) for `--soak-secs` (default 600).
5. Results: `summary.json`, `latency.json` (p50/p95/p99 per route), `probes.json`, `gaps.json`, `metrics.json`
   (server RSS/CPU from `docker stats`, DB connections from `pg_stat_activity`), `events.ndjson`.

## Isolation probes (PASS only if refused uniformly)

For each ordered pair (attacker A, victim B), with B's REAL ids: every route that carries `:childId` (read from
`server/routes.mjs` so a new route is swept automatically) is called with A's guardian token and A's child token,
once with B's real child id and once with a random id. Pass requires a refusal (never 2xx) and an answer that is
identical in status, body keys and error text for the real and the random id (no existence oracle). Plus: tampered /
garbage / missing / wrongly-keyed tokens, A's child token on adult routes, A's credential against B's device id,
reuse of B's pairing code and invite, guessed invite / device / table ids, forged signed-media URLs, a websocket
upgrade to a guessed relay room, pairing-code guessing (uniform misses, a limiter engages) and the cross-family side effect of
that limiter, and a timing comparison (real vs random id, interleaved, flagged not failed). A 429 from the
per-principal write limiter is retried, because it answers before authorisation and proves nothing.

## Known limits of what this proves

* It runs one server process and one Postgres, on one machine, over loopback. It says nothing about a real network, TLS, a proxy, or horizontal scale.
* Day-parts are compressed onto the real clock; DST, midnight wrap and multi-day behaviour are not exercised.
* The `ready` to `delivered` step is done by a harness worker because nothing in the running system performs it (gap G5).
* Call and relay checks cover authorisation and setup, not media.
* The dev-login shortcut stands in for the sign-in ceremony (passkey), so the ceremony itself is not simulated.
* All traffic shares 127.0.0.1, so the per-IP auth bucket is raised in the sim compose; the per-principal write bucket is real (300 burst, 600/min here, 60 and 60/min by default).
* Timing probes are noisy at the millisecond level on a laptop; a flag is a lead, not a proof.
