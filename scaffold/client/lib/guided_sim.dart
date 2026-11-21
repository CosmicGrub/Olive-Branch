// OLIVE BRANCH — the DEV-ONLY simulation seam for the guided first run. MASTERFILE §8.5.14.
//
// A build made with --dart-define=OLIVE_SIM_ONBOARDING=true (bool.fromEnvironment reads exactly "true") starts the
// guided first run on a device that has ALREADY finished first run, WITHOUT erasing anything, so each half can be shown
// on one device alone:
//   * the grown-up's half on a phone: the welcome, then a STAND-IN for the connect step (a "waiting for her tablet" card
//     that completes after one tap, marked SIMULATED), then the real tour, help and the last screen. The name, age, PIN and
//     family are not asked again and are never touched;
//   * her half on a tablet that is already paired: the grown-up gate card, then her welcome.
// It restarts on every launch of such a build, so a tester can run it again by relaunching. Every simulated screen
// carries a visible "SIMULATED (developer build)" band.
//
// No normal build script, workflow or Dockerfile may pass it: tools/check-sim-onboarding.mjs fails CI if any file other
// than the short allow-list names it (prose documents may describe it). A store or release cut never carries it.
import 'package:flutter/material.dart';

import 'guided_widgets.dart' show GuidedProgressStrip;

const bool kSimOnboarding = bool.fromEnvironment('OLIVE_SIM_ONBOARDING');

/// The band every simulated screen shows.
class SimBand extends StatelessWidget {
  const SimBand({super.key});
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('simBand'),
        width: double.infinity,
        color: Colors.amber.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: const Text('SIMULATED (developer build)',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
      );
}

/// Stands in for "waiting for her tablet" when only one device is at hand. Completes after one tap, and says so.
class SimulatedTabletScreen extends StatelessWidget {
  const SimulatedTabletScreen({super.key, required this.childName, required this.onConnected});
  final String childName;
  final VoidCallback onConnected;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("Connect a child's device")),
        body: SafeArea(
          child: Column(children: <Widget>[
            const SimBand(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    const GuidedProgressStrip(step: 2, of: 5, prefix: 'Tablet step'),
                    const SizedBox(height: 16),
                    Text("Waiting for ${childName.isEmpty ? 'her' : childName}'s tablet",
                        key: const Key('simWaiting'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('This is a stand-in. No other device is needed. Tap below to carry on as if her tablet connected.'),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: const Key('simConnect'),
                        onPressed: onConnected,
                        child: const Text('Simulate: her tablet connected'),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}
