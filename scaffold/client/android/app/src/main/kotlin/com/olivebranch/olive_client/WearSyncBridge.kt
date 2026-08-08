// OLIVE BRANCH — phone-side Wear Data Layer bridge. UNVERIFIED (compiled via
// `:app:compileDebugKotlin`, not confirmed against a real paired watch this
// pass). MASTERFILE §21.5.
//
// Closes half of the gap a prior feasibility audit flagged: the Wear OS
// companion module (android/wear/) rendered a hardcoded
// DEMO_SLEEPS_UNTIL_HANDOVER constant with no phone->watch sync of any kind
// -- no play-services-wearable dependency on the phone side, no
// WearableListenerService, no DataClient listener on the watch. This is the
// phone-side half: a MethodChannel (wear_sync_channel.dart calls it) backed
// by a real DataClient.putDataItem() call, mirroring KioskBridge.kt's own
// pattern in this same package (an object exposing named channel/method
// constants and a `register` function, contract-checked against its Dart
// caller by transport.test.mjs).
//
// Deliberately narrow, matching the task this was scoped to: ONE value
// (sleepsUntilHandover), not a general-purpose sync mechanism, and no
// "presence" companion field -- no computation logic for presence exists
// anywhere yet, so there is nothing honest to send. The "Call Dad" ->
// MessageClient round trip back to the phone (wear/MainActivity.kt's own
// header) is a separate, larger piece of native+Flutter glue and is not
// built here either.
//
// UNVERIFIED, specifically: unlike KioskBridge.kt (built, installed, and
// manually verified on a real device before its own marker was removed),
// no Wear OS emulator was installed and no physical Watch6 was paired this
// pass (disk-space caution) to confirm putDataItem() here actually reaches
// wear/.../MainActivity.kt's listener. Drop this marker only once someone
// does that round trip for real -- see wear/MainActivity.kt's own header for
// the two specific things static compilation cannot catch.
package com.olivebranch.olive_client

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodChannel

object WearSyncBridge {
    // Mirrored in client/lib/wear_sync_channel.dart and contract-checked
    // against it by transport.test.mjs, the same way KioskBridge's channel
    // names are checked against kiosk_channel.dart.
    const val METHOD_CHANNEL = "com.olivebranch.olive_client/wear_sync"

    const val M_SYNC_SLEEPS_UNTIL_HANDOVER = "syncSleepsUntilHandover"

    // DataItem path and key the watch's OnDataChangedListener (wear/.../
    // MainActivity.kt) reads from. "now" because this rides the same DataItem
    // the phone's own /v1/children/:childId/now endpoint would eventually
    // back, if/when this bridge grows beyond one field.
    const val PATH_NOW = "/olive/now"
    const val KEY_SLEEPS_UNTIL_HANDOVER = "sleepsUntilHandover"

    fun register(context: Context, methods: MethodChannel) {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                M_SYNC_SLEEPS_UNTIL_HANDOVER -> {
                    val sleeps = call.arguments as? Int
                    if (sleeps == null) {
                        result.error("bad_args",
                            "syncSleepsUntilHandover requires an int argument", null)
                        return@setMethodCallHandler
                    }
                    val request = PutDataMapRequest.create(PATH_NOW).apply {
                        dataMap.putInt(KEY_SLEEPS_UNTIL_HANDOVER, sleeps)
                        // DataClient only notifies listeners when the DataItem's
                        // content actually changes -- two consecutive syncs of
                        // the same integer (e.g. re-launching the app on the
                        // same day) would otherwise never reach the watch a
                        // second time. A timestamp keeps every sync a real
                        // change.
                        dataMap.putLong("syncedAtMillis", System.currentTimeMillis())
                    }.asPutDataRequest().setUrgent()
                    // Success here means the Data Layer accepted the item
                    // locally, NOT that the watch has received it -- sync to a
                    // paired device is asynchronous and best-effort, and there
                    // is no ack path back to the phone in this pass.
                    Wearable.getDataClient(context).putDataItem(request)
                        .addOnSuccessListener { result.success(true) }
                        .addOnFailureListener { e ->
                            result.error("put_data_item_failed", e.message, null)
                        }
                }
                else -> result.notImplemented()
            }
        }
    }
}
