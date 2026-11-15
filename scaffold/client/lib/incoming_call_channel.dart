// UNVERIFIED on a real device and against Google: covered by flutter test only (MASTERFILE 7.20).
// OLIVE BRANCH — the Dart end of the Android incoming-call bridge. MASTERFILE §5.25.2, §7.18.
//
// Mirrors android/app/.../IncomingCallBridge.kt. The names below are contract-checked against it by
// test/android_push_contract_test.dart (a renamed channel or key on one side only fails the build).
//
// WHAT THE NATIVE SIDE DOES, AND WHY NOT DART. A closed app is rung by a small Android broadcast receiver
// (OlivePushReceiver.kt) that reads the push's three content-free keys and posts the call notification with a
// full-screen intent. It must not depend on Dart: a killed app has no Dart isolate, and a separate background
// isolate is the unreliable road. When the grown-up's ring is tapped (or the screen was off and the full-screen
// intent opened the app), MainActivity hands the session id here:
//
//   Dart -> native   attach              ->  the ring that opened the app, if any (consumed once)
//                    ringFinished(ref)   ->  put away the ring (notification, show-over-lock-screen)
//                    status              ->  { notifications, fullScreen } booleans, for the grown-up's card
//                    requestNotifications->  the system's one-time "allow notifications" box (a grown-up taps it)
//                    openFullScreenSettings
//   native -> Dart   ring {ref, at}      ->  a ring arrived while Dart is attached (the app was already open)
//                    cancel {ref}        ->  the caller hung up
//
// Every call is a no-op, never a crash, where there is no native side (Windows, `flutter test`).
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';

import 'call_lifecycle.dart' show isCallSessionId;

/// A ring that came from the phone's own notification or full-screen intent.
@immutable
class IncomingRing {
  const IncomingRing(this.ref, this.postedAtMs);
  final String ref;

  /// When the phone received the push (epoch milliseconds), or null if it did not say.
  final int? postedAtMs;

  /// null for anything that is not a well-formed ring: a missing or non-string ref, a ref that is not a canonical
  /// session id, a negative or non-integer time. Hostile or damaged data is dropped, not repaired.
  static IncomingRing? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? ref = raw['ref'];
    if (!isCallSessionId(ref)) return null;
    final Object? at = raw['at'];
    final int? ms = (at is int && at > 0) ? at : null;
    return IncomingRing((ref! as String).toLowerCase(), ms);
  }
}

/// What the phone currently allows. Two booleans, nothing else.
@immutable
class AlertStatus {
  const AlertStatus({required this.notifications, required this.fullScreen});
  final bool notifications;
  final bool fullScreen;

  static AlertStatus? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? n = raw['notifications'], f = raw['fullScreen'];
    if (n is! bool || f is! bool) return null;
    return AlertStatus(notifications: n, fullScreen: f);
  }
}

class IncomingCallChannel {
  IncomingCallChannel({MethodChannel? channel}) : _channel = channel ?? methodChannel;

  static const MethodChannel methodChannel = MethodChannel('app.olive/incoming_call');

  static const mAttach = 'attach';
  static const mRingFinished = 'ringFinished';
  static const mStatus = 'status';
  static const mRequestNotifications = 'requestNotifications';
  static const mOpenFullScreenSettings = 'openFullScreenSettings';
  static const eRing = 'ring';
  static const eCancel = 'cancel';
  static const kRef = 'ref';
  static const kAt = 'at';

  final MethodChannel _channel;

  /// Starts listening for native rings and cancels and returns the ring that opened the app, if one did. Safe to
  /// call where there is no native side: it listens to nothing and returns null.
  Future<IncomingRing?> attach({
    required void Function(IncomingRing ring) onRing,
    required void Function(String ref) onCancel,
  }) async {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case eRing:
          final IncomingRing? r = IncomingRing.tryParse(call.arguments);
          if (r != null) onRing(r);
        case eCancel:
          final Object? a = call.arguments;
          final Object? ref = a is Map ? a[kRef] : null;
          if (isCallSessionId(ref)) onCancel((ref! as String).toLowerCase());
      }
      return null;
    });
    try {
      return IncomingRing.tryParse(await _channel.invokeMethod<Object?>(mAttach));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void detach() => _channel.setMethodCallHandler(null);

  /// Puts the ring away. [ref] null means "whatever ring is up" (a call that came from a ring has ended).
  Future<void> ringFinished([String? ref]) async {
    try {
      await _channel.invokeMethod<void>(mRingFinished, <String, Object?>{kRef: ref});
    } on MissingPluginException {
      // No native side.
    } on PlatformException {
      // Best effort: a ring that cannot be put away times itself out in ninety seconds.
    }
  }

  /// null where there is no native side.
  Future<AlertStatus?> status() async {
    try {
      return AlertStatus.tryParse(await _channel.invokeMethod<Object?>(mStatus));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Shows the system's "allow notifications" box (Android 13 and later). true when allowed afterwards.
  Future<bool> requestNotifications() async {
    try {
      return await _channel.invokeMethod<bool>(mRequestNotifications) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openFullScreenSettings() async {
    try {
      await _channel.invokeMethod<void>(mOpenFullScreenSettings);
    } on MissingPluginException {
      // No native side.
    } on PlatformException {
      // Nothing to do; the card keeps saying what is still off.
    }
  }
}
