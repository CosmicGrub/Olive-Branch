package com.olivebranch.olive_client

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

// The phone's own notification surface for Olive: the two channels the server's pushes name, and the one
// call notification. MASTERFILE §11, §5.25.2, §7.18. Mirrors incoming_call_channel.dart.
//
// CHANNELS. packages/transport/src/push.ts puts a push on `calls` (call_incoming, call_cancelled) or `reminders`
// (everything else, including the delivery worker's message_ready). Android shows a push that carries a
// notification block on the channel the push names, and silently falls back to a generic "Miscellaneous"
// channel when that channel does not exist. So both are created at start-up (idempotent), before any push can
// need them. The ids below are contract-checked against push.ts by test/android_push_contract_test.dart.
//
// THE KNOCK, NOT AN ALARM (§5.25.2). The call notification uses the default notification sound (not a
// ringtone), never repeats, never escalates, and removes itself after the knock's own ninety seconds. It has
// no action buttons: the answers ("Answer", "Just talking", "Not now") live on the knock screen inside the
// app, and no button on the phone offers a word of refusal. Its words come from strings.xml and say nothing
// about who or what. The launcher badge is switched off for both channels, because a badge is a count.
//
// LOCK SCREEN. Both channels and the ring are VISIBILITY_PRIVATE: on a locked phone Android shows only the app name and its
// own "contents hidden" line, whatever the text is (ISS-107). The words are content-free anyway; this is the second lock.
// The knock itself opens over the lock screen through the full-screen intent, which private visibility does not affect.
//
// WHAT IT NEVER DOES: read anything but the push's `kind` and `ref` (the receiver), carry a name or a body,
// or post anything while the app is open on screen (the open app knocks itself; a banner over a pinned
// kiosk would only be noise, and lock-task mode hides it anyway).
object OliveNotifications {
    const val CHANNEL_CALLS = "calls"
    const val CHANNEL_REMINDERS = "reminders"

    /** One ring at a time on screen; the session id is the notification's tag so a hang-up removes the right one. */
    private const val RING_ID = 7101

    /** The knock waits ninety seconds (call_knock.dart knockWaitsSeconds). */
    const val RING_WINDOW_MS = 90_000L

    const val EXTRA_KIND = "kind"
    const val EXTRA_REF = "ref"

    private val SESSION_ID = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    /** Only a canonical session id is believed (the server mints nothing else); anything else is dropped. */
    fun isSessionId(value: String?): Boolean = value != null && value.length == 36 && SESSION_ID.matches(value)

    /** One spelling of a session id everywhere (notification tag, ring record, Dart memory): lower case. */
    fun canonicalRef(value: String): String = value.lowercase()

    // THE RING RECORD. MainActivity has to be exported (it is the launcher), so any app on the device, or
    // `adb shell am start`, can send it an intent with the ring action and a well-formed ref. The intent
    // therefore proves nothing. What proves a ring is real is that OlivePushReceiver posted it: postRing writes
    // the ref and the time into this private file BEFORE it notifies, and IncomingCallBridge.handleIntent only
    // rings for a ref it can take out of it (once, and only inside the knock's ninety seconds). A forged intent
    // finds nothing, wakes nothing and knocks nothing. The file is private to this app, so another app cannot
    // write to it either.
    private const val RING_PREFS = "olive_rings"

    private fun ringPrefs(context: Context) = context.getSharedPreferences(RING_PREFS, Context.MODE_PRIVATE)

    /** Remember that this app itself posted a ring for [ref] at [at]; forget anything older than the knock's window. */
    fun recordPosted(context: Context, ref: String, at: Long) {
        val prefs = ringPrefs(context)
        val edit = prefs.edit()
        for ((key, value) in prefs.all) {
            if (value !is Long || at - value > RING_WINDOW_MS || value > at) edit.remove(key)
        }
        edit.putLong(canonicalRef(ref), at).commit()
    }

    /**
     * Takes [ref] out of the record: returns the time it was posted if this app posted it and it is still inside
     * the knock's window, otherwise null. Taking it removes it, so a ring can open the app only once.
     */
    fun takePosted(context: Context, ref: String, now: Long): Long? {
        val prefs = ringPrefs(context)
        val key = canonicalRef(ref)
        val at = prefs.getLong(key, 0L)
        if (at <= 0L) return null
        prefs.edit().remove(key).commit()
        if (at > now || now - at > RING_WINDOW_MS) return null
        return at
    }

    private fun forgetPosted(context: Context, ref: String) {
        ringPrefs(context).edit().remove(canonicalRef(ref)).commit()
    }

    fun ensureChannels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val calls = NotificationChannel(
            CHANNEL_CALLS,
            context.getString(R.string.olive_channel_calls_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.olive_channel_calls_desc)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(false)
        }
        val reminders = NotificationChannel(
            CHANNEL_REMINDERS,
            context.getString(R.string.olive_channel_reminders_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.olive_channel_reminders_desc)
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            setShowBadge(false)
        }
        nm.createNotificationChannels(listOf(calls, reminders))
    }

    /**
     * True when this app's own process is the one on screen. The Firebase plugin delivers a push to Dart through
     * the open app in exactly this state, and Dart knocks by itself, so the phone's notification stays out of it.
     * Same test the plugin itself uses to choose between its foreground and background roads.
     */
    fun appInForeground(context: Context): Boolean {
        val am = context.getSystemService(ActivityManager::class.java) ?: return false
        val processes = am.runningAppProcesses ?: return false
        val me = context.packageName
        return processes.any {
            it.processName == me && it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        }
    }

    fun postRing(context: Context, rawRef: String) {
        if (!isSessionId(rawRef)) return
        val ref = canonicalRef(rawRef)
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (!nm.areNotificationsEnabled()) return
        ensureChannels(context)
        val postedAt = System.currentTimeMillis()
        recordPosted(context, ref, postedAt)
        val open = Intent(context, MainActivity::class.java).apply {
            action = IncomingCallBridge.ACTION_RING
            putExtra(EXTRA_REF, ref)
            putExtra(IncomingCallBridge.EXTRA_AT, postedAt)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pending = PendingIntent.getActivity(
            context,
            ref.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(context, CHANNEL_CALLS)
            .setSmallIcon(R.drawable.ic_stat_olive)
            .setContentTitle(context.getString(R.string.olive_ring_title))
            .setContentText(context.getString(R.string.olive_ring_text))
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setTimeoutAfter(RING_WINDOW_MS)
            .setContentIntent(pending)
            // Opens the knock over the lock screen when the screen is off or locked. Where the phone has not
            // allowed that (Android 14 and later: the "full-screen notifications" switch), it quietly becomes
            // an ordinary heads-up notification, which is the honest fallback.
            .setFullScreenIntent(pending, true)
            .build()
        nm.notify(ref, RING_ID, notification)
    }

    fun cancelRing(context: Context, ref: String?) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (ref != null && isSessionId(ref)) {
            forgetPosted(context, ref)
            nm.cancel(canonicalRef(ref), RING_ID)
        } else {
            // "Whatever ring is up": remove every ring this app has posted.
            nm.activeNotifications
                .filter { it.id == RING_ID }
                .forEach { nm.cancel(it.tag, it.id) }
        }
    }
}
