// OLIVE BRANCH — wear_sync_channel.dart tests. §21.5.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/wear_sync_channel.dart';

void main() {
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
  });
}
