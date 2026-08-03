// OLIVE BRANCH — kiosk platform channel. UNVERIFIED (no Flutter toolchain). §5.20.
//
// Mirrors native/android/KioskBridge.kt and native/windows/AssignedAccessBridge.cs.
// The constants below are contract-checked against both native files.
import 'package:flutter/services.dart';

class KioskChannel {
  static const methodChannel = MethodChannel('app.olive/kiosk');
  static const eventChannel  = EventChannel('app.olive/kiosk_events');

  static const mStart   = 'startLockTask';
  static const mStop    = 'stopLockTask';
  static const mMode    = 'lockTaskMode';
  static const mIsOwner = 'isDeviceOwner';

  static const eExited     = 'lockTaskExited';
  static const eBackground = 'backgrounded';
  static const eResumed    = 'resumed';

  Future<String> start() async =>
      await methodChannel.invokeMethod<String>(mStart) ?? 'none';
  Future<String> mode() async =>
      await methodChannel.invokeMethod<String>(mMode) ?? 'none';
  Future<bool> isFullyLocked() async =>
      await methodChannel.invokeMethod<bool>(mIsOwner) ?? false;

  // BOTH events are defeats. Backgrounding drops escalation and revokes tokens
  // exactly as an explicit lock-task exit does — losing focus does not
  // invalidate a JWT.
  Stream<String> events() => eventChannel
      .receiveBroadcastStream()
      .map((e) => (e as Map)['event'] as String);
}
