// OLIVE BRANCH — the teen shell's on-device store and her own copy (lib/teen_store.dart, lib/own_copy.dart). UNVERIFIED
// until CI runs it. Real LocalStore on a memory backend (sealed with the real cipher); the copy is written to a real
// temp directory and read back.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/journal_screen.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart' show LocalNamespace;
import 'package:olive_client/own_copy.dart';
import 'package:olive_client/teen_logic.dart';
import 'package:olive_client/teen_store.dart';

final DateTime t0 = DateTime(2026, 11, 9, 9);

void main() {
  late LocalServices services;
  late TeenRepository repo;
  setUp(() {
    services = LocalServices.memory(childId: 'ivy');
    repo = TeenRepository(services.area('teen'));
  });

  group('the teen area', () {
    test('it is in the catalogue, sealed, and says in words that it is never uploaded', () {
      final LocalDataEntry e = localDataEntry('teen');
      expect(e.encrypted, isTrue);
      expect(e.scope, LocalScope.child);
      expect(e.what.toLowerCase(), contains('never uploaded'));
      expect(services.area('teen').spec.encrypted, isTrue);
    });

    test('events: add, read back in order, remove', () async {
      await repo.addEvent(const TeenEvent(id: 'e2', year: 2026, month: 11, day: 12, title: 'Second', share: EventShare.with_(<String>{'dad'})));
      await repo.addEvent(const TeenEvent(id: 'e1', year: 2026, month: 11, day: 11, title: 'First'));
      final List<TeenEvent> all = await repo.events();
      expect(all.map((TeenEvent e) => e.id), <String>['e1', 'e2']);
      expect(all.last.share.sees('dad'), isTrue);
      await repo.removeEvent('e1');
      expect((await repo.events()).map((TeenEvent e) => e.id), <String>['e2']);
    });

    test('free times, asks, the handover choice, staying in touch and notes round-trip', () async {
      await repo.saveFreeTimes(const FreeTimes().toggled(true, 'eve').asPublished());
      expect((await repo.freeTimes()).weekends, <String>{'eve'});
      await repo.saveAsks(const AskLedger().ask('a1', 'mom', 'calendar', t0, herAge: 15)!);
      expect((await repo.asks()).open.single.askerId, 'mom');
      await repo.saveHandover(const HandoverRecord().chose(HandoverChoice.keep, t0));
      expect((await repo.handover()).choice, HandoverChoice.keep);
      await repo.saveTouch(const StayInTouch().offer(Channel.messages, true));
      expect((await repo.touch()).offered, <Channel>{Channel.messages});
      await repo.saveNote('mom', '  I am so proud of you.  ');
      await repo.saveNote('dad', 'Drive safe.');
      expect(await repo.notes(), <String, String>{'mom': 'I am so proud of you.', 'dad': 'Drive safe.'});
      await repo.saveNote('dad', '   ');
      expect((await repo.notes()).containsKey('dad'), isFalse, reason: 'an empty note removes it');
    });

    test('nothing stored yet reads as nothing, never as a failure', () async {
      expect(await repo.events(), isEmpty);
      expect((await repo.freeTimes()).published, isFalse);
      expect((await repo.asks()).asks, isEmpty);
      expect((await repo.handover()).chosen, isFalse);
      expect((await repo.touch()).offered, isEmpty);
      expect(await repo.notes(), isEmpty);
    });

    test('a damaged document is skipped, not fatal', () async {
      final LocalNamespace ns = services.area('teen');
      await ns.put('ev.bad', <String, Object?>{'id': 5});
      await ns.put('asks', 'junk');
      await ns.put('handover', <String, Object?>{'choice': 'nonsense'});
      await ns.put('notes', <String, Object?>{'mom': 7, 'dad': 'ok'});
      final TeenRepository r = TeenRepository(ns);
      expect(await r.events(), isEmpty);
      expect((await r.asks()).asks, isEmpty);
      expect((await r.handover()).chosen, isFalse);
      expect(await r.notes(), <String, String>{'dad': 'ok'});
    });

    test('it is her own namespace: another child on the same device cannot reach it', () async {
      await repo.addEvent(const TeenEvent(id: 'e1', year: 2026, month: 1, day: 1, title: 'mine'));
      final TeenRepository other = TeenRepository(services.area('teen', ownerId: 'someone-else'));
      expect(await other.events(), isEmpty);
    });
  });

  group('the app copy goes only when, and exactly when, the rules say', () {
    test('purgeIfDue removes nothing without a saved copy, or before 30 days, or on keep', () async {
      int ran = 0;
      Future<void> purge() async => ran++;
      await repo.saveHandover(const HandoverRecord().chose(HandoverChoice.take, t0));
      expect(await purgeIfDue(repo, t0.add(const Duration(days: 40)), purge), isFalse, reason: 'no saved copy');
      await repo.saveHandover(const HandoverRecord().chose(HandoverChoice.take, t0).copyMade(t0, '/x'));
      expect(await purgeIfDue(repo, t0.add(const Duration(days: 29)), purge), isFalse, reason: 'before 30 days');
      await repo.saveHandover(const HandoverRecord().chose(HandoverChoice.keep, t0).copyMade(t0, '/x'));
      expect(await purgeIfDue(repo, t0.add(const Duration(days: 400)), purge), isFalse, reason: 'keep never removes');
      expect(ran, 0);
      await repo.saveHandover(const HandoverRecord().chose(HandoverChoice.take, t0).copyMade(t0, '/x'));
      expect(await purgeIfDue(repo, t0.add(const Duration(days: 30)), purge), isTrue);
      expect(ran, 1);
    });

    test('a real purge (forgetChild) takes this child only', () async {
      await repo.addEvent(const TeenEvent(id: 'e1', year: 2026, month: 1, day: 1, title: 'mine'));
      final TeenRepository other = TeenRepository(services.area('teen', ownerId: 'sibling'));
      await other.addEvent(const TeenEvent(id: 'e9', year: 2026, month: 1, day: 1, title: 'theirs'));
      await services.forgetChild('ivy');
      expect(await TeenRepository(services.area('teen')).events(), isEmpty);
      expect((await other.events()).single.title, 'theirs');
    });
  });

  group('her own copy', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('olive_copy_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('it holds what is hers, including the journal, and leaves out what is not hers', () async {
      await JournalRepository(services.area('journal')).add(JournalEntry(id: 'j1', childId: 'ivy', body: 'private words', createdAt: t0));
      await repo.addEvent(const TeenEvent(id: 'e1', year: 2026, month: 1, day: 1, title: 'Dentist'));
      await services.area('family').put('x', <String, Object?>{'who': 'the grown-ups built this'});
      await services.area('worries').put('w', <String, Object?>{'tap': 'a worry'});
      await services.area('devicekey').put('k', 'secret');
      final Map<String, Object?> copy = await buildOwnCopy(services, childName: 'Ivy', now: t0);
      final Map<String, Object?> areas = copy['areas']! as Map<String, Object?>;
      expect(areas.keys, containsAll(<String>['journal', 'teen']));
      expect(areas.keys, isNot(contains('family')));
      expect(areas.keys, isNot(contains('worries')));
      expect(areas.keys, isNot(contains('devicekey')));
      expect(jsonEncode(copy), contains('private words'));
      expect(copy['notIncluded'], ownCopyExcludes);
      expect(copy['notOnThisDevice'], ownCopyNotHere, reason: 'honest about what a copy made offline cannot hold');
    });

    test('it is written to a real file, read back and checked', () async {
      await repo.addEvent(const TeenEvent(id: 'e1', year: 2026, month: 1, day: 1, title: 'Dentist'));
      final OwnCopyResult r = await saveOwnCopy(services, childName: 'Ivy', now: t0, documentsDirectory: () async => dir);
      expect(r.verified, isTrue);
      expect(File(r.path).existsSync(), isTrue);
      final Map<String, Object?> back = jsonDecode(File(r.path).readAsStringSync()) as Map<String, Object?>;
      expect(back['child'], <String, Object?>{'name': 'Ivy'});
      expect(File(r.path).readAsStringSync(), contains('Dentist'));
    });

    test('readable areas are not reported as unread', () async {
      await services.area('journal').put('e.1', <String, Object?>{'id': '1'});
      final Map<String, Object?> copy = await buildOwnCopy(services, childName: 'Ivy', now: t0, childId: 'ivy');
      expect(copy.containsKey('couldNotRead'), isFalse);
    });

    test('the words describing it have no number and say plainly what an offline copy cannot hold', () {
      final String all = <String>[for (final (String a, String b) in ownCopyIncludes) '$a $b', ownCopyExcludes, ownCopyNotHere, ownCopyForm].join(' ');
      expect(all, isNot(matches(RegExp(r'\d'))));
      expect(ownCopyNotHere.toLowerCase(), contains('online'));
    });
  });
}
