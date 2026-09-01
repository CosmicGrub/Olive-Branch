// OLIVE BRANCH — Connect 4, the ad-hoc local board game. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). Network
// resilience & ad-hoc mode roadmap, Track B Option 2, ad-hoc games
// expansion. Builds on local_pairing.dart (shared foundation),
// connect4_engine.dart (board/rules), and connect4_bot.dart (CPU
// opponent). Second of five new local-play activities — proves the
// CPU-bot pattern and a persistent, accumulating board state, neither of
// which War (the first) needed.
//
// Two real modes, chosen at "found": a fully local vs-CPU game that never
// touches the transport at all (the bot's "thinking" never leaves this
// device, only its resulting column choice would if this were the network
// mode — here there's no peer to send to in the first place), and the
// real two-device network mode over local_pairing.dart, same pattern as
// game_war.dart.
//
// P2 (MASTERFILE §2.1) governs the whole screen: no score, no streak, no
// ELO, no "you lost" framing — game_tictactoe.dart's own convention
// ("Good game." / a plain fact, never a verdict) applies here too.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'connect4_bot.dart';
import 'connect4_engine.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;
import 'live_games.dart' show Side, auditLiveView;
import 'local_pairing.dart';

class GameConnect4Screen extends StatefulWidget {
  const GameConnect4Screen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  State<GameConnect4Screen> createState() => _GameConnect4ScreenState();
}

enum _Mode { none, vsCpu, vsPeer }

class _GameConnect4ScreenState extends State<GameConnect4Screen> {
  LocalPairingController? _pairing;
  StreamSubscription<LocalTurnPayload>? _turnSub;
  final _rand = Random();

  _Mode _mode = _Mode.none;
  Connect4Board _board = Connect4Board.empty();
  Side _toMove = Side.b; // dad moves first, matching every other fixed convention in this expansion
  Connect4Outcome _outcome = Connect4Outcome.none;
  Side? _winner;
  CpuDifficulty _difficulty = CpuDifficulty.medium;

  Side get _mySide => widget.role == 'ivy' ? Side.a : Side.b;

  void _startVsCpu() {
    setState(() {
      _mode = _Mode.vsCpu;
      _board = Connect4Board.empty();
      _toMove = Side.b;
      _outcome = Connect4Outcome.none;
      _winner = null;
    });
    _maybeCpuMove();
  }

  void _startVsPeer() {
    final pairing = LocalPairingController(role: widget.role, displayName: widget.displayName);
    _pairing = pairing;
    pairing.addListener(_onPairingChanged);
    _turnSub = pairing.incomingTurns.listen(_handleIncomingTurn);
    setState(() => _mode = _Mode.vsPeer);
    unawaited(pairing.start());
  }

  void _onPairingChanged() {
    if (mounted) setState(() {});
  }

  /// Only relevant in [_Mode.vsCpu] — the CPU seat is always Side.a here
  /// (the human is always Side.b, matching this device's own fixed
  /// identity when playing locally against a bot rather than a paired
  /// human). Runs synchronously; see connect4_bot.dart's own header on why
  /// a fixed, conservative depth per tier was chosen over an async
  /// wall-clock budget under real time pressure.
  void _maybeCpuMove() {
    if (_mode != _Mode.vsCpu || _outcome != Connect4Outcome.none || _toMove != Side.a) return;
    final col = chooseColumn(_board, Side.a, _difficulty, _rand);
    if (col < 0) return;
    _applyLocalMove(col, Side.a);
  }

  void _applyLocalMove(int col, Side side) {
    final result = applyMove(_board, col, side);
    if (!result.applied) return;
    setState(() {
      _board = result.board;
      _outcome = result.outcome;
      _winner = result.winner;
      _toMove = side == Side.a ? Side.b : Side.a;
    });
    if (_mode == _Mode.vsCpu) {
      // Give the "CPU is thinking" state a beat to actually render before
      // it moves — consequence motion, not an instant snap (§8.13).
      if (_outcome == Connect4Outcome.none && _toMove == Side.a) {
        Future.delayed(const Duration(milliseconds: 500), _maybeCpuMove);
      }
    }
  }

  Future<void> _tapColumn(int col) async {
    if (_outcome != Connect4Outcome.none) return;
    if (_mode == _Mode.vsCpu) {
      if (_toMove != Side.b) return; // human is always Side.b locally
      _applyLocalMove(col, Side.b);
      return;
    }
    // vsPeer
    if (_toMove != _mySide) return;
    final result = applyMove(_board, col, _mySide);
    if (!result.applied) return;
    setState(() {
      _board = result.board;
      _outcome = result.outcome;
      _winner = result.winner;
      _toMove = _mySide == Side.a ? Side.b : Side.a;
    });
    final payload = <String, dynamic>{'type': 'connect4_move', 'column': col};
    final audit = auditLiveView(payload);
    if (!audit.ok) {
      debugPrint('game_connect4: refusing to send a payload with forbidden keys: ${audit.leaks}');
      return;
    }
    await _pairing?.sendTurn(payload);
  }

  void _handleIncomingTurn(LocalTurnPayload payload) {
    if (payload['type'] != 'connect4_move') return;
    final col = payload['column'];
    if (col is! int) return;
    final side = _toMove; // whoever's turn it locally is must be who just moved on the wire
    final result = applyMove(_board, col, side);
    if (!result.applied) return; // a stale/foreign move must never crash local state
    if (mounted) {
      setState(() {
        _board = result.board;
        _outcome = result.outcome;
        _winner = result.winner;
        _toMove = side == Side.a ? Side.b : Side.a;
      });
    }
  }

  void _playAgain() {
    setState(() {
      _board = Connect4Board.empty();
      _toMove = Side.b;
      _outcome = Connect4Outcome.none;
      _winner = null;
    });
    if (_mode == _Mode.vsCpu) _maybeCpuMove();
  }

  @override
  void dispose() {
    unawaited(_turnSub?.cancel());
    _pairing?.removeListener(_onPairingChanged);
    _pairing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measured once, outside any scroll view — see game_uno.dart's own
    // build() for why this must happen above a LayoutBuilder, not inside
    // one nested in something scrollable.
    return LayoutBuilder(builder: (context, constraints) {
      final posture = ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
      // 7 real columns, each with its own 3dp padding, inside a
      // container with 8dp padding on every side — the REAL leftover
      // budget per cell, not a guessed constant that had no relationship
      // to whatever screen this actually renders on.
      final cellSize = ((constraints.maxWidth - 48 - 16) / 7).clamp(44.0, 84.0);
      final Widget body;
      if (_mode == _Mode.none) {
        body = _ModePicker(
          difficulty: _difficulty,
          onDifficulty: (d) => setState(() => _difficulty = d),
          onVsCpu: _startVsCpu,
          onVsPeer: _startVsPeer,
        );
      } else if (_mode == _Mode.vsCpu) {
        body = _BoardView(
          board: _board, outcome: _outcome, winner: _winner, toMove: _toMove,
          mySide: Side.b, peerName: 'the computer', onTapColumn: _tapColumn, onPlayAgain: _playAgain,
          cpuThinking: _toMove == Side.a && _outcome == Connect4Outcome.none, cellSize: cellSize,
        );
      } else {
        final pairing = _pairing!;
        final haveStartedPlaying = _board.discCount > 0 || _outcome != Connect4Outcome.none;
        if (pairing.phase == PairingPhase.error) {
          body = _MessageView(message: pairing.errorMessage ?? "Can't play locally right now.",
            icon: Icons.error_outline);
        } else if (haveStartedPlaying || pairing.phase == PairingPhase.found) {
          // No "deal" step needed here, unlike War — an empty board is
          // fully, deterministically derivable by both devices with zero
          // network round-trip, so "found" goes straight to a playable
          // board. A resumed peer (found again after a transient peerLost)
          // with a game already under way also lands here, not back at
          // searching — the same resume-not-restart pattern
          // local_play_screen.dart/game_war.dart already establish.
          body = _BoardView(
            board: _board, outcome: _outcome, winner: _winner, toMove: _toMove,
            mySide: _mySide, peerName: pairing.peer?.name ?? 'the other side',
            onTapColumn: _tapColumn, onPlayAgain: _playAgain, cpuThinking: false, cellSize: cellSize,
          );
        } else {
          body = switch (pairing.phase) {
            PairingPhase.searching => const _Status(message: 'Looking nearby…'),
            PairingPhase.peerLost =>
              _MessageView(message: pairing.errorMessage!, icon: Icons.wifi_off_outlined),
            PairingPhase.found => throw StateError('handled above'),
            PairingPhase.error => throw StateError('handled above'),
          };
        }
      }
      final outerPad = posture == ff.Posture.foldTabletop ? 12.0 : 24.0;
      return Scaffold(
        appBar: AppBar(title: const Text('Connect 4')),
        // SingleChildScrollView, not a bare Center — see game_uno.dart's own
        // build() for why: real-device testing at foldTabletop's ~420dp
        // height overflowed there, and this screen's 6-row board is just as
        // tall. Same child_home.dart/care_note.dart scroll convention.
        body: SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(outerPad),
          child: Center(child: body),
        )),
      );
    });
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.difficulty, required this.onDifficulty, required this.onVsCpu, required this.onVsPeer});
  final CpuDifficulty difficulty;
  final ValueChanged<CpuDifficulty> onDifficulty;
  final VoidCallback onVsCpu;
  final VoidCallback onVsPeer;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text('Connect 4', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 24),
    Text('Play the computer', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    SegmentedButton<CpuDifficulty>(
      segments: const [
        ButtonSegment(value: CpuDifficulty.easy, label: Text('Easy')),
        ButtonSegment(value: CpuDifficulty.medium, label: Text('Medium')),
        ButtonSegment(value: CpuDifficulty.hard, label: Text('Hard')),
      ],
      selected: {difficulty},
      onSelectionChanged: (s) => onDifficulty(s.first),
    ),
    const SizedBox(height: 12),
    FilledButton(onPressed: onVsCpu, child: const Text('Start')),
    const SizedBox(height: 32),
    Text('Or find someone nearby', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    OutlinedButton(onPressed: onVsPeer, child: const Text('Play nearby')),
  ]);
}

class _Status extends StatelessWidget {
  const _Status({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(message, style: Theme.of(context).textTheme.bodyLarge),
  ]);
}

class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.board, required this.outcome, required this.winner, required this.toMove,
    required this.mySide, required this.peerName, required this.onTapColumn, required this.onPlayAgain,
    required this.cpuThinking, required this.cellSize,
  });
  final Connect4Board board;
  final Connect4Outcome outcome;
  final Side? winner;
  final Side toMove;
  final Side mySide;
  final String peerName;
  final void Function(int col) onTapColumn;
  final VoidCallback onPlayAgain;
  final bool cpuThinking;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = outcome != Connect4Outcome.none;
    final myTurn = !finished && toMove == mySide;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (finished)
        Text(outcome == Connect4Outcome.draw ? 'Draw. Good game.' : 'Good game.',
          style: theme.textTheme.headlineSmall)
      else
        Text(cpuThinking ? "$peerName is thinking…" : myTurn ? 'Your turn' : "Waiting for $peerName…",
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 16),
      _Board(board: board, canPlay: myTurn, onTapColumn: onTapColumn, cellSize: cellSize),
      if (finished) ...[
        const SizedBox(height: 20),
        FilledButton(onPressed: onPlayAgain, child: const Text('Play again')),
      ],
    ]);
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.board, required this.canPlay, required this.onTapColumn, required this.cellSize});
  final Connect4Board board;
  final bool canPlay;
  final void Function(int col) onTapColumn;
  /// The REAL per-cell size this screen has room for — measured from the
  /// actual viewport by GameConnect4Screen.build(), not a fixed 44dp
  /// guess with no relationship to a Fold closed at 344dp or a desktop
  /// window past 1024dp.
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = connect4Rows - 1; row >= 0; row--)
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var col = 0; col < connect4Cols; col++)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: GestureDetector(
                    onTap: canPlay && !board.isColumnFull(col) ? () => onTapColumn(col) : null,
                    child: Container(
                      width: cellSize, height: cellSize,
                      constraints: const BoxConstraints(minWidth: 64 / 1.45, minHeight: 64 / 1.45),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: board.at(col, row) == null ? theme.colorScheme.surface : Colors.transparent,
                        border: Border.all(color: theme.colorScheme.outline, width: 1),
                      ),
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      child: board.at(col, row) == null ? null : _DroppedDisc(side: board.at(col, row)!, row: row, cellSize: cellSize),
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

}

/// A disc that falls into place from above the column when it first
/// appears — real, physical motion rather than an instant snap. Only ever
/// plays once, on this exact cell's first mount (an already-settled disc
/// never replays it just because the board rebuilds for some other
/// reason) — consequence motion under §8.13, triggered directly by the
/// move that placed it, never a loop.
class _DroppedDisc extends StatelessWidget {
  const _DroppedDisc({required this.side, required this.row, required this.cellSize});
  final Side side;
  final int row;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final fallDistance = (connect4Rows - row) * (cellSize + 6);
    final glyphScale = cellSize / 44; // scales the glyph with the real cell size, floor unchanged
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -fallDistance, end: 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeIn,
      builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
      child: Container(
        width: cellSize, height: cellSize,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _discColor(side),
          border: Border.all(color: Colors.black26, width: 1)),
        alignment: Alignment.center,
        // Colorblind-safe: shape/glyph, never color alone.
        child: side == Side.a
          ? Icon(Icons.change_history, size: 18 * glyphScale, color: Colors.white70)
          : Icon(Icons.circle, size: 14 * glyphScale, color: Colors.white70),
      ),
    );
  }
}

Color _discColor(Side side) => switch (side) {
  Side.a => Colors.amber.shade700,
  Side.b => Colors.indigo.shade400,
};

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(height: 16),
    Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
  ]);
}
