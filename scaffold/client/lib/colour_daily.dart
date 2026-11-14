// OLIVE BRANCH — her colour, the daily pick. No longer UNVERIFIED — verified by
// CI (`flutter analyze` and `flutter test` run for real in tools/verify.sh and
// .github/workflows/verify.yml). §8.6.3.
//
// Renders MARKUP screen 'colourDaily'. A two-up A/B, not the full twelve —
// lower effort than a grid, and it plays like a game rather than a settings
// screen. One of the pair is always her CURRENT colour (dailyPair() puts it
// on a randomised side), so keeping it is exactly as easy as changing it. A
// daily prompt that nudged toward change would be manufacturing churn out of
// a child, so there is deliberately no streak, no "N days in a row", and no
// framing of either option as new or better.
//
// "Other colours" (Wave 4, prototype k.colour): one quiet button under the pair opens
// the whole curated set, for the day she wants a colour that is on neither card. It is
// the same answer (the same store call), the same twelve swatches as her first pick, and
// it asks for nothing: no new/better framing, nothing counted, nothing to scroll past.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'palette_logic.dart';

class ColourDailyScreen extends StatefulWidget {
  const ColourDailyScreen({super.key, required this.currentColourId, required this.onChoose,
    this.random});

  final String currentColourId;
  final ValueChanged<String> onChoose;
  /// Injectable for deterministic tests; defaults to dailyPair()'s own
  /// shared Random.
  final double Function()? random;

  @override
  State<ColourDailyScreen> createState() => _ColourDailyScreenState();
}

class _ColourDailyScreenState extends State<ColourDailyScreen> {
  late final DailyPair _pair = dailyPair(widget.currentColourId, rand: widget.random);
  String? _picked;
  bool _all = false;

  void _pick(Swatch s) {
    setState(() => _picked = s.id);
    widget.onChoose(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        // Stacks on the Fold5 cover screen (344px), sits side by side once
        // there is room — no fixed pixel width either way.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool narrow = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) < 2;
        final options = [_pair.a, _pair.b]
          .map((s) => Expanded(child: _ColourCard(
            swatch: s, picked: _picked == s.id, onTap: () => _pick(s))))
          .toList();
        return SingleChildScrollView(child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Which do you like more today?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Pick one — there is no wrong answer.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            narrow
              ? Column(children: [
                  for (final s in [_pair.a, _pair.b]) Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(width: double.infinity, height: 120,
                      child: _ColourCard(swatch: s, picked: _picked == s.id, onTap: () => _pick(s)))),
                ])
              : SizedBox(height: 180, child: Row(children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    options[i],
                  ]])),
            const SizedBox(height: 12),
            if (!_all) TextButton(
              key: const Key('colourMore'),
              style: TextButton.styleFrom(minimumSize: const Size(64, 56)),
              onPressed: () => setState(() => _all = true),
              child: const Text('Other colours', style: TextStyle(fontSize: 18))),
            if (_all) Wrap(
              key: const Key('colourAll'), alignment: WrapAlignment.center, spacing: 12, runSpacing: 12,
              children: [for (final s in palette) Semantics(
                button: true, label: s.label, excludeSemantics: true,
                child: InkWell(
                  key: Key('all_${s.id}'), customBorder: const CircleBorder(), onTap: () => _pick(s),
                  child: Container(width: 64, height: 64,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle,
                      border: _picked == s.id ? Border.all(color: scheme.onSurface, width: 4) : null),
                    child: _picked == s.id ? Icon(Icons.check_rounded, color: s.ink) : null)))]),
          ]),
        )));
      })),
    );
  }
}

class _ColourCard extends StatelessWidget {
  const _ColourCard({required this.swatch, required this.picked, required this.onTap});
  final Swatch swatch;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: swatch.color,
    borderRadius: BorderRadius.circular(24),
    elevation: picked ? 6 : 1,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (picked) Icon(Icons.check_circle_rounded, color: swatch.ink, size: 28),
          if (picked) const SizedBox(height: 4),
          Text(swatch.label, style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800, color: swatch.ink)),
        ])),
      ),
    ),
  );
}
