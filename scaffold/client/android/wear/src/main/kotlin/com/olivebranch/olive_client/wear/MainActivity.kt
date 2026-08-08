// OLIVE BRANCH — Galaxy Watch6 Classic companion. MASTERFILE §21.5.
//
// Deliberately NOT a second ChildHome. §21.5's "the quieting" principle says
// the product should feel less present as it matures, never more -- the
// worst version of a watch companion is one that mirrors the whole phone
// app onto a 1.5" screen. This shows exactly two things a glance actually
// needs: the sleeps-until-handover countdown (never hours, matching
// child_home.dart's own §8.2.5 rule) and a one-tap way to reach Dad.
//
// REAL PHONE -> WATCH SYNC, AS OF THIS PASS -- UNVERIFIED (compiled, not
// device-confirmed). A prior feasibility audit found none of this existed:
// no play-services-wearable dependency on the phone side, no
// WearableListenerService anywhere, no DataClient listener here. That gap is
// now closed for ONE field:
//   - the phone (android/app/.../WearSyncBridge.kt, driven by
//     client/lib/wear_sync_channel.dart) calls
//     Wearable.getDataClient(context).putDataItem() on path "/olive/now"
//     whenever LiveChildHomeScreen holds a real, non-null
//     sleepsUntilHandover;
//   - this Activity registers a DataClient.OnDataChangedListener
//     (onResume/onPause below) for that same path and feeds the parsed int
//     into `sleepsUntilHandover`, a Compose MutableState OliveWatchGlance
//     reads, replacing the old direct DEMO_SLEEPS_UNTIL_HANDOVER call site.
// DEMO_SLEEPS_UNTIL_HANDOVER is NOT deleted -- it is still the value shown
// before any real sync arrives, which is a real, reachable state: this app
// is standalone-launchable and can be opened before ever pairing, or after
// pairing but before the phone has sent anything.
//
// Verified only by `:app:compileDebugKotlin` / `:wear:compileDebugKotlin`
// both succeeding (see CHANGELOG) -- NOT by an actual DataItem round-tripping
// to a real or emulated watch. Per this session's disk-space caution, no
// Wear OS emulator system image was installed to check that live, and no
// physical Watch6 was paired during this pass either. That is a materially
// weaker claim than the phone-side KioskBridge.kt's own "built, installed,
// and manually verified on a device" precedent, so this stays honestly
// UNVERIFIED at the runtime-behavior level until someone actually pairs a
// watch and confirms `onDataChanged` fires. (Two things static compilation
// genuinely cannot catch here: whether `event.dataItem.uri.path` really
// equals "/olive/now" rather than some prefixed variant, and whether
// `DataClient` delivers the event to a *paused-then-resumed* Activity at
// all versus only one already in the foreground.)
//
// STILL NOT DONE, unchanged from before this pass: "Call Dad" remains a
// local no-op. The MessageClient round trip back to the phone -- a
// message this watch sends that the phone app receives and turns into the
// same CallScreen(who: 'dad', ...) push guardian_home.dart's own
// FilledButton already triggers -- is a separate, larger piece of
// native+Flutter glue on BOTH ends and was explicitly out of scope for this
// pass (per the task that produced this file's current state). "Presence"
// was never part of this watch face and still is not -- no computation
// logic for it exists anywhere in this codebase, so there is nothing honest
// to sync.
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            OliveWatchGlance(
                sleepsUntilHandover = sleepsUntilHandover.value,
                onCallDad = { /* TODO: MessageClient -> phone app, see file header */ },
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
}

// Path and key must match android/app/.../WearSyncBridge.kt exactly -- these
// are the two sides of one contract with no shared Kotlin module to enforce
// it, so a typo on either end fails silently (the listener just never
// fires). transport.test.mjs's channel-name check covers the MethodChannel
// between Dart and the phone's Kotlin; it does not reach this file, since
// this module has no Dart counterpart to contract-check against.
private const val PATH_NOW = "/olive/now"
private const val KEY_SLEEPS_UNTIL_HANDOVER = "sleepsUntilHandover"

// Fallback shown before any real sync arrives -- launched standalone, never
// paired, or paired but the phone hasn't sent anything yet. Kept
// deliberately, not deleted; see file header.
private const val DEMO_SLEEPS_UNTIL_HANDOVER = 3

@Composable
fun OliveWatchGlance(sleepsUntilHandover: Int, onCallDad: () -> Unit) {
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
        }
    }
}
