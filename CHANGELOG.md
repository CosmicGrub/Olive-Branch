# OLIVE BRANCH — CHANGELOG

All notable changes to this project are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
applied to the **specification**, not to shipped software.

**Canonical.** This file is amended, never duplicated. Every entry has a matching
section in `MASTERFILE.md` and a matching panel in `VISUAL.html`.

**Prohibitions.** Any change that removes or weakens an entry in MASTERFILE §2.1
must appear here by prohibition number, with the requester and the rationale.
Silent deletion is a process failure.

---

## [Unreleased]

### Reversed
- **§16.2 #6 — call/video infrastructure, reversed at the owner's direction.**
  v0.40.0 settled on staying on LiveKit Cloud (see the callout above the tech
  stack table in MASTERFILE.md). That is now superseded: Olive moves to
  **Jitsi Meet + Jitsi Videobridge** as the basis for all calls, video calls,
  screen-sharing, and streaming. Staged in two steps — Step 1 (in progress)
  proves the calling UX against Jitsi's public `meet.jit.si` server via the
  official `jitsi_meet_flutter_sdk`; Step 2 (staged and container-verified
  as of v0.46.2, not yet device-verified) self-hosts the full stack
  (Prosody, Jicofo, Jitsi Videobridge). `scaffold/client/pubspec.yaml`
  dropped `livekit_client` for `jitsi_meet_flutter_sdk`;
  `scaffold/tools/local-call-server.mjs` (LiveKit token minting) was replaced
  by `scaffold/tools/local-call-room-server.mjs` (Jitsi room-name
  coordination only — no JWT to mint against a public server).
  `packages/session-runtime/src/rooms.ts` is untouched; its I1/I4-preserving
  `createSession`/`mintToken` are reused as-is, just without forwarding the
  LiveKit-shaped `grant` to the client. Left in place rather than deleted per
  standing practice, so the reversal is visible rather than gradual.

### Rejected
- **§16.2 #12 — child-initiated affection signal ("send a hug"), rejected at the
  owner's direction.** Raised while evaluating a Gemini-drafted alternate build
  for compatible additions; the owner reviewed the five open questions (spam
  pressure on the receiving parent, interaction with the `pending_asks` ceiling,
  sender symmetry, voice-memo retention treatment, and whether showcase/letters
  already cover the need) and declined the feature outright rather than resolve
  them. **Unlike §16.2 #10 (foster/kinship, deferred — not needed *yet*), this is
  not a deferral.** The owner does not want this in the product. Recorded in
  §19 as considered-and-declined rather than removed silently, per standing
  practice — but with no revisit date and no scaffold, since there is nothing
  here worth keeping a foothold in. Should not be re-proposed absent new
  direction from the owner.

Phase 2 decisions: §16.2 #6 Step 2 (self-hosting Jitsi). §21.9 D — whether
"becomes a parent" reuses the account. (§16.2 #8 was resolved in 0.40.0 — this
line went stale for three versions before being caught here.)

---

## [0.46.2] — 2026-08-08 — §16.2 #6 Step 2 staged and container-verified

The other bug from v0.46.0's callout — the public server's moderator lobby —
gets its fix staged: a local `docker-jitsi-meet` stack
(`scaffold/tools/jitsi-selfhost/`), actually brought up on this dev machine
rather than only written and assumed correct. Doing so surfaced three real
bugs, all fixed; what's confirmed and what isn't is kept explicit below,
same standard v0.46.0/v0.46.1 already hold this project to.

### Added
- **`scaffold/tools/jitsi-selfhost/`** — `setup.sh` (clones
  `jitsi/docker-jitsi-meet` pinned to `stable-11146-1` into a gitignored
  `.jitsi-docker/`, layers `olive.env` over upstream's `env.example`, runs
  `gen-passwords.sh`, installs `docker-compose.override.yml`),
  `olive.env` (anonymous domain — no `ENABLE_AUTH` — is the whole point;
  see its own inline comments for why each setting is what it is), and
  `docker-compose.override.yml` (the Windows bind-mount fix, see "Fixed").
  `scaffold/tools/with-jitsi.sh` mirrors `with-livekit.sh`'s lifecycle
  pattern (bring up, wait for health, optionally run a command, `down` to
  tear down) but — unlike `with-livekit.sh` — leaves the stack running by
  default, since a multi-container compose stack is too slow to cycle per
  test run.
- **`JITSI_SERVER_URL` env var** in `local-call-room-server.mjs`, defaulting
  to `https://meet.jit.si` so the original v0.46.0 finding stays
  reproducible with no config; override to point at the local Step 2 stack.
  `call_screen.dart`'s header comment updated to match.

### Fixed — three bugs found by actually running this, not by reading the compose file
- **Docker Desktop's containerd-snapshotter image store corrupted these
  images' user resolution.** Every container failed identically —
  `unable to find user s6: no matching entries in passwd file` — reproduced
  even with a bare `docker run --entrypoint sh`, ruling out a compose/volume
  cause. Root cause: `UseContainerdSnapshotter: true` in Docker Desktop's
  own `settings-store.json`; the classic `overlay2` graphdriver doesn't have
  this bug. Fixed by flipping the setting, restarting Docker Desktop, and
  re-pulling the images clean. Not specific to this project.
- **JVB's colibri HTTP port (`8080` default) collides with
  `server/index.mjs`'s own `PORT` default.** Found via `docker compose ps`
  after first bringing the stack up, not from reading `docker-compose.yml`
  — the collision is with this project's own server, not anything in
  upstream Jitsi. Fixed: `JVB_COLIBRI_PORT=8181` in `olive.env`.
- **Prosody couldn't write its own TLS cert.** `docker-jitsi-meet`'s default
  `${CONFIG}/storage/prosody:/var/lib/prosody` bind mount, with `CONFIG` a
  Windows host path, loses POSIX ownership through Docker Desktop's
  file-sharing translation — Prosody's container (uid 1000) can never write
  into it, so cert generation silently failed (`The directory
  /var/lib/prosody is not owned by the current user`), cascading into
  Jicofo and JVB's XMPP connections failing outright (`No stream features
  to proceed with`) — the whole signaling chain was down, presenting as a
  Jicofo/JVB problem rather than obviously a Prosody one. Fixed:
  `docker-compose.override.yml` gives Prosody's two writable paths named
  Docker volumes instead of Windows bind mounts, installed automatically by
  `setup.sh`.

### Verified
- All four containers (prosody, jicofo, jvb, web) reach a stable `Up` state
  with no restart loop, after the three fixes above.
- Jicofo's log shows it discovering Prosody's components (lobby, breakout,
  av-moderation, etc.), joining the JVB brewery MUC, and registering the
  videobridge — the full signaling handshake completes, not just individual
  containers reporting healthy in isolation.
- Prosody's own **live-rendered** config
  (`/run/prosody/config/conf.d/jitsi-meet.cfg.lua` inside the container,
  read directly rather than inferred from env vars) confirms
  `authentication = "jitsi-anonymous"` on `VirtualHost "meet.jitsi"`, with
  `muc_lobby_rooms` loaded as an available module but no forced-lobby or
  auth-gated-moderator setting anywhere in the rendered config — the actual
  mechanism, not just the compose file, that avoids the meet.jit.si
  moderator-lobby finding from v0.46.0.
- `curl -sk https://127.0.0.1:8443/` returns the real Jitsi Meet SPA
  (HTTP 200).
- Stack torn down cleanly after verification (`with-jitsi.sh down`); named
  volumes (certs, registered users) persist for the next `up`.

### NOT verified — and why this entry says so rather than claiming otherwise
No real WebRTC join was completed. The stack's self-signed cert (no
`ENABLE_LETSENCRYPT` — that needs a real public DNS name, out of scope for
localhost dev) blocks a browser outright — confirmed via the Chrome
devtools protocol: `net::ERR_CERT_AUTHORITY_INVALID` on every request to
`https://127.0.0.1:8443` — and would equally block
`jitsi_meet_flutter_sdk` on a real device, which has no client-side
"skip cert validation" flag. Fixing that (a `<trust-anchors>` entry in
`network_security_config.xml` for dev builds, or running the stack behind a
tunnel with a real cert) is not done here. Physical two-device
re-verification — the standard v0.46.0 itself holds this project to — is
also not done: this session has no attached Android hardware, and the
cert-trust gap above would block it even if it did. Tracked in
`scaffold/tools/jitsi-selfhost/README.md`'s status note, and in the §16.2
#6 callout and §20.2b in MASTERFILE.md.

---

## [0.46.1] — 2026-08-08 — the kiosk-lock half of §16.2 #6 fixed, not yet re-verified live

v0.46.0 drove §16.2 #6 Step 1 end to end on two physical devices and found
two independent bugs. This increment fixes one of them — the child-side
kiosk-lock/Activity conflict — and evaluates the three options v0.46.0's
callout left open. The other bug (the public server's moderator lobby) is
untouched, still gated on Step 2.

### Fixed
- **Kiosk lock-task vs. the Jitsi call Activity (§16.2 #6, §5.20).**
  `jitsi_meet_flutter_sdk` launches calls in `WrapperJitsiMeetActivity`
  (`singleTask`), which Android's `ActivityTaskManager` opens in a new task
  regardless of shared package identity — exactly what screen-pinning
  refuses mid-lock, logging `Attempted Lock Task Mode violation` and leaving
  `call_screen.dart`'s "Joining…" spinner waiting forever on a callback from
  an Activity that never started.
  - **Device-Owner lock-task allowlisting — ruled out.** Both real test
    devices already carry ordinary Google/system accounts;
    `dpm set-device-owner` refuses on a device with any existing account
    short of a factory reset. Not viable for an already-provisioned family
    phone, which is this app's actual deployment shape.
  - **Embedding the call without a second Activity — deferred.** Jitsi's
    Android SDK is React-Native-based with no fragment/embedded-view entry
    point today; a Flutter `PlatformView` bridge into it is real future
    work, not a same-session change.
  - **Implemented: a lock-task handoff**, not a plain unpin/re-pin. A naive
    exit-and-re-enter was checked against `WrapperJitsiMeetActivity`'s own
    `singleTask` semantics and found to leave the *entire call*, not just
    the transition, unpinned — the call Activity opens in a separate task
    that re-pinning the original Activity never reaches. Instead:
    `client/lib/kiosk_channel.dart` gets `beginCallHandoff()`;
    `KioskBridge.kt`'s new `beginCallHandoff` method unpins `MainActivity`
    and flags the coming `onStop()` as an intentional handoff rather than a
    kiosk defeat; the already-patched
    `client/third_party/jitsi_meet_flutter_sdk_patched/.../WrapperJitsiMeetActivity.kt`
    self-pins for the call's duration and reports its own mid-call defeat
    (Back+Recents during the call) back through the same `lockTaskExited`
    event path an ordinary defeat already uses — calling capability adds no
    new, undetected escape route. The app module and the Jitsi plugin
    module have no compile-time reference path between them (a library
    can't depend on the app consuming it), so the two sides coordinate
    through a SharedPreferences flag and a `LocalBroadcastManager` action,
    string-mirrored across files the same way the MethodChannel/EventChannel
    names already are.
  - Surfaced one real build gap along the way: `androidx.localbroadcastmanager`
    was reachable from `WrapperJitsiMeetActivity.kt`'s own module (a
    transitive dependency of `org.jitsi:jitsi-meet-sdk`) but not from the
    app module — Flutter wires plugin modules in as `implementation`, which
    doesn't expose a dependency's own transitive deps to the consumer.
    `compileDebugKotlin` failed with `Unresolved reference
    'localbroadcastmanager'` until `android/app/build.gradle.kts` declared
    it explicitly.

### Verified
- `flutter analyze`: clean. `flutter test`: all 1239 tests pass, including
  3 new ones in `test/kiosk_channel_test.dart` covering `beginCallHandoff`'s
  method-channel contract and its `MissingPluginException` degradation.
- `node packages/transport/test/transport.test.mjs`: 66 passed, 0 failed —
  the Android-source-no-longer-UNVERIFIED assertion still holds against the
  new `KioskBridge.kt` code.
- Full Gradle/Kotlin build succeeds across both the app module and the
  patched Jitsi plugin module (`flutter build apk --debug`).
- Reinstalled on the real Fold5 from v0.46.0's session: the OS's own "App is
  pinned" dialog appeared and `dumpsys activity activities` reported
  `mLockTaskModeState=PINNED`, confirming screen-pinning still engages
  correctly under the changed `MainActivity.kt`.

### NOT verified — and why this entry says so rather than claiming otherwise
Whether `WrapperJitsiMeetActivity` actually launches under the handoff
without the violation, and whether the pin visibly survives the Activity
swap, was **not** confirmed live this session. A concurrent session was
mid-edit on this same repo (§16.2 #6 Step 2 self-hosting work) and, per
logcat (`PackageManager: installation completed for package:
com.olivebranch.olive_client`), reinstalled the app on the same physical
Fold5 mid-test, killing the run before the call attempt completed. This
failure mode produces no crash and no visible error under `flutter test` —
a green CI run would look identical whether the fix works or not — so it is
recorded here as unverified rather than assumed working from the code path
alone. See `client/docs/MANUAL_VERIFY_call_lock_task.md` for the exact
procedure to finish this once the devices are free, and update that file's
own Provenance section with the real outcome when it's run.

---

## [0.46.0] — 2026-08-07 — the client's first live screen, a CI blind spot closed, and the call verified broken on real devices

A stranded branch merge finished, a real CI gap found and fixed, and — the
headline finding — §16.2 #6 Step 1 (Jitsi over the public server) driven
end to end on two physical Android devices rather than trusted from code
review. It does not work, on either device, for two independent reasons.

### Added
- **`LiveChildHomeScreen` (`client/lib/child_home_live.dart`) +
  `main_live.dart`.** The first client screen wired to real network calls
  instead of demo constants: fetches `/v1/me` + `/inbox` through the
  existing dev-login path, reuses `ChildHome` unmodified so every invariant
  its own test suite already asserts still holds on the live path, and is
  honest about what isn't real yet — `presence` and `sleepsUntilHandover`
  render as an absence, not a guessed number, since no day-part or
  custody-schedule endpoint exists server-side. 4 new tests (loading,
  real-data render, unreachable-server retry, recovery).
- **`server/routes.mjs`**: `/v1/me` now resolves a real `display_name`
  instead of returning bare ids.

### Fixed
- **`.github/workflows/verify.yml` had never once run.** It lived at
  `scaffold/.github/workflows/verify.yml` — GitHub Actions only discovers
  workflows under `<repo-root>/.github/workflows/`. Confirmed via
  `gh api repos/.../actions/workflows` returning zero registered workflows
  despite Actions being enabled repo-wide and the file existing on every
  branch since it was introduced; `gh run list` returned an empty run
  history for the entire project. Fixed with a `git mv` to the true root.
  **Not live yet** — blocked on an OAuth token missing the `workflow` scope
  needed to push a change under `.github/workflows/`; the commit is queued
  and pushes as soon as that scope is granted.
- **`call_screen.dart`'s `devRoomServerBase` hardcoded a dead LAN IP**
  (`192.168.1.78`, from a network this project is no longer on) — silently
  breaks two-device testing with no clue why. Switched to `127.0.0.1` +
  `adb reverse tcp:8787 tcp:8787` per device, which works over USB
  regardless of whether the phones and the dev machine share a WiFi network.
- **`network_security_config.xml` still whitelisted the old LAN IP** after
  the fix above — config drift caught in the same pass. Updated to match.

### Verified — and found broken, on two real devices
§16.2 #6 Step 1 was driven end to end on a guardian tablet and a child's
Galaxy Z Fold5, in both join orders. Neither completes, for two independent
reasons (full detail in the §16.2 #6 callout in MASTERFILE.md and the new
§20.2b row):

- **The child's kiosk lock blocks the call from ever starting**, and this
  is orthogonal to Step 1 vs. Step 2 — self-hosting will not fix it alone.
  `jitsi_meet_flutter_sdk` opens calls in a separate `singleTask` Activity;
  Android's screen-pinning (§5.20, engaged for real on the child side)
  refuses to launch it — `E/ActivityTaskManager: Attempted Lock Task Mode
  violation` — and `call_screen.dart`'s "Joining…" spinner waits forever on
  a callback from an Activity the OS never started.
- **The public `meet.jit.si` server puts new rooms in a moderator-approval
  lobby** — `[app:lobby] Lobby starting knocking (membersOnly = ...)` in the
  SDK's own log, on the guardian side, which otherwise connected cleanly and
  captured real camera/mic. No login/moderator flow exists to clear it. This
  is evidence *for* Step 2 (self-hosting), not a reason to distrust Jitsi
  generally.

Neither device crashed — both degrade to a stuck-but-recoverable state,
confirmed against a full logcat capture with zero `FATAL EXCEPTION`s from
the app across the session. Homework capture, the emergency card, and
general navigation were also spot-checked on both physical devices (tablet
+ Fold5) with no crashes or layout issues found beyond what the 0.45.0
responsive pass already covered.

---

## [0.45.0] — 2026-08-04 — Windows joins the kiosk bridge, a watch companion, and a responsive-hardening pass across every screen

§8.3's platform table listed Android real, Windows and iOS as gaps. This
increment closes the Windows half honestly — a real bridge that has never
actually been run end to end, not a rewritten contract stub — and adds a
Wear OS companion that is explicitly a demo shell. It also runs the full
95-screen client back through the four required viewports and fixes what
that audit found.

### Added
- **`client/windows/runner/kiosk_bridge.{h,cpp}`** — a real Win32 kiosk
  implementation, not a stub: strips the window's caption/system menu/
  resize border and maximizes it, installs a `WH_KEYBOARD_LL` hook that
  swallows the Windows key, Alt+Tab, and Ctrl+Esc, and re-arms it on a 3s
  heartbeat to detect the OS silently dropping a slow low-level hook. **This
  is an app-level lock, not OS Assigned Access** — see the §8.3 table
  correction below. **Ctrl+Alt+Del is deliberately left untouched** —
  OS-reserved, not deliverable to any user-mode hook — and the header
  comment says so rather than implying otherwise by omission.
  `lockTaskMode()`/`isDeviceOwner()` report `"assigned"`/`false`, matching
  what Windows actually lets an app claim. `flutter_window.{h,cpp}` wires it
  into the engine messenger; `scaffold/native/windows/AssignedAccessBridge.cs`
  (the old contract-only C# stub) is deleted — `scaffold/native/` is now
  empty.
- **A Galaxy Watch6 companion** (`client/android/wear/`) — a standalone Wear
  OS Gradle module (Jetpack Wear Compose) showing a sleeps-until-handover
  count and a "Call Dad" button. Compiles and installs as a real,
  standalone-launchable APK. **Explicitly a demo**: phone↔watch sync via the
  Wear Data Layer API is not implemented.
- **`tools/verify.sh` gains a `:wear:assembleDebug` gate**, same "gap, not
  skip" posture as the existing `:app:compileDebugKotlin` one.
- **Responsive-hardening pass, all 95 client files**, re-audited at the four
  required viewports (Fold5 cover 344px, Fold5 main 673×841, phone 390px,
  tablet/desktop ~1100px). Ten real overflow/layout bugs found and fixed —
  the chess/checkers button bars, the chain/story turn banners, the
  word-search default grid, `the_book.dart`'s stat row,
  `weeks_screen.dart`'s legend chip, `collection_screen.dart` (plus a latent
  reorder identity-key bug found the same pass), `court_export.dart` /
  `gallery_screen.dart`, `guardian_home.dart`'s action grid, and a real dead
  prop in `child_home.dart`: `unreadCount` was accepted by the constructor
  but never rendered anywhere — now drives a badge on the Messages tile.
  ~55 files were confirmed already correct at all four widths, with test
  coverage added regardless so this is a permanent regression guard, not a
  one-time pass.

### Fixed
- Two hygiene bugs bundled in because they were on files already open for
  the audit: `birthday_marked.dart`'s duplicated month-name list, and a
  misplaced widget `Key`.

### Verified
- `flutter analyze` (client): clean.
- `flutter test` (client): **1235 passed, 0 failed** (up from 76).
- `npm run test:transport`: 60 passed, 0 failed, including new Windows
  J-bridge contract assertions.
- `:wear:compileDebugKotlin` and `:wear:assembleDebug`: BUILD SUCCESSFUL.

### Out of scope, on purpose
- **`flutter build windows` does not run here** — the local Visual Studio
  Build Tools install is missing the "Desktop development with C++"
  workload (confirmed via `vswhere.exe` and `flutter doctor -v` — a real
  gap, not a code problem). Substitute verification: the new/modified C++
  was compiled directly with `cl.exe /W4` against the cached Flutter
  Windows embedder headers — 0 errors, 0 warnings. **Still marked
  UNVERIFIED** in both the header comment and the transport contract test,
  same discipline Android only dropped the marker under after an actual
  successful build+run on a real device.
- Phone↔watch data sync (Wear Data Layer API) — flagged for follow-up, not
  attempted this pass.

---

## [0.44.0] — 2026-08-04 — fourteen groups, one navigation graph

Fourteen parallel build groups had each shipped their assigned client screens
in isolation — onboarding, games, storyteller, journal/letters, calendar,
guardian ops, live-call extras, showcase, archive/export, and the maturation
ladder — landing 75 new files in `client/lib/` with zero existing files
touched, per every group's own report. Correct in isolation, and exactly the
gap the v0.30.0 standing rule ("everything shipped renders in the demo") was
written to catch on the web side: **62 of the batch's 72 MARKUP screens had no
path to them from either home screen in the actual Flutter client.**
`GamePickerScreen`, `HomeworkScreen`, `InboxScreen` existed and compiled; a
family opening the app could not reach them.

### Added
- **`client/lib/hub_widgets.dart`** — `HubTile`/`HubSection`, the shared
  list-tile chrome the three new hub screens below are built on, so they read
  as one system rather than three groups' worth of ad hoc layouts.
- **`client/lib/games_hub.dart` — `GamesHubScreen`.** `game_picker.dart`'s own
  catalogue only ever renders cards for its four ported `GameKind` values
  (tic-tac-toe, dots & boxes, memory, story); the concrete boards other
  groups built (checkers, chess, battleship, word search, Kim's game, word
  chain, scavenger hunt, find the thing) had no picker of their own. This is
  the second door — reached from ChildHome's new "More games" tile —
  alongside `GamePickerScreen`, not a replacement for it.
- **`client/lib/child_more.dart` / `guardian_more.dart`** — "More for you" /
  "More" hubs holding every remaining child- and guardian-facing screen that
  doesn't warrant its own top-level tile (journal, letters, weeks, the
  ladder, teach-me, the quiet corner, doodle desk, colouring, the shared
  gallery, the story library, shared reading, and, on the guardian side, the
  expiry digest, court export, year book, gallery, show-me, closing ritual,
  call security, live-degrade demo, busy-fork demo, kiosk advisory, invite-a-
  co-parent, guardian setup, her colour, the ladder's guardian view,
  siblings, deletion, and storyteller safety) — so neither home screen's grid
  had to grow past what a real dashboard, or a young child, can scan.
- **`client/lib/onboarding_flow.dart` — `OnboardingFlowScreen`.** The
  onboarding group's own report noted every first-run screen it built is
  "fully self-contained via constructor callbacks, so it can be sequenced
  ... without any code changes" — this is that sequencing glue (name → age →
  who → colour → birthday month → day → marked), reached from
  ChildMoreScreen's "Redo the welcome tour" since no real first-run detector
  exists yet to trigger it automatically.
- **`client/lib/shared_gallery.dart`** — the single `AppGallery` instance
  `snapshot_button.dart`'s own wiring note asked for ("one instance app-wide
  ... so saves accumulate in one place"), constructed once and shared by
  `AppGalleryScreen`'s new entry point.
- **`child_home.dart`**: `Homework` → `HomeworkScreen`; `Play together` →
  `GamePickerScreen` (wired for its `story` kind to the real
  `GameStoryScreen`, honest not-built-yet for the rest of its own
  catalogue); `Messages` → `InboxScreen`; four new tiles (`More games`, `My
  day`, `Storyteller`, `Show & tell`, `More for you`).
- **`guardian_home.dart`**: the `Exchange` and `Expenses` stub tiles now
  route to `ExchangeScreen`/`ExpensesScreen`; four new tiles (`Send-time
  guard`, `Meds & care`, `Morning briefing`, `Care note`, `More`).
- **62 of the 72 MARKUP screens marked `data-amended="0.44.0"`** in
  `MARKUP.html` — every slug this pass gave a real navigation path to, found
  by grepping each new file's own "Renders MARKUP screen '…'" header comment
  against every `data-screen` in the document rather than trusting either
  side's naming.

### Fixed
- **`child_home.dart` and `guardian_home.dart`'s outer `ListView` silently
  dropped content below the fold from the element tree**, not just from
  view — the same sliver-virtualization defect several of the fourteen
  groups independently hit and fixed in their own files this batch
  (`message_banking.dart`, `letters_screen.dart`, and others, per their
  reports). Invisible until this pass's own grid expansion pushed
  `child_home.dart`'s "sleeps until" counter past the default test viewport
  and `invariants_test.dart` caught it for real, not by inspection. Both
  files now use `SingleChildScrollView` + `Column`, matching the convention
  the affected groups already established.
- **`widget_test.dart`'s stub-tile test still tapped `Exchange`**, which this
  pass gave a real screen — repointed at `Availability`, the one guardian
  tile with no implementing screen anywhere in the batch (confirmed by the
  same MARKUP-header grep above: nothing renders that slug).
- Naming/argument mismatches surfaced while wiring, all fixed at the call
  site rather than in the fourteen groups' own files: none found — every
  constructor signature in the eleven agent reports matched the actual
  source exactly on inspection.

### Verified
- `flutter analyze` (client): clean — 2 pre-existing `prefer_initializing_formals`
  info lints in `game_chess.dart`, already noted and accepted in that group's
  own report.
- `flutter test` (client): **874 passed, 0 failed**, run once as one suite
  against the fully-wired app rather than per-group — the fourteen groups
  each verified their own files in isolation and reported different partial
  totals (828–861 passed) with a handful of cross-group collisions they
  correctly attributed to concurrent editing, not to their own work; this is
  the first run of the whole client suite together. Includes 7 new parity
  tests added to `widget_test.dart` for the tiles this pass wired.

### Out of scope, on purpose
- **`availability`** — MARKUP's own guardian-surface slug, "when he can
  actually be reached, honestly rendered." No file in this 70-file batch
  renders it under any name (verified by header grep, not assumption); the
  guardian tile stays an honest not-built-yet stub rather than being pointed
  at `sendguard` or `busyFork`, which are real but answer a different
  question.
- **`SnapshotButton` embedded on every play/create surface.** The button
  itself needs a `currentSurface` id and the shared `AppGallery`; wiring it
  onto `doodle_desk.dart`/`colouring_screen.dart` would mean editing those
  groups' own files rather than adding new ones, which this pass avoided by
  policy. `AppGalleryScreen` (the gallery it saves into) is reachable from
  `ChildMoreScreen` today; the button itself is a follow-up.

---

## [0.43.0] — 2026-08-04 — the native kiosk bridge, for real

Picked up as the standing gap named identically by MASTERFILE §20.2b, this
file's own `[Unreleased]` section, and the code's own comments in `main.dart`
("no kiosk lock... NOT kiosk-locked: standard Android navigation still
works"). Built on top of what the other active line of work had already
landed rather than redoing it — `kiosk_channel.dart` (the Dart platform
channel) and `pin_gate.dart` (the shuffled keypad) were already complete and
correct, just never wired to anything.

### Added
- **`client/android/.../KioskBridge.kt` — real, not reference.** The
  `native/android/KioskBridge.kt` copy (wrong package, "never compiled, never
  run on a device") is retired; the real implementation now lives in the
  actual Gradle module and is registered from `MainActivity.kt`
  (`configureFlutterEngine`), which was previously a bare `FlutterActivity`
  subclass with zero overrides.
- **`client/lib/lock_controller.dart`** — a 1:1 semantic port of
  `packages/child-lock/src/lock.ts` to Dart (same function names, same
  ordering, same constants), so the two stay auditable side by side the same
  way the cross-language channel contract already is.
- **`client/lib/kiosk_shell.dart`** — the missing wiring. Owns a
  `LockController`, engages the native lock on entry, and renders exactly one
  of ChildHome / PinGate / a locked-out surface through `canRender()`'s
  deny-by-default gate. Replaces `child_home.dart`'s labeled dev-preview PIN
  button with the real trigger.
- **`packages/child-lock/test/lock.test.mjs`** (47 assertions) — the TS state
  machine had zero tests since it was written at v0.7.0; an orphaned package
  despite being logic-complete. Wired into `verify.sh` and `package.json`.
- **`client/test/lock_controller_test.dart`** (17 assertions) mirrors the same
  coverage against the Dart port. `client/test/invariants_test.dart` gained a
  `KioskShell` group (5 assertions) exercising the actual widget: a
  `lockTaskExited` event lands on the PIN gate and never the child surface, a
  correct PIN after a defeat recovers, five wrong PINs lock out without ever
  fabricating error copy.
- **An Android toolchain gate in `verify.sh`.** There was no native-Android
  check in the automated suite at all before this — only Dart analyze/test
  touched `client/`. Runs `:app:compileDebugKotlin` when an SDK is present;
  logs the same "MISSING TOOLCHAIN — not a skip, a gap" pattern as the
  existing Dart/LiveKit gates otherwise.

### Fixed
- **A real bug caught by the new gate before this even shipped**: the first
  version of `MainActivity.kt` registered a `BroadcastReceiver` for
  `Intent.ACTION_LOCK_TASK_ENTERING`/`_EXITING`, names that do not exist in
  the public SDK (compileSdk 36 — "Unresolved reference"). Replaced with a
  mechanism built entirely on APIs already proven to compile
  (`ActivityManager.getLockTaskModeState()`, the same call `currentMode()`
  already used): poll the mode at `onStop()`/`onResume()` and diff against
  the last-observed value. Exactly the standing-rule-5 failure mode this
  project keeps finding — a declaration (the reference copy's channel
  contract) that had never actually been exercised.
- **`KioskBridge.register()`'s `events` parameter was accepted but never
  wired to a stream handler** in the original reference copy — a declaration
  without an implementation, invisible only because that copy was never
  compiled. Fixed in the real module.
- **The stale "*End of MASTERFILE v0.37.0*" closing line**, five versions
  behind the header's own `0.42.0` — the header advanced with every
  increment from 0.38.0 on; the footer didn't.
- **`transport.test.mjs`'s native-bridge contract check** pointed at the now-
  retired `native/android/KioskBridge.kt`; repointed at the real module path,
  and its "every native file marked UNVERIFIED" assertion split in two —
  Windows must still say so (genuinely untouched), Android must now say it
  does **not** (genuinely built, wired, and manually verified on a real
  device this session).

### Verified
- `lock.test.mjs`: 47 passed, 0 failed (new).
- `transport.test.mjs`: 58 passed, 0 failed (3 new J-bridge assertions).
- Dart: `flutter analyze` clean; `flutter test`: 76 passed, 0 failed (was 54).
- Manually built and installed on the same physical Android device used for
  the previous session's screenshot audit: `startLockTask()` pins the app for
  real, Home/Recents is suppressed, exiting lands on the PIN gate rather than
  any guardian surface, the demo PIN recovers it, five wrong attempts cool
  down, break-glass recovers without granting escalation.

### Out of scope, on purpose
- **Windows Assigned Access** (`native/windows/AssignedAccessBridge.cs`) — no
  `windows/` Flutter platform target is scaffolded yet; left as the
  contract-only stub it already was.
- **iOS Guided Access** — MASTERFILE §8.3's own table marks this **Ph.4**,
  deliberately future work, not a gap to close now.
- **Real backend PIN verification** — `auth.ts`'s `verifyPin` is designed to
  run behind a live API against a server-held, RLS-protected
  `pin_credential` table; no backend is deployed for this client to call yet.
  `KioskShell` takes an injected `verifyPin` callback; the demo build supplies
  a fixed code rather than pretending to reach a server that isn't there —
  same posture as §8.5.0's `guardianSetup` stub.
- **Guardian escalation** (`escalate()`, PIN + biometric →
  `guardian_escalation`) is ported to `lock_controller.dart` and unit-tested,
  but not wired to any UI: there is no "guardian settings reachable from the
  child's device" screen anywhere in this app yet to escalate into. Wiring it
  to nothing would be exactly the declaration-without-implementation failure
  mode standing rule 4 warns against.

---

## [0.42.0] — 2026-08-03 — the sync/async pairing pattern, formalised

Requested: make sure every activity has a synchronous and asynchronous form
where one makes sense, accounting for the family's time difference, and
complementing the system that keeps the voice alive when video degrades
(clarified as the quality ladder, §5.28, not the come-back signal — a naming
mix-up worth recording since both are now cross-referenced from the same new
section).

### Added
- **§8.15 — the sync/async pairing pattern**, naming and tabulating a
  philosophy that already existed piecemeal: the quality ladder (§5.28) never
  fails outright, a live game degrades to turn-based play rather than
  vanishing, and turn clocks already tick in reachable hours, not wall hours
  (§4.7). This section is the one place a future addition gets checked
  against: does this activity need both forms, and do both already exist?
  Includes the full pairing table across the call, games, homework, reading,
  drawing, the come-back signal, and showcase asks.
- **§5.27.9 — reachable-hours deferral for the come-back signal.** A
  non-safety-critical signal blocked by silent hours or a blocked window is
  now deferred to the next reachable window (capped at one, staleness at one
  hour) instead of silently dropped — closing a real gap, since §5.27.6
  already (correctly) shows the sender nothing, which made a dropped signal
  indistinguishable from one that arrived and was ignored.
- **§9.12.4 amendment — a live pairing for the doodle desk.** Reuses the
  existing shared annotation canvas (`annotation/canvas.ts`) rather than
  building new logic — its per-actor undo scoping already solves the one hard
  problem a live shared doodle would otherwise reintroduce.
- **§9.10 amendment — reachable-hours-aware showcase asks.** `askForShow()`'s
  three-slot FIFO ceiling is unchanged; `askAgeInReachableHours()` is
  additive, letting a caller weight an ask's age by the asker's actual
  reachable hours instead of wall-clock time, mirroring §4.7.
- **`exchange.ts` gained test coverage for the first time** — `askForShow`,
  `answerAsk`, and `MAX_PENDING_ASKS` had zero prior assertions; 8 new
  assertions close that gap alongside the 4 for the new reachable-hours
  function.

### Verified
- `signal.test.mjs`: 122 passed, 0 failed (11 new).
- `activities.test.mjs`: 131 passed, 0 failed (3 new).
- `showcase.test.mjs`: 72 passed, 0 failed (12 new, 8 of which close a
  pre-existing coverage gap unrelated to this increment).

## [0.41.0] — 2026-08-03 — the entry gate

Raised as a request to make onboarding "all-inclusive," specifically: one
shared onboarding modal that reads a typed age and routes the device to
either the child kiosk or the full guardian app (proposed cutoffs: under 10 →
child, 23+ → guardian). **Evaluated and rejected in that exact form** before
any doc was touched, per the project's own standing practice of not sketching
an unsettled design into inertia. Rebuilt into something that keeps the
underlying goal — one unified, less-friction onboarding — without the
security regression.

### Added
- **§8.5.0 — the entry gate.** A role question ("my child's device" / "the
  grown-up's device"), not an age gate. `chooseEntry()`, `suggestEntryRole()`,
  `routeFromEntry()`, and the named invariant `ENTRY_CHOICE_GRANTS_NO_AUTHORITY`
  in `onboarding.ts`. Choosing "grown-up" routes to real account setup
  (passkey/WebAuthn, §11) and grants nothing by itself — every guardian
  capability is still gated by `family-graph/authorize.ts`'s `can()`, reading
  real edges, exactly as before. **Proved, not just asserted**: the test suite
  calls the real authorizer with a guardian-role tap and zero edges and
  confirms it's denied (`no_edge`) — a genuine cross-package integration test,
  not a same-file assertion.
- Demo: two new screens, `welcome` (the role choice) and `guardianSetup` (an
  honest stub for the real account flow, documented as not-yet-built the same
  way the native kiosk bridges are, rather than faked).

### Rejected
- **Age-gated single onboarding**, in the form originally proposed. Would have
  let anyone holding the device grant themselves full guardian authority by
  typing a number ≥23 — no verification, no consent, no edge. Would also have
  quietly narrowed §21's continuous 2–17 maturation ladder down to "child mode
  ends at 10," which §21 does not say and this proposal was not trying to
  change. Not recorded in §19 (no lasting shape to preserve) — the reasoning
  lives in §8.5.0 directly since that's where anyone extending onboarding will
  actually look.

### Clarified
- **The child side is not a one-way "transmitter → receiver."** She already
  sends homework photos, drawings, showcase items, and letters to the
  guardian side (§9.1, §9.10, §9.12.4, §9). Named explicitly in §8.5.0 so this
  framing doesn't quietly become the mental model for future work.

## [0.40.0] — 2026-08-01 — two open decisions resolved

### Settled
- **§16.2 #6 — self-host vs. LiveKit Cloud.** Stay on Cloud. Revisits only at a
  concrete trigger, not "when residency demands" left undefined forever: 500
  concurrently active families, or any institutional/court-mandated deployment
  explicitly requiring residency guarantees a managed cloud can't make. The
  real cost of staying on Cloud is COPPA sub-processor disclosure (§10.1) for
  LiveKit as a third-party recipient of a minor's live video — solvable with a
  DPA, not infrastructure. Recorded in §11 alongside the tech-stack table.

### Rejected
- **§16.2 #8 — curriculum-standard tagging, declined outright, not deferred.**
  `school.ts` (§11.5) had already settled the closely related SIS/gradebook
  question, for a reason that applies here too: a gradebook-style signal would
  put a child's academic standing in front of a parent she didn't choose to
  tell, inverting §9.1's "homework help is something she brings." Neither
  Common Core (state holdouts) nor fifty-state tagging (fifty taxonomies) was
  chosen — the feature itself is declined. The hint engine's value is that it
  works on any problem without knowing what grade or standard it belongs to.
  Recorded in §19 as considered-and-declined, same pattern as §16.2 #12.

§16.2 is down to six open items, none of them blocking near-term build work.

### Fixed
- **§11.5 written — closing a phantom reference.** `school.ts` had cited
  "MASTERFILE §11.5" in its own header comment since v0.3.0, but that section
  was never actually written here — a small declaration-without-implementation
  gap, caught only because settling §16.2 #8 required leaning on it directly.
  Now a real section: no SIS/gradebook integration, and the three reasons why,
  matching what the code already documented.

## [0.39.1] — 2026-08-01 — §5.27 renumbered

### Fixed
- **§5.27 was double-booked** — the MASTERFILE heading assigned it to both "The
  come-back signal" and "Stream stability · the capability budget," a defect
  flagged in 0.39.0's own changelog entry but not yet corrected. Every prose
  reference to "§5.27" elsewhere in the document (P11, §16.2 #12) means the
  come-back signal, so that section keeps the number; **stream stability moves
  to §5.28**, along with its four internal subsections (§5.27.1–4 → §5.28.1–4)
  and the matching comments in `stream.ts`. No behavior changes — this is a
  numbering fix only, verified by rerunning the pane and budget suites
  unchanged at 83 and 87 passed.
- **VISUAL.html refreshed** — stuck at v0.2.0 while the rest of the canonical
  set moved to v0.39.x. Panels 01–04 (system map, delivery engine, time
  resolution, data model) remain architecture-level and substantially accurate
  as written; panel 05 (Phases) was the stale one and is rewritten honestly —
  Phases 0–3 marked complete, Phase 4 marked in progress with iOS and the
  native kiosk bridges called out explicitly as not yet built rather than
  glossed over. Not a full redraw: MARKUP.html remains the source of
  screen-by-screen truth, generated from the same manifest that gates every
  release, and VISUAL now says so.

## [0.39.0] — 2026-08-01 — four additions evaluated against a Gemini-drafted alternate build

Chris built an alternate version of this product with Gemini, prompted from our
own predecessor files, and asked for the good parts to be integrated. Most of
what it proposed was already shipped under different names (TTS is §8.8b's
baseline `spoken` form; oversized touch targets are §8.4's 48dp floor; the
shuffled PIN pad is §8.3; three of its "co-op games" are already three of the
ten live games). Four items were genuinely additive. One ("send a hug") was
raised, evaluated, and rejected outright at the owner's direction — see
`[Unreleased] → Rejected` above, §16.2 #12.

### Added
- **§8.8.5 — read-aloud for pre-readers.** A 🔊 control that speaks whatever a
  screen reader would already announce (`speakableText()` sources §8.8.4's
  `LABELS` directly, so the two strings cannot drift apart), on-device only
  (mirrors §8.8.1's caption posture), default-on below age 8, never autonomous —
  the audio equivalent of §8.13's motion ban. Ephemeral; not the caption
  pipeline, nothing here is retained or logged.
- **§8.13.8 — the touch chime.** Web Audio confirmation sounds, but treated as
  consequence motion wearing sound rather than a fifth motion category — it
  inherits every existing §8.13 rule wholesale. Silent on every `still` surface
  (bedtime, homework, journal, emergency card), never autonomous, never loops,
  composes with a one-tap mute setting independent of reduced-motion.
- **§9.12.4 — the doodle desk.** Free strokes plus six stamps (heart, star,
  smiley, rainbow, sun, moon) alongside — not replacing — the existing
  tap-to-fill colouring engine. Same unlimited-undo pattern as everywhere else
  in §9.2; no score, timer, or completion state, because a blank canvas has no
  finish line for one to mean anything against.
- **§8.2.2 amendment — day-part icons.** A static sun/moon/dusk glyph per
  segment of the Day Ribbon, declared in the same table as the friendly label
  (`phase3.ts`) rather than a second lookup, so the two cannot drift apart.
  Static, never pulsing — §8.13's autonomous-motion ban has no icon exception.
- **§9.15 — the capture button**, raised separately at the owner's suggestion
  once the Gemini review was underway. A dedicated in-app photo/screenshot
  control that auto-uploads to the app's own storage and never touches the
  device's shared camera roll. Camera capture reuses §9.1's quality gate
  wholesale; screenshot capture is scoped off the call surface entirely
  (`live_call`, `call_video`, `pane_video`), so a parent's face can never be
  captured mid-call without him knowing.

### Fixed
- **A quadruple-backslash escaping bug** in the doodle screen's engine-room
  copy (`build\\\\'s` instead of `build\'s`) broke the demo's bundled JS at
  runtime. Invisible to `npm run build` (which only compiles the TypeScript
  engines, not the shell's inline strings) and caught only by
  `drive.test.mjs` throwing a `SyntaxError` on load — recorded because it is a
  category of bug the build step cannot see by construction.
- **A duplicated read-aloud import** across two locations in `demo/src/play.ts`
  (one from wiring it into the activities section, one from the "nine
  modules E2 named" block) would have been a duplicate-identifier build
  failure. Removed the redundant one; the freed slot became the capture
  module's import, which is also what satisfies E2 for it.
- **A naming collision**: the new capture-button demo screen was first named
  `capture`, colliding with a pre-existing MARKUP screen slug already named
  `capture` (mapped to the message-banking screen). Renamed the new screen to
  `snapshot` throughout — the demo screen function, its P_engine explainer, the
  nav index entry, and both dispatcher targets — before the collision could
  silently misroute either screen.
- **An accidental deletion of the `data-obcol` onboarding-colour handler**,
  caught mid-edit when a `str_replace` anchor included it in the region being
  replaced. Restored before it shipped as a silent regression.

## [0.38.0] — 2026-08-01 — the fourth canonical document, actually canonical

### Fixed
- **Homework OCR fixtures now exist as code.** The K-series OCR probes shelled
  out to `/tmp/hw_clean.png`, `hw_blur.png`, `hw_skew.png` — images generated
  ad-hoc in one session and never committed. On any fresh environment the clean
  probe failed and, worse, the blur and skew probes passed **vacuously**: a
  missing file OCRs to nothing, and nothing satisfies "recovers nothing." A
  fixture that does not exist proves nothing. `packages/homework/test/`
  `make-fixtures.sh` is now the committed, deterministic generator; the suite
  regenerates all three images every run and asserts they exist before OCR.
  +1 assertion (30 → 31 in the homework suite).
- **The transport suite ran zero assertions when verify was invoked from the
  wrong directory level.** The repo root is `scaffold/`; the canonical documents
  live one level above it, and `transport.test.mjs` resolves `MASTERFILE.md`
  through that parent. Not a code change — recorded so the layout is never
  "corrected" flat again.
- **Duplicate version number.** 0.36.0 was cut twice (the come-back signal, then
  motion). The motion entry is renumbered **0.36.1** in place. Screens citing it
  in MARKUP cite 0.36.1.

### Added
- **MARKUP.html reconstructed — and the gap that required it, recorded.** The
  standing rule declares four canonical documents. An audit of the Drive folder
  "THROUGHLINE — Canonical" found MASTERFILE, CHANGELOG and VISUAL present and
  **MARKUP never uploaded at all**: the fourth canonical document existed only
  in an ephemeral container and died with it. A declaration is not an
  implementation — this time the declaration was ours, about our own process.
  MARKUP.html is rebuilt at this version from the two places its structure
  provably survived: the demo manifest (D3 forces an exact mirror of the screen
  list — all 68 slugs recovered) and this changelog (per-screen `data-since`
  attributions are derived from the entries that shipped each surface, and are
  marked best-effort where the record is coarse). C1–C7 enforce it from here.

### Known
- **§5.27 is double-booked**: the MASTERFILE heading assigns it to the come-back
  signal, while `live/stream.ts` claims it for stream stability. Recorded, not
  silently renumbered — resolving it amends the MASTERFILE and the module
  headers together in a future increment.
- **VISUAL.html lags at the 0.3.0 era.** The Drive copy predates the visual-era
  rebuild and there is no newer local copy. Restored locally from Drive so the
  file exists; a catch-up pass to current is queued as its own increment rather
  than half-done here.

## [0.37.0] — 2026-07-27 — stream stability and the capability budget

**2,327 assertions, all green. 44 correspondence checks.** Both, in that order —
because once the call knows how to degrade internally, the budget only has to
decide **how much to give it** rather than **what it does with less**.

### The stream ladder sits under the rung ladder
Three video qualities before the picture goes at all, with **hysteresis**: two
seconds to shed, twelve to restore.

> A picture that keeps appearing and vanishing is worse than no picture. She looks
> up expecting her father and gets a grey rectangle — and she will stop looking up.

A connection good for three seconds is not a good connection. One step per
evaluation, never two, so a collapse walks down and each step is a chance to
stabilise. **No connection meter** — a five-year-old watching a signal indicator
is a five-year-old not watching her father. Video returning does **not** ask
permission; that rule is for a reconnect, not a picture inside a call that never
stopped.

### The budget closes the real gap
The device matrix declared three tiers and **exactly one thing consumed them.**
Games, colouring, the gallery, the storyteller and the pane each assumed
independently what the hardware could do.

Fifteen costed features, three capacities, and a resolution order: ambient motion,
then video quality *by substitution*, then the pane to a still frame, then
concurrent activity, then video entirely. **The voice is never a candidate** —
`NEVER_SHED` holds it and the loop refuses to consider it, which is stronger than
sorting it last.

Five previously-unmodelled combinatorial cases now resolve, and
`audioAlwaysSurvives()` asserts the voice survives all of them on every tier.

### Binding, and honest about the cost
`admit()` refuses what does not fit. It also now **discloses substitutions** — a
first version returned a bare `{ ok: true }` when a feature fitted only because
the video had been dropped to 360 to make room. **Admitting without disclosing the
cost is a quieter version of the advisory budget this module exists to avoid.**

### Ceilings with reasons, not numbers
Group call at four, because beyond that the solo rotation outlasts a child's
patience. Story library at 300, because past that a shelf becomes a search
problem, which a five-year-old cannot use.

### H1–H5
Every expensive feature declares a cost · the voice outranks everything · ceilings
exist where needed · **no ceiling is a bare magic number** · the quality ladder is
asymmetric. H1 and H5 shown to fail when their guard was removed.

### Fixed
- One expectation of mine again: I assumed adding find-the-thing to a loaded low
  tier would require a *drop*. It resolved by substitution alone — which was the
  budget working correctly, and which is what exposed the missing disclosure in
  `admit()`.

---

## [0.36.0] — 2026-07-27 — the come-back signal, and P11

**2,156 assertions, all green. 39 correspondence checks.** Sixteen applications,
four family configurations, a nineteen-form accessibility matrix, and a new
prohibition.

### He requests. She acts.
No data flows back, no control channel exists, and the child performs every action
herself. That one constraint is what lets this expand to sixteen applications
safely — each inherits the same safety rather than needing its own argument.

### P11 — no remote control of a child's device, including for the child's benefit
The wording matters. **"Including for the child's benefit"** is deliberate: the
benign framing is exactly how a remote-control channel gets reintroduced in two
years, by someone with a good reason.

### Three decisions settled
- **No third adults.** Only a parent may send. A grandparent or stepparent in the
  room can simply speak; widening it makes the signal a household broadcast.
- **The ignored signal is invisible.** No count, no badge, no "she hasn't
  responded". If he needs to know she is alright, that is a phone call to the other
  adult — **not an inference drawn from a child's non-tap.**
- **Two independent channels, always.** The baseline set alone covers sight and
  hearing before any option is enabled.

### Priority, and the line I would not cross
Safety first, then **absence beats presence** — the parent she is with can simply
talk to her. Then in-call, then simply first.

> No seniority, no primary/secondary, no custody weighting. **Under no
> circumstances does the order of a court order become the order of a prompt on a
> child's screen.**

The loser is never told they lost. That is a competition she would be the prize in.

### The family never shows through
One parent or two, restricted or not — identical behaviour. **Both parents in the
same house: the whole mechanic stands down**, because a signal from the next room
is absurd and a product looking absurd there is how a family stops trusting it.

### The entry gate
A prompt that always appears in the same place **will** be tapped by accident. An
application whose action is not harmless under that condition cannot use this
pattern — refused at construction, not noticed in review.

### The rules
One at a time (a queue is a demand list) · 90-second silent expiry · **a hard daily
ceiling of 12 independent of the age bands**, because 16 applications × 2 parents
could satisfy every individual rule and still deliver forty · silent hours 20:00–07:00
· mid-transition signals **dropped, not queued** · **she can mute everything for an
hour with nobody told** · and **signals are never preserved** — they are gestures,
and minuting gestures changes what people send.

### The accessibility matrix
Nineteen forms across four readiness states, built to be **extended and rolled out
incrementally**. Promoting a form to `shipped` with an unmet requirement is
**refused**; readiness only moves forward. The matrix is data, so a form can be
added without touching a single consumer.

Currently 9 shipped, 3 scaffolded, 4 specified, 3 considered — including signed
video, which for a deaf child is the difference between reading and being spoken
to, and which sixteen applications is a small enough vocabulary to record by hand.

### The G-series
Seven checks: every application declares an interruptibility, a safe-if-mistapped
verdict and an audience; none ships unsafe; the baseline a11y set covers two
channels; no shipped form carries an unmet requirement. **Sixteen applications is
precisely the count at which one quietly ships without them.**

G3, G4 and G6 were each shown to fail when their guard was removed.

---

## [0.36.1] — 2026-07-27 — motion

**2,240 assertions, all green.** The demo now has **real gestures** — a swipeable
rail with momentum and rubber-band, a scrobbler, and a rotary dial. Before this it
had two CSS transitions and **zero touch handlers**.

### The principle
> **Motion follows the finger. It never leads it.**

Every animation is either driven 1:1 by her gesture or a consequence of something
she just did. **Nothing moves on its own to attract her.** That single rule is the
difference between an interface that feels alive and a slot machine — which is what
children's software usually becomes, and it becomes it through motion.

`admitMotion()` refuses `autonomous` outright, at any duration, on any surface.
Ambient motion is allowed only on four surfaces where **the movement is the
information** — a waveform meaning *he is talking*, a recording dot. Everywhere
else it is decoration competing for her attention.

### One vocabulary, learned once
Ten gestures, each meaning exactly one thing everywhere. Horizontal swipe always
means siblings; time is horizontal across the whole product. Scrobble is how a
child says *"go back a bit"*. A dial rather than a slider, because **a dial has a
centre to orbit and a slider has a line to stay on** — a small hand wanders off a
line.

**`TAP_ALWAYS_SUFFICES`.** No gesture is ever the only way to reach anything.

### Wordless instruction
A pre-reader cannot be told to swipe, so a swipeable row shows a **22 px peek** of
the next item. It is the most effective wordless instruction available and costs a
few pixels. Touching a draggable thing moves it within 40 ms, before a drag has
registered — that tiny response is what tells her it is hers to move.

### Physics
Spring, not linear: children read a spring as a real object and a linear ease as a
slide show. **No spring may overshoot more than 6%**, because a bigger bounce reads
as a reward. Rubber-band at the edges, because that is how a child learns there is
nothing more — a wall reads as broken.

### Where motion is a bad idea — the caveat, honoured
Bedtime, homework, the journal and the emergency card are **still**. The come-back
signal, story reading and wind-down are **reduced**. Each declares why.

**"Still" means a crossfade, not a cut** — a hard cut is disorienting in its own
way. And reduced motion composes: the quieter of surface and setting always wins,
so an accessibility preference is never overridden by a default.

### The budget
Two moving things at once. Nothing auto-plays. And:

> **Celebration once is delight. Every time is a reward schedule.**

`celebrate()` returns `play: false` from the second occurrence.
`auditMotion()` refuses `attractLoop`, `pulseToTap`, `jackpot`, `combo`,
`streakAnimation` and `confettiEvery`.

### The demo actually moves now
Six touch handlers where there were none. The rail uses the real `rubberBand()`
and `flingDistance()` from the module rather than reimplementing them, so what you
drag is the shipped physics.

---

## [0.35.0] — 2026-07-27 — the pane

**2,045 assertions, all green.** All ten pane recommendations, in
`packages/live/src/pane.ts`.

### The core move: do not use the OS at all
Android Go disables platform PiP outright. FireOS reports Android 9 and may still
refuse it. And **screen pinning blocks the PiP API by design** — the kiosk that
keeps a child in the app is the same mechanism that forbids the feature.

So the pane is a positioned view inside our own hierarchy. No platform API, no
firmware dependency, no permission, no kiosk conflict. **It renders identically on
a £50 Fire tablet and a Fold, because it is a box we draw.**

### She cannot close it
`closePane(p, 'child')` returns `child_cannot_close`, and `childControls().close`
is a literal `false`.

> A child who accidentally loses her father's face and cannot work out how to get
> it back has lost the call — and she will not say so, she will just go quiet.

Only ending the call ends the pane. Her view is audited for any close, dismiss,
hide or remove affordance.

### Audio is decoupled entirely
**If the pane fails, is occluded, or the renderer dies, the voice never drops.**
The video is the enhancement; the voice is the call. On this hardware a renderer
falling over is a Tuesday.

### Docked, not floating
Four magnetic corners. A five-year-old dragging a small target loses it behind her
own thumb — and a corner is **position without coordinates**, so it survives
rotation, folding and a text-scale change with no arithmetic.

### The floor is relative
A fixed 96 px is a postage stamp on a 10-inch tablet and a screen-filler on a
344 px cover display. The pane is a fraction of the **shorter** viewport
dimension with an 88 px absolute floor — on the cover screen `large` covers 7.6%,
not the 30%+ a width-based calculation would have given.

### The pane yields; she never has to
It relocates to the corner furthest from **every** hot zone, not merely the
nearest, and snaps home once her hands move away.

### The probe attempts and verifies
`SDK_INT >= 26` is a lie on FireOS. The probe tries, confirms the mode was
actually entered, and falls back silently — **only the observation counts**.
`OS_PIP_IS_NEVER_LOAD_BEARING`, and every path through `effectivePane()` returns
either an OS window or the in-app pane on any hardware/firmware combination.

### Also
Low tier plus a running activity degrades to a **still frame that says nothing
about itself** — a frame announcing itself is an apology. Homework capture and
Fold tabletop refuse the pane outright, each with a reason.

### Fixed
- One of my own expectations again: I asserted `large` would not fit a 344×882
  cover screen. It fits at **7.6%** — precisely because the fraction comes from
  the short edge, which is the relative floor doing its job. Replaced with an
  assertion that tests the property, plus a squat 900×360 viewport where the
  coverage ceiling actually bites.

---

## [0.34.0] — 2026-07-27 — the call, properly

**1,962 assertions, all green.** All thirty-four recommendations, plus a new
permanent prohibition.

### Audio-only is a choice, not a punishment
**He is told the call is voice-only. He is never told why.** "She chose not to be
seen" is a fact a parent will overinterpret, and the overinterpretation lands on
her. The voice-only answer button is the **same size** as the video one, because a
smaller one is a judgement and she will read it as one.

Never a black rectangle — her colour, a 4 Hz waveform (a fast one is a stimulant
at bedtime), or the canvas. Bedtime mode dims to 8% with no video. Push-to-talk is
a walkie-talkie, which a five-year-old already understands.

### A frozen father and an ended call are the same event to a five-year-old
And they are not the same thing. *"The picture stopped. He is still there."* is a
different sentence from *"That is the end of the call."*

Eleven phrases banned from a child's screen including **"failed"**, **"poor
connection"** and **"check your network"** — she cannot check her network and
should not be asked to. The ladder is HD → SD → audio → banked: the call falls
*down* it rather than off it.

Reconnection preserves the game, the story position and the half-coloured picture.
**Resuming asks first** — a call that reconnects itself and starts transmitting a
child's bedroom because the wifi came back is a privacy failure with good
intentions.

### The rear camera turns mirroring off
"Show me" during a call is turning the phone around — the showcase happening live,
and probably the highest-value item in the set. **Flipping to the rear disables
mirroring**, because a mirrored rear camera renders every word she holds up
backwards. One line, and the homework case works.

Torch is rear-only. Lighting advice is about the room, never about her.

### P10 — no appearance modification on a child's video
**New permanent prohibition.** No beauty filters, no smoothing, no slimming, no
eye enlargement, no "touch-up" — not as a default, not as an option, not as a
sticker that happens to reshape a face.

> It teaches a five-year-old that the version of her face the software prefers is
> better than the one her father sees, during the one activity in this product
> that exists so he can see her.

Costs nothing today, expensive to remove later once somebody likes it. **Dog ears
are fine.**

**Virtual backgrounds settled:** guardian yes, child no. A child's background is
the only thing in a call that tells the other parent she is somewhere ordinary,
and it arrives without anybody deciding to send it.

### PiP conflicts with the lock
PiP exists so a call survives you leaving the app. A child in kiosk mode **cannot
leave the app**. So on her device it solves a problem she does not have, and
building it would mean a hole in the lock.

**PiP is guardian-only** — a structural conclusion, not a limitation. And what the
product has been calling "picture in picture" in game layouts is a *layout*: a
weaker claim than the name was borrowing.

### The Fold, mid-call
`HINGE_NEVER_ENDS_CALL`. Folding, unfolding and standing it up are things she does
*while* talking, and every one of them tore the call down until now. Half-open is
the only posture that announces itself: *"You can put it down now — he can still
see you."* Detected from the viewport, so no vendor hinge API is required.

This also finally implements `TABLETOP_KEEPS_CALL_ALIVE`, which had exactly one
reference — its own declaration — for two increments.

### Knocking, not ringing
A knock waits 90 seconds, never escalates, and becomes a banked message. He is
told *"she did not come to it"*, never that she declined. **`decline` is banned
from the answer surface**; "Not now" is a real answer.

### Both-free windows, finally used
The ribbon has computed the overlap since v0.2.0 and never offered to start a call
with it. It does now — **to the guardian only**. A prompt telling a five-year-old
that now would be a good time to call her father makes his availability her
responsibility.

### Also
Speaker by default for a child; a hearing ceiling she cannot raise; headphones
mentioned neutrally and never characterised as privacy; echo warning for siblings
in one room, which the group call makes certain rather than possible.

---

## [0.33.0] — 2026-07-27 — ten from the audit, and three of them were mine

**1,828 assertions, all green. 33 correspondence checks.** The audit ran first, and
the first three items it produced were things I declared last increment and never
built.

### What the audit found before anything was written
1. **`court_export_request`** — a `degradesTo` target the layout audit demanded by
   name. Implemented in **zero** modules. It existed as a string.
2. **`fold_tabletop`** — a declared posture with no layout anywhere. Zero
   references in the demo.
3. **The FireOS fallback.** The device matrix declared
   `foreground_socket_and_sms`. The transport still had
   `Platform = 'android' | 'ios'` and **no fallback path at all** — the matrix
   described a mechanism that did not exist.

> A declaration with nothing behind it is **worse than an omission**. An omission
> is visible; a documented assurance reads as done, and every check passed because
> they verified the declaration was well-formed rather than that anything answered
> it.

### The ten
1. **The delivery fallback, built.** Push → held socket → text to the adult after
   90 minutes. Every rejected route is recorded with its reason.
2. **The sender is told the truth.** The original defect was never that FCM was
   missing — it was that *both people were misled and neither could discover it*.
   A fallback that fails quietly reproduces that with more machinery, so an
   unreachable child is reported as unreachable, with the one thing he can do.
3. **The adult text names nobody and says nothing** — the other parent may be in
   the room. Same reasoning as §10.4, unchanged.
4. **The tabletop layout.** The crease is **horizontal** in this posture, so the
   split is top/bottom and nothing interactive may sit above the hinge — it is
   angled away from her hands. Putting the phone down does not end the call.
5. **Landscape arrangements** for seven postures. Rotation preserves state,
   because a child who loses a half-coloured picture by turning the tablet over
   does not try again.
6. **The degraded export.** Requesting works at 344 px; reviewing needs 600. The
   confirmation does not pretend otherwise — *"it needs a bigger screen to check
   through."*
7. **The no-install web path.** Joining a call and replying are the **minimum
   viable relationship**, and gating either behind an app store is how a reluctant
   second parent quietly never joins.
8. **The sibling group call.** The mechanic is that **the youngest goes first** —
   by the time a thirteen-year-old has been on for ten minutes, a five-year-old
   has left the room. A waiting sibling is told to go and do something, never
   shown a queue position.
9. **The therapist's view**, built to the settled ladder-only scope, with what is
   *not* visible named on the surface rather than buried.
10. **"Call me when you can", at the limit.** §9.9's refusal was silent so she is
    never told off — but silence is only right if she has another way to say it.
    At the limit the tap **banks** instead, and **the line she sees is identical
    either way**. A child who can tell she hit a limit has been told off by a
    counter. The guardian is told the truth, because he needs it to respond well.

### The F-series
Four new checks for exactly the class of error I made:
- **F1** every `degradesTo` target resolves to an implementation
- **F2** every landscape-capable posture has a landscape arrangement
- **F3** every declared fallback has a matching route in the `Route` union
- **F4** no module is constants-only while claiming behaviour

F2 and F3 were both shown to fail when their guard was removed.

### Fixed
- **My first F2 counted occurrences** and flagged `fold_cover` and `phone`, which
  are portrait-only and correctly have no landscape arrangement. **A check that
  cries wolf gets switched off by the next person, which is worse than no check** —
  rewritten to test the property rather than a proxy for it.
- **My first F3 scanned all source** and reported `no route for: you`, having
  matched `fallback: 'you'` in onboarding — the guardian-entered *name* fallback,
  an unrelated field sharing a word. Cross-module regex checks are fragile in
  exactly this way; scoped to the one capability table.

---

## [0.32.0] — 2026-07-27 — the device matrix, and a silent-device defect

**1,717 assertions, all green.** The audit came first this time, per the rule
added last increment — and it found two things before a line was written.

### Audit findings, before building
1. **Two junk directories** — `packages/{a11y,offline,...}` and
   `packages/{auth,storage,api}`, brace expansions that never expanded, left on
   disk by an earlier `mkdir`. Empty, removed. 38 real packages.
2. **`Platform = 'android' | 'ios'`.** No desktop, and nothing anywhere in the
   codebase mentioned FireOS, Play Services, or their absence.

### The silent device
**A great many separated families hand a child a £50 Amazon Fire tablet.** FireOS
has no Play Services, therefore no FCM — and with the transport as it stood, a
notification would be constructed, dispatched, and silently discarded.

> **She never learns he wrote. He never learns she was not told.**

No error, no bounce, no way for either of them to discover it. It is the one
failure mode where both people are misled at once, and it was one type union away.

Six channels are now declared; three cannot push. Each declares a fallback, and
**a channel that can neither push nor fall back is refused rather than warned
about.** The guardian-facing copy blames neither the device nor the parent.

### The half-open Fold
Half-open, the Fold stands by itself with the camera at eye level. **It is the
only hands-free call posture the hardware offers** — the difference between a
child holding a phone for eleven minutes and playing on the floor while her father
watches. Now a declared posture, landscape-only, video above the crease.

### Tablets live in landscape
The opposite of phones, and the assumption most layouts get wrong. A portrait-only
surface now **fails the audit** on any landscape-only posture.

### Nine postures, 344 px floor
Fold closed, Fold open, Fold half-open, phone, three tablet sizes, PC, DeX. The
floor applies to **guardian surfaces too** — a parent checks this app on a phone
far more often than at a desk, so a 600 px guardian inbox is broken exactly as a
child surface would be.

Columns come from the **effective** width (viewport ÷ text scale), so a 10-inch
tablet at 2.0× type gets one column like a phone.

### Input is per posture, not per platform
**DeX breaks the assumption that platform implies input** — it is a phone with a
mouse. Child-facing targets never relax below 64 dp even with a mouse, because a
child using a mouse is still a child. An S Pen improves two things and gates none.

### Lock-down differs everywhere
**iOS Guided Access cannot be enabled remotely or programmatically** — a parent
must switch it on by hand, and the product must say so rather than implying a lock
it cannot deliver. There is no kiosk in a browser tab, so the **web client is
guardian-only**.

### Performance
Three tiers. A 2 GB tablet gets 180p at 15 fps — **a call is degraded, never
refused**, because a recognisable face is the whole requirement and a call that
connects beats one that looks good.

### Honest exceptions
`auditLayouts()` accepts that a certified court export is not a 344 px surface —
but only if it declares `degradesTo` **and that degraded form is implemented**.
Declaring an intention is not enough. The real case: producing an export in a
solicitor's waiting room, on a phone.

### Fixed
- Two of my own expectations again: a PC at 2.0× type drops to **one** column
  (640 px effective), not two — and a 600 px *guardian* surface really is broken
  on a folded Fold, so the unrealistic thing was my claim, not the audit.

---

## [0.31.0] — 2026-07-27 — §21 built, in its own order

**1631 assertions across 35 suites.** Ten items, following the sequencing §21.10
wrote for itself in v0.21.0. Seven new MARKUP screens, eight new demo screens.

### 1. The grant record
Append-only. There is `recordGrants()` and **there is no `revoke()`** — the
absence is the mechanism, the same construction as P7 and P8. Jumping the age
forward backfills every rung passed at once.

**§21.9 A, settled: ages move later only, and only by both guardians.** Later is
kind to an unusually vulnerable child; earlier, or unilateral, is the obvious lever
for a controlling parent. `adjustRung()` refuses both — including a legitimate
direction requested by one parent alone.

**§21.9 B, settled: only rungs that change what a parent can SEE notify them** —
15 and 18. A notification saying "your daughter's journal is now permanently
private" tells a parent something about her that the rung exists to stop them
knowing.

**§21.9 C, settled:** the guardian is told **once, warmly**, then never again. A
permanent banner would be a daily reminder that she once did not control her own
time.

### 2. The quieting
Seven scaffolds with fade ages. At five she sees all seven; at seventeen, none.

**The asymmetry is the whole thing.** The send-time guard fades on her side at
fourteen and **never fades on his**. A parent messaging a sleeping child at 2am is
a different act from a teenager messaging a parent at 2am — *the guard exists to
protect her sleep, not to teach her manners.*

### 3. Letters to her future self
Sealed at nine, opened at eighteen. `preserved` is a literal `true`.

**Nobody can open it early, including her.** That second half is the interesting
one: a sealed letter she can peek at is not sealed, and the value is that
nine-year-old-her gets to say something eighteen-year-old-her cannot pre-edit. She
*can* delete it, because it is hers — **delete-without-read** is an unusual
permission and the correct one. A guardian can do neither and knows only that it
exists.

### 4. Reverse banking — she banks for him
The delivery engine needed no change; only the direction differs. What needed care
was the framing: *"you have not recorded anything for Dad's deployment"* turns a
gift into homework, **and a child who feels she owes her father a video will send a
worse one.** No target, no reminder, no count, no empty state implying she should
have done more.

### 5. Rung 15 — the inversion
She publishes; the ribbon shows what she set. The inference does not disappear — it
becomes the **fallback for hours she has not spoken about**, which is the right
relationship between a system's guess and a person's answer, and the source is
always stated so a parent knows which he is reading.

The copy never editorialises. *"She has said she is busy"* is a fact; *"she does
not want to talk"* is an interpretation and not the product's to make.

### 6–7. Rungs 16 and 17
Curation: she can hide, era-tag and retitle from sixteen, and **a guardian can do
none of it in either direction** — a curation a parent can reverse is a suggestion.
Hiding is deliberately not deleting: a sixteen-year-old embarrassed by something at
fourteen may want it back at twenty-five.

Export at seventeen: `requiresGuardianApproval` is a literal `false`, because a
grant a guardian can withhold is not a grant. No principal's export ever contains a
guardian's journal — her right to her own record is not a right to theirs.

### 8. Rung 18 — the hardest button
**`COOLING_OFF_HOURS = 0`, and there is no `executeAfter` field to set.** A delay
is a soft refusal dressed as care; every product that ever added one added it to
reduce the number of people who went through with it.

The confirmation lists what goes and what stays, then does it. Fifteen banned
strings keep it honest — no "are you sure", no "before you go", no "just deactivate
instead". *Using those on an eighteen-year-old asking for her childhood back would
be contemptible.*

What is not hers: the parent-to-parent log, the expense ledger, the custody order.
Records between her parents about a legal relationship she was the subject of but
not a party to. **She can have a copy of everything; she cannot erase somebody
else's record of their own conduct.**

### 9. Siblings, staggered
The risk §21.7 named. **Guardianship closes per child, never per family** — a
parent whose eldest turns eighteen has not stopped being a parent. The notice is
shown once, on the day, and never again: not an offboarding flow and not a
bereavement. Ten banned words keep it that way. A sibling link survives closure,
because she and her brother are still siblings at thirty.

### 10. Teach me something (§9.14)
He knows how to do things, and teaching is the most natural form of presence there
is. Sixteen seeds, four media, and **asking again is the only measure** — a lesson
she asks for twice becomes a preserved artifact. From about six she teaches him,
which is why §21.5 calls this the one feature that improves with her age.

### Removed
- `packages/maturation/src/SCAFFOLD.ts` — types only, superseded by the real
  module. Leaving it would have been dead weight beside a live implementation.

### Notes
- **145 assertions passed on the first run**, which is unusual on this project and
  is downstream of §21 having been specified carefully a fortnight earlier. Writing
  the spec first paid for itself.
- E2 forced the demo wiring rather than trusting me to remember it — the check
  added in v0.30.0 did its job on the first increment after it existed.

---

## [0.30.0] — 2026-07-27 — everything shipped now renders in the demo

**1,470 assertions, unchanged. 28 correspondence checks, up from 21.** No new
product screens; this is about closing a gap that was invisible in a green build.

### The audit
Instructed to make the demo render everything built, I audited it rather than
assuming. **21 of 37 built modules had no demo surface at all:**

`agency` · `annotation` · `api` · `archive` · `auth` · `care` · `child-lock` ·
`custody` · `delivery-engine/gate` · `delivery-engine/materialize` ·
`family-graph/authorize` · `family-graph/session` · `homework` · `ledger` ·
`ledger/sha256` · `messaging` · `phase3` · `session-runtime/rooms` · `storage` ·
`time-engine` · `transport`

Screens existed for several of them — the homework capture, the journal, the
wants-and-needs list, the court export, the year book, the majority handover —
but they were **static mockups sitting beside a fully tested engine that nothing
called.** Every one of those engines was green in `verify.sh` and none of them had
ever run in a browser.

### Seventeen are wired; four cannot be
A correct test of browser-bundleability found that 17 of the 21 bundle fine. The
other four import `node:http` or `node:crypto` and cannot — **by construction, not
by neglect:**

| Module | Needs | Why |
|---|---|---|
| `api/api` | `node:http` | it is an HTTP server |
| `auth/auth` | `node:crypto` | scrypt for PIN hashing |
| `session-runtime/rooms` | `node:crypto` | LiveKit token signing |
| `storage/storage` | `node:crypto` | signed-URL HMAC |

These are now **declared** in the demo manifest with the dependency named, rather
than being quietly absent.

### The Engine Room
A new demo surface calling all fourteen wired engine groups **live**. Every value
it shows was computed at page load: the portable SHA-256 actually hashes in the
browser, the ping bands come from `PING_BANDS`, the OCR thresholds are the
measured ones from v0.11.0, the push allowlist is the real approved copy.

**33 live probes, 0 failing.** One nice detail it surfaced: `call_incoming` has
`null` approved copy — a kind with no approved string sends **nothing at all**
rather than something vague being invented.

### And it is enforced — E1 to E7
The rule is now a build failure rather than a discipline:

- **E2** is the important one: every built module is imported by the bridge or
  declared node-only. **Silence fails.**
- **E4** stops a stale excuse hiding a real regression — nothing may be both
  wired and excused.
- **E5** refuses a declaration for a module that no longer exists, because dead
  weight there would mask the next genuine omission.
- **E7** verifies a node-only *claim is true* by reading the module and checking it
  really does import what it says.

Each was **shown to fail** when its guard was removed, per standing rule 3
(§20.4): unwiring `ledger` fails E2, adding a `ghost/ghost` declaration fails E5,
and claiming `time-engine` is node-only fails both E4 and E7.

### Fixed
- **My bundleability test harness was wrong before the modules were.** It checked
  esbuild's *output emptiness* rather than its exit code, and esbuild writes a
  success summary to stdout — so every module looked like it failed. Twenty-one
  false negatives from one bad shell conditional.
- **E6 originally matched minified identifiers** and passed locally while checking
  nothing in the built artifact. It now matches engine *titles*, which survive
  minification — the built file is the only one that matters.
- The push allowlist was module-private, so the demo could only describe it rather
  than render it. Now exported.
- A duplicate `storyArtifact` import between `games` and `storyteller` — aliased.

---

## [0.29.0] — 2026-07-27 — the thirteen gaps

**1470 assertions across 34 suites.** Twelve new demo screens, six new MARKUP
screens, three new modules.

### Show me pointed one way
Seven of the eight original show types were child→parent, which made it a feature
about **a child performing for an absent adult**.

- **The pending ask.** A prompt she goes looking for is a menu; one waiting for her,
  by name, is a message. **Capped at three** — if he asks six and she answers none,
  the app has built her a backlog of disappointment. A fourth pushes the oldest out
  silently, and no count or age ever reaches her: *a four-day-old ask looks exactly
  like this morning's.*
- **Reply in kind** is now nudged with a reason — *"'Nice!' is the reply that ends
  it"* — but never refused, because some reply beats none.
- **The shelf** holds every collection, most recently added first. Counts on the
  parent side only.
- **He shows her his world.** Nine things, and the first is why the rest exist:
  **"Where you sleep here."** A child who knows which bed is hers arrives
  differently. One is deliberately *not offerable* — "someone you will meet" — a new
  partner or a new baby belongs to a conversation, not a prompt deck.
- **The gallery.** Everything she ever made, by year, and **medium-agnostic**. A
  five-year-old's best work is usually made of cardboard and glue; a gallery holding
  only digital paintings would quietly tell her the things she is proudest of do not
  count. `frameFor()` returns an *identical* frame for all five media, so that claim
  is testable rather than aspirational. Companion to The Book — stories in one
  volume, pictures in the other. Its note: *"Cardboard counts. It always did."*

### The guardian shell
- **The pre-call briefing** is probably the highest-value screen in the product.
  Three facts and **one** opener, chosen by specificity — *"she showed you a
  Diplodocus yesterday"* beats *"she likes dinosaurs"*, because it is something only
  he could know. It must not become a script: a parent reading questions off a card
  is worse than one with nothing prepared. **P7 asserted: nothing from her journal,
  ever.**
- **The handoff care note.** Two decisions matter more than the feature. It is
  **not evidence** — outside the tamper-evident log, seven-day expiry, because if
  every "she has a cough" became a court exhibit parents would stop writing them
  honestly, **and an honest note is worth more than a preserved one**. And **the
  child never sees it**: "Mum said you were in a bad mood" is poison. Sixteen banned
  constructions catch the dig disguised as care, including *"she says you…"* — the
  child used as ammunition.
- **The catch-up** never guilt-trips: no "you missed 14 things", no unread badge, no
  oldest-first scroll through his own absence. Capped at four groups, silent about
  the gap itself, one thing to start with.
- **The coordination inbox** admits **only actionable items** — an inbox carrying
  news is a feed, and `admitToInbox()` is the gate that stops it becoming one.
  Deadline first, then oldest, because the oldest has kept somebody waiting.

### Around the call
- **The closing ritual.** Calls end with "ok, bye" and a black screen — for a child
  that is the moment the absence restarts at full volume with no warning. Three
  beats: forward-looking, certain, then a goodbye that is not "bye". The forward beat
  becomes a **real ask**, so *"I'll show you my tooth"* is waiting for her tomorrow.
  The certain beat **never invents a date**. Skippable at every beat, because a
  ritual she cannot escape stops being a comfort within a week.
- **Shared reading.** **She turns the pages.** A parent-controlled turn makes her a
  spectator to her own bedtime story; the button keeps her hands in it, and she will
  turn back to look at a picture — which is the whole point of reading with a small
  child. Turning back is explicitly not an error.
- **The mid-call handoff**, with a rule that is not negotiable: **only the child or
  the parent physically present can start it.** The remote parent never can, or the
  feature becomes a way to summon your ex through your child. Announced, two-minute
  box, and **not minuted** — recording a hello in a hallway would stop anybody doing
  it.
- **She is busy, so bank it.** A failed call is the worst possible output: rejection
  to him, a missed call she caused to her. Now a fork with two good branches. **And
  she is never shown a missed call** — a five-year-old who reads "Dad tried to call
  you at 10:40" has been handed a guilt she did nothing to earn.

### Added
- `packages/showcase/src/exchange.ts`, `packages/guardian/`,
  `packages/live/src/around.ts` — **153 assertions.**
- §9.10.7–11, §12.4–7, §9.13; MARKUP screens 56–61.

### Fixed
- Three of my own test expectations again: I asserted four parent-shows were
  age-2-appropriate (it is two), used a `>40` character threshold where the real
  property is *"gives a reason, not a label"* (now: full sentence, longer than its
  own title, at least six words), and advanced the closing ritual twice when
  checking a beat that occurs after one advance.
- Three more read-only surfaces excluded from the demo's playability check —
  briefing, his-world and catch-up have no controls by design, and asserting
  playability on them asserts the wrong property.

---

## [0.28.0] — 2026-07-27 — activities, the library, the book, and a P3 leak in the transport

**1301 assertions across 33 suites.** The security finding is the most important
thing in this release.

### §5.21 — the leak that would have shipped
WebRTC prefers a peer-to-peer path, and when it succeeds **each side learns the
other's IP address**. An IP is a coarse location: city, often neighbourhood, and
with a subpoena an exact one.

P3 forbids live location, and every previous increment enforced it at the
application layer — no coordinate columns, arrival as an event, no location keys in
push payloads. **And a peer-to-peer video call would have leaked it anyway, through
a channel nobody had looked at.**

It is worse than a privacy defect. `guardianship.restricted` exists for protective
orders — a parent whose address is legally withheld from the other. A peer path
hands the restricted party a location fix on a protected one.

> **That is a safety defect, not a privacy one, and it would have shipped.**

All media is now relayed, always. `callPolicy()` returns
`iceTransportPolicy: 'relay'` as a literal, with **no parameter that can change
it** — a future contributor optimising for bandwidth has to edit the file and fail
the test rather than pass a flag. The trade is explicit and recorded: both parties
are exposed to *us* instead of to each other.

### Screen sharing is the leak parents cause themselves
A father shares his screen to help with fractions, and along the top of it is a
text from his lawyer. He is not careless — a whole-screen share simply shows
everything, and the child is looking straight at it.

Sharing is scoped to **one window**, whole-screen is not offered, notifications
are suppressed for the duration, and a preflight names exactly what will be visible
before it starts. Capture is released the instant the app loses focus.

### E2EE and the contradiction it creates
E2EE makes server-side recording impossible, and §5.15 supervised visitation
depends on recording. `auditE2ee()` refuses both dishonest combinations: E2EE
claimed alongside recording — *"one of them is a lie to somebody"* — and encryption
given up with no recording to show for it.

### §5.21.4 — what still leaks, named
Six residual risks, **three of which we cannot fix at all**, including *a parent
standing behind the child during a call with the other parent*. That one is worth
naming precisely because no amount of transport security touches it, and it is the
most common real breach of a child's privacy this product will ever see.

### §9.12 — three quiet activities
Things she will do for twenty minutes with nobody else present. **Not every minute
in this product can require the other house to be awake.**

- **Colouring book.** Tap a region, it fills. Vector artwork, so one asset covers
  both Fold screens. In by-numbers mode a *"wrong"* colour still fills — the number
  is a suggestion, not a test, and a child who wants a purple giraffe gets one.
  Undo restores the *previous* colour rather than clearing the region.
- **Find the thing.** A where's-Wally where **the parent chooses what is hidden**,
  reading §9.10.3 interests directly. Difficulty is decoy count and similarity
  (24/2 up to 320/14) — **never a timer**, because a clock turns a hunt into a test
  and a slower child is not worse at looking, she is five. A miss does nothing at
  all: no buzz, no shake, no counter.
- **Spot the difference.** Difficulty is count *and* subtlety, from 1.0 (present or
  absent) down to 0.15 (a shade change on one small thing). Generous tap radius: a
  five-year-old aims with a whole finger. How many are *left* is a goal, not a
  score.

### §9.11.6 — the library and the book
- **Bookmark ⌾** reopens a story at exactly the line they stopped on. If she
  stopped *after* a refrain, the recap shows her line again first — starting her
  cold on line eight of a story whose chant she has forgotten is worse than one
  repeated sentence. A bookmark on the last line is refused.
- **Star ★** builds a list that grows for years, newest first. `timesRead` is
  counted for the book and **banned from her view**.
- **The book 📖** — he collects her favourites and prints them. Ordered **oldest
  first**, so it reads as a year rather than a leaderboard, with *"you asked for
  this one nine times"* under each title. Plain text (§2.11), front matter a print
  shop can quote from, and under five stories it says it is a pamphlet rather than
  taking the money.

The whole book regenerates from six-character codes, so a hundred stories is six
hundred bytes and the artifact is reproducible forever — including at majority
handover, when the codes go with her.

### Added
- `packages/activities`, `packages/session-runtime/src/security.ts`,
  `packages/storyteller/src/library.ts` — **114 assertions.**
- §5.21, §9.12, §9.11.6; MARKUP screens 51–55; all playable in the demo, with
  star and bookmark on the story screen itself.

### Fixed
- **The drive test harness assumed every control was HTML.** The colouring book's
  tappable regions are SVG `<path>` elements, and `SVGElement` in jsdom has no
  `.click()`. Replaced with a helper that falls back to a bubbling synthetic event,
  which is what the shell's delegated listeners actually receive.
- One test expectation of mine was wrong again: I asserted a bookmark at line 4
  would recap a refrain, but line 4 *is* the first refrain, so nothing precedes it.
  `null` was correct. Both cases are now tested.

---

## [0.27.0] — 2026-07-27 — the storyteller

**1177 assertions across 32 suites.** Roughly **2.9 × 10¹⁷** stories, a refrain
she says aloud, and a six-character code so she can ask for the same one again.

### The refrain is the whole thing
The highlighted line is **hers**. It appears three times, identically, and is
marked so the parent stops, looks at her, and lets her say it. By the third time
she gets there first.

That single affordance is the difference between reading *to* a child and reading
*with* one, and it costs a boolean. Most generators omit it, which is why most
generated stories get read once.

### It will not repeat
Eight shapes across twelve pools. A story every night for eighteen years draws
6,570 of them — under a billionth of a billionth of the space.

### A story is a six-character code
Not stored, **regenerated**. The same code always produces the same story exactly,
so *"the one about the octopus"* is six characters rather than a stored paragraph.
A thousand favourites cost six kilobytes, and a story she asks for **twice** is
preserved automatically — that is the signal worth acting on.

### Safe for five, checked on output
Gentle, silly, occasionally sad — a lost mitten, a wilting flower, missing
somebody. Fifty-plus banned terms, and the audit runs on the **generated output**
rather than the vocabulary, because a bad combination is where a problem would
actually surface. **4,000 generated stories are swept on every build.**

**And never about her parents.** A story about a bear who lives in two houses
could be wonderful or devastating, and the product cannot tell which on any given
evening. `divorce`, `two houses`, `custody`, `Mummy and Daddy` are banned
outright. *If a family wants that story, a parent can tell it. Software should not
choose the moment.*

### Personalisation is capped at two touches
Her colour in one line, her name in another. A story where every noun has been
swapped for the child's name is not a story about an octopus any more, and
children spot the machinery immediately.

### Added
- `packages/storyteller` — **64 assertions**, including the corpus sweep, the
  4,000-story output audit, the code round-trip, and refrain presence across
  every seed.
- §9.11; MARKUP screens 49–50; playable in the demo under **Games → Storyteller**.
- It sits *beside* the co-op story from §9.2, not instead of it. Both are wanted,
  for different evenings.

### Fixed — three prose bugs that only reading it aloud would find
Printing real output was the step that mattered. No unit test would have caught
any of these; they are all grammar.

- **Openings come in two grammatical kinds** and were treated as one, producing
  *"Nobody expected any of this. in a forest where the trees leaned in to
  listen."* Split into lead-in fragments and standalone sentences, with the
  setting clause capitalised accordingly.
- **The personalisation did string surgery on a finished sentence** and mangled it
  into *"So she went and found, and a child called OLIVE a nurse walking home."*
  Now the line is built with the name in place, not rewritten afterwards.
- **"a marble that rolled uphill with her, who was no help at all"** — a relative
  pronoun that has to agree with objects and creatures alike. Sidestepped
  entirely with two short sentences, which reads better aloud anyway.

A grammar sweep now runs 800 stories per build checking for lowercase after a
full stop, mangled clauses, pronoun mismatch, double spaces, and missing terminal
punctuation.

### Fixed — other
- **Her age is 5, not 6.** Demo defaults corrected throughout — birth year 2021,
  and the game/showcase/birthday screens now default to a five-year-old.
- **`gun` matched inside `begun`.** The audit used substring matching on single
  words and flagged *"The day had begun so well."* Single words now match on word
  boundaries; phrases still match as substrings. This is the **third instance of
  this class** on the project — after exact conjugations in the framing guard and
  a capitalisation heuristic in the push audit — so it is worth naming: *a text
  guard matching the wrong granularity is not a strict guard, it is a broken one,
  and it fails in both directions.*
- **The re-read promise was silently broken.** `codeFromSeed` encoded base-29 and
  `seedFromCode` was an FNV hash — not inverses of anything, so `reread(code)`
  returned a *different* story. Caught by a round-trip assertion, which is the only
  kind that would have caught it. Seeds are now constrained to the code space,
  because a code that cannot represent its own seed is not a code.
- **A state-key collision in the demo.** The turn-based co-op story game stores
  its board at `S.story`, and the storyteller was writing to the same key — each
  clobbering the other. Found by the drive test visiting both screens in one
  session, which is exactly what that test is for.

---

## [0.26.0] — 2026-07-27 — she places her own birthday

**1108 assertions across 31 suites.** A fifth onboarding step, and a shared
calendar primitive the whole product now reads.

### One month grid, not a throwaway picker
`monthGrid()` is the single month renderer: seven columns aligned to the week,
with leading and trailing blanks as **real cells** so no consumer computes
offsets. The child's calendar, the guardian's, the exchange schedule and this
picker all read it.

A throwaway picker would have been quicker and would have drifted from the real
calendar within two increments. It is the same grid or it is not worth building.

### The hard part is the year, so she is never asked for it
A six-year-old finding a date six years in the past is genuinely difficult —
scrolling back 72 months is 72 taps, and she may not know the year at all. But she
almost certainly knows the **month** and the **number**.

So those are the only two things she is asked for. The year is **derived** from her
age (§8.5.2) plus **one yes/no**: *"Have you had your birthday this year?"* — a
question a five-year-old can answer with certainty, and the only ambiguity that
exists. Where a guardian has already entered the date, even that disappears.

### The hint is a nudge, not an answer
With a guardian date on file the correct month is outlined. She still does the
finding; the hunt is simply short enough to succeed. `shouldHint()` returns false
from age **nine** — scaffolding that withdraws, exactly as §21.5 requires.

### She is not corrected about her own birthday
Place it a day out and the guardian's date stays of record, hers is kept, and the
disagreement is recorded — **never surfaced.** Being corrected about your own
birthday, by software, in front of nobody, is a small humiliation with no upside.

### Her calendar begins with her birthday
That ordering is the reason this step exists at all. **The first entry a child
ever sees in a co-parenting product should be a thing she is looking forward
to** — not a custody exchange. The suite asserts no custody vocabulary appears
anywhere near it.

The marker recurs yearly, takes her colour from §8.6, records that *she* placed
it, and `deletableByGuardian` is a literal `false`. A birthday is a fact, not a
preference. The year lives on her record; the event is a month and a day.

### 29 February
Without an explicit rule the event silently vanishes three years in four.
Observed on **28 February** in a common year — the choice more families make, and
more to the point it keeps the birthday inside the correct month, which is what a
child cares about. Asserted across four consecutive years.

### Added
- `packages/calendar` — **71 assertions**, including the century and 400-year leap
  rules, whole-week grid alignment, and markers landing on exactly one day.
- §8.7 in the MASTERFILE; MARKUP screens 46–48; playable in the demo under
  **First run → Her birthday**, with age presets to watch the hint appear and
  fade.

### Fixed
- Four of my own test expectations were wrong, not the code: I asserted a
  six-year-old in 2026 was born in **2026**. She was born in 2020. I had also put
  the future-birthday branches the wrong way round — for a nought-year-old,
  *"not yet"* resolves to last December and *"already had"* resolves to this
  December, which is the one that must be refused.

---

## [0.25.0] — 2026-07-27 — her colour

**1032 assertions across 30 suites.** A fourth onboarding step, a daily two-up,
and her colour on her father's screen.

### The oversaturation constraint was the real problem
The naive implementation sets one accent variable and the whole app turns hot
pink. Worse, it collides with the **semantic** colours the Day Ribbon depends on —
a ribbon band encodes what she is doing, the overlap green means *"you can both
talk right now"*, red means a prohibition.

So there is a **placement budget**: eight allowed positions, fourteen forbidden
ones, and `MAX_PLACEMENTS_PER_SCREEN = 3`. The forbidden list is deliberately the
longer one, `applyColour()` refuses those placements outright rather than trusting
a stylesheet, and anything past three is **dropped** — beyond that the colour
stops reading as *hers* and starts reading as a theme.

### Contrast is never her problem
She picks yellow; yellow text on white is unreadable. **The answer is not to
refuse her choice.** The pure hue is used for fills and a derived ink colour
wherever text is involved. All twelve swatches are asserted to pass WCAG AA as
ink — real luminance and contrast-ratio maths, not a vibe.

There is deliberately no pure red: red means a prohibition everywhere else, and a
child should not have to fight the warning colour for her own accent.

### One of the daily pair is always her current colour
Keeping it is therefore exactly as easy as changing it, and the side is
randomised so hers is not always on the left. **A daily prompt that nudged toward
change would be manufacturing churn out of a child.**

### The prohibition this module exists to hold
*"She picked grey today — is she sad?"* is the product making a psychological
claim about a child from a tap. A parent acting on it will get it wrong in a way
that costs them the exchange, and a product that offers the inference has invited
them to.

He is told **what she picked and nothing else**. No sentiment, no trend, no "her
colours have been darker this week" — and **no field in which such a thing could
be recorded**. `auditColourPayload()` refuses `mood`, `sentiment`, `trend`,
`concern`, `flag`, `volatility`. The interpretation belongs to the parent who
knows her, reached by asking her.

### Added
- `packages/palette` — **56 assertions**. §8.6 in the MASTERFILE.
- A colour step in onboarding, between age and who. Skippable like everything
  else: a child with no colour simply has no colour, and the app looks as it did.
- MARKUP screens 43–45; all three playable in the demo under **First run**.
- A year of colours is now a Year Book section — the cheapest in the product.

### Fixed
- The demo drive test asserted playability on `paletteParent`, which is a
  read-only view of what a parent sees and correctly has no controls. Asserting
  playability there was asserting the wrong property. Read-only screens are now
  excluded from that check and remain covered by the render check.

---

## [0.24.0] — 2026-07-27 — the child's first run

**969 assertions across 29 suites.** Three screens, and two of them turn on a
refusal.

### She spells her own name
Spelling your own name is very often the first thing a child learns to write, so
the app opens by asking for the one thing she is already certain she can do.

**Her spelling stands.** If she writes OLIVEE, the app says OLIVEE. Correcting a
child's spelling of her own name on the first screen of a product about being
known by her father would be a small, precise cruelty. The guardian-entered legal
name stays on the record for exports and the emergency card; this is her name
inside her app, and she can change it any time without asking.

The copy audit refuses *try again*, *invalid* and *wrong* — and equally *well
done*, *good job* and *nearly*. **She is not being tested, so she may be neither
corrected nor praised for getting it right.**

### She taps her age, and it is not believed
Age gates real things — which games unlock, the ping band, the §21 rung, the
§21.5 quieting schedule. A six-year-old who taps *10* because ten sounds better
must not thereby unlock a privacy tier.

The guardian's birth date always wins. Her tap is **kept**, the disagreement is
**recorded** rather than silently overwritten, and `effectiveAge()` — which every
other module reads — returns the real number. Asserted: tapping 17 with a birth
date of 2020 still yields 6.

It also matters under §10.2. Age is a COPPA-relevant fact and cannot rest on a
tap by the subject.

### She is told who is here — she does not choose
**§17.1 — one grown-up means no choice screen at all.** Not a shortcut: asking a
child to pick between Mummy and Daddy on the first screen of a co-parenting
product would be tactless at best, and §2.4 says the child never sees the
machinery of conflict. She is not choosing which parent exists; she is being told
who is already here.

A parent who has not accepted appears greyed and nothing more — no nudge, no
"invite them", no empty state implying something is missing (§2.12, §17.5).
Where two have joined, both are selected by default and **the last one cannot be
deselected**. Labels are each guardian's own word; hard-coding *Mommy* and
*Daddy* would fail a great many families.

For this version only one guardian is in the graph, so the flow lands on the
no-choice branch — which is exactly the §17.1 default rather than a special case.

### Added
- `packages/onboarding` — **56 assertions.**
- §8.5 in the MASTERFILE; MARKUP screens 40–42; the flow is playable in the demo
  under **First run**, letter keypad and all.

---

## [0.23.0] — 2026-07-27 — Olive Branch, and three Phase 1 decisions settled

**911 assertions across 28 suites.** §16.2 is down to five items, none of which
block Phase 1.

### §16.2 #1 — the name. Two of them, deliberately.

| Audience | Name |
|---|---|
| The child | **Olive** |
| Adults | **Olive Branch** |

To a child, *Olive* is a name, a colour, a fruit, a friend. It carries nothing —
and it must not, because §2.4 says the child never sees the machinery of
conflict. A product called *Olive Branch* on her home screen would announce every
day that something between her parents needed repairing.

To an adult it is unmistakable: a peace offering, extended by one party to
another. **That is precisely the register §17.2 spent a whole section
constructing in invitation copy — the name now does that work before a word of
body text is read.** At the hardest moment in the funnel, a reluctant second
parent receives an invitation from an ex-partner; everything depends on whether
they open it or read it as an opening move. An invitation from *Olive Branch* has
already said the right thing.

**The rule:** the child never sees the two-word form. "Branch" implies something
broken and being mended, which is adult knowledge about her family. Push titles
and SMS prefixes carry `'Olive'` alone, enforced by the existing allowlist audits.

Renamed across **41 files**, including the contract-checked channel constants in
Kotlin, C# and Dart. Still requires USPTO and app-store clearance — settled as a
working decision, not a cleared one.

### §16.2 #4 — the ping limit scales, then stops existing

| Age | Per day |
|---|---|
| to 7 | 3 |
| to 9 | 5 |
| to 12 | 8 |
| **13+** | **no limit** |

A uniform 3/day treated a five-year-old and a fifteen-year-old as the same case.
The younger child needs the limit as a boundary around a habit she cannot yet
self-regulate; the older one experiences the same limit as a **cap on contacting
her own parent**, which is a different and worse thing. §21.5 governs the top of
the table: the limit is scaffolding, and scaffolding fades.

At 13+ the function returns early — not a large number, the *absence* of one, so
there is no counter to compare against.

### §16.2 #5 — preservation is a standing rule, and nothing is lost silently

Anything a parent sends is now **kept by default**. Opt-in optimises for storage
cost at the expense of the one thing this product exists to protect: a parent who
forgets to tick a box loses the thing forever. **The cost of over-keeping is
pennies; the cost of under-keeping is a message from a father who has since
died.**

The counterweight, and the reason it survives §10.7: incidental material — call
clips, screenshare frames — is still on a clock, but it surfaces in an **expiry
digest 14 days before deletion**, with one tap to keep it. That was the user's
condition and it is what makes the posture defensible rather than merely
generous.

**The digest is never shown to a child.** *"These memories are about to be
deleted"* is a sentence no eight-year-old should read about her own life.
`digestVisibleTo('child')` returns `false`, the payload declares
`audience: 'guardian'`, and the headline copy is asserted to contain no deletion
language.

### Added
- §16.3 (the name), §10.1b (the standing rule), §16.1b (a settled register).
- `PING_BANDS` / `pingLimitForAge()`, `expiringSoon()` / `digestVisibleTo()` /
  `keepForever()`. **20 new assertions.**
- MARKUP screen 39 — the expiry digest.

### Fixed
- **The rename corrupted two Dart identifiers.** The prose rule turned
  `ThroughlineApi` into `Olive BranchApi` — with a space, which is not a valid
  Dart identifier. `flutter analyze` caught it immediately. Identifiers now take
  the single-word name; only prose takes the two-word one.
- **The rename script ran inside `scaffold/` and missed the four canonical docs
  at the repo root.** Caught because the MASTERFILE header still read
  THROUGHLINE after the pass reported success.
- **The MASTERFILE status line was eleven versions stale** — it still claimed 396
  assertions from v0.10.0. Replaced with a pointer to `npm run verify`, since
  standing rule 5 says a number quoted in prose that nothing checks is a defect.
- **`retention.ts` split out of `storage.ts`.** The digest is a *policy* and had
  no business requiring a Node runtime via `storage.ts`'s `node:crypto` import —
  the same reasoning as the ledger's portable SHA-256. It has to be evaluable in
  a browser, a worker, and a test. `storage.ts` re-exports, so no caller changed.

---

## [0.22.0] — 2026-07-27 — §9.10 the showcase, "show me"

**879 assertions across 28 suites.** Built from an observation about a real
child, and it reframes something the spec had wrong.

### The observation
A child can be highly communicative in person and near-silent on a video call,
and the reason is **not shyness**.

In person you share a room — there is always something to point at, and most of
what a child says is anchored to it. Over video the shared referent is gone, and
what remains is *"how was your day"*, which is an interview. Children are bad at
interviews, and adults conducting them get monosyllables and blame the child.

**Showing restores the shared referent.** For most children it is the native
register, and every previous section of this spec treated it as a side feature.

### Standing rule added
No copy anywhere in this product may describe a child as shy, quiet, reticent,
reluctant, or as needing to be *drawn out*, *opened up*, or *got talking*. That
framing takes a thing she is good at and re-describes it as a deficiency.
Enforced by `auditFraming()` across the module's own copy.

### Added — `packages/showcase`, 60 assertions
- **The matrix**: eight show types — a thing, what you made, what you learned,
  what you can do, where you are, all of them, let-me-teach-you, and look-what-
  happened. Each carries a `parentRole` column, which is the one that matters:
  a parent who answers *"look at my dinosaur"* with *"that's nice, how was
  school"* has ended the exchange.
- Two are load-bearing. **"Let me teach you"** is the only feature in the product
  that gets *better* as she ages rather than fading (§21.5), and **"Look what
  happened"** has no prompt and no schedule — the tap she reaches for when
  something happens, which is the best case the module exists to receive.
- **Interests**, recorded lightly and expiring gently. No intensity score, no
  ranking, nothing ever deleted. After 120 days without a show an interest simply
  stops generating prompts.
- **Collections**, for the enumerable interests most children have.
- **MARKUP screens 36–38** and four demo screens with live controls.

### The rule that matters most
**The product never says "you used to like dinosaurs."** A receded interest is
visible on the *guardian* side, where glancing back at what she was into two
years ago is warm. The same list shown to her is not. Being reminded of what you
have outgrown is a small humiliation, and P9 already establishes that resurfacing
is dangerous in this population.

### Prompts are parameterised, never hard-coded
Templates take `{one}` and `{plural}`, so an interest nobody anticipated works
exactly as well as one we thought of — asserted with *washing machines*.
Hard-coding dinosaurs would have been faster and would have failed the moment she
moved on. Every kind also has a generic fallback, so a child with nothing
recorded is never worse off than one with several.

### Collections have no denominator, deliberately
*"You have shown me 23"* is a record of what happened. *"23 of 151"* is a homework
assignment. **Pokémon has over a thousand** — a completion bar there is a small
cruelty, and P2 forbids the pressure. `SHOWCASE_FORBIDDEN` bans `total`,
`percent`, `completion`, `missing`, `remaining`, `goal`, `target` and `quota`
from any child-facing payload.

This is also what replaces streaks: a collection that grew is a real record; a
47-day streak is a punishment waiting to happen.

### P5, named explicitly
`INTEREST_FORBIDDEN_USES` names all six: ad targeting, recommendation engine,
model training, analytics segmentation, lookalike audiences, content feed. A
future contributor has to delete a line rather than merely forget.

### Fixed
- **The framing guard matched exact conjugations.** It caught *"comes out of her
  shell"* and sailed straight past *"come out of her shell"* — a guard that only
  catches the wording someone happened to think of is close to no guard at all.
  Rewritten to match stems, plus regex patterns for the constructions that
  pathologise not-talking. A second pass added the irregular past: it caught
  *"gets her talking"* but not *"got her talking."*

---

## [0.21.0] — 2026-07-27 — §21 the maturation ladder, specified

**Specification only. No behavioural change, no assertion change — 811, exactly
as before.** Nothing in §1–§20 was touched.

### The directive
Recorded in §0, and it governs future increments rather than this one. Every
change is now measured against three questions:

1. Does this hold at seventeen, or only at seven?
2. Does it move authority *toward* the child as she ages, or away?
3. At what age should it stop being shown to her at all?

### §21, in full
- **§21.1** The principle: a single cliff at 18 is emotionally powerful and
  structurally wrong as the *only* transition. Growing up is a hundred small
  transfers of authority. A rung is **irreversible** — `canGuardianRevoke()`
  returns `false` and there is no inverse function, the same construction that
  makes P7 unreachable. The ages may move by jurisdiction; **the order may not.**
- **§21.2** The ladder: 10 her list · 13 the journal locks · 14 her calendar ·
  **15 she publishes her availability** · 16 archive curation · 17 her own
  export · 18 everything.
- **§21.3** The inversion at fifteen, and the rung worth arguing about. For ten
  years the Day Ribbon has been two adults coordinating *around* a child, with
  her day-parts inferred. At fifteen she publishes and the ribbon shows what she
  set. A parent can then be told "she is not free" **by her**, rather than by a
  system modelling her. That is a real transfer of power, it will be
  uncomfortable, and refusing it would make the whole ladder decorative.
- **§21.4** Authorship: reverse message banking — she banks for *him*, for his
  deployment — and letters to her future self, sealed at nine and opened at
  eighteen, always preserved because a letter on a 90-day clock is a lost letter.
  Both need no schema change.
- **§21.5** **The quieting.** Most products add features as users age and measure
  success in engagement; this one withdraws. A fade schedule per scaffold: sleeps
  countdown at 11, prompt decks at 13, the child-side send-time guard at 14 (it
  stays on *his* side permanently), day-part labels at 15, handicap offers at 15,
  ritual reminders at 16. What never fades: calendar, call, archive, journal, and
  the guardian-side coordination layer. **A product whose stated goal is to become
  unnecessary is a strange thing to build, and the only honest reading of "grows
  up with you."**
- **§21.6** After eighteen: take-and-go, keep-as-archive, or becomes-a-parent —
  a twenty-five-year loop that turns §2.10 from a privacy stance into something
  structural. Not to be designed for prematurely, but nothing built before then
  should make it impossible.
- **§21.7** Three risks with a **position taken on each**, including: the product
  sides with the child on every rung above 13 and accepts the revenue cost,
  because the parent is the one paying and the drift toward
  surveillance-through-adolescence is commercially rewarded. If that position is
  ever reversed, §2.1 must gain a prohibition recording it — so the reversal is
  visible rather than gradual.
- **§21.8** What already exists: privacy tiers, `closed_at`, `era_tag`,
  `preserved`, delivery policies, `authorizeExport()`. Genuinely new: an
  append-only `maturation_grant` table, and a child-authored availability table
  that takes precedence over inferred day-parts.
- **§21.9** Four open questions, including whether the ages are family-shiftable
  — kind to an unusual child, and also the obvious lever for a controlling one.
- **§21.10** Build sequencing, starting with the grant table and **the quieting**,
  which is mostly deletion.

### Added
- `scaffold/packages/maturation/src/SCAFFOLD.ts` — the ladder, the fade schedule
  and the deletion shape as types. **Not in the build, not in `verify.sh`, not
  imported by anything.** It exists so the shape is captured in types rather than
  only in prose.

---

## [0.20.0] — 2026-07-27 — ten live games, played during the call

**811 assertions across 27 suites.** Twelve asynchronous games and ten live ones.

### Why live games exist here
A five-year-old runs out of things to say on a video call in about ninety
seconds. Then it is *"what did you do today"* → *"nothing"* → silence, and the
call ends early with both people feeling worse. **The job of a live game is to be
a spine for the call** — structure, not entertainment. That framing decided every
choice below.

### Added
- **`packages/live`** — ten games and their prompt decks. **59 assertions.**
  Simon says, copy me, freeze dance, charades, I spy, "show me something…",
  twenty questions, would you rather, two truths and a lie, and Pictionary.
- **MARKUP screens 34–35** — the unfolded side-by-side call, and what the child
  sees when the connection drops.
- Two demo screens with live controls: switch games, and break the connection to
  watch the fallback.

### The three constraints are structural, not documentation

**1. Nothing sub-200ms.** `register()` **throws** `UnplayableOverNetwork` for any
game declaring a lower tolerance, so a reflex game cannot enter the registry at
all. Verified by attempting to register whack-a-mole at 80ms and confirming the
registry does not grow. The refusal message names why it matters: over a real
connection the network becomes the opponent and **the child takes the blame for
it**.

**2. The parent's face is never hidden.** `VideoLayout` has exactly two members —
`side_by_side` and `picture_in_picture`. There is no `hidden` and no
`fullscreen`; a game that covers the video has inverted the entire product.
`liveLayout()` returns `videoVisible: true` as a literal in every branch.

**3. A live game degrades rather than dies.** The train goes into a tunnel:
twenty questions becomes turn-based and waits with every answer preserved. Games
that genuinely need a live camera **say so honestly** rather than pretending —
*"Simon Says needs to see each other. It is saved for next time."*

### Never blame the child for the network
A laggy game implicitly tells a child she is being slow. So the strings are
explicit and asserted: **"The connection is slow right now — not you."** and
*"The call dropped. Nothing is lost."* The suite checks that no connection
message contains *you are*, *too slow*, *your fault*, or *missed it*.

### The Fold turns out to be genuinely better at this
The main screen is 673 × 841 — nearly square — so the video and the board fit
**side by side**, with the gutter falling on the crease. On a tall phone you would
have to choose one or the other. Folded, it stacks and the face stays on top.
`liveLayout()` derives this from the viewport rather than a device string, and
the demo re-renders it live when the hinge opens.

### Notes
- Decks **reshuffle** rather than ending — a call should never be cut short
  because the cards ran out.
- The lead **alternates** each round, so the child is not always the one being
  tested.
- Pictionary reuses the §9.1 canvas entirely: stroke sync, per-actor undo that
  cannot erase the child's work, ephemeral pointer. The only new pieces are a
  word and a guess.
- `auditLiveView()` refuses `reactionMs`, `accuracy`, `streak`, `countdown` — P2
  applies to live play exactly as it does to turn-based.
- The demo drive test now plays **all fourteen** interactive screens at both Fold
  viewports. **54 assertions.**

### Fixed
- My new wide MARKUP screen used `class="deskscreen"` where the established
  convention is `class="screen"` on the inner element. C3 caught it immediately —
  the declared count and the rendered count disagreed.

---

## [0.19.0] — 2026-07-27 — three games only this product can do

**807 assertions across 26 suites.** Twelve games now, all playable in the demo.

### Added
- **"I went to the market"** — the campfire chain, not Simon.
- **Kim's game** — a photo of his table with one thing taken away.
- **The scavenger hunt** — a list he sets, photographed around her house.

### Why not Simon
Classic Simon is a **machine testing a child against a high score**, which
collides with P2 head-on. The campfire version fixes everything at once: the
chain is *theirs*, it fails together, and one step per turn is exactly a day
apart. When it drops, the closing line is **"You two got to eleven together"** —
shared, never who dropped it. `ended.by` exists for the transcript and is asserted
never to reach a scoreboard.

Then the steps are **recordings of his voice**. That makes the memory game out of
the parent, which is this product's thesis compressed into one mechanic. Past
five steps the chain becomes a preserved artifact.

### Kim's game is the best of the memory family and nobody builds it
Dad photographs his kitchen table with eight things on it; she looks; he removes
one and photographs it again. **Real photos, real rooms, zero art assets** — and
it quietly teaches her what his house looks like, which matters more than the
game. Fewer than five objects is refused: below that it is spot-the-obvious, not
memory. Getting it wrong is not a failure state — *"it was the keys, tricky
one"*. She still looked at his kitchen.

### The hunt is the only one that gets her out of the chair
For a product whose thesis is presence rather than engagement, that is not a
minor point — and it reuses the homework camera entirely, so it costs almost
nothing.

Two decisions worth recording:

- **No timer, and no field for one.** `auditNoScore()` refuses `countdown`,
  `timeLeft`, `seconds`, `elapsed` anywhere in these three. A countdown would turn
  wandering around the house into a test.
- **Everything she photographs is `preserved: true`.** A picture of the oldest
  thing in her mother's house, taken because her father asked, is exactly the
  material §9.8.2 and §9.8.4 exist for. Putting it on a 90-day retention clock
  would be a mistake we could not undo later — so `huntArtifacts()` returns
  `preserved` as a literal `true`, not a default that could drift.
- More than eight prompts is refused: past that it stops being a game and becomes
  a chore.

### Notes
- **58 assertions** in `games3`, including: the list is hidden during recall
  (that *is* the game), a wrong step ends cooperatively rather than erroring,
  no blame language appears in any closing string, exactly one object is removed
  from the second photo, and every hunt find comes back preserved.
- The demo drive test now plays **all twelve** games at both Z Fold 5 viewports —
  **50 assertions**, up from 44.

---

## [0.18.0] — 2026-07-27 — all nine games, fully playable in the demo

**801 assertions across 25 suites.** Every game from the recommendation list is
built with real rules, and every one is playable end to end inside `DEMO.html`.

### Added — five more titles
- **Checkers** — real draughts. **Captures are compulsory**, multi-jumps keep you
  on move, and crowning ends a jump chain. That last one is the detail
  hand-rolled implementations routinely miss, and it is asserted.
- **Battleship** — the best async cadence of any classic: place once, then one
  shot per turn, which maps onto a day apart. A hit grants another shot. The
  opponent's ship positions never reach the client — only what has been hit.
- **Word search** — normally a *solitaire* game and a poor two-player one. What
  rescues it is that **the parent hides the words**, and they are personal. It
  becomes a message disguised as a puzzle, and it is the only game here where the
  parent's turn happens before the child opens it.
- **Guess the word (hangman)** — eight lives rather than the usual six, because
  this is not a game about a child failing. The parent picks the word and may
  leave a hint.
- **Chess** — on `chess.js`, so castling, en passant, promotion, stalemate,
  threefold repetition and the fifty-move rule are correct. Hand-rolling those is
  a classic underestimate and a family product getting them wrong would be worse
  than not shipping chess. Three material handicaps the child may impose, and
  coaching that reuses §9.1 exactly: **it asks the parent a question and never
  gives the move.**

### The demo is now genuinely playable
Nine boards, all interactive, all driven by the same `play()` the tests exercise
— so what a visitor sees is the rules that are verified, not a reimplementation.
The parent's side is played by a deliberately modest opponent: it prefers
captures and hunts adjacent cells after a battleship hit, but it is weak enough
that a child wins, which is the point. A demo that beats a visitor at chess
teaches them nothing about the product.

Where a takeback cannot be modelled honestly — checkers, battleship, word search,
hangman, chess keep no shared move list — the demo offers **restart** and says so,
rather than pretending an undo happened.

### The drive test now plays, not just renders
Previously it rendered every screen and clicked every control. It now drives
**every one of the nine games through real moves** at both Z Fold 5 viewports,
then exercises restart, take-back and handicap on each board. **44 assertions, up
from 24**, and 1,080 control clicks per viewport.

### Added — MARKUP
Four screens: checkers with the compulsory-capture refusal, battleship, word
search with the hidden personal words, and chess with the material handicap and
the Socratic coaching line. The picker is **amended** to list nine.

### Notes
- `packages/games/src/games2.ts` — **72 assertions**, including the cases most
  likely to be wrong: a quiet move refused while a capture exists, crowning
  ending a multi-jump, stalemate scored as a draw rather than a loss, castling
  offered and legal, and the no-queen handicap removing exactly one queen while
  the child keeps hers.
- Chess coaching is asserted to contain **no algebraic notation** — the guard is
  structural, not a matter of prompt wording.

---

## [0.17.0] — 2026-07-27 — four games, and the mechanics that make them safe here

**781 assertions across 24 suites.** Three in a row, dots and boxes, a memory
game built from the family's own photos, and a co-op story.

### Why these four
§9.2 already said co-op beats competitive, and the reason is specific: a parent
who plays properly against a seven-year-old is running a weekly demonstration
that they are better. That is not a reason to skip competitive games — it is a
reason to build them differently. Three mechanics carry that weight, and they
matter more than the titles.

**The handicap is set by the CHILD.** Not a difficulty slider. She chooses what
the parent gives up — *"Dad can't use the middle square"*. Same material effect,
opposite power dynamic: she is granting a condition rather than receiving
charity. `setHandicap()` **refuses** a parent handicapping themselves, and the
banner reads "Dad's playing the hard way", never that she needs help. The engine
enforces it: the parent's move into the centre returns `handicap_forbids` from
the runtime rather than being hidden by the UI.

**Takebacks are free, unlimited, either side.** A physical board lets you hover a
piece and change your mind; a digital one that refuses is worse than the analog
version for no gain. Implemented by **replaying from the start** rather than
inverting the last move — inversion is where takeback bugs live, and
dots-and-boxes has an extra-turn rule that makes inversion genuinely hard. Tested
on exactly that case: undoing a box-completing move restores both the score and
the extra turn.

**A move can carry a voice note.** You cannot watch someone think across a
timezone. *"I saw what you did there"* attached to a move is the difference
between a chess app and this product, and it also solves the async problem.

### The losing streak surfaces itself
A parent who always wins is a harm the product created, so the handicap prompt
appears after three straight losses rather than waiting to be found. The record
exists **only** to decide when to offer — it is never rendered, never returned by
`childView()`, and the prompt is phrased as her choosing: *"Want to make it
harder for Dad?"* Draws do not count as losses; a win resets it; co-op games
never trigger it.

### P2, enforced on the payload
No ELO, no ranking, no win-loss record, no cross-game score. `childView()` has
**no field** for any of it, and `auditChildView()` walks nested structures for
`elo`, `wins`, `losses`, `streak`, `rank` and friends. There is no "you lost"
screen — a competitive game closes with **"Good game."** and a story with
**"What a story."** The suite asserts no losing language appears anywhere in the
child's view.

### Added
- **`packages/games`** — the runtime and all four titles. **77 assertions.**
- **MARKUP screens 24–26** — the picker, the handicap with its voice note and
  takeback, and the story.
- **Three demo screens** with live controls: toggle the handicap and watch the
  refusal appear and disappear; switch ages and watch the shelf change; feed the
  streak detector different histories.
- A finished story becomes a **preserved artifact** (§9.8), so it survives to the
  Year Book and the majority handover.

### Deliberately not built yet
Checkers, Battleship, word search with parent-hidden words, hangman and chess are
designed and recorded under `more_games`. Chess should use `chess.js` rather than
hand-rolled rules — castling, en passant, promotion, stalemate and threefold
repetition are a classic underestimate.

### Fixed
- A test asserted a four-year-old sees three titles; the catalogue gives two.
  The expectation was wrong, not the code — the stated target is 5+, where all
  four unlock. Added an assertion that nothing is gated above 5.

---

## [0.16.2] — 2026-07-27 — the demo targets a Galaxy Z Fold 5

New standing rule at the owner's direction: **the demo must match the dimensions
of the device it is being tested on.** That device is a Galaxy Z Fold 5, which is
not one device — it is two, and building for either one alone builds for neither.

| | CSS viewport | Physical | Shape |
|---|---|---|---|
| **Folded — cover** | 344 × 882 | 904 × 2316 | narrower than almost any other phone |
| **Unfolded — main** | 673 × 841 | 1812 × 2176 | **nearly square**, not phone-shaped |

### Added
- **A declared device block in `DEMO.html`** — both viewports, physical
  resolutions, DPRs, crease axis, and the four consequences that follow from
  them. Stated once so a correction lands in one place and the frames, the media
  queries, and the drive test all follow.
- **A fold toggle** — Folded / Unfolded. The frame is drawn at the **true aspect
  ratio** of whichever screen is selected: 0.390 folded, 0.800 unfolded. Showing
  a generic tall rectangle for a nearly-square main screen would misrepresent
  every layout decision made against it.
- **Breakpoints set from the device, not from generic phone/tablet guesses.**
  At ≤480 px the page is single-column with tighter gutters; between 481 and
  900 px it is two-column — and the gutter sits on the crease deliberately,
  rather than laying content across it. The crease is marked in the unfolded
  frame so decisions about it are visible.
- **Live resize handling.** Unfolding resizes the viewport while the app is
  running, so nothing may depend on a width measured once at load. The layout
  recomputes on `resize`.
- **Checks D6–D7**: the device is declared with both viewports; the main screen
  is recorded as nearly square (0.7–0.95) rather than phone-shaped; the cover
  screen is recorded as narrow; and no hard element width exceeds 344 px.

### The drive test now runs twice
Previously one arbitrary viewport. Now the **entire** drive — guided tour both
directions, all 19 screens, 473 control clicks, repeated folding and unfolding —
runs at **both** the cover and main viewports. **24 assertions, up from 11.**
A demo that works folded and breaks unfolded is not wired.

Two new per-viewport assertions: the frame matches the true aspect ratio to
within 0.02, and never exceeds the viewport width.

### Fixed — in the checker
D7's first version flagged `max-width:1180px` on the page container and the
480/900 media-query breakpoints. Neither is an element width — a max-width is a
cap that shrinks correctly, and a breakpoint is a condition, not a size. Media
conditions are now stripped before matching, and only a hard `width:` counts.

---

## [0.16.1] — 2026-07-27 — the demo tracks the changelog, enforced

New standing rule at the owner's direction: **DEMO.html amends in step with the
CHANGELOG and MARKUP.** Implemented as five new checks rather than a promise,
because this project has now proven three times that an unverified correspondence
rule drifts within one increment.

### Added
- **`data-screen` slugs on all 23 MARKUP screens**, so the link between the
  annotated reference and the runnable demo is declared rather than inferred.
- **A machine-readable manifest inside `DEMO.html`** — version, spec, assertion
  count, and an explicit coverage map: every MARKUP screen is either mapped to a
  demo screen or listed in `notDemoed` with a reason.
- **Checks D1–D5** in `tools/check-markup.mjs`, now a
  MARKUP ↔ CHANGELOG ↔ DEMO checker running inside `verify.sh`:

  | | Check |
  |---|---|
  | D1 | Demo manifest version equals the newest CHANGELOG version |
  | D2 | Demo's declared assertion count equals verify.sh's computed total |
  | D3a | Every MARKUP screen slug is accounted for in the manifest |
  | D3b | The manifest names no screen MARKUP does not have |
  | D3c | MARKUP screen slugs are unique |
  | D4 | Every mapped target exists among the demo's actual screens |
  | D5 | Under-construction areas are referenced and non-empty |

### Why D3 is the one that matters
A new MARKUP screen now **fails the build** until someone decides whether it is
demoable. That forces the question at the moment the screen is added, rather than
leaving the demo quietly a version behind — which is exactly how MARKUP itself
drifted before 0.10.1.

Two screens are declared `notDemoed` with reasons: the invitation (an onboarding
flow the demo starts past) and the lock advisory (setup on a physical device the
browser does not have).

### Changed
- MASTERFILE §0: the canonical set is four documents plus **DEMO.html as a
  derived artifact that must not lag them.**

---

## [0.16.0] — 2026-07-27 — a runnable end-to-end demo

**691 assertions across 22 suites.** `DEMO.html` — one self-contained file, no
server, no build step for the reader.

### Added
- **`DEMO.html`** — 19 screens across the child shell, the guardian shell, and
  the not-yet-built. Two modes: a **14-step guided tour**, and **free
  exploration** with a full navigation index.
- **`demo/src/bridge.ts`** — the demo is driven by the **shipped engines**, not
  by mock data. The ribbon offsets, the sleeps countdown, the double-dose
  refusal, the expense split, the hash-chain verdict, the tutor guard: all
  produced by the same code the other 680 assertions test. Each screen shows the
  actual engine call and its output beside it.
- **Interactive probes.** Feed the tutor a hint that gives away the answer and
  watch it refused. Photograph a blurred worksheet and get the retake advice.
  Edit, delete, or reorder a message in the court export and watch the chain
  break. Try the majority handover a year early.
- **`demo/test/drive.test.mjs`** — 11 assertions that walk the guided tour end to
  end, render all 19 screens, click **every** interactive control on every
  screen, and fail on any error card or uncaught exception. Wired into
  `verify.sh`, so the demo cannot silently rot.

### Unfinished areas say so
Seven `UNDER_CONSTRUCTION` entries — live video, native kiosk, captions, live
OCR, print fulfilment, the school layer, and the games board — each explaining
what exists and what does not. A demo that quietly pretends is worse than one
that admits a gap.

Every screen and panel renders inside an error boundary, so a throw shows a
readable card rather than a blank page. Verified by clicking everything.

### Fixed
- **The ledger depended on `node:crypto`, which is the wrong dependency for this
  particular artifact.** §16.1 #3 promises an export a reader can verify *from
  the file alone*; a verifier that only runs on our runtime is one the other side
  has to take on trust. Replaced with a portable SHA-256 checked byte-for-byte
  against `node:crypto` — NIST vectors, every block-boundary length (55, 56, 63,
  64, 65, 119, 120), multi-byte UTF-8, and 500 random inputs. **13 new
  assertions.** The court export now verifies in a browser, which is where a
  reader is most likely to open it.

---

## [0.15.0] — 2026-07-27 — the Dart toolchain, and a layout bug it found

**667 assertions across 20 suites.** The client is no longer unverified.

### Toolchain
The Dart SDK archive still 404s, but `flutter_infra_release` returns 200 — and
Flutter bundles Dart. Same lesson as LiveKit in 0.12.0: the "latest" path fails
where a pinned artefact succeeds. Flutter 3.24.5 / Dart 3.5.4 now runs here.

One repair was needed: the tarball extracts without git metadata, so the tool
self-reports `0.0.0-unknown` and pub refuses `flutter_test` because it cannot
verify the SDK constraint. Writing a correct `version` and
`bin/cache/flutter.version.json` fixes it.

### Added
- **`client/pubspec.yaml`** and a strict `analysis_options.yaml` — strict casts,
  strict inference, strict raw types, with `unused_import`, `dead_code` and
  `missing_return` promoted from warning to **error**. This project's record is
  that an unchecked assumption becomes a defect, so the analyzer refuses rather
  than warns.
- **`client/test/invariants_test.dart`** — 14 widget tests asserting the same
  properties the TypeScript suites assert, but against the tree a child actually
  sees: no settings affordance at any depth, countdown in sleeps and never hours,
  singular "1 sleep" rather than "1 sleeps", 48 dp minimum touch targets, child
  time dominant over actor time, no timezone arithmetic shown to a parent, a
  shuffled keypad across twelve renders, and no error text after a kiosk defeat.
- `flutter analyze` and `flutter test` now run inside `verify.sh` and in CI. A
  missing toolchain is a **gap, not a skip**.

### The bug it found on first run
`ChildHome` used `GridView.count` with the default aspect ratio of 1, so tile
height scaled with device **width**. On a tablet — the actual target device for a
child — two rows of square tiles consumed the viewport and pushed the
**"sleeps until" counter below the fold**, where a child would never scroll to
find it. §8.2.5 is one of the more considered decisions in this product and it
was invisible in practice.

Four increments of contract-checking never caught it, because endpoint strings
and brace balance say nothing about layout. Fixed with a fixed 108 dp
`mainAxisExtent`. MARKUP screen 1 amended accordingly.

Both failing tests shared this single cause, which is worth noting: the
`_Sleeps` widget was never built at all, so *neither* the number nor the label
was findable.

### Changed
- **§16.2 #10 removed at the owner's direction** — foster/kinship consent is not
  needed yet. Scaffolded at `packages/kinship/src/DEFERRED.md` rather than
  deleted, recording why it is hard (the state is a party, which breaks the
  §10.2 two-individual consent model and sets P7 against a caseworker's
  statutory duty of care), what already exists to build on (`contact_ladder`,
  `closed_at`, `sibling_link.contact_allowed`), and three preconditions before
  any work begins. The data model is not the blocker; the consent model is.
- §16.2 is down to eight open items, one of which — the product name — is the
  only launch blocker.

---

## [0.14.0] — 2026-07-27 — Phase 3 court tier and the archive

Ten items. **653 assertions across 18 suites.** Phase 3 is functionally complete.

### Added
- **`packages/ledger`** (items 1, 2, 4, 5) — the tamper-evident hash chain,
  exact expense allocation, and both export paths.
- **`packages/archive`** (items 6, 10) — Year Book compilation, majority
  handover, opt-in resurfacing.
- **`packages/phase3`** (items 7, 8, 9) — turn-based game runtime, visual
  schedule strip, SMS bridge.
- **`db/migrations/0006_court_tier.sql`** (item 3) — `message_log` with P8
  enforced by trigger, `expense` with FORCEd RLS, `export_record`, and two new
  health checks. 22 tables.
- **`db/test/0005_court.test.sql`** — 11 database assertions.
- **MARKUP screens 19–23** — schedule strip, expense ledger, certified export,
  Year Book, majority handover.

### P8 stops being a policy
`message_log` carries `BEFORE UPDATE` and `BEFORE DELETE` triggers that raise
unconditionally, and a `BEFORE INSERT` trigger that refuses any entry not linking
to the current head or breaking sequence contiguity. A broken chain cannot exist
in the table at all, rather than being discovered at export time. Verified: a
second genesis, a non-linking entry, a sequence gap, an edit, and a delete are
all rejected.

### The chain is verifiable without us
The attestation carries the head hash, the entry count, and a SHA-256 over the
serialized bundle — **all recomputable from the downloaded file alone.** A judge
is not going to query our Postgres, so verification that depends on us is worth
nothing. Every tamper mode is caught from the file: editing, deleting,
reordering, inserting, and rehashing-after-edit (which still breaks the *link*).
A broken chain prints `VERIFICATION FAILED` rather than passing quietly.

Hashing is **length-prefixed** per field. Naive concatenation lets bytes move
across field boundaries: author `ab` + body `c` would hash identically to author
`a` + body `bc`. Asserted.

### Money must not be created or lost
Naive per-share rounding of 3¢ split evenly gives 2¢ + 2¢ = 4¢. Over a year of
shared costs that is a real discrepancy in a document a court may read.
`allocate()` uses largest-remainder allocation with deterministic tie-breaking,
so the parts **always** sum to the whole. Verified across 1,000 amounts and a
three-way split.

### Turn clocks tick in reachable hours
§4.7, now implemented: a 24-hour turn timer that burns down while she is asleep
and at school is not a 24-hour timer — it is roughly a 9-hour one, and it expires
games nobody abandoned. `turnExpired()` takes reachable hours, and 24 wall hours
containing 2 reachable ones does not expire a turn.

### The SMS audit learned from the push audit
Same allowlist approach rather than a heuristic — v0.10.0 established that
guessing at the shape of a leak is the wrong instrument. The body must be
identical to an approved template, so a name, a link, an amount, or anything from
the emergency card is refused (§10.8).

### Notes
- The Year Book compiles from **preserved** artifacts only. Anything still on a
  retention clock may be gone before printing, and a volume with holes is worse
  than none — which is why `preserved` shipped in the Phase 0 migration two years
  ahead of this feature (§12.1). Below twelve items it is a slideshow and we do
  not offer to print it.
- Handover is refused the day *before* the birthday: one day early strips a
  guardian of access they still legally hold.

### Fixed
- **`§2.10` resolved to nothing.** The §2 principles were an unnumbered list, so
  the handover screen's reference to "the archive belongs to the child" pointed
  at no section — the same defect the checker found in §8.2 at 0.10.1, in a
  different list. All twelve principles are now addressable as `§2.N`.

### Process
- The MARKUP gate fired for the third consecutive increment — 567 → 653 — forced
  five new screens because five of these ten are user-facing, **and** caught the
  §2.10 dangling reference on the same run. Third distinct drift it has found.

---

## [0.13.0] — 2026-07-27 — ten Phase 1–2 features

**567 assertions across 16 suites.** Phase 1 is functionally complete and most of
Phase 2 landed with it.

### Added — four packages, ten features
- **`packages/custody`** (items 1–2) — the rotation engine and the child
  calendar. 2-2-3, 2-2-5-5, alternating weeks; holiday rules that **override**
  the pattern; exchanges resolved in `order_tz`; and `sleepsUntilSideChange()`,
  which is what "3 sleeps until Dad's week" in MARKUP had been rendering from
  nothing since 0.8.0. **42 assertions.**
- **`packages/annotation`** (item 3) — shared strokes, per-actor undo/redo,
  ephemeral pointer.
- **`packages/care`** (items 4, 6, 8) — emergency card offline bundle,
  medication slot guard with PRN support, bag manifest and arrival event.
- **`packages/agency`** (items 5, 7, 9, 10) — child ping, private journal,
  rituals, wants/needs. **63 assertions** across the three.
- **MARKUP screens 16–18** — child calendar, emergency card, private journal.

### Design decisions worth recording

- **Collaborative undo cannot pop the last stroke on the canvas.** That
  implementation means a parent's undo erases the child's drawing, and on a
  homework sheet that reads as the parent deleting her work. Undo is scoped to
  the actor's own strokes, skips already-undone ones so repeated undo walks
  backwards rather than toggling, and **cannot reach past a stroke another actor
  deliberately erased**.

- **A holiday rule overrides the base pattern, and precedence is explicit.**
  Getting that backwards puts a child in the wrong house on Christmas. Overlaps
  break on priority, then on the later start — a rule beginning inside another is
  the more specific one, so "Christmas Day" beats "Christmas".

- **Order-time is authoritative and never converted.** A decree saying 6:00 PM
  Eastern means 6:00 PM Eastern during the six weeks she spends in Texas — which
  is 5:00 PM where she actually is. Both are asserted.

- **The ping refusal has no message field.** Not an empty string — no field. A
  child is never told she has used up contact with her parent, and a type with
  nowhere to put that sentence cannot grow one by accident.

- **`auditChildPayload()` walks nested structures** for `streak`, `count`,
  `missed`, `claimedBy`, `price` and friends. P2 and §2.1 are enforced on the
  payload rather than trusted to the view layer.

- **The emergency card sorts severe allergies first** because the reader may only
  get through the first line, and the bundle is self-contained — no ids to
  resolve, no URLs to fetch. A card that needs connectivity is not an emergency
  card.

### Fixed
- **Negative modulo in the rotation index.** A child-local date *before* the
  order's anchor produced a negative index and read off the end of the cycle
  array. Guarded with `((n % 14) + 14) % 14`; a date 14 days before the anchor
  now equals the anchor, and dates before it resolve rather than throwing.

### Process
- The MARKUP correspondence gate fired again — 462 → 567 — and three of these ten
  items are user-facing surfaces, so it also forced the three new screens. Second
  consecutive increment where the rule caught real drift.

---

## [0.12.0] — 2026-07-27 — LiveKit verified against a running server

**462 assertions across 14 suites.** The §20.2b LiveKit gap is closed: a real
livekit-server 1.8.0 now runs inside `verify.sh`.

### Added
- **`packages/session-runtime/test/live.test.mjs`** — 21 assertions against a
  live server, and **`tools/with-livekit.sh`**, which owns the server lifecycle
  because it does not survive between shells. A missing binary is treated as a
  **gap, not a skip**.
- CI fetches and configures livekit-server as a declared dependency.

### I2 proven, rather than asserted
Every prior session assertion checked the JWT we *produce*. This checks what a
real server *accepts* — the only thing that establishes that a join token is not
an admin credential. Our minted token is refused by the server for `ListRooms`,
`CreateRoom`, `DeleteRoom`, `ListParticipants`, and `RemoveParticipant`, and for
`ListParticipants` on another child's room.

### Findings from the real server

- **I5 was overstated. LiveKit accepts tokens well past `exp`.** Measured:
  HTTP 200 at 3s, 30s and 60s past expiry; 401 at 95s. So the effective window
  is TTL plus a leeway we do not control, and **expiry is not a revocation
  mechanism at all** — it bounds new joins only. This retroactively strengthens
  the v0.10.0 finding: eviction via `removeParticipant` is not belt-and-braces,
  it is the mechanism. §5.19 I5 corrected to say so.

- **`removeParticipant` throws when the participant is absent, and `deleteRoom`
  throws when the room is gone.** Both are real defects in the §8.3 path. Kiosk
  defeat fires eviction *unconditionally* and cannot depend on join state — the
  participant may have already left. A throw there aborts the rest of defeat
  handling, **which includes dropping guardian escalation**, the severe case.
  And two parties hanging up simultaneously produces two `endSession` calls.
  Both now tolerate "not found" and report `absent`, while a genuine failure
  still surfaces.

### Fixed — in the verification harness itself
- **`dropdb`/`createdb` in `verify.sh` omitted `-U`**, failed silently behind
  `2>/dev/null`, and every database suite ran against the *previous* run's data.
  This produced 12 failures that had nothing to do with the code. The role flags
  now match the rest of the script, and a freshly created database that applies
  fewer migrations than exist **aborts the run** rather than continuing.
- Same missing `-U` in `run_concurrency.sh`, which is why it reported zero
  assertions — caught only because `verify.sh` treats zero as a failure.
- **Fourth instance of order-dependence.** The e2e suite called
  `claim_due_intents(50)` assuming it owned the queue; with the concurrency
  seed's 500 rows ahead of it, the claim never reached its own intent. Its
  orphan-risk assertions also counted globally. Both now scoped to
  `storage_key LIKE 'e2e/%'`.

### Process
- 10 increments, **14 false-greens**. Three new, all in the harness rather than
  the product: the silent `dropdb`, the silent concurrency driver, and the
  unscoped e2e claim. The pattern is now unmistakable — **on this project the
  verification harness has produced more defects than the code it verifies**, and
  every one was found by making a check fail on purpose.

---

## [0.11.0] — 2026-07-26 — OCR, observability, migrations, CI, native bridge

Five items. **441 assertions across 13 suites**, now including real tesseract.

### Toolchain reality, stated first
The Dart SDK archive and the LiveKit release binary are both unreachable from
this environment (404). **Tesseract 5.3.4 is installed**, so OCR became genuinely
testable. Scope was adjusted to match what can be executed rather than claimed.

### Added
- **`packages/homework`** — image quality gate and the tutor guard. **30
  assertions**, several shelling out to real tesseract against generated
  worksheets.
- **`tools/migrate.mjs`** — migration runner with four enforced properties:
  ordered (refuses a gap), idempotent, **immutable** (SHA-256 per file; an edited
  applied migration is refused), and transactional per file.
- **`db/migrations/0005_observability.sql`** + **`tools/healthcheck.mjs`** —
  seven health checks with severities, exiting non-zero on breach.
- **`.github/workflows/verify.yml`** — CI running migrations twice (the second
  must be a no-op), the full suite, and the health check.
- **`native/android/KioskBridge.kt`**, **`native/windows/AssignedAccessBridge.cs`**,
  **`client/lib/kiosk_channel.dart`** — the kiosk bridge across three languages.
- **MARKUP screen 15** — the retake prompt.

### OCR thresholds were guessed, and both guesses were wrong
The first draft set `MAX_SKEW_DEG = 25` and `MIN_EDGE_PX = 640` from intuition.
Swept against real tesseract, scoring the fraction of expected tokens recovered:

| skew | 0° | 2° | 4° | 6° | 8° | 10° |
|---|---|---|---|---|---|---|
| recovery | 100% | 100% | 83% | 67% | 33% | **0%** |

| blur σ | 0 | 1 | 2 | 3 | 4 | 6 |
|---|---|---|---|---|---|---|
| recovery | 100% | 100% | 100% | 50% | 33% | **0%** |

| min edge | 800px | 480px | 400px | 320px | 240px |
|---|---|---|---|---|---|
| recovery | 100% | 100% | 100% | 100% | 67% |

Wrong in **opposite directions**: 25° admitted images recovering nothing, while
640px rejected images recovering everything. Now `MAX_SKEW_DEG = 6` and
`MIN_EDGE_PX = 320`, with the measurements recorded beside the constants.

### The tutor guard is a control, not a prompt
"Hint, don't solve" is a safety property with a specific failure mode: a model
that answers destroys the thing the feature protects — the authority of a parent
who forgot fractions fifteen years ago. Prompt instructions are a request. So the
answer is derived **server-side** from the problem text and the model's output is
refused if it contains it, including the common denominator for fractions, which
is equally a giveaway. Word-boundary matching so "159" does not trip on "15".

### Findings

- **A production view was defined inside a test file.** `orphan_risk` was created
  by `0004_e2e_message.test.sql`, so it existed only in databases where that test
  had run — a monitoring view that was never deployed. The migration runner
  surfaced it the first time 0005 referenced it. Moved into a migration.
- **Sentinel bug in the runner's gap check.** `findIndex` returns −1 when every
  migration is applied, and `slice(-1)` returns the **last** element rather than
  an empty list — so a fully up-to-date database reported itself as out-of-order.
  Found by running the idempotency probe.
- **Orphan detection was ordered after the gap check**, so a migration missing
  from the repository was reported as an ordering problem, sending the reader to
  the wrong place. Reordered.
- **The MARKUP correspondence gate fired on its first real increment.** The
  computed total moved 396 → 441 while MARKUP still quoted 396; C7 failed the
  build. The rule added in 0.10.1 caught exactly what it was written for, one
  increment later.

### Unverified, precisely
- `client/lib` — 5 Dart files, never compiled. Endpoint strings, brace balance,
  CSPRNG use, absence of a settings affordance, and channel constants **are**
  contract-checked.
- `native/` — Kotlin and C#, never compiled. Channel names, method names, and
  event names are checked byte-identical across all three languages, because a
  mismatch there presents as "the kiosk just doesn't lock" with no error anywhere.
- LiveKit — tokens and lifecycle correct against the real SDK; no network call.

### Process
- 9 increments, **11 false-greens**. Two new: the runner's sentinel bug, and the
  guessed OCR thresholds — the latter is a new category, a constant that was
  never measured rather than a check that could not fail.
- Standing rule 6 adopted: **a threshold that governs a real-world signal must be
  measured against that signal, not chosen.** Recorded in §20.4.

---

## [0.10.1] — 2026-07-26 — MARKUP tracks the CHANGELOG, enforced

New standing rule at the user's request: the visual MARKUP amends in step with
the CHANGELOG. Implemented as a checker rather than a promise, because on this
project an unverified claim of correspondence has a poor record.

### Added
- **`scaffold/tools/check-markup.mjs`** — seven correspondence checks, exits
  non-zero on drift, wired into `verify.sh`:

  | | Check |
  |---|---|
  | C1 | MARKUP's version tag equals the newest CHANGELOG version |
  | C2 | MARKUP's spec tag equals the MASTERFILE version |
  | C3 | Declared screen count equals rendered screens |
  | C4a/b/c | Every screen declares `data-since`; every declared version exists in the CHANGELOG; every visual-era CHANGELOG version appears in MARKUP |
  | C5 | Every §ref in MARKUP resolves to a real MASTERFILE section |
  | C6 | Every prohibition ref resolves to a real §2.1 entry |
  | C7 | The assertion count MARKUP quotes equals what `verify.sh` computes |

- **Per-screen version provenance.** All 14 screens now carry `data-since`, and
  `data-amended` where a later release altered them.
- **MARKUP §06 Changelog correspondence** — a ledger of what each release changed
  visually, so the relationship is legible to a reader and not only to the
  checker.
- MASTERFILE §0 rule text for MARKUP↔CHANGELOG lockstep.

### Fixed — drift the checker found on its first run
- **Seven broken references.** MARKUP cited §8.2.1 through §8.2.9, but MASTERFILE
  §8.2 was an unnumbered list, so none of those references resolved to anything.
  The closeness-UI patterns are now explicit `#### §8.2.N` subsections. This is
  precisely the rot the rule exists to prevent: the references had been wrong
  since 0.8.0 and nothing would ever have noticed.
- **C7 is the standing-rule-5 case applied to a document.** MARKUP quoted "396
  assertions" as literal prose. That is the same defect as the hardcoded total in
  the v0.9.0 verification script — a number in a document that nothing checks.
  It is now compared against `verify.sh`'s computed output and the build fails if
  they diverge.

### Fixed — in the checker itself
- The §ref extractor flagged MARKUP's own section label `§05` as a broken
  MASTERFILE reference. MARKUP numbers its sections `§01`–`§06` zero-padded while
  MASTERFILE uses unpadded `§1`–`§20`; excluding a leading zero separates the two
  namespaces. Caught by running the checker rather than by reading it.

---

## [0.10.0] — 2026-07-26 — Phase 0 exit items 1–5

All five items from the §20.5 exit order. **396 assertions green** across 11
suites, against real Postgres 16.14, the real LiveKit SDK, real ES256 crypto, and
a real HTTP socket.

### Added
- **`packages/auth` (item 2)** — scrypt PIN hashing, WebAuthn ES256 assertion
  verification, signed short-TTL sessions, two-factor escalation. `withSession()`
  finally has something that produces a verified principal; P6/P7 rested on
  nothing until now.
- **`packages/api` (item 1)** — router with three invariants enforced
  structurally rather than by convention: **A1** every route must declare its
  required `Action` and a child-scoped route with none is refused *at
  registration*; **A2** session context is set only from the verified principal,
  inside the transaction, and a handler never receives a raw connection; **A3**
  `childId` is read from the path only, never from a body, query, or header.
- **`packages/storage` (item 3)** — port, in-memory adapter, key-bound signed
  URLs at a 300s TTL, and the reaper.
- **`db/migrations/0004_auth_and_reaper.sql`** — `webauthn_credential`,
  `webauthn_challenge`, `pin_credential` (RLS FORCED, no child read of PIN
  material even its own), `reap_tombstone`, `artifacts_due_for_reaping()`,
  `retention_breach`. 18 tables total.
- **`client/lib` (item 4)** — four Dart files: API surface, child home, guardian
  home with the ribbon, PIN gate. **UNVERIFIED — see below.**
- **`packages/transport` (item 5)** — push payload builders and the room
  lifecycle port.
- **`tools/verify.sh`** extended to 11 suites.

### The reaper: order is the whole design
Row-then-blob and blob-then-row both have a failure mode; only one is
discoverable. If the row is deleted first and the blob delete fails, media
containing a child's face and voice sits in storage **with no record that it
exists** — nothing will ever retry it, and nothing can find it. Blob first means a
failure leaves a row pointing at nothing: recoverable, visible, and already caught
by `orphan_risk`. The reaper therefore deletes the blob, and only on success the
row; on failure it tombstones and **leaves the row in place**. Tested both paths.

Also: a candidate with no expiry is **refused, not guessed**. That state should be
unrepresentable under the §5.6 CHECK, so its appearance means the constraint has
been dropped — and guessing a retention date at that point would be worse than
stopping.

### Push: notifications disclose nothing
A lock-screen banner reading "Goodnight video from Dad" tells anyone holding the
tablet that this child has a parent living elsewhere and what time she goes to
bed. On a child's device — shared, left on kitchen tables — that is a disclosure
of family structure to whoever picks it up. Payloads are a pointer and nothing
else: `kind`, an opaque `ref`, a version. Calls carry **no banner text at all**,
because CallKit and full-screen intent own that UI and a call must ring rather
than notify.

### Findings

- **scrypt N=32768 r=8 exceeds Node's default 32 MiB `maxmem`** — it needs
  ~33.5 MiB, so `scryptSync` **threw on the very first PIN ever set**. A cost
  parameter chosen without checking the runtime ceiling is not a strong hash, it
  is an outage; and an implementation that "helpfully" degraded to weaker
  parameters would be worse. Now computed explicitly via `scryptMaxmem()`.
- **`require()` inside an ESM module.** esbuild warned; it would have failed at
  runtime inside `verifyAssertion` — meaning every passkey login. Moved to a
  top-level import, and the build is now warning-clean.
- **The push audit was a heuristic, and heuristics were the wrong instrument.**
  A first version looked for capitalised words that might be names. It flagged
  "Something" — a sentence-initial capital — and would equally have missed a
  lowercase name. Replaced with an **allowlist**: the banner text must be
  *identical* to one of the approved constants. Shipping any custom banner is now
  impossible rather than merely discouraged, and even a harmless rewording is
  refused.
- **Token revocation is not eviction.** §8.3 revokes a LiveKit token on kiosk
  defeat, but an already-joined participant stays connected until the media
  server removes them — a short TTL bounds *new* joins, not the live one.
  `revokeLiveAccess()` calls `removeParticipant`, and the test asserts eviction
  rather than expiry.
- **PIN material must be unreadable by a child session, including its own hash.**
  `pin_credential` carries RLS with FORCE and a policy excluding the child role
  outright.

### The client caveat, stated plainly
`client/lib` contains **real Dart that is never compiled.** No toolchain exists
here. What *is* verified: every endpoint string is checked against the §7 surface
and must use `:childId` rather than a literal; exactly one journal path exists and
it is child-scoped; braces and parens balance; the PIN keypad uses
`Random.secure()` and re-shuffles after every attempt; the child shell contains no
settings affordance; and every file carries an `UNVERIFIED` marker, which is
itself asserted. That prevents silent drift from the API. It does not mean the
client works.

### Process
- 8 increments, **9 false-greens**, both new ones caught by their own suite: the
  scrypt parameter crash and the push heuristic. Standing rule 3 held — the push
  audit was required to be *shown to catch* a leak, which is how the heuristic's
  weakness surfaced at all.
- One test-only defect: the client-path validator's character class omitted
  uppercase, so `:childId` failed its own regex. Fixed, not counted as a
  false-green — it failed loudly.

---

## [0.9.0] — 2026-07-26 — async message end to end, and Phase 0 review

Sixth increment. First time every package runs together, and the first honest
accounting of how far Phase 0 actually is from a usable product.

### Added
- **`packages/messaging`** — §9.5 capture through receipt. `captureMessage()`,
  `openReceipt()`, `retentionOnOpen()`. **32 assertions.**
- **`db/test/0004_e2e_message.test.sql`** — the full chain in one suite:
  capture → artifact → intent → materialize → sweep → deliver → open → receipt.
  **16 assertions**, idempotent across re-runs.
- **`orphan_risk` view** — any pending intent whose artifact expires before it
  does. Belongs in monitoring, not only in a test.
- **MASTERFILE §20 Phase 0 review** — §20.1 what is built, §20.2 what does not
  exist, §20.3 honest assessment, §20.4 process findings, §20.5 exit order.
- **MARKUP screens 13–14** — record-and-review-before-send, and the receipt.
- **MARKUP §05 "Not yet real"** — six panels naming what produces these pixels
  (nothing, so far), so the document cannot be mistaken for a working product.

### The seam finding
- **The two retention clocks were unrelated, and nothing noticed.**
  `media_artifact.expires_at` (storage retention) and
  `delivery_intent.expires_at` (delivery validity) are set by different concerns,
  and no constraint relates them. If the artifact clock is shorter, the sweep
  delivers an intent whose blob has already been reaped and **the child opens a
  message that plays nothing** — worse than an undelivered one, because she sees
  it arrive.

  Fixed three ways: `captureMessage()` derives artifact retention *from* the
  resolved delivery instant plus `ARTIFACT_GRACE_DAYS = 7` and refuses to emit a
  shorter clock; the e2e suite asserts the ordering; and `orphan_risk` detects
  any pair that drifts. The detector was proven to fire by inserting a
  short-clocked artifact.

  This is the first bug found purely by wiring packages together — it was
  invisible inside either one.

### Also surfaced
- **Opening a message must not lengthen its retention.** The natural
  implementation sets `expires_at = opened + 30d`, which *extends* the life of an
  artifact whose unopened clock had less than 30 days left. `retentionOnOpen()`
  takes the minimum.
- **Receipts must use her zone at OPEN, not at capture.** A message recorded
  while she was in Texas and opened after she flew home reads Eastern, because
  that is the fact the parent wants. Tested both directions across a move.
- **Observers may send messages, deliberately.** `message` is not in the WRITES
  list, so §17.3 permits it. A reluctant parent saying goodnight is the outcome
  we want; recorded explicitly so it is not "fixed" later.

### Phase 0 status, stated plainly
**280 assertions across 8 suites, all green**, against real Postgres 16.14 and
the real LiveKit SDK. What is complete is the part hardest to retrofit: temporal
semantics, retention that cannot be indefinite by accident, authorization where a
prohibition is unreachable by construction, and exactly-once delivery under real
concurrency.

**No client exists. No auth. No object storage. No API. No push. No LiveKit
server. No native kiosk bridge.** That is the majority of remaining work by
volume, and it is mostly integration rather than novel design — a good position,
but not "nearly done." See §20.2 and MARKUP §05.

### Process
- Six increments, **seven false-greens**, all found by attacking our own
  verification. Tabulated in §20.4. Number seven happened while writing this
  entry: the ad-hoc verification command printed a **hardcoded** total —
  `echo "280 passing, 0 failing"` — while all four database suites had silently
  returned zero, the Postgres process having died. The claim was correct by
  coincidence and would have stayed correct-looking indefinitely.
- **`tools/verify.sh` added** as the single verification entry point. Totals are
  **computed** by summing what each suite reports, never asserted. A suite
  reporting zero assertions is a **failure**, not a pass. An unreachable database
  is a hard abort, not a skip. Proven to fail in both modes: database stopped →
  abort; a suite stubbed to report nothing → `NO ASSERTIONS RAN`, total drops to
  248, `NOT GREEN`.
- Standing rule extended: **the reporting is part of the test surface.** A
  hardcoded total in a build script is the same defect class as a test that
  cannot fail.

---

## [0.8.0] — 2026-07-26 — MARKUP becomes visual

Corrected interpretation. The user's intent for MARKUP was the product **made
visible** — what the end result looks like as choices are locked in — not a
written inventory.

### Added
- **`MARKUP.html` — canonical, visual.** Twelve rendered screens in device
  frames: child home, a banked message arriving, homework with shared
  annotation, the post-kiosk-defeat PIN gate, guardian home with the **live** Day
  Ribbon, the send-time guard, message banking, the medication double-dose block,
  the desktop exchange and bag manifest, the invitation, lock-mode disclosure,
  and the child's wants/needs view.
- **Every screen is annotated with the decisions that produced it** — 32 settled
  choices tagged in green, 6 prohibitions tagged in red. A screen is a
  consequence, not a sketch.
- **"Cannot be drawn yet" panel.** Six screens that are unbuildable because a
  decision is still open, each naming its §16.2 or §19 blocker — the product name
  (blocking launch, and carried by all twelve screens), the ping cap at the
  limit, the preservation prompt, the therapist view, sibling group calls, and
  the no-install web path. **This makes the cost of a deferred decision visible
  before it is made.**
- The day-cycle palette from VISUAL.html is reused as the product's actual design
  system, so the mockups and the architecture diagrams are visibly one thing.

### Changed
- **MASTERFILE §0 rewritten.** MARKUP is now defined as visual, with the rule:
  any increment that changes a user-facing surface, settles a §16.2 decision, or
  adds a prohibition must update MARKUP in the same turn.
- The generated schema inventory moved from `MARKUP.md` to
  **`scaffold/INVENTORY.md`** — a regenerable build artifact, no longer canonical.
  The generator and its coverage assertion are retained unchanged; `npm run
  markup` now writes to the new path. The canonical set stays at four.

### Surfaced by drawing it
- **The observer tier needed a second line of copy, not just a permission.**
  §17.3 grants read-only access, but the invitation screen has to *say* what
  watching means — "you can see her drawings and calendar; nothing is shared
  about you, and no one is told whether you opened this." A tier the reluctant
  parent cannot understand from the invite is a tier they will not accept.
- **The medication block needed attribution without blame.** Rendering it forced
  the exact wording: name the parent and the local time, state what is due next,
  and stop. Any additional framing reads as an accusation.
- **The banking screen must disclose cycling in the parent's own terms**
  ("30 messages for 181 nights, so they'll repeat about six times"), not as a
  ratio. The spec said "cycling is disclosed"; the screen shows what that
  sentence has to be.

---

## [0.7.1] — 2026-07-26 — MARKUP becomes the fourth canonical document

At the user's request, a complete part-by-part markup of the platform is now a
standing requirement.

### Added
- **`MARKUP.md` — fourth canonical document.** An exhaustive annotated inventory:
  14 tables, 140 columns, 63 constraints, 26 indexes, 12 functions, 2 views,
  1 RLS policy, 6 triggers, 1 enum, 5 packages with every export, every test
  group with its executed assertion count, 9 prohibitions with their enforcement
  mechanism, and 12 principles.
- **`scaffold/tools/generate-markup.mjs`** — MARKUP is **generated, never
  hand-maintained.** Authority order: live Postgres introspection → TypeScript
  sources → executed test output → MASTERFILE. A hand-written inventory of this
  size is stale the moment the next migration lands, and a stale inventory is
  worse than none because it is trusted.
- **Coverage assertion (MARKUP §0).** Parses every object declared in
  `db/migrations/*.sql` and confirms each appears in the document. The generator
  **exits non-zero** if anything is missing. Verified by temporarily adding an
  undocumented table: exit 1, and the missing object named. Exhaustiveness is now
  a checked invariant, not a claim.
- `npm run markup`.
- MASTERFILE §0 rewritten: four canonical documents, and any increment that adds
  a schema object, package export, or test group must regenerate MARKUP in the
  same turn.

### Findings in the generator itself
- **14 of 26 "platform functions" were `citext` extension internals**
  (`regexp_match`, `replace`, and friends). An inventory padded with a
  dependency's internals misrepresents the surface area it is meant to describe.
  Now excluded via `pg_depend` where `deptype = 'e'`; the true count is 12.
- **Test counts were wrong in two of four packages.** Regex-counting `check(`
  call sites reported 34/37 for delivery and 63/67 for session, because some
  calls span lines the pattern did not match. Group names and counts now come
  from **executing** each suite and parsing its own output; the document reports
  187, matching the real run exactly. A generated inventory that misreports test
  counts is worse than one that omits them.
- `packages/child-lock` has no test directory of its own — it is covered by the
  session-runtime suite. The generator now says so explicitly rather than
  rendering a silent gap.

---

## [0.7.0] — 2026-07-26 — session runtime + child lock

Fourth increment, and the first with a real external dependency
(`livekit-server-sdk` 2.17.0). Token assertions are made against the decoded
JWT payload, so they describe what LiveKit actually receives.

### Added
- **`packages/session-runtime`** — §5.19. Opaque room identity, grant
  derivation, mint-time authorization.
- **`packages/child-lock`** — §5.20. Kiosk defeat state machine.
- **67 assertions passing** across both.

### Security invariants established (§5.19)
- **I1** Room names are 24 random bytes. `roomNameLeaks()` runs as a **runtime
  assertion at session creation**, not only in tests — 2000 generated names,
  zero collisions, no identifier substrings.
- **I2** `roomJoin` scoped to exactly one room; all seven admin-class grants
  asserted absent on the wire; `canUpdateOwnMetadata: false`.
- **I3** `identity` is the authenticated principal.
- **I4** `can('call', …)` re-runs at mint time, **before** the participant list
  is consulted.
- **I5** 600-second TTL.

### Findings

- **A stale participant list was an authorization bypass.** The natural
  implementation checks "is this user in `authorizedUserIds`" and mints. That
  lets a parent whose edge has since closed, been restricted by a protective
  order, expired, or dropped to ladder step `none` rejoin a room they were
  legitimately added to earlier. `can()` now runs first and membership second;
  all five revocation paths are tested, including a deliberately poisoned
  participant list.

- **§17.3 observer tier was underspecified and would have shipped wrong.** The
  v0.4.0 wording — "see drawings, see the calendar, watch a recorded message" —
  says nothing about live calls, and the obvious implementation gives every
  guardian a publishing grant. An observer with a live camera and microphone is
  participating, which is the opposite of what the tier offers a reluctant
  parent. Observers are now `canPublish: false`, `canPublishData: false`,
  subscribe only.

- **The dangerous kiosk-defeat case is not the one it looks like.** A child
  reaching the app switcher is minor. The severe case is a parent escalating to
  guardian scope, handing the device back, and *then* the kiosk being defeated —
  leaving live guardian scope in a child's hands. Escalation is now dropped
  unconditionally on both lock-task exit and backgrounding, before anything else
  happens, and that case is audited distinctly
  (`kiosk_defeated_while_escalated`) and notifies the other guardian.

- **Losing app focus does not invalidate a JWT.** A defeated kiosk leaves a
  valid LiveKit token on the device for the remainder of its TTL. Defeat and
  backgrounding now both trigger server-side token revocation, and TTL was set
  at 600s specifically to bound this window.

### Resolved tension
- **§10.5 vs §5.15.** Recording is off by default and a child cannot consent —
  yet a court-ordered supervised visit *is* recorded. Recording under a
  supervision order is lawful, is disclosed to every participant including the
  child in age-appropriate language fixed in code, and is never silent.
  `monitored` is explicitly *not* recorded; the professional joins unannounced.

### Notes
- Break-glass (§8.3) clears the cooldown so a 9 p.m. call is not lost, but lands
  on `child_home` and grants **no** escalation. Verified.
- `canRender()` is deny-by-default: an unlisted surface is unreachable.
- Escapable lock modes are **disclosed at setup** rather than hidden. A parent
  who believes the device is sealed will make worse decisions than one who knows
  it is not.

---

## [0.6.0] — 2026-07-26 — family graph + session context

Third increment. The layer that makes P6 and P7 real in the *product*, not only
in the database. Two findings, one of which was a live crash bug.

### Added
- **`packages/family-graph`** — §5.17–5.18. **59 assertions passing.**
  - `can()` — pure authorization over resolved edges, with P7 checked
    unconditionally before edge resolution and P6 second.
  - `withSession()` / `withSystemSession()` — the only writers of
    `app.role` / `app.child_id` / `app.user_id`.
  - `isSingleGuardianViable()` — §17.1 enforced as a testable predicate.
- **`db/migrations/0003_session_context.sql`** — `current_child()`,
  `current_role_name()`, `current_actor()`, the `effective_guardianship` view,
  `actor_has_edge()`, `exportable_artifacts()`, and the hardened P7 policy.
- **`db/test/0003_session.test.sql`** — 14 assertions, idempotent, self-reporting.

### Findings

- **Empty-string GUC was a crash, not a denial.**
  `current_setting('app.child_id', true)::uuid` returns NULL when the GUC is
  *unset* but **raises `invalid input syntax for type uuid: ""`** on an empty
  string. A connection pool that sets both GUCs unconditionally — the normal
  pattern, and the one `withSession()` implements — therefore turned every
  journal read into a 500 rather than an empty result. Fail-crash instead of
  fail-closed. Wrapped in `NULLIF(...)`, verified as a denial.

  | `app.child_id` | before 0003 | after |
  |---|---|---|
  | unset | 0 rows | 0 rows |
  | `''` | **ERROR 22P02** | 0 rows |

- **Sibling traversal was an open lateral-privilege path.** `sibling_link`
  creates a graph edge between children; any authorization query that joined
  through it would grant a guardian of one sibling access to the other.
  `actor_has_edge()` is scoped to `guardianship` alone, and both suites now test
  that Dad — guardian of Maya, not Eli — reaches Maya's archive and *not* Eli's,
  despite a live `sibling_link` between them.

### Hardening
- P7 verified end-to-end as a **non-superuser table owner** with full session
  context: 0 rows. Maya reads her own entry; Eli reads only his.
- Expired sitter tokens excluded from `effective_guardianship` and denied by
  `actor_has_edge()`.
- Ladder step `none` blocks contact while preserving a coordinator's read.
- `observer_only` (§17.3) blocks all writes, permits reads and calls — so a
  reluctant parent can watch without participating.
- Raw export allowed off the court tier and through an observer edge
  (principle §2.11); certified export gated (§16.1 #3).

### Fixed
- **`0003_session.test.sql` was not idempotent.** `child_journal_entry` and
  `media_artifact` have no natural unique key, so a second run doubled the
  fixtures and three assertions failed against correct code. Fixtures now clear
  first; verified green across three consecutive runs.
- **`0003` used raw value output read by a shell parser.** The parser miscounted
  and reported 8 failures against a suite that was entirely correct. Replaced
  with `assert_eq` / `assert_raises` emitting PASS/FAIL directly, matching every
  other suite. A test whose result must be eyeballed is a test that gets misread.
- `DROP ROLE app_owner` failed whenever the role owned objects in another
  database, aborting the suite. Now create-if-absent.
- **Fixture used `ON CONFLICT DO NOTHING` where it needed to reopen.** Because
  `guardianship` carries `UNIQUE (child_id, user_id)`, a closed edge left by an
  earlier suite silently blocked the fixture's live edge — `actor_has_edge()`
  correctly returned false and two assertions failed against correct code. This
  is precisely the constraint recorded in the v0.4.1 notes: restoring a
  previously revoked parent must **reopen the existing row**, not insert a new
  one, so their history cannot fork. The fixture now does that, which means the
  suite exercises the reunification path rather than tripping over it.

### Process
- **Three increments, three instances of the same defect class**: assertions
  counting *globally* against a database other suites also write to. v0.5.0 hit
  it in the concurrency driver, v0.6.0 twice more. Standing rule adopted: every
  assertion scopes to rows the suite itself created, and every DB suite is
  verified across an **order-independence matrix** — alone, after each sibling
  suite, and re-run on a dirty database. All four orderings green.
- Cumulative false-greens found by attacking our own tests: **five.** On this
  project the tests need the same adversarial treatment as the code, because a
  test that cannot fail is indistinguishable from one that passes.

---

## [0.5.0] — 2026-07-26 — delivery engine

Second increment. The engine that turns a policy into a delivered message,
built and attacked. Three findings, two of them design-level.

### Added
- **`packages/delivery-engine`** — §6.3–6.5 implemented as pure functions over
  the child's timezone timeline and day-parts, so the entire decision surface is
  testable without a database. **37 assertions passing.**
  - `materialize()` — all six policies.
  - `gate()` / `recipientContext()` — two-sided notification gate.
  - Day-parts that wrap midnight (`asleep` 21:00 → 06:30) handled explicitly.
- **`db/migrations/0002_delivery_sweep.sql`** — `claim_due_intents()`,
  `expire_stale_intents()`, `invalidate_for_child()`, invalidation triggers, and
  the parent-facing `batch_progress` view.
- **`db/test/run_concurrency.sh`** — 8 real parallel workers racing a 500-intent
  due queue. Result: 500 delivered, 0 double-fired, 0 left behind, 50
  future-dated intents untouched.
- **§4.8 Delivery guards** — the constants and rules table.

### Findings

- **Retroactive delivery was possible.** Nothing prevented a missed night from
  firing whenever the sweep next ran. After an outage a child could receive a
  week of accumulated goodnight videos in one burst at 3 a.m. Added
  `PAST_GRACE_MINUTES = 120`: late enough to absorb a sweep hiccup or a DST
  shift, not late enough to dump history.

- **`at_daypart` and `on_local_date` needed opposite past-handling.** "Next
  bedtime" is an open promise and must roll forward; "the night of June 1st" is
  a specific promise and must expire rather than move. Conflating them either
  silently re-dates a banked message or permanently drops a recurring one.
  An *explicitly dated* `at_daypart` also does not roll.

- **The invalidation trigger was row-level and quadratic-ish.** Seeding 10
  day-parts against a 550-intent batch produced ~5,500 redundant UPDATEs, and
  bulk timezone imports would have been worse. Replaced with statement-level
  triggers using `REFERENCING NEW TABLE` / `OLD TABLE`. Measured after the fix:
  **1 trigger invocation, 50 rows rewritten** for the same bulk insert.

- **The concurrency driver reported PASS on empty values.** With the database
  unreachable, `[ "$delivered" = "$due" ]` compared `""` to `""` and passed —
  the same false-green class as the v0.4.1 superuser finding. Every assertion
  now routes through helpers that treat a non-numeric result as a hard abort.

- **Unbounded defer chain.** A gate that defers on every attempt could postpone
  a message forever, which presents as silence rather than as an error. Capped
  at `MAX_DEFERS = 3`, then **fails open and logs**.

### Fixed
- **Concurrency assertions counted globally instead of per-batch**, so the suite
  passed alone and failed when run after the constraint suite against a shared
  database — the constraint fixtures create two valid intents for the same child.
  Order-dependent tests are unreliable tests. Every batch assertion is now
  scoped to `batch_id`, and both orderings verified green.
- Seed ordering in `0002_seed.sql`. Day-parts were inserted after the intents,
  so the invalidation trigger wiped the queue the sweep was meant to drain. The
  trigger was correct; the fixture was wrong. Day-parts now come first, with a
  comment saying why.

---

## [0.4.1] — 2026-07-26 — Phase 0 hardening

First code executed against real infrastructure. Migration and time engine both
green; two security findings, one of them serious.

### Security

- **P7 was unenforced. `ENABLE ROW LEVEL SECURITY` alone does not stop the table
  owner** — Postgres owners bypass RLS by default, and applications
  overwhelmingly connect as the owner of their own schema. The journal policy
  was decorative in the most common deployment configuration. Fixed with
  `FORCE ROW LEVEL SECURITY` on `child_journal_entry` and, pre-emptively, on
  `expense` (P6, same failure mode, Phase 3).

  Measured before and after against Postgres 16.14:

  | | table owner reads journal |
  |---|---|
  | `ENABLE` only | **1 row — breached** |
  | `ENABLE` + `FORCE` | 0 rows — enforced |

- **The original P7 test reported a false green.** It ran the owner probe as
  `postgres`, a superuser — and superusers bypass RLS *even with FORCE*. A test
  that cannot fail proves nothing. Rewritten to use a dedicated
  `NOSUPERUSER NOBYPASSRLS` owner role, which is the realistic deployment shape.

- **New `db/DEPLOYMENT.md`.** The database role model is now documented as a
  safety control rather than an ops detail: application role must be
  `NOSUPERUSER NOBYPASSRLS`; every RLS table needs both ENABLE and FORCE;
  `app.role` / `app.child_id` must be set by the connection pool from the
  authenticated session and never derived from request input, or P7 degrades to
  a parameter-tampering bug; GUCs must be `SET LOCAL` or reset on pool checkout,
  since a retained `app.child_id` is a cross-tenant read.

### Added
- `db/migrations/0001_phase0_init.sql` — executes clean against Postgres 16.14.
- `db/test/0001_constraints.test.sql` — **24 adversarial probes, 24 passing.**
  Every guarantee is attacked rather than asserted: overlapping timezone
  intervals and ladder steps (GiST exclusion), reversed and self-referential
  sibling links, artifacts with neither retention clock nor preservation,
  preserved-but-unattributed artifacts, closure without a reason, every delivery
  policy missing its target, NULL `expires_at`, backwards batch windows, and SMS
  channel without a phone number.
- `packages/time-engine/` — §6.1–6.2 with the six golden fixtures. **24 passing.**
- Scaffold `README.md`, `package.json`, `npm run test:golden`.

### Fixed
- `current_setting('app.role')` → `current_setting('app.role', true)` in both
  policies. The one-argument form **raises** when the GUC is unset; the
  two-argument form returns NULL, so an unconfigured session sees zero rows.
  Fail-closed, deliberately.

### Notes
- `guardianship UNIQUE (child_id, user_id)` means a closed edge cannot be
  re-created for the same pair — restoring a previously revoked parent requires
  reopening the existing row, not inserting a new one. Correct for succession
  and audit, but the reunification flow must be written against it. Recorded in
  §19 rather than changed.

---

## [0.4.0] — 2026-07-26

Three structural holes closed. Two blocking decisions resolved provisionally.
Phase 0 unblocked.

### Added

**§17 Adoption and asymmetric use** — the existential gap. Every prior version
assumed a populated family graph on day one, which is the failure mode that kills
products in this category.
- §17.1 **Single-guardian mode.** No feature may be gated on a second guardian
  existing. Promoted to principle **§2.12**.
- §17.2 Invitation framing — "Maya's other house", never "co-parenting account";
  no court-tier mention in the invite path; **no read receipts on an invitation**,
  because that is pressure.
- §17.3 **Observer tier** — read-only acceptance for a reluctant parent, invisible
  to the other guardian.
- §17.4 Third-party invitation from mediator, coordinator, caseworker, therapist,
  court, or grandparent. Primary channel for the institutional segment.
- §17.5 Permanent asymmetry as a supported end state. No "complete your family"
  prompts.

**§5.14 Siblings** — previously two children of the same parents were two
disconnected trees. `sibling_link` (kind, `contact_allowed`, `travels_together`)
with canonical ordering; `exchange.cohort_id` for shared manifests.
**Sibling-to-sibling contact is a right that survives the separation of their
guardians.** One-on-one session scoping made a first-class concept.

**§18 Succession and bereavement** — the shadow of P1.
- §5.16 `succession_directive`, recorded by the parent about themselves while
  living. `continue` / `stop` / `deliver_all`. **Nobody else may create, alter,
  or override it** — not the surviving guardian, not a court, not support.
- §18.1 Guardianship edges **close** rather than delete; authored artifacts
  auto-preserve; default on no directive is `stop` + preserve + custodian
  handoff.
- §18.2 **Posthumous restatement of P1.** A grieving child is the most
  sympathetic possible case for the most harmful possible feature.
- §18.3 Death of a child — single flag halts every automated surface; human
  support contact only.

**§5.15 Contact ladder** — five steps (`none` → `supervised` → `monitored` →
`time_limited` → `open`), advanced only by coordinator, therapist, or caseworker;
guardians may always hold or step down. GiST exclusion prevents overlap.

**§19 Deferred register** — eight items recorded so they are neither
re-litigated from scratch nor silently dropped. §8.5 child-device-reality stub.

**§2 Principles** — **§2.11 the archive is never held hostage**; **§2.12 one
parent is a complete product.**

**Roles** — `foster_parent`, `caseworker`, `therapist` added to `guardianship.role`.

### Changed
- **§16 restructured** into 16.1 Resolved and 16.2 Still open.
  - **#2 Teen privacy tiers RESOLVED (provisional).** `transparent` 0–12,
    `graduated` 13–15, `autonomous` 16–majority. Tiers advance on birthday and
    **cannot be reversed downward by a guardian**; both guardians together may
    delay once by ≤12 months with a logged reason. The child is told. **P7 has no
    age exception** — a 9-year-old's diary is a diary.
  - **#3 Court export RESOLVED (provisional).** Split by artifact: raw export
    free/unlimited/all tiers/post-cancellation; certified tamper-evident export
    on the Court tier with **one free per guardian per rolling 12 months.**
- **Phase 0 scope** now includes single-guardian mode, `sibling_link`, and
  `guardianship.closed_at` — three schema-only items ahead of their features.
- §16.2 grew two new open items (#10 foster consent model pending counsel,
  #11 therapist visibility scope).

### Removed
- **`guardianship.supervised boolean`.** A boolean cannot express reunification.
  Superseded by `contact_ladder` (§5.15). This is a breaking schema change with
  no shipped data, which is exactly why it is happening now.

### Fixed
- Guardianship deletion semantics. Deleting an edge would have destroyed a
  deceased parent's history along with their access. Edges now close with a
  reason.
- **§6.2 `resolveWallClock` — nonexistent-time detection was broken.** The
  reference implementation branched on `dt.isValid`, but Luxon does **not**
  invalidate a nonexistent local time; it silently maps it forward across the
  DST gap. The branch never fired, so the anomaly was never detected and never
  logged — exactly the "library chooses for you" failure the function exists to
  prevent. The *instant* returned was coincidentally correct, which is what
  makes this class of bug survive code review. Replaced with a round-trip
  check: if formatting the result back to local wall clock does not reproduce
  the requested time, the time did not exist. **Found by golden fixture F1 on
  its first execution.**

---

## [0.3.0] — 2026-07-25

Scope expansion. The transactional product becomes a durable one: an archive with
an owner, a coordination layer, a designed exchange, and child-initiated contact.
Nine prohibitions recorded permanently.

### Added

**Prohibitions register — §2.1**
- **P1** Synthetic or cloned parent voice/likeness — banned at every tier.
- **P2** Punitive streaks or engagement scoring shown to a child — banned.
- **P3** Live location sharing — banned; arrival events only.
- **P4** Purchase mechanics on the wants list — banned (was a §9.3 note, now a
  numbered prohibition).
- **P5** Behavioral advertising, data brokerage, child data for model training —
  banned.
- **P6** Any financial or expense surface visible to a child role — banned,
  RLS-enforced.
- **P7** Parent access to the child's private journal at any tier, including
  guardian escalation — banned, RLS-enforced, with an explicit carveat that the
  correct response to child danger is a human and a crisis path, not a window.
- **P8** Deletion or editing of parent↔parent log entries — banned.
- **P9** Unsolicited resurfacing of pre-separation archive material — banned;
  "on this day" is opt-in with per-era mute.
- Each prohibition carries an **"arrives disguised as"** column, because each
  will be re-proposed in good faith with a sympathetic framing.

**Archive — §9.8, §5.6**
- `media_artifact` table with `preserved` / `preserved_by` / `era_tag` and a
  `retention_or_preserved` CHECK constraint making "indefinite by accident"
  unrepresentable.
- §9.8.2 **Year Book** — annual auto-compilation from preserved artifacts,
  printable. Revenue line, retention hook, and emotional payoff in one feature.
- §9.8.3 "On this day" — opt-in, per-era mute.
- §9.8.4 **Majority handover** — at the child's age of majority the archive
  transfers to them, guardian read access ends, export is generated,
  `handed_over_at` set, irreversible.
- Principle **§2.10**: the archive belongs to the child; parents are custodians.

**Message banking — §9.5, §5.7, §6.5**
- `intent_batch` table; `batch_id` / `batch_seq` on `delivery_intent`.
- `bankMessages()` — fans one recording set across N child-local dates as
  `on_local_date` intents. **Zero new scheduling machinery**; the §4 engine
  already resolves these correctly across DST, travel, and custody zone changes.
- Cycling disclosed to the parent; batch payloads archive-tier by default;
  revocation affects the undelivered remainder only.
- §8.2.8 — the child is never shown the mechanism, the counter, or a
  "pre-recorded" label.

**Coordination layer — §9.6, §5.8–5.11**
- **Medication handoff log** with a `UNIQUE (medication_id, local_date, slot)`
  constraint keyed on **child-local** date — the exchange-day double-dose guard.
  `recordDose()` in §6.7 surfaces collisions to the adult with attribution and
  local time, never to the child and never as blame.
- Shared medical record; **emergency card** (offline, sitter-readable, Phase 1);
  school layer (guardian-upload only, keeping FERPA out of scope).
- **Expense ledger** with RLS policy granting no child access.

**The exchange — §9.7, §5.10**
- Bag manifest with `essential` flagging and pre-exchange reminders.
- Arrival ping as an **event**; `exchange` has no coordinate column and must
  never acquire one (P3).
- One-tap running-late with immutable ETA logging.
- Transition warnings for the child, in sleeps.

**Child agency — §9.9, §5.12, §6.6**
- "Call me when you can" — child-initiated ping, `when_reachable` against the
  *recipient*, rate-limited to 3/parent/child-local day, **silently absorbed**
  over the limit so no child is told they have used up contact with a parent.
- Private journal, RLS-restricted to the owning child role with deliberately no
  guardian policy and no API route.
- "Teach me something" module — roles inverted.
- Rituals — recurring, day-part anchored, never scored.

**Accessibility and inclusion — §8.4**
- Neurodivergent visual schedule strip built from existing `day_part` data.
- Captions on live calls and every async artifact (`caption_key`).
- Bilingual live caption translation.
- Pre-reader, dyslexia, and low-bandwidth affordances.
- **SMS bridge** for parents without smartphones — incarcerated, elderly,
  device-restricted, or poor. If the away parent cannot participate, the product
  has failed at its only job.

**Roles — §5.1, §8.1**
- `guardianship.role` extended: `step_parent`, `sitter` (time-boxed via
  `expires_at`), `coordinator` (parenting coordinator / guardian ad litem,
  read-only, no child-facing surface).
- `guardianship.restricted` flag for protective orders.

**Together activities — §9.10**
- Co-listen, cook-along, watch-together, read-together as session modules.

**Other**
- §8.2.9 conversation starters drawn from the archive and calendar.
- §10.7 majority handover framed as the retention terminus — the defensible
  answer to a regulator on indefinite retention.
- §10.8 SMS bridge constraints: summaries and notifications only, never media,
  never the journal, never the emergency card.
- §13 new metrics: batch coverage, **dose collisions prevented**, archive depth.
- §14 **Court tier** split out from Family tier; Year Book as à-la-carte print.
- §12.1 — the single early schema dependency, called out explicitly.

### Changed
- **Roadmap restructured.** Message banking, emergency card, and child ping pulled
  forward to Phase 1 — all three are near-free on the Phase 0 engine and carry
  disproportionate emotional weight. Expense ledger and coordinator role land in
  Phase 3 with the court tier.
- **§7 Retention schedule** extended to cover banked payloads, medication events,
  exchanges, expenses, preserved artifacts, and the journal.
- §10.2 — preservation elections require **either** guardian, not both.
  Requiring consensus would mean conflict destroys the archive.
- §3.1 — activity module list extended; `archive` added to §3.2 as a first-class
  service rather than a storage concern.
- §16 Open decisions expanded from 6 to 9, with a blocking-phase column. Items 2
  and 3 now block Phase 0.

### Fixed
- **§12.1 latent data-loss bug.** The v0.2.0 retention schedule deleted video
  messages 90 days after open with no archival tier. Any Year Book built later
  would have had nothing to compile. `media_artifact.preserved` and the
  `retention_or_preserved` CHECK now land in the **Phase 0** migration, two
  phases ahead of the feature that consumes them.
- §4.6 — added a golden-test fixture for a 180-night banked batch spanning both
  DST transitions. A single stale batch can mis-deliver every night in a
  deployment window.

---

## [0.2.0] — 2026-07-25

Market scope narrowed to the United States. Temporal architecture specified in
full and promoted to foundational infrastructure.

### Added
- **§4 Temporal architecture** — the defining subsystem.
  - §4.1 Four-frame doctrine: child-local, actor-local, order-time, instant.
    Child-local declared canonical.
  - §4.2 Timezone modelled as a **timeline** (`child_tz_interval`), not a column.
    Zone flips at the custody exchange event, not at midnight.
  - §4.3 **Day-parts** semantic layer — features address time by meaning
    (`bedtime`, `after_school`) rather than by clock. Stored as wall-clock `time`.
  - §4.4 Six **delivery policies**: `immediate`, `at_instant`, `at_daypart`,
    `on_local_date`, `when_reachable`, `on_event`.
  - §4.5 Materialization + invalidation model. `scheduled_at` declared a cache.
  - §4.6 US temporal edge-case matrix and five mandatory golden-test fixtures.
  - §4.7 Feature-level time semantics table.
- **§5.2 / §5.3** Schema for `child_tz_interval`, `day_part`, `delivery_intent`.
  Non-overlap enforced by a GiST exclusion constraint.
- **§5.4** `custody_order.order_tz` — explicit zone binding. "Friday 6:00 PM" is
  meaningless without it and defaulting to the server zone is a courtroom risk.
- **§6** Reference implementation: `childZoneAt`, `resolveWallClock` (both DST
  pathologies handled explicitly), `materialize`, two-sided notification `gate`,
  `recipientContext` for the send-time guard.
- **§7.2** Time-engine API surface, including `/ribbon` and `/overlap`.
- **§8.2** Closeness UI patterns — dual clock, **Day Ribbon** (signature
  element), receipts in child-local frame, countdowns in "sleeps",
  ambient texture, send-time guard.
- **§10** United States compliance section: amended COPPA Rule (effective
  22 Apr 2026), retention schedule per payload kind, dual-guardian consent state
  machine, app-store age-verification integration, state design codes,
  all-party recording consent, FERPA avoidance.
- **§13** Metrics defined on **child-local calendar day** boundaries.
- **§16** Open decisions register.

### Changed
- **Roadmap** — time engine promoted from later polish into **Phase 0**.
  Rationale: retrofitting timezone semantics onto shipped data is a rewrite,
  not a migration.
- **§2 Principles** — added "the child's clock is canonical" as principle 2.
- **§5.3** `delivery_intent.expires_at` made `NOT NULL`, tying the async engine
  directly to the COPPA retention ban.
- **§14 Business model** — "per family, not per parent" elevated from a note to
  the stated competitive attack.

### Removed
- **UK and EU compliance scope.** Age Appropriate Design Code (UK), GDPR, and
  GDPR-K obligations dropped from the specification. Retained only as a design
  reference where a standard happens to be good practice.
- International launch considerations. Non-US *markets* are out of scope; note
  that non-US *actors* (deployed military parents) remain explicitly in scope.

### Fixed
- Recurrence storage corrected: recurring events store **local wall clock + IANA
  zone + RRULE**, materialized at query time. Storing recurring events as UTC
  instants guarantees a one-hour drift twice yearly.

---

## [0.1.0] — 2026-07-25

Initial architecture and product thesis.

### Added
- **§1 Product thesis** — the child is a first-class user, not a subject of
  record. Competitive gap identified between court-oriented co-parenting tooling
  (OurFamilyWizard, TalkingParents, AppClose, 2Houses, Custody X Change) and
  child-facing co-presence tooling (Caribu, Messenger Kids). Amazon Glow recorded
  as the hardware-dependency cautionary tale.
- **§1.1 Positioning** — reframed from "divorce app" to "staying present."
  Segment table: military deployment, travel-heavy work, long-haul trucking,
  incarcerated parents, hospitalization, separation, distant grandparents.
- **§2 Product principles** — nine constitutional rules, headed by "the child
  never sees parental conflict."
- **§3.1 Session runtime** — the core architectural bet. Video, games, and
  homework are **activity modules on one synchronized runtime**, not three
  parallel features.
- **§3.2 Service map.**
- **§5.1 Family graph** — child modelled as **root entity**; guardianship as an
  **edge** carrying scope, validity window, supervised flag, and court reference.
  Rejected `account → family → children`, which breaks on separation, remarriage,
  or a protective order.
- **§9.1 Homework** — photo → deskew → OCR → shared annotation, plus
  **"hint, don't solve"** mode coaching the *parent* Socratically.
- **§9.2 Games** — runtime not studio; turn-based first; co-op over competitive.
- **§9.3 Wants/needs** — strictly separated; needs claimable; wants carry no
  price and no buy button; claim state invisible to the child.
- **§9.4 Calendar** — two-layer split between child view and guardian/custody
  view; change requests as a workflow.
- **§8.3 Child lock** — OS-level enforcement (Android Screen Pinning, Windows
  Assigned Access, iOS Guided Access), shuffled PIN keypad, break-glass path.
- **§11 Technology stack** — Flutter, LiveKit, NestJS, PostgreSQL with RLS,
  on-device ML Kit OCR, passkeys, CallKit/full-screen intent.
- **§13 Metrics** — north star is relationship continuity; "gap coverage"
  defined.
- **§14 Business model** — free / family / institutional tiers.
- **§15 Safety** — threat model includes surveillance by a controlling ex and
  contact in violation of a court order.
- **§0** Standing three-document canonical rule established.

---

[Unreleased]: #unreleased
[0.3.0]: #030--2026-07-25
[0.2.0]: #020--2026-07-25
[0.1.0]: #010--2026-07-25
