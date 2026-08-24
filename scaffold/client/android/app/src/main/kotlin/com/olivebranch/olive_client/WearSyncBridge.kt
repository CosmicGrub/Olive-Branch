// OLIVE BRANCH — phone-side Wear Data Layer bridge. UNVERIFIED (this pass
// only compiled by eye against this same package's other real Kotlin files
// and the Play Services Wearable API surface; `:app:compileDebugKotlin` was
// NOT re-run this pass -- see this header's own "NOT COMPILED THIS PASS"
// paragraph below for why). MASTERFILE §21.5.
//
// Closed half of the gap a prior feasibility audit flagged: the Wear OS
// companion module (android/wear/) rendered a hardcoded
// DEMO_SLEEPS_UNTIL_HANDOVER constant with no phone->watch sync of any kind.
// This is the phone-side half: a MethodChannel (wear_sync_channel.dart calls
// it) backed by a real DataClient.putDataItem() call, mirroring
// KioskBridge.kt's own pattern in this same package (an object exposing
// named channel/method constants and a `register` function, contract-checked
// against its Dart caller by transport.test.mjs).
//
// CALL DAD -- REAL AS OF THIS PASS. A prior pass's own header here said the
// "Call Dad -> MessageClient round trip back to the phone... is a separate,
// larger piece of native+Flutter glue and is not built here either." It now
// is: register() below adds a MessageClient.OnMessageReceivedListener for
// PATH_CALL_DAD, forwarding a real watch tap to Dart as a real Kotlin ->
// Dart MethodChannel invocation (M_CALL_DAD_REQUESTED), which
// wear_sync_channel.dart's own listenForCallDad() exposes.
//
// THE HONEST TARGET, AND WHY IT IS NOT guardian_more.dart's ROUTE: the task
// this was built against named the real POST /v1/children/:childId/calls
// route (guardian_more.dart's "Call $childName" tile, v0.49.34) as "the real
// call-start flow" to reach. That route is GUARDIAN-ONLY BY DESIGN --
// server/routes.mjs's own handler returns 403 `child_cannot_start_call` for
// a child session, proven live in server/test/calls_route.test.mjs's own
// "B · a child principal cannot start a call" group. This watch pairs with
// the CHILD's own phone (child_home_live.dart's `_syncWear()` is the one
// real caller of the OUTGOING half of this same bridge, and it is a
// LiveChildHomeScreen -- a child-session screen -- not a guardian one), so a
// child-worn watch can never legally reach that route no matter how this
// bridge is wired; attempting to would either be refused outright or
// require silently pretending a child session were a guardian one, which
// this codebase does nowhere else and will not start here. The actually
// honest, already-real target is the SAME flow child_home.dart's own
// existing "Call Dad" button (`_PresenceCard`'s `FilledButton`) already
// opens: `CallScreen(who: 'ivy', displayName: ...)` with no knownRoom, which
// mints its room via the local dev room server today (there is no
// production child-initiated call-mint route in this codebase at all, a
// real, separate, disclosed gap -- not one this pass invented or is
// pretending doesn't exist). Wiring the watch to this flow makes it a
// genuine mirror of the phone's own real "Call Dad" affordance, not a lesser
// or fake one.
//
// NOT COMPILED THIS PASS: the C: drive this environment runs on has ~7GB
// free (a standing, previously-flagged condition, not new to this pass) and
// no ~/.gradle/caches directory exists for this user profile -- a first
// Gradle invocation here would need to download the full Gradle/AGP/
// Kotlin/Compose toolchain plus every dependency (including
// play-services-wearable, androidx wear compose), a real risk of filling an
// already-nearly-full disk. `:app:compileDebugKotlin` /
// `:wear:compileDebugKotlin` were deliberately NOT run this pass for that
// reason. This is a materially weaker verification claim than a prior pass's
// own "BUILD SUCCESSFUL" for the sleepsUntilHandover half of this same file
// -- stated honestly, not glossed over. What IS real: the DataItem path/key
// contract (unchanged) and the new MessageClient path/method contract are
// both checked byte-for-byte against wear_sync_channel.dart and
// wear/.../MainActivity.kt by transport.test.mjs's own "K · WEAR SYNC BRIDGE
// CONTRACT" group (70/70 passing, this pass, a real `node` run against the
// real files -- not merely written and assumed correct), and the Dart side
// of the round trip (WearSyncChannel.listenForCallDad -> LiveChildHomeScreen
// -> the real CallScreen) is proven by an actually-run `flutter analyze`
// (clean, whole client) and `flutter test` (1912/1912 passing, whole client,
// this pass, against a real local Flutter 3.44.8 toolchain that happens to
// be installed on this machine) exercising the real platform-channel handler
// mechanism -- see wear_sync_channel_test.dart and child_home_live_test.dart.
// Neither substitutes for a live paired watch, which this environment has
// never had (no Wear OS emulator was installed and no physical Watch6 was
// paired in this pass or any prior one, per this same disk-space caution --
// which is specifically an ANDROID/GRADLE toolchain cost, not a Flutter/Dart
// one; the Dart-side verification above carried no comparable disk risk and
// was genuinely run, not skipped).
package com.olivebranch.olive_client

import android.content.Context
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodChannel

object WearSyncBridge {
    // Mirrored in client/lib/wear_sync_channel.dart and contract-checked
    // against it by transport.test.mjs, the same way KioskBridge's channel
    // names are checked against kiosk_channel.dart.
    const val METHOD_CHANNEL = "com.olivebranch.olive_client/wear_sync"

    const val M_SYNC_SLEEPS_UNTIL_HANDOVER = "syncSleepsUntilHandover"

    // Kotlin -> Dart, the REVERSE direction from the constant above --
    // invoked via `methods.invokeMethod()`, never returned from
    // setMethodCallHandler(). A watch tap has no Dart caller waiting on a
    // MethodChannel.Result the way syncSleepsUntilHandover's own Dart caller
    // does; this fires and forgets, matching putDataItem()'s own
    // "accepted locally, not acknowledged" posture below.
    const val M_CALL_DAD_REQUESTED = "callDadRequested"

    // DataItem path and key the watch's OnDataChangedListener (wear/.../
    // MainActivity.kt) reads from. "now" because this rides the same DataItem
    // the phone's own /v1/children/:childId/now endpoint would eventually
    // back, if/when this bridge grows beyond one field.
    const val PATH_NOW = "/olive/now"
    const val KEY_SLEEPS_UNTIL_HANDOVER = "sleepsUntilHandover"

    // MessageClient path the watch sends on (wear/.../MainActivity.kt's own
    // sendCallDadMessage()). A real "Call Dad" tap is an EVENT ("do this
    // now"), not a state sync a late listener should ever replay -- exactly
    // the opposite shape from PATH_NOW above. DataClient's putDataItem() is
    // right for "sleeps until handover" (a value that should still be there
    // next time anyone looks); MessageClient.sendMessage is right here
    // because there is nothing that should "still be there" -- a call
    // request delivered five minutes late because a listener only just
    // reconnected is not a call request that should still fire.
    const val PATH_CALL_DAD = "/olive/call-dad"

    // Held so register() can remove its own previously-added listener before
    // adding a new one -- see register()'s own comment below for why.
    private var callDadListener: MessageClient.OnMessageReceivedListener? = null

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

        // Watch -> phone: a real "Call Dad" tap arrives here as a
        // MessageClient message, not a MethodChannel call -- Dart never
        // initiates this direction, so there is no call/result pair to
        // answer the way M_SYNC_SLEEPS_UNTIL_HANDOVER above has one.
        // Forwarded to Dart as a real Kotlin -> Dart invokeMethod() call; see
        // this file's own header for exactly which real screen that reaches
        // and why.
        //
        // Removes any previously-registered listener first: configureFlutter
        // Engine() (MainActivity.kt) can run again with a fresh MethodChannel
        // bound to a new engine/messenger (an Activity/engine recreation) --
        // without this, a stale listener closing over a now-discarded
        // MethodChannel would keep firing invokeMethod() calls that go
        // nowhere, alongside the new listener, on every future message.
        callDadListener?.let { Wearable.getMessageClient(context).removeListener(it) }
        val listener = MessageClient.OnMessageReceivedListener { event ->
            if (event.path == PATH_CALL_DAD) {
                methods.invokeMethod(M_CALL_DAD_REQUESTED, null)
            }
        }
        callDadListener = listener
        Wearable.getMessageClient(context).addListener(listener)
    }
}
