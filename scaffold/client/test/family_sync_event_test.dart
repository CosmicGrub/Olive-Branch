// OLIVE BRANCH — family sync, the event: seal, sign, open, and every way a hostile event is refused. Verified by CI,
// headless.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart' show cat, lv;
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_sync_event.dart';
import 'package:olive_client/local_services.dart';

import 'family_sync_test_support.dart';
import 'family_test_support.dart';

const Map<String, SyncKind> _other = <String, SyncKind>{'zz.other': SyncKind('zz.other', 'emergencycard', 1)};

/// Builds a wire event by hand, the way an attacker who holds the guardian key (but not the other phone's signing
/// key) would. [plainOf] may change the plain bytes before sealing.
Future<Uint8List> forge({
  required P signer,
  required P claimed,
  required FamilyKeyring ring,
  required Uint8List fid,
  required Uint8List sid,
  Map<String, Object?>? inner,
  Uint8List Function(Uint8List framed, int bucket)? plainOf,
  int? bucketIn,
  int epoch = 0,
}) async {
  final Uint8List innerBytes = encodeValue(inner ??
      <String, Object?>{
        'fid': fid, 'sid': sid, 'dev': claimed.key.publicKey, 'seq': 1, 'hlc': 1800000000000, 'hc': 0,
        'prev': <Object?>[], 'kind': 'emergency.set', 'schema': 1, 'payload': <String, Object?>{'x': 'y'},
      });
  final Uint8List sig = await signer.key.sign(cat(<List<int>>[lv(utf8.encode(kSyncSigDomain)), innerBytes]));
  final Uint8List framed = cat(<List<int>>[lv(innerBytes), lv(sig)]);
  final int bucket = bucketIn ?? kSyncBuckets.firstWhere((int b) => b >= framed.length);
  final Uint8List plain = plainOf != null ? plainOf(framed, bucket) : (Uint8List(bucket)..setRange(0, framed.length, framed));
  final Uint8List outer = cat(<List<int>>[
    lv(utf8.encode(kSyncOuterLabel)),
    Uint8List.fromList(<int>[0, 0, 0, epoch]),
    Uint8List.fromList(<int>[(bucket >> 24) & 255, (bucket >> 16) & 255, (bucket >> 8) & 255, bucket & 255]),
  ]);
  return cat(<List<int>>[outer, await guardianSeal(ring, epoch, plain, aad: outer)]);
}

bool containsBytes(List<int> hay, List<int> needle) {
  for (int i = 0; i + needle.length <= hay.length; i++) {
    int j = 0;
    while (j < needle.length && hay[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}

void main() {
  late SyncRig rig;
  late FamilyKeyring ring;
  late Uint8List sid;

  setUp(() async {
    rig = await SyncRig.make();
    ring = guardianRing();
    sid = await syncStreamId(rig.fid, 'emergencycard', 'ivy');
  });

  Future<SyncEvent> make({
    P? by,
    int seq = 1,
    int ms = 1800000000000,
    List<List<int>> prev = const <List<int>>[],
    Map<String, Object?>? payload,
    int epoch = 0,
  }) =>
      SyncEvent.create(
        device: (by ?? rig.mom).key, ring: ring, epoch: epoch, fid: rig.fid, streamId: sid, seq: seq, hlcMs: ms,
        hlcC: 0, prev: prev, kind: 'emergency.set', payload: payload ?? <String, Object?>{'note': 'peanut'},
      );

  group('the closed table and the stream id', () {
    test('no sync kind belongs to a never-leaves-the-device area, and every kind\'s area is catalogued', () {
      final Set<String> catalogued = <String>{for (final LocalDataEntry e in localDataCatalogue) e.area};
      expect(kSyncKinds, isNotEmpty);
      for (final SyncKind k in kSyncKinds.values) {
        expect(kSyncNeverAreas, isNot(contains(k.area)), reason: k.name);
        expect(catalogued, contains(k.area), reason: k.name);
        expect(kSyncKinds[k.name], same(k));
      }
    });

    test('the never-leaves list and the sync table never overlap', () {
      final Set<String> catalogued = <String>{for (final LocalDataEntry e in localDataCatalogue) e.area};
      for (final String a in kSyncNeverAreas.where(catalogued.contains)) {
        expect(kSyncKinds.values.where((SyncKind k) => k.area == a), isEmpty, reason: a);
      }
    });

    test('the stream id is derived: the same inputs agree on every phone, and any change of family, area or child changes it', () async {
      final Uint8List a = await syncStreamId(rig.fid, 'emergencycard', 'ivy');
      expect(a, await syncStreamId(rig.fid, 'emergencycard', 'ivy'));
      expect(a.length, 16);
      expect(hexOf(await syncStreamId(rig.fid, 'emergencycard', 'zoe')), isNot(hexOf(a)));
      expect(hexOf(await syncStreamId(rig.fid, 'careguide', 'ivy')), isNot(hexOf(a)));
      expect(hexOf(await syncStreamId(Uint8List(16), 'emergencycard', 'ivy')), isNot(hexOf(a)));
    });
  });

  group('seal and open', () {
    test('an event round-trips with every field, and its id does not depend on the epoch it is sealed under', () async {
      final SyncEvent e = await make(payload: <String, Object?>{'a': 'b', 'n': 3, 'l': <Object?>['x', null, true]});
      final SyncOpenResult o = await SyncEvent.open(e.wire, ring: ring, fid: rig.fid);
      expect(o.reason, isNull);
      final SyncEvent r = o.event!;
      expect(r.idHex, e.idHex);
      expect(r.seq, 1);
      expect(r.kind, 'emergency.set');
      expect(r.authorHex, hexOf(rig.mom.key.publicKey));
      expect(r.payload, <String, Object?>{'a': 'b', 'n': 3, 'l': <Object?>['x', null, true]});
      // The same content sealed under a second epoch has the same id (prev links survive a key rotation).
      final FamilyKeyring two = guardianRing()..putGk(1, Uint8List.fromList(List<int>.filled(32, 5)));
      final SyncEvent again = await SyncEvent.create(
        device: rig.mom.key, ring: two, epoch: 1, fid: rig.fid, streamId: sid, seq: 1, hlcMs: 1800000000000, hlcC: 0,
        prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'a': 'b', 'n': 3, 'l': <Object?>['x', null, true]},
      );
      expect(again.idHex, e.idHex);
      expect(again.epoch, 1);
      expect(hexOf(again.wire), isNot(hexOf(e.wire)));
    });

    test('outside the encryption there is only a label, an epoch and a size: nothing names the family, the writer, the stream, the kind or the words', () async {
      final SyncEvent e = await make(payload: <String, Object?>{'note': 'peanutbutter'});
      for (final List<int> secret in <List<int>>[
        rig.fid, rig.mom.key.publicKey, sid, utf8.encode('emergency.set'), utf8.encode('peanutbutter'), utf8.encode('emergencycard'),
      ]) {
        expect(containsBytes(e.wire, secret), isFalse);
      }
      expect(containsBytes(e.wire, utf8.encode(kSyncOuterLabel)), isTrue);
    });

    test('events are padded to a fixed size so two small edits look alike', () async {
      final SyncEvent small = await make(payload: <String, Object?>{'n': 'a'});
      final SyncEvent small2 = await make(payload: <String, Object?>{'n': 'abcdefgh'});
      final SyncEvent medium = await make(payload: <String, Object?>{'n': 'a' * 600});
      final SyncEvent big = await make(payload: <String, Object?>{'n': 'a' * 3000});
      final int head = lv(utf8.encode(kSyncOuterLabel)).length + 8 + 12 + 16;
      expect(small.wire.length - head, 256);
      expect(small2.wire.length, small.wire.length, reason: 'two small edits are the same size');
      expect(medium.wire.length - head, 1024);
      expect(big.wire.length - head, 4096);
    });

    test('a flipped bit anywhere (header, epoch, size, nonce, ciphertext, tag) is refused', () async {
      final SyncEvent e = await make();
      final List<int> spots = <int>[for (int i = 0; i < e.wire.length; i += 11) i, e.wire.length - 1, 0, 1, 16, 17, 18, 19, 20, 21, 22];
      for (final int i in spots) {
        final Uint8List bad = Uint8List.fromList(e.wire)..[i] ^= 1;
        final SyncOpenResult o = await SyncEvent.open(bad, ring: ring, fid: rig.fid);
        expect(o.event, isNull, reason: 'byte $i');
      }
    });

    test('truncated, extended, empty and random bytes are refused without throwing', () async {
      final SyncEvent e = await make();
      for (final List<int> bad in <List<int>>[
        <int>[], <int>[1, 2, 3], e.wire.sublist(0, e.wire.length - 1), <int>[...e.wire, 0], e.wire.sublist(1),
        List<int>.generate(400, (int i) => (i * 37) & 255),
      ]) {
        expect((await SyncEvent.open(bad, ring: ring, fid: rig.fid)).event, isNull);
      }
    });

    test('another family\'s guardian key, a missing epoch and a child device\'s keyring all fail to open it', () async {
      final SyncEvent e = await make();
      expect((await SyncEvent.open(e.wire, ring: guardianRing(gk: Uint8List(32)), fid: rig.fid)).reason, 'seal');
      expect((await SyncEvent.open(e.wire, ring: guardianRing(epoch: 3), fid: rig.fid)).reason, 'no_key');
      expect((await SyncEvent.open(e.wire, ring: childRing(), fid: rig.fid)).reason, 'no_key');
    });

    test('the same key but another family id is refused as another family', () async {
      final SyncEvent e = await make();
      expect((await SyncEvent.open(e.wire, ring: ring, fid: Uint8List(16))).reason, 'family');
    });

    test('the epoch in the header is bound: re-labelling an event with another epoch does not open it', () async {
      final FamilyKeyring two = guardianRing()..putGk(1, kTestGk); // the same key under two epoch numbers
      final SyncEvent e = await make();
      final Uint8List relabelled = Uint8List.fromList(e.wire);
      final int epochAt = lv(utf8.encode(kSyncOuterLabel)).length + 3;
      relabelled[epochAt] = 1;
      expect((await SyncEvent.open(relabelled, ring: two, fid: rig.fid)).reason, 'seal', reason: 'associated data differs');
    });
  });

  group('who wrote it, and what the inside must look like', () {
    test('another grown-up cannot write as someone else: a claimed writer with the wrong signature is refused', () async {
      final Uint8List w = await forge(signer: rig.dad, claimed: rig.mom, ring: ring, fid: rig.fid, sid: sid);
      expect((await SyncEvent.open(w, ring: ring, fid: rig.fid)).reason, 'signature');
    });

    test('a forged event with the right writer opens (so the test above is meaningful)', () async {
      final Uint8List w = await forge(signer: rig.mom, claimed: rig.mom, ring: ring, fid: rig.fid, sid: sid);
      expect((await SyncEvent.open(w, ring: ring, fid: rig.fid)).event, isNotNull);
    });

    test('the signature is for events only: it does not verify under the ledger\'s or the pairing certificate\'s domain', () async {
      final SyncEvent e = await make();
      Future<bool> under(String domain) => DeviceKey.verify(e.author, cat(<List<int>>[lv(utf8.encode(domain)), e.inner]), e.signature);
      expect(await under(kSyncSigDomain), isTrue);
      expect(await under(kLedgerDomain), isFalse);
      expect(await under(kVoteDomain), isFalse);
      expect(await under('olive-cert-v1'), isFalse);
    });

    test('padding that is not all zeros, an unknown kind, a wrong schema and a non-canonical inner are refused', () async {
      Future<String?> reason(Map<String, Object?>? inner, {Uint8List Function(Uint8List, int)? plainOf}) async => (await SyncEvent.open(
              await forge(signer: rig.mom, claimed: rig.mom, ring: ring, fid: rig.fid, sid: sid, inner: inner, plainOf: plainOf),
              ring: ring, fid: rig.fid))
          .reason;
      Map<String, Object?> base() => <String, Object?>{
            'fid': rig.fid, 'sid': sid, 'dev': rig.mom.key.publicKey, 'seq': 1, 'hlc': 1800000000000, 'hc': 0,
            'prev': <Object?>[], 'kind': 'emergency.set', 'schema': 1, 'payload': <String, Object?>{'x': 'y'},
          };
      expect(await reason(null, plainOf: (Uint8List f, int b) => Uint8List(b)..setRange(0, f.length, f)..[b - 1] = 1), 'inner');
      expect(await reason(base()..['kind'] = 'journal.add'), 'kind');
      expect(await reason(base()..['schema'] = 2), 'kind');
      expect(await reason(base()..['extra'] = 1), 'inner');
      expect(await reason(base()..['seq'] = 0), 'inner');
      expect(await reason(base()..['sid'] = Uint8List(5)), 'inner');
      expect(await reason(base()..['prev'] = <Object?>[Uint8List(31)]), 'inner');
      expect(await reason(base()..['prev'] = <Object?>[Uint8List(32)..[0] = 9, Uint8List(32)..[0] = 8]), 'inner', reason: 'links must ascend');
      expect(await reason(base()..['prev'] = <Object?>[for (int i = 0; i < 9; i++) Uint8List(32)..[0] = i + 1]), 'inner');
      expect(await reason(base()..['payload'] = 'text'), 'inner');
    });
  });

  group('building one', () {
    test('create refuses a kind outside the table, a payload that is too large, unsorted or oversized links and bad counters', () async {
      Future<void> go({String kind = 'emergency.set', Map<String, Object?>? payload, List<List<int>> prev = const <List<int>>[], int seq = 1}) =>
          SyncEvent.create(
            device: rig.mom.key, ring: ring, epoch: 0, fid: rig.fid, streamId: sid, seq: seq, hlcMs: 1, hlcC: 0, prev: prev,
            kind: kind, payload: payload ?? <String, Object?>{},
          );
      await expectLater(go(kind: 'journal.add'), throwsArgumentError);
      await expectLater(go(payload: <String, Object?>{'a': 'x' * (kSyncMaxPayloadBytes + 1)}), throwsArgumentError);
      await expectLater(go(prev: <List<int>>[Uint8List(32)..[0] = 2, Uint8List(32)..[0] = 1]), throwsArgumentError);
      await expectLater(go(prev: <List<int>>[Uint8List(32)..[0] = 1, Uint8List(32)..[0] = 1]), throwsArgumentError);
      await expectLater(go(prev: <List<int>>[Uint8List(5)]), throwsArgumentError);
      await expectLater(go(prev: <List<int>>[for (int i = 0; i < 9; i++) Uint8List(32)..[0] = i + 1]), throwsArgumentError);
      await expectLater(go(seq: 0), throwsArgumentError);
      await go(); // and the plain case works
    });

    test('a child device\'s keyring cannot seal an event at all', () async {
      await expectLater(
        SyncEvent.create(
          device: rig.kid.key, ring: childRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: 1, hlcC: 0,
          prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{},
        ),
        throwsStateError,
      );
    });

    test('the largest allowed payload still seals and opens', () async {
      final SyncEvent e = await make(payload: <String, Object?>{'n': 'a' * (kSyncMaxPayloadBytes - 64)});
      expect((await SyncEvent.open(e.wire, ring: ring, fid: rig.fid)).event, isNotNull);
    });

    test('an event with a different kind table is refused by one with the default table', () async {
      final SyncEvent e = await SyncEvent.create(
        device: rig.mom.key, ring: ring, epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: 1, hlcC: 0,
        prev: const <List<int>>[], kind: 'zz.other', payload: <String, Object?>{}, kinds: _other,
      );
      expect((await SyncEvent.open(e.wire, ring: ring, fid: rig.fid)).reason, 'kind');
      expect((await SyncEvent.open(e.wire, ring: ring, fid: rig.fid, kinds: _other)).event, isNotNull);
    });
  });
}
