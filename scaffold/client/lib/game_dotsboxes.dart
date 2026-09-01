// OLIVE BRANCH — dots and boxes. Verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). MASTERFILE §9.2, P2.
//
// A 1:1 semantic port of the 'dotsboxes' branch of packages/games/src/
// games.ts's generic game engine (newGame()'s `n = 4` / 3x3-box dotsboxes
// base, play()'s dotsboxes branch — including `claimBoxes()`'s cascade rule,
// where completing a box grants the SAME side another move rather than
// passing the turn — and takeBack()) plus setHandicap()'s dotsboxes-relevant
// side effects (`start_behind`, `child_first`), narrowed to just this one
// game kind. Same discipline, same reasoning, as game_tictactoe.dart's own
// header — see that file for the fuller account of why this reuses
// game_logic.dart's `Side` directly rather than inventing a second type,
// and why setup goes through the shared, reusable `HandicapScreen` rather
// than a bespoke setup screen (dots-and-boxes is already a real entry in
// game_logic.dart's shared catalogue).
//
// DELIBERATE FIDELITY, flagged rather than "fixed": games.ts's own
// `setHandicap()` reads `if (handicapId === 'start_behind') state = { ...
// state, scores: { A: 2, B: 0 } }` — the CHILD (side A) starts two BOXES
// AHEAD, not the parent starting behind, despite the handicap's own label
// text ("Dad starts two boxes behind") describing it the other way around.
// Both phrasings describe the identical material fact (a two-box gap
// favoring the child) — this is not the chess-file's FEN-transposition bug
// (which handed the wrong SIDE'S piece away entirely); it is just an odd
// choice of reference point in the source's own comment. Ported here
// exactly as games.ts wrote it, per the assignment's explicit instruction
// not to reinterpret it.
//
// As in game_tictactoe.dart/game_chess.dart/game_checkers.dart: the
// "parent" is a simulated local opponent (a uniformly random legal move,
// after a short "thinking" pause) — and, per §9.2's own cascade rule, the
// simulated parent keeps taking its "thinking" turn for as long as its own
// moves keep completing boxes, the same recursive-continuation shape
// game_checkers.dart's `_applyBotMove` already uses for a simulated
// multi-jump chain. A move carrying a voice note is acknowledged honestly
// as not built here, for the same reason those files give.
//
// P2 governs the whole screen: no ELO, no rank, no streak, no "you lost"
// screen. The live box tally is shown only while play continues — mirroring
// games.ts's own `childView()`, whose `boxesEach` field is documented
// "Present only while a game is live, and only as an in-game tally" — and
// disappears the moment the game ends, replaced by a plain factual close-out
// line. The board itself keeps showing which boxes went to which side after
// the game ends (she could see that across a real table too); the product
// just never narrates it as a verdict.
//
// Layout is driven by the real §8.11.1 posture system (form_factors.dart),
// not a hand-rolled per-screen pixel breakpoint — see game_tictactoe.dart's
// header for the fuller account (same technique, same reasoning, same
// court_export.dart precedent). At `foldCover`/`phone`/`tabletSmall` (1
// column) the board is the only thing on screen, full width, everything
// else stacked below it. At `foldMain`/`tabletLarge`+ (2+ columns) the
// board shares the screen with a persistent side panel carrying the same
// banners/tally plus a full-width button `Column` — genuinely more layout,
// not the narrow layout scaled up.
import 'dart:math';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'game_logic.dart';
import 'handicap_screen.dart';

// ============================================================ RULES ENGINE ==

enum EdgeKind { h, v }

/// Mirrors games.ts's generic `outcome` union narrowed to what
/// dots-and-boxes can actually produce.
enum DbOutcome { childWin, parentWin, draw }

class DbMove {
  const DbMove({required this.side, required this.kind, required this.r, required this.c});
  final Side side;
  final EdgeKind kind;
  final int r, c;
}

class DbState {
  const DbState({
    required this.n,
    required this.h,
    required this.v,
    required this.owner,
    required this.turn,
    required this.moves,
    required this.scores,
    required this.outcome,
    required this.handicap,
  });
  /// 4 dots per side → 3x3 boxes, matching games.ts's `newGame()` literally
  /// (`const n = 4`).
  final int n;
  /// Horizontal edges: n rows x (n-1) cols.
  final List<List<Side?>> h;
  /// Vertical edges: (n-1) rows x n cols.
  final List<List<Side?>> v;
  /// Box ownership: (n-1) x (n-1).
  final List<List<Side?>> owner;
  final Side turn;
  final List<DbMove> moves;
  final Map<Side, int> scores;
  final DbOutcome? outcome;
  final String? handicap;
}

List<List<Side?>> _mat(int r, int c) => List.generate(r, (_) => List<Side?>.filled(c, null));

/// New game. §9.2 — the child always moves first, same default as every
/// other game in games.ts's newGame().
DbState newDotsAndBoxes() {
  const n = 4;
  return DbState(
    n: n,
    h: _mat(n, n - 1),
    v: _mat(n - 1, n),
    owner: _mat(n - 1, n - 1),
    turn: Side.a,
    moves: const [],
    scores: const {Side.a: 0, Side.b: 0},
    outcome: null,
    handicap: null,
  );
}

List<List<Side?>> _cloneMat(List<List<Side?>> m) => [for (final row in m) [...row]];

/// Claims every box that [side]'s just-drawn edge completed, mutating
/// [owner] in place — a 1:1 port of games.ts's `claimBoxes()`, including its
/// in-place mutation style, since that function's own caller (`play()`)
/// relies on the same shape.
int _claimBoxes(List<List<Side?>> h, List<List<Side?>> v, List<List<Side?>> owner, int n, Side side) {
  var claimed = 0;
  for (var r = 0; r < n - 1; r++) {
    for (var c = 0; c < n - 1; c++) {
      if (owner[r][c] != null) continue;
      if (h[r][c] != null && h[r + 1][c] != null && v[r][c] != null && v[r][c + 1] != null) {
        owner[r][c] = side;
        claimed++;
      }
    }
  }
  return claimed;
}

class DbPlayResult {
  const DbPlayResult.ok(this.state) : reason = null;
  const DbPlayResult.err(this.reason) : state = null;
  final DbState? state;
  /// 'not_your_turn' | 'game_over' | 'occupied' | 'out_of_range' — mirrors
  /// games.ts's `MoveError` union, restricted to reasons this branch can
  /// actually produce (dots-and-boxes carries no per-move handicap check;
  /// `start_behind`/`child_first` only ever act at `setHandicap()` time).
  final String? reason;
  bool get ok => state != null;
}

/// Applies one edge. Mirrors games.ts's `play()` dotsboxes branch exactly,
/// including the turn-keeping rule bug-for-bug: a move that both completes
/// a box AND fills the board (`claimed > 0 && full`) still flips `turn` in
/// the recorded state, same as the source — harmless in practice because
/// `outcome` is non-null the instant that happens, so no further `play()`
/// call is ever accepted either way.
DbPlayResult dbPlay(DbState g, Side side, EdgeKind kind, int r, int c) {
  if (g.outcome != null) return const DbPlayResult.err('game_over');
  if (side != g.turn) return const DbPlayResult.err('not_your_turn');
  final grid = kind == EdgeKind.h ? g.h : g.v;
  if (r < 0 || r >= grid.length || c < 0 || c >= grid[r].length) {
    return const DbPlayResult.err('out_of_range');
  }
  if (grid[r][c] != null) return const DbPlayResult.err('occupied');

  final h = _cloneMat(g.h);
  final v = _cloneMat(g.v);
  final owner = _cloneMat(g.owner);
  if (kind == EdgeKind.h) {
    h[r][c] = side;
  } else {
    v[r][c] = side;
  }

  // THE rule that makes this game deep: completing a box gives another
  // turn, so a single move can cascade into a long chain.
  final claimed = _claimBoxes(h, v, owner, g.n, side);
  final scores = {...g.scores, side: (g.scores[side] ?? 0) + claimed};
  final full = owner.every((row) => row.every((x) => x != null));
  DbOutcome? outcome;
  if (full) {
    final a = scores[Side.a] ?? 0, b = scores[Side.b] ?? 0;
    outcome = a == b ? DbOutcome.draw : (a > b ? DbOutcome.childWin : DbOutcome.parentWin);
  }
  final keepTurn = claimed > 0 && !full;
  final moves = [...g.moves, DbMove(side: side, kind: kind, r: r, c: c)];
  return DbPlayResult.ok(DbState(
    n: g.n, h: h, v: v, owner: owner,
    turn: keepTurn ? side : (side == Side.a ? Side.b : Side.a),
    moves: moves, scores: scores, outcome: outcome, handicap: g.handicap,
  ));
}

class DbMoveOpt {
  const DbMoveOpt(this.kind, this.r, this.c);
  final EdgeKind kind;
  final int r, c;
}

/// Every empty edge on the board — dots-and-boxes carries no per-side move
/// restriction (unlike tic-tac-toe's `no_centre`), so this is the same pool
/// for either side; used to pick the simulated parent's move.
List<DbMoveOpt> dbLegalMoves(DbState g) {
  final moves = <DbMoveOpt>[];
  for (var r = 0; r < g.h.length; r++) {
    for (var c = 0; c < g.h[r].length; c++) {
      if (g.h[r][c] == null) moves.add(DbMoveOpt(EdgeKind.h, r, c));
    }
  }
  for (var r = 0; r < g.v.length; r++) {
    for (var c = 0; c < g.v[r].length; c++) {
      if (g.v[r][c] == null) moves.add(DbMoveOpt(EdgeKind.v, r, c));
    }
  }
  return moves;
}

class DbSetHandicapResult {
  const DbSetHandicapResult.ok(this.state) : refusal = null;
  const DbSetHandicapResult.refused(this.refusal) : state = null;
  final DbState? state;
  /// 'child_only' | 'unknown' — mirrors games.ts's `setHandicap` refusal
  /// union.
  final String? refusal;
  bool get ok => state != null;
}

/// §9.2 — only the child may set a handicap, and only on the parent; refused
/// unconditionally before the id is even looked at, matching games.ts's own
/// `setHandicap()`. Mutates the CURRENT state (board/moves untouched) rather
/// than starting a fresh game — see game_tictactoe.dart's header for why
/// that fidelity to the "even mid-game" promise matters.
DbSetHandicapResult dbSetHandicap(DbState g, Side bySide, String? handicapId) {
  if (bySide != Side.a) return const DbSetHandicapResult.refused('child_only');
  if (handicapId != null &&
      !catalogueFor(GameKind.dotsboxes).handicaps.any((h) => h.id == handicapId)) {
    return const DbSetHandicapResult.refused('unknown');
  }
  var turn = g.turn;
  var scores = g.scores;
  // Ported exactly as games.ts wrote it — see the file header's "DELIBERATE
  // FIDELITY" note: the CHILD starts two boxes ahead, not the parent behind.
  if (handicapId == 'start_behind') scores = const {Side.a: 2, Side.b: 0};
  if (handicapId == 'child_first') turn = Side.a;
  return DbSetHandicapResult.ok(DbState(
    n: g.n, h: g.h, v: g.v, owner: g.owner, turn: turn, moves: g.moves,
    scores: scores, outcome: g.outcome, handicap: handicapId,
  ));
}

/// Free, unlimited takebacks (§9.2) — implemented by replaying from the
/// start, same reasoning as games.ts's own `takeBack()` doc comment: "a
/// digital [board] that refuses is worse than the analog version for no
/// gain… inversion is where takeback bugs live, especially with the
/// extra-turn rules in dots-and-boxes." Replaying naturally recomputes every
/// box-completion and every extra turn along the way, so undoing a
/// box-completing move correctly hands the turn back to whoever's turn it
/// was immediately before that move — no special-cased inversion logic.
DbState dbTakeBack(DbState g) {
  if (g.moves.isEmpty) return g;
  final keep = g.moves.sublist(0, g.moves.length - 1);
  var s = newDotsAndBoxes();
  if (g.handicap != null) {
    final r = dbSetHandicap(s, Side.a, g.handicap);
    if (r.ok) s = r.state!;
  }
  for (final m in keep) {
    final r = dbPlay(s, m.side, m.kind, m.r, m.c);
    if (r.ok) s = r.state!;
  }
  return s;
}

// ================================================================= WIDGET ===
class GameDotsBoxes extends StatefulWidget {
  const GameDotsBoxes({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.botThinkDelay = const Duration(milliseconds: 550),
  });

  final String childName;
  final String parentName;
  /// How long the simulated opponent "thinks" before replying (and, per the
  /// cascade rule, before each FURTHER move in the same extra turn). Exposed
  /// for tests, not because a settings affordance belongs on this screen.
  final Duration botThinkDelay;

  @override
  State<GameDotsBoxes> createState() => _GameDotsBoxesState();
}

class _GameDotsBoxesState extends State<GameDotsBoxes> {
  DbState _state = newDotsAndBoxes();
  bool _parentThinking = false;

  void _tapEdge(EdgeKind kind, int r, int c) {
    if (_state.outcome != null || _parentThinking || _state.turn != Side.a) return;
    final result = dbPlay(_state, Side.a, kind, r, c);
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
      final moves = dbLegalMoves(_state);
      if (moves.isEmpty) {
        setState(() => _parentThinking = false);
        return;
      }
      final pick = moves[Random().nextInt(moves.length)];
      final result = dbPlay(_state, Side.b, pick.kind, pick.r, pick.c);
      setState(() {
        _parentThinking = false;
        if (result.ok) _state = result.state!;
      });
      if (_state.outcome == null && _state.turn == Side.b) {
        // The parent's own move just completed a box and earned another
        // turn — keep going, the same recursive-continuation shape
        // game_checkers.dart's _applyBotMove uses for a simulated
        // multi-jump chain.
        _scheduleParentMove();
      }
    });
  }

  void _takeBack() {
    if (_state.moves.isEmpty) return;
    setState(() {
      _state = dbTakeBack(_state);
      _parentThinking = false;
    });
  }

  void _playAgain() {
    setState(() {
      var s = newDotsAndBoxes();
      if (_state.handicap != null) {
        final r = dbSetHandicap(s, Side.a, _state.handicap);
        if (r.ok) s = r.state!;
      }
      _state = s;
      _parentThinking = false;
    });
  }

  void _applyHandicap(String? id) {
    final result = dbSetHandicap(_state, Side.a, id);
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
    final banner = handicapBanner(GameKind.dotsboxes, _state.handicap);
    return Scaffold(
      appBar: AppBar(
        title: Text(catalogueFor(GameKind.dotsboxes).title),
        actions: [
          IconButton(
            tooltip: 'Make it fair',
            icon: const Icon(Icons.balance_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => HandicapScreen(
                kind: GameKind.dotsboxes,
                currentHandicapId: _state.handicap,
                onChanged: _applyHandicap,
              ),
            )),
          ),
          IconButton(
            tooltip: 'Add a voice note',
            icon: const Icon(Icons.mic_none),
            onPressed: () => _notBuiltYetDb(context, 'Voice notes on moves'),
          ),
        ],
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — see game_tictactoe.dart's own build() for the fuller
        // comment (same technique, same court_export.dart precedent).
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;

        final boardView = AspectRatio(aspectRatio: 1, child: _DotsBoxesBoardView(
          state: _state, onTapEdge: _tapEdge, scheme: scheme,
        ));
        // The narrow, single-column layout has no second breakpoint of its
        // own to honor — see game_tictactoe.dart's identical note: it
        // simply fills the width it's given, and the wide layout below
        // builds its own independently-capped boardView inside its
        // Expanded regardless.
        final board = Center(child: boardView);

        // Present only while play continues, mirroring games.ts's own
        // childView()'s `boxesEach` — an in-game tally, not a scoreboard,
        // and gone the instant the game ends.
        final statusArea = !finished
            ? _TallyRow(childName: widget.childName, parentName: widget.parentName,
                childCount: _state.scores[Side.a] ?? 0, parentCount: _state.scores[Side.b] ?? 0)
            : _EndBanner(line: _state.outcome == DbOutcome.draw ? 'Draw. Good game.' : 'Good game.');

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
            const SizedBox(height: 12),
            statusArea,
            const SizedBox(height: 12),
            board,
            const SizedBox(height: 16),
            // Wrap, not a Row — same Fold5 cover-screen (344 CSS px)
            // overflow guard game_tictactoe.dart's/game_chess.dart's/
            // game_checkers.dart's own comments describe.
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
              key: const Key('dbSidePanel'),
              width: 260,
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null) Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: _CalloutBanner(text: banner)),
                  _TurnBanner(finished: finished, parentThinking: _parentThinking,
                    childName: widget.childName, parentName: widget.parentName,
                    isChildTurn: _state.turn == Side.a),
                  const SizedBox(height: 12),
                  statusArea,
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

void _notBuiltYetDb(BuildContext context, String what) {
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
      key: const Key('dbTakeBack'),
      onPressed: canTakeBack ? onTakeBack : null,
      icon: const Icon(Icons.undo),
      label: const Text('Take that back'),
    )),
    if (finished) SizedBox(height: 48, child: FilledButton.icon(
      key: const Key('dbPlayAgain'),
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
      key: const Key('dbTakeBack'),
      onPressed: canTakeBack ? onTakeBack : null,
      icon: const Icon(Icons.undo),
      label: const Text('Take that back'),
    )),
    if (finished) ...[
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48, child: FilledButton.icon(
        key: const Key('dbPlayAgain'),
        onPressed: onPlayAgain,
        icon: const Icon(Icons.refresh),
        label: const Text('Play again'),
      )),
    ],
  ]);
}

class _DotsBoxesBoardView extends StatelessWidget {
  const _DotsBoxesBoardView({required this.state, required this.onTapEdge, required this.scheme});
  final DbState state;
  final void Function(EdgeKind kind, int r, int c) onTapEdge;
  final ColorScheme scheme;

  static const _childColor = Color(0xFFE8735B);
  static const _parentColor = Color(0xFF4A3F8F);
  static const _dotR = 6.0;
  static const _edgeThickness = 18.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final n = state.n;
    final side = constraints.maxWidth;
    final cell = side / (n - 1);
    final children = <Widget>[];

    // Claimed boxes first, so edges/dots draw on top of them.
    for (var r = 0; r < n - 1; r++) {
      for (var c = 0; c < n - 1; c++) {
        final owner = state.owner[r][c];
        if (owner == null) continue;
        children.add(Positioned(
          left: c * cell, top: r * cell, width: cell, height: cell,
          child: Padding(padding: const EdgeInsets.all(3), child: DecoratedBox(
            decoration: BoxDecoration(
              color: (owner == Side.a ? _childColor : _parentColor).withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(6)))),
        ));
      }
    }

    // Horizontal edges.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n - 1; c++) {
        final owner = state.h[r][c];
        children.add(Positioned(
          left: c * cell + _dotR, top: r * cell - _edgeThickness / 2,
          width: cell - 2 * _dotR, height: _edgeThickness,
          child: GestureDetector(
            key: Key('dbH_${r}_$c'),
            onTap: owner == null ? () => onTapEdge(EdgeKind.h, r, c) : null,
            child: Center(child: Container(
              height: owner == null ? 4 : _edgeThickness * 0.55,
              decoration: BoxDecoration(
                color: owner == null ? scheme.outlineVariant : (owner == Side.a ? _childColor : _parentColor),
                borderRadius: BorderRadius.circular(4)),
            )),
          ),
        ));
      }
    }

    // Vertical edges.
    for (var r = 0; r < n - 1; r++) {
      for (var c = 0; c < n; c++) {
        final owner = state.v[r][c];
        children.add(Positioned(
          left: c * cell - _edgeThickness / 2, top: r * cell + _dotR,
          width: _edgeThickness, height: cell - 2 * _dotR,
          child: GestureDetector(
            key: Key('dbV_${r}_$c'),
            onTap: owner == null ? () => onTapEdge(EdgeKind.v, r, c) : null,
            child: Center(child: Container(
              width: owner == null ? 4 : _edgeThickness * 0.55,
              decoration: BoxDecoration(
                color: owner == null ? scheme.outlineVariant : (owner == Side.a ? _childColor : _parentColor),
                borderRadius: BorderRadius.circular(4)),
            )),
          ),
        ));
      }
    }

    // Dots on top of everything.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        children.add(Positioned(
          left: c * cell - _dotR, top: r * cell - _dotR, width: _dotR * 2, height: _dotR * 2,
          child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.onSurface)),
        ));
      }
    }

    return SizedBox(width: side, height: side, child: Stack(clipBehavior: Clip.none, children: children));
  });
}
