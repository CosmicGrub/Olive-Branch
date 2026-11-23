package com.olivebranch.olive_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

// OLIVE BRANCH -- receives the PackageInstaller's answers for the DIRECT flavor's update session (UpdateBridge.kt).
// MASTERFILE 7.24. Registered at run time by UpdateBridge.register, NOT exported (on Android 13 and later; earlier
// versions cannot say so, and an answer a stranger forged would only change what a grown-up sees on a screen, never
// what is installed): only the system installer, through the PendingIntent the bridge handed it, normally reaches it.
//
// STATUS_PENDING_USER_ACTION is Android asking the person to confirm: the confirmation screen it names is started
// (that is the one step that needs a person, and it is Android's own screen). Every other status is a final answer and
// is passed to Dart as a plain word (UpdateNativeChannel in client/lib/update_platform.dart); nothing from the
// installer's message is forwarded (it can name paths).
//
// NOT COMPILED LOCALLY (no Gradle on the authoring machine, by rule). CI compiles it.
class UpdateStatusReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val versionCode = intent.getLongExtra("versionCode", 0L)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = intent.getParcelableExtra(Intent.EXTRA_INTENT)
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(confirm)
                    } catch (e: Exception) {
                        UpdateBridge.emit("failed", versionCode)
                    }
                }
            }
            PackageInstaller.STATUS_SUCCESS -> UpdateBridge.emit("success", versionCode)
            PackageInstaller.STATUS_FAILURE_ABORTED -> UpdateBridge.emit("declined", versionCode)
            PackageInstaller.STATUS_FAILURE_BLOCKED -> UpdateBridge.emit("blocked", versionCode)
            PackageInstaller.STATUS_FAILURE_INVALID -> UpdateBridge.emit("invalid", versionCode)
            PackageInstaller.STATUS_FAILURE_CONFLICT -> UpdateBridge.emit("conflict", versionCode)
            PackageInstaller.STATUS_FAILURE_STORAGE -> UpdateBridge.emit("storage", versionCode)
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> UpdateBridge.emit("incompatible", versionCode)
            else -> UpdateBridge.emit("failed", versionCode)
        }
    }
}
