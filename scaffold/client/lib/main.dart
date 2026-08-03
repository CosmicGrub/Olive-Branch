// OLIVE BRANCH — child shell entry point. UNVERIFIED (no Flutter toolchain). DEMO WIRING.
//
// This is a preview build: it renders the real ChildHome widget (lib/child_home.dart,
// MARKUP screen 01, §8.1) with placeholder data, so the actual child-facing screen
// can be seen on a real device. There is no backend behind it yet — no live /now or
// /ribbon calls (see lib/api_client.dart) — and no kiosk lock (§5.20's native bridge
// is unwritten, see MASTERFILE §20.2). It is NOT kiosk-locked: standard Android
// navigation (Home/Recents/Back) still works.
import 'package:flutter/material.dart';
import 'child_home.dart';

void main() {
  runApp(const OliveChildDemo());
}

class OliveChildDemo extends StatelessWidget {
  const OliveChildDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (demo)',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    ),
    home: const ChildHome(
      childName: 'Ivy',
      presence: ParentPresence('Dad', '6:42 PM', '9:00 PM her time'),
      sleepsUntilHandover: 3,
      unreadCount: 2,
    ),
  );
}
