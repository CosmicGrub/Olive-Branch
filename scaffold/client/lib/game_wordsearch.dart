// OLIVE BRANCH — word search. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.2.
//
// The puzzle engine below (WordSearchPuzzle/buildWordSearch/findWord/
// wordSearchComplete) is a 1:1 semantic port of the `WORD SEARCH` section of
// packages/games/src/games2.ts, kept close to the original on purpose (same
// function names, same shapes, same 400-attempt placement loop) — the same
// discipline lock_controller.dart applies when porting lock.ts.
//
// §9.2's whole point for this title: "word search is a poor two-player game
// as normally played. What makes it work here is that the PARENT hides the
// words, and the words are personal... It becomes a message disguised as a
// puzzle." That single sentence drives the split below into two screens:
//
//   WordSearchSetupScreen — guardian-facing. Where the words are typed and
//   hidden. Never reachable from a child surface.
//
//   WordSearchScreen — child-facing. Only ever sees the finished puzzle: the
//   grid and the list of words to find, never how or when they were placed.
//   No settings affordance, selection works by tap alone (TAP_ALWAYS_
//   SUFFICES, §8.13.2) so no gesture precision is required to play.
//
// There is no live transport yet (see api_client.dart), so this demo chains
// the two screens directly in one Navigator stack — the setup screen pushes
// straight to the play screen with the freshly-built puzzle — rather than
// pretending the words travelled over a real network to a second device.
//
// P2: no score, no time, no streak. Completion is "you found them all",
// never a number.
import 'package:flutter/material.dart';
import 'dart:math';

// ============================================================ PUZZLE ENGINE =
class WordSearchWord {
  const WordSearchWord({required this.word, required this.cells, required this.found});
  final String word;
  final List<int> cells;
  final bool found;
  WordSearchWord copyWith({bool? found}) =>
      WordSearchWord(word: word, cells: cells, found: found ?? this.found);
}

class WordSearchPuzzle {
  const WordSearchPuzzle({required this.grid, required this.size, required this.words});
  final List<List<String>> grid;
  final int size;
  final List<WordSearchWord> words;
}

class WordSearchBuildResult {
  const WordSearchBuildResult.ok(this.puzzle) : reason = null, word = null;
  const WordSearchBuildResult.err(this.reason, {this.word}) : puzzle = null;
  final WordSearchPuzzle? puzzle;
  final String? reason;
  final String? word;
  bool get ok => puzzle != null;
}

const _wsDirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
const _wsLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

WordSearchBuildResult buildWordSearch(List<String> words, {int size = 10, Random? random}) {
  final rand = random ?? Random();
  final clean = words
      .map((w) => w.toUpperCase().replaceAll(RegExp('[^A-Z]'), ''))
      .where((w) => w.isNotEmpty)
      .toList();
  if (clean.isEmpty) return const WordSearchBuildResult.err('no_words');
  for (final w in clean) {
    if (w.length > size) return WordSearchBuildResult.err('word_too_long', word: w);
  }

  final grid = List<List<String?>>.generate(size, (_) => List<String?>.filled(size, null));
  final placed = <WordSearchWord>[];

  for (final w in clean) {
    var done = false;
    for (var attempt = 0; attempt < 400 && !done; attempt++) {
      final (dr, dc) = _wsDirs[rand.nextInt(_wsDirs.length)];
      final r0 = rand.nextInt(size), c0 = rand.nextInt(size);
      final cells = <int>[];
      var fits = true;
      for (var i = 0; i < w.length; i++) {
        final r = r0 + dr * i, c = c0 + dc * i;
        if (r < 0 || r >= size || c < 0 || c >= size) { fits = false; break; }
        final cur = grid[r][c];
        if (cur != null && cur != w[i]) { fits = false; break; }
        cells.add(r * size + c);
      }
      if (!fits) continue;
      for (var i = 0; i < cells.length; i++) {
        grid[cells[i] ~/ size][cells[i] % size] = w[i];
      }
      placed.add(WordSearchWord(word: w, cells: cells, found: false));
      done = true;
    }
    if (!done) return WordSearchBuildResult.err('could_not_place', word: w);
  }
  final full = [
    for (final row in grid) [for (final x in row) x ?? _wsLetters[rand.nextInt(26)]],
  ];
  return WordSearchBuildResult.ok(WordSearchPuzzle(grid: full, size: size, words: placed));
}

class WordSearchFindResult {
  const WordSearchFindResult({required this.found, required this.puzzle});
  final String? found;
  final WordSearchPuzzle puzzle;
}

String _sortedKey(List<int> cells) => ([...cells]..sort()).join(',');

WordSearchFindResult findWord(WordSearchPuzzle p, List<int> cells) {
  final key = _sortedKey(cells);
  WordSearchWord? hit;
  for (final w in p.words) {
    if (w.found) continue;
    if (_sortedKey(w.cells) == key) { hit = w; break; }
  }
  if (hit == null) return WordSearchFindResult(found: null, puzzle: p);
  final theHit = hit;
  return WordSearchFindResult(
    found: theHit.word,
    puzzle: WordSearchPuzzle(grid: p.grid, size: p.size,
      words: [for (final w in p.words) identical(w, theHit) ? w.copyWith(found: true) : w]),
  );
}

bool wordSearchComplete(WordSearchPuzzle p) => p.words.every((w) => w.found);

/// A straight line only — horizontal, vertical, or a perfect diagonal —
/// mirroring the four directions `buildWordSearch` ever places a word along.
/// Returns null for anything else, including a single cell.
List<(int, int)>? straightPath((int, int) start, (int, int) end) {
  final dr = end.$1 - start.$1, dc = end.$2 - start.$2;
  if (dr == 0 && dc == 0) return null;
  if (!(dr == 0 || dc == 0 || dr.abs() == dc.abs())) return null;
  final stepR = dr == 0 ? 0 : (dr > 0 ? 1 : -1);
  final stepC = dc == 0 ? 0 : (dc > 0 ? 1 : -1);
  final steps = max(dr.abs(), dc.abs());
  return [for (var i = 0; i <= steps; i++) (start.$1 + stepR * i, start.$2 + stepC * i)];
}

const List<Color> wordSearchPalette = [
  Color(0xFFF7B267), Color(0xFF8FD3C7), Color(0xFFE8735B),
  Color(0xFF8E9EE8), Color(0xFFD4A5E0), Color(0xFFA6D189),
];

// ============================================================= SETUP (guardian)
/// Guardian-facing. She never sees this screen; it is where the words get
/// hidden, per §9.2 — "the PARENT hides the words, and they are personal".
class WordSearchSetupScreen extends StatefulWidget {
  const WordSearchSetupScreen({
    super.key,
    this.childName = 'Ivy',
    this.initialWords = const ['Ivy', 'Biscuit', 'Maple Street', 'Soccer'],
  });

  final String childName;
  /// Demo-only starter words (her name, the dog, her street, this week's
  /// thing) — a real build has the guardian type these fresh each time.
  final List<String> initialWords;

  @override
  State<WordSearchSetupScreen> createState() => _WordSearchSetupScreenState();
}

class _WordSearchSetupScreenState extends State<WordSearchSetupScreen> {
  late final List<String> _words = [...widget.initialWords];
  final _controller = TextEditingController();
  // 12, not 10: the default demo word "Maple Street" cleans to 11 letters
  // (buildWordSearch strips the space), which doesn't fit an initial 10x10
  // grid — a brand-new guardian who never touches the size control would
  // hit "too long for a 10x10 grid" on the very first tap of "Hide these
  // words". Every default starter word fits a 12x12 grid.
  int _size = 12;
  String? _problem;

  void _addWord() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _words.add(text); _controller.clear(); _problem = null; });
  }

  void _removeWord(int i) => setState(() { _words.removeAt(i); _problem = null; });

  void _hideWords() {
    final result = buildWordSearch(_words, size: _size);
    if (!result.ok) {
      setState(() => _problem = switch (result.reason) {
        'no_words' => 'Add at least one word first.',
        'word_too_long' =>
          '"${result.word}" is too long for a $_size×$_size grid — try a shorter word, or a bigger grid.',
        _ => 'Couldn\'t fit "${result.word}" in with the others — try removing one.',
      });
      return;
    }
    setState(() => _problem = null);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WordSearchScreen(puzzle: result.puzzle!, childName: widget.childName),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Hide words for ${widget.childName}')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Her name, the dog, her street, something she\'s excited about this '
           'week — a word search is a message disguised as a puzzle.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: TextField(controller: _controller,
          decoration: const InputDecoration(hintText: 'A personal word…', isDense: true,
            border: OutlineInputBorder()),
          onSubmitted: (_) => _addWord())),
        const SizedBox(width: 8),
        FilledButton(onPressed: _addWord, child: const Text('Add')),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < _words.length; i++)
          InputChip(label: Text(_words[i]), onDeleted: () => _removeWord(i)),
      ]),
      const SizedBox(height: 20),
      Text('Grid size', style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 8, label: Text('Small')),
          ButtonSegment(value: 10, label: Text('Medium')),
          ButtonSegment(value: 12, label: Text('Large')),
        ],
        selected: {_size},
        onSelectionChanged: (s) => setState(() => _size = s.first),
      ),
      if (_problem != null) Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
          child: Text(_problem!, style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer)))),
      const SizedBox(height: 24),
      SizedBox(height: 48, width: double.infinity,
        child: FilledButton.icon(onPressed: _hideWords,
          icon: const Icon(Icons.visibility_off_outlined),
          label: const Text('Hide these words'))),
    ])),
  );
}

// =============================================================== PLAY (child)
class WordSearchScreen extends StatefulWidget {
  const WordSearchScreen({super.key, required this.puzzle, this.childName = 'Ivy'});
  final WordSearchPuzzle puzzle;
  final String childName;

  @override
  State<WordSearchScreen> createState() => _WordSearchScreenState();
}

class _WordSearchScreenState extends State<WordSearchScreen> {
  late WordSearchPuzzle _puzzle = widget.puzzle;
  (int, int)? _anchor;

  void _tapCell(int r, int c) {
    if (_anchor == null) { setState(() => _anchor = (r, c)); return; }
    if (_anchor == (r, c)) { setState(() => _anchor = null); return; }
    final path = straightPath(_anchor!, (r, c));
    if (path == null) {
      // Not a line — start a fresh selection here instead of doing nothing.
      // TAP_ALWAYS_SUFFICES: every tap is legible (§8.13.2).
      setState(() => _anchor = (r, c));
      return;
    }
    final cells = [for (final (rr, cc) in path) rr * _puzzle.size + cc];
    final result = findWord(_puzzle, cells);
    setState(() {
      if (result.found != null) _puzzle = result.puzzle;
      _anchor = null;
    });
  }

  int? _colorIndexFor(int cellIndex) {
    for (var i = 0; i < _puzzle.words.length; i++) {
      final w = _puzzle.words[i];
      if (w.found && w.cells.contains(cellIndex)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final complete = wordSearchComplete(_puzzle);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.childName}\'s word search')),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final w in _puzzle.words) Chip(
              avatar: w.found ? const Icon(Icons.check, size: 18) : null,
              label: Text(w.word, style: TextStyle(
                decoration: w.found ? TextDecoration.lineThrough : TextDecoration.none)),
            ),
          ]),
          const SizedBox(height: 16),
          if (complete) Container(
            key: const Key('wsComplete'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(16)),
            child: const Row(children: [
              Icon(Icons.celebration_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('You found them all!',
                style: TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ) else Text('Tap a letter, then tap the last letter of the word.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Center(child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: min(constraints.maxWidth, 480)),
            child: AspectRatio(aspectRatio: 1, child: _Grid(
              puzzle: _puzzle, anchor: _anchor, onTapCell: _tapCell,
              colorIndexFor: _colorIndexFor, scheme: scheme,
            )),
          )),
        ]);
      })),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.puzzle, required this.anchor, required this.onTapCell,
    required this.colorIndexFor, required this.scheme});
  final WordSearchPuzzle puzzle;
  final (int, int)? anchor;
  final void Function(int r, int c) onTapCell;
  final int? Function(int cellIndex) colorIndexFor;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final cell = constraints.maxWidth / puzzle.size;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r < puzzle.size; r++) Row(children: [
          for (var c = 0; c < puzzle.size; c++) _buildCell(r, c, cell),
        ]),
      ]),
    );
  });

  Widget _buildCell(int r, int c, double cell) {
    final index = r * puzzle.size + c;
    final colorIdx = colorIndexFor(index);
    final isAnchor = anchor == (r, c);
    final bg = colorIdx != null
        ? wordSearchPalette[colorIdx % wordSearchPalette.length].withValues(alpha: 0.55)
        : isAnchor ? scheme.primary.withValues(alpha: 0.4) : Colors.transparent;
    return GestureDetector(
      key: Key('wsCell_${r}_$c'),
      onTap: () => onTapCell(r, c),
      child: Container(
        // -2 so the 1px margin on every side doesn't push the row/column
        // past the exact `cell` budget it was given (that overflow is
        // small enough to be invisible but RenderFlex still refuses it).
        width: cell - 2, height: cell - 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        margin: const EdgeInsets.all(1),
        child: Text(puzzle.grid[r][c],
          style: TextStyle(fontSize: (cell * 0.42).clamp(10, 20), fontWeight: FontWeight.w600)),
      ),
    );
  }
}
