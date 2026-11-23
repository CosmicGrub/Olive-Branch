package com.olivebranch.olive_client

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.StatFs

// OLIVE BRANCH -- what the phone says about itself, for the app updater (client/lib/update_platform.dart,
// MASTERFILE 7.24). Shared by BOTH distribution flavors: reading the battery, the connection and the free space
// installs nothing and needs no permission beyond ACCESS_NETWORK_STATE, which the app already holds. Every value
// is best effort: a value the phone will not give is simply left out, and the Dart side treats "unknown" as
// "do not block". Nothing here is sent anywhere; the map goes to the one Dart caller over the MethodChannel.
//
// NOT COMPILED LOCALLY (no Gradle on the authoring machine, by rule): written against the public SDK surface only
// (compileSdk 36, minSdk 26). CI's release-smoke and the verify Android gate compile it.
object UpdateEnvironment {
    @Suppress("DEPRECATION")
    fun snapshot(context: Context, flavor: String): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["flavor"] = flavor
        try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            out["versionCode"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                info.versionCode.toLong()
            }
            out["versionName"] = info.versionName ?: ""
        } catch (e: Exception) {
            out["versionCode"] = 0L
            out["versionName"] = ""
        }
        out["abis"] = Build.SUPPORTED_ABIS.toList()
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val net = cm.activeNetwork
            val caps = if (net == null) null else cm.getNetworkCapabilities(net)
            out["network"] = when {
                caps == null -> "none"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                else -> "unknown"
            }
            out["metered"] = cm.isActiveNetworkMetered
            out["roaming"] = caps != null && !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING)
            // Data Saver (background data restricted for this app): the updater stays out of the way while it is on.
            out["dataSaver"] = cm.restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
        } catch (e: Exception) {
            out["network"] = "unknown"
        }
        try {
            val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (battery != null) {
                val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                if (level >= 0 && scale > 0) out["batteryPercent"] = (level * 100) / scale
                val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                out["charging"] = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            }
        } catch (e: Exception) {
            // unknown: not blocked
        }
        try {
            out["freeBytes"] = StatFs(context.filesDir.path).availableBytes
        } catch (e: Exception) {
            // unknown: not blocked
        }
        return out
    }
}
