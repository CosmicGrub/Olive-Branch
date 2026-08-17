// OLIVE BRANCH — kiosk platform channel. UNVERIFIED (no Flutter toolchain). §5.20.
//
// Mirrors android/app/.../KioskBridge.kt and windows/runner/kiosk_bridge.{h,cpp}.
// The constants below are contract-checked against both native implementations,
// except `mBeginCallHandoff`, which is Android-only (see its own doc comment).
import 'package:flutter/services.dart';

class KioskChannel {
  static const methodChannel = MethodChannel('app.olive/kiosk');
  static const eventChannel  = EventChannel('app.olive/kiosk_events');

  static const mStart   = 'startLockTask';
  static const mStop    = 'stopLockTask';
  static const mMode    = 'lockTaskMode';
  static const mIsOwner = 'isDeviceOwner';
  // Android-only. §16.2 #6 / §5.20: the Jitsi SDK opens calls in its own
  // singleTask Activity, which lock-task pinning refuses to launch as a
  // second task. This hands the pin off to that Activity for the call's
  // duration instead of just dropping it — see WrapperJitsiMeetActivity.kt
  // (third_party/jitsi_meet_flutter_sdk_patched) and KioskBridge.kt.
  static const mBeginCallHandoff = 'beginCallHandoff';

  static const eExited     = 'lockTaskExited';
  static const eBackground = 'backgrounded';
  static const eResumed    = 'resumed';

  Future<String> start() async =>
      await methodChannel.invokeMethod<String>(mStart) ?? 'none';
  Future<String> mode() async =>
      await methodChannel.invokeMethod<String>(mMode) ?? 'none';
  Future<bool> isFullyLocked() async =>
      await methodChannel.invokeMethod<bool>(mIsOwner) ?? false;

  /// Releases the native lock entirely — the real action behind guardian
  /// escalation's "exit kiosk mode" (guardian_escalation_screen.dart). A
  /// no-op, not a crash, on a platform/test context with no native handler
  /// (mirrors [beginCallHandoff]'s own MissingPluginException handling).
  Future<void> stop() async {
    try {
      await methodChannel.invokeMethod<void>(mStop);
    } on MissingPluginException {
      // No native kiosk bridge (Windows without the bridge wired, `flutter
      // test`) — nothing was locked to begin with from this channel's view.
    }
  }

  /// Call right before launching the Jitsi call Activity when [mode] is not
  /// 'none'. Unpins this Activity (so the launch isn't itself a lock-task
  /// violation) and tells the native side to treat the coming backgrounding
  /// as a call handoff rather than a kiosk defeat — see KioskBridge.kt's
  /// `expectingCallHandoff`. A no-op on platforms without this method
  /// (Windows has no Jitsi-Activity conflict to hand off from).
  Future<void> beginCallHandoff() async {
    try {
      await methodChannel.invokeMethod<void>(mBeginCallHandoff);
    } on MissingPluginException {
      // Platform has no call-handoff concept (Windows, `flutter test`).
    }
  }

  // BOTH events are defeats. Backgrounding drops escalation and revokes tokens
  // exactly as an explicit lock-task exit does — losing focus does not
  // invalidate a JWT.
  Stream<String> events() => eventChannel
      .receiveBroadcastStream()
      .map((e) => (e as Map)['event'] as String);
}
