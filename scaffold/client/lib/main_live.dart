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
import 'api_client.dart';
import 'child_home_live.dart';
import 'kiosk_shell.dart';

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
      verifyPin: _verifyGuardianPin,
      child: LiveChildHomeScreen(
        baseUrl: _defaultBaseUrl,
        childId: _defaultChildId,
      ),
    ),
  );
}
