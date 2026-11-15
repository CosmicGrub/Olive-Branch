package com.olivebranch.olive_client

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.MethodChannel

// The native end of incoming_call_channel.dart. MASTERFILE §5.25.2, §5.20, §7.18.
//
// It does four small things and no more:
//  1. Remembers the ring that OPENED the app (a tap on the knock notification, or the full-screen intent that
//     fired while the screen was off) until Dart attaches and asks for it once ("attach"). A ring that arrives
//     while Dart is attached is pushed to it as a "ring" event instead.
//  2. While a ring is up it lets the activity show over the lock screen and wake the screen, and puts that
//     back the moment the ring is put away ("ringFinished") or the activity stops. Nothing else about the lock
//     screen is touched: it never dismisses the keyguard, so a PIN-locked phone stays PIN-locked.
//  3. Answers two questions for the grown-up's "Alerts on this tablet" card (status) and performs the two
//     taps that card offers (the one-time notifications permission box, the full-screen settings page).
//  4. Refuses forged, stale or malformed rings: an intent whose ref is not a canonical session id, or that this
//     app's own OlivePushReceiver did not post (the ring record in OliveNotifications), or that was posted more
//     than the knock's ninety seconds ago, is ignored and wakes nothing. The intent is consumed when read, so an
//     activity that is recreated with the same intent cannot ring twice.
//
// The kiosk rules are unchanged by it and are applied in Dart (incoming_call.dart): a ring never covers a
// grown-up in Guardian mode, and calling never changes the lock.
object IncomingCallBridge {
    const val METHOD_CHANNEL = "app.olive/incoming_call"
    const val ACTION_RING = "com.olivebranch.olive_client.INCOMING_RING"
    const val EXTRA_AT = "at"

    private const val M_ATTACH = "attach"
    private const val M_RING_FINISHED = "ringFinished"
    private const val M_STATUS = "status"
    private const val M_REQUEST_NOTIFICATIONS = "requestNotifications"
    private const val M_OPEN_FULL_SCREEN_SETTINGS = "openFullScreenSettings"
    private const val E_RING = "ring"
    private const val E_CANCEL = "cancel"
    private const val K_REF = "ref"
    private const val K_AT = "at"

    const val REQ_NOTIFICATIONS = 4711

    private var channel: MethodChannel? = null
    private var attached = false
    private var pendingRing: Map<String, Any>? = null
    private var pendingPermission: MethodChannel.Result? = null

    fun register(activity: Activity, methodChannel: MethodChannel) {
        channel = methodChannel
        attached = false
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                M_ATTACH -> {
                    attached = true
                    val first = pendingRing
                    pendingRing = null
                    result.success(first)
                }
                M_RING_FINISHED -> {
                    val ref = (call.arguments as? Map<*, *>)?.get(K_REF) as? String
                    OliveNotifications.cancelRing(activity, ref)
                    showOverLockScreen(activity, false)
                    result.success(null)
                }
                M_STATUS -> result.success(status(activity))
                M_REQUEST_NOTIFICATIONS -> requestNotifications(activity, result)
                M_OPEN_FULL_SCREEN_SETTINGS -> {
                    openFullScreenSettings(activity)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Called from MainActivity.onCreate and onNewIntent with whatever intent just arrived. */
    fun handleIntent(activity: Activity, intent: Intent?) {
        if (intent == null || intent.action != ACTION_RING) return
        val ref = intent.getStringExtra(OliveNotifications.EXTRA_REF)
        // Consume it: a recreated activity, or a second delivery of this intent, must not ring again.
        intent.action = null
        if (!OliveNotifications.isSessionId(ref)) return
        // The intent itself proves nothing (this activity is exported, so any app can send this action with a
        // well-formed ref). Only a ring that OlivePushReceiver really posted is believed: it is in the private ring
        // record, once, and inside the knock's window. The time used is the recorded one, never the intent's.
        val at = OliveNotifications.takePosted(activity, ref!!, System.currentTimeMillis()) ?: return
        showOverLockScreen(activity, true)
        val ring = mapOf<String, Any>(K_REF to OliveNotifications.canonicalRef(ref), K_AT to at)
        if (attached && channel != null) {
            channel!!.invokeMethod(E_RING, ring)
        } else {
            pendingRing = ring
        }
    }

    /** The activity is no longer in front: give the lock screen back. */
    fun onActivityStopped(activity: Activity) {
        showOverLockScreen(activity, false)
    }

    fun onDestroyed() {
        attached = false
        channel = null
    }

    fun onPermissionResult(activity: Activity, requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_NOTIFICATIONS) return
        val result = pendingPermission ?: return
        pendingPermission = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(granted && notificationsEnabled(activity))
    }

    @Suppress("DEPRECATION")
    private fun showOverLockScreen(activity: Activity, on: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            activity.setShowWhenLocked(on)
            activity.setTurnScreenOn(on)
        } else {
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) activity.window.addFlags(flags) else activity.window.clearFlags(flags)
        }
    }

    private fun notificationsEnabled(activity: Activity): Boolean =
        activity.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: false

    private fun fullScreenAllowed(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        return activity.getSystemService(NotificationManager::class.java)?.canUseFullScreenIntent() ?: false
    }

    private fun status(activity: Activity): Map<String, Any> = mapOf(
        "notifications" to notificationsEnabled(activity),
        "fullScreen" to fullScreenAllowed(activity),
    )

    private fun requestNotifications(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || notificationsEnabled(activity)) {
            result.success(notificationsEnabled(activity))
            return
        }
        if (pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    private fun openFullScreenSettings(activity: Activity) {
        val uri = Uri.fromParts("package", activity.packageName, null)
        val target = if (Build.VERSION.SDK_INT >= 34) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, uri)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
        }
        try {
            activity.startActivity(target)
        } catch (e: RuntimeException) {
            try {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri))
            } catch (e2: RuntimeException) {
                // Nothing to open; the card keeps saying what is still off.
            }
        }
    }
}
