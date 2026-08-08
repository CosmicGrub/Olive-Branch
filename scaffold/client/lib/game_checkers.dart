// OLIVE BRANCH — checkers. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.2, P2.
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
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

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

// ======================================================= NETWORK HOOK ======
// A minimal, transport-agnostic seam for LIVE (non-local) network play —
// see MASTERFILE's network-play security review. This file stays entirely
// ignorant of WebSockets, HTTP, or any transport package; the real
// implementation (networked_checkers_channel.dart) imports THIS file for
// these types, never the other way, so there is no dependency cycle and a
// unit test can supply a trivial fake hook with no networking at all.
//
// When `GameCheckers.network` is null, every code path below behaves
// EXACTLY as it always has — local pass-and-play against the built-in
// simulated opponent. Supplying a hook is strictly additive.

/// One move as received from the remote peer, already shape- and
/// turn-validated by the SERVER (packages/game-sync/src/table.ts) and by the
/// transport layer — but the server deliberately never checks GAME legality
/// (it has never heard of checkers). That check happens HERE, via the exact
/// same `playCheckers` the local pass-and-play path already uses, before
/// the move is ever applied — defense in depth: never trust a move just
/// because it arrived over an authenticated channel.
class CkRemoteMove {
  const CkRemoteMove(this.from, this.to, this.continues);
  final CkCell from;
  final CkCell to;
  final bool continues;
}

enum CkNetStatus { connecting, waitingForPeer, active, ended }

/// Wires one live networked table into [GameCheckers].
class CkNetworkHook {
  const CkNetworkHook({
    required this.mySide,
    required this.onLocalMove,
    required this.remoteMoves,
    required this.status,
  });

  /// Which side of the board THIS device's player controls — assigned by
  /// the server at token-mint time, never chosen by this widget. The
  /// built-in simulated opponent never runs when a hook is supplied: the
  /// remote peer IS the opponent.
  final CkSide mySide;

  /// Called once, immediately after a LOCAL move (made by [mySide]) has
  /// already been validated and applied via the existing `playCheckers`
  /// path. `continues` mirrors `CheckersState.mustContinueFrom != null`
  /// after that move — i.e. whether this was mid multi-jump chain.
  final void Function(CkCell from, CkCell to, {required bool continues}) onLocalMove;

  /// Moves from the remote peer. Re-validated via `playCheckers` before
  /// being applied — see `_GameCheckersState._applyRemoteMove`. A move that
  /// fails that check is dropped, never applied.
  final Stream<CkRemoteMove> remoteMoves;

  /// Connection/table lifecycle, rendered as a banner rather than silently
  /// swallowed.
  final Stream<CkNetStatus> status;
}

// ================================================================= WIDGET ===
class GameCheckers extends StatefulWidget {
  const GameCheckers({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.botThinkDelay = const Duration(milliseconds: 550),
    this.network,
  });

  final String childName;
  final String parentName;
  /// How long the simulated opponent "thinks" before replying. Exposed so
  /// tests can keep it short rather than because a real product setting
  /// belongs here — there is no settings affordance on this screen.
  final Duration botThinkDelay;

  /// When non-null, this screen is a LIVE networked game instead of local
  /// pass-and-play: [CkNetworkHook.mySide] decides which side this device
  /// plays, remote moves arrive over the network instead of from the
  /// built-in simulated opponent (which is disabled entirely), and the
  /// undo control is disabled (undoing locally would desync the two boards
  /// — there is no "local-only" move in a live game).
  final CkNetworkHook? network;

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

  StreamSubscription<CkRemoteMove>? _remoteMoveSub;
  StreamSubscription<CkNetStatus>? _netStatusSub;
  CkNetStatus _netStatus = CkNetStatus.connecting;
  String? _netNotice;

  /// Which side THIS device's human player controls. Local pass-and-play
  /// (network == null) always plays the child's side, exactly as before —
  /// this getter changes nothing there; it only starts to matter once a
  /// [CkNetworkHook] assigns the local player the parent's side instead.
  CkSide get _localSide => widget.network?.mySide ?? CkSide.child;

  @override
  void initState() {
    super.initState();
    final net = widget.network;
    if (net != null) {
      _remoteMoveSub = net.remoteMoves.listen(_applyRemoteMove);
      _netStatusSub = net.status.listen((s) {
        if (!mounted) return;
        setState(() => _netStatus = s);
      });
    }
  }

  @override
  void dispose() {
    _remoteMoveSub?.cancel();
    _netStatusSub?.cancel();
    super.dispose();
  }

  bool get _forcedJumpPending =>
      _state.outcome == null &&
      _state.turn == _localSide &&
      checkersMoves(_state, _localSide).any((m) => m.jumps.isNotEmpty);

  void _reset() {
    if (widget.network != null) return; // a live table has no "play again" — see undo, same reasoning
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
    if (piece == null || piece.side != _localSide) return;
    final legal = checkersMoves(_state, _localSide).where((m) => m.from == cell).toList();
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
    // UX guard, not a security boundary: the server enforces table-active
    // and turn-order regardless (see game-sync's own T6) — this just avoids
    // sending a move the server would reject (and drop the connection for)
    // before the peer has even joined.
    if (widget.network != null && _netStatus != CkNetStatus.active) return;
    if (_state.turn != _localSide) return;
    final cell = (r, c);
    if (_selected == null) {
      _selectPiece(cell);
      return;
    }
    if (cell == _selected) {
      setState(() { _selected = null; _legalFromSelected = const []; });
      return;
    }
    final ownPieceHere = _state.board[r][c]?.side == _localSide;
    final isDestination = _legalFromSelected.any((m) => m.to == cell);
    if (!isDestination && ownPieceHere) {
      _selectPiece(cell);
      return;
    }
    if (!isDestination) return;
    _applyMove(_localSide, _selected!, cell);
  }

  void _applyMove(CkSide side, CkCell from, CkCell to) {
    final result = playCheckers(_state, side, from, to);
    if (!result.ok) return; // engine already vetted via _legalFromSelected
    _history.add(_state);
    final continued = result.state!.mustContinueFrom != null;
    setState(() {
      _state = result.state!;
      _hint = null;
      if (continued && side == _localSide) {
        _selected = _state.mustContinueFrom;
        _legalFromSelected = checkersMoves(_state, _localSide);
      } else {
        _selected = null;
        _legalFromSelected = const [];
      }
    });

    final net = widget.network;
    if (net != null) {
      // Networked: the remote peer is the opponent. Tell them about OUR
      // move; never run the built-in bot.
      if (side == _localSide) net.onLocalMove(from, to, continues: continued);
      return;
    }

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

  /// DEFENSE IN DEPTH — a move arriving over the network is never applied
  /// on trust. It is re-validated through the exact same pure engine
  /// (`playCheckers`) the local pass-and-play path already uses. A move
  /// that fails this check (an illegal move from an authenticated-but-
  /// compromised peer, or simple corruption) is dropped outright and
  /// surfaced as a notice — never silently applied, never crashes the UI.
  void _applyRemoteMove(CkRemoteMove m) {
    final remoteSide = _localSide.opposite;
    final result = playCheckers(_state, remoteSide, m.from, m.to);
    if (!result.ok) {
      setState(() => _netNotice = "Ignored an invalid move from the network (${result.reason}).");
      return;
    }
    _history.add(_state);
    setState(() {
      _state = result.state!;
      _hint = null;
      _netNotice = null;
      _selected = null;
      _legalFromSelected = const [];
    });
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
        final narrow = constraints.maxWidth < 420;
        final networked = widget.network != null;
        final waitingForPeer = networked &&
            (_netStatus == CkNetStatus.connecting || _netStatus == CkNetStatus.waitingForPeer);
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (networked && _netStatus == CkNetStatus.ended) const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _CalloutBanner(text: 'Connection to the other player ended.'),
          ),
          if (waitingForPeer) const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _CalloutBanner(text: 'Waiting for the other player to join…'),
          ),
          if (_netNotice != null) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CalloutBanner(text: _netNotice!),
          ),
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
            constraints: BoxConstraints(maxWidth: narrow ? constraints.maxWidth : 460),
            child: AspectRatio(aspectRatio: 1, child: _Board(
              state: _state, selected: _selected,
              legalDestinations: _legalFromSelected.map((m) => m.to).toSet(),
              onTapCell: _tapCell, scheme: scheme,
            )),
          )),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(height: 48, child: OutlinedButton.icon(
              key: const Key('ckUndo'),
              // Undo is local-board-only. In a live networked game the peer
              // never sees it, so it would desync the two boards — disabled
              // outright rather than pretending to work.
              onPressed: (networked || _history.isEmpty) ? null : _undo,
              icon: const Icon(Icons.undo),
              label: const Text('Take that back'),
            )),
            const SizedBox(width: 12),
            if (finished && !networked) SizedBox(height: 48, child: FilledButton.icon(
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
    const SizedBox(width: 10),
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
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text('$count', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
    ]),
  );
}

class _GoodGameBanner extends StatelessWidget {
  const _GoodGameBanner();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16)),
    child: const Row(children: [
      Icon(Icons.emoji_events_outlined),
      SizedBox(width: 10),
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
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: const TextStyle(fontSize: 13)),
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
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1.5))],
      ),
      child: piece.king
          ? const Center(child: Icon(Icons.star, color: Colors.white, size: 16))
          : null,
    );
  }
}
