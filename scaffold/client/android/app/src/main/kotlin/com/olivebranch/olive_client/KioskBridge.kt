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
                M_START -> { activity.startLockTask(); result.success(currentMode(activity)) }
                M_STOP  -> { activity.stopLockTask();  result.success(null) }
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
