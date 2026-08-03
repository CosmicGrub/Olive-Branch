// OLIVE BRANCH — Android kiosk bridge. MASTERFILE §5.20, §8.3.
//
// UNVERIFIED: no Android toolchain exists in this repository. Not compiled, not
// linted, never run on a device. The platform-channel method names and the
// event contract ARE checked against the Dart side and against the §5.20 state
// machine by packages/transport/test/transport.test.mjs.
//
// The design point: PINNED mode is escapable by the child (Back + Recents), and
// only LOCK_TASK_MODE_LOCKED — which requires device-owner provisioning — is
// not. Most installs will be PINNED. So this bridge's job is not to prevent
// escape; it is to REPORT escape immediately and truthfully.
package app.olive.kiosk

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

object KioskBridge {
    const val METHOD_CHANNEL = "app.olive/kiosk"
    const val EVENT_CHANNEL  = "app.olive/kiosk_events"

    // Method names. Mirrored in client/lib/kiosk_channel.dart.
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

    fun register(activity: Activity, methods: MethodChannel, events: EventChannel) {
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
    }

    // Emitted from onPause/onStop. The Dart side must treat BOTH as a defeat:
    // escalation is dropped and session tokens are revoked server-side, because
    // losing focus does not invalidate a JWT.
    fun emitExit(sink: EventChannel.EventSink?, wasPinned: Boolean) {
        sink?.success(mapOf("event" to E_EXITED, "mode" to if (wasPinned) "pinned" else "locked"))
    }
    fun emitBackgrounded(sink: EventChannel.EventSink?) {
        sink?.success(mapOf("event" to E_BACKGROUND))
    }
}
