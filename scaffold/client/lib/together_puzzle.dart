// OLIVE BRANCH — Piece It Together, the ad-hoc cooperative puzzle engine.
// No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs for real in tools/verify.sh's
// automated pipeline — CHANGELOG v0.49.61). Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion. Fourth of five
// new local-play activities — the first with no
// existing analogue anywhere in this codebase to reuse.
//
// Hand-rolled, not a TS port: same reasoning as war_deck.dart/
// connect4_engine.dart's own headers — no packages/games/src counterpart
// exists for this, and this file's whole reason to exist is a game that
// never touches a server at all. game_chess.dart already establishes real
// precedent for a hand-rolled, non-ported engine when that is the honest
// choice.
//
// WHY SHAPE-PLACEMENT, not a sliding/8-puzzle or a grid-reveal puzzle
// (both considered and rejected): a sliding puzzle carries a real,
// well-known correctness trap — not every shuffled arrangement is actually
// solvable (a parity constraint on the permutation), a sharp thing to get
// wrong in a first new engine, and a genre that's already frustrating for
// a young child even when solvable. A grid-reveal puzzle is mechanically
// the safest option but needs real pre-sliced illustration art, with no
// existing content pipeline in this codebase to lean on. Shape-placement
// needs neither: it's a direct assignment (piece -> its one correct slot),
// not a permutation-shift mechanic, so there is no unsolvable-board class
// of bug to worry about at all, and pieces are small code-drawn vector
// glyphs (colouring_screen.dart's own Path-based, not raster, tradition),
// not full illustrations.
//
// COOPERATIVE BY CONSTRUCTION: a wrong-slot drop is rejected on-screen
// (game_puzzle.dart's own DragTarget.onWillAcceptWithDetails) and never
// reaches this file at all — there is no "wrong placement" representable
// in [TogetherPuzzleState], on the wire or off it, matching P2's own
// "nothing resembling a mistake" discipline. [placedPieces] only ever
// grows, which is also what makes [mergeIncoming] safe: a union of two
// monotonically-growing sets can never lose data or need real conflict
// resolution, unlike a map that could record a wrong placement and would
// then need to decide whose "wrong" wins.
library;

import 'live_games.dart' show Side;

class PuzzlePiece {
  const PuzzlePiece({required this.id, required this.label, required this.correctSlotId});
  final String id;
  final String label;
  final String correctSlotId;
}

class PuzzleSlot {
  const PuzzleSlot({required this.id, required this.label});
  final String id;
  final String label;
}

class PuzzleDef {
  const PuzzleDef({required this.id, required this.pieces, required this.slots});
  final String id;
  final List<PuzzlePiece> pieces;
  final List<PuzzleSlot> slots;
}

/// One MVP puzzle catalogue entry, deliberately — matching this whole
/// expansion's "prove one real thing" discipline. Content authored here,
/// not fetched or user-generated: puzzleId and every pieceId are fixed,
/// curated, in-repo constants, the same discipline guessDoodleWords holds
/// itself to for live_games.dart's own Pictionary deck.
const PuzzleDef farmyardPuzzle = PuzzleDef(
  id: 'farmyard',
  pieces: [
    PuzzlePiece(id: 'cow', label: 'Cow', correctSlotId: 'slot1'),
    PuzzlePiece(id: 'barn', label: 'Barn', correctSlotId: 'slot2'),
    PuzzlePiece(id: 'tractor', label: 'Tractor', correctSlotId: 'slot3'),
    PuzzlePiece(id: 'sun', label: 'Sun', correctSlotId: 'slot4'),
    PuzzlePiece(id: 'tree', label: 'Tree', correctSlotId: 'slot5'),
    PuzzlePiece(id: 'fence', label: 'Fence', correctSlotId: 'slot6'),
  ],
  slots: [
    PuzzleSlot(id: 'slot1', label: 'Cow spot'),
    PuzzleSlot(id: 'slot2', label: 'Barn spot'),
    PuzzleSlot(id: 'slot3', label: 'Tractor spot'),
    PuzzleSlot(id: 'slot4', label: 'Sun spot'),
    PuzzleSlot(id: 'slot5', label: 'Tree spot'),
    PuzzleSlot(id: 'slot6', label: 'Fence spot'),
  ],
);

const List<PuzzleDef> puzzleCatalogue = [farmyardPuzzle];

PuzzleDef? puzzleFor(String id) {
  for (final p in puzzleCatalogue) {
    if (p.id == id) return p;
  }
  return null;
}

PuzzlePiece? pieceFor(PuzzleDef def, String pieceId) {
  for (final p in def.pieces) {
    if (p.id == pieceId) return p;
  }
  return null;
}

class TogetherPuzzleState {
  const TogetherPuzzleState({required this.puzzleId, required this.placedPieces, required this.mover});
  final String puzzleId;

  /// Monotonically growing — see this file's own header on why that's
  /// what makes [mergeIncoming] safe. Never a map, never records a wrong
  /// attempt.
  final Set<String> placedPieces;
  final Side mover;

  bool get solved {
    final def = puzzleFor(puzzleId);
    if (def == null) return false;
    return placedPieces.length == def.pieces.length;
  }
}

/// No bootstrap turn needed — MVP has exactly one puzzle, so puzzleId
/// needs no negotiation, and "start of session = zero pieces placed,
/// mover: Side.b" is fully derivable by both devices with zero network
/// round-trip, matching the same convention every other game in this
/// expansion fixes for its own first mover.
TogetherPuzzleState newPuzzle(String puzzleId) =>
    TogetherPuzzleState(puzzleId: puzzleId, placedPieces: const <String>{}, mover: Side.b);

class PlaceResult {
  const PlaceResult({required this.state, required this.accepted});
  final TogetherPuzzleState state;
  final bool accepted;
}

/// Attempts to place [pieceId] into [slotId] as [side]. Re-validated here,
/// not just trusted because the sending UI disabled dragging — mirrors
/// game_war.dart's/game_connect4.dart's own "only the leader/mover acts"
/// re-check on receipt, the same real discipline for the same real reason
/// (this transport has no auth beyond same-LAN presence). A wrong slot, an
/// out-of-turn attempt, or an already-placed piece are all simply
/// refused — never a crash, never new state.
PlaceResult placePiece(TogetherPuzzleState state, Side side, String pieceId, String slotId) {
  if (side != state.mover) return PlaceResult(state: state, accepted: false);
  if (state.placedPieces.contains(pieceId)) return PlaceResult(state: state, accepted: false);
  final def = puzzleFor(state.puzzleId);
  if (def == null) return PlaceResult(state: state, accepted: false);
  final piece = pieceFor(def, pieceId);
  if (piece == null || piece.correctSlotId != slotId) return PlaceResult(state: state, accepted: false);
  final newPlaced = <String>{...state.placedPieces, pieceId};
  final newMover = side == Side.a ? Side.b : Side.a;
  return PlaceResult(
    state: TogetherPuzzleState(puzzleId: state.puzzleId, placedPieces: newPlaced, mover: newMover),
    accepted: true,
  );
}

/// Unions incoming placements into local state — never overwrites. A
/// stray, duplicate, or out-of-order network message can only ever ADD to
/// [TogetherPuzzleState.placedPieces], never remove from it, which is what
/// makes this safe with no real conflict-resolution logic needed at all.
/// [mover] is still taken from the incoming payload (whoever sent it knows
/// whose turn is next), not re-derived locally.
TogetherPuzzleState mergeIncoming(TogetherPuzzleState local, {required List<String> placedPieces, required Side mover}) {
  final merged = <String>{...local.placedPieces, ...placedPieces};
  return TogetherPuzzleState(puzzleId: local.puzzleId, placedPieces: merged, mover: mover);
}
