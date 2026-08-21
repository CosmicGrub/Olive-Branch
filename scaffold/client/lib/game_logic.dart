// OLIVE BRANCH — game hub & handicap, ported rules. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.2, P2.
//
// A scoped port of packages/games/src/games.ts — CATALOGUE, forAge(), the
// handicap functions, and the losing-streak trigger — kept close to the TS
// names and shapes, the same discipline lock_controller.dart already applies
// porting packages/child-lock/src/lock.ts.
//
// NOT ported here: GameState / play() / takeBack() / childView(). Those are
// the per-game move engines (tic-tac-toe, dots-and-boxes, memory, story) —
// this group's assignment is the game hub (picker) and the handicap surface
// only, not any individual board. (Compare game_checkers.dart, which ports
// its own CkSide/CheckersState independently rather than sharing this file —
// each screen's group ports only what it needs, self-contained, so 14
// parallel groups never collide on a shared module.)
//
// One consequence of that narrowing: games.ts's `setHandicap()` takes and
// returns a full `GameState` (so it can also apply the handicap's mechanical
// side effects — e.g. `start_behind` pre-loading the parent's score). This
// port has no GameState to mutate, so `setHandicap()` here is trimmed to
// exactly the validation shape the picker/handicap screens need — refuse a
// non-child `bySide`, refuse an id that isn't in that game's catalogue entry,
// otherwise accept — leaving the mechanical side effects to whichever
// screen actually holds the board.
//
// §9.2's constitutional line for this file: HANDICAP IS SET BY THE CHILD, and
// the type refuses a parent handicapping themselves — not a UI convention,
// enforced in `setHandicap()` itself, unconditionally, before the id is even
// looked at. P2 governs the catalogue and the losing-streak trigger: no win
// count, no rank, no streak number is ever exposed by anything in this file.

/// A = child, B = parent, always. Mirrors games.ts's `Side`.
enum Side { a, b }

enum GameKind {
  tictactoe, dotsboxes, memory, story, drawTogether, guessDoodle,
  sillySentence, wouldYouRather, twoTruths, twentyQuestions,
  copyPattern, findIt,
}

/// One condition the child may impose on the parent for a given game.
class Handicap {
  const Handicap(this.id, this.label);
  final String id;
  final String label;
}

class GameMeta {
  const GameMeta({
    required this.kind,
    required this.title,
    required this.minAge,
    required this.competitive,
    required this.handicaps,
    required this.blurb,
  });
  final GameKind kind;
  final String title;
  final int minAge;
  final bool competitive;
  /// Handicaps the CHILD may impose on the parent. Empty for co-op games —
  /// there is nothing to be behind at.
  final List<Handicap> handicaps;
  final String blurb;
}

/// 1:1 with games.ts's `CATALOGUE`.
const List<GameMeta> catalogue = [
  GameMeta(
    kind: GameKind.tictactoe,
    title: 'Three in a row',
    minAge: 4,
    competitive: true,
    blurb: 'A five-year-old can genuinely win this one.',
    handicaps: [
      Handicap('no_centre', "Dad can't use the middle square"),
      Handicap('child_first', 'I always go first'),
    ],
  ),
  GameMeta(
    kind: GameKind.dotsboxes,
    title: 'Dots and boxes',
    minAge: 5,
    competitive: true,
    blurb: 'Simplest rules of any deep game.',
    handicaps: [
      Handicap('start_behind', 'Dad starts two boxes behind'),
      Handicap('child_first', 'I always go first'),
    ],
  ),
  GameMeta(
    kind: GameKind.memory,
    title: 'Our photos',
    minAge: 4,
    competitive: true,
    blurb: 'Made from your own photos, not stock pictures.',
    handicaps: [
      Handicap('extra_pairs', 'Dad needs two more pairs than me'),
    ],
  ),
  // Co-op. No handicap, because there is nothing to be behind at.
  GameMeta(
    kind: GameKind.story,
    title: 'Make up a story',
    minAge: 5,
    competitive: false,
    blurb: 'One line each. Nobody wins.',
    handicaps: [],
  ),
  // Batch A (Play Together phase 1) — both reuse annotation_canvas.dart's
  // AnnotationCanvas, both co-op, both carry no handicap for the same reason
  // 'story' does: nothing to be behind at.
  GameMeta(
    kind: GameKind.drawTogether,
    title: 'Draw together',
    minAge: 4,
    competitive: false,
    blurb: 'One shared page. Draw whatever you like.',
    handicaps: [],
  ),
  GameMeta(
    kind: GameKind.guessDoodle,
    title: 'Guess the doodle',
    minAge: 5,
    competitive: false,
    blurb: 'One of you draws it, the other guesses.',
    handicaps: [],
  ),
  // Batch B (Play Together phase 1) — four curated-prompt activities, all
  // in the same co-op shape as 'story'/'drawTogether'/'guessDoodle': a
  // fixed, in-repo, curated content bank instead of free text, no handicap
  // because there is nothing to be behind at. See game_curated_activity.dart
  // for the shared layout base all four use, and each game file's own
  // header for its curated content and (for game_two_truths.dart) the
  // safe-content design reasoning the spec singled out by name.
  GameMeta(
    kind: GameKind.sillySentence,
    title: 'Silly sentence maker',
    minAge: 4,
    competitive: false,
    blurb: 'Build the silliest sentence you can, one word at a time.',
    handicaps: [],
  ),
  GameMeta(
    kind: GameKind.wouldYouRather,
    title: 'Would you rather',
    minAge: 4,
    competitive: false,
    blurb: 'Impossible choices, no wrong answers.',
    handicaps: [],
  ),
  GameMeta(
    kind: GameKind.twoTruths,
    title: 'Two truths and a tall tale',
    minAge: 6,
    competitive: false,
    blurb: 'Two are true. Can she guess the made-up one?',
    handicaps: [],
  ),
  GameMeta(
    kind: GameKind.twentyQuestions,
    title: '20 questions',
    minAge: 5,
    competitive: false,
    blurb: 'Yes, no, and a secret only one of you knows.',
    handicaps: [],
  ),
  // Batch C (Play Together phase 1, the closing batch) — two younger-age,
  // icon/color/shape-based activities, minAge 2, in exactly 'story's own
  // co-op shape: competitive: false, handicaps: [] — self-scaling
  // difficulty (a growing pattern length; a curated scene's own fixed
  // object count) means there is nothing for a parent-set handicap to
  // apply to, the same reasoning every other Batch A/B entry above already
  // states. See game_copy_pattern.dart / game_find_it.dart for the real,
  // curated content and the zero-text-gameplay mechanism both rest on.
  GameMeta(
    kind: GameKind.copyPattern,
    title: 'Copy the pattern',
    minAge: 2,
    competitive: false,
    blurb: 'Watch it light up, then tap it back — it grows one more every time.',
    handicaps: [],
  ),
  GameMeta(
    kind: GameKind.findIt,
    title: 'Find it',
    minAge: 2,
    competitive: false,
    blurb: 'A picture full of little things to spot — point, and she taps it.',
    handicaps: [],
  ),
];

GameMeta catalogueFor(GameKind kind) => catalogue.firstWhere((m) => m.kind == kind);

/// Mirrors games.ts's `forAge` — gates which games render; a younger child
/// sees fewer boards, never a harder version of the same one.
List<GameMeta> forAge(int age) => catalogue.where((g) => age >= g.minAge).toList();

// ------------------------------------------------------------ handicap -----

/// Refusal reasons a caller can act on. Mirrors games.ts's `setHandicap`
/// return shape (`'child_only' | 'unknown'`).
enum HandicapRefusal { childOnly, unknown }

class SetHandicapResult {
  const SetHandicapResult._(this.handicapId, this.refusal);
  const SetHandicapResult.ok(String? handicapId) : this._(handicapId, null);
  const SetHandicapResult.refused(HandicapRefusal reason) : this._(null, reason);

  final String? handicapId;
  final HandicapRefusal? refusal;
  bool get ok => refusal == null;
}

/// §9.2 — only the child may set a handicap, and only on the parent. A parent
/// quietly handicapping themselves is charity; the child imposing a condition
/// is a different transaction, and this refuses the first outright and
/// unconditionally — before the id is even checked, so a parent asking to
/// *clear* a handicap is refused exactly the same way as one asking to set
/// one.
SetHandicapResult setHandicap({
  required Side bySide,
  required GameKind kind,
  required String? handicapId,
}) {
  if (bySide != Side.a) return const SetHandicapResult.refused(HandicapRefusal.childOnly);
  if (handicapId != null && !catalogueFor(kind).handicaps.any((h) => h.id == handicapId)) {
    return const SetHandicapResult.refused(HandicapRefusal.unknown);
  }
  return SetHandicapResult.ok(handicapId);
}

/// Shown to both. Never "Dad is worse"; always "Dad is playing the hard way".
/// Returns null when no handicap is active.
String? handicapBanner(GameKind kind, String? handicapId) {
  if (handicapId == null) return null;
  for (final h in catalogueFor(kind).handicaps) {
    if (h.id == handicapId) return "Dad's playing the hard way — ${h.label.toLowerCase()}";
  }
  return null;
}

// -------------------------------------------------- the losing streak ------
/// A parent who always wins is a harm the product created, so the handicap
/// prompt SURFACES ITSELF rather than waiting to be found. The record exists
/// only to decide when to offer — nothing in this file, or in
/// handicap_screen.dart, ever renders it.
const streakBeforeOffer = 3;

/// Outcome of one finished game, from the shared record. `null` (a game
/// still in progress) never counts toward the streak.
enum GameOutcome { a, b, draw, done }

/// Mirrors games.ts's `shouldOfferHandicap`: true only when the last
/// [streakBeforeOffer] *decided* games (draws/co-op "done" outcomes don't
/// count either way) were all parent wins, for a competitive game.
bool shouldOfferHandicap(List<GameOutcome?> recentOutcomes, GameKind kind) {
  if (!catalogueFor(kind).competitive) return false;
  final decided = recentOutcomes.where((o) => o == GameOutcome.a || o == GameOutcome.b).toList();
  final last = decided.length > streakBeforeOffer
      ? decided.sublist(decided.length - streakBeforeOffer)
      : decided;
  return last.length == streakBeforeOffer && last.every((o) => o == GameOutcome.b);
}

class HandicapOffer {
  const HandicapOffer(this.prompt, this.options);
  final String prompt;
  final List<Handicap> options;
}

/// Mirrors games.ts's `handicapOffer`. Her choice, her framing — never
/// "you keep losing".
HandicapOffer handicapOffer(GameKind kind) => HandicapOffer(
      'Want to make it harder for Dad?',
      catalogueFor(kind).handicaps,
    );
