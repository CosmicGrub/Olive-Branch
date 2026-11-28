# Onboarding extension ledger

This ledger lists user-visible features that have merged to `main` since the onboarding baseline and still have **no onboarding entry**. It exists so the guided first run (see [ONBOARDING-SCOPE.md](ONBOARDING-SCOPE.md), section 15) never silently falls behind the app.

**Baseline.** App version 0.51.0 (build 5100), `origin/main` at commit `6e4f9249` on 2026-11-21. Onboarding script version at baseline: none yet (the script is not built; v1 is the scope's version 1).

## The rule

When **more than four** user-visible features are waiting in the table below, the onboarding must be extended before the next release is cut: each waiting feature gets an entry (template in the scope, section 15.4; slots as in the script) in its proposed slot, `onboardingVersion` is raised, and the rows move to the "Done" table.

A PR that adds a user-visible feature adds a row here in the same PR (or adds the onboarding entry itself). Fixes, refactors, tests, docs and server-only changes are not listed.

## Waiting (no onboarding entry yet)

| Feature | PR | Merged date | User-visible side | Onboarding slot proposed | Status |
|---|---|---|---|---|---|
| App updates from GitHub releases (check, download, install) | #260, #262 | 2026-11-23 | adult | adult.tour.features | waiting |
| "Her tablet" one button (banner, state, connect, disconnect) | #258 | 2026-11-28 | both | adult.tour.features | waiting |

Count waiting: 2 of 4.

## Done (entry added)

| Feature | PR | Merged date | Side | Slot | Entry id | Script version |
|---|---|---|---|---|---|---|
| (none) | | | | | | |

## How to fill a row

- Side: adult, child or both.
- Slot: one of the slots in ONBOARDING-SCRIPT.md (usually `adult.tour.features` for a grown-up tour stop, or `child.extra` for a child icon label).
- Status: `waiting`, `entry drafted`, or `deferred (reason)`.
