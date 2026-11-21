package com.olivebranch.olive_client

import android.app.Activity
import android.app.ActivityManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

// OLIVE BRANCH -- the app updater's native half for the DIRECT flavor (sideload, GitHub releases, a family's own
// server). MASTERFILE 7.24. Dart side: client/lib/update_platform.dart (UpdateNativeChannel); the channel and method
// names are contract-checked against it by test/update_source_test.dart.
//
// WHAT THIS DOES: reads a downloaded file WITHOUT installing it (package name, version, signing certificates), and, only
// when asked, streams it into an Android PackageInstaller session and commits it. Android then shows its OWN
// confirmation; there is no silent install and no root. The file is checked against the SHA-256 and size the Dart side
// verified from the signed manifest while it is copied into the session (a second look: a file touched after it was
// verified is refused here and the session is abandoned).
//
// WHAT IT NEVER DOES: install without the system confirmation, install from a path outside the app's own update
// folder, run while a kiosk lock-task is active (the system dialog would be swallowed and the child's screen disturbed:
// it answers "kioskLocked" and does nothing), or accept a file for another package. REQUEST_INSTALL_PACKAGES is
// declared ONLY in this flavor's manifest (src/direct/AndroidManifest.xml); the play flavor has no install code at all.
//
// THE INSTALLER'S ANSWERS come back to a receiver that is registered here, at run time, for the lifetime of the process,
// and is NOT exported (a manifest receiver would need a second line in src/direct/AndroidManifest.xml, which belongs to the
// flavor split). If the process is gone before the answer arrives (Android replaces the app when the install succeeds), the
// next start reconciles from the installed version (UpdateController._reconcile), so nothing depends on the answer.
//
// NO FileProvider: a PackageInstaller session reads the file from the app's own private folder through a stream, so no
// content URI is ever shared and no provider is declared (a provider would be extra surface for nothing).
//
// NOT COMPILED LOCALLY (no Gradle on the authoring machine, by rule): written against the public SDK surface only
// (compileSdk 36, minSdk 26). CI's release-smoke and the verify Android gate compile it.
object UpdateBridge {
    const val CHANNEL = "app.olive/update"
    const val FLAVOR = "direct"

    const val M_ENVIRONMENT = "environment"
    const val M_CAN_INSTALL = "directCanInstall"
    const val M_OPEN_INSTALL_SETTINGS = "directOpenInstallSettings"
    const val M_INSPECT = "directInspect"
    const val M_INSTALL = "directInstall"
    const val E_INSTALL = "installEvent"

    /** The folder inside the app's own files that the Dart updater keeps its downloads in (UpdateStaging). */
    const val STAGING_DIR = "olive_updates"
    const val ACTION_STATUS = "com.olivebranch.olive_client.UPDATE_STATUS"

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    internal var channel: MethodChannel? = null

    private var receiverRegistered = false

    fun register(activity: Activity, ch: MethodChannel) {
        channel = ch
        val app = activity.applicationContext
        if (!receiverRegistered) {
            receiverRegistered = true
            val filter = IntentFilter(ACTION_STATUS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                app.registerReceiver(UpdateStatusReceiver(), filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                app.registerReceiver(UpdateStatusReceiver(), filter)
            }
        }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                M_ENVIRONMENT -> result.success(UpdateEnvironment.snapshot(app, FLAVOR))
                M_CAN_INSTALL -> result.success(app.packageManager.canRequestPackageInstalls())
                M_OPEN_INSTALL_SETTINGS -> {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + app.packageName))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("unavailable", null, null)
                    }
                }
                M_INSPECT -> {
                    val path = call.argument<String>("path")
                    worker.execute {
                        val out = if (path == null) null else inspect(app, path)
                        main.post { result.success(out) }
                    }
                }
                M_INSTALL -> {
                    val path = call.argument<String>("path")
                    val sha = call.argument<String>("sha256")
                    val size = (call.argument<Number>("size") ?: 0).toLong()
                    val versionCode = (call.argument<Number>("versionCode") ?: 0).toLong()
                    if (path == null || sha == null || size <= 0) {
                        result.success("refused")
                    } else if (lockTaskActive(app)) {
                        result.success("kioskLocked")
                    } else if (!app.packageManager.canRequestPackageInstalls()) {
                        result.success("needsPermission")
                    } else {
                        worker.execute {
                            val answer = install(app, path, sha, size, versionCode)
                            main.post { result.success(answer) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Play-flavor hooks the shared MainActivity calls; nothing to do in this flavor. */
    @Suppress("UNUSED_PARAMETER")
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean = false

    @Suppress("UNUSED_PARAMETER")
    fun onResume(activity: Activity) {}

    private fun lockTaskActive(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
    }

    /** Only a file inside the app's own update folder is ever read. */
    private fun stagedFile(context: Context, path: String): File? {
        return try {
            val dir = File(context.filesDir, STAGING_DIR).canonicalFile
            val f = File(path).canonicalFile
            if (f.parentFile == dir && f.isFile) f else null
        } catch (e: Exception) {
            null
        }
    }

    private fun hex(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) sb.append(String.format("%02x", b))
        return sb.toString()
    }

    /**
     * SHA-256 of the signing certificates. For the INSTALLED app the whole lineage is listed (a key that was rotated
     * keeps its history, so an update signed by the newer key still matches); for a downloaded FILE only the
     * certificate(s) it is signed with now are listed, so a pinned certificate must be one it really carries.
     */
    @Suppress("DEPRECATION")
    private fun signerHashes(info: android.content.pm.PackageInfo?, includeHistory: Boolean): List<String> {
        if (info == null) return emptyList()
        val sigs: Array<android.content.pm.Signature>? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val si = info.signingInfo
                if (si == null) null
                else if (si.hasMultipleSigners() || !includeHistory) si.apkContentsSigners
                else si.signingCertificateHistory
            } else {
                info.signatures
            }
        if (sigs == null) return emptyList()
        val md = MessageDigest.getInstance("SHA-256")
        return sigs.map { hex(md.digest(it.toByteArray())) }
    }

    @Suppress("DEPRECATION")
    private fun inspect(context: Context, path: String): Map<String, Any?>? {
        val f = stagedFile(context, path) ?: return null
        return try {
            val pm = context.packageManager
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                PackageManager.GET_SIGNATURES
            }
            val archive = pm.getPackageArchiveInfo(f.path, flags) ?: return null
            val installed = pm.getPackageInfo(context.packageName, flags)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) archive.longVersionCode else archive.versionCode.toLong()
            mapOf(
                "packageName" to archive.packageName,
                "versionCode" to code,
                "signers" to signerHashes(archive, false),
                "installedSigners" to signerHashes(installed, true),
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Streams the verified file into a PackageInstaller session, checking size and SHA-256 as it goes, and commits it.
     * Returns "waiting" (the system confirmation is coming), or "refused".
     */
    private fun install(context: Context, path: String, sha256: String, size: Long, versionCode: Long): String {
        val file = stagedFile(context, path) ?: return "refused"
        if (file.length() != size) return "refused"
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        params.setSize(size)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }
        val id = installer.createSession(params)
        val session = installer.openSession(id)
        try {
            val md = MessageDigest.getInstance("SHA-256")
            var copied = 0L
            file.inputStream().use { input ->
                session.openWrite("olive.apk", 0, size).use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        copied += n
                        if (copied > size) throw IllegalStateException("longer than declared")
                        md.update(buf, 0, n)
                        out.write(buf, 0, n)
                    }
                    session.fsync(out)
                }
            }
            if (copied != size || hex(md.digest()) != sha256) throw IllegalStateException("not the verified file")
            // Explicit enough for a mutable PendingIntent: an action AND this app's own package (never delivered elsewhere).
            val intent = Intent(ACTION_STATUS)
            intent.setPackage(context.packageName)
            intent.putExtra("versionCode", versionCode)
            // The installer adds its status extras to this intent, so the PendingIntent must be mutable.
            val pending = PendingIntent.getBroadcast(
                context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            session.commit(pending.intentSender)
            return "waiting"
        } catch (e: Exception) {
            try {
                session.abandon()
            } catch (ignored: Exception) {
            }
            return "refused"
        } finally {
            session.close()
        }
    }

    /** Called by [UpdateStatusReceiver] on the main thread. */
    internal fun emit(status: String, versionCode: Long) {
        channel?.invokeMethod(E_INSTALL, mapOf("status" to status, "versionCode" to versionCode))
    }
}
