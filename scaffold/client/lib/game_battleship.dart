// OLIVE BRANCH — battleship. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.2.
//
// The rules engine below (BsShip/BsState/placeShip/fire) is a 1:1 semantic
// port of the `BATTLESHIP` section of packages/games/src/games2.ts — same
// fleet, same board size, same "a hit grants another shot" turn rule, same
// function shapes — mirroring the discipline lock_controller.dart applies
// when porting lock.ts.
//
// MARKUP's one-line brief for this screen is the load-bearing constraint:
// "Hers and his boards, never both on one screen." That, plus §9.2's
// "opponent positions never leave the server", drive the split below into
// three pieces instead of one State object holding everything:
//
//   _BattleshipHost   Plays the part of "the server" for this single local
//                      demo. It is a plain Dart object, NOT a Widget/State —
//                      nothing in the widget tree can accidentally read it
//                      directly. It owns the one BsState with BOTH fleets,
//                      places the parent's ships itself (randomly, since
//                      there is no live second device here) and even keeps
//                      the parent AI's hunt-after-a-hit memory privately —
//                      that targeting knowledge belongs to "the opponent",
//                      not to anything the child's screen can inspect.
//
//   EnemyBoardView    The ONLY thing the "enemy waters" grid widget ever
//                      receives. It is a flat list of 64 `BsCellStatus`
//                      values (unknown/miss/hit/sunk) — there is no field
//                      on this type that could carry an unrevealed ship's
//                      cells even by accident, because a real server
//                      response would not carry them either.
//
//   OwnBoardView      What "your fleet" renders from: full detail, because
//                      it is the child's own board.
//
// The UI itself shows exactly one of those two boards at a time via a
// segmented toggle, never a split screen — satisfying the MARKUP brief
// structurally, not just by convention.
//
// P2: no rank, no win/loss record. Ship counts remaining are an in-game
// tally only, same posture as games.ts's `childView().boxesEach`, and
// disappear at "Good game."
import 'dart:math';
import 'package:flutter/material.dart';

// ============================================================ RULES ENGINE ==
enum BsSide { child, parent }

extension BsSideX on BsSide {
  BsSide get opposite => this == BsSide.child ? BsSide.parent : BsSide.child;
}

enum BsPhase { placing, playing }

class BsFleetSpec {
  const BsFleetSpec(this.name, this.len);
  final String name;
  final int len;
}

const List<BsFleetSpec> bsFleet = [
  BsFleetSpec('Carrier', 5), BsFleetSpec('Battleship', 4),
  BsFleetSpec('Cruiser', 3), BsFleetSpec('Submarine', 3),
  BsFleetSpec('Destroyer', 2),
];
const int bsSize = 8;

class BsShip {
  BsShip({required this.name, required this.cells, required this.hits});
  final String name;
  final List<int> cells;
  final List<int> hits;
  bool get sunk => hits.length == cells.length;
}

class BsState {
  const BsState({required this.ships, required this.shots, required this.turn,
    required this.outcome, required this.phase});
  final Map<BsSide, List<BsShip>> ships;
  final Map<BsSide, List<int>> shots;
  final BsSide turn;
  final BsSide? outcome;
  final BsPhase phase;
}

BsState newBattleship() => const BsState(
  ships: {BsSide.child: [], BsSide.parent: []},
  shots: {BsSide.child: [], BsSide.parent: []},
  turn: BsSide.child, outcome: null, phase: BsPhase.placing);

class BsPlaceResult {
  const BsPlaceResult.ok(this.state) : reason = null;
  const BsPlaceResult.err(this.reason) : state = null;
  final BsState? state;
  final String? reason;
  bool get ok => state != null;
}

BsPlaceResult placeShip(BsState s, BsSide side, String name, int start, bool horizontal) {
  BsFleetSpec? spec;
  for (final f in bsFleet) { if (f.name == name) { spec = f; break; } }
  if (spec == null) return const BsPlaceResult.err('unknown_ship');
  if (s.ships[side]!.any((x) => x.name == name)) return const BsPlaceResult.err('already_placed');
  final r = start ~/ bsSize, c = start % bsSize;
  final cells = <int>[];
  for (var i = 0; i < spec.len; i++) {
    final rr = horizontal ? r : r + i;
    final cc = horizontal ? c + i : c;
    if (rr >= bsSize || cc >= bsSize) return const BsPlaceResult.err('off_board');
    cells.add(rr * bsSize + cc);
  }
  final taken = <int>{for (final x in s.ships[side]!) ...x.cells};
  if (cells.any(taken.contains)) return const BsPlaceResult.err('overlaps');
  final newShips = {...s.ships, side: [...s.ships[side]!, BsShip(name: name, cells: cells, hits: [])]};
  final ready = newShips[BsSide.child]!.length == bsFleet.length &&
      newShips[BsSide.parent]!.length == bsFleet.length;
  return BsPlaceResult.ok(BsState(ships: newShips, shots: s.shots, turn: s.turn,
    outcome: s.outcome, phase: ready ? BsPhase.playing : BsPhase.placing));
}

class BsFireResult {
  const BsFireResult.ok({required this.state, required this.hit, required this.sunk})
      : reason = null;
  const BsFireResult.err(this.reason) : state = null, hit = false, sunk = null;
  final BsState? state;
  final bool hit;
  final String? sunk;
  final String? reason;
  bool get ok => state != null;
}

BsFireResult fire(BsState s, BsSide side, int cell) {
  if (s.phase != BsPhase.playing) return const BsFireResult.err('still_placing');
  if (s.outcome != null) return const BsFireResult.err('game_over');
  if (side != s.turn) return const BsFireResult.err('not_your_turn');
  if (s.shots[side]!.contains(cell)) return const BsFireResult.err('already_fired');
  if (cell < 0 || cell >= bsSize * bsSize) return const BsFireResult.err('off_board');

  final foe = side.opposite;
  final foeShips = [for (final x in s.ships[foe]!) BsShip(name: x.name, cells: x.cells, hits: [...x.hits])];
  BsShip? target;
  for (final x in foeShips) { if (x.cells.contains(cell)) { target = x; break; } }
  String? sunk;
  if (target != null) {
    target.hits.add(cell);
    if (target.sunk) sunk = target.name;
  }
  final newShips = {...s.ships, foe: foeShips};
  final newShots = {...s.shots, side: [...s.shots[side]!, cell]};
  final allSunk = foeShips.every((x) => x.sunk);
  return BsFireResult.ok(hit: target != null, sunk: sunk,
    state: BsState(ships: newShips, shots: newShots, phase: s.phase,
      outcome: allSunk ? side : null,
      // A hit grants another shot — the rule that gives the game its rhythm.
      turn: (target != null && !allSunk) ? side : foe));
}

// ---------------------------------------------------- projections ("wire") --
enum BsCellStatus { unknown, miss, hit, sunk }

/// Everything the "enemy waters" grid is allowed to know. No field here can
/// carry an unrevealed ship's cells — the same shape discipline a real
/// server response to this screen would need.
class EnemyBoardView {
  const EnemyBoardView(this.statuses);
  final List<BsCellStatus> statuses; // length 64
}

class OwnCellInfo {
  const OwnCellInfo({required this.hasShip, required this.hit});
  final bool hasShip;
  final bool hit;
}

class OwnBoardView {
  const OwnBoardView(this.cells);
  final List<OwnCellInfo> cells; // length 64
}

BsCellStatus _statusForCell(int i, List<int> myShots, List<BsShip> foeShips) {
  if (!myShots.contains(i)) return BsCellStatus.unknown;
  for (final ship in foeShips) {
    if (ship.cells.contains(i)) return ship.sunk ? BsCellStatus.sunk : BsCellStatus.hit;
  }
  return BsCellStatus.miss;
}

/// Stands in for "the server" in this offline demo: the one place both
/// fleets exist together. It is a plain object, never a Widget/State, so
/// nothing painting the enemy grid can reach into it for more than the
/// projection it asks for.
class _BattleshipHost {
  _BattleshipHost({Random? random}) : _rand = random ?? Random() {
    _autoPlaceRandom(BsSide.parent);
  }

  BsState _state = newBattleship();
  final Random _rand;
  final List<int> _huntQueue = []; // the parent AI's own memory, kept private

  BsState get state => _state;

  void _autoPlaceRandom(BsSide side) {
    for (final spec in bsFleet) {
      var guard = 0;
      while (guard < 500) {
        guard++;
        final result = placeShip(_state, side, spec.name, _rand.nextInt(bsSize * bsSize), _rand.nextBool());
        if (result.ok) { _state = result.state!; break; }
      }
    }
  }

  BsPlaceResult place(BsSide side, String name, int start, bool horizontal) {
    final result = placeShip(_state, side, name, start, horizontal);
    if (result.ok) _state = result.state!;
    return result;
  }

  BsFireResult fireAt(BsSide side, int cell) {
    final result = fire(_state, side, cell);
    if (result.ok) _state = result.state!;
    return result;
  }

  int _pickParentTarget() {
    while (_huntQueue.isNotEmpty) {
      final c = _huntQueue.removeLast();
      if (!_state.shots[BsSide.parent]!.contains(c)) return c;
    }
    final available = [for (var i = 0; i < bsSize * bsSize; i++) i]
      ..removeWhere((i) => _state.shots[BsSide.parent]!.contains(i));
    return available[_rand.nextInt(available.length)];
  }

  /// The parent AI's one turn: pick a target (hunting near a recent hit if
  /// it has one queued) and fire. Returns the fire result so the UI can
  /// narrate it against the CHILD's own board — never the reverse.
  BsFireResult parentTakeShot() {
    final cell = _pickParentTarget();
    final result = fireAt(BsSide.parent, cell);
    if (result.ok && result.hit && result.sunk == null) {
      final r = cell ~/ bsSize, c = cell % bsSize;
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final rr = r + dr, cc = c + dc;
        if (rr >= 0 && rr < bsSize && cc >= 0 && cc < bsSize) _huntQueue.add(rr * bsSize + cc);
      }
    }
    return result;
  }

  EnemyBoardView enemyBoardView(BsSide side) {
    final myShots = _state.shots[side]!;
    final foeShips = _state.ships[side.opposite]!;
    return EnemyBoardView([for (var i = 0; i < bsSize * bsSize; i++) _statusForCell(i, myShots, foeShips)]);
  }

  OwnBoardView ownBoardView(BsSide side) {
    final myShips = _state.ships[side]!;
    final enemyShots = _state.shots[side.opposite]!;
    return OwnBoardView([for (var i = 0; i < bsSize * bsSize; i++) OwnCellInfo(
      hasShip: myShips.any((s) => s.cells.contains(i)), hit: enemyShots.contains(i))]);
  }

  int shipsRemaining(BsSide side) => _state.ships[side]!.where((s) => !s.sunk).length;
}

// ================================================================= WIDGET ===
enum _BoardTab { mine, enemy }

class GameBattleship extends StatefulWidget {
  const GameBattleship({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.botThinkDelay = const Duration(milliseconds: 500),
    this.random,
  });

  final String childName;
  final String parentName;
  final Duration botThinkDelay;
  /// Injectable for deterministic tests.
  final Random? random;

  @override
  State<GameBattleship> createState() => _GameBattleshipState();
}

class _GameBattleshipState extends State<GameBattleship> {
  late _BattleshipHost _host = _BattleshipHost(random: widget.random);
  String? _pendingShip;
  bool _horizontal = true;
  _BoardTab _tab = _BoardTab.mine;
  bool _parentThinking = false;
  String? _placementHint;
  String? _shotNarration;

  List<String> get _unplacedNames {
    final placed = _host.state.ships[BsSide.child]!.map((s) => s.name).toSet();
    return [for (final f in bsFleet) if (!placed.contains(f.name)) f.name];
  }

  void _tapOwnCellForPlacement(int cell) {
    final name = _pendingShip ?? (_unplacedNames.isEmpty ? null : _unplacedNames.first);
    if (name == null) return;
    final result = _host.place(BsSide.child, name, cell, _horizontal);
    setState(() {
      if (!result.ok) {
        _placementHint = switch (result.reason) {
          'overlaps' => "That's already got a ship on it.",
          'off_board' => "That won't fit there — try turning it or moving over.",
          _ => "Can't place that one there.",
        };
        return;
      }
      _placementHint = null;
      _pendingShip = _unplacedNames.isEmpty ? null : _unplacedNames.first;
      if (_host.state.phase == BsPhase.playing) _tab = _BoardTab.enemy;
    });
  }

  void _fireChild(int cell) {
    final result = _host.fireAt(BsSide.child, cell);
    if (!result.ok) return;
    setState(() {
      _shotNarration = result.sunk != null
          ? 'You sank the ${result.sunk}!'
          : result.hit ? 'Hit! Go again.' : 'Splash — miss.';
    });
    if (_host.state.outcome == null && _host.state.turn == BsSide.parent) {
      _scheduleParentShot();
    }
  }

  void _scheduleParentShot() {
    setState(() => _parentThinking = true);
    Future.delayed(widget.botThinkDelay, () {
      if (!mounted) return;
      final result = _host.parentTakeShot();
      setState(() {
        if (result.ok) {
          _shotNarration = result.sunk != null
              ? '${widget.parentName} sank your ${result.sunk}.'
              : result.hit ? '${widget.parentName} hit your fleet.' : '${widget.parentName} missed.';
        }
      });
      if (_host.state.outcome == null && _host.state.turn == BsSide.parent) {
        _scheduleParentShot();
      } else {
        setState(() => _parentThinking = false);
      }
    });
  }

  void _resetGame() {
    // A fresh _BattleshipHost is a fresh "server" for a new game — nothing
    // from the finished game (including the old parent-fleet layout) can
    // leak into the new one.
    setState(() {
      _host = _BattleshipHost(random: widget.random);
      _pendingShip = null;
      _horizontal = true;
      _tab = _BoardTab.mine;
      _parentThinking = false;
      _placementHint = null;
      _shotNarration = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final scheme = Theme.of(context).colorScheme;
    final placing = host.state.phase == BsPhase.placing;
    final finished = host.state.outcome != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Battleship'), actions: [
        IconButton(
          tooltip: 'Add a voice note',
          icon: const Icon(Icons.mic_none),
          onPressed: () => _notBuiltYetBs(context, 'Voice notes on shots'),
        ),
      ]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        _StatusBanner(placing: placing, finished: finished, parentThinking: _parentThinking,
          isChildTurn: host.state.turn == BsSide.child,
          childName: widget.childName, parentName: widget.parentName,
          narration: _shotNarration),
        const SizedBox(height: 12),
        if (!placing && !finished) _TallyRowBs(
          childName: widget.childName, parentName: widget.parentName,
          childShips: host.shipsRemaining(BsSide.child),
          parentShips: host.shipsRemaining(BsSide.parent),
        ),
        if (placing) _PlacementPanel(
          unplacedNames: _unplacedNames,
          pending: _pendingShip ?? (_unplacedNames.isEmpty ? null : _unplacedNames.first),
          horizontal: _horizontal,
          onPickShip: (n) => setState(() => _pendingShip = n),
          onToggleOrientation: () => setState(() => _horizontal = !_horizontal),
          hint: _placementHint,
        ) else if (!finished) SegmentedButton<_BoardTab>(
          segments: const [
            ButtonSegment(value: _BoardTab.mine, label: Text('Your fleet'), icon: Icon(Icons.shield_outlined)),
            ButtonSegment(value: _BoardTab.enemy, label: Text('Enemy waters'), icon: Icon(Icons.waves)),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: 12),
        Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AspectRatio(aspectRatio: 1, child: placing || _tab == _BoardTab.mine
              ? _OwnGrid(view: host.ownBoardView(BsSide.child), scheme: scheme,
                  onTapCell: placing && !finished ? _tapOwnCellForPlacement : null)
              : _EnemyGrid(view: host.enemyBoardView(BsSide.child), scheme: scheme,
                  enabled: !finished && host.state.turn == BsSide.child && !_parentThinking,
                  onTapCell: _fireChild)),
        )),
        const SizedBox(height: 16),
        if (finished) Center(child: SizedBox(height: 48, child: FilledButton.icon(
          onPressed: _resetGame, icon: const Icon(Icons.refresh), label: const Text('Play again')))),
      ])),
    );
  }
}

void _notBuiltYetBs(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.placing, required this.finished, required this.parentThinking,
    required this.isChildTurn, required this.childName, required this.parentName, this.narration});
  final bool placing, finished, parentThinking, isChildTurn;
  final String childName, parentName;
  final String? narration;

  @override
  Widget build(BuildContext context) {
    final title = finished ? 'Good game.'
        : placing ? 'Place your fleet'
        : isChildTurn ? "$childName's turn" : parentThinking ? "$parentName is taking aim…" : "$parentName's turn";
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (narration != null && !finished) Padding(padding: const EdgeInsets.only(top: 4),
        child: Text(narration!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
    ]);
  }
}

class _TallyRowBs extends StatelessWidget {
  const _TallyRowBs({required this.childName, required this.parentName,
    required this.childShips, required this.parentShips});
  final String childName, parentName;
  final int childShips, parentShips;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Expanded(child: _TallyChipBs(label: '$childName\'s ships', count: childShips,
        color: Theme.of(context).colorScheme.primaryContainer)),
      const SizedBox(width: 10),
      Expanded(child: _TallyChipBs(label: '$parentName\'s ships', count: parentShips,
        color: Theme.of(context).colorScheme.secondaryContainer)),
    ]),
  );
}

class _TallyChipBs extends StatelessWidget {
  const _TallyChipBs({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      Text('$count', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
    ]),
  );
}

class _PlacementPanel extends StatelessWidget {
  const _PlacementPanel({required this.unplacedNames, required this.pending, required this.horizontal,
    required this.onPickShip, required this.onToggleOrientation, this.hint});
  final List<String> unplacedNames;
  final String? pending;
  final bool horizontal;
  final ValueChanged<String> onPickShip;
  final VoidCallback onToggleOrientation;
  final String? hint;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final name in unplacedNames)
        ChoiceChip(label: Text(name), selected: name == pending, onSelected: (_) => onPickShip(name)),
    ]),
    const SizedBox(height: 10),
    SizedBox(height: 48, child: OutlinedButton.icon(
      onPressed: onToggleOrientation,
      icon: Icon(horizontal ? Icons.swap_horiz : Icons.swap_vert),
      label: Text(horizontal ? 'Lying flat' : 'Standing up'))),
    if (hint != null) Padding(padding: const EdgeInsets.only(top: 8),
      child: Text(hint!, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.error))),
  ]);
}

class _OwnGrid extends StatelessWidget {
  const _OwnGrid({required this.view, required this.scheme, this.onTapCell});
  final OwnBoardView view;
  final ColorScheme scheme;
  final void Function(int cell)? onTapCell;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: bsSize),
      itemCount: bsSize * bsSize,
      itemBuilder: (context, i) {
        final info = view.cells[i];
        final color = info.hit && info.hasShip ? Colors.red.shade400
            : info.hit ? scheme.surfaceContainerHighest
            : info.hasShip ? scheme.primary.withValues(alpha: 0.55)
            : scheme.surfaceContainerLow;
        return GestureDetector(
          key: Key('bsOwn_$i'),
          onTap: onTapCell == null ? null : () => onTapCell!(i),
          child: Container(margin: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: info.hit ? const Center(child: Icon(Icons.close, size: 14)) : null),
        );
      },
    ),
  );
}

class _EnemyGrid extends StatelessWidget {
  // NOTE: this widget's only input is EnemyBoardView. It has no way to
  // reach the opponent's unrevealed ship layout even if it wanted to —
  // that data was never handed to it. See the file header.
  const _EnemyGrid({required this.view, required this.scheme, required this.enabled, required this.onTapCell});
  final EnemyBoardView view;
  final ColorScheme scheme;
  final bool enabled;
  final void Function(int cell) onTapCell;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: bsSize),
      itemCount: bsSize * bsSize,
      itemBuilder: (context, i) {
        final status = view.statuses[i];
        final color = switch (status) {
          BsCellStatus.unknown => scheme.tertiaryContainer.withValues(alpha: 0.5),
          BsCellStatus.miss => scheme.surfaceContainerHighest,
          BsCellStatus.hit => Colors.orange.shade400,
          BsCellStatus.sunk => Colors.red.shade700,
        };
        final icon = switch (status) {
          BsCellStatus.miss => const Icon(Icons.remove, size: 14),
          BsCellStatus.hit => const Icon(Icons.local_fire_department, size: 14, color: Colors.white),
          BsCellStatus.sunk => const Icon(Icons.close, size: 16, color: Colors.white),
          BsCellStatus.unknown => null,
        };
        return GestureDetector(
          key: Key('bsEnemy_$i'),
          onTap: (enabled && status == BsCellStatus.unknown) ? () => onTapCell(i) : null,
          child: Container(margin: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: icon == null ? null : Center(child: icon)),
        );
      },
    ),
  );
}
