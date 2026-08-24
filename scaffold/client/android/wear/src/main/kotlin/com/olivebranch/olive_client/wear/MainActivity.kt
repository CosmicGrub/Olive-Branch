// OLIVE BRANCH — Galaxy Watch6 Classic companion. MASTERFILE §21.5.
//
// Deliberately NOT a second ChildHome. §21.5's "the quieting" principle says
// the product should feel less present as it matures, never more -- the
// worst version of a watch companion is one that mirrors the whole phone
// app onto a 1.5" screen. This shows exactly two things a glance actually
// needs: the sleeps-until-handover countdown (never hours, matching
// child_home.dart's own §8.2.5 rule) and a one-tap way to reach Dad.
//
// PHONE <-> WATCH SYNC, AS OF THIS PASS -- UNVERIFIED (compiled by eye, not
// device-confirmed, and NOT re-run through `:wear:compileDebugKotlin` this
// pass -- see WearSyncBridge.kt's own header for why: an already-known,
// still-true disk-space constraint in this environment). A prior feasibility
// audit found none of this existed: no play-services-wearable dependency on
// the phone side, no WearableListenerService anywhere, no DataClient
// listener here, and (closed in a LATER pass, not this one) a "Call Dad"
// button that was a local no-op with no MessageClient wiring at all. Both
// directions are now real:
//   - PHONE -> WATCH: the phone (android/app/.../WearSyncBridge.kt, driven by
//     client/lib/wear_sync_channel.dart) calls
//     Wearable.getDataClient(context).putDataItem() on path "/olive/now"
//     whenever LiveChildHomeScreen holds a real, non-null
//     sleepsUntilHandover; this Activity registers a
//     DataClient.OnDataChangedListener (onResume/onPause below) for that
//     same path and feeds the parsed int into `sleepsUntilHandover`, a
//     Compose MutableState OliveWatchGlance reads.
//   - WATCH -> PHONE (new this pass): tapping "Call Dad" calls
//     sendCallDadMessage() below, which sends a real
//     MessageClient.sendMessage() on path "/olive/call-dad" to every
//     currently connected node. WearSyncBridge.kt's own
//     MessageClient.OnMessageReceivedListener picks that up and forwards it
//     to Dart, which (LiveChildHomeScreen's own listenForCallDad wiring)
//     opens the SAME real CallScreen(who: 'ivy', ...) child_home.dart's own
//     existing "Call Dad" button already opens on the phone itself -- see
//     WearSyncBridge.kt's own header for exactly why that is the honest
//     target and not guardian_more.dart's guardian-only POST route.
// DEMO_SLEEPS_UNTIL_HANDOVER is NOT deleted -- it is still the value shown
// before any real sync arrives, which is a real, reachable state: this app
// is standalone-launchable and can be opened before ever pairing, or after
// pairing but before the phone has sent anything.
//
// Verified only by a careful read against this same module's other
// (previously `:wear:compileDebugKotlin`-verified) code and the Play
// Services Wearable API surface -- NOT by an actual DataItem or Message
// round-tripping to a real or emulated watch, and NOT by a fresh Gradle
// compile this pass. Per this session's own disk-space caution (a
// pre-existing, previously-flagged condition -- ~7GB free, no Gradle cache
// yet for this user profile), no Wear OS emulator was installed and no
// physical Watch6 was paired, and no `:wear:compileDebugKotlin` was re-run
// either. That is honestly a WEAKER claim than the phone-side KioskBridge
// .kt's own "built, installed, and manually verified on a device" precedent,
// or even than an earlier pass's own "BUILD SUCCESSFUL" claim for THIS
// module's sleepsUntilHandover half -- stated plainly, not glossed over.
// Drop this marker only once someone actually compiles this module again and
// does the real device round trip. Two things static reading genuinely
// cannot catch: whether `event.dataItem.uri.path` / `event.path` really
// equal "/olive/now" / "/olive/call-dad" rather than some prefixed variant
// once actually exchanged between real Data Layer nodes, and whether
// `NodeClient.getConnectedNodes()` actually resolves the phone as a
// connected node in every real pairing state (mid-reconnect, Bluetooth
// briefly down, etc.) rather than only the steady-state case this code
// assumes.
//
// "Call Dad" feedback is deliberately non-committal ("Reaching Dad…"), not
// "Called Dad" or a checkmark: sendMessage() succeeding only means the Data
// Layer accepted the message locally for delivery to a connected node, not
// that the phone actually received it or that a call actually started --
// there is no ack path back to the watch in this pass, matching
// WearSyncBridge.kt's own putDataItem() posture in the other direction. An
// honest claim about what just happened, not a guess about what happens
// next.
package com.olivebranch.olive_client.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable

class MainActivity : ComponentActivity(), DataClient.OnDataChangedListener {
    // A Compose MutableState, not a plain var: onDataChanged() below fires
    // off the Compose recomposition scope (it's a Data Layer binder
    // callback), so OliveWatchGlance needs to observe this through the
    // snapshot system to actually redraw when a real value arrives, rather
    // than only ever showing whatever was current at setContent() time.
    private val sleepsUntilHandover = mutableStateOf(DEMO_SLEEPS_UNTIL_HANDOVER)

    // Local, transient tap feedback only -- see this file's own header for
    // why it is worded the way it is. Cleared on every fresh onCreate (a
    // relaunch), not persisted -- this is not a call history.
    private val callDadFeedback = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            OliveWatchGlance(
                sleepsUntilHandover = sleepsUntilHandover.value,
                callDadFeedback = callDadFeedback.value,
                onCallDad = ::sendCallDadMessage,
            )
        }
    }

    // Registered only while visible, matching the Data Layer API's own
    // recommended lifecycle (and this codebase's existing preference for
    // lifecycle-scoped registration over a background
    // WearableListenerService, which would need a manifest service
    // declaration this pass deliberately keeps out of scope -- the glance
    // only needs a fresh value when it's actually on someone's wrist).
    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
    }

    override fun onPause() {
        Wearable.getDataClient(this).removeListener(this)
        super.onPause()
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            if (event.dataItem.uri.path != PATH_NOW) continue
            val map = DataMapItem.fromDataItem(event.dataItem).dataMap
            if (!map.containsKey(KEY_SLEEPS_UNTIL_HANDOVER)) continue
            sleepsUntilHandover.value = map.getInt(KEY_SLEEPS_UNTIL_HANDOVER)
        }
        dataEvents.release()
    }

    // Real MessageClient send -- the watch half of the round trip this
    // file's own header used to describe as entirely unbuilt (a local no-op
    // button). See WearSyncBridge.kt's own header for the phone-side
    // listener and exactly which real call-start flow this reaches.
    //
    // Sent to every currently connected node rather than assuming exactly
    // one: the Data Layer API's own documented shape (a watch can in
    // principle see more than one connected device), and iterating an empty
    // or single-item list costs nothing extra. Fire-and-forget, matching
    // WearSyncBridge.kt's own putDataItem() posture in the other direction --
    // a failed Task here has no user-facing retry path in this pass; the
    // only feedback the wearer gets is the honest, non-committal
    // `callDadFeedback` line (see this file's own header for why it's worded
    // that way).
    private fun sendCallDadMessage() {
        callDadFeedback.value = "Reaching Dad…"
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (node in nodes) {
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, PATH_CALL_DAD, ByteArray(0))
                }
            }
    }
}

// Path and key must match android/app/.../WearSyncBridge.kt exactly -- these
// are the two sides of one contract with no shared Kotlin module to enforce
// it, so a typo on either end fails silently (the listener just never
// fires). transport.test.mjs's channel-name check covers the MethodChannel
// between Dart and the phone's Kotlin; it also reads this file directly
// (its "K · WEAR SYNC BRIDGE CONTRACT" group) to check these path/key
// literals agree with WearSyncBridge.kt's own copies, since this module has
// no Dart counterpart of its own to contract-check against otherwise.
private const val PATH_NOW = "/olive/now"
private const val KEY_SLEEPS_UNTIL_HANDOVER = "sleepsUntilHandover"

// Must match WearSyncBridge.kt's own PATH_CALL_DAD exactly -- see that
// constant's own comment for why this is a MessageClient path, not a second
// DataItem.
private const val PATH_CALL_DAD = "/olive/call-dad"

// Fallback shown before any real sync arrives -- launched standalone, never
// paired, or paired but the phone hasn't sent anything yet. Kept
// deliberately, not deleted; see file header.
private const val DEMO_SLEEPS_UNTIL_HANDOVER = 3

@Composable
fun OliveWatchGlance(
    sleepsUntilHandover: Int,
    callDadFeedback: String?,
    onCallDad: () -> Unit,
) {
    MaterialTheme {
        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "$sleepsUntilHandover",
                fontSize = 40.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                // "sleeps", never hours -- same rule as child_home.dart §8.2.5.
                text = if (sleepsUntilHandover == 1) "sleep until\nthe handover" else "sleeps until\nthe handover",
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.padding(8.dp))
            Button(onClick = onCallDad) {
                Text(text = "Call Dad", fontSize = 12.sp)
            }
            if (callDadFeedback != null) {
                Spacer(Modifier.padding(4.dp))
                Text(text = callDadFeedback, fontSize = 10.sp, textAlign = TextAlign.Center)
            }
        }
    }
}
