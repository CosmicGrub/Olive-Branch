// OLIVE BRANCH — checkers. Verified by CI (a Flutter toolchain now runs for
// real in tools/verify.sh's automated pipeline — CHANGELOG v0.49.61).
// MASTERFILE §9.2, P2.
//
// The rules engine below (CkSide/CkPiece/CheckersState/checkersMoves/
// playCheckers/checkersCount) is a 1:1 semantic port of the `CHECKERS`
// section of packages/games/src/games2.ts — same function names, same
// shapes, same ordering — mirroring the discipline lock_controller.dart
// already applies when porting packages/child-lock/src/lock.ts. One
// deliberate narrowing: the TS `outcome` type is `Side | 'draw' | null`,
// but the checkers implementation itself never produces `'draw'` (only "no
// legal moves left" resolves a game), so the Dart port types `outcome` as
// `CkSide?` rather than carrying a draw variant that can never occur.
//
// §9.2 names three mechanics that separate this from a bare rules engine:
// compulsory captures (enforced by the engine, not by the UI hiding a
// square — a child tapping a non-jumping piece while a jump is available
// gets told why, never a silent no-op), multi-jump chains, and crowning
// ending a chain even mid-jump. A fourth, "a move can carry a voice note",
// is acknowledged honestly below as not built yet rather than faked.
//
// P2 governs the whole screen: no ELO, no rank, no win/loss record. Piece
// counts are shown only as a live in-game tally while play continues —
// the same posture games.ts's `childView()` takes with `boxesEach` — and
// disappear the moment the game ends, replaced by "Good game." regardless
// of who has more pieces on the board.
import 'dart:math';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// ============================================================ RULES ENGINE ==
enum CkSide { child, parent }

extension CkSideX on CkSide {
  CkSide get opposite => this == CkSide.child ? CkSide.parent : CkSide.child;
}

typedef CkCell = (int r, int c);

class CkPiece {
  const CkPiece({required this.side, required this.king});
  final CkSide side;
  final bool king;
  CkPiece copyWith({bool? king}) => CkPiece(side: side, king: king ?? this.king);
}

class CheckersState {
  const CheckersState({
    required this.board,
    required this.turn,
    required this.outcome,
    required this.mustContinueFrom,
  });
  final List<List<CkPiece?>> board;
  final CkSide turn;
  final CkSide? outcome;
  final CkCell? mustContinueFrom;
}

/// Parent's pieces start nearest row 0, child's nearest row 7 — matching
/// newCheckers() in games2.ts, where side B (parent) occupies rows 0-2 and
/// side A (child) occupies rows 5-7, on dark squares only.
CheckersState newCheckers() {
  final board = List<List<CkPiece?>>.generate(8, (_) => List<CkPiece?>.filled(8, null));
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 8; c++) {
      if ((r + c) % 2 == 1) board[r][c] = const CkPiece(side: CkSide.parent, king: false);
    }
  }
  for (var r = 5; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      if ((r + c) % 2 == 1) board[r][c] = const CkPiece(side: CkSide.child, king: false);
    }
  }
  return CheckersState(board: board, turn: CkSide.child, outcome: null, mustContinueFrom: null);
}

bool _inB(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

List<CkCell> _dirs(CkPiece p) {
  if (p.king) return const [(-1, -1), (-1, 1), (1, -1), (1, 1)];
  return p.side == CkSide.child ? const [(-1, -1), (-1, 1)] : const [(1, -1), (1, 1)];
}

class CkMove {
  const CkMove({required this.from, required this.to, required this.jumps});
  final CkCell from;
  final CkCell to;
  final List<CkCell> jumps;
}

/// All legal moves for [side]. Captures are MANDATORY: if any jump exists
/// anywhere on the board, only jumps are returned — a plain slide is not a
/// legal move at all while a capture is on offer, exactly as standard
/// draughts requires.
List<CkMove> checkersMoves(CheckersState s, CkSide side) {
  final jumps = <CkMove>[];
  final plain = <CkMove>[];
  void scan(int r, int c) {
    final p = s.board[r][c];
    if (p == null || p.side != side) return;
    for (final (dr, dc) in _dirs(p)) {
      final mr = r + dr, mc = c + dc, jr = r + 2 * dr, jc = c + 2 * dc;
      final mid = _inB(mr, mc) ? s.board[mr][mc] : null;
      if (_inB(jr, jc) && mid != null && mid.side != side && s.board[jr][jc] == null) {
        jumps.add(CkMove(from: (r, c), to: (jr, jc), jumps: [(mr, mc)]));
      } else if (_inB(mr, mc) && s.board[mr][mc] == null) {
        plain.add(CkMove(from: (r, c), to: (mr, mc), jumps: const []));
      }
    }
  }

  if (s.mustContinueFrom != null) {
    scan(s.mustContinueFrom!.$1, s.mustContinueFrom!.$2);
    return jumps;
  }
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      scan(r, c);
    }
  }
  return jumps.isNotEmpty ? jumps : plain;
}

class CkPlayResult {
  const CkPlayResult.ok(this.state) : reason = null;
  const CkPlayResult.err(this.reason) : state = null;
  final CheckersState? state;
  final String? reason;
  bool get ok => state != null;
}

List<List<CkPiece?>> _cloneBoard(List<List<CkPiece?>> b) =>
    [for (final row in b) [...row]];

CkPlayResult playCheckers(CheckersState s, CkSide side, CkCell from, CkCell to) {
  if (s.outcome != null) return const CkPlayResult.err('game_over');
  if (side != s.turn) return const CkPlayResult.err('not_your_turn');
  final legalMoves = checkersMoves(s, side);
  CkMove? legal;
  for (final m in legalMoves) {
    if (m.from == from && m.to == to) { legal = m; break; }
  }
  if (legal == null) {
    final anyJump = legalMoves.any((m) => m.jumps.isNotEmpty);
    return CkPlayResult.err(anyJump ? 'must_capture' : 'illegal_move');
  }
  final board = _cloneBoard(s.board);
  final p = board[from.$1][from.$2]!;
  board[from.$1][from.$2] = null;
  for (final (jr, jc) in legal.jumps) {
    board[jr][jc] = null;
  }
  // Crowning. A piece that reaches the far rank becomes a king and its
  // multi-jump ends there, regardless of whether another jump would
  // otherwise be available — §9.2's "crowning ends a chain".
  final crowned = !p.king &&
      ((side == CkSide.child && to.$1 == 0) || (side == CkSide.parent && to.$1 == 7));
  board[to.$1][to.$2] = CkPiece(side: side, king: p.king || crowned);

  CkCell? mustContinue;
  if (legal.jumps.isNotEmpty && !crowned) {
    final probe = CheckersState(board: board, turn: s.turn, outcome: null, mustContinueFrom: to);
    if (checkersMoves(probe, side).any((m) => m.jumps.isNotEmpty)) mustContinue = to;
  }
  final next = mustContinue != null ? side : side.opposite;
  var state = CheckersState(board: board, turn: next, outcome: null, mustContinueFrom: mustContinue);
  // A player with no legal move left loses.
  if (checkersMoves(state, next).isEmpty) {
    state = CheckersState(
      board: board, turn: next, mustContinueFrom: null,
      outcome: next == CkSide.child ? CkSide.parent : CkSide.child);
  }
  return CkPlayResult.ok(state);
}

int checkersCount(CheckersState s, CkSide side) =>
    s.board.expand((row) => row).where((p) => p?.side == side).length;

// ================================================================= WIDGET ===
class GameCheckers extends StatefulWidget {
  const GameCheckers({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.botThinkDelay = const Duration(milliseconds: 550),
  });

  final String childName;
  final String parentName;
  /// How long the simulated opponent "thinks" before replying. Exposed so
  /// tests can keep it short rather than because a real product setting
  /// belongs here — there is no settings affordance on this screen.
  final Duration botThinkDelay;

  @override
  State<GameCheckers> createState() => _GameCheckersState();
}

class _GameCheckersState extends State<GameCheckers> {
  CheckersState _state = newCheckers();
  final List<CheckersState> _history = [];
  CkCell? _selected;
  List<CkMove> _legalFromSelected = const [];
  bool _parentThinking = false;
  String? _hint;

  bool get _forcedJumpPending =>
      _state.outcome == null &&
      _state.turn == CkSide.child &&
      checkersMoves(_state, CkSide.child).any((m) => m.jumps.isNotEmpty);

  void _reset() {
    setState(() {
      _state = newCheckers();
      _history.clear();
      _selected = null;
      _legalFromSelected = const [];
      _parentThinking = false;
      _hint = null;
    });
  }

  void _selectPiece(CkCell cell) {
    final piece = _state.board[cell.$1][cell.$2];
    if (piece == null || piece.side != CkSide.child) return;
    final legal = checkersMoves(_state, CkSide.child).where((m) => m.from == cell).toList();
    if (legal.isEmpty) {
      // Compulsory-capture told kindly rather than a silent no-op — §9.2.
      setState(() => _hint = _forcedJumpPending
          ? "That one has to wait — another piece can jump!"
          : "That piece can't move right now.");
      return;
    }
    setState(() {
      _selected = cell;
      _legalFromSelected = legal;
      _hint = null;
    });
  }

  void _tapCell(int r, int c) {
    if (_state.outcome != null || _parentThinking) return;
    if (_state.turn != CkSide.child) return;
    final cell = (r, c);
    if (_selected == null) {
      _selectPiece(cell);
      return;
    }
    if (cell == _selected) {
      setState(() { _selected = null; _legalFromSelected = const []; });
      return;
    }
    final ownPieceHere = _state.board[r][c]?.side == CkSide.child;
    final isDestination = _legalFromSelected.any((m) => m.to == cell);
    if (!isDestination && ownPieceHere) {
      _selectPiece(cell);
      return;
    }
    if (!isDestination) return;
    _applyMove(CkSide.child, _selected!, cell);
  }

  void _applyMove(CkSide side, CkCell from, CkCell to) {
    final result = playCheckers(_state, side, from, to);
    if (!result.ok) return; // engine already vetted via _legalFromSelected
    _history.add(_state);
    setState(() {
      _state = result.state!;
      _hint = null;
      if (_state.mustContinueFrom != null && side == CkSide.child) {
        _selected = _state.mustContinueFrom;
        _legalFromSelected = checkersMoves(_state, CkSide.child);
      } else {
        _selected = null;
        _legalFromSelected = const [];
      }
    });
    if (_state.outcome == null &&
        _state.turn == CkSide.parent &&
        _state.mustContinueFrom == null) {
      _scheduleParentMove();
    } else if (_state.turn == CkSide.parent && _state.mustContinueFrom != null) {
      // Shouldn't happen (mustContinueFrom only persists same side to move),
      // guarded defensively so the bot never stalls the game.
      _scheduleParentMove();
    }
  }

  void _scheduleParentMove() {
    setState(() => _parentThinking = true);
    Future.delayed(widget.botThinkDelay, () {
      if (!mounted) return;
      final moves = checkersMoves(_state, CkSide.parent);
      if (moves.isEmpty) return; // outcome already resolved by the engine
      final pick = moves[Random().nextInt(moves.length)];
      _applyBotMove(pick);
    });
  }

  void _applyBotMove(CkMove m) {
    final result = playCheckers(_state, CkSide.parent, m.from, m.to);
    if (!result.ok) { setState(() => _parentThinking = false); return; }
    _history.add(_state);
    setState(() => _state = result.state!);
    if (_state.outcome == null && _state.turn == CkSide.parent) {
      // Parent is mid multi-jump — keep going.
      _scheduleParentMove();
    } else {
      setState(() => _parentThinking = false);
    }
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _state = _history.removeLast();
      _selected = null;
      _legalFromSelected = const [];
      _parentThinking = false;
      _hint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finished = _state.outcome != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkers'),
        actions: [
          IconButton(
            tooltip: 'Add a voice note',
            icon: const Icon(Icons.mic_none),
            onPressed: () => _notBuiltYetCk(context, 'Voice notes on moves'),
          ),
        ],
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // breakpoint.
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return ListView(padding: const EdgeInsets.all(16), children: [
          _TurnBanner(
            finished: finished,
            parentThinking: _parentThinking,
            childName: widget.childName,
            parentName: widget.parentName,
            isChildTurn: _state.turn == CkSide.child,
          ),
          if (_forcedJumpPending && !finished) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _CalloutBanner(text: 'A jump is waiting! Only jumping pieces can move.'),
          ),
          if (_hint != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _CalloutBanner(text: _hint!),
          ),
          const SizedBox(height: 12),
          if (!finished) _TallyRow(
            childName: widget.childName, parentName: widget.parentName,
            childCount: checkersCount(_state, CkSide.child),
            parentCount: checkersCount(_state, CkSide.parent),
          ) else const _GoodGameBanner(),
          const SizedBox(height: 12),
          Center(child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 460 : constraints.maxWidth),
            child: AspectRatio(aspectRatio: 1, child: _Board(
              state: _state, selected: _selected,
              legalDestinations: _legalFromSelected.map((m) => m.to).toSet(),
              onTapCell: _tapCell, scheme: scheme,
            )),
          )),
          const SizedBox(height: 16),
          // Wrap, not a Row: on the Fold5 cover screen (344 CSS px) "Take
          // that back" and "Play again" together don't fit on one line, and
          // this must wrap to a second row rather than overflow.
          Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
            SizedBox(height: 48, child: OutlinedButton.icon(
              key: const Key('ckUndo'),
              onPressed: _history.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo),
              label: const Text('Take that back'),
            )),
            if (finished) SizedBox(height: 48, child: FilledButton.icon(
              key: const Key('ckPlayAgain'),
              onPressed: _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Play again'),
            )),
          ]),
        ]);
      })),
    );
  }
}

void _notBuiltYetCk(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.finished, required this.parentThinking,
    required this.childName, required this.parentName, required this.isChildTurn});
  final bool finished, parentThinking, isChildTurn;
  final String childName, parentName;

  @override
  Widget build(BuildContext context) {
    final text = finished
        ? 'Good game.'
        : isChildTurn ? "$childName's move" : parentThinking
            ? "$parentName is thinking…" : "$parentName's move";
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({required this.childName, required this.parentName,
    required this.childCount, required this.parentCount});
  final String childName, parentName;
  final int childCount, parentCount;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _TallyChip(label: childName, count: childCount,
      color: Theme.of(context).colorScheme.primaryContainer)),
    const SizedBox(width: 12),
    Expanded(child: _TallyChip(label: parentName, count: parentCount,
      color: Theme.of(context).colorScheme.secondaryContainer)),
  ]);
}

class _TallyChip extends StatelessWidget {
  const _TallyChip({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text('$count', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    ]),
  );
}

class _GoodGameBanner extends StatelessWidget {
  const _GoodGameBanner();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16)),
    child: const Row(children: [
      Icon(Icons.emoji_events_outlined),
      SizedBox(width: 8),
      Expanded(child: Text('Good game.', style: TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );
}

class _CalloutBanner extends StatelessWidget {
  const _CalloutBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Board extends StatelessWidget {
  const _Board({required this.state, required this.selected,
    required this.legalDestinations, required this.onTapCell, required this.scheme});
  final CheckersState state;
  final CkCell? selected;
  final Set<CkCell> legalDestinations;
  final void Function(int r, int c) onTapCell;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      itemBuilder: (context, i) {
        final r = i ~/ 8, c = i % 8;
        final dark = (r + c) % 2 == 1;
        final piece = state.board[r][c];
        final isSelected = selected == (r, c);
        final isLegal = legalDestinations.contains((r, c));
        return GestureDetector(
          key: Key('ckCell_${r}_$c'),
          onTap: () => onTapCell(r, c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: !dark
                ? const Color(0xFFF3E9D8)
                : isSelected
                    ? scheme.primary.withValues(alpha: 0.55)
                    : isLegal
                        ? scheme.primary.withValues(alpha: 0.25)
                        : const Color(0xFF7A5230),
            child: piece == null ? null : Center(
              child: FractionallySizedBox(
                widthFactor: 0.72, heightFactor: 0.72,
                child: _PieceView(piece: piece),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _PieceView extends StatelessWidget {
  const _PieceView({required this.piece});
  final CkPiece piece;
  @override
  Widget build(BuildContext context) {
    final color = piece.side == CkSide.child ? const Color(0xFFE8735B) : const Color(0xFF4A3F8F);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2.5),
        // Soft and tinted toward the theme's own shadow role, not a flat
        // grey/black box-shadow.
        boxShadow: [
          BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.25),
              blurRadius: 3,
              offset: const Offset(0, 1.5)),
        ],
      ),
      child: piece.king
          ? const Center(child: Icon(Icons.star, color: Colors.white, size: 16))
          : null,
    );
  }
}
