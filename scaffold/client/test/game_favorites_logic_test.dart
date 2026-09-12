// OLIVE BRANCH — pure logic tests for GamePickerScreen's Recommended row
// (game_favorites_logic.dart). Mirrors the same behaviours
// packages/games/test/favorites.test.mjs asserts against the TS original,
// against the Dart port game_picker.dart/live_game_picker.dart actually
// use. MASTERFILE §9.2, prohibition P2.
// docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-
// design.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_favorites_logic.dart';
import 'package:olive_client/game_logic.dart';

void main() {
  group('star / unstar — idempotent, no duplicates', () {
    test('starring adds it; starring twice is one star, not two', () {
      var list = <String>[];
      list = star(list, 'tictactoe');
      expect(list, contains('tictactoe'));
      final again = star(list, 'tictactoe');
      expect(again.length, 1);
      expect(identical(again, list), isTrue, reason: 'nothing to re-render on a repeat star');
    });

    test('unstar removes it and leaves the others alone', () {
      var list = star(star(<String>[], 'tictactoe'), 'chess');
      list = unstar(list, 'tictactoe');
      expect(list, isNot(contains('tictactoe')));
      expect(list, ['chess']);
    });

    test('unstarring something never starred is a harmless no-op', () {
      expect(unstar(['chess'], 'nope'), ['chess']);
    });
  });

  group('favouritesFor — resolves against the live catalogue, no dangling refs', () {
    test('a stale kind name is dropped, not a crash, and order follows the catalogue', () {
      final result = favouritesFor(catalogue, {'chess', 'tictactoe'});
      // 'chess' is not a real GameKind name in this Dart catalogue at all —
      // the same "removed from the catalogue" case favorites.ts's own test
      // covers, just via a name that was never real here rather than one
      // that used to be.
      expect(result.map((g) => g.kind), [GameKind.tictactoe]);
    });

    test('no starred kinds resolves to an empty list, not null', () {
      expect(favouritesFor(catalogue, <String>{}), isEmpty);
    });

    test('every real starred kind resolves to its full GameMeta, no duplicates', () {
      final result = favouritesFor(catalogue, {'story', 'memory'});
      expect(result.length, 2);
      expect(result.map((g) => g.kind).toSet(), {GameKind.story, GameKind.memory});
    });
  });

  group('newlyUnlocked — the age-crossed-since-last-open rule', () {
    test('a null ageAtLastOpen (first-ever open) returns nothing', () {
      expect(newlyUnlocked(catalogue, 8, null), isEmpty);
    });

    test('a game whose minAge sits strictly between ageAtLastOpen and her real age is newly unlocked', () {
      // twoTruths has minAge 6 — the only catalogue entry with that floor.
      final result = newlyUnlocked(catalogue, 6, 5);
      expect(result.map((g) => g.kind), contains(GameKind.twoTruths));
    });

    test('a game she already had at ageAtLastOpen is not newly unlocked', () {
      final result = newlyUnlocked(catalogue, 8, 6);
      expect(result.map((g) => g.kind), isNot(contains(GameKind.tictactoe)));
    });

    test('a game still above her current age never shows, unlocked or not', () {
      final result = newlyUnlocked(catalogue, 5, 2);
      expect(result.map((g) => g.kind), isNot(contains(GameKind.twoTruths)));
    });

    test('no age crossed since last open returns nothing', () {
      expect(newlyUnlocked(catalogue, 6, 6), isEmpty);
    });
  });

  group('randomGame — never the one she just left', () {
    test('returns a game she can play', () {
      final g = randomGame(catalogue, 6, null, pick: () => 0.5);
      expect(g, isNotNull);
      expect(g!.minAge, lessThanOrEqualTo(6));
    });

    test('deterministic pick drives the choice', () {
      final poolAt8 = catalogue.where((g) => g.minAge <= 8).toList();
      final g = randomGame(catalogue, 8, null, pick: () => 0);
      expect(g!.kind, poolAt8.first.kind);
    });

    test('two hundred draws never repeat the excluded kind', () {
      final first = randomGame(catalogue, 6, null, pick: () => 0)!;
      var repeats = 0;
      for (var i = 0; i < 200; i++) {
        final g = randomGame(catalogue, 6, first.kind);
        if (g?.kind == first.kind) repeats++;
      }
      expect(repeats, 0);
    });

    test('pick at the very top of the range is clamped inside the pool, never null', () {
      expect(randomGame(catalogue, 8, null, pick: () => 0.999999), isNotNull);
    });

    test('below the youngest floor there is honestly nothing, not a crash', () {
      expect(randomGame(catalogue, 1, null), isNull);
    });

    test('no default pick argument still returns a real catalogue game (math.Random path)', () {
      final g = randomGame(catalogue, 8, null);
      expect(catalogue.map((c) => c.kind), contains(g!.kind));
    });
  });

  group('P2 — nothing here carries a count, order, or streak', () {
    test('a favourite is a bare kind string', () {
      expect(star(<String>[], 'chess'), isA<List<String>>());
      expect(star(<String>[], 'chess').first, isA<String>());
    });
  });
}
