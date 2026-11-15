package com.olivebranch.olive_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Rings a closed or backgrounded app. MASTERFILE §11, §7.18.
//
// WHY A RECEIVER AND NOT DART. A killed app has no Dart isolate, and the plugin's background isolate is the
// unreliable road for something that must ring. The Firebase plugin itself is driven by the same broadcast
// (com.google.android.c2dm.intent.RECEIVE), so this receiver sees every push the plugin sees, with no extra
// dependency and nothing from the Firebase SDK on this module's compile path. Only Google Play services can send
// that broadcast (the manifest requires the c2dm SEND permission), so another app cannot ring the tablet.
//
// WHAT IT READS: the push's `kind` and `ref`, nothing else. A push is content-free by construction
// (packages/transport/src/push.ts), and this file would not know what to do with a name if one were there.
//   call_incoming   -> post the knock notification (unless the app is open, when Dart knocks itself)
//   call_cancelled  -> take the notification away (the caller hung up); silent, no sound, nothing shown
//   anything else   -> not this receiver's business: message_ready's banner is drawn by the system from the
//                      push itself on the `reminders` channel, and the plugin handles the rest
//
// A `ref` that is not a canonical session id is dropped before anything is posted.
class OlivePushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RECEIVE) return
        val extras = intent.extras ?: return
        val kind = extras.getString(OliveNotifications.EXTRA_KIND) ?: return
        val ref = extras.getString(OliveNotifications.EXTRA_REF)
        if (!OliveNotifications.isSessionId(ref)) return
        try {
            when (kind) {
                KIND_CALL_INCOMING ->
                    if (!OliveNotifications.appInForeground(context)) OliveNotifications.postRing(context, ref!!)
                KIND_CALL_CANCELLED -> OliveNotifications.cancelRing(context, ref)
            }
        } catch (e: RuntimeException) {
            // A push must never be able to crash the app. Nothing is shown; the knock times out on its own.
            android.util.Log.w("OlivePushReceiver", "could not handle a push: " + e.javaClass.simpleName)
        }
    }

    companion object {
        const val ACTION_RECEIVE = "com.google.android.c2dm.intent.RECEIVE"
        const val KIND_CALL_INCOMING = "call_incoming"
        const val KIND_CALL_CANCELLED = "call_cancelled"
    }
}
