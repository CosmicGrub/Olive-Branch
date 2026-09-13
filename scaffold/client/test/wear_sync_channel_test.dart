// OLIVE BRANCH — wear_sync_channel.dart tests. §21.5.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/wear_sync_channel.dart';

void main() {
  // Required before any TestDefaultBinaryMessengerBinding.instance access
  // below (kiosk_channel_test.dart's own identical line, for the identical
  // reason) — plain `test()` blocks, unlike `testWidgets()`, don't implicitly
  // initialize the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  // WearSyncChannel.methodChannel is a shared static — a handler one test
  // installs would otherwise still be registered when the next test runs.
  // Matches kiosk_channel_test.dart's own identical hygiene for the same
  // shared-static-channel reason.
  tearDown(() => WearSyncChannel.methodChannel.setMethodCallHandler(null));

  group('WearSyncChannel', () {
    test('channel and method names match the native contract', () {
      // Mirrored literally in android/app/.../WearSyncBridge.kt and
      // contract-checked against it by transport.test.mjs, the same way
      // kiosk_channel.dart's constants are checked. Asserting the exact
      // strings here too means a typo shows up as a failing Dart test, not
      // only as a failing Node one.
      expect(WearSyncChannel.methodChannel.name,
          'com.olivebranch.olive_client/wear_sync');
      expect(WearSyncChannel.mSyncSleepsUntilHandover, 'syncSleepsUntilHandover');
      expect(WearSyncChannel.mCallDadRequested, 'callDadRequested');
    });

    test('is a no-op on a non-Android test host, not a MissingPluginException',
        () async {
      // `flutter test` runs on the host platform (this machine, not
      // Android), and no native handler is registered for
      // 'com.olivebranch.olive_client/wear_sync' under the test binding —
      // exactly the situation kiosk_shell.dart's own `_engage()` comment
      // describes for the kiosk channel. Without the `Platform.isAndroid`
      // guard, this call would throw MissingPluginException and this test
      // would fail; that it completes cleanly is the actual thing being
      // tested, not just documented.
      await WearSyncChannel().syncSleepsUntilHandover(3);
    });

    test('listenForCallDad registers no handler on a non-Android test host',
        () async {
      // Same [Platform.isAndroid] guard as above, other direction: without
      // it, this would install a real MethodChannel handler even on a host
      // with no native counterpart ever able to invoke it — a permanent
      // no-op masquerading as a live listener. Proven here by simulating a
      // real incoming platform message (see the group below for the full
      // shape of that simulation) and asserting the callback never fires.
      var fired = false;
      WearSyncChannel().listenForCallDad(() => fired = true);
      final data = const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('callDadRequested'));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              'com.olivebranch.olive_client/wear_sync', data, (_) {});
      expect(fired, false);
    });
  });

  group('WearSyncChannel — the real watch -> phone round trip, proven at '
      'the platform-channel layer', () {
    // Uses [WearSyncChannel.installCallDadHandlerForTest], not
    // [WearSyncChannel.listenForCallDad] itself: this suite's own host is
    // not Android (see the dedicated no-op test above), and `dart:io`'s
    // `Platform.isAndroid` reflects the real host OS with no test-time way
    // to fake it, so calling [listenForCallDad] directly here would silently
    // register nothing and every test below would vacuously pass for the
    // wrong reason. [installCallDadHandlerForTest] delegates to the exact
    // same private handler-installing code [listenForCallDad] itself calls
    // once its own [Platform.isAndroid] gate passes — see that method's own
    // doc comment — so this is still exercising the real production
    // registration logic, not a rewritten copy of it.
    //
    // None of these tests call the registered callback's Dart function
    // directly either — that would only prove a closure works, not that the
    // wiring actually reaches a real MethodChannel handler the way
    // android/app/.../WearSyncBridge.kt's real
    // `methods.invokeMethod(M_CALL_DAD_REQUESTED, null)` call would arrive.
    // Instead, each test round-trips through
    // TestDefaultBinaryMessengerBinding — Flutter's own test seam for
    // simulating a platform message exactly as the engine would deliver one
    // from native code — using the real `StandardMethodCodec` a real
    // MethodChannel uses to encode/decode. This is the strongest proof
    // available without a live device or emulator (see WearSyncBridge.kt's
    // own header for why neither exists in this environment this pass):
    // real Dart-side platform-channel plumbing, a real codec, a message
    // shaped exactly like the one native code sends — only the actual
    // Kotlin `invokeMethod` call and the physical watch tap upstream of it
    // are unverified here. This is honestly disclosed as compiled/
    // unit-tested only, not live-device-verified.
    const codec = StandardMethodCodec();
    const channelName = 'com.olivebranch.olive_client/wear_sync';

    Future<void> simulateNativeCall(String method, {Object? arguments}) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
                channelName,
                codec.encodeMethodCall(MethodCall(method, arguments)),
                (_) {});

    test('a real callDadRequested platform message invokes the registered '
        'callback exactly once', () async {
      var callCount = 0;
      WearSyncChannel().installCallDadHandlerForTest(() => callCount++);

      await simulateNativeCall(WearSyncChannel.mCallDadRequested);

      expect(callCount, 1);
    });

    test('fires again on a second real tap — not a one-shot listener',
        () async {
      var callCount = 0;
      WearSyncChannel().installCallDadHandlerForTest(() => callCount++);

      await simulateNativeCall(WearSyncChannel.mCallDadRequested);
      await simulateNativeCall(WearSyncChannel.mCallDadRequested);
      await simulateNativeCall(WearSyncChannel.mCallDadRequested);

      expect(callCount, 3);
    });

    test('an unrelated method name on the same channel is ignored, not '
        'mistaken for a call-dad tap', () async {
      var fired = false;
      WearSyncChannel().installCallDadHandlerForTest(() => fired = true);

      await simulateNativeCall('someOtherMethod');

      expect(fired, false);
    });

    test('registering a second time replaces the first handler, matching '
        "WearSyncBridge.kt's own single-listener contract", () async {
      var firstFired = false;
      var secondFired = false;
      final channel = WearSyncChannel();
      channel.installCallDadHandlerForTest(() => firstFired = true);
      channel.installCallDadHandlerForTest(() => secondFired = true);

      await simulateNativeCall(WearSyncChannel.mCallDadRequested);

      expect(firstFired, false);
      expect(secondFired, true);
    });
  });
}
