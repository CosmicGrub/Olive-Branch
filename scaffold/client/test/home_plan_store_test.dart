// OLIVE BRANCH — the plan for her home: the daily time total and the per-age planner choices.
// No longer UNVERIFIED — verified by CI (this file). MASTERFILE §8.1, §8.6.6.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/home_plan_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

void main() {
  group('HomePlan', () {
    test('defaults: daily time off, her home waits at every age, no reminders', () {
      const HomePlan p = HomePlan.defaults;
      expect(p.dailyHours, 0);
      for (final int age in plannerAges) {
        expect(p.holdWhenArrives(age), isTrue, reason: 'the prototype holds by default');
        expect(p.remindBefore(age), isFalse);
      }
      expect(plannerBandOfAge.keys.toList(), plannerAges);
    });

    test('round-trips through JSON', () {
      const HomePlan p = HomePlan(dailyHours: 2, dailyNote: 'You raised this from 1 h to 2 h.',
          holdAt: <int, bool>{8: false}, remind: <int, bool>{13: true});
      expect(HomePlan.fromJson(p.toJson()), p);
    });

    test('junk falls back to the defaults, field by field', () {
      expect(HomePlan.fromJson('x'), HomePlan.defaults);
      expect(HomePlan.fromJson(<String, Object?>{'dailyHours': 9}).dailyHours, 0, reason: 'only off, 1, 2 or 3');
      expect(HomePlan.fromJson(<String, Object?>{'dailyHours': '2'}).dailyHours, 0);
      expect(HomePlan.fromJson(<String, Object?>{'holdAt': <String, Object?>{'7': false, '5': 'no', '8': false}}).holdAt,
          <int, bool>{8: false}, reason: 'only 5, 8 and 13, only booleans');
      expect(HomePlan.fromJson(<String, Object?>{'dailyNote': 'x' * 300}).dailyNote, isNull);
    });

    test('words for the daily total and for a change', () {
      expect(dailyHoursWords(0), 'Off');
      expect(dailyHoursWords(2), '2 h');
      expect(dailyChangeNote(1, 2), 'You raised this from 1 h to 2 h.');
      expect(dailyChangeNote(2, 0), 'You changed this from 2 h to Off.');
      expect(dailyChangeNote(1, 1), '');
    });
  });

  group('repositories', () {
    test('memory keeps what it is given, and a failing save throws so no screen reports it kept', () async {
      final MemoryHomePlanRepository r = MemoryHomePlanRepository();
      await r.save(const HomePlan(dailyHours: 3));
      expect((await r.load()).dailyHours, 3);
      r.failSaves = true;
      await expectLater(r.save(const HomePlan(dailyHours: 1)), throwsA(isA<LocalStoreFull>()));
      expect((await r.load()).dailyHours, 3);
    });

    test('the LocalStore one survives a restart (a new repository over the same files)', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy', demoSeeds: false);
      await LocalStoreHomePlanRepository(s.area('plan', ownerId: 'ivy'))
          .save(const HomePlan(dailyHours: 1, holdAt: <int, bool>{5: false}));
      final HomePlan back = await LocalStoreHomePlanRepository(s.area('plan', ownerId: 'ivy')).load();
      expect(back.dailyHours, 1);
      expect(back.holdWhenArrives(5), isFalse);
    });

    test('the area is in the data catalogue: scoped to the child, small, not private, and says what it keeps', () {
      final LocalDataEntry e = localDataEntry('plan');
      expect(e.scope, LocalScope.child);
      expect(e.maxBytes, lessThanOrEqualTo(64 * 1024));
      expect(e.what.toLowerCase(), contains('no count'));
    });
  });
}
