# Olive Branch planning files

This folder is the project's planning record, kept in the repository so it is versioned, reviewable and survives any one machine or chat session. The spec of record is `MASTERFILE.md`; these files say **what we decided, what is in flight, what is left, and how to resume**.

| File | What it holds |
|---|---|
| [ANDROID-ROADMAP.md](ANDROID-ROADMAP.md) | The Android-first roadmap: what has merged, what is in flight, what remains, the team lanes and the completion gate. |
| [DECISIONS.md](DECISIONS.md) | Owner decisions already taken (the rules every contributor must follow). |
| [OPEN-DECISIONS.md](OPEN-DECISIONS.md) | Decisions still open, each with a recommendation. |
| [HOSTING-AND-CALLS.md](HOSTING-AND-CALLS.md) | Where the server runs and how calls work: options researched, the chosen direction, what was scrapped, store-distribution and multi-family readiness plans. |
| [OPERATIONS-RUNBOOK.md](OPERATIONS-RUNBOOK.md) | How to resume work: CI rules and gotchas, the merge procedure, the device-push recipe, the Docker stack, memory limits. |

Related documents elsewhere in the repo:

- `docs/roadmaps/IOS-ROADMAP.md` — the separate iOS roadmap (on hold until the owner says Android is complete).
- `docs/superpowers/parity/` — the prototype-to-Flutter parity matrix, build plan and ledger.
- `docs/superpowers/research/` — research reports (GameSuite multiplayer for Play together).
- `docs/superpowers/specs/` — design specs (adult gate and pairing, server snoop hardening, and others).
- `docs/RELEASING.md` — how a version is cut and published.
- `docs/operators/` — operator notes (proxy and TLS, certificate pinning, and others).

## Keeping this folder in sync

1. When a PR merges that changes status, update the relevant row in `ANDROID-ROADMAP.md` in the same PR or the next one.
2. When the owner decides something, move it from `OPEN-DECISIONS.md` to `DECISIONS.md` with the date.
3. Never put secrets, personal data, device serials, IP addresses or account details in these files. The repository is public.
4. Anything that exists only on one machine (a local branch, an uncommitted worktree, a published artifact) should be pushed or linked here so nothing depends on one disk.
