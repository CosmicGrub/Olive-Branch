// OLIVE BRANCH — the rules of the four colour activities, and the food
// inventory behind them. P2: nothing here can be added up.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_activities_logic.dart';
import 'package:olive_client/colour_foods.dart';
import 'package:olive_client/palette_logic.dart';

void main() {
  group('the catalogue grows up with her', () {
    List<String> ids(int age, {bool code = true}) =>
        [for (final a in activitiesFor(age: age, codeActivities: code)) a.id];

    test('a 3-year-old gets sorting and colouring only', () => expect(ids(3), ['sort', 'critter']));
    test('a 5-year-old gains Path code', () => expect(ids(5), ['sort', 'path', 'critter']));
    test('a 7-year-old has no pixel garden', () => expect(ids(7).contains('pixel'), isFalse));
    test('nothing closes as she grows: every early activity is still there at 9, 12 and 17', () {
      for (final age in [9, 10, 12, 13, 17]) {
        expect(ids(age), containsAll(['sort', 'path', 'critter', 'pixel']), reason: 'age $age');
      }
    });
    test('an activity opens at its age and has no age it closes at', () {
      for (final a in colourActivities) {
        expect(activitiesFor(age: a.minAge, codeActivities: true).map((x) => x.id), contains(a.id));
        expect(activitiesFor(age: a.minAge - 1, codeActivities: true).map((x) => x.id), isNot(contains(a.id)));
      }
    });
    test('an 8-year-old gets the pixel garden', () => expect(ids(8).contains('pixel'), isTrue));
    test('the guardian can switch both coding activities off', () {
      expect(ids(8, code: false), isNot(contains('path')));
      expect(ids(8, code: false), isNot(contains('pixel')));
      expect(ids(8, code: false), contains('critter'));
    });
    test('pixel garden and the repeat block both open at exactly 8', () {
      expect(pixelGardenMinAge, 8);
      expect(repeatUnlocked(7), isFalse);
      expect(repeatUnlocked(8), isTrue);
    });
    test('four activities, each with a name a child can read', () {
      expect(colourActivities.length, 4);
      expect(colourActivities.map((a) => a.name), ['Colour sort', 'Path code', 'Colour critter', 'Pixel garden']);
    });
  });

  group('the food inventory', () {
    test('every one of the twelve colours has something', () {
      for (final s in palette) {
        expect(foodsFor(s.id), isNotEmpty, reason: s.id);
      }
    });
    test('storm grey has no fruit, and says so by leaning on animals', () {
      expect(foodsFor('storm').where((i) => i.group == 'fruit'), isEmpty);
      expect(foodsFor('storm').where((i) => i.group == 'animals'), isNotEmpty);
    });
    test('a storybook item is named as pretend, never passed off as real', () {
      final purple = foodsFor('grape').firstWhere((i) => !i.real);
      expect(purple.spoken, startsWith('a pretend '));
      expect(foodsFor('sea').firstWhere((i) => i.name == 'Whale').spoken, 'Whale');
    });
    test('the sorting pool is at most nine and drawn from every group present', () {
      for (final s in palette) {
        final pool = sortPool(s.id);
        expect(pool.length, lessThanOrEqualTo(9), reason: s.id);
      }
      expect({for (final i in sortPool('sea')) i.group}, {'fruit', 'veg', 'animals'});
    });
    test('a group can be left out', () {
      expect(sortPool('sea', groups: const ['animals']).every((i) => i.group == 'animals'), isTrue);
    });
    test('Path code always finds a hero and a goal', () {
      for (final s in palette) {
        expect(pathHero(s.id).group, 'animals');
        expect(pathGoal(s.id).group, isNot('animals'));
      }
    });
  });

  group('Colour sort', () {
    test('right basket: it goes in, and says so', () {
      final r = SortRound(sortPool('sea'));
      r.pick(0);
      expect(r.put(r.items[0].group), isTrue);
      expect(r.placed[0], r.items[0].group);
      expect(r.message, startsWith('Yes!'));
    });
    test('wrong basket: nothing is placed, no buzzer words, and the right one glows', () {
      final r = SortRound(sortPool('sea'));
      r.pick(0);
      final wrong = r.baskets.firstWhere((b) => b != r.items[0].group);
      expect(r.put(wrong), isFalse);
      expect(r.placed, isEmpty);
      expect(r.glow, r.items[0].group);
      expect(r.message, isNot(matches(RegExp('wrong|incorrect|try again|fail', caseSensitive: false))));
    });
    test('a basket with no picture chosen asks for one', () {
      final r = SortRound(sortPool('sea'));
      expect(r.put('fruit'), isFalse);
      expect(r.message, 'Tap a picture first.');
    });
    test('everything sorted ends quietly', () {
      final r = SortRound(sortPool('sea'));
      for (var i = 0; i < r.items.length; i++) {
        r.pick(i);
        r.put(r.items[i].group);
      }
      expect(r.allSorted, isTrue);
      expect(r.message, 'All sorted.');
      expect(r.remaining, isEmpty);
    });
    test('a guardian is told what she did, never how well', () {
      expect(SortRound(sortPool('sea')).guardianLine, 'sorted fruit, vegetables and animals');
    });
  });

  group('Path code', () {
    test('every level can be solved', () {
      for (final l in pathLevels) {
        expect(levelSolvable(l), isTrue);
      }
    });
    test('the plain route reaches the food', () {
      final r = runProgram(pathLevels[0], const [PathBlock(Dir.right), PathBlock(Dir.right), PathBlock(Dir.right)]);
      expect(r.reached, isTrue);
      expect(r.positions.last, (3, 2));
    });
    test('a rock stops the hero where it stands, gently', () {
      final r = runProgram(pathLevels[1], const [PathBlock(Dir.up), PathBlock(Dir.up), PathBlock(Dir.right)]);
      expect(r.end, 'rock');
      final r2 = runProgram(pathLevels[1], const [PathBlock(Dir.up), PathBlock(Dir.up), PathBlock(Dir.right)]);
      expect(r2.end, 'rock');
      expect(r2.positions.last, (0, 1));
    });
    test('the edge does not hurt either', () {
      expect(runProgram(pathLevels[0], const [PathBlock(Dir.left)]).end, 'edge');
    });
    test('a short program is just short', () {
      expect(runProgram(pathLevels[0], const [PathBlock(Dir.right)]).end, 'short');
    });
    test('the repeat block runs its arrow that many times', () {
      final r = runProgram(pathLevels[0], const [PathBlock(Dir.right, repeat: 3)]);
      expect(r.reached, isTrue);
      expect(expand(const [PathBlock(Dir.up, repeat: 2), PathBlock(Dir.left)]), [Dir.up, Dir.up, Dir.left]);
    });
    test('the run stops the moment it reaches the food', () {
      final r = runProgram(pathLevels[0], const [PathBlock(Dir.right, repeat: 4)]);
      expect(r.reached, isTrue);
      expect(r.positions.length, 4);
    });
    test('the saved picture is the arrows and nothing else', () {
      expect(programArrows(const [PathBlock(Dir.up), PathBlock(Dir.right, repeat: 2)]), '↑ →×2');
    });
    test('no run result carries a number to show her', () {
      final r = runProgram(pathLevels[0], const []);
      expect(r.end, 'short');
    });
  });

  group('Colour critter', () {
    test('fill, then undo restores the earlier tint', () {
      final d = CritterDrawing('fox');
      d.fill(3, 1);
      d.fill(3, 2);
      expect(d.fills[3], 2);
      d.undo();
      expect(d.fills[3], 1);
      d.undo();
      expect(d.fills.containsKey(3), isFalse);
      expect(d.canUndo, isFalse);
      d.undo(); // nothing to undo: no error
    });
    test('clear empties the drawing', () {
      final d = CritterDrawing('fox')..fill(1, 0);
      d.clear();
      expect(d.fills, isEmpty);
      expect(d.canUndo, isFalse);
    });
  });

  group('Pixel garden', () {
    test('an empty garden is a fine garden', () => expect(Garden.empty().isEmpty, isTrue));
    test('planting sets a square; planting the same tint again lifts it', () {
      var g = Garden.empty().plant(2, 3, 2);
      expect(g.at(2, 3), 2);
      g = g.plant(2, 3, 2);
      expect(g.at(2, 3), 0);
    });
    test('mirror copies the tap across the middle', () {
      final g = Garden.empty(mirror: true).plant(1, 4, 3);
      expect(g.at(1, 4), 3);
      expect(g.at(6, 4), 3);
    });
    test('the repeat stamp copies a pattern along the row', () {
      var g = Garden.empty().plant(0, 0, 1).plant(1, 0, 3);
      g = g.repeatRow(0, 2);
      expect([for (var x = 0; x < 8; x++) g.at(x, 0)], [1, 3, 1, 3, 1, 3, 1, 3]);
    });
    test('out-of-range taps and tints change nothing', () {
      final g = Garden.empty();
      expect(identical(g.plant(8, 0, 1), g), isTrue);
      expect(identical(g.plant(0, 0, 4), g), isTrue);
      expect(identical(g.repeatRow(0, 8), g), isTrue);
    });
    test('clear keeps the mirror switch; a guardian line carries no amount', () {
      final g = Garden.empty(mirror: true).plant(0, 0, 1).cleared();
      expect(g.isEmpty, isTrue);
      expect(g.mirror, isTrue);
      expect(g.guardianLine, 'made a pixel picture');
    });
  });
}
