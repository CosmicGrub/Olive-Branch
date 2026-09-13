// OLIVE BRANCH — connect4_engine.dart tests. Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic
// tests, no Flutter/widget/network involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect4_engine.dart';
import 'package:olive_client/live_games.dart' show Side;

Side otherOf(Side s) => s == Side.a ? Side.b : Side.a;

void main() {
  group('Connect4Board basics', () {
    test('an empty board has no winner and is not full', () {
      final board = Connect4Board.empty();
      expect(connect4Winner(board), isNull);
      expect(board.isFull, isFalse);
      expect(board.discCount, 0);
    });

    test('a full column rejects further moves — board unchanged, applied is false', () {
      var board = Connect4Board.empty();
      for (var i = 0; i < connect4Rows; i++) {
        board = applyMove(board, 0, i.isEven ? Side.a : Side.b).board;
      }
      expect(board.isColumnFull(0), isTrue);
      final result = applyMove(board, 0, Side.a);
      expect(result.applied, isFalse);
      expect(result.board.columns[0].length, connect4Rows);
    });
  });

  group('connect4Winner', () {
    test('detects a horizontal four-in-a-row', () {
      var board = Connect4Board.empty();
      for (final col in [0, 1, 2, 3]) {
        board = board.withMove(col, Side.a);
      }
      expect(connect4Winner(board), Side.a);
    });

    test('detects a vertical four-in-a-row', () {
      var board = Connect4Board.empty();
      for (var i = 0; i < 4; i++) {
        board = board.withMove(2, Side.b);
      }
      expect(connect4Winner(board), Side.b);
    });

    test('detects a rising diagonal four-in-a-row', () {
      // Build a staircase: col0 h1, col1 h2, col2 h3, col3 h4, all Side.a on top.
      var board = Connect4Board.empty();
      board = board.withMove(0, Side.a); // (0,0) a
      board = board.withMove(1, Side.b);
      board = board.withMove(1, Side.a); // (1,1) a
      board = board.withMove(2, Side.b);
      board = board.withMove(2, Side.b);
      board = board.withMove(2, Side.a); // (2,2) a
      board = board.withMove(3, Side.b);
      board = board.withMove(3, Side.b);
      board = board.withMove(3, Side.b);
      board = board.withMove(3, Side.a); // (3,3) a
      expect(connect4Winner(board), Side.a);
    });

    test('detects a falling diagonal four-in-a-row', () {
      var board = Connect4Board.empty();
      board = board.withMove(0, Side.b);
      board = board.withMove(0, Side.b);
      board = board.withMove(0, Side.b);
      board = board.withMove(0, Side.a); // (0,3) a
      board = board.withMove(1, Side.b);
      board = board.withMove(1, Side.b);
      board = board.withMove(1, Side.a); // (1,2) a
      board = board.withMove(2, Side.b);
      board = board.withMove(2, Side.a); // (2,1) a
      board = board.withMove(3, Side.a); // (3,0) a
      expect(connect4Winner(board), Side.a);
    });

    test('three in a row is not a win', () {
      var board = Connect4Board.empty();
      for (final col in [0, 1, 2]) {
        board = board.withMove(col, Side.a);
      }
      expect(connect4Winner(board), isNull);
    });
  });

  group('applyMove', () {
    test('isFull is true only once every column is full', () {
      var board = Connect4Board.empty();
      for (var col = 0; col < connect4Cols; col++) {
        for (var row = 0; row < connect4Rows - 1; row++) {
          board = board.withMove(col, Side.a);
        }
      }
      expect(board.isFull, isFalse, reason: 'every column is one short');
      board = board.withMove(0, Side.a);
      expect(board.isFull, isFalse, reason: 'column 0 alone being full does not fill the board');
    });

    test('applyMove reports outcome=draw once the board fills with no winner', () {
      // Self-verifying construction rather than a hand-derived pattern
      // (hand-deriving a 42-cell no-4-in-a-row layout is exactly the kind
      // of thing that's easy to get subtly wrong under real time
      // pressure): greedily fill the board, using connect4Winner itself —
      // already independently verified above — to steer away from ever
      // creating a win. By construction, the resulting full board has no
      // winner; the real assertion is that applyMove's own outcome
      // correctly reports draw on the final placement.
      var board = Connect4Board.empty();
      var side = Side.a;
      var col = 0;
      MoveResult? last;
      var guard = 0;
      while (!board.isFull) {
        guard++;
        expect(guard < 1000, isTrue, reason: 'must terminate well within 42 real placements');
        if (!isLegalMove(board, col)) {
          col = (col + 1) % connect4Cols;
          continue;
        }
        var trial = applyMove(board, col, side);
        if (trial.outcome == Connect4Outcome.win) {
          final alt = applyMove(board, col, otherOf(side));
          if (alt.outcome == Connect4Outcome.win) {
            col = (col + 1) % connect4Cols;
            continue;
          }
          trial = alt;
        }
        last = trial;
        board = trial.board;
        side = otherOf(side);
        col = (col + 1) % connect4Cols;
      }
      expect(connect4Winner(board), isNull);
      expect(last!.outcome, Connect4Outcome.draw);
    });

    test('winning move reports outcome=win and the correct winner', () {
      var board = Connect4Board.empty();
      board = board.withMove(0, Side.a);
      board = board.withMove(1, Side.a);
      board = board.withMove(2, Side.a);
      final result = applyMove(board, 3, Side.a);
      expect(result.outcome, Connect4Outcome.win);
      expect(result.winner, Side.a);
    });
  });
}
