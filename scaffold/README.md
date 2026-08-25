# OLIVE BRANCH — Phase 0 scaffold

Spec: `MASTERFILE.md`, canonical — see that file for the current version;
this directory's own numbering does not track it in lockstep. This
directory is implementation; the three canonical documents remain the
source of truth.

## Layout

```
scaffold/
├── db/migrations/
│   └── 0001_phase0_init.sql        full Phase 0 schema, §5
│   ├── migrations/0002_delivery_sweep.sql   claim, expiry, invalidation §4.5
│   ├── migrations/0003_session_context.sql  GUC accessors, effective edges
│   ├── test/0001_constraints.test.sql       24 adversarial probes
│   ├── test/0002_seed.sql                   550-intent batch fixture
│   ├── test/run_concurrency.sh              8-worker exactly-once proof
│   ├── test/0003_session.test.sql           14 isolation assertions
│   └── DEPLOYMENT.md                        RLS role model — a safety control
└── packages/
    ├── time-engine/                the subsystem everything else depends on
    │   ├── src/time.ts             zone resolution, DST-safe wall clock
    │   └── test/golden.test.mjs    the six mandatory fixtures, §4.6
    ├── delivery-engine/
    │   ├── src/materialize.ts      six policies + retroactive-delivery guard
    │   ├── src/gate.ts             two-sided gate, bounded defer chain
    │   └── test/delivery.test.mjs  37 probes, §6.3–6.5
    ├── family-graph/
    │   ├── src/authorize.ts        can() — P7 first, then P6, then edges
    │   ├── src/session.ts          the ONLY writer of app.* GUCs
    │   └── test/graph.test.mjs     59 probes, §5.17–5.18
    ├── session-runtime/
    │   ├── src/rooms.ts            opaque rooms, grant derivation, I1–I5
    │   └── test/session.test.mjs   67 probes incl. child-lock, real LiveKit SDK
    └── child-lock/
        └── src/lock.ts             kiosk defeat state machine, §8.3
```

The three siblings once tracked here as "planned, not yet written" are now
all built: `family-graph/` (already shown above — this list duplicated it
by mistake), `packages/api/` (a hand-rolled router — `packages/api/src/api.ts`
— not the NestJS gateway §7 originally described), and the Flutter client,
which landed at `client/` rather than `app/`. The scaffold has grown well
past these three since — `packages/` holds 40+ modules today. See
`MASTERFILE.md` for the current, complete inventory rather than expanding
this illustrative Layout section to match.

## Run everything

```bash
npm install
npm run test             # all packages  → now chains 43 sub-suite
                          #   invocations (42 unique -- test:games2 is
                          #   invoked twice), well past the four below;
                          #   see tools/verify.sh for the current
                          #   combined total (that script also runs six
                          #   more Postgres-dependent suites this chain
                          #   does not -- test:db, test:auth-credentials,
                          #   test:db:export, test:message-capture,
                          #   test:messages-route, test:calls-route)
npm run test:golden      # time engine   →  24
npm run test:delivery    # delivery      →  37
npm run test:graph       # family graph  →  59
npm run test:session     # session+lock  →  67

# database (needs a live Postgres 16) — apply every migration in order,
# idempotently, via the real runner (see tools/migrate.mjs; this replaced
# hand-listing each file one at a time after that produced two real
# incidents — a suite run against a database missing a migration, and one
# run twice against the same database):
PSQL_CMD="psql" node tools/migrate.mjs
psql -f db/test/0001_constraints.test.sql     # 24 PASS
psql -f db/test/0002_seed.sql
bash db/test/run_concurrency.sh               #  7 PASS
psql -f db/test/0003_session.test.sql         # 14 PASS  (non-superuser only)
psql -f db/test/0004_e2e_message.test.sql
psql -f db/test/0005_court.test.sql
```

The four package suites above (`24 + 37 + 59 + 67 = 187`, reconfirmed by
actually running all four, unchanged since Phase 0) plus the three counted
DB suites (`0001_constraints.test.sql` 24, `run_concurrency.sh` 7,
`0003_session.test.sql` 14) still total **232 assertions, all green** —
this is the same 232 the doc has always claimed, not a new figure. But both
`npm run test` and `db/test/` have since grown well past what this section
originally covered (48 npm test sub-suites now exist, plus the two DB
suites added above, neither counted in the 232). See `CHANGELOG.md`'s
latest entry for the current repo-wide combined total — **6010** as of
v0.49.40 (JS/server + Flutter), not this file's 232.

> The database suites must run as a `NOSUPERUSER NOBYPASSRLS` role. Run as
> `postgres` they measure nothing — superusers bypass RLS even with FORCE.
> See `db/DEPLOYMENT.md`.

## Why these six fixtures

| Fixture | Catches |
|---|---|
| F1 spring forward | 2:30 AM on 8 Mar 2026 does not exist |
| F2 fall back | 1:30 AM on 1 Nov 2026 exists twice |
| F3 Chicago ↔ Phoenix | gap is 1 h winter / 2 h summer — never constant |
| F4 El Paso | Texas is Central *except* two counties |
| F5 TX ↔ NC handoff | zone flips at the exchange, not at midnight |
| F6 180-night batch | one stale batch mis-delivers an entire deployment |

F1 failed on first execution and exposed a real bug in the spec's own reference
implementation. See CHANGELOG 0.4.0 → Fixed.

## Delivery engine guards

| Guard | Prevents |
|---|---|
| `PAST_GRACE_MINUTES = 120` | A recovered outage retroactively dumping a week of bedtime videos at once. Inside the window a late message still goes out; beyond it, the intent expires. |
| `at_daypart` rolls, `on_local_date` expires | "Next bedtime" and "the night of June 1st" are different promises. Only the first may move. |
| `MAX_DEFERS = 3` | A gate deferring forever. Fails **open** and logs — silence is worse than imperfect timing. |
| `FOR UPDATE SKIP LOCKED` + CAS | Concurrent workers double-delivering. Proven with 8 parallel workers against 500 due intents. |
| Statement-level triggers | 5,500 redundant UPDATEs collapsing to 50 on a bulk day-part insert. |
| Invalidation scoped to future + undelivered | A delivered message being retroactively re-timed. It belongs to the child. |

## Authorization guards

| Guard | Prevents |
|---|---|
| P7 checked before edge resolution | Any construction of arguments returning allow for `journal.read`. The answer never depends on the graph. |
| `actor_has_edge()` ignores `sibling_link` | Guardian of one sibling reaching another — the lateral escalation path a family graph invites. |
| `NULLIF(current_setting(...), '')` | An empty GUC raising 22P02 instead of denying. Fail-crash → fail-closed. |
| `set_config(..., is_local => true)` | A pooled connection retaining the previous request's child context. |
| Verified-principal typing | Session context sourced from request input. |

## Session + child-lock invariants

| Invariant | Prevents |
|---|---|
| **I1** room names are 24 random bytes, asserted not to contain any identifier | Room enumeration. `child:<uuid>` is guessable by anyone holding a child id. |
| **I2** `roomJoin` for exactly one room; no `roomAdmin`/`roomCreate`/`roomList`/`recorder` | A call token doubling as an admin credential. Verified on the wire via the real SDK. |
| **I3** `identity` = authenticated principal | Impersonation via client-supplied identity. |
| **I4** `can()` re-runs at **mint** time, membership checked second | A revoked, restricted, or expired edge riding a stale participant list. |
| **I5** 600s TTL | A token outliving a defeated kiosk. |
| Escalation dropped on kiosk exit **and** on backgrounding | Guardian scope live in a child's hands — the real failure mode, not the child seeing a menu. |
| Session tokens revoked server-side on defeat | The app losing focus does not invalidate a JWT. |
| Deny-by-default `canRender` | An unlisted surface being reachable. |

## Migration notes

Three groups of columns ship ahead of the features that consume them, because
each is cheap now and a migration-with-backfill later:

| Column | Feature | Ships |
|---|---|---|
| `media_artifact.preserved` | Year Book | Phase 3 |
| `sibling_link` | group calls, split-placement contact | Phase 2 |
| `guardianship.closed_at` | succession | Phase 4 |

`guardianship.supervised` does **not** exist. It was removed in v0.4.0 and
replaced by `contact_ladder` — a boolean cannot express reunification.

## Before Phase 0 ships

MASTERFILE.md's own §20 "Phase 0 review" now tracks this more rigorously
than this list ever did; cross-checked against it directly below.

- [ ] §16.2 #1 — product name cleared. **Still open** — MASTERFILE's own
      header confirms USPTO/app-store collision clearance has not happened.
- [x] RLS policy tests: prove the child role cannot read `expense` or another
      child's `child_journal_entry` (P6, P7). **COMPLETE since v0.49.42**
      (PR #67, round-5 audit). The `child_journal_entry` half was already
      proven (`db/test/0003_session.test.sql`'s real `assert_eq` pairs); the
      `expense` half — a real `expense_no_child` RLS policy and a real
      FORCE-RLS structural check existed, but the behavioral proof of an
      actual denied read did not — is now closed too: `db/test/0005_court.test.sql`
      proves a `child`-role session sees zero rows on a real expense row
      while a `guardian`-role session sees the same row (proving the denial
      is the policy, not an empty table), live-Postgres-verified including a
      superuser-bypasses-RLS negative control.
- [x] `policy_has_target` CHECK exercised for all six delivery policies.
      **COMPLETE since v0.49.42** (PR #67, round-5 audit). The constraint
      itself always covered all six branches (`db/migrations/0001_phase0_init.sql`);
      `db/test/0001_constraints.test.sql` now has adversarial probes for all
      six, not just three — `at_instant`, `on_event`, and `immediate` each
      gained a must_fail/must_pass pair, live-Postgres-verified.
- [x] Nightly rematerialization sweep + the event-driven invalidation hooks.
      **COMPLETE since v0.49.43** (PR #68). The invalidation guarantee was
      already real and proven (`materialize()`'s own "future + undelivered
      only" behavior, `delivery.test.mjs`'s 37 probes); the sweep half — no
      cron or scheduler anywhere in this repo actually called it — is now
      closed by `tools/scheduler.mjs`, a real Postgres advisory-lock-guarded
      job runner (`rematerialize` + `health-alert` jobs). Wired into
      `docker-compose.dev.yml`/`docker-compose.prod.yml` as an **opt-in**
      Compose service (a background sweep is a real footgun against a live
      debug session, so it is not part of the default `up -d`) — an operator
      must explicitly turn it on (`--profile scheduler`), which is a real,
      deliberate deployment choice, not an unclosed gap in the code itself.
      See `scaffold/docs/scheduler.md`.
- [x] Single-guardian mode verified end to end with no second guardian row
      (§17.1). **COMPLETE since v0.49.6** — MASTERFILE §20.1.

Phase 0 has, in fact, long since shipped, and this list was more done than
its all-unchecked state implied. As of v0.49.43, every item on it is closed
except one: the product name is still the only simply, entirely open item —
a real business/legal decision, not a code gap.
