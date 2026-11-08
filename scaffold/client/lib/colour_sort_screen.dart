// OLIVE BRANCH — Colour sort, the first colour activity. No longer UNVERIFIED —
// verified by CI (a Flutter toolchain runs for real in tools/verify.sh's
// automated pipeline). MASTERFILE §8.6.5, P2.
//
// "Let's find things that are sea blue." Up to nine pictures, all today's
// colour, and three baskets: fruit, vegetables, animals. She taps a picture,
// then a basket. Right: it hops in. Not quite: it wobbles back, with no buzzer
// and no red, and the right basket glows softly. "All done" is always there.
//
// The rules live in colour_activities_logic.dart (SortRound). This screen has
// no score, no counter, no timer and no streak (P2): the only numbers on it are
// the ones a child can count herself, the pictures.
import 'package:flutter/material.dart';
import 'colour_activities_logic.dart';
import 'colour_foods.dart';
import 'her_colour_art.dart';
import 'palette_logic.dart';

class ColourSortScreen extends StatefulWidget {
  const ColourSortScreen({super.key, required this.swatch, required this.style,
    this.groups = foodGroups});

  final Swatch swatch;
  /// One of the seven art styles; drawn as the guardian chose.
  final String style;
  final List<String> groups;

  @override
  State<ColourSortScreen> createState() => _ColourSortScreenState();
}

class _ColourSortScreenState extends State<ColourSortScreen> {
  late final SortRound _round = SortRound(sortPool(widget.swatch.id, groups: widget.groups));
  int? _wobble;

  void _put(String group) {
    final sel = _round.selected;
    final ok = _round.put(group);
    setState(() => _wobble = (!ok && sel != null) ? sel : null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = widget.swatch.label;
    return Scaffold(
      appBar: AppBar(title: const Text('Colour sort')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_round.items.isEmpty)
            Text('There is nothing for this colour to sort today.',
              style: Theme.of(context).textTheme.titleMedium)
          else ...[
            Text('Let’s find things that are $label.',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_round.message, key: const Key('sortMessage'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final i in _round.remaining)
                _ItemButton(
                  key: Key('sortItem$i'),
                  item: _round.items[i], swatch: widget.swatch, style: widget.style,
                  selected: _round.selected == i, wobbling: _wobble == i,
                  onTap: () => setState(() { _wobble = null; _round.pick(i); })),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              for (final g in _round.baskets) ...[
                Expanded(child: _Basket(
                  key: Key('basket_$g'),
                  group: g, glow: _round.glow == g,
                  inside: [for (final e in _round.placed.entries) if (e.value == g) _round.items[e.key]],
                  swatch: widget.swatch, style: widget.style, onTap: () => _put(g))),
                if (g != _round.baskets.last) const SizedBox(width: 8),
              ],
            ]),
          ],
          const SizedBox(height: 18),
          Align(alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              key: const Key('sortDone'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('All done'))),
        ]),
      )),
    );
  }
}

class _ItemButton extends StatelessWidget {
  const _ItemButton({super.key, required this.item, required this.swatch, required this.style,
    required this.selected, required this.wobbling, required this.onTap});
  final FoodItem item;
  final Swatch swatch;
  final String style;
  final bool selected;
  final bool wobbling;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true, selected: selected, label: item.spoken,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(wobbling ? 4 : 0, 0, 0),
          constraints: const BoxConstraints(minWidth: 88, minHeight: 88),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(child: ColourArt(recipe: item.art, color: swatch.color, style: style, size: 64)),
            Text(item.spoken, style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      ),
    );
  }
}

class _Basket extends StatelessWidget {
  const _Basket({super.key, required this.group, required this.glow, required this.inside,
    required this.swatch, required this.style, required this.onTap});
  final String group;
  final bool glow;
  final List<FoodItem> inside;
  final Swatch swatch;
  final String style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true, label: foodGroupLabels[group],
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: glow ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: glow ? scheme.primary : scheme.outlineVariant, width: glow ? 3 : 1)),
          child: Column(children: [
            Text(foodGroupLabels[group]!, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(alignment: WrapAlignment.center, children: [
              for (final it in inside)
                ExcludeSemantics(child: ColourArt(recipe: it.art, color: swatch.color, style: style, size: 34)),
            ]),
          ]),
        ),
      ),
    );
  }
}
