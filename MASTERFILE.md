# OLIVE BRANCH — MASTERFILE

> **Two names, settled v0.23.0.** **Olive** to the child; **Olive Branch** to
> adults. (And, as it happens, the name of the first child this was built for —
> which is three meanings in one word and none of them accidental.) The child never sees the two-word form — "branch" implies something
> broken and being mended, which is adult knowledge about her family. See §16.3.
> **Name search completed v0.49.44 — kept, no blocking conflict found.** A
> real, good-faith USPTO/app-store search (not a placeholder): no
> established co-parenting/custody app anywhere in the market — checked
> against OurFamilyWizard, AppClose, TalkingParents, WeParent, Custody
> X Change, MyFam, Pairently — uses "Olive" or "Olive Branch." A live app
> called bare "Olive" exists (Giga Studios' food/cosmetic allergen scanner,
> `oliveapp.com`) but in an unrelated category. USPTO's own trademark
> database (`tmsearch.uspto.gov`, searched directly, live) turned up one
> real, disclosed risk worth naming rather than burying: Serial 98817745,
> a live-but-suspended "OLIVE BRANCH" service-mark application filed Oct.
> 2024 by Silvius Enterprise, Inc., in Class 042 — the same class a
> software-services filing for this app would likely use — but for
> financial/accounting/tax-preparation SaaS, a wholly different market and
> goods description; a genuine same-class prosecution risk if this app
> ever files its own federal application in that class, not a consumer
> confusion risk given how different the actual services are. Every other
> "OLIVE BRANCH" filing found (hosiery, restaurant, nutrition, kids'
> entertainment, packaged foods, internet chat rooms) is either dead
> (abandoned/cancelled) or in an unrelated goods category. **This is a
> real due-diligence search, not a substitute for a licensed trademark
> attorney's formal clearance opinion** — that remains the right step
> before any actual USPTO application filing or wide commercial launch,
> not something this decision claims to replace.

| | |
|---|---|
| **Document** | MASTERFILE (canonical) |
| **Version** | 0.49.61 |
| **Last amended** | 2026-09-01 |
| **Status** | Phases 0–3 built; §9.10 showcase, 12 async + 10 live games. **The kiosk bridge is real on Android and Windows** (§5.20, §8.3, §20.2b) — Windows is an app-level lock, not OS Assigned Access, and is still **UNVERIFIED** (no local C++ toolchain to actually run `flutter build windows`); iOS Guided Access remains Ph.4 and, per Apple's own restriction, cannot be enabled programmatically at all. A **Wear OS companion** (Galaxy Watch6) has real, compiled phone↔watch data sync in both directions (`WearSyncBridge.kt`/`MainActivity.kt`'s `DataClient`/`MessageClient` wiring, `wear_sync_channel.dart` — sleeps-until-handover phone→watch, "Call Dad" watch→phone) — unit/contract-tested, but **UNVERIFIED against real or emulated Wear OS hardware** (no watch has ever paired with this code in this environment). §21 **built** — the ladder, the quieting, letters, reverse banking, rungs 15–18, siblings. **The Flutter client's own navigation graph is complete** (v0.44.0) — 62 screens built across fourteen parallel groups are reachable from `ChildHome`/`GuardianHome` and their new `*_more.dart`/`games_hub.dart` sub-hubs, not just compiled and tested in isolation. **The real-time call ran on self-hosted Jitsi through v0.49.56 — SUPERSEDED v0.49.57, moved back to LiveKit Cloud (§16.2 #6 REVERSED AGAIN), NOT yet verified against a real LiveKit Cloud project or real hardware.** The Jitsi-era account that follows is real history, kept visible per §21.7, not a description of the current transport: **the real-time call had two independent bugs, verified live on two physical devices, both since fixed in code (v0.46.1/v0.46.2) and re-verified live** (§16.2 #6 callout, §20.2b) — the child-side kiosk-lock/Activity conflict had an implemented, compiled, `flutter analyze`/`flutter test`-clean fix confirmed live on a real Fold5; the public Jitsi server's moderator lobby had Step 2 (self-hosting) staged and container-verified as of v0.46.2 — `scaffold/tools/jitsi-selfhost/` — and its cert-trust gap fixed at the TLS layer as of v0.49.28 (the stack's own self-signed cert had zero X.509 SAN extensions, a second failure mode independent of "untrusted issuer" that a bare CA-trust fix would not have caught; `generate-dev-cert.sh` fixes both, confirmed via `openssl s_client` that the corrected cert is actually served) — and confirmed live on a real device over real WiFi as of v0.49.30 — the self-hosted stack's own served client config still hardcoded `wss://localhost:8443/...` for its XMPP websocket (`config.js`, derived from `PUBLIC_URL` defaulting to `localhost`), which a device reaches as itself, not the dev machine, so every join attempt failed with a real Strophe websocket error before this pass set `PUBLIC_URL` to the dev machine's actual LAN address; fixed, and a real `CONFERENCE_JOINED` event with a real room URL followed on the very next attempt — see CHANGELOG v0.49.30 for the fuller account (this cell previously cited "§9.12.4's own status note," which is the doodle desk feature and unrelated to calls — a wrong citation, corrected by removal). **Real guardian authentication is now wired end to end** (v0.47.0, §7.1, §8.1, §8.3) — the hardcoded, unauthenticated `'1273'` kiosk PIN is gone, replaced by a real scrypt-hashed PIN + WebAuthn/passkey system against RLS-scoped Postgres (`pin_credential`/`webauthn_credential`/`auth_challenge`, migration 0008), a real Android Credential Manager bridge, and a real client wiring. Two independent adversarial reviews found five real defects (two CRITICAL: a connection-pool self-deadlock that froze the entire server, and a PIN-lockout that gave zero protection against a concurrent brute-force burst); both CRITICALs and both MEDIUM webauthn signCount findings are fixed and **verified live** — real Postgres (WSL2), a real running server, real concurrent HTTP load, and a real Android device kiosk-PIN unlock (wrong PIN rejected, right PIN accepted, screenshotted). The WebAuthn native Kotlin bridge compiles clean against the real androidx.credentials 1.6.0 AAR (one real compile-time API misuse found and fixed in this pass — see CHANGELOG v0.47.0) but the interactive on-device passkey ceremony itself was **not** independently re-verified this pass — device-blocked, not skipped: the only device with a configured secure lock screen + biometric available was the operator's own personal phone, correctly left unlocked/untouched rather than bypassed. **Real homework OCR closes §20.2b's own "specified, not built" OCR gap** (v0.47.0, §9.1, §20.2b) — a real quality gate (blur/skew measurement), real tesseract.js text recognition, and a rule-based (explicitly non-LLM — no API key for one exists anywhere in this repository) hint generator all run server-side through the existing guardHint() output guard; the client's simulated demo path is demoted to a fallback for when no live backend is configured. **A real family agreement screen is wired in** (v0.46.3, §7, §9) — `guardian_setup.dart`'s "Review the family agreement" tile no longer dead-ends at an honest-stub snackbar; it opens a real, read-only view of the actual custody order already backed by `db/migrations/0007_custody_order.sql` and `packages/custody/src/schedule.ts`'s tested `Order`/`HolidayRule` types, reached via a new `GET /v1/children/:childId/custody-order` route. No bespoke "family agreement" data model was invented — MASTERFILE names none, and none was needed. **A guardian's own account deletion is now real** (v0.47.0, §2.10/§2.11/§9.8/P8, §21.7's "hardest button") — `POST /v1/me/delete` deactivates the login, cancels undelivered content, and leaves delivered messages/the parent-to-parent log/the child's archive untouched, proven against real Postgres RLS (`packages/db/test/deletion.test.mjs`, 29/29) — see §21.7's status note. **§11 push delivery is now implemented end to end as of v0.48.0** — server-side (v0.47.0): `device_token` table + RLS, a real FCM v1 sender, a real APNs HTTP/2 sender, and `notifyDevices()`'s single sendGuard()-gated dispatch; client-side (v0.48.0): `client/lib/push_channel.dart`'s real `firebase_messaging` wiring — permission request, token registration, `onTokenRefresh` re-registration, a real top-level background handler, and a foreground handler that (like the background one) reads only the content-free `kind`/`ref`/`callHandle` fields, never `message.notification` or any other payload key. All of it tested against a live Postgres / mocked network transports / a mocked HTTP client respectively — but **never run against a live FCM/APNs endpoint or a real device** (no credentials and no `google-services.json` exist in this environment, neither fabricated) and **not wired to any real server-side trigger** (none exists yet on `main` to wire it to). **Hardened v0.48.1** after three adversarial reviews of the already-shipped feature: fixed a client-side parser crash on a non-String data value (`PushPointer.fromData`), an APNs HTTP/2 socket leak on both error paths, and unbounded concurrent FCM OAuth-token minting; no authorization bypass was found (confirmed by re-tracing, independently of the review) and the dedupe-by-token reattribution design is unchanged, already documented in `0012_push_device_token.sql`. See CHANGELOG v0.48.1 for the full account, including which of the seven raw findings were fixed vs. recorded as already-handled. **v0.48.2 is a CI-green pass, not a feature change** — running this branch's CI for real (rather than only locally) surfaced two genuine, previously-unhit bugs in v0.47.0's `deactivateAccount()` (it deleted from `pin_credential`/`webauthn_challenge` using columns and a table name that guardian authentication's own migration 0008 had already superseded — see CHANGELOG v0.48.2), plus one latent test assertion in `availability.test.mjs` (#11) that had never actually run against a real Postgres before, plus one test misfiled into the wrong verify.sh section. All four fixed; none touch push delivery's own behavior. **v0.48.3** fixed a fifth issue v0.48.2 missed: `deactivateAccount()` was still opening its session under the caller's own role, and `auth_challenge`'s RLS is `system`-only — now runs as `system` throughout, checked against every policy the transaction touches, not just the one that failed. **§16.1 #3's certified export is now real as of v0.49.0** — `certifiedExportBundleFor()` reads a child's real hash-chained `message_log`, re-verifies it via `ledger.ts`'s real `verifyChain()`, and applies the real annual-free-allowance/court-tier rule via `authorizeExport()`; served from the SAME `GET .../export` route raw export already used, dispatched on `?kind=`, not a second registration (see §16.1's own status note above for the full account and why). `db/migrations/0013_court_tier_flag.sql` also closed a real, independently-discovered RLS-monitoring gap: `device_token` (v0.48.0) had `FORCE ROW LEVEL SECURITY` but was never added to `health_check`'s `rls_unforced` probe. **Hardened v0.49.1** after an adversarial review found a real TOCTOU on the annual allowance (two concurrent requests could both walk away free) and a real denial-reason type/contract bug — both fixed, see §16.1's own status note and CHANGELOG v0.49.1. **v0.49.2 fixed a real, pre-existing coordinator lockout** found reviewing this rebase's own merge work before it landed: the merged `GET .../export` route's single coarse `'export.raw'` action gate wrongly denied every coordinator's certified-export request before the handler (and `certifiedExportBundleFor()`'s own correct check) ever ran — coordinator holds `'export.certified'` in `ROLE_CAPS`, not `'export.raw'`. Fixed by moving real authorization into each pool function individually (`action: null, identityScopedByHandler: true` on the route, mirroring `kiosk-pin/verify`); also closed the `rls_unforced` monitoring gap this same review found (`custody_order`/`guardian_availability_window`/`app_user` were unmonitored). See CHANGELOG v0.49.2. **v0.49.3 fixed a real, previously-shipped deactivation gap (SEC-01, found by a round-2 post-merge audit) and two more the fix's own pre-merge adversarial review found in the same class:** `deactivateAccount()` now also removes every `device_token` row the deactivating user owns (they previously kept receiving push indefinitely), and `registerDeviceToken()` refuses a deactivated guardian/coordinator's still-valid session if it tries to register a NEW device, mirroring `devLogin`'s existing gate — narrower than a general session deny-list, which does not exist in this codebase and remains a documented, accepted limitation. The review then found a materially worse, unbounded variant: a deactivated guardian could mint a brand-new WebAuthn passkey and re-authenticate indefinitely, never merely outliving one session's TTL — `storeWebauthnCredential()` and `webauthnLoginVerify()` (server/index.mjs) are both fixed now, the former atomically (`FOR UPDATE` inside the write's own transaction, not a separate check). `setPinCredential()` got the same atomic fix for consistency. See CHANGELOG v0.49.3 for the full account and exact boundary. **v0.49.4** is CI-coverage housekeeping, not a feature or fix: `tools/verify.sh` was silently never running 8 real, passing test files — `health_alert.test.mjs`, `messages_route.test.mjs`, `games2`/`games3.test.mjs`, `packages/live/test/live.test.mjs` (name-collided with a DIFFERENT `live.test.mjs` under `session-runtime` that WAS running), `attestation.test.mjs`, `contract.test.mjs`, and `availability_contract.test.mjs` — found by the same round-2 audit (TEST-01 through TEST-07 in `Merge Aftermath`). All 8 wired in; none needed a code change, only CI actually running them. See CHANGELOG v0.49.4. **v0.49.5 fixed two demo screens that had thrown a caught JS error since the repo's very first commit** — "Observers" and "Accessibility" both called bridge functions (`observerView()`, `a11yView()`) that never existed anywhere, found by a full click-through rendering pass (`Every Door, Opened`). Both are now real, backed by the actual `packages/observer`/`packages/a11y` engines rather than invented data — including a new, honestly-scoped `OBSERVER_GRANT_TTL_DAYS` constant, since "time-boxed by default" never had a number attached to it before. See CHANGELOG v0.49.5. **v0.49.6 closes five of the real, buildable gaps found by a full engine-capacity scoping pass** (24 gaps catalogued; most were genuinely environment-blocked — a real device, a running LiveKit/Jitsi server, a print-fulfilment partner — or open product decisions this pass declined to invent, and are recorded, not built): a real `who_is_here_screen.dart` closes §17.1's last "predicate tested, no UI" line; `game_hangman.dart` gives the already-tested hangman engine (`games2.ts`) the one client widget it was missing, wired into `games_hub.dart`; `FilesystemStorage` gives `StoragePort` (§10.1, §5.6) a second, real, non-memory implementation for self-hosted deployment (a cloud provider still needs real credentials this environment doesn't have); and `school.test.mjs`/`print.test.mjs` give the school layer (§11.5) and print fulfilment (§9.15) — both already real, both already wired into the demo's probe harness — their own dedicated automated coverage. One catalogued gap, "no guardian-facing surface for siblings aging out one at a time" (§21.7), turned out to be **stale**: `siblings_screen.dart`'s `StaggerBanner` already implements exactly that, and was missed by the scoping pass's own package-batch boundaries — corrected here, not rebuilt. See CHANGELOG v0.49.6. **v0.49.7 gives §8.3's PIN+biometric guardian escalation ceremony a real screen** — the first of gap-fill batch 2. `escalate()` (`lock_controller.dart`, real since day one) had nowhere to go; `guardian_escalation_screen.dart` is now that destination, reached from a small persistent affordance over the locked child surface, reusing the existing kiosk-pin and WebAuthn-login routes for its two factors rather than inventing new ones. Its own real action is releasing the native kiosk lock. See §7.1's own status note for the full account, including a separately-found, not-yet-wired `escalateSession()` in `packages/auth`. See CHANGELOG v0.49.7. **v0.49.8 resolves that open question — and corrects a claim v0.49.7 got wrong rather than leaves it stand.** `escalateSession()` is NOT untested: `packages/api/test/stack.test.mjs`'s "C sessions" and "F api" sections already exercise it directly (both-factors success, PIN-alone/biometric-alone refusal, a child role refused outright, its own 15-minute TTL) and end-to-end through a synthetic `escalated: true` test route proving `Api`'s gate (`packages/api/src/api.ts`) honors it correctly — v0.49.7's "no test file at all" was true only of `packages/auth/test/` specifically and should not have been read as "untested." Three more assertions close the one genuine gap that search actually surfaced: `readSession()`'s malformed-token branches (no `.` at all, an empty payload, a validly-signed non-JSON payload) had zero coverage anywhere. Separately, on the real open question — whether escalation should mint a live elevated guardian API session, not just release the kiosk lock — **this pass declines to invent a route for it to call**, the same posture as every other declined-not-deferred product decision in this document (§19): nothing in §7.1's real API surface or §8.3 currently needs one, and inventing a consumer just to give `escalateSession()` a caller would be exactly the "declaration with nothing behind it" §0 warns against, aimed at the wrong target. `Api`'s `Route.escalated` field stands as the ready, already-tested integration point for whenever a real route needs PIN+biometric step-up rather than ordinary guardianship-edge authorization — and P7 sets a permanent boundary on it: the child's journal may never be that route, escalated or otherwise (§2.1 P7 names "guardian escalation" explicitly). See §7.1's own status note and CHANGELOG v0.49.8. **v0.49.9 closes gap-fill batch 2's second item** — real create/read/accept-decision/revoke for a guardian invitation (`db/migrations/0014_guardian_invite.sql`, `POST /v1/children/:childId/guardianships` and three more real routes, `invitation_screen.dart`'s real accept path). Honestly incomplete by design: no `guardianship` row is created, because doing so would require an account-creation security model this codebase has never built for a brand-new guardian — `guardian_setup.dart`'s passkey registration has needed an already-authenticated session since it was written, and nowhere does a first-time guardian ever acquire one. That gap is real, foundational, and recorded rather than papered over with an invented auth flow. See §7.1's own status note and CHANGELOG v0.49.9. **v0.49.10 wires §8.8.5's read-aloud spec into the real Flutter client for the first time** — `flutter_tts` was undeclared as a dependency and the whole section was pure, unwired TypeScript logic (`packages/a11y/src/a11y.ts`) until this pass. `a11y_speech.dart` ports `speakableText()`/`admitSpeech()` 1:1, the same discipline `lock_controller.dart` already applies to `lock.ts`; `tts_channel.dart` wraps the plugin's real, per-platform offline synthesizer (AVSpeechSynthesizer, `android.speech.tts.TextToSpeech`, ...) — never a cloud API, honoring `READ_ALOUD_ON_DEVICE_ONLY`/`READ_ALOUD_NEVER_LOGGED` in the running client, not just by name in a spec. `emergency_card.dart` (§9.6.3) and `handover_notes.dart` (§21.7, P8) are the first two screens with a working speaker button — both tap-gated only (`admitSpeech(tap)`, never autonomous), both reading real on-screen text back verbatim with no summarizing or composed digest, and both falling back to an honest "not built yet" message rather than a silent no-op when unwired, the same posture as every other real-but-optionally-wired affordance in this codebase. Built per an explicit user directive to deepen Galaxy Z Fold 5/tablet fidelity and add a cost-free, rule-based (never generative) assistant layer for the child's — and possibly the adult's — live navigation of the app; this pass scoped the full candidate list against every P1–P9 prohibition (§2.1) before writing any code, and built the two highest-stakes surfaces first. The remaining screens §8.8b's sixteen come-back-signal applications cover do not yet have a speaker button — a deliberately narrow first slice, not the full sweep. See §8.8.5's own status note and CHANGELOG v0.49.10. **v0.49.11 wires §8.11.4's real device-channel awareness into push delivery for the first time, closing this codebase's own top-ranked prior-audit finding** — `devices.ts`'s `CHANNELS`/`admitDevice()`/`channelAdvice()` had existed, fully unit-tested, since well before this pass with zero production callers; `notify.ts`'s `notifyDevices()` now calls `admitDevice()` per device before attempting a send and skips (rather than fires FCM/APNs into) a device resolved to a push-incapable channel. The same pass found and fixed a real, silent bug this exact duplication had already caused: `channels.ts`'s independent `route()`/`reachability()` re-declared the same channel facts by hand and had drifted — a `web` device (which `devices.ts` has never declared SMS-eligible) could still be routed/advised straight to `sms_to_adult`. `channels.ts` now imports its facts from `devices.ts` as the single source of truth, and gained its own dedicated test file (`channels.test.mjs`) after this pass found it had zero coverage in its own package — its only prior test exposure was transitive, through a differently-named suite in the `devices` package. Two wrong MASTERFILE citations `channels.ts` carried since its first commit (§10.5, §10.4 — both unrelated law) are corrected to §8.11.4/§10.8. `push_channel.dart` reports the one channel it can currently know for certain (`'ios'`); real Android channel detection (Play Services / install-source APIs, both credential-free) is scoped, named precisely, and explicitly deferred this pass — the same reasoning, and the same missing piece, as the already-deferred `LOCK_METHODS` gap. See §7's own status note and CHANGELOG v0.49.11. **v0.49.12 gives §5.25.2's "knocking, not ringing" spec its first real client screen** — `call_knock.dart` ports the section's own `Knock`/`knockUnanswered()`/`ANSWER_WORDS`/`ANSWER_BANNED`/`notNowOutcome()` (deliberately not the rest of `lifecycle.ts`, since nothing else in this client calls it); `call_knock_screen.dart` is the real, calm UI — no countdown, no urgent color, "Answer"/"Just talking" both lead to the same real `CallScreen` join since the source specifies no technical difference between them, "Not now" shows the real gentle line and dismisses itself, and an unanswered knock quietly times out after the real 90 seconds with zero missed-call framing (§9.13.4's own rule, applied here for the first time). A speaker button reads the prompt and every answer option back verbatim. Honestly disclosed as of v0.49.12: not yet reachable from a live call. That gap closed in two real steps since — v0.49.33 gave the server a real route (`POST /v1/children/:childId/calls`, mints a session, authorizes the caller, calls `notifyDevices()`); v0.49.34 gave the CLIENT a real caller for it (`OliveApi.startCall()`, `guardian_more.dart`'s own "Call $childName" tile) — `api_client.dart`'s own comment said "no OliveApi method calls it yet" right up until this pass, so v0.49.33's own claim of "finally has a real caller" was the server's honesty getting ahead of the client; corrected in CHANGELOG v0.49.34. What remains genuinely unreachable, not fabricated around: no `google-services.json`/real FCM or APNs credential exists anywhere in this environment, so a real push still cannot land on a real device — verified live anyway (two physical devices, guardian tap to child answer, in real time) via a dev-only bridge confined entirely to already-dev-only test files, standing in for exactly that one undeliverable hop and nothing else; see CHANGELOG v0.49.34 for the full account. The code-comment-only "waiting room" half of `lifecycle.ts` (no matching MASTERFILE section backs it) stays out of scope — building it would mean inventing supervisor-facing product decisions this codebase has already separately declined to make unilaterally. See §5.25.2's own status note and CHANGELOG v0.49.12. **v0.49.13 gives §8.11.1's device matrix its first real Dart port, and finally implements §8.11.7's own "requesting must work on a phone even if reviewing does not" rule** — both queued from the same scoping pass as v0.49.12. `form_factors.dart` ports `FORM_FACTORS`/`postureFor()`/`columnsAt()`; `court_export.dart`'s `CourtExportScreen` is its first real consumer, replacing an unexplained bare `760` breakpoint with the real, tested 660px threshold. More consequentially: `postures.ts`'s own `REQUEST_MIN_WIDTH`/`REVIEW_MIN_WIDTH`/`reviewableAt()` existed, real and tested, since before this pass — with zero client enforcement. Both `CourtExportScreen` and the real, backend-wired `LiveCourtExportScreen` rendered the FULL certified-export review UI at any width, including a 344px Fold-cover screen, directly contradicting `requestConfirmation()`'s own promise that reviewing needs "a computer or a tablet." Both screens now show that honest copy instead, below 600px — raw export, never gated by this rule, stays available at any width. A real bug was found and fixed building this: `LiveCourtExportScreen` initially read the gate from `MediaQuery.sizeOf(context).width`, which does not reliably track a test's `setSurfaceSize` (confirmed via an isolated repro) — rebuilt on `LayoutBuilder`, matching `CourtExportScreen`'s own already-correct approach, which is also more precise in production. A third wrong MASTERFILE citation was found and fixed in the same pass: `postures.ts`'s own header cited "§8.12.3," which does not exist anywhere in this document — corrected to §8.11.7. See §8.11.1's and §8.11.7's own status notes and CHANGELOG v0.49.13. **v0.49.14 is an adversarial audit of gap-fill batch 2 (PRs #26–#30), run before merging the last of them — and what it actually found.** Five independent review dimensions, every finding independently re-verified by a second pass trying to refute it: 15 raised, 13 confirmed real, all 13 fixed. The one that would have shipped broken: **the entire guardian-invitation accept flow (v0.49.9) was completely non-functional for its only intended caller** — `Api.handle()` required a Bearer session token unconditionally, before ever consulting a route's own flags, so `GET`/`POST .../accept` (built for an unauthenticated invited party with no session to send one from) 401'd every real call; no test caught it because every existing test bypassed either HTTP or auth entirely. Fixed with a new, registration-time-enforced `Route.noSessionRequired` flag on `Api` — the third escape hatch after `identityScopedByHandler`/`skipOuterSession` — scoped to exactly the two routes that need it, proven both ways (the bypass works, and it does not leak to `revoke`, which correctly still requires a session). Also fixed: a real, sender-facing false statement in `channels.ts`'s `senderStatus()` (told the sender "we don't have a number for the house" when a number genuinely was on file and SMS simply hadn't escalated yet); `call_knock_screen.dart`'s read-aloud text was not actually verbatim, and separately skipped the `admitSpeech()` gate every sibling screen uses; `court_export.dart`'s `reviewableAt()` ignored text scale while its own sibling `columnsAt()`, two lines away, correctly didn't; a stale "§8.12.3" citation, already corrected once at its origin, was reintroduced into every file v0.49.13 touched to consume it; four real, previously-undisclosed test-coverage gaps (two in `notify.ts`, one in `LiveCourtExportScreen`, one in `call_knock_screen.dart`'s production timeout path) closed with new injection seams and tests; two CHANGELOG test-count overclaims corrected. Mutation testing (7 deliberate mutants reintroducing bugs this session already fixed once) confirmed 7/7 killed by the existing suites before the audit even started. See CHANGELOG v0.49.14 for the complete account. **v0.49.15 is a dedicated "dead wire" sweep** — real backend data genuinely fetched, then discarded or never rendered by the screen that fetched it. Six confirmed and fixed: the child-home Messages badge counted already-watched messages as unread (`/inbox` returns both `'delivered'` and `'opened'` rows); `sleepsUntilHandover` stayed hardcoded `null` in `child_home_live.dart` though `OliveApi.fetchNow()` — backed by a real, working `/now` endpoint — had zero callers anywhere in this client; a certified-export `chain_broken` denial's real per-entry `verifyChain()` diagnostics (`faults`) were fetched and silently dropped by `api_client.dart`'s own decoder; a successful certified export's real whole-bundle hash and record id were fetched alongside the attestation and never read out of the response; `POST /v1/me/delete`'s real response (cancelled-message count included) was discarded without even being assigned to a variable; and a holiday rule's real `priority` field — the actual tie-break `schedule.ts`'s `holidayOn()` uses when rules overlap — was parsed and never shown or used to order the list. All are genuinely small, single-screen reads of data already in flight, not new features — one candidate (`GuardianHome` having no live-data screen at all) was confirmed to be a real, screen-sized gap rather than a dead wire and was deliberately NOT built here, per this document's own "report honestly on what needs a bigger decision, don't invent it" discipline (§19). See CHANGELOG v0.49.15 for the complete account, file-by-file. **v0.49.16 gives §9.8.4 its first real backend and closes a documented gap named at `rawExportBundleFor()`'s own header since v0.49.0** — a child's OWN export, and the guardianship closure §9.8.4 requires alongside it, in one atomic action: `POST /v1/children/:id/handover` (server/routes.mjs), `packages/db/src/pool.ts`'s `takeAndGo()`. Reuses, rather than reinvents, both halves of its own name: `assembleRawExportBundle()` is the exact bundle-assembly/serialize/hash code `rawExportBundleFor()` already used for a guardian's own pull, now extracted and shared (her bundle additionally carries her REAL journal and a real copy of the parent-to-parent log — "she can have a copy of everything," `rungs.ts`'s own `NOT_HERS_TO_DELETE`); `handover()` (`packages/archive/src/archive.ts`, real and tested since before this pass via `phase3.test.mjs`, never wired to a route) is the exact, unmodified business rule for the age/deceased/idempotency gate and the guardianship-closure semantics — this pass writes no age-comparison logic of its own anywhere. `db/migrations/0016_child_take_and_go.sql` closes the one real schema gap that blocked this: `export_record.requested_by` required an `app_user` row a child principal has never had; `requested_by_child_id` (nullable, exactly-one-of CHECK, mirroring `device_token`'s existing owner-column split) lets a child-initiated export be recorded honestly, with `export_record_no_child`'s RLS left untouched — `takeAndGo()` runs its actual write as `system`, after the route's own `identityScopedByHandler` check (same shape as kiosk-pin/verify) has already verified the caller really is this exact child. `child.majority_age`/`birth_date`/`handed_over_at` and `guardianship.closed_reason`'s `'majority'` value have all existed, unused, since `0001_phase0_init.sql` — this is their first real writer. `child_more.dart` gains a real, always-reachable "Take your data and go" tile (`take_and_go_screen.dart`) mirroring `deletion_screen.dart`'s own rigor — a real acknowledge-before-enable gate, an audited-copy discipline (`takeAndGoForbiddenCopy`, leaning on `rungs.ts`'s own `DELETION_FORBIDDEN_COPY` as its tone precedent), NO cooling-off period (§21.7's own words: "a delay is a soft refusal dressed as care"), and a real save-to-file-and-hash-verify flow identical in shape to the guardian's raw-export button. Deliberately declined: rung 18's separate, more drastic "delete everything" action (`requestDeletion()`/`deletionConfirmation()` in `rungs.ts`) is a DIFFERENT, heavier grant this pass does not wire up — nothing about "take your data and go" implies erasing it, and the task this pass was scoped to asks for a mirror of guardian ACCOUNT DELETION (deactivation — nothing of the child's own data is destroyed), not of rung 18's own separate, more serious deletion. See §9.8.4's own status note and CHANGELOG v0.49.16. **v0.49.17 closes two of §9.2's four client-side game gaps: real screens for tic-tac-toe and dots-and-boxes.** `game_tictactoe.dart` and `game_dotsboxes.dart` port games.ts's own `newGame()`/`play()`/`takeBack()`/`setHandicap()` for these two kinds directly into Dart, not a network call to any server route — there is none, and none was needed, since these are LOCAL, single-device games, the same as `game_story.dart`. Real win/draw detection; the `no_centre` handicap enforced at the move-validation layer, not just hidden in the UI; dots-and-boxes' box-completion cascade (`claimBoxes()`) correctly granting the same side another turn, including the double-cross case where one edge closes two boxes at once; and free, unlimited takebacks implemented by replaying from the start — verified to correctly hand an extra turn back across a take-back that undoes a box-completing move, the exact edge case games.ts's own `takeBack()` doc comment warns inversion would get wrong. Both reuse the existing `HandicapScreen`/`catalogueFor()`/`handicapBanner()` machinery already real in `game_logic.dart` rather than building a second setup screen, and both simulate the parent as a local opponent (a short "thinking" delay, then a uniformly random legal move) — the same posture `game_chess.dart`/`game_checkers.dart` already established, not a new one. Layout is driven by the real §8.11.1 posture system (`form_factors.dart`, v0.49.13) rather than a second hand-rolled breakpoint: a single stacked column at `foldCover`/`phone`/`tabletSmall` (1 layout column), a persistent side panel — turn/handicap banners plus a real button `Column`, not the narrow layout's `Wrap` merely given room to stop reflowing — alongside the board at `foldMain`/`tabletLarge`+ (2+ columns). `child_home.dart`'s "Play together" `onPlay` now switches on `GameKind` for real; `GameKind.memory` is deliberately left on the honest not-built-yet path — a separate, still-open product decision about where real photos for that game come from, not an oversight. See §9.2's own status note and CHANGELOG v0.49.17. **v0.49.18 gives §9.2's catalogue Play Together Phase 1's Batch A** (`docs/superpowers/specs/2026-08-20-play-together-phase1-design.md`, a docs-only PR merged just ahead of this one) — Draw Together and Guess the Doodle, the second and third real consumers of `annotation_canvas.dart`'s `AnnotationCanvas` engine outside `doodle_desk.dart` (§9.12.4), and the first with TWO real actors ('child'/'parent') drawing on it at once rather than one. `game_draw_together.dart` is a genuinely shared, always-on canvas with per-actor undo scoping — never a "clear everything" button, which would defeat the whole point of an engine built specifically so a parent's undo can never erase a child's stroke; `game_guess_doodle.dart` adds a real, drafted 86-word curated word bank (dozens, not a handful; no duplicates; every word reviewed for warmth and age fit) and a soft "did you get it?" reveal that is never tallied across rounds, matching P2 exactly. Both are real `GameKind` catalogue entries (`competitive: false, handicaps: []`, `story`'s own precedent) wired into `child_home.dart`'s `onPlay` switch. Also carries `game_picker.dart`'s own hand-rolled 420/680px breakpoint migration onto `form_factors.dart`'s real, tested `columnsAt()` — the exact anti-pattern that file's own header already named as fixed elsewhere (`court_export.dart`, v0.49.13) but never migrated here until now; one real, intentional column-count change this carries: a 10-inch tablet now gets 2 columns, not 3, matching `FORM_FACTORS`' own `tabletLarge.columns` value, giving each card more real width rather than less. A real, pre-existing §8.8 accessibility bug this same migration's own new test surfaced is fixed alongside it: `_GameCard`'s fixed 182px grid-tile height did not scale with text size, overflowing at large accessibility text — it now does. Both new screens are genuinely device-adaptive, not just non-overflowing: a slim bottom bar at `foldCover` width, a persistent side panel on the crease gutter (`foldMain`'s own documented convention) at two-plus columns, proven by a widget test asserting the layout ROOT's actual runtime type differs (`Column` vs `Row`) between postures, not merely "no overflow." See §9.2's own status note and CHANGELOG v0.49.18. **The app's color identity is real now, guardian-configurable, backend-synced** (v0.49.19, §8.16) — `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`, unstyled since the very first build, is replaced by a real six-palette x light/dark catalog (`client/lib/theme.dart`), a new guardian-only picker (`theme_picker_screen.dart`, reached from `guardian_more.dart`), and a real RLS-backed backend (`db/migrations/0017_child_theme_preference.sql`, `GET`/`PUT /v1/children/:childId/theme`) — §8.1's "no settings affordance" for the child shell holds exactly as before, now also proven by a client-side Dart test mirroring `transport.test.mjs`'s own contract check. See §8.16's own status note and CHANGELOG v0.49.19. **v0.49.20 gives §9.2's catalogue Play Together Phase 1's Batch B** — Silly Sentence Maker, Would You Rather, Two Truths and a Tall Tale, and 20 Questions, the four curated-prompt activities the spec's own batching plan named as "mechanically the simplest once Batch A has proven the device-adaptive pattern," carrying the real content-drafting weight this batch actually named as its work: 80 mad-libs words across four categories, 50 would-you-rather pairs, 30 curated two-truths-and-a-tall-tale round sets across five categories (90 statements), and 100 curated 20-questions secrets across five categories — none of it a placeholder. All four are real `GameKind` catalogue entries (`competitive: false, handicaps: []`, `story`'s own precedent) wired into `child_home.dart`'s `onPlay` switch, sharing a new `game_curated_activity.dart` layout base (`CuratedActivityLayout`/`SessionHistoryPanel`) rather than each re-deriving the same posture-driven split four times — the shared base the spec's own batching plan floated as optional, built once here. Two Truths and a Tall Tale is the one activity the spec flagged by name as needing real design judgment: rather than the classic party game's each-player-invents-their-own-facts shape (still an open-text/personal-information risk even with no `TextField` anywhere, since it pressures a real personal fact to be SPOKEN if not typed), every statement — both truths and the tall tale — is fixed, in-repo trivia the app itself authored, never about either player; see `game_two_truths.dart`'s own header for the full reasoning. 20 Questions never asks the app to understand a spoken question either, only to tally curated yes/no taps, which double as a real per-round history log — twenty is a nudge, never a hard stop, per P2. Device-adaptive per the spec's own words for this batch specifically: a single prompt at `foldCover` width, a persistent session-history side panel alongside it at two-plus columns, genuinely ABSENT at narrow width rather than resized, proven by the same layout-ROOT-type widget test (`Column` vs `Row`) Batch A established. See §9.2's own status note and CHANGELOG v0.49.20. **v0.49.21 completes Play Together Phase 1** with Batch C — Copy the Pattern and Find It, the catalogue's first two `minAge: 2` entries, icon/color/shape-based with zero required reading. Copy the Pattern is a genuine Simon-says: a growing tap-back pattern whose LENGTH is the entire difficulty curve, no parent-set dial, self-scaling exactly the way the spec asked. Find It is the one activity in the whole phase where device posture changes real CONTENT, not just layout — a narrow posture renders fewer of a curated scene's hand-placed icon objects, a two-plus-column posture renders its full curated set, proven by a widget test asserting the actual rendered object COUNT differs. Three genuinely distinct curated scenes ship (different icon sets AND different hand-placed layouts, not one scene re-skinned three times). See §9.2's own status note and CHANGELOG v0.49.21. **v0.49.22 is an audit-fix pass** over everything PRs #34–#40 shipped this session (tic-tac-toe/dots-and-boxes, the theme suite, Play Together Batches A–C, the push_channel_test CRLF fix) — a 6-dimension adversarial audit raised 9 findings (1 HIGH child-safety/P2, 4 MEDIUM, 4 LOW), a second pass tried to refute each and could not, and all 9 are fixed here: the HIGH finding was that `game_two_truths.dart`'s and `game_twenty_questions.dart`'s persisted session history encoded a correct/incorrect verdict per round — a de facto win/loss tally P2 exists to prevent, even with no literal number shown — now content-only, matching how `game_would_you_rather.dart`/`game_silly_sentence.dart` already did it; Batch A's own spec-required "common canvas-hosting wrapper" (line ~74) had silently shipped as two independently duplicated private widgets instead, now genuinely shared via `annotation_canvas_view.dart`. See CHANGELOG v0.49.22 for the full account. **v0.49.23 is a documentation-staleness pass, not a feature or code-correctness change** — a full sweep of MASTERFILE, CHANGELOG, MARKUP/shell.html, the two `docs/superpowers/specs/` design docs, README/BRANCHES, and every citation carried by the fourteen Dart files this session's Play Together and theme work added. One more wrong citation was found beyond the two PR #41 already fixed: `theme_picker_screen.dart`'s own header cited its client-side no-settings-affordance test as `child_no_settings_test.dart`; the real file (matching this section's own §8.16 citation) is `child_no_settings_contract_test.dart` — fixed. `BRANCHES.md`'s claim that the four `device/*` branches sit "at the same commit as `main`" was true on 2026-08-08 when they were cut but stale today — `main` has since moved 37 commits ahead while the device branches (correctly, by design) have not; reworded to state that plainly rather than implying current parity. This document's own footer (below) still read "v0.49.21" three versions after the fact — corrected. No other citation errors, broken cross-references, or stale "not yet built" claims were found: §9.2's Play Together status notes, §8.16's theme status note, and both specs' own text already accurately reflect the fully-shipped, fully-corrected state. The real CI-computed assertion total is unchanged at 5447 — confirmed by an actual local run (WSL Postgres 16 + Node 22 + a real `livekit-server` binary for the JS/DB suites, native Windows Flutter 3.44.8 for the 1842 Dart cases), not assumed. See CHANGELOG v0.49.23 for the full account, including two pre-existing documentation gaps found and deliberately left unfixed as out of scope for a citation-and-accuracy pass (CHANGELOG's own early `0.47.0` version-numbering history, and `VISUAL.html`'s long-standing lag behind the other three canonical documents). **v0.49.24 is a compatibility/dependency-audit fix pass, not a feature change** — an independent 3-dimension audit (dependency-resolution, device-adaptive coverage, performance) raised 13 findings, one correctly refuted on re-verification (a `child_home.dart` grid claim with no live bug once actually tested — left alone), and of the 12 confirmed, 11 concrete mechanical fixes are shipped here: `pubspec.yaml`'s SDK floor tightened to match its own already-resolved lockfile and CI's real Flutter pin (`>=3.12.0`, `flutter: >=3.44.0`); `scaffold/package.json` gained a real `engines` field (jsdom's own declared Node range) and `engineStrict`, with CI's `setup-node` pinned to a concrete satisfying version; `jsdom`/`livekit-server-sdk` moved from `dependencies` to `devDependencies`, where their only real callers (a jsdom-driven demo probe, the LiveKit-backed session-runtime suite) already live; `flutter_lints` bumped two majors to `^6.0.0` with every newly-surfaced lint fixed, not suppressed; eight screens (`guardian_home.dart`, `storyteller_screen.dart`, `game_checkers.dart`, `game_chess.dart`, `degradation_banner.dart`, `colour_daily.dart`, `colouring_screen.dart`, `doodle_desk.dart`, `maturation_ladder.dart` — nine files) had a hand-rolled `maxWidth < 420`/`>= 560` breakpoint replaced by this section's own real `columnsAt()`, closing exactly the "none of them matched this table's own nine boundaries" gap named in this section's v0.49.13 note, now textScale-aware everywhere it wasn't before; and the shared annotation-canvas engine (`annotation_canvas.dart`, `annotation_canvas_view.dart`, `game_draw_together.dart`, `game_guess_doodle.dart`) gained a cached `visible()`, a committed/live painter split behind a `RepaintBoundary`, and an O(n²) per-pointer-move point-list copy replaced with in-place `.add()` — see §9.12.4's own status note for the one deliberate deviation this last fix required from its own originally-proposed `shouldRepaint` check, found and corrected by direct probe rather than assumed correct. The 12th, broader finding (roughly 60 screens with no device-adaptive layout at all, of which 15–19 are nav-reachable content screens that should eventually get a `form_factors.dart`-driven two-column tablet layout) is a prioritized backlog item, deliberately NOT attempted this pass — it needs real per-screen design and testing judgment, not a mechanical width-check swap, and is left for a human decision rather than invented here. See CHANGELOG v0.49.24 for the complete account. **v0.49.25 starts that backlog item on its named priority tier of 4 — and treats each of the 4 as its own design decision, not a mechanical apply-to-all.** `message_banking.dart` (a guardian-side compose form followed by a banked-message list, both halves already visible in one `Column`) is the one screen of the four that genuinely fits `court_export.dart`'s established two-pane `Row`/`Expanded` pattern — done, gated by the same real `columnsAt() >= 2` threshold, with the narrow path spreading the same two widget lists back into one flat `Column` in the original order rather than nesting a wrapper `Column` around them, an actually-identical tree at `columnsAt() < 2`, not merely a visually-equivalent one. The other three — `homework_screen.dart` (§8.13.5's own documented "still" surface, deliberately the sparsest in the product, no list-selects-detail shape to split), `weeks_screen.dart` (a rhythm visualization, a `Wrap` of night-beads that already reflows on its own), `inbox_screen.dart` (whose only "detail" relationship is a `Navigator.push` to a full-screen `ReceiptScreen`, and turning that into a persistent pane would be a separate, bigger interaction-model decision) — do not fit a two-pane split, so instead all three get one new, lighter, shared treatment: `form_factors.dart` gains a new `comfortableReadingWidth` constant (640, explicitly documented as a typography cap, not a tenth posture), and each screen's single column is centered and capped to it once `columnsAt() >= 2`, so it stops stretching edge-to-edge on a tablet or desktop. `homework_screen.dart`'s `AnimatedSwitcher`/`fadeMs` motion-budget logic is untouched inside the cap; `weeks_screen.dart`/`inbox_screen.dart` apply the cap to both their empty- and populated-state paths. 7 new widget tests (4 for the two-pane split, 1 per capped screen) prove both the wide-viewport behavior and that the Fold5 cover/phone widths are byte-for-byte unchanged; `flutter test` is 1849/1849 (1842 + 7), `flutter analyze` clean. This closes 4 of the ~60 screens (all nav-reachable content screens) — roughly 56 remain overall, and the nav-reachable content-screen subset drops from 15–19 to 11–15. See CHANGELOG v0.49.25 for the complete account. **v0.49.26 continues the same tier with three more real two-pane candidates** — `wants_needs.dart`, `expenses_screen.dart`, `letters_screen.dart` — each read individually and confirmed to share `message_banking.dart`'s exact compose/list-halves-already-visible shape; `expenses_screen.dart`'s P6 gate (`_NotAGuardianSurface`) is confirmed untouched and still unconditionally first. `journal_screen.dart` was read, planned, then deliberately dropped from this tier — a separate, further-along effort already gives it a reading-width cap instead, a better fit for §8.13.5's "permanently still" framing than a two-pane split, and this pass defers to that judgment rather than duplicating or overriding it. `flutter test` is 1861/1861 (1849 + 12), `flutter analyze` clean. See CHANGELOG v0.49.26 for the complete account. **v0.49.36 makes real OS PiP possible for the child too, at the owner's explicit, informed direction after the tradeoff was disclosed twice, and live-verifies both the safety fix this required and a second feature it does NOT support** — see §5.24.4's own REVISED note for the full account. `call_screen.dart`'s `callFeatureFlagsFor()` sets `pipEnabled`/`pipWhileScreenSharingEnabled` true for both roles (was guardian-only since v0.49.35's own containment pass). A real native fix closes the containment hole this opens: `KioskBridge.kt`'s new `ACTION_CALL_ACTIVITY_DESTROYED` broadcast (fired from `WrapperJitsiMeetActivity.kt`'s own `onDestroy()`) is now the ONLY thing that clears the call-handoff flag, replacing a one-shot read-and-clear design a real PiP entry could already silently defeat; `MainActivity.onResume()` now re-pins on every resume while a handoff is outstanding. **Live-device verified**, not just compiled: a real, genuinely kiosk-pinned tablet (`mLockTaskModeState=PINNED`, the real system "App is pinned" dialog) showed the unpin/re-pin sequence trace correctly through `dumpsys`/logcat exactly as designed. A separate, paired feature — automatically opening a drawing screen the moment she PiPs — was built, live-tested, and **reverted**: the assumption it depended on (PiP entry resumes the host Activity) was found false for a Home-triggered PiP specifically, traced to Android's own `RootWindowContainer.startHomeOnTaskDisplayArea` reasserting the launcher as PiP host — a real platform policy three separate native mitigations all lost to, not a bug any of them missed. `flutter analyze`/`flutter test` both clean (1904/1904). Also found and fixed along the way: `api_client.dart`'s `devLoginFor()` had no timeout, hanging indefinitely on a slow/unresponsive dev server — a real dev-tooling bug, not a production one. See §5.24.4's own status note and CHANGELOG v0.49.36. **v0.49.37 is a fresh, from-scratch 118-agent audit's Tier-1 findings, fixed** (not the 2026-08-14/17 scoping docs, which had drifted stale) — every finding independently verified real by 3 skeptics against the current files before being acted on. Two real P1-P9-relevant bugs closed: `onThisDay()`'s own `a.eraTag &&` short-circuit let untagged material bypass every P9 era mute a family configured (archive.ts, now fails closed); `care.ts`'s emergency-card leak guard maintained its own narrower duplicate of the location-key list its sibling guard already got right, missing `lat`/`lng`/`coords`/`geohash`/`accuracy`/`altitude` (now shares one list with both guards). A real-harm bug closed: `buildCard()` silently overwrote a guardian's own corrected emergency contact with the hardcoded US default, with zero trace — a guardian-supplied contact now wins. `packages/emergency`'s own module had zero test coverage anywhere in this repo before this pass; a real, dedicated 26-assertion suite now covers it, wired into `verify.sh`. The global child-payload sweep (`globalaudit.ts`'s `GLOBAL_CHILD_FORBIDDEN`) is wired into real production for the first time — `Api.handle()` itself, the one choke point every response to a child principal passes through — after having zero real callers despite existing specifically so "a field one author knew was dangerous protects surfaces they never saw." **A real regression this same wiring caused was found and fixed the same pass, before merge**: the child's own real take-and-go export (§9.8.4) legitimately includes her message log by design (`rungs.ts`'s `NOT_HERS_TO_DELETE`) and started 500ing on the sweep's own ban of that field name — fixed with a new, narrow `skipChildPayloadSweep` route flag, the fourth of its kind, set on exactly that one route. A stale citation (`globalaudit.ts`'s own header claimed "MASTERFILE §20.5" for years; that section is actually "Recommended Phase 0 exit order," unrelated) corrected rather than propagated into the new code that references it. Real, computed total 5581 (corrected from this note's own first published 5560 after real CI, not a second local guess, surfaced a local verification gap — a missing `/tmp/livekit-server` binary had silently zeroed 21 real assertions in `live.test.mjs`; see CHANGELOG v0.49.37 for the full root-cause account), confirmed via a full local `tools/verify.sh` run with the real binary present, 0 failed. No live-device verification needed — every change is server/package-level. See CHANGELOG v0.49.37. **v0.49.38 hardens the kiosk re-pin path itself** (§5.20, §8.3) — `KioskBridge.startLockTaskVerified()` (new, duplicated in `WrapperJitsiMeetActivity.kt` for the same module-boundary reason `ACTION_CALL_ACTIVITY_DESTROYED` already is) calls `startLockTask()` once and polls for real settlement rather than firing and assuming, gated on `Activity.hasWindowFocus()` first. **This fix's own first version was itself wrong and self-corrected via live re-testing**, not shipped on one green run: real `dumpsys`/logcat evidence showed the original re-call-on-every-retry design was interfering with Android's own asynchronous screen-pinning confirmation UI, and separately that `kiosk_shell.dart`'s `_engage()` (Dart's own `initState()`) can reach native code before the Activity's window has focus at all — both fixed within the same pass. Honestly disclosed, not claimed solved: this specific Tab S9 FE's pin settlement remains variable under this test harness's own heavy Jitsi-SDK-prewarm load, the same already-accepted device quirk v0.49.36 disclosed. Also closes a real handoff-flag leak (`M_STOP` now clears `expecting_call_handoff`, not just the pin itself; a fresh process start defensively clears an orphaned flag too) and adds real-time PiP defeat detection via `onPictureInPictureModeChanged()`, reusing the existing `ACTION_CALL_LOCK_TASK_EXITED` signal rather than waiting on `onStop()`, which Android defers while a PiP window is visible. See CHANGELOG v0.49.38. **v0.49.39 closes eight Tier-2 audit findings, each independently adversarially re-verified against the actual base code, not the implementer's own report** — a real dead-wire crash in `take_and_go_screen.dart` (`result['bundleJson']` read against a response whose real key is `serialized`); a real account-bootstrap route (`POST /v1/guardian-invites/:inviteId/bootstrap`, `bootstrapGuardianInvite()`) closing the first-time-guardian gap CHANGELOG v0.49.9 explicitly declined to invent; a schema fix making a child a real, representable message sender for the first time (`author_child_id`/`sender_child_id`, `db/migrations/0021_child_message_sender.sql`); real call metadata folded into the certified export bundle's own hash; `offline_outbox.dart`, giving a connectivity gap an honest, distinct state from a real server rejection; and a real, unit-tested (not live-device-verified — no watch hardware in this environment) "Call Dad" wiring on the Wear OS companion. **Two of the eight re-verifications came back SUSPECT and were right**: `annotation_canvas.dart`/`canvas.ts`'s `redo()` had a second, independent erased-stroke ordering bug the first fix missed (closed by having `erase()` clear a stale `undoneAt` rather than leaving the invariant to every future reader), and the offline-outbox refactor had left the camera-picker call outside any error handling, able to strand the UI in a fake "Sending…" state forever — both fixed before merge, not after. See CHANGELOG v0.49.39. **v0.49.40 closes nine Tier-3 test-coverage gaps, all at the same HTTP/route layer** — kiosk-pin/verify, guardian-invite creation, WebAuthn registration, theme routes, device-token routes, `/now`, `POST /v1/me/delete`, guardian-invite revoke, and a real `CaptionPort` interface (§8.8.1) mirroring this codebase's own `StoragePort`/`RoomLifecyclePort` house pattern — an unimplemented, doc-commented contract, not a fake captioning backend, since none exists yet. Every underlying pool function was already honestly tested; nothing exercised the real HTTP route's own identity/authorization boundary, validation, or error-code mapping through `Api.handle()` itself. **A real, previously-silent bug was found and fixed along the way**: `revokeGuardianInvite()` promised idempotency but had no `revoked_at IS NULL` guard, so a double-tap silently overwrote the real revocation timestamp — a genuine integrity issue for a feature whose own court-export exists to produce a trustworthy record of when access was revoked. All nine findings independently adversarially re-verified; all nine CONFIRMED. See CHANGELOG v0.49.40. **v0.49.41 is the fourth and final tier of the post-audit doc-parity/CI-tooling pass** — §5.26's own PiP claims reconciled with shipped reality (see this section's own REVISED note above), a real Windows dev-notes doc added (`scaffold/docs/windows-dev-notes.md`), and a real CI-reproducibility gap closed: `.github/workflows/verify.yml` now explicitly pins the Android SDK/build-tools version (`android-actions/setup-android@v3` + `sdkmanager`) the same way it already pins Flutter — the original investigation of this finding was itself wrong (assumed CI's Android gate never runs; real CI logs show it does, unpinned, since GitHub's runner image ships one), caught and corrected by this pass's own adversarial re-verification before shipping. See CHANGELOG v0.49.41. **v0.49.42 is a fresh 5-lens audit pass beyond the four tiers above** — a real authorization bug closed (`server/routes.mjs`'s call-start route hardcoded `observerOnly: false`, so an observer-only guardian's session could still publish; now reads the real per-edge value, fail-closed); the dev-stack's Postgres port closed to loopback-only, matching the earlier `server`/`callroom` hardening (v0.49.32) it had been left out of; `invitation_screen.dart` now loads the real invite before Accept is reachable, closing a dead-wire fetch that let a caller-supplied name go uncross-checked against the server; two test-coverage gaps this document's own `README.md` had named as open since Phase 0 (the `expense` RLS read-denial proof, three missing `policy_has_target` probes) are closed with live-Postgres-verified assertions; and three phantom section citations (a fabricated §12.8–§12.11/§17.6 range in `pending.ts`, a fabricated §8.9 in `i18n.ts` — which had zero test coverage anywhere before this pass — and a fabricated §11.4 in `emergency.ts`) are corrected across every file each had propagated to, including one instance a fixing pass's own adversarial re-review caught left unfixed with a false verification claim in its commit message. Real total 6072 (4123 JS/server/SQL + 1949 Dart), confirmed via a fresh `tools/verify.sh` and native Windows `flutter test`, not carried forward. See CHANGELOG v0.49.42. **v0.49.43 closes three real infrastructure gaps named in §20.2b since at least Phase 0** — a real scheduled-jobs runner (`tools/scheduler.mjs`, closing the "no cron ever calls materialize()'s sweep" gap, whose real severity turned out to be that no message this product delivers could ever actually go out in a real deployment without it), Postgres backup/restore + production-grade Docker hardening (`tools/backup-db.sh`/`restore-db.sh`, `docker-compose.prod.yml`, real healthchecks — proven with a real drop-the-database-and-restore-it roundtrip, 27/27 tables, not asserted), and real object-storage wiring closing the `StoragePort` gap directly above this note. Two real bugs found integrating these systems, beyond what their own adversarial review caught: a `::text`-cast timestamp bug that silently stuck real messages in an unreachable state (fixed with this codebase's own established `to_char(...)` idiom), and a migration (`0022_backup_reader_role.sql`) that would have broken CI itself because `tools/verify.sh`'s own Postgres provisioning never created the role the migration grants onto. See CHANGELOG v0.49.43 for the complete account. **v0.49.44 closes the product-name question** (§16.2 #1, the one item this document's own README checklist still had open) — a real, good-faith USPTO/app-store search, not a placeholder; see this document's own header note for the full account. Kept "Olive"/"Olive Branch," no blocking conflict found in the co-parenting/custody category; one same-class, different-goods pending application disclosed rather than hidden, with the honest caveat that a licensed trademark attorney's formal opinion remains the right step before any real filing or wide launch. See CHANGELOG v0.49.44. **v0.49.45 closes two real production-readiness gaps, Tier B of a fresh tier/priority/risk-organized gap-inventory pass** (highest priority, lowest risk): `docker-compose.prod.yml`'s `server` service had no persistent volume for uploaded child media (`POST /v1/children/:childId/media`, v0.49.43) — every uploaded photo lived only in the container's writable layer, gone on any routine redeploy, a real data-loss risk in this same session's own recently-shipped work; now a named `olive-prod-media` volume, matching `olive-prod-pgdata`'s existing pattern, with `MEDIA_STORAGE_ROOT` pinned explicitly rather than left to an internal path-derivation fallback (`docker-compose.dev.yml` gets the same fix — its own `db` data was already persisted via `olive-dev-pgdata` while media was not, an inconsistency worth closing there too). Second: `docker-compose.prod.yml` had no `scheduler` service at all, so the nightly rematerialization sweep (v0.49.43) could never actually run in a real deployment, regardless of the dev-only opt-in Compose profile that service uses — closed by adding a `scheduler` service to the production file that is deliberately NOT profile-gated, since dev's opt-in rationale (protecting a live debug session from a background sweep rewriting rows mid-inspection) has no production analogue, and gating it there would instead mean the documented default `up -d` silently delivers nothing until an operator finds an undocumented second flag. See CHANGELOG v0.49.45. **v0.49.46 closes a real, previously-undisclosed fourth infrastructure gap in the same family — Tier B continued**: `packages/storage/src/storage.ts`'s `reap()`, the real, tested COPPA retention reaper (real since before v0.49.43, its own header naming the stakes: "the blob IS the regulated personal information... a reaper that deletes rows and leaves media is not a retention policy"), and its SQL half (`artifacts_due_for_reaping()`/`reap_tombstone`, migration 0004) had zero production callers — found only by this pass's own gap-inventory sweep, not by the pass that built them. The monitoring existed and was already live (`reap_tombstone`/`retention_breach` feed `health_check`, wired since migration 0009); only the thing it would ever have anything to alert ON was missing. `tools/scheduler.mjs` gains a third job, `reap-media`, closing it — real Postgres-backed glue proven by 16 new live-Postgres assertions (`packages/db/test/scheduler.test.mjs` section C): a due row's blob and row both go, a preserved row is excluded by the SQL `WHERE` clause itself (never reaching `reap()`'s own belt-and-braces check), a not-yet-due row is untouched, an already-tombstoned row is excluded by the SQL `NOT EXISTS` rather than re-attempted, and a blob-delete failure leaves the row in place with a real `reap_tombstone` write. See §20.2b's own status note and CHANGELOG v0.49.46. **v0.49.47 closes Tier C's one genuine item (a fresh tier/priority/risk gap-inventory pass had flagged four; three turned out to be deliberate, already-reasoned design decisions on direct inspection — WebAuthn attestation-signature verification, general server-side session revocation, and the SEC-01 device-token TOCTOU race are each explicitly declined in their own code — and were correctly NOT built) — real row-level security for `media_artifact`, `intent_batch`, `delivery_intent`, the exact gap `persistCapturedMessage()`'s own doc comment named as needing "its own migration and its own review."** A full pre-migration audit (three independent sweeps, one per table) found every real write to all three tables already runs as `system`; real caller-scoped reads exist for exactly two — `GET .../inbox` (a child reading her own messages, or any of guardian/step_parent/trusted_adult/foster_parent) and `GET .../export` raw kind (a live guardian). The design this pass shipped is NOT this schema's older `expense_no_child`/`custody_order`-style "any non-child role, any child" pattern — an adversarial security review found that shape would leave zero RLS restriction on which child's rows a guardian session can see, relying entirely on the application's own `WHERE child_id = $1` binding; a second, independent functionality review then found the review's own proposed fix (copying `call_log`/`child_theme_preference`'s hardcoded `= 'guardian'` condition) would have silently broken every step_parent/trusted_adult/foster_parent's real, working inbox read. The shipped policy generalizes `actor_has_edge(child_id)` to the full role set `authorize.ts`'s own `ROLE_CAPS['message']` actually grants, proven by 22 live-Postgres assertions (`db/test/0007_message_media_rls.test.sql`) including a `coordinator` role holding a real, live edge but still correctly excluded (the role list is real, independent enforcement, not a redundant echo of the edge check). **Writing this migration's own first-ever HTTP-level test for `GET .../inbox` — a route this document had zero coverage of before this pass — surfaced a real, previously-undiscovered production bug, unrelated to RLS**: the route's response wraps its rows under the key `messages`, which is on `globalaudit.ts`'s own `GLOBAL_CHILD_FORBIDDEN` list (banned there for an unrelated reason) — meaning `Api.handle()`'s global child-payload sweep (wired in v0.49.37) has 500'd `child_payload_leak` on every real child session's own inbox read since that sweep first shipped, invisibly, because every existing manual/device check of this route was a guardian request and `child_home_live.dart`'s own header already disclosed this exact screen had never been run against a real deployed backend. Fixed by renaming the field to `entries` (client and its own test updated to match) rather than exempting the route from the sweep — the field itself was never adult plumbing, only its old name collided. See §20.2b's own new status row and CHANGELOG v0.49.47 for the complete account. **v0.49.48 is a Tier A + Tier E polish pass — doc-parity corrections plus four zero-coverage test files, each verified real before being acted on rather than trusted from an earlier gap-inventory list.** Tier A: three stale product-name passages (§16.1b/§16.2/§16.3) updated to reflect the real v0.49.44 clearance search; `notify.ts`'s own header corrected — it still claimed `notifyDevices()` "has zero HTTP call sites," true when written but false since v0.49.33's real `POST .../calls` route; §5.25.2's own "no live call site" disclosure updated to the real v0.49.33/v0.49.34 closure; §20.2b's stale "child cannot yet send an async video message" row struck through and closed (v0.49.39 already closed it in code; this document simply never caught up, including a residual stale migration-number reference in `messages_route.test.mjs`'s own comment that a prior pass's "every cross-referencing comment updated" claim had itself missed); and a phantom `§8.12` citation family spanning `postures.ts`/`postures.test.mjs`/this document, first partially caught in v0.49.13 for one sub-citation and left otherwise uncorrected, retargeted to its real matches (§8.11.2, §8.11.1) with one sub-citation honestly disclosed as having no confirmed MASTERFILE section at all rather than forced to fit. Tier E: `packages/globalaudit`/`observer`/`offline`/`toddler` each get a first real test file (163 new assertions) — writing `globalaudit.test.mjs` found and fixed a genuine (harmless but real) duplicate entry in `GLOBAL_CHILD_FORBIDDEN` (`'balance'`, listed in two groups). Three of the gap-inventory pass's original four Tier C items were separately found to be deliberate, already-reasoned design decisions rather than gaps — see this section's own v0.49.47 note above; this entry does not revisit that finding. See CHANGELOG v0.49.48 for the complete account. **v0.49.49/v0.49.50 closed out Tier D, the plan's fifth and final tier — judgment-call items, not mechanical fixes**: a real sign-out flow (`guardian_more.dart`), `receipt_screen.dart`'s live caller (`inbox_screen.dart` self-fetching its own real inbox, the same self-fetching pattern `HomeworkScreen` established), a signed-URL media-serving route (`server/signed_media.mjs`), and — the item deferred at v0.49.49 pending one real tie-break judgment call, resolved at v0.49.50 by porting `signal.ts`'s `prioritise()` convention — `ChildHome.presence`'s live data source. Call-quality UX wiring was explicitly declined (a real architecture decision between the shipped native-Jitsi hand-off and the aspirational §5.26 in-app pane, judged the product owner's call, not inferred). **v0.49.51 is a post-tier adversarial audit-and-fix pass** over everything shipped since the round-5 audit (v0.49.45 through v0.49.50): a 5-lens, 50-agent independent review (correctness, security/RLS, child-safety, doc-parity, production-readiness) found 14 findings surviving adversarial verification, of which 13 were confirmed real and fixed here (a real COPPA-relevant bug — the `reap-media` scheduler job silently orphaning blobs while deleting their tracking rows, because the `scheduler` container never shared `server`'s own media volume; an unguarded row-delete in `reap()` that could poison-pill the whole nightly sweep; the prod media volume never being backed up at all despite this document's own "backups exclude nothing" claim; a live parent-reachability signal reachable by sitters/coordinators/caseworkers via the same `calendar.view` capability static schedule data uses; `POST .../inbox/:id/opened`, declared in §7.3 since that section was first written, finally built; a signing secret that silently re-randomized on every server restart, invalidating every outstanding signed media URL) — and one finding (a real-seeming, 3/3-adversarially-"confirmed" claim that migration 0023's RLS blinds `health-alert.mjs`'s own monitoring) was independently re-verified against a real Postgres and found to be a genuine false positive: `health_check`/`orphan_risk`, both VIEWS owned by a superuser from running migrations, correctly see RLS-protected rows regardless of the querying role's own restrictions — Postgres evaluates row security for a non-`security_invoker` view using the view owner's privileges, not the caller's, which is exactly why `health-alert.mjs` has kept working correctly without `app.role` ever being set. Left as a real, disclosed, un-silently-resolved product/wording question: whether `ChildHome.presence`'s existing "free right now... until `<time>`" framing sits comfortably beside §5.25.4's own stated reasoning against a structurally similar pattern. See CHANGELOG v0.49.51 for the complete account. A direct "is everything actually built" question, answered by a real evidence-based audit rather than assumed, found the coordination layer's own parent-to-parent handover log (`message_log`, court-tier RLS/append-only/hash-chain enforcement since it was first migrated) had real client UI and zero production writers — **CLOSED v0.49.52**: real `GET`/`POST /v1/children/:childId/handover-notes`, real `appendHandoverNote()`/`handoverNotesFor()`, real live client wiring behind a new `guardian_more.dart` tile. Expenses (`expense`, real FORCE RLS since 0006 too) closed the same way next — **CLOSED v0.49.53**: real `proposeExpense()`/`expensesFor()`/`resolveExpense()`, real `GET`/`POST /v1/children/:childId/expenses` + `.../accept|dispute|reimburse`, a new `expense.resolve` Action, real live client wiring with P6 (no financial surface for a child, checked twice: RLS and the client's own `viewerRole` gate) proven to hold even under live wiring. Medications + the emergency card closed next — **CLOSED v0.49.54**: a real `medication`/`medication_dose`/`medical_record` schema (the dose-collision guard is a real Postgres partial unique index, not just an app-layer check; "Guardians" is derived live from real `guardianship`/`app_user` rows, never a second stored copy), a new `emergency_card.edit` Action, both `meds_care.dart` and `emergency_card.dart` live-wired with their demo modes fully preserved. This pass's own test suite caught a real bug before it shipped: all four new routes' first draft relied on the outer gate alone, which only auto-refuses a child session for P6/P7 — every other action passes it by design — fixed with the same explicit per-route child guard every other coordination route already carries. Exchange (`exchange_screen.dart`'s bag manifest/running-late log/arrival — Handoff/Coming-up deliberately stay on demo data, a disclosed scope split) closed next — **CLOSED v0.49.55**: real `exchange_bag_item`/`exchange_running_late_log`/`exchange_arrival_event` (`db/migrations/0027_exchange.sql`), `scheduled_at`/`delay_minutes` computed server-side from the child's real active custody order (`activeCustodyOrderFor()`), never client-supplied, with a real honest-absence 409 (`no_active_custody_order`) when none is on file. Care notes and letters closed last — **CLOSED v0.49.56**, the final two pieces of this coordination-layer closure plan: `care_note` (guardian-only, a real server-side tone guard reused directly from `packages/guardian/src/guardian.ts`, never re-implemented) and `letter` — the ONE child-owned, guardian-EXCLUDED table in this whole schema, RLS mirroring `journal_owner_only` exactly, a real server-computed current age from her real `birth_date` gating both sealing and opening, and a letter's real body text withheld at the SQL projection layer itself until she has actually opened it — proven not just by route tests but by a raw RLS query directly. The coordination-layer audit this whole plan answers is now fully closed. See CHANGELOG v0.49.52/v0.49.53/v0.49.54/v0.49.55/v0.49.56. |
| **Assertions** | See `npm run verify` — the count is computed, never quoted here (standing rule 5, §20.4). |
| **Market scope** | **United States only** |
| **Companion docs** | `OLIVE BRANCH_CHANGELOG.md`, `OLIVE BRANCH_VISUAL.html`, `OLIVE BRANCH_MARKUP.html` |

---

## §0 Document control

**Standing rule.** **Four** documents are canonical: this MASTERFILE, the
CHANGELOG, the VISUAL representation, and the MARKUP. They are **amended, never
duplicated**. All four are kept in sync across three locations:

1. Project knowledge
2. Assistant memory
3. Google Drive — folder `OLIVE BRANCH — Canonical`

No forked copies. No `MASTERFILE_v2_final.md`. Every change lands as a CHANGELOG
entry with a matching version bump here and a corresponding update in
VISUAL.html.

**MARKUP is visual.** `OLIVE BRANCH_MARKUP.html` shows what the product looks
like — rendered screens in device frames, one per surface, across the child
shell, the guardian shell, desktop, and setup.

Its purpose is not decoration. **Every screen is a consequence, and every caption
names the decisions that produced it.** Locking in a choice has a visible result;
reversing one has a visible cost. Tags on each screen mark settled choices in
green and prohibitions being honoured in red.

The final panel — *Cannot be drawn yet* — is the point of the document. It lists
the screens that are **unbuildable because a decision is still open**, each
naming the §16.2 or §19 item that blocks it. A choice's cost is visible before it
is made.

**MARKUP amends in step with the CHANGELOG, and this is enforced.** Any increment
that changes a user-facing surface, settles a §16.2 decision, or adds a
prohibition must update MARKUP in the same turn.

`scaffold/tools/check-markup.mjs` fails the build on drift, and runs inside
`npm run verify`:

| | Check |
|---|---|
| C1 | MARKUP's version tag equals the newest CHANGELOG version |
| C2 | MARKUP's spec tag equals this document's version |
| C3 | Declared screen count equals rendered screens |
| C4 | Every screen carries `data-since` (and `data-amended` where altered); every declared version exists in the CHANGELOG; every visual-era CHANGELOG version appears in MARKUP |
| C5 | Every §ref in MARKUP resolves to a real section here |
| C6 | Every prohibition ref resolves to a live §2.1 entry — so deleting a prohibition while a screen still honours it fails the build |
| C7 | The assertion count MARKUP quotes equals what `verify.sh` computes |
| D1 | `DEMO.html`'s manifest version equals the newest CHANGELOG version |
| D2 | The demo's declared assertion count equals what `verify.sh` computes |
| D3 | Every MARKUP screen slug is accounted for in the demo manifest — mapped to a demo screen, or listed in `notDemoed` with a reason. **A new MARKUP screen fails the build until someone decides whether it is demoable.** |
| D4 | Every mapped target exists among the demo's actual screens |
| D5 | Under-construction areas are referenced and non-empty |
| D6 | The demo declares its target device — **Galaxy Z Fold 5** — with **both** viewports: cover 344×882 CSS (904×2316 physical) and main 673×841 CSS (1812×2176). The main screen must be recorded as nearly square, because a layout tuned for a tall phone wastes it and one tuned for a tablet breaks the cover screen. |
| D7 | No hard element width exceeds the 344 px cover screen |
| **E1** | The demo declares a `nodeOnly` list |
| **E2** | **Every module in the build script is either imported by the demo bridge or declared node-only.** Silence fails. |
| E3 | Every node-only declaration names the dependency, and it begins `node:` |
| E4 | Nothing is both wired *and* excused — a stale excuse cannot hide a regression |
| E5 | No node-only declaration refers to a module that no longer exists |
| E6 | The engine room names all fourteen wired engines **in the built artifact** |
| E7 | A node-only claim is **true** — the module really does import what it says |

Every one of the seven has been **shown to fail** when the thing it guards is
broken, per standing rule 3 (§20.4). C7 is standing rule 5 applied to a document:
a number quoted in prose that nothing checks is the same defect as a hardcoded
total in a build script.

**Standing rule, extended v0.33.0: a declaration is not an implementation.**
Three times in one increment I declared a mechanism — a `degradesTo` target, a
posture, a delivery fallback — and shipped nothing behind it. Every check passed,
because they verified the declaration was *well-formed* rather than that anything
answered it. **A documented assurance with nothing behind it is worse than an
omission, because an omission is visible.** Enforced by F1–F4 in
`check-markup.mjs`.

**Standing rule, extended v0.31.0: read the package directory before writing a
module.** Twice in one increment I wrote a module that already existed — a
maturation ladder that `maturation.ts`, `rungs.ts` and `family.ts` already
implemented, and an observer/accessibility pair that `observer.ts` and `a11y.ts`
already implemented. Both were reverted. A project with 46 modules has outgrown
the point where recall is a reliable index of what exists; **`ls packages/` is the
index, and it is now the first step of any build turn.**

**Standing rule (added at user request, v0.30.0): everything shipped renders in
the demo.** An audit at v0.29.0 found **21 of 37 built modules had no demo surface
at all** — the homework capture, the journal, the court export and eighteen others
were static mockups sitting beside fully tested engines that nothing called. That
is the kind of gap that grows quietly and is invisible in a green build.

From now on a module is either **wired into the demo bridge** or **declared
node-only with the dependency that makes it so.** Enforced by E1–E7 in
`check-markup.mjs`; each has been shown to fail when its guard is removed. The
Engine Room screen renders every wired engine by calling it live, so the values
shown are computed at page load rather than written by hand.

**The same rule found the same gap on the Flutter client, v0.44.0.** Fourteen
parallel build groups each shipped their assigned client screens — 75 new
files in `client/lib/`, each `flutter analyze`/`flutter test` clean in
isolation — but 62 of the batch's 72 MARKUP screens had no path to them from
either `ChildHome` or `GuardianHome`: correct code with no navigation route is
the client-side twin of an engine with no demo bridge. Closed by a single
navigation-wiring pass (`child_home.dart`, `guardian_home.dart`, and three new
hub screens — `games_hub.dart`, `child_more.dart`, `guardian_more.dart`) that
touched no other group's file. `availability` is the one screen this did not
close, because nothing in the batch renders it under any name.

**Standing directive (§21).** The product is intended to **grow up with the
child**, and the handover at 18 is the last of many transitions rather than the
only one. Every future increment is measured against three questions:

1. Does this hold at seventeen, or only at seven?
2. Does it move authority *toward* the child as she ages, or away?
3. At what age should it stop being shown to her at all?

§21 is **specified, not built.** No increment should implement it piecemeal
without reading §21.7 first — the adolescence risk there is the one that would
quietly turn this into a different product.

**The target device is a Galaxy Z Fold 5, and it is two devices.** The cover
screen is 344 CSS px wide — narrower than almost any other phone — and the main
screen is 673 × 841, nearly square. The crease runs vertically down the centre
of the unfolded screen, so two-column gutters are placed there deliberately.
Unfolding resizes the viewport live, so no layout may depend on a width measured
once at load. `demo/test/drive.test.mjs` runs its entire drive at **both**
viewports.

**`DEMO.html` is a derived artifact and must not lag.** It is built from
`scaffold/demo/` and driven by the shipped engines, so it cannot show a figure
the code does not produce. It amends in step with the CHANGELOG and MARKUP, and
`demo/test/drive.test.mjs` renders every screen and clicks every control on each
`verify.sh` run so it cannot rot silently.

> The generated schema inventory formerly at this name now lives at
> `scaffold/INVENTORY.md` as a build artifact — regenerate with
> `npm run markup`. It is tooling output, not canonical.

**§2.1 is load-bearing.** Removing or weakening any prohibition requires an
explicit CHANGELOG entry naming the prohibition, the requester, and the rationale.
Silent deletion is a process failure.

---

## §1 Product thesis

**The child is a first-class user, not a subject of record.**

Two mature categories exist and neither occupies the middle:

- **Co-parenting legal tooling** — OurFamilyWizard, TalkingParents, AppClose,
  2Houses, Custody X Change. Built for courtrooms. Message logs, expense ledgers,
  custody calendars, tamper-evident records. The child has no login. Pricing is
  typically per-parent and annual.
- **Kid co-presence tooling** — Caribu, Messenger Kids, plain Zoom/FaceTime. Warm,
  child-facing, and completely absent any family-governance layer. Amazon Glow is
  the cautionary tale: strong co-presence concept, killed by requiring dedicated
  hardware.

**Olive Branch is a child-first co-presence platform with adult-grade governance
underneath it.** Every decision in this document follows from that sentence.

### 1.1 Positioning

Do **not** brand as a divorce product. Frame as *staying present*. The addressable
population is far wider than custody disputes and carries none of the stigma:

| Segment | Why it fits | Notes |
|---|---|---|
| Military deployment | Extreme separation, poor connectivity, async-native | Institutional funding exists (USO, Blue Star Families). Strongest wedge. §9.5 is aimed here. |
| Travel-heavy work | Consulting, sales, aviation | Highest willingness to pay, lowest support burden |
| Long-haul trucking | Weeks away, irregular hours | Async engine is the entire value prop |
| Incarcerated parents | Severe need, funded programs | Heavy compliance; SMS bridge (§8.4) is the enabling piece |
| Hospitalized parent or child | Long-term care separation | Partnership channel via child-life services |
| Separated / divorced | Largest raw volume | Court-adjacent features are the paid tier |
| Grandparents at distance | Expansion surface, not a wedge | Trusted Adult role |

---

## §2 Product principles

Constitutional. Any feature that violates one gets cut, not negotiated.

1. **§2.1 — The child never sees parental conflict.** Not in the calendar, not in the
   wants/needs list, not in a declined request, not in an expense, not in a
   notification.
2. **§2.2 — The child's clock is canonical.** Every time a parent sees about their child
   renders in the child's local time first. Parents never do arithmetic.
3. **§2.3 — Async is not a degraded mode.** It is the primary mode. Synchronous calls are
   the highlight; async is the heartbeat.
4. **§2.4 — Guardianship is an edge, not an account tier.** Access derives from a
   relationship with its own scope, dates, and court reference.
5. **§2.5 — No discovery, ever.** No search, no public profiles, no strangers. The family
   graph is invite-only and guardian-approved.
6. **§2.6 — Data symmetry between guardians; privacy from the child where appropriate.**
   Neither parent can hide platform activity from the other. Both retain private
   space the child cannot see.
7. **§2.7 — Nothing is retained indefinitely without an owner.** Every artifact carries
   an expiry or an explicit preservation election. See §9.8.
8. **§2.8 — Recording is off by default.** Children cannot consent.
9. **§2.9 — Teens get graduated privacy.** A surveilled 15-year-old abandons the app.
10. **§2.10 — The archive belongs to the child.** Parents are custodians of it, not owners.
    At majority it transfers. See §9.8.4.
11. **§2.11 — The archive is never held hostage.** Raw export is available to any guardian
    at any time, free, on every tier, including after cancellation. Lapsed payment
    degrades features; it never withholds a child's material. Only the *certified,
    court-formatted* export is tiered. See §16 #3.
12. **§2.12 — One parent is a complete product.** The platform must be fully useful with a
    single guardian. Asymmetric adoption is a permanent supported state, not a
    funnel stage. See §17.

### 2.1 Prohibited by design — permanent bans

These are not backlog items that lost a prioritization fight. They are features
we have decided are harmful, and each will be re-proposed — usually in good faith,
usually with a sympathetic framing. The right-hand column exists so the proposal
is recognizable when it arrives.

| # | Prohibited | Why | Arrives disguised as |
|---|---|---|---|
| **P1** | **Synthetic or cloned parent voice / likeness.** No generated audio or video of a real parent, in any feature, at any tier. | A child cannot meaningfully consent to a synthetic version of their parent. The failure mode — a child who can no longer distinguish a real message from a generated one — is severe and irreversible. | "AI bedtime stories in Dad's voice for deployment", "voice preservation for terminal illness", "just filling gaps when he can't record" |
| **P2** | **Punitive streaks or engagement scoring shown to the child.** Continuity is measured internally (§13) and never surfaced to a child as a score, badge, or broken-streak notification. | Manufactures guilt in a child for an absence they did not cause and cannot control. | "gamify engagement", "streak badges", "consistency rewards", "nudge the away parent" |
| **P3** | **Live location sharing.** Arrival *events* only (§9.7.2). No coordinates stored, transmitted, or displayed, ever. | Converts the product into the exact surveillance instrument named in the §15 threat model. | "safety check-in", "find my kid", "did she get there", "geofence for peace of mind" |
| **P4** | **Purchase mechanics on the wants list.** No price field, no buy button, no affiliate link, no gift routing. | Builds a bidding war between parents and amplifies the Disneyland-parent dynamic. | "one-tap gifting for grandparents", "make it easy to actually deliver", "wishlist integration" |
| **P5** | **Behavioral advertising, data brokerage, or child data used for model training.** | Not a close call under the amended COPPA Rule (§10.1), and it permanently forecloses the institutional market (§14). | "free tier monetization", "anonymized insights", "improving the product with usage data" |
| **P6** | **Any financial or expense surface visible to a child role.** No totals, no summaries, no notifications, no "Dad paid for this." | Principle §2.1. Enforced at the RLS layer (§5.11), not by UI convention. | "teach financial literacy", "let her see what things cost", "gratitude prompts" |
| **P7** | **Parent access to the child's private journal (§5.12) at any tier, including guardian escalation and court order response.** | The graduated-privacy contract (§2.9) is worthless if it has an override. A teen who learns the override exists stops using the product. | "safety review", "wellbeing monitoring", "just for at-risk kids", "self-harm detection" |
| **P8** | **Deletion or editing of parent↔parent log entries.** | Court-tier integrity (§12 Phase 3). A log with an unsend button is not evidence. | "let me unsend", "I typed that in anger", "GDPR-style erasure" |
| **P9** | **Unsolicited resurfacing of pre-separation archive material.** "On this day" is opt-in with per-era mute (§9.8.3). | A memory from before a split can wound without warning, and the product chose the moment. | "delightful memories", "engagement through nostalgia" |
| **P10** | **No appearance modification on a child's video.** No beauty filters, no smoothing, no slimming, no eye enlargement, no "touch-up" — not as a default, not as an option, not as a sticker that happens to reshape a face. Silly effects (dog ears, googly eyes) are fine. |
| **P11** | **No remote control of a child's device, including for the child's benefit.** No input injection, no remote navigation, no screen takeover, by any party at any tier. The come-back signal (§5.27) is the sanctioned alternative: he requests, she acts. |

**P7 carveat, stated explicitly so it is not mistaken for an oversight.** If a
child is in danger, the correct response is a human — a guardian, a counselor, a
crisis line surfaced *to the child* — not a parent-facing readout of their private
writing. Build the escalation path; do not build the window.

---

## §3 System architecture

### 3.1 The core bet: one session runtime, many activity modules

Video calling, games, and homework are **not** separate features. They are
activity modules riding one synchronized session runtime.

```
                      ┌───────────────────────────┐
                      │     SESSION RUNTIME       │
                      ├───────────────────────────┤
   media tracks ────► │  Media layer   (LiveKit)  │
   state events ────► │  State layer   (authoritative + event log)
   presence     ────► │  Presence layer(focus, cursor, reachability)
                      ├───────────────────────────┤
                      │  ACTIVITY MODULES         │
                      │  ├─ homework              │
                      │  ├─ game (turn-based)     │
                      │  ├─ game (realtime co-op) │
                      │  ├─ canvas                │
                      │  ├─ storybook             │
                      │  ├─ co-listen   (§9.10)   │
                      │  ├─ cook-along  (§9.10)   │
                      │  ├─ watch-together (§9.10)│
                      │  ├─ teach-me    (§9.9.3)  │
                      │  └─ calendar-review       │
                      └───────────────────────────┘
```

Consequences:

- A new activity is a module, not a rearchitecture.
- The child gets one mental model and one UI shell for every shared activity.
- Session recording, moderation, logging, captioning, and retention are
  implemented **once**.
- A module can run **synchronously** (both present) or **asynchronously** (state
  advances, other party receives a delivery intent). Same code path.

### 3.2 Service map

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Flutter      │  │ Flutter      │  │ Flutter      │  │  SMS bridge  │
│ Android      │  │ Windows      │  │ iOS (Ph.4)   │  │   (§8.4)     │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       └─────────────────┼─────────────────┼─────────────────┘
                         │  HTTPS / WSS
                ┌────────▼─────────┐
                │   API Gateway    │  auth, rate limit, RLS context
                └────────┬─────────┘
   ┌──────────┬──────────┼─────────┬──────────┬──────────┬──────────┐
   ▼          ▼          ▼         ▼          ▼          ▼          ▼
┌────────┐┌────────┐┌────────┐┌────────┐┌─────────┐┌────────┐┌──────────┐
│identity││family  ││ time   ││session ││delivery ││archive ││compliance│
│ + auth ││ graph  ││ engine ││runtime ││ engine  ││ §9.8   ││ + audit  │
└───┬────┘└───┬────┘└───┬────┘└───┬────┘└────┬────┘└───┬────┘└────┬─────┘
    └─────────┴─────────┴─────────┴──────────┴─────────┴──────────┘
                         │
     ┌───────────────────┼────────────────────┐
     ▼                   ▼                    ▼
┌──────────┐      ┌────────────┐       ┌─────────────┐
│PostgreSQL│      │   Redis    │       │ S3-compat   │
│  (RLS)   │      │ presence,  │       │ media, short│
│          │      │ queues     │       │ TTL signed  │
└──────────┘      └────────────┘       └─────────────┘
```

**`time-engine` is a first-class service, not a utility library.** See §4.
**`archive` is a first-class service**, because retention decisions cannot be an
afterthought bolted onto storage. See §9.8.

---

## §4 Temporal architecture

The defining subsystem. Reference case throughout: **parent in Texas
(`America/Chicago`), child in North Carolina (`America/New_York`).**

### 4.1 Doctrine — four frames, never conflated

| Frame | Owner | Governs |
|---|---|---|
| **Child-local** | child's residence at that instant | all delivery, day-parts, streaks, medication slots, "sleeps until" |
| **Actor-local** | each parent / trusted adult | their own quiet hours, their compose UI |
| **Order-time** | the custody decree | exchange times, holiday windows — legally binding |
| **Instant (UTC)** | system | storage, ordering, audit |

Conflating child-local with order-time is the failure that ends up in front of a
judge. Conflating actor-local with child-local is the failure that wakes a
sleeping seven-year-old — or double-doses a medication.

**The child's local time is canonical. Everything else is a rendering.**

Rationale: the child's day has fixed structure — school bell, bus, dinner, bath,
bedtime. The parent's schedule flexes around it. Closeness comes not from knowing
*what time it is there* but from knowing *what your kid is doing right now*.

### 4.2 Timezone is a timeline, not a column

A child is in NC during the school year and in TX for six weeks each summer. That
is the product, not an edge case.

Resolution order for "what zone is the child in at instant T":

1. `child_tz_interval` covering T, highest confidence
2. derived from custody schedule + household address
3. `child.home_tz` fallback

The zone changes **at the custody exchange event** (`exchange.tz_flips_here`),
not at midnight.

### 4.3 Day-parts — the semantic layer

Features address time by **meaning**, not by clock:

`wake · before_school · school · after_school · activity · dinner ·
wind_down · bedtime · asleep · free`

Each carries a `reachable` boolean. Day-parts are per-child, per-household
(Dad's bedtime may be 8:30, Mom's 9:00), and per-season (`effective` daterange
splits school year from summer).

Stored as **wall-clock `time`, never `timestamptz`**. Bedtime is 8:30 PM
regardless of DST. This is the entire point.

Day-parts are consumed by: delivery (§4.4), the notification gate (§6.4),
medication slots (§9.6.1), turn clocks (§4.7), rituals (§9.9.4), and the
visual schedule strip for neurodivergent users (§8.4).

### 4.4 Delivery policies

An intent carries a **policy**, not a timestamp.

| Policy | Semantics | Example |
|---|---|---|
| `immediate` | next child app-open | reaction to a drawing |
| `at_instant` | exact UTC moment | scheduled call reminder |
| `at_daypart` | resolve to child-local day-part | goodnight video → `bedtime` |
| `on_local_date` | fires on **her** date, in the zone she'll be in then | time capsule, banked message |
| `when_reachable` | next window where child is free and has device | game turn nudge, child ping |
| `on_event` | anchored to a calendar entity | "first day of school" |

### 4.5 Materialization and invalidation

`scheduled_at` is a **cache**. It goes stale. Rematerialize on:

```
child_tz_interval.changed    travel, move, summer custody block
day_part.changed             new bedtime; school year → summer
custody_schedule.changed     exchange time moved
calendar_event.moved         anchored intents shift
dst.transition               nightly sweep; real effect 2×/yr
```

Skipping rematerialization is the single largest source of *"why did Dad's
goodnight video arrive at 3 a.m."* — and with message banking (§9.5) a single
stale batch can mis-deliver 180 nights in a row.

Cadence: event-driven invalidation **plus** a nightly sweep as the safety net.

### 4.6 US temporal edge cases — mandatory golden tests

| Case | Example | Rule |
|---|---|---|
| Both zones observe DST | Chicago ↔ New York | Constant 1 h gap. Easy case — still never hardcode. |
| One zone opts out | Chicago ↔ Phoenix | Gap is **1 h Nov–Mar, 2 h Mar–Nov**. Compute per-instant. |
| Never-DST jurisdictions | `Pacific/Honolulu`, `America/Puerto_Rico`, `Pacific/Guam`, `Pacific/Pago_Pago` | No transitions at all |
| **States split across zones** | Texas is Central *except* El Paso & Hudspeth (Mountain). Also FL, TN, KY, IN, KS, NE, ND, SD, OR, ID, MI, AK | **Never infer zone from state.** Resolve IANA id from precise address or device. |
| DST islands | Navajo Nation observes DST; Hopi Reservation inside it does not | County-level geocoding fails |
| Deployed parent | Ramstein, shipboard | US-centric market ≠ US-only *actors*. Don't constrain actor zone set. |
| Spring forward | 2:30 a.m., 2nd Sun in March | Nonexistent — shift forward, log |
| Fall back | 1:30 a.m., 1st Sun in Nov | Ambiguous — take first, log |
| Exchange day | Child flies TX→NC Friday | Zone flips at the exchange event |
| **Banked batch across a transition** | 180-night batch spanning Nov 1 | Every intent rematerializes; none drift |

**Required test fixtures:** March 8 2026 spring-forward · November 1 2026
fall-back · Chicago↔Phoenix pair straddling both · El Paso family ·
summer TX↔NC handoff · 180-night banked batch spanning both transitions.

### 4.7 Feature-level time semantics

| Feature | Semantics |
|---|---|
| Goodnight video | `at_daypart('bedtime')` — 8:30 p.m. *her* time, DST-proof, travel-proof |
| **Banked batch** | one `on_local_date` intent per child-local date; rematerializes as a set |
| Turn-based games | Turn clocks tick in **reachable hours**, not wall hours |
| Turn nudges | Delivered at her next `after_school`, never at 2 a.m. |
| **Medication slots** | Keyed to child-local date + slot. Dedupe guard is a DB constraint. |
| Homework | Due dates on child-local school calendar |
| Time capsules | `on_local_date`, resolved against the zone she'll be in *then* |
| Streaks / gap coverage | Computed on **child-local calendar days**, internal only (P2) |
| Call scheduling | Overlap finder across both day-part sets |
| **Child ping** | `when_reachable` against the *recipient*. Never an override. |

### 4.8 Delivery guards

Constants and rules that exist because their absence is a specific failure.

| Guard | Value | Prevents |
|---|---|---|
| `PAST_GRACE_MINUTES` | 120 | A recovered outage retroactively delivering a week of goodnight videos at once. Inside the window a late message still goes out; beyond it the intent expires. |
| `at_daypart` rolls forward | — | "Next bedtime" is an open promise and may move. |
| `on_local_date` expires | — | "The night of June 1st" is a specific promise and may **not** move. Delivering night 41 alongside night 60 is worse than not delivering it. |
| `MAX_DEFERS` | 3 | A gate deferring indefinitely. Fails **open** and logs — silence is worse than imperfect timing. |
| Claim uses `FOR UPDATE SKIP LOCKED` + compare-and-swap | — | Concurrent workers double-delivering. |
| Invalidation scoped to `state IN ('pending','ready')` **and** future `scheduled_at` | — | A delivered message being retroactively re-timed. It belongs to the child. |
| Invalidation triggers are **statement-level** with transition tables | — | O(rows) redundant queue rewrites on bulk day-part or timezone imports. |

---

## §5 Data model

Postgres 16+. Row-level security scopes every query to the family graph.

### 5.1 Family graph — child as root

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE app_user (
  id            uuid PRIMARY KEY,
  email         citext UNIQUE,           -- NULL for child profiles
  display_name  text NOT NULL,
  home_tz       text NOT NULL,
  channel       text NOT NULL DEFAULT 'app'
                CHECK (channel IN ('app','sms')),   -- §8.4 SMS bridge
  phone_e164    text,                    -- required when channel = 'sms'
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE child (
  id            uuid PRIMARY KEY,
  display_name  text NOT NULL,
  birth_date    date NOT NULL,
  home_tz       text NOT NULL,           -- IANA; fallback only, never the answer
  privacy_tier  text NOT NULL DEFAULT 'transparent'
                CHECK (privacy_tier IN ('transparent','graduated','autonomous')),
  majority_age  smallint NOT NULL DEFAULT 18,   -- state of residence governs
  handed_over_at timestamptz              -- §9.8.4; NULL until majority transfer
);

CREATE TABLE household (
  id           uuid PRIMARY KEY,
  label        text NOT NULL,            -- "Dad's house"
  tz           text NOT NULL,
  postal_code  text
);

-- Guardianship is an EDGE with scope, dates, and court reference.
CREATE TABLE guardianship (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role         text NOT NULL CHECK (role IN
                 ('guardian','trusted_adult','step_parent','sitter','coordinator',
                  'foster_parent','caseworker','therapist')),
  scope        jsonb NOT NULL,           -- {calls:true, homework:true, settings:false}
  restricted   boolean NOT NULL DEFAULT false,   -- protective order
  order_ref    text,                     -- court order citation
  valid        tstzrange NOT NULL,
  expires_at   timestamptz,              -- time-boxed sitter tokens
  -- Edges CLOSE, they do not delete. A deceased or removed parent's history
  -- must survive the end of their access. See §18.
  closed_at    timestamptz,
  closed_reason text CHECK (closed_reason IN
                 ('death','court_order','revoked','expired','majority')),
  UNIQUE (child_id, user_id)
);
-- `supervised boolean` REMOVED in v0.4.0. A boolean cannot express reunification.
-- Superseded by contact_ladder (§5.15).
```

> Modelling `account → family → children` breaks the instant parents separate,
> remarry, or a protective order lands. The child is the root. Guardianship is
> the edge. `coordinator` covers court-appointed parenting coordinators and
> guardians ad litem — read access to the log, no write access to the child's
> experience.

### 5.2 Temporal tables

```sql
CREATE TABLE child_tz_interval (
  id         uuid PRIMARY KEY,
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  tz         text NOT NULL,                      -- 'America/New_York'
  valid      tstzrange NOT NULL,                 -- [start, end)
  source     text NOT NULL CHECK (source IN ('custody','manual','device','travel')),
  confidence smallint NOT NULL DEFAULT 100,
  EXCLUDE USING gist (child_id WITH =, valid WITH &&)   -- overlaps are a data bug
);

CREATE TABLE day_part (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  household_id  uuid REFERENCES household(id),   -- NULL = both homes
  kind          text NOT NULL,
  starts_local  time NOT NULL,                   -- WALL CLOCK. Deliberate.
  ends_local    time NOT NULL,
  days_of_week  smallint[] NOT NULL,             -- 0 = Sunday
  reachable     boolean NOT NULL,
  effective     daterange NOT NULL               -- school year vs summer
);
```

### 5.3 Async delivery engine

```sql
CREATE TYPE delivery_policy AS ENUM (
  'immediate','at_instant','at_daypart','on_local_date','when_reachable','on_event'
);

CREATE TABLE delivery_intent (
  id                uuid PRIMARY KEY,
  child_id          uuid NOT NULL REFERENCES child(id),
  sender_id         uuid NOT NULL REFERENCES app_user(id),
  payload_kind      text NOT NULL,   -- video_msg|game_turn|capsule|nudge|homework_note
  payload_ref       uuid NOT NULL,
  policy            delivery_policy NOT NULL,

  target_instant    timestamptz,     -- only the relevant arg is populated
  target_daypart    text,
  target_local_date date,
  target_event_id   uuid,

  batch_id          uuid REFERENCES intent_batch(id) ON DELETE CASCADE,  -- §9.5
  batch_seq         integer,

  scheduled_at      timestamptz,     -- MATERIALIZED cache. Recomputed, never trusted.
  materialized_tz   text,            -- which zone produced it (audit trail)
  materialized_at   timestamptz,
  state             text NOT NULL DEFAULT 'pending'
                    CHECK (state IN ('pending','ready','delivered','opened','expired','revoked')),
  expires_at        timestamptz NOT NULL,        -- COPPA §10.1. Non-nullable on purpose.
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ON delivery_intent (scheduled_at) WHERE state = 'pending';
CREATE INDEX ON delivery_intent (child_id, state);
CREATE INDEX ON delivery_intent (batch_id) WHERE batch_id IS NOT NULL;
```

### 5.4 Custody and calendar

```sql
CREATE TABLE custody_order (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id),
  order_tz     text NOT NULL,   -- "Friday 6:00 PM" is meaningless without this.
                                -- Default: child's primary-residence zone at entry.
                                -- NEVER default to the server zone.
  pattern      text NOT NULL,   -- '2-2-3'|'2-2-5-5'|'alternating_weeks'|'custom'
  rrule        text,
  holiday_rules jsonb NOT NULL DEFAULT '[]',
  cost_split   jsonb NOT NULL DEFAULT '{}'   -- drives §5.11 split_rule
);

CREATE TABLE calendar_event (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id),
  kind          text NOT NULL,  -- birthday|school|medical|activity|exchange|holiday
  title         text NOT NULL,
  starts_local  timestamp NOT NULL,  -- wall clock, no offset
  ends_local    timestamp,
  tz            text NOT NULL,       -- resolved zone at creation
  rrule         text,                -- recurring: wall clock + tz + rule, never UTC
  visible_to_child boolean NOT NULL DEFAULT true
);
```

> **Real implementation, v0.46.3.** `custody_order` above is the original spec
> shape; `db/migrations/0007_custody_order.sql`'s real table diverges from it
> deliberately (drops the unimplemented `'custom'` pattern, adds
> `anchor_local_date`/`exchange_time`/`effective_from`/`effective_to` — see
> that migration's own header for why) and is what `packages/custody/src/
> schedule.ts`'s tested `Order`/`HolidayRule` types and `activeCustodyOrderFor()`
> actually consume. As of v0.46.3 that real order is exposed end to end: `GET
> /v1/children/:childId/custody-order` (`server/routes.mjs`) returns it as
> JSON, and `client/lib/family_agreement_screen.dart` renders it read-only —
> pattern in plain words, order timezone, exchange time, anchor date, holiday
> rules — reachable from `guardian_more.dart`'s "Guardian setup" tile. No
> editing surface exists anywhere; a `custody_order` row is written by a
> future intake flow, not by this screen. `calendar_event` above remains
> unimplemented — no route or table exists for it yet.
>
> **v0.49.15 dead-wire fix.** Each holiday rule's real `priority` field
> (parsed off the wire since v0.46.3) was never read anywhere — the actual
> tie-break `schedule.ts`'s own `holidayOn()` uses when two rules overlap.
> `family_agreement_screen.dart` now sorts the holiday list the same way the
> engine does and states each rule's priority number, instead of rendering
> in raw wire order.

> **Recurrence rule.** Recurring events store **local wall clock + IANA zone +
> RRULE**, materialized to instants at query time. Storing a recurring event as
> a UTC instant guarantees a one-hour drift twice a year.

### 5.5 Wants / needs

```sql
CREATE TABLE child_list_item (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id),
  kind         text NOT NULL CHECK (kind IN ('want','need')),  -- strictly separate
  title        text NOT NULL,
  note         text,
  -- Needs route to action. Wants carry NO price and NO buy action. See P4.
  claimed_by   uuid REFERENCES app_user(id),
  claimed_at   timestamptz,
  fulfilled_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
```

> `claimed_by` is **never surfaced to the child**. The child sees "handled" or
> "on the list." Which parent claimed, declined, or ignored an item is invisible
> to them. Principle §2.1.

### 5.6 Media artifacts and the archive

```sql
CREATE TABLE media_artifact (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  author_id     uuid REFERENCES app_user(id),
  kind          text NOT NULL,  -- video_msg|voice_note|drawing|homework|photo|call_clip
  storage_key   text NOT NULL,
  duration_ms   integer,
  caption_key   text,                   -- transcript/caption sidecar, §8.4
  captured_at   timestamptz NOT NULL,
  captured_tz   text NOT NULL,          -- child's zone at capture — for the Year Book
  era_tag       text,                   -- e.g. 'pre-2024-separation'; drives P9 mute

  -- ARCHIVE TIER. This column must exist from Phase 0 even though the
  -- Year Book (§9.8.2) ships in Phase 3/4. Without it, Phase 0 retention
  -- deletes the material the archive would have been built from.
  preserved     boolean NOT NULL DEFAULT false,
  preserved_by  uuid REFERENCES app_user(id),
  preserved_at  timestamptz,

  expires_at    timestamptz,
  CONSTRAINT retention_or_preserved
    CHECK (preserved = true OR expires_at IS NOT NULL)
);

CREATE INDEX ON media_artifact (child_id, captured_at);
CREATE INDEX ON media_artifact (expires_at) WHERE preserved = false;
```

> The `CHECK` is the whole archive design in one line: an artifact is either on a
> retention clock or explicitly preserved by a named guardian. There is no third
> state, and "indefinite by accident" is unrepresentable.

### 5.7 Message banking

```sql
CREATE TABLE intent_batch (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  sender_id    uuid NOT NULL REFERENCES app_user(id),
  label        text NOT NULL,        -- "Deployment — Mar to Sep"
  reason       text CHECK (reason IN
                 ('deployment','medical','treatment','travel','custody_gap','other')),
  cadence      text NOT NULL CHECK (cadence IN ('daily','weekdays','weekly','custom')),
  daypart      text NOT NULL DEFAULT 'bedtime',
  starts_local date NOT NULL,
  ends_local   date NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
```

### 5.8 Medication — the double-dose guard

```sql
CREATE TABLE medication (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  name         text NOT NULL,
  dose         text NOT NULL,
  slots        text[] NOT NULL,       -- day_part kinds: {'wake','after_school'}
  prn          boolean NOT NULL DEFAULT false,   -- as-needed
  notes        text,
  active       boolean NOT NULL DEFAULT true
);

CREATE TABLE medication_event (
  id              uuid PRIMARY KEY,
  medication_id   uuid NOT NULL REFERENCES medication(id) ON DELETE CASCADE,
  slot            text NOT NULL,
  local_date      date NOT NULL,      -- CHILD-local. Not server, not actor.
  local_tz        text NOT NULL,
  administered_at timestamptz NOT NULL,
  by_user         uuid NOT NULL REFERENCES app_user(id),
  household_id    uuid REFERENCES household(id),
  status          text NOT NULL CHECK (status IN ('given','skipped','refused','missed')),
  note            text,
  -- THE POINT OF THIS TABLE. One dose per med, per slot, per child-local day,
  -- across BOTH households. Prevents the exchange-day double-dose.
  UNIQUE (medication_id, local_date, slot)
);
```

> A parent in Texas administering an 8 a.m. dose and a parent in North Carolina
> administering "the morning dose" are the same slot on the same child-local day.
> Keyed on server time or actor time, this constraint silently fails to fire.

### 5.9 Medical record and emergency card

```sql
CREATE TABLE emergency_card (
  child_id      uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  blood_type    text,
  allergies     jsonb NOT NULL DEFAULT '[]',
  conditions    jsonb NOT NULL DEFAULT '[]',
  meds_summary  jsonb NOT NULL DEFAULT '[]',   -- denormalized from §5.8
  providers     jsonb NOT NULL DEFAULT '[]',   -- pediatrician, dentist, specialist
  insurance     jsonb,                          -- carrier, member id, card image key
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE school_record (
  id           uuid PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  school_name  text NOT NULL,
  grade        text,
  contacts     jsonb NOT NULL DEFAULT '[]',
  doc_keys     text[] NOT NULL DEFAULT '{}',   -- IEP / 504, guardian-uploaded only
  updated_at   timestamptz NOT NULL DEFAULT now()
);
```

> `school_record.doc_keys` holds **guardian-uploaded** documents only. Ingesting
> from a school portal would pull the product into FERPA scope. See §10.6.

### 5.10 The exchange

```sql
CREATE TABLE exchange (
  id                uuid PRIMARY KEY,
  child_id          uuid NOT NULL REFERENCES child(id),
  from_household    uuid REFERENCES household(id),
  to_household      uuid REFERENCES household(id),
  scheduled_at      timestamptz NOT NULL,
  order_tz          text NOT NULL,        -- rendered verbatim; see §5.4
  tz_flips_here     boolean NOT NULL DEFAULT false,  -- drives child_tz_interval
  -- Arrival is an EVENT, never a coordinate. Prohibition P3.
  arrived_at        timestamptz,
  delay_minutes     integer,
  delay_notified_at timestamptz
);

CREATE TABLE bag_item (
  id           uuid PRIMARY KEY,
  exchange_id  uuid NOT NULL REFERENCES exchange(id) ON DELETE CASCADE,
  label        text NOT NULL,
  essential    boolean NOT NULL DEFAULT false,   -- retainer, inhaler, glasses
  sent         boolean NOT NULL DEFAULT false,
  returned     boolean NOT NULL DEFAULT false
);
```

> There is no `latitude`, `longitude`, `accuracy`, or `geohash` column here, and
> there must never be one. A geofence may *fire* an arrival event on-device; the
> coordinates never leave it.

### 5.11 Expenses — Phase 3, court tier

```sql
CREATE TABLE expense (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id),
  paid_by       uuid NOT NULL REFERENCES app_user(id),
  amount_cents  bigint NOT NULL,
  category      text NOT NULL,   -- medical|school|activity|clothing|childcare|other
  incurred_on   date NOT NULL,
  receipt_key   text,
  split_rule    jsonb NOT NULL,  -- derived from custody_order.cost_split
  status        text NOT NULL DEFAULT 'proposed'
                CHECK (status IN ('proposed','accepted','disputed','reimbursed')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- PROHIBITION P6, ENFORCED. No SELECT policy exists for the child role.
-- Do not add one. This is not a UI concern.
ALTER TABLE expense ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense FORCE  ROW LEVEL SECURITY;   -- see P7 note; same failure mode
CREATE POLICY expense_guardians_only ON expense
  FOR ALL USING (current_setting('app.role') IN ('guardian','coordinator'));
```

### 5.12 Child agency

```sql
CREATE TABLE child_ping (
  id          uuid PRIMARY KEY,
  child_id    uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  to_user     uuid NOT NULL REFERENCES app_user(id),
  local_date  date NOT NULL,          -- child-local; rate-limit key
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON child_ping (child_id, to_user, local_date);

CREATE TABLE child_journal_entry (
  id          uuid PRIMARY KEY,
  child_id    uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  body        text,
  media_ref   uuid REFERENCES media_artifact(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- PROHIBITION P7, ENFORCED. The owning child is the only readable role.
-- There is deliberately no guardian policy, no escalation policy, and no
-- admin policy. Adding one requires a CHANGELOG entry per §0.
ALTER TABLE child_journal_entry ENABLE ROW LEVEL SECURITY;
-- CRITICAL, added v0.4.1. ENABLE alone is NOT sufficient: the table OWNER
-- bypasses RLS by default, and applications overwhelmingly connect as the
-- owner of their own schema. Without FORCE this policy is decorative.
-- Measured: owner reads 1 journal row without FORCE, 0 with it.
-- FORCE does not stop SUPERUSER or BYPASSRLS roles — the application role
-- must be neither. See scaffold/db/DEPLOYMENT.md.
ALTER TABLE child_journal_entry FORCE ROW LEVEL SECURITY;
CREATE POLICY journal_owner_only ON child_journal_entry
  FOR ALL USING (
    current_setting('app.role', true) = 'child'
    AND child_id = current_setting('app.child_id', true)::uuid
  );
```

### 5.13 Rituals

```sql
CREATE TABLE ritual (
  id            uuid PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  with_user     uuid NOT NULL REFERENCES app_user(id),
  label         text NOT NULL,        -- "Sunday pancakes call"
  activity_kind text,                 -- session module to auto-attach
  daypart       text NOT NULL,
  days_of_week  smallint[] NOT NULL,
  active        boolean NOT NULL DEFAULT true
);
```

> Rituals are **never scored, counted, or streaked to the child.** Prohibition P2.
> A missed pancake call produces no badge, no notification to the child, and no
> visible break in anything.

### 5.14 Siblings

Prior to v0.4.0, two children of the same parents were **two disconnected trees**
with duplicated guardianship edges and no relation between them. That broke group
calls, one-on-one time protection, shared exchanges, and — most seriously —
sibling contact when children are split across households or placements.

```sql
-- Relationship, not parentage. Half-siblings and foster siblings are siblings.
CREATE TABLE sibling_link (
  child_a          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  child_b          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  kind             text NOT NULL CHECK (kind IN ('full','half','step','foster','kin')),
  -- Sibling separation is a recognised crisis in placement. Contact between
  -- siblings is a right that survives the separation of their guardians.
  contact_allowed  boolean NOT NULL DEFAULT true,
  travels_together boolean NOT NULL DEFAULT true,   -- shared exchange cohort
  PRIMARY KEY (child_a, child_b),
  CHECK (child_a < child_b)                          -- canonical ordering, no dupes
);

-- Sibling exchanges share one manifest event.
ALTER TABLE exchange ADD COLUMN cohort_id uuid;
CREATE INDEX ON exchange (cohort_id) WHERE cohort_id IS NOT NULL;
```

**One-on-one protection.** A session may be scoped to a single child even within a
sibling group. "Dad gets twenty minutes with each, separately" is a first-class
scheduling concept, not a workaround — it is frequently the thing a therapist or
court has specifically ordered.

### 5.15 The contact ladder

`supervised boolean` is deleted. Reunification after estrangement, incarceration,
or treatment is a graduated clinical process with real practitioners, and a
boolean cannot express any of it.

```sql
CREATE TABLE contact_ladder (
  id              uuid PRIMARY KEY,
  guardianship_id uuid NOT NULL REFERENCES guardianship(id) ON DELETE CASCADE,
  step            text NOT NULL CHECK (step IN
                    ('none','supervised','monitored','time_limited','open')),
  -- Only a coordinator, therapist, or caseworker may advance a step.
  -- A guardian may always request a HOLD or a step DOWN on their own child.
  advanced_by     uuid REFERENCES app_user(id),
  effective       tstzrange NOT NULL,
  order_ref       text,
  notes           text,
  EXCLUDE USING gist (guardianship_id WITH =, effective WITH &&)
);
```

| Step | Means |
|---|---|
| `none` | No contact. Edge exists for history and future advancement. |
| `supervised` | Sessions recorded and reviewable by the advancing professional |
| `monitored` | Not recorded; professional sees metadata and can join unannounced |
| `time_limited` | Open content, capped duration and frequency |
| `open` | Full guardian scope |

Advancement is never automatic and never time-based. A professional acts, or the
step holds.

### 5.16 Succession

```sql
-- Recorded by the parent, about themselves, while living. Nobody else may
-- create, alter, or override this record — not the other guardian, not a
-- court, not support staff. See §18.
CREATE TABLE succession_directive (
  id              uuid PRIMARY KEY,
  user_id         uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  child_id        uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  banked_on_death text NOT NULL CHECK (banked_on_death IN
                    ('continue','stop','deliver_all')),
  successor_id    uuid REFERENCES app_user(id),   -- custodian until majority
  message         text,                            -- read to the child on transfer
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, child_id)
);
```

### 5.17 Authorization model

`can(action, edges, childId, now, actorRole, tier)` — pure, over resolved edges.
The database enforces P6/P7 independently (§5.11, §5.12); this is the second
lock, not the only one.

**Deny order matters.** P7 is evaluated **first, unconditionally, before edge
resolution** — so the answer never depends on the graph and no construction of
arguments returns allow for `journal.read`. P6 is second.

Four independent ways an edge stops granting access, each a real bug in
someone's system:

| Condition | Cause |
|---|---|
| `closed_at` | parent died, order changed, access revoked (§18.1) |
| `expires_at` | sitter token lapsed |
| `valid` range | order not yet in force, or already ended |
| `restricted` | protective order |

Then: ladder step `none` blocks **contact** but not a coordinator's read;
`observer_only` blocks **writes** but not reads (§17.3); role capability;
explicit `scope[action] === false`.

**`actor_has_edge()` deliberately does not traverse `sibling_link`.** Being
guardian of one sibling must never confer access to another — that traversal is
the obvious lateral privilege-escalation path in a family graph, and it is
tested for explicitly in both the pure and the database suite.

### 5.18 Session context

The GUCs `app.role`, `app.child_id`, `app.user_id` are written in exactly one
place: `withSession()`. A second writer turns P6 and P7 into
parameter-tampering bugs.

- `set_config(..., is_local => true)` — transaction-scoped, unwinds on COMMIT
  **and** ROLLBACK. Plain `SET` persists on a pooled connection, so the next
  request inherits the previous request's child context: a cross-tenant read
  with no code path that looks wrong.
- Bound parameters, never interpolation — the security context is the last place
  to accept string concatenation.
- Context originates from a verified principal. A `child` role with no
  `childId`, or a guardian with no `userId`, throws rather than matching nothing.
- Accessors are wrapped: `current_child()` uses
  `NULLIF(current_setting(...,true),'')::uuid`. The bare cast **raises** on an
  empty string, which a pool that sets both GUCs unconditionally will produce —
  turning fail-closed into fail-crash. See v0.6.0 findings.
- `withSystemSession()` for the sweep: role `system`, no child context.

### 5.19 Session runtime — token invariants

Five invariants, each one a real breach if dropped. Verified against the actual
`livekit-server-sdk` claim payload, not against our intermediate objects.

| # | Invariant | Breach it prevents |
|---|---|---|
| **I1** | Room names are 24 random bytes, asserted at creation not to contain any identifier | Room enumeration. `child:<uuid>` is guessable by anyone holding a child id, and child ids appear in every API path. |
| **I2** | `roomJoin` for exactly one room. Never `roomAdmin`, `roomCreate`, `roomList`, `roomRecord`, `ingressAdmin`, `recorder`, `agent`. `canUpdateOwnMetadata: false`. | A call token doubling as an admin credential, or a child renaming themselves in the room. |
| **I3** | `identity` is the authenticated principal | Impersonation via a client-supplied identity. |
| **I4** | `can('call', …)` re-runs at **mint** time; participant-list membership is checked **second** | A revoked, deceased, restricted, or expired edge riding a stale participant list. Membership is not authorization. |
| **I5** | TTL is 600 seconds | Bounds **new joins** only. **Measured against livekit-server 1.8.0: the server accepts a token ~60s past its `exp`** (200 at 60s, 401 at 95s), so expiry is not a revocation mechanism. §8.3 evicts via `removeParticipant`; TTL alone would leave a defeated kiosk connected. |

**§17.3 refinement.** An observer-only guardian receives `canPublish: false` and
`canPublishData: false` — subscribe only. The tier promises *watching without
obligation*; a parent whose camera and microphone are live in the room is
participating. This was a gap in the v0.4.0 wording, closed here.

**§5.15 → recording mapping.** `supervised` sessions are recorded and reviewable
by the professional who advanced the step. `monitored` is **not** recorded — they
may join unannounced instead. `open` and `time_limited` are never recorded.
`none` cannot create a session at all.

**§10.5 tension, resolved.** Recording is off by default and a child cannot
consent — yet a court-ordered supervised visit *is* recorded. Resolution: such
recording is lawful under the order, is disclosed to every participant including
the child in age-appropriate language, and is never silent. The child-facing
string is fixed in code, not left to a template.

### 5.20 Child lock — defeat is expected, not exceptional

The platform primitives are unreliable by design:

| Platform | Mechanism | Escapable by the child? |
|---|---|---|
| Android | `startLockTask()` PINNED | **Yes** — Back + Recents |
| Android | LOCK_TASK_MODE_LOCKED (device-owner) | No, but requires provisioning |
| Windows | Assigned Access | **Yes** — Ctrl+Alt+Del |
| iOS | Guided Access | Yes, if the child knows the device passcode |

Most installs will be escapable. So the design question is not how to prevent
defeat but **what is on screen one frame after it happens.**

On lock-task exit or backgrounding, in this order:

1. **Drop escalation, unconditionally.** The real failure mode is not a child
   seeing a menu — it is a parent who escalated, handed the device back, and had
   the kiosk defeated with guardian scope still live.
2. **Revoke session tokens server-side.** The app losing focus does not
   invalidate a JWT.
3. **Land on the PIN gate** — never the guardian surface, never mid-session.

A defeat while escalated, or a third defeat, notifies the **other** guardian —
not the one holding the device. An escapable mode is disclosed at setup rather
than hidden.

---

## §6 Reference implementation — time engine

TypeScript. **Luxon** today; migrate to `Temporal` when all runtime targets ship
it. Never hand-roll offset math. Never store offsets.

### 6.1 Zone resolution

```ts
import { DateTime } from 'luxon';

/** The child's zone is a lookup against the timeline, not a field read. */
export async function childZoneAt(childId: string, at: DateTime): Promise<string> {
  const row = await db.oneOrNone(`
    SELECT tz FROM child_tz_interval
     WHERE child_id = $1 AND valid @> $2::timestamptz
     ORDER BY confidence DESC
     LIMIT 1`, [childId, at.toJSDate()]);
  return row?.tz ?? (await db.one(
    'SELECT home_tz FROM child WHERE id = $1', [childId])).home_tz;
}
```

### 6.2 Wall-clock resolution — DST pathologies handled explicitly

```ts
type Ambiguity = 'first' | 'last';

/**
 * Resolve a wall-clock local time to an absolute instant.
 *
 *  - Spring forward (2nd Sun in March): 2:30 AM does not exist.
 *  - Fall back (1st Sun in Nov): 1:30 AM exists twice.
 *
 * Both are silent-corruption bugs if the library chooses for you.
 */
export function resolveWallClock(
  localDate: string,          // 'YYYY-MM-DD'
  localTime: string,          // 'HH:mm'
  zone: string,
  onAmbiguous: Ambiguity = 'first'
): DateTime {
  const dt = DateTime.fromISO(`${localDate}T${localTime}`, { zone });
  if (!dt.isValid) throw new Error('unparsable local time');

  // CORRECTED in v0.4.0. Luxon does NOT invalidate a nonexistent local time —
  // it silently maps it forward across the gap. Checking `isValid` here means
  // the anomaly is never detected and never logged, which is precisely the
  // "library chooses for you" failure this function exists to prevent.
  // Round-trip instead: if the resulting instant does not reproduce the wall
  // clock we asked for, the requested time did not exist.
  if (dt.toFormat('HH:mm') !== localTime) {
    return { instant: dt, anomaly: 'nonexistent' };
  }

  // During the repeated hour, adding 1h to the instant leaves wall clock
  // unchanged (the offset absorbs it). Reliable ambiguity test.
  const later = dt.plus({ hours: 1 });
  const isAmbiguous =
    later.toFormat('yyyy-MM-dd HH:mm') === dt.toFormat('yyyy-MM-dd HH:mm');

  return isAmbiguous && onAmbiguous === 'last' ? later : dt;
}
```

### 6.3 Materializer

```ts
export async function materialize(i: DeliveryIntent): Promise<Materialized> {
  const now = DateTime.utc();

  switch (i.policy) {
    case 'at_instant':
      return { scheduledAt: i.targetInstant!, tz: 'UTC' };

    case 'at_daypart': {
      const zone = await childZoneAt(i.childId, now);
      const date = i.targetLocalDate ?? now.setZone(zone).toISODate()!;
      const part = await lookupDayPart(i.childId, i.targetDaypart!, date);
      if (!part) return { scheduledAt: null, tz: zone, reason: 'daypart_undefined' };
      return {
        scheduledAt: resolveWallClock(date, part.startsLocal, zone).toUTC(),
        tz: zone,
      };
    }

    case 'on_local_date': {
      // Time capsules AND banked messages. Fires on HER date, in the zone
      // she'll actually be in on that date.
      const anchor = DateTime.fromISO(i.targetLocalDate!, { zone: 'utc' });
      const zone   = await childZoneAt(i.childId, anchor);
      const part   = await lookupDayPart(
        i.childId, i.targetDaypart ?? 'after_school', i.targetLocalDate!);
      return {
        scheduledAt: resolveWallClock(
          i.targetLocalDate!, part?.startsLocal ?? '16:00', zone
        ).toUTC(),
        tz: zone,
      };
    }

    case 'when_reachable': {
      const zone = await childZoneAt(i.childId, now);
      const win  = await nextReachableWindow(i.childId, now, zone);
      return { scheduledAt: win?.start.toUTC() ?? null, tz: zone };
    }

    case 'immediate':
      return { scheduledAt: now, tz: await childZoneAt(i.childId, now) };
  }
}
```

### 6.4 Notification gate — two-sided

```ts
/** Recipient side: block arrivals during asleep/school. */
export async function gate(intent: DeliveryIntent, recipientId: string) {
  if (intent.priority === 'emergency') return { allow: true };

  const zone  = await zoneForUser(recipientId);
  const local = DateTime.utc().setZone(zone);
  const part  = await currentDayPart(recipientId, local);

  if (part && !part.reachable) {
    return {
      allow: false,
      reason: part.kind,                                   // 'asleep' | 'school'
      deferTo: await nextReachableWindow(recipientId, local, zone),
    };
  }
  return { allow: true };
}

/** Sender side: called live as the parent composes. Powers the send-time guard. */
export async function recipientContext(childId: string) {
  const zone  = await childZoneAt(childId, DateTime.utc());
  const local = DateTime.utc().setZone(zone);
  const part  = await currentDayPart(childId, local);
  return {
    localTime: local.toFormat('h:mm a'),
    zoneAbbr:  local.toFormat('ZZZZ'),                     // 'EDT'
    dayPart:   part?.kind,
    reachable: part?.reachable ?? true,
    skewHours: (local.offset - DateTime.local().offset) / 60,
  };
}
```

Drives the guard prompt:

> ⏰ It's **10:40 PM** for Maya — she's asleep.
> **Send now** · **Deliver at breakfast (7:00 AM her time)**

### 6.5 Message banking

```ts
/**
 * Fan one recording set out across N child-local dates.
 *
 * Zero new scheduling machinery: this is N `on_local_date` intents, which the
 * existing materializer already resolves correctly across DST, travel, and
 * custody-driven zone changes. That is the whole reason §4 was built first.
 */
export async function bankMessages(input: {
  childId: string;
  senderId: string;
  label: string;
  reason: BatchReason;
  startLocal: string;              // 'YYYY-MM-DD', child-local
  endLocal: string;
  cadence: 'daily' | 'weekdays' | 'weekly';
  daypart: string;                 // default 'bedtime'
  artifactIds: string[];           // ordered; preserved = true on all of them
}): Promise<{ batchId: string; scheduled: number; cycled: boolean }> {

  const dates = enumerateLocalDates(input.startLocal, input.endLocal, input.cadence);
  if (dates.length === 0) throw new BadRequest('empty_window');
  if (input.artifactIds.length === 0) throw new BadRequest('no_recordings');

  const batchId = uuid();
  await db.insert('intent_batch', {
    id: batchId, child_id: input.childId, sender_id: input.senderId,
    label: input.label, reason: input.reason, cadence: input.cadence,
    daypart: input.daypart, starts_local: input.startLocal, ends_local: input.endLocal,
  });

  // Fewer recordings than nights → cycle, and say so. Never silently truncate
  // the window; a parent who recorded 30 for 180 nights must know.
  const cycled = input.artifactIds.length < dates.length;

  await db.insertMany('delivery_intent', dates.map((d, i) => ({
    id: uuid(),
    batch_id: batchId,
    batch_seq: i,
    child_id: input.childId,
    sender_id: input.senderId,
    payload_kind: 'video_msg',
    payload_ref: input.artifactIds[i % input.artifactIds.length],
    policy: 'on_local_date',
    target_local_date: d,
    target_daypart: input.daypart,
    // Banked payloads are archive-tier by default: a deployment is exactly the
    // material a Year Book (§9.8.2) is made of.
    expires_at: DateTime.fromISO(d).plus({ years: 1 }).toJSDate(),
  })));

  await preserveArtifacts(input.artifactIds, input.senderId);
  return { batchId, scheduled: dates.length, cycled };
}
```

### 6.6 Child ping — agency with a governor

```ts
const PING_LIMIT_PER_DAY = 3;

/**
 * "Call me when you can." The child gets initiative; the parent's day-parts
 * still hold. A ping is a request, never an override, and never an emergency.
 */
export async function ping(childId: string, toUser: string) {
  const zone      = await childZoneAt(childId, DateTime.utc());
  const localDate = DateTime.utc().setZone(zone).toISODate()!;

  const { n } = await db.one(`
    SELECT count(*)::int AS n FROM child_ping
     WHERE child_id = $1 AND to_user = $2 AND local_date = $3`,
    [childId, toUser, localDate]);

  if (n >= PING_LIMIT_PER_DAY) {
    // Silently absorbed. The child is never told they have "used up" contact
    // with their parent, and no scolding copy is ever shown. Prohibition P2.
    return { sent: false, silent: true };
  }

  await db.insert('child_ping',
    { child_id: childId, to_user: toUser, local_date: localDate });

  return enqueue({
    childId, senderId: childId, payloadKind: 'nudge',
    policy: 'when_reachable',          // respects the PARENT's day-parts
    expiresAt: DateTime.utc().plus({ days: 2 }).toJSDate(),
  });
}
```

### 6.7 Medication — the exchange-day guard

```ts
/**
 * The double-dose case: Dad gives the morning dose in Austin at 8:00 CT,
 * hands off at noon, Mom reaches for "the morning dose" in Charlotte.
 * Both actors believe they are correct. The child-local slot key is what
 * makes the second write fail instead of the child taking two doses.
 */
export async function recordDose(input: {
  medicationId: string; childId: string; slot: string;
  byUser: string; householdId?: string; status: DoseStatus; note?: string;
}) {
  const now       = DateTime.utc();
  const zone      = await childZoneAt(input.childId, now);
  const localDate = now.setZone(zone).toISODate()!;

  try {
    return await db.insert('medication_event', {
      medication_id: input.medicationId,
      slot: input.slot,
      local_date: localDate,          // CHILD-local. The dedupe axis.
      local_tz: zone,
      administered_at: now.toJSDate(),
      by_user: input.byUser,
      household_id: input.householdId,
      status: input.status,
      note: input.note,
    });
  } catch (e) {
    if (isUniqueViolation(e)) {
      const prior = await db.one(`
        SELECT me.*, u.display_name FROM medication_event me
          JOIN app_user u ON u.id = me.by_user
         WHERE medication_id=$1 AND local_date=$2 AND slot=$3`,
        [input.medicationId, localDate, input.slot]);
      // Surfaced to the ADULT as a block, with attribution and local time.
      // Never surfaced to the child, and never framed as either parent's fault.
      throw new AlreadyAdministered({
        by: prior.display_name,
        atLocal: DateTime.fromJSDate(prior.administered_at)
                   .setZone(prior.local_tz).toFormat('h:mm a ZZZZ'),
      });
    }
    throw e;
  }
}
```

---

## §7 API surface

REST + WSS. All responses carry `child_local_time` alongside any timestamp.

**A scoping note, added by this project's own post-tier audit, not a
retroactive rewrite of the section below:** this §7 sketch predates almost
every route this codebase has actually built, and its own path shapes
(`:id` as a generic param name, several bare non-child-scoped paths like
`GET /v1/inbox`) do not match the real, shipped convention every genuinely
built route below actually uses (`:childId` explicitly, everything
child-facing scoped under `/v1/children/:childId/...`, per A3's own
childId-match authorization check, which needs a real childId in the path
to check against). Treat this section as the original architectural intent,
not a literal, still-current contract — each row's own real closing note
(where one exists) is what states the actually-shipped shape. A full
line-by-line reconciliation of every declared-but-not-yet-annotated row
against real code is a genuine, disclosed, separate undertaking, not done
here — this note exists so a reader doesn't take an unfixed line as a
current claim by default.

### 7.1 Identity & family graph

```
POST   /v1/auth/passkey/register        parent passkey enrollment
POST   /v1/auth/passkey/assert          parent sign-in
POST   /v1/auth/child/pin               child profile unlock (device-bound token)
POST   /v1/auth/escalate                PIN + biometric → guardian scope, 15 min TTL

GET    /v1/children                     children visible to caller
POST   /v1/children
GET    /v1/children/:id
POST   /v1/children/:id/guardianships   invite guardian / trusted adult / sitter / coordinator
PATCH  /v1/guardianships/:id            scope, supervised, restricted, expiry
```

**v0.47.0 — real routes actually built, named differently than the block
above.** The four lines above were this section's original, pre-implementation
placeholders; §7 was never revisited when `packages/db/src/pool.ts`,
`server/routes.mjs`, and `server/index.mjs` shipped the real thing, which is a
real drift this entry records rather than silently reconciles (a full §7.1
rewrite is out of scope for an authentication fix-and-verify pass). What
actually exists, real and RLS-backed against `db/migrations/0008_auth_credentials.sql`:

```
POST   /v1/children/:childId/kiosk-pin/verify   child kiosk unlock — tries the
                                                 PIN against every LIVE guardian
                                                 of that child (server/routes.mjs)
POST   /v1/me/pin                               guardian sets/replaces her own PIN
POST   /v1/auth/webauthn/register/challenge     guardian passkey enrollment, step 1
POST   /v1/auth/webauthn/register/verify        guardian passkey enrollment, step 2
POST   /v1/auth/webauthn/login/challenge        guardian passkey sign-in, step 1 (server/index.mjs — pre-session, cannot go through api.register())
POST   /v1/auth/webauthn/login/verify           guardian passkey sign-in, step 2 (ditto)
POST   /v1/auth/dev-login                       DEV_LOGIN=1 only — never production
```

**v0.49.9 — the guardian invitation route, real, and honestly incomplete.**
Closes half of `invitation_screen.dart`'s own named gap ("the API surface
names `POST /v1/children/:id/guardianships`, but no such route exists") —
create/read/accept-decision/revoke, all real and RLS-backed
(`db/migrations/0014_guardian_invite.sql`). Does NOT create a `guardianship`
row: that needs an app_user row for the invited party, and this codebase has
no account-creation route for one, for a first OR an invited guardian — see
this section's own note below and the migration's own header.

```
POST   /v1/children/:childId/guardianships      a real guardian invites a
                                                 new guardian/adult; no
                                                 dedicated Action exists for
                                                 "invite" so the handler
                                                 checks edgesFor() directly
GET    /v1/guardian-invites/:inviteId           no session — the invite's own
                                                 unguessable id is the
                                                 credential (mirrors a
                                                 single-use WebAuthn challenge)
POST   /v1/guardian-invites/:inviteId/accept    records a real decision only
POST   /v1/guardian-invites/:inviteId/revoke    only the inviting guardian —
                                                 RLS-enforced, not app logic
```

**Corrected v0.49.14 — the "no session" claim above was true in intent, not
in practice, until this pass.** `Api.handle()` required a Bearer session
token unconditionally for every route, before ever consulting a route's own
flags — so `GET`/`POST .../accept` above, despite being registered with
`skipOuterSession: true` and a comment saying exactly what the table above
says, still 401'd every real call from the unauthenticated invited party
they were built for. Found by an adversarial audit, not by a live incident:
this shipped in v0.49.9 and was never actually reachable. Fixed with a new
`Route.noSessionRequired` flag (`packages/api/src/api.ts`) — `Api`'s third
escape hatch, after `identityScopedByHandler` and `skipOuterSession`,
registration-time enforced to require `skipOuterSession` alongside it (no
verified principal exists to scope `db.withSession()` with). Set on exactly
these two routes, not on `revoke`/`create` above, which correctly still
require the caller's real session. See CHANGELOG v0.49.14 for the full
account, including why no existing test had caught this
(`guardian_invite.test.mjs` called `pool.mjs` directly, bypassing HTTP;
`contract.test.mjs` never calls `api.handle()`; `routes.test.mjs` had zero
guardian-invite coverage) and the new tests that now do, at both the `Api`
mechanism level and against these real routes end to end.

No dedicated `escalate` server route exists, and none was needed — **as of
v0.49.7, §8.3's PIN+biometric escalation ceremony has a real UI surface**
(`guardian_escalation_screen.dart`, reached from a small persistent affordance
`kiosk_shell.dart` now renders over the locked child surface). The PIN factor
reuses the existing `kiosk-pin/verify` route; the biometric factor reuses the
existing WebAuthn login challenge/verify routes
(`webauthn_channel.dart`'s new `buildVerifyBiometricCallback`) — a real
platform-authenticator assertion, checked server-side, not a device-local
prompt taken on faith. `lock_controller.dart`'s `escalate()` itself
(`packages/child-lock/src/lock.ts`, not `family-graph` — this entry's own
package name was wrong) was ported and unit-tested well before this pass;
what was missing, and is now real, was purely the "nowhere to escalate to"
half. The one real action the resulting screen offers is releasing the
native kiosk lock (`KioskChannel.stop()`) — see CHANGELOG v0.49.7.
**Separately found in v0.49.7, resolved in v0.49.8:** `packages/auth/src/auth.ts`
also exports `escalateSession()` — a server-side primitive that mints a real,
independently-TTL'd escalated session token — with no caller anywhere in
`server/`. v0.49.7 additionally claimed "no test file at all," which was true
only of `packages/auth/test/` and was a miss, not a finding: `escalateSession()`
is directly exercised by `packages/api/test/stack.test.mjs`'s "C sessions"
section (both factors required, either alone refused, a child role refused
outright, its own `ESCALATION_TTL_MS` = 15 min TTL distinct from the ordinary
session's `SESSION_TTL_MS`) and, in that same file's "F api" section, end to
end through a synthetic `escalated: true` test route proving `Api.handle()`
(`packages/api/src/api.ts`) actually honors `Route.escalated` — `m.route.escalated
&& !principal.escalated` gates the request before authorization even runs.
v0.49.8 closed the one branch that search surfaced as genuinely uncovered —
`readSession()`'s own malformed-token paths — and otherwise corrected the
record rather than added new code there.

Whether client-side escalation should also mint one of these — giving an
escalated guardian a live elevated API session, not just a released kiosk
lock — remains a real, still-open **product** question, and v0.49.8
deliberately does not answer it by inventing a route: nothing in the API
surface below or in §8.3 currently needs step-up authorization beyond what
an ordinary authenticated guardian session (passkey sign-in, full
guardianship-edge authorization via `can()`) already grants. Wiring
`escalateSession()` to a route that exists only to give it a caller would be
a fabricated product decision, not a fix. What v0.49.8 does instead: leaves
`escalateSession()` and `Api`'s `Route.escalated` field in place, together,
as tested, working, intentional groundwork — not dead code — for whichever
future guardian-facing action turns out to need "prove PIN+biometric again,
right now" rather than "hold a valid guardian session." One boundary is
permanent, not a future decision: per **P7** (§2.1), that action must never
be reading the child's journal — P7 names "guardian escalation" by name as a
forbidden override, and no future route may make escalation the exception
graduated privacy was built to have none of.

### 7.2 Time engine

```
GET    /v1/children/:id/now             { localTime, zone, dayPart, reachable }
GET    /v1/children/:id/ribbon?hours=18 day-part bands + viewer overlay + overlap
GET    /v1/children/:id/timezone-timeline
POST   /v1/children/:id/timezone-intervals
GET    /v1/children/:id/day-parts
PUT    /v1/children/:id/day-parts
POST   /v1/children/:id/overlap         availability intersection with actor set
GET    /v1/children/:id/schedule-strip  visual next-N-day-parts, child shell (§8.4)
```

### 7.3 Async delivery & message banking

```
POST   /v1/intents                      { payloadKind, policy, target*, payloadRef }
GET    /v1/intents?state=pending
PATCH  /v1/intents/:id                  reschedule / revoke before delivery
POST   /v1/intents/:id/rematerialize    force recompute (admin / test)
GET    /v1/inbox                        child view: delivered + ready
POST   /v1/children/:childId/inbox/:id/opened   receipt, recorded in child-local
                                         time. REAL, CLOSED v0.49.51 (this
                                         project's own post-tier audit) — declared
                                         here since this section was first written,
                                         never built until now; a real, disclosed,
                                         user-visible gap the moment the inbox
                                         itself went live (Tier C/D): inbox_screen.
                                         dart's own _open() only ever flipped
                                         `watched` in local widget state, so every
                                         previously-read message re-materialized as
                                         "New" on the next load, and the unread
                                         badge never actually cleared. Real path
                                         shape is child-scoped
                                         (`/v1/children/:childId/inbox/:id/opened`),
                                         not this section's own bare original —
                                         see §7's own scoping note above.

POST   /v1/batches                      bank N messages across a date window
GET    /v1/batches/:id                  progress: delivered / remaining / next
PATCH  /v1/batches/:id                  extend, shorten, swap recordings
DELETE /v1/batches/:id                  revoke undelivered remainder only
```

### 7.4 Sessions & activities

```
POST   /v1/sessions                     create; returns LiveKit token + room
GET    /v1/sessions/:id
POST   /v1/sessions/:id/activities      attach module { kind, config }
WSS    /v1/sessions/:id/state           authoritative state sync
POST   /v1/sessions/:id/captions        live caption + translation stream (§8.4)
POST   /v1/sessions/:id/end
```

### 7.5 Homework

```
POST   /v1/homework                     multipart: image → deskew → OCR
GET    /v1/homework/:id
POST   /v1/homework/:id/annotations     stroke batch, per-user undo stack
POST   /v1/homework/:id/hint            Socratic hint for the PARENT. Never solves.
GET    /v1/homework?subject=&from=&to=  archive, child-local date range
```

### 7.6 Calendar, custody, lists

```
GET    /v1/children/:id/calendar?view=child|guardian
POST   /v1/calendar/events
POST   /v1/custody/orders
POST   /v1/custody/change-requests       propose → accept/decline → immutable record
GET    /v1/custody/schedule?from=&to=    materialized occurrences

GET    /v1/children/:id/list?kind=want|need
POST   /v1/children/:id/list
POST   /v1/list/:id/claim                guardian only; never surfaced to child
```

### 7.7 Coordination layer

```
GET    /v1/children/:id/medications
POST   /v1/children/:id/medications
POST   /v1/medications/:id/doses         409 ALREADY_ADMINISTERED on slot collision
GET    /v1/medications/:id/log?days=30

GET    /v1/children/:id/emergency-card   offline-cacheable; sitter role readable
PUT    /v1/children/:id/emergency-card
GET    /v1/children/:id/school
PUT    /v1/children/:id/school

GET    /v1/children/:id/expenses         403 for child role — RLS, not middleware
POST   /v1/children/:id/expenses
POST   /v1/expenses/:id/accept | /dispute | /reimburse
GET    /v1/children/:id/expenses/export  court-tier PDF (Phase 3)

GET    /v1/children/:id/availability     every co-guardian's windows, incl. the caller's own
PUT    /v1/me/availability               the calling guardian's own windows only — identity-only,
                                          not child-scoped; always the session's own userId
```

**Built — see CHANGELOG's `[Unreleased]` → "Guardian availability" entry.**
`db/migrations/0010_availability.sql` (`guardian_availability_window`, real
RLS), `packages/db/src/pool.ts`
(`setAvailabilityWindows`/`availabilityFor`/`guardiansOfChild`),
`server/routes.mjs`, `client/lib/availability_screen.dart` — MARKUP screen
`availability`, §9. CHANGELOG has the full account, including what remains
unverified (the RLS suite needs a real Postgres this session's sandbox
didn't have).

### 7.8 Exchange

```
GET    /v1/children/:id/exchanges?from=&to=
POST   /v1/exchanges/:id/bag             upsert manifest items
POST   /v1/exchanges/:id/bag/:item/sent
POST   /v1/exchanges/:id/bag/:item/returned
POST   /v1/exchanges/:id/arrived         EVENT ONLY. Rejects any coordinate payload.
POST   /v1/exchanges/:id/delay           { minutes, note } — immutable once written
```

### 7.9 Archive

```
GET    /v1/children/:id/archive?from=&to=&kind=
POST   /v1/artifacts/:id/preserve        guardian election; clears expires_at
POST   /v1/artifacts/:id/release         re-attaches a retention clock
GET    /v1/children/:id/yearbook/:year   compiled edition (Phase 3/4)
POST   /v1/children/:id/yearbook/:year/print
GET    /v1/children/:id/onthisday        opt-in; honours era mutes
PUT    /v1/children/:id/onthisday/prefs  { enabled, mutedEras[] }
POST   /v1/children/:id/handover         majority transfer. Irreversible. §9.8.4
GET    /v1/children/:id/export           full portable bundle
```

### 7.10 Child agency

```
POST   /v1/ping                          child → guardian. Rate-limited, silent.
GET    /v1/journal                       child role ONLY. No guardian route exists.
POST   /v1/journal
GET    /v1/rituals
POST   /v1/rituals
```

> There is deliberately no `GET /v1/children/:id/journal`. The absence is the
> feature. See P7.

---

## §8 UI architecture

### 8.1 Shells

| Shell | Entry | Characteristics |
|---|---|---|
| **Child** | PIN | Kiosk-locked. Icon-first. 64 dp targets. No settings surface. TTS everywhere. No expense surface at any depth. |
| **Guardian** | passkey + escalation | Full. Dual-clock persistent. Court-export surface. |
| **Step-parent** | passkey | Scoped by the guardian who invited them. Calls, calendar read, bag manifest. |
| **Trusted Adult** | passkey | Calls and messages only. No calendar edit, no settings, no list claims. |
| **Sitter** | time-boxed link | Emergency card, medication log write, calendar read. Auto-expires. |
| **Coordinator / GAL** | passkey + order_ref | Read-only across the parent↔parent log, custody changes, and expense ledger. No child-facing surface at all. |

### 8.2 Closeness UI patterns

#### §8.2.1 **Persistent dual clock**, child's time dominant:
   > **Maya · 4:12 PM EDT** — just got home from school
   > you · 3:12 PM CDT

#### §8.2.2 **The Day Ribbon** — 18-hour horizontal band of her day, colored by day-part,
   parent availability overlaid. Green overlap = *"you're both free 5:30–6:45
   her time."* Tap to schedule. **This single component replaces all timezone
   arithmetic.** Signature element.

   **Amended v0.39.0** — each segment also carries a static glyph (🌅 wake,
   ☀️ school/free, 🌇 dinner, 🌆 wind-down, 🌙 bedtime/asleep), declared next to
   the friendly label in the same table (`phase3.ts`) rather than a second
   lookup, so the two cannot drift apart. Static, never pulsing — §8.13 still
   bans anything that moves on its own to draw the eye.

#### §8.2.3 **Never make a parent do math.** Every child-related time renders child-local
   with actor-local as subscript: *"arrives 8:30 PM her time (7:30 PM yours)."*

#### §8.2.4 **Receipts in her frame.** *"Watched at 7:04 AM her time — before school."*

#### §8.2.5 **Countdowns in sleeps.** *"3 sleeps until Dad's week."* Computed on her local
   day boundaries. Children do not think in hours.

#### §8.2.6 **Ambient texture.** Sunset in Charlotte. Weather at her school.

#### §8.2.7 **Send-time guard.** See §6.4.

#### §8.2.8 **Batch progress, parent-side only.** *"Night 42 of 180 — next delivers
   tomorrow, 8:30 PM her time."* The child sees a message from Dad. She is never
   shown that it was pre-recorded, and never shown a counter. That framing is
   the parent's to give, not the product's to expose.

#### §8.2.9 **Conversation starters.** Drawn from the archive and calendar: *"ask about
   the science fair — she mentioned it Tuesday."* Aimed at the parent facing a
   monosyllabic nine-year-old.

### 8.3 Child lock — use the OS

| Platform | Mechanism |
|---|---|
| Android | Screen Pinning / kiosk (`startLockTask`) |
| Windows | **App-level lock** (window-chrome strip + a re-arming `WH_KEYBOARD_LL` hook) — **not** OS Assigned Access; Ctrl+Alt+Del is OS-reserved and undeliverable to any user-mode hook, by design |
| iOS (Ph.4) | Guided Access + Screen Time API |

- Escalation to guardian scope requires **PIN + biometric**, or a passkey.
- **Shuffled numeric keypad** for guardian PIN — the child is literally watching.
- Failed-attempt cooldown notifies the *other* guardian.
- **Break-glass path** so a parent locked out at 9 p.m. does not lose a
  scheduled call.

### 8.4 Accessibility and inclusion

Not a compliance checklist. Each of these unlocks a population that currently
cannot use any product in this category.

| Need | Implementation | Why it earns its place |
|---|---|---|
| **Neurodivergent children** | Visual schedule strip built from `day_part`; transition countdowns in sleeps; predictable routine surfaces; "what happens next" band | The architecture is *already* a visual-schedule tool. Occupational therapists build this by hand today. Marginal cost is near zero. |
| **ADHD households** | Medication log (§5.8), checklists, routine rituals, bag manifest | The single highest-frequency daily friction in these families |
| **Deaf / hard of hearing** | Captions on live calls **and** every async artifact (`media_artifact.caption_key`) | Also serves hearing grandparents with age-related loss — a far larger population than the primary case |
| **Bilingual families** | Live caption translation; dual-language UI; per-user language preference | Large, badly served US population. Lets a Spanish-only grandparent participate fully. |
| **Pre-readers (4–7)** | Icon-only navigation, voice-driven nav, TTS on everything, 64 dp targets | The youngest users are the ones who most need the absent parent |
| **Dyslexia** | Optional dyslexia-friendly face, adjustable spacing, TTS | Cheap toggle, meaningful effect |
| **No-smartphone parents** | **SMS bridge**: receive text summaries, reply by text, receive a voice call bridge. Reduced fidelity, full participation. | Incarcerated, elderly, deployed with device restrictions, or simply poor. **If the away parent cannot participate, the product has failed at its only job.** |
| **Low bandwidth** | Audio-only fallback, SVC/simulcast, local-first SQLite + outbox, everything async-capable | Deployed parent, rural grandparent, school wifi |

---

## §9 Feature specifications

### 9.1 Homework

Photo → auto-deskew → crop → OCR → **shared annotation layer** with laser pointer
and per-user undo.

**"Hint, don't solve" mode** is the defensible core: an AI tutor coaches *the
parent* with Socratic prompts. A parent who forgot algebra fifteen years ago can
still be the one who helps. That protects their authority, which is the actual
job-to-be-done. Never auto-answers. AI assistance is logged and visible.

OCR runs **on-device first** (ML Kit) — free, offline, and the photo never leaves
the device, which is a compliance argument as much as a privacy one.

### 9.2 Games

Build a **runtime, not a studio.** Ship 5–8 small games.

- **Turn-based first** — cheap, async-native, survives bad connections.
- **Co-op over competitive.** "Us against the puzzle" builds relationship;
  parent-vs-child competition goes sideways.
- Tag educational games to curriculum standards so a parent sees *"practiced
  3rd-grade fractions,"* not *"played a game."*
- Turn clocks tick in **reachable hours**. See §4.7.

**Shipped v0.17.0:** three in a row, dots and boxes, memory from the family's own
photos, and a co-op story. Three mechanics matter more than the titles:

| Mechanic | Why |
|---|---|
| **The handicap is set by the CHILD** | Not a difficulty slider. She chooses what the parent gives up — same material effect, opposite power dynamic. `setHandicap()` refuses a parent handicapping themselves, and the engine enforces the condition rather than the UI hiding it. |
| **Takebacks are free and unlimited** | A physical board lets you hover a piece and change your mind. Implemented by replaying from the start, because inverting the last move breaks on the extra-turn rules. |
| **A move can carry a voice note** | You cannot watch someone think across a timezone. |

**A parent who always wins is a harm the product created**, so the handicap
prompt surfaces itself after three straight losses. The record exists only to
decide when to offer; it is never rendered, and the prompt is phrased as her
choosing.

**Shipped v0.18.0:** checkers (compulsory captures, multi-jump, crowning ends a
chain), battleship (a hit grants another shot; opponent positions never leave the
server), word search (**the parent hides the words, and they are personal**),
guess-the-word (eight lives, because this is not a game about a child failing),
and chess on `chess.js` — because castling, en passant, promotion, stalemate,
threefold repetition and the fifty-move rule are a classic underestimate.

Chess coaching reuses §9.1 exactly: it asks the parent a question and never gives
the move, and is asserted to contain no algebraic notation.

**Shipped v0.19.0** — three the product is uniquely able to do:

| Game | Why it belongs here |
|---|---|
| **"I went to the market"** | Simon is a machine testing a child against a high score; the campfire chain is cooperative, fails together, and runs one step per turn. The steps are **recordings of the parent's voice** — the memory game is made out of the parent. |
| **Kim's game** | A photo of his real table with one thing removed. Zero art assets, and it teaches her what his house looks like. |
| **The scavenger hunt** | The only game that gets her **off the screen and around her house**. No timer — a countdown would make wandering a test. Every find is `preserved: true`, because a photograph of the oldest thing in her mother's house, taken because her father asked, is exactly what §9.8.2 and §9.8.4 exist for. |

**Shipped v0.20.0 — ten LIVE games, played during a call.** A five-year-old runs
out of things to say in about ninety seconds; a live game is a **spine for the
call**, not entertainment. Three constraints, all enforced structurally:

| Constraint | Enforcement |
|---|---|
| **Nothing sub-200ms** | `register()` throws `UnplayableOverNetwork`. Over a real connection a reflex game makes the network the opponent and **the child takes the blame**. |
| **The face is never hidden** | `VideoLayout` has exactly two members; there is no `hidden` and no `fullscreen`. `liveLayout()` returns `videoVisible: true` in every branch. |
| **Degrade, do not die** | The call drops and the game becomes turn-based with progress preserved. Games needing a live camera say so honestly. |

Connection strings blame the network explicitly — *"The connection is slow right
now — not you."* — and are asserted to contain no blame directed at the child.

On the Z Fold 5's nearly-square main screen the video and board sit **side by
side with the gutter on the crease**; folded, they stack with the face on top.

P2 applies throughout: no ELO, no ranking, no record, no "you lost" screen. A
competitive game closes with "Good game."

> **Status, v0.49.17 — two of the four §9.2 catalogue entries listed above as
> "Shipped v0.17.0" now have a real CLIENT board too, not just a tested engine.**
> `newGame()`/`play()`/`takeBack()`/`setHandicap()`'s tic-tac-toe and
> dots-and-boxes branches (`packages/games/src/games.ts`, real and tested since
> before this pass) had no Flutter screen to reach them — `GamePickerScreen`
> fell through to an honest not-built-yet acknowledgment for both. `client/lib/
> game_tictactoe.dart` and `client/lib/game_dotsboxes.dart` port those four
> functions directly into Dart (reusing `game_logic.dart`'s own `Side`, not a
> second side type), matching the exact structural pattern
> `game_chess.dart`/`game_checkers.dart` already established: an ENGINE
> section, a WIDGET section, a simulated local parent opponent (a short
> "thinking" delay, then a uniformly random legal move — no live session
> runtime exists to relay moves between two real devices), and P2 discipline
> throughout (a finished game closes with a plain factual line, never a score
> or a verdict). Dots-and-boxes' `claimBoxes()` cascade — completing a box
> grants the SAME side another move — is ported exactly, including the
> double-cross case (one edge closing two boxes at once) and the take-back
> edge case games.ts's own doc comment names by name: undoing a box-completing
> move must hand the turn back to whoever it was before that move, not to
> whoever would normally go next. Both games start with no handicap active and
> reuse the existing, already-real `HandicapScreen`/`catalogueFor()`/
> `handicapBanner()` (rather than a second setup screen, since both kinds are
> already real catalogue entries) — a handicap applies immediately to the
> CURRENT game state, board and move history untouched, honoring
> `HandicapScreen`'s own "even mid-game" promise literally rather than
> restarting the game. `GameKind.memory` — "Our photos" — remains on the
> honest not-built-yet path: a separate, still-open product decision about
> where real photos for that game come from, deliberately out of scope here,
> not forgotten. Layout genuinely adapts by real device posture
> (`form_factors.dart`, v0.49.13) rather than a single no-overflow breakpoint:
> a stacked single column at `foldCover`/`phone`/`tabletSmall`, a persistent
> side panel (banners plus a real button column) alongside the board at
> `foldMain`/`tabletLarge`+. See CHANGELOG v0.49.17 for the full account,
> including an adversarial self-verify pass's findings.

**Play Together Phase 1, Batch A — shipped v0.49.18.** The catalogue's local
pass-and-play roster grows from four `GameKind`s to six: **Draw Together**
(co-op, minAge 4, "One shared page. Draw whatever you like.") and **Guess the
Doodle** (co-op-framed, minAge 5, "One of you draws it, the other guesses.").
Both are `game_logic.dart` catalogue entries in exactly `story`'s own shape —
`competitive: false, handicaps: []`, nothing to be behind at. Both are also
the second and third real screens to build on `annotation_canvas.dart`'s
`AnnotationCanvas` (§9.12.4's shared engine), and the first to put TWO real
actors on it at once: `game_draw_together.dart` lets 'child' and 'parent'
draw on one canvas simultaneously with each person's undo scoped to their
own strokes only (the engine's whole reason for existing — see its own
header on why a naive "pop the last stroke" implementation lets a parent's
undo erase a child's drawing); `game_guess_doodle.dart` puts only ONE
actor's strokes live at a time (the guesser never draws — there is only one
`GestureDetector` on the whole screen) and adds a real, drafted 86-word
curated bank across seven categories (animals, food, everyday objects,
nature, places/vehicles, actions, and a little gentle fantasy) — a curated,
in-repo constant, never free text, the actual content-safety mechanism this
whole phase rests on. Its closest thing to an outcome is "did you get it?" —
yes/no, shown once, never tallied across rounds, matching P2's "no scores,
streaks, or ranks" exactly as `doodle_desk.dart`'s own header already
establishes for this family of screens. Both screens are genuinely
device-adaptive (§8.11.1): a slim bottom bar for tools/round controls at
`foldCover` width, a persistent side panel on the crease gutter (`foldMain`'s
own documented two-column-gutter convention) at two-plus columns —
structurally different widget trees, not the same layout resized, and
proven as such by a widget test. **Batches B (four curated-prompt
activities) and C (two younger-age visual activities) remain unbuilt**,
scoped for later, sequential passes per the spec's own batching plan. See
CHANGELOG v0.49.18.
>
> **Correction (v0.49.22 audit-fix).** The spec's own Batch A section (line
> ~74) explicitly required "a common canvas-hosting wrapper both screens
> use" — Batch A shipped without one: `game_draw_together.dart` and
> `game_guess_doodle.dart` each carried their own near-identical private
> `_Canvas` widget (same Container/BoxDecoration/GestureDetector/CustomPaint
> structure), a silent omission an adversarial audit caught. The shared
> wrapper now exists — `annotation_canvas_view.dart`'s `AnnotationCanvasView`
> — and both screens build on it; each keeps its own `CustomPainter` (fixed
> ink color vs per-stroke color), so this was a behavior-preserving
> refactor, not a rewrite: both screens' existing test suites pass
> unchanged. See CHANGELOG v0.49.22.

**Play Together Phase 1, Batch B — shipped v0.49.20.** The catalogue's local
pass-and-play roster grows from six `GameKind`s to ten: **Silly Sentence
Maker** (co-op, minAge 4, "Build the silliest sentence you can, one word at
a time."), **Would You Rather** (co-op, minAge 4, "Impossible choices, no
wrong answers."), **Two Truths and a Tall Tale** (co-op, minAge 6, "Two are
true. Can she guess the made-up one?"), and **20 Questions** (co-op, minAge
5, "Yes, no, and a secret only one of you knows."). All four are
`game_logic.dart` catalogue entries in exactly `story`'s own shape —
`competitive: false, handicaps: []`, nothing to be behind at — and all four
share a new small layout base, `game_curated_activity.dart`
(`CuratedActivityLayout`/`SessionHistoryPanel`), rather than each
re-deriving the same posture-driven prompt/history split independently, the
shared base the spec's own batching plan floated as optional for this batch
specifically. The real work was content: `game_silly_sentence.dart` drafts
80 mad-libs words across four curated categories (always leading with a
'silly character' blank so a capital letter never lands mid-sentence) and
five sentence templates; `game_would_you_rather.dart` drafts 50 curated
either/or pairs, each answered independently by both people before either
answer reveals — never who chose "better," because there isn't one;
`game_twenty_questions.dart` drafts 100 curated secrets across five
categories (never free text — a curated category picker deals the secret)
and never tries to parse the spoken QUESTIONS themselves, only tallying
curated yes/no taps, which double as a real per-round history log, with
twenty as a gentle nudge, never a hard stop (P2). `game_two_truths.dart` is
the one activity the spec flagged by name as needing real design judgment,
because the classic party game's each-player-invents-their-own-facts shape
is still an open-text/personal-information risk even with no `TextField`
anywhere — it pressures a real personal fact to be SPOKEN if not typed. The
mechanism shipped instead: 30 curated round sets across five trivia
categories (90 statements total), every truth AND the tall tale authored by
the app about the world, never about either player — see that file's own
header for the full reasoning, the safest and most conservative reading of
the spec's mandate available. All four screens are genuinely device-adaptive
(§8.11.1), following the convention Batch A proved rather than inventing a
fourth variant: a single prompt at `foldCover` width with no history panel
at all, a persistent session-history side panel appearing only at two-plus
columns — the panel's absence at narrow width IS the structural difference,
proven by the same layout-ROOT-type widget test (`Column` vs `Row`) Batch A
established. See CHANGELOG v0.49.20.

**Play Together Phase 1, Batch C — shipped v0.49.21. Phase 1 is now
complete: the catalogue's local pass-and-play roster grows from ten
`GameKind`s to twelve**, closing every activity the spec named across all
three batches. **Copy the Pattern** (co-op, minAge 2, "Watch it light up,
then tap it back — it grows one more every time.") and **Find It** (co-op,
minAge 2, "A picture full of little things to spot — point, and she taps
it.") are both `game_logic.dart` catalogue entries in exactly `story`'s own
shape — `competitive: false, handicaps: []` — for the same reason every
other Play Together entry carries none: self-scaling difficulty (a growing
pattern length; a curated scene's own fixed, posture-driven object count)
means there is nothing for a parent-set handicap to apply to. Both are also
this catalogue's first `minAge: 2` entries, and earn it structurally rather
than by claim: `game_copy_pattern.dart`'s tap-grid is four color-AND-icon
tiles with no word anywhere gameplay depends on reading, and
`game_find_it.dart`'s curated scenes are the same — a scene's objects carry
a plain-language reference name only for a screen-reader label and a
parent-facing tooltip, never rendered as on-screen text. `game_copy_pattern.
dart`'s pattern playback is a real §8.13 consequence-animation chain (one
tile highlights at a time, never a loop, triggered only by something she
just did), and a wrong tap resets INPUT PROGRESS ONLY — the pattern never
shrinks or restarts at length 1 — a conservative, explicitly-reasoned open
design decision (the spec did not specify wrong-tap handling) made per this
run's overnight-autonomous instructions, matching this codebase's existing
house style for handling a child's mistake gently rather than as a setback.
`game_find_it.dart` is **the one activity in the whole Phase 1 spec where
device posture changes real CONTENT, not just layout** — `visibleObjectsFor
()` renders a curated scene's first five hand-placed objects at a single-
column posture and its FULL curated set (nine per scene) at two-plus
columns, text-scale-aware exactly like `columnsAt()`'s own effective-width
math (§8.8), proven by a widget test asserting the actual rendered object
COUNT differs, not just a layout. Three curated scenes ship (`yardScene`,
`kitchenScene`, `toyBoxScene`) — genuinely distinct icon sets AND genuinely
distinct hand-placed layouts (a grid, an organic scatter, and a corners-
plus-quadrants arrangement), never one scene re-skinned three times, each
using Flutter's built-in `Icons` set (zero image assets, matching this
codebase's icon-forward visual style established throughout `game_picker.
dart`'s own `_GameCard`). `child_home.dart`'s `onPlay` switch now has a real
case for every `GameKind` except `memory`, which remains on the honest
not-built-yet fallback pending its own separate, still-open photo-source
product decision — deliberately out of scope for this entire phase, as
every batch's own note above already states. See CHANGELOG v0.49.21.

**Audit-fix pass — shipped v0.49.22.** A 6-dimension adversarial audit of
everything PRs #34–#40 shipped this session (tic-tac-toe/dots-and-boxes,
the theme suite, Play Together Batches A–C, the `push_channel_test` CRLF
fix) raised 9 findings — 1 HIGH, 4 MEDIUM, 4 LOW — every one independently
re-verified by a second pass that tried to refute it and could not. All 9
are fixed. The HIGH finding, and the one worth stating plainly here: both
`game_two_truths.dart` and `game_twenty_questions.dart` shipped in Batch B
with a persisted session-history list that recorded whether each round's
guess was correct — a de facto win/loss tally, exactly what this section's
own P2 discipline exists to forbid, even with no literal score ever shown.
Neither file's own P2 test group caught it, because both only checked that
the forbidden-vocabulary sweep found nothing on the CURRENT screen state,
never the content of what got persisted into history — the sibling files in
the same batch (`game_would_you_rather.dart`, `game_silly_sentence.dart`)
already got this right, which is what made the gap avoidable rather than a
hard problem. Fixed: both persisted-history entries are content-only now: no
outcome word, no distinction between a correct guess and an incorrect one.
The Batch A shared-canvas-wrapper correction is noted in that batch's own
status paragraph above, not repeated here. See CHANGELOG v0.49.22 for the
complete account of all 9 findings.

**"Right now, together" — local ad-hoc play, shipped v0.49.59.** Every game
above assumes a network path back to a server: async turn-based via
`games.ts`, or live-during-a-call via `live_games.ts`. Real gap, confirmed
by direct inspection before building: nothing in this catalogue works when
two devices are in the same room on the same WiFi with no internet at all
— the literal "no signal, the kids want to play something together right
now" case. Five new games ship on a wholly separate transport built for
exactly that: `local_pairing.dart`'s `LocalPairingController` does real
mDNS discovery (`bonsoir` — both broadcast and browse; a query-only
library cannot do the broadcast half) to find the other device on the same
LAN, then exchanges turns over one plain HTTP POST per move to a small
embedded local server (`local_session.dart`) — no LiveKit, no push
notification, no account, nothing leaving the WiFi network. Capped at
exactly 2 physical devices, no mesh; a device can locally host more than
one seat (a human plus one or more CPU seats).

**Uno** (`game_uno.dart`/`uno_session.dart`/`uno_bot.dart`/`uno_deck.dart`)
is the deepest of the five: a real seat-based 2–4 seat engine, not
hardcoded to 2; 3-tier CPU opponents that only ever see public information
(an opponent's hand *count*, never its contents). **Corrected v0.49.59
overstatement (found and fixed in the v0.49.60 pass below, not silently
left standing):** this row originally claimed "the four house-rule
toggles Mattel's own current rules document as legitimate variants (Wild
Draw Four Challenge, 7-0, capped same-card-only stacking, arbitrated
jump-in)" and "an auto-clearing 'UNO!' badge" were real at this version —
neither was true. As of v0.49.59, Wild Draw Four auto-resolved with no
challenge option, there was no "Uno!"-calling/catch mechanic of any kind,
and none of Mattel's own four genuinely-optional house-rule variants
(Wild Draw Four Challenge, 7-0, capped same-card-only stacking, arbitrated
jump-in) were wired in — only a first casino-table visual layer (fanned
hands, a one-shot action-card glow), grounded in real research into
official rules, house-rule community consensus, and the genre's own
commercial/video-game history, not guessed. **As of v0.49.60, the table
and engine are both real, remodeled after a specific reference the owner
asked to match as closely as possible — the 2006 Xbox Live Arcade UNO,
watched frame-by-frame for this pass:** a real 4-seat 360°-around-the-
table arrangement, a curved turn-direction indicator, a discard trail, no
avatar icon (this app's own explicit, disclosed divergence from the
reference), and a P2-safe win screen (the reference's own round/game
screens race a numeric point total to a target score, exactly what P2
bans — put to the owner directly, not copied or silently dropped). The
Wild Draw Four Challenge is now real (a base Uno rule, not a house-rule
toggle) and so is calling "Uno!" with a real out-of-turn catch penalty;
7-0, capped same-card-only stacking, and arbitrated jump-in remain
genuinely unimplemented, each its own disclosed follow-up. vsCpu now
offers a real 2/3/4 seat-count choice matching the reference's own table;
vsPeer stays exactly 2 seats, a real transport limit. A card-size
customization suite (a live-preview slider, bounded per-device so it can
never cross the existing §8.4 64dp touch-target floor, with a real
horizontal-scroll fallback guaranteeing every hand stays playable at any
chosen size) — verified live on both the Fold5 and the tablet. **War**,
**Connect 4** (a real minimax+alpha-beta CPU, 3 difficulty tiers, the
Easy tier deliberately skipping its own block-check rather than pretending
to), **Piece It Together** (a cooperative shape-placement puzzle, chosen
deliberately over a sliding puzzle to avoid that genre's own real
solvability-parity bug class), and **Pictionary** (reusing
`live_games.ts`'s existing `Pictionary`/`guessDrawing()` engine and
`annotation_canvas.dart`'s canvas verbatim, rather than a second one) round
out the five.

All five are posture-aware (`form_factors.dart`'s real
`Posture`/`postureFor()`) and P2-compliant throughout — no score, streak,
or rank persists anywhere, including hidden state; Uno's round-end
celebration names only who won *this* round. Hardware-verified end to end
on two real devices repeatedly across this build, including one real bug
this section's own discipline exists to catch: at the true
`foldTabletop` landscape posture's short ~420dp height, all five screens'
shared `Center`-in-`Padding` body overflowed by close to 300px — found only
by forcing the real posture on real hardware, not by `flutter analyze` or
any unit test, and fixed the same way `child_home.dart`/`care_note.dart`
already handle a short viewport: `SingleChildScrollView`, not a bare
`Center`.

**Not yet wired into real navigation.** All five are reachable today only
through dedicated `main_local_*_test.dart` DEV-VERIFICATION-ONLY entry
points (the same posture as `main_live_child_call_test.dart` and its
siblings) — none of `child_home.dart`, `guardian_more.dart`, or
`game_picker.dart` has a real tile or route to any of them yet. This is a
disclosed, deliberate scope boundary, not an oversight: where a
same-WiFi, right-now local-play mode belongs relative to the existing
"Play together" (async, any-network) catalogue is a real product/
navigation decision — a new hub section, a device-discovery-gated tile, or
something else — not decided here.

### 9.3 Wants / needs

- Strictly separate lists.
- **Needs route to action** — claimable by one guardian, with status. Prevents
  both-buy and neither-buy.
- **No price field, no buy button, no affiliate link.** Prohibition P4.
- Claim/decline state is invisible to the child.

### 9.4 Calendar

Two layers: **child view** (birthdays, school events, "Dad's week" in friendly
language) and **guardian view** (exchanges, holiday rotation, in order-time with
zone shown verbatim — *"Fri 6:00 PM ET, per order"*).

Patterns: 2-2-3, 2-2-5-5, alternating weeks, holiday rotation generating years
forward. Change requests are a workflow, not free editing. Two-way sync with
Google/Apple Calendar; ICS import from school districts.

### 9.5 Message banking

**The highest emotional value per unit of engineering effort in the product**,
because §4 already did the hard part.

A deploying parent records thirty goodnight videos before they leave. One
delivers each night at her bedtime, in her timezone, for the whole blackout.
Mechanically: thirty `on_local_date` intents in one `intent_batch`. No new
scheduling machinery. See §6.5.

Applies to any known-in-advance absence: deployment, surgery, a treatment
program, a long haul, a custody gap.

**Design rules:**

- **Cycling is disclosed.** 30 recordings across 180 nights repeats; the parent
  is told, with the option to record more or shorten the window.
- **Batch payloads are archive-tier by default** (`preserved = true`). A
  deployment is precisely the material a Year Book is made of.
- **Revocation affects the undelivered remainder only.** Delivered messages are
  the child's.
- **The child is never shown the mechanism.** No "pre-recorded" label, no
  counter, no "42 of 180." See §8.2.8.
- **A batch rematerializes as a set** when the child's zone or bedtime changes.
  See §4.5.

### 9.6 Coordination layer

The boring surface that makes both parents open the app daily.

#### 9.6.1 Medication handoff log

Dosing errors cluster at exchanges. *"Did she get her 8am?"* is a daily,
high-stakes question — acutely so in the very large population of ADHD
households. Both parents log; both parents see; the schema refuses the second
dose. See §5.8 and §6.7.

The collision message names the other parent, the local time, and nothing else.
No blame framing, no notification to the child.

#### 9.6.2 Shared medical record

Allergies, conditions, prescriptions, providers, immunizations, insurance card
images. Guardian-writable, sitter-readable.

#### 9.6.3 Emergency card

**One screen. Offline-capable. Readable by the sitter role.** Allergies, meds,
blood type, both guardians, pediatrician, insurance. Built for a babysitter or an
ER intake nurse, not for browsing. Ships in Phase 1 because it costs almost
nothing and the downside of not having it is unbounded.

#### 9.6.4 School layer

Teacher contacts, grade snapshots, guardian-uploaded IEP/504 documents,
conference scheduling. **Camera and manual entry only — no portal ingestion.**
See §10.6.

#### 9.6.5 Expense ledger

Receipt capture, split rules driven by `custody_order.cost_split`, reimbursement
status, support-payment log. Court-exportable. Phase 3, paid tier.

**Invisible to the child at every depth.** Enforced by RLS (§5.11), not by
navigation. Prohibition P6.

### 9.7 The exchange

The physical handoff is the highest-friction, highest-conflict recurring event in
a separated family's week, and no product in the category has designed for it.

#### 9.7.1 The bag manifest

What went, what came back. Retainer, inhaler, glasses, homework folder, the
specific stuffed animal. `essential` items surface first and produce a
pre-exchange reminder. This sounds trivial and is a top-three daily friction.

#### 9.7.2 Arrival ping

**An event, not a location.** A geofence may fire on-device; coordinates never
leave it and no coordinate column exists (§5.10). The receiving parent gets
"arrived." Prohibition P3.

#### 9.7.3 Running late

One tap, an ETA, immutably logged. Pattern-forming, which matters if it ever
reaches a courtroom — and which is precisely why it cannot be edited after the
fact.

#### 9.7.4 Transition warnings for the child

*"Dad's week starts in 3 sleeps."* Computed on her local day boundaries. Doubles
as the neurodivergent transition support in §8.4.

### 9.8 The archive

Everything else in this document is transactional. The archive is what a family
*has* after four years — hundreds of goodnight videos, homework photos, drawings,
first-day clips. **It is more valuable than any single feature, and the Phase 0
retention schedule would otherwise delete most of it.**

#### 9.8.1 Preservation

Every `media_artifact` is either on a retention clock or explicitly preserved by
a named guardian (§5.6). Guardians elect preservation per-artifact or by standing
rule (e.g. "preserve all video messages"). Preserved artifacts move to
cold storage; the retention terminus becomes §9.8.4 rather than a timer.

#### 9.8.2 The Year Book

Auto-compiled annually from preserved artifacts: best moments, growth,
homework progression, drawings, a map of where she was each season. Printable
and fulfilled through a print partner.

One feature, three jobs — a revenue line, a retention hook, and the emotional
payoff that makes the preceding year of small interactions feel cumulative.

#### 9.8.3 "On this day"

Opt-in. Never on by default. Per-era mute (`media_artifact.era_tag`) so a family
can suppress pre-separation material without deleting it. Prohibition P9.

Resurfacing is powerful and dangerous in exactly this population: a memory from
before the split can wound, and the product chose the moment.

#### 9.8.4 The majority handover

At the child's age of majority (state-governed, `child.majority_age`):

1. Archive ownership transfers to the young adult.
2. A full portable export is generated and delivered to them.
3. **Guardian read access ends** unless the young adult explicitly grants it.
4. `child.handed_over_at` is set. The transition is irreversible.

This reframes the product from "co-parenting utility" to *"we kept this for you."*
It is also the cleanest possible answer to a regulator asking what the retention
terminus is: the data is returned to the data subject at majority. See §10.7.

### 9.9 Child agency

Every interaction specified before v0.3.0 was parent-initiated or shared. That
was a real gap: a child with no initiative is a subject, which contradicts §1.

#### 9.9.1 "Call me when you can"

A child-initiated ping that respects the recipient's day-parts and rate-limits
itself to three per parent per child-local day. Over the limit, it is **silently
absorbed** — a child is never told they have used up contact with their parent.
See §6.6.

#### 9.9.2 The private journal

Text and media, visible to the child alone. No guardian route, no escalation
path, no admin override, at any privacy tier. Prohibition P7.

This is what makes the graduated-privacy tier credible to a fifteen-year-old
rather than insulting.

#### 9.9.3 "Teach me something"

A session module with the roles inverted — the child teaches, the parent learns.
Genuinely different relational texture from every other activity in the product.

#### 9.9.4 Rituals

Standing, recurring, named: Sunday pancakes call, Wednesday chess move. Attached
to a day-part, not a clock. **Never scored, never streaked.** Prohibition P2.

### 9.10 Together activities

Additional session modules, all riding §3.1 with no new architecture:

- **Co-listen** — synchronized playback, shared queue
- **Cook-along** — same recipe, both kitchens, step-locked
- **Watch-together** — synchronized playback with a shared pause
- **Read-together** — the storybook module, either party narrating

---

## §10 Compliance — United States

### 10.1 Federal

The amended COPPA Rule has been in full effect since **22 April 2026**, with
active enforcement exposure for incomplete compliance programs.

- Personal information now covers **biometric identifiers** (voiceprints, face
  templates), **audio recordings**, and geolocation. Since the product is built
  on audio and video of children, effectively the **entire payload is regulated
  PI**. This is also an independent argument for P1 and P3.
- **Indefinite retention is banned.** Penalties reach roughly **$51,744 per
  incident per day**. Hence `delivery_intent.expires_at NOT NULL` and the
  `retention_or_preserved` CHECK in §5.6.
- **Separate verifiable parental consent** required for third-party disclosure —
  permanently constrains analytics and crash-reporting SDK choices.
- **Written information security policy** is mandatory.
- Collecting children's data for **AI training is never** part of providing the
  service. Prohibition P5.

**Retention schedule** (per payload kind, default when `preserved = false`):

| Kind | Retention |
|---|---|
| Game turn state | 90 days after game end |
| Video / voice message | 30 days after open, 90 days if unopened |
| **Banked batch payload** | preserved by default; 1 year if released |
| Homework image + OCR | 1 school year, guardian-extendable |
| Time capsule | until delivery + 30 days |
| Call recording | opt-in only, 7 days default |
| Medication event | 3 years (medical record) |
| Exchange / bag manifest | 2 years |
| Expense + receipt | 7 years (court tier) |
| Parent↔parent log | 7 years, tamper-evident |
| **Preserved artifact** | until majority handover (§9.8.4) |
| Child journal | until majority handover; transfers with the archive |

### 10.2 Dual-guardian consent

Two legal guardians may both need to consent and may disagree. Build a **consent
state machine**, not a boolean. Handle: one guardian restricted by protective
order, guardianship changing mid-year, consent revoked by one party.

Preservation elections (§9.8.1) require **either** guardian, not both —
preserving material is not a privacy expansion, and requiring consensus would
mean conflict destroys the archive.

### 10.3 App store age verification

Texas's App Store Accountability Act took effect **1 January 2026** after the
Fifth Circuit stayed the preliminary injunction; expect it to remain in force.
Texas, Utah, Louisiana, and California have all passed app-store
age-verification laws.

- **Integrate the platform age-signal APIs.** Do not build a bespoke age gate.
- Data received from app stores may be used **only** to enforce age restrictions
  and safety defaults, and **must be deleted once verification completes**.

### 10.4 State design codes

California's AADC became **partially enforceable** following the Ninth Circuit
opinion of **12 March 2026**: covered services likely to be accessed by under-18s
must estimate age or apply child-level protections to everyone, and may not reuse
age-estimation data. Texas SCOPE Act (HB 18) uses an under-18 threshold, as does
Vermont's AADC effective 1 January 2027.

**Decision: apply the strictest standard universally.** The product is
unambiguously child-directed; geo-branching compliance is more expensive and more
fragile than a single high floor.

### 10.5 Recording consent

Roughly a dozen states require all-party consent, and **a minor cannot legally
consent regardless**. Default off. Per-clip opt-in. Visible indicator to every
participant. Texas and North Carolina are both one-party states — irrelevant when
a child is the other party.

### 10.6 FERPA

Live **only** if the school layer ingests from a school portal rather than
guardian upload. **Keep §9.6.4 on camera and manual entry** to stay out of scope.

### 10.7 The majority handover as retention terminus

§9.8.4 is a compliance asset, not only a product feature. "Preserved indefinitely"
is indefensible under the amended Rule. "Held in custodianship and returned to
the data subject at the age of majority, at which point operator retention ends
unless the adult data subject elects otherwise" is a clean, defensible answer,
and it happens to be the emotionally correct one.

### 10.8 SMS bridge

The §8.4 bridge carries child-related content over an unencrypted carrier
channel. Constraints: text summaries and notifications only — **never media,
never the journal, never the emergency card**. Explicit separate consent at
enrollment. Documented in the security policy required by §10.1.

---

## §11 Technology stack

| Layer | Choice | Rationale |
|---|---|---|
| Client | **Flutter** (+ Flame for games) | One codebase across Android / Windows / iOS / macOS / Web. Real desktop support. Strong for custom-drawn annotation and game surfaces. |
| Realtime media | **LiveKit** | Open source, WebRTC, SDKs for Flutter/RN/Swift/Android. Self-host or cloud. Start on Cloud; move self-hosted when residency demands. |
| Backend | **NestJS (TypeScript)**, Turborepo monorepo | Shared Zod schemas and types between client and server |
| Database | **PostgreSQL 16** | RLS maps cleanly onto family-scoped isolation — and onto P6/P7 enforcement |
| Cache / queue | **Redis** | Presence, delivery queue, rate limits, ping governor |
| Object store | S3-compatible, hot + cold tiers | Short-TTL signed URLs; cold tier for preserved artifacts |
| OCR | **ML Kit on-device** | Free, offline, photo never leaves device |
| Captions | On-device STT first, cloud fallback | §8.4; also produces `caption_key` sidecars for async artifacts |
| Translation | Cloud, per-session, not retained | Bilingual families; transcript retained only under §10.1 schedule |
| SMS bridge | Twilio or Bandwidth | §8.4, §10.8 |
| Print fulfilment | Third-party API | Year Book (§9.8.2); separate consent for address disclosure per §10.1 |
| Time | **Luxon** → `Temporal` | Never hand-roll offsets |
| Auth | Passkeys / WebAuthn (parents); device-bound token + PIN (children) | Children should not need email addresses |
| Push | FCM + APNs with **CallKit / Android full-screen intent** | A call from Dad arriving as a silent notification is a broken product |

> **Push delivery, server side, real as of v0.47.0.** `db/migrations/
> 0012_push_device_token.sql` (`device_token`, dual owner — a child's own
> tablet is a push target too, not only a guardian's phone — real RLS,
> ENABLE+FORCE); `packages/transport/src/fcm.ts` (real FCM v1 HTTP sender,
> real OAuth2 self-signed-JWT-bearer flow via `node:crypto`); `packages/
> transport/src/apns.ts` (real APNs HTTP/2 sender, real ES256
> provider-token JWT); `packages/transport/src/notify.ts`'s
> `notifyDevices()` (looks up a target's devices, runs `buildPush()` then
> `sendGuard()` — see `push.ts`'s own header for why that is non-negotiable
> — before either sender, per-device try/catch so one failure never aborts
> another). `push.ts` itself (`buildPush`/`auditPush`/`sendGuard`/
> `GENERIC`/`FORBIDDEN_DATA_KEYS`) is untouched — this is new code on top of
> that existing, already-tested contract.
>
> **Never run against a live FCM or APNs endpoint** — no
> `FCM_SERVICE_ACCOUNT_JSON` or `APNS_KEY_P8`/`APNS_KEY_ID`/`APNS_TEAM_ID`/
> `APNS_TOPIC` exists in this environment; every claim about request shape
> and JWT-signature correctness is proven against a mocked transport (see
> `packages/transport/test/fcm.test.mjs`, `apns.test.mjs`). **Not wired to
> any real trigger** — the live route surface on `main` at the time this was
> built is essentially auth routes plus a couple of GETs, with nothing that
> writes a message/call/reminder for `notifyDevices()` to hang off; this
> ships `notifyDevices()` itself plus real `POST`/`DELETE
> /v1/me/device-tokens` registration routes rather than a fabricated trigger
> route. Client-side device registration is a separate, not-yet-done pass.
> See CHANGELOG v0.47.0 for the full account, including a real RLS defect
> (Postgres's UPDATE/DELETE policies do not substitute for a SELECT policy)
> caught only by testing against a live database.

> **Push delivery, client side, real as of v0.48.0.** `client/lib/
> push_channel.dart`'s `PushChannel` — real `FirebaseMessaging.instance.
> requestPermission()`, real `getToken()` + registration against `POST
> /v1/me/device-tokens`, real re-registration on every `onTokenRefresh`
> event (a token can rotate at any time, not only at first launch). A real
> top-level `firebaseMessagingBackgroundHandler`, `@pragma('vm:entry-point')`
> annotated and independently calling `Firebase.initializeApp()` (a
> background isolate shares no state with the main isolate) — proven to
> actually BE top-level (not a closure, the well-known Flutter/Firebase
> pitfall that compiles fine and then silently never fires in the
> background) via a `const` function-reference assignment, which only a
> top-level/static function tear-off can satisfy. Both the background and
> foreground handlers read ONLY `kind`/`ref`/`callHandle` out of a message —
> `PushPointer` structurally has no field `message.notification` text or any
> other payload key could occupy, so there is no call site in this client
> that could surface real content even by accident. Wired into
> `child_home_live.dart`, the one place a real authenticated session already
> exists in this client (mirrors how `_syncWear()` already piggybacks on the
> same token) — push registration failing (which it does, honestly, absent
> real Firebase config) never breaks that screen's own readiness.
>
> **Never run against a real device** — no Firebase project config
> (`google-services.json`/`GoogleService-Info.plist`) exists in this
> environment, neither fabricated (see `pubspec.yaml`'s own comment on why a
> fake one would be worse than none — it would fail confusingly deep inside
> the Firebase SDK instead of loudly at `Firebase.initializeApp()`). No
> `ios/` platform folder exists in this client at all (Android and Windows
> are its only two real build targets), so `firebase_messaging`'s iOS path
> is real, compiled, unexercised code, same as any platform this client does
> not yet build for. No sign-out flow exists anywhere in `lib/`, so
> `PushChannel.unregister()` (symmetric with the server's `DELETE
> /v1/me/device-tokens`) is written and unit-tested but has no real call
> site yet. See CHANGELOG v0.48.0 for the full account.
>
> **Sign-out flow added v0.49.49.** `guardian_more.dart` gains a real
> `_signOut()` method and a "Sign out" `HubTile` in its Preferences
> section — the first real call site `PushChannel.unregister()` has ever
> had. Deliberately best-effort: the unregister call (when a live session
> is threaded in at all) is wrapped in its own try/catch, matching
> `_endRealCall()`'s own established "never let a bookkeeping failure trap
> the guardian on the screen" posture, since this app persists no session
> token to clear — there is nothing else sign-out needs to do beyond that
> one push-unregister call and leaving the screen. Navigation is
> `Navigator.of(context).popUntil((route) => route.isFirst)` rather than a
> hardcoded destination, deliberately: `main.dart`'s offline demo build
> roots at `EntryGate` (a real "return to start"), while
> `main_live_guardian.dart` (the live build) boots directly into
> `GuardianMoreScreen` itself, making this a harmless no-op there without
> `GuardianMoreScreen` needing to know or care which build it's running
> in. Proven in `guardian_more_test.dart`'s new "Sign out" group: tapping
> the tile with no live session returns cleanly with no network call
> attempted; tapping it WITH a live session still returns cleanly even
> though the real unregister call genuinely throws in the widget-test
> sandbox (no Firebase app initialized) — proving the resilience contract
> holds, not merely the wire-level DELETE call, which would need a new
> dependency-injection seam on `GuardianMoreScreen` to observe directly
> and was judged out of scope for this pass.

> **Hardening pass, v0.48.1.** Three independent adversarial reviews of the
> above, already-shipped feature. Fixed: `PushPointer.fromData`'s unguarded
> casts (a non-String `kind`/`ref`/`callHandle` — possible from an
> unconstrained APNs custom-data payload — threw instead of degrading, which
> for `call_incoming` meant a malformed call push crashed the handler
> instead of ringing); `apns.ts`'s `sendApns()` leaking an open HTTP/2
> session on both its error paths (only the clean path called
> `session.close()`); `fcm.ts`'s `mintAccessToken()` letting concurrent
> `sendFcm()` calls each mint a redundant OAuth token (fixed with an
> in-flight-promise join). Re-traced the authorization surface independently
> of the review and found no bypass (`registerDeviceToken`/
> `unregisterDeviceToken` take the principal only from the verified session;
> `deviceTokensFor()` has no route reachable from any client-facing role).
> The dedupe-by-token reattribution behavior and the client's missing
> sign-out flow were both reviewed and left as-is — already documented
> design and an already-disclosed gap, respectively, not bugs in this diff.
> See CHANGELOG v0.48.1 for the full account, including two DB-dependent
> test suites (`device_token.test.mjs`, `notify.test.mjs`) that could not be
> re-run because no live Postgres was reachable in that session's sandbox.

> **§8.11.4 channel awareness wired in, v0.49.11.** `POST /v1/me/
> device-tokens` gains an OPTIONAL `channel` field (validated against
> `devices.ts`'s own `CHANNELS`, `db/migrations/0015`'s new nullable
> `device_token.channel` column) — omitted entirely when the client doesn't
> know its real §8.11.4 channel, never a guessed value written to storage.
> `notifyDevices()` (`notify.ts`) now calls `admitDevice()` per device before
> attempting a send, skipping (not silently firing FCM/APNs at) a device
> resolved to a push-incapable channel — closing this codebase's own
> top-ranked prior-audit finding, the exact "constructed, dispatched, and
> silently discarded" failure `devices.ts`'s header names for a FireOS
> tablet. `push_channel.dart` reports the one channel it can currently know
> for certain (`'ios'`); no Android build yet distinguishes Play/Amazon/bare
> Android — closing that needs a real native `PackageManager`/
> `GoogleApiAvailability` bridge, scoped and explicitly deferred this pass
> for the same reason `LOCK_METHODS` wiring was deferred (see `devices.ts`'s
> own §8.11.4 header for the exact APIs and the cross-reference). Also fixed
> in the same pass: `devices.ts`'s `CHANNELS`/`admitDevice()`/
> `channelAdvice()` and `channels.ts`'s `route()`/`reachability()` had
> quietly become two independent, drifted copies of the same channel facts —
> `channels.ts`'s `route()` could escalate a `web` device to `sms_to_adult`
> even though `devices.ts` has never declared `web` SMS-eligible.
> `channels.ts` now imports its facts from `devices.ts` rather than
> re-declaring them, and gained its own dedicated test file
> (`channels.test.mjs`) — it had zero coverage in its own package before
> this pass, only transitive exposure via a differently-named test suite in
> a different package. See CHANGELOG v0.49.11 for the full account.

> **§16.2 #6, settled v0.40.0.** Stay on LiveKit Cloud. Self-hosting is
> revisited only when either trigger fires — not on a vague "when residency
> demands," which was never a real trigger:
>
> - **Usage threshold:** 500 concurrently active families, or
> - **Compliance trigger:** any institutional or court-mandated deployment that
>   explicitly requires data-residency guarantees a managed cloud cannot make.
>
> **Why Cloud, not self-host, right now.** A self-hosted SFU/TURN cluster is a
> real, ongoing operational burden — on-call, patching, NAT-traversal edge
> cases — for a small team building a product where "the call didn't connect"
> is close to the worst possible failure. A well-run managed service's uptime
> in year one is very likely better than a small team's own cluster, not worse.
> Cost inverts at scale, but at today's scale the fixed cost of self-hosting is
> the harder problem to justify.
>
> **The real cost of staying on Cloud is COPPA sub-processor disclosure** — the
> amended COPPA Rule (§10.1, in effect since April 2026) requires disclosing
> LiveKit as a third-party recipient of a minor's live video, with a proper
> DPA. That is the one genuine functional cost of this choice, and it is
> solvable with proper paperwork rather than infrastructure.

> **§16.2 #6, REVERSED, unreleased (post-v0.42.0).** The above is superseded.
> Olive moves off LiveKit onto **Jitsi Meet + Jitsi Videobridge** as the core
> basis for all calls, video calls, screen-sharing, and streaming — at the
> owner's direction, not because LiveKit failed technically. The v0.40.0
> reasoning above (managed-service uptime beats a small team's own cluster at
> today's scale) is not what changed; the *choice of vendor* did, and the
> operational-burden tradeoff it describes now applies to Jitsi Videobridge
> instead of LiveKit's SFU. This entry is left in place rather than deleted so
> the reversal is visible rather than gradual, matching the standing practice
> §21.7 established for exactly this situation.
>
> **Current state, staged in two steps, deliberately:**
>
> - **Step 1 (in progress).** Prove the calling UX end to end against Jitsi's
>   public `meet.jit.si` server via the official `jitsi_meet_flutter_sdk`, so
>   the client integration is validated on real hardware before any
>   self-hosting work starts. No SFU is self-hosted yet at this step — calls
>   run on Jitsi's shared public infrastructure, which is **not** an
>   acceptable posture for a real family's call metadata or media long-term.
> - **Step 2 (staged, container-level verified, unreleased).** Self-host the
>   full stack — Prosody, Jicofo, and Jitsi Videobridge, via
>   `docker-jitsi-meet` — so the same COPPA sub-processor and
>   data-residency reasoning above applies to a server Olive operates, not a
>   third party's. `scaffold/tools/jitsi-selfhost/` stands the stack up
>   locally (pinned `stable-11146-1`), gitignored/vendored rather than
>   committed, matching how `local-call-room-server.mjs` already stands in
>   for the production API. Actually bringing it up — not just writing the
>   compose config — surfaced three real bugs, now fixed and documented in
>   that directory's README: a Docker Desktop containerd-snapshotter bug
>   that corrupts these images' user resolution, a JVB port collision with
>   `server/index.mjs`, and a Windows bind-mount permissions bug that
>   silently broke Prosody's own TLS cert generation (masquerading as a
>   Jicofo/JVB connection failure, not obviously a Prosody problem). Once
>   healthy, Prosody's live-rendered config was read directly to confirm
>   `authentication = "jitsi-anonymous"` with no forced-lobby or
>   auth-gated-moderator setting — the actual mechanism, not just the
>   compose file, that avoids the meet.jit.si finding below.
>
> **The self-signed-cert gap, fixed (v0.49.28) at the TLS layer, still not
> device-proven.** Turned out to be two independent problems, not one:
> docker-jitsi-meet's own generated cert is untrusted (expected for
> self-signed) *and* has zero X.509v3 extensions — confirmed via `openssl
> x509 -noout -ext subjectAltName` returning "No extensions in
> certificate" — so even a device told to fully trust its issuer would
> still fail on hostname-mismatch grounds, since nothing in the cert
> asserts it's valid for anything. `generate-dev-cert.sh` replaces it with
> one carrying `subjectAltName=IP:127.0.0.1,DNS:localhost`, written to
> docker-jitsi-meet's own documented operator-override path rather than
> fought through nginx config directly, with the public half committed to
> `client/android/app/src/main/res/raw/` and a matching
> `<trust-anchors>` entry in `network_security_config.xml`. Verified via
> `openssl s_client` that the corrected cert is actually served, not just
> generated. **Not verified:** whether Android's trust-anchor mechanism
> resolves this on a real device — this session's own browser tool runs in
> an isolated context that doesn't consult the Windows cert store, so
> importing the cert there and re-testing couldn't confirm or refute it
> either. Physical two-device re-verification is still what closes this,
> and no session so far has had hardware access to do it.
>
> **What this reopens.** The COPPA sub-processor disclosure above must name
> whichever party is running the videobridge at each step (a public
> `meet.jit.si` deployment operated by 8x8/Jitsi during Step 1; nobody, once
> Step 2 lands). `packages/session-runtime/src/rooms.ts`'s
> `Grant`/`deriveGrant`/`mintToken` are LiveKit-grant-shaped and are **not**
> deleted — I1 (room name never guessable) and I4 (authorization gate) still
> hold and are reused as-is by `scaffold/tools/local-call-room-server.mjs`;
> only the LiveKit-specific `Grant`/JWT shape stops being the thing consumed
> at the end of the pipe. Whether Jitsi's own JWT auth (`mod_auth_token` via
> Prosody) replaces that shape, or whether room-name secrecy alone remains the
> security boundary, is still the real open decision for a production
> deployment. The local dev stack above makes a provisional, scoped choice —
> anonymous domain, no `ENABLE_AUTH` — precisely so I1/I4 stay the boundary
> and `rooms.ts` doesn't need to change to prove Step 2 out; that is a dev
> convenience, not a resolution of the production question, which still
> blocks anything beyond this local scaffold.
>
> **Step 1, tested end to end on two physical devices, does not work —
> verified rather than trusted from code review.** A guardian tablet and a
> child's Galaxy Z Fold5 were driven through a real call attempt in both
> join orders. Neither completed, for two independent reasons:
>
> - **The child's kiosk lock blocks the call from ever starting, and this is
>   orthogonal to Step 1 vs. Step 2.** `jitsi_meet_flutter_sdk` opens calls in
>   a separate `singleTask` Activity (`WrapperJitsiMeetActivity`); Android's
>   screen-pinning (§5.20, engaged for real on the child side) refuses to
>   launch any second Activity, logging `E/ActivityTaskManager: Attempted
>   Lock Task Mode violation`. `call_screen.dart`'s "Joining…" spinner then
>   waits forever on a callback from an Activity the OS never started.
>   Self-hosting the videobridge will not fix this by itself — the child side
>   needs either a lock-task exit/re-entry around the call, a Device-Owner-
>   level lock-task allowlist naming the Jitsi activity, or the call rendered
>   without a second Activity at all.
> - **The public `meet.jit.si` server puts new/unclaimed rooms in a
>   moderator-approval lobby.** Confirmed via the SDK's own log —
>   `[app:lobby] Lobby starting knocking (membersOnly = ...)` — on the
>   guardian side, which otherwise connected cleanly and captured real
>   camera/mic. The app has no login/moderator flow, so it waits indefinitely
>   for an approval nobody can grant. This is direct evidence *for* Step 2
>   rather than a reason to distrust Jitsi generally — a self-hosted
>   Videobridge under Olive's own Prosody/Jicofo config is not subject to a
>   public instance's anti-abuse lobby default.
>
> Neither device crashed; both degrade to a stuck-but-recoverable state,
> confirmed against a full logcat capture with zero `FATAL EXCEPTION`s from
> the app across the session. Tracked as two separate follow-ups rather than
> one, since fixing the lock-task conflict does not require Step 2 and
> completing Step 2 does not by itself fix the lock-task conflict.

> **Lock-task conflict — fix implemented v0.46.1, NOT yet fully device-verified.**
> Evaluated the three options the previous callout named:
>
> - **Device-Owner lock-task allowlist — ruled out.** Both real test devices
>   (a Tab S9 FE and the Fold5 above) already carry a normal set of Google/
>   system accounts. `dpm set-device-owner` refuses to run against a device
>   with any existing account, short of a factory reset — not a scope
>   question, a hard blocker for an already-provisioned family phone, which
>   is the deployment shape this app targets.
> - **Embed without a second Activity — deferred, not attempted.** Jitsi's
>   Android SDK is React-Native-based, not Flutter; there is no fragment/
>   embedded-view entry point exposed today. Real long-term value, but
>   building a Flutter `PlatformView` bridge into a foreign RN view hierarchy
>   is a substantially larger, higher-risk change than one session should
>   attempt and claim verified.
> - **Exit/re-enter lock task around the call — implemented, refined.** The
>   naive version (unpin, launch, re-pin on pop) was checked against
>   `WrapperJitsiMeetActivity.launch()`'s own `singleTask` semantics and found
>   to leave the **entire call**, not just the transition, unpinned — Android
>   opens that Activity in a new task, so re-pinning the original Activity
>   once it's popped never re-pins the call itself. Built instead as a
>   handoff: `KioskBridge.kt`'s new `beginCallHandoff` unpins the main
>   Activity and flags the coming `onStop()` as intentional (so the existing
>   defeat-detector in `MainActivity.kt` doesn't misreport it as a kiosk
>   defeat); the patched `WrapperJitsiMeetActivity.kt`
>   (`third_party/jitsi_meet_flutter_sdk_patched`) self-pins for the call's
>   duration and reports its own mid-call defeat (Back+Recents during the
>   call) back through the same `lockTaskExited` event path a defeat outside
>   a call already uses — no new Dart-side state machine, no new escape
>   route introduced by adding calling capability. The two Activities live in
>   separate Gradle modules with no compile-time reference path between
>   them, so the handoff is coordinated through a plain SharedPreferences
>   flag and a `LocalBroadcastManager` action (string-mirrored across files,
>   the same convention already used for the MethodChannel/EventChannel
>   names).
>
> **Confirmed:** `flutter analyze` clean, all 1239 widget tests pass, the
> full Gradle/Kotlin build succeeds across both modules (surfaced one real
> gap: `androidx.localbroadcastmanager` wasn't on the app module's compile
> classpath — the app module depends on the Jitsi plugin module, and Flutter
> wires plugin modules in as `implementation`, which doesn't expose a
> dependency's own transitive deps to the consuming module; fixed with an
> explicit line in `android/app/build.gradle.kts`). Reinstalled on the real
> Fold5 and confirmed, via the OS's own "App is pinned" dialog and
> `dumpsys activity activities` reporting `mLockTaskModeState=PINNED`, that
> screen-pinning still engages correctly under the changed `MainActivity.kt`.
>
> **NOT yet confirmed:** whether `WrapperJitsiMeetActivity` actually launches
> under the handoff without the lock-task violation, and whether the pin
> visibly survives the Activity swap. The live two-device session hit a real
> collision — a concurrent session was mid-edit on this same repo (Step 2
> self-hosting work: `tools/jitsi-selfhost/`, `with-jitsi.sh`) and, per
> logcat, reinstalled the app on the same physical Fold5 mid-test,
> killing the run before the call attempt completed. Recorded here rather
> than silently claimed working, per this document's own standing rule
> against declaring something verified when it was only reasoned about —
> see `client/docs/MANUAL_VERIFY_call_lock_task.md` for the exact procedure
> to finish this once the devices are free. Written as a standalone manual
> procedure rather than only a test on purpose: this failure mode produces
> no crash and no visible error, so it is easy to silently reintroduce and
> a CI-green build would not catch it.

> **§16.2 #6, REVERSED AGAIN, unreleased (v0.49.57).** The Jitsi entry above
> is superseded. Olive moves back onto **LiveKit Cloud** — the v0.40.0
> choice — as the core basis for calls, at the owner's own direction after
> this session's own hands-on cost standing up `tools/jitsi-selfhost/`:
> Docker Desktop containerd-snapshotter crash-loops, manual TLS cert SAN
> generation to fix a self-signed cert with zero X.509v3 extensions, and a
> Windows Firewall rule needing admin elevation — real, paid-for operational
> friction, not a hypothetical one, for a single self-hosted JVB instance
> that still could not clear its own moderator-lobby finding on the public
> fallback it depended on during Step 1. Matching §21.7's own standing
> practice, neither the v0.40.0 nor the Jitsi entry above is deleted — the
> two reversals stay visible, not silently smoothed over. The kiosk
> lock-task handoff work (`KioskBridge.kt`'s `beginCallHandoff`,
> `third_party/jitsi_meet_flutter_sdk_patched/`) is disclosed, not deleted,
> for the identical reason §21.7 names: it was real, tested engineering
> against a real problem (Jitsi's `singleTask` second-Activity conflict with
> §5.20 screen-pinning) that this reversal makes moot, not wrong.
>
> **Why the reversal holds up against the SAME v0.40.0 reasoning that once
> favored Jitsi.** The Step 1/Step 2 staging this document used to justify
> Jitsi never actually removed the operational-burden problem v0.40.0
> already weighed — it relocated it from LiveKit's SFU onto Jitsi
> Videobridge, Prosody, and Jicofo, three services instead of one, each with
> its own upgrade cadence and failure mode. LiveKit Cloud's real global edge
> network is exactly the "well-run managed service" advantage v0.40.0's own
> uptime argument described; a single self-hosted JVB instance run by a
> small team is the structural quality/distance ceiling that argument
> warned against, now confirmed hands-on rather than theoretical. The
> COPPA sub-processor disclosure obligation v0.40.0 named as the real cost
> of Cloud returns unchanged — LiveKit, not Jitsi/8x8, is once again the
> third party to name in the DPA.
>
> **What carries over unmodified.** `packages/session-runtime/src/rooms.ts`'s
> `Grant`/`deriveGrant`/`mintToken` turn out to already be byte-for-byte
> LiveKit's own `VideoGrant` shape (confirmed by reading
> `livekit-server-sdk`'s own `grants.d.ts` directly, not assumed) — the
> Jitsi entry above already anticipated this exact possibility ("whether
> room-name secrecy alone remains the security boundary… still the real
> open decision"), and it resolved in LiveKit's favor: I1 (unguessable room
> names) and I4 (the real `can('call', …)` authorization gate) needed zero
> logic changes, only a new serialization step
> (`packages/session-runtime/src/livekit-token.ts`'s `mintLiveKitToken`,
> pure JWT signing, not a new authorization decision) turning `mintToken`'s
> existing output into a real, signed LiveKit access token.
>
> **The one genuine, previously-unaccounted-for gap this reversal
> surfaced.** Jitsi let a callee join with nothing more than a bare room
> name; LiveKit requires a real, signed, per-identity token to join at all
> — a callee answering a knock never had one for a call someone else
> started. Closed with a new, real route,
> `POST /v1/children/:childId/calls/:sessionId/join`
> (`server/routes.mjs`), gated by the same real `mintToken()` I4 check
> every other mint in this codebase already uses — not a shortcut, a second
> real authorization decision for the second real participant.
> `call_knock_screen.dart`'s real Answer button now makes a real second
> round-trip through it before joining, a genuine behavior change from the
> Jitsi build worth naming plainly rather than silently absorbing.
>
> **Two real improvements folded into the same pass, both scoped to calls
> only but architected for the screen-share/streaming work already staged
> in §16.2's own roadmap:** real live call-quality signal (LiveKit's own
> `ParticipantConnectionQualityUpdatedEvent`, polled on a 250ms ticker
> since it only fires on change, feeding the pre-existing, unmodified
> `degradation_banner.dart` hysteresis state machine — no new UI, no new
> thresholds, just a real signal where a fake one would have gone
> undetected) and a scoped design for real supervised-call recording via
> LiveKit Egress to S3
> (`docs/superpowers/specs/2026-08-29-supervised-call-recording-design.md`,
> depends on this migration, not yet implemented).
>
> **Verified so far, server-side and client-side, all live against a real
> Postgres and real (compiled, not hand-inspected) code — NOT yet verified
> against a real LiveKit Cloud project or real hardware.** 82 session-runtime
> assertions (real JWT shape, I2 forbidden grants absent on the wire, a real
> I5 TTL check against the SDK's actual `nbf`/`exp` claims — it does not
> emit `iat`, found by decoding a real minted token rather than assuming).
> 50 server route assertions, including the join route's own real
> authorization boundary: an uninvited guardian with a real edge on the
> same child is refused with a real `not_a_participant`, not merely
> untested. A self-caught, real identity-impersonation bug in this
> session's own earlier dev-test scaffolding (`main_live_child_call_test
> .dart`/`main_live_dad_answer_test.dart`'s own room-bridging helpers were
> bridging the CALLER's own identity-bound token to the RECEIVER's poll
> slot — since a LiveKit token carries a `sub` claim, the receiver would
> have joined AS the caller) was found and fixed before being carried
> forward, not after. 2020 Dart widget/unit tests, `flutter analyze` clean.
> A real, upstream `livekit_client` SDK gap — `Room()`'s internal `TTLMap`
> cleanup timer has no `dispose()`/`cancel()` anywhere in the SDK — was
> root-caused (not worked around blind) by reading the SDK's own
> `ttl_map.dart` source, and fixed at the production-code level by
> constructing `Room` lazily, only right before `connect()`.
>
> **What blocks calling this reversal done.** Every check above ran against
> compiled code, a real database, and a real JWT decoder — none of it has
> touched a real LiveKit Cloud project or a real device, because no
> `LIVEKIT_URL`/`LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET` has been supplied to
> any session yet. `third_party/jitsi_meet_flutter_sdk_patched/` and the
> kiosk-handoff code it exists for are deliberately NOT deleted until that
> device verification succeeds — the same "verified rather than trusted
> from code review" discipline the Jitsi entry above established for
> itself, applied to its own reversal.

---

## §11.5 The school layer — no system integration

**Written v0.40.0, closing a reference gap that predated it.** `school.ts` had
carried this section number in its own header comment since v0.3.0 without the
section ever being written here — a small declaration-without-implementation
gap, the same category this project's own audits exist to catch, just one that
had gone unnoticed until settling §16.2 #8 required leaning on it directly.

**The decision: Olive does not integrate with school systems.** No SIS
connector, no gradebook sync, no attendance feed. Three reasons, the third
deciding it:

1. **There is no standard.** Thousands of districts, half a dozen incompatible
   platforms — an integration built for one is a rewrite for the next.
2. **It is FERPA-adjacent**, and a consumer app touching an education record
   takes on an obligation it is poorly placed to carry.
3. **A gradebook feed would put a child's marks in front of a parent she did
   not choose to tell.** That inverts §9.1's entire posture — homework help is
   something she brings, not something served to him.

What IS built is the small, honest version: dates a parent types in (§9's
school-event calendar entries), and a shared place for the paper that comes
home in a bag. Nothing here reads or writes any external education record.

This is also the precedent §16.2 #8 (curriculum-standard tagging, §19) leans on
directly — grade-level tagging of a homework problem is the same risk in
different clothes.

---

## §12 Roadmap

**This table is the ORIGINAL pre-build planning snapshot, not a live status board** — unlike §16.2's and §20.2b's tables, it was never maintained with strikethrough/CLOSED annotations as items shipped, so most rows below now understate what's real (nearly everything through Phase 3, and several Phase 4 items, has since shipped — see §16.2's own decision table and §20.2b's tracking table for current, maintained status). One specific correction, flagged by a 2026-08-30 doc-parity pass: **majority handover** below reads as unbuilt Phase 4 "Reach" work; it has been real since **v0.49.16** (`POST /v1/children/:childId/handover`, `takeAndGo()` in `pool.ts`, `take_and_go_screen.dart` — see §9.8.4/§10.7 and CHANGELOG v0.49.16). Left un-rewritten wholesale rather than re-auditing all ~25 items in this table against current status, which is a larger pass than this correction scoped for.

| Phase | Scope | Notes |
|---|---|---|
| **0** (8–10 wks) | Family graph · roles · child lock · 1:1 audio/video · async video messages on the full delivery-intent engine · **time engine** · **`media_artifact` with `preserved` + the retention CHECK** · **single-guardian mode (§17.1)** · **`sibling_link` + `guardianship.closed_at` schema** | Three items ship as schema-only ahead of their features: the archive columns (§12.1), sibling links (§5.14), and edge closure (§18.1). All three are cheap now and migrations-with-backfill later. |
| **1** | Homework capture + annotation · child-view calendar · **message banking (§9.5)** · **emergency card (§9.6.3)** · **"call me when you can" (§9.9.1)** · captions | Banking and ping are near-free on the Phase 0 engine and carry the most emotional weight |
| **2** | Three turn-based games · wants/needs · **medication log** · **medical record** · **bag manifest + arrival ping** · private journal · rituals · visual schedule strip | The daily-habit phase |
| **3** | Custody schedule engine · tamper-evident log · **expense ledger** · **coordinator/GAL role** · school layer · court-export PDF · **Year Book** | The paid and institutional tier |
| **4** | iOS · realtime co-op games · together activities · SMS bridge · translation · ~~majority handover~~ **majority handover — CLOSED v0.49.16** | Reach |

### 12.1 The one early dependency

If Phase 0 ships a retention schedule that deletes video messages at 90 days with
no archival tier, **the Year Book cannot be built later** — the material will
already be gone. `media_artifact.preserved`, `preserved_by`, and the
`retention_or_preserved` CHECK must land in the Phase 0 migration even though
§9.8.2 is two years out.

This is the only item in the roadmap where the schema and the feature are
separated by more than one phase, and it is deliberate.

---

## §13 Metrics

North star is **relationship continuity**, measured directly. Not DAU.

| Metric | Definition |
|---|---|
| **Gap coverage** | % of child-local days with ≥1 touchpoint from the away parent |
| Connection events | per child, per week |
| Homework sessions completed together | count |
| Contact streak | consecutive weeks, child-local boundaries |
| Async ratio | async touchpoints ÷ total — expected to exceed 3:1 |
| Batch coverage | % of a known-absence window covered by banked messages |
| Dose collisions prevented | count of 409s on §7.7 — a direct harm-avoided metric |
| Archive depth | preserved artifacts per child-year |

All day-boundary metrics compute on **child-local calendar days**. A parent's
11:30 p.m. CT message lands 12:30 a.m. ET — that is tomorrow for her.

**None of these are ever shown to a child.** Prohibition P2.

---

## §14 Business model

| Tier | Contents |
|---|---|
| Free | 1 child · unlimited calls · basic games · calendar · emergency card |
| **Family** ($9.99–14.99/mo, **per family**) | Homework archive · message banking · medication log · bag manifest · archive preservation · extended games · multiple children · trusted adults |
| **Court** (+$X) | Tamper-evident log · expense ledger · custody engine · coordinator/GAL seat · court-export PDF |
| Year Book | Per-edition print, à la carte |
| Institutional | Military family orgs, supervised-visitation providers, hospital child-life services, reentry programs |

**One price per family is a direct competitive attack.** Per-parent pricing is
the incumbents' most-criticized weakness, because one parent is often unwilling
to pay at all — which blocks adoption for both.

Getting named on a court's approved-tools list is worth more than any ad spend.

---

## §15 Safety

- Invite-only family graph. No search, no discovery, no public profiles.
- **Supervised mode** for court-ordered supervised visitation — a real, funded
  market segment.
- Moderation on any free-text between a child and a non-guardian adult.
- Block paths, safety contact, escalation route.
- **Sitter and step-parent tokens are time-boxed and revocable** by either
  guardian unilaterally.
- Threat model explicitly includes **a controlling ex using the platform for
  surveillance** and **contact in violation of a court order**. `guardianship`
  can express `restricted` and `supervised`; P3 removes the surveillance surface
  entirely.
- **Child-facing crisis path.** If distress signals appear, the response is
  resources surfaced *to the child* and, where a guardian is safe, a guardian
  alert that names concern without quoting content. Never a readout of the
  journal. See the P7 carveat in §2.1.

---

## §16 Open decisions

### 16.1 Resolved — provisional, reversible before data exists

**#2 Teen privacy tiers — RESOLVED (provisional).** Tiers advance automatically on
birthday and **cannot be reversed downward by a guardian.** Both guardians acting
together may delay one advancement by up to 12 months, once, with a written
reason recorded in the log. The child is told when their tier changes and what it
changes.

| Tier | Ages | Guardians can see |
|---|---|---|
| `transparent` | 0–12 | All activity; full content of exchanges with any non-guardian adult |
| `graduated` | 13–15 | *That* contact occurred, and with whom, for approved contacts. **Not content.** New contacts still require approval. |
| `autonomous` | 16–majority | Approved contact list only. No activity log, no metadata feed. |

Safety moderation runs identically at every tier and is never a parent-facing
readout. The private journal (§9.9.2) is invisible at **every** tier including
`transparent` — P7 has no age exception, because a 9-year-old's diary is a
diary.

**#3 Court export — RESOLVED (provisional).** Split on artifact type, per
principle §2.11:

- **Raw export** — the archive, message history, calendar, medication log, as
  portable files. **Free, all tiers, unlimited, including after cancellation.**
- **Certified export** — tamper-evident, court-formatted, hash-chained, with an
  attestation page. **Court tier**, with **one free certified export per guardian
  per rolling 12 months.**

Rationale: pricing the evidence of your own life behind a paywall is both
ethically indefensible and a reputational liability, and the free annual
certified export covers the genuine single-hearing case. Sustained litigation use
— which is where the real support cost sits — pays.

> **Both halves real as of v0.49.0, certified half hardened v0.49.1 against
> an adversarial review, a real coordinator-lockout bug fixed v0.49.2.**
> `GET /v1/children/:id/export` (§7.9's own already-documented shape) is
> registered once (`server/routes.mjs`), `action: null,
> identityScopedByHandler: true` (not a single coarse action string, as an
> earlier version was — see v0.49.2's own CHANGELOG entry for the real bug
> that shape caused: coordinator holds `'export.certified'` in `ROLE_CAPS`
> but not `'export.raw'`, so gating this route under either one alone
> wrongly denies real callers of the other kind before the handler runs).
> Each kind's own pool function now runs its own independent `can()` check
> for its own real action, and dispatches on `?kind=`, serving both:
>
> **Raw** — backed by `packages/db/src/pool.ts`'s `rawExportBundleFor()`,
> the default when `kind` is `raw` or omitted (matching the original,
> already-shipped client contract). Runs its own `can('export.raw', ...)`
> check as of v0.49.2 (the route no longer does), then re-derives a live
> `guardian` edge a second way in SQL (delivery_intent/media_artifact/
> message_log carry no RLS of their own — see that function's header for
> exactly what closes the gap), a real
> sha256 `bundle_hash`, `was_free: true`. `client/lib/deletion_screen.dart`'s
> "Download raw export" button is wired to it for real: a network round
> trip, a real file on disk, a client-side-verified hash.
>
> **Certified** — `kind=certified`, backed by `certifiedExportBundleFor()`.
> `db/migrations/0013_court_tier_flag.sql` adds the real `app_user.court_tier`
> boolean this decision's own tier gate needed and never had (default false;
> nothing in this codebase can set it true except a manual/admin path —
> there is no payment processor anywhere in this repository, confirmed by
> grep, same honest boundary already drawn for Firebase/APNs/Twilio). Reads
> a child's real, already hash-chained `message_log` (0006), runs it through
> `ledger.ts`'s real `verifyChain()`/`certify()`/`authorizeExport()`
> unmodified. A real denial (`tier_required` / `chain_broken` /
> not-a-guardian) states its exact reason, never a fabricated success or a
> silent failure — `authorizeExport()` itself only ever actually returns
> `tier_required` once the allowance is spent (there is no live path to
> `annual_allowance_used` in the current rule); v0.49.1 fixed a real contract
> bug where `pool.ts`'s own `CertifiedExportDenial` type excluded that value,
> and the message now states both halves of the real reason (allowance spent
> AND court tier required) rather than only one. v0.49.1 also closed a real
> TOCTOU: two concurrent certified-export requests from the SAME guardian
> could each read the annual count before either committed and both walk
> away `was_free: true`, defeating the one-per-rolling-year rule with
> nothing more than two browser tabs — closed with a `SELECT ... FOR UPDATE`
> on the guardian's own `app_user` row, taken before the count query, proven
> by a genuine-concurrency regression test (`court_export.test.mjs` section
> E: 5 simultaneous requests, exactly 1 wins the free credit, the database
> itself agrees). `client/lib/court_export.dart`'s `LiveCourtExportScreen`
> calls it for real, falling back to the original synthetic demo chain only
> when no live backend is configured. See CHANGELOG.md's v0.49.0/v0.49.1/
> v0.49.2 entries for the full test/verification list.
>
> **v0.49.15 dead-wire fix:** two real fields this route had returned since
> v0.49.0 were fetched by `LiveCourtExportScreen` and never surfaced. A
> `chain_broken` denial's real per-entry `faults` (`verifyChain()`'s own
> diagnostics, forwarded by `certifiedExportBundleFor()`) were dropped by
> `api_client.dart`'s decoder before any screen could see them —
> `ApiException` now carries them, and the denied state renders each one. A
> successful export's top-level `bundleHash` (a hash over `{chain,
> attestation}` together — genuinely different from `attestation.bundleHash`,
> which hashes the chain alone) and `exportRecordId` were parsed by nothing
> — both now render in the ready state, gated by the same §8.11.7
> review-width rule as the attestation panel.

### 16.1b Settled

| # | Decision | Settled | Where |
|---|---|---|---|
| 1 | **The name.** Two names, deliberately: **Olive** to a child, **Olive Branch** to an adult. | v0.23.0 | §16.3 |
| 4 | **Ping limit scales with age, then stops existing.** 3/day to 7, 5 to 9, 8 to 12, **none from 13**. | v0.23.0 | §9.9, `PING_BANDS` |
| 5 | **Preservation is a standing rule, not an election** — anything a parent sends is kept. Everything else surfaces in a 14-day expiry digest, guardian-only, one tap to keep. | v0.23.0 | §10.1b, `expiringSoon()` |
| 6 | **Call/video/streaming infrastructure.** LiveKit Cloud (v0.40.0) → **REVERSED**, Jitsi Meet + Jitsi Videobridge (unreleased) → **REVERSED AGAIN**, back to LiveKit Cloud, not yet device-verified. | v0.40.0, reversed unreleased, reversed again v0.49.57 | §16.2 callout above the tech-stack table |

**Cleared, v0.49.44.** A real USPTO/app-store search (not a placeholder) found
no blocking conflict for this product category — one real, disclosed risk (a
live-but-suspended, same-class/different-goods "OLIVE BRANCH" application for
financial SaaS), not a consumer-confusion risk. Kept both names. A licensed
trademark attorney's formal clearance opinion remains the right step before
any actual USPTO filing or wide commercial launch — this was a good-faith
search sufficient to keep building under this name, not a substitute for
that opinion. See this document's own header note and CHANGELOG v0.49.44 for
the full account.

### 16.2 Still open

| # | Decision | Blocking |
|---|---|---|
| ~~1~~ | ~~**Product name.** "Olive Branch" is a codename; needs USPTO and app-store collision clearance.~~ **CLOSED v0.49.44** — see §16.1b/§16.3 for the real search and its one disclosed risk. | ~~Launch~~ |
| ~~4~~ | ~~Ping limit of 3/day — right number, and should it vary by age?~~ **NARROWED, v0.49.57 doc-parity pass** — §16.1b/#4 already settles "should it vary by age?": yes, `PING_BANDS` (3/day under some age, 5, 8, then none from 13). Only found here as an un-struck duplicate, not re-opened as a product question. What's genuinely left, if anything, is narrower than this row's own framing: is `3` specifically (the youngest band's number) still the right figure — never explicitly re-affirmed since v0.23.0. | Phase 1, narrowly |
| ~~5~~ | ~~Preservation default: opt-in per artifact, or standing-rule-on? Interacts with §10.1 retention posture.~~ **SUPERSEDED, v0.49.57 doc-parity pass** — §16.1b/#5 directly answers this exact binary: "Preservation is a standing rule, not an election." Left here as an un-struck duplicate since v0.23.0, not a live open question — struck rather than silently deleted so the correction stays visible per §21.7. | ~~Phase 1~~ |
| 7 | Supervised-visitation go-to-market: direct, or via existing providers? | Phase 3 |
| 9 | Majority age by state, and a child who turns 18 mid-custody-order. | Phase 4 |
| 11 | Does the therapist role see the contact ladder only, or session metadata too? | Phase 3 |

---

## §16.3 The name

**Two names, deliberately.**

| Audience | Name | Where it appears |
|---|---|---|
| The child | **Olive** | The child shell, push notifications, SMS, anything she can read |
| Adults | **Olive Branch** | The guardian shell, the invitation, the website, court exports, all documentation |

### Why the split does real work

To a child, **Olive** is a name, a colour, a fruit, a friend. It carries nothing.
She does not know she is using co-parenting software and she should not: §2.4
says the child never sees the machinery of conflict, and a product called
*Olive Branch* on her home screen would announce every day that something between
her parents needed repairing.

To an adult, **Olive Branch** is unmistakable. It is a peace offering, extended
by one party to another — and that is precisely the emotional register §17.2
spent a whole section trying to construct in the invitation copy. The name does
the work that copy was doing.

That matters most at the hardest moment in the funnel. A reluctant second parent
receives an invitation from an ex-partner. Everything about the framing decides
whether they open it or read it as the opening move in a custody fight. An
invitation from something called *Olive Branch* has said the right thing before a
word of body text is read.

### The rule

**The child never sees the two-word name.** "Branch" implies a thing that was
broken and is being mended, which is adult knowledge about her family. Push
notification titles, SMS prefixes, and every child-facing string use **Olive**
alone — enforced by the existing allowlist audits in `packages/transport` and
`packages/phase3`, which now hold `'Olive'` as the only approved title.

Identifiers take the single word: `app.olive/kiosk`, `olive_client`,
`olive.app`.

### Cleared, v0.49.44

A real USPTO/app-store search — not a placeholder, and not this document
inventing its own clearance — found no blocking conflict for this product's
actual category (family custody coordination). Every established co-parenting
competitor was checked directly; every live "OLIVE BRANCH" USPTO filing found
was either dead or in an unrelated goods class, except one real, disclosed
risk: a live-but-suspended Class 042 application for financial/accounting
SaaS (a wholly different market), a same-class *prosecution* consideration
for any future federal filing, not a consumer-confusion risk, and currently
blocking nothing. **The name is settled, and now cleared by a real
good-faith search — not merely a working decision.** A licensed trademark
attorney's formal clearance opinion remains the right step before any actual
USPTO filing or wide commercial launch; this search does not substitute for
that, and is not claimed to. See this document's own header note and
CHANGELOG v0.49.44 for the complete account.

---

## §10.1b Preservation is a standing rule

**§16.2 #5, settled v0.23.0.** Anything a parent sends is preserved by default.

The alternative — opt-in per artifact — optimises for storage cost at the expense
of the one thing this product exists to protect. **A parent who forgets to tick a
box loses the thing forever**, and no amount of later regret recovers it. That
asymmetry decides it: the cost of over-keeping is measured in pennies, and the
cost of under-keeping is measured in a message from a father who has since died.

### The counterweight, and why this survives §10.7

Standing-rule-on cannot mean *keep everything forever*, or the COPPA answer in
§10.7 collapses. So the rule is bounded:

- **Covered by the standing rule, kept indefinitely:** anything a guardian
  authored *for* the child — video messages, voice notes, drawings sent to her,
  scavenger-hunt finds, showcase artifacts (§9.10.6).
- **Not covered, and therefore on a clock:** incidental capture — call clips,
  screenshare frames, transient session media.

Everything in the second group appears in an **expiry digest** before it is
deleted, with a lead of `DIGEST_LEAD_DAYS = 14` and one tap to keep it. Nothing
is ever lost without the guardian having been given the chance to say otherwise,
which is the whole of the user's instruction and the reason the posture is
defensible rather than merely generous.

### The digest is never shown to a child

*"These memories are about to be deleted"* is a sentence no eight-year-old should
read about her own life. `digestVisibleTo('child')` returns `false`, the digest
declares `audience: 'guardian'`, and the headline copy is asserted to contain no
deletion language at all. **The decision is an adult's; the child experiences
only the outcome.**


---

## §17 Adoption and asymmetric use

**This is the existential problem, and it is not a feature.** Every product in
this category dies here. One parent signs up. The other reads the invitation as
surveillance, as control, or as the opening move in a custody fight — and
refuses. Versions before 0.4.0 assumed a populated family graph on day one.

### 17.1 Single-guardian mode is the default assumption

The product must deliver full value with exactly one guardian and one child:
calls, homework, games, calendar, archive, message banking. **If it is inert
until the second parent joins, the first parent churns before the second is ever
asked.** No feature may be gated on a second guardian existing.

### 17.2 Invitation framing

- The invite says *"Maya's other house."* It does not say co-parenting account,
  log, record, or export.
- Nothing in the invitation path mentions the court tier. A parent who first
  encounters this product as evidence-gathering software will never join it.
- The inviting parent cannot see whether the invite was opened. Read receipts on
  an invitation are pressure.

### 17.3 Observer tier

A reluctant parent may accept **read-only**: see drawings, see the calendar,
watch a recorded message. No obligation, no visible participation, no
notification to the other parent that they are observing.

Two weeks of seeing your kid's drawings converts better than any pitch.

### 17.4 Third-party invitation

An invite may be sent by a mediator, parenting coordinator, caseworker,
therapist, court, or grandparent. A neutral sender changes the emotional register
completely, and is the primary channel for the institutional segment (§14).

### 17.5 Permanent asymmetry

Some families will run one-sided forever: the other parent is absent, deceased,
incarcerated without access, or simply refuses. **That is a supported end state,
not a failure.** No nagging, no "complete your family" prompts, no empty-state
copy that implies something is missing. Principle §2.12.

---

## §18 Succession and bereavement

Message banking (§9.5) plus terminal illness is a real and wrenching use case,
and it is the exact shadow of prohibition **P1**. Someone will propose
synthesising a dead parent's voice, framed as a gift to a grieving child. The
register already bans it. This section exists so the surrounding policy is not
improvised at 2 a.m. with a widow on support asking what happens to the videos.

### 18.1 On the death of a guardian

1. The guardianship edge **closes** (`closed_at`, `closed_reason = 'death'`). It
   is never deleted. Their history, messages, and authored artifacts remain.
2. All artifacts they authored are set `preserved = true` automatically.
3. Banked batches follow the **parent's own pre-recorded directive** (§5.16):
   `continue`, `stop`, or `deliver_all` immediately. **Nobody else may change
   this.** Not the surviving guardian, not a court, not support staff.
4. If no directive exists, the default is `stop`, and the material is preserved
   and handed to the surviving guardian as custodian — not deleted, not delivered.
5. A named `successor_id` takes custodianship of the archive until majority.
6. §9.8.4 majority handover proceeds unchanged. This is often the entire point.

### 18.2 Posthumous restatement of P1

**No synthesis. Ever. Under any framing.** Not voice, not video, not
"what Dad would have said." A grieving child is the most sympathetic possible
case for the most harmful possible feature, and that is precisely why it is
written down here rather than left to judgement in the moment.

What *is* offered: recording well in advance, unlimited preservation, the
`deliver_all` option, and a written message read at transfer.

### 18.3 Death of a child

Archive is preserved indefinitely and transferred to guardians on request.
Every automated surface — countdowns, "on this day", ritual reminders, banked
deliveries, Year Book compilation — **halts immediately** on the setting of a
single flag. Nothing about this path may be automated beyond that halt, and
support contact must be human.

---

## §19 Deferred — considered, not lost

Recorded so these are not re-litigated from scratch, and not silently dropped.

| Item | Status | Revisit |
|---|---|---|
| **Foster and kinship placement** | **Removed from §16.2 at the owner's direction — not needed yet. Scaffolded only** at `scaffold/packages/kinship/src/DEFERRED.md`, which records why it is hard (the state is a party, which breaks the §10.2 consent model and puts P7 against a statutory duty of care), what already exists to build on, and three preconditions before any work starts. | Unscheduled |
| **Child-initiated affection signal** (§16.2 #12 — "send a hug," raised evaluating a Gemini-drafted alternate build). **Declined outright at the owner's direction, not deferred.** The come-back signal's "he requests, she acts" asymmetry (§5.27) does not extend to a child-initiated push; five open questions were raised (spam/pressure on the receiver, `pending_asks` ceiling interaction, sender symmetry, voice-memo retention treatment, and whether showcase/letters already cover the need) and the owner declined the feature rather than resolve them. No scaffold exists and none is planned. | **Not planned** — do not re-propose absent new owner direction |
| **Curriculum-standard tagging** (§16.2 #8 — Common Core vs. state-by-state).
**Declined outright, not deferred, v0.40.0.** `school.ts` (§11.5) had already
settled a closely related question: no SIS/gradebook integration, because a
gradebook feed would put a child's marks in front of a parent she did not
choose to tell — the exact inversion of §9.1's "homework help is something she
brings, not something served to him." Standard-tagging a homework problem by
grade level is the same risk wearing different clothes, at real ongoing
maintenance cost either way (Common Core has state holdouts; fifty-state
tagging is fifty taxonomies to track). The hint engine's value is precisely
that it works on any problem without knowing what grade or standard it
belongs to. If targeted help is wanted later, the safer version is a
per-session parent-typed tag with no persistent record — not a standard
taxonomy. | **Not planned** — do not re-propose absent new owner direction |
| Therapist role scope definition | Role landed; visibility scope open — §16 #11 | Phase 3 |
| Child device reality — no-install web path, household-device mode, offline playback | Deferred to §8.5 stub | Phase 2 |
| Dispute tiebreak beyond propose/accept/decline | Routes to coordinator seat; escalation ladder undefined | Phase 3 |
| Sibling-to-sibling contact across split placements | Schema landed (`sibling_link.contact_allowed`); UX undefined | Phase 2 |
| Group call with multiple children + one parent | Schema supports; scheduling UX undefined | Phase 2 |
| Print fulfilment partner selection | — | Phase 3 |
| Insurance / benefits coordination | Out of scope; adjacent product | — |

### §8.5 Child device reality — stub

The SMS-bridge insight (§8.4) applied to the child's side. A child may have a
shared family tablet, a school Chromebook, a phone the *other* parent controls,
or nothing at all. Required before Phase 2: a no-install web path, a
household-device mode where the child is not the account holder, and offline
playback of delivered messages. School wifi and rural DSL are the norm, not the
exception.

---

## §20 Phase 0 review

Written at the close of the sixth increment. The purpose of this section is to
be **accurate about the gap** between a green test suite and a product a family
can use, because that gap is currently large and easy to misjudge from the
outside.

### 20.1 What is actually built

| Phase 0 item | Status | Evidence |
|---|---|---|
| Time engine (§4, §6.1–6.2) | **COMPLETE** | 24 golden assertions incl. both DST pathologies, Chicago↔Phoenix, El Paso, TX↔NC handoff, 181-night batch |
| Delivery engine (§6.3–6.5) | **COMPLETE** | 37 assertions; exactly-once proven with 8 concurrent workers against 500 due intents |
| Schema (§5, migrations 0001–0003) | **COMPLETE** | 14 tables, 63 constraints, 24 adversarial probes |
| Family graph + authorization (§5.17) | **COMPLETE** | 59 assertions; P7 unreachable by any argument, no sibling traversal |
| Session context (§5.18) | **COMPLETE** | 14 isolation assertions as a non-superuser owner |
| Session token minting (§5.19) | **COMPLETE** | 67 assertions against the real `livekit-server-sdk` payload |
| Child-lock state machine (§5.20) | **LOGIC ONLY** | Defeat/escalation/cooldown modelled and tested; **no native bridge** |
| Async message pipeline (§9.5) | **LOGIC + DB + real POST route** | 32 unit + 16 end-to-end assertions, plus (v0.47.0) `POST /v1/children/:childId/messages` and a real client capture UI (`receipt_screen.dart`'s "Send one back") — 33 + 20 new assertions. **Still no object storage, and a child cannot yet be a real sender** — see §20.2b |
| `media_artifact.preserved` (§12.1) | **COMPLETE** | CHECK constraint proven unrepresentable-otherwise |
| `sibling_link`, `guardianship.closed_at` | **SCHEMA** | Ahead of their features, as planned |
| Single-guardian mode (§17.1) | **COMPLETE** (v0.49.6) | `isSingleGuardianViable()` ported to Dart and given a real UI — `who_is_here_screen.dart`, §8.5.3's full spec (no chooser for a solo guardian, a pending invite greyed, the last selected guardian never deselectable) |

**280 assertions across 8 suites, all green.** Every one runs against real
Postgres 16.14 or the real LiveKit SDK, not mocks.

### 20.2 What does not exist

This list matters more than the one above.

**Closed in v0.10.0** — §20.5 items 1–5:

| Was missing | Now |
|---|---|
| Authentication | **`packages/auth`** — scrypt PIN hashing, WebAuthn ES256 assertion verification with signCount replay guard, signed short-TTL sessions, two-factor escalation. `withSession()` finally has something that produces a verified principal. |
| API layer | **`packages/api`** — router with three structural invariants (A1 mandatory declared action, A2 context only from the principal, A3 `childId` from the path only), verified over a real socket. |
| Object storage + reaper | **`packages/storage`** — port, adapter, key-bound signed URLs, and a reaper that deletes **blob before row**. Migration 0004 adds `reap_tombstone` and `retention_breach`. |
| Push / call ringing | **`packages/transport`** — content-free payloads with an allowlist audit, VoIP push and full-screen intent for calls. |
| Client shell | **`client/lib`** — grew from four Dart files to 95 (75 new from this round) across fourteen parallel build groups (onboarding, games, storyteller, journal/letters, calendar, guardian ops, live-call extras, showcase, archive/export, the maturation ladder) plus the entry gate, kiosk lock, and call screen already there. **CLOSED v0.44.0**: every one of those screens is now reachable from `ChildHome`/`GuardianHome`, not just compiled — the "20.2b still missing" row directly below is what remains unclosed on the client. |

### 20.2b Still missing

| Missing | Consequence |
|---|---|
| ~~A compiled client~~ | **CLOSED v0.15.0.** Flutter 3.24.5 / Dart 3.5.4. `flutter analyze` clean under strict casts, strict inference and strict raw types; 14 widget tests execute inside `verify.sh`. A missing toolchain is treated as a gap, not a skip. |
| ~~A live LiveKit server~~ | **CLOSED v0.12.0.** livekit-server 1.8.0 runs inside `verify.sh` via `tools/with-livekit.sh`. 21 assertions against the real server, including the I2 proof that a join token is refused for every admin call. |
| ~~Native kiosk bridge (Android)~~ | **CLOSED v0.43.0.** `startLockTask` wired end to end: `client/android/.../KioskBridge.kt` (real, in the actual Gradle module — the old `native/android/` copy was a never-compiled reference), `client/lib/lock_controller.dart` (a port of the §5.20 state machine), `client/lib/kiosk_shell.dart` (the wiring). The §5.20 state machine is driven by real lock-task/lifecycle events on a real device, not only synthetic ones. Windows and Wear OS are covered in the two rows below; iOS remains Ph.4 per §8.3's own table. |
| **Windows kiosk bridge** | **REAL, UNVERIFIED — v0.45.0.** `client/windows/runner/kiosk_bridge.{h,cpp}` — an app-level lock (window-chrome strip + a re-arming `WH_KEYBOARD_LL` hook), not OS Assigned Access. Compiled clean with `cl.exe /W4` against the real embedder headers; `flutter build windows` itself cannot run here (Visual Studio Build Tools missing the "Desktop development with C++" workload) — still marked UNVERIFIED in the header comment and the transport contract test until it is. |
| **Wear OS companion (Galaxy Watch6)** | **REAL SYNC CODE, HARDWARE-UNVERIFIED — v0.45.0 shell, sync added by v0.49.11–v0.49.39, doc corrected v0.49.57.** Standalone Jetpack Wear Compose module (`client/android/wear/`); `:wear:assembleDebug`/`:wear:compileDebugKotlin` both BUILD SUCCESSFUL. Phone↔watch data sync via the Wear Data Layer API is real in both directions — `WearSyncBridge.kt` (phone side, `DataClient.putDataItem()`/`MessageClient` listener) and `.../wear/MainActivity.kt` (watch side, `DataClient.OnDataChangedListener` on `/olive/now`, `sendCallDadMessage()` on `/olive/call-dad`), bridged to Dart via `wear_sync_channel.dart` and called from `child_home_live.dart`. Unit/contract-tested (`transport.test.mjs`'s "K · WEAR SYNC BRIDGE CONTRACT" group, `wear_sync_channel_test.dart`) — but **no Wear OS emulator or physical watch has ever paired with this code in this environment**, so the actual Data Layer round-trip remains unverified; this row previously read "not implemented," which understated what's real. No `MANUAL_VERIFY_wear_sync.md` exists yet — worth writing one, matching `MANUAL_VERIFY_call_lock_task.md`'s own precedent, before attempting real-hardware verification. |
| **`GuardianHome` has no live-data screen** | **REAL AS OF v0.49.57 — built, compiled, 2030/2030 Dart tests + 31/31 client/server contract assertions passing, NOT YET verified against a real deployed backend or physical device.** Real, previously-open gap (confirmed v0.49.15, re-confirmed unchanged through v0.49.39/v0.49.56, 24+ patch versions) closed the way `child_home_live.dart` closed the identical gap for the child side: a new `GET /v1/children/:childId/ribbon` route (`server/routes.mjs`, guardian-only, reusing `childCtxFor()`/`availabilityFor()`/`parentGuardiansOfChild()` verbatim — zero new pool.ts functions), a new `OliveApi.fetchRibbon()`, and a new `guardian_home_live.dart` wrapping `GuardianHome` unmodified, mirroring `child_home_live.dart`'s own shape (disclosed divergences: no wear/push seams, no secondary-fetch split, no session-token threading — none of the three apply to `GuardianHome`'s own current shape). `main_live_guardian.dart` now boots into it directly. Two fields stay an honest, disclosed absence rather than a guess: `childStateSentence` (no real one-sentence-status source exists anywhere yet — the field was loosened to nullable) and `overlapLabel` (the route deliberately omits it from the wire — no confirmed definition yet of what counts as "child free" for the sentence, a product question left open, not answered unilaterally). `server/test/ribbon_route.test.mjs` (real Postgres assertions) could not be run locally this pass (no reachable Postgres/Docker in this environment) — registered in `tools/verify.sh`, awaiting a real CI run for the one piece of verification this pass couldn't do itself. |
| ~~`ChildHome.presence` had no live data source~~ | **CLOSED v0.49.50.** Tier D item deferred at v0.49.49 pending one narrow judgment call: which guardian to surface when several are simultaneously free, and how to break the tie. Resolved by porting `packages/signal/src/signal.ts`'s `prioritise()` reasoning (MASTERFILE §5.27.4, "no seniority, no primary/secondary, no custody weighting") — after the on-duty guardian is excluded (§5.27.4 rule 2, presence loses to absence), the remaining guardian whose availability window started earliest wins; the same verbatim §5.27.4 quote is carried as a code comment at the computation site, matching this codebase's established discipline of disclosing judgment calls in the code itself, not just in this document. New `GET /v1/children/:childId/presence` route (`server/routes.mjs`), a new pure `freeGuardianNow()` (`packages/custody/src/schedule.ts`), and `parentGuardiansOfChild()` (`packages/db/src/pool.ts`, role-filtered to `'guardian'` — the same principle already governing the come-back signal, applied here so a step-parent/sitter/coordinator is never shown as callable). **A real, pre-existing schema gap surfaced along the way, found not invented, and left disclosed rather than silently expanded into this feature's scope**: `custody_order` had no column anywhere mapping its abstract `Side` ('A'\|'B') to a real `app_user.id` — nothing in this codebase has ever recorded "which of this child's guardians IS Side A." `db/migrations/0024_custody_order_side_guardians.sql` adds nullable `side_a_guardian_id`/`side_b_guardian_id`; a `NULL` (every pre-migration row, and any row never populated by a real order-creation flow, which itself does not exist yet — `family_agreement_screen.dart`'s own header: "no editing UI exists here, deliberately") is an honest "unmapped," skipping the on-duty exclusion rather than guessing, never a faked value. A second, separate finding from this same build's own adversarial review: `guardian_availability_window`'s `CHECK (end_local > start_local)` constraint (migration 0010, predates this feature) makes an overnight availability window impossible to store at all today — `freeGuardianNow()`'s wrap-around handling is real and unit-tested (13 assertions, `packages/custody/test/custody.test.mjs`) but cannot be exercised via real data until that constraint is relaxed, which is its own separate, undecided product change (does `availability_screen.dart`'s guardian-facing UI even need to accept an overnight range?) — tracked here, not built. Guardian "sole parent" and "no one free" responses are byte-identical (`{ free: null }`), so this card never leaks which of those two is true. **A real wording tension, found by this project's own post-tier audit and disclosed rather than unilaterally resolved**: the presence card's own shipped copy — "`<Name>` is free right now... until `<time>` her time" plus a Call button — pairs a live parent-reachability fact with an expiring window, the same shape §5.25.4 states its own reasoning against for the (guardian-only) Day Ribbon overlap prompt: "a prompt telling a five-year-old that now would be a good time to call her father makes his availability her responsibility." `ChildHome.presence` and its Call button predate this pass and were not newly invented here, and this pass's own design review (a dedicated privacy/§2.1 verify lens) found nothing wrong with it — but that review evaluated the mechanism (who can be shown, on-duty exclusion, no family-shape leak), not this specific wording's own relationship to §5.25.4's stated concern for the same underlying pattern. Not rewritten here — matching this project's own posture on the separately-declined call-quality UX item, a copy/framing call like this is a product decision, not a mechanical bug fix; tracked here for a real decision, not silently left unexamined. |
| ~~A child cannot yet send an async video message~~ | **CLOSED v0.49.39.** `db/migrations/0021_child_message_sender.sql` adds `author_child_id`/`sender_child_id` alongside the existing `app_user`-only columns (mirroring `export_record`'s own exactly-one-of split); `server/routes.mjs`'s `POST .../messages` route derives the sending child's id from the verified session, never the body; `pipeline.ts`'s `captureMessage()` threads it through. A child session sending about herself now really succeeds (201), proven over real HTTP against a real database in `packages/api/test/messages_route.test.mjs`'s "D auth" group — the same suite this row's own earlier text cited for the opposite, now-stale result. Message banking (§9.8.1, guardian-only) is deliberately untouched — a child-originated capture fails loudly with a named error if it ever tries to start a batch, rather than a raw constraint violation. §9.10.2's "Look what happened → send one back" matrix entry now has a real reply direction, not merely a described gap. |
| ~~No object storage backend~~ | **CLOSED v0.49.43.** `FilesystemStorage` (real, tested since v0.49.6) is now wired to a real HTTP path: `POST /v1/children/:childId/media` writes real bytes to a real persistent volume and returns the real storage key; `GET .../messages/:artifactId/media` reads them back, authorized by the same `action: 'message'` gate the message route already runs, with `mediaArtifactFor()`'s double-scoped query as the real cross-child boundary underneath it. `receipt_screen.dart`'s "Send one back" now uploads the real recorded bytes before sending. Proven end-to-end (25 assertions, real Postgres + real filesystem, byte-for-byte roundtrip). **Both remaining gaps this row named CLOSED v0.49.49**: `inbox_screen.dart` now supplies `receipt_screen.dart`'s live params (self-fetches its own real inbox via `OliveApi.fetchInbox()`, the same self-fetching pattern `HomeworkScreen` already established, rather than requiring a caller to pre-fetch and pass down a list) — a real bug in the wiring's own first draft (`_open()` computed the live params but never actually threaded them into `ReceiptScreen(...)`) was caught by this same pass's own new test, not shipped silently. And a real `GET /media/:key?exp=...&sig=...` route (`server/signed_media.mjs`) now serves `StoragePort.verifySignedKey()`'s real result — a genuinely separate, unauthenticated-except-for-the-signature path, deliberately outside `api.ts`'s session-based dispatch. Writing that route's own first test found and fixed a real validation gap of its own: `Number(null)` coerces to `0`, not `NaN`, so a bare `!Number.isFinite(exp)` check silently admitted a request with no `exp` param at all. **Correction, found by this project's own post-tier audit**: the signed-URL route above is real, tested, and correctly authorized in isolation — but "now serves what could already mint" undersold a real gap rather than closed one: nothing in this codebase, anywhere, ever actually mints a URL for it to serve. `StoragePort.signedUrl()` is called nowhere in production code (test files only); no `OliveApi` method requests a signed URL; the one real, live media-read path (`GET .../messages/:artifactId/media`) still returns raw base64 bytes in a JSON body, untouched by this route's existence. The signed-URL route is complete and functionally dead code from an end-to-end perspective — treat it as real infrastructure awaiting a real caller, not as the production media-read path, until something actually wires one. |
| **Real-time call — SUPERSEDED TRANSPORT, v0.49.57.** The account below is real history about the self-hosted-Jitsi build (both causes genuinely fixed and confirmed live on real hardware, at the time), left visible per §21.7 rather than deleted — but §16.2 #6 REVERSED AGAIN (above the tech-stack table) has since moved calls back onto LiveKit Cloud, which is **NOT yet verified against a real LiveKit Cloud project or real hardware**. Do not read this row as describing the current transport. | Two independent causes were found in the self-hosted-Jitsi build, detailed in the §16.2 #6 callout above the tech-stack table — both closed with hard evidence at the time, not just a compiled/tested fix awaiting a device run. **Kiosk lock-task conflict:** fixed via a pin handoff (`KioskBridge.kt`'s `beginCallHandoff`, the patched `WrapperJitsiMeetActivity.kt` self-pinning for the call's duration) — **confirmed live** by a device owner driving the real procedure by hand on the Fold5 (real finger, real dialog, real "Call Dad") while a session independently captured a 114,222-line `adb logcat` + polled `dumpsys`: zero `Attempted Lock Task Mode violation` events across the whole capture, `WrapperJitsiMeetActivity` launching and taking the foreground cleanly while pinned, a real `CONFERENCE_JOINED`, and `mLockTaskModeState` staying `PINNED` continuously through the launch/join/lobby-wait window with no gap — see `client/docs/MANUAL_VERIFY_call_lock_task.md` (now itself carrying its own SUPERSEDED notice) for the full evidence. **Moderator lobby / self-hosted stack:** Step 2 (self-hosting, `scaffold/tools/jitsi-selfhost/`) staged and container-verified as of v0.46.2, its self-signed-cert gap fixed at the TLS layer as of v0.49.28 — and **confirmed live on real hardware as of v0.49.30**: the stack's own served client config (`config.js`) still hardcoded `wss://localhost:8443/...` for its XMPP websocket, derived from `PUBLIC_URL` defaulting to `localhost` — a physical device resolves that to itself, not the dev machine, so every join attempt failed with a real Strophe websocket error regardless of the TLS fix being correct. Fixed by pointing `PUBLIC_URL` at the dev machine's real LAN address; the very next join attempt produced a real `CONFERENCE_JOINED` event with a real room URL, captured directly in that device's own logcat — the first time this Step actually connected on real hardware. See CHANGELOG v0.49.30 for the full account (the "§9.12.4's own note" citation this row previously carried was wrong — §9.12.4 is the doodle desk feature, unrelated to calls; corrected by removal rather than left dangling). The public `meet.jit.si` server's moderator lobby itself remains open and expected under the (now-superseded) Jitsi transport — self-hosting was its intended resolution, not a bug to fix in the public path. |
| ~~OCR~~ | **CLOSED v0.47.0.** Real `ImageStats` from real photo bytes (`packages/homework/src/measure.ts` — variance-of-Laplacian sharpness, tolerance-banded clipping histogram, projection-profile skew search, all documented approximate), real tesseract.js OCR (`packages/homework/src/capture-route.ts`), a real rule-based (explicitly NOT an AI model — no LLM key is configured anywhere in this repo) hint generator (`packages/homework/src/hints.ts`) run through the pre-existing `guardHint()` unchanged, and a real client camera path (`client/lib/capture_gate.dart`, `image_picker`) POSTing to the new `POST /v1/children/:childId/homework/capture`. `measure.test.mjs` 20/20, `capture-route.test.mjs` 34/34 (real photo in, real recognizable text out), `flutter test` 1286/1286. Persisting recognized problems for later retrieval (§7.5's broader `GET /v1/homework/:id` surface) remains a real, separate follow-up — this closed exactly the OCR row, not the whole of §7.5. |
| ~~CI, migration runner, observability~~ | **CLOSED.** `verify.yml`'s own path/discovery gap is long resolved — `.github/workflows/verify.yml` lives at the repo root and has run real, green CI on every PR since (confirmed directly, repeatedly, via `gh run view`/`gh pr checks` across dozens of PRs this session; this row's earlier "not yet live, blocked on an OAuth token" claim was itself stale and is corrected here rather than left standing). `tools/healthcheck.mjs`/`tools/health-alert.mjs` (real `health_check` view probe, structured `ALERT` lines, non-zero exit on a breach — `packages/db/test/health_alert.test.mjs`, 10/10) are both wired into `verify.sh`. **`tools/scheduler.mjs` (v0.49.43) closes the one piece that was still genuinely missing**: a real, self-hosted-appropriate job runner — Postgres advisory-lock-guarded, real structured logs — that actually calls `health-alert.mjs` and the delivery-engine's rematerialization sweep on a schedule — gated behind an opt-in Compose profile in `docker-compose.dev.yml` so it never runs unattended against a live debugging session by accident, but wired into `docker-compose.prod.yml`'s **default** service set (v0.49.45), not opt-in there, since the dev footgun that motivates the gate has no production analogue and gating it there would instead mean production silently never delivers anything until an operator finds an undocumented flag. Still no email/Slack/pager integration — `health-alert.mjs`'s own structured stderr lines are the full extent of "alerting" today; a real paging integration remains a genuine, disclosed, unbuilt follow-up. **A fourth gap in this same family, missed by v0.49.43 itself and found only by a later gap-inventory pass, closed v0.49.46**: `packages/storage/src/storage.ts`'s `reap()` — real and tested since before v0.49.43, its own header naming the stakes plainly ("Under the amended [COPPA] Rule the blob IS the regulated personal information... a reaper that deletes rows and leaves media is not a retention policy") — had zero production callers, and neither did its SQL half (`artifacts_due_for_reaping()`/`reap_tombstone`, migration 0004; the §20.5 "Closed in v0.10.0" table above names this reaper as built, which was true of the CODE but silently never disclosed that nothing ever called it). The monitoring existed and was already live (`reap_tombstone`/`retention_breach` feed `health_check`, wired since migration 0009 — `tools/health-alert.mjs` was already capable of alerting on a stuck tombstone); only the thing it would ever have anything to alert ON was missing. `tools/scheduler.mjs` gained a third job, `reap-media`, closing it — real Postgres-backed `ReaperDb` glue (`packages/db/test/scheduler.test.mjs` section C, 16 new assertions: a due row's blob and row both go, a preserved row is excluded by the SQL `WHERE` clause itself, a not-yet-due row is untouched, an already-tombstoned row is excluded by the SQL `NOT EXISTS` rather than re-attempted, and a blob-delete failure leaves the row in place with a real `reap_tombstone` write, per `reap()`'s own "blob first, then row" design). See CHANGELOG v0.49.46. |
| ~~No row-level security on media_artifact, intent_batch, delivery_intent~~ | **CLOSED v0.49.47.** First tracked as its own MASTERFILE row here — previously disclosed only in `pool.ts`'s own `persistCapturedMessage()` doc comment ("its own migration and its own review, not a side effect of adding one new write path"). `db/migrations/0023_message_media_delivery_rls.sql` closes it, preceded by a real audit of every reader/writer of all three tables and two independent adversarial reviews of the proposed policy (one security, one functionality — see this document's own status paragraph above for the full account of what each caught). 22 new live-Postgres assertions (`db/test/0007_message_media_rls.test.sql`), plus the full pre-existing `db/test/*.sql` suite re-run clean against the new policies (94/94, one true pass, matching `tools/verify.sh`'s real suite order) and every affected `.mjs` suite (`message_capture`, `raw_export`, `take_and_go`, `deletion`, `health_alert`, `messages_route`, `media_route`, `scheduler` — 233 assertions, zero regressions). Writing this migration's own audit and its first-ever `GET .../inbox` HTTP test also surfaced a real, unrelated production bug — see the CI/scheduler/reaper row above's sibling note in this document's status paragraph, or CHANGELOG v0.49.47, for the full account: the route's response key collided with `globalaudit.ts`'s own forbidden-field list, 500ing on every real child's own inbox read since v0.49.37 shipped, invisible because nothing had ever tested this route against a real HTTP call before now. Fixed alongside the RLS work, not deferred. |
| **The coordination layer — most of it has real client UI and real unit-tested logic, but no real database/server backend at all.** | **PARTIALLY CLOSED — the parent-to-parent handover log CLOSED v0.49.52, expenses CLOSED v0.49.53, medications + emergency card CLOSED v0.49.54, the exchange CLOSED v0.49.55; care notes and letters remain open, tracked here.** Found by a direct, evidence-based audit answering the plain question "is everything the specification and this whole session's own work actually built" — not from memory, per this project's own standing lesson (§20.4) about verifying rather than trusting recall. **Closed piece — the handover log (`message_log`, `handover_notes.dart`):** `message_log` (`db/migrations/0006_court_tier.sql`) has had real FORCE RLS (`log_no_child`), a real append-only trigger, and a real hash-chain-linkage trigger since it was first migrated, and `certifiedExportBundleFor()` has been able to READ and verify it since v0.14.0 — but nothing anywhere ever WROTE a row; `handover_notes.dart`'s own client UI was pure in-memory local state with zero network calls. Closed by new `appendHandoverNote()`/`handoverNotesFor()` (`packages/db/src/pool.ts`), new `GET`/`POST /v1/children/:childId/handover-notes` (`server/routes.mjs` — a real child-session guard needed at the route itself, since `handoverNotesFor()`'s system-scoped read bypasses `log_no_child`'s RLS, which only excludes the `'child'` role), real concurrency safety (`pg_advisory_xact_lock`, proven via a real race + `verifyChain()`), and real live client wiring (`handover_notes.dart`'s existing offline demo mode preserved exactly when no live params are supplied; a new `guardian_more.dart` Coordination tile, since neither `guardian_more.dart` nor `guardian_home.dart` had a live call site for it before this pass). 27 server assertions, 7 new/extended Dart tests, zero regressions. See CHANGELOG v0.49.52. **Closed piece 2 — expenses (`expense`, `expenses_screen.dart`):** CLOSED v0.49.53. `expense` (`db/migrations/0006_court_tier.sql`) has had real FORCE ROW LEVEL SECURITY (`expense_no_child`) since it was first migrated, and `family-graph/src/authorize.ts` already had `expense.view`/`expense.create` in its `Action` union with a real, unconditional P6 block ("a child role never sees a financial surface") — but nothing anywhere ever wrote or read a row. Closed by new `proposeExpense()`/`expensesFor()`/`resolveExpense()` (`packages/db/src/pool.ts`), a new `expense.resolve` `Action` (guardian-only; a coordinator keeps read-only `expense.view`, matching MASTERFILE's own "Read-only across... the expense ledger"), new `GET`/`POST /v1/children/:childId/expenses` and `POST .../expenses/:expenseId/accept|dispute|reimburse` (`server/routes.mjs` — child-scoped throughout, not §7.7's own bare `/v1/expenses/:id/accept` sketch, matching the handover log's own precedent for why), a real lateral-privilege boundary (`resolveExpense()`'s own `WHERE id=$1 AND child_id=$2`, since `expense_no_child`'s RLS does not scope by child at all — proven by a dedicated cross-child test, not assumed), and a new `expense.description` column (`db/migrations/0025_expense_description.sql` — the shipped table had never had a free-text field, though the client's own demo fixtures always carried one). `expenses_screen.dart` is now genuinely live-wired (its P6 gate — `_NotAGuardianSurface`, zero financial widgets ever constructed for a non-guardian viewer — proven to run BEFORE the live fetch even fires, by a dedicated test) behind a new `guardian_more.dart` tile, and the demo's own real bug (`_resolve()` hardcoding `amountCents: 0` on Agree) does not carry over to the live path, which always renders the server's real amount. `Decline` maps to the real `disputed` status (there is no `declined` value in `expense.status`'s CHECK constraint); `Query it` stays honestly unbuilt (no server concept for "a question was asked" exists yet), never silently mapped to accept/dispute. 45 new server assertions, 20 new/extended Dart tests.

****Closed piece 3 — medications + emergency card (`medication`/`medication_dose`/`medical_record`, `meds_care.dart`, `emergency_card.dart`):** CLOSED v0.49.54. `medication.view`/`medication.log`/`emergency_card.view` already existed in `authorize.ts`'s `Action` union with real, already-differentiated `ROLE_CAPS` (a sitter can log a dose but never edit the card; a step_parent can view medications but never log a dose — real, pre-existing distinctions this pass did not invent) — but no table existed for either feature, and `meds_care.dart`/`emergency_card.dart` were pure hardcoded client state (the latter a `StatelessWidget` with a single const string) with zero network calls. Closed by `db/migrations/0026_medications_emergency_card.sql` (three tables: `medication`, an append-and-collide-checked `medication_dose` with a real Postgres partial unique index — `medication_dose_no_double_given` — enforcing the exact "no second given dose in the same slot/day" rule `recordDose()`'s own pure port already checked client-side, now backstopped by the database itself against a real concurrent-write race; and `medical_record`, which deliberately does NOT store "Guardians" at all — that section is derived LIVE from the real `guardianship`/`app_user.phone_e164` columns, which already existed and are already the real source of truth, rather than a second, driftable copy), a new `emergency_card.edit` `Action` (guardian-only — a sitter's own real `emergency_card.view` stays read-only), and real live client wiring for both screens with their existing demo modes fully preserved (`emergency_card.dart`'s conversion from a `StatelessWidget` to a live-capable one kept every one of its 16 pre-existing tests passing unchanged). **A real bug this pass's own test suite caught before it ever shipped**: the first draft of all four new routes relied on the outer authorization gate alone, which (per `api.ts`'s own real design) only auto-refuses a child session for `P6_child_financial`/`P7_journal_never` — every other action, `medication.view` included, passes that gate for a child principal by construction, so a child session could originally reach both new medical routes freely; fixed with the same explicit `roleName === 'child'` route-level guard every other coordination route in this file already carries, caught by section H of the new server test file before merge, not after. 36 new server assertions, 40 new/extended Dart tests.

**Closed piece 4 — the exchange (`exchange_bag_item`/`exchange_running_late_log`/`exchange_arrival_event`, `exchange_screen.dart`):** CLOSED v0.49.55. `packages/care/src/care.ts`'s `manifestOrder()`/`recordArrival()`/`auditArrival()` were real and already tested, but no table, route, or pool.ts function existed for any of the bag manifest, running-late log, or arrival event — `exchange_screen.dart` had never made a network call. Closed by `db/migrations/0027_exchange.sql` (three `..._no_child`-RLS tables; `exchange_arrival_event` has no latitude/longitude/coords/address column at all — P3, §9.7.2, enforced structurally, not just by convention, matching the client's own `auditArrivalPayload` guard), new `bagItemsFor()`/`setBagItemStatus()`/`runningLateLogFor()`/`logRunningLate()`/`arrivalEventFor()`/`recordExchangeArrival()` (`packages/db/src/pool.ts`), and new `GET`/`POST` routes under `/v1/children/:childId/exchange/...` reusing the existing `calendar.view`/`calendar.edit` actions (no dedicated Action exists for the exchange yet — the same closest-existing-action gap the pre-existing `GET .../now` and `GET .../custody-order` routes already disclose, not a new one invented here). `recordExchangeArrival()`'s `scheduled_at` is never client-supplied — it is computed from the child's real active custody order (`activeCustodyOrderFor()`'s own `exchange_time`/`order_tz`, proven by a dedicated test to use the ORDER's zone, not the child's `home_tz`), with a real, honest 409 (`no_active_custody_order`) when no order is on file, never a guessed schedule. A real lateral-privilege guard (`setBagItemStatus()`'s own `WHERE id=$1 AND child_id=$2`, the same shape `resolveExpense()` established) was proven by a dedicated cross-child test, not assumed from RLS alone (`exchange_bag_item_no_child`'s policy excludes only the `child` role, the same way `expense_no_child`/`medication_no_child` do — it is not itself a per-child scoping mechanism). Scope, disclosed: `exchange_screen.dart`'s Handoff/Coming-up sections stay on `_demoOrder`'s demo data even when this screen is live-wired — making those live would mean porting `packages/custody/src/schedule.ts`'s full timezone-aware `exchanges()`, a separate, larger task from the bag/late/arrival domain actually closed here. 50 new server assertions, 30 new/extended Dart tests, zero regressions. See CHANGELOG v0.49.55.**

**Closed piece 5 — care notes and letters (`care_note`, `letter`, `care_note.dart`, `letters_screen.dart`):** CLOSED v0.49.56, the final two pieces of this closure plan. `care_note`: guardian-only, the same `..._no_child` RLS shape every other table in this migration series uses; `writeCareNoteRow()` (`packages/db/src/pool.ts`) reuses `packages/guardian/src/guardian.ts`'s own real, already-tested `writeCareNote()` directly — the tone guard (`CARE_NOTE_BANNED`) and the real 7-day TTL computation both run before a row is ever written, never re-implemented and never applied as an after-the-fact filter. New `care_note.view`/`care_note.write` Actions — guardian/sitter/foster_parent get both, step_parent/caseworker view only, and a coordinator gets NEITHER, since a care note is deliberately outside the court-tier record (that role's own real exclusion, not an oversight). `letter` is the one genuinely new shape in this whole schema: CHILD-owned, GUARDIAN-EXCLUDED. RLS (`letter_owner_only`) mirrors `journal_owner_only` exactly; the new `letter` Action is listed in NO role's `ROLE_CAPS`, so a guardian session is refused 403 structurally, with no scope override or court tier that could ever admit one — proven end to end by a dedicated security battery, not just at the pure `can()` layer. `written_at_age` is always computed server-side from her real `birth_date`, never trusted from the client; a letter's real body text is withheld at the SQL projection itself (`CASE WHEN opened_at IS NOT NULL THEN body ELSE NULL END`) until she has genuinely opened it — age alone never reveals it, only a real, server-validated open does, and that same real age gates the open itself, so nobody, not a guardian and not her either, can ever get there early. One deliberate departure from `packages/maturation/src/maturation.ts`'s own `Letter.artifactId` shape: `body` is stored directly on the table rather than routed through `media_artifact`, whose retention/preservation model assumes a guardian explicitly preserves something that would otherwise expire — a letter has no guardian preserver and is never on a retention clock at all ("It gets kept forever," the screen's own copy). 57 new server assertions (21 care-notes + 36 letters, the latter including a raw-query RLS proof, not just a route-level one), 13 new/extended Dart tests, zero regressions across the full 2016-case Dart suite. This closes the coordination-layer audit's own scope in full — every feature that audit found (handover log, expenses, medications/emergency-card, the exchange, care notes, letters) is now real end to end. See CHANGELOG v0.49.56.** (`packages/school` — the §11.5 school layer — was never part of this row: it is deliberately non-integrating by design, "Olive does not integrate with school systems," per its own header, not an unbuilt backend.) |

### 20.3 Honest assessment

What has been built is **the part that is hardest to retrofit and cheapest to
get wrong**: temporal semantics, retention that cannot be indefinite by accident,
authorization where a prohibition is unreachable by construction, and a delivery
queue that is exactly-once under real concurrency. Those are load-bearing and
were the correct first targets.

What remains is **the majority of the work by volume** — client, auth, storage,
API, transport — and it is mostly well-understood integration rather than novel
design. That is a good position to be in, but it is not "nearly done."

A realistic Phase 0 exit — one guardian and one child on two real devices,
exchanging a video message and completing a call — requires the whole of §20.2.

### 20.4 Process findings

Ten increments produced **fourteen false-greens in our own verification**. The
pattern is now unmistakable: on this project the verification harness has
produced more defects than the product code it verifies. Every one was found by
deliberately breaking the thing a check guards and confirming the check fails, every one found
by attacking the tests rather than the code:

| # | Increment | Defect |
|---|---|---|
| 1 | 0.4.0 | `resolveWallClock` branched on `isValid`; Luxon never sets it for nonexistent times |
| 2 | 0.4.1 | P7 RLS probe ran as superuser — passed against a broken policy |
| 3 | 0.5.0 | Concurrency driver compared `""` to `""` and passed with the database down |
| 4 | 0.5.0 | Assertions counted globally, so the suite passed alone and failed in sequence |
| 5 | 0.6.0 | Session suite non-idempotent; fixtures doubled on re-run |
| 6 | 0.6.0 | Fixture used `ON CONFLICT DO NOTHING` where the unique pair required a reopen |
| 7 | 0.9.0 | The verification command printed a **hardcoded** total while every database suite silently returned zero |
| 8 | 0.10.0 | scrypt cost parameters exceeded Node's default `maxmem`; the hash threw on first use |
| 9 | 0.10.0 | The push-leak audit was a capitalisation heuristic — flagged "Something", would have missed a lowercase name |
| 10 | 0.11.0 | Migration runner's gap check: `findIndex` sentinel −1 made `slice(-1)` report an up-to-date database as out-of-order |
| 11 | 0.11.0 | OCR thresholds were **guessed**, and wrong in both directions — 25° admitted images recovering nothing, 640px rejected images recovering everything |
| 12 | 0.12.0 | `dropdb`/`createdb` in `verify.sh` omitted `-U`, failed silently, and every DB suite ran against the previous run's data |
| 13 | 0.12.0 | Same missing `-U` in the concurrency driver — reported zero assertions, caught only because zero is treated as failure |
| 14 | 0.12.0 | e2e suite claimed with `LIMIT 50`, assuming it owned the queue; 500 seed rows sat ahead of its own intent |

Standing rules adopted as a result, all now in force:

1. Every assertion scopes to rows the suite itself created.
2. Every database suite is verified across an order-independence matrix — alone,
   after each sibling suite, and re-run against a dirty database.
3. Every completeness or safety check must be **shown to fail** when the thing it
   guards is removed. Verified for `FORCE ROW LEVEL SECURITY`, the MARKUP
   coverage assertion, and `orphan_risk`.
4. Security suites run as `NOSUPERUSER NOBYPASSRLS`. Run as `postgres` they
   measure nothing.
6. **A threshold that governs a real-world signal must be measured against that
   signal, not chosen.** Guessed constants look like code and behave like
   assumptions. The OCR limits were swept against real tesseract and the
   measurements are recorded beside them.
5. **The reporting is part of the test surface** — including prose. Totals are
   computed by summing what each suite reports, never asserted, and a figure
   quoted in a canonical document is checked against the computed value (C7). A suite reporting zero assertions is
   a failure, not a pass. A hardcoded total in a build script is the same defect
   class as a test that cannot fail. Enforced by `tools/verify.sh`, itself proven
   to fail on both a dead database and a silent suite.

### 20.5 Recommended Phase 0 exit order

1. **API layer** over the existing engines — the packages are pure and portless
   by design, so this is wiring, not design.
2. **Auth**, because `withSession()` is inert until something can produce a
   verified principal, and P6/P7 depend on it entirely.
3. **Object storage + the retention reaper.** `expires_at` currently expires a
   row while the blob lives forever. That is a live COPPA exposure the moment
   real media exists.
4. **Flutter shell** — child and guardian, two screens each, against real APIs.
5. **LiveKit server + push**, last, because a call that cannot ring is a demo
   problem rather than an architecture problem.

---

## §8.5.0 The entry gate — which side is this?

**New v0.41.0.** Raised as an idea to make onboarding "all-inclusive and
comprehensive" — one unified modal that reads an age and decides whether the
device becomes the child's kiosk or the guardian's full app. **Evaluated and
rejected in that exact form**, then rebuilt into something that keeps the
underlying goal.

**Why the original form doesn't ship.** `AgeStep` (§8.5, below) already exists
to guard against precisely this failure mode one layer down: *"a six-year-old
who taps '10' ... must not thereby unlock a privacy tier."* Routing FULL
GUARDIAN AUTHORITY off a self-reported, unverified age is the same mistake at
a far higher stakes level — court exports, the other guardian's private
handoff notes, financial data, message-deletion authority, the child's own
emergency card, all reachable by whoever types the larger number. It would
also have quietly narrowed §21's continuous 2–17 maturation ladder down to
"child mode ends at 10," which is not what §21 says and not something this
proposal was trying to change.

**What ships instead: a role question, not an age gate.** Two buttons — *"my
child's device"* or *"the grown-up's device."* Nothing about this screen
grants anything:

- Choosing **child** routes, unchanged, into the existing first-run flow
  below (`begin()`, ages 2–17, still feeding §21).
- Choosing **grown-up** routes to the real account path — passkey/WebAuthn
  (§11) — and every guardian capability afterward is still gated exactly as
  it always was, by `family-graph/authorize.ts`'s `can()`, which reads real
  edges and has never heard of this screen. The test suite proves this
  directly rather than merely asserting it: it calls the real authorizer
  with a guardian-role tap and zero edges, and confirms denial.

**Suggestion, never authority.** A device that already has a child's birth
date on record (because a guardian set one up here before) pre-highlights the
child button. Absence of a birth date suggests nothing — it never defaults
toward guardian, since defaulting toward the higher-authority side on missing
information would be the same mistake wearing a different shape.

**One more clarification this raised:** the child side is not a one-way
"receiver." She already sends homework photos, drawings, showcase items, and
letters *to* the guardian side today (§9.1, §9.10, §9.12.4, §9). Nothing about
this gate changes that; it was worth naming so the "transmitter/receiver"
framing doesn't quietly become the mental model going forward.

---

## §8.5 The child's first run

Three steps. She spells her name, taps her age, and is **told** who she is here
to talk to.

**Nothing here may fail and no step may trap her.** Every step is skippable,
because a five-year-old who cannot get past screen one has been locked out of her
father — the worst outcome this product can produce.

### 8.5.1 She spells her own name

Spelling your own name is very often the first thing a child learns to write, so
the app opens by asking for the one thing she is already certain she can do.

**Her spelling stands.** If she writes OLIVEE, the app says OLIVEE. Correcting a
child's spelling of her own name on the first screen of a product about being
known by her father would be a small, precise cruelty — and §21's direction of
travel is authority toward the child, starting here. The guardian-entered legal
name remains on the record for exports and the emergency card; this is her name
inside her app, and `renameSelf()` lets her change it any time without asking.

Copy in this flow is audited: `auditOnboardingCopy()` refuses *try again*,
*invalid*, *wrong* — and equally *well done*, *good job*, *nearly*. **She is not
being tested, so she may be neither corrected nor praised for getting it right.**

### 8.5.2 She taps her age, and it is not believed

Age gates real things: which games unlock (§9.2), the ping band (§9.9), the §21
rung, the §21.5 quieting schedule.

So a six-year-old who taps *10* because ten sounds better must not thereby unlock
a privacy tier.

| | |
|---|---|
| `selfReported` | What she tapped. Kept, never discarded. |
| `authoritative` | Derived from the guardian's birth date. **Wins, always.** |
| `disagrees` | Recorded, not silently overwritten. |
| `effectiveAge()` | What every other module reads. |

**Nothing a child taps can raise a gate.** This also matters under §10.2: age is
a COPPA-relevant fact and cannot rest on a tap by the subject. Where no birth
date exists at all, her figure is used and the outcome carries
`ageWasSelfReportedOnly: true` so the guardian side knows the footing it is on.

### 8.5.3 She is told who is here — she does not choose

**§17.1 — with one grown-up in the family graph, no choice is presented at all.**

That is not a shortcut. Asking a child to pick between Mummy and Daddy on the
first screen of a co-parenting product would be tactless at best, and §2.4 says
the child never sees the machinery of conflict. **She is not choosing which
parent exists; she is being told who is already here.**

- A parent who has not accepted the invitation appears greyed, and nothing more.
  No nudge, no "invite them", no empty state implying something is missing
  (§2.12, §17.5).
- Where nobody has joined yet, that is a supported state with neutral copy —
  *"Nobody is here yet. We will let you know when they are."*
- Where two have joined, both are selected by default, and **the last one cannot
  be deselected.** She may never end up with nobody.
- Labels are each guardian's **own word** — Daddy, Papa, Baba, Mum, Mama, Nana.
  Hard-coding "Mommy" and "Daddy" would fail a great many families.


---

## §8.6 Her colour

She picks a colour. It is hers, it appears in the app, and her father can see it.
Three problems have to be solved for that to be worth building rather than
decorative.

### 8.6.1 A curated palette, and contrast is never her problem

Twelve swatches, not a colour picker. A free picker hands a five-year-old the
ability to choose `#FEFEFE` and then wonder why nothing changed. Labels are her
words — *sunny yellow*, *sea blue*, *storm grey*.

She picks yellow, and yellow text on white is unreadable. **The answer is not to
refuse her choice.** The pure hue is used for fills, where legibility is not at
stake, and a pre-derived `inkHex` is used wherever the colour has to carry text.
All twelve are asserted to pass WCAG AA as ink. **She never learns that her
favourite colour was a problem, because it was not one.**

There is deliberately **no pure red**: red means a prohibition everywhere else in
this product, and a child should not have to fight the warning colour for her own
accent.

### 8.6.2 The placement budget — the oversaturation guard

The naive implementation sets one accent variable and the whole app turns hot
pink. Worse, it collides with the **semantic** colours the Day Ribbon depends on.

| | |
|---|---|
| **Allowed** | accent stripe · avatar ring · sleeps numeral · game piece · header flourish · loading dots · collection tile · show frame |
| **Forbidden** | prohibition · error · warning · destructive · ribbon band · day part · overlap band · now line · medication block · expiry digest · court export · body text · background · surface |
| **Budget** | `MAX_PLACEMENTS_PER_SCREEN = 3` |

The forbidden list is the important half, and it is deliberately the longer one.
Every entry there is a colour that **means** something: a ribbon band encodes what
she is doing, the overlap green means *"you can both talk right now"*, red means a
prohibition. If her colour could land in any of those, the Day Ribbon stops being
readable and a warning stops looking like a warning.

`applyColour()` refuses a forbidden placement outright rather than trusting a
stylesheet, and silently **drops** anything past the budget — beyond three, the
colour stops reading as *hers* and starts reading as a theme.

### 8.6.3 "Which do you like more today?"

A two-up rather than the full twelve: lower effort than a grid, it plays like a
game rather than a settings screen, and it produces a history worth printing.

**One of the pair is always her current colour**, and the side is randomised so
hers is not always on the left. Keeping it is therefore exactly as easy as
changing it — *a daily prompt that nudged toward change would be manufacturing
churn out of a child.*

A year of colours becomes a Year Book section (§9.8.2), and it is the cheapest
one in the product: twelve swatches and a count.

### 8.6.4 A colour is a fact, not a mood

**This is the prohibition the module exists to hold.**

*"She picked grey today — is she sad?"* is the product making a psychological
claim about a child from a tap. A parent acting on that claim will get it wrong
in a way that costs them the exchange, and a product that offers the inference
has invited them to.

So the parent is told **what she picked and nothing else**. There is no sentiment
field, no trend, no *"her colours have been darker this week"*, and **no field in
which such a thing could be recorded** — `auditColourPayload()` refuses `mood`,
`sentiment`, `feeling`, `trend`, `concern`, `flag` and `volatility` anywhere in
the payload.

The interpretation, if there is one, belongs to the parent who knows her. It is
reached by asking her, which is the entire point of the product.


---

## §8.7 She places her own birthday

The fourth step of the first run, after her colour. She finds her birthday on the
calendar and marks it — permanently.

### 8.7.1 One month grid for the whole product

`monthGrid()` is the single month renderer. The child's calendar (§9.4), the
guardian's, the exchange schedule and this picker all read it: seven columns
aligned to the week, with leading and trailing blanks as **real cells** so no
consumer has to compute offsets.

A throwaway picker would have been quicker and would have drifted from the real
calendar within two increments. It is the same grid or it is not worth building.

US market scope (§1), so weeks begin on Sunday.

### 8.7.2 The hard part is the year, so she is never asked for it

A six-year-old finding a date six years in the past is genuinely difficult.
Scrolling back 72 months is 72 taps, and she may not know the year at all.

But she almost certainly knows the **month** and the **number**. So those are the
only two things she is asked for, and the year is **derived**:

| Input | Source |
|---|---|
| Month | She taps it, from twelve named tiles |
| Day | She taps it, on the real month grid |
| Year | `deriveBirthYear(age, hadBirthdayThisYear)` — her age from §8.5.2, plus **one yes/no** |

*"Have you had your birthday this year?"* is a question a five-year-old can answer
with certainty, and it is the only ambiguity that exists. Where a guardian has
already entered the birth date, even that question disappears.

### 8.7.3 The hint is a nudge, not an answer

When a guardian's date is on file, the correct month is outlined. She still does
the finding; the hunt is simply short enough to succeed.

`shouldHint()` returns false from age **nine** — scaffolding that withdraws,
exactly as §21.5 requires. A nine-year-old finding her own birthday needs no help,
and offering it would be the kind of small condescension that section exists to
prevent.

### 8.7.4 She is not corrected about her own birthday

If she places it a day out from the guardian's date, the guardian's date remains
of record, **hers is kept**, and the disagreement is recorded — never surfaced.

> Being corrected about your own birthday, by software, in front of nobody, is a
> small humiliation with no upside.

Where no guardian date exists, hers **is** the record.

### 8.7.5 The permanent marker

| Property | Value | Why |
|---|---|---|
| `recurrence` | `'yearly'` | |
| `deletableByGuardian` | literal `false` | A birthday is a fact, not a preference. |
| `colourId` | hers, from §8.6 | An allowed placement under the §8.6.2 budget. |
| `placedByChild` | recorded | Because it mattered to her. |
| Year | **not on the event** | It lives on the child record; the event is a month and a day. |

**29 February needs an explicit rule** or the event silently vanishes three years
in four. The birthday is observed on **28 February** in a common year — the choice
more families make, and more to the point it keeps the birthday inside the correct
month, which is what a child cares about.

### 8.7.6 Her calendar begins with her birthday

That ordering is the reason this step sits in onboarding at all.

**The first entry a child ever sees in a co-parenting product should be a thing
she is looking forward to** — not a custody exchange. The label reads *"My
birthday"*, and the suite asserts that no custody vocabulary appears anywhere near
it.


---

## §5.23–§5.25 The call, properly

Thirty-four recommendations, built. Three concerns.

### 5.23 Audio-only is a choice, not a punishment

Voice-only has been a thing the network does to you. It should be a thing she
chooses — a self-conscious eleven-year-old, a bad hair day, a child who simply
does not want to be seen today.

> **He is told the call is voice-only. He is never told why.**
>
> "She chose not to be seen" is a fact a parent will overinterpret, and the
> overinterpretation lands on her. The reason is hers.

The voice-only answer button is **the same size** as the video one — a smaller
button is a judgement and she will read it as one. And there is never a black
rectangle: her colour, a slow waveform (4 Hz, because a fast one is a stimulant at
bedtime), or the canvas.

**Bedtime mode** dims the screen to 8% with no video at all, because a lit screen
undoes the reading. **Push-to-talk** is a walkie-talkie — a five-year-old already
understands one, and it sits exactly between banked messages and a live call.

### 5.23.2 When it goes wrong

**A frozen father and an ended call are the same event to a five-year-old**, and
they are not the same thing.

| State | What she is told |
|---|---|
| frozen | *"The picture stopped. He is still there."* |
| dropped | *"It stopped. We are getting him back."* |
| ended | *"That is the end of the call."* |

Eleven phrases are banned from a child's screen, including **"failed"**, **"poor
connection"** and **"check your network"** — a five-year-old cannot check her
network and should not be asked to.

The **degradation ladder** is HD → SD → audio-only → banked. The call falls *down*
the ladder rather than off it, and the bottom rung always works.

Reconnection preserves the game, the story position and the half-coloured picture
— losing them is how a child learns not to bother starting anything on a call. And
**resuming asks first**: a call that reconnects itself and starts transmitting a
child's bedroom because the wifi came back is a privacy failure with good
intentions.

### 5.24.1 The rear camera is the point

"Show me" during a call is turning the phone around. Every other product treats
the rear camera as an afterthought; here it is **the showcase (§9.10) happening
live**.

**Flipping to the rear turns mirroring off.** A mirrored rear camera renders every
word she holds up backwards — the single most common complaint about showing a
drawing on a video call, and the thing that made the homework case useless.

The torch is rear-only, because offering it on the front is a flash in the face.
Lighting advice is about the **room**, never about her.

### 5.24.2 P10 — no appearance modification on a child's video

**No beauty filters, no smoothing, no slimming, no eye enlargement, no
"touch-up".** Not as a default, not as an option, not as a fun sticker that
happens to reshape a face.

> Appearance modification aimed at a child is a self-image harm wearing a fun hat.
> It teaches a five-year-old that the version of her face the software prefers is
> better than the one her father sees — and it does it during the one activity in
> this product that exists so he can see her.

It costs nothing to prohibit today and becomes very expensive to remove later,
because by then it is a feature somebody likes. **Dog ears are fine.**

**Virtual backgrounds, settled:** allowed for a guardian, refused for a child. An
adult may have good reason not to show a room. A child's background is the only
thing in a call that tells the other parent she is somewhere ordinary, and it
arrives without anybody deciding to send it.

### 5.24.4 Picture-in-picture conflicts with the lock

PiP exists so a call survives you leaving the app. **A child in kiosk mode cannot
leave the app** — that is what the lock is for. So on her device PiP solves a
problem she does not have, and implementing it would mean punching a hole in the
thing that keeps her in one place.

**PiP is guardian-only**, and that is a structural conclusion rather than a
limitation. It also means what the product has been calling "picture in picture"
in game layouts is a *layout*, not PiP — a distinction the name was quietly
borrowing authority from.

> **§5.24.4, REVISED 2026-08-24.** The above is superseded, at the owner's
> explicit, informed direction — not a limitation this codebase found a way
> around unilaterally. Real OS PiP now ships for the child too. The tension
> named above is real and was not waved away: **PiP genuinely does punch a
> hole in what kiosk lock guarantees**, because a PiP window is not
> full-screen and whatever sits behind it is reachable. What changed is the
> mitigation, not the tension — a real native fix (`KioskBridge.kt`'s
> `ACTION_CALL_ACTIVITY_DESTROYED`, `MainActivity.kt`'s `onResume()`)
> closes the specific hole this decision opens: the original one-shot
> "consume the handoff flag on first resume" design would have left a
> kiosk-locked device unpinned after a real call end if PiP had ever been
> entered mid-call. The fix re-pins on **every** resume while a call
> handoff is outstanding, and only a real Activity-destroyed signal — never
> a mere resume — clears that flag. **Live-device verified, not just
> compiled**: a genuine `LOCK_TASK_MODE_PINNED` state, the real system "App
> is pinned" dialog, and `beginCallHandoff`'s unpin/re-pin sequence all
> traced correctly through `dumpsys`/logcat on a real tablet.
>
> **Correction, same pass:** the original plan also paired PiP with an
> automatic "open a shared drawing screen the moment she PiPs" feature —
> built, then live-tested and reverted, because the assumption it depended
> on ("entering PiP resumes the host Activity exactly the way a genuine
> call end does") turned out false for the path a child would actually
> use. Pressing Home to trigger PiP does **not** reliably resume
> `MainActivity` — `dumpsys` traced the real cause to Android's own
> `RootWindowContainer.startHomeOnTaskDisplayArea`: once Home is pressed,
> WindowManagerService has already decided the launcher is the sanctioned
> host behind that PiP window, and re-asserts it regardless of what an
> ordinary app does afterward. Three native mitigations were tried and
> live-tested; all three lost to this same system policy. The re-pin fix
> above is unaffected by this — it re-pins correctly on every genuine
> `MainActivity` resume, however she gets there — but nothing auto-navigates
> her to an activity screen on PiP entry. She can still reach Doodle Desk
> on her own, from her own menu. See CHANGELOG v0.49.36 for the full
> account. The layout-not-PiP distinction the paragraph above draws still
> stands — this section is about the real, OS-level PiP only.

### 5.25 The Fold, mid-call

A hinge is not a lifecycle event. Folding, unfolding and standing the phone up are
things she does *while* talking to her father, and every one of them destroyed the
call until now. `HINGE_NEVER_ENDS_CALL`.

Half-open is the only posture that announces itself: *"You can put it down now —
he can still see you."*

### 5.25.2 Knocking, not ringing

A ring demands answering. A knock waits ninety seconds, never escalates, and
becomes a banked message — and he is told *"she did not come to it"*, never that
she declined. **"Not now" is a real answer and is not a decline**; the word
`decline` is banned from the answer surface.

**Wired into the Flutter client as of v0.49.12.** `call_knock.dart` is a
deliberately partial 1:1 port of `lifecycle.ts`'s own §5.25.2 section —
`Knock`/`knockUnanswered()`/`ANSWER_WORDS`/`ANSWER_BANNED`/`notNowOutcome()`,
nothing else from that file, since nothing else is called client-side.
`call_knock_screen.dart` is the real, calm UI on top of it: no numeric
countdown, no urgent color, three real answer buttons ("Answer"/"Just
talking" both lead to the same real `CallScreen` join — the source names no
technical difference between them, and none is invented here; "Not now"
shows the real gentle line then dismisses on its own), and an unanswered
knock times out after the real 90 seconds and dismisses itself with zero
missed-call framing, per §9.13.4's own rule applied here. A speaker button
(§8.8.5) reads the prompt and every answer option back verbatim —
**genuinely, as of a v0.49.14 fix**: as first shipped in v0.49.12, this
line was not actually true. The spoken text appended a hand-composed
instructional sentence ("You can answer, say you are just talking, or say
not now.") that appeared nowhere on screen, and the read-aloud call site
skipped the `admitSpeech()` gate every sibling screen (`emergency_card.
dart`, `handover_notes.dart`) uses — both found by an adversarial audit,
neither by a live incident. Both fixed: the spoken text is now the real
prompt, the real on-screen reassurance line, and the three real button
labels, nothing composed; the call site now gates through `admitSpeech
(SpeechTrigger.tap)` identically to its siblings. See CHANGELOG v0.49.14.
**Reachability, closed in two real steps since (v0.49.33/v0.49.34), corrected
here rather than left stale:** v0.49.33 gave the server a real trigger —
`POST /v1/children/:childId/calls` (`server/routes.mjs`) mints a session,
authorizes the caller, and calls `notify.ts`'s `notifyDevices()` with a real
`call_incoming` kind. v0.49.34 gave the client a real caller for it —
`OliveApi.startCall()`, reached from `guardian_more.dart`'s own "Call
$childName" tile — and `child_home_live.dart`'s `_LiveChildHomeScreenState`
now wires `buildCallIncomingHandler()` to `PushChannel.onForegroundPointer`
for real, gated on `widget.navigatorKey` being supplied (null is an honest,
unchanged absence for a build with no navigator key, not a regression). What
remains genuinely unreachable, not fabricated around: no real
`google-services.json`/FCM or APNs credential exists anywhere in this
environment, so an actual push still cannot land on a real device — verified
live anyway (two physical devices, guardian tap to child answer, in real
time) via a dev-only bridge confined to already-dev-only test files, standing
in for exactly that one undeliverable hop. See CHANGELOG v0.49.33/v0.49.34
for the full account. The code-comment-only "§5.25.5 waiting room" in
`lifecycle.ts` — no matching MASTERFILE section backs it — remains unbuilt
and out of scope: it needs a real supervisor-facing admission UI, which would
mean inventing product decisions this codebase has already, separately,
declined to make unilaterally (`therapist_role_visibility_scope` and its
siblings, per the engine-capacity scoping pass).

### 5.25.4 Both-free windows, finally used

The Day Ribbon has computed the overlap since v0.2.0 and never offered to start a
call with it. It does now — **to the guardian only.** A prompt telling a
five-year-old that now would be a good time to call her father makes his
availability her responsibility.


---

## §5.26 The pane

**The core move is not to use the OS at all.**

Android Go disables platform PiP outright. FireOS reports Android 9 and may still
refuse it. And screen pinning / lock-task mode — the very mechanism that keeps a
child inside the app — **blocks the PiP API by design.** The kiosk and the platform
feature are mutually exclusive on exactly the hardware that matters most.

So the pane is a positioned view inside our own hierarchy. No platform API, no
firmware dependency, no permission, no kiosk conflict. **It renders identically on
a £50 Fire tablet and a Fold, because it is a box we draw.**

That also makes "PiP" mean something honest on her side: the call keeps running
while she moves between *our* surfaces, which is the only "somewhere else" a
locked app has.

### 5.26.1 Docked, not floating

Four magnetic corners. A five-year-old dragging a small target loses it behind her
own thumb, and a video she cannot find is a video that is not there.

Corners are also **position without coordinates** — they survive rotation, folding
and a text-scale change with no arithmetic at all, which is the second reason to
prefer them. `FREE_DRAG_ALLOWED = false`.

### 5.26.2 Three sizes, no pinch

Small, medium, large as a single toggle. Pinch-resizing a video is a lost video:
the gesture is imprecise, it competes with everything else on a touch surface, and
there is no undo for *"it is now four pixels wide"*.

### 5.26.3 The floor is a face, expressed relatively

A fixed 96 px is wrong in both directions — a postage stamp on a 10-inch tablet,
and a screen-filler on a 344 px cover display.

The pane is a fraction of the **shorter** viewport dimension, with an absolute
floor of 88 px beneath it. On the Fold's cover screen `large` therefore covers
7.6% rather than the 30%+ a width-based calculation would have produced, and it
can never fall below a recognisable face.

### 5.26.4 She cannot close it

**There is no dismiss button on a child's pane.**

> A child who accidentally loses her father's face and cannot work out how to get
> it back has lost the call — and she will not say so, she will just go quiet.

`closePane(p, 'child')` returns `child_cannot_close`. Only ending the call ends the
pane. She may move it and resize it; `childControls().close` is a literal `false`,
and the child view is audited for any close, dismiss, hide or remove affordance.

### 5.26.5 The pane yields; she never has to

An active surface declares where her hands are — the region she is colouring, the
word she is tapping — and the pane relocates to the corner furthest from **every**
hot zone, not merely the nearest one. It snaps home once her hands move away, so
it does not wander permanently.

Distances are computed in viewport fractions, so the behaviour is
resolution-independent.

### 5.26.6 Audio is decoupled entirely

**If the pane fails, is occluded, or the renderer dies, the audio never drops.**

The video is the enhancement; the voice is the call. On the hardware this has to
run on, a renderer falling over is a Tuesday — and a child who can still hear her
father has not lost anything that matters. She is told *"the picture has gone for a
minute. You can still hear him"*, which is not framed as a failure.

### 5.26.7 On a low tier, a still frame

A 2 GB tablet running a live pane *and* a game is a dropped call. A photograph of
her father plus his voice beats a frozen call and costs almost nothing to render.

The still frame **says nothing about itself** — a frame that announces itself is an
apology.

### 5.26.8 Two surfaces refuse it

| Surface | Why |
|---|---|
| Homework capture | The rear camera is composing a document and the capture guide needs the whole frame. Two competing camera surfaces is a confusion, not a feature. |
| Fold tabletop | That posture already gives video the best position it will ever have, above the crease at eye level. Shrinking it there is strictly worse. |

### 5.26.9 The probe attempts and verifies — it never asks

`Build.VERSION.SDK_INT >= 26` is a lie on FireOS, which reports Android 9 and may
still refuse. Android Go disables PiP while reporting a version that supports it.
Lock-task mode blocks it with no capability flag at all.

So the probe **tries**, confirms the mode was actually entered, and falls back
silently. Only the observation counts; the claim is ignored entirely.

**`OS_PIP_IS_NEVER_LOAD_BEARING`** — OS PiP is progressive enhancement for a
guardian and nothing more. Every path through `effectivePane()` returns either an
OS window or the in-app pane, on any hardware and firmware combination.

> **§5.26, REVISED 2026-08-24.** Two claims above are superseded, for the same
> reason given at §5.24.4's own REVISED note: at the owner's explicit, informed
> direction, real OS PiP now ships for the child too. First, the section's own
> opening — that screen pinning / lock-task mode "blocks the PiP API by design"
> and that "the kiosk and the platform feature are mutually exclusive on
> exactly the hardware that matters most" — no longer holds. They coexist: a
> genuine kiosk re-pin fix (`KioskBridge.kt`'s `ACTION_CALL_ACTIVITY_DESTROYED`,
> `MainActivity.kt`'s `onResume()` re-pinning on every resume while a handoff
> is outstanding) closes the hole a floating, non-full-screen PiP window opens
> in what the pin guarantees, live-verified on a real tablet. v0.49.38 hardened
> this further: `startLockTask()` is now polled for genuine settlement rather
> than fire-and-forget, and `onPictureInPictureModeChanged` gives real-time
> detection if a pin is silently lost mid-PiP. Second, this subsection's own
> `OS_PIP_IS_NEVER_LOAD_BEARING` line — "OS PiP is progressive enhancement for
> a guardian and nothing more" — is corrected the same way: `call_screen.dart`'s
> `callFeatureFlagsFor()` now sets `pipEnabled`/`pipWhileScreenSharingEnabled`
> true unconditionally, not `isGuardian`-only, so OS PiP is progressive
> enhancement for **both roles**.
>
> What does **not** change: the pane itself is real, still built, and still
> needed — this was not a limitation the codebase found a way around
> unilaterally, and nothing above about the pane's own behaviour (§5.26.1
> through §5.26.8) is affected. Android Go still disables platform PiP
> outright; FireOS still misreports its own version and may still refuse it;
> low-tier hardware still falls back to the still frame (§5.26.7); homework
> capture and the Fold tabletop posture still refuse the pane entirely
> (§5.26.8), regardless of role. The pane was never solely a child-side
> workaround for a permanently guardian-only OS feature — it is, and remains,
> whatever `effectivePane()` falls back to on any hardware or firmware
> combination where the real thing is unavailable or already refused, for
> whichever role hits that condition. See CHANGELOG v0.49.35 (the containment
> fix that first made these flags genuinely role-conditional at all), v0.49.36
> (real PiP for the child, live-verified) and v0.49.38 (the kiosk re-pin
> hardening) for the full account.

---

## §5.27 The come-back signal

**Bolstered v0.42.0 — reachable-hours deferral, amending §5.27.7's own
Silent hours/Blocked window rows below.** (Cited as "§5.27.9" for years —
a 2026-08-24 audit found no such subsection was ever actually written;
§5.27 only defines .1 through .8. Corrected to name the real section this
note amends, rather than a phantom one.) Previously, a
signal blocked by silent hours or a blocked window was simply dropped, and
because §5.27.6 already (correctly) shows the sender nothing, a dropped
signal was indistinguishable from one that arrived and was ignored. It is now
deferred to the next reachable window instead — capped at one, never a
queue — the same graceful-degradation philosophy as the quality ladder
(§5.28) and a live game's async fallback. See §8.15 for the pattern this now
fits into.

**He requests. She acts.**

No data flows back, no control channel exists, and the child performs every action
herself. That single constraint is what lets this expand to sixteen applications
safely — each inherits the same safety rather than needing its own argument.

It exists because the alternative was remote control of a child's device, which is
a stalkerware primitive however kindly it is framed. **P11** forbids that outright,
*including for the child's benefit* — the benign framing is exactly how it would be
reintroduced in two years.

### 5.27.1 Sixteen applications

Come back · I'm here · Look at this · Show me that again · Turn it round · Can you
hear me · Louder · Nearly bedtime · Your turn · Wave to Mum · Running late · Say
goodnight · Someone says hello · Sorry, my end · Nearly there · Well done.

*Can you hear me* is visual by necessity — it is the only channel that survives the
failure it is diagnosing. *Sorry, my end* exists to take blame off a child who will
otherwise assume it. *Wave to Mum* and *Nearly bedtime* may only come from the
parent physically present, per §9.13.3.

### 5.27.2 Who may send — settled

**Only a parent.** Not a grandparent, a stepparent, a caregiver, a therapist or a
coordinator. The signal is a parent–child channel; widening it makes it a household
broadcast, and **anyone in the room with her can simply speak.**

### 5.27.3 The four family shapes

Both parents, one parent only, sole guardian — the mechanic is identical in all
three. **Both parents in the same house: the whole mechanic stands down.** A signal
from somebody in the next room is absurd, and a product looking absurd there is how
a family stops trusting it.

> **The signal never reveals the family's shape to the child.** One parent or two,
> restricted or not, present or absent — it looks and behaves the same. She should
> not be able to infer her parents' legal arrangement from a prompt on her tablet.

### 5.27.4 Priority

1. **Safety** overrides everything.
2. **Presence loses to absence** — the parent she is with can simply talk to her.
3. **In-call** beats out-of-call.
4. Then simply **first**.

No seniority, no primary/secondary, no custody weighting. **Under no circumstances
does the order of a court order become the order of a prompt on a child's screen.**

The loser is never told they lost — that is a competition she would be the prize in.

### 5.27.5 The entry gate

A prompt that always appears in the same place **will** be tapped by accident. An
application whose action is not harmless under that condition **cannot use this
pattern**, and `admitApplication()` refuses it at construction rather than in
review.

### 5.27.6 The ignored signal is invisible — settled

**The sender sees nothing, ever.** No count, no badge, no *"she hasn't responded."*

Three unanswered come-backs in an evening is information a parent would act on, and
whatever the product did with it would have consequences. If he needs to know she
is alright, that is a phone call to the other adult — **not an inference drawn from
a child's non-tap.**

### 5.27.7 The rules

| Rule | Value |
|---|---|
| One at a time | A second replaces the first. A queue is a demand list. |
| Expiry | 90 s, silently. A prompt still there twenty minutes later is a reproach. |
| Daily ceiling | **12**, independent of the age bands — 16 applications × 2 parents could satisfy every individual rule and still deliver forty. |
| Silent hours | 20:00–07:00, emergency card excepted. |
| Blocked window | School, asleep, wind-down — it banks like everything else. |
| Mid-transition | **Dropped, not queued.** She is already going back. |
| Interruptibility | Declared per application; a busy surface defers all but `always`. |
| Child mute | One hour, one tap, no reason given, **nobody told**. If she cannot opt out, it is not a request. |
| Preservation | **Never.** Signals are gestures — not in the archive, not in a court export. Minuting gestures changes what people send. |

### 5.27.8 The escape hatch and the first-run lesson

From any surface, during any call, **one unmissable control** returns her to the
call — reachable in one tap, present everywhere, and not dismissible. It is the
signal's structural counterpart and the reason a *come back* is usually
unnecessary.

She meets the signal once, deliberately, in onboarding: her father sends the first
one and she taps it. **A pattern learned in a calm moment is one she recognises in
a confused one.**

---

## §8.8b The accessibility matrix

Built to be **extended and rolled out incrementally** rather than shipped complete.

Each form carries a readiness state — **shipped**, **scaffolded**, **specified**,
**considered** — so a form can be specified long before it is built and the build
can tell the difference. That is the F-series lesson applied to accessibility:
**promoting a form to `shipped` with an unmet requirement is refused**, and
readiness only ever moves forward.

| Readiness | Count | Examples |
|---|---|---|
| shipped | 9 | words, icon, his face, read aloud, her colour, soft sound, bigger words, stronger colours, less movement |
| scaffolded | 3 | haptic, dyslexia type, simplified language |
| specified | 4 | symbol set, switch access, longer to tap, one-handed reach |
| considered | 3 | signed video, braille, eye gaze |

### The rule that shapes it

**The signal is the product's only interruption pattern**, so it cannot be
sight-gated or hearing-gated. Every signal must be perceivable through **at least
two independent channels** — and the *baseline alone* satisfies that, covering
sight and hearing before any option is enabled.

Text alone is not perceivable. Sound alone is not perceivable. A scaffolded form
does not count toward coverage, because it does not render yet.

### It is data, not code

A form can be added at any time without touching a single consumer, because every
consumer reads the matrix rather than hard-coding a list. `rollout()` reports what
is shipped and what is next, so the roadmap stays honest.


---

## §8.8.5 Read-aloud for pre-readers

**New v0.39.0.** §8.8b's baseline `spoken` form covers the sixteen come-back-signal
applications — it guarantees a *signal* is never sight-gated. It does not cover
general navigation: a five-year-old still cannot tell what "My weeks" says on an
ordinary screen. Raised evaluating a Gemini-drafted alternate build, which put a
plain 🔊 button on every screen. The button was the right idea; this is the
safety-checked version.

**On-device only, always** — the same posture already settled for captions
(§8.8.1). A child's voice browsing her own calendar never leaves the device for a
cloud text-to-speech API.

**Reads the accessibility label, not a second copy of it.** `speakableText()`
sources the same string a screen reader already gets (§8.8.4's `LABELS`) wherever
one exists, falling back to visible text only where no label has been written yet.
Two hand-maintained strings for the same control is a drift bug waiting to happen;
this makes drift structurally impossible for anything with a label.

**Never autonomous.** Speech that starts itself, rather than in response to a tap,
is §8.13's slot-machine mechanic wearing a voice. `admitSpeech('autonomous')` is
refused unconditionally.

**Default-on below age 8**, opt-in above it — mirrors the birthday-hint fade
already used elsewhere (`HINT_FADES_AT_AGE`): a scaffolding aid that quietly stops
being necessary, rather than a setting a child has to go find and switch off.

**Ephemeral, never logged.** This is not §8.8.1's caption pipeline; nothing here
is retained, transcribed, or treated as call media.

**Wired into the Flutter client as of v0.49.10.** `a11y_speech.dart` is a 1:1
port of this section's own `speakableText()`/`admitSpeech()`, and
`tts_channel.dart` wraps `package:flutter_tts` for the real, on-device,
offline speech synthesis this section always specified — no cloud API was
ever called, and none is now. Two screens carry the first real speaker
buttons: `emergency_card.dart` (§9.6.3, reading the whole card back verbatim,
allergy-first — the same order a scanning eye already reads it in) and
`handover_notes.dart` (§21.7, P8, one button per entry, reading that entry
alone — never a composed summary across entries, so a parent scanning a long
log never gets an AI-flavored gloss on what the other parent actually wrote).
Both fall back to an honest "not built yet" message when no `speak` callback
is wired, matching every other real-but-unwired affordance in this codebase
rather than rendering nothing or pretending to work. The rest of this
section's own `LABELS` map, and the remaining fifteen of §8.8b's sixteen
come-back-signal applications, do not yet have a speaker button — this pass
closed the two highest-stakes surfaces, not the full sweep. See CHANGELOG
v0.49.10.


---

## §8.13 Motion

Everything on the child's side was static. A five-year-old reads a static
interface as a **picture** of an app rather than an app: things do not appear to
be touchable, and when they change they simply cut, which teaches her nothing
about where anything went.

### 8.13.1 The principle

> **Motion follows the finger. It never leads it.**

Every animation is either driven 1:1 by her gesture, or a consequence of
something she just did. **Nothing moves on its own to attract her** — and that one
rule is the difference between an interface that feels alive and a slot machine,
which is what children's software usually becomes.

| Kind | Allowed? |
|---|---|
| **driven** — 1:1 with her finger | always |
| **consequence** — a result of her action | yes, under 400 ms |
| **ambient** — slow, informational | only on four named surfaces |
| **autonomous** — moves to attract | **never** |

Ambient motion is permitted only where **the movement is the information**: a
waveform meaning *he is talking*, a recording dot meaning *this is recording*.
Everywhere else it is decoration competing for her attention.

### 8.13.2 One vocabulary, learned once

Ten gestures, each meaning exactly one thing across the whole product — the only
way sixteen surfaces stay legible to a five-year-old.

Notable choices:

- **Horizontal swipe always means siblings.** Cards, stories, months. Time is
  horizontal everywhere.
- **Scrobble** is how a child says *"go back a bit"* — dragging along a line is
  the only natural way to express it, and she will want the refrain again.
- **A dial rather than a slider**, because a dial has a centre to orbit and a
  slider has a line to stay on. A small hand wanders off a line.
- **Pinch is zoom only**, never resizing, and never before six.
- **Long-press is never the only route to anything** — a five-year-old lifts her
  finger.

> **`TAP_ALWAYS_SUFFICES`.** No gesture is ever the only way to reach something. A
> child who cannot make the shape, or whose hand is unsteady, gets everywhere by
> tapping.

### 8.13.3 Physics a child can predict

Spring, not linear. Children read a spring as a real object and a linear ease as a
slide show — the difference is legibility, not polish. Heavier things move slower,
which is how she learns what is heavy.

**No spring may overshoot more than 6%.** A bigger bounce reads as a reward, and
`springSettles()` refuses it.

**Rubber-band at the edges**, because that is how a child learns there is nothing
more — far better than a wall, which reads as broken.

### 8.13.4 Wordless instruction

A pre-reader cannot be *told* to swipe. So a swipeable row shows a **22 px peek**
of the next item: the single most effective piece of wordless instruction
available, and it costs a few pixels.

Touching a draggable thing moves it slightly within 40 ms, before a drag has even
registered. That tiny response is what tells her it is hers to move.

### 8.13.5 Where motion is a bad idea

| Surface | | Why |
|---|---|---|
| bedtime | **still** | Movement on a lit screen undoes the reading it accompanies. |
| homework | **still** | The one surface in the product that asks her to concentrate. |
| journal | **still** | Somewhere to think. Nothing should move while she does. |
| emergency card | **still** | Read once, in a hurry, possibly by a frightened child. |
| come-back signal | reduced | A prompt that is itself a moving distraction defeats its own purpose. |
| story reading | reduced | The refrain is the only thing that should draw the eye. |
| wind-down | reduced | The whole point of the window is that things are slowing. |

Reduced motion (§8.8) **composes** with these, and the quieter of the two always
wins — an accessibility setting is never overridden by a surface default.

**"Still" means a crossfade, not a cut.** A hard cut is disorienting in its own
way; a crossfade with no travel reads as calm rather than broken.

### 8.13.6 The budget

**Two moving things at once.** Three is a distraction — the same construction as
§8.6.2's colour placement budget, for the same reason.

Nothing loops outside the ambient set. Nothing ever auto-plays.

> **Celebration once is delight. Every time is a reward schedule.**

`celebrate()` returns `play: false` from the second occurrence onward, and P2
exists because habits trained into children are hard to untrain.

### 8.13.8 The touch chime

**New v0.39.0.** Raised evaluating a Gemini-drafted alternate build, which fired
a Web Audio "pop" on every touch. The idea is cheap (§8.14: a synthesized
oscillator is negligible against the capability budget) and good; it needed the
same discipline every other sound in this section already has.

A chime is **consequence motion wearing sound instead of pixels** — not a fifth
category. It inherits §8.13.1–§8.13.6 wholesale: it fires only after something
she did, never autonomously; it is silent wherever the surface is `still`
(bedtime, homework, journal, emergency card — exactly the list a wiggle is
banned from); and it never loops. `chimeAllowed()` composes a one-tap mute
setting with the same surface-quietness table motion already reads, so a
household that needs silence — a classroom, a shared bedroom — gets it
regardless of surface.


---

## §5.28 Stream stability · §8.14 The capability budget

**Renumbered v0.39.1.** Previously double-booked at §5.27, which the come-back
signal (above) already owns — every prose reference to "§5.27" in this document
(P11, §16.2 #12) means the come-back signal, so this section was the intruder.
Moved here rather than the other way around, since the come-back signal's
number is load-bearing in more places.

### 5.28 The quality ladder sits under the rung ladder

`LADDER` already said HD → SD → audio-only → banked. What it lacked was
**hysteresis** — and without it, a wobbling connection flickers between rungs
every few seconds.

> A picture that keeps appearing and vanishing is worse than no picture at all. It
> draws the eye each time; she looks up expecting her father and gets a grey
> rectangle. **She will stop looking up.**

Three video qualities — 720, 360, 180 — sit *underneath* the rung ladder, so by
the time it drops to audio-only, three steps have already been tried.

**Quick to shed, slow to restore.** Two seconds down, twelve seconds up: a
connection that has been bad for twenty seconds and good for two is not a good
connection, and treating it as one produces exactly the flicker this exists to
prevent. One step per evaluation, never two — a collapse walks down, and each step
is a chance to stabilise.

She is told **once**: *"It has gone a bit slow — you can still hear him."* Never a
banner that lingers, and **no connection meter** — a five-year-old watching a
signal indicator is a five-year-old not watching her father. Nine phrases banned,
including *"your connection"* and *"check your"*.

**Video returning does not ask permission.** `resumeOffer()` is for a call that
dropped and reconnected — a new transmission. A picture coming back inside a call
that never stopped is not that, and asking would interrupt the thing it improves.

### 8.14 The budget

The device matrix declared three tiers, and **exactly one thing consumed them:
the call.** Games, colouring, the gallery, the storyteller and the pane each
assumed independently what the hardware could do, and none of them checked.

A 2 GB tablet running the pane, a checkers board and a waveform had three claims
that were each individually reasonable. **Nothing computed the total, because
there was no budget to compute against.**

Fifteen features declare a cost in memory, decode load, surfaces, cameras and
sockets. Three capacities. And a resolution order:

| Order | What gives |
|---|---|
| 1 | ambient motion |
| 2 | video quality, **by substitution** |
| 3 | the pane, to a still frame |
| 4 | concurrent activity |
| 5 | video entirely |
| — | **the voice, never** |

`NEVER_SHED` contains `call_audio`, and the shedding loop **refuses to consider
it** — a stronger guarantee than sorting it last. `audioAlwaysSurvives()` asserts
it across every scenario on every tier.

**Substitution before removal**, because a smaller picture is better than no
picture.

### The budget is binding, not advisory

An advisory budget is the same class of thing as a declaration with nothing behind
it — which the F-series exists to catch.

`admit()` also **discloses what admitting cost**. A first version returned a bare
`{ ok: true }` when a feature fitted only because something else had been
substituted: the caller was told it succeeded and not that the video had dropped
to 360 to make room. Admitting without disclosing the cost is a quieter version of
the advisory budget this module exists to avoid.

### Ceilings

Seven, each with a reason rather than a number: a group call caps at four because
beyond that the solo rotation outlasts a child's patience; the story library at
300 because past that a shelf becomes a search problem, which a five-year-old
cannot use.

### H1–H5

Every expensive feature declares a cost; the voice outranks everything; ceilings
exist for the modules that need them; **no ceiling is a bare magic number**; and
the quality ladder is asymmetric. H1 and H5 were both shown to fail when their
guard was removed.


---

## §8.15 The sync/async pairing pattern

**New v0.42.0**, formalising a pattern that already existed piecemeal across
the product before this section had a name. Raised as a direct request: make
sure every activity has both a synchronous and asynchronous form where one
makes sense, and that both account for the family's time difference — the
same governing philosophy already proven in two other places in this spec:

- **The quality ladder** (§5.28) — a call never fails outright. It steps down
  720p → 360p → 180p → audio-only, one rung at a time, and the voice —
  priority 100 in §8.14's capability budget, the single highest of any
  feature in the product — is never a candidate for shedding.
- **A live game's fallback** (`live.ts`) — *"the call drops on a train; the
  game becomes turn-based and waits, rather than vanishing."*

**The rule, stated once so every activity can be checked against it:**

> **An activity that has a live form must also have a form that survives the
> live form failing or simply not being available right now** — a dropped
> call, a school day on one side and a workday on the other, a timezone eight
> hours apart. The asynchronous form is not a lesser fallback; it is the
> reason the synchronous form is safe to build at all, the same way §5.28's
> quality ladder is what makes video worth offering in the first place.

### 8.15.1 The pairing table

| Activity | Synchronous | Asynchronous | Time-difference handling |
|---|---|---|---|
| The call itself | Live video/audio | Message banking (§8.2) + async video messages | Send-time guard (§6.4): "next bedtime" ≠ "the night of June 1st" |
| Games | `live.ts` — 10 titles, explicitly *"a spine for the call"* | `games.ts`/`games2`/`games3` — ~10 turn-based titles | Turn clocks tick in **reachable hours, not wall hours** (§4.7) |
| Homework | The pane (§5.26) + shared annotation canvas, live help during a call | Photo capture + the "hint, don't solve" tutor engine | Delivery engine's day-part policies |
| Reading | Shared reading (v0.33.0) — one book, two screens, his voice | Storyteller — self-serve, bookmarkable, resumable | — |
| Drawing | **New v0.42.0** — the shared annotation canvas, reused, live, per-actor undo | The doodle desk (§9.12.4) — solo, no timer, no completion state | — |
| The come-back signal | Sent live, delivered immediately if reachable | **New v0.42.0** — deferred to the next reachable window, capped at one, never a queue (§5.27.7) | Silent-hours + day-part window already existed; the deferral is what's new |
| Showcase asks (§9.10.7) | Answered live during a call | The 3-slot pending queue, oldest silently displaced | **New v0.42.0** — `askAgeInReachableHours()` weights an ask's age by the asker's actual reachable hours, not wall-clock hours, mirroring §4.7 |

### 8.15.2 What this section does NOT change

No existing behavior was altered to build this. Every synchronous/asynchronous
form in the table above that predates v0.42.0 works exactly as it did — this
section names and audits an existing pattern and fills two identified gaps
(live drawing, showcase reachable-hours), rather than rebuilding anything.

### 8.15.3 The audit

`auditPairing()`-style checks are the responsibility of each module's own
test suite rather than a single central registry — the same way §8.13's
motion rules and §8.8b's accessibility forms are each enforced where they are
declared, not through one god-module. What this section provides is the one
place a future addition gets checked against: **does this activity need a
synchronous and asynchronous form, and if so, do both already exist?**


---

## §8.11 The device matrix

Everything until now was designed against two viewports — a Galaxy Z Fold 5
folded and unfolded — and everything else was assumed. Nine postures are now
declared, and the layout audit runs against all of them.

### 8.11.1 Nine postures

| Posture | Floor (CSS px) | Orientations | Columns |
|---|---|---|---|
| Fold, closed | 344 × 882 | portrait | 1 |
| Fold, open | 673 × 841 | portrait, landscape | 2 |
| **Fold, half-open** | 673 × 420 | **landscape only** | 2 |
| Ordinary phone | 360 × 640 | portrait | 1 |
| 7-inch tablet | 600 × 960 | portrait, landscape | 1 |
| 8-inch tablet | 768 × 1024 | portrait, landscape | 2 |
| 10-inch tablet | 800 × 1280 | portrait, **landscape** | 2 |
| PC | 1024 × 640 | landscape | 3 |
| Samsung DeX | 1280 × 720 | landscape | 3 |

**344 px is the floor for everything**, guardian surfaces included. A parent
checks this app on a phone far more often than at a desk, so a 600 px guardian
inbox is broken exactly as a child surface would be.

Columns are computed from the **effective** width — viewport ÷ text scale — so a
10-inch tablet at 2.0× type gets one column, like a phone. Computing from device
width is the mistake that makes accessible layouts break on small screens.

**Wired into the Flutter client as of v0.49.13.** `form_factors.dart` is a
deliberately partial 1:1 port of this section's own `FORM_FACTORS`/
`postureFor()`/`columnsAt()` — §8.11.2's input/stylus subsection is not
ported, since nothing client-side calls it yet. Before this pass, several
screens each hand-rolled their own single, arbitrary pixel breakpoint for
"wide enough" — none of them matched this table's own nine boundaries, and
none of them matched each other. `court_export.dart` is the first real
consumer, replacing a bare `760` with `columnsAt()`'s real, tested 660px
threshold. See §8.11.7's own status note for the second, more consequential
fix this same pass made to that screen.

**Nine more files migrated v0.49.24**, closing a compatibility-audit
finding: `guardian_home.dart`, `storyteller_screen.dart`,
`game_checkers.dart`, `game_chess.dart`, `degradation_banner.dart`,
`colour_daily.dart`, `colouring_screen.dart`, `doodle_desk.dart`, and
`maturation_ladder.dart` each still carried their own hand-rolled
`maxWidth < 420`/`>= 560` breakpoint, ignoring text scale exactly the way
this section's own second paragraph warns against. All nine now read
`columnsAt()` directly. Two required care beyond a mechanical swap:
`guardian_home.dart`'s action grid clamps the raw `columnsAt()` result to a
`[2, 3]` floor — an unclamped swap would have collapsed both the Fold5
cover screen and the 7-inch `tabletSmall` posture from the grid's
deliberately-tuned 2 columns down to 1, since `columnsAt()` only returns 2+
above 660px effective width; `game_checkers.dart`/`game_chess.dart`'s board
`ConstrainedBox` had its boolean sense inverted along with the rename
(the old `narrow` meant "let the board fill the available width," the new
`wide` means the opposite), confirmed against both files' own Fold5-pinned
widget tests. This still leaves roughly 60 screens with no device-adaptive
layout of any kind (of which 15–19 are nav-reachable content screens) —
named, catalogued, and deliberately left as a backlog item rather than
mechanically swapped in this same pass, since giving each one a real
two-column tablet layout needs per-screen design judgment this pass was not
scoped to invent. See CHANGELOG v0.49.24.

**v0.49.25 opens that backlog with a 4-screen priority tier, each screen
actually read and judged individually rather than assigned a treatment from
the audit's generic label.** `message_banking.dart` — a guardian-side compose
form followed by a banked-message list, genuinely both halves already
visible in one `Column` at once — is the only one of the four that fits the
two-pane `Row`/`Expanded` pattern above; it now gets exactly that, gated by
this section's own `columnsAt() >= 2`, with the narrow path an
actually-identical widget tree to before (the same two child lists spread
back into one flat `Column`, not two nested `Column`s wrapped around
visually-equivalent content). `homework_screen.dart`, `weeks_screen.dart`,
and `inbox_screen.dart` do NOT get a two-pane split — §8.13.5's own "still
surface" documentation rules it out for the first, a `Wrap`-based rhythm
visualization that already reflows rules it out for the second, and a
tap-to-navigate (not list-selects-detail) interaction model rules it out for
the third. All three instead get a new, lighter, shared treatment: a
`comfortableReadingWidth` constant (640px, immediately below `columnsAt()` in
this same file, explicitly documented as a typography cap and NOT a tenth
posture) that centers and caps their single column once `columnsAt() >= 2`,
so a phone-width column of prose stops stretching edge-to-edge on a tablet
or desktop. This closes 4 of the ~60 screens named above — all four
nav-reachable content screens — leaving roughly 56 overall, and the
nav-reachable content-screen subset at 11–15 (down from 15–19). See
CHANGELOG v0.49.25.

**v0.49.26 continues the tier with three more genuine two-pane candidates,
each read individually before deciding.** `wants_needs.dart`, `expenses_screen.dart`,
and `letters_screen.dart` all share message_banking.dart's exact shape — two
halves already visible in one `Column` at once — and now get the same real
`columnsAt() >= 2` `Row`/`Expanded` split, narrow path unchanged
(actually-identical widget tree, spread back into one flat `Column`, not a
visual approximation). `wants_needs.dart`'s two halves are its own pre-existing
`_ItemSection` widgets (wants \| needs), already self-contained, so this is the
cleanest of the three. `expenses_screen.dart` needed one addition the pattern
hadn't needed before: a shared, unsplit banner rendered once above the split
region in both layouts, since "Guardian ↔ guardian only" orientation copy
belongs to neither pane — and P6's own gate (`inboxVisibleTo()` →
`_NotAGuardianSurface`) stays completely outside and prior to any of this,
unconditionally, confirmed line-for-line against the diff, not assumed.
`letters_screen.dart` gets the identical unsplit-header treatment for its own
info banner. `journal_screen.dart` — read and initially planned for the same
two-pane split — was deliberately dropped from this tier once a separate,
already-further-along effort was found mid-build giving it a
`comfortableReadingWidth` cap instead: §8.13.5 calls the journal "a permanently
STILL surface," and a single calm reading/writing column honors that framing
more directly than pulling compose and read apart into two panes — the other
effort's judgment call, deferred to rather than duplicated or overridden. This
closes 3 more of the remaining backlog, leaving roughly 53 (before whatever
`journal_screen.dart`'s own landing closes separately). See CHANGELOG v0.49.26.

**v0.49.27 is batch A of 3 continuing that backlog**, opened by a dedicated
read-only investigation that read each still-named nav-reachable content
screen individually rather than assigning it a treatment from the generic
label — the investigation itself sharpened the previously-estimated 11–15
subset to a precise 16, split by actual content shape into two treatments.
Nine screens whose body is genuinely one scrollable column —
`journal_screen.dart`, `siblings_screen.dart`, `emergency_card.dart`,
`exchange_screen.dart`, `meds_care.dart`, `family_agreement_screen.dart`,
`the_book.dart`, `year_book.dart`, `shared_reading.dart` — get this section's
own `comfortableReadingWidth` cap, batch A, done here; the other seven this
investigation originally named (`letters_screen.dart`, `wants_needs.dart`,
`expenses_screen.dart`, `care_note.dart` — batch B; `handover_notes.dart`,
`availability_screen.dart`, `show_guardian.dart` — batch C) have a genuine
list-selects-detail or compose-plus-list shape and were queued for the
two-pane `Row`/`Expanded` pattern above in two further batches — but three of
batch B (`letters_screen.dart`, `wants_needs.dart`, `expenses_screen.dart`)
landed sooner than planned, via v0.49.26 above: a separate, concurrent pass
built and merged first, independently reaching the same two-pane treatment
for those three files from its own per-screen read, before this batch
rebased onto it. `shared_reading.dart` is the one file in batch A given the
cap specifically INSTEAD OF a two-pane split for a safety reason, not a
mechanical one: §9.13.2 requires that no page count or percentage ever reach
her screen, and a two-pane split would have put her screen and his (which
may plainly show a line count) on view simultaneously on a wide viewport —
the cap keeps the existing toggle, and a dedicated widget test proves
exactly one of `_HerScreen`/`_HisScreen` is ever in the tree at once, at
every tested width. This closes 9 more of the ~56 screens remaining after
v0.49.25; combined with v0.49.26's 3, roughly 44 remain overall. Of the
nav-reachable content-screen subset (a precise 16 per this investigation),
9 close here and 3 closed via v0.49.26, leaving 4 — `care_note.dart` (the
remainder of batch B) plus all of batch C. See CHANGELOG v0.49.27.

**v0.49.29 closes the remaining 4 and, with them, this entire 16-screen
investigation.** `care_note.dart` (compose: intro, kind chips, note field,
guidance banner, Send button | list: sent notes) plus all three of batch C —
`handover_notes.dart` (compose: disclaimer, add-note field, button | list:
entries, newest first — the one screen needing genuine restructuring, since
its compose row was pinned to the bottom of a fixed-height `Column` rather
than already living in a scrollable form list; rebuilt on
`SingleChildScrollView` + `Column`, the same fix `message_banking.dart`
already applies, with its own narrow path deliberately reordered
compose-above-list to match this tier's own convention, called out rather
than left unstated), `availability_screen.dart` (compose: the editable
7-day weekly-hours form + Save | list: the read-only co-guardians list),
and `show_guardian.dart` (compose: the ask composer alone | list: pending
asks + shelf + received-show replies, stacked as a unit) — all now get the
same real `columnsAt() >= 2` `Row`/`Expanded` split. One real, previously
latent bug was found and fixed along the way: `availability_screen.dart`'s
`_dayRow` start/end time `Row` could overflow at a pane's narrower width,
invisible before this pass because the row always had the full screen
width — changed to a `Wrap`. This closes the last 4 of the 16
nav-reachable content screens this investigation named (9 batch A +
3 batch B closed early via v0.49.26 + 4 here); **the device-adaptive
two-pane/reading-cap backlog this investigation scoped is now fully
closed.** What remains, unscoped and not read screen-by-screen the way
these 16 were: roughly 40 non-priority screens with no device-adaptive
layout of any kind, plus the pre-existing zero-adaptive games. See
CHANGELOG v0.49.29.

**v0.49.31 closes the "pre-existing zero-adaptive games" half of that
remainder — five older titles that predate this whole backlog effort:
`game_kim.dart`, `game_hunt.dart`, `game_chain.dart`,
`game_battleship.dart`, `game_hangman.dart`.** Each was read individually
and judged to have no genuine form+list or list+detail shape, so all five
get this section's own `comfortableReadingWidth` cap rather than a
two-pane split — `game_battleship.dart`'s pre-existing 460px board cap and
tab-toggle single-board model are both left untouched underneath the new
outer cap. `game_kim.dart`'s `_ItemGrid` needed a real fix alongside the
mechanical wrap: capping the outer width shrank its `Wrap`-based grids
enough to need an extra row at the default 800px test width, breaking a
pre-existing test — confirmed to be a latent fragility the cap exposed
rather than introduced (the same failure reproduces against the original,
unmodified file at a narrower width), fixed by a `compact` tile-size floor
that only ever applies in the new capped state, never on any previously-
existing posture. See CHANGELOG v0.49.31. **v0.49.30 closes two real gaps found live-testing calling for the first time with two real devices, plus containerizes this project's own dev server.** `guardian_more.dart` and everything under it had never been reachable from any running live build — `main_live.dart`'s own boot sequence hardcodes a child dev-login with no guardian path at all, a gap that file's own comment already named. A new `main_live_guardian.dart` entry point (a third build target, alongside `main.dart`/`main_live.dart`) boots straight into `GuardianMoreScreen` with a real guardian session — deliberately NOT the full ribbon/dual-clock `GuardianHome`, which needs a `/ribbon` endpoint `api_client.dart` only declares a path constant for (`OliveApi.childRibbon`), with no real server route and no client fetch method behind it; building that honestly is its own separate, larger piece of work, tracked and not invented here. `GuardianSetupScreen`'s own real `setGuardianPin` field (backed by the already-real `POST /v1/me/pin`) had never been wired at either of its two call sites — fixed, so a guardian can now set a real kiosk PIN through the app's own onboarding screen instead of a developer setting one by hand. A real "Call " tile was added to `guardian_more.dart`'s existing (previously demo-only) Calls section. Separately: `scaffold/Dockerfile` + `docker-compose.dev.yml` (`tools/docker-dev/README.md`) containerize `server/index.mjs` and `tools/local-call-room-server.mjs` against a dedicated Postgres, provisioning `app_owner` as NOSUPERUSER NOBYPASSRLS from creation rather than needing a manual grants pass after each new migration -- replacing a bare `node` process that had silently died once already this session the moment the shell command that launched it exited, with no crash log and no obvious symptom beyond a device saying it couldn't reach the server. See CHANGELOG v0.49.30 for the complete account, including the real websocket bug found and fixed getting the self-hosted Jitsi stack to actually connect from a physical device (§9.12.4/§16.2 #6). Still unscoped and not read the
way these 5 were: roughly 40 non-priority screens with no device-adaptive
layout of any kind, and `game_findthing.dart`/`game_wordsearch.dart`/
`game_story.dart` — a separate, deliberately not-yet-scoped tier that
needs its own hand-rolled sizing migrated onto `columnsAt()` directly, a
different-shaped decision than the reading-cap treatment given here.

### 8.11.2 The half-open Fold

Half-open, the Fold stands by itself with the camera at roughly eye level. **It is
the only hands-free call posture the hardware offers**, and for a child that is
the difference between holding a phone for eleven minutes and playing on the floor
while her father watches.

Video above the crease, controls below. Nothing used it.

### 8.11.3 Input, and what a stylus is for

`INPUTS_BY_POSTURE` is declared per posture rather than per platform, because
**DeX breaks the assumption that platform implies input** — it is a phone with a
mouse.

Touch targets stay at 64 dp (§8.4). A mouse-only *guardian* surface may relax to
32; **a child-facing surface never relaxes**, because a child using a mouse is
still a child.

An S Pen improves exactly two things — the annotation canvas and homework markup —
and `stylusRequired()` returns `false` permanently. A stylus is an improvement,
never a gate.

### 8.11.4 The silent device

**A great many separated families hand a child a £50 Amazon Fire tablet.**

FireOS has no Google Play Services, therefore no FCM. With the transport as it
stood — `Platform = 'android' | 'ios'` — a notification would be constructed,
dispatched, and silently discarded.

> **She never learns he wrote. He never learns she was not told.** No error, no
> bounce, no way for either of them to discover it. It is the one failure mode
> where both people are misled at once, and it was one type union away.

Six channels are now declared, three of which cannot push: `android_amazon`,
`android_bare`, `web`. Each declares a fallback, and **a channel that can neither
push nor fall back is refused rather than warned about** — a silent device is
worse than no device.

The guardian is told plainly, and the copy blames neither the device nor the
parent: *"Her tablet can't show pop-up alerts, so she sees new things when she
opens Olive — and we can text the grown-up there if something is waiting."*

### 8.11.5 Performance tiers

A 2 GB tablet is a real device in this market, and 720p will drop frames on it
until the child gives up.

| Tier | RAM | Video | Animation | Video + canvas |
|---|---|---|---|---|
| low | 2 GB | 180p @ 15 | off | no |
| mid | 4 GB | 360p @ 24 | on | yes |
| high | 6 GB+ | 720p @ 30 | on | yes |

**A call is degraded, never refused.** 180p at 15 fps is a recognisable face, and
a call that connects beats a call that looks good.

### 8.11.6 Lock-down differs on every platform

| Channel | Method | Remotely enabled? |
|---|---|---|
| Android + Play | Device Owner / screen pinning | yes |
| FireOS | Amazon Kids profile | **no** |
| Android, bare | screen pinning | no |
| iOS | Guided Access | **no — cannot be, at all** |
| Windows | Assigned Access | yes |
| Web | none | — |

**iOS Guided Access cannot be enabled remotely or programmatically.** A parent
must switch it on by hand, and the product must say so rather than implying a lock
it cannot deliver.

There is no kiosk in a browser tab, so **the web client is guardian-only**. A
child shell with no lock is one that can be navigated out of in a single tap.

### 8.11.7 The audit, and honest exceptions

`auditLayouts()` fails any surface needing more width than a posture provides, and
any portrait-only surface on a landscape-only posture.

Some surfaces genuinely are not for a 344 px screen — a certified court export is
a document-production task. **Saying so is honest; breaking is not.** A wide
surface must declare `degradesTo`, and the audit still fails it until that
degraded form is actually implemented.

The real case: a parent needs to produce an export in a solicitor's waiting room,
on a phone. *Requesting* it must work there even if reviewing it does not.

**Actually implemented as of v0.49.13.** `packages/devices/src/postures.ts`'s
`REQUEST_MIN_WIDTH`/`REVIEW_MIN_WIDTH`/`reviewableAt()`/`requestableAt()`
existed, real and tested, since before this pass — with zero client
enforcement. `court_export.dart`'s `CourtExportScreen` rendered its full
certified-export review UI (preview controls, "Generate certified export,"
the attestation panel) at ANY width, including a 344px Fold-cover screen,
directly contradicting this section's own rule and `requestConfirmation()`'s
own copy, which promises reviewing needs "a computer or a tablet." Below
`REVIEW_MIN_WIDTH` (600px) both `CourtExportScreen` and the real, backend-
wired `LiveCourtExportScreen` now show that honest copy instead of the
review UI — raw export, never gated by this rule, stays fully available at
any width. `postures.ts`'s own header cited "§8.12.3" for this section,
which does not exist anywhere in MASTERFILE (§8.12 is skipped entirely
between here and §8.13) — corrected to this section, §8.11.7, in the same
pass. **The rest closed, not just found, in a later pass**: `postures.ts`'s
top-level header and its `§8.12.1`/`§8.12.2`/`§8.12.4` section markers, plus
`postures.test.mjs`'s own bare "§8.12," all carried the identical phantom
citation for the tabletop/landscape/web-path content — retargeted to their
real matches (§8.11.2 "The half-open Fold" for the tabletop layout, whose
own "Nothing used it" line is exactly the gap `TabletopLayout` closes;
§8.11.1 "Nine postures," where per-posture landscape support was originally
declared with nothing behind it, for the landscape arrangement). The web-path
content (`WebCapability`/`WEB_ALLOWED`) has no confirmed matching MASTERFILE
prose section at all — honestly disclosed as real, tested code without one,
in `postures.ts`'s own comment, rather than a citation forced to fit.

**Text-scale bug fixed v0.49.14.** An adversarial audit found `reviewableAt()`
ignored text scale while its sibling `columnsAt()` — two lines away, same
`build()` method — correctly divided by it, exactly the mistake §8.11.1
names by name. A guardian at 2.0x accessibility text on a ~650px-wide
screen (raw width above `REVIEW_MIN_WIDTH`) has an *effective* width of
~325px, narrower than the 344px Fold-cover floor this same file already
guards for — and would have gotten the full review UI squeezed into that
space. `reviewableAt()`/`requestableAt()` both now take the same optional
`textScale` `columnsAt()` already does. The same audit also found the
§8.12.3-to-§8.11.7 citation fix above hadn't propagated to `court_export.
dart`/`court_export_test.dart`, the very files that pass edited to consume
it — corrected there too, five more instances. See CHANGELOG v0.49.14.


---

## §9.10 The showcase — "show me"

**Amended v0.42.0 (§8.15).** Pending asks (§9.10.7) were capped at three but
aged in wall-clock time — an ask made at his 11pm during her school day was
treated as exactly as "old" as one made during her free time, so the ceiling
could silently displace a fresh ask nobody had a reasonable chance to see yet.
`askAgeInReachableHours()` weights an ask's age by the asker's actual
reachable hours instead, mirroring §4.7's `turnExpired` for games. Additive —
`askForShow()`'s existing FIFO displacement is unchanged.

### 9.10.1 The observation this is built on

A child can be highly communicative in person and near-silent on a video call,
and the reason is not shyness.

**In person you share a room.** There is always something to point at, and most
of what a child says is anchored to it. Over video the shared referent is gone,
and what remains is *"how was your day"* — which is an interview. Children are
bad at interviews, and adults conducting them get monosyllables and blame the
child.

**Showing restores the shared referent.** It is not a workaround for a child who
will not talk; for most children it is the native register, and every previous
section of this spec has treated it as a side feature.

> **Standing rule.** No copy anywhere in this product may describe a child as
> shy, quiet, reticent, reluctant, or as needing to be *drawn out*, *opened up*,
> or *got talking*. That framing takes a thing she is good at and re-describes it
> as a deficiency. Enforced by `auditFraming()`, which matches stems rather than
> exact conjugations.

### 9.10.2 The matrix

Eight show types. The `parentRole` column is the one that matters most: a parent
who answers *"look at my dinosaur"* with *"that's nice, how was school"* has
ended the exchange.

| Kind | Who starts | Live / async | What remains | What the parent is told to do |
|---|---|---|---|---|
| **Show me a thing** | either | both | artifact | Ask one *specific* question. Not "is that nice" — "which bit is your favourite". |
| **Show me what you made** | child | both | artifact | Ask how it was made before saying whether you like it. **Process before praise.** |
| **Show me what you learned** | either | both | artifact | Be told something you did not know, and say so out loud. |
| **Show me what you can do** | either | both | artifact | Watch the whole thing. Ask to see it again. |
| **Show me where you are** | either | live | ephemeral | Ask about something in the background you have not seen. |
| **Show me all of them** | child | both | collection entry | Learn two of the names. Use them next time. |
| **Let me teach you** | child | both | artifact | Be genuinely taught. Pretending is detected instantly. |
| **Look what happened** | child | async | artifact | Reply *in kind*, not in words. Send one back. |

Two of these are load-bearing. **"Let me teach you"** is the only feature in the
product that gets *better* as she ages rather than fading (§21.5), and
**"Look what happened"** is the one with no prompt and no schedule — the tap she
reaches for when something happens, which is the best case the whole module is
built to receive.

### 9.10.3 Interests, recorded lightly and expiring gently

Dinosaurs now. In eighteen months it will be something else, and in three years
she will be faintly embarrassed by both.

So an interest carries **no intensity score and no ranking**, and nothing is ever
deleted — she may come back to it. After `RECEDE_AFTER_DAYS = 120` with nothing
shown, an interest simply stops generating prompts.

> **The rule that matters: the product never says "you used to like dinosaurs".**
> A receded interest is visible on the **guardian** side, where glancing back at
> what she was into two years ago is warm. The same list shown to her is not.
> Being reminded of what you have outgrown is a small humiliation, and P9 already
> establishes that resurfacing is dangerous in this population.

**P5 applies without exception.** Interests are family context. They are never
used for advertising, recommendation, model training, analytics segmentation,
lookalike audiences, or a content feed. `INTEREST_FORBIDDEN_USES` names all six
so a future contributor has to delete a line rather than merely forget.

### 9.10.4 Prompts are parameterised, never hard-coded

Templates take `{one}` and `{plural}`, so an interest nobody anticipated works
exactly as well as one we thought of. Hard-coding dinosaurs would have been
faster and would have failed the moment she moved on.

Every show kind also has a **generic** prompt set requiring no interest at all,
so a child with nothing recorded is never worse off than one with several.

### 9.10.5 Collections — a record, not a target

Children's interests are usually **enumerable sets**, which makes a collection
the long-running shape the product otherwise lacks: something that grows over
months rather than within a session. It is also what should replace streaks,
which P2 forbids for good reason — a plant that grew is a real record; a 47-day
streak is a punishment waiting to happen.

> **There is deliberately no denominator.** *"You have shown me 23"* is a record
> of what happened. *"23 of 151"* is a homework assignment. Pokémon has over a
> thousand; a completion bar there is a small cruelty. `SHOWCASE_FORBIDDEN` bans
> `total`, `percent`, `completion`, `missing`, `remaining`, `goal`, `target` and
> `quota` from any child-facing payload.

### 9.10.6 A year of shows is the best Year Book material we have

Every show is `preserved: true`. Grouped by kind and year, they become sections
titled from *her* side — "Things you made", "Things you taught me", "Things that
happened" — and that is a better portrait of who she was that year than anything
else the product collects.


---

## §9.11 The storyteller

Built for a five-year-old who likes being read to, and a parent who likes reading
to her. Four things follow from that, and they shape everything.

### 9.11.1 It will not repeat

Eight story shapes crossed with twelve slot pools. `spaceSize()` computes the
floor — it ignores personalisation and ordering — and it comes to roughly
**2.9 × 10¹⁷**.

A story every night for eighteen years draws 6,570 of them. That is under a
billionth of a billionth of the space, which is the arithmetic behind the promise
that she will never hear the same one twice.

### 9.11.2 A story is a six-character code

She will want *the one about the octopus* again.

So a story is not stored, it is **regenerated**: the same code always produces the
same story, exactly. Codes are six characters from a 29-letter alphabet with `0`,
`O`, `1`, `I` and `U` removed, giving 594,823,321 stories reachable by code.

A thousand favourites cost six kilobytes. A story she asks for **twice** is
preserved automatically (§9.8.1) — that is the signal worth acting on, and it
costs six characters to honour.

### 9.11.3 It is shaped for a voice, not an eye

Short lines with a breath at every break, and — the important part — a
**refrain**.

The refrain is **her** line. It appears three times, identically, and is marked so
the parent knows to stop, look at her, and let her say it. By the third time she
gets there first.

> That single affordance is the difference between reading *to* a child and
> reading *with* one, and it costs a boolean. Most generators leave it out
> entirely, which is why most generated stories are read once.

Read time is estimated at 130 words a minute — slower than silent reading, which
is the figure that matters when a parent is deciding at bedtime. Every story comes
in under two minutes.

Personalisation is capped at `MAX_PERSONAL_TOUCHES = 2`. Her colour appears in one
line, her name in another. **A story where every noun has been swapped for the
child's name is not a story about an octopus any more**, and children spot the
machinery immediately.

### 9.11.4 Safe for five — and never about her parents

Gentle, silly, occasionally sad. A lost mitten, a wilting flower, missing
somebody. Sad-then-resolved is good for a five-year-old; frightening is not.

Fifty-plus banned terms cover everything alarming, and the audit runs on the
**generated output** rather than trusting the vocabulary — a bad combination is
where a problem would actually surface. Four thousand generated stories are swept
on every build.

**And never about her parents.**

> A story about a bear who lives in two houses could be wonderful or could be
> devastating, and the product cannot tell which on any given evening. So the
> storyteller does not go near it. `divorce`, `two houses`, `custody`,
> `separated`, `Mummy and Daddy` and `take sides` are banned outright.
>
> **If a family wants that story, a parent can tell it. Software should not choose
> the moment.**

That is §2.4 applied to fiction: the child never sees the machinery of conflict,
least of all in a bedtime story.

### 9.11.5 It sits beside the co-op story, not instead of it

§9.2 already ships *"I went to the market"* and the alternate-a-line story, where
they build something together. This is the other half: a story that arrives
finished, to be read aloud.

Both are wanted, and for different evenings.


---

## §5.21 Call security

### 5.21.1 The leak that would have shipped

WebRTC prefers a peer-to-peer path. When it succeeds, **each side learns the
other's IP address** — a coarse location: city, often neighbourhood, and with a
subpoena an exact one.

Prohibition **P3** forbids live location, and every previous increment enforced it
at the application layer: no coordinate columns, arrival modelled as an event,
no location keys permitted in push payloads (§10.4). **And a peer-to-peer video
call would have leaked it anyway, through a channel nobody had looked at.**

It is worse than a general privacy defect. `guardianship.restricted` exists for
protective orders — a parent whose address is legally withheld from the other. A
peer path hands the restricted party a location fix on a protected one.

> **That is a safety defect, not a privacy one, and it would have shipped.**

So: **all media is relayed, always.** `callPolicy()` returns
`iceTransportPolicy: 'relay'` as a literal with no parameter that can change it,
so a future contributor optimising for bandwidth has to edit this file and fail
the test rather than pass a flag.

The trade is explicit: both parties are exposed to **us** instead of to each
other. That is the right direction for the exposure to point, and §5.21.4 records
it as a residual risk rather than pretending it away.

> **Status note, v0.49.33.** The paragraph above describes `callPolicy()`'s
> `iceTransportPolicy: 'relay'` as the enforcement mechanism — real code,
> real tests (`packages/session-runtime/src/security.ts`), but a live audit
> this pass found it was never actually imported by the real Flutter
> client (`call_screen.dart`), and the self-hosted stack's own served
> config confirmed live that direct P2P is attempted by default upstream
> (`config.p2p.enabled: true`) — exactly the leak this whole section exists
> to prevent, not enforced in the path a real call actually takes. Fixed
> this pass, but via a DIFFERENT, more robust mechanism than the one this
> section names: `tools/jitsi-selfhost/olive.env`'s `ENABLE_P2P=0` disables
> P2P server-wide (a server default holds regardless of what any given
> client does or forgets to set), with a client-side `configOverrides`
> override in `call_screen.dart` as defense in depth. `callPolicy()`'s own
> `iceTransportPolicy: 'relay'` still isn't wired into the live client —
> a real, smaller residual gap, not the one this section originally
> described as closed.
>
> **v0.49.35 closes that smaller gap, with one correction this section's
> own framing got wrong.** `iceTransportPolicy: 'relay'` is now set in
> `call_screen.dart`'s `configOverrides`, verified against upstream
> lib-jitsi-meet documentation before writing it, not guessed: it is only
> a documented **P2P-connection** setting — with P2P already disabled
> (`ENABLE_P2P=0`), there was no live P2P path for it to apply to even
> before this fix. It is not, and was never, a knob that hardens the main
> JVB-relayed media path this app actually uses for every real call — that
> path is inherently server-mediated already, with nothing for a
> peer-to-peer ICE policy to restrict. Set anyway, nested under the same
> `p2p` key `enabled: false` already uses, for the identical defense-in-
> depth reason: the day P2P is ever re-enabled on some other deployment
> this build points at, this ensures that path can still only negotiate a
> TURN-relayed candidate. `callPolicy()`'s own field is genuinely wired
> into the live client now — this section's original "still isn't wired"
> framing is resolved, but "residual gap" should be read as "defense in
> depth for an already-fully-mitigated risk," not as a live exposure that
> was open until this pass.

### 5.21.2 Screen sharing is the leak parents cause themselves

A father shares his screen to help with fractions. Along the top of it: a text
from his lawyer, an email subject line, a notification from a dating app. He is
not careless — **a whole-screen share simply shows everything**, and the child is
looking straight at it.

- Sharing is scoped to **one window**. Whole-screen is not offered.
- Notifications are suppressed for the sharing party for the duration.
- A preflight names exactly what is about to be visible, in plain words, before
  it starts.
- Camera and microphone are released the instant the app loses focus.

### 5.21.3 E2EE, and the contradiction it creates

With end-to-end encryption on, the SFU forwards ciphertext it cannot read. That is
the correct default for a child's face and voice.

It also makes **server-side recording impossible**, and §5.15 supervised
visitation depends on recording. The two cannot both be true for one call, and
pretending otherwise would be exactly the kind of quiet contradiction that ships.

| Call type | E2EE | Recording |
|---|---|---|
| Ordinary | **on** | off |
| Supervised (§5.15, §14) | off | disclosed before it starts |

`auditE2ee()` refuses both combinations that would be dishonest: E2EE claimed
alongside recording (*"one of them is a lie to somebody"*), and encryption given
up with no recording to show for it.

### 5.21.4 What still leaks — named honestly

A security section listing only what it fixed is marketing. Three of these cannot
be fixed by us at all.

| Risk | Ours to fix? |
|---|---|
| The relay sees IP addresses | Yes — deliberate; exposure points at us, not at each other |
| The SFU can decrypt a supervised call | Yes — disclosed on screen first |
| Either party can point a second phone at the screen | **No.** No software prevents a camera |
| OS-level screen recording | **No.** Detectable on iOS, partially on Android; disclosed where the platform allows |
| Call metadata — who, when, how long | Yes — retained for §14 court export; §16.2 #11 still open |
| A parent standing behind the child during a call with the other parent | **No** |

That last one is worth naming precisely because no amount of transport security
touches it, and it is the most common real breach of a child's privacy this
product will ever see.

---

## §9.12 Quiet activities

Three things a five-year-old will do for twenty minutes with nobody else present.
That matters: **not every minute in this product can require the other house to be
awake.**

All three share one rule. **Nothing here has a timer, a score, or a wrong
answer** — and these are the features where the temptation is strongest. A
colouring book with a completion percentage is a worksheet.

### 9.12.1 The colouring book

Tap a region, it fills. That is the whole interaction, and it is the right one at
five: no brush size, no pressure, no staying inside the lines. Artwork is vector,
so it scales from the 344 px cover screen to the unfolded main one without a
second asset.

**In by-numbers mode a "wrong" colour still fills.** The number is a suggestion,
not a test — a child who wants a purple giraffe gets a purple giraffe. The
mismatch is recorded because it is mildly interesting to a parent, and is never
shown to her.

Undo restores the **previous** colour rather than clearing the region, so
recolouring twice and undoing once does what she expects. Free and unlimited, like
every undo in §9.2.

### 9.12.2 Find the thing

A where's-Wally, except **the parent chooses what is hidden.**

That is the whole difference. A stock puzzle is a stock puzzle; a picture with
*her* dinosaur hidden in it, chosen by her father that morning, is a message. It
reads §9.10.3 interests directly, so what gets hidden follows what she is into
now.

| Level | Decoys | Similar shapes | Zoom |
|---|---|---|---|
| Gentle | 24 | 2 | 2× |
| Normal | 80 | 5 | 3× |
| Tricky | 180 | 9 | 4× |
| Fiendish | 320 | 14 | 5× |

**Difficulty is decoy count and decoy similarity, never a timer.** A clock turns a
hunt into a test, and the child who is slower is not worse at looking — she is
five. A miss does nothing at all: no buzz, no shake, no counter, exactly as with a
paper puzzle. A hint gives a quadrant and never the answer.

### 9.12.3 Spot the difference

Difficulty is the **number** of differences and how **subtle** they are.
`subtlety` runs from 1.0 — an object present or absent — down to 0.15, a shade
change on one small thing.

| Level | Differences | Subtlety |
|---|---|---|
| Gentle | 3 | 0.80–1.00 |
| Normal | 5 | 0.50–0.85 |
| Tricky | 7 | 0.30–0.55 |
| Fiendish | 10 | 0.15–0.35 |

Scaling subtlety rather than adding a countdown is what makes this pleasant at
five and still interesting at ten. The tap radius is deliberately generous: a
five-year-old aims with a whole finger.

How many are **left** is a goal, not a score. The distinction matters: a goal is
the shape of the puzzle, a score compares her to somebody. Escalation is manual —
the product never raises the difficulty on her behalf.

### 9.12.4 The doodle desk

**New v0.39.0.** Raised evaluating a Gemini-drafted alternate build's "Art &
Doodle Desk." §9.12.1's colouring engine is deliberately constrained — tap a
region, it fills, no brush, no staying inside lines — which is right for a
pre-drawn picture and wrong for a child who wants to draw her own thing. That is
a genuinely separate mode, not a replacement: free strokes on a blank canvas plus
six fixed stamps (heart, star, smiley, rainbow, sun, moon).

It inherits every rule this section already enforces without exception. A blank
page has no finish line, so unlike numbered colouring there is nothing for a
"finished" state to mean — the child view is a standing invitation ("Draw
anything you want" → "Keep going, or send it when you like"), never a count,
never a completion percentage. Undo is the same free, unlimited, exact-history
pattern as everywhere else in §9.2. A finished drawing is preservable the moment
it has anything on it at all, and is preserved like any other artifact she makes.

**Live pairing added v0.42.0 (§8.15).** The doodle desk had no synchronous
counterpart — a gap the sync/async pairing audit found. Rather than build a new
live-drawing engine, the live form reuses the existing shared annotation canvas
(`annotation/canvas.ts`) outright: its per-actor undo scoping already solves the
one hard problem a live shared doodle would otherwise reintroduce (a parent's
undo must never erase the child's stroke). The pairing is a naming and a demo
surface, not new logic.

**A second and third real consumer, v0.49.17 (§9.2 Play Together Batch A).**
`game_draw_together.dart` and `game_guess_doodle.dart` are the first screens
outside this one to build on `annotation_canvas.dart`'s `AnnotationCanvas` —
see §9.2's own status note for the full account. Neither reimplements or
forks the engine; both import it and use it as-is, same discipline this
section's own "reused, not rebuilt" line already establishes.

**Performance-hardened v0.49.24.** A compatibility/performance audit found
`AnnotationCanvas.visible()` recomputing and re-sorting the full stroke
history on every call (every rebuild, including one per pointer-move during
a live drag) and `AnnotationCanvasView` painting the entire committed
history AND the in-progress stroke together, unconditionally, on the same
`CustomPaint` every frame. `visible()` is now cached, invalidated only by a
real mutation (add/undo/redo/erase); `AnnotationCanvasView` now paints
committed and live strokes on two separate layers, the committed one
wrapped in a `RepaintBoundary` so the small, always-repainting live layer
never drags the (growing) stroke history along with it. A companion fix
(the same audit) replaced an O(n²) point-list rebuild in each screen's
`_onPanUpdate` (`game_draw_together.dart`, `game_guess_doodle.dart`, and
`doodle_desk.dart`) with an in-place `.add()` — safe only because
`_onPanStart` already hands each stroke a fresh list and `_onPanEnd` already
reassigns rather than clears it, both preserved unchanged. That fix
required one deliberate deviation from its own first-drafted
`shouldRepaint` check on the live layer: with the point list mutated in
place rather than rebuilt, the "old" and "new" painter end up aliasing the
exact same list object by the time `shouldRepaint` runs, so neither a
length comparison nor `identical()` can ever observe a change mid-stroke —
confirmed directly with a throwaway Dart probe, not assumed. The live
layer's `shouldRepaint` returns `true` unconditionally instead; it is small
and already isolated by the committed layer's own `RepaintBoundary`, so an
unconditional repaint there is the correct, cheap choice, not a missed
optimization. All existing `game_draw_together`/`game_guess_doodle`/
`annotation_canvas` widget tests pass unchanged, proving the refactor
behavior-preserving; the actual frame-timing improvement during a long
drawing session is not testable via widget tests and was not device-
verified this pass (no device available) — deferred, not skipped.

---

## §9.11.6 The library, and the book

Two gestures for her, and one for him. All three are nearly free because a story
is a six-character code (§9.11.2).

### Bookmark ⌾

She stops halfway. Tapping the bookmark later reopens that story **at exactly the
line they stopped on** — a bedtime that ran out of time is resumed rather than
restarted. A bookmark is a code plus an integer.

One detail worth the code: if she stopped *after* a refrain, the recap shows her
line again before carrying on. **Starting her cold on line eight of a story whose
chant she has forgotten is worse than one repeated sentence.** A bookmark on the
last line is refused rather than stored — nothing is more annoying than a bookmark
that reopens on the final page.

### Star ★

It joins a list that grows for years, newest first, because the one she starred
tonight is the one she wants tomorrow. `timesRead` is counted — for the book — and
is **banned from her view** by `auditLibraryChildView()`. P2.

### The book 📖

He collects the favourites and prints them: a bound volume of the stories they
read together. For Christmas.

- Ordered **oldest first**, so the volume reads as a year rather than a
  leaderboard.
- Under each title, the detail that will matter to her in fifteen years and costs
  nothing now: *"you asked for this one nine times."*
- Front matter carries a word count and page estimate a print shop can quote from.
- Output is **plain text**. §2.11 — a family's material is never held hostage by a
  file format.
- Under five stories it is a pamphlet, and the product says so rather than taking
  the money.

The whole book regenerates from a list of codes, so a hundred stories is six
hundred bytes of stored state and the printed artifact is **reproducible
forever** — including at majority handover (§9.8.4), when the codes go with her.


---

## §9.10.7–§9.10.11 Closing the gaps in "show me"

The module shipped in v0.22.0 pointed one way. Seven of its eight show types were
child→parent, which made it a feature about **a child performing for an absent
adult**. Five additions turn it into an exchange.

### 9.10.7 The pending ask

A prompt she has to go looking for is a menu. A prompt *waiting* for her, from her
father, by name, is a message.

**Capped at three.** If he asks six things and she answers none, the app has built
her a backlog of disappointment — so a fourth pushes the oldest out **silently**,
and no count, age, or "unanswered" ever reaches her. *A four-day-old ask looks
exactly like this morning's.*

### 9.10.8 Reply in kind

The matrix already said *reply in kind, not in words*. Nothing enforced it, and
"nice!" is what a tired parent types at eleven at night.

This **nudges, once, with the reason** — it does not refuse. Refusing would mean
some shows go unanswered, which is worse than a weak answer.

### 9.10.9 The shelf

All her collections in one place, most recently added to first, because the one she
is filling now is the one she wants. Counts live on the parent side;
`shelfChildView` strips them. P2.

### 9.10.10 He shows her his world

**The gap that mattered most.** A child who has never seen her father's flat cannot
picture him anywhere, and a product about presence that only carries her outwards
has the arrow the wrong way round.

Nine things, and the first is the reason the rest exist: **"Where you sleep here."**
A child who knows which bed is hers at the other house arrives differently.

One is deliberately **not offerable**: *"someone you will meet."* A new partner, a
new baby, a stepsibling — that belongs to a conversation, not a prompt deck. The
product supports it and will never suggest it.

### 9.10.11 The gallery

Everything she has ever made, in one room, grouped by year.

> **A five-year-old's best work is usually made of cardboard and glue.**

A gallery holding only digital paintings would quietly tell her that the things she
is proudest of do not count. So it is **medium-agnostic**: digital paint,
colouring, collage, photos she took, and **photographs of physical work** all hang
at the same size with no badge. `frameFor()` returns an identical frame for every
medium — which is why that claim is testable rather than aspirational.

From sixteen she can hide a work (§21.2 rung). **A guardian never can**, in either
direction. The exhibition compiles **oldest-first**, so it reads as a growing-up
rather than a best-of, and it is the companion to The Book: stories in one volume,
pictures in the other. Its note reads *"Cardboard counts. It always did."*

---

## §12.4–§12.7 The guardian shell

### 12.4 The pre-call briefing

Probably the highest-value screen in the product, because it decides whether the
call that follows is any good.

What he needs is spread across five screens, so in practice he opens none of them
and opens with *"how was school"*, and she says *"fine"*, and the call dies in
ninety seconds (§9.10.1).

**It must not become a script.** A parent reading questions off a card is worse
than one with nothing prepared — children hear it immediately. So: **three facts
and one opener**, chosen by *specificity*. "She showed you a Diplodocus yesterday"
beats "she likes dinosaurs", because it is something only he could know.

**P7 is asserted here.** Nothing from her journal reaches a briefing, at any age,
for any reason.

### 12.5 The handoff care note

*"She has a cough, she didn't sleep well, she's upset about a friend."* The single
most requested feature in this category in the real world, and it was not here —
the bag manifest handled objects; nothing handled the child.

Two decisions matter more than the feature:

1. **A care note is not evidence.** It sits outside the §13 tamper-evident log and
   expires in seven days. If every "she has a cough" became a court exhibit,
   parents would stop writing them honestly — **and an honest note is worth more
   than a preserved one.**
2. **The child never sees it.** "Mum said you were in a bad mood" is poison, and a
   child who knows her parents file notes about her stops telling either of them
   anything.

A care note is also the obvious place for a dig, and a dig disguised as care is the
hardest kind to call out — which is why the product **refuses** it rather than
leaving the other parent to absorb it. Sixteen banned constructions, including
*"she says you…"*, which is the child used as ammunition.

### 12.6 The catch-up

A parent who has not opened the app in five days got a home screen.

**The rule: a catch-up must never be a guilt trip.** No "you missed 14 things", no
unread badge in the hundreds, no oldest-first ordering that makes him scroll
through his own absence. Grouped, capped at four, largest first, and **silent about
the gap itself**. One thing to start with, never a list.

### 12.7 The coordination inbox

One place for things that need his answer.

**Only actionable items.** An inbox that also carries informational items is a
feed, and a feed is something you scroll past. `admitToInbox()` is the gate that
stops this becoming a timeline six months from now.

Ordered by real deadline first, then **oldest** — because the oldest is the one
that has been making the other parent wait. Every expense offers *Query it* as well
as yes and no. Adult-only, per §2.4.

---

## §9.13 Around the call

### 9.13.1 The closing ritual

Calls end with "ok, bye" and a black screen. For an adult that is fine. For a child
it is **the moment the absence starts again, at full volume, with no warning.**

Three beats, and the order does the work: something **forward-looking**, then
something **certain**, then a goodbye that is not the word "bye". The forward beat
becomes a real §9.10.7 ask, so *"I'll show you my tooth"* is waiting for her
tomorrow rather than evaporating.

The certain beat **never invents a date**. If the schedule does not know, it says
"we'll sort out when" — nobody is pretending.

**Skippable at every beat.** Forcing a ritual on a child who wants to go and play
is worse than a bad ending, and a ritual she cannot escape stops being a comfort
within a week.

### 9.13.2 Shared reading

**She turns the pages.** He reads, but the pacing is hers.

A parent-controlled page turn makes her a spectator to her own bedtime story;
giving her the button keeps her hands and attention in it — and she will turn back
to look at a picture, which is the whole point of reading with a small child.
Turning back is explicitly allowed and is not an error.

Roles swap, because some nights she reads. Her line, where the book has one, works
exactly like the storyteller's refrain (§9.11.3). No page count and no percentage
reach her.

### 9.13.3 The mid-call handoff

She is on a call with her father. Her mother walks through the room. There was no
way to include her for thirty seconds, and the absence of one makes the product
feel like it is keeping the adults apart.

> **The rule, and it is not negotiable: a handoff can only be initiated by the
> child or by the parent who is physically present. The remote parent never can.**

Otherwise the feature becomes a way to summon your ex through your child — using
her as a conduit, which is §2.4 and the thing this whole product exists to avoid.
The refusal points him at the coordination layer instead.

Announced before it happens, time-boxed to two minutes, and **not minuted**. It is
a hello in a hallway; recording it would stop anybody ever doing it.

### 9.13.4 She is busy, so bank it

He rings during school. The ribbon warned him, but the call attempt itself had
nowhere to go — **and a failed call is the worst possible output**, because it reads
to him as rejection and to her, later, as a missed call she caused.

So an attempt at a blocked time is never a failure. It is a fork and both branches
are good: state the fact plainly, offer banking (§9.5, unchanged), name the next
real window. Ten banned words ensure nothing reads as refusal.

> **And the other half, which matters just as much: she is never shown a missed
> call.** A five-year-old who sees "Dad tried to call you at 10:40" has been handed
> a small guilt she did nothing to earn.


---

## §9.14 Teach me something — the parent is the curriculum

Every educational feature before this treats learning as something **she** does
and **he** supervises. Homework help has an expertise gradient, and §9.1 had to
invent the *hint, never solve* guard precisely to stop that gradient becoming
corrosive.

This inverts it. **He knows how to do things**, and teaching is the most natural
form of presence there is. Five minutes, once a week, whatever he actually knows —
how to tie a bowline, why the sky goes red at sunset, the one card trick he is
good at, what he actually did at work today properly explained.

It costs almost nothing to build: the canvas (§9.1), the recording (§9.5) and the
showcase (§9.10) already exist. Sixteen seed prompts, four media, one object.

**From about six, she teaches him.** That is why §21.5 lists this as the only
feature in the product that gets *better* as she ages rather than fading — and why
the note the parent is shown says *"be genuinely taught; pretending is detected
instantly."*

**Asking again is the only measure.** A lesson she asks for twice becomes a
preserved artifact — the same rule as a story (§9.11.2), for the same reason:
asking again is the only honest measure a child gives you. Thirteen banned fields
keep a grade, a level or a "mastery" score out of it, because this is the feature
where that temptation is strongest.


---

## §9.15 The capture button

**New v0.39.0.** Raised at the owner's suggestion: a dedicated in-app photo and
screenshot control, auto-uploading into the app's own storage rather than the
device's shared camera roll.

**Why this needs its own button rather than "just use the OS screenshot."** A
device is shared — a sibling, a step-parent, anyone who picks it up unlocked can
open the general gallery app and find whatever landed there. §9.1's homework
capture and §5.26.7's pane still-frame already settled this exact posture for
their own narrow cases; this generalises it into a standing feature rather than
re-arguing the same constraint a third time somewhere else.

**Two kinds, deliberately not merged — they carry different risk:**

- **Camera capture** — a photo of the physical world (her homework, a drawing on
  paper, something she wants to show). Reuses §9.1's quality gate *wholesale*:
  `MIN_EDGE_PX` / `MIN_SHARPNESS` / `MAX_SKEW_DEG`, the exact same measured
  thresholds, because a blurred photo is a blurred photo whether it is headed for
  OCR or a keepsake. A photo that fails the gate is asked to be retaken rather
  than uploaded unreadable.
- **Screenshot capture** — of the app's own surface. Already digital, no
  blur or skew possible, but a different risk: it could capture a parent's live
  video mid-call, which would make it call media inheriting §8.8.1's retention
  rules — a complication this feature does not take on. So screenshot capture is
  **scoped off the call surface entirely** (`live_call`, `call_video`,
  `pane_video`) rather than solved here. A screenshot mid-call is refused, not
  silently taken.

**The one guarantee the feature exists for:** `neverToDeviceGallery` and
`autoUploadsToAppStorage`, declared as named invariants the same way §8.8.1
declares `onDevice: true` for captions — an intention with a name can be
asserted; a mere intention cannot.

**No count shown to her.** Same discipline as §9.12's quiet activities — "Saved
to your gallery" on success, "Let's try that again" on a failed gate, and nothing
that tallies how many she has taken.


---

## §21 The maturation ladder — "it grows up with you"

**Status: BUILT, v0.31.0.** Items 1–6 of §21.10 are shipped, in that order.
`packages/maturation/` holds the grant record, the quieting, letters, reverse
banking, and rungs 15–18; `family.ts` holds the sibling staggering §21.7
identified as a risk. The scaffold file is gone — it was types only and is
superseded.

Two of the §21.9 questions are settled, and are recorded in §21.9 below.

### 21.1 The principle

**The handover at 18 should be the last of many transitions, not the only one.**

A single cliff is emotionally powerful and structurally wrong. Nothing else in a
childhood works that way — growing up is a hundred small transfers of authority,
each one small, each one permanent. The product should mirror that, and each
transfer should be a *ceremony* rather than a settings change.

Two rules govern every rung:

1. **A rung is irreversible.** A guardian may never lower one. `canGuardianRevoke()`
   returns `false` and there is no inverse function — the same construction that
   makes P7 unreachable.
2. **The order is not configurable, even where the ages are.** §16.2 #9 already
   establishes that a jurisdiction can move the top rung; the same mechanism may
   move the others. What must never move is the sequence, or a parent's ability
   to reorder it.

### 21.2 The ladder

| Age | What becomes hers | Mechanism |
|---|---|---|
| ~10 | Her own list, uncurated by anyone | `list_item` write scope moves to the child |
| 13 | The journal locks absolutely | Already live — §17 tier 2 |
| 14 | She edits her own calendar | `child_event` gains a child-authored origin |
| **15** | **She publishes her own availability** | **See §21.3 — this is the inversion** |
| 16 | Archive curation — hide, era-tag, decide what belongs | `media_artifact.era_tag` + a child-only hidden flag |
| 17 | Her own export | `authorizeExport()` accepts a child principal |
| 18 | Everything; guardianship closes | §9.8.4, already built |

### 21.3 The inversion at fifteen

This is the rung to argue about, and the one that matters most.

For ten years the Day Ribbon has been **two adults coordinating around a child**.
Her day-parts are *inferred* — school hours, bedtime, a wind-down window — and
both parents consult them to decide when to reach her. She is the subject of the
schedule, not a party to it.

At fifteen that inverts. **She publishes her availability and the ribbon shows
what she set.** The inferred day-parts stop being the source of truth and become
a fallback for when she has published nothing.

The consequence is deliberate: a parent can now be told *"she is not free"* by
her, rather than by a system modelling her. That is a real transfer of power and
it will be uncomfortable for some parents. It is also exactly what a fifteen-
year-old is owed, and refusing it would make the whole ladder decorative.

### 21.4 She becomes an author, not a subject

Everything in §9 is currently done **to** her or **for** her. Two mechanics
reverse the direction, and both are nearly free because the delivery engine, the
retention model and the preservation flag already exist.

**Reverse message banking.** She banks messages *for a parent* — for his
deployment, for his birthday, for the week she is away. `delivery_intent` needs
no schema change; only the direction differs.

**Letters to her future self.** Sealed at nine, opened at eighteen. Always
`preserved: true` — a letter on a 90-day clock is a lost letter. Minimum seal is
one year, so it cannot become a novelty.

### 21.5 The quieting — the measure of success is that she needs it less

This is the unusual part, and the most defensible thing about the concept.

Most products **add** features as users age and measure success in engagement.
This one **withdraws**. At five the app is scaffolding — day-parts, send-time
guards, sleeps countdowns, prompt decks. At seventeen, a girl texting her father
does not need a send-time guard, and offering her one is faintly insulting.

| Scaffold | Fades at | Why |
|---|---|---|
| Sleeps countdown | 11 | She can read a calendar. Counting sleeps for her is talking down. |
| Prompt decks | 13 | A thirteen-year-old does not need a card telling her what to say to her father. |
| Send-time guard, **child side only** | 14 | She knows what time it is where he lives. The guard stays on *his* side permanently. |
| Game prominence | 14 | Games move to the back of the app, not out of it. |
| Day-part labels | 15 | Superseded by §21.3. |
| Handicap offer | 15 | Offering to handicap a parent to a fifteen-year-old reads as pity. |
| Ritual reminders | 16 | A ritual she still wants at sixteen is one she keeps herself. |

**Never fades:** the calendar, the call, the archive, the journal, and the whole
coordination layer on the guardian side. That is the app at seventeen, and it
should be quiet.

A product whose stated goal is to become unnecessary is a strange thing to build.
It is also the only honest reading of "grows up with you", and it is a strong
story to tell a parent who is worried about screens.

### 21.6 After eighteen

Three paths, and the product should be equally willing to serve all three.

| Path | What it means |
|---|---|
| **Take and go** | She exports everything and deletes the account. §21.7. |
| **Keep as archive** | She administers it herself. Guardians have no access (§9.8.4). |
| **Becomes a parent** | The archive she was handed becomes the first thing in her own child's. |

The third is a twenty-five-year product loop, and it is what turns §2.10 — *the
archive belongs to the child* — from a privacy stance into something structural.
It should not be designed for prematurely, but nothing built before then should
make it impossible.

### 21.7 Risks, and the position taken on each

**Adolescence is where this gets dangerous.** Thirteen to sixteen is precisely
when a parent most wants visibility and a child most needs privacy. A
"grows-with-you" product drifts very easily into a surveillance-through-
adolescence product, and the drift is commercially rewarded because **the parent
is the one paying.**

> **Position:** the product sides with the child on every rung above 13, and
> accepts the revenue cost. If that position is ever reversed, §2.1 must gain a
> prohibition recording it, so the reversal is visible rather than gradual.

**She may not want it.** An eighteen-year-old who says *"delete all of it"* must
be able to, immediately and completely. No cooling-off period — a delay is a soft
refusal. The one exclusion is the parent-to-parent log, which is not hers to
delete: it is theirs, and P8 makes it append-only regardless.

> This will be the hardest button anyone builds here. If it is not real, §2.10 is
> decoration.

> **Status, v0.47.0 — the GUARDIAN half is real, the child's own §21.6 "take and
> go" is not yet.** `client/lib/deletion_screen.dart`'s `_confirm()` now calls a
> real endpoint (`POST /v1/me/delete` — `server/routes.mjs`,
> `packages/db/src/pool.ts`'s `deactivateAccount()`,
> `db/migrations/0011_account_deletion.sql`): a guardian's own login, PIN/passkey
> credentials, and anything they had queued-but-undelivered are actually removed,
> in one transaction, while delivered messages, the parent-to-parent log
> (`message_log`), and the child's preserved archive are left untouched — proven
> against real Postgres and real RLS in `packages/db/test/deletion.test.mjs`
> (29/29). The account row itself is deactivated, never dropped — the log's
> `author_id` and a delivered intent's `sender_id` both still need somewhere to
> point. What §21.6/§21.7 actually describe (an eighteen-year-old exporting and
> closing out her OWN account, guardians losing access to her archive per
> §9.8.4) is a different, still-unbuilt operation — this pass only closes the
> gap for a guardian deleting their own guardian account.
>
> **Update, v0.49.16 — the CHILD half is real now too**, closing the specific
> gap this note named. `POST /v1/children/:id/handover` (§7.9's own
> long-specified path, never implemented until now) — `server/routes.mjs`,
> `packages/db/src/pool.ts`'s `takeAndGo()`, `db/migrations/
> 0016_child_take_and_go.sql` — does exactly what this note said was missing:
> a live guardianship edge closes for every guardian (reason `'majority'`,
> already a valid value in the schema's own CHECK since `0001_phase0_init
> .sql`), `child.handed_over_at` is set (irreversible — a second call is
> refused, not silently repeated), and she leaves with a real, full export
> bundle — reusing `rawExportBundleFor()`'s own bundle-assembly code, not a
> second implementation of it, and additionally carrying her REAL journal and
> a real copy of the parent-to-parent log (never available to a guardian's own
> pull — see §5.12/P7). The age/deceased/idempotency gate is
> `packages/archive/src/archive.ts`'s `handover()` itself, real and unit-
> tested since before this pass (`phase3.test.mjs`) but never wired to
> anything until now — this route adds no age-comparison logic of its own.
> `client/lib/take_and_go_screen.dart` gives it the same rigor
> `deletion_screen.dart` already has: a real acknowledge-before-enable gate,
> an audited-copy discipline, and NO cooling-off period — reached from a new,
> always-visible tile in `child_more.dart`. Proven against real Postgres RLS
> in `packages/db/test/take_and_go.test.mjs`, including that
> `export_record_no_child`'s RLS is left untouched (the write runs as
> `system`, after the route's own identity check, exactly like
> `deactivateAccount()`'s own posture). **Still not built, honestly**: §21.6's
> OWN further step for the "take and go" path specifically — a subsequent,
> full deletion of her own data — is `rungs.ts`'s separate rung-18
> `requestDeletion()`/`deletionConfirmation()`, a different and more drastic
> grant this pass does not wire up; what is real now is the shared §9.8.4
> mechanism underlying all three of §21.6's paths (take-and-go, keep-as-
> archive, becomes-a-parent) — guardian access ending, with a full export in
> hand. See CHANGELOG v0.49.16.

> **v0.49.15 dead-wire fix:** `deactivateAccount()`'s real response body —
> `cancelledDeliveryIntents` chief among them — was fetched by `_confirm()`
> and discarded outright (the call wasn't even assigned to a variable). The
> success card now states the real cancelled-message count when it's
> nonzero, making the "queued or banked" half of the promise above a real
> number rather than an abstraction.

**Siblings age out one at a time.** A family with three children has three
handovers across six years, and the guardian-facing app must survive losing them
one by one. This is a schema question rather than a feature: `guardianship`
already closes per child, and `sibling_link` already survives closure — but no
surface has been designed for a parent whose eldest has just left.

### 21.8 What already exists to build on

Encouragingly little is missing at the data layer.

| Exists | Serves |
|---|---|
| §17 privacy tiers (0–12 / 13–15 / 16+, non-reversible downward) | Rungs 13, 16, 17 |
| `guardianship.closed_at` + `closed_reason` | Rung 18, sibling staggering |
| `media_artifact.era_tag` | Rung 16 curation |
| `media_artifact.preserved` | Letters to self, reverse banking |
| `delivery_intent` policies | Reverse banking, unchanged |
| `authorizeExport()` | Rung 17, needs a child principal |
| `child_tz_interval` + `day_part` | Rung 15 fallback when nothing is published |

**Genuinely new:** a `maturation_grant` table recording which rung was reached
and when — append-only, since a rung never rescinds — and a child-authored
availability table that takes precedence over inferred day-parts.

### 21.9 Decided, and still open

**A — SETTLED v0.31.0. Ages move later only, and only by both guardians.**
Shifting a rung later is kind to an unusually vulnerable child. Shifting it
earlier, or unilaterally, is the obvious lever for a controlling parent — so
`adjustRung()` refuses both, and refuses a single-guardian request even when the
direction is legitimate.

**B — SETTLED v0.31.0. Only rungs that change what a parent can SEE notify them**
— 15 and 18. The rest are hers, quietly. A notification that "your daughter's
journal is now permanently private" tells a parent something about her that the
rung exists to stop them knowing.

**C — SETTLED v0.31.0.** The day after rung 15 the guardian is told **once,
warmly**, and never again. A permanent banner explaining that a fifteen-year-old
now controls her own time would be a daily reminder that she once did not.

Still open:
4. Is "becomes a parent" a new account linked to the old one, or the same account
   with a new role? This decides whether the loop is real or sentimental.

### 21.10 Sequencing — all six shipped v0.31.0

1. `maturation_grant` (append-only) and the ladder constants — cheap, and every
   later rung depends on it.
2. **The quieting.** Mostly deletion, which is the best kind of work, and it
   improves the product for older children immediately.
3. Letters to self, then reverse banking — both nearly free on existing engines.
4. Rung 15, the inversion. Needs the new availability table and the most design
   care of anything here.
5. Rung 16–17 curation and export.
6. Deletion at 18, done properly.


---

## §8.16 Theme customization — a real, guardian-configurable visual foundation

Sub-project 1 of the "intuitivism pass" (`docs/superpowers/specs/2026-08-21-
intuitivism-visual-foundation-design.md`) — the design-token foundation only.
Screen-level simplification (ChildHome, GamePickerScreen, navigation/density)
is separate, later work that builds on this; not designed or built here.

**Root cause this closes:** the entire app's color identity had been
`ColorScheme.fromSeed(seedColor: Colors.deepPurple)` in `main.dart`/
`main_live.dart` since the very first build — Flutter's stock starter-
template default, never once customized. Every screen already builds on
`Theme.of(context).colorScheme`, so replacing the seed catalog improves
everything downstream without touching a single screen's layout.

**Two independent axes.** `client/lib/theme.dart`'s `ThemePalette` (six real
hue identities — `classic`, `calmModern` [suggested default], `warmGrounded`,
`softPlayful`, `deepCozy`, `brightBold`) crossed with `ThemeBrightness`
(light/dark) via a real `colorSchemeFor(AppTheme)` catalog function — each
palette its own real seed color through `ColorScheme.fromSeed()`, not 12
hand-tuned schemes. `classic` keeps `Colors.deepPurple` as an explicit reset
option, not a removed one.

**Guardian-only, app-wide, backend-synced.** §8.1's "no settings affordance
exists at any depth" for the child shell is unchanged and CI-enforced exactly
as before (`transport.test.mjs`'s own contract check, now mirrored by a
client-side Dart test too — `child_no_settings_contract_test.dart`): the
picker (`theme_picker_screen.dart`) is reachable only from `guardian_more
.dart`'s `GuardianMoreScreen`, itself reached from `GuardianHome` — nothing
in the child's own import graph references it. `db/migrations/
0017_child_theme_preference.sql` adds a new, narrowly-RLS'd table (a
guardian with a live edge to the child may read and write; the child reads
her own; nobody else can do either) rather than widening `child` itself,
which has never had row-level security enabled at any point in this schema's
history — see that migration's own header for why extending its blast radius
was out of scope here. `GET`/`PUT /v1/children/:childId/theme`
(`server/routes.mjs`) reuses `family-graph/src/authorize.ts`'s own
`'settings'` Action — declared since early in this project, never wired to a
route until now. `main_live.dart`'s session bootstrap fetches the active
theme and applies it before first paint, failing closed to `classic`/`light`
on any unset value or fetch failure — the same discipline `verifyKioskPin`'s
own doc comment describes.

**Selecting has no side effect.** The picker previews the PENDING selection
in its own local `Theme` override; only an explicit Apply writes anywhere. A
brief, real crossfade (`AnimatedTheme`) plays on a successful Apply — §8.13
permits user-initiated consequence motion. No score, rank, or "you've tried N
themes" tally of any kind — P2; this is a preference, not a game.

**Known gap, stated honestly:** `GuardianHome`/`GuardianMoreScreen` are not
yet threaded into `main_live.dart`'s own live navigation tree — the same
pre-existing gap every other `guardian_more.dart` tile already has today
(Message banking, Handover notes, Availability's own optional
`baseUrl`/`guardianId`/`childId` wiring, …). This pass closes the READ half
of cross-device sync for real (session bootstrap fetch-and-apply); the WRITE
UI is guardian-side navigation, wired the same optional, forward-compatible
way every other guardian feature in this codebase already is, ready the
moment a live guardian session is threaded into that tree — a separate,
not-yet-done piece of navigation work.

---

*End of MASTERFILE v0.49.59. Amend in place. Bump version. Log in CHANGELOG.
Update VISUAL. Update MARKUP. §2.1 changes require an explicit rationale entry per §0.
§16.1 resolutions are provisional and reversible until Phase 0 data exists.*
