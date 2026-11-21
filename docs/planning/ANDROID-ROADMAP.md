# Android roadmap (living status)

Snapshot re-written 2026-11-21 against `origin/main` at 58c25ff (merged through PR #234). It was first written 2026-11-14 at 8440203. Android comes first and is completed first; iOS lives in `docs/roadmaps/IOS-ROADMAP.md` and starts only when the owner says Android is complete.

Direction in force: **offline-first and on-device**. Online features (network calls, push, network invites, any server relay) stay parked behind honest "later" states, never fake success. The server runs in Docker for now. Calls will use the self-hosted Jitsi stack (see [HOSTING-AND-CALLS.md](HOSTING-AND-CALLS.md)). The server-side delivery worker is no longer parked: it only moves rows inside the server's own database and the app reads by polling its inbox, so it neither needs credentials nor gates local use (MASTERFILE section 7.16). The Android screens that use it (media player, sender receipts, bedtime and zone settings) are still to build.

Every gap between the planned family features and the shipped code is in [GAP-REGISTER.md](GAP-REGISTER.md); this file says what is done and what comes next.

## Merged so far (main)

Foundations and hardening: server hardening (#137), real authenticated session (#138), on-device LocalStore (#141), performance pass (#146), non-superuser migration fix (#164), security round 2 (#158), domain correctness (#160), server snoop hardening (#172), security follow-ups including the PIN step-up client, first-PIN passkey check, PIN recovery from a second grown-up's phone and the S-B11 least-privilege runtime role (#180), health counters under FORCE RLS (#177).

Offline product waves: family structure and age bands (#139), colour of the day, play window and Settings hub (#140), Growing/Care (#142), Rhythm/Voice (#143), accessibility and read-aloud (#144), Village/Compass (#147), role-first first run with local family and local PIN (#155), label adoption (#153), prohibition fixes (#159), age-band homes 5-7 and 8-12 (#165), guardian home and Settings hub (#166), her colour and art, child side of the play window and family structure (waves 4 and 5, #175), 13-17 home, teen privacy contract and 18 handover (wave 2b, #183), care and coordination on this device (wave 9a, #184), child creative and feelings (wave 6a, #186), local suites parity (wave 7, #191), daily time enforcement and the expiry-digest reader (#189), adult safety: app lock, hidden recents, quick hide (#190), app-lock PIN field fix (#193).

Design parity: tokens (#151), component library (#156), JetBrains Mono (#163), parity harness (#161).

Adult gate and pairing: adult gate and PIN-primary pairing (#167), phone unlock and Forget this tablet (#170), play admission (#171), pairing leak fixes (nameless discovery, no child error screen, per-source attempt budget, #196), the persistent pairing picture with Match, Settle in and Keep watch (#197).

Play together: play envelope, shared game contract, calm session end and resume (#173), play wiring into every game (#182).

Calls and operations: self-hosted Jitsi default with LiveKit selectable (#178), the ten-family simulation and watchable control room (#179).

Planning and design documents: planning files (#185), external crypto review brief and two-device pairing test plan (#194), family identity design (#195), village welcome design (#199).

Since the first snapshot (#200 to #234): the care-guide drafts (#200), the family sync and notification design (#201), the spec amendments and gap register (#202), the release-launch crash fix and its CI guards (#204, #210), CPace draft-21 conformance (#211), pairing hardening (#214), an integration of the dev screenshot switch, the pairing copy, the family identity core, the About her profile and the care-guide engine (#215), the delivery chain (#220), integration wave 3 (#223: the clock-dependent family-simulation fix, the connected tablet opening from the device, the village welcome screens, the family sync first slice, the screenshots setting and in-app share), the server integration of the identity lane, the live chain and push and calls (#225, migrations 0050 to 0052), the dev-stack rebuild and the live-stack move runbook (#226), the client integration of the child receive path, the family account and Android push and calls (#230), and the last integration (#234: dev-only cleartext, housekeeping tools, account recovery and claim without email with the child's message player, the media3 duplicate-class fix).

Releases: 0.50.0 (#149), 0.51.0 (#168, tag `v0.51.0`), small wins batch (#174). No release has been cut since 0.51.0.

## In flight (at snapshot time)

| Work | What | Notes |
|---|---|---|
| PR #176 | iOS inert scaffold and roadmap | iOS compile job is advisory only; on hold by owner direction; not touched by Android work. |
| Wave 4b lane | Village welcome wiring; the screenshot share and family sync wiring; compose and send; the day-part editor | Not yet a PR. Wiring only: the screens and engines are built (see Status below). |
| Lost-phone and recovery lane | Mark as lost; account recovery follow-ups; encrypted backup (server and client); a data-loss harness | Not yet a PR. |
| This PR | Release hygiene and docs parity | Network config and backup rules, placeholders in docs, and the canonical documents re-read against shipped code. |

Closed without merging: #181 (the `ubuntu-24.04` runner pin is already on main), #187 and #188 (CI probes). Closed after being folded into an integration PR: #205 to #209, #212, #213, #216 to #218, #221 to #224 and #227 to #229; #231 to #233 were merged through #234.

Branches kept for later, not PRs: `feat/live-server-bake` (adult-only Server address setting, tunnel work stopped), `feat/vps-deploy-kit` (Oracle/Hetzner kit, paused), `feature/secure-network-play` (older server-mediated network play work), `feat/play-admission-wiring`.

## Wave plan (what comes next, in order)

The family features share one dependency: **a real family object** (see GAP-REGISTER G-01). Waves below are ordered by that dependency and by the gates; each wave is a set of small independent PRs.

| Wave | Content | Depends on | Gate |
|---|---|---|---|
| A. Assurance and docs (now) | This PR; refresh the crypto review brief to current main; update the two-device test plan's discovery step; send the clinician packet; the lead runs the two-device pairing pass on the Fold 5 and the tablet. | Nothing | None; they start the long-lead gates |
| B. Child-side hygiene | Replace the standalone code screen a signed-out child device lands on with the calm card (G-03); call `TrustBook.observe` from the first service that contacts a tablet (G-26); force screenshot hiding on the picture and Match screens (G-27; done on the grown-up's pairing window and on every child root in the screenshot-setting PR, not yet run on a device). | Nothing | Child-first rule |
| C. Family foundation | FAMILY-IDENTITY PRs 1 to 4: ledger core, family state and founding, pairing channel v2, child holds the family. | Wave A brief refresh | External crypto review of the ledger (scope two) before real families |
| D. Second grown-up and removal | Identity PRs 5 to 7: second grown-up joins, connections and removal, key rotation; lost-tablet revocation. | Wave C | None beyond C |
| E. Village welcome, local-first | VILLAGE-WELCOME W1 to W9, with the design edited first so a limit on a parent restricts only actions (G-35). | Waves C and D | Usability read with real parents; counsel on the limits agreement |
| F. About Mia profile | Guardian-only, on the device, grows the care binder; per-person sharing waits for Wave E. | Can start now for the single-guardian part | Counsel on the care-note exception (G-38); clinician review of every app-written string |
| G. Care guides library | Offline library, reviewed date, region setting, the "For Mia" strip, the new-carer arrival links. | Clinician sign-off per guide | **Hard gate: nothing ships without sign-off** |
| H0. Family sync, first slice | Built: signed sealed events, the engine, a copy-and-paste update, the emergency card shared and chosen between two grown-ups' phones (FAMILY-SYNC S1 to S3, road E, S5 card half). Not reachable from any menu until Waves C and D wire founding and the second grown-up's join. Next: same-Wi-Fi road (S4), medicines and doses (S6), About Mia, receipts, then the mailbox (S10 to S11). | Waves C and D to be reachable | Outside crypto review (brief addendum); two-phone run |
| H. Server-backed family | Family tenant migration, routes and sync, the pause flag (identity PRs 8 and 9, W10). The edge-creating routes, invite-only sign-up and the env-driven relying party shipped in the identity lane (migration 0050, MASTERFILE 7.17); the family tenant itself did not. The grown-up client for those routes (make an account, sign in, add a child, invite and confirm another grown-up; optional, resumable, adult words) is built and tested headless and once against a real server, not run on a device (MASTERFILE 8.5.13). | Waves C and E; the S-D26 text | Ten-family simulation with cross-family probes: zero isolation misses |
| I. Parity docs | MASTERFILE, CHANGELOG, MARKUP and the demo shell updated with each shipped wave; totals set from CI by the lead. | Each wave | None |

## Wave status at 58c25ff

The table above is the plan as written; this is where each wave stands.

- **A.** Done: the review brief, the test plan, the design documents. The two-device pairing pass has not been run by a person.
- **B.** Pairing hardening merged (#196, #213, #214).
- **C.** The ledger core, the two keys and the local-family migration are built and tested, **not wired into pairing** (MASTERFILE 8.5.12).
- **D.** Not built (second grown-up joining as a ledger member, removal, key rotation).
- **E.** The request, approval and profile screens are built headless and **not reachable** (MASTERFILE 8.28); wiring is in flight.
- **F.** The About her profile is built on one phone (MASTERFILE 8.24.8); sharing between phones waits for C to E.
- **G.** The care-guide engine is built and gated (MASTERFILE 8.30); no guide is reviewed or shipped.
- **H0.** The first family sync slice is built (the emergency card between two grown-ups' phones, by copy and paste), not reachable from any menu until C and D wire it; wiring is in flight. **H.** The server half of identity (migrations 0050 to 0053), the delivery chain and readiness are merged; the family tenant is not.
- **I.** This PR re-reads MASTERFILE, DECISIONS, MARKUP and the demo against the code; totals come only from CI.

## Remaining (Android), by lane

Lane A, child experience: Wave 8 child games parity (#192) is merged, with Wave 6a and Wave 7.

Lane B, guardian and care: the Wave 9a offline care UI, daily-time enforcement plus the expiry-digest reader and adult safety are merged. What remains is the family work above (Waves C to G).

Lane C, server and security (starts when capacity frees): the security findings still listed as not shipped in MASTERFILE section 7.12 (S-B2, S-B7, S-B10, S-B12 and others; re-check which section 7.12.1 closed), the family tenant isolation (S-D26, Wave H), the server-backed half of Wave 9 (9b), the open domain findings listed in section 7.13.

Lane D, release and QA (starts last): store-readiness audit, release cut 0.52, real-device test plan and runs, the 10-family simulation as a standing check.

Parked online items (need credentials or hosting): calls over the internet, push (FCM and APNs; the server sender, the delivery worker and the invite-only sign-up are built, see OPERATIONS-RUNBOOK and MASTERFILE 7.16 to 7.18, and the Android client side is built without any credential, MASTERFILE 7.20: guarded token registration, notification channels, a native knock for a closed app, the availability and call-log client; nothing has run against Google or on a device, and it needs the owner's Firebase project), network invites, networked games beyond the encrypted relay, the public server address, relaying a pairing window through the server.

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
