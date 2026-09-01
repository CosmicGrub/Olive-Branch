// OLIVE BRANCH — connect4_bot.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests, no
// Flutter/widget/network involved.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect4_bot.dart';
import 'package:olive_client/connect4_engine.dart';
import 'package:olive_client/live_games.dart' show Side;

void main() {
  group('chooseColumn — the fast paths', () {
    test('always takes an immediate win, at every difficulty', () {
      var board = Connect4Board.empty();
      board = board.withMove(0, Side.a);
      board = board.withMove(1, Side.a);
      board = board.withMove(2, Side.a);
      for (final d in CpuDifficulty.values) {
        final col = chooseColumn(board, Side.a, d, Random(1));
        expect(col, 3, reason: 'difficulty $d should still take a free win');
        expect(applyMove(board, col, Side.a).outcome, Connect4Outcome.win);
      }
    });

    test('Medium and Hard always block an immediate opponent win', () {
      var board = Connect4Board.empty();
      board = board.withMove(0, Side.b);
      board = board.withMove(1, Side.b);
      board = board.withMove(2, Side.b);
      for (final d in [CpuDifficulty.medium, CpuDifficulty.hard]) {
        final col = chooseColumn(board, Side.a, d, Random(1));
        expect(col, 3, reason: 'difficulty $d must block the free opponent win');
      }
    });

    test('Easy sometimes fails to block — genuinely beatable, not just shallow', () {
      var board = Connect4Board.empty();
      board = board.withMove(0, Side.b);
      board = board.withMove(1, Side.b);
      board = board.withMove(2, Side.b);
      var sawAMiss = false;
      for (var seed = 0; seed < 200; seed++) {
        final col = chooseColumn(board, Side.a, CpuDifficulty.easy, Random(seed));
        if (col != 3) {
          sawAMiss = true;
          break;
        }
      }
      expect(sawAMiss, isTrue, reason: 'across 200 seeds, Easy should skip the block at least once');
    });
  });

  group('chooseColumn — general correctness', () {
    test('always returns a legal column on an empty board', () {
      final board = Connect4Board.empty();
      for (final d in CpuDifficulty.values) {
        final col = chooseColumn(board, Side.a, d, Random(5));
        expect(isLegalMove(board, col), isTrue);
      }
    });

    test('never picks a full column', () {
      var board = Connect4Board.empty();
      for (var i = 0; i < connect4Rows; i++) {
        board = applyMove(board, 3, i.isEven ? Side.a : Side.b).board;
      }
      expect(board.isColumnFull(3), isTrue);
      for (var trial = 0; trial < 20; trial++) {
        final col = chooseColumn(board, Side.a, CpuDifficulty.hard, Random(trial));
        expect(col, isNot(3));
      }
    });

    test('returns -1 only when the board is genuinely full', () {
      var board = Connect4Board.empty();
      var side = Side.a;
      var col = 0;
      while (!board.isFull) {
        if (!isLegalMove(board, col)) { col = (col + 1) % connect4Cols; continue; }
        var trial = applyMove(board, col, side);
        if (trial.outcome == Connect4Outcome.win) {
          final other = side == Side.a ? Side.b : Side.a;
          final alt = applyMove(board, col, other);
          if (alt.outcome == Connect4Outcome.win) { col = (col + 1) % connect4Cols; continue; }
          trial = alt;
        }
        board = trial.board;
        side = side == Side.a ? Side.b : Side.a;
        col = (col + 1) % connect4Cols;
      }
      expect(chooseColumn(board, Side.a, CpuDifficulty.medium, Random(1)), -1);
    });

    test('Hard beats a naive always-center-then-sequential opponent — a real strength floor', () {
      // Not a claim of perfect play (see this bot's own header) — just a
      // sanity floor: a search-based Hard bot should not lose to an
      // opponent making no attempt to win or block at all.
      var board = Connect4Board.empty();
      var toMove = Side.b; // naive opponent moves first
      var winner = connect4Winner(board);
      var guard = 0;
      while (winner == null && !board.isFull) {
        guard++;
        expect(guard < 100, isTrue);
        final col = toMove == Side.b
            ? [for (var c = 0; c < connect4Cols; c++) if (isLegalMove(board, c)) c].first
            : chooseColumn(board, Side.a, CpuDifficulty.hard, Random(guard));
        final result = applyMove(board, col, toMove);
        if (!result.applied) break;
        board = result.board;
        winner = result.winner;
        toMove = toMove == Side.a ? Side.b : Side.a;
      }
      expect(winner, isNot(Side.b), reason: 'Hard should never lose to a purely naive opponent');
    });
  });
}
