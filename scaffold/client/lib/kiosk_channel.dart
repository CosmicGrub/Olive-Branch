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
  // Android-only. §16.2 #6 / §5.20: the Jitsi SDK opened calls in its own
  // singleTask Activity, which lock-task pinning refuses to launch as a
  // second task. This handed the pin off to that Activity for the call's
  // duration instead of just dropping it — see WrapperJitsiMeetActivity.kt
  // (third_party/jitsi_meet_flutter_sdk_patched) and KioskBridge.kt.
  //
  // MASTERFILE §16.2 #6 REVERSED AGAIN — NOT CALLED ANYWHERE as of the
  // LiveKit migration (call_screen.dart's own doc comment on why: a LiveKit
  // call is a normal Flutter route in the SAME Activity, so there's no
  // second Activity left to hand the pin off to). Left in place, not
  // removed — the method, the native KioskBridge.kt implementation, and
  // MainActivity.kt's ACTION_CALL_ACTIVITY_DESTROYED re-pin-on-resume logic
  // are all unremoved pending real kiosk-lock verification on the Fold5
  // with a real LiveKit project (see docs/superpowers/specs/2026-08-29
  // -livekit-call-migration-design.md's own testing plan) — "verified
  // rather than trusted from code review," this file's own standing
  // discipline, applies to REMOVING code with real safety implications
  // (§8.3 kiosk lock-task) just as much as it applies to shipping it.
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

  /// NOT CALLED ANYWHERE as of the LiveKit migration — see this method's
  /// own field-level doc comment above ([mBeginCallHandoff]) for the full
  /// account. Kept working, not stubbed out, pending real verification.
  ///
  /// What it did and would still do if called: unpins this Activity (so
  /// launching a second, singleTask Activity isn't itself a lock-task
  /// violation) and tells the native side to treat the coming backgrounding
  /// as a call handoff rather than a kiosk defeat — see KioskBridge.kt's
  /// `expectingCallHandoff`. A no-op on platforms without this method
  /// (Windows never had a Jitsi-Activity conflict to hand off from).
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
