// OLIVE BRANCH — WAR, real-device verification entry point. DEV
// VERIFICATION ONLY, same posture as every other main_live_*_test.dart in
// this repo (see main_live_child_call_test.dart's own header for the
// fuller account of what that status means). UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). Network resilience &
// ad-hoc mode roadmap, Track B Option 2, ad-hoc games expansion.
//
// Deliberately the SIMPLEST possible entry point, mirroring
// main_live_local_play_test.dart exactly: no backend, no devLoginFor, no
// OLIVE_API_BASE_URL. `--dart-define=OLIVE_ROLE=dad|ivy` picks which real
// identity this device plays; local_pairing.dart does the rest, over the
// local network only.
//
// `flutter run --target=lib/main_local_war_test.dart
//   --dart-define=OLIVE_ROLE=ivy` on one device, `OLIVE_ROLE=dad` on the
// other, both on the same wifi network.
import 'package:flutter/material.dart';
import 'game_war.dart';

const _role = String.fromEnvironment('OLIVE_ROLE', defaultValue: 'ivy');
const _displayName = _role == 'ivy' ? 'Ivy' : 'Dad';

void main() {
  runApp(const _OliveLocalWarTest());
}

class _OliveLocalWarTest extends StatelessWidget {
  const _OliveLocalWarTest();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (local War test)',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
    home: const GameWarScreen(role: _role, displayName: _displayName),
  );
}
