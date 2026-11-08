// OLIVE BRANCH — Colour critter, the third colour activity. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline). MASTERFILE §8.6.5, P2.
//
// She picks an animal from today's list and a style from the ones her guardian
// allows. A line drawing: tap a part, it fills with today's colour, a lighter
// tint or a darker tint. Undo is one tap. Nothing can go wrong, nothing is
// graded, and nothing counts how many parts she filled. A second picture shows
// the same animal in the chosen style so she can see what the style does.
import 'package:flutter/material.dart';
import 'colour_activities_logic.dart';
import 'colour_foods.dart';
import 'her_colour_art.dart';
import 'palette_logic.dart';

class ColourCritterScreen extends StatefulWidget {
  const ColourCritterScreen({super.key, required this.swatch, required this.allowedStyles,
    required this.initialStyle});

  final Swatch swatch;
  final List<String> allowedStyles;
  final String initialStyle;

  @override
  State<ColourCritterScreen> createState() => _ColourCritterScreenState();
}

class _ColourCritterScreenState extends State<ColourCritterScreen> {
  late final List<FoodItem> _animals = () {
    final a = foodsFor(widget.swatch.id).where((i) => i.group == 'animals').toList();
    return a.isEmpty ? [const FoodItem('Fox', 'fox', 'animals')] : a;
  }();
  int _animal = 0;
  int _tint = 1;
  late String _style = widget.allowedStyles.contains(widget.initialStyle)
      ? widget.initialStyle : widget.allowedStyles.first;
  late CritterDrawing _drawing = CritterDrawing(_animals.first.art);

  void _pick(int i) => setState(() { _animal = i; _drawing = CritterDrawing(_animals[i].art); });

  @override
  Widget build(BuildContext context) {
    final tints = tintsOf(widget.swatch.color);
    final regions = {for (final e in _drawing.fills.entries) e.key: tints[e.value]};
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Colour critter')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pick an animal, then tap a part to colour it.',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < _animals.length; i++) ChoiceChip(
              key: Key('animal$i'), label: Text(_animals[i].spoken),
              selected: _animal == i, onSelected: (_) => _pick(i)),
          ]),
          const SizedBox(height: 12),
          Center(child: Container(
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.all(8),
            child: ColourArt(
              key: const Key('critterCanvas'),
              recipe: _animals[_animal].art, color: widget.swatch.color, style: 'line', size: 260,
              regions: regions, semanticLabel: 'A line drawing of ${_animals[_animal].spoken} to colour',
              onRegionTap: (r) => setState(() => _drawing.fill(r, _tint))))),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var t = 0; t < 3; t++) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Semantics(button: true, selected: _tint == t,
                label: const ['A lighter tint', 'Today’s colour', 'A darker tint'][t],
                child: InkWell(
                  key: Key('tint$t'), customBorder: const CircleBorder(),
                  onTap: () => setState(() => _tint = t),
                  child: Container(width: 52, height: 52,
                    decoration: BoxDecoration(color: tints[t], shape: BoxShape.circle,
                      border: Border.all(color: _tint == t ? scheme.primary : scheme.outlineVariant, width: _tint == t ? 4 : 1)))))),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton.icon(key: const Key('critterUndo'),
              onPressed: _drawing.canUndo ? () => setState(_drawing.undo) : null,
              icon: const Icon(Icons.undo), label: const Text('Undo')),
            const SizedBox(width: 8),
            OutlinedButton(key: const Key('critterClear'), onPressed: () => setState(_drawing.clear), child: const Text('Clear')),
          ]),
          const SizedBox(height: 16),
          Text('How it looks in a style', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final s in widget.allowedStyles) ChoiceChip(
              key: Key('style_$s'), label: Text(styleName(s)),
              selected: _style == s, onSelected: (_) => setState(() => _style = s)),
          ]),
          const SizedBox(height: 8),
          Center(child: ColourArt(key: const Key('critterPreview'),
            recipe: _animals[_animal].art, color: widget.swatch.color, style: _style, size: 140,
            semanticLabel: '${_animals[_animal].spoken} in ${styleName(_style)} style')),
        ]),
      )),
    );
  }
}

/// A child-friendly name for each art style.
String styleName(String id) => const {
  'paper': 'Paper cut', 'sticker': 'Sticker', 'crayon': 'Crayon', 'watercolour': 'Watercolour',
  'felt': 'Felt', 'line': 'Line art', 'pixel': 'Pixel',
}[id] ?? id;
