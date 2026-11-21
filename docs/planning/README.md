# Olive Branch planning files

This folder is the project's planning record, kept in the repository so it is versioned, reviewable and survives any one machine or chat session. The spec of record is `MASTERFILE.md`; these files say **what we decided, what is in flight, what is left, and how to resume**.

| File | What it holds |
|---|---|
| [ANDROID-ROADMAP.md](ANDROID-ROADMAP.md) | The Android-first roadmap: what has merged, what is in flight, what remains, the team lanes and the completion gate. |
| [DECISIONS.md](DECISIONS.md) | Owner decisions already taken (the rules every contributor must follow). |
| [OPEN-DECISIONS.md](OPEN-DECISIONS.md) | Decisions still open, each with a recommendation. |
| [HOSTING-AND-CALLS.md](HOSTING-AND-CALLS.md) | Where the server runs and how calls work: options researched, the chosen direction, what was scrapped, store-distribution and multi-family readiness plans. |
| [OPERATIONS-RUNBOOK.md](OPERATIONS-RUNBOOK.md) | How to resume work: CI rules and gotchas, the merge procedure, the device-push recipe, the Docker stack, memory limits. |
| [GAP-REGISTER.md](GAP-REGISTER.md) | Every gap between the planned family features (persistent QR, village welcome, About Mia, care guides, family sync) and the shipped code and spec, classed blocking / spec amendment / build item / decision / assurance gate, with evidence, fix and owner. |
| [BACKUP-AND-RESTORE.md](BACKUP-AND-RESTORE.md) | Built on the client, CI-verified only: encrypted backup (family, her keepsakes, her private areas), restore onto a new phone and a replacement tablet, the formats, the server wire that is not built, and the owner decisions BK-1 to BK-5. |
| [FAMILY-IDENTITY-DESIGN.md](FAMILY-IDENTITY-DESIGN.md) | Design (not built): one family id and key, a signed ledger, a second grown-up joining, removal, key rotation, the server family tenant. |
| [VILLAGE-WELCOME-DESIGN.md](VILLAGE-WELCOME-DESIGN.md) | Design (not built): adults approving new adults, permission profiles, time boxes, pause and end, the limits agreement. |
| [PERSISTENT-QR-PAIRING.md](PERSISTENT-QR-PAIRING.md) | The persistent pairing picture: design, decisions and build status (built in PR #197, not run on two real devices). |
| [QR-VETTING-BRAINSTORM.md](QR-VETTING-BRAINSTORM.md) | The owner-facing brainstorm: welcoming devices and people, the About Mia profile and the care guides, adopted decisions. (The reshaped version is on open PR #198.) |
| [EXTERNAL-CRYPTO-REVIEW-BRIEF.md](EXTERNAL-CRYPTO-REVIEW-BRIEF.md) | The brief for an outside cryptographer to review the pairing key exchange. Predates PRs #196 and #197; refresh before sending. |
| [TWO-DEVICE-PAIRING-TEST-PLAN.md](TWO-DEVICE-PAIRING-TEST-PLAN.md) | The run sheet for the first real two-device pairing test. Its discovery step predates PR #196; update before running. |
| [FAMILY-SYNC-DESIGN.md](FAMILY-SYNC-DESIGN.md) | Design; the first slice (emergency card, copy-and-paste update) is built but not reachable from any menu: how guardian devices share data as sealed, signed event logs over several roads (same Wi-Fi, mailbox, hand-carried file), conflicts, notifications, threat model and build order. |

Related documents elsewhere in the repo:

- `docs/roadmaps/IOS-ROADMAP.md` — the separate iOS roadmap (on hold until the owner says Android is complete).
- `docs/superpowers/parity/` — the prototype-to-Flutter parity matrix, build plan and ledger.
- `docs/superpowers/research/` — research reports (GameSuite multiplayer for Play together).
- `docs/superpowers/specs/` — design specs (adult gate and pairing, server snoop hardening, and others).
- `docs/care-guides/` — the care guide drafts and the clinician review packet (merged, PR #200; `DRAFT_UNREVIEWED`, not for use by anyone yet) and `CLINICIAN-COVER-LETTER.md`, the ready-to-send letter and one-page checklist for the reviewers.
- `docs/RELEASING.md` — how a version is cut and published.
- `docs/operators/` — operator notes (proxy and TLS, certificate pinning, and others).

## Keeping this folder in sync

1. When a PR merges that changes status, update the relevant row in `ANDROID-ROADMAP.md` in the same PR or the next one.
2. When the owner decides something, move it from `OPEN-DECISIONS.md` to `DECISIONS.md` with the date.
3. Never put secrets, personal data, device serials, IP addresses or account details in these files. The repository is public.
4. A planned feature appears in MASTERFILE only under a heading or lead-in that says PLANNED, NOT BUILT, and every gap that stops it is a row in `GAP-REGISTER.md`.
5. Anything that exists only on one machine (a local branch, an uncommitted worktree, a published artifact) should be pushed or linked here so nothing depends on one disk.
