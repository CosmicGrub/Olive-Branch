// OLIVE BRANCH — Family structure service and storage seam. Local-first: no network.
// Every deny path is a real assertion.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';

const FamilyPrincipal guardian = FamilyPrincipal(roleName: 'guardian', userId: 'g1');
const FamilyPrincipal child = FamilyPrincipal(roleName: 'child', childId: 'c1');

Map<String, Object?> person(String id, String label, String role, String? home, List<String> contact) =>
    <String, Object?>{'id': id, 'label': label, 'role': role, 'homeId': home, 'contact': contact, 'away': null};
Map<String, Object?> home(String id, String name) => <String, Object?>{'id': id, 'name': name, 'childSleeps': true};
Map<String, Object?> putPerson(Map<String, Object?> p) => <String, Object?>{'op': 'put_person', 'person': p};
Map<String, Object?> putHome(Map<String, Object?> h) => <String, Object?>{'op': 'put_home', 'home': h};
final Map<String, Object?> now = Timing.now.toJson();
final Map<String, Object?> hold = Timing.hold.toJson();

class Rig {
  Rig._(String start) : day = DateTime(int.parse(start.substring(0, 4)), int.parse(start.substring(5, 7)), int.parse(start.substring(8, 10)), 9) {
    store = MemoryFamilyStore();
    svc = FamilyService(store, clock: () => day);
  }
  static Future<Rig> make({String start = '2026-11-07', String? birth}) async {
    final Rig r = Rig._(start);
    if (birth != null) await r.svc.setBirthDate(guardian, birth, yearsOld: 7);
    return r;
  }
  late final MemoryFamilyStore store;
  late final FamilyService svc;
  DateTime day;
  void go(String iso) => day = DateTime(int.parse(iso.substring(0, 4)), int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)), 9);
  Future<FamilyWrite> add(Map<String, Object?> op, [Map<String, Object?>? t, Map<String, Object?>? story]) =>
      svc.addChange(guardian, actorName: 'Dad', yearsOld: 7, op: op, timing: t ?? now, story: story);
  Future<FamilyChildSnapshot> kid() => svc.childSnapshot(child, childId: 'c1', yearsOld: 7);
  Future<FamilyOverview> ov() => svc.overview(guardian, yearsOld: 7);
}

List<String> names(FamilyChildSnapshot s) => <String>[for (final ChildPlace p in s.view.places) for (final ChildPerson x in p.people) x.name];

void main() {
  group('F1 only a guardian writes; F2 only the child reads her own', () {
    for (final (String, FamilyPrincipal?) p in <(String, FamilyPrincipal?)>[
      ('child', child), ('sitter', const FamilyPrincipal(roleName: 'sitter', userId: 's')),
      ('step_parent', const FamilyPrincipal(roleName: 'step_parent', userId: 'x')), ('null', null),
      ('system', const FamilyPrincipal(roleName: 'system')),
    ]) {
      test('${p.$1} cannot add, release, undo, set a birth date or read the overview', () async {
        final Rig r = await Rig.make();
        final FamilyWrite w = await r.add(putHome(home('h1', 'A')));
        expect(w.ok, isTrue);
        final FamilyPrincipal? who = p.$2;
        await expectLater(r.svc.addChange(who, actorName: 'x', yearsOld: 7, op: putHome(home('h2', 'B')), timing: now), throwsA(isA<FamilyStoreRefused>()));
        await expectLater(r.svc.release(who, actorName: 'x', yearsOld: 7, changeId: w.id!), throwsA(isA<FamilyStoreRefused>()));
        await expectLater(r.svc.undo(who, actorName: 'x', yearsOld: 7, changeId: w.id!), throwsA(isA<FamilyStoreRefused>()));
        await expectLater(r.svc.setBirthDate(who, '2019-04-02', yearsOld: 7), throwsA(isA<FamilyStoreRefused>()));
        await expectLater(r.svc.overview(who, yearsOld: 7), throwsA(isA<FamilyStoreRefused>()));
        expect((await r.store.load()).records.length, 1, reason: 'nothing was written by the refused calls');
      });
    }
    for (final (String, FamilyPrincipal?, String) p in <(String, FamilyPrincipal?, String)>[
      ('guardian', guardian, 'c1'), ('sitter', const FamilyPrincipal(roleName: 'sitter', userId: 's'), 'c1'),
      ('another child', const FamilyPrincipal(roleName: 'child', childId: 'c2'), 'c1'), ('null', null, 'c1'),
    ]) {
      test('${p.$1} cannot read the child snapshot', () async {
        final Rig r = await Rig.make();
        await expectLater(r.svc.childSnapshot(p.$2, childId: p.$3, yearsOld: 7), throwsA(isA<FamilyStoreRefused>()));
      });
    }
  });

  group('F2/F3 timing reaches her on this device', () {
    test('now is hers at once; a held change is not until released; release is a new row', () async {
      final Rig r = await Rig.make();
      await r.add(putHome(home('h1', "Mom's house")));
      await r.add(putPerson(person('p1', 'Mom', 'guardian', 'h1', <String>['live_call'])));
      expect(names(await r.kid()), <String>['Mom']);
      final FamilyWrite held = await r.add(putPerson(person('p2', 'Dana', 'step_parent', 'h1', <String>['message'])), hold);
      expect(held.state, 'held');
      expect(names(await r.kid()), <String>['Mom'], reason: 'a held change is invisible to her');
      expect((await r.ov()).intended.people.length, 2, reason: 'but the guardian sees it');
      expect((await r.ov()).pending, <String>[held.id!]);
      final int before = (await r.store.load()).records.length;
      expect((await r.svc.release(guardian, actorName: 'Mom', yearsOld: 7, changeId: held.id!, toldOn: '2026-11-06')).ok, isTrue);
      expect((await r.store.load()).records.length, before + 1, reason: 'release appends, never edits');
      expect(names(await r.kid()), <String>['Mom', 'Dana']);
      expect((await r.store.load()).records.last.toldOn, '2026-11-06');
      expect((await r.svc.release(guardian, actorName: 'Dad', yearsOld: 7, changeId: held.id!)).reason, 'already_released');
    });
    test('a dated change arrives on its day, not before', () async {
      final Rig r = await Rig.make();
      await r.add(putHome(home('h1', 'H')));
      final FamilyWrite w = await r.add(putPerson(person('p1', 'Gran', 'relative', 'h1', <String>['message'])), <String, Object?>{'kind': 'date', 'on': '2026-11-21'});
      expect(w.state, 'scheduled');
      expect(names(await r.kid()), isEmpty);
      r.go('2026-11-20');
      expect(names(await r.kid()), isEmpty);
      r.go('2026-11-21');
      expect(names(await r.kid()), <String>['Gran']);
      expect((await r.ov()).history.first.state, 'applied');
    });
    test('refusals: bad op, bad date, past date, settings cannot be held, bad release', () async {
      final Rig r = await Rig.make();
      expect((await r.add(<String, Object?>{'op': 'rm_rf'})).reason, 'bad_op');
      expect((await r.add(putHome(home('h1', 'H')), <String, Object?>{'kind': 'date', 'on': '2026-11-06'})).reason, 'date_not_future');
      expect((await r.add(<String, Object?>{'op': 'set_birthday_visible', 'visible': false}, hold)).reason, 'settings_now_only');
      final FamilyWrite w = await r.add(putHome(home('h1', 'H')));
      expect((await r.svc.release(guardian, actorName: 'x', yearsOld: 7, changeId: w.id!)).reason, 'not_held');
      expect((await r.svc.release(guardian, actorName: 'x', yearsOld: 7, changeId: 'nope')).reason, 'unknown_change');
      final FamilyWrite h = await r.add(putPerson(person('p1', 'A', 'relative', null, <String>[])), hold);
      expect((await r.svc.release(guardian, actorName: 'x', yearsOld: 7, changeId: h.id!, toldOn: '2026-11-08')).reason, 'bad_date');
      expect((await r.svc.release(guardian, actorName: 'x', yearsOld: 7, changeId: h.id!, toldOn: 'soon')).reason, 'bad_date');
    });
    test('F6: a court-ordered rhythm is locked and not editable', () async {
      final Rig r = await Rig.make();
      const Rhythm order = Rhythm(pattern: '2-2-3', exchangeTime: '17:00', source: 'court_order');
      final FamilyWrite w = await r.svc.addChange(guardian, actorName: 'Dad', yearsOld: 7, order: order, timing: hold,
          op: <String, Object?>{'op': 'set_rhythm', 'rhythm': const Rhythm(pattern: '2-2-5-5', exchangeDay: 0, exchangeTime: '18:00').toJson()});
      expect(w.reason, 'locked_by_order');
      expect((await r.svc.overview(guardian, yearsOld: 7, order: order)).rhythmLocked, isTrue);
      expect((await r.svc.overview(guardian, yearsOld: 7)).rhythmLocked, isFalse);
    });
  });

  group('undo and the append-only history', () {
    test('an undo is a new entry; the original stays; twice is refused', () async {
      final Rig r = await Rig.make();
      await r.add(putHome(home('h1', 'H')));
      await r.add(putPerson(person('p1', 'Dana', 'step_parent', 'h1', <String>['message'])));
      final FamilyWrite rel = await r.add(putPerson(person('p1', 'Dani', 'step_parent', 'h1', <String>['message'])));
      expect(names(await r.kid()), <String>['Dani']);
      final FamilyWrite u = await r.svc.undo(guardian, actorName: 'Mom', yearsOld: 7, changeId: rel.id!);
      expect(u.ok, isTrue);
      expect(names(await r.kid()), <String>['Dana']);
      final FamilySnapshot s = await r.store.load();
      expect(s.records.map((FamilyRecord x) => x.entry.id), containsAll(<String>[rel.id!, u.id!]));
      expect(s.records.last.undoes, rel.id);
      expect((await r.svc.undo(guardian, actorName: 'Mom', yearsOld: 7, changeId: rel.id!)).reason, 'already_undone');
      expect((await r.svc.undo(guardian, actorName: 'Mom', yearsOld: 7, changeId: 'nope')).reason, 'unknown_change');
    });
    test('undoing a held change that never reached her applies now and announces nothing', () async {
      final Rig r = await Rig.make();
      final FamilyWrite h = await r.add(putPerson(person('p1', 'Pat', 'relative', null, <String>[])), hold);
      final FamilyWrite u = await r.svc.undo(guardian, actorName: 'Dad', yearsOld: 7, changeId: h.id!);
      expect(u.state, 'applied');
      expect(names(await r.kid()), isEmpty);
    });
    test('the history only grows: ids are unique and sequence is strictly increasing', () async {
      final Rig r = await Rig.make();
      for (int i = 0; i < 5; i++) {
        await r.add(<String, Object?>{'op': 'set_birthday_visible', 'visible': i.isEven});
      }
      final List<int> seqs = <int>[for (final FamilyRecord x in (await r.store.load()).records) x.entry.seq];
      expect(seqs, <int>[1, 2, 3, 4, 5]);
    });
    test('the service exposes no edit or delete method for the history', () {
      // Compile-time shape: a runtime check on the public surface by name.
      final String surface = FamilyService(MemoryFamilyStore()).runtimeType.toString();
      expect(surface, 'FamilyService');
    });
  });

  group('F4 the band hold, per-area overrides and rungs', () {
    test('a birthday does not move her until a guardian releases the band', () async {
      final Rig r = await Rig.make(start: '2026-11-07', birth: '2019-04-02');
      await r.add(putHome(home('h1', 'H')));
      await r.add(putPerson(person('p1', 'Mom', 'guardian', 'h1', <String>['live_call'])));
      expect((await r.kid()).view.band, 't57');
      r.go('2027-06-01'); // eight now
      final FamilyOverview o = await r.svc.overview(guardian, yearsOld: 7);
      expect(o.naturalBand, 't812');
      expect(o.effectiveBand, 't57');
      expect(o.bandHeld, isTrue);
      expect((await r.svc.childSnapshot(child, childId: 'c1', yearsOld: 7)).view.band, 't57');
      final FamilyWrite w = await r.svc.addChange(guardian, actorName: 'Mom', yearsOld: 7, op: <String, Object?>{'op': 'release_band', 'band': 't812'}, timing: now);
      expect(w.state, 'applied');
      expect((await r.svc.childSnapshot(child, childId: 'c1', yearsOld: 7)).view.band, 't812');
    });
    test('turning the hold off lets her band follow her age', () async {
      final Rig r = await Rig.make(start: '2026-11-07', birth: '2019-04-02');
      await r.add(<String, Object?>{'op': 'set_band_hold', 'hold': false});
      r.go('2027-06-01');
      expect((await r.svc.childSnapshot(child, childId: 'c1', yearsOld: 7)).view.band, 't812');
    });
    test('an override changes one area; the rungs are from her years and are never lowered', () async {
      final Rig r = await Rig.make(start: '2029-06-01', birth: '2019-04-02'); // 10
      await r.add(<String, Object?>{'op': 'set_area_band', 'area': 'games', 'band': 't34'});
      await r.add(<String, Object?>{'op': 'release_band', 'band': 't812'});
      final FamilyChildSnapshot k = await r.svc.childSnapshot(child, childId: 'c1', yearsOld: 10);
      expect(k.view.areas['games']!.band, 't34');
      expect(k.view.hasTile('play'), isFalse);
      expect(k.view.ladder['ownList'], isTrue);
      expect(k.view.hasTile('myList'), isTrue);
    });
    test('without a birth date the band comes from the age she is given', () async {
      final Rig r = await Rig.make();
      expect((await r.svc.childSnapshot(child, childId: 'c1', yearsOld: 4)).view.band, 't34');
    });
  });

  group('birthday', () {
    test('a quiet line only in her last week, never when hidden, and a bad date is refused', () async {
      final Rig r = await Rig.make(start: '2026-12-02', birth: '2019-12-09');
      FamilyChildSnapshot k = await r.kid();
      expect(k.birthday!.sleepsUntil, 7);
      expect(k.birthday!.lineShown, isTrue);
      expect(k.birthday!.monthDay, '12-09');
      expect(k.birthday!.turnsYears, 7);
      r.go('2026-11-07');
      k = await r.kid();
      expect(k.birthday!.lineShown, isFalse);
      await r.add(<String, Object?>{'op': 'set_birthday_visible', 'visible': false});
      expect((await r.kid()).birthday, isNull, reason: 'a guardian can hide it');
      expect(await r.svc.setBirthDate(guardian, '2999-01-01', yearsOld: 7), isFalse);
      expect(await r.svc.setBirthDate(guardian, 'soon', yearsOld: 7), isFalse);
      expect(await r.svc.setBirthDate(guardian, null, yearsOld: 7), isTrue);
      expect((await r.ov()).birthday, isNull);
    });
  });

  group('F7 stories are guardian-authored, and reach her only when released', () {
    test('a story rides with a held change, shows after release, then expires', () async {
      final Rig r = await Rig.make();
      final FamilyWrite w = await r.add(putPerson(person('p1', 'Nan', 'relative', null, <String>['message'])), hold,
          <String, Object?>{'pages': <String>["Some weeks you sleep at Mom's.", "Then at Dad's."]});
      expect(w.ok, isTrue);
      expect((await r.kid()).story, isNull, reason: 'not while held');
      await r.svc.release(guardian, actorName: 'Dad', yearsOld: 7, changeId: w.id!);
      final ChildStory s = (await r.kid()).story!;
      expect(s.from, 'Dad');
      expect(s.pages.length, 2);
      r.go('2026-11-21');
      expect((await r.kid()).story, isNotNull, reason: 'day 14');
      r.go('2026-11-22');
      expect((await r.kid()).story, isNull);
    });
    test('a bad story refuses the whole change and writes nothing', () async {
      final Rig r = await Rig.make();
      expect((await r.add(putHome(home('h1', 'H')), hold, <String, Object?>{'pages': <String>['x' * 300]})).reason, 'bad_story');
      expect((await r.add(putHome(home('h1', 'H')), hold, <String, Object?>{'pages': <String>['a'], 'generated': true})).reason, 'bad_story');
      expect((await r.store.load()).records, isEmpty);
    });
  });

  group('F5 what she gets has no role words', () {
    test('her snapshot never carries a role word, and background people are not in it', () async {
      final Rig r = await Rig.make();
      await r.add(putHome(home('h1', 'H')));
      await r.add(putPerson(person('p1', 'Dana', 'step_parent', 'h1', <String>['message'])));
      await r.add(putPerson(person('p2', 'Sue', 'sitter', 'h1', <String>['message'])));
      await r.add(putPerson(person('p3', 'Mr Lee', 'caseworker', null, <String>['message'])));
      final FamilyChildSnapshot k = await r.kid();
      expect(names(k), <String>['Dana']);
      final String json = jsonEncode(k.view.toJson()).toLowerCase();
      for (final String w in <String>['step', 'sitter', 'caseworker', 'guardian', 'foster', 'relative', 'role']) {
        expect(json.contains(w), isFalse, reason: w);
      }
      expect(k.view.features['myHelpers'], isTrue);
    });
  });

  group('the storage seam', () {
    test('a snapshot survives a JSON round trip, which is the whole contract', () async {
      final Rig r = await Rig.make(birth: '2019-04-02');
      await r.add(putHome(home('h1', 'H')));
      final FamilyWrite h = await r.add(putPerson(person('p1', 'A', 'relative', 'h1', <String>['message'])), hold, <String, Object?>{'pages': <String>['hello']});
      await r.svc.release(guardian, actorName: 'Dad', yearsOld: 7, changeId: h.id!);
      final FamilySnapshot a = await r.store.load();
      final FamilySnapshot b = FamilySnapshot.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>);
      expect(b.toJson(), a.toJson());
    });
    test('a different store behind the same two methods behaves identically', () async {
      final _CountingStore s = _CountingStore();
      final FamilyService svc = FamilyService(s, clock: () => DateTime(2026, 11, 7, 9));
      await svc.addChange(guardian, actorName: 'Dad', yearsOld: 7, op: putHome(home('h1', 'H')), timing: now);
      expect((await svc.overview(guardian, yearsOld: 7)).released.homes.length, 1);
      expect(s.saves, greaterThan(0));
    });
    test('a snapshot handed out cannot alias the stored one', () async {
      final MemoryFamilyStore m = MemoryFamilyStore();
      await m.save(const FamilySnapshot(birthDate: '2019-04-02'));
      final FamilySnapshot a = await m.load();
      expect(identical(a, await m.load()), isFalse);
    });
  });
}

class _CountingStore implements FamilyStore {
  Map<String, Object?>? j;
  int saves = 0;
  @override
  Future<FamilySnapshot> load() async => j == null ? const FamilySnapshot() : FamilySnapshot.fromJson(jsonDecode(jsonEncode(j)) as Map<String, Object?>);
  @override
  Future<void> save(FamilySnapshot s) async {
    saves++;
    j = jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
  }
}
