// OLIVE BRANCH — CONNECT 4, real-device verification entry point. DEV
// VERIFICATION ONLY, same posture as every other main_live_*_test.dart in
// this repo. Verified by CI (a Flutter toolchain now runs for real in
// tools/verify.sh's automated pipeline — CHANGELOG v0.49.61). Network
// resilience & ad-hoc mode roadmap, Track B Option 2, ad-hoc games
// expansion.
//
// `flutter run --target=lib/main_local_connect4_test.dart
//   --dart-define=OLIVE_ROLE=ivy` on one device, `OLIVE_ROLE=dad` on the
// other — or just one device alone for the vs-CPU mode, which needs no
// pairing at all.
import 'package:flutter/material.dart';
import 'game_connect4.dart';

const _role = String.fromEnvironment('OLIVE_ROLE', defaultValue: 'ivy');
const _displayName = _role == 'ivy' ? 'Ivy' : 'Dad';

void main() {
  runApp(const _OliveLocalConnect4Test());
}

class _OliveLocalConnect4Test extends StatelessWidget {
  const _OliveLocalConnect4Test();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (local Connect 4 test)',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
    home: const GameConnect4Screen(role: _role, displayName: _displayName),
  );
}
