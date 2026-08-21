// OLIVE BRANCH — game_tictactoe.dart tests. MASTERFILE §9.2, P2.
//
// Same split as game_chess_test.dart/game_checkers_test.dart: the rules
// engine (win/draw detection, the no_centre handicap refused AT THE ENGINE
// — not just inferred from a disabled button — free takebacks, and
// setHandicap's mid-game side effects) exercised directly against the
// ported functions, then the screen itself against the same §9.2/P2
// invariants those files hold their own screens to.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_logic.dart';
import 'package:olive_client/game_tictactoe.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('tic-tac-toe engine — real rules (§9.2)', () {
    test('newTicTacToe: empty board, child moves first, no handicap', () {
      final s = newTicTacToe();
      expect(s.board, List<Side?>.filled(9, null));
      expect(s.turn, Side.a);
      expect(s.moves, isEmpty);
      expect(s.outcome, isNull);
      expect(s.handicap, isNull);
    });

    test('a row win is detected the move it happens', () {
      var s = newTicTacToe();
      for (final at in [0, 3, 1, 4, 2]) {
        // Turns alternate A,B,A,B,A — child claims the top row (0,1,2).
        final side = s.turn;
        final r = tttPlay(s, side, at);
        expect(r.ok, isTrue, reason: '$at should be legal (${r.reason})');
        s = r.state!;
      }
      expect(s.outcome, TttOutcome.childWin);
    });

    test('a column win for the parent is detected too — this is not a child-only check', () {
      var s = newTicTacToe();
      // A takes 0,1,3 (no line); B takes 2,5,8 (the right column).
      for (final at in [0, 2, 1, 5, 3, 8]) {
        final side = s.turn;
        final r = tttPlay(s, side, at);
        expect(r.ok, isTrue, reason: '$at should be legal (${r.reason})');
        s = r.state!;
      }
      expect(s.outcome, TttOutcome.parentWin);
    });

    test('a full board with no line anywhere is a draw', () {
      // X O X / X O O / O X X — no three-in-a-row for either mark.
      var s = newTicTacToe();
      const order = [0, 1, 2, 4, 3, 5, 7, 6, 8]; // A,B,A,B,A,B,A,B,A
      for (final at in order) {
        final side = s.turn;
        final r = tttPlay(s, side, at);
        expect(r.ok, isTrue, reason: '$at should be legal (${r.reason})');
        s = r.state!;
      }
      expect(s.outcome, TttOutcome.draw);
    });

    test('occupied, out-of-range, wrong turn, and game-over are all refused', () {
      var s = newTicTacToe();
      final r1 = tttPlay(s, Side.a, 0);
      expect(r1.ok, isTrue);
      s = r1.state!;
      expect(tttPlay(s, Side.b, 0).reason, 'occupied'); // turn is B's; occupied is still checked
      expect(tttPlay(s, Side.b, 9).reason, 'out_of_range');
      expect(tttPlay(s, Side.b, -1).reason, 'out_of_range');
      expect(tttPlay(s, Side.a, 1).reason, 'not_your_turn'); // it's B's turn, not A's
      var finished = newTicTacToe();
      for (final at in [0, 3, 1, 4, 2]) {
        final side = finished.turn;
        finished = tttPlay(finished, side, at).state!;
      }
      expect(finished.outcome, TttOutcome.childWin);
      expect(tttPlay(finished, Side.b, 5).reason, 'game_over');
    });

    group('§9.2 no_centre handicap — enforced at the engine, not just the UI', () {
      test("the parent is refused the centre square once the child sets no_centre", () {
        var s = newTicTacToe();
        final h = tttSetHandicap(s, Side.a, 'no_centre');
        expect(h.ok, isTrue);
        s = h.state!;
        // Get the turn to B without touching the centre.
        s = tttPlay(s, Side.a, 0).state!;
        final refused = tttPlay(s, Side.b, 4);
        expect(refused.ok, isFalse);
        expect(refused.reason, 'handicap_forbids');
      });

      test('the CHILD may still play the centre under her own no_centre handicap', () {
        final s = tttSetHandicap(newTicTacToe(), Side.a, 'no_centre').state!;
        final r = tttPlay(s, Side.a, 4);
        expect(r.ok, isTrue);
      });

      test('the bots own candidate pool excludes the centre — never relies on tttPlay to refuse it',
          () {
        var s = tttSetHandicap(newTicTacToe(), Side.a, 'no_centre').state!;
        s = tttPlay(s, Side.a, 0).state!; // hand turn to B
        expect(tttLegalMoves(s, Side.b), isNot(contains(4)));
        expect(tttLegalMoves(s, Side.a), contains(4), reason: "the child's own moves aren't gated");
      });

      test('with no handicap active the centre is open to both sides', () {
        expect(tttLegalMoves(newTicTacToe(), Side.b), contains(4));
      });
    });

    group('setHandicap — §9.2 child-only, applied to the CURRENT state', () {
      test('refuses a parent handicapping themselves', () {
        final r = tttSetHandicap(newTicTacToe(), Side.b, 'no_centre');
        expect(r.ok, isFalse);
        expect(r.refusal, 'child_only');
      });

      test('refuses a parent even when asking to clear a handicap', () {
        final r = tttSetHandicap(newTicTacToe(), Side.b, null);
        expect(r.ok, isFalse);
        expect(r.refusal, 'child_only');
      });

      test('refuses a handicap id that does not belong to tic-tac-toe', () {
        final r = tttSetHandicap(newTicTacToe(), Side.a, 'start_behind');
        expect(r.ok, isFalse);
        expect(r.refusal, 'unknown');
      });

      test('child_first sets turn to the child even mid-game, after the parent already moved', () {
        var s = newTicTacToe();
        s = tttPlay(s, Side.a, 0).state!;
        s = tttPlay(s, Side.b, 1).state!; // now it's A's turn again naturally
        s = tttPlay(s, Side.a, 2).state!; // now it's B's turn
        expect(s.turn, Side.b);
        final h = tttSetHandicap(s, Side.a, 'child_first');
        expect(h.ok, isTrue);
        expect(h.state!.turn, Side.a, reason: 'child_first hands the turn back mid-game');
        // The board itself is untouched — this mutates the current state,
        // it does not restart the game.
        expect(h.state!.moves.length, 3);
        expect(h.state!.board[0], Side.a);
      });

      test('applying a handicap never resets the board or move history', () {
        var s = newTicTacToe();
        s = tttPlay(s, Side.a, 0).state!;
        final h = tttSetHandicap(s, Side.a, 'no_centre');
        expect(h.state!.moves.length, 1);
        expect(h.state!.board[0], Side.a);
      });
    });

    group('free, unlimited takebacks — replay from the start, §9.2', () {
      test('a take-back with no moves is a harmless no-op', () {
        final s = newTicTacToe();
        expect(identical(tttTakeBack(s), s) || tttTakeBack(s).moves.isEmpty, isTrue);
      });

      test('undoes exactly the last move and hands the turn back', () {
        var s = newTicTacToe();
        s = tttPlay(s, Side.a, 0).state!;
        s = tttPlay(s, Side.b, 4).state!;
        final undone = tttTakeBack(s);
        expect(undone.moves.length, 1);
        expect(undone.turn, Side.b, reason: "only the child's move remains");
        expect(undone.board[0], Side.a);
        expect(undone.board[4], isNull);
      });

      test('a take-back replays the handicap too, so no_centre still binds the parent afterward', () {
        var s = tttSetHandicap(newTicTacToe(), Side.a, 'no_centre').state!;
        s = tttPlay(s, Side.a, 0).state!;
        s = tttPlay(s, Side.b, 1).state!;
        s = tttPlay(s, Side.a, 2).state!;
        final undone = tttTakeBack(s); // undoes the child's 3rd move (cell 2)
        expect(undone.handicap, 'no_centre');
        expect(undone.turn, Side.a, reason: 'replay reproduces the exact turn as before that move');
        final afterChildMove = tttPlay(undone, Side.a, 3).state!;
        expect(afterChildMove.turn, Side.b);
        final parentTriesCentre = tttPlay(afterChildMove, Side.b, 4);
        expect(parentTriesCentre.ok, isFalse);
        expect(parentTriesCentre.reason, 'handicap_forbids');
      });

      test('take-back correctly restores a finished games outcome to null', () {
        var s = newTicTacToe();
        for (final at in [0, 3, 1, 4, 2]) {
          s = tttPlay(s, s.turn, at).state!;
        }
        expect(s.outcome, TttOutcome.childWin);
        final undone = tttTakeBack(s);
        expect(undone.outcome, isNull);
      });
    });
  });

  group('tic-tac-toe screen — §9.2, P2', () {
    testWidgets('opens directly on the board — no setup gate, matching game_story.dart', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe()));
      expect(find.text('Three in a row'), findsOneWidget); // AppBar title
      expect(find.text("Ivy's move"), findsOneWidget);
      expect(find.byKey(const Key('tttCell_0')), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe()));
      expect(find.byIcon(Icons.settings, skipOffstage: false), findsNothing);
      expect(find.textContaining('Settings', skipOffstage: false), findsNothing);
    });

    testWidgets('P2 — no ELO, rank, score, streak, or win/lose framing anywhere', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe()));
      for (final forbidden in [
        'ELO', 'Rank', 'Score', 'streak', 'leaderboard', 'You win', 'You lose', 'You lost', 'Winner', 'Loser'
      ]) {
        expect(find.textContaining(forbidden, skipOffstage: false), findsNothing, reason: forbidden);
      }
    });

    testWidgets('voice note mic is an honest not-built-yet acknowledgment', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe()));
      await t.tap(find.byIcon(Icons.mic_none));
      await t.pump();
      expect(find.textContaining('not built yet'), findsOneWidget);
    });

    testWidgets('a real move: tap a cell, it fills, and the simulated parent replies', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(botThinkDelay: Duration.zero)));
      await t.tap(find.byKey(const Key('tttCell_0')));
      await t.pump();
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget, reason: "the child's own mark");
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget, reason: "the parent's reply");
      expect(find.text("Ivy's move"), findsOneWidget);
    });

    testWidgets('take-back is free: disabled with no history, enabled after one move, and undoes it',
        (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(botThinkDelay: Duration(days: 1))));
      OutlinedButton takeBackButton() =>
          t.widget<OutlinedButton>(find.byKey(const Key('tttTakeBack')));
      expect(takeBackButton().onPressed, isNull);
      await t.tap(find.byKey(const Key('tttCell_0')));
      await t.pump();
      expect(takeBackButton().onPressed, isNotNull);
      await t.tap(find.byKey(const Key('tttTakeBack')));
      await t.pump();
      expect(find.byIcon(Icons.circle_outlined), findsNothing, reason: 'the move was undone');
      expect(takeBackButton().onPressed, isNull);
      // Flush the simulated parent's still-pending 1-day "thinking" timer —
      // it is now stale (the take-back already restored the child's turn),
      // and _scheduleParentMove's own turn/outcome re-check (added for
      // exactly this reason) makes firing it now a safe no-op rather than a
      // bot move that's no longer valid.
      await t.pump(const Duration(days: 2));
    });

    testWidgets("Make it fair reaches HandicapScreen, and selecting no_centre binds immediately",
        (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe()));
      await t.tap(find.byTooltip('Make it fair'));
      await t.pumpAndSettle();
      expect(find.text('Want to make it harder for Dad?'), findsOneWidget);
      await t.tap(find.text("Dad can't use the middle square"));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.textContaining("playing the hard way"), findsOneWidget);
    });

    testWidgets('a full game — whoever wins or draws — ends with a plain factual close-out line',
        (t) async {
      // Deliberately does not predict the simulated (random) parent's picks:
      // each round taps whatever cell the live board actually shows as
      // still empty, so this stays deterministic-in-outcome (it always
      // terminates within 9 plies) without depending on a specific random
      // sequence — real play-to-completion, not a scripted board.
      await t.pumpWidget(wrap(const GameTicTacToe(botThinkDelay: Duration.zero)));
      for (var round = 0; round < 9; round++) {
        if (find.textContaining('Good game.', skipOffstage: false).evaluate().isNotEmpty) break;
        int? empty;
        for (var cell = 0; cell < 9; cell++) {
          final icon = find.descendant(
              of: find.byKey(Key('tttCell_$cell')), matching: find.byType(Icon));
          if (icon.evaluate().isEmpty) { empty = cell; break; }
        }
        if (empty == null) break;
        await t.tap(find.byKey(Key('tttCell_$empty')));
        await t.pumpAndSettle();
      }
      // "Good game." (win) or "Draw. Good game." (draw) — either is a plain
      // factual line, never a verdict on her, per P2. findsWidgets (not
      // findsOneWidget): the plain turn banner also reads "Good game." once
      // finished, same as the end banner's own line does — the same
      // harmless redundancy game_chess.dart's _TurnBanner/_EndBanner pair
      // already carries; what matters for P2 is that EVERY occurrence is
      // this same flat, factual phrase, never a verdict.
      final goodGame = find.textContaining('Good game.', skipOffstage: false);
      expect(goodGame, findsWidgets);
      for (final w in t.widgetList<Text>(goodGame)) {
        expect(w.data, anyOf('Good game.', 'Draw. Good game.'));
      }
      expect(find.byKey(const Key('tttPlayAgain')), findsOneWidget);
    });

    testWidgets('applying child_first mid-game clears a stale "is thinking" banner '
        '(found during adversarial self-verify)', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(botThinkDelay: Duration(days: 1))));
      await t.tap(find.byKey(const Key('tttCell_0'))); // child's move; turn passes to the parent
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
      await t.pumpWidget(wrap(const GameTicTacToe()));
      await t.pump();
      expect(find.byKey(const Key('tttSidePanel')), findsNothing);
      expect(find.byType(ListView), findsOneWidget,
          reason: 'the narrow layout is a single stacked ListView, not a board+panel Row');
      expect(find.byKey(const Key('tttCell_0')), findsOneWidget);
      expect(find.byKey(const Key('tttTakeBack')), findsOneWidget);
    });

    testWidgets('foldMain (~673 CSS px, 2 columns): the board shares the screen with a persistent '
        'side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameTicTacToe()));
      await t.pump();
      expect(find.byKey(const Key('tttSidePanel')), findsOneWidget);
      expect(find.byType(ListView), findsNothing,
          reason: 'the wide layout is a board+panel Row, not the narrow stacked ListView');
      expect(find.byKey(const Key('tttCell_0')), findsOneWidget, reason: 'the board is still on screen too');
      expect(find.byKey(const Key('tttTakeBack')), findsOneWidget, reason: 'controls live in the panel now');
    });

    testWidgets('a tablet/desktop width (~1100 CSS px, 3 columns) also gets the side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameTicTacToe()));
      await t.pump();
      expect(find.byKey(const Key('tttSidePanel')), findsOneWidget);
    });

    testWidgets('a standard phone width (~390 CSS px, 1 column) stays board-only, same as foldCover',
        (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameTicTacToe()));
      await t.pump();
      expect(find.byKey(const Key('tttSidePanel')), findsNothing);
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
        await t.pumpWidget(wrap(const GameTicTacToe(botThinkDelay: Duration.zero)));
        await t.pump();
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('tttCell_0')));
        await t.pumpAndSettle(); // let the simulated parent's reply finish before teardown
        expect(t.takeException(), isNull, reason: 'the take-back button row must not overflow');
      });
    }

    testWidgets('the FINISHED button row (take-back + play-again together) fits the Fold5 cover '
        'width (344 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const GameTicTacToe(botThinkDelay: Duration.zero)));
      for (var round = 0; round < 9; round++) {
        if (find.textContaining('Good game.', skipOffstage: false).evaluate().isNotEmpty) break;
        int? empty;
        for (var cell = 0; cell < 9; cell++) {
          final icon = find.descendant(
              of: find.byKey(Key('tttCell_$cell')), matching: find.byType(Icon));
          if (icon.evaluate().isEmpty) { empty = cell; break; }
        }
        if (empty == null) break;
        await t.tap(find.byKey(Key('tttCell_$empty')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('tttPlayAgain')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
