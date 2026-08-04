// OLIVE BRANCH — unified entry point. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run this
// session, see HANDOFF notes, but verify.sh itself still can't find it).
//
// This is a preview build: it renders the real EntryGate (lib/entry_gate.dart,
// §8.5.0), ChildHome (lib/child_home.dart, MARKUP screen 01, §8.1), and
// GuardianHome (lib/guardian_home.dart, MARKUP screen 05, §8.2) widgets with
// placeholder data, so both actual app-facing screens can be seen on a real
// device from a single install. There is no backend behind it yet — no live
// /now or /ribbon calls (see lib/api_client.dart) — and no kiosk lock (§5.20's
// native bridge is unwritten, see MASTERFILE §20.2). It is NOT kiosk-locked:
// standard Android navigation (Home/Recents/Back) still works.
//
// Formerly two separate builds (this file plus main_guardian.dart, built via
// `flutter build apk --target=lib/main_guardian.dart`) sharing one
// applicationId — meaning only one could ever be installed at a time. Now
// stitched into the two reachable halves of one app, entered through the
// same entry gate a real family would see.
import 'package:flutter/material.dart';
import 'child_home.dart';
import 'entry_gate.dart';
import 'guardian_home.dart';

void main() {
  runApp(const OliveDemo());
}

class OliveDemo extends StatelessWidget {
  const OliveDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (demo)',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    ),
    home: const EntryGate(
      childDestination: childHomeDemo,
      grownupDestination: guardianHomeDemo,
    ),
  );
}

// The same placeholder data each half rendered on its own before unification.
const childHomeDemo = ChildHome(
  childName: 'Ivy',
  presence: ParentPresence('Dad', '6:42 PM', '9:00 PM her time'),
  sleepsUntilHandover: 3,
  unreadCount: 2,
);

const guardianHomeDemo = GuardianHome(
  childName: 'Ivy',
  childLocalTime: '9:14 PM',
  childZoneAbbr: 'EST',
  actorLocalTime: '6:14 PM',
  childStateSentence: 'Winding down for bed',
  childBands: [
    RibbonBand(0.0, 0.30, Color(0xFF3949AB), 'asleep'),
    RibbonBand(0.30, 0.45, Color(0xFFFFB300), 'school'),
    RibbonBand(0.75, 0.25, Color(0xFF43A047), 'free time'),
  ],
  actorBands: [
    RibbonBand(0.0, 0.35, Color(0xFF3949AB), 'asleep'),
    RibbonBand(0.35, 0.50, Color(0xFFFFB300), 'work'),
    RibbonBand(0.85, 0.15, Color(0xFF43A047), 'free time'),
  ],
  overlapLabel: 'Both free 7:00–8:00 PM her time',
);
