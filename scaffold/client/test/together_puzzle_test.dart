// OLIVE BRANCH — together_puzzle.dart tests. Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic
// tests, no Flutter/widget/network involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/together_puzzle.dart';
import 'package:olive_client/live_games.dart' show Side;

void main() {
  group('newPuzzle', () {
    test('starts empty, unsolved, mover=Side.b', () {
      final s = newPuzzle('farmyard');
      expect(s.placedPieces, isEmpty);
      expect(s.solved, isFalse);
      expect(s.mover, Side.b);
    });
  });

  group('placePiece', () {
    test('a correct placement by the real mover is accepted and flips mover', () {
      final s = newPuzzle('farmyard');
      final r = placePiece(s, Side.b, 'cow', 'slot1');
      expect(r.accepted, isTrue);
      expect(r.state.placedPieces, {'cow'});
      expect(r.state.mover, Side.a);
    });

    test('an out-of-turn attempt is refused, state unchanged', () {
      final s = newPuzzle('farmyard'); // mover is Side.b
      final r = placePiece(s, Side.a, 'cow', 'slot1');
      expect(r.accepted, isFalse);
      expect(r.state.placedPieces, isEmpty);
    });

    test('a wrong slot is refused — never recorded as a "wrong attempt"', () {
      final s = newPuzzle('farmyard');
      final r = placePiece(s, Side.b, 'cow', 'slot2'); // cow's real slot is slot1
      expect(r.accepted, isFalse);
      expect(r.state.placedPieces, isEmpty);
    });

    test('an already-placed piece cannot be placed again', () {
      var s = newPuzzle('farmyard');
      s = placePiece(s, Side.b, 'cow', 'slot1').state;
      final r = placePiece(s, Side.a, 'cow', 'slot1');
      expect(r.accepted, isFalse);
    });

    test('an unknown puzzle id is refused, never crashes', () {
      const s = TogetherPuzzleState(puzzleId: 'no-such-puzzle', placedPieces: {}, mover: Side.b);
      final r = placePiece(s, Side.b, 'cow', 'slot1');
      expect(r.accepted, isFalse);
    });

    test('placing every real piece in its real slot solves the puzzle', () {
      var s = newPuzzle('farmyard');
      final def = puzzleFor('farmyard')!;
      for (final piece in def.pieces) {
        final r = placePiece(s, s.mover, piece.id, piece.correctSlotId);
        expect(r.accepted, isTrue, reason: 'placing ${piece.id} should be accepted');
        s = r.state;
      }
      expect(s.solved, isTrue);
      expect(s.placedPieces.length, def.pieces.length);
    });
  });

  group('mergeIncoming — the real safety property', () {
    test('a union never loses a placement already known locally', () {
      const local = TogetherPuzzleState(puzzleId: 'farmyard', placedPieces: {'cow', 'barn'}, mover: Side.a);
      final merged = mergeIncoming(local, placedPieces: const ['tractor'], mover: Side.b);
      expect(merged.placedPieces, {'cow', 'barn', 'tractor'});
    });

    test('a stale/duplicate incoming message is a safe no-op', () {
      const local = TogetherPuzzleState(puzzleId: 'farmyard', placedPieces: {'cow', 'barn'}, mover: Side.a);
      final merged = mergeIncoming(local, placedPieces: const ['cow'], mover: Side.a);
      expect(merged.placedPieces, {'cow', 'barn'});
    });

    test('an empty incoming list changes nothing but the mover', () {
      const local = TogetherPuzzleState(puzzleId: 'farmyard', placedPieces: {'cow'}, mover: Side.a);
      final merged = mergeIncoming(local, placedPieces: const [], mover: Side.b);
      expect(merged.placedPieces, {'cow'});
      expect(merged.mover, Side.b);
    });
  });

  group('real two-sided simulation', () {
    test('both devices converge on the same solved state, alternating movers', () {
      var a = newPuzzle('farmyard');
      var b = newPuzzle('farmyard');
      final def = puzzleFor('farmyard')!;
      for (final piece in def.pieces) {
        final mover = a.mover; // both sides agree on whose turn it is at every step
        expect(b.mover, mover);
        if (mover == Side.a) {
          final r = placePiece(a, Side.a, piece.id, piece.correctSlotId);
          expect(r.accepted, isTrue);
          a = r.state;
          b = mergeIncoming(b, placedPieces: [piece.id], mover: a.mover);
        } else {
          final r = placePiece(b, Side.b, piece.id, piece.correctSlotId);
          expect(r.accepted, isTrue);
          b = r.state;
          a = mergeIncoming(a, placedPieces: [piece.id], mover: b.mover);
        }
      }
      expect(a.solved, isTrue);
      expect(b.solved, isTrue);
      expect(a.placedPieces, b.placedPieces);
    });
  });
}
