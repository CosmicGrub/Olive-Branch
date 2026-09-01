// OLIVE BRANCH — LOCAL PLAY, real-device verification entry point. DEV
// VERIFICATION ONLY, same posture as every other main_live_*_test.dart in
// this repo (see main_live_child_call_test.dart's own header for the
// fuller account of what that status means). Network resilience & ad-hoc
// mode roadmap, Track B Option 2.
//
// Deliberately the SIMPLEST possible entry point: no backend, no
// devLoginFor, no OLIVE_API_BASE_URL — the entire point of this screen is
// that it needs NONE of that. `--dart-define=OLIVE_ROLE=dad|ivy` picks
// which real identity this device plays; local_discovery.dart/
// local_session.dart do the rest, over the local network only.
//
// `flutter run --target=lib/main_live_local_play_test.dart
//   --dart-define=OLIVE_ROLE=ivy` on one device, `OLIVE_ROLE=dad` on the
// other — both on the same wifi network (or, for the real test this
// exists to prove, the SAME wifi network with the dev machine's own
// internet-backed server unreachable, confirming this path genuinely does
// not need it).
import 'package:flutter/material.dart';
import 'local_play_screen.dart';

const _role = String.fromEnvironment('OLIVE_ROLE', defaultValue: 'ivy');
const _displayName = _role == 'ivy' ? 'Ivy' : 'Dad';

void main() {
  runApp(const _OliveLiveLocalPlayTest());
}

class _OliveLiveLocalPlayTest extends StatelessWidget {
  const _OliveLiveLocalPlayTest();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (live, local play test)',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
    home: const LocalPlayScreen(role: _role, displayName: _displayName),
  );
}
