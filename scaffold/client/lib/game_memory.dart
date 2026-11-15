// OLIVE BRANCH — Memory pairs, on her own. No longer UNVERIFIED — verified by CI (test/game_memory_test.dart).
// Prototype k.g.mem (mod-child.js). MASTERFILE §2.1 P1-P3, §9.2.
//
// Flip two cards; a pair stays together, a miss turns back over. The number of pairs grows with her age
// (game_solo_logic.dart memoryPairsForAge: 3 for the youngest, then 4 / 6 / 8). This is NOT the "Our photos"
// game (GameKind.memory, which waits on the photo-source decision and stays unbuilt): it uses eight drawn
// symbols and no photograph, so nothing here needs a camera, an upload or a guardian's picture.
//
// Calm by construction: no timer, no move counter, no score, no "best". A miss waits 900 ms (1200 ms when she
// has reduced motion on, so there is longer to look, not less) and turns back over. The end line is
// "All the pairs are together." and one quiet "Play again".
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'access_scope.dart' show reduceMotionOf;
import 'form_factors.dart' as ff;
import 'game_solo_logic.dart';

/// The drawn symbols: shape AND colour both differ, so a pair is never told apart by colour alone.
const List<IconData> _symbolIcons = <IconData>[
  Icons.star_rounded, Icons.favorite_rounded, Icons.nightlight_round, Icons.wb_sunny_rounded,
  Icons.eco_rounded, Icons.set_meal_rounded, Icons.pets_rounded, Icons.local_florist_rounded,
];
const List<Color> _symbolColours = <Color>[
  Color(0xFFD9A400), Color(0xFFC94F6D), Color(0xFF4A3F8F), Color(0xFFE8735B),
  Color(0xFF3F8F5A), Color(0xFF2F7FA8), Color(0xFF8A5A3C), Color(0xFFB04FA8),
];

class GameMemoryPairs extends StatefulWidget {
  const GameMemoryPairs({super.key, this.childAge = 7, this.seed});

  /// Chooses how many pairs. Only her age band is read; the age itself is never shown.
  final int childAge;

  /// Fixes the shuffle for tests.
  final int? seed;

  @override
  State<GameMemoryPairs> createState() => _GameMemoryPairsState();
}

class _GameMemoryPairsState extends State<GameMemoryPairs> {
  late final Random _rng = Random(widget.seed);
  late MemoryState _s = newMemory(memoryPairsForAge(widget.childAge), _rng);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tap(int i) {
    final MemoryState next = memoryFlip(_s, i);
    if (identical(next, _s)) return;
    setState(() => _s = next);
    if (next.needsResolve) {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: reduceMotionOf(context) ? 1200 : 900), () {
        if (!mounted) return;
        setState(() => _s = memoryResolve(_s));
      });
    }
  }

  void _again() {
    _timer?.cancel();
    setState(() => _s = newMemory(memoryPairsForAge(widget.childAge), _rng));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int n = _s.cards.length;
    final int columns = n <= 6 ? 3 : 4;
    return Scaffold(
      appBar: AppBar(title: const Text('Memory pairs')),
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(ff.Viewport(w: c.maxWidth, h: c.maxHeight), textScale) >= 2;
        final Widget board = Center(child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 520 : 460),
          child: GridView.builder(
            key: const Key('memoryBoard'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: n,
            itemBuilder: (BuildContext context, int i) => _MemoryCard(
              key: Key('memoryCard_$i'),
              symbol: _s.cards[i],
              up: _s.faceUp.contains(i),
              matched: _s.matched.contains(i),
              onTap: () => _tap(i),
            ),
          ),
        ));
        final Widget line = _s.complete
            ? Container(
                key: const Key('memoryDone'),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Row(children: <Widget>[
                  const Icon(Icons.favorite_border_rounded),
                  const SizedBox(width: 8),
                  Expanded(child: Text('All the pairs are together.',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                ]))
            : Text('Turn two over. Find the ones that match.',
                key: const Key('memoryPrompt'), style: theme.textTheme.titleMedium);
        final Widget again = _s.complete
            ? SizedBox(height: 48, child: FilledButton.icon(
                key: const Key('memoryAgain'), onPressed: _again,
                icon: const Icon(Icons.refresh), label: const Text('Play again')))
            : const SizedBox.shrink();
        if (wide) {
          return Padding(padding: const EdgeInsets.all(16), child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: SingleChildScrollView(child: board)),
              const SizedBox(width: 24),
              SizedBox(width: 260, child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[line, const SizedBox(height: 16), again])),
            ],
          ));
        }
        return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          line, const SizedBox(height: 12), board, const SizedBox(height: 16),
          Center(child: again),
        ]);
      })),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({super.key, required this.symbol, required this.up, required this.matched, required this.onTap});
  final int symbol;
  final bool up, matched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool shown = up || matched;
    final String name = memorySymbols[symbol];
    return Semantics(
      button: !matched, container: true, excludeSemantics: true,
      label: shown ? (matched ? '$name, together' : name) : 'Card, face down',
      onTap: matched ? null : onTap,
      child: Material(
        color: shown ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: matched ? null : onTap,
          child: Center(child: shown
              ? Icon(_symbolIcons[symbol], size: 40, color: _symbolColours[symbol])
              : Icon(Icons.help_outline_rounded, size: 32, color: scheme.onPrimaryContainer.withValues(alpha: 0.6))),
        ),
      ),
    );
  }
}
