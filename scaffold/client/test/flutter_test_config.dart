// Loaded automatically by `flutter test` before EVERY test file in this
// directory (the package:flutter_test config hook).
//
// Audit G-02/G-06: dev login is an explicit, opt-in path in the app
// (AuthSession.devLoginEnabled defaults to false, so a release build can never
// reach POST /v1/auth/dev-login). The existing widget suite drives its screens
// through mock http clients that answer /v1/auth/dev-login, so it opts in HERE,
// once, for the test isolate — not per-file and not in app code. Tests that
// exercise the production (device-credential) path, or the fail-closed default,
// set the flag back to false themselves (see auth_session_test.dart).
//
// On-device storage (local_services.dart): every test starts with a FRESH
// in-memory LocalServices, so what one test saves (a journal entry, a starred
// story) can never leak into the next test's screen. Tests that exercise
// persistence build their own LocalServices (or hand a screen its own
// repository) instead.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/local_services.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AuthSession.devLoginEnabled = true;
  AuthSession.use(null);
  setUp(LocalServices.resetForTest);
  await testMain();
}
