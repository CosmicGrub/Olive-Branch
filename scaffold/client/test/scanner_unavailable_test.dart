// OLIVE BRANCH — when the camera cannot start on a GROWN-UP's scan screen, the plugin's raw English error text is
// replaced by plain words and a button that opens this app's settings. Verified by CI, headless.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/guardian_pin_recovery_screens.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_recovery.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/scanner_unavailable.dart';
import 'package:olive_client/unlock_challenge.dart';
import 'package:olive_client/unlock_child_screen.dart';

const MobileScannerException _denied = MobileScannerException(
    errorCode: MobileScannerErrorCode.permissionDenied,
    errorDetails: MobileScannerErrorDetails(message: 'CAMERA_PERMISSION_DENIED raw plugin text'));

String _everythingShown(WidgetTester t) {
  final List<String> out = <String>[];
  for (final Text w in t.widgetList<Text>(find.byType(Text))) {
    out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  return out.join(' | ');
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 30));
  }
}

/// Pumps whatever errorBuilder the given scanner has, with the plugin's own raw error.
Future<void> _showErrorOf(WidgetTester t, MobileScanner scanner) async {
  expect(scanner.errorBuilder, isNotNull, reason: 'without one the plugin draws its own raw English error text');
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (BuildContext c) => scanner.errorBuilder!(c, _denied)))));
}

void _expectCalm(WidgetTester t) {
  expect(find.byKey(const Key('scannerUnavailableTitle')), findsOneWidget);
  expect(find.byKey(const Key('scannerOpenSettings')), findsOneWidget);
  final String all = _everythingShown(t);
  expect(all, isNot(contains('PERMISSION')));
  expect(all, isNot(contains('denied')));
  expect(all, isNot(contains('raw plugin text')));
  expect(all, contains('Open settings'));
}

void main() {
  testWidgets('the card says it plainly, offers the settings button, and the button asks for the app settings', (t) async {
    int opened = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ScannerUnavailableCard(openSettings: () async => opened++))));
    _expectCalm(t);
    await t.tap(find.byKey(const Key('scannerOpenSettings')));
    expect(opened, 1);
  });

  testWidgets('scannerErrorBuilder drops the plugin error and shows the card', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (BuildContext c) => scannerErrorBuilder(c, _denied)))));
    _expectCalm(t);
  });

  test('openAppSettings calls the native "open", and a missing or failing native side is not an error', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel ch = MethodChannel('test/app_settings');
    final List<String> calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (MethodCall c) async {
      calls.add(c.method);
      return null;
    });
    await openAppSettings(ch);
    expect(calls, <String>['open']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (MethodCall c) async {
      throw PlatformException(code: 'unavailable');
    });
    await openAppSettings(ch);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null);
    await openAppSettings(ch);
    expect(kAppSettingsChannel, 'olive/app_settings');
  });

  group('the real scanners on grown-up screens have it', () {
    testWidgets('unlock a child device (unlockScanner)', (t) async {
      final DeviceKey ak = (await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())))!;
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.pumpWidget(MaterialApp(
          home: UnlockChildScreen(
              pin: pin, responder: UnlockResponder(adultKey: ak, kids: () async => <PairedKid>[]), childName: 'Ivy')));
      await t.pump();
      final MobileScanner s = t.widget<MobileScanner>(find.byKey(const Key('unlockScanner')));
      await _showErrorOf(t, s);
      _expectCalm(t);
    });

    testWidgets('forgot my PIN (forgotScanner)', (t) async {
      final DeviceKey ka = (await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())))!;
      final DeviceKey kb = (await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())))!;
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      final GuardianRecovery a = GuardianRecovery(peers: MemoryGuardianPeerRepository(), deviceKey: () async => ka);
      final GuardianRecovery b = GuardianRecovery(peers: MemoryGuardianPeerRepository(), deviceKey: () async => kb);
      await t.runAsync(() async {
        final GuardianLinker la = await a.linker(), lb = await b.linker();
        await la.accept(await lb.offer('Dad phone'));
        await lb.accept(await la.offer('Mum phone'));
      });
      await t.pumpWidget(MaterialApp(home: ForgotPinScreen(pin: pin, recovery: a)));
      await _settle(t);
      await t.tap(find.byKey(const Key('forgotScanAnswer')));
      await t.pump();
      final MobileScanner s = t.widget<MobileScanner>(find.byKey(const Key('forgotScanner')));
      await _showErrorOf(t, s);
      _expectCalm(t);
    });
  });
}
