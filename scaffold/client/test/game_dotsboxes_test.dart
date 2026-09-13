// OLIVE BRANCH — game_dotsboxes.dart tests. MASTERFILE §9.2, P2.
//
// Same split as game_chess_test.dart/game_checkers_test.dart: the rules
// engine (box-completion cascades granting an extra turn, take-back
// correctly restoring whose turn it is even across a box-completing move,
// and setHandicap's mid-game side effects) exercised directly against the
// ported functions, then the screen itself against the same §9.2/P2
// invariants those files hold their own screens to.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_dotsboxes.dart';
import 'package:olive_client/game_logic.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// Builds a state with [filled] boxes already claimed (round-robin between
/// A and B) and only [target] left open — a direct-construction technique
/// for targeted engine tests, the same one game_chess_test.dart's
/// `_positionOf` uses for hand-built positions. `claimBoxes` skips any box
/// whose `owner` is already non-null, so the surrounding edges of the
/// ALREADY-claimed boxes never need to be filled in for this to be valid —
/// only the target box's own four edges matter.
DbState _almostFull(int nOwnedByA, int nOwnedByB, (int, int) target, {Side turn = Side.a}) {
  const n = 4;
  final owner = List.generate(n - 1, (_) => List<Side?>.filled(n - 1, null));
  var remainingA = nOwnedByA, remainingB = nOwnedByB;
  for (var r = 0; r < n - 1; r++) {
    for (var c = 0; c < n - 1; c++) {
      if ((r, c) == target) continue;
      if (remainingA > 0) { owner[r][c] = Side.a; remainingA--; }
      else if (remainingB > 0) { owner[r][c] = Side.b; remainingB--; }
    }
  }
  final h = List.generate(n, (_) => List<Side?>.filled(n - 1, null));
  final v = List.generate(n - 1, (_) => List<Side?>.filled(n, null));
  final (tr, tc) = target;
  // Top, left, and bottom of the target box are already drawn; its right
  // edge (v[tr][tc + 1]) is deliberately left open for the test's own final
  // move to supply.
  h[tr][tc] = Side.a;
  v[tr][tc] = Side.a;
  h[tr + 1][tc] = Side.a;
  return DbState(
    n: n, h: h, v: v, owner: owner, turn: turn, moves: const [],
    scores: {Side.a: nOwnedByA, Side.b: nOwnedByB}, outcome: null, handicap: null,
  );
}

void main() {
  group('dots-and-boxes engine — real rules (§9.2)', () {
    test('newDotsAndBoxes: a 3x3-box board, empty, child moves first, no handicap', () {
      final s = newDotsAndBoxes();
      expect(s.n, 4);
      expect(s.h.length, 4);
      expect(s.h[0].length, 3);
      expect(s.v.length, 3);
      expect(s.v[0].length, 4);
      expect(s.owner.length, 3);
      expect(s.owner[0].length, 3);
      expect(s.turn, Side.a);
      expect(s.scores, {Side.a: 0, Side.b: 0});
      expect(s.outcome, isNull);
      expect(dbLegalMoves(s).length, 24, reason: '12 horizontal + 12 vertical edges at the start');
    });

    test('a move with no completed box simply passes the turn', () {
      final r = dbPlay(newDotsAndBoxes(), Side.a, EdgeKind.h, 0, 0);
      expect(r.ok, isTrue);
      expect(r.state!.turn, Side.b);
      expect(r.state!.scores[Side.a], 0);
    });

    test('completing a box grants the SAME side another move — the cascade rule', () {
      var s = newDotsAndBoxes();
      s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!; // top
      s = dbPlay(s, Side.b, EdgeKind.h, 1, 0).state!; // bottom
      s = dbPlay(s, Side.a, EdgeKind.v, 0, 0).state!; // left
      expect(s.turn, Side.b);
      final r = dbPlay(s, Side.b, EdgeKind.v, 0, 1); // right — completes box (0,0)
      expect(r.ok, isTrue);
      final after = r.state!;
      expect(after.owner[0][0], Side.b);
      expect(after.scores[Side.b], 1);
      expect(after.turn, Side.b, reason: 'completing a box earns another move, the turn does not pass');
    });

    test('one edge can complete two boxes at once (a "double-cross"), scoring both', () {
      var s = newDotsAndBoxes();
      // Box (0,0): top/bottom/left already drawn, missing only the shared
      // edge v[0][1]. Box (0,1): top/bottom/right already drawn, missing
      // the SAME shared edge.
      s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!;
      s = dbPlay(s, Side.b, EdgeKind.h, 1, 0).state!;
      s = dbPlay(s, Side.a, EdgeKind.v, 0, 0).state!;
      s = dbPlay(s, Side.b, EdgeKind.h, 0, 1).state!;
      s = dbPlay(s, Side.a, EdgeKind.h, 1, 1).state!;
      s = dbPlay(s, Side.b, EdgeKind.v, 0, 2).state!;
      expect(s.turn, Side.a);
      final r = dbPlay(s, Side.a, EdgeKind.v, 0, 1); // completes BOTH boxes at once
      expect(r.ok, isTrue);
      expect(r.state!.owner[0][0], Side.a);
      expect(r.state!.owner[0][1], Side.a);
      expect(r.state!.scores[Side.a], 2);
      expect(r.state!.turn, Side.a, reason: 'still an extra turn after claiming two at once');
    });

    test('the child wins when the board fills with more boxes than the parent', () {
      final s = _almostFull(4, 4, (2, 2));
      final r = dbPlay(s, Side.a, EdgeKind.v, 2, 3); // the last edge closes box (2,2) for A
      expect(r.ok, isTrue);
      expect(r.state!.owner[2][2], Side.a);
      expect(r.state!.scores, {Side.a: 5, Side.b: 4});
      expect(r.state!.outcome, DbOutcome.childWin);
    });

    test('the parent wins the same way, symmetrically — this is not a child-only check', () {
      final s = _almostFull(3, 5, (2, 2), turn: Side.b);
      final r = dbPlay(s, Side.b, EdgeKind.v, 2, 3);
      expect(r.ok, isTrue);
      expect(r.state!.scores, {Side.a: 3, Side.b: 6});
      expect(r.state!.outcome, DbOutcome.parentWin);
    });

    test('the turn still flips on the game-ending move even though a box was just claimed — ported '
        'bug-for-bug from games.ts\'s own play(), harmless because outcome is already set', () {
      final s = _almostFull(4, 4, (2, 2));
      final r = dbPlay(s, Side.a, EdgeKind.v, 2, 3);
      expect(r.ok, isTrue);
      expect(r.state!.outcome, isNotNull);
      expect(r.state!.turn, Side.b, reason: "flips to B even though A just claimed the final box");
    });

    test('occupied, out-of-range, wrong turn, and game-over are all refused', () {
      var s = newDotsAndBoxes();
      s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!;
      expect(dbPlay(s, Side.b, EdgeKind.h, 0, 0).reason, 'occupied');
      expect(dbPlay(s, Side.b, EdgeKind.h, 4, 0).reason, 'out_of_range'); // h has only 4 rows (0-3)
      expect(dbPlay(s, Side.b, EdgeKind.v, 0, 4).reason, 'out_of_range'); // v has only 4 cols (0-3)
      expect(dbPlay(s, Side.a, EdgeKind.h, 0, 1).reason, 'not_your_turn');
      final finished = _almostFull(4, 4, (2, 2));
      final done = dbPlay(finished, Side.a, EdgeKind.v, 2, 3).state!;
      expect(dbPlay(done, Side.b, EdgeKind.h, 3, 0).reason, 'game_over');
    });

    group('setHandicap — §9.2 child-only, applied to the CURRENT state', () {
      test('refuses a parent handicapping themselves', () {
        final r = dbSetHandicap(newDotsAndBoxes(), Side.b, 'start_behind');
        expect(r.ok, isFalse);
        expect(r.refusal, 'child_only');
      });

      test('refuses a handicap id that does not belong to dots-and-boxes', () {
        final r = dbSetHandicap(newDotsAndBoxes(), Side.a, 'no_centre');
        expect(r.ok, isFalse);
        expect(r.refusal, 'unknown');
      });

      test('start_behind pre-loads the CHILD two boxes ahead — ported exactly as games.ts wrote it',
          () {
        final r = dbSetHandicap(newDotsAndBoxes(), Side.a, 'start_behind');
        expect(r.ok, isTrue);
        expect(r.state!.scores, {Side.a: 2, Side.b: 0});
        expect(r.state!.handicap, 'start_behind');
      });

      test('child_first sets turn to the child even mid-game, after the parent already moved', () {
        var s = newDotsAndBoxes();
        s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!;
        expect(s.turn, Side.b);
        final h = dbSetHandicap(s, Side.a, 'child_first');
        expect(h.ok, isTrue);
        expect(h.state!.turn, Side.a);
        expect(h.state!.moves.length, 1, reason: 'the board itself is untouched');
      });
    });

    group('free, unlimited takebacks correctly restore whose turn it is, even across an '
        'extra-turn/box-completing move (§9.2)', () {
      test('undoing a follow-up move made during an extra turn hands the extra turn back, not '
          'to the opponent', () {
        var s = newDotsAndBoxes();
        s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!;
        s = dbPlay(s, Side.b, EdgeKind.h, 1, 0).state!;
        s = dbPlay(s, Side.a, EdgeKind.v, 0, 0).state!;
        s = dbPlay(s, Side.b, EdgeKind.v, 0, 1).state!; // B completes box (0,0), earns another turn
        expect(s.turn, Side.b);
        expect(s.owner[0][0], Side.b);
        s = dbPlay(s, Side.b, EdgeKind.h, 0, 1).state!; // B's extra-turn follow-up move
        expect(s.turn, Side.a);
        expect(s.moves.length, 5);

        final undone = dbTakeBack(s); // undo move 5 (B's follow-up)
        expect(undone.moves.length, 4);
        expect(undone.owner[0][0], Side.b, reason: 'the box completion itself still stands');
        expect(undone.scores[Side.b], 1);
        expect(undone.turn, Side.b,
            reason: "B's extra turn is restored, NOT handed to A — this is the exact edge case");
      });

      test('undoing the box-completing move itself hands the turn back to whoever it was before, '
          'and un-claims the box', () {
        var s = newDotsAndBoxes();
        s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!;
        s = dbPlay(s, Side.b, EdgeKind.h, 1, 0).state!;
        s = dbPlay(s, Side.a, EdgeKind.v, 0, 0).state!; // turn is now B's, about to complete the box
        final beforeCompletion = s.turn;
        s = dbPlay(s, Side.b, EdgeKind.v, 0, 1).state!; // B completes box (0,0)
        s = dbPlay(s, Side.b, EdgeKind.h, 0, 1).state!; // B's extra-turn follow-up
        expect(s.moves.length, 5);

        var undone = dbTakeBack(s); // undo move 5
        undone = dbTakeBack(undone); // undo move 4 — the box-completing move itself
        expect(undone.moves.length, 3);
        expect(undone.owner[0][0], isNull, reason: 'the box is un-claimed');
        expect(undone.scores[Side.b], 0);
        expect(undone.turn, beforeCompletion, reason: "the turn reverts to exactly what it was before");
      });

      test('a take-back with no moves is a harmless no-op', () {
        final s = newDotsAndBoxes();
        final undone = dbTakeBack(s);
        expect(undone.moves, isEmpty);
        expect(undone.turn, Side.a);
      });

      test('a take-back replays a start_behind handicap too', () {
        var s = dbSetHandicap(newDotsAndBoxes(), Side.a, 'start_behind').state!;
        s = dbPlay(s, Side.a, EdgeKind.h, 0, 0).state!;
        final undone = dbTakeBack(s);
        expect(undone.handicap, 'start_behind');
        expect(undone.scores, {Side.a: 2, Side.b: 0}, reason: 'the pre-loaded lead survives the take-back');
      });

      test('take-back correctly restores a finished games outcome to null', () {
        final s = _almostFull(4, 4, (2, 2));
        final finished = dbPlay(s, Side.a, EdgeKind.v, 2, 3).state!;
        expect(finished.outcome, isNotNull);
        final undone = dbTakeBack(finished);
        expect(undone.outcome, isNull);
      });
    });
  });

  group('dots-and-boxes screen — §9.2, P2', () {
    testWidgets('opens directly on the board — no setup gate, matching game_story.dart', (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      expect(find.text('Dots and boxes'), findsOneWidget); // AppBar title
      expect(find.text("Ivy's move"), findsOneWidget);
      expect(find.byKey(const Key('dbH_0_0')), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      expect(find.byIcon(Icons.settings, skipOffstage: false), findsNothing);
      expect(find.textContaining('Settings', skipOffstage: false), findsNothing);
    });

    testWidgets('P2 — no ELO, rank, score, streak, or win/lose framing anywhere', (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      for (final forbidden in [
        'ELO', 'Rank', 'streak', 'leaderboard', 'You win', 'You lose', 'You lost', 'Winner', 'Loser'
      ]) {
        expect(find.textContaining(forbidden, skipOffstage: false), findsNothing, reason: forbidden);
      }
    });

    testWidgets('a live box tally is shown by name while play continues, not a bare "Score" label',
        (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes(childName: 'Ivy', parentName: 'Dad')));
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    });

    testWidgets('voice note mic is an honest not-built-yet acknowledgment', (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      await t.tap(find.byIcon(Icons.mic_none));
      await t.pump();
      expect(find.textContaining('not built yet'), findsOneWidget);
    });

    testWidgets('a real move: tap an edge, it draws, and the simulated parent replies', (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes(botThinkDelay: Duration.zero)));
      await t.tap(find.byKey(const Key('dbH_0_0')));
      await t.pump();
      expect(find.text("Dad is thinking…"), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text("Ivy's move"), findsOneWidget);
    });

    testWidgets('take-back is free: disabled with no history, enabled after one move, and undoes it',
        (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes(botThinkDelay: Duration(days: 1))));
      OutlinedButton takeBackButton() =>
          t.widget<OutlinedButton>(find.byKey(const Key('dbTakeBack')));
      expect(takeBackButton().onPressed, isNull);
      await t.tap(find.byKey(const Key('dbH_0_0')));
      await t.pump();
      expect(takeBackButton().onPressed, isNotNull);
      await t.tap(find.byKey(const Key('dbTakeBack')));
      await t.pump();
      expect(takeBackButton().onPressed, isNull);
      // Flush the simulated parent's still-pending 1-day "thinking" timer —
      // it is now stale (the take-back already restored the child's turn),
      // and _scheduleParentMove's own turn/outcome re-check (added for
      // exactly this reason) makes firing it now a safe no-op rather than a
      // bot move that's no longer valid.
      await t.pump(const Duration(days: 2));
    });

    testWidgets("Make it fair reaches HandicapScreen, and selecting start_behind binds immediately",
        (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      await t.tap(find.byTooltip('Make it fair'));
      await t.pumpAndSettle();
      expect(find.text('Want to make it harder for Dad?'), findsOneWidget);
      await t.tap(find.text('Dad starts two boxes behind'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.textContaining('playing the hard way'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: "the child's live tally reflects the pre-loaded lead");
    });

    testWidgets('applying child_first mid-game clears a stale "is thinking" banner '
        '(found during adversarial self-verify)', (t) async {
      await t.pumpWidget(wrap(const GameDotsBoxes(botThinkDelay: Duration(days: 1))));
      await t.tap(find.byKey(const Key('dbH_0_0'))); // child's move; turn passes to the parent
      await t.pump();
      expect(find.textContaining('is thinking', skipOffstage: false), findsOneWidget);
      await t.tap(find.byTooltip('Make it fair'));
      await t.pumpAndSettle();
      await t.tap(find.text('I always go first')); // child_first hands the turn straight back to her
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.textContaining('is thinking', skipOffstage: false), findsNothing,
          reason: 'the stale "thinking" indicator must not survive a handicap that ends the wait');
      expect(find.text("Ivy's move"), findsOneWidget);
      await t.pump(const Duration(days: 2)); // flush the now-stale pending bot timer
    });
  });

  group('§8.11.1 posture-driven layout — a real side panel, not just no-overflow', () {
    // Mirrors court_export_test.dart's reviewableAt()/requestableAt() width
    // tests: proves DIFFERENT rendered structure at different postures
    // (form_factors.dart), not merely the absence of a RenderFlex overflow.
    testWidgets('foldCover (344 CSS px, 1 column): board-only, stacked — no side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      await t.pump();
      expect(find.byKey(const Key('dbSidePanel')), findsNothing);
      expect(find.byType(ListView), findsOneWidget,
          reason: 'the narrow layout is a single stacked ListView, not a board+panel Row');
      expect(find.byKey(const Key('dbH_0_0')), findsOneWidget);
      expect(find.byKey(const Key('dbTakeBack')), findsOneWidget);
    });

    testWidgets('foldMain (~673 CSS px, 2 columns): the board shares the screen with a persistent '
        'side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      await t.pump();
      expect(find.byKey(const Key('dbSidePanel')), findsOneWidget);
      expect(find.byType(ListView), findsNothing,
          reason: 'the wide layout is a board+panel Row, not the narrow stacked ListView');
      expect(find.byKey(const Key('dbH_0_0')), findsOneWidget, reason: 'the board is still on screen too');
      expect(find.byKey(const Key('dbTakeBack')), findsOneWidget, reason: 'controls live in the panel now');
    });

    testWidgets('a tablet/desktop width (~1100 CSS px, 3 columns) also gets the side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      await t.pump();
      expect(find.byKey(const Key('dbSidePanel')), findsOneWidget);
    });

    testWidgets('a standard phone width (~390 CSS px, 1 column) stays board-only, same as foldCover',
        (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameDotsBoxes()));
      await t.pump();
      expect(find.byKey(const Key('dbSidePanel')), findsNothing);
    });
  });

  group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
    for (final MapEntry<String, Size> entry in const <String, Size>{
      'Fold5 cover (344 CSS px)': Size(344, 882),
      'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
      'a standard phone (~390 CSS px)': Size(390, 844),
      'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
    }.entries) {
      testWidgets('renders without overflow at ${entry.key}', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const GameDotsBoxes(botThinkDelay: Duration.zero)));
        await t.pump();
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('dbH_0_0')));
        await t.pumpAndSettle(); // let the simulated parent's reply (and any cascade) finish first
        expect(t.takeException(), isNull, reason: 'the take-back button row must not overflow');
      });
    }
  });
}
