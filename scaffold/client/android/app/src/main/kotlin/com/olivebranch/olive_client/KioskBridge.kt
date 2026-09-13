// OLIVE BRANCH — Android kiosk bridge. MASTERFILE §5.20, §8.3.
//
// Ported from the former scaffold/native/android/KioskBridge.kt reference copy
// (package app.olive.kiosk, never compiled) into the real Gradle module. Built,
// installed, and manually verified against a real device this session — see
// CHANGELOG. verify.sh has no automated Android/Gradle gate yet (see
// tools/verify.sh's Android block), so this is not yet CI-checked on every run,
// only on the device it was actually tested against.
//
// The design point, unchanged from the reference copy: PINNED mode is escapable
// by the child (Back + Recents), and only LOCK_TASK_MODE_LOCKED — which requires
// device-owner provisioning outside this app's control — is not. Most installs
// will be PINNED. So this bridge's job is not to prevent escape; it is to
// REPORT escape immediately and truthfully, matching lock.ts's own framing.
package com.olivebranch.olive_client

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

object KioskBridge {
    const val METHOD_CHANNEL = "app.olive/kiosk"
    const val EVENT_CHANNEL  = "app.olive/kiosk_events"

    // Method names. Mirrored in client/lib/kiosk_channel.dart and contract-
    // checked against it (and the Windows stub) by transport.test.mjs.
    const val M_START      = "startLockTask"
    const val M_STOP       = "stopLockTask"
    const val M_MODE       = "lockTaskMode"
    const val M_IS_OWNER   = "isDeviceOwner"
    // §16.2 #6 / §5.20 — see kiosk_channel.dart's beginCallHandoff doc comment
    // for why this exists. Android-only; no Windows/dart-contract check.
    const val M_BEGIN_CALL_HANDOFF = "beginCallHandoff"

    // Event names. Each maps to a §5.20 state-machine transition.
    const val E_EXITED     = "lockTaskExited"     // -> onLockTaskExited()
    const val E_BACKGROUND = "backgrounded"       // -> onBackgrounded()
    const val E_RESUMED    = "resumed"

    // ------------------------------------------------------------------
    // Call handoff (§16.2 #6). `WrapperJitsiMeetActivity` (patched, in
    // third_party/jitsi_meet_flutter_sdk_patched — a SEPARATE Gradle module
    // that this app depends on, not the other way round) cannot import this
    // object directly: that would be a library depending on the app that
    // consumes it, which Gradle won't allow. SharedPreferences and a
    // same-process LocalBroadcastManager action are the two primitives here
    // that need only a shared string contract, not a compile-time reference
    // — the same trick the Jitsi SDK's own WrapperJitsiMeetActivity already
    // uses (via LocalBroadcastManager) to get its native events back into
    // this process's Flutter side. Every string below is duplicated
    // verbatim in that Activity; there is nothing to import it from.
    // ------------------------------------------------------------------
    private const val HANDOFF_PREFS = "app.olive.kiosk"
    private const val HANDOFF_KEY   = "expecting_call_handoff"
    // WrapperJitsiMeetActivity broadcasts this literal string directly (it
    // cannot import this constant — see the module-boundary note above); this
    // copy exists only so MainActivity has one place to read it from when it
    // registers its own receiver. If this ever drifts from the string in
    // WrapperJitsiMeetActivity.kt, the mismatch fails silently (the broadcast
    // just never arrives) — same failure shape as a channel-name typo, which
    // is exactly why the transport contract test mirrors string constants
    // this same way for the MethodChannel/EventChannel names above.
    const val ACTION_CALL_LOCK_TASK_EXITED = "app.olive.kiosk.CALL_LOCK_TASK_EXITED"
    // 2026-08-24 — real PiP for the child (see call_screen.dart's own
    // header for the fuller account) surfaced a real bug in the ORIGINAL
    // read-and-clear handoff design this constant's sibling used to be
    // named after: entering PiP mid-call is ALSO a MainActivity.onResume()
    // (Android brings the host task back behind the floating PiP window),
    // so a one-shot "consume on first resume" flag got cleared the moment
    // PiP was entered — leaving NOTHING to re-pin on the SECOND resume,
    // the one that happens when the call genuinely ends. A kiosk-locked
    // child's device could end a real call and never re-lock. Same string-
    // duplication contract as ACTION_CALL_LOCK_TASK_EXITED above —
    // WrapperJitsiMeetActivity.kt's own onDestroy() broadcasts this
    // literal, verbatim, for the identical module-boundary reason.
    const val ACTION_CALL_ACTIVITY_DESTROYED = "app.olive.kiosk.CALL_ACTIVITY_DESTROYED"

    private fun setExpectingCallHandoff(ctx: Context, expecting: Boolean) {
        ctx.getSharedPreferences(HANDOFF_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(HANDOFF_KEY, expecting).apply()
    }

    /// Peek, never consume — see this file's own ACTION_CALL_ACTIVITY_
    /// DESTROYED comment above for exactly why a read-and-clear was wrong.
    /// MainActivity.onResume() calls this on EVERY resume while a call is
    /// outstanding (a real call end, a mid-call kiosk defeat, AND a PiP
    /// entry all resume this Activity) and re-pins every single time —
    /// re-pinning an already-pinned Activity is a safe, standard no-op,
    /// verified live rather than assumed. Only clearCallHandoff() below
    /// ever actually turns this off.
    fun stillExpectingCallHandoff(ctx: Context): Boolean =
        ctx.getSharedPreferences(HANDOFF_PREFS, Context.MODE_PRIVATE)
            .getBoolean(HANDOFF_KEY, false)

    /// Called ONLY from MainActivity's ACTION_CALL_ACTIVITY_DESTROYED
    /// receiver — the one signal that actually means the call Activity is
    /// gone for good, not just backgrounded behind a PiP window.
    fun clearCallHandoff(ctx: Context) = setExpectingCallHandoff(ctx, false)

    fun currentMode(ctx: Context): String =
        when ((ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
                .lockTaskModeState) {
            ActivityManager.LOCK_TASK_MODE_LOCKED -> "locked"
            ActivityManager.LOCK_TASK_MODE_PINNED -> "pinned"
            else -> "none"
        }

    // 2026-08-24 — real fix for a live-confirmed bug: startLockTask() can
    // return without throwing yet not actually leave the device pinned
    // (confirmed live this session on a real Galaxy Tab S9 FE — see
    // CHANGELOG's own disclosed pin-quirk note).
    //
    // REVISED same day, after this first version's own live test caught IT
    // making a false claim of failure. The original theory here (window
    // needs FOCUS, not just onResume) was wrong, or at least not what this
    // device is actually doing — real dumpsys/logcat evidence from that test
    // run showed the true mechanism: for an app that is NOT a device owner
    // (i.e. every real install this app supports — see this file's own
    // header), Android's SystemUI shows a real, asynchronous confirmation
    // surface (`ScreenPinningRequest`/`ScreenPinningConfirmation`, visible in
    // logcat as WindowManager addView/removeView churn) as PART of actually
    // committing the pin, and that transition can genuinely take several
    // hundred ms to settle — dumpsys showed mLockTaskModeState still NONE at
    // the ~450ms mark this function's original 3×150ms budget gave up at,
    // yet PINNED (with the OS's own "App is pinned" notice on screen) a
    // short while after. The original design RE-CALLED startLockTask() on
    // every retry, reasoning that was a safe no-op — but re-invoking it
    // WHILE that confirmation surface is still transitioning is exactly what
    // the logcat churn (repeated removeView/addView of the same window
    // class, once per retry) shows happening, which risks resetting the
    // OS's own transition rather than helping it along. Fixed: call
    // startLockTask() exactly ONCE, then only POLL currentMode() — never
    // re-invoke — across a total budget generous enough to clear the
    // observed real-world settle time with real margin.
    //
    // Widened again the same pass, after a THIRD live re-test on the same
    // Tab S9 FE: a 6×250ms (1.5s) budget still gave a false failure — real
    // dumpsys evidence showed the transition genuinely can still be pending
    // (a WindowManager Transition record open, type UNKNOWN, no pinning
    // confirmation surface even drawn yet) well past 1.5s, and on an earlier
    // run that same cold-start attempt didn't visibly settle to PINNED until
    // multiple *minutes* later, well outside anything a synchronous-feeling
    // UI wait should ever block on. This is the known, already-disclosed
    // pin-quirk on this specific tablet (see CHANGELOG; the user has
    // explicitly accepted it as a non-blocking device flakiness, not
    // something every future session should keep re-chasing). 8×300ms
    // (2.4s) here buys real, evidenced margin over the fast/common case
    // without making the child wait unreasonably long for the normal path;
    // it does NOT claim to make this tablet's pin reliable — onResult(false)
    // still fires honestly when it doesn't settle in time, exactly as
    // lock_controller.dart's own fail-truthfully framing (this file's own
    // header) requires.
    // FOURTH revision, same pass — the real trigger source, not just the
    // OS-side settle time, turned out to matter. kiosk_shell.dart's
    // `_engage()` (KioskShell's own real "pin now" call) runs from Dart's
    // `initState()`, which fires as soon as the Flutter widget tree first
    // builds — a Flutter-side lifecycle event with no defined relationship
    // to the native Activity's own lifecycle, and empirically much earlier
    // than it: a cold-launch M_START can reach this method before the
    // Activity's WINDOW has focus at all, which is exactly the documented
    // Android constraint startLockTask() is built around (the ORIGINAL
    // theory at the top of this doc comment, dismissed too quickly the
    // first time this was revised — real evidence this pass showed both
    // things are true: the OS confirmation surface is slow AND focus can
    // genuinely not be there yet). Gates the actual startLockTask() call on
    // Activity.hasWindowFocus() now, polling for focus first rather than
    // assuming onResume() already implies it.
    fun startLockTaskVerified(
        activity: Activity, totalChecks: Int = 8, delayMs: Long = 300,
        focusChecksLeft: Int = 10, focusDelayMs: Long = 100,
        onResult: (pinned: Boolean) -> Unit,
    ) {
        if (!activity.hasWindowFocus() && focusChecksLeft > 1) {
            Handler(Looper.getMainLooper()).postDelayed({
                startLockTaskVerified(activity, totalChecks, delayMs,
                    focusChecksLeft - 1, focusDelayMs, onResult)
            }, focusDelayMs)
            return
        }
        activity.startLockTask() // exactly once — see this function's own doc comment above
        pollLockTaskMode(activity, totalChecks, delayMs, onResult)
    }

    private fun pollLockTaskMode(
        activity: Activity, checksLeft: Int, delayMs: Long, onResult: (pinned: Boolean) -> Unit,
    ) {
        val mode = currentMode(activity)
        if (mode != "none") { onResult(true); return }
        if (checksLeft <= 1) {
            Log.w("KioskBridge", "startLockTask() did not pin after the full poll budget " +
                "(activity=${activity.javaClass.simpleName})")
            onResult(false)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            pollLockTaskMode(activity, checksLeft - 1, delayMs, onResult)
        }, delayMs)
    }

    // `events` was accepted but never wired to a stream handler in the
    // original reference copy — a declaration without an implementation,
    // invisible only because that copy was never compiled or run. Fixed here:
    // the caller supplies the EventSink via `onSink`.
    fun register(
        activity: Activity, methods: MethodChannel, events: EventChannel,
        onSink: (EventChannel.EventSink?) -> Unit,
    ) {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                // Verified, not fire-and-forget (2026-08-24) — see
                // startLockTaskVerified()'s own doc comment for the real bug
                // this closes. Async now (result.success() called from the
                // retry's own callback); MethodChannel supports a delayed
                // result exactly this way.
                M_START -> startLockTaskVerified(activity) { result.success(currentMode(activity)) }
                // 2026-08-24 — also clears the call-handoff flag, not just
                // the pin. Real, live gap this closes: `expecting_call_
                // handoff` previously only ever cleared from a real call
                // Activity's own onDestroy() broadcast (see
                // ACTION_CALL_ACTIVITY_DESTROYED's own doc comment) — never
                // from an explicit guardian exit-kiosk action
                // (GuardianEscalationScreen's "exit kiosk mode" button,
                // kiosk_shell.dart's _exitKiosk(), this exact method). If a
                // call's own Activity died abnormally mid-call (a process
                // kill, never reaching its own onDestroy()) the flag stays
                // orphaned true, and the VERY NEXT onResume() re-pins the
                // device — potentially seconds after a guardian explicitly,
                // successfully unpinned it, with no signal telling her why
                // it re-locked. An explicit stop request is a strictly
                // stronger, more authoritative signal than "assume a call
                // might still be in flight" — clearing here is always safe.
                M_STOP  -> { activity.stopLockTask(); clearCallHandoff(activity); result.success(null) }
                M_MODE  -> result.success(currentMode(activity))
                // Reported honestly at setup (§5.20): a parent who believes the
                // tablet is sealed makes worse decisions than one who knows it
                // is not.
                M_IS_OWNER -> result.success(currentMode(activity) == "locked")
                // §16.2 #6 — unpin THIS Activity so the Jitsi SDK's own
                // Activity is actually allowed to launch (pinning permits
                // only one task on screen; launching a second one is exactly
                // what §16.2 #6 diagnosed as the violation), and mark that
                // the onStop() this triggers is an intentional handoff, not
                // a defeat. `activity.stopLockTask()` is a no-op if we
                // weren't pinned to begin with (e.g. the guardian side).
                M_BEGIN_CALL_HANDOFF -> {
                    setExpectingCallHandoff(activity, true)
                    activity.stopLockTask()
                    result.success(currentMode(activity))
                }
                else -> result.notImplemented()
            }
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) = onSink(sink)
            override fun onCancel(args: Any?) = onSink(null)
        })
    }

    // Emitted from MainActivity's onStop/onUserLeaveHint. The Dart side must
    // treat BOTH exit and backgrounding as a defeat: escalation is dropped and
    // session tokens are revoked server-side, because losing focus does not
    // invalidate a JWT.
    fun emitExit(sink: EventChannel.EventSink?, wasPinned: Boolean) {
        sink?.success(mapOf("event" to E_EXITED, "mode" to if (wasPinned) "pinned" else "locked"))
    }
    fun emitBackgrounded(sink: EventChannel.EventSink?) {
        sink?.success(mapOf("event" to E_BACKGROUND))
    }
    fun emitResumed(sink: EventChannel.EventSink?) {
        sink?.success(mapOf("event" to E_RESUMED))
    }
}
