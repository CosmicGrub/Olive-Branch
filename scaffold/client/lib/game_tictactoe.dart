// OLIVE BRANCH — three in a row (tic-tac-toe). UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §9.2, P2.
//
// A 1:1 semantic port of the 'tictactoe' branch of packages/games/src/
// games.ts's generic game engine (newGame()'s tictactoe base, play()'s
// tictactoe branch — including its no_centre handicap check enforced at the
// move-validation layer, not just hidden in the UI — tttOutcome(), and
// takeBack()) plus setHandicap()'s tictactoe-relevant side effect
// (child_first), narrowed to just this one game kind, the same discipline
// game_chess.dart/game_checkers.dart apply to their own slices of the games
// engine.
//
// Reuses `Side` from game_logic.dart ("A = child, B = parent, always")
// directly, rather than inventing a second side type — a deliberate choice
// for THIS file, unlike game_story.dart's own `StorySide` (that file's own
// header explains it invents one specifically so a screen importing more
// than one of these game files never hits an ambiguous top-level `Side`).
// This file already imports game_logic.dart for `GameKind`/`catalogueFor`/
// `handicapBanner`/`HandicapScreen` — tic-tac-toe and dots-and-boxes both
// do, and both are wired from the same child_home.dart onPlay switch — so
// there is exactly one `Side` in scope either way, and reusing it (rather
// than adding a differently-named third alternative) is the simpler choice
// here.
//
// §9.2's handicap system is reused wholesale rather than re-invented: THIS
// game is already a real entry in game_logic.dart's shared `catalogue`
// (`no_centre` / `child_first`), so setup goes through the existing,
// reusable `HandicapScreen` rather than a bespoke setup screen of this
// file's own (contrast game_chess.dart, which built its own because chess
// isn't in that shared catalogue at all). The game therefore starts
// immediately with no handicap active — the same "no setup gate"
// simplicity as game_story.dart — and a "Make it fair" AppBar action opens
// `HandicapScreen`, whose own doc comment promises a handicap can change
// "any time — even mid-game." `_applyHandicap` below honors that literally:
// it mirrors games.ts's own `setHandicap()`, which mutates the CURRENT
// `GameState` in place (board and moves untouched, only `handicap` and any
// immediate side effect) rather than starting a fresh game — a full restart
// would silently break the "even mid-game" promise the picker screen makes
// to her.
//
// As in game_chess.dart/game_checkers.dart: the "parent" is a simulated
// local opponent (a uniformly random legal move, after a short "thinking"
// pause) because this preview build has no session runtime to relay moves
// between two real devices — not a "smarter" AI, and never deliberately
// losing. A move carrying a voice note (§9.2's third mechanic) is
// acknowledged honestly as not built here, for the same reason those files
// give: no audio-capture infrastructure exists yet in this codebase.
//
// P2 governs the whole screen: no ELO, no rank, no streak, no "you lost"
// screen. A finished game — win or draw — closes with a plain factual line
// ("Good game." / "Draw. Good game.") never a verdict on her.
//
// Layout is driven by the real §8.11.1 posture system (form_factors.dart),
// not a hand-rolled per-screen pixel breakpoint — that file's own header
// names exactly that anti-pattern, and court_export.dart is its established
// consumer. At `foldCover`/`phone`/`tabletSmall` (1 column) the board is the
// only thing on screen, full width, with the turn banner/handicap
// banner/buttons stacked below it in a `Wrap`. At `foldMain`/`tabletLarge`+
// (2+ columns, `columnsAt() >= 2`) the board shares the screen with a
// persistent side panel carrying the same banners plus a full-width
// `Column` of buttons — genuinely more layout, not the same stacked layout
// scaled up, mirroring game_picker.dart's own column breakpoint in spirit.
import 'dart:math';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'game_logic.dart';
import 'handicap_screen.dart';

// ============================================================ RULES ENGINE ==

/// Mirrors games.ts's generic `outcome` union narrowed to what tic-tac-toe
/// can actually produce: a winning side or a draw. (TS's union also allows
/// `'done'` for the co-op story game and stays `null` while play continues —
/// neither is a distinct case here; `null` is simply `TttState.outcome`.)
enum TttOutcome { childWin, parentWin, draw }

class TttMove {
  const TttMove({required this.side, required this.at});
  final Side side;
  final int at;
}

class TttState {
  const TttState({
    required this.board,
    required this.turn,
    required this.moves,
    required this.outcome,
    required this.handicap,
  });
  /// Length 9, index-major left-to-right/top-to-bottom — null is empty.
  final List<Side?> board;
  final Side turn;
  final List<TttMove> moves;
  final TttOutcome? outcome;
  final String? handicap;
}

/// New game. §9.2 — the child always moves first, same default as every
/// other game in games.ts's newGame().
TttState newTicTacToe() => const TttState(
      board: [null, null, null, null, null, null, null, null, null],
      turn: Side.a,
      moves: [],
      outcome: null,
      handicap: null,
    );

const List<List<int>> _tttLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // columns
  [0, 4, 8], [2, 4, 6], // diagonals
];

TttOutcome? _tttOutcomeFor(List<Side?> b) {
  for (final line in _tttLines) {
    final a = b[line[0]], c = b[line[1]], d = b[line[2]];
    if (a != null && a == c && c == d) return a == Side.a ? TttOutcome.childWin : TttOutcome.parentWin;
  }
  return b.every((x) => x != null) ? TttOutcome.draw : null;
}

class TttPlayResult {
  const TttPlayResult.ok(this.state) : reason = null;
  const TttPlayResult.err(this.reason) : state = null;
  final TttState? state;
  /// 'not_your_turn' | 'game_over' | 'occupied' | 'out_of_range' |
  /// 'handicap_forbids' — mirrors games.ts's `MoveError` union, restricted
  /// to the reasons this branch can actually produce.
  final String? reason;
  bool get ok => state != null;
}

/// Applies one move. Mirrors games.ts's `play()` tictactoe branch, including
/// the `no_centre` handicap check — enforced here, at the engine, exactly as
/// the source comment insists: "the engine enforces it rather than trusting
/// the UI to hide the square."
TttPlayResult tttPlay(TttState g, Side side, int at) {
  if (g.outcome != null) return const TttPlayResult.err('game_over');
  if (side != g.turn) return const TttPlayResult.err('not_your_turn');
  if (at < 0 || at > 8) return const TttPlayResult.err('out_of_range');
  if (g.board[at] != null) return const TttPlayResult.err('occupied');
  if (g.handicap == 'no_centre' && side == Side.b && at == 4) {
    return const TttPlayResult.err('handicap_forbids');
  }
  final board = [...g.board];
  board[at] = side;
  final moves = [...g.moves, TttMove(side: side, at: at)];
  return TttPlayResult.ok(TttState(
    board: board,
    turn: side == Side.a ? Side.b : Side.a,
    moves: moves,
    outcome: _tttOutcomeFor(board),
    handicap: g.handicap,
  ));
}

/// Every square [side] may legally play right now — used to pick the
/// simulated parent's move, so the bot's own candidate pool already honors
/// `no_centre` rather than relying on `tttPlay` to reject a bad pick.
List<int> tttLegalMoves(TttState g, Side side) {
  final moves = <int>[];
  for (var i = 0; i < 9; i++) {
    if (g.board[i] != null) continue;
    if (g.handicap == 'no_centre' && side == Side.b && i == 4) continue;
    moves.add(i);
  }
  return moves;
}

class TttSetHandicapResult {
  const TttSetHandicapResult.ok(this.state) : refusal = null;
  const TttSetHandicapResult.refused(this.refusal) : state = null;
  final TttState? state;
  /// 'child_only' | 'unknown' — mirrors games.ts's `setHandicap` refusal
  /// union.
  final String? refusal;
  bool get ok => state != null;
}

/// §9.2 — only the child may set a handicap, and only on the parent; refused
/// unconditionally before the id is even looked at, matching games.ts's own
/// `setHandicap()`. Mutates the CURRENT state's `handicap` field (and, for
/// `child_first`, `turn`) rather than starting a fresh game — see the file
/// header on why that specific fidelity matters here.
TttSetHandicapResult tttSetHandicap(TttState g, Side bySide, String? handicapId) {
  if (bySide != Side.a) return const TttSetHandicapResult.refused('child_only');
  if (handicapId != null &&
      !catalogueFor(GameKind.tictactoe).handicaps.any((h) => h.id == handicapId)) {
    return const TttSetHandicapResult.refused('unknown');
  }
  var turn = g.turn;
  if (handicapId == 'child_first') turn = Side.a;
  return TttSetHandicapResult.ok(TttState(
    board: g.board, turn: turn, moves: g.moves, outcome: g.outcome, handicap: handicapId,
  ));
}

/// Free, unlimited takebacks (§9.2) — implemented by replaying from the
/// start, same reasoning as games.ts's own `takeBack()` doc comment and
/// game_chess.dart's `chessTakeBack()`: inverting the last move is where
/// takeback bugs live.
TttState tttTakeBack(TttState g) {
  if (g.moves.isEmpty) return g;
  final keep = g.moves.sublist(0, g.moves.length - 1);
  var s = newTicTacToe();
  if (g.handicap != null) {
    final r = tttSetHandicap(s, Side.a, g.handicap);
    if (r.ok) s = r.state!;
  }
  for (final m in keep) {
    final r = tttPlay(s, m.side, m.at);
    if (r.ok) s = r.state!;
  }
  return s;
}

// ================================================================= WIDGET ===
class GameTicTacToe extends StatefulWidget {
  const GameTicTacToe({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.botThinkDelay = const Duration(milliseconds: 550),
  });

  final String childName;
  final String parentName;
  /// How long the simulated opponent "thinks" before replying. Exposed for
  /// tests, not because a settings affordance belongs on this screen —
  /// there is none, anywhere in this file.
  final Duration botThinkDelay;

  @override
  State<GameTicTacToe> createState() => _GameTicTacToeState();
}

class _GameTicTacToeState extends State<GameTicTacToe> {
  TttState _state = newTicTacToe();
  bool _parentThinking = false;

  void _tapCell(int i) {
    if (_state.outcome != null || _parentThinking || _state.turn != Side.a) return;
    final result = tttPlay(_state, Side.a, i);
    if (!result.ok) return;
    setState(() => _state = result.state!);
    if (_state.outcome == null && _state.turn == Side.b) _scheduleParentMove();
  }

  void _scheduleParentMove() {
    setState(() => _parentThinking = true);
    Future.delayed(widget.botThinkDelay, () {
      if (!mounted) return;
      // A pending timer can outlive a takeback or a mid-game handicap
      // change that already handed the turn elsewhere — guard rather than
      // let a stale callback play a move that is no longer the parent's.
      if (_state.outcome != null || _state.turn != Side.b) {
        setState(() => _parentThinking = false);
        return;
      }
      final moves = tttLegalMoves(_state, Side.b);
      if (moves.isEmpty) {
        setState(() => _parentThinking = false);
        return;
      }
      final pick = moves[Random().nextInt(moves.length)];
      final result = tttPlay(_state, Side.b, pick);
      setState(() {
        _parentThinking = false;
        if (result.ok) _state = result.state!;
      });
    });
  }

  void _takeBack() {
    if (_state.moves.isEmpty) return;
    setState(() {
      _state = tttTakeBack(_state);
      _parentThinking = false;
    });
  }

  void _playAgain() {
    setState(() {
      var s = newTicTacToe();
      if (_state.handicap != null) {
        final r = tttSetHandicap(s, Side.a, _state.handicap);
        if (r.ok) s = r.state!;
      }
      _state = s;
      _parentThinking = false;
    });
  }

  void _applyHandicap(String? id) {
    final result = tttSetHandicap(_state, Side.a, id);
    if (!result.ok) return; // defense in depth — see handicap_screen.dart's own note
    setState(() {
      _state = result.state!;
      // child_first can hand the turn straight back to her while the
      // simulated parent's "thinking" timer is still pending (found during
      // adversarial self-verify) — clear the stale indicator now rather
      // than leave it showing "$parentName is thinking…" until that timer
      // eventually fires and self-corrects. The pending timer itself is
      // still safely guarded by _scheduleParentMove's own turn/outcome
      // re-check either way.
      _parentThinking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finished = _state.outcome != null;
    final banner = handicapBanner(GameKind.tictactoe, _state.handicap);
    return Scaffold(
      appBar: AppBar(
        title: Text(catalogueFor(GameKind.tictactoe).title),
        actions: [
          IconButton(
            tooltip: 'Make it fair',
            icon: const Icon(Icons.balance_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => HandicapScreen(
                kind: GameKind.tictactoe,
                currentHandicapId: _state.handicap,
                onChanged: _applyHandicap,
              ),
            )),
          ),
          IconButton(
            tooltip: 'Add a voice note',
            icon: const Icon(Icons.mic_none),
            onPressed: () => _notBuiltYetTtt(context, 'Voice notes on moves'),
          ),
        ],
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — same technique court_export.dart already established:
        // two genuine layout columns available at the current text scale
        // means room for a persistent side panel, not just "wide enough to
        // avoid overflow".
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;

        final boardView = AspectRatio(aspectRatio: 1, child: _TttBoardView(
          state: _state, onTapCell: _tapCell, scheme: scheme,
        ));
        // Only the narrow, single-column layout caps the board's width —
        // inside the wide layout's Expanded it should simply fill whatever
        // room the side panel leaves it.
        final board = Center(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: narrow ? constraints.maxWidth : 460),
          child: boardView,
        ));

        if (!wide) {
          // foldCover/phone/tabletSmall (1 column): the board is the only
          // thing that matters — full width, everything else stacked below.
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (banner != null) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CalloutBanner(text: banner)),
            _TurnBanner(finished: finished, parentThinking: _parentThinking,
              childName: widget.childName, parentName: widget.parentName,
              isChildTurn: _state.turn == Side.a),
            if (finished) Padding(padding: const EdgeInsets.only(top: 8),
              child: _EndBanner(line: _state.outcome == TttOutcome.draw ? 'Draw. Good game.' : 'Good game.')),
            const SizedBox(height: 12),
            board,
            const SizedBox(height: 16),
            // Wrap, not a Row: on the Fold5 cover screen (344 CSS px) "Take
            // that back" plus a "Play again" button once the game finishes
            // don't fit on one line — this must wrap, never overflow, same
            // regression game_chess.dart's and game_checkers.dart's own
            // comments describe.
            _ButtonsWrap(canTakeBack: _state.moves.isNotEmpty, onTakeBack: _takeBack,
              finished: finished, onPlayAgain: _playAgain),
          ]);
        }

        // foldMain/tabletLarge+ (2+ columns): the board shares the screen
        // with a persistent side panel — genuinely more layout, not the
        // narrow layout scaled up: a real Column of full-width buttons, not
        // the same Wrap that merely stops reflowing once there's room.
        return Padding(padding: const EdgeInsets.all(16), child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560), child: boardView))),
            const SizedBox(width: 24),
            SizedBox(
              key: const Key('tttSidePanel'),
              width: 260,
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null) Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: _CalloutBanner(text: banner)),
                  _TurnBanner(finished: finished, parentThinking: _parentThinking,
                    childName: widget.childName, parentName: widget.parentName,
                    isChildTurn: _state.turn == Side.a),
                  if (finished) Padding(padding: const EdgeInsets.only(top: 8),
                    child: _EndBanner(
                      line: _state.outcome == TttOutcome.draw ? 'Draw. Good game.' : 'Good game.')),
                  const SizedBox(height: 20),
                  _ButtonsColumn(canTakeBack: _state.moves.isNotEmpty, onTakeBack: _takeBack,
                    finished: finished, onPlayAgain: _playAgain),
                ],
              )),
            ),
          ],
        ));
      })),
    );
  }
}

void _notBuiltYetTtt(BuildContext context, String what) {
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
    final text = finished ? 'Good game.'
        : isChildTurn ? "$childName's move"
        : parentThinking ? "$parentName is thinking…" : "$parentName's move";
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _EndBanner extends StatelessWidget {
  const _EndBanner({required this.line});
  final String line;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      const Icon(Icons.emoji_events_outlined),
      const SizedBox(width: 8),
      Expanded(child: Text(line, style: const TextStyle(fontWeight: FontWeight.w600))),
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
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// The narrow-layout control row — a `Wrap`, not a `Row`: on the Fold5
/// cover screen (344 CSS px) "Take that back" plus a "Play again" button
/// once the game finishes don't fit on one line, and this must wrap rather
/// than overflow.
class _ButtonsWrap extends StatelessWidget {
  const _ButtonsWrap({required this.canTakeBack, required this.onTakeBack,
    required this.finished, required this.onPlayAgain});
  final bool canTakeBack, finished;
  final VoidCallback onTakeBack, onPlayAgain;
  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, children: [
    SizedBox(height: 48, child: OutlinedButton.icon(
      key: const Key('tttTakeBack'),
      onPressed: canTakeBack ? onTakeBack : null,
      icon: const Icon(Icons.undo),
      label: const Text('Take that back'),
    )),
    if (finished) SizedBox(height: 48, child: FilledButton.icon(
      key: const Key('tttPlayAgain'),
      onPressed: onPlayAgain,
      icon: const Icon(Icons.refresh),
      label: const Text('Play again'),
    )),
  ]);
}

/// The wide-layout (side panel) control column — deliberately a real
/// `Column` of full-width buttons, not the narrow layout's `Wrap` merely
/// given enough room to stop reflowing; §8.11.1's persistent-side-panel
/// posture gets its own genuine layout.
class _ButtonsColumn extends StatelessWidget {
  const _ButtonsColumn({required this.canTakeBack, required this.onTakeBack,
    required this.finished, required this.onPlayAgain});
  final bool canTakeBack, finished;
  final VoidCallback onTakeBack, onPlayAgain;
  @override
  Widget build(BuildContext context) => Column(children: [
    SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
      key: const Key('tttTakeBack'),
      onPressed: canTakeBack ? onTakeBack : null,
      icon: const Icon(Icons.undo),
      label: const Text('Take that back'),
    )),
    if (finished) ...[
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48, child: FilledButton.icon(
        key: const Key('tttPlayAgain'),
        onPressed: onPlayAgain,
        icon: const Icon(Icons.refresh),
        label: const Text('Play again'),
      )),
    ],
  ]);
}

class _TttBoardView extends StatelessWidget {
  const _TttBoardView({required this.state, required this.onTapCell, required this.scheme});
  final TttState state;
  final ValueChanged<int> onTapCell;
  final ColorScheme scheme;

  static const _childColor = Color(0xFFE8735B);
  static const _parentColor = Color(0xFF4A3F8F);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
      itemCount: 9,
      itemBuilder: (context, i) {
        final side = state.board[i];
        return GestureDetector(
          key: Key('tttCell_$i'),
          onTap: () => onTapCell(i),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: side == null ? null : Icon(
              side == Side.a ? Icons.circle_outlined : Icons.close_rounded,
              size: 44,
              color: side == Side.a ? _childColor : _parentColor,
            )),
          ),
        );
      },
    ),
  );
}
