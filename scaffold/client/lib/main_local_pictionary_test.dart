// OLIVE BRANCH — LOCAL PICTIONARY, real-device verification entry point.
// DEV VERIFICATION ONLY, same posture as every other main_live_*_test.dart
// in this repo. UNVERIFIED (no Flutter toolchain in tools/verify.sh's
// automated pipeline). Network resilience & ad-hoc mode roadmap, Track B
// Option 2, ad-hoc games expansion.
//
// `flutter run --target=lib/main_local_pictionary_test.dart
//   --dart-define=OLIVE_ROLE=ivy` on one device, `OLIVE_ROLE=dad` on the
// other, both on the same wifi network.
import 'package:flutter/material.dart';
import 'game_pictionary.dart';

const _role = String.fromEnvironment('OLIVE_ROLE', defaultValue: 'ivy');
const _displayName = _role == 'ivy' ? 'Ivy' : 'Dad';

void main() {
  runApp(const _OliveLocalPictionaryTest());
}

class _OliveLocalPictionaryTest extends StatelessWidget {
  const _OliveLocalPictionaryTest();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (local Pictionary test)',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
    home: const GamePictionaryScreen(role: _role, displayName: _displayName),
  );
}
