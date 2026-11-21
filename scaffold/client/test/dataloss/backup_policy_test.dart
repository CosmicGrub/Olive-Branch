// OLIVE BRANCH — data-loss harness, the backup's rules: every catalogued area has a decided place, her private areas and
// the device's own never ride along, a hostile or damaged snapshot cannot plant anything, one bad area never blocks the
// rest, a full phone refuses an area whole, and restore never deletes or overwrites.
@Tags(<String>['dataloss'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_sync_event.dart' show SyncKind, kSyncKinds, kSyncNeverAreas;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_snapshot.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

NamespaceSpec specOf(String area, {String owner = 'ivy'}) {
  final LocalDataEntry e = localDataEntry(area);
  final String name = switch (e.scope) {
    LocalScope.child => 'child.$owner.$area',
    LocalScope.guardian => 'guardian.local-guardian.$area',
    LocalScope.device => 'device.$area',
  };
  return NamespaceSpec(name: name, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes);
}

LocalStore fresh([int fill = 5]) =>
    LocalStore(backend: MemoryStoreBackend(), cipher: AesGcmStoreCipher(Uint8List.fromList(List<int>.filled(32, fill))));

LocalSnapshot snapOf(Map<String, Map<String, Object?>> areas, {int schema = 1}) => LocalSnapshot(<String, AreaImage>{
      for (final MapEntry<String, Map<String, Object?>> e in areas.entries) e.key: AreaImage(e.key, schema, e.value),
    });

void main() {
  group('every area has a decided place in the family backup', () {
    test('the table and the catalogue name exactly the same areas (a new area cannot be added without deciding)', () {
      expect(kBackupClass.keys.toSet(), localDataCatalogue.map((LocalDataEntry e) => e.area).toSet());
    });

    test('her private areas never sync, and nothing the sync carries is left out of the backup', () {
      final Set<String> priv = <String>{
        for (final MapEntry<String, BackupClass> e in kBackupClass.entries)
          if (e.value == BackupClass.childPrivate) e.key,
      };
      expect(priv, <String>{'journal', 'worries', 'feelings', 'teen', 'mymarks', 'memorybox'});
      expect(kSyncNeverAreas.toSet().containsAll(priv), isTrue);
      for (final SyncKind k in kSyncKinds.values) {
        expect(kBackupClass[k.area], BackupClass.family, reason: '${k.name} syncs but its area is not in the backup');
      }
    });

    test('what belongs to one device is never copied to another', () {
      final Set<String> dev = <String>{
        for (final MapEntry<String, BackupClass> e in kBackupClass.entries)
          if (e.value == BackupClass.deviceBound) e.key,
      };
      expect(dev, containsAll(<String>['devicekey', 'childpairing', 'adultunlock', 'localpin', 'role', 'account']));
    });
  });

  group('a snapshot that is not exactly the right shape is refused whole, and never throws', () {
    final Map<String, Object?> good = <String, Object?>{
      'v': 1,
      'areas': <String, Object?>{
        'child.ivy.lists': <String, Object?>{'schema': 1, 'data': <String, Object?>{'k': 1}},
      },
    };
    test('the good one reads', () => expect(LocalSnapshot.fromJson(good), isNotNull));
    final Map<String, Object?> bads = <String, Object?>{
      'not a map': <Object?>[1],
      'wrong version': <String, Object?>{...good, 'v': 2},
      'extra field': <String, Object?>{...good, 'x': 1},
      'areas a list': <String, Object?>{'v': 1, 'areas': <Object?>[]},
      'bad namespace name': <String, Object?>{
        'v': 1,
        'areas': <String, Object?>{'../x': <String, Object?>{'schema': 1, 'data': <String, Object?>{}}},
      },
      'schema a string': <String, Object?>{
        'v': 1,
        'areas': <String, Object?>{'child.ivy.lists': <String, Object?>{'schema': '1', 'data': <String, Object?>{}}},
      },
      'bad key': <String, Object?>{
        'v': 1,
        'areas': <String, Object?>{'child.ivy.lists': <String, Object?>{'schema': 1, 'data': <String, Object?>{'bad key': 1}}},
      },
      'area with extra field': <String, Object?>{
        'v': 1,
        'areas': <String, Object?>{'child.ivy.lists': <String, Object?>{'schema': 1, 'data': <String, Object?>{}, 'x': 1}},
      },
    };
    for (final MapEntry<String, Object?> bad in bads.entries) {
      test('refused: ${bad.key}', () => expect(LocalSnapshot.fromJson(bad.value), isNull));
    }
    test('bytes that are not JSON, or not UTF-8, are refused', () {
      expect(LocalSnapshot.fromBytes(Uint8List.fromList(<int>[0xff, 0xfe, 0x00])), isNull);
      expect(LocalSnapshot.fromBytes(Uint8List.fromList(utf8.encode('{"v":1'))), isNull);
      expect(LocalSnapshot.fromBytes(Uint8List(0)), isNull);
    });
  });

  group('a hostile or damaged snapshot cannot plant anything, and one bad area never blocks the rest', () {
    test('a device key, her journal, an unknown area, the wrong scope, a too-big area are each refused by name; the good areas still land', () async {
      final LocalStore s = fresh();
      final Map<String, Map<String, Object?>> areas = <String, Map<String, Object?>>{
        'child.ivy.lists': <String, Object?>{'want:1': 'a bike'},
        'device.devicekey': <String, Object?>{'key': 'planted'},
        'child.ivy.journal': <String, Object?>{'entry:1': 'planted'},
        'child.ivy.nonsense': <String, Object?>{'k': 1},
        'device.pictures': <String, Object?>{'k': 1}, // pictures is a child area: wrong scope
        'child.ivy.passes': <String, Object?>{'k': 'x' * (64 * 1024 + 1)}, // over its 64 KiB ceiling
        'guardian.local-guardian.emergencycard': <String, Object?>{'k': 1}, // emergencycard is a child area
        'child.ivy.pictures': <String, Object?>{'doodle:1': 'strokes'},
      };
      final RestoreReport r = await restoreSnapshot(s, snapOf(areas));
      expect(r.refused, <String, String>{
        'device.devicekey': 'not_family',
        'child.ivy.journal': 'not_family',
        'child.ivy.nonsense': 'not_listed',
        'device.pictures': 'not_listed',
        'child.ivy.passes': 'too_big',
        'guardian.local-guardian.emergencycard': 'not_listed',
      });
      expect(r.restored, <String>['child.ivy.lists', 'child.ivy.pictures']);
      expect(await s.namespaces(), <String>['child.ivy.lists', 'child.ivy.pictures']);
    });

    test('a newer schema is refused, not guessed at', () async {
      final LocalStore s = fresh();
      final RestoreReport n = await restoreSnapshot(
          s, snapOf(<String, Map<String, Object?>>{'child.ivy.stories': <String, Object?>{'k': 1}}, schema: 2));
      expect(n.refused, <String, String>{'child.ivy.stories': 'schema'});
      expect(await s.namespaces(), isEmpty);
    });

    test('a full phone refuses that area whole (nothing partly written) and still restores the others', () async {
      final LocalStore s = fresh();
      final LocalNamespace passes = s.open(specOf('passes'));
      await passes.put('mine', 'y' * (60 * 1024));
      final RestoreReport r = await restoreSnapshot(s, snapOf(<String, Map<String, Object?>>{
        'child.ivy.passes': <String, Object?>{'theirs': 'z' * (10 * 1024)},
        'child.ivy.lists': <String, Object?>{'want:1': 'a bike'},
      }));
      expect(r.refused, <String, String>{'child.ivy.passes': 'full'});
      expect(r.restored, <String>['child.ivy.lists']);
      expect(await passes.list(), <String>['mine'], reason: 'a refused area must be left exactly as it was');
    });
  });

  group('restore never deletes and never overwrites', () {
    test('a key the phone holds keeps its value, the backup\'s different value is kept in quarantine, and a repeat changes nothing', () async {
      final LocalStore s = fresh();
      await s.open(specOf('lists')).put('want:1', 'THIS PHONE');
      await s.open(specOf('lists')).put('want:2', 'same');
      await s.open(specOf('lists')).put('only-here', 'stays');
      final LocalSnapshot snap = snapOf(<String, Map<String, Object?>>{
        'child.ivy.lists': <String, Object?>{'want:1': 'THE BACKUP', 'want:2': 'same', 'only-in-backup': 'comes'},
      });
      final RestoreReport r = await restoreSnapshot(s, snap);
      expect(<int>[r.keysAdded, r.keysAlreadyHeld, r.valuesKept], <int>[1, 1, 1]);
      final LocalNamespace ns = s.open(specOf('lists'));
      final Map<String, Object?> expected = <String, Object?>{
        'want:1': 'THIS PHONE', 'want:2': 'same', 'only-here': 'stays', 'only-in-backup': 'comes',
      };
      expect(await ns.readAll(), expected);
      expect(await s.quarantined(), 1);
      final RestoreReport again = await restoreSnapshot(s, snap);
      expect(again.keysAdded, 0);
      expect(await ns.readAll(), expected);
    });

    test('an empty snapshot changes nothing', () async {
      final LocalStore s = fresh();
      await s.open(specOf('lists')).put('a', 1);
      final Map<String, String> before = await areaDigests(s);
      final RestoreReport r = await restoreSnapshot(s, snapOf(<String, Map<String, Object?>>{}));
      expect(r.restored, isEmpty);
      expect(await areaDigests(s), before);
    });

    test('an invalid key in a document is refused before anything of that area is written', () async {
      final LocalStore s = fresh();
      final LocalNamespace ns = s.open(specOf('lists'));
      await ns.put('keep', 1);
      await expectLater(ns.mergeMissing(<String, Object?>{'good': 1, 'bad key': 2}), throwsA(isA<LocalStoreBadName>()));
      expect(await ns.readAll(), <String, Object?>{'keep': 1}, reason: 'half of a refused merge was written');
    });
  });

  group('a changed byte is caught', () {
    test('editing one value in the backup text changes its digest, so the equivalence check names the area', () async {
      final LocalStore a = fresh();
      await a.open(specOf('lists')).put('want:1', 'a bike');
      final LocalSnapshot snap = await takeSnapshot(a);
      final String text = utf8.decode(snap.toBytes());
      final LocalSnapshot tampered =
          LocalSnapshot.fromBytes(Uint8List.fromList(utf8.encode(text.replaceFirst('a bike', 'a bake'))))!;
      expect(tampered.digest, isNot(snap.digest));
      final LocalStore b = fresh(9);
      await restoreSnapshot(b, tampered);
      expect(compareDigests(await areaDigests(a), await areaDigests(b)).changed, <String>['child.ivy.lists']);
    });
  });
}
