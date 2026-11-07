# Co-viewing ("Read together" / "Watch together") — design

Status: **DRAFT — owner decisions 1–4 recorded 2026-11-07 (§5); sub-questions on decisions 2 and 3 still open.** No app code has been written or changed. The only files added are two design-stage
models under `scaffold/tools/co-viewing-model/` (not wired into `verify.sh`). Date: 2026-11-07.

Origin: the owner asked whether the away-parent loop can run past two hours, e.g. streaming a kids' show or sharing
a screen so the child watches along with low latency. (The "2 hours" was only the length of the pilot acceptance
test, not a product limit.)

## 1. Verdict

1. **Duration is not the hard part.** I found no call-duration cap in the code or the LiveKit quota docs I could
   read. The real long-session risks are (a) the 1 h paired-device token with no refresh route (known spine gap),
   (b) LiveKit join-token TTL ("minutes, not hours", `livekit-token.ts`), whose effect on a connected,
   hours-long session I could **not** confirm, and (c) Android stopping screen capture when the screen locks.
2. **Share-your-screen is the wrong primary mechanism on Android, for four independent reasons** (§3). The right
   primary mechanism is **synced playback inside Olive**: both devices play the same content, and only small
   control messages cross the network.
3. **Build in this order:** Read together (in-app, one guardian-controlled view) → Watch together (synced
   playback of content the family owns) → Share an app (Android 14+ single-app share, only if still wanted).

## 2. What exists today (verified in the repo)

| Fact | Where |
|---|---|
| Official `livekit_client ^2.8.1` is the call SDK | `scaffold/client/pubspec.yaml:21` |
| A `CallPolicy` already exists: `screenShare: 'window_only' \| 'disabled'`, notifications suppressed while sharing, and a fault list incl. `whole_screen_share` | `packages/session-runtime/src/security.ts` |
| That policy has **no live enforcement**; the file says the LiveKit-era call screen has no real screen-share feature at all | same file, header comment |
| Spec §5.21.2: share is scoped to one window, never whole screen; notifications suppressed; a plain-words preflight; **camera and mic released the instant the app loses focus** | `MASTERFILE.md:5545` |
| Spec §5.21.3: ordinary calls are E2EE with no recording; supervised calls are the reverse and disclosed | `MASTERFILE.md:5558` |
| Screenshare frames are already classed as incidental capture "on a clock", shown in the expiry digest | `MASTERFILE.md:3476` |
| Call tokens are minted with a short TTL and explicit publish/subscribe/data grants | `packages/session-runtime/src/livekit-token.ts` |
| A WebSocket table-sync channel already exists for ad-hoc play | `packages/game-sync`, `server/test/game_tables.test.mjs` |

## 3. Research findings (with verification status)

| # | Finding | Source | Status |
|---|---|---|---|
| R1 | Flutter entry point is `room.localParticipant.setScreenShareEnabled(true)`. Android needs a `mediaProjection` foreground service; LiveKit's docs point at the `flutter_background` plugin's service. | [LiveKit screen-share docs](https://docs.livekit.io/transport/media/screenshare/) | Read directly. Exact signature to confirm against `^2.8.1`. |
| R2 | LiveKit's docs describe **audio sharing only for browsers** (tab audio). Nothing says Flutter/Android can publish captured app audio. | same | Read directly. **A silent shared show is plausible; must test.** |
| R3 | Android requires user consent for **every** capture session; a session is one `createVirtualDisplay()`; a token is single-use. | [Android media projection](https://developer.android.com/media/grow/media-projection) | Read directly. |
| R4 | Android 14+ offers single-app sharing by default; system UI (status bar, notifications) is excluded. Apps can opt out only to force full-screen, and OEMs may override that. | same | Read directly. |
| R5 | Capture **stops when the screen locks**, and on Android 15 QPR1+ a prominent status-bar chip lets the user stop it. `onStop()` must be handled. | same | Read directly. Hours-long sharing needs the parent's phone awake and unlocked. |
| R6 | Protected (DRM / `FLAG_SECURE`) content shows as a black frame to MediaProjection. | [2016 security write-up](https://wwws.nightwatchcybersecurity.com/2016/04/13/research-securing-android-applications-from-screen-capture/), [MWR advisory](https://labs.withsecure.com/content/dam/labs/docs/mwri-android-MediaProjection-tapjacking-advisory-2017-11-14.pdf) | **Weak:** old, secondary. Not tested against any specific streaming app. |
| R7 | LiveKit Build plan: 5,000 WebRTC participant-min/month, 50 GB/month downstream, 100 concurrent participants. Ship/Scale amounts and any max session length are **not stated** on the quotas page. | [LiveKit quotas](https://docs.livekit.io/cloud/quotas-and-limits) | Read directly (Build only). |
| R8 | Overage ≈ $0.0004/participant-min and ≈ $0.10–0.12/GB; plan tiers/prices differ between sources. | [trtc.io](https://trtc.io/blog/details/livekit-pricing-2026), others | **Unverified, secondary.** Re-check on [livekit.com/pricing](https://livekit.com/pricing). |
| R9 | Watch-party sync designs use: clock-offset estimation, a scheduled shared start, expected-position = last position + elapsed, a dead zone, rate-nudging in a soft zone, hard seek beyond ~2 s. Thresholds in the wild range 0.04–1.5 s. | [OpenWatchParty](https://mhbxyz.github.io/OpenWatchParty/technical/sync), [NoMercy](https://docs.nomercy.tv/nomercy-video-player/advanced/distributed-playback) | Community code, not a standard. Starting points only. |
| R10 | No measured LiveKit end-to-end latency figure was found. "<200 ms glass-to-glass" appears only as a generic design target. | search | **Unknown. Measure it (§8).** |

## 4. Why screen share is not the primary mechanism

1. **Sound (R2).** A show is half audio; Flutter/Android audio capture is undocumented in LiveKit's page.
2. **Black frames (R6).** Commercial streaming apps may render black. Olive cannot and should not work around DRM.
3. **Spec contradiction (§5.21.2 vs R4).** "Share one window" on Android 14+ means the parent picks *another app*.
   That puts Olive in the background, and §5.21.2 says camera/mic release the instant focus is lost.
   Either the rule gets a documented exception or the feature cannot meet its own spec.
4. **Fragility for long sessions (R3, R5).** Fresh consent per session, a status-bar chip anyone can tap,
   auto-stop on lock, and a foreground service. Fine for ten minutes, bad for a bedtime show.
5. **Cost shape.** Pushing video through the SFU meters bandwidth; syncing playback does not (§6).

It is still worth offering later ("Share an app", Android 14+, single app only) for homework help — the §5.21.2
fractions scenario — because there the content is the parent's own screen, not protected media.

## 5. Scope

### In scope

| Phase | Feature | What the child sees | What the guardian does |
|---|---|---|---|
| **1** | **Read together** | One large page-turning view; one big "Stop" button | Picks a story/book/drawing from content Olive already holds, turns pages; child's view follows |
| **2** | **Watch together** | The video, with a one-tap "Stop" | Picks a video the family owns or that was uploaded; play/pause/seek drives both |
| **3** | **Share an app** (optional) | The parent's chosen app window | Android 14+ single-app share with the §5.21.2 preflight |

Principles carried from the spec: the child never sees the machinery (§2.4); the guardian owns start/stop and
a daily time budget; the child can always end it; no recording by default (§5.21.3).

### Out of scope (explicitly)

Sharing DRM-protected streaming apps; iOS (repo is Android + Windows only); recording or clipping; multi-viewer
rooms; a general video-hosting backend; a text-to-speech or read-aloud engine (read-aloud is a separate unwired gap).

### Decisions (owner, 2026-11-07)

1. **Focus-rule exception: YES (Phase 3).** Olive may keep camera/mic live while a shared app is foreground.
   Consequences to design for: §5.21.2 needs a written amendment (not a silent exception); the exception applies
   only while a guardian-started share is active and ends with it; the child always sees that the camera/mic are
   live. Android restricts camera/mic use by backgrounded apps, so this likely needs `camera` and `microphone`
   foreground-service types alongside `mediaProjection` — **to verify against developer.android.com before building.**
2. **Content sources: BOTH guardian uploads and a curated library, "with additional options".** The extra options
   were not specified. Candidates to confirm before Phase 2 (each adds a rights/retention question): the device's
   own files/camera roll, a link the guardian pastes (own-content hosts only), content recorded in-app
   (e.g. the parent reading a story to camera), and a family-shared collection both households can add to.
   Storage/retention (§10.1) and copyright review apply to all of them.
3. **Time allowance: 2 hours per day by default, adjustable up or down by a guardian in parental controls.**
   Open sub-questions: (a) is the limit per household or per child across both households (recommend per child,
   so two homes can't stack to a double allowance — but this needs the owner's call); (b) can one guardian raise
   it unilaterally, or does raising it need the co-guardian's visibility (recommend: either may lower it; a raise
   is logged and visible to the other, in line with the existing append-only audit posture); (c) sensible
   min/max bounds (recommend a floor of 0 = off and a hard ceiling, number to be set in review).
4. **Both channels: YES.** See §6: the sync layer is transport-agnostic, using the LiveKit data channel when a
   call is live and the game-sync WebSocket when it is not.

## 6. Architecture

```
Guardian app                                 Child app
 ┌────────────────────┐   control msgs only   ┌────────────────────┐
 │ CoViewController   │ ───────────────────▶ │ CoViewFollower     │
 │  (leader: owns     │  {pos, rate, paused,  │  (drift controller)│
 │   position/state)  │   sentAt, seq}        │                    │
 └─────────┬──────────┘                       └─────────┬──────────┘
           │ plays local/own media                      │ plays same media
           ▼                                            ▼
     ContentSource (asset id → bytes via existing media store, cached on both devices)
```

- **Mechanism: synced playback, not pixels.** Only a few small messages every ~2 s cross the network. Pixels
  never leave the guardian's device, which sidesteps R2, R6, and most of R5.
- **Channel: both, behind one interface (decided).** `CoViewTransport` has two implementations:
  - *LiveKit data channel* — used when a call is already live (face-to-face alongside the show); adds no extra
    connection and no extra minutes beyond the call itself.
  - *Existing game-sync WebSocket table* — used when there is no call; no LiveKit minutes at all.
  - Selection rule: if a call room is connected, use it; otherwise open a table. If a call starts or ends mid-session
    the session migrates transports without restarting playback (the leader re-announces `{pos, seq}`; the follower
    keeps playing meanwhile). Messages carry `seq` so a stale tick from the old transport is ignored.
  - To confirm: the table protocol can carry a new message type without a version bump; and that the same
    `CoViewMsg` payload fits both channels' size limits (ticks are tiny, so expected).
- **Content delivery.** Prefetch the asset to the child device before the session starts so playback never depends
  on a live network. This removes buffering from the sync problem and works on a flaky connection.
- **Policy.** Extend `CallPolicy`/`auditCallPolicy` so `coViewing` is a first-class policy field with its own faults,
  rather than leaving `screenShare` as dead logic.
- **Authorisation.** Only a guardian principal may lead. Child principals are follower-only. (Child principals are
  "default-allow" today per the whole-app review, so this needs an explicit deny test, not an assumption.)

### Sync controller (validated by simulation, §7)

Zones: `|err| ≤ 0.15 s` do nothing; `0.15–2 s` nudge `playbackRate` within ±5 %; `> 2 s` hard seek. Leader sends a
tick every 2 s and immediately on play/pause/seek. A scheduled start (shared target time) is used so both devices
begin together.

## 7. Scaling and cost (modelled, not measured)

`scaffold/tools/co-viewing-model/capacity.mjs` — assumptions: 1.5 Mbps to the child, 2 h sessions,
5 families × 7 sessions/week = 150 sessions/month. Rates and plan amounts are the unverified ones from R7/R8.

| Scenario | Per 2 h session | Build plan fits | Pilot month (150 sessions) |
|---|---|---|---|
| A. Screen-share video via SFU | 240 participant-min, 1.35 GB | ~20 sessions (minutes bind first) | 36,000 min, ~203 GB, overage ≈ $28–31 |
| B. Synced playback, in a call room | 240 participant-min, ~0 GB | ~20 sessions | 36,000 min, overage ≈ $12 |
| C. A plus two-way face call | 240 participant-min, 1.89 GB | ~20 sessions | 36,000 min, ~284 GB, overage ≈ $36–40 |

Reading it:
- **Participant-minutes, not bandwidth, bind first** on the Build plan. A free-tier pilot covers roughly 20 two-hour
  sessions, so a real pilot needs a paid plan regardless of design.
- Synced playback cuts the bandwidth bill to ~nothing but **does not cut minutes if it lives inside a call room**.
  Running it on the game-sync channel when no call is needed removes the minutes too. That is the main cost lever.
- Estimates exclude the plan fee and any rate I could not verify. Treat as order-of-magnitude.

`scaffold/tools/co-viewing-model/sync-sim.mjs` — 600 s runs, 2 s ticks, follower clock 0.5 % fast. Results after
fixing a bug in my first version (its tick scheduler used floating-point time and stopped firing, which made the
first results look unrealistically clean — worth knowing the original numbers were wrong):

| Case | Hard seeks | Mean / max drift after 30 s |
|---|---|---|
| Clean Wi-Fi, child joins 3 s late | 1 (the initial jump) | 0.16 s / 0.20 s |
| Jittery Wi-Fi, 10 % tick loss, joins 8 s late | 1 | 0.17 s / 0.19 s |
| Cellular, 0.5 s latency-estimate error | 1 | 0.67 s / 0.70 s |
| Guardian pauses 20 s mid-show | 0 | 0.17 s / 0.34 s |
| Bad link: 40 % tick loss, 1 s jitter | 1 | 0.47 s / 0.50 s |

Findings: the controller holds ~0.2 s on good links without extra seeks and recovers from a pause cleanly. The
dominant error is **bias from a wrong latency estimate**, not jitter or loss, so a short RTT ping handshake at
session start (estimate offset from the minimum of ~5 round trips) is part of the design, not an optimisation.
Limit of the model: it does not model the player's real seek latency or audio-output delay, so real-device numbers
(§8) will differ.

## 8. Scripting — what is run, and what remains

Built (design stage):
- `scaffold/tools/co-viewing-model/capacity.mjs` — cost/capacity model, flags `--mbps --hours --families --sessionsPerWeek`.
- `scaffold/tools/co-viewing-model/sync-sim.mjs` — drift-controller simulation.

To write with the implementation (each needs real devices; none can be validated on a desk):
1. **Soak test** (`tools/co-viewing-model/soak.md` runbook + a harness): 4-hour session across a token-TTL expiry,
   screen lock/unlock, Wi-Fi drop/rejoin, app background/foreground. Pass = session survives or recovers
   without a guardian action. This is what actually answers the owner's "beyond 2 hours".
2. **Latency probe**: timestamp overlay or audio-click loopback between Fold5 and Tab S9 FE to measure real
   leader→follower offset, with the Fold5 on cellular and the tablet on Wi-Fi.
3. **Audio capture probe** (Phase 3 only): publish a screen share with and without audio from the Flutter client
   and confirm what the child hears. Resolves R2.
4. **DRM probe** (Phase 3 only): capture two real streaming apps and record whether frames are black. Resolves R6.
5. **Unit/golden tests** for the controller (mirror of `sync-sim.mjs`), the policy audit, and the authorisation
   deny (child principal tries to lead → refused).

## 9. Scaffolding — proposed layout (not created)

```
packages/co-view/                      # pure TS, no I/O, like time-engine
  src/controller.ts                    # leader state machine + tick/seek messages
  src/follower.ts                      # drift controller (zones above)
  src/clock.ts                         # RTT-based offset estimate
  src/policy.ts                        # time budget, who may lead, stop rules
  test/                                # golden + property tests; added to verify.sh
packages/session-runtime/src/security.ts   # + coViewing policy field & faults
server/                                # + message type on the game-sync table channel
db/migrations/0034_co_view.sql         # co_view_session (who, when, asset, ended_by) — metadata only
client/lib/co_view_leader_screen.dart  # guardian shell
client/lib/co_view_child_screen.dart   # child shell: one big Stop, nothing else
client/lib/co_view_player.dart         # wraps video/page view; exposes position/rate/seek
```

Interfaces (sketch):

```ts
type CoViewMsg =
  | { t: 'tick';  seq: number; pos: number; rate: number; paused: boolean; sentAt: number }
  | { t: 'seek';  seq: number; pos: number; sentAt: number }
  | { t: 'start'; seq: number; at: number; assetId: string }   // scheduled shared start
  | { t: 'stop';  seq: number; by: 'guardian' | 'child' | 'budget' };
function correct(err: number, cfg = { dead: 0.15, seek: 2.0, band: 0.05 }):
  { action: 'none' | 'rate' | 'seek'; rate?: number };
```

Constraints to honour: add the new suite to `verify.sh` (a CI guard that every `*/test/` file is named there is
already on the Tier-0 list); bump the assertion total in `MARKUP.html` and `demo/shell.html` per the existing
C7/D2 checks; every new assertion needs a unique test child UUID (the shared-DB lesson from PR #124).

## 10. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Long-session drop at token TTL boundary | Unknown | Soak test first; fix in the auth-refresh spine work either way |
| Content licensing / copyright of uploaded shows | Real | Phase 2 limited to content the guardian owns/uploaded; owner decision #2; counsel question |
| Child screen-time harm / overuse | Real | Guardian-set daily budget, child-visible "last one" cue, hard stop on budget |
| Sync feels off on cellular | Medium | RTT handshake; prefetch; measure on the Fold5 |
| Spec contradiction §5.21.2 | Certain for Phase 3 | Decided: amend §5.21.2 explicitly (decision 1); verify Android FGS camera/mic rules first |
| Transport migration glitches (call starts/ends mid-show) | Medium | `seq`-stamped messages, leader re-announce, a dedicated test that swaps transports mid-session |
| Two households set different allowances | Real | Decision 3 sub-questions; per-child cap, logged raises |
| Model numbers wrong | Medium | Every model figure here is labelled; replace with §8 measurements |

## 11. Suggested order of work

1. Finish the Tier 1 spine (token refresh, family bootstrap, delivery) — Phases 1–2 depend on it.
2. Run soak test #1 and latency probe #2 on the real devices with the existing call screen. Their answers could
   change §6's channel choice.
3. Phase 1 (Read together), then Phase 2, each with its own plan and PR.
4. Phase 3 only if the owner still wants it after seeing 1–2.

## 12. Sources

- [LiveKit — screen sharing](https://docs.livekit.io/transport/media/screenshare/)
- [LiveKit — quotas and limits](https://docs.livekit.io/cloud/quotas-and-limits)
- [Android — media projection](https://developer.android.com/media/grow/media-projection)
- [OpenWatchParty — sync algorithms](https://mhbxyz.github.io/OpenWatchParty/technical/sync)
- [NoMercy — distributed playback](https://docs.nomercy.tv/nomercy-video-player/advanced/distributed-playback)
- [Nightwatch — screen-capture protection (2016)](https://wwws.nightwatchcybersecurity.com/2016/04/13/research-securing-android-applications-from-screen-capture/)
- [WithSecure — MediaProjection advisory (2017)](https://labs.withsecure.com/content/dam/labs/docs/mwri-android-MediaProjection-tapjacking-advisory-2017-11-14.pdf)
- [LiveKit pricing](https://livekit.com/pricing) and a [third-party summary](https://trtc.io/blog/details/livekit-pricing-2026) (unverified)
