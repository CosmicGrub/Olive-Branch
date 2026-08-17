// OLIVE BRANCH — kiosk_channel.dart contract tests. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline).
//
// §16.2 #6 / §5.20 — beginCallHandoff() coverage. This is the half of the
// call/kiosk-lock-task fix that a widget test CAN actually see: whether the
// method channel call is shaped correctly and degrades gracefully with no
// native handler. It CANNOT see the half that matters most — whether
// WrapperJitsiMeetActivity actually launches under lock-task pinning instead
// of hitting `E/ActivityTaskManager: Attempted Lock Task Mode violation` —
// because that is real Android ActivityManager behavior with no Dart-visible
// surface at all. That half is the manual/device procedure in
// client/docs/MANUAL_VERIFY_call_lock_task.md, run against real hardware,
// precisely because this failure mode produces no crash and no visible error
// under `flutter test` — it would pass clean either way.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/kiosk_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = KioskChannel.methodChannel;

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('beginCallHandoff — §16.2 #6', () {
    test('invokes the exact method name native code expects', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return 'pinned';
      });

      await KioskChannel().beginCallHandoff();

      expect(seen, isNotNull);
      expect(seen!.method, 'beginCallHandoff');
      expect(seen!.method, KioskChannel.mBeginCallHandoff);
    });

    test('does not throw with no native handler registered '
        '(Windows / flutter test — no Jitsi-Activity conflict to hand off from)',
        () async {
      // No setMockMethodCallHandler call at all — this is the exact
      // situation kiosk_shell.dart's own _engage() already relies on
      // MissingPluginException-swallowing for, on a platform with no kiosk
      // bridge. beginCallHandoff() must degrade the same way, not crash the
      // call flow on a platform that never had a lock-task conflict to
      // begin with.
      await expectLater(KioskChannel().beginCallHandoff(), completes);
    });

    test('a thrown platform exception other than MissingPluginException '
        'still propagates — this method only swallows the "no plugin" case',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'native side blew up');
      });

      await expectLater(
        KioskChannel().beginCallHandoff(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('stop — the real action behind guardian escalation exiting kiosk mode', () {
    test('invokes the exact method name native code expects (mStop)', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return null;
      });

      await KioskChannel().stop();

      expect(seen, isNotNull);
      expect(seen!.method, 'stopLockTask');
      expect(seen!.method, KioskChannel.mStop);
    });

    test('does not throw with no native handler registered', () async {
      await expectLater(KioskChannel().stop(), completes);
    });

    test('a thrown platform exception other than MissingPluginException still propagates',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'native side blew up');
      });

      await expectLater(KioskChannel().stop(), throwsA(isA<PlatformException>()));
    });
  });
}
