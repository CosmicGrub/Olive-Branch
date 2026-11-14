# Android roadmap (living status)

Snapshot written 2026-11-14. Android comes first and is completed first; iOS lives in `docs/roadmaps/IOS-ROADMAP.md` and starts only when the owner says Android is complete.

Direction in force: **offline-first and on-device**. Online features (network calls, push, the delivery worker, network invites, any server relay) stay parked behind honest "later" states, never fake success. The server runs in Docker for now. Calls will use the self-hosted Jitsi stack (see [HOSTING-AND-CALLS.md](HOSTING-AND-CALLS.md)).

## Merged so far (main)

Foundations and hardening: server hardening (#137), real authenticated session (#138), on-device LocalStore (#141), performance pass (#146), non-superuser migration fix (#164), security round 2 (#158), domain correctness (#160), server snoop hardening (#172).

Offline product waves: family structure and age bands (#139), colour of the day, play window and Settings hub (#140), Growing/Care (#142), Rhythm/Voice (#143), accessibility and read-aloud (#144), Village/Compass (#147), role-first first run with local family and local PIN (#155), label adoption (#153), prohibition fixes (#159), age-band homes 5-7 and 8-12 (#165), guardian home and Settings hub (#166).

Design parity: tokens (#151), component library (#156), JetBrains Mono (#163), parity harness (#161).

Adult gate and pairing: adult gate and PIN-primary pairing (#167), phone unlock and Forget this tablet (#170), play admission (#171).

Play together: play envelope, shared game contract, calm session end and resume (#173).

Releases: 0.50.0 (#149), 0.51.0 (#168, tag `v0.51.0`), small wins batch (#174).

## In flight (open PRs at snapshot time)

| PR | What | Notes |
|---|---|---|
| #181 | CI: pin runners to ubuntu-24.04 | `ubuntu-latest` became 26.04 and broke every database suite; also corrects the assertion total. Merge first. |
| #175 | Waves 4 and 5: her colour and art, child side of the play window, family structure and history | Needs a fresh CI run after #181. |
| #176 | iOS inert scaffold and roadmap | iOS compile job is advisory only. |
| #177 | Fix health_check views reading 0 under FORCE RLS | Monitoring blind spot. |
| #178 | Calls: self-hosted Jitsi default, LiveKit selectable | Provider switch. |
| #179 | Ten-family simulation and watchable control room | Isolation, onboarding gaps, performance. |
| #180 | Security follow-ups | Client PIN step-up, first-PIN passkey check, PIN recovery, S-B11 if it fits. |

Branches kept for later, not PRs: `feat/live-server-bake` (adult-only Server address setting, tunnel work stopped), `feat/vps-deploy-kit` (Oracle/Hetzner kit, paused), `feature/secure-network-play` (older server-mediated network play work), `feat/wave2b-teen-home` (13-17 home and 18 handover, pushed, in progress), `feat/play-admission-wiring`.

## Remaining (Android)

Lane A, child experience (in order): Wave 6a creative and feelings, Wave 7 local suites parity, Wave 8 child games parity.

Lane B, guardian and care (in order): Wave 9a care and coordination offline UI, daily-time enforcement plus expiry-digest reader, adult safety (app lock, recents blur, quick hide).

Lane C, server and security (starts when capacity frees): the rest of the security findings (S-B2, S-B7, S-B10, S-B12 and others), the family tenant isolation (S-D26), the server-backed half of Wave 9 (9b), the open domain findings (S-D3 to S-D5, S-D16 to S-D18, S-D24 to S-D27).

Lane D, release and QA (starts last): store-readiness audit, release cut 0.52, real-device test plan and runs, the 10-family simulation as a standing check.

Parked online items (need credentials or hosting): calls over the internet, push (FCM and APNs), the delivery worker, network invites, networked games beyond the encrypted relay, the public server address.

## Completion gate for "Android complete"

The owner decides, but the proposed gate is: offline parity waves merged; the 10-family simulation passes with zero isolation misses; the server runs from a documented, repeatable Docker deployment; store-readiness audit done; a release cut verified on both test devices (Fold 5 and tablet). When the owner declares Android complete, the iOS roadmap's waves may start.

## Team operating rules

- At most two to three agents run heavy Flutter or Gradle work at once; the machine has limited memory (see the runbook).
- Each agent works in its own git worktree and branch, never in another agent's files.
- Totals (`MARKUP.html` line 20, `scaffold/demo/shell.html`, `scaffold/package.json`) always come from CI's `COMPUTED TOTAL`, never from arithmetic.
- Agents may merge their own PR only when `verify` and `image` are green and the PR is clean; otherwise they report.
