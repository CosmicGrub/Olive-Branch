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

0. **Before touching Olive Branch at all: confirm the device's own native
   pinning actually works.** Long-press an app icon (any app) in
   Recents/Overview and check that a **"Pin this app"** option is offered.
   If it isn't, this is a platform/OS problem, not an Olive Branch one —
   see the 2026-08-22 Provenance entry below for the full trail (a real
   finger, zero Olive code involved, still got nothing on two separate
   real devices on this exact OS build). Don't spend time on steps 1+ until
   this pre-check passes on a real finger, on the real device — it will
   look exactly like the §16.2 #6 fix regressed and it won't have.
   - Samsung/One UI devices specifically: also check Settings → search "pin
     windows" → **Allow apps to be pinned** is ON first (Settings → More/
     Additional/Other security settings, naming varies by One UI version).
     Confirmed OFF by default on two real devices on 2026-08-22 — but be
     aware turning it on is **necessary, not sufficient**: on this session's
     two test devices (both One UI 8 / Android 16, security patch
     2026-07-05) it did not fix the underlying problem, and the native
     pin-from-Recents pre-check above still failed even with the toggle on
     and a full reboot.
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
explain what's happening on these two devices right now.

**Resolved (as far as Olive Branch is concerned): platform-level, not an
app bug.** Went back and closed out both hypotheses the section above left
open, this time with a real finger on the actual glass (not `adb shell
input tap`) driving Android's own **native** pin-from-Recents flow —
zero Olive code involved, not even the app installed matters for this
test:

1. On the Fold5, with "Allow apps to be pinned" confirmed **on** (survived
   a full reboot — checked again via `uiautomator dump`,
   `checked="true"`), a human long-pressed an app icon in Recents and
   looked for the "Pin this app" option.
2. **No pin option appeared at all**, on the real device, with a real
   finger, through Android/Samsung's own stock UI.

That result rules out both remaining hypotheses in one shot:
- **Not synthesized-touch distrust** — a genuine finger got the same
  non-result `adb shell input tap` did.
- **Not an Olive Branch defect** — this is Android's own native pinning
  entry point, reached with zero app code in the path.

Only explanation left standing: a platform/OS-level fault on this specific
build (Android 16, One UI 8, security patch 2026-07-05), independent of
anything in this repo. Corroborating, though not a certain match — a
Samsung Community thread, ["Pinning apps not possible on OneUI
8.0"](https://eu.community.samsung.com/t5/tablets/pinning-apps-not-possible-on-oneui-8-0/td-p/13546242),
reports pinning broken after the One UI 8 update, with a Samsung moderator
directing users to file feedback rather than confirming a fix. Flagging
one honest gap rather than overclaiming: that thread's own framing (DeX,
"pin apps on top of other windows," multitasking) reads like it could be
describing Samsung's *separate* multi-window "always on top" pin feature
rather than the *security* screen-pinning feature this doc is about — the
two features share the word "pin" in Samsung's UI but are not the same
thing, and nothing found conclusively confirms which one that thread means.

**Where this leaves Olive Branch:** the kiosk-lock feature — and by
extension the call-handoff fix this doc exists to verify, since it can't
be exercised without a working pin to hand off — cannot currently be
verified, or used, on this Fold5's exact OS build, for reasons entirely
outside this app's code. Whoever picks this up next should not spend more
time treating it as an Olive Branch defect: either test on a device/OS
build where Samsung's own native pinning demonstrably works first (that's
now a fast, cheap pre-check — long-press an app icon in Recents, confirm
"Pin this app" is offered, *before* touching Olive Branch at all), or
track the platform bug (via Samsung Members → Get Help → Feedback, per
that community thread) separately from this app's own issue tracking.
