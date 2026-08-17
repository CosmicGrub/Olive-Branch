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
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'child_home_live.dart';
import 'kiosk_shell.dart';
import 'push_channel.dart';

const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias
const _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy

/// The real backend PIN check — replaces the former hardcoded
/// `_demoVerifyGuardianPin` ('1273', never checked against anything). This is
/// the actual release-blocker fix: server/routes.mjs's real
/// POST /kiosk-pin/verify now backs the kiosk lock's PIN gate on this entry
/// point, exactly the way KioskShell's own header always said a real backend
/// would slot in once one existed.
///
/// Reuses child_home_live.dart's own session plumbing rather than inventing
/// a second path: the same `devLoginFor()` dev-login helper, against the same
/// `_defaultBaseUrl`/`_defaultChildId` this file already defines (see that
/// file's `_load()` for the pattern this mirrors). A fresh dev-login per PIN
/// attempt, not a token cached across this screen's lifetime: dev-login is a
/// stateless, side-effect-free shortcut fenced behind DEV_LOGIN=1 (see
/// server/index.mjs's own header) with nothing worth preserving between
/// attempts, and re-authenticating here means a PIN check never trusts a
/// token that might have outlived whatever this session's real lifecycle
/// should be.
///
/// FAILS CLOSED at every stage. [OliveApi.verifyKioskPin] already fails
/// closed on a network error reaching /kiosk-pin/verify itself; the
/// `devLoginFor()` call in front of it is wrapped the same way here — a
/// server that's unreachable, or a dev-login that 404s/500s, must reject the
/// PIN, never accept it. A broken network must never look like a correct PIN.
Future<bool> _verifyGuardianPin(String pin) async {
  try {
    final token = await devLoginFor(_defaultBaseUrl, childId: _defaultChildId);
    final api = OliveApi(_defaultBaseUrl, token);
    final ok = await api.verifyKioskPin(_defaultChildId, pin);
    api.close();
    return ok;
  } catch (_) {
    return false;
  }
}

/// The biometric half of §8.3 guardian escalation
/// (webauthn_channel.dart's `buildVerifyBiometricCallback`) needs a KNOWN
/// guardian `userId` to request a login challenge for — unlike
/// [_verifyGuardianPin] above, which deliberately checks a PIN against every
/// live guardian rather than one. This entry point has no such identity to
/// give it: `devLoginFor()` is a stateless DEV_LOGIN=1 shortcut with no
/// signed-in guardian behind it, by design (see this file's own header) —
/// there is nothing here playing the role a real onboarded device's stored
/// guardian identity would. Rather than invent one (which would prove
/// nothing real, since `buildVerifyBiometricCallback`'s own WebAuthn
/// round trip would just be exercised against a guessed/hardcoded id, not a
/// device's actual configured guardian), this stays an honest stand-in —
/// same posture as `_demoVerifyGuardianPin` in main.dart, one layer down.
/// `buildVerifyBiometricCallback` itself is real and ready for whichever
/// real entry point ends up knowing its own guardian's userId.
Future<bool> _liveVerifyBiometricStub() async => true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // MASTERFILE §11 -- registers the real top-level background handler
  // (push_channel.dart's firebaseMessagingBackgroundHandler) at the one
  // place FlutterFire's own docs require it: before runApp(), so a
  // background/terminated-state push tap has a real callback waiting for it
  // from the moment this isolate exists.
  //
  // Wrapped in try/catch because Firebase.initializeApp() genuinely fails in
  // this checkout -- no real android/app/google-services.json exists here
  // (see pubspec.yaml's own comment on why one is not fabricated). Letting
  // that exception escape would crash this entire preview build before it
  // ever draws a frame, which would defeat main_live.dart's whole purpose
  // (see this file's own header -- a real device/emulator target meant to
  // stay inspectable). push_channel.dart's PushChannel.initialize(), called
  // later from child_home_live.dart once a real session exists, is the
  // second, independent attempt -- THAT failure is the one surfaced (as
  // PushInitializationError) rather than silently caught, per house style;
  // this one is intentionally the boot-time exception.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[olive.push] background handler not registered at boot: $e');
  }
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
      verifyPin: _verifyGuardianPin,
      verifyBiometric: _liveVerifyBiometricStub,
      child: LiveChildHomeScreen(
        baseUrl: _defaultBaseUrl,
        childId: _defaultChildId,
      ),
    ),
  );
}
