// OLIVE BRANCH — game_chess.dart tests. MASTERFILE §9.2, P2.
//
// Two groups: the rules engine (castling, en passant, promotion, stalemate,
// threefold repetition, the fifty-move rule, the corrected handicaps, free
// takebacks, and the "hint, don't solve" coach) exercised directly against
// hand-built positions, then the screen itself against the same invariants
// invariants_test.dart already holds child-facing surfaces to.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_chess.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

ChBoard _emptyBoard() => List<List<ChPiece?>>.generate(8, (_) => List<ChPiece?>.filled(8, null));
const _noCastle = ChCastleRights(childK: false, childQ: false, parentK: false, parentQ: false);

ChessState _positionOf(ChBoard board, ChSide turn,
    {ChCastleRights castleRights = _noCastle, int halfmoveClock = 0, List<ChMove> history = const []}) =>
  ChessState(board: board, turn: turn, castleRights: castleRights, enPassantTarget: null,
    halfmoveClock: halfmoveClock, history: history, positionCounts: const {}, outcome: null);

void main() {
  group('chess engine — real rules (§9.2)', () {
    test('kingside castling moves both the king and the rook', () {
      final board = _emptyBoard();
      board[0][4] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
      board[0][7] = const ChPiece(type: ChPieceType.rook, side: ChSide.child);
      board[7][4] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
      final s = _positionOf(board, ChSide.child,
        castleRights: const ChCastleRights(childK: true, childQ: false, parentK: false, parentQ: false));
      final castle = chessLegalMoves(s).where((m) => m.castle == 'K');
      expect(castle, isNotEmpty);
      final result = chessMove(s, castle.first.from, castle.first.to);
      expect(result.ok, isTrue);
      expect(result.state!.board[0][6]?.type, ChPieceType.king);
      expect(result.state!.board[0][5]?.type, ChPieceType.rook);
      expect(result.state!.board[0][7], isNull);
    });

    test('castling through an attacked square is refused', () {
      final board = _emptyBoard();
      board[0][4] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
      board[0][7] = const ChPiece(type: ChPieceType.rook, side: ChSide.child);
      board[7][4] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
      board[7][5] = const ChPiece(type: ChPieceType.rook, side: ChSide.parent); // rakes the f-file
      final s = _positionOf(board, ChSide.child,
        castleRights: const ChCastleRights(childK: true, childQ: false, parentK: false, parentQ: false));
      expect(chessLegalMoves(s).where((m) => m.castle == 'K'), isEmpty);
    });

    test('en passant: a double push can be captured immediately, never later', () {
      final board = _emptyBoard();
      board[0][4] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
      board[7][4] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
      board[1][3] = const ChPiece(type: ChPieceType.pawn, side: ChSide.child);
      board[3][4] = const ChPiece(type: ChPieceType.pawn, side: ChSide.parent);
      var s = _positionOf(board, ChSide.child);
      final push = chessMove(s, (1, 3), (3, 3));
      expect(push.ok, isTrue);
      s = push.state!;
      expect(s.enPassantTarget, (2, 3));
      final capture = chessMove(s, (3, 4), (2, 3));
      expect(capture.ok, isTrue);
      expect(capture.state!.board[3][3], isNull, reason: 'the passed pawn is removed');
      expect(capture.state!.board[2][3]?.side, ChSide.parent);
    });

    test('promotion requires a choice and is never silently auto-queened', () {
      final board = _emptyBoard();
      board[0][4] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
      board[7][4] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
      board[6][0] = const ChPiece(type: ChPieceType.pawn, side: ChSide.child);
      final s = _positionOf(board, ChSide.child);
      final noChoice = chessMove(s, (6, 0), (7, 0));
      expect(noChoice.ok, isFalse);
      expect(noChoice.reason, 'promotion_required');
      final knight = chessMove(s, (6, 0), (7, 0), promotion: ChPieceType.knight);
      expect(knight.ok, isTrue);
      expect(knight.state!.board[7][0]?.type, ChPieceType.knight);
    });

    test('stalemate ends the game as a draw, not a loss', () {
      final board = _emptyBoard();
      board[7][0] = const ChPiece(type: ChPieceType.king, side: ChSide.parent); // a8
      board[5][1] = const ChPiece(type: ChPieceType.king, side: ChSide.child); // b6
      board[6][7] = const ChPiece(type: ChPieceType.queen, side: ChSide.child); // h7
      final s = _positionOf(board, ChSide.child);
      final result = chessMove(s, (6, 7), (6, 2)); // queen h7 -> c7
      expect(result.ok, isTrue);
      expect(result.state!.outcome, ChessOutcome.drawStalemate);
      expect(isInCheck(result.state!.board, ChSide.parent), isFalse,
        reason: 'stalemate is specifically NOT check');
    });

    test('checkmate is detected the move it happens', () {
      final board = _emptyBoard();
      board[7][7] = const ChPiece(type: ChPieceType.king, side: ChSide.parent); // h8
      board[5][5] = const ChPiece(type: ChPieceType.king, side: ChSide.child); // f6
      board[0][6] = const ChPiece(type: ChPieceType.queen, side: ChSide.child); // g1
      final s = _positionOf(board, ChSide.child);
      final result = chessMove(s, (0, 6), (6, 6)); // queen g1 -> g7#
      expect(result.ok, isTrue);
      expect(result.state!.outcome, ChessOutcome.checkmateChild);
      expect(chessLegalMoves(result.state!), isEmpty);
    });

    test('threefold repetition is an automatic draw', () {
      final board = _emptyBoard();
      board[3][3] = const ChPiece(type: ChPieceType.king, side: ChSide.child); // d4
      board[7][3] = const ChPiece(type: ChPieceType.king, side: ChSide.parent); // d8
      board[0][0] = const ChPiece(type: ChPieceType.rook, side: ChSide.child); // keeps material sufficient
      var s = _positionOf(board, ChSide.child);
      ChessMoveResult step(ChCell from, ChCell to) {
        final r = chessMove(s, from, to);
        expect(r.ok, isTrue, reason: '$from -> $to should be legal (${r.reason})');
        s = r.state!;
        return r;
      }
      // Two full there-and-back cycles put every position on this 4-square
      // shuttle at count 2. The third repeat of the very first hop (child
      // d4-e4) is what tips it to a third occurrence — the rule fires on
      // the recurring POSITION, not specifically on "where the game began",
      // so this is deliberately checked one half-move before a naive
      // "three round trips" count would expect it.
      for (var cycle = 0; cycle < 2; cycle++) {
        step((3, 3), (3, 4)); // child d4-e4
        step((7, 3), (7, 4)); // parent d8-e8
        step((3, 4), (3, 3)); // child e4-d4
        step((7, 4), (7, 3)); // parent e8-d8 — back to the starting arrangement
      }
      final third = step((3, 3), (3, 4)); // child d4-e4 for the third time
      expect(third.state!.outcome, ChessOutcome.drawRepetition);
    });

    test('the fifty-move rule is an automatic draw', () {
      final board = _emptyBoard();
      board[3][3] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
      board[7][3] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
      board[0][0] = const ChPiece(type: ChPieceType.rook, side: ChSide.child);
      final s = _positionOf(board, ChSide.child, halfmoveClock: 99);
      final result = chessMove(s, (3, 3), (3, 4)); // a quiet move: 99 -> 100 half-moves
      expect(result.ok, isTrue);
      expect(result.state!.outcome, ChessOutcome.drawFiftyMove);
    });

    test('capturing down to king vs king is an automatic draw', () {
      final board = _emptyBoard();
      board[3][3] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
      board[7][3] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
      board[4][3] = const ChPiece(type: ChPieceType.knight, side: ChSide.parent);
      final s = _positionOf(board, ChSide.child);
      final result = chessMove(s, (3, 3), (4, 3)); // king takes the last non-king piece
      expect(result.ok, isTrue);
      expect(result.state!.outcome, ChessOutcome.drawInsufficientMaterial);
    });

    test('takebacks are free, unlimited, and replay from the start', () {
      var s = newChess();
      final r1 = chessMove(s, (1, 4), (3, 4));
      expect(r1.ok, isTrue);
      s = r1.state!;
      final r2 = chessMove(s, (6, 4), (4, 4));
      expect(r2.ok, isTrue);
      s = r2.state!;
      final undone = chessTakeBack(s);
      expect(undone.history.length, 1);
      expect(undone.turn, ChSide.parent, reason: 'only the childs move remains');
      expect(undone.board[3][4]?.side, ChSide.child);
      expect(undone.board[4][4], isNull);
    });

    group('§9.2 handicaps — she chooses what the PARENT gives up', () {
      test('no_queen removes the PARENT queen, never the childs own', () {
        final s = newChess(handicapId: 'no_queen');
        expect(s.board[0][3]?.type, ChPieceType.queen, reason: "child's own queen must stay");
        expect(s.board[0][3]?.side, ChSide.child);
        expect(s.board[7][3], isNull, reason: "parent's queen is what she took away");
      });

      test('no_queen_rooks clears exactly three parent squares', () {
        final s = newChess(handicapId: 'no_queen_rooks');
        expect(s.board[7][0], isNull);
        expect(s.board[7][3], isNull);
        expect(s.board[7][7], isNull);
        expect(s.board[7][4]?.type, ChPieceType.king, reason: 'the king is never a handicap');
      });
    });

    group('§9.1 "hint, don\'t solve" reused for chess — never algebraic notation', () {
      final notation = RegExp(r'\b[NBRQK]?[a-h][1-8]\b');

      test('a king in check is coached toward blocking or escaping', () {
        final board = _emptyBoard();
        board[3][3] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
        board[3][5] = const ChPiece(type: ChPieceType.rook, side: ChSide.child);
        board[0][0] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
        final s = _positionOf(board, ChSide.parent);
        final hint = chessCoach(s);
        expect(hint.toLowerCase(), contains('check'));
        expect(notation.hasMatch(hint), isFalse, reason: hint);
      });

      test('an available capture is flagged without naming the square', () {
        final board = _emptyBoard();
        board[0][0] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
        board[7][7] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
        // A parent knight, not the king itself, does the capturing — a pawn
        // sitting where the king could take it would also be giving check,
        // which is a different (and differently-coached) branch.
        board[4][4] = const ChPiece(type: ChPieceType.knight, side: ChSide.parent);
        board[2][3] = const ChPiece(type: ChPieceType.pawn, side: ChSide.child);
        final s = _positionOf(board, ChSide.parent);
        final hint = chessCoach(s);
        expect(hint.toLowerCase(), contains('undefended'));
        expect(notation.hasMatch(hint), isFalse, reason: hint);
      });

      test('early game nudges toward stuck pieces; later it asks about the last move', () {
        final board = _emptyBoard();
        board[0][0] = const ChPiece(type: ChPieceType.king, side: ChSide.child);
        board[7][7] = const ChPiece(type: ChPieceType.king, side: ChSide.parent);
        final early = _positionOf(board, ChSide.parent);
        expect(chessCoach(early).toLowerCase(), contains('cannot move'));
        const dummy = ChMove(from: (0, 0), to: (0, 0));
        final later = _positionOf(board, ChSide.parent, history: List<ChMove>.filled(6, dummy));
        expect(chessCoach(later).toLowerCase(), contains('last move was defending'));
      });
    });
  });

  group('chess screen — §9.2, P2', () {
    testWidgets('opens on a setup screen where SHE chooses the handicap', (t) async {
      await t.pumpWidget(wrap(const GameChess()));
      expect(find.text('You go first.'), findsOneWidget);
      expect(find.text('Want to make it harder for Dad?'), findsOneWidget);
      expect(find.text('No — play it straight'), findsOneWidget);
      for (final h in chessHandicaps) {
        expect(find.text(h.label), findsOneWidget);
      }
      final startButton = t.getSize(find.widgetWithText(FilledButton, 'Start game'));
      expect(startButton.height, greaterThanOrEqualTo(48));
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      // skipOffstage: false throughout this test — the screen scrolls once a
      // move is on the board, and an absence check that only looks at what
      // currently fits on screen would prove nothing about what's below the
      // fold.
      await t.pumpWidget(wrap(const GameChess()));
      expect(find.byIcon(Icons.settings, skipOffstage: false), findsNothing);
      expect(find.textContaining('Settings', skipOffstage: false), findsNothing);
      await t.tap(find.text('Start game'));
      await t.pump();
      expect(find.byIcon(Icons.settings, skipOffstage: false), findsNothing);
      expect(find.textContaining('Settings', skipOffstage: false), findsNothing);
    });

    testWidgets('P2 — no ELO, rank, score, or win/lose framing anywhere', (t) async {
      await t.pumpWidget(wrap(const GameChess()));
      await t.tap(find.text('Start game'));
      await t.pump();
      for (final forbidden in ['ELO', 'Rank', 'Score', 'You win', 'You lose', 'You lost', 'Winner', 'Loser']) {
        expect(find.textContaining(forbidden, skipOffstage: false), findsNothing, reason: forbidden);
      }
    });

    testWidgets('a real move: tap a piece, then a highlighted square, moves it', (t) async {
      await t.pumpWidget(wrap(const GameChess(botThinkDelay: Duration.zero)));
      await t.tap(find.text('Start game'));
      await t.pump();
      final cells = find.descendant(of: find.byType(GridView), matching: find.byType(GestureDetector));
      expect(cells, findsNWidgets(64));
      // Board index i maps to (r = 7 - i~/8, c = i%8); (1,4) is a child pawn's
      // start square, (3,4) is two squares ahead of it.
      await t.tap(cells.at((7 - 1) * 8 + 4));
      await t.pump();
      await t.tap(cells.at((7 - 3) * 8 + 4));
      await t.pump();
      expect(find.textContaining("is thinking", skipOffstage: false), findsOneWidget);
      // While it's the grown-up's turn, a coaching hint is shown, and it is
      // asserted here — not just at the engine level — to contain no
      // algebraic notation anywhere on screen. skipOffstage: false because
      // the board pushes some of this content below the fold on a small
      // test viewport, and a notation leak that's merely scrolled out of
      // view is still a notation leak.
      final notation = RegExp(r'\b[NBRQK]?[a-h][1-8]\b');
      for (final text in t.widgetList<Text>(find.byType(Text, skipOffstage: false))) {
        final data = text.data;
        if (data == null) continue;
        expect(notation.hasMatch(data), isFalse, reason: data);
      }
      await t.pumpAndSettle();
      expect(find.textContaining("Ivy's move", skipOffstage: false), findsOneWidget);
    });

    testWidgets('takeback is free: disabled with no history, enabled after one move', (t) async {
      await t.pumpWidget(wrap(const GameChess(botThinkDelay: Duration.zero)));
      await t.tap(find.text('Start game'));
      await t.pump();
      // skipOffstage: false — the button sits below the board, which scrolls
      // it out of the small test viewport once the board and a hint/banner
      // are both showing; that's a real, harmless scroll, not an absence.
      OutlinedButton takeBackButton() => t.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Take that back', skipOffstage: false));
      expect(takeBackButton().onPressed, isNull);
      final cells = find.descendant(of: find.byType(GridView), matching: find.byType(GestureDetector));
      await t.tap(cells.at((7 - 1) * 8 + 4));
      await t.pump();
      await t.tap(cells.at((7 - 3) * 8 + 4));
      await t.pump();
      expect(takeBackButton().onPressed, isNotNull);
      final btnSize = t.getSize(
        find.widgetWithText(OutlinedButton, 'Take that back', skipOffstage: false));
      expect(btnSize.height, greaterThanOrEqualTo(48));
      await t.pumpAndSettle(); // let the simulated grown-up's move finish before teardown
    });
  });
}
