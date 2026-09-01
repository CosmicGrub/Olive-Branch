// OLIVE BRANCH — UNO, real-device verification entry point. DEV
// VERIFICATION ONLY, same posture as every other main_live_*_test.dart in
// this repo. Verified by CI (a Flutter toolchain now runs for real in
// tools/verify.sh's automated pipeline — CHANGELOG v0.49.61). Network
// resilience & ad-hoc mode roadmap, Track B Option 2, ad-hoc games
// expansion.
//
// `flutter run --target=lib/main_local_uno_test.dart
//   --dart-define=OLIVE_ROLE=ivy` on one device, `OLIVE_ROLE=dad` on the
// other, both on the same wifi network — or run solo against the CPU,
// which needs no pairing at all.
import 'package:flutter/material.dart';
import 'game_uno.dart';

const _role = String.fromEnvironment('OLIVE_ROLE', defaultValue: 'ivy');
const _displayName = _role == 'ivy' ? 'Ivy' : 'Dad';

void main() {
  runApp(const _OliveLocalUnoTest());
}

class _OliveLocalUnoTest extends StatelessWidget {
  const _OliveLocalUnoTest();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (local Uno test)',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
    home: const GameUnoScreen(role: _role, displayName: _displayName),
  );
}
