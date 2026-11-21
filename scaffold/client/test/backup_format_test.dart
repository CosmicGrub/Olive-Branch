// OLIVE BRANCH — backup_format.dart: sealing, opening, and every way a backup can be wrong.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_format.dart';
import 'package:olive_client/backup_keys.dart';
import 'package:olive_client/local_services.dart';

import 'support/backup_rig.dart';

class _Sealed {
  _Sealed(this.set, this.chunks, this.snap);
  final SealedSet set;
  final Map<String, Uint8List> chunks;
  final BackupSnapshot snap;
}

Future<_Sealed> _seal(Phone p, BackupKind kind, Uint8List pub,
    {int big = 0, int seq = 1, String? setId}) async {
  final LocalServices s = p.open();
  await populate(s, kind, bigPictures: big);
  final BackupSnapshot snap = await captureSnapshot(s.store, kind);
  final Map<String, Uint8List> chunks = <String, Uint8List>{};
  final SealedSet sealed = await sealSnapshot(snap, pub,
      onChunk: (String id, Uint8List b) async => chunks[id] = b,
      createdMs: 1700000000000, seq: seq, from: 'A grown-up\'s phone', setId: setId, random: Random(3));
  return _Sealed(sealed, chunks, snap);
}

void main() {
  late BackupKeyPair family;
  late BackupKeyPair other;

  setUpAll(() async {
    family = await BackupKeyPair.fromSecret(newBackupSecret(Random(1)), BackupPurpose.family);
    other = await BackupKeyPair.fromSecret(newBackupSecret(Random(2)), BackupPurpose.family);
  });

  group('canonical json and fingerprints', () {
    test('key order does not change the bytes, so equal data has one fingerprint', () async {
      expect(canonicalJson(<String, Object?>{'b': 1, 'a': <String, Object?>{'z': 1, 'y': <Object?>[2, 1]}}),
          canonicalJson(<String, Object?>{'a': <String, Object?>{'y': <Object?>[2, 1], 'z': 1}, 'b': 1}));
      expect(await areaContentHash('child.mia.care', <String, Object?>{'a': 1, 'b': 2}),
          await areaContentHash('child.mia.care', <String, Object?>{'b': 2, 'a': 1}));
      expect(await areaContentHash('child.mia.care', <String, Object?>{'a': 1}),
          isNot(await areaContentHash('child.mia.care', <String, Object?>{'a': 2})));
      expect(await areaContentHash('child.mia.care', <String, Object?>{'a': 1}),
          isNot(await areaContentHash('child.sam.care', <String, Object?>{'a': 1})), reason: 'bound to the namespace');
    });

    test('namespaces parse to their area, owner and scope, and strays do not parse', () {
      expect(NsRef.parse('child.mia.care')!.area, 'care');
      expect(NsRef.parse('child.mia.care')!.ownerId, 'mia');
      expect(NsRef.parse('guardian.gid-one.localfamily')!.scope, LocalScope.guardian);
      expect(NsRef.parse('device.role')!.scope, LocalScope.device);
      for (final String bad in <String>['restoreundo.ab12.child.mia.care', 'child.mia.nothing', 'guardian.x.care',
          'device.care', 'child.care', 'x', '', 'device.x.role', 'restoreundo.abcd.3']) {
        expect(NsRef.parse(bad), isNull, reason: bad);
      }
      expect(NsRef.parse('child.mia.care')!.withOwner('sam').name, 'child.sam.care');
    });
  });

  group('the snapshot', () {
    test('holds exactly the areas of the kind that have something in them, and writes nothing', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      await populate(s, BackupKind.family);
      await populate(s, BackupKind.hersPrivate);
      // A device-bound area that must never be captured.
      await s.area('devicekey').put('k', <String, Object?>{'secret': 'do-not-copy'});
      final List<String> before = await s.store.namespaces();
      final BackupSnapshot fam = await captureSnapshot(s.store, BackupKind.family);
      final BackupSnapshot priv = await captureSnapshot(s.store, BackupKind.hersPrivate);
      expect(await s.store.namespaces(), before, reason: 'read-only');
      expect(fam.areas.map((AreaSnapshot a) => a.ref.area).toSet(), areasOfBackup(BackupKind.family).toSet());
      expect(priv.areas.map((AreaSnapshot a) => a.ref.area).toSet(), areasOfBackup(BackupKind.hersPrivate).toSet());
      for (final AreaSnapshot a in fam.areas) {
        expect(a.ref.area, isNot('devicekey'));
        expect(a.ref.area, isNot('journal'));
      }
      expect(fam.contentHash, isNot(priv.contentHash));
    });

    test('an area that cannot be read is named, not silently dropped', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      await s.area('care').put('k', 'v');
      p.backend.plant('child.mia.care', Uint8List.fromList(utf8.encode('not json')));
      final BackupSnapshot snap = await captureSnapshot(p.open().store, BackupKind.family);
      expect(snap.unreadable, <String>['child.mia.care']);
      expect(snap.areas, isEmpty);
    });
  });

  group('sealing and opening', () {
    test('a backup opens with the right key and gives back every area with the same fingerprint', () async {
      final _Sealed s = await _seal(Phone(), BackupKind.family, family.publicKey);
      final OpenedManifest m = await openManifest(s.set.header, s.set.manifest, family);
      expect(m.kind, BackupKind.family);
      expect(m.seq, 1);
      expect(m.from, "A grown-up's phone");
      expect(m.contentHash, s.snap.contentHash);
      final List<RestoredArea> back = await readAreas(m, (String id) async => s.chunks[id]);
      expect(back.length, s.snap.areas.length);
      for (int i = 0; i < back.length; i++) {
        expect(back[i].entry.hash, s.snap.areas[i].hash);
        expect(await areaContentHash(back[i].entry.namespace, back[i].data), s.snap.areas[i].hash);
      }
    });

    test('a large area takes several chunks, every full chunk is 128 KiB, and it still round trips', () async {
      final _Sealed s = await _seal(Phone(), BackupKind.hersKeep, family.publicKey, big: 9000);
      expect(s.chunks.length, greaterThan(1));
      final BackupHeader h = BackupHeader.parse(s.set.header);
      for (int i = 0; i < h.chunks.length - 1; i++) {
        expect(h.chunks[i].value, kChunkBytes + 4 + 12 + 16);
      }
      expect((h.chunks.last.value - 12 - 16) % kChunkPadStep, 0, reason: 'the last chunk is padded to a step');
      final OpenedManifest m = await openManifest(s.set.header, s.set.manifest, family);
      final List<RestoredArea> back = await readAreas(m, (String id) async => s.chunks[id]);
      expect(back.map((RestoredArea a) => a.entry.hash).toList(), s.snap.areas.map((AreaSnapshot a) => a.hash).toList());
    });

    test('an empty snapshot still seals and opens (a phone with nothing yet)', () async {
      final LocalServices s = Phone().open();
      final BackupSnapshot snap = await captureSnapshot(s.store, BackupKind.family);
      expect(snap.isEmpty, isTrue);
      final Map<String, Uint8List> chunks = <String, Uint8List>{};
      final SealedSet sealed = await sealSnapshot(snap, family.publicKey,
          onChunk: (String id, Uint8List b) async => chunks[id] = b, createdMs: 1, seq: 1);
      final OpenedManifest m = await openManifest(sealed.header, sealed.manifest, family);
      expect(await readAreas(m, (String id) async => chunks[id]), isEmpty);
    });

    test('the sealed bytes and the header carry no area name, no child, no text', () async {
      final _Sealed s = await _seal(Phone(), BackupKind.family, family.publicKey);
      final String header = utf8.decode(s.set.header);
      final List<String> secrets = <String>['mia', 'care', 'emergencycard', 'gid-one', 'note '];
      for (final String w in secrets) {
        expect(header.contains(w), isFalse, reason: 'header: $w');
      }
      // Sealed bytes are random-looking: a 3-letter name could appear by chance, so only longer words are looked for.
      for (final String w in secrets.where((String x) => x.length > 4)) {
        expect(utf8.decode(s.set.manifest, allowMalformed: true).contains(w), isFalse, reason: 'manifest: $w');
        for (final Uint8List c in s.chunks.values) {
          expect(utf8.decode(c, allowMalformed: true).contains(w), isFalse, reason: 'chunk: $w');
        }
      }
    });

    test('two backups of the same data share no chunk bytes and no chunk names', () async {
      final Phone p = Phone();
      final _Sealed a = await _seal(p, BackupKind.family, family.publicKey);
      final LocalServices s = p.open();
      final BackupSnapshot snap = await captureSnapshot(s.store, BackupKind.family);
      final Map<String, Uint8List> chunks2 = <String, Uint8List>{};
      final SealedSet b = await sealSnapshot(snap, family.publicKey,
          onChunk: (String id, Uint8List x) async => chunks2[id] = x, createdMs: 2, seq: 2);
      expect(a.chunks.keys.toSet().intersection(chunks2.keys.toSet()), isEmpty);
      expect(a.set.setId, isNot(b.setId));
    });

    test('the wrong key, a key for another purpose and another family\'s key never open it', () async {
      final _Sealed s = await _seal(Phone(), BackupKind.family, family.publicKey);
      for (final BackupKeyPair bad in <BackupKeyPair>[
        other,
        await BackupKeyPair.fromSecret(newBackupSecret(Random(1)), BackupPurpose.keep),
      ]) {
        await expectLater(openManifest(s.set.header, s.set.manifest, bad),
            throwsA(isA<BackupFormatException>().having((BackupFormatException e) => e.code, 'code', 'key')));
      }
    });

    test('a changed header, a changed manifest or a swapped manifest fails to open', () async {
      final _Sealed a = await _seal(Phone(), BackupKind.family, family.publicKey, seq: 1);
      final _Sealed b = await _seal(Phone(), BackupKind.family, family.publicKey, seq: 2);
      // Header edited (drop the last chunk from the list).
      final Map<String, Object?> h = jsonDecode(utf8.decode(a.set.header)) as Map<String, Object?>;
      final List<Object?> ch = List<Object?>.of(h['chunks'] as List);
      if (ch.length > 1) {
        ch.removeLast();
      } else {
        ch[0] = <Object?>['0' * 64, (ch[0] as List)[1]];
      }
      h['chunks'] = ch;
      final Uint8List edited = Uint8List.fromList(utf8.encode(canonicalJson(h)));
      await expectLater(openManifest(edited, a.set.manifest, family), throwsA(isA<BackupFormatException>()));
      // Manifest bit flipped.
      final Uint8List flipped = Uint8List.fromList(a.set.manifest)..[20] ^= 1;
      await expectLater(openManifest(a.set.header, flipped, family), throwsA(isA<BackupFormatException>()));
      // Manifest of another set under this header.
      await expectLater(openManifest(a.set.header, b.set.manifest, family), throwsA(isA<BackupFormatException>()));
      // Not a header at all.
      await expectLater(openManifest(Uint8List.fromList(utf8.encode('{}')), a.set.manifest, family),
          throwsA(isA<BackupFormatException>()));
      await expectLater(openManifest(Uint8List.fromList(<int>[1, 2, 3]), a.set.manifest, family),
          throwsA(isA<BackupFormatException>()));
    });

    test('a missing, damaged, swapped or foreign chunk is refused whole', () async {
      final _Sealed a = await _seal(Phone(), BackupKind.family, family.publicKey, seq: 1);
      final _Sealed b = await _seal(Phone(childId: 'zed'), BackupKind.family, family.publicKey, seq: 2);
      final OpenedManifest m = await openManifest(a.set.header, a.set.manifest, family);
      final String first = a.set.chunkIds.first;
      // missing
      await expectLater(readAreas(m, (String id) async => id == first ? null : a.chunks[id]),
          throwsA(isA<BackupFormatException>().having((BackupFormatException e) => e.code, 'code', 'chunk')));
      // flipped bit
      await expectLater(
          readAreas(m, (String id) async => id == first ? (Uint8List.fromList(a.chunks[id]!)..[30] ^= 1) : a.chunks[id]),
          throwsA(isA<BackupFormatException>().having((BackupFormatException e) => e.code, 'code', 'chunk')));
      // a chunk from a different backup served under this chunk's name
      await expectLater(readAreas(m, (String id) async => id == first ? b.chunks.values.first : a.chunks[id]),
          throwsA(isA<BackupFormatException>()));
      // truncated
      await expectLater(
          readAreas(m, (String id) async => id == first ? Uint8List.sublistView(a.chunks[id]!, 0, 40) : a.chunks[id]),
          throwsA(isA<BackupFormatException>()));
    });

    test('chunks cannot be reordered inside a set: the position is part of what is sealed', () async {
      final _Sealed a = await _seal(Phone(), BackupKind.hersKeep, family.publicKey, big: 9000);
      expect(a.set.chunkIds.length, greaterThan(1));
      final OpenedManifest m = await openManifest(a.set.header, a.set.manifest, family);
      final String c0 = a.set.chunkIds[0], c1 = a.set.chunkIds[1];
      // serve chunk 1's bytes where chunk 0 is asked for, under chunk 0's name: the name check catches it...
      await expectLater(readAreas(m, (String id) async => id == c0 ? a.chunks[c1] : a.chunks[id]), throwsA(isA<BackupFormatException>()));
      // ...and a forged header that swaps the two names (with their sizes) fails the manifest check instead.
      final Map<String, Object?> h = jsonDecode(utf8.decode(a.set.header)) as Map<String, Object?>;
      final List<Object?> ch = List<Object?>.of(h['chunks'] as List);
      final Object? t = ch[0];
      ch[0] = ch[1];
      ch[1] = t;
      h['chunks'] = ch;
      await expectLater(
          openManifest(Uint8List.fromList(utf8.encode(canonicalJson(h))), a.set.manifest, family), throwsA(isA<BackupFormatException>()));
    });

    test('a kind cannot be passed off as another: the kind is part of the key and of every seal', () async {
      final _Sealed priv = await _seal(Phone(), BackupKind.hersPrivate, family.publicKey);
      final Map<String, Object?> h = jsonDecode(utf8.decode(priv.set.header)) as Map<String, Object?>;
      h['kind'] = 'family';
      await expectLater(
          openManifest(Uint8List.fromList(utf8.encode(canonicalJson(h))), priv.set.manifest, family), throwsA(isA<BackupFormatException>()));
    });
  });
}
