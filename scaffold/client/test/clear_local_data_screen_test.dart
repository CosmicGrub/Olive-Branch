// OLIVE BRANCH — "Data on this device": the guardian-only, PIN-gated wipe.
// Fail closed at every stage; a wipe removes data AND the key; nothing here
// is an export.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/clear_local_data_screen.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/maturation_ladder.dart';
import 'package:olive_client/shared_gallery.dart';
import 'package:olive_client/store_cipher.dart';

class _MemorySecure implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(500, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

Future<void> _typePinAndClear(WidgetTester t, String pin) async {
  await t.enterText(find.byKey(const Key('clearDataPin')), pin);
  await t.pump();
  await t.tap(find.byKey(const Key('clearDataButton')));
  await t.pumpAndSettle();
}

void main() {
  late LocalServices services;

  setUp(() {
    services = LocalServices.memory(childId: 'ivy');
    LocalServices.install(services);
  });

  // Seeded INSIDE each test body, never in setUp: setUp runs in the real zone,
  // and a namespace whose futures were created there cannot be awaited from a
  // widget test's fake-async zone.
  Future<void> seed() async {
    await services.area('lists').put('wants', <Object?>['bike']);
    await services.area('journal').put('e1', 'private');
  }

  testWidgets('lists exactly what is kept, from the same catalogue the storage is built from', (t) async {
    await _pump(t, ClearLocalDataScreen(verifyPin: (String _) async => true));
    for (final LocalDataEntry e in localDataCatalogue) {
      expect(find.byKey(ValueKey<String>('data-${e.area}')), findsOneWidget, reason: e.area);
    }
    expect(find.text('Sealed with encryption on this phone.'), findsNWidgets(
        localDataCatalogue.where((LocalDataEntry e) => e.encrypted).length));
    expect(find.textContaining('never part of the court export'), findsOneWidget);
  });

  testWidgets('there is no export or share affordance on this screen (P7, export-free by design)', (t) async {
    await _pump(t, ClearLocalDataScreen(verifyPin: (String _) async => true));
    expect(find.textContaining('xport'), findsOneWidget,
        reason: 'the only mention is the sentence saying it is NOT part of the court export');
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.byIcon(Icons.file_download_outlined), findsNothing);
    expect(find.byIcon(Icons.download), findsNothing);
  });

  testWidgets('a wrong PIN clears nothing', (t) async {
    await seed();
    await _pump(t, ClearLocalDataScreen(verifyPin: (String pin) async => pin == '1234'));
    await _typePinAndClear(t, '0000');
    expect(find.byKey(const Key('clearDataWrongPin')), findsOneWidget);
    expect(find.byKey(const Key('clearDataConfirm')), findsNothing, reason: 'never reaches the confirmation');
    expect(await services.area('lists').get('wants'), <Object?>['bike']);
    expect(await services.area('journal').get('e1'), 'private');
  });

  testWidgets('a verifier that throws is a wrong PIN: fail closed', (t) async {
    await seed();
    await _pump(t, ClearLocalDataScreen(verifyPin: (String _) async => throw const SocketException('offline')));
    await _typePinAndClear(t, '1234');
    expect(find.byKey(const Key('clearDataWrongPin')), findsOneWidget);
    expect(await services.area('lists').get('wants'), <Object?>['bike']);
  });

  testWidgets('with no way to check a PIN the action is unavailable, said plainly, and nothing is cleared', (t) async {
    await seed();
    await _pump(t, const ClearLocalDataScreen(verifyPin: null));
    expect(find.byKey(const Key('clearDataUnavailable')), findsOneWidget);
    expect(find.byKey(const Key('clearDataPin')), findsNothing);
    expect(find.byKey(const Key('clearDataButton')), findsNothing);
    expect(await services.area('lists').get('wants'), <Object?>['bike']);
  });

  testWidgets('the button is disabled until a PIN is typed', (t) async {
    await _pump(t, ClearLocalDataScreen(verifyPin: (String _) async => true));
    expect(t.widget<FilledButton>(find.byKey(const Key('clearDataButton'))).onPressed, isNull);
  });

  testWidgets('a right PIN still asks once more, and "Keep it" clears nothing', (t) async {
    await seed();
    await _pump(t, ClearLocalDataScreen(verifyPin: (String _) async => true));
    await _typePinAndClear(t, '1234');
    expect(find.byKey(const Key('clearDataConfirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('clearDataCancel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('clearDataDone')), findsNothing);
    expect(await services.area('lists').get('wants'), <Object?>['bike']);
  });

  testWidgets('right PIN + confirmation wipes everything, tells the caller, and resets in-process mirrors', (t) async {
    await seed();
    int cleared = 0;
    childSeenRungReveals.add(Grant.ownList);
    await _pump(t, ClearLocalDataScreen(verifyPin: (String pin) async => pin == '1234', onCleared: () => cleared++));
    await _typePinAndClear(t, '1234');
    await t.tap(find.byKey(const Key('clearDataConfirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('clearDataDone')), findsOneWidget);
    expect(cleared, 1);
    expect(await services.area('lists').get('wants'), isNull);
    expect(await services.area('journal').get('e1'), isNull);
    expect(await services.store.namespaces(), isEmpty);
    expect(childSeenRungReveals, isEmpty);
    expect(demoAppGallery.photos, isEmpty);
    expect(t.widget<TextField>(find.byKey(const Key('clearDataPin'))).controller!.text, isEmpty,
        reason: 'the PIN is not left on screen');
  });

  test('a real device wipe takes the files AND the encryption key, and leaves pairing alone', () async {
    final Directory dir = await Directory.systemTemp.createTemp('olive_wipe_test_');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    final _MemorySecure secure = _MemorySecure()..data['olive_paired_device_id'] = 'dev-1';
    final LocalServices real = await LocalServices.boot(
        childId: 'ivy', isLive: true, secure: secure, rootOverride: dir);
    await real.area('journal').put('e1', 'private');
    expect(secure.data.keys, containsAll(<String>[StoreCipherKeyring.keyName, 'olive_paired_device_id']));
    await real.wipeAll();
    expect(dir.existsSync(), isFalse);
    expect(secure.data.containsKey(StoreCipherKeyring.keyName), isFalse);
    expect(secure.data['olive_paired_device_id'], 'dev-1', reason: 'unpairing is the paired-devices screen\'s job');
  });

  group('guardian hub wiring', () {
    testWidgets('the hub lists "Data on this device" and it opens this screen; unavailable without a session', (t) async {
      await _pump(t, const GuardianMoreScreen());
      await t.scrollUntilVisible(find.byKey(const Key('moreDeviceData')), 300,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('moreDeviceData')));
      await t.pumpAndSettle();
      expect(find.byType(ClearLocalDataScreen), findsOneWidget);
      expect(find.byKey(const Key('clearDataUnavailable')), findsOneWidget,
          reason: 'no live session -> no PIN to check -> fail closed');
    });
  });
}
