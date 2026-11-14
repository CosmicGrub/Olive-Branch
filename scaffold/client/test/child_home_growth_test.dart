// OLIVE BRANCH — 'your home grows': the birthday rules. No longer UNVERIFIED — verified by CI. Prototype:
// growCheck / kid.growLater / kid.birthday in mod-child.js, and the `birthday` parity scenario (age 12 to 13 at
// local midnight). Pure logic and the state holder; the screens are tested in child_home_bands_ui_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home_bands.dart';
import 'package:olive_client/child_home_growth.dart';

void main() {
  group('her age moves by itself at local midnight on her birthday', () {
    int age(int a, DateTime last, DateTime today, {int m = 11, int d = 10}) =>
        ageAtLocalDay(age: a, month: m, day: d, lastDay: last, today: today);

    test('the evening before: still 12; at midnight: 13 (the parity scenario)', () {
      expect(age(12, DateTime(2026, 11, 9, 17, 30), DateTime(2026, 11, 9, 23, 59)), 12);
      expect(age(12, DateTime(2026, 11, 9, 17, 30), DateTime(2026, 11, 10, 0, 0)), 13);
    });
    test('only once: the next midnight and the next day leave her 13', () {
      expect(age(13, DateTime(2026, 11, 10), DateTime(2026, 11, 11)), 13);
      expect(age(13, DateTime(2026, 11, 10, 9), DateTime(2026, 11, 10, 23)), 13);
    });
    test('a device that slept through the birthday catches up when it wakes', () {
      expect(age(12, DateTime(2026, 11, 8), DateTime(2026, 11, 20)), 13);
    });
    test('a gap of more than a year counts each birthday, and her age no longer stops at 17', () {
      expect(age(9, DateTime(2024, 1, 1), DateTime(2026, 1, 1)), 11);
      expect(age(16, DateTime(2020, 1, 1), DateTime(2026, 1, 1)), 22, reason: 'real past 18 (wave 2b)');
      expect(age(17, DateTime(2026, 11, 9), DateTime(2026, 11, 10), m: 11, d: 10), 18, reason: 'the 18th birthday counts');
    });
    test('only a sanity bound stops the count (a damaged store cannot count a child up to 400)', () {
      expect(age(100, DateTime(1900, 1, 1), DateTime(2100, 1, 1)), kMaxHomeAge);
    });
    test('a Feb 29 birthday falls on Mar 1 in a common year and on Feb 29 in a leap year', () {
      expect(age(8, DateTime(2027, 2, 27), DateTime(2027, 2, 28), m: 2, d: 29), 8);
      expect(age(8, DateTime(2027, 2, 28), DateTime(2027, 3, 1), m: 2, d: 29), 9);
      expect(age(8, DateTime(2028, 2, 28), DateTime(2028, 2, 29), m: 2, d: 29), 9);
    });
    test('the time to the next local midnight', () {
      expect(untilLocalMidnight(DateTime(2026, 11, 9, 23, 0)), const Duration(hours: 1));
      expect(untilLocalMidnight(DateTime(2026, 11, 9, 0, 0)), const Duration(hours: 24));
    });
  });

  group('growCheck: the page a crossing earns', () {
    test('7 to 8 is the band page for 8; 12 to 13 the band page for 13', () {
      final GrowthMark a = growCheck(7, 8)!, b = growCheck(12, 13)!;
      expect((a.key, a.kind, a.state), (8, 'band', GrowState.ready));
      expect((b.key, b.kind, b.state), (13, 'band', GrowState.ready));
    });
    test('9 to 10 is a quiet step inside the band (a rung), not a band', () {
      final GrowthMark m = growCheck(9, 10)!;
      expect((m.key, m.kind), (10, 'rung'));
    });
    test('a crossing of no key earns no page', () {
      expect(growCheck(5, 6), isNull);
      expect(growCheck(10, 12), isNull);
    });
    test('several keys at once: the band key wins, else the last', () {
      expect(growCheck(4, 9)!.key, 8);
      expect(growCheck(9, 11)!.key, 10);
      expect(growCheck(12, 15)!.key, 13);
      expect(growCheck(13, 16)!.key, 16);
    });
    test('every key has a page', () {
      for (final int k in kGrowKeys) {
        expect(kGrowPages.containsKey(k), isTrue, reason: '$k');
      }
    });
  });

  group('ChildGrowth: ready, Not now, the Later card, Show me', () {
    test('the first age she is seen at earns no page; a birthday after it does', () async {
      final ChildGrowth g = ChildGrowth();
      await g.observe(12);
      expect(g.pageReady, isNull);
      await g.observe(13);
      expect(g.pageReady!.key, 13);
      expect(g.laterCard, isFalse);
    });

    test('Not now: the page goes away and the quiet row stays; tapping the row brings the page back', () async {
      final ChildGrowth g = ChildGrowth();
      await g.observe(7);
      await g.observe(8);
      expect(g.pageReady, isNotNull);
      await g.markLater();
      expect(g.pageReady, isNull);
      expect(g.laterCard, isTrue);
      await g.reopen();
      expect(g.pageReady, isNotNull);
      expect(g.laterCard, isFalse);
    });

    test('Show me: seen, no page, no Later row, and nothing is left to count', () async {
      final ChildGrowth g = ChildGrowth();
      await g.observe(4);
      await g.observe(5);
      await g.markSeen();
      expect(g.pageReady, isNull);
      expect(g.laterCard, isFalse);
    });

    test('a correction downward (a guardian fixes her age) clears the page and never makes one', () async {
      final ChildGrowth g = ChildGrowth();
      await g.observe(7);
      await g.observe(8);
      await g.observe(7);
      expect(g.mark, isNull);
      expect(g.shownAge, 7);
    });

    test('the same age again changes nothing and tells nobody', () async {
      final ChildGrowth g = ChildGrowth();
      await g.observe(7);
      int calls = 0;
      g.addListener(() => calls++);
      await g.observe(7);
      expect(calls, 0);
    });

    test('it is kept on the device: a new holder over the same store sees the same page, and the Later row', () async {
      final MemoryGrowthRepository repo = MemoryGrowthRepository();
      final ChildGrowth a = ChildGrowth(repository: repo);
      await a.observe(9);
      await a.observe(10);
      await a.markLater();
      final ChildGrowth b = ChildGrowth(repository: repo);
      await b.observe(10);
      expect(b.laterCard, isTrue);
      expect(b.shownAge, 10);
    });

    test('showFor opens the page for her current age on demand (the prototype\'s kid.birthday force)', () async {
      final ChildGrowth g = ChildGrowth();
      await g.showFor(9);
      expect(g.pageReady!.key, 8);
      await g.showFor(4);
      expect(g.pageReady!.key, 5, reason: 'below the first key the first page is shown');
    });

    test('a damaged saved mark reads as nothing', () {
      expect(GrowthMark.fromJson(<String, Object?>{'from': 1, 'to': 2, 'key': 99, 'kind': 'band', 'state': 'ready'}), isNull);
      expect(GrowthMark.fromJson('junk'), isNull);
      expect(GrowthMark.fromJson(<String, Object?>{'from': 7, 'to': 8, 'key': 8, 'kind': 'band', 'state': 'later'})!.state, GrowState.later);
    });
  });

  group('the band follows the age (the home re-lays itself at 5, 8 and 13)', () {
    test('protoBandOfAge', () {
      expect(<int, String>{4: protoBandOfAge(4), 5: protoBandOfAge(5), 7: protoBandOfAge(7), 8: protoBandOfAge(8), 12: protoBandOfAge(12), 13: protoBandOfAge(13)},
          <int, String>{4: 't34', 5: 't57', 7: 't57', 8: 't812', 12: 't812', 13: 't1317'});
    });
  });
}
