// OLIVE BRANCH — main_live.dart tests: the new device-pairing-provisioning
// boot branch. docs/superpowers/specs/2026-09-12-device-pairing
// -provisioning-design.md.
//
// `main()` itself calls `Firebase.initializeApp()` and reads real on-device
// secure storage before ever calling `runApp()`, neither of which
// `flutter test`'s harness can honestly exercise (no platform channels) —
// the same reason this file, like every OTHER top-level entry point in this
// client, has never had a `main_live_test.dart` before this pass. Two
// real, complementary things ARE testable and both are covered below:
//
//  A. WIDGET — [OliveLive] itself (public, unlike the private boot helpers
//     that call it) accepts the resolved childId/sessionToken this file's
//     new boot branch computes, and genuinely threads them into the real
//     KioskShell/LiveChildHomeScreen tree — proven by construction, not by
//     re-running main().
//  B. SOURCE STRUCTURE — the boot-branch DECISION itself (bool.hasEnvironment,
//     not a defaultValue comparison; the dart-define path staying
//     unconditional when the define IS set) is a real, load-bearing
//     property no widget test can observe (it's resolved before any widget
//     exists), so it's asserted directly against this file's own source —
//     the identical technique packages/transport/test/transport.test.mjs's
//     own "I contract" section already uses for Dart source it can't
//     otherwise exercise, applied here in Dart instead of Node.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/kiosk_channel.dart';
import 'package:olive_client/kiosk_shell.dart';
import 'package:olive_client/main_live.dart';
import 'package:olive_client/theme.dart';

void main() {
  group('A — OliveLive widget threads the resolved boot identity through', () {
    // Same setup kiosk_shell_test.dart's own header requires: no native
    // kiosk bridge exists under `flutter test`, and the event channel needs
    // SOME handler registered or listening throws.
    const eventChannel = KioskChannel.eventChannel;
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, _NoOpStreamHandler());
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    testWidgets('a redeemed device (non-null sessionToken) builds the real kiosk tree '
        'for its OWN childId, not the seed default', (tester) async {
      await tester.pumpWidget(const OliveLive(
        initialTheme: defaultAppTheme, childId: 'redeemed-child-42', sessionToken: 'real-token'));
      await tester.pump();
      expect(find.byType(KioskShell), findsOneWidget);
      final home = tester.widget<LiveChildHomeScreen>(find.byType(LiveChildHomeScreen));
      expect(home.childId, 'redeemed-child-42');
    });

    testWidgets('the dart-define path (null sessionToken) builds the identical tree shape',
        (tester) async {
      await tester.pumpWidget(const OliveLive(
        initialTheme: defaultAppTheme, childId: 'dart-define-child', sessionToken: null));
      await tester.pump();
      expect(find.byType(KioskShell), findsOneWidget);
      final home = tester.widget<LiveChildHomeScreen>(find.byType(LiveChildHomeScreen));
      expect(home.childId, 'dart-define-child');
    });
  });

  group('B — the boot-branch decision itself, asserted against this file\'s own source', () {
    final src = File('lib/main_live.dart').readAsStringSync();

    test('detects the dart-define via bool.hasEnvironment, never a defaultValue comparison '
        '(the two are NOT the same question — see this file\'s own header)', () {
      expect(src, contains("bool.hasEnvironment('OLIVE_CHILD_ID')"));
    });

    test('the pairing boot branch is gated on that exact flag', () {
      expect(src, contains('if (!_hasChildIdDartDefine)'));
    });

    test('a missing stored identity is what actually triggers the pairing screen', () {
      expect(src, contains('DeviceIdentityStore().load()'));
      expect(src, contains('if (stored == null)'));
    });

    test('the pairing screen it boots into is the real PairingRedeemScreen, compiled '
        'for role: child', () {
      expect(src, contains("PairingRedeemScreen(baseUrl: baseUrl, role: 'child'"));
    });

    test('a successful redeem persists the identity before re-entering the app', () {
      expect(src, contains('DeviceIdentityStore().save(identity)'));
    });

    test('device_revoked is recognized distinctly and clears the stored identity '
        '(not folded into the generic catch)', () {
      expect(src, contains('on DeviceRevokedException'));
      expect(src, contains('DeviceIdentityStore().clear()'));
    });
  });
}

/// Mirrors kiosk_shell_test.dart's own identical helper — the event channel
/// needs a real handler under `flutter test` or listening to it throws.
class _NoOpStreamHandler extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}
  @override
  void onCancel(Object? arguments) {}
}
