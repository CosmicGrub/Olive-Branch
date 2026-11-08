// OLIVE BRANCH — Path code, the second colour activity. No longer UNVERIFIED —
// verified by CI (a Flutter toolchain runs for real in tools/verify.sh's
// automated pipeline). MASTERFILE §8.6.5, P2, §21.
//
// "Help the fox get to the carrot." Today's colour is the path. She builds a
// row of arrow blocks and presses Run; the hero follows it step by step. A rock
// gently stops it and the blocks stay on screen so she can change one. From 8
// there is a repeat block. Nothing here counts attempts, shows a level number,
// times her or scores her (P2); the program is only ever shown back to her as
// the arrows she wrote.
import 'package:flutter/material.dart';
import 'colour_activities_logic.dart';
import 'colour_foods.dart';
import 'her_colour_art.dart';
import 'palette_logic.dart';

class PathCodeScreen extends StatefulWidget {
  const PathCodeScreen({super.key, required this.swatch, required this.style, required this.age,
    this.stepDuration = const Duration(milliseconds: 350)});

  final Swatch swatch;
  final String style;
  final int age;
  /// How long the hero takes per step. Injectable so tests need not wait.
  final Duration stepDuration;

  @override
  State<PathCodeScreen> createState() => _PathCodeScreenState();
}

class _PathCodeScreenState extends State<PathCodeScreen> {
  int _level = 0;
  List<PathBlock> _program = [];
  Cell? _hero;
  String _message = 'Add arrows, then press Run.';
  bool _running = false;
  bool _reached = false;
  int _runId = 0;

  PathLevel get _lv => pathLevels[_level];
  FoodItem get _heroItem => pathHero(widget.swatch.id);
  FoodItem get _goalItem => pathGoal(widget.swatch.id);

  @override
  void dispose() {
    _runId++;
    super.dispose();
  }

  String _style() => widget.style == 'pixel' ? 'paper' : widget.style;

  void _add(Dir d) {
    if (_running || _program.length >= _lv.maxBlocks) return;
    setState(() { _program = [..._program, PathBlock(d)]; _hero = null; _reached = false; });
  }

  void _repeat() {
    if (_running || _program.isEmpty || !repeatUnlocked(widget.age)) return;
    final last = _program.last;
    setState(() => _program = [..._program.take(_program.length - 1), last.withRepeat(last.repeat >= 4 ? 2 : last.repeat + 1)]);
  }

  void _clear() {
    if (_running) return;
    setState(() { _program = []; _hero = null; _reached = false; _message = 'Add arrows, then press Run.'; });
  }

  Future<void> _run() async {
    if (_running || _program.isEmpty) return;
    final id = ++_runId;
    final run = runProgram(_lv, _program);
    setState(() { _running = true; _reached = false; _hero = _lv.start; });
    final reduce = MediaQuery.disableAnimationsOf(context);
    for (final c in run.positions.skip(1)) {
      if (!reduce) await Future<void>.delayed(widget.stepDuration);
      if (!mounted || id != _runId) return;
      setState(() => _hero = c);
    }
    if (!mounted || id != _runId) return;
    final hero = _heroItem.name.toLowerCase(), goal = _goalItem.name.toLowerCase();
    setState(() {
      _running = false;
      _reached = run.reached;
      _message = switch (run.end) {
        'reached' => 'The $hero reached the $goal!',
        'rock' => 'A rock! The $hero stops. Change a block and run again.',
        'edge' => 'The $hero stays on the path. Change a block and run again.',
        _ => 'Not there yet. Add another arrow.',
      };
    });
  }

  void _next() => setState(() {
    _level = (_level + 1) % pathLevels.length;
    _program = []; _hero = null; _reached = false; _message = 'Add arrows, then press Run.';
  });

  @override
  Widget build(BuildContext context) {
    final lv = _lv;
    final c = widget.swatch.color;
    final hero = _hero ?? lv.start;
    return Scaffold(
      appBar: AppBar(title: const Text('Path code')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Help the ${_heroItem.name.toLowerCase()} get to the ${_goalItem.name.toLowerCase()}.',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_message, key: const Key('pathMessage'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Center(child: Column(children: [
            for (var y = 0; y < lv.size; y++) Row(mainAxisSize: MainAxisSize.min, children: [
              for (var x = 0; x < lv.size; x++) _CellView(
                key: Key('cell_${x}_$y'),
                path: c, rock: lv.rocks.contains((x, y)),
                child: hero == (x, y)
                    ? ColourArt(recipe: _heroItem.art, color: c, style: _style(), size: 40, semanticLabel: _heroItem.name)
                    : lv.goal == (x, y)
                        ? ColourArt(recipe: _goalItem.art, color: c, style: _style(), size: 38, semanticLabel: _goalItem.name)
                        : null),
            ]),
          ])),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, key: const Key('pathProgram'), children: [
            for (final b in _program) Chip(label: Text(programArrows([b]))),
            if (_program.isEmpty) const Text('No arrows yet.'),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in Dir.values) IconButton.filledTonal(
              key: Key('add_${d.name}'),
              tooltip: 'Add ${d.name}',
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
              onPressed: () => _add(d),
              icon: Icon(switch (d) {
                Dir.up => Icons.arrow_upward, Dir.down => Icons.arrow_downward,
                Dir.left => Icons.arrow_back, Dir.right => Icons.arrow_forward }))
            ,
            if (repeatUnlocked(widget.age))
              FilledButton.tonalIcon(key: const Key('repeatBlock'), onPressed: _repeat,
                icon: const Icon(Icons.repeat), label: const Text('Repeat')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(key: const Key('runPath'), onPressed: _run,
              icon: const Icon(Icons.play_arrow), label: const Text('Run'))),
            const SizedBox(width: 8),
            OutlinedButton(key: const Key('clearPath'), onPressed: _clear, child: const Text('Clear')),
          ]),
          if (_reached) ...[
            const SizedBox(height: 12),
            Text('Your program: ${programArrows(_program)}', key: const Key('pathSaved')),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight,
              child: FilledButton.tonal(key: const Key('nextPath'), onPressed: _next, child: const Text('Another path'))),
          ],
        ]),
      )),
    );
  }
}

class _CellView extends StatelessWidget {
  const _CellView({super.key, required this.path, required this.rock, this.child});
  final Color path;
  final bool rock;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    width: 54, height: 54, margin: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: rock ? const Color(0xFF9AA0A6) : path.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(rock ? 18 : 10)),
    alignment: Alignment.center,
    child: rock ? const Icon(Icons.landscape, color: Colors.white70) : child);
}
