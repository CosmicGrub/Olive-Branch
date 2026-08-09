// OLIVE BRANCH — phone-side Wear Data Layer client. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §21.5.
//
// Mirrors kiosk_channel.dart's shape: a thin MethodChannel wrapper whose
// channel/method names are contract-checked against the native side
// (android/app/.../WearSyncBridge.kt) by transport.test.mjs, so the two
// cannot drift silently the way an unwired declaration would.
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
// `flutter test`.
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class WearSyncChannel {
  static const methodChannel =
      MethodChannel('com.olivebranch.olive_client/wear_sync');

  static const mSyncSleepsUntilHandover = 'syncSleepsUntilHandover';

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
}
