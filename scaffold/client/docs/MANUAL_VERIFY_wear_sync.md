# Manual verification — Galaxy Watch6 companion sync (§21.5)

**Status: never run.** No Wear OS emulator has ever been installed and no
physical Watch6 has ever been paired in this environment, in any pass, per
a standing, previously-flagged disk-space constraint (see
`WearSyncBridge.kt`'s own header: ~7GB free, no `~/.gradle/caches`
directory yet for this user profile — an Android/Gradle toolchain cost
specifically, not a Flutter/Dart one). This document exists so that
whoever eventually has the disk headroom (or a second machine, or a
cleared cache) has a real, code-grounded procedure to run rather than
inventing one from scratch — matching this repo's own established
`MANUAL_VERIFY_call_lock_task.md` precedent for exactly this class of gap
(a real feature, code/build-verified, that only a live device can actually
confirm).

**What is real without a device, and what genuinely isn't:**
- `flutter analyze` (clean, whole client) and `flutter test` (passing,
  whole client — see `wear_sync_channel_test.dart` and
  `child_home_live_test.dart`'s own `_FakeWearSyncChannel`) exercise the
  real Dart-side `MethodChannel` handler-registration mechanism, just not
  against a real native counterpart.
- `packages/transport/test/transport.test.mjs`'s own "K · WEAR SYNC BRIDGE
  CONTRACT" group (real, DB-free, `node`-run assertions) proves the
  channel name, method names, and the `/olive/now` / `/olive/call-dad`
  path+key literals agree byte-for-byte across `wear_sync_channel.dart`,
  `WearSyncBridge.kt`, and `MainActivity.kt` — so a typo on any one side
  would be caught here, not just at runtime.
- Neither of the above can catch what only a real Data Layer round trip
  can: whether `event.dataItem.uri.path` / `event.path` really equal
  `/olive/now` / `/olive/call-dad` once actually exchanged between real
  nodes (rather than some prefixed variant), and whether
  `NodeClient.getConnectedNodes()` actually resolves the phone as
  connected in every real pairing state (mid-reconnect, Bluetooth briefly
  down), not just the steady-state case the code assumes.
- `WearSyncBridge.kt`/`MainActivity.kt` were also NOT recompiled this pass
  (`:app:compileDebugKotlin` / `:wear:compileDebugKotlin` not re-run) — a
  materially weaker claim than "BUILD SUCCESSFUL," stated plainly in both
  files' own headers, not glossed over.

Run this after any change to: `client/lib/wear_sync_channel.dart`,
`client/android/app/.../WearSyncBridge.kt`,
`client/android/wear/src/main/kotlin/.../MainActivity.kt`, or
`client/lib/child_home_live.dart`'s `_syncWear()`/`listenForCallDad` wiring.

## What this actually tests

Two independent directions over the Wear Data Layer API, both real code as
of this pass, neither ever device-confirmed:

1. **Phone → watch (state sync):** `child_home_live.dart`'s `_syncWear()`
   calls `WearSyncChannel.syncSleepsUntilHandover(int)` whenever it holds a
   real, non-demo `sleepsUntilHandover` value → `WearSyncBridge.kt`'s
   `register()` receives it over the `com.olivebranch.olive_client/wear_sync`
   `MethodChannel` and calls `Wearable.getDataClient(context).putDataItem()`
   on path `/olive/now`, key `sleepsUntilHandover` → the watch's
   `MainActivity.onDataChanged()` (registered `onResume`/removed `onPause`)
   updates the Compose `MutableState` `OliveWatchGlance` reads.
2. **Watch → phone (an event, not a state sync):** tapping "Call Dad" on
   the watch calls `sendCallDadMessage()` → `Wearable.getMessageClient
   (this).sendMessage()` on path `/olive/call-dad` to every connected node
   → `WearSyncBridge.kt`'s `MessageClient.OnMessageReceivedListener`
   forwards it to Dart via `invokeMethod(M_CALL_DAD_REQUESTED, null)` →
   `WearSyncChannel.listenForCallDad`'s registered handler fires →
   `LiveChildHomeScreen` opens the SAME real
   `CallScreen(who: 'ivy', displayName: ...)` the phone's own existing
   "Call Dad" button already opens — **not** `guardian_more.dart`'s
   guardian-only `POST /v1/children/:childId/calls` route, which
   `server/routes.mjs` refuses for a child session by design
   (`child_cannot_start_call`, proven in `server/test/calls_route.test.mjs`).
   See `WearSyncBridge.kt`'s own header for the full reasoning on why this
   is the honest target.

Both directions are deliberately fire-and-forget with no ack path back —
`putDataItem()`'s success callback means "the Data Layer accepted it
locally," not "the watch received it"; `sendMessage()`'s only user-facing
feedback is the non-committal "Reaching Dad…" line, never a checkmark or
"Called Dad." Confirming actual delivery is exactly what this procedure is
for.

## Setup

0. **Disk space first.** A fresh Gradle invocation for this module
   downloads the full Gradle/AGP/Kotlin/Compose toolchain plus every
   dependency (`play-services-wearable`, androidx wear compose) — confirm
   real free space before starting, not mid-build. If space is tight,
   clear old `~/.gradle/caches` entries or build on a machine that isn't
   also running this repo's other work.
1. A real Galaxy Watch6 (or compatible Wear OS device/emulator) actually
   **paired** to the test phone via the Galaxy Wearable / Wear OS app —
   this is an OS-level pairing step outside Olive Branch entirely; confirm
   it's genuinely paired (not just Bluetooth-connected) before touching
   this app.
2. `adb devices -l` should show both the phone and the watch (Wear OS
   devices are `adb`-addressable once developer options + ADB debugging
   are enabled on the watch itself, same as any Android device).
3. Build and install BOTH modules fresh, not just the phone app —
   `flutter build apk --debug` alone only builds `:app`. A real Gradle
   invocation covering `:wear:assembleDebug` is needed for the watch
   module; confirm the resulting `wear-debug.apk` actually installs on
   the watch (`adb -s <watch> install -r
   build/wear/outputs/apk/debug/wear-debug.apk`), not just that the phone
   side builds.
4. `adb -s <phone> logcat -c` and `adb -s <watch> logcat -c` immediately
   before testing — capture both devices, since each direction's failure
   mode is only visible on one side.

## Procedure

**Direction 1 — phone → watch (sleeps-until-handover sync)**

1. Launch Olive Branch on the phone, choose **"My child's device"**, let
   `LiveChildHomeScreen` fetch a real (non-demo) `sleepsUntilHandover`
   value.
2. On the watch, launch the Olive companion app (standalone-launchable —
   it does not require the phone app to already be running first).
   Confirm it initially shows `DEMO_SLEEPS_UNTIL_HANDOVER` (3) if this is
   the watch's first launch since pairing, or whatever value it last
   received — this is real, honest, reachable state per `MainActivity
   .kt`'s own header, not a bug.
3. Within a few seconds of the phone screen loading, confirm the watch's
   own display updates to the phone's real value. Check `adb -s <watch>
   logcat -d | grep -i "onDataChanged\|DataClient"` for the real Data
   Layer event arriving.
4. On the phone, force a second sync of the exact same integer value
   (e.g., background and re-foreground `LiveChildHomeScreen` on the same
   day, so `sleepsUntilHandover` hasn't actually changed). Confirm the
   watch still receives an update — `WearSyncBridge.kt`'s own
   `syncedAtMillis` timestamp field exists specifically so two identical
   integer syncs still register as a real DataItem change; if the watch
   does NOT update on a same-value re-sync, that timestamp mechanism has
   regressed.
5. `adb -s <phone> logcat -d | grep -i "put_data_item_failed"` → should be
   **absent**. A hit here means the phone-side `putDataItem()` call itself
   is failing (Play services unavailable, no watch paired at the OS
   level), not a code bug in this app.

**Direction 2 — watch → phone ("Call Dad")**

6. On the watch, tap **"Call Dad."** Confirm the non-committal "Reaching
   Dad…" feedback line appears immediately (this is real regardless of
   whether the phone ever receives it — it only confirms the local
   `sendMessage()` call was made).
7. On the phone, confirm the SAME real `CallScreen(who: 'ivy', ...)` the
   phone's own "Call Dad" button opens actually launches — not a stub, not
   `guardian_more.dart`'s route. `adb -s <phone> logcat -d | grep -i
   "callDadRequested\|invokeMethod"` should show the real Kotlin → Dart
   invocation.
8. **Multiple connected nodes edge case**, if more than one device is
   paired to the watch: confirm the message reaches the intended phone
   specifically, not silently dropped or misdirected — `MainActivity.kt`'s
   `sendCallDadMessage()` iterates every connected node, so this is worth
   a real check if the test environment has more than one paired device.
9. **Listener replacement check** (a real, disclosed risk named in
   `WearSyncBridge.kt`'s own comments): force an Activity/engine
   recreation on the phone (e.g., rotate the device if the app supports
   it, or background-and-relaunch aggressively enough to trigger
   `configureFlutterEngine()` again) with the watch still paired, then
   repeat step 6. Confirm exactly ONE `CallScreen` launch happens, not a
   duplicate — `register()`'s own `callDadListener?.let { ... removeListener
   (it) }` line exists specifically to prevent a stale listener from a
   discarded engine firing alongside a fresh one.

## What "pass" looks like, summarized

| Check | Expected |
|---|---|
| Watch shows `DEMO_SLEEPS_UNTIL_HANDOVER` (3) before first real sync | Yes |
| Watch updates to the phone's real value within a few seconds | Yes |
| A same-value re-sync still updates the watch (via `syncedAtMillis`) | Yes |
| `put_data_item_failed` in phone logcat | **Absent** |
| Watch "Call Dad" tap shows "Reaching Dad…" locally | Yes, immediately |
| Phone receives the message and opens the real `CallScreen` | Yes |
| A second engine recreation does not cause a duplicate call-launch | Confirmed single launch |

## Known limitations of this note

- Steps 6–9 only confirm the watch's tap reaches the phone and opens the
  real call screen — they do NOT confirm a full connected call (that's
  gated on the same LiveKit device-verification gap tracked elsewhere,
  see `MASTERFILE.md`'s standing "real two-device LiveKit call
  verification" item — this procedure is upstream of that, not a
  duplicate of it).
- This procedure assumes the watch is already OS-paired to the phone
  before Olive Branch is ever involved — pairing failures are a platform
  concern, not something this document or this app's own code can fix.
- Nothing here exercises `WearableListenerService`-style background
  delivery — both sides register listeners only while their own Activity
  is visible (`onResume`/`onPause`), a deliberate scope choice per
  `MainActivity.kt`'s own header, not a gap this procedure should flag as
  a bug if a background/backgrounded-app message is missed.

## Provenance

**2026-09-01.** This document authored, grounded in a direct read of
`wear_sync_channel.dart`, `WearSyncBridge.kt`, and `MainActivity.kt` (all
three in full) plus `transport.test.mjs`'s real "K · WEAR SYNC BRIDGE
CONTRACT" assertions — no code changed, no device touched, per the
session's own "avoid live-testing this pass" instruction. Nothing below
this line exists yet; the next real hardware pass should append its
findings here rather than starting a new document, matching this repo's
own established practice.
