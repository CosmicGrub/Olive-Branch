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

    // Event names. Each maps to a §5.20 state-machine transition.
    const val E_EXITED     = "lockTaskExited"     // -> onLockTaskExited()
    const val E_BACKGROUND = "backgrounded"       // -> onBackgrounded()
    const val E_RESUMED    = "resumed"

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
