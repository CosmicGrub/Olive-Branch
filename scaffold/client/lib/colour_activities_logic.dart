// OLIVE BRANCH — her colour: the rules of the four colour activities. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline). MASTERFILE §8.6.5, P2, §21.
//
// Pure Dart, no widgets, so every rule is testable and nothing about a screen
// can quietly add a score. What these four have in common, on purpose:
//   - NO scores, streaks, timers, levels shown, rewards or counters (P2). There
//     is nothing here that could be added up, and the result types carry no
//     number that could be shown to her as a tally.
//   - Nothing fails. A wrong basket wobbles back; a rock stops the fox gently;
//     an empty garden is a fine garden. Messages never say "wrong" or "try
//     again".
//   - They grow up with her (§21): Path code from 5, its repeat block and Pixel
//     garden from 8. A guardian can switch both coding activities off. An
//     activity only ever OPENS at its age; none closes again (there is no upper
//     age: the standing rule is to keep the early bands and unlock more as she
//     grows, so a nine-year-old still has Colour sort if she likes it).
import 'colour_foods.dart';

// ============================================================ the catalogue ==
class ColourActivity {
  const ColourActivity(this.id, this.name, this.kind, this.minAge, {this.coding = false});
  final String id;
  final String name;
  /// 'Learn' | 'Code' | 'Design'
  final String kind;
  /// The age it opens at. There is no age it closes at.
  final int minAge;
  /// Switched off by the guardian's "coding activities" toggle.
  final bool coding;
}

const List<ColourActivity> colourActivities = [
  ColourActivity('sort', 'Colour sort', 'Learn', 3),
  ColourActivity('path', 'Path code', 'Code', 5, coding: true),
  ColourActivity('critter', 'Colour critter', 'Design', 3),
  ColourActivity('pixel', 'Pixel garden', 'Code', 8, coding: true),
];

/// Pixel garden and the repeat block open at 8 and cannot be opened earlier.
const int pixelGardenMinAge = 8;
const int repeatBlockMinAge = 8;

bool repeatUnlocked(int age) => age >= repeatBlockMinAge;

/// What she sees for her age and her guardian's coding toggle.
List<ColourActivity> activitiesFor({required int age, required bool codeActivities}) => [
  for (final a in colourActivities)
    if (age >= a.minAge && (codeActivities || !a.coding)) a,
];

// ================================================================ colour sort ==
class SortRound {
  SortRound(this.items);

  final List<FoodItem> items;
  /// item index -> the basket it is in.
  final Map<int, String> placed = {};
  int? selected;
  String message = 'Tap a picture, then a basket.';
  /// The right basket, softly glowing after a miss. Null otherwise.
  String? glow;

  List<int> get remaining => [for (var i = 0; i < items.length; i++) if (!placed.containsKey(i)) i];
  bool get allSorted => items.isNotEmpty && placed.length == items.length;

  /// Groups that actually have something in them this round.
  List<String> get baskets => [for (final g in foodGroups) if (items.any((i) => i.group == g)) g];

  void pick(int i) {
    if (placed.containsKey(i)) return;
    selected = i;
    glow = null;
    message = 'Now tap a basket.';
  }

  /// Returns true if it went in. A miss wobbles back with no sound and no mark.
  bool put(String group) {
    final s = selected;
    if (s == null) {
      message = 'Tap a picture first.';
      return false;
    }
    final item = items[s];
    if (item.group == group) {
      placed[s] = group;
      selected = null;
      glow = null;
      message = 'Yes! ${item.spoken} goes with ${foodGroupLabels[group]!.toLowerCase()}.';
      if (allSorted) message = 'All sorted.';
      return true;
    }
    glow = item.group;
    message = 'Not quite. Let’s find another basket.';
    return false;
  }

  /// The one line a guardian may see afterwards: what she did, never how well.
  String get guardianLine => 'sorted fruit, vegetables and animals';
}

// ================================================================== path code ==
enum Dir { up, down, left, right }

typedef Cell = (int, int);

Cell step(Cell c, Dir d) => switch (d) {
  Dir.up => (c.$1, c.$2 - 1),
  Dir.down => (c.$1, c.$2 + 1),
  Dir.left => (c.$1 - 1, c.$2),
  Dir.right => (c.$1 + 1, c.$2),
};

class PathBlock {
  const PathBlock(this.dir, {this.repeat = 1});
  final Dir dir;
  /// 1 = a plain arrow; 2..4 = the repeat block, unlocked at 8.
  final int repeat;
  PathBlock withRepeat(int r) => PathBlock(dir, repeat: r);
}

class PathLevel {
  const PathLevel({required this.size, required this.start, required this.goal,
    this.rocks = const {}, this.maxBlocks = 10});
  final int size;
  final Cell start;
  final Cell goal;
  final Set<Cell> rocks;
  final int maxBlocks;
}

const List<PathLevel> pathLevels = [
  PathLevel(size: 4, start: (0, 2), goal: (3, 2), maxBlocks: 6),
  PathLevel(size: 4, start: (0, 3), goal: (3, 0), rocks: {(1, 1), (2, 2)}, maxBlocks: 8),
  PathLevel(size: 5, start: (0, 4), goal: (4, 0), rocks: {(2, 4), (1, 2), (3, 1)}, maxBlocks: 10),
];

class PathRun {
  const PathRun(this.positions, this.end);
  /// Every cell the hero stands on, in order, starting where it started.
  final List<Cell> positions;
  /// 'reached' | 'rock' | 'edge' | 'short'. None of these is a failure: the
  /// blocks stay on screen so she can change one.
  final String end;
  bool get reached => end == 'reached';
}

/// Expands repeat blocks into single moves, in order.
List<Dir> expand(List<PathBlock> program) =>
    [for (final b in program) for (var i = 0; i < b.repeat; i++) b.dir];

/// Runs the program one step at a time. A rock or the edge stops the hero
/// gently where it stands; reaching the food ends the run at once.
PathRun runProgram(PathLevel level, List<PathBlock> program) {
  var at = level.start;
  final seen = <Cell>[at];
  for (final d in expand(program)) {
    final next = step(at, d);
    final off = next.$1 < 0 || next.$2 < 0 || next.$1 >= level.size || next.$2 >= level.size;
    if (off) return PathRun(seen, 'edge');
    if (level.rocks.contains(next)) return PathRun(seen, 'rock');
    at = next;
    seen.add(at);
    if (at == level.goal) return PathRun(seen, 'reached');
  }
  return PathRun(seen, at == level.goal ? 'reached' : 'short');
}

/// True if some program of at most [PathLevel.maxBlocks] plain arrows reaches
/// the food. Used by the tests to hold every level to "solvable".
bool levelSolvable(PathLevel level) {
  final seen = <Cell>{level.start};
  var frontier = <Cell>[level.start];
  var depth = 0;
  while (frontier.isNotEmpty && depth < level.maxBlocks) {
    final next = <Cell>[];
    for (final c in frontier) {
      for (final d in Dir.values) {
        final n = step(c, d);
        if (n.$1 < 0 || n.$2 < 0 || n.$1 >= level.size || n.$2 >= level.size) continue;
        if (level.rocks.contains(n) || !seen.add(n)) continue;
        if (n == level.goal) return true;
        next.add(n);
      }
    }
    frontier = next;
    depth++;
  }
  return false;
}

/// The saved picture of a finished program is the arrows, nothing else.
String programArrows(List<PathBlock> program) {
  const glyph = {Dir.up: '↑', Dir.down: '↓', Dir.left: '←', Dir.right: '→'};
  return program.map((b) => b.repeat == 1 ? glyph[b.dir]! : '${glyph[b.dir]}×${b.repeat}').join(' ');
}

// ============================================================ colour critter ==
/// A line drawing she fills one part at a time with today's colour, a lighter
/// tint or a darker tint. Undo is one tap. Nothing can go wrong.
class CritterDrawing {
  CritterDrawing(this.recipe);
  final String recipe;
  /// region index -> tint (0 light, 1 colour, 2 dark).
  final Map<int, int> fills = {};
  final List<(int, int?)> _history = [];

  void fill(int region, int tint) {
    _history.add((region, fills[region]));
    fills[region] = tint;
  }

  bool get canUndo => _history.isNotEmpty;

  void undo() {
    if (_history.isEmpty) return;
    final (region, before) = _history.removeLast();
    if (before == null) {
      fills.remove(region);
    } else {
      fills[region] = before;
    }
  }

  void clear() {
    fills.clear();
    _history.clear();
  }
}

// ============================================================== pixel garden ==
/// An 8 by 8 garden. A tint is 1 (light), 2 (colour) or 3 (dark); 0 is empty.
class Garden {
  const Garden(this.cells, {this.mirror = false});
  static const int size = 8;
  factory Garden.empty({bool mirror = false}) => Garden(List<int>.filled(size * size, 0), mirror: mirror);

  final List<int> cells;
  /// Each tap is copied across the middle, which teaches symmetry.
  final bool mirror;

  int at(int x, int y) => cells[y * size + x];

  Garden withMirror(bool m) => Garden(cells, mirror: m);

  /// Plant a tint; planting the same tint again lifts it (a gentle toggle).
  Garden plant(int x, int y, int tint) {
    if (x < 0 || y < 0 || x >= size || y >= size || tint < 1 || tint > 3) return this;
    final next = List<int>.of(cells);
    final value = at(x, y) == tint ? 0 : tint;
    next[y * size + x] = value;
    if (mirror) next[y * size + (size - 1 - x)] = value;
    return Garden(next, mirror: mirror);
  }

  /// The repeat stamp: copies the first [length] cells of row [y] along the
  /// rest of the row. Unlocked at 8, like the repeat block in Path code.
  Garden repeatRow(int y, int length) {
    if (y < 0 || y >= size || length < 1 || length >= size) return this;
    final next = List<int>.of(cells);
    for (var x = length; x < size; x++) {
      next[y * size + x] = next[y * size + (x % length)];
    }
    return Garden(next, mirror: mirror);
  }

  Garden cleared() => Garden.empty(mirror: mirror);

  bool get isEmpty => cells.every((c) => c == 0);

  /// What a guardian may see: that she made one, never how much of it.
  String get guardianLine => 'made a pixel picture';
}
