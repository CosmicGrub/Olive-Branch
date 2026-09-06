// OLIVE BRANCH — pure logic tests for the ported jokebook in joke_logic.dart.
// Mirrors the same behaviours packages/jokes/test/jokes.test.mjs asserts,
// against the Dart port actually used by jokebook_screen.dart. MASTERFILE
// §9.2, prohibition P2.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/joke_logic.dart';

void main() {
  group('catalogue — a real library, not a placeholder', () {
    test('at least fifty jokes, every id unique, every setup and punchline present', () {
      expect(kJokeCatalogue.length, greaterThanOrEqualTo(50));
      expect(kJokeCatalogue.map((j) => j.id).toSet().length, kJokeCatalogue.length);
      for (final j in kJokeCatalogue) {
        expect(j.setup.trim(), isNotEmpty, reason: j.id);
        expect(j.punchline.trim(), isNotEmpty, reason: j.id);
      }
    });

    test('floor starts at 4 (same as the games catalogue) and nothing is gated above 12', () {
      expect(kJokeCatalogue.map((j) => j.minAge).reduce((a, b) => a < b ? a : b), 4);
      expect(kJokeCatalogue.map((j) => j.minAge).reduce((a, b) => a > b ? a : b), 12);
    });

    test('every promised category is represented and none is more than half the book', () {
      final counts = <JokeCategory, int>{};
      for (final j in kJokeCatalogue) {
        counts[j.category] = (counts[j.category] ?? 0) + 1;
      }
      for (final c in JokeCategory.values) {
        expect(counts[c], isNotNull, reason: 'category $c has no jokes');
        expect(counts[c]!, lessThanOrEqualTo(kJokeCatalogue.length ~/ 2), reason: '$c dominates');
      }
    });

    test('the Dart port carries the same ids as the TS original — spot check across the age range', () {
      for (final id in ['dino-snore', 'kk-lettuce', 'impasta', 'outstanding-field',
          'abdominal-snowman', 'anti-gravity', 'parallel-lines']) {
        expect(byId(id), isNotNull, reason: id);
      }
      expect(byId('nope'), isNull);
    });
  });

  group('forAge — a floor, never a ceiling', () {
    test('a four-year-old still has jokes, and never a 5+ one', () {
      final four = forAge(4);
      expect(four, isNotEmpty);
      expect(four.every((j) => j.minAge <= 4), isTrue);
    });

    test('more unlock at every step from 4 to 12, and a teenager keeps the whole book', () {
      var prev = 0;
      for (var age = 4; age <= 12; age++) {
        final n = forAge(age).length;
        expect(n, greaterThan(prev), reason: 'age $age');
        prev = n;
      }
      expect(forAge(12).length, kJokeCatalogue.length);
      expect(forAge(15).length, kJokeCatalogue.length);
    });

    test('a seven-year-old already has a real choice — twenty or more', () {
      expect(forAge(7).length, greaterThanOrEqualTo(20));
    });
  });

  group('randomJoke — never the one she just heard', () {
    test('returns a joke she can get', () {
      expect(randomJoke(6, pick: () => 0.5)!.minAge, lessThanOrEqualTo(6));
    });

    test('a deterministic pick drives the choice', () {
      expect(randomJoke(12, pick: () => 0)!.id, kJokeCatalogue.first.id);
    });

    test('with the last one excluded, pick 0 lands on the NEXT joke, not the same one', () {
      final pool = forAge(4);
      final first = randomJoke(4, pick: () => 0)!;
      expect(first.id, pool[0].id);
      expect(randomJoke(4, excludeId: first.id, pick: () => 0)!.id, pool[1].id);
    });

    test('two hundred real random draws never repeat the excluded joke', () {
      final first = randomJoke(4, pick: () => 0)!;
      for (var i = 0; i < 200; i++) {
        expect(randomJoke(4, excludeId: first.id)!.id, isNot(first.id));
      }
    });

    test('a pick at the very top of the range stays inside the pool', () {
      expect(randomJoke(12, pick: () => 0.999999), isNotNull);
    });

    test('below the youngest floor there is honestly nothing, not a crash', () {
      expect(randomJoke(3), isNull);
    });
  });

  group('favourites — P2', () {
    test('star adds, starring twice is one star and returns the same list', () {
      var list = <JokeFavourite>[];
      list = star(list, 'dino-snore', '2026-09-01T20:00:00Z');
      expect(isStarred(list, 'dino-snore'), isTrue);
      final again = star(list, 'dino-snore', '2026-09-01T20:01:00Z');
      expect(again.length, 1);
      expect(identical(again, list), isTrue);
    });

    test('newest first — tonight\'s star is tomorrow\'s first pick', () {
      var list = star(<JokeFavourite>[], 'dino-snore', '2026-09-01T20:00:00Z');
      list = star(list, 'impasta', '2026-09-02T20:00:00Z');
      expect(favouritesChildView(list).first.id, 'impasta');
    });

    test('unstar removes only that one', () {
      var list = star(<JokeFavourite>[], 'dino-snore', '2026-09-01T20:00:00Z');
      list = star(list, 'impasta', '2026-09-02T20:00:00Z');
      list = unstar(list, 'dino-snore');
      expect(isStarred(list, 'dino-snore'), isFalse);
      expect(list.length, 1);
    });

    test('a stale id (a joke removed from the book) is dropped from her view, not crashed on', () {
      expect(favouritesChildView([const JokeFavourite(id: 'no-such-joke', starredAt: 'x')]), isEmpty);
    });

    test('her view is clean by the same audit library_logic.dart runs, and the audit really bites', () {
      final list = star(<JokeFavourite>[], 'impasta', '2026-09-02T20:00:00Z');
      final view = [for (final j in favouritesChildView(list)) {'id': j.id, 'setup': j.setup}];
      expect(auditChildView(view).ok, isTrue);
      final leak = auditChildView([{'id': 'x', 'timesRead': 3}]);
      expect(leak.ok, isFalse);
      expect(leak.leaks, ['timesRead']);
      expect(jokebookForbidden, contains('streak'));
    });
  });
}
