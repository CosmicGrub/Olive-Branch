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
   pinning actually works — with a genuine, deliberate attempt, not a
   quick guess.** Long-press an app icon (any app) in Recents/Overview and
   check that a **"Pin this app"** option is offered. If it genuinely
   isn't there after really looking, that points at a platform/OS problem
   rather than an Olive Branch one — but treat that conclusion carefully:
   a 2026-08-22 session escalated exactly this kind of unconfirmed "it
   didn't work" report into a formal (and wrong) "confirmed platform bug"
   writeup that had to be retracted — see that date's Provenance entries
   below for the full, corrected trail before drawing conclusions from a
   single attempt. This pre-check is still worth running first, since a
   real platform issue here will look identical to the §16.2 #6 fix
   regressing — just don't let one inconclusive try stand in for it.
   - Samsung/One UI devices specifically: also check Settings → search "pin
     windows" → **Allow apps to be pinned** is ON first (Settings → More/
     Additional/Other security settings, naming varies by One UI version).
     Confirmed OFF by default on two real devices on 2026-08-22, and
     confirmed insufficient by itself even once turned on — see Provenance.
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

**RETRACTED, same day — the "confirmed platform bug" conclusion below was
wrong and should not have been written.** A prior revision of this section
claimed the real-finger native-pin-from-Recents test came back negative
("no pin option appeared") and treated that as decisive: ruling out an
Olive Branch defect, ruling out synthetic-touch distrust, corroborating
with a Samsung Community thread, and declaring the kiosk-lock feature
broken at the platform level. **The device owner has since clarified that
screen pinning is in fact functional on this device — the negative result
came from declining to actually run the test, not from a genuine attempt
that failed.** That single unverified report was escalated into formal
documentation, a public PR, and a merge into `main` without pushing back
or asking for confirmation first, and it very nearly went out as an
external bug report to Samsung besides. That was a real process failure —
treating one unconfirmed claim as settled fact, compounded by searching
for and presenting a web result that fit the conclusion rather than
weighing against it — and it is called out here rather than quietly
edited away, matching this project's own standing practice for reversals
(see `MASTERFILE.md` §21.7).

**Actual status, honestly: unverified, not confirmed broken.** Nothing in
this session establishes that screen pinning fails on this hardware. What
is independently confirmed (by direct `dumpsys`/`logcat` inspection, not
by a secondhand report) is only what the paragraph above this one says:
`Activity.startLockTask()` was called correctly and
`mLockTaskModeState` stayed `NONE` across many attempts *during that
session's own testing*, with the "Allow apps to be pinned" toggle being a
real, confirmed-on-device factor that was insufficient by itself. Whether
that reflects a genuine platform issue, a leftover artifact of this
session's own heavy `adb`-driven testing (many reinstalls, a full
`flutter clean`, forced reboots, hours of scripted taps), or something
else entirely is now **open again**. Do not cite the retracted section
below as evidence of anything. Do not file a Samsung platform bug report
based on it. If a genuine platform bug report is ever warranted, it needs
a real, deliberately-run confirmation first — not a report of one.

**Where this leaves Olive Branch:** the call-handoff fix itself is still
implemented and code/build-verified (see the 2026-08-08 entry above) and
was never shown to be broken by anything in this document — only *live
call-launch-under-pin* verification remains incomplete, and it remains
incomplete because it was deprioritized, not because of a confirmed
blocker. Whoever picks this up next should re-run Setup step 0's native
pin-from-Recents pre-check as a genuine, good-faith attempt before
concluding anything either way.

<details>
<summary>Retracted section (kept for the record, not as a source of truth)</summary>

Went back and (claimed to have) closed out both hypotheses the section
above left open, with a real finger on the actual glass (not `adb shell
input tap`) driving Android's own native pin-from-Recents flow — zero
Olive code involved, not even the app installed matters for this test:

1. On the Fold5, with "Allow apps to be pinned" confirmed **on** (survived
   a full reboot — checked again via `uiautomator dump`,
   `checked="true"`), a human reported long-pressing an app icon in
   Recents and looking for the "Pin this app" option.
2. Reported: no pin option appeared at all.

That result was treated as ruling out both synthesized-touch distrust and
an Olive Branch defect, with a Samsung Community thread — ["Pinning apps
not possible on OneUI
8.0"](https://eu.community.samsung.com/t5/tablets/pinning-apps-not-possible-on-oneui-8-0/td-p/13546242)
— cited as corroboration (itself already flagged at the time as possibly
describing a different, DeX-specific "pin on top" feature rather than
security screen pinning). **Retracted above: the report behind step 2 was
not a genuine attempt.** The Samsung thread may still be relevant to a
real investigation later; it just isn't evidence of anything about *this*
device right now.

</details>

(A prior revision here also suggested filing a Samsung platform bug report
via Samsung Members. Don't — not until a genuine, deliberately-run
confirmation actually exists.)
