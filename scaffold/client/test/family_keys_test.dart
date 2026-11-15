// OLIVE BRANCH — the family key (FK) and the guardian-only key (GK): kept apart, delivered to one device at a time, and
// never to a child device (GK). Verified by CI, headless.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';

import 'family_test_support.dart';

void main() {
  late P mom, dad, kid, stranger;
  final Uint8List fid = Uint8List.fromList(List<int>.filled(16, 9));
  final Uint8List key32 = Uint8List.fromList(List<int>.generate(32, (int i) => i));

  setUp(() async {
    mom = await P.make(1);
    dad = await P.make(2);
    kid = await P.make(3);
    stranger = await P.make(5);
  });

  group('a wrap reaches one device and nobody else', () {
    test('the addressed device opens it', () async {
      final Uint8List w = await wrapKey(fid: fid, epoch: 2, kind: 'fk', recipient: kid.rec, key: key32, random: Random(1));
      expect(w.length, 80);
      expect(await unwrapKey(fid: fid, epoch: 2, kind: 'fk', ownDeviceKey: kid.key.publicKey, agreement: kid.agree, wrapped: w), key32);
    });

    test('another device, another family, another epoch, another kind, or a flipped bit: nothing opens', () async {
      final Uint8List w = await wrapKey(fid: fid, epoch: 2, kind: 'fk', recipient: kid.rec, key: key32, random: Random(2));
      Future<Uint8List?> open({Uint8List? f, int epoch = 2, String kind = 'fk', P? who, Uint8List? wrapped}) =>
          unwrapKey(fid: f ?? fid, epoch: epoch, kind: kind, ownDeviceKey: (who ?? kid).key.publicKey, agreement: (who ?? kid).agree, wrapped: wrapped ?? w);
      expect(await open(who: stranger), isNull);
      expect(await open(f: Uint8List(16)), isNull);
      expect(await open(epoch: 3), isNull);
      expect(await open(kind: 'gk'), isNull);
      for (int i = 0; i < w.length; i += 7) {
        expect(await open(wrapped: Uint8List.fromList(w)..[i] ^= 1), isNull, reason: 'byte $i');
      }
      expect(await open(wrapped: w.sublist(1)), isNull);
    });

    test('a wrap needs an agreement key: a device without one cannot be wrapped to', () async {
      expect(() => wrapKey(fid: fid, epoch: 0, kind: 'fk', recipient: DeviceRecord(key: kid.key.publicKey), key: key32), throwsArgumentError);
    });

    test('an agreement key is certified by its device: a substituted key does not verify', () async {
      expect(await verifyAgreementCert(kid.rec), isTrue);
      final DeviceRecord swapped = DeviceRecord(key: kid.key.publicKey, agree: stranger.agree.publicKey, cert: kid.cert);
      expect(await verifyAgreementCert(swapped), isFalse, reason: 'a signer cannot put their own agreement key into somebody else\'s device');
    });
  });

  group('FK and GK are different keys with different jobs', () {
    test('subkeys for different purposes are all different, and a purpose changes with the key', () async {
      final FamilyKeyring ring = FamilyKeyring(guardianDevice: true)..putFk(0, key32)..putGk(0, Uint8List.fromList(key32.reversed.toList()));
      final List<Uint8List> ks = <Uint8List>[
        await ring.familySubkey(0, kFkBind), await ring.familySubkey(0, kFkMember), await ring.familySubkey(0, kFkDiscovery),
        await ring.guardianSealKey(0),
      ];
      expect(ks.map(hexOf).toSet().length, 4);
      expect(hexOf(await ring.familySubkey(0, kFkBind, salt: <int>[1])), isNot(hexOf(ks[0])));
    });

    test('a child device\'s keyring cannot hold a guardian key, cannot make the seal key, and cannot open guardian-sealed data', () async {
      final FamilyKeyring grown = FamilyKeyring(guardianDevice: true)..putFk(0, key32)..putGk(0, Uint8List.fromList(key32.reversed.toList()));
      final FamilyKeyring child = FamilyKeyring(guardianDevice: false)..putFk(0, key32);
      expect(() => child.putGk(0, key32), throwsStateError);
      expect(() => child.guardianSealKey(0), throwsStateError);
      final Uint8List sealed = await guardianSeal(grown, 0, <int>[1, 2, 3, 4], aad: <int>[9], random: Random(3));
      expect(await guardianOpen(grown, 0, sealed, aad: <int>[9]), <int>[1, 2, 3, 4]);
      expect(await guardianOpen(grown, 0, sealed, aad: <int>[8]), isNull);
      expect(await guardianOpen(child, 0, sealed), isNull, reason: 'a child device has no way to even build the key');
      // And nothing the child device CAN derive from FK opens it either.
      for (final String purpose in <String>[kFkBind, kFkMember, kFkDiscovery, kGkSeal]) {
        final Uint8List k = await child.familySubkey(0, purpose);
        final FamilyKeyring fake = FamilyKeyring(guardianDevice: true)..putGk(0, k);
        expect(await guardianOpen(fake, 0, sealed, aad: <int>[9]), isNull, reason: purpose);
      }
      expect(child.gkEpochs, isEmpty);
    });

    test('a commitment checks a key without giving it away, and is bound to family, epoch and kind', () async {
      final Uint8List c = await keyCommit('fk', fid, 0, key32);
      expect(c.length, 32);
      expect(hexOf(await keyCommit('gk', fid, 0, key32)), isNot(hexOf(c)));
      expect(hexOf(await keyCommit('fk', fid, 1, key32)), isNot(hexOf(c)));
      expect(hexOf(await keyCommit('fk', Uint8List(16), 0, key32)), isNot(hexOf(c)));
    });
  });

  group('rotation: a new epoch is fresh and reaches exactly the right devices', () {
    Future<(Fam, LedgerState)> family() async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      await f.addChild(mom, kid);
      f.clock += 4 * day;
      return (f, await f.state());
    }

    test('every device with an agreement key gets an FK wrap; only grown-ups\' devices get a GK wrap; the plan passes the ledger\'s own rule', () async {
      final (Fam f, LedgerState s) = await family();
      final RotationPlan plan = await planKeyRotation(s, random: Random(4));
      expect(plan.epoch, 1);
      final List<Object?> wraps = plan.body['wraps']! as List<Object?>;
      expect(wraps.length, 3);
      for (final Object? w in wraps) {
        final Map<String, Object?> m = w! as Map<String, Object?>;
        final bool isChild = hexOf(m['to']! as Uint8List) == kid.keyHex;
        expect(m['gk'] == null, isChild);
      }
      final LedgerEntry e = await f.add(mom, EntryType.keyRotate, plan.body);
      final LedgerState after = await f.state();
      expect(after.rejected.containsKey(e.hashHex), isFalse);
      expect(after.epoch, 1);
    });

    test('each device opens its own wraps; a child device ends up with FK and no GK; a stranger gets nothing', () async {
      final (Fam f, LedgerState s) = await family();
      final RotationPlan plan = await planKeyRotation(s, random: Random(5));
      Future<FamilyKeyring> open(P who, bool grown) async {
        final FamilyKeyring ring = FamilyKeyring(guardianDevice: grown);
        await openKeyRotation(fid: s.fid!, body: plan.body, device: who.key, agreement: who.agree, ring: ring);
        return ring;
      }

      final FamilyKeyring m = await open(mom, true), d = await open(dad, true), c = await open(kid, false);
      expect(m.fk(1), plan.fk);
      expect(m.gk(1), plan.gk);
      expect(d.gk(1), plan.gk);
      expect(c.fk(1), plan.fk);
      expect(c.gk(1), isNull);
      final FamilyKeyring none = FamilyKeyring(guardianDevice: true);
      expect(await openKeyRotation(fid: s.fid!, body: plan.body, device: stranger.key, agreement: stranger.agree, ring: none), isFalse);
      expect(none.fkEpochs, isEmpty);
      expect(f.entries, isNotEmpty);
    });

    test('a child device that is somehow handed a GK wrap does not take it (its keyring refuses)', () async {
      final (_, LedgerState s) = await family();
      final RotationPlan plan = await planKeyRotation(s, random: Random(6));
      // Re-address the guardian wrap of Mom to the child's key: the child device cannot open it (wrong recipient), and
      // a keyring that is not a grown-up's would not store it anyway.
      final List<Object?> wraps = plan.body['wraps']! as List<Object?>;
      final Map<String, Object?> momWrap = wraps.cast<Map<String, Object?>>().firstWhere((Map<String, Object?> w) => hexOf(w['to']! as Uint8List) == mom.keyHex);
      final Map<String, Object?> forged = <String, Object?>{...plan.body, 'wraps': <Object?>[<String, Object?>{...momWrap, 'to': kid.key.publicKey}]};
      final FamilyKeyring ring = FamilyKeyring(guardianDevice: false);
      expect(await openKeyRotation(fid: s.fid!, body: forged, device: kid.key, agreement: kid.agree, ring: ring), isFalse);
      expect(ring.gkEpochs, isEmpty);
    });

    test('a removed grown-up, a revoked tablet and a pending person are not wrapped to; the new key is fresh, not a ratchet', () async {
      final (Fam f, _) = await family();
      await f.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      await f.add(mom, EntryType.deviceRevoke, f.revokeBody(kid, reason: 'forgotten'));
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom], name: 'Eve'));
      expect(p.hashHex, isNotEmpty);
      final LedgerState s = await f.state();
      final RotationPlan one = await planKeyRotation(s, random: Random(7));
      final RotationPlan two = await planKeyRotation(s, random: Random(8));
      final Set<String> to = <String>{for (final Object? w in one.body['wraps']! as List<Object?>) hexOf((w! as Map<String, Object?>)['to']! as Uint8List)};
      expect(to, <String>{mom.keyHex});
      expect(hexOf(one.fk), isNot(hexOf(two.fk)));
      // Dad (who left) cannot open any of it.
      final FamilyKeyring dring = FamilyKeyring(guardianDevice: true);
      expect(await openKeyRotation(fid: s.fid!, body: one.body, device: dad.key, agreement: dad.agree, ring: dring), isFalse);
    });

    test('a wrap whose key does not match the published commitment is refused', () async {
      final (_, LedgerState s) = await family();
      final RotationPlan plan = await planKeyRotation(s, random: Random(9));
      final Map<String, Object?> lie = <String, Object?>{...plan.body, 'fkc': Uint8List(32)};
      final FamilyKeyring ring = FamilyKeyring(guardianDevice: true);
      expect(await openKeyRotation(fid: s.fid!, body: lie, device: mom.key, agreement: mom.agree, ring: ring), isFalse);
      expect(ring.fkEpochs, isEmpty);
    });

    test('a legacy tablet with no agreement key yet is left out until it upgrades', () async {
      final Fam f = await Fam.found(mom, legacyFids: <String>['local-x']);
      await f.add(mom, EntryType.deviceAdd, f.childBody(kid, legacy: true, bare: true));
      final RotationPlan plan = await planKeyRotation(await f.state(), random: Random(10));
      expect((plan.body['wraps']! as List<Object?>).length, 1);
    });
  });
}
