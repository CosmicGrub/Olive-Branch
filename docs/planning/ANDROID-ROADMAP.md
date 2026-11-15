# Android roadmap (living status)

Snapshot written 2026-11-14 against `origin/main` at 8440203 (merged through PR #199). Android comes first and is completed first; iOS lives in `docs/roadmaps/IOS-ROADMAP.md` and starts only when the owner says Android is complete.

Direction in force: **offline-first and on-device**. Online features (network calls, push, the delivery worker, network invites, any server relay) stay parked behind honest "later" states, never fake success. The server runs in Docker for now. Calls will use the self-hosted Jitsi stack (see [HOSTING-AND-CALLS.md](HOSTING-AND-CALLS.md)).

Every gap between the planned family features and the shipped code is in [GAP-REGISTER.md](GAP-REGISTER.md); this file says what is done and what comes next.

## Merged so far (main)

Foundations and hardening: server hardening (#137), real authenticated session (#138), on-device LocalStore (#141), performance pass (#146), non-superuser migration fix (#164), security round 2 (#158), domain correctness (#160), server snoop hardening (#172), security follow-ups including the PIN step-up client, first-PIN passkey check, PIN recovery from a second grown-up's phone and the S-B11 least-privilege runtime role (#180), health counters under FORCE RLS (#177).

Offline product waves: family structure and age bands (#139), colour of the day, play window and Settings hub (#140), Growing/Care (#142), Rhythm/Voice (#143), accessibility and read-aloud (#144), Village/Compass (#147), role-first first run with local family and local PIN (#155), label adoption (#153), prohibition fixes (#159), age-band homes 5-7 and 8-12 (#165), guardian home and Settings hub (#166), her colour and art, child side of the play window and family structure (waves 4 and 5, #175), 13-17 home, teen privacy contract and 18 handover (wave 2b, #183), care and coordination on this device (wave 9a, #184), child creative and feelings (wave 6a, #186), local suites parity (wave 7, #191), daily time enforcement and the expiry-digest reader (#189), adult safety: app lock, hidden recents, quick hide (#190), app-lock PIN field fix (#193).

Design parity: tokens (#151), component library (#156), JetBrains Mono (#163), parity harness (#161).

Adult gate and pairing: adult gate and PIN-primary pairing (#167), phone unlock and Forget this tablet (#170), play admission (#171), pairing leak fixes (nameless discovery, no child error screen, per-source attempt budget, #196), the persistent pairing picture with Match, Settle in and Keep watch (#197).

Play together: play envelope, shared game contract, calm session end and resume (#173), play wiring into every game (#182).

Calls and operations: self-hosted Jitsi default with LiveKit selectable (#178), the ten-family simulation and watchable control room (#179).

Planning and design documents: planning files (#185), external crypto review brief and two-device pairing test plan (#194), family identity design (#195), village welcome design (#199).

Releases: 0.50.0 (#149), 0.51.0 (#168, tag `v0.51.0`), small wins batch (#174). No release has been cut since 0.51.0.

## In flight (open PRs at snapshot time)

| PR | What | Notes |
|---|---|---|
| #192 | Wave 8: child games parity | Last item of Lane A. |
| #176 | iOS inert scaffold and roadmap | iOS compile job is advisory only; on hold by owner direction. |
| #198 | Docs: reshape the QR brainstorm and mockups for welcoming people into the village | Adds the About Mia profile and care guides sections. Docs only. |
| this PR | Docs: spec amendments, gap register, roadmap, clinician cover letter | Docs only, marked PLANNED where not built. |

Closed without merging: #181 (the `ubuntu-24.04` runner pin is already on main), #187 and #188 (CI probes).

Branches kept for later, not PRs: `feat/live-server-bake` (adult-only Server address setting, tunnel work stopped), `feat/vps-deploy-kit` (Oracle/Hetzner kit, paused), `feature/secure-network-play` (older server-mediated network play work), `feat/play-admission-wiring`.

## Wave plan (what comes next, in order)

The family features share one dependency: **a real family object** (see GAP-REGISTER G-01). Waves below are ordered by that dependency and by the gates; each wave is a set of small independent PRs.

| Wave | Content | Depends on | Gate |
|---|---|---|---|
| A. Assurance and docs (now) | This PR; refresh the crypto review brief to current main; update the two-device test plan's discovery step; send the clinician packet; the lead runs the two-device pairing pass on the Fold 5 and the tablet. | Nothing | None; they start the long-lead gates |
| B. Child-side hygiene | Replace the standalone code screen a signed-out child device lands on with the calm card (G-03); call `TrustBook.observe` from the first service that contacts a tablet (G-26); force screenshot hiding on the picture and Match screens (G-27). | Nothing | Child-first rule |
| C. Family foundation | FAMILY-IDENTITY PRs 1 to 4: ledger core, family state and founding, pairing channel v2, child holds the family. | Wave A brief refresh | External crypto review of the ledger (scope two) before real families |
| D. Second grown-up and removal | Identity PRs 5 to 7: second grown-up joins, connections and removal, key rotation; lost-tablet revocation. | Wave C | None beyond C |
| E. Village welcome, local-first | VILLAGE-WELCOME W1 to W9, with the design edited first so a limit on a parent restricts only actions (G-35). | Waves C and D | Usability read with real parents; counsel on the limits agreement |
| F. About Mia profile | Guardian-only, on the device, grows the care binder; per-person sharing waits for Wave E. | Can start now for the single-guardian part | Counsel on the care-note exception (G-38); clinician review of every app-written string |
| G. Care guides library | Offline library, reviewed date, region setting, the "For Mia" strip, the new-carer arrival links. | Clinician sign-off per guide | **Hard gate: nothing ships without sign-off** |
| H. Server-backed family | Family tenant migration, routes and sync, the edge-creating route, the pause flag (identity PRs 8 and 9, W10). | Waves C and E; the S-D26 text | Ten-family simulation with cross-family probes: zero isolation misses |
| I. Parity docs | MASTERFILE, CHANGELOG, MARKUP and the demo shell updated with each shipped wave; totals set from CI by the lead. | Each wave | None |

## Remaining (Android), by lane

Lane A, child experience: Wave 8 child games parity (#192). Wave 6a and Wave 7 are merged.

Lane B, guardian and care: the Wave 9a offline care UI, daily-time enforcement plus the expiry-digest reader and adult safety are merged. What remains is the family work above (Waves C to G).

Lane C, server and security (starts when capacity frees): the security findings still listed as not shipped in MASTERFILE section 7.12 (S-B2, S-B7, S-B10, S-B12 and others; re-check which section 7.12.1 closed), the family tenant isolation (S-D26, Wave H), the server-backed half of Wave 9 (9b), the open domain findings listed in section 7.13.

Lane D, release and QA (starts last): store-readiness audit, release cut 0.52, real-device test plan and runs, the 10-family simulation as a standing check.

Parked online items (need credentials or hosting): calls over the internet, push (FCM and APNs), the delivery worker, network invites, networked games beyond the encrypted relay, the public server address, relaying a pairing window through the server.

## Gates before real families rely on any of this

1. External cryptographic review of the custom key exchange, the Match derivation and (when built) the ledger.
2. A real two-device run of pairing, the picture in both directions, Match, unlock and a forgotten tablet.
3. Clinician review of each care guide (and a first-aid instructor for choking and CPR), guide by guide.
4. Counsel on the care-note exception and the limits agreement.
5. The ten-family simulation with zero isolation misses.

## Completion gate for "Android complete"

The owner decides, but the proposed gate is: offline parity waves merged; the 10-family simulation passes with zero isolation misses; the server runs from a documented, repeatable Docker deployment; store-readiness audit done; a release cut verified on both test devices (Fold 5 and tablet); and the gates above that apply to the features shipped in that cut. When the owner declares Android complete, the iOS roadmap's waves may start.

## Team operating rules

- At most two to three agents run heavy Flutter or Gradle work at once; the machine has limited memory (see the runbook).
- Each agent works in its own git worktree and branch, never in another agent's files.
- Totals (`MARKUP.html` line 20, `scaffold/demo/shell.html`, `scaffold/package.json`) always come from CI's `COMPUTED TOTAL`, never from arithmetic.
- Agents may merge their own PR only when `verify` and `image` are green and the PR is clean; otherwise they report.
