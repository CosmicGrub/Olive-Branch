// OLIVE BRANCH — checkers tests. MASTERFILE §9.2, P2.
//
// Split the same way lock_controller_test.dart / invariants_test.dart split:
// pure rules-engine correctness (compulsory capture, multi-jump, crowning
// ends a chain) at the function level, and P2/interaction properties
// against the actual rendered widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_checkers.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// The board plus the tally, banners and undo/play-again row together run
/// taller than flutter_test's default 600px surface, and ListView only
/// builds slivers within its viewport/cache extent — so a control below the
/// fold simply doesn't exist as an Element yet, independent of scrolling.
/// Widening the test surface (rather than scrolling) keeps every assertion
/// below working against what's actually on screen, which is what these
/// tests are for.
void useTallSurface(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

CheckersState _emptyBoard({CkSide turn = CkSide.child}) => CheckersState(
      board: List<List<CkPiece?>>.generate(8, (_) => List<CkPiece?>.filled(8, null)),
      turn: turn, outcome: null, mustContinueFrom: null,
    );

CheckersState _withPieces(CheckersState s, Map<CkCell, CkPiece> pieces) {
  final board = [for (final row in s.board) [...row]];
  for (final entry in pieces.entries) {
    board[entry.key.$1][entry.key.$2] = entry.value;
  }
  return CheckersState(board: board, turn: s.turn, outcome: s.outcome,
      mustContinueFrom: s.mustContinueFrom);
}

void main() {
  group('checkers engine — §9.2', () {
    test('newCheckers seeds 12 pieces per side on dark squares only', () {
      final s = newCheckers();
      expect(checkersCount(s, CkSide.child), 12);
      expect(checkersCount(s, CkSide.parent), 12);
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          if (s.board[r][c] != null) expect((r + c) % 2, 1, reason: 'piece on a light square');
        }
      }
      expect(s.turn, CkSide.child);
    });

    test('compulsory capture: a jump anywhere forbids a plain move anywhere', () {
      var s = _emptyBoard();
      s = _withPieces(s, {
        // Piece A can capture the parent at (2,3), landing (1,4).
        (3, 2): const CkPiece(side: CkSide.child, king: false),
        (2, 3): const CkPiece(side: CkSide.parent, king: false),
        // Piece B has only a plain move available, no capture.
        (5, 4): const CkPiece(side: CkSide.child, king: false),
      });

      final moves = checkersMoves(s, CkSide.child);
      expect(moves.length, 1);
      expect(moves.single.from, (3, 2));
      expect(moves.single.to, (1, 4));
      expect(moves.any((m) => m.from == (5, 4)), isFalse);

      final blocked = playCheckers(s, CkSide.child, (5, 4), (4, 3));
      expect(blocked.ok, isFalse);
      expect(blocked.reason, 'must_capture');

      final allowed = playCheckers(s, CkSide.child, (3, 2), (1, 4));
      expect(allowed.ok, isTrue);
      expect(allowed.state!.board[2][3], isNull, reason: 'captured piece removed');
    });

    test('multi-jump: landing next to another capture forces continuation', () {
      var s = _emptyBoard();
      s = _withPieces(s, {
        (5, 0): const CkPiece(side: CkSide.child, king: false),
        (4, 1): const CkPiece(side: CkSide.parent, king: false),
        (2, 3): const CkPiece(side: CkSide.parent, king: false),
      });
      final first = playCheckers(s, CkSide.child, (5, 0), (3, 2));
      expect(first.ok, isTrue);
      expect(first.state!.mustContinueFrom, (3, 2));
      expect(first.state!.turn, CkSide.child, reason: 'turn does not pass mid-chain');

      // Only the continuing jump is legal — not a fresh selection elsewhere.
      final onlyMove = checkersMoves(first.state!, CkSide.child);
      expect(onlyMove.length, 1);
      expect(onlyMove.single.from, (3, 2));
      expect(onlyMove.single.to, (1, 4));

      final second = playCheckers(first.state!, CkSide.child, (3, 2), (1, 4));
      expect(second.ok, isTrue);
      expect(second.state!.mustContinueFrom, isNull);
      expect(second.state!.turn, CkSide.parent, reason: 'chain over, turn passes');
    });

    test('crowning ends a chain even when another jump would otherwise be legal', () {
      var s = _emptyBoard();
      s = _withPieces(s, {
        (2, 1): const CkPiece(side: CkSide.child, king: false),
        (1, 2): const CkPiece(side: CkSide.parent, king: false),
        // A second parent piece that WOULD offer a further jump from (0,3)
        // if the landing piece were still allowed to keep jumping.
        (1, 4): const CkPiece(side: CkSide.parent, king: false),
      });
      final result = playCheckers(s, CkSide.child, (2, 1), (0, 3));
      expect(result.ok, isTrue);
      final after = result.state!;
      expect(after.board[0][3]!.king, isTrue, reason: 'reaching the far rank crowns it');
      expect(after.mustContinueFrom, isNull, reason: 'crowning ends the chain');
      expect(after.turn, CkSide.parent, reason: 'turn passes despite a further jump existing');
    });

    test('a side with no legal move left loses', () {
      var s = _emptyBoard();
      s = _withPieces(s, {
        // A free move for the child, unrelated to the boxed-in parent piece.
        (5, 0): const CkPiece(side: CkSide.child, king: false),
        // Parent's only piece, fully boxed: both diagonals ahead are
        // occupied, and both possible jump landings are blocked too.
        (0, 1): const CkPiece(side: CkSide.parent, king: false),
        (1, 0): const CkPiece(side: CkSide.child, king: false),
        (1, 2): const CkPiece(side: CkSide.child, king: false),
        (2, 3): const CkPiece(side: CkSide.child, king: false),
      });
      final result = playCheckers(s, CkSide.child, (5, 0), (4, 1));
      expect(result.ok, isTrue);
      expect(checkersMoves(result.state!, CkSide.parent), isEmpty);
      expect(result.state!.outcome, CkSide.child, reason: 'parent has no legal move left');
    });
  });

  group('checkers screen — P2, §9.2', () {
    testWidgets('renders with no settings affordance and no score language', (t) async {
      await t.pumpWidget(wrap(const GameCheckers(childName: 'Ivy', parentName: 'Dad')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      for (final banned in ['ELO', 'rank', 'streak', 'wins', 'losses', 'leaderboard', 'Rating']) {
        expect(find.textContaining(banned), findsNothing, reason: '"$banned" must never reach a child');
      }
    });

    testWidgets('shows both names as an in-game tally, not a scoreboard label', (t) async {
      await t.pumpWidget(wrap(const GameCheckers(childName: 'Ivy', parentName: 'Dad')));
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);
      expect(find.text('12'), findsNWidgets(2)); // 12 pieces each, at the start
    });

    testWidgets('undo is disabled until a move is made, then reverts the board', (t) async {
      useTallSurface(t);
      await t.pumpWidget(wrap(const GameCheckers(
        childName: 'Ivy', parentName: 'Dad',
        botThinkDelay: Duration(milliseconds: 10))));

      final undoButton = find.byKey(const Key('ckUndo'));
      OutlinedButton button = t.widget<OutlinedButton>(undoButton);
      expect(button.onPressed, isNull);

      // A legal opening move for the child: (5,0) -> (4,1).
      await t.tap(find.byKey(const Key('ckCell_5_0')));
      await t.pump();
      await t.tap(find.byKey(const Key('ckCell_4_1')));
      await t.pump();
      // Let the simulated parent reply land.
      await t.pumpAndSettle(const Duration(milliseconds: 50));

      button = t.widget(undoButton);
      expect(button.onPressed, isNotNull, reason: 'a move was made; undo should be live');

      await t.tap(undoButton); // undo parent's reply
      await t.pump();
      await t.tap(undoButton); // undo the child's own move
      await t.pump();

      button = t.widget(undoButton);
      expect(button.onPressed, isNull, reason: 'back to the start, nothing left to undo');
    });

    testWidgets('the closing message is "Good game." never a win/loss verdict', (t) async {
      await t.pumpWidget(wrap(const GameCheckers(childName: 'Ivy', parentName: 'Dad')));
      expect(find.text('Good game.'), findsNothing, reason: 'game has not finished yet');
      expect(find.textContaining('You lost'), findsNothing);
      expect(find.textContaining('You win'), findsNothing);
      expect(find.textContaining('You won'), findsNothing);
    });
  });
}
