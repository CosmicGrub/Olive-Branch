// OLIVE BRANCH — founding a family, keeping it on the device, and carrying an existing 'local-<fingerprint>' family
// into a ledger without changing any pairing behaviour. Verified by CI, headless.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/local_pin.dart' show kLocalGuardianScope;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart' show LocalNamespace;
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';

import 'family_test_support.dart';

void main() {
  late DeviceKey adult;
  late DeviceKey tabA, tabB, other;

  setUp(() async {
    adult = (await P.make(1)).key;
    tabA = (await P.make(21)).key;
    tabB = (await P.make(22)).key;
    other = (await P.make(30)).key;
  });

  Future<List<PairedKid>> v1World() async => <PairedKid>[
        PairedKid(certId: 'c2', childDeviceKey: tabB.publicKey, childId: 'ivy', deviceName: 'Hall tablet', issuedAtMs: 1700000002000),
        PairedKid(certId: 'c1', childDeviceKey: tabA.publicKey, childId: 'ivy', deviceName: 'Ivy tablet', issuedAtMs: 1700000001000),
      ];

  Future<PairingCert> v1Cert(DeviceKey signer, DeviceKey child, {String? fid, String childId = 'ivy', String id = 'c1'}) =>
      PairingCert.issue(signer,
          childDeviceKey: child.publicKey, familyId: fid ?? legacyFamilyId(adult), childId: childId, certId: id, issuedAtMs: 1700000001000);

  group('founding a family', () {
    test('a founded family has a random 128-bit id, a signed genesis, epoch-0 keys, and one grown-up device', () async {
      final MemoryFamilyRepository repo = MemoryFamilyRepository();
      final FamilyContext c = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: repo, random: Random(1));
      final LedgerState s = await c.state(nowMs: t0 + hour);
      expect(s.ok, isTrue);
      expect(s.fid!.length, 16);
      expect(c.familyId, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
      expect(s.guardians.single.name, 'Mom');
      expect(s.devices.single.agree, isNotNull);
      expect(c.keyring.guardianDevice, isTrue);
      expect(c.keyring.fk(0), isNotNull);
      expect(c.keyring.gk(0), isNotNull);
      expect(hexOf(c.keyring.fk(0)!), isNot(hexOf(c.keyring.gk(0)!)));
      expect(c.pin.matches(s.pin!), isTrue);
      expect(await repo.load(), isNotNull);
    });

    test('the published commitments match the keys the founder holds', () async {
      final FamilyContext c = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: MemoryFamilyRepository(), random: Random(2));
      final LedgerEntry g = c.entries.first;
      expect(await keyCommit('fk', c.pin.fid, 0, c.keyring.fk(0)!), g.body['fkc']);
      expect(await keyCommit('gk', c.pin.fid, 0, c.keyring.gk(0)!), g.body['gkc']);
    });

    test('two families founded on two devices have different ids; the same seeded Random gives the same family', () async {
      final FamilyContext a = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: MemoryFamilyRepository(), random: Random(3));
      final FamilyContext b = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: MemoryFamilyRepository(), random: Random(4));
      final FamilyContext a2 = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: MemoryFamilyRepository(), random: Random(3));
      expect(a.familyId, isNot(b.familyId));
      expect(a.familyId, a2.familyId);
      expect(hexOf(a.pin.genesisHash), hexOf(a2.pin.genesisHash));
    });

    test('a name with control characters or no characters is cleaned; the ledger still accepts it', () async {
      final FamilyContext c = await FamilyFounder.found(device: adult, guardianName: '\n\t ', nowMs: t0, repo: MemoryFamilyRepository(), random: Random(5));
      expect((await c.state(nowMs: t0)).guardians.single.name, 'Grown-up');
    });

    test('ensure() founds once and then returns the same family every time', () async {
      final MemoryFamilyRepository repo = MemoryFamilyRepository();
      final FamilyContext a = await FamilyFounder.ensure(device: adult, guardianName: 'Mom', kids: const <PairedKid>[], nowMs: t0, repo: repo, random: Random(6));
      final FamilyContext b = await FamilyFounder.ensure(device: adult, guardianName: 'Mom', kids: await v1World(), nowMs: t0 + day, repo: repo, random: Random(7));
      expect(b.familyId, a.familyId);
      expect(b.entries.length, a.entries.length, reason: 'a family is not re-founded');
    });
  });

  group('migrating a local-<fingerprint> family', () {
    test('the id the migration records is exactly what the live pairing code computes today', () async {
      // connect_child_screen.dart: 'local-${b64(key.fingerprint)}'
      expect(legacyFamilyId(adult), 'local-${b64(adult.fingerprint)}');
      final String src = File('lib/connect_child_screen.dart').readAsStringSync();
      expect(src, contains(r"'local-${b64(key.fingerprint)}'"), reason: 'if the live formula changes, the migration must follow it');
    });

    test('every paired tablet becomes a legacy device with its original issue time, and the genesis records the old id', () async {
      final FoundingResult r = await FamilyFounder.foundFromLegacy(
          adult: adult, adultName: 'Mom', kids: await v1World(), nowMs: t0, repo: MemoryFamilyRepository(), random: Random(8));
      expect(r.skippedCertIds, isEmpty);
      final LedgerState s = await r.context.state(nowMs: t0 + hour);
      expect(s.legacyFids, <String>[legacyFamilyId(adult)]);
      expect(s.childDeviceKeys.length, 2);
      final LedgerDevice a = s.deviceFor(tabA.publicKey)!;
      expect(a.legacy, isTrue);
      expect(a.childId, 'ivy');
      expect(a.agree, isNull, reason: 'a v1 tablet has no agreement key until it upgrades');
      expect(a.name, 'Ivy tablet');
      final LedgerEntry add = r.context.entries.firstWhere((LedgerEntry e) => e.type == EntryType.deviceAdd && (e.body['name'] == 'Ivy tablet'));
      expect(add.body['orig'], 1700000001000);
    });

    test('founding is deterministic given the randomness, whatever order the paired list arrives in', () async {
      final List<PairedKid> kids = await v1World();
      final FoundingResult a = await FamilyFounder.foundFromLegacy(adult: adult, adultName: 'Mom', kids: kids, nowMs: t0, repo: MemoryFamilyRepository(), random: Random(9));
      final FoundingResult b = await FamilyFounder.foundFromLegacy(
          adult: adult, adultName: 'Mom', kids: kids.reversed.toList(), nowMs: t0, repo: MemoryFamilyRepository(), random: Random(9));
      expect(<String>[for (final LedgerEntry e in a.context.entries) e.hashHex], <String>[for (final LedgerEntry e in b.context.entries) e.hashHex]);
    });

    test('every v1 certificate the phone issued is still accepted; a tampered family id, another grown-up\'s signature, or an unknown tablet is not', () async {
      final FoundingResult r = await FamilyFounder.foundFromLegacy(
          adult: adult, adultName: 'Mom', kids: await v1World(), nowMs: t0, repo: MemoryFamilyRepository(), random: Random(10));
      final LedgerState s = await r.context.state(nowMs: t0 + hour);
      expect(await acceptsLegacyCert(s, await v1Cert(adult, tabA)), isTrue);
      expect(await acceptsLegacyCert(s, await v1Cert(adult, tabB, id: 'c2')), isTrue);
      expect(await acceptsLegacyCert(s, await v1Cert(adult, tabA, fid: 'local-somebody-else')), isFalse, reason: 'tampered family id');
      expect(await acceptsLegacyCert(s, await v1Cert(other, tabA)), isFalse, reason: 'signed by a key that is not a grown-up of this family');
      expect(await acceptsLegacyCert(s, await v1Cert(adult, other)), isFalse, reason: 'a tablet the ledger does not list');
      expect(await acceptsLegacyCert(s, await v1Cert(adult, tabA, childId: 'someone')), isFalse, reason: 'another child');
      // A certificate edited after signing does not verify.
      final PairingCert good = await v1Cert(adult, tabA);
      final PairingCert edited = PairingCert(
          childDeviceKey: good.childDeviceKey, familyId: good.familyId, childId: good.childId, adultFingerprint: good.adultFingerprint,
          issuedAtMs: good.issuedAtMs + 1, certId: good.certId, signature: good.signature);
      expect(await acceptsLegacyCert(s, edited), isFalse);
    });

    test('a revoked tablet\'s old certificate stops being accepted', () async {
      final FoundingResult r = await FamilyFounder.foundFromLegacy(
          adult: adult, adultName: 'Mom', kids: await v1World(), nowMs: t0, repo: MemoryFamilyRepository(), random: Random(11));
      final List<LedgerEntry> es = List<LedgerEntry>.of(r.context.entries);
      es.add(await LedgerEntry.sign(adult,
          type: EntryType.deviceRevoke,
          prev: <List<int>>[es.last.hash],
          issuedAtMs: t0 + 60000,
          body: <String, Object?>{'key': tabA.publicKey, 'reason': 'forgotten', 'eff': t0 + 60000}));
      final LedgerState s = await reduceLedger(entries: es, nowMs: t0 + hour, pin: r.context.pin);
      expect(await acceptsLegacyCert(s, await v1Cert(adult, tabA)), isFalse);
      expect(await acceptsLegacyCert(s, await v1Cert(adult, tabB, id: 'c2')), isTrue);
    });

    test('migration reads the paired-kids list and never writes it: current pairing behaviour is untouched', () async {
      final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
      for (final PairedKid k in await v1World()) {
        await kids.add(k);
      }
      final List<String> before = <String>[for (final PairedKid k in await kids.load()) '${k.certId}/${k.deviceName}/${k.phoneOnly}'];
      await FamilyFounder.foundFromLegacy(
          adult: adult, adultName: 'Mom', kids: await kids.load(), nowMs: t0, repo: MemoryFamilyRepository(), random: Random(12));
      expect(<String>[for (final PairedKid k in await kids.load()) '${k.certId}/${k.deviceName}/${k.phoneOnly}'], before);
    });

    test('a tablet that does not fit (no child id, or past the family size) is listed as skipped, not dropped silently', () async {
      final List<PairedKid> many = <PairedKid>[
        for (int i = 0; i < 14; i++)
          PairedKid(certId: 'c${i.toString().padLeft(2, '0')}', childDeviceKey: Uint8List.fromList(List<int>.filled(32, 50 + i)), childId: 'ivy', deviceName: 'T$i', issuedAtMs: 1),
        PairedKid(certId: 'bad', childDeviceKey: tabA.publicKey, childId: '', deviceName: 'X', issuedAtMs: 1),
      ];
      final FoundingResult r = await FamilyFounder.foundFromLegacy(
          adult: adult, adultName: 'Mom', kids: many, nowMs: t0, repo: MemoryFamilyRepository(), random: Random(13));
      expect((await r.context.state(nowMs: t0 + hour)).childDeviceKeys.length, kMaxChildDevices);
      expect(r.skippedCertIds.toSet(), <String>{'bad', 'c12', 'c13'});
    });

    test('a ledger-founded family does not change what the old pairing flow needs: the file that computes the id is not touched by the ledger code', () async {
      for (final String f in <String>['pairing_protocol.dart', 'lan_pairing_transport.dart', 'connect_child_screen.dart', 'child_connect_screen.dart']) {
        final String src = File('lib/$f').readAsStringSync();
        expect(src, isNot(contains('family_ledger')), reason: f);
        expect(src, isNot(contains('family_state')), reason: f);
        expect(src, isNot(contains('family_keys')), reason: f);
        expect(src, isNot(contains('family_channel_v2')), reason: f);
      }
    });
  });

  group('keeping the family on the device', () {
    test('the sealed area round-trips: ledger, votes, keys, and the same family comes back after a restart', () async {
      final LocalServices svc = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      expect(svc.area('familyledger').spec.encrypted, isTrue);
      final LocalStoreFamilyRepository repo = LocalStoreFamilyRepository(svc.area('familyledger', ownerId: kLocalGuardianScope));
      final FamilyContext c = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: repo, random: Random(14));
      final FamilyContext? back = await FamilyContext.load(repo, adult, nowMs: t0 + hour);
      expect(back!.familyId, c.familyId);
      expect(back.keyring.fk(0), c.keyring.fk(0));
      expect(back.keyring.gk(0), c.keyring.gk(0));
      expect(back.agreement.publicKey, c.agreement.publicKey);
      expect(back.entries.length, c.entries.length);
    });

    test('a damaged stored ledger is "no family", never a half-trusted one', () async {
      final LocalServices svc = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = svc.area('familyledger', ownerId: kLocalGuardianScope);
      final LocalStoreFamilyRepository repo = LocalStoreFamilyRepository(ns);
      await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: repo, random: Random(15));
      final Map<String, Object?> raw = Map<String, Object?>.from((await ns.get('family'))! as Map);
      final List<Object?> es = List<Object?>.from(raw['e']! as List);
      final Map<String, Object?> g = Map<String, Object?>.from(es.first! as Map);
      final Uint8List bytes = unb64(g['b']! as String)..[40] ^= 1;
      es[0] = <String, Object?>{'b': b64(bytes), 's': g['s']};
      await ns.put('family', <String, Object?>{...raw, 'e': es});
      expect(await FamilyContext.load(repo, adult, nowMs: t0 + hour), isNull);
    });

    test('a child device\'s store refuses a guardian-only key, and drops one it finds on load', () async {
      final FamilyContext c = await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: MemoryFamilyRepository(), random: Random(16));
      final FamilySnapshot s = c.snapshot();
      final FamilySnapshot asChild = FamilySnapshot(
          entries: s.entries, votes: s.votes, agreementSeed: s.agreementSeed, guardianDevice: false, fk: s.fk, gk: s.gk);
      expect(() => MemoryFamilyRepository().save(asChild), throwsStateError);
      final LocalServices svc = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = svc.area('familyledger', ownerId: kLocalGuardianScope);
      final LocalStoreFamilyRepository repo = LocalStoreFamilyRepository(ns);
      expect(() => repo.save(asChild), throwsStateError);
      // Plant one by hand: it is not used.
      await repo.save(FamilySnapshot(entries: s.entries, votes: s.votes, agreementSeed: s.agreementSeed, guardianDevice: false, fk: s.fk, gk: <int, Uint8List>{}));
      final Map<String, Object?> raw = Map<String, Object?>.from((await ns.get('family'))! as Map);
      await ns.put('family', <String, Object?>{...raw, 'gk': <String, Object?>{'0': b64(s.gk[0]!)}});
      final FamilyContext? back = await FamilyContext.load(repo, adult, nowMs: t0 + hour);
      expect(back!.keyring.guardianDevice, isFalse);
      expect(back.keyring.gk(0), isNull);
      expect(back.keyring.fk(0), isNotNull);
    });

    test('clearing removes the family', () async {
      final MemoryFamilyRepository repo = MemoryFamilyRepository();
      await FamilyFounder.found(device: adult, guardianName: 'Mom', nowMs: t0, repo: repo, random: Random(17));
      await repo.clear();
      expect(await FamilyContext.load(repo, adult, nowMs: t0), isNull);
    });
  });
}
