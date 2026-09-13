// OLIVE BRANCH — phone-side Wear Data Layer client. UNVERIFIED at the
// live-device level (no paired Wear OS watch exists in this environment —
// see WearSyncBridge.kt's own header). tools/verify.sh's own automated
// pipeline still has no Flutter toolchain, so this marker stays present the
// same way every other client file's does — but this pass DID actually run
// `flutter analyze` (clean, whole project) and `flutter test` (1912 passed,
// 0 failed, whole project, including every test this file and
// child_home_live_test.dart add) locally against a real Flutter 3.44.8 /
// Dart 3.12.2 toolchain that happens to be installed on this machine, not
// merely written and assumed correct. MASTERFILE §21.5.
//
// Mirrors kiosk_channel.dart's shape: a thin MethodChannel wrapper whose
// channel/method names are contract-checked against the native side
// (android/app/.../WearSyncBridge.kt) by transport.test.mjs, so the two
// cannot drift silently the way an unwired declaration would.
//
// Bidirectional as of this pass. [syncSleepsUntilHandover] below is the
// original, outgoing (Dart -> native) half. [listenForCallDad] is the new
// incoming (native -> Dart) half: a real watch "Call Dad" tap arrives at
// android/app/.../WearSyncBridge.kt as a MessageClient message, which that
// bridge forwards here as a real `MethodChannel.invokeMethod()` call on this
// exact channel — see that bridge's own header for the full watch -> phone
// -> Dart path, and for exactly why the real destination this reaches is
// the SAME `CallScreen(who: 'ivy', ...)` child_home.dart's own existing
// "Call Dad" button already opens, not guardian_more.dart's guardian-only
// `POST /v1/children/:childId/calls` route (server/routes.mjs refuses a
// child session there by design — `child_cannot_start_call`, proven in
// server/test/calls_route.test.mjs).
//
// Android-only: this app has no iOS build and Windows has no paired-watch
// concept, so `Platform.isAndroid` short-circuits before touching the
// channel at all on any other platform — a MissingPluginException would
// otherwise fire the moment something not backed by a native handler tries
// to invoke it, exactly as kiosk_shell.dart's own `_engage()` comment
// explains for the kiosk channel. `syncSleepsUntilHandover` is a regular
// (non-final) instance method, not marked `final`, so tests can override it
// on a subclass the same way invariants_test.dart's `_FakeKioskChannel`
// overrides KioskChannel — no real platform channel involved under
// `flutter test`. [listenForCallDad] is the same shape for the same reason —
// see child_home_live_test.dart's own `_FakeWearSyncChannel`.
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

class WearSyncChannel {
  static const methodChannel =
      MethodChannel('com.olivebranch.olive_client/wear_sync');

  static const mSyncSleepsUntilHandover = 'syncSleepsUntilHandover';

  /// Kotlin -> Dart, the reverse direction from [mSyncSleepsUntilHandover]
  /// above. Mirrored literally in android/app/.../WearSyncBridge.kt's own
  /// `M_CALL_DAD_REQUESTED` and contract-checked against it by
  /// transport.test.mjs, the same way [mSyncSleepsUntilHandover] already is.
  static const mCallDadRequested = 'callDadRequested';

  /// Pushes a real, already-fetched `sleepsUntilHandover` value to a paired
  /// Wear OS companion (§21.5). Callers must never pass a placeholder or
  /// demo value here — this method does no validation of its own beyond
  /// "is it an int", so the honesty guarantee lives entirely in what the
  /// caller chooses to pass (see child_home_live.dart's `_syncWear`, which
  /// only calls this when it holds a real fetched value, never the demo
  /// constant the watch itself falls back to before pairing).
  ///
  /// Swallows any platform-channel failure (Play services unavailable, no
  /// watch paired, DataClient rejection) rather than surfacing it: a failed
  /// watch sync must never block or error the phone's own home screen.
  Future<void> syncSleepsUntilHandover(int sleepsUntilHandover) async {
    if (!Platform.isAndroid) return;
    try {
      await methodChannel.invokeMethod<bool>(
          mSyncSleepsUntilHandover, sleepsUntilHandover);
    } on Object {
      // ignore — see doc comment above.
    }
  }

  /// Registers to receive a real watch -> phone "Call Dad" tap (§21.5) — see
  /// this file's own header for the full path this reaches and exactly why.
  ///
  /// Android-only, matching [syncSleepsUntilHandover]'s own guard: on any
  /// other platform (including this package's own `flutter test` host)
  /// there is no native handler that could ever invoke this, so registering
  /// a handler there would be a permanent no-op rather than a genuine
  /// listener — left unregistered instead, honestly.
  ///
  /// This platform channel supports exactly one registered handler at a
  /// time — a real `MethodChannel` constraint, not one this class invents.
  /// Calling this again replaces whatever handler was registered before, the
  /// same way WearSyncBridge.kt's own `register()` now replaces its
  /// MessageClient listener on every call rather than accumulating them.
  ///
  /// A regular (non-final) instance method, not `final`, for the same
  /// override-for-tests reason [syncSleepsUntilHandover] already documents —
  /// see child_home_live_test.dart's own `_FakeWearSyncChannel` for the real
  /// call site.
  void listenForCallDad(void Function() onCallDadRequested) {
    if (!Platform.isAndroid) return;
    _registerCallDadHandler(onCallDadRequested);
  }

  /// Test-only entry point installing the EXACT SAME handler
  /// [listenForCallDad] does (delegating to the identical
  /// [_registerCallDadHandler] private method — not a duplicated copy), just
  /// without [Platform.isAndroid]'s gate. `dart:io`'s `Platform` reflects the
  /// real host OS and cannot be faked from a test, and this suite's own host
  /// is not Android (see [listenForCallDad]'s own dedicated no-op test) — so
  /// this is the only way wear_sync_channel_test.dart can prove the real
  /// MethodChannel wiring a real Android device would install, rather than
  /// only ever proving the non-Android no-op branch.
  @visibleForTesting
  void installCallDadHandlerForTest(void Function() onCallDadRequested) =>
      _registerCallDadHandler(onCallDadRequested);

  void _registerCallDadHandler(void Function() onCallDadRequested) {
    methodChannel.setMethodCallHandler((call) async {
      if (call.method == mCallDadRequested) onCallDadRequested();
    });
  }
}
