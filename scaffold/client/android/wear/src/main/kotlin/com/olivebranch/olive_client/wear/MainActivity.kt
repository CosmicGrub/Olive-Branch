// OLIVE BRANCH — Galaxy Watch6 Classic companion. MASTERFILE §21.5.
//
// Deliberately NOT a second ChildHome. §21.5's "the quieting" principle says
// the product should feel less present as it matures, never more -- the
// worst version of a watch companion is one that mirrors the whole phone
// app onto a 1.5" screen. This shows exactly two things a glance actually
// needs: the sleeps-until-handover countdown (never hours, matching
// child_home.dart's own §8.2.5 rule) and a one-tap way to reach Dad.
//
// HONEST SCOPE: both values below are DEMO constants, not live data.
// Phone<->watch sync via the Wear Data Layer API (com.google.android.gms.
// wearable.DataClient / MessageClient -- the standard mechanism, already a
// declared dependency in build.gradle.kts) is NOT implemented. Wiring it
// means: the phone app publishes state via a DataClient.putDataItem() call
// keyed to a path this watch app listens for via a DataClient.OnDataChangedListener
// (or a WearableListenerService for background delivery), OR
// simpler-but-phone-must-be-reachable: a MessageClient request/response round
// trip mirroring api_client.dart's existing OliveApi shape. Tapping "Call
// Dad" currently does nothing but log -- a real implementation would send a
// MessageClient message the phone app listens for and turns into the exact
// same CallScreen(who: 'dad', ...) push that guardian_home.dart's own
// FilledButton already does today, so the call itself is never duplicated
// logic, only the trigger differs by platform.
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            OliveWatchGlance(
                sleepsUntilHandover = DEMO_SLEEPS_UNTIL_HANDOVER,
                onCallDad = { /* TODO: MessageClient -> phone app, see file header */ },
            )
        }
    }
}

// Demo-only stand-in for real Data Layer sync -- see file header.
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
