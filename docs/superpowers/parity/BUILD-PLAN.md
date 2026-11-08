# Build plan: bringing the Flutter client to parity with the live prototype

Companion to `MATRIX.md` (the 387 rows; row numbers `#n` and ids below refer to it) and `matrix.json`. Baseline: Flutter `main` at 0.50.0 plus #150. Reference: the LIVE prototype (`docs/superpowers/mockups/live/`, PR #152). Owner decision, 2026-11-08: the real app looks the same, with parity, and much more. Owner direction (earlier): offline-first, so online items are parked behind the offline ones and never block them.

This is a plan, not a commitment: every wave is one PR-sized change set (or two where marked) and each one flips matrix rows from missing/partial/differs to built, verified by a test that replays the prototype's behaviour.

## 0. Ground rules for every wave

1. **Design parity is a dependency, not part of these waves.** `feat/design-parity-tokens` supplies the colour/type/spacing tokens (and `K.theme`-equivalent palettes and modes); `feat/design-parity-ui` supplies the component library under `lib/ui`. The prototype's building blocks (from `kit.js`) that the library should cover, and that the waves below assume exist: top bar with back and eyebrow, page, card, chip, button, icon button, row, form field, segmented, toggle row, radio row, slider row, avatar and avatar stack, banner, notice, offline banner, empty state, error state, skeleton, bottom sheet, modal, stepper, PIN pad, keypad, tile (hero/featured/standard, with dot badge), ribbon/dual clock, schedule block, month calendar, record button, player, QR card, toast. A wave that needs a component the library lacks adds a thin local widget and a TODO row in the PR; it never forks a second library.
2. **Standing docs rule (memory: canonical-docs parity).** Any wave that changes shipped behaviour updates MASTERFILE, MARKUP and DEMO with real functional parity in the same PR, then runs `node tools/check-markup.mjs --total <current>` in `scaffold`. This docs-only PR touches none of them.
3. **Prohibitions P1 to P11 are tests, not comments.** Each wave adds or extends a contract test in the style of `child_no_settings_contract_test.dart` for the rules its screens touch (no counts, no scores, no location, no child settings, journal and worry box never visible to guardians, feelings weather never visible to guardians, picture-only child errors).
4. **Offline first.** The `offline-buildable` rows of a wave land first behind local data (LocalStore namespaces, `OnboardingDraftRepository`-style repositories); the `online-parked` rows get a typed repository interface and a fake in the test, so the screen is finished and only the transport is parked.
5. **Matrix bookkeeping.** Each PR edits `matrix.json` statuses for the rows it closes and adds the test file name in a `test` field (the field is introduced by wave P). `tools/check-parity-matrix.mjs` (wave P) fails CI if a row is `built` with no existing test file.
6. **Hardware.** Per the standing verification practice, waves that change child homes or play get a real-device pass on the Fold5 and the tablet (wireless adb notes in memory) at wave end; that is a manual step outside CI and outside this plan's authority to start.

## 1. Waves in recommended order

Order follows the owner's direction: the shell, onboarding/roles and the age-band homes first (they set the look), then the guardian settings hub and suites, then care and coordination, with messages and calls last because they are online-parked. Wave P (the parity harness) has no dependency on the design agents and starts immediately; wave 1a can start in parallel with it.

| Wave | Title | Matrix scope | Size | Mode | Needs design agents |
|---|---|---|---|---|---|
| P | Parity harness | test infrastructure (no rows flip) | M | offline | no (goldens wait for tokens) |
| 1a | Prohibition fixes and label wiring | `#` rows for inbox counts, messages hide, `ContactLabels` | S | offline | no |
| 1b | Role-first onboarding and shell (offline half) | Onboarding and roles (offline rows), Offline states shell rows | L | offline | tokens + ui |
| 2 | Age-band homes | Child home per age band (all), My people, home grows | L (2 PRs) | offline | tokens + ui |
| 3 | Guardian home and settings hub | Guardian home and settings hub, Safety (offline rows), Family structure hub rows | M to L | offline | tokens + ui |
| 4 | Her colour and art, play window | Her colour and art, `g-play`, colour-of-day child flow | M | offline | tokens + ui |
| 5 | Family structure and history | Family structure and ages | M | offline | ui |
| 6 | Child creative, feelings, teen own space, 18 handover | Child games and creative (non-game rows), Teen and 18 handover | L (2 PRs) | offline | ui |
| 7 | Local suites parity | Local suites | M | offline | ui |
| 8 | Child games parity | Child games and creative (game rows) | M | offline | ui |
| 9 | Care and coordination | Care and coordination | L (2 PRs) | mostly online-parked | ui |
| 10 | Onboarding and safety, online half | Onboarding online rows, Safety online rows | L | online-parked | none |
| 11 | Messages and calls | Messages and calls | L (3 PRs) | online-parked | ui |

### Wave P. Parity harness (starts now)

- **Scope.** No rows flip. Builds what every later wave uses to prove parity (section 2 below): `FakeOliveServer`, `FakeClock`, `ScenarioRunner`, scenario vectors, the tokens drift test, the structure-assertion helper, the golden helper with pinned fonts, `tools/check-parity-matrix.mjs`.
- **Files.** `scaffold/client/test/parity/` (new: `fake_olive_server.dart`, `scenario_runner.dart`, `structure_probe.dart`, `golden_harness.dart`), `scaffold/client/test/parity/vectors/*.json`, `scaffold/tools/gen-parity-vectors.mjs` and `scaffold/tools/check-parity-matrix.mjs` (same style as the existing `gen-colour-vectors.mjs`, `gen-family-vectors.mjs`, `gen-learn-vectors.mjs`), `scaffold/tools/parity-shots/` (headless-browser capture script, dev tool only, not run in the main CI job), CI workflow addition to run the parity tests.
- **Depends on.** Nothing. Goldens are generated but marked advisory until `feat/design-parity-tokens` merges.
- **Ports as tests.** The harness itself is tested by replaying a two-step stub scenario.
- **Size.** M. **Risks.** Dart has no equivalent of the prototype's virtual clock and `L.api`; the fake server must implement the contract in `LIVE-API.md` faithfully (error codes `not_a_child_surface`, `stale_version`, `device_revoked`, `invalid_device_credential`, `pin_locked`, `rate_limited`, `role_mismatch`). Keep it a contract mirror, not a second backend.

### Wave 1a. Prohibition fixes and label wiring (S, quick, high value)

- **Scope.** The three places where Flutter breaks a prototype/owner rule today: (1) `InboxScreen` greets the child with a count ("you've got N new messages", `inbox_screen.dart:280`), breaking "the child never sees counts": make it a dot or picture; (2) `parental_controls_screen.dart` lists `tile:messages` as hideable and `child_home.dart:293` honours it, where the prototype refuses (`cannot_hide_messages`): remove it from the hideable set; (3) `contact_labels.dart` (Mommy/Daddy by age, nickname wins) is tested but called by nothing: wire it into My people, the child home greeting and the guardian "Ivy calls you Dada" line. Also reconcile its rule (Flutter caps Mommy/Daddy to a locked age 5 to 15; the prototype, per `LIVE-API.md`, says 5 to 15 only after the age is locked and 'Mom'/'Dad' before the lock, 16 and up 'Mom'/'Dad'); **DECIDE** for ages 3 and 4.
- **Files.** `inbox_screen.dart`, `parental_controls_screen.dart`, `child_home.dart`, `contact_labels.dart`, `family_structure_screens.dart` (`MyPeopleScreen`), tests: `inbox_screen_test.dart`, `parental_controls_screen_test.dart`, new `child_no_counts_contract_test.dart`.
- **Ports as tests.** Scenario `birthday` first step (labels), prohibitions P2/P3.
- **Depends on.** Nothing. **Size.** S. **Mode.** offline. **Risks.** Hiding-messages is currently covered by a spec (parental controls and pacing design, 2026-09-13); removing it needs the owner's explicit nod, so make the PR description say so.

### Wave 1b. Role-first onboarding and shell, offline half (L)

- **Scope.** Rows `ob.role`, `ob.kid.name|age|color|birthday|names|connect|welcome`, `ob.g.you|child|zone|pin|connect|done|join`, `ob.other`, actions `ob.pickRole`, `ob.kid.askLock`, `ob.kid.lockAge`, `ob.pad`, the shell states (`loading`, empty/error states, `stateLine`), `ob.names`, `ob.pinInfo`. Concretely: (a) a role-first first screen (Kid / Mom / Dad / Someone else) replacing `EntryGate`'s child/grown-up buttons; (b) the kid path in the prototype's order (name, age with the confirm-and-lock sheet, colour, birthday, "what do you call your grown-ups", then Connect last); today's flow is name, age, gender, who, colour, birthday and the age picker has no lock (`onboarding_age.dart` offers 2 to 17, `lockKidAge` in `contact_labels.dart` is called by no screen); (c) the guardian path as an offline draft (your name and label, child name and age with lock, home time zone, PIN twice), connect last; (d) nickname fields in `OnboardingDraft` so they upload after pairing; (e) shared empty/loading/error states from `lib/ui`.
- **Files.** `entry_gate.dart`, `first_run_flow.dart`, `onboarding_flow.dart`, `onboarding_age.dart`, `onboarding_who.dart`, `onboarding_draft.dart`, `onboarding_logic.dart`, `guardian_setup.dart`, new `onboarding_role.dart`, `onboarding_guardian_flow.dart`, `main.dart`, `main_live.dart`, `main_live_guardian.dart`, tests beside each, plus `scaffold/packages/onboarding` TS sibling if its sequencing is the shared source (verify before editing).
- **Depends on.** Tokens and ui library; wave 1a for labels. The dual-role question (one APK versus two) is **DECIDE**: the role-first screen can ship inside the demo/offline build now and in the live builds later.
- **Ports as tests.** Scenario `golden` steps 1 to 6 and 9 to 13 (both devices' draft phases, age lock, nicknames) against the fake server. Rows with online rows (`ob.g.connect`, `POST /v1/families`) assert the draft survives and the retry picture appears (offline states), see wave 10 for the real call.
- **Size.** L. **Mode.** offline. **Risks.** Changing `main_live.dart`'s boot order risks the pairing-last behaviour just shipped in #150; keep `FirstRunFlow`'s state machine and add the new steps in front of it. Pairing code alphabet (prototype digits 1 to 9 versus server 0 to 9) is **DECIDE**.

### Wave 2. Age-band homes (L, two PRs: 2a t57 and t812; 2b t1317 and the 13/18 band split)

- **Scope.** All 42 "Child home per age band" rows: `k.home.t57`, `k.home.t812`, `k.home.t1317`, the tile registry and `BANDSET` per band (tile renames: Games, Downtime, Studio, Today), `k.more` per band, `k.people` with the call/message/rename sheet, "your home grows" (`k.birthday` growth page: scene, change list, Not now / Later card, ages 5 and 8 pages), the reduced offline home, tile hides that exclude Messages. Today Flutter renders one standard home for ages 5 and up (`child_home.dart`); `homeVariant` ('pictures'/'words'), `speakEveryWord` and `wordsBesidePictures` are computed in `family_structure_logic.dart` but no widget reads them. Implement as one `ChildHome` that switches on the effective band to per-band layout widgets, with `AgeHome34` as the pattern.
- **Files.** `child_home.dart` (split), new `child_home_t57.dart`, `child_home_t812.dart`, `child_home_t13.dart`, `child_more.dart`, `family_structure_screens.dart` (`MyPeopleScreen`, `BirthdayScreen`), `tiered_tile.dart`, `maturation_ladder.dart`, `family_structure_logic.dart` (decide whether `t13` splits into t1317 and an 18 handover band to match the prototype), tests `child_home_*_test.dart`, `child_no_settings_contract_test.dart`.
- **Depends on.** Wave 1a (labels), tokens and ui (tile, ribbon/dual clock). Wave 4 for the colour-of-day tile content; wave 6 for Journal/Calendar/Privacy destinations (tiles show only when their destination exists).
- **Ports as tests.** Scenario `birthday` (age 12 to 13 at local midnight, band moves, home re-lays itself out, no badge or count), plus the "four homes" snapshot of tile ids per band from the prototype's `BANDSET` as a vector file asserted against Flutter's visible tiles.
- **Size.** L each half. **Mode.** offline. **Risks.** Posture work (foldCover collapse, tabletop split, 600 dp floor, 2.0x text overflow bugs found in #148) must not regress; run each new home through the existing form-factor tests at 344, 390, 600 and 800 dp and at 2.0x text scale. The Flutter-side `t13` band is shared with ladder rungs; splitting it touches `rungsAt` consumers.

### Wave 3. Guardian home and settings hub (M to L)

- **Scope.** `home` (guardian) with the one-sentence state line and the two clocks ("her time, your time"), `more` hub, `settings` hub groups Her / Family / Safety / Learn / Account with the prototype's rows (25 `settings-row` rows), the Age band row opening `AgeBandsScreen` (today an info dialog), Family structure and Family history rows in the hub, `g-planner` (what changes at each age, with per-band hold and reminder), accessibility text size (`g-access`), daily time (`g-play`), parental controls reconciliation (messages unhideable; pace meaning: per-item minimum age in Flutter versus minutes per day in the prototype, **DECIDE**), `g-data` page, `g-pin` change flow (4-digit versus Flutter's 4 to 8 digits, **DECIDE**), Adults and helpers row (today opens `InvitationScreen` with hard-coded labels).
- **Files.** `guardian_home.dart`, `guardian_home_live.dart`, `guardian_more.dart`, `guardian_settings_hub.dart`, `parental_controls_screen.dart`, `access_screen.dart`, `access_settings.dart`, `play_window_screen.dart`, `family_structure_screens.dart` (`AgeBandsScreen`), `invitation_screen.dart`, `pin_gate.dart`, `clear_local_data_screen.dart`, new `age_planner_screen.dart`, tests.
- **Depends on.** Tokens and ui; wave 1b for sign-in/expired states.
- **Ports as tests.** Scenario `play` (set window, wind-down, rest, reopen) for the daily-time and play window; settings-hub snapshot test comparing group/title/subtitle strings against `matrix.json` row strings.
- **STATUS (Wave 3 PR).** Built: hub groups/order/titles (held by `settings_hub_prototype.json`), "Ivy calls you", Age band row opens `AgeBandsScreen`, `g-planner` (`age_planner_screen.dart`), accessibility text size, play window and daily time (scenario `play` 12/12; the wind-down now FOLLOWS the rest time, the prototype's order), Adults and helpers with a labelled invitation preview, Change PIN on the local PIN (explainer, easy-guess and same-PIN refusals, 5 tries then 15 minutes), the guardian home's honest state sentence, Family structure / history / Weekly rhythm / Add tablet rows. Left: messages-unhideable is done by wave 1a; pace meaning (minutes per day vs minimum age) and PIN length 4 vs 4 to 8 stay owner decisions; `g-data` download/sign-out-on-wipe; the per-age hold that ACTS (the planner stores the plan; the single Age bands hold is what acts); a bedtime marker on the play timeline; Her suites as one screen with an On her shelf chip; the simulated co-guardian row (not applicable).
- **Size.** M to L. **Mode.** offline except the PIN server check. **Risks.** `guardian_more.dart` is 984 lines and has accreted demo-only tiles ("Closing ritual (demo)", "Busy fork (demo)", dev passkey): the parity hub should hide dev items behind a debug flag, not delete them (never delete the user's work without asking).

### Wave 4. Her colour and art; play window (M)

- **Scope.** `g-colour`, `g-look`, `k.colour`, `k.c.sort|path|critter|pixel`, art styles, daily colour question. **DECIDE (owner):** the prototype says a guardian never picks or changes her colour for her ("You can't"), while Flutter's `HerColourGuardianScreen` has a guardian colour-day picker, allowed styles and a coding-activities switch. Also the A/B two-up question (Flutter) versus eight swatches (prototype), and the games' age limits.
- **Files.** `her_colour_*.dart`, `colour_*.dart`, `theme_picker_screen.dart`, `palette_logic.dart`, `path_code_screen.dart`, `pixel_garden_screen.dart`, tests.
- **Depends on.** Tokens (palettes `K.SEEDS` versus `palette_logic.dart`: the drift test from wave P is the gate); wave 2 for the Colour tile.
- **Ports as tests.** Palette vector file (SEEDS to Flutter palette) and the colour-of-day sync rule (what the child's tablet shows after a guardian publish).
- **Size.** M. **Mode.** offline (publish to a second device is online-parked, see wave 7 note).

### Wave 5. Family structure and history (M)

- **Scope.** `g-family`, `g-fam-person`, `g-fam-preview`, `g-history`, `g-schedule`, hold/release/undo of a family change, "My people" updating on the child device. Flutter's on-device engine is richer than the prototype (2-2-3, week-on-week-off, postcards, supervised visits); parity here means the prototype's flows work on top of it, not removing the engine. The `differs` rows are mostly "server publishes" versus "same-device LocalStore": the family-change routes are **online-parked** (wave 10), the on-device behaviour is complete earlier.
- **Files.** `family_structure_*.dart`, `rhythm_*.dart`, tests.
- **Ports as tests.** Scenario `family` (add Grandma Rose, hold, history shows held, child unchanged, release, My people shows her).
- **Size.** M. **Risks.** Court-order lock banner in the schedule editor was not confirmed during extraction (`g-schedule` is `uncertain`).

### Wave 6. Child creative, feelings, teen own space and the 18 handover (L, two PRs: 6a creative/feelings, 6b teen)

- **Scope.** 6a: `k.list` (own list at 10), `k.feel`, `k.weather` (sky set differs), `k.worry` (share-with choice Mom/Dad/both versus "my grown-up" only), `k.journal` lock code (missing), `k.weeks` (prototype shows day numbers, Flutter deliberately never formats a date: keep Flutter's rule, **DECIDE**), memory box / capsule / growth, stories, show and tell, jokebook. 6b: `k.cal` (own calendar with per-event sharing), `k.free` (child-published free times), `k.privacy` (who sees what), `k.ladder`, `k.archive` hide control, `k.copy` (prototype shows per-category counts to the child, which breaks the no-counts rule: port without counts), `k.handover` (Keep as an archive, Someday for your own family, preview; `take_and_go_screen.dart` covers only Take and go).
- **Files.** `wants_needs.dart`, `voice_screens.dart`, `journal_screen.dart`, `growing_screens.dart`, `weeks_screen.dart`, `calendar_*.dart` (new child calendar screens), `maturation_ladder.dart`, `gallery_screen.dart`, `take_and_go_screen.dart`, `archive_models.dart`, new `child_privacy_screen.dart`, `child_free_times_screen.dart`, tests.
- **Ports as tests.** Privacy contract tests: journal and worry box not reachable by any guardian code path; feelings weather never in a guardian query.
- **Size.** L. **Mode.** offline. **Risks.** Encryption at rest and the `LocalStore` catalogue (`local_services.dart`) must gain areas for each new store, or the "wipe" screen lies.

### Wave 7. Local suites parity (M)

- **Scope.** `g-suites`, `g-s-rhythm|voice|growing|care|village|compass`, authored-content publish with the "On Ivy's tablet / Waiting to send" tag, sensory model, Voice feelings toggle, Compass free-text questions. **DECIDE:** the prototype publishes guardian-authored content to a separate child device through the server; Flutter suites write LocalStore on the same install. Parity needs either the on-device model with a "this tablet" tag, or the server publish (online-parked). Recommended: keep on-device now, add the tag from local state, port the server publish with wave 10.
- **Files.** `rhythm_voice_*.dart`, `village_*.dart`, `compass_*.dart`, `growing_*.dart`, `rhythm_*.dart`.
- **Size.** M. **Mode.** offline.

### Wave 8. Child games parity (M)

- **Scope.** `k.play`, `k.g.ttt|c4|war|mem|word|pict`: CPU levels Easy/Normal/Hard for tic-tac-toe (Flutter's opponent is random), same-screen two-player mode for every game (none today), a CPU seat for War, Memory pairs (Flutter lists `GameKind.memory` as unbuilt), Guess the word per band (Flutter is guardian-typed hangman), Draw and guess reveal. All ~25 existing Flutter games stay.
- **Files.** `game_*.dart`, `games_hub.dart`, `game_picker.dart`, `game_logic.dart`, `connect4_bot.dart`, `play_window_gate.dart`.
- **Ports as tests.** Scenario `play` (child side: the Games tile goes quiet at rest, in-progress game may finish) and per-game rule vectors.
- **Size.** M. **Mode.** offline. **Risks.** The picker must scale from 6 to 25 games without becoming a settings-like wall; design check at wave 2.

### Wave 9. Care and coordination (L, two PRs: 9a offline UI and local data, 9b server-backed)

- **Scope.** `g-care` hub, `g-emergency` (merge non-overlapping edits on `stale_version`, restore as new version), `g-hospital`, `g-meds`/`g-med` (create, edit, retire: server only has GET and doses), `g-handover` (chain card, per-note fingerprint, "this can never be changed" confirm, 1000-character cap, offline banked queue, add a correction), `g-schedule`, `g-swap` (missing entirely, client and server), `g-overlap` (7 AM to 9 PM overlap window not confirmed in Flutter), `g-expenses` (propose, accept, dispute with reason, reimburse; `proposeExpense` exists but is never called), `g-bag` (Flutter has two unrelated lists; the prototype has one shared list plus "medicines that travel"), `g-binder`, `g-appt`, the home tiles with counts (due now, waiting for you).
- **Files.** `emergency_card*.dart`, `care_screens.dart`, `meds_care.dart`, `handover_notes.dart`, `exchange_screen.dart`, `expenses_screen.dart`, `availability_screen.dart`, `guardian_home.dart` (`_TileSpec` badges), server routes (swaps, medications CRUD) in `scaffold/server`.
- **Depends on.** Server work for swaps and medications; the `LocalServices` catalogue has no area for any of these, so the local/offline part needs new areas.
- **Ports as tests.** No named prototype scenario covers this area; add three to the prototype's console and the vectors: "swap a night round trip", "expense dispute", "handover note correction", so parity has something to replay.
- **Size.** L. **Mode.** mostly online-parked (16 of 24 rows). **Risks.** Hash-chain display must agree with the server's court-export chain verification.

### Wave 10. Online half of onboarding and safety (L)

- **Scope.** `POST /v1/families` (in-app family creation), PIN sign-in/sign-out screens (`ob.signin|expired|signedout`) versus Flutter's "sign out revokes the device", pairing code issuance with PIN gate and rate limits, `g-delete`/`g-hold` with the 6 to 12 month recovery window (server currently deactivates at once; **DECIDE** with counsel on COPPA/P8), family-change publish routes, authored-content publish, `ob.revoked` picture. Needs the server contract settled first.
- **Depends on.** Owner decisions (store posture, dual-role app, recovery window), server work. **Mode.** online-parked. **Risks.** Highest: it makes the chain "sign in, create family, bank message, deliver, read" real.

### Wave 11. Messages and calls (L, three PRs: 11a banking and delivery, 11b child inbox/reply/offline pictures, 11c calls)

- **Scope.** 52 rows: banking rules (bedtime / night / wake), recording and trim, delivery detail and failed/retry/reschedule, notifications (content-free, quiet hours, knocks-through), push priming, "watched = played through" (Flutter marks watched on open), reply modes (voice, drawing, recipient choice), expiry (her replies expire in 14 days unless a grown-up preserves), the child knock-only call model (today the child's "Call Dad" joins a LiveKit room directly; no knock route exists), guardian "Mom will call back" line.
- **Files.** `message_banking.dart`, `inbox_screen.dart`, `receipt_screen.dart`, `call_screen.dart`, `call_knock*.dart`, `push_channel.dart`, `offline_outbox.dart`, `child_home.dart` (`_PresenceCard`), `kiosk_shell.dart`, server routes and the delivery worker.
- **Depends on.** Server delivery worker on a 1-minute cadence, FCM and LiveKit credentials (owner supplies), wave 10.
- **Ports as tests.** Scenarios `golden` steps 14 to 16 (bank, jump to bedtime, arrives and plays, "watched" on the guardian phone), `offline` (tablet offline at bedtime, picture-only state, arrives on return, nothing lost or sent twice), `call` (child knocks, guardian rings, answers, ends; a child can never ring a guardian).
- **Size.** L. **Mode.** online-parked. **Risks.** Real-device verification of calls is still blocked on LiveKit credentials.

## 2. Parity test strategy

Four layers, cheapest and most robust first. Each wave names which layers it uses; a row is `built` only when its test exists and passes.

### 2.1 Scenario replay (behaviour parity). Required in every wave

- The prototype's seven scenarios (`golden`, `offline`, `birthday`, `call`, `play`, `family`, `deletion`; steps are data in `mod-console.js`) and the per-screen rules become **scenario vectors**: JSON files `test/parity/vectors/<scenario>.json` listing, per step, the actor (guardian phone or child tablet), the action by prototype name (`ob.pickRole`, `ob.g.pickAge`, `msg.bank`, `call.knock`, ...), the input, and the expected observable result (screen title, visible strings, tile ids present or absent, error code). Generated once from the prototype by `tools/gen-parity-vectors.mjs` (headless run of the prototype's scenario engine, recording `L.current(dev)` and visible text after each step, in the style of the existing `gen-*-vectors.mjs`), then committed and diffed in CI so prototype drift is visible.
- A Dart `ScenarioRunner` maps each prototype action name to a Flutter interaction (finder by `Key`, so waves must put stable keys named after the prototype ids on interactive elements, for example `Key('ob.kid.pickAge.9')`) and runs the vector against the real screens with `FakeClock` (injected where screens already accept a clock; screens that do not get a clock parameter as they are touched) and `FakeOliveServer` (a `package:http/testing` `MockClient`, which 39 existing tests already use, implementing the `LIVE-API.md` contract: principals guardian/child/sitter, error codes, rate limits, pairing code lifecycle, offline = status 0).
- Two devices in one test: two `MaterialApp` subtrees in a single `testWidgets` sharing one `FakeOliveServer` and `FakeClock`; the test steps alternate actors exactly as the scenario does. Promote to the `integration_test` package on the Fold5/tablet only for wave end hardware passes.
- Assertions are on observable behaviour (text, keys, absence of counts), never on pixel positions.

### 2.2 Tokens drift test

- `tools/gen-parity-vectors.mjs` also exports `tokens.json` from the prototype (`K.SEEDS`, `K.theme(palette, mode)` for each palette and mode, type scale, radii, spacing, the `--font-display`/`--font-body` stacks). A Dart test (`test/parity/tokens_drift_test.dart`) asserts every value equals the Flutter token (`design_tokens.dart`, `theme_data.dart`, `lib/ui` tokens from `feat/design-parity-tokens`) within an exact-hex tolerance. This is the gate that keeps look parity from silently rotting; it reuses the pattern of `gen-colour-vectors.mjs`.

### 2.3 Structure assertions (layout parity, robust)

- A `StructureProbe` test helper extracts, for a screen under test, the ordered list of landmark components by key (top bar, hero tile, featured grid, standard grid, bottom sheet, notice) and their normalised rectangles (fraction of viewport), and compares them with the same data extracted from the prototype's DOM (the headless script reads bounding boxes of elements chosen by stable class names from `kit.js`; if that proves brittle, add a `data-pid` attribute to the kit helpers, a small prototype-side change needing its own PR on the round3-live branch). Tolerance is generous (for example 3 percent of viewport) because it checks layout, not pixels. Viewports: Fold5 cover 344x882, phone 390x844, tablet 800x1280, each at 1.0x and 2.0x text scale (the sizes that already produced overflow bugs in #148).

### 2.4 Screenshot comparison (look parity, advisory first)

- **Reference side.** `tools/parity-shots/` loads `docs/superpowers/mockups/live/index.html` in headless Chromium (Playwright, a dev-only dependency kept out of `scaffold/client`), freezes the virtual clock (`L.setClock({paused:true})`), forces `prefers-reduced-motion`, injects the same two font families Flutter bundles (`AtkinsonHyperlegible` and `BricolageGrotesque`, both already in `pubspec.yaml`) from local files instead of Google Fonts so rendering does not depend on the network, drives the scenario with `L.reset({scenario:id})` (the console's own autostart) or by calling the same `L.tap`/`L.run` actions the scenarios use, and writes one PNG per prototype screen id at each viewport and in light and dark mode into `build/parity/reference/<id>.png`.
- **Flutter side.** Golden tests (`matchesGoldenFile`; none exist today) under `test/parity/golden/`, using the pinned bundled fonts via `loadAppFonts`, fixed device sizes, `FakeClock`, animations settled, generated and compared only on the pinned Linux CI runner (goldens are platform dependent), output to `build/parity/flutter/<id>.png`.
- **Comparison.** A script produces a side-by-side PNG and a perceptual-difference score (SSIM) per screen id and uploads it as a CI artifact `parity-report`. Phase 1 (until tokens and ui merge): report only, never fails. Phase 2: the threshold becomes a per-screen gate recorded in `matrix.json` (`lookScore`), ratcheted up as waves land; a wave may not lower an existing screen's score.
- **Rejected alternative.** Pixel-exact comparison across Chromium and Skia: text anti-aliasing and font hinting differ by renderer, so exact diffs are noise. Hence the tiering: behaviour exact (2.1), tokens exact (2.2), structure within tolerance (2.3), pixels perceptual and advisory (2.4).

### 2.5 Which layers each wave uses

| Wave | 2.1 scenario | 2.2 tokens | 2.3 structure | 2.4 shots |
|---|---|---|---|---|
| P | self-test | creates | creates | creates |
| 1a | yes (labels) | no | no | no |
| 1b | golden steps 1 to 13 | yes | onboarding screens | advisory |
| 2 | birthday | yes | four homes | advisory, gate for the four homes |
| 3 | play | yes | hub | advisory |
| 4 | colour sync | yes (palettes) | no | advisory |
| 5 | family | no | no | no |
| 6 | privacy contracts | no | no | advisory |
| 7 | new vectors | no | no | no |
| 8 | play (child side) | no | no | no |
| 9 | three new vectors | no | no | no |
| 10 | golden connect, deletion | no | no | no |
| 11 | golden 14 to 16, offline, call | no | no | no |

## 3. Recommended first three waves

1. **Wave P** (parity harness) and **wave 1a** (prohibition fixes and label wiring) in parallel: neither depends on the design agents, 1a removes live rule violations (child sees a count, Messages can be hidden, nickname/label rule unused), and P is the gate for everything else.
2. **Wave 1b** (role-first onboarding and shell, offline half): sets the first thing a family sees and the look of the shell; ready to start the moment `feat/design-parity-ui` merges.
3. **Wave 2** (age-band homes, 2a then 2b): the largest visible gap (one home for all ages from 5 up, versus four bands), the surface the child lives in, and the place where look parity is most noticed.

## 4. Open owner decisions that block or shape waves

Dual-role app versus two listings (1b, 10); pairing-code alphabet 1 to 9 versus 0 to 9 (1b; RESOLVED 0 to 9, see PARITY.md); Mommy/Daddy rule at ages 3 and 4 (1a); the gender onboarding step (1b); `t13` split into 13 to 17 and an 18 handover band (2); guardian colour picker versus "a grown-up can never pick her colour" (4); parental-controls pace meaning and hiding Messages (1a, 3); PIN length 4 versus 4 to 8 (3); `k.weeks` day numbers (6); on-device versus server publish for authored suites (7, 10); the 6 to 12 month recovery window and the counsel items (10); i18n scope now or later; captions.
