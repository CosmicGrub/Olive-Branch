// OLIVE BRANCH — Pixel garden, the fourth colour activity. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline). MASTERFILE §8.6.5, P2, §21.
//
// An 8 by 8 garden and today's colour in three tints. Tap squares to plant. A
// mirror switch copies each tap across the middle, which teaches symmetry; a
// stamp copies a pattern along a row. It opens at 8 and only if the guardian
// has coding activities on. There is no score, no "percent planted" and no goal:
// an empty garden is a fine garden.
import 'package:flutter/material.dart';
import 'colour_activities_logic.dart';
import 'her_colour_art.dart';
import 'palette_logic.dart';

class PixelGardenScreen extends StatefulWidget {
  const PixelGardenScreen({super.key, required this.swatch, required this.age, required this.codeActivities});

  final Swatch swatch;
  final int age;
  final bool codeActivities;

  @override
  State<PixelGardenScreen> createState() => _PixelGardenScreenState();
}

class _PixelGardenScreenState extends State<PixelGardenScreen> {
  Garden _garden = Garden.empty();
  int _tint = 2;
  bool _stamp = false;

  bool get _open => widget.age >= pixelGardenMinAge && widget.codeActivities;

  void _tap(int x, int y) => setState(() {
    if (_stamp) {
      _garden = _garden.repeatRow(y, x + 1);
      _stamp = false;
    } else {
      _garden = _garden.plant(x, y, _tint);
    }
  });

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pixel garden')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Text(widget.codeActivities
              ? 'The pixel garden opens at 8.'
              : 'The pixel garden is resting for now.',
            key: const Key('pixelClosed'), style: Theme.of(context).textTheme.titleMedium))));
    }
    final tints = tintsOf(widget.swatch.color);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pixel garden')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(_stamp ? 'Tap where your pattern ends.' : 'Tap squares to plant.',
            key: const Key('pixelHint'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (var y = 0; y < Garden.size; y++) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var x = 0; x < Garden.size; x++) GestureDetector(
              key: Key('px_${x}_$y'),
              onTap: () => _tap(x, y),
              child: Container(
                width: 38, height: 38, margin: const EdgeInsets.all(1),
                color: _garden.at(x, y) == 0 ? scheme.surfaceContainerHighest : tints[_garden.at(x, y) - 1])),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var t = 1; t <= 3; t++) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Semantics(button: true, selected: _tint == t, label: const ['', 'A lighter tint', 'Today’s colour', 'A darker tint'][t],
                child: InkWell(key: Key('ptint$t'), customBorder: const CircleBorder(),
                  onTap: () => setState(() => _tint = t),
                  child: Container(width: 48, height: 48, decoration: BoxDecoration(color: tints[t - 1], shape: BoxShape.circle,
                    border: Border.all(color: _tint == t ? scheme.primary : scheme.outlineVariant, width: _tint == t ? 4 : 1)))))),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(key: const Key('mirrorSwitch'), title: const Text('Mirror'),
            subtitle: const Text('Each tap is copied across the middle.'),
            value: _garden.mirror, onChanged: (m) => setState(() => _garden = _garden.withMirror(m))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilterChip(key: const Key('stampChip'), label: const Text('Repeat stamp'),
              selected: _stamp, onSelected: (s) => setState(() => _stamp = s)),
            const SizedBox(width: 8),
            OutlinedButton(key: const Key('pixelClear'), onPressed: () => setState(() => _garden = _garden.cleared()),
              child: const Text('Clear')),
          ]),
        ]),
      )),
    );
  }
}
