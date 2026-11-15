// OLIVE BRANCH — family sync, the emergency card shared between two grown-ups' phones: sharing, choosing between two
// cards, and every way a shared card is kept from changing this phone's card by itself. Verified by CI, headless.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;
import 'package:olive_client/family_sync_bundle.dart';
import 'package:olive_client/family_sync_emergency.dart';
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_event.dart';

import 'family_sync_test_support.dart';
import 'family_test_support.dart';

const FamilyPrincipal _mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal _dad = FamilyPrincipal(roleName: 'guardian', userId: 'dad');
const FamilyPrincipal _kid = FamilyPrincipal(roleName: 'child', childId: 'ivy');

LocalEmergencyCard card({List<String> allergies = const <String>['penicillin'], String doctor = 'Dr A', List<EcContact>? contacts}) =>
    LocalEmergencyCard(
      allergies: allergies,
      doctor: EcDoctor(name: doctor, phone: '555-0100'),
      contacts: contacts ?? const <EcContact>[EcContact(name: 'Nan', relation: 'grandmother', phone: '555-0101')],
    );

void main() {
  late SyncRig rig;
  late Clock clock;
  late SyncEngine m, d;
  late EmergencySync ms, ds;
  late EmergencyCardService momCard, dadCard;

  setUp(() async {
    rig = await SyncRig.make();
    clock = Clock(t0 + 10 * day);
    m = rig.engine(rig.mom, clock: clock);
    d = rig.engine(rig.dad, clock: clock);
    ms = EmergencySync(m, 'ivy');
    ds = EmergencySync(d, 'ivy');
    momCard = EmergencyCardService.memory(clock: () => DateTime.utc(2026, 11, 14));
    dadCard = EmergencyCardService.memory(clock: () => DateTime.utc(2026, 11, 14));
  });

  Future<void> carry(SyncEngine from, SyncEngine to) async {
    final SyncBundleOut out = await exportBundle(from, force: true);
    await importBundle(to, out.text, state: rig.state);
  }

  group('sharing', () {
    test('nothing shared yet reads as not started', () async {
      final EmergencyView v = await ms.view();
      expect(v.started, isFalse);
      expect(v.forked, isFalse);
      expect(v.settled, isNull);
    });

    test('one grown-up shares a card; the other phone sees it, as typed, with who shared it', () async {
      final SyncAppend r = await ms.share(card(), byName: 'Mom', state: rig.state);
      expect(r.event, isNotNull);
      await carry(m, d);
      final EmergencyView v = await ds.view();
      expect(v.settled!.byName, 'Mom');
      expect(v.settled!.card!.allergies, <String>['penicillin']);
      expect(v.settled!.card!.doctor.name, 'Dr A');
      expect(v.settled!.card!.contacts.single.name, 'Nan');
    });

    test('a shared card never changes this phone\'s card by itself; only "use it here" does, through the card service and its history', () async {
      await momCard.save(_mom, card(), expectedVersion: 0);
      await ms.share(card(), byName: 'Mom', state: rig.state);
      await dadCard.save(_dad, card(allergies: <String>['dust'], doctor: 'Dr B'), expectedVersion: 0);
      await carry(m, d);
      EmergencyCardDoc doc = await dadCard.read(_dad);
      expect(doc.version, 1);
      expect(doc.card!.allergies, <String>['dust'], reason: 'receiving an update left the card alone');
      final EmergencyVersion shared = (await ds.view()).settled!;
      final EcResult r = await EmergencySync.useHere(dadCard, _dad, shared, expectedVersion: doc.version);
      expect(r.ok, isTrue);
      doc = await dadCard.read(_dad);
      expect(doc.version, 2);
      expect(doc.card!.allergies, <String>['penicillin']);
      expect(doc.history.length, 2, reason: 'the history gained an entry; the earlier card is still in it');
      expect(doc.history.last.previous!.allergies, <String>['dust']);
    });

    test('using a shared card when this phone\'s card moved meanwhile is refused (stale), and a child cannot use one', () async {
      await ms.share(card(), byName: 'Mom', state: rig.state);
      await carry(m, d);
      final EmergencyVersion shared = (await ds.view()).settled!;
      await dadCard.save(_dad, card(allergies: <String>['dust']), expectedVersion: 0);
      expect((await EmergencySync.useHere(dadCard, _dad, shared, expectedVersion: 0)).reason, 'stale_version');
      expect((await EmergencySync.useHere(dadCard, _kid, shared, expectedVersion: 1)).reason, 'guardian_only');
      expect((await EmergencySync.useHere(dadCard, null, shared, expectedVersion: 1)).reason, 'guardian_only');
      expect((await dadCard.read(_dad)).card!.allergies, <String>['dust']);
    });

    test('a blank card, a card past the limits, the same card again, and a phone that is not a grown-up\'s are not shared', () async {
      expect((await ms.share(const LocalEmergencyCard(), byName: 'Mom', state: rig.state)).reason, 'empty');
      expect((await ms.share(card(allergies: <String>[for (int i = 0; i < 21; i++) 'a$i']), byName: 'Mom', state: rig.state)).reason, 'too_many');
      expect((await ms.share(card(allergies: <String>['x' * 201]), byName: 'Mom', state: rig.state)).reason, 'too_long');
      await ms.share(card(), byName: 'Mom', state: rig.state);
      expect((await ms.share(card(), byName: 'Mom', state: rig.state)).reason, 'same');
      expect((await EmergencySync(rig.engine(rig.kid), 'ivy').share(card(), byName: 'x', state: rig.state)).reason, 'not_member');
      expect(m.eventCount, 1);
    });

    test('a long name is shortened, and a blank one reads as "A guardian"', () async {
      await ms.share(card(), byName: 'M' * 60, state: rig.state);
      expect((await ms.view()).settled!.byName.length, 40);
      await ms.share(card(allergies: <String>['dust']), byName: '', state: rig.state);
      expect((await ms.view()).settled!.byName, ecUnnamedGuardian);
    });

    test('a different child gets a different stream', () async {
      await ms.share(card(), byName: 'Mom', state: rig.state);
      expect((await EmergencySync(m, 'zoe').view()).started, isFalse);
    });
  });

  group('two cards at once', () {
    test('both grown-ups share different cards offline: both phones show both, sharing is blocked, and nothing is changed or chosen', () async {
      await momCard.save(_mom, card(), expectedVersion: 0);
      await ms.share(card(), byName: 'Mom', state: rig.state);
      clock.ms += 1000;
      await ds.share(card(allergies: <String>['dust'], doctor: 'Dr B'), byName: 'Dad', state: rig.state);
      await carry(m, d);
      await carry(d, m);
      for (final EmergencySync s in <EmergencySync>[ms, ds]) {
        final EmergencyView v = await s.view();
        expect(v.forked, isTrue);
        expect(v.settled, isNull);
        expect(v.ends.map((EmergencyVersion e) => e.byName).toSet(), <String>{'Mom', 'Dad'});
      }
      expect((await ms.share(card(allergies: <String>['third']), byName: 'Mom', state: rig.state)).reason, 'forked');
      expect((await momCard.read(_mom)).card!.allergies, <String>['penicillin'], reason: 'the card on the phone is untouched');
    });

    test('choosing one writes a version that follows both, and the other phone settles on it', () async {
      await ms.share(card(), byName: 'Mom', state: rig.state);
      clock.ms += 1000;
      await ds.share(card(allergies: <String>['dust'], doctor: 'Dr B'), byName: 'Dad', state: rig.state);
      await carry(m, d);
      await carry(d, m);
      final EmergencyVersion pick = (await ms.view()).ends.firstWhere((EmergencyVersion e) => e.byName == 'Dad');
      final SyncAppend r = await ms.choose(pick, byName: 'Mom', state: rig.state);
      expect(r.event!.prev.length, 2);
      expect((await ms.view()).settled!.card!.allergies, <String>['dust']);
      await carry(m, d);
      final EmergencyView v = await ds.view();
      expect(v.forked, isFalse);
      expect(v.settled!.card!.doctor.name, 'Dr B');
      expect(v.settled!.byName, 'Mom', reason: 'the resolution is Mom\'s event; the history shows who chose');
    });

    test('choosing a version that is no longer an end (it moved on) is refused', () async {
      await ms.share(card(), byName: 'Mom', state: rig.state);
      clock.ms += 1000;
      await ds.share(card(allergies: <String>['dust']), byName: 'Dad', state: rig.state);
      await carry(m, d);
      await carry(d, m);
      final EmergencyView v = await ms.view();
      await ms.choose(v.ends.first, byName: 'Mom', state: rig.state);
      expect((await ms.choose(v.ends.last, byName: 'Mom', state: rig.state)).reason, 'moved');
    });
  });

  group('a shared card that cannot be trusted', () {
    test('a card past the card\'s own limits, one that is not a card, and one with an unnamed contact show as unreadable and can never be used, chosen or stacked on', () async {
      final Uint8List sid = await ms.streamId();
      final List<Object?> bad = <Object?>[
        <String, Object?>{'allergies': <Object?>[for (int i = 0; i < 25; i++) 'a$i']},
        'not a card',
        <String, Object?>{'contacts': <Object?>[<String, Object?>{'name': '', 'phone': '1'}]},
        <String, Object?>{'allergies': <Object?>[]}, // blank
        <String, Object?>{'allergies': <Object?>['x' * 400]},
      ];
      for (final Object? b in bad) {
        final SyncEngine fresh = rig.engine(rig.mom, clock: clock);
        final SyncEvent e = await SyncEvent.create(
          device: rig.dad.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: clock.ms, hlcC: 0,
          prev: const <List<int>>[], kind: kEmergencyKind, payload: <String, Object?>{'child': 'ivy', 'by': 'Dad', 'card': b},
        );
        expect((await fresh.ingest(<Uint8List>[e.wire], state: rig.state)).added, 1);
        final EmergencySync s = EmergencySync(fresh, 'ivy');
        final EmergencyView v = await s.view();
        expect(v.started, isTrue);
        expect(v.settled, isNull, reason: '$b');
        expect(v.ends.single.readable, isFalse);
        expect((await EmergencySync.useHere(momCard, _mom, v.ends.single, expectedVersion: 0)).reason, 'unreadable');
        expect((await s.choose(v.ends.single, byName: 'Mom', state: rig.state)).reason, 'unreadable');
        expect((await s.share(card(), byName: 'Mom', state: rig.state)).reason, 'unreadable');
      }
      expect((await momCard.read(_mom)).version, 0);
    });

    test('a readable shared card still passes the service\'s own checks when used', () async {
      final Uint8List sid = await ms.streamId();
      final SyncEvent e = await SyncEvent.create(
        device: rig.dad.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: clock.ms, hlcC: 0,
        prev: const <List<int>>[], kind: kEmergencyKind, payload: <String, Object?>{'child': 'ivy', 'by': 'Dad', 'card': card().toJson()},
      );
      await m.ingest(<Uint8List>[e.wire], state: rig.state);
      final EmergencyVersion v = (await ms.view()).settled!;
      expect((await EmergencySync.useHere(momCard, _mom, v, expectedVersion: 0)).ok, isTrue);
      expect((await momCard.read(_mom)).card!.contacts.single.name, 'Nan');
    });
  });
}
