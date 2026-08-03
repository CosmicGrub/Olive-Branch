// OLIVE BRANCH — guardian shell entry point. DEMO WIRING.
//
// Companion to lib/main.dart (the child build). This is a preview build: it
// renders the real GuardianHome widget (lib/guardian_home.dart, MARKUP screen 05,
// §8.2) with placeholder data so the actual guardian-facing screen can be seen on
// a real device. There is no backend behind it yet — no live /now or /ribbon calls
// (see lib/api_client.dart) — so the dual clock below is static demo data, not a
// live feed.
//
// Built separately from lib/main.dart via:
//   flutter build apk --target=lib/main_guardian.dart --debug
import 'package:flutter/material.dart';
import 'guardian_home.dart';

void main() {
  runApp(const OliveGuardianDemo());
}

class OliveGuardianDemo extends StatelessWidget {
  const OliveGuardianDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive Branch (demo)',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    ),
    home: GuardianHome(
      childName: 'Ivy',
      childLocalTime: '9:14 PM',
      childZoneAbbr: 'EST',
      actorLocalTime: '6:14 PM',
      childStateSentence: 'Winding down for bed',
      childBands: const [
        RibbonBand(0.0, 0.30, Color(0xFF3949AB), 'asleep'),
        RibbonBand(0.30, 0.45, Color(0xFFFFB300), 'school'),
        RibbonBand(0.75, 0.25, Color(0xFF43A047), 'free time'),
      ],
      actorBands: const [
        RibbonBand(0.0, 0.35, Color(0xFF3949AB), 'asleep'),
        RibbonBand(0.35, 0.50, Color(0xFFFFB300), 'work'),
        RibbonBand(0.85, 0.15, Color(0xFF43A047), 'free time'),
      ],
      overlapLabel: 'Both free 7:00–8:00 PM her time',
    ),
  );
}
