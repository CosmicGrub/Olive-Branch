package org.jitsi.jitsi_meet_flutter_sdk

import android.app.Activity
import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import org.jitsi.meet.sdk.BroadcastEvent
import org.jitsi.meet.sdk.JitsiMeetActivity
import android.app.KeyguardManager
import android.view.WindowManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.jitsi.meet.sdk.JitsiMeetConferenceOptions
import org.jitsi.jitsi_meet_flutter_sdk.JitsiMeetEventStreamHandler
import org.jitsi.meet.sdk.JitsiMeet

// PATCHED (see ../../../../PATCH.md and the app's own MASTERFILE §16.2 #6):
// this Activity's own singleTask launch mode is exactly what the host app's
// kiosk lock-task pinning refuses to launch as a second task
// (`E/ActivityTaskManager: Attempted Lock Task Mode violation`, confirmed on
// a real Galaxy Z Fold5). The host app now unpins itself and hands the pin
// to THIS Activity right before launching it (com.olivebranch.olive_client's
// KioskBridge.kt, method channel `beginCallHandoff`) rather than just
// dropping it for the call's duration. The two halves of that handoff can't
// share a compile-time import — this library module cannot depend on the
// app module that depends on it — so they agree only on plain string
// contracts (a SharedPreferences file/key, a broadcast action), duplicated
// verbatim on both sides and cross-referenced in comments, the same way the
// MethodChannel/EventChannel name strings already are between
// kiosk_channel.dart, KioskBridge.kt, and kiosk_bridge.cpp.
private const val HANDOFF_PREFS = "app.olive.kiosk"
private const val HANDOFF_KEY   = "expecting_call_handoff"
// Mirrors com.olivebranch.olive_client.KioskBridge.ACTION_CALL_LOCK_TASK_EXITED.
private const val ACTION_CALL_LOCK_TASK_EXITED = "app.olive.kiosk.CALL_LOCK_TASK_EXITED"
// Mirrors com.olivebranch.olive_client.KioskBridge.ACTION_CALL_ACTIVITY_DESTROYED
// — see that constant's own doc comment for the real bug this closes (a
// one-shot handoff flag that PiP entry alone could already consume, before
// the call genuinely ended).
private const val ACTION_CALL_ACTIVITY_DESTROYED = "app.olive.kiosk.CALL_ACTIVITY_DESTROYED"

class WrapperJitsiMeetActivity : JitsiMeetActivity() {
    private val eventStreamHandler = JitsiMeetEventStreamHandler.instance
    private val broadcastReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            this@WrapperJitsiMeetActivity.onBroadcastReceived(intent)
        }
    }

    // Set once we've self-pinned, so a config change or PiP-related onResume
    // doesn't call startLockTask() a second time. This Activity instance
    // only ever hosts one call, so it's never reset.
    private var hasSelfPinned = false
    // Tracked the same way MainActivity.onStop() tracks it, to tell a
    // genuine mid-call defeat (Back+Recents) apart from this Activity simply
    // never having been pinned (a guardian device that was never
    // kiosk-locked, where beginCallHandoff is never called at all).
    private var lastKnownMode = "none"
    // A clean call end (readyToClose) and a mid-call kiosk defeat both end
    // with this Activity unpinned — the same ambiguity call_screen.dart's own
    // header comment already calls out for conferenceTerminated vs
    // readyToClose. Only report a defeat if the SDK never told us it was
    // ready to close first.
    private var didReceiveReadyToClose = false

    private fun currentLockTaskMode(): String =
        when ((getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).lockTaskModeState) {
            ActivityManager.LOCK_TASK_MODE_LOCKED -> "locked"
            ActivityManager.LOCK_TASK_MODE_PINNED -> "pinned"
            else -> "none"
        }

    companion object {
        fun launch(context: Context, options: JitsiMeetConferenceOptions?) {
            val intent = Intent(context, WrapperJitsiMeetActivity::class.java)
            intent.action = "org.jitsi.meet.CONFERENCE"
            intent.putExtra("JitsiMeetConferenceOptions", options)
            if (context !is Activity) {
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        showOnLockscreen()

        // Ensure JitsiMeet is initialized as a safeguard
        try {
            val defaultOptions = JitsiMeetConferenceOptions.Builder().build()
            JitsiMeet.setDefaultConferenceOptions(defaultOptions)
        } catch (e: Exception) {
            // Log or handle initialization error
        }

        super.onCreate(savedInstanceState)
        registerForBroadcastMessages()
    }

    override fun onResume() {
        super.onResume()
        // §16.2 #6 — self-pin for the call's duration, once, only when the
        // host app actually handed the pin off to us (never on a device that
        // was never kiosk-locked to begin with — see beginCallHandoff's own
        // doc comment in kiosk_channel.dart for why that guard lives on the
        // Dart side, one level up from here). Verified, not fire-and-forget,
        // as of 2026-08-24 — see startLockTaskVerified()'s own doc comment
        // below for the real, live-confirmed bug this closes.
        if (!hasSelfPinned && expectingCallHandoff()) {
            hasSelfPinned = true
            startLockTaskVerified()
        }
        lastKnownMode = currentLockTaskMode()
    }

    private fun expectingCallHandoff(): Boolean =
        getSharedPreferences(HANDOFF_PREFS, Context.MODE_PRIVATE)
            .getBoolean(HANDOFF_KEY, false)

    // 2026-08-24 — duplicate of com.olivebranch.olive_client.KioskBridge's
    // own startLockTaskVerified() (see this file's own top-of-file note on
    // why this module can't import that object). Real fix for a
    // live-confirmed bug: startLockTask() can return without throwing yet
    // not actually pin (confirmed live this session on a real Galaxy Tab
    // S9 FE — see CHANGELOG's own disclosed pin-quirk note). The original
    // fire-and-forget call here, combined with hasSelfPinned's own one-shot
    // latch, meant a silent failure here was permanent for the whole call —
    // nothing ever retried.
    //
    // REVISED same day — this function's first version (re-calling
    // startLockTask() on every retry, 3×150ms) itself gave a false failure
    // on a live re-test: real dumpsys/logcat evidence showed Android's own
    // SystemUI confirmation surface for a non-device-owner pin
    // (ScreenPinningRequest/ScreenPinningConfirmation — visible as
    // WindowManager addView/removeView churn) genuinely takes several
    // hundred ms to settle, and re-invoking startLockTask() while that
    // surface is still transitioning risks resetting it rather than
    // helping — see KioskBridge.startLockTaskVerified()'s own doc comment
    // (this file's own sibling, kept in sync by hand) for the full account.
    // Same fix mirrored here: call startLockTask() exactly once, then only
    // POLL — never re-invoke — across a budget with real margin over the
    // observed settle time. Widened to 8×300ms (2.4s) after a further live
    // re-test — see KioskBridge.startLockTaskVerified()'s own doc comment
    // (this file's sibling) for the full evidence trail, including why this
    // still does not claim to make this tablet's pin fully reliable.
    //
    // Also gated on hasWindowFocus() now, same sibling fix, same reasoning:
    // this Activity's own onResume() self-pin above can fire before its
    // window genuinely has focus — plausible here of all places, given this
    // Activity's whole job is mid-multi-window-transition PiP/call handoff.
    private fun startLockTaskVerified(
        totalChecks: Int = 8, delayMs: Long = 300,
        focusChecksLeft: Int = 10, focusDelayMs: Long = 100,
    ) {
        if (!hasWindowFocus() && focusChecksLeft > 1) {
            Handler(Looper.getMainLooper()).postDelayed({
                startLockTaskVerified(totalChecks, delayMs, focusChecksLeft - 1, focusDelayMs)
            }, focusDelayMs)
            return
        }
        startLockTask() // exactly once
        pollLockTaskMode(totalChecks, delayMs)
    }

    private fun pollLockTaskMode(checksLeft: Int, delayMs: Long) {
        if (currentLockTaskMode() != "none") return
        if (checksLeft <= 1) {
            Log.w("WrapperJitsiMeetActivity",
                "startLockTask() did not pin after the full poll budget")
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            pollLockTaskMode(checksLeft - 1, delayMs)
        }, delayMs)
    }

    override fun onStop() {
        super.onStop()
        val current = currentLockTaskMode()
        val wasPinnedByUs = lastKnownMode == "pinned" || lastKnownMode == "locked"
        if (wasPinnedByUs && current == "none" && !didReceiveReadyToClose) {
            // Mid-call defeat: this Activity was pinned and lost that pin
            // before the SDK ever said it was ready to close. Reported back
            // to the app process via a plain broadcast rather than a direct
            // call — see this file's own top-of-file note on why the two
            // modules can't share a compile-time reference. MainActivity
            // (always alive, same process) relays it into the real
            // EventChannel as `lockTaskExited`, same as any other defeat.
            LocalBroadcastManager.getInstance(this)
                .sendBroadcast(Intent(ACTION_CALL_LOCK_TASK_EXITED))
        }
        lastKnownMode = current
    }

    // 2026-08-24 — real defeat-detection at the actual moment PiP begins,
    // not only whenever onStop() eventually fires. Android DEFERS onStop()
    // while a PiP window stays visible, so on a kiosk-locked device that
    // silently lost its pin (T1-1's own bug — startLockTask() returning
    // without actually pinning), a PiP entry could leave the app in an
    // unpinned state with NOTHING reporting it until onStop() eventually
    // fires, possibly much later, possibly never in a way that's still
    // distinguishable from a clean end. onPictureInPictureModeChanged()
    // fires reliably and immediately on the real PiP transition — checking
    // the real lock-task mode right here, rather than assuming the pin
    // held just because PiP itself succeeded, catches a silent pin loss at
    // the earliest possible moment instead of leaving it undetected.
    // Reuses the EXISTING ACTION_CALL_LOCK_TASK_EXITED signal (not a new,
    // separate one) — KioskBridge.kt's own header is explicit that this
    // bridge's job is to "REPORT escape immediately and truthfully," and a
    // silently-lost pin during a real, sanctioned PiP entry is exactly
    // that same category of event, just caught earlier than onStop() ever
    // could.
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        val mode = currentLockTaskMode()
        Log.d("WrapperJitsiMeetActivity",
            "onPictureInPictureModeChanged($isInPictureInPictureMode) lockTaskMode=$mode " +
                "hasSelfPinned=$hasSelfPinned")
        if (isInPictureInPictureMode && hasSelfPinned && mode == "none" && !didReceiveReadyToClose) {
            LocalBroadcastManager.getInstance(this)
                .sendBroadcast(Intent(ACTION_CALL_LOCK_TASK_EXITED))
        }
    }

    private fun showOnLockscreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun registerForBroadcastMessages() {
        val intentFilter = IntentFilter()
        for (eventType in BroadcastEvent.Type.values()) {
            intentFilter.addAction(eventType.action)
        }
        intentFilter.addAction("org.jitsi.meet.ENTER_PICTURE_IN_PICTURE")
        LocalBroadcastManager.getInstance(this)
            .registerReceiver(this.broadcastReceiver, intentFilter)
    }

    private fun onBroadcastReceived(intent: Intent?) {
        if (intent != null) {
            if (intent.action == "org.jitsi.meet.ENTER_PICTURE_IN_PICTURE") {
                enterPiP()
            } else {
                val event = BroadcastEvent(intent)
                val data = event.data
                when (event.type.action!!) {
                    BroadcastEvent.Type.CONFERENCE_JOINED.action -> eventStreamHandler.conferenceJoined(data)
                    BroadcastEvent.Type.CONFERENCE_TERMINATED.action -> eventStreamHandler.conferenceTerminated(
                        data
                    )

                    BroadcastEvent.Type.CONFERENCE_WILL_JOIN.action -> eventStreamHandler.conferenceWillJoin(
                        data
                    )

                    BroadcastEvent.Type.PARTICIPANT_JOINED.action -> eventStreamHandler.participantJoined(data)
                    BroadcastEvent.Type.PARTICIPANT_LEFT.action -> eventStreamHandler.participantLeft(data)
                    BroadcastEvent.Type.AUDIO_MUTED_CHANGED.action -> eventStreamHandler.audioMutedChanged(data)
                    BroadcastEvent.Type.VIDEO_MUTED_CHANGED.action -> eventStreamHandler.videoMutedChanged(data)
                    BroadcastEvent.Type.ENDPOINT_TEXT_MESSAGE_RECEIVED.action -> eventStreamHandler.endpointTextMessageReceived(
                        data
                    )

                    BroadcastEvent.Type.SCREEN_SHARE_TOGGLED.action -> eventStreamHandler.screenShareToggled(
                        data
                    )

                    BroadcastEvent.Type.CHAT_MESSAGE_RECEIVED.action -> eventStreamHandler.chatMessageReceived(
                        data
                    )

                    BroadcastEvent.Type.CHAT_TOGGLED.action -> eventStreamHandler.chatToggled(data)
                    BroadcastEvent.Type.PARTICIPANTS_INFO_RETRIEVED.action -> eventStreamHandler.participantsInfoRetrieved(
                        data
                    )

                    BroadcastEvent.Type.READY_TO_CLOSE.action -> {
                        didReceiveReadyToClose = true
                        eventStreamHandler.readyToClose()
                    }

                    BroadcastEvent.Type.CUSTOM_BUTTON_PRESSED.action -> eventStreamHandler.customButtonPressed(
                        data
                    )

                    else -> {}
                }
            }
        }
    }

    override fun onDestroy() {
        // 2026-08-24 — the one real "this Activity is gone for good" signal,
        // distinct from every onResume() a PiP entry ALSO produces on the
        // host. Sent unconditionally, not just when hasSelfPinned — a
        // guardian device (never pinned, beginCallHandoff never called)
        // simply has no receiver listening for HANDOFF_KEY at all on its
        // side, so this is harmless there; see KioskBridge.kt's own
        // ACTION_CALL_ACTIVITY_DESTROYED doc comment for the fuller account.
        LocalBroadcastManager.getInstance(this)
            .sendBroadcast(Intent(ACTION_CALL_ACTIVITY_DESTROYED))
        LocalBroadcastManager.getInstance(this).unregisterReceiver(this.broadcastReceiver)
        super.onDestroy()
    }

    fun enterPiP() {
        // 2026-08-24 — real diagnostic, not a guess: logs the lock-task
        // mode at the exact moment PiP entry is REQUESTED, before the
        // transition itself. Paired with onPictureInPictureModeChanged()'s
        // own log (fires AFTER the transition completes) above — comparing
        // the two tells whether a pin was already lost going in, or was
        // lost DURING the PiP transition itself, the one distinction this
        // session's own live testing needed and didn't have yet.
        Log.d("WrapperJitsiMeetActivity",
            "enterPiP() requested, lockTaskMode=${currentLockTaskMode()} " +
                "hasSelfPinned=$hasSelfPinned")
        jitsiView?.enterPictureInPicture()
    }
}
