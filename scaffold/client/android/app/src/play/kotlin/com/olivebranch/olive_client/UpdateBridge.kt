package com.olivebranch.olive_client

import android.app.Activity
import android.content.Context
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallException
import com.google.android.play.core.install.InstallState
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallErrorCode
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.MethodChannel

// OLIVE BRANCH -- the app updater's native half for the GOOGLE PLAY flavor. MASTERFILE 7.24. Dart side:
// client/lib/update_platform.dart (UpdateNativeChannel); the channel and method names are contract-checked against it
// by test/update_source_test.dart.
//
// PLAY POLICY: this flavor updates ONLY through Google Play's In-App Updates API. It contains NO PackageInstaller
// code, no file download, no install intent and no REQUEST_INSTALL_PACKAGES (this flavor's manifest removes the
// permission explicitly, so a library cannot add it back). It answers only the shared "environment" call and the three
// "play*" calls; the direct flavor's calls answer "not implemented", which the Dart side treats as "not available".
//
// FLEXIBLE vs IMMEDIATE: flexible (Play downloads in the background, the grown-up chooses when to restart) by default;
// immediate (Play's own full-screen flow) only when the Dart side asks for it, which it does only for an update the
// owner marked critical (in-app update priority 4 or 5) that Play allows as immediate. Whether a grown-up is looking at
// the screen is the Dart side's business: only a grown-up's screen can call these.
//
// NOT COMPILED LOCALLY (no Gradle on the authoring machine, by rule): written against the Play In-App Updates 2.1.0
// public API (com.google.android.play:app-update, play flavor only). CI compiles it.
object UpdateBridge {
    const val CHANNEL = "app.olive/update"
    const val FLAVOR = "play"

    const val M_ENVIRONMENT = "environment"
    const val M_PLAY_CHECK = "playCheck"
    const val M_PLAY_START = "playStart"
    const val M_PLAY_COMPLETE = "playComplete"
    const val E_PLAY = "playEvent"

    private const val REQUEST_CODE = 7121

    @Volatile
    private var channel: MethodChannel? = null
    private var manager: AppUpdateManager? = null
    private var lastInfo: AppUpdateInfo? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingImmediate = false

    private val listener = InstallStateUpdatedListener { state: InstallState -> onInstallState(state) }

    fun register(activity: Activity, ch: MethodChannel) {
        channel = ch
        val app = activity.applicationContext
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                M_ENVIRONMENT -> result.success(UpdateEnvironment.snapshot(app, FLAVOR))
                M_PLAY_CHECK -> check(app, result)
                M_PLAY_START -> start(activity, call.argument<Boolean>("immediate") ?: false, result)
                M_PLAY_COMPLETE -> {
                    manager?.completeUpdate()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun manager(context: Context): AppUpdateManager {
        val m = manager ?: AppUpdateManagerFactory.create(context)
        manager = m
        return m
    }

    private fun check(context: Context, result: MethodChannel.Result) {
        val m = manager(context)
        m.appUpdateInfo.addOnSuccessListener { info ->
            lastInfo = info
            val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
            result.success(
                mapOf(
                    "available" to available,
                    "supported" to true,
                    "versionCode" to info.availableVersionCode(),
                    "priority" to info.updatePriority(),
                    "staleDays" to (info.clientVersionStalenessDays() ?: 0),
                    "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                    "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                    "downloaded" to (info.installStatus() == InstallStatus.DOWNLOADED),
                ),
            )
        }.addOnFailureListener { e ->
            // A copy of this build that Google Play did not install (or a phone without Play) has no update to offer
            // through Play: the Dart side steps aside quietly instead of showing an error.
            val code = (e as? InstallException)?.errorCode
            val notPlay = code == InstallErrorCode.ERROR_APP_NOT_OWNED || code == InstallErrorCode.ERROR_PLAY_STORE_NOT_FOUND
            if (notPlay) {
                result.success(mapOf("available" to false, "supported" to false))
            } else {
                result.error("unavailable", null, null)
            }
        }
    }

    private fun start(activity: Activity, immediate: Boolean, result: MethodChannel.Result) {
        val m = manager(activity.applicationContext)
        val info = lastInfo
        if (info == null || info.updateAvailability() != UpdateAvailability.UPDATE_AVAILABLE) {
            result.success(false)
            return
        }
        val type = if (immediate) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
        if (!info.isUpdateTypeAllowed(type)) {
            result.success(false)
            return
        }
        try {
            if (!immediate) m.registerListener(listener)
            pendingResult = result
            pendingImmediate = immediate
            val started = m.startUpdateFlowForResult(info, activity, AppUpdateOptions.newBuilder(type).build(), REQUEST_CODE)
            if (!started) {
                pendingResult = null
                result.success(false)
            }
        } catch (e: Exception) {
            pendingResult = null
            result.success(false)
        }
    }

    /** The activity result of Play's own consent screen: answers the pending "start" call. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val r = pendingResult
        pendingResult = null
        // RESULT_OK = the person agreed; anything else (cancelled, Play's own failure code) = nothing started.
        r?.success(resultCode == Activity.RESULT_OK)
        if (resultCode != Activity.RESULT_OK) emit("cancelled", 0L, 0L)
        return true
    }

    /** An immediate update that was started and interrupted must carry on when the app comes back. */
    fun onResume(activity: Activity) {
        val m = manager ?: return
        m.appUpdateInfo.addOnSuccessListener { info ->
            if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS && pendingImmediate) {
                try {
                    m.startUpdateFlowForResult(info, activity, AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(), REQUEST_CODE)
                } catch (e: Exception) {
                    // Play will offer it again at the next check.
                }
            } else if (info.installStatus() == InstallStatus.DOWNLOADED) {
                emit("downloaded", 0L, 0L)
            }
        }
    }

    private fun onInstallState(state: InstallState) {
        when (state.installStatus()) {
            InstallStatus.PENDING -> emit("pending", 0L, 0L)
            InstallStatus.DOWNLOADING -> emit("downloading", state.bytesDownloaded(), state.totalBytesToDownload())
            InstallStatus.DOWNLOADED -> emit("downloaded", 0L, 0L)
            InstallStatus.INSTALLING -> emit("installing", 0L, 0L)
            InstallStatus.INSTALLED -> {
                manager?.unregisterListener(listener)
                emit("installed", 0L, 0L)
            }
            InstallStatus.CANCELED -> {
                manager?.unregisterListener(listener)
                emit("cancelled", 0L, 0L)
            }
            InstallStatus.FAILED -> {
                manager?.unregisterListener(listener)
                emit("failed", 0L, 0L)
            }
            else -> {}
        }
    }

    private fun emit(status: String, bytes: Long, total: Long) {
        channel?.invokeMethod(E_PLAY, mapOf("status" to status, "bytes" to bytes, "total" to total))
    }
}
