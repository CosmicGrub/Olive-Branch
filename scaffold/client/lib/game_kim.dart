// OLIVE BRANCH — Kim's game. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.2.
//
// Unlike checkers/battleship/word search, there is no `packages/games`
// source for this title — MASTERFILE §9.2 describes it only in prose:
// "A photo of his real table with one thing removed. Zero art assets, and
// it teaches her what his house looks like." There is no photo pipeline in
// this codebase yet (no upload, no storage, no moderation queue for a
// parent's own photo), so building the real version here would mean faking
// a capability that doesn't exist — exactly what this project's culture
// treats as worse than admitting the gap.
//
// HONEST STUB: the "table" below is a small set of hand-picked icons
// standing in for a photograph, not a photograph. That is said plainly in
// the UI (a quiet caption, not an apology) rather than only in this
// comment, because a child-facing screen that silently pretends a stand-in
// is the real thing is the failure mode §9.2 exists to avoid. When a real
// photo pipeline exists, `KimScene.items` is the seam: swap hand-picked
// icons for cropped regions of an uploaded photo and the round logic below
// is unchanged.
//
// Game shape, chosen to fit the house rules elsewhere in this file:
//   - Self-paced, no timer. "Ready?" is a button, not a countdown — the
//     product's own scavenger-hunt rule ("a countdown would make wandering
//     a test", §9.2) applies here for the same reason.
//   - Unlimited, ungraded guesses. Guessing wrong just says "take another
//     look" — there is no lives counter, no attempt tally, nothing that
//     could read as a score. P2 governs even where it isn't a competitive
//     game against the parent.
import 'dart:math';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

class KimItem {
  const KimItem({required this.id, required this.icon, required this.label});
  final String id;
  final IconData icon;
  final String label;
}

class KimScene {
  const KimScene({required this.title, required this.items});
  final String title;
  final List<KimItem> items;
}

/// Placeholder "tables" standing in for a parent's own photographed scene.
const List<KimScene> kimDemoScenes = [
  KimScene(title: "Dad's kitchen table", items: [
    KimItem(id: 'mug', icon: Icons.coffee, label: 'Mug'),
    KimItem(id: 'keys', icon: Icons.vpn_key, label: 'Keys'),
    KimItem(id: 'glasses', icon: Icons.visibility_outlined, label: 'Glasses'),
    KimItem(id: 'apple', icon: Icons.eco, label: 'Apple'),
    KimItem(id: 'book', icon: Icons.menu_book, label: 'Book'),
    KimItem(id: 'plant', icon: Icons.local_florist, label: 'Plant'),
    KimItem(id: 'phone', icon: Icons.smartphone, label: 'Phone'),
    KimItem(id: 'lamp', icon: Icons.emoji_objects, label: 'Lamp'),
  ]),
  KimScene(title: "Dad's desk", items: [
    KimItem(id: 'laptop', icon: Icons.laptop_mac, label: 'Laptop'),
    KimItem(id: 'pencil', icon: Icons.edit, label: 'Pencil'),
    KimItem(id: 'photo', icon: Icons.photo, label: 'Photo frame'),
    KimItem(id: 'clock', icon: Icons.access_time, label: 'Clock'),
    KimItem(id: 'headphones', icon: Icons.headphones, label: 'Headphones'),
    KimItem(id: 'notebook', icon: Icons.book, label: 'Notebook'),
    KimItem(id: 'mug2', icon: Icons.local_cafe, label: 'Mug'),
  ]),
  KimScene(title: 'The porch', items: [
    KimItem(id: 'boots', icon: Icons.hiking, label: 'Boots'),
    KimItem(id: 'ball', icon: Icons.sports_soccer, label: 'Ball'),
    KimItem(id: 'watering', icon: Icons.water_drop, label: 'Watering can'),
    KimItem(id: 'chair', icon: Icons.chair, label: 'Chair'),
    KimItem(id: 'dogbowl', icon: Icons.pets, label: "Biscuit's bowl"),
    KimItem(id: 'mail', icon: Icons.mail_outline, label: 'Mail'),
  ]),
];

class GameKim extends StatefulWidget {
  const GameKim({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.scenes = kimDemoScenes,
    this.random,
  });

  final String childName;
  final String parentName;
  final List<KimScene> scenes;
  /// Injectable for deterministic tests; a real game uses the platform RNG.
  final Random? random;

  @override
  State<GameKim> createState() => _GameKimState();
}

class _GameKimState extends State<GameKim> {
  late final Random _rand = widget.random ?? Random();
  int _sceneIndex = 0;
  bool _studying = true;
  late KimItem _missing;
  late List<KimItem> _choiceOrder;
  bool? _lastGuessCorrect;

  KimScene get _scene => widget.scenes[_sceneIndex];

  @override
  void initState() {
    super.initState();
    _startRound();
  }

  void _startRound() {
    final items = _scene.items;
    _missing = items[_rand.nextInt(items.length)];
    _choiceOrder = [...items]..shuffle(_rand);
    _studying = true;
    _lastGuessCorrect = null;
  }

  void _reveal() => setState(() => _studying = false);

  void _guess(KimItem item) {
    setState(() => _lastGuessCorrect = item.id == _missing.id);
  }

  void _nextTable() {
    setState(() {
      _sceneIndex = (_sceneIndex + 1) % widget.scenes.length;
      _startRound();
    });
  }

  void _sameTableAgain() => setState(_startRound);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleItems = _studying
        ? _scene.items
        : _scene.items.where((i) => i.id != _missing.id).toList();
    final solved = _lastGuessCorrect == true;

    return Scaffold(
      appBar: AppBar(title: const Text("Kim's game")),
      // On a wide tablet/desktop viewport the single column is only ever
      // capped to a comfortable reading width and centered, never split —
      // same real columnsAt() gate every other reading-cap screen uses
      // (form_factors.dart). Nothing below this changes.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        final Widget content = ListView(padding: const EdgeInsets.all(16), children: [
          Text(_scene.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('made of stand-in pictures for now — a real photo of the table comes later',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text(_studying
              ? 'Take a good look at ${widget.parentName}\'s table.'
              : "Which one's missing?",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _ItemGrid(items: visibleItems, keyPrefix: 'kimTable', compact: capWidth),
          const SizedBox(height: 20),
          if (_studying)
            Center(child: SizedBox(height: 48, child: FilledButton.icon(
              key: const Key('kimReady'),
              onPressed: _reveal,
              icon: const Icon(Icons.visibility),
              label: const Text("I'm ready"))))
          else ...[
            if (solved) _SolvedBanner(missing: _missing)
            else ...[
              Text('Tap the thing you think is gone:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              _ItemGrid(items: _choiceOrder, keyPrefix: 'kimChoice', onTap: _guess,
                highlightWrong: _lastGuessCorrect == false, compact: capWidth),
              if (_lastGuessCorrect == false) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: _CalloutKim(text: 'Not quite — want to look again?'),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _sameTableAgain,
                icon: const Icon(Icons.refresh),
                label: const Text('Same table again')),
              const SizedBox(width: 12),
              if (solved) FilledButton.icon(
                key: const Key('kimNextTable'),
                onPressed: _nextTable,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Another table')),
            ]),
          ],
        ]);
        return capWidth
            ? Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                child: content))
            : content;
      })),
    );
  }
}

class _SolvedBanner extends StatelessWidget {
  const _SolvedBanner({required this.missing});
  final KimItem missing;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('kimSolved'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      const Icon(Icons.celebration_outlined),
      const SizedBox(width: 8),
      Expanded(child: Text('Yes! The ${missing.label.toLowerCase()} was missing.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
    ]),
  );
}

class _CalloutKim extends StatelessWidget {
  const _CalloutKim({required this.text});
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

class _ItemGrid extends StatelessWidget {
  const _ItemGrid({required this.items, required this.keyPrefix,
    this.onTap, this.highlightWrong = false, this.compact = false});
  final List<KimItem> items;
  final String keyPrefix;
  final ValueChanged<KimItem>? onTap;
  final bool highlightWrong;
  /// True only when the screen's own reading-width cap (form_factors.dart)
  /// has engaged. A narrower cross-axis for the SAME item count needs the
  /// Wrap to add a row it never needed at full width, which on a short
  /// viewport (a real §8.11.1 example: the Fold half-open in landscape,
  /// 673x420) can push the wrong-guess callout below the fold. Tiles stay
  /// exactly 88px — the pre-existing, byte-for-byte narrow-posture size —
  /// whenever the cap is NOT engaged; this only ever shrinks them a little
  /// under the cap this same change introduces, never on any posture that
  /// existed before it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final double tileMin = compact ? 72 : 88;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final item in items) InkWell(
        key: Key('${keyPrefix}_${item.id}'),
        onTap: onTap == null ? null : () => onTap!(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: BoxConstraints(minWidth: tileMin, minHeight: tileMin),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(item.icon, size: 30, color: scheme.onPrimaryContainer),
            const SizedBox(height: 4),
            Text(item.label, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer)),
          ]),
        ),
      ),
    ]);
  }
}
