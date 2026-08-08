// OLIVE BRANCH — live-backend entry point. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline). MASTERFILE §7.
//
// A SEPARATE build target from lib/main.dart, on purpose: main.dart is an
// intentionally offline, backend-independent preview build (see its own
// header) so the app's screens stay inspectable on a real device with
// nothing else running. Bolting live networking onto that entry point would
// break the one thing it's for. This mirrors the project's own prior
// pattern of separate main_X.dart entry points (main.dart + the former
// main_guardian.dart, before §8.5.0's entry gate unified the demo build).
//
// `flutter run --target=lib/main_live.dart --dart-define=OLIVE_API_BASE_URL=http://<host>:8123`
// against a running server/index.mjs (DEV_LOGIN=1 required — see that
// file's own header for why). childId defaults to the seed data in
// server/seed-dev.mjs ("Ivy").
import 'package:flutter/material.dart';
import 'child_home_live.dart';
import 'kiosk_shell.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy

/// Demo-only stand-in for a real backend PIN check, same posture as
/// main.dart's own — see that file for why this isn't pretending to reach a
/// real guardian-PIN endpoint that doesn't exist.
Future<bool> _demoVerifyGuardianPin(String pin) async => pin == '1273';

void main() {
  runApp(const OliveLive());
}

class OliveLive extends StatelessWidget {
  const OliveLive({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Olive (live)',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    ),
    home: const KioskShell(
      verifyPin: _demoVerifyGuardianPin,
      child: LiveChildHomeScreen(
        baseUrl: _defaultBaseUrl,
        childId: _defaultChildId,
      ),
    ),
  );
}
