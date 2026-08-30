# Call infrastructure migration: self-hosted Jitsi → LiveKit Cloud

**Status:** approved, ready for implementation
**Scope:** the call feature only (server token minting, `call_screen.dart`, kiosk integration, dev/test scaffolding, docs) plus wiring real live call-quality adaptation into the same new call screen. Real supervised-call recording is a separate, later spec (`2026-08-29-supervised-call-recording-design.md`) that depends on this one being built first.

## Goal

MASTERFILE §16.2 #6 reversed LiveKit Cloud → self-hosted Jitsi "at the owner's direction, not because LiveKit failed technically." This session's own hands-on work standing up `tools/jitsi-selfhost/` reproduced, in practice, exactly the operational burden the original v0.40.0 LiveKit decision predicted for self-hosting ("on-call, patching, NAT-traversal edge cases... for a small team"): a Docker Desktop stale-socket crash-loop, a containerd-snapshotter image-resolution bug, a Windows bind-mount permissions bug that silently broke Prosody's TLS generation, manual TLS cert SAN regeneration, and — the one that actually blocked the live two-device test — a Windows Firewall rule requiring admin elevation neither the owner's dev environment nor Claude could grant without the owner running it manually.

Separately, self-hosting a single JVB instance in one location has a structural ceiling a managed edge network doesn't: call quality between two real users far apart depends on both users' distance to that one server, with no fix short of running multiple regions yourself (Jitsi's "Octo" multi-bridge relay — more infrastructure, not less).

**Decision, confirmed directly with the owner:** move to LiveKit Cloud. Free tier (5,000 participant-minutes/month, ~$0.0004/min after) comfortably covers this app's realistic usage — even daily 30-minute two-person calls is only ~1,800 participant-minutes/month. LiveKit Cloud auto-routes each device to its nearest point of presence (sub-100ms media latency, multiple global regions), which is the actual fix for the distance problem. The real ongoing cost of this choice is the same one already anticipated once before: LiveKit becomes a named third-party sub-processor in COPPA disclosure paperwork — a documentation task, not code, tracked as a follow-up below.

This is the project's SECOND reversal of this decision (LiveKit → Jitsi → LiveKit). Per the standing practice §21.7 already established for the first reversal, MASTERFILE keeps this history visible rather than deleted — see the Doc-sync section.

## What does NOT change

`packages/session-runtime/src/rooms.ts` — `createSession()`, `mintToken()`, and all five invariants (I1 room-unguessability, I2 single-room grant, I3 authenticated identity, I4 `can('call', ...)` gate, I5 short TTL) stay exactly as they are, untouched, unretested-from-scratch. Confirmed by reading the file directly: its `Grant` interface (`roomJoin`, `room`, `canPublish`, `canSubscribe`, `canPublishData`, `canUpdateOwnMetadata`, `hidden`) is already byte-for-byte LiveKit's own server-SDK token-grant shape — this was never a Jitsi-shaped type awkwardly reused, it's LiveKit's shape that the Jitsi integration has been discarding all along (`local-call-room-server.mjs`'s own header already says as much: "We just don't forward the LiveKit-shaped grant field to the client — Jitsi's public server doesn't consume it").

## Architecture — server side

**New, additive function** (lives beside `rooms.ts`, e.g. `packages/session-runtime/src/livekit-token.ts`): `mintLiveKitToken(token: MintedToken, apiKey: string, apiSecret: string): string`, using the `livekit-server-sdk` npm package's `AccessToken` to sign `token.identity` + `token.grant` into a real JWT with `token.ttlSeconds` as its TTL. Pure serialization of `mintToken()`'s existing output — no new authorization logic, no new invariant.

**`server/routes.mjs`'s `POST /v1/children/:childId/calls`** — read directly: today's handler already runs the real `createSession()`/`mintToken()` pipeline correctly, then throws away `minted.token.grant` and returns `{room: session.roomName, serverURL: JITSI_SERVER_URL, identity, displayName: 'Dad', rang, sessionId}`. The fix is narrow: call `mintLiveKitToken(minted.token, ...)` and return `{token: <jwt>, wsURL: LIVEKIT_URL, rang, sessionId}` instead. `notifyDevices()`/`recordCallStart()` calls above it are untouched.

**New env vars:** `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL` (`wss://<project>.livekit.cloud`) — owner creates the LiveKit Cloud project and supplies these; not invented or guessed here.

**`tools/local-call-room-server.mjs`** (dev/test scaffold) gets the identical treatment: `GET /room?who=dad|ivy` mints a real LiveKit token via the same function instead of handing back a Jitsi room+serverURL pair. `/pending-call` and `/pending-call-for-dad` (this session's own addition, bridging the child-initiated leg) carry `{token, wsURL}` instead of `{room, serverURL}` — same in-memory, single-slot, no-auth posture, unchanged.

**A real gap found and closed during implementation, not anticipated when this spec was first written:** Jitsi's SDK let a callee join with just a bare room name — no per-identity token needed. LiveKit requires a real, signed JWT to join at all, which the callee never had a way to get for a call someone else started. Closed with a real new route, `POST /v1/children/:childId/calls/:sessionId/join` — the callee (almost always the child answering a `call_incoming` push) mints her own token for the exact existing session, gated by the same real `mintToken()` I4 check every other mint already uses (refuses a real, otherwise-authorized guardian who simply wasn't part of THIS session — proven by a live test, not assumed). `db/migrations/0018_call_log.sql`'s own header comment had already anticipated this exact route ("a future second-guardian-join route... should be able to append to this same column without a further migration") — no migration needed, just widening `participant_ids` from `[caller]` to the real `session.authorizedUserIds` at the call-start site, and a new `callSessionFor()` read in `pool.ts` to reconstruct enough of the original session to re-mint from. **Implemented, tested live against real Postgres — 50/50 passing, including 12 new tests covering this exact route's real authorization boundary.**

## Architecture — client side

**`call_screen.dart` rewrite:** replace `jitsi_meet_flutter_sdk`'s `JitsiMeet`/`JitsiMeetConferenceOptions`/`JitsiMeetEventListener` with `livekit_client`'s `Room`, `room.connect(wsURL, token)`, and `RoomEvent` listeners (`ParticipantConnected`, `TrackSubscribed`, `Disconnected`, matching today's `conferenceJoined`/`readyToClose` semantics as closely as the two SDKs' event models allow — mapped, not assumed identical).

**A real, new minimal call UI** is required here, not optional: unlike Jitsi, LiveKit hands you room/track primitives, not a prebuilt meeting UI. Needed: local self-view + remote participant tile(s) via `VideoTrackRenderer`, and mic/camera/hang-up controls. Built as plain Flutter widgets, giving Olive actual design control over a screen a child uses — arguably the right outcome given `call_screen.dart`'s own existing comments describe fighting Jitsi's native UI to strip settings/chat/lobby-toggle for the child's role.

**Feature-flag equivalents:** today's `callFeatureFlagsFor(bool isGuardian)` (settings off for both roles, chat off for the child only, PiP on for both) gets re-expressed as plain conditionals in the new UI — e.g. no chat widget rendered at all when `!isGuardian`, rather than a Jitsi `FeatureFlags.chatEnabled` toggle. Same real, role-conditional behavior, expressed in code Olive owns instead of an SDK flag.

**`kiosk_channel.dart`/`MainActivity.kt`:** `beginCallHandoff()` and `ACTION_CALL_ACTIVITY_DESTROYED`'s re-pin-on-resume logic exist ONLY because Jitsi's SDK opens its own separate native Android Activity, which lock-task pinning refuses to launch as a second task. A LiveKit call is a normal Flutter route inside the already-pinned Activity — this handoff mechanism is very likely dead code afterward. **To be confirmed during implementation by actually testing kiosk-lock behavior on the real Fold5 with the new call screen, not assumed from this reasoning alone** — matching this codebase's own "verified rather than trusted from code review" standard (MASTERFILE §16.2 #6's own callout uses this exact phrase).

**PiP:** Jitsi's native Activity gave real PiP for free (2026-08-24 decision, `call_screen.dart`'s own doc comment). A plain Flutter call route needs its own explicit `enterPictureInPictureMode()` wiring to keep this. **Explicit follow-up, not built in this pass** — flagged here so PiP's current real behavior isn't silently lost without anyone noticing; the owner decides whether it's worth the follow-up before it's needed.

## Real live call quality (folded into this migration, confirmed with owner)

`degradation_banner.dart` is a complete, tested, MASTERFILE §5.28/§8.14-compliant quality-ladder state machine (`stepQualityDown`/`stepQualityUp`, shed-fast/restore-slow hysteresis, told once) — a 1:1 port of `packages/live/src/stream.ts`, currently fed by nothing real; the only call site is `guardian_more.dart`'s `LiveDegradeScreen`, explicitly labeled "(demo)".

**Wiring:** the new `call_screen.dart` subscribes to LiveKit's real per-participant `ConnectionQuality` events (`excellent`/`good`/`poor`) and feeds them into the existing `stepQualityDown`/`stepQualityUp` function pair — no changes to that state machine's own logic, it already does the right thing, it's just never been given real input. The resulting quality level drives LiveKit's per-track subscription quality (asking the SFU for the appropriate simulcast layer for the remote participant's video), and the same one-time notice behavior `degradation_banner.dart` already implements.

**Naming:** once real, `guardian_more.dart`'s tile label loses "(demo)" — matching this codebase's own established convention (a tile's title string encodes real-vs-simulated status; see `child_home_live.dart`'s "Live:" banner pattern for the same discipline applied elsewhere). `LiveDegradeScreen` itself can stay as a standalone demonstration/test harness for the algorithm in isolation — it doesn't need deleting, it needs to stop being the ONLY place this logic runs.

## Dev/test scaffolding

`main_live_child_call_test.dart`, `main_live_guardian_call_test.dart`, `main_live_dad_answer_test.dart` keep their exact architecture from this session (the `/pending-call` + `/pending-call-for-dad` bridge-then-join pattern, `buildCallIncomingHandler`/`CallKnockScreen` reuse) — only the payload shape changes, from `{room, serverURL}` to `{token, wsURL}`, matching the server-side change above.

**A real, permanent simplification for all future testing:** LiveKit Cloud is reachable over the normal internet. No LAN IP, no self-signed cert, no `adb reverse` for call media, no Windows Firewall rule. Nearly every networking/TLS obstacle from this session's Jitsi self-host work stops applying — not just for this migration's own verification, but for any future two-device (or truly remote, different-network) test.

## Testing plan

**Part 1 (server-only, no Flutter app):** a unit test on `mintLiveKitToken()`'s decoded JWT claims (right identity, right grant shape, right TTL) and an updated `calls_route.test.mjs` asserting the new `{token, wsURL, rang, sessionId}` response shape. Verified before any client code changes.

**Part 2 (real two-device verification):** once the client is rewritten, re-run the same real bidirectional protocol from this session — Fold5 and tablet, alternating caller/receiver/who-ends-the-call, real detection via knock screen, real sustained connection, real hangup — confirming parity with (and, given the removed networking friction, likely higher reliability than) what was verified against the self-hosted Jitsi stack.

## Doc-sync

`MASTERFILE.md` gets a new `§16.2 #6, REVERSED AGAIN` entry directly beneath the existing two (v0.40.0 LiveKit → post-v0.42.0 Jitsi), left in place rather than replacing them — same "the reversal is visible rather than gradual" practice already established. Real reasoning: this session's own hands-on self-host operational cost, the structural distance/quality ceiling, and LiveKit Cloud's free-tier economics for this app's realistic usage. `CHANGELOG.md`, `MARKUP.html`, `scaffold/demo/shell.html` updated in the same lockstep this project already requires for every change.

`tools/jitsi-selfhost/README.md` gets a status line marking it superseded — **archived, not deleted**, matching how the LiveKit→Jitsi reversal itself was kept visible rather than erased. The vendored `third_party/jitsi_meet_flutter_sdk_patched/` fork and the `jitsi_meet_flutter_sdk` pubspec dependency/override are removed once the migration is verified — a vendored third-party patch isn't project history worth preserving the way a documented architecture decision is.

**COPPA sub-processor disclosure** — flagged as the owner's own follow-up (naming LiveKit in the privacy/DPA paperwork), not implemented as code here, matching how the original v0.40.0 LiveKit decision already anticipated this exact cost ("solvable with proper paperwork rather than infrastructure").

## Explicitly out of scope for this spec

- **Real supervised-call recording** — separate spec (`2026-08-29-supervised-call-recording-design.md`), depends on this migration being live first.
- **Screen-sharing / shared drawing during a call** — a LiveKit room already supports N tracks per participant, so this becomes cheap later (another published track in the same room, or a data-channel message) — not designed or built here.
- **Multi-guardian/group calls** — already a known, separate future gap per `routes.mjs`'s own comment; LiveKit's N-participant room model makes it easier whenever it's tackled, but nothing about that is decided or built in this pass.
- **PiP** — real today via Jitsi's native Activity, needs new explicit wiring under LiveKit; flagged above as a follow-up, not included here.
