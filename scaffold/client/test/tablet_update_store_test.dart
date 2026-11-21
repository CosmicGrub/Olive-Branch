// OLIVE BRANCH — the sealed `updatestage` area: a record survives a restart, and a tampered or hostile record is
// dropped as if absent (never trusted, never a path out of the private folder). Headless.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/tablet_update_store.dart';

StagedUpdate sample({String file = 'update-5200.apk'}) => StagedUpdate(
    stage: StageState.ready,
    versionName: '0.52.0',
    versionCode: 5200,
    fileName: file,
    document: Uint8List.fromList(<int>[1, 2, 3, 4]),
    headline: 'Calmer pairing',
    notes: const <String>['Calmer pairing.']);

void main() {
  test('the area is in the catalogue, device-scoped and sealed', () {
    final LocalDataEntry e = localDataCatalogue.singleWhere((LocalDataEntry x) => x.area == 'updatestage');
    expect(e.scope, LocalScope.device);
    expect(e.encrypted, isTrue);
  });

  test('a staged record, the last result and what is new round-trip through the real area', () async {
    final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
    final LocalStoreStagedUpdateStore store = LocalStoreStagedUpdateStore(s.area('updatestage'));
    expect(await store.loadStaged(), isNull);
    await store.saveStaged(sample());
    await store.saveLastResult('installDeclined');
    await store.saveWhatsNew(const WhatsNew(versionName: '0.52.0', headline: 'h', notes: <String>['a']));
    final LocalStoreStagedUpdateStore again = LocalStoreStagedUpdateStore(s.area('updatestage'));
    final StagedUpdate? got = await again.loadStaged();
    expect(got!.versionCode, 5200);
    expect(got.document, <int>[1, 2, 3, 4]);
    expect(await again.loadLastResult(), 'installDeclined');
    expect((await again.loadWhatsNew())!.notes, <String>['a']);
    await again.clearStaged();
    expect(await again.loadStaged(), isNull);
  });

  test('a hostile stored record is read as nothing: path tricks, bad types, huge or empty notices', () {
    final Map<String, Object?> good = sample().toJson();
    expect(StagedUpdate.tryParse(good), isNotNull);
    for (final String bad in <String>['../evil.apk', 'a/b.apk', 'a\b.apk', '', '..', 'x' * 81]) {
      expect(StagedUpdate.tryParse(<String, Object?>{...good, 'f': bad}), isNull, reason: 'file name "$bad"');
    }
    expect(StagedUpdate.tryParse(<String, Object?>{...good, 's': 'nonsense'}), isNull);
    expect(StagedUpdate.tryParse(<String, Object?>{...good, 'vc': 0}), isNull);
    expect(StagedUpdate.tryParse(<String, Object?>{...good, 'vc': '5200'}), isNull);
    expect(StagedUpdate.tryParse(<String, Object?>{...good, 'doc': ''}), isNull);
    expect(StagedUpdate.tryParse(<String, Object?>{...good, 'doc': '***not base64***'}), isNull);
    expect(StagedUpdate.tryParse(<String, Object?>{...good, 'n': List<String>.filled(13, 'x')}), isNull);
    expect(StagedUpdate.tryParse('a string'), isNull);
    expect(StagedUpdate.tryParse(null), isNull);
  });
}
