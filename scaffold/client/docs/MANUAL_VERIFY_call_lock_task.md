# Manual verification — call vs. kiosk lock-task (§16.2 #6 / §5.20)

**Why this exists as a manual procedure, not just a test.** The bug this
guards against — `WrapperJitsiMeetActivity` refused as a lock-task violation,
`call_screen.dart`'s "Joining…" spinner hanging forever — produces **no
crash and no visible error**. `flutter analyze` stays clean, `flutter test`
stays green, the app never logs a caught exception. The only place the
failure is observable at all is `adb logcat` on a real device with real
screen-pinning engaged, which is exactly the surface no CI pipeline in this
repo exercises (`tools/verify.sh` has no Android/Gradle gate yet — see its
own header). A regression here will not fail a build. It will only ever be
caught by someone actually running this procedure.

Run this after any change to: `client/lib/call_screen.dart`,
`client/lib/kiosk_channel.dart`, `client/android/app/.../KioskBridge.kt`,
`client/android/app/.../MainActivity.kt`, or anything under
`client/third_party/jitsi_meet_flutter_sdk_patched/android/`.

## Setup

0. **Samsung/One UI devices: check "Allow apps to be pinned" is ON before
   assuming anything else is broken.** Settings → search "pin windows" →
   **Allow apps to be pinned**. Confirmed OFF by default on two separate
   real devices (a Fold5 and a Tab S9 FE, both Android 16 / One UI, security
   patch 2026-07-05) on 2026-08-22. With it off, `Activity.startLockTask()`
   still gets called, the OS still shows the "App is pinned" confirmation
   toast, and `RestrictionPolicy: isScreenPinningAllowed` logs `false` right
   before the transition — but `dumpsys activity activities |
   grep mLockTaskModeState` never leaves `NONE`, indefinitely, no timeout,
   no error. This is **the same silent-hang shape as the bug this whole
   document exists for**, just one layer further out (OS setting, not app
   code) — worth checking first since it produces near-identical symptoms
   and will make it look like the §16.2 #6 fix itself regressed when it
   hasn't. Confirmed present as a toggle back to at least One UI 6 per
   Samsung's own support content; not part of the stock AOSP screen-pinning
   flow, so don't expect to find it documented on developer.android.com.
1. A real Android device (screen-pinning does not reproduce reliably on the
   emulator — this bug was only ever caught on hardware). `adb devices -l`
   should show it.
2. `flutter build apk --debug` from `client/`, then
   `adb -s <device> install -r build/app/outputs/flutter-apk/app-debug.apk`.
3. `local-call-room-server.mjs` needs to be running and reachable from the
   device. **Check `adb -s <device> reverse --list` and whatever is already
   listening on `127.0.0.1:8787` on the dev machine before touching either**
   — this port is shared with anyone else's local testing session. If
   something is already there, either coordinate, or point a *device-side*
   reverse rule at your own instance on a different host port instead of
   restarting/killing what's already running:
   `adb -s <device> reverse tcp:8787 tcp:<your-own-port>`.
4. `adb -s <device> logcat -c` immediately before the test, so the capture
   below isn't drowned in unrelated noise.

## Procedure

1. Launch the app, choose **"My child's device"**. Confirm the OS's own
   "App is pinned" dialog appears (first run only) and dismiss it.
2. Confirm pinning actually engaged:
   `adb -s <device> shell dumpsys activity activities | grep mLockTaskModeState`
   → must read `PINNED` (or `LOCKED` on a device-owner build).
3. Tap the call button ("Call Dad" in the demo build). This is the exact
   moment that used to hang forever.
4. **Within a few seconds**, one of two things should happen — either is a
   pass, since the public `meet.jit.si` server has its own separate,
   already-documented moderator-lobby issue (§16.2 #6's second cause) that
   is not what this procedure checks:
   - The native Jitsi call UI actually appears on screen, or
   - The call reaches Jitsi's lobby-waiting state (confirmed via
     `[app:lobby] Lobby starting knocking` in logcat).

   What must **not** happen: the Flutter "Joining…" spinner sitting there
   indefinitely with nothing else on screen.
5. Pull the log and check it:
   `adb -s <device> logcat -d > call_test.log`
   - `grep "Attempted Lock Task Mode violation" call_test.log` → **must be
     empty**. A hit here means the fix regressed and this whole procedure
     has failed, regardless of what step 4 looked like.
   - `grep "mLockTaskModeState" call_test.log` (or re-run the dumpsys from
     step 2 while the call is up) → should still read `PINNED`/`LOCKED`,
     confirming the handoff actually transferred the pin to the call
     Activity rather than leaving the device unpinned for the call's
     duration.
6. Back out of the call (however the Jitsi UI exposes hanging up, or Back).
   Confirm the pin returns to the main Activity:
   `dumpsys activity activities | grep mLockTaskModeState` → `PINNED` again
   within a second or two of returning to the app.
7. **Mid-call defeat check** (the harder-to-trigger case, but the one that
   silently reopens an escape route if it regresses): while the call is up
   and pinned to `WrapperJitsiMeetActivity`, perform the screen-pinning
   unpin gesture (Back + Overview, held). Confirm:
   - The device returns to the home/launcher screen — pinning really was
     defeated, not just visually similar.
   - On returning to the Olive app (however you get back to it), it lands
     on the **PIN gate**, not silently back on the child home screen. This
     confirms `WrapperJitsiMeetActivity`'s own defeat detection reported
     through to `lock_controller.dart`'s existing `onLockTaskExited`
     transition, the same as any other defeat.

## What "pass" looks like, summarized

| Check | Expected |
|---|---|
| `Attempted Lock Task Mode violation` in logcat | **Absent** |
| Call actually starts (native UI or lobby-wait, not an infinite spinner) | Yes |
| Device stays pinned throughout the call | Yes (`PINNED`/`LOCKED` before, during, after) |
| Mid-call Back+Overview defeat | Lands on PIN gate, not child home, not silently ignored |

## Known limitation of this note

Steps 3–7 require a second person or device to actually answer the call for
a *connected* (not just *attempted*) call — this procedure only requires the
call *attempt* to succeed past the point that used to hang, which is the
part §16.2 #6's kiosk-lock finding was actually about. A fully connected
two-device call is still gated on §16.2 #6's second, separate cause (the
public server's moderator lobby) until Step 2 (self-hosting) lands.

## Provenance

**2026-08-08.** Implemented and code/build-verified (`flutter analyze`,
`flutter test`, `node packages/transport/test/transport.test.mjs`, a full
Gradle/Kotlin build across both the app module and the patched
`jitsi_meet_flutter_sdk_patched` module). Steps 1–2 above were confirmed
live on a real Galaxy Z Fold5 that session (screen-pinning engaged
correctly under the changed `MainActivity.kt`). Steps 3–7 were **not**
completed — a concurrent session's own testing reinstalled the app on the
same physical device mid-run before the call attempt finished.

**2026-08-22, still not closed — screen-pinning itself would not engage at
all, on either real device.** Returned to finish steps 3–7 and could not
get past step 2: `Activity.startLockTask()` was called correctly (confirmed
in logcat — `ActivityClientController.startLockTaskModeByToken`, a real
`ScreenPinningConfirmation` window drawn) but
`dumpsys activity activities | grep mLockTaskModeState` stayed `NONE`
indefinitely — reproduced identically on **both** the Fold5 and a Tab S9
FE, ruling out a device-specific cause. Root-caused one real contributing
factor: **Settings → "Allow apps to be pinned" was OFF on both devices**
(now Setup step 0 above) — `RestrictionPolicy: isScreenPinningAllowed`
logged `false` right before the doomed transition. Turned it on
(confirmed via `uiautomator dump`: `checked="true"`), confirmed the
`RestrictionPolicy` log line flips to `true`, full device reboot to clear
any stuck WindowManager transition state — **`mLockTaskModeState` still
never left `NONE`**, polled for 80+ seconds. So the toggle was real and is
worth keeping as a first check, but it is not sufficient by itself to
explain what's happening on these two devices right now. Not yet
determined: whether this is Android 16 / One UI security-hardening around
lock-task specifically for non-device-owner apps (searched
developer.android.com's Android 16 behavior-change pages — nothing
documented there for lock task mode, so if this is a real platform change
it isn't showing up in the usual place), a leftover Knox/Secure Folder
interaction (this device has a Secure Folder profile owner under a
separate user id — unconfirmed whether that's relevant to the main user's
own lock-task state), or a genuine device-level fault reproducing
identically by coincidence. Attempted to isolate further: (a) whether
`adb shell input tap`-synthesized touches are specifically distrusted by
Android 16 for this security-sensitive transition, by asking a human to
drive the same flow with real touch input — inconclusive, no confirmed
result captured before the polling window closed; (b) the OS's own manual
"pin from Recents" flow (long-press the app icon in Overview), independent
of Olive's code entirely, as a cleaner isolation test — didn't reach a
conclusive result either; the long-press gesture kept triggering this
Samsung build's split-screen app-picker instead of the pin context menu.
**Whoever picks this up next: start with (a), a real finger on the actual
touchscreen, since it's the cheapest test and was never conclusively
ruled in or out.** If genuine touch also fails to pin, this is a real
platform/device issue outside Olive's control, and the honest fix is
probably "wait for both devices to reproduce it in Google's/Samsung's own
Settings app pinning independent of any of our code, then file it as a
platform bug" rather than continuing to treat it as an Olive Branch defect.
