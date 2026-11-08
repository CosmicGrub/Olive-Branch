// OLIVE BRANCH — the LOCAL emergency card: guardian-only, sealed, versioned, with an
// append-only history. Memory and LocalStore behave alike; the durable one survives a
// restart and is wiped with the device. Every deny path is a real assertion.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

const FamilyPrincipal gA = FamilyPrincipal(roleName: 'guardian', userId: 'ga');
const FamilyPrincipal gB = FamilyPrincipal(roleName: 'guardian', userId: 'gb');
const FamilyPrincipal ivy = FamilyPrincipal(roleName: 'child', childId: 'ivy');
const FamilyPrincipal sitter = FamilyPrincipal(roleName: 'sitter', userId: 's1');
const FamilyPrincipal guardianNoId = FamilyPrincipal(roleName: 'guardian');

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 7));

LocalServices _device(MemoryStoreBackend b) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: 'ivy', isLive: true, demoSeeds: false);

DateTime _t = DateTime.utc(2026, 11, 8, 10);

LocalEmergencyCard cardA() => const LocalEmergencyCard(
      allergies: <String>['Penicillin (rash)'],
      conditions: <String>['Asthma'],
      medicines: <EcMedicine>[EcMedicine(name: 'Inhaler', dose: '2 puffs when wheezy')],
      doctor: EcDoctor(name: 'Dr Okoye', practice: 'Riverside Surgery', phone: '020 7946 0000'),
      contacts: <EcContact>[EcContact(name: 'Claire', relation: 'Mum', phone: '07700 900123')],
    );

void both(String name, Future<void> Function(EmergencyCardService s, EmergencyCardService Function() reopen) body) {
  test('$name (memory)', () {
    final MemoryEmergencyCardRepository repo = MemoryEmergencyCardRepository();
    return body(EmergencyCardService(repo, clock: () => _t), () => EmergencyCardService(repo, clock: () => _t));
  });
  test('$name (LocalStore, reopened as after a restart)', () {
    final MemoryStoreBackend disk = MemoryStoreBackend();
    return body(EmergencyCardService.local(_device(disk), clock: () => _t),
        () => EmergencyCardService.local(_device(disk), clock: () => _t));
  });
}

void main() {
  setUp(() => _t = DateTime.utc(2026, 11, 8, 10));

  group('defaults', () {
    both('nothing is written until a guardian writes it: version 0, no card, no history', (s, _) async {
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.version, 0);
      expect(d.card, isNull);
      expect(d.history, isEmpty);
    });

    test('the model has no invented content: an empty card has every field empty', () {
      const LocalEmergencyCard c = LocalEmergencyCard();
      expect(c.isEmpty, isTrue);
      expect(c.toJson().toString(), isNot(contains('Peanut')));
      expect(c.spokenText(), 'No allergies written down.');
    });
  });

  group('guardian only, inside the service', () {
    both('a child, a sitter, a half-formed guardian and nobody are refused for writes and reads', (s, _) async {
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[ivy, sitter, guardianNoId, null, const FamilyPrincipal()]) {
        final EcResult r = await s.save(p, cardA(), expectedVersion: 0, byName: 'Nobody');
        expect(r.ok, isFalse, reason: '$p');
        expect(r.reason, 'guardian_only', reason: '$p');
        await expectLater(s.read(p), throwsA(isA<EcRefused>()), reason: '$p');
        await expectLater(s.nameOf(p), throwsA(isA<EcRefused>()), reason: '$p');
      }
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.version, 0);
      expect(d.card, isNull);
    });
  });

  group('writing, versions and history', () {
    both('the first save is version 1 with who, when and no previous card', (s, _) async {
      final EcResult r = await s.save(gA, cardA(), expectedVersion: 0, byName: 'Claire');
      expect(r.ok, isTrue);
      expect(r.version, 1);
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.version, 1);
      expect(d.card!.allergies, <String>['Penicillin (rash)']);
      expect(d.card!.doctor.name, 'Dr Okoye');
      expect(d.history.single.version, 1);
      expect(d.history.single.byName, 'Claire');
      expect(d.history.single.byId, 'ga');
      expect(d.history.single.at, '2026-11-08T10:00:00.000Z');
      expect(d.history.single.previous, isNull);
    });

    both('a change records the previous card in full and only ever appends', (s, _) async {
      await s.save(gA, cardA(), expectedVersion: 0, byName: 'Claire');
      final String firstEntry = jsonEncode((await s.read(gA)).history.first.toJson());
      _t = DateTime.utc(2026, 11, 9, 8);
      final LocalEmergencyCard changed = LocalEmergencyCard(
          allergies: const <String>['Penicillin (rash)', 'Tree nuts'], conditions: cardA().conditions,
          medicines: cardA().medicines, doctor: cardA().doctor, contacts: cardA().contacts);
      final EcResult r = await s.save(gB, changed, expectedVersion: 1, byName: 'Marcus');
      expect(r.version, 2);
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.history.length, 2);
      expect(jsonEncode(d.history.first.toJson()), firstEntry, reason: 'the first entry is untouched');
      expect(d.history.last.byName, 'Marcus');
      expect(d.history.last.at, '2026-11-09T08:00:00.000Z');
      expect(d.history.last.previous!.allergies, <String>['Penicillin (rash)']);
      expect(d.card!.allergies, <String>['Penicillin (rash)', 'Tree nuts']);
    });

    both('the remembered name is the local profile name; without one it says "A guardian"', (s, _) async {
      expect(await s.nameOf(gA), ecUnnamedGuardian);
      await s.save(gA, cardA(), expectedVersion: 0);
      expect((await s.read(gA)).history.single.byName, ecUnnamedGuardian);
      await s.save(gA, const LocalEmergencyCard(allergies: <String>['Eggs']), expectedVersion: 1, byName: 'Claire S');
      expect(await s.nameOf(gA), 'Claire S');
      expect(await s.nameOf(gB), ecUnnamedGuardian, reason: 'a name belongs to the guardian who gave it');
      // Next time no name is typed: the remembered one is used.
      await s.save(gA, const LocalEmergencyCard(allergies: <String>['Eggs', 'Soy']), expectedVersion: 2);
      expect((await s.read(gA)).history.last.byName, 'Claire S');
    });

    both('saving exactly what is stored changes nothing: no new version, no new history', (s, _) async {
      await s.save(gA, cardA(), expectedVersion: 0, byName: 'Claire');
      final EcResult r = await s.save(gA, cardA(), expectedVersion: 1, byName: 'Claire');
      expect(r.ok, isTrue);
      expect(r.version, 1);
      expect((await s.read(gA)).history.length, 1);
    });

    both('a blank card is not a change when nothing was ever written', (s, _) async {
      final EcResult r = await s.save(gA, const LocalEmergencyCard(), expectedVersion: 0);
      expect(r.ok, isTrue);
      expect(r.version, 0);
      expect((await s.read(gA)).history, isEmpty);
    });

    both('a guardian can clear a field and the history still holds what it said', (s, _) async {
      await s.save(gA, cardA(), expectedVersion: 0, byName: 'Claire');
      await s.save(gA, const LocalEmergencyCard(), expectedVersion: 1);
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.card!.isEmpty, isTrue);
      expect(d.version, 2);
      expect(d.history.last.previous!.allergies, <String>['Penicillin (rash)'], reason: 'never destroyed');
    });
  });

  group('conflicts are refused, never silently overwritten', () {
    both('a stale version is refused and nothing moves', (s, _) async {
      await s.save(gA, cardA(), expectedVersion: 0, byName: 'Claire');
      await s.save(gB, const LocalEmergencyCard(allergies: <String>['Latex']), expectedVersion: 1, byName: 'Marcus');
      final EcResult r = await s.save(gA, const LocalEmergencyCard(allergies: <String>['Mine']), expectedVersion: 1);
      expect(r.ok, isFalse);
      expect(r.reason, 'stale_version');
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.version, 2);
      expect(d.card!.allergies, <String>['Latex']);
      expect(d.history.length, 2);
    });

    both('a version from the future is refused too', (s, _) async {
      final EcResult r = await s.save(gA, cardA(), expectedVersion: 5);
      expect(r.reason, 'stale_version');
      expect((await s.read(gA)).version, 0);
    });

    both('two saves at once with the same version: exactly one wins', (s, _) async {
      final List<EcResult> r = await Future.wait(<Future<EcResult>>[
        s.save(gA, const LocalEmergencyCard(allergies: <String>['One']), expectedVersion: 0),
        s.save(gB, const LocalEmergencyCard(allergies: <String>['Two']), expectedVersion: 0),
      ]);
      expect(r.where((EcResult x) => x.ok).length, 1);
      expect(r.where((EcResult x) => x.reason == 'stale_version').length, 1);
      expect((await s.read(gA)).version, 1);
    });
  });

  group('bounds', () {
    both('too many rows, too-long text and a nameless row are refused with nothing stored', (s, _) async {
      final List<LocalEmergencyCard> bad = <LocalEmergencyCard>[
        LocalEmergencyCard(allergies: <String>[for (int i = 0; i < ecMaxAllergies + 1; i++) 'a$i']),
        LocalEmergencyCard(allergies: <String>['x' * (ecMaxLineChars + 1)]),
        const LocalEmergencyCard(medicines: <EcMedicine>[EcMedicine(name: '', dose: '5 ml')]),
        const LocalEmergencyCard(contacts: <EcContact>[EcContact(name: '', phone: '123')]),
        LocalEmergencyCard(contacts: <EcContact>[
          for (int i = 0; i < ecMaxContacts + 1; i++) EcContact(name: 'c$i')
        ]),
        const LocalEmergencyCard(doctor: EcDoctor(phone: '1111111111111111111111111111111111111111111')),
      ];
      for (final LocalEmergencyCard c in bad) {
        final EcResult r = await s.save(gA, c, expectedVersion: 0);
        expect(r.ok, isFalse);
      }
      expect((await s.read(gA)).version, 0);
      expect((await s.save(gA, cardA(), expectedVersion: 0, byName: 'n' * 41)).reason, 'too_long');
    });

    test('control characters are stripped and blank rows dropped', () {
      final LocalEmergencyCard c = checkedCard(const LocalEmergencyCard(
          allergies: <String>['  Eggs\u0000 ', '   ', ''],
          contacts: <EcContact>[EcContact(name: '', phone: '', relation: '')]));
      expect(c.allergies, <String>['Eggs']);
      expect(c.contacts, isEmpty);
    });

    test('a damaged document loads as an empty one and a tolerant parse never throws', () {
      expect(EmergencyCardDoc.fromJson('nope').version, 0);
      expect(EmergencyCardDoc.fromJson(<String, Object?>{'version': 'x', 'history': 5, 'card': 7}).card!.isEmpty, isTrue);
      final EmergencyCardDoc d = EmergencyCardDoc.fromJson(<String, Object?>{
        'version': 0,
        'history': <Object?>[<String, Object?>{'version': 3, 'at': '2026-01-01T00:00:00Z', 'byName': ''}, 4, null],
      });
      expect(d.version, 3, reason: 'the counter never falls behind its own history');
      expect(d.history.single.byName, ecUnnamedGuardian);
    });
  });

  group('the durable store', () {
    test('is catalogued, per child, sealed and guardian-side; the wipe screen lists it', () {
      final LocalDataEntry e = localDataEntry('emergencycard');
      expect(e.scope, LocalScope.child);
      expect(e.encrypted, isTrue);
      expect(e.what.toLowerCase(), contains('guardian'));
      expect(e.what.toLowerCase(), contains('never deleted'));
      expect(describeLocalData(), contains('emergencycard'));
    });

    test('survives a restart and is unreadable on disk', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final EmergencyCardService a = EmergencyCardService.local(_device(disk));
      await a.save(gA, cardA(), expectedVersion: 0, byName: 'Claire');
      final String raw = utf8.decode(disk.rawFor('child.ivy.emergencycard')!, allowMalformed: true);
      expect(raw, isNot(contains('Penicillin')));
      expect(raw, isNot(contains('Okoye')));
      final EmergencyCardService b = EmergencyCardService.local(_device(disk));
      expect((await b.read(gA)).card!.allergies, <String>['Penicillin (rash)']);
    });

    test('a full box refuses the write instead of dropping history', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalStore store = LocalStore(backend: disk, cipher: AesGcmStoreCipher(_key));
      final EmergencyCardService s = EmergencyCardService(LocalStoreEmergencyCardRepository(store.open(
          const NamespaceSpec(name: 'child.ivy.emergencycard', schema: 1, encrypted: true, maxBytes: 6 * 1024))));
      int version = 0;
      EcResult r = const EcResult.ok(0);
      for (int i = 0; i < 200 && r.ok; i++) {
        r = await s.save(gA, LocalEmergencyCard(allergies: <String>['v$i ${'z' * 150}']), expectedVersion: version);
        if (r.ok) version = r.version;
      }
      expect(r.reason, 'full');
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.history.length, version, reason: 'every accepted change is still in the history');
      expect(d.version, version);
      expect(d.card!.allergies.single, startsWith('v${version - 1} '), reason: 'the refused card did not replace it');
    });

    test('one child\'s card is not reachable from another child\'s service', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices dev = _device(disk);
      await EmergencyCardService.local(dev, childId: 'ivy').save(gA, cardA(), expectedVersion: 0);
      expect((await EmergencyCardService.local(dev, childId: 'leo').read(gA)).card, isNull);
    });

    test('a device wipe removes it', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices dev = _device(disk);
      await EmergencyCardService.local(dev).save(gA, cardA(), expectedVersion: 0);
      await dev.forgetChild('ivy');
      expect((await EmergencyCardService.local(_device(disk)).read(gA)).card, isNull);
    });

    test('a live build refuses the demo-child scope for this area too', () {
      final LocalServices live = LocalServices.memory(childId: 'real', isLive: true, demoSeeds: false);
      expect(() => EmergencyCardService.local(live, childId: 'demo-child'), throwsStateError);
    });
  });

  group('what is read aloud', () {
    test('allergies first, in the guardian\'s words, and nothing added', () {
      expect(cardA().spokenText(),
          'Allergies: Penicillin (rash). Conditions: Asthma. Medicines: Inhaler, 2 puffs when wheezy. '
          'Doctor: Dr Okoye, Riverside Surgery. Phone: 020 7946 0000. Contacts: Claire, Mum, 07700 900123.');
    });
  });
}
