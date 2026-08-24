package com.olivebranch.olive_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Registers KioskBridge (§5.20, §8.3) against the two platform channels
// kiosk_channel.dart already expects.
//
// Lock-task exit detection: an earlier version of this file tried to register
// a BroadcastReceiver for `Intent.ACTION_LOCK_TASK_ENTERING`/`_EXITING`. Those
// names do not exist in the public SDK (compileSdk 36) — caught immediately by
// tools/verify.sh's new Android gate ("Unresolved reference"), which is
// exactly the failure mode that gate exists for. Replaced with a mechanism
// built entirely on APIs already proven to compile and work here
// (`ActivityManager.getLockTaskModeState()`, the same call `currentMode()`
// already uses): poll the mode at the two lifecycle points that bracket any
// backgrounding, `onStop()` and `onResume()`, and diff against the
// last-observed mode.
//
//  - onStop(): the app just lost the foreground, for any reason. If the mode
//    ALSO dropped from pinned/locked to none in the same moment, that's a
//    genuine lock-task exit (the child's Back+Recents gesture unpins before
//    backgrounding away) — the higher-severity signal. Otherwise it's a plain
//    backgrounding (e.g. an incoming call covering the still-pinned app).
//  - onResume(): purely informational (E_RESUMED); also refreshes the
//    tracked mode so the next onStop() comparison is accurate.
class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private var lastKnownMode: String = "none"

    // §16.2 #6 — WrapperJitsiMeetActivity (a different Gradle module; see
    // KioskBridge.ACTION_CALL_LOCK_TASK_EXITED's own doc comment for why this
    // can't just be a direct method call) broadcasts this when ITS pin gets
    // defeated mid-call. Relayed through the exact same emitExit() the
    // ordinary (non-call) defeat path already uses, so lock_controller.dart's
    // onLockTaskExited handles both uniformly with no Dart-side change.
    private val callDefeatReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            KioskBridge.emitExit(eventSink, wasPinned = true)
        }
    }

    // 2026-08-24 — the real, non-PiP-confusable "the call is truly over"
    // signal. See KioskBridge.ACTION_CALL_ACTIVITY_DESTROYED's own doc
    // comment for the real bug this closes: onResume() alone fires for a
    // PiP entry too, so a read-and-clear handoff flag could already be
    // gone by the time the call genuinely ends, leaving nothing to re-pin.
    private val callActivityDestroyedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            KioskBridge.clearCallHandoff(this@MainActivity)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        KioskBridge.register(
            this,
            MethodChannel(messenger, KioskBridge.METHOD_CHANNEL),
            EventChannel(messenger, KioskBridge.EVENT_CHANNEL),
            onSink = { eventSink = it },
        )
        lastKnownMode = KioskBridge.currentMode(this)
        LocalBroadcastManager.getInstance(this).registerReceiver(
            callDefeatReceiver, IntentFilter(KioskBridge.ACTION_CALL_LOCK_TASK_EXITED),
        )
        LocalBroadcastManager.getInstance(this).registerReceiver(
            callActivityDestroyedReceiver, IntentFilter(KioskBridge.ACTION_CALL_ACTIVITY_DESTROYED),
        )

        // Phone -> watch sync (§21.5). See WearSyncBridge.kt's own header for
        // scope.
        WearSyncBridge.register(this, MethodChannel(messenger, WearSyncBridge.METHOD_CHANNEL))

        // Real WebAuthn/passkey ceremony (§7.1, §8.1, §11). See
        // WebAuthnBridge.kt's own header for the API-level tension and the
        // discoverable-credential requirement this bridge is built around.
        WebAuthnBridge.register(this, MethodChannel(messenger, WebAuthnBridge.METHOD_CHANNEL))
    }

    override fun onStop() {
        super.onStop()
        val current = KioskBridge.currentMode(this)
        val wasLocked = lastKnownMode == "pinned" || lastKnownMode == "locked"
        if (wasLocked && current == "none") {
            KioskBridge.emitExit(eventSink, wasPinned = lastKnownMode == "pinned")
        } else {
            KioskBridge.emitBackgrounded(eventSink)
        }
        lastKnownMode = current
    }

    override fun onResume() {
        super.onResume()
        // §16.2 #6, revised 2026-08-24 for real child PiP — see KioskBridge
        // .stillExpectingCallHandoff()'s own doc comment for exactly why
        // this peeks rather than consumes now. stillExpectingCallHandoff()
        // only ever returns true if M_BEGIN_CALL_HANDOFF actually ran,
        // which the Dart side only does when this device was pinned/locked
        // to begin with (kiosk_channel.dart's beginCallHandoff callers all
        // guard on mode() != 'none' first) — so this never fires on an
        // unlocked/guardian device. Re-pins on EVERY resume while a call is
        // outstanding: a clean end, a mid-call defeat, AND a PiP entry all
        // resume this Activity, and only the LAST of those (whichever one
        // actually happens) should leave the child free to leave the app —
        // callActivityDestroyedReceiver above is what actually clears the
        // flag, not this method.
        if (KioskBridge.stillExpectingCallHandoff(this)) {
            startLockTask()
        }
        lastKnownMode = KioskBridge.currentMode(this)
        KioskBridge.emitResumed(eventSink)
    }
}
