// OLIVE BRANCH — unified entry point. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61).
//
// This is a preview build: it renders the real EntryGate (lib/entry_gate.dart,
// §8.5.0), ChildHome (lib/child_home.dart, MARKUP screen 01, §8.1), and
// GuardianHome (lib/guardian_home.dart, MARKUP screen 05, §8.2) widgets with
// placeholder data, so both actual app-facing screens can be seen on a real
// device from a single install. There is no backend behind it yet — no live
// /now or /ribbon calls (see lib/api_client.dart).
//
// The child side IS now kiosk-locked (§5.20, kiosk_shell.dart) — entering it
// calls startLockTask() for real on Android. `_demoVerifyGuardianPin` is a
// placeholder for the real PIN check: no backend exists yet to check a real
// guardian PIN against (auth.ts's scrypt hash is deliberately server-only),
// so this demo build accepts one fixed code instead of pretending to reach a
// server that isn't there.
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
import 'kiosk_shell.dart';

void main() {
  runApp(const OliveDemo());
}

/// Demo-only stand-in for a real backend PIN check (see api_client.dart /
/// auth.ts). Not the shuffled-keypad UI's concern — PinGate never sees the
/// correct code, only whatever the child/guardian typed.
const _demoGuardianPin = '1273';
Future<bool> _demoVerifyGuardianPin(String pin) async => pin == _demoGuardianPin;

/// Demo-only stand-in for the real WebAuthn ceremony
/// (webauthn_channel.dart's `buildVerifyBiometricCallback`) — no backend and
/// no platform authenticator exist to check in this preview build, so this
/// always succeeds rather than pretending to reach either. Honest about what
/// it is: nothing here proves this build resists a stolen device the way the
/// live build's real PIN+biometric ceremony does.
Future<bool> _demoVerifyBiometric() async => true;

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
      childDestination: KioskShell(
        verifyPin: _demoVerifyGuardianPin,
        verifyBiometric: _demoVerifyBiometric,
        child: childHomeDemo,
      ),
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
