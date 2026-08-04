// OLIVE BRANCH — her colour, first pick. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). §8.6.
//
// Renders MARKUP screen 'colourPick'. Twelve curated swatches, not a colour
// picker — a free picker hands a five-year-old #FEFEFE and no explanation.
// Skippable, like every first-run step: a child with no colour simply has no
// colour, and the app looks exactly as it did before.
//
// The live preview below uses applyColour() for real, not decoratively — it
// asks for two placements (avatar_ring, accent_stripe), both on the §8.6.2
// allowed list, so the same guard the palette module enforces is visibly the
// thing drawing this screen.
import 'package:flutter/material.dart';
import 'onboarding_shared.dart';
import 'palette_logic.dart';

class ColourPickScreen extends StatefulWidget {
  const ColourPickScreen({super.key, required this.childName, required this.onContinue});

  final String childName;
  final ValueChanged<String?> onContinue;

  @override
  State<ColourPickScreen> createState() => _ColourPickScreenState();
}

class _ColourPickScreenState extends State<ColourPickScreen> {
  String? _chosenId;

  @override
  Widget build(BuildContext context) {
    final chosen = swatchFor(_chosenId);
    return ChildOnboardingScaffold(
      title: 'Pick your colour',
      subtitle: 'It shows up around the app, just for you.',
      accent: chosen?.color,
      onContinue: () => widget.onContinue(_chosenId),
      onSkip: () => widget.onContinue(null),
      body: Column(children: [
        if (chosen != null) _LivePreview(childName: widget.childName, swatch: chosen),
        if (chosen != null) const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1,
          children: [for (final s in palette) _SwatchTile(
            swatch: s,
            selected: s.id == _chosenId,
            onTap: () => setState(() => _chosenId = s.id),
          )],
        ),
      ]),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  const _SwatchTile({required this.swatch, required this.selected, required this.onTap});
  final Swatch swatch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: swatch.label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        decoration: BoxDecoration(
          color: swatch.color,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: Colors.white, width: 3.5) : null,
          boxShadow: selected
            ? [BoxShadow(color: swatch.color.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 1)]
            : const [],
        ),
        child: selected ? Icon(Icons.check_rounded, color: swatch.ink) : null,
      ),
    ),
  );
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.childName, required this.swatch});
  final String childName;
  final Swatch swatch;

  @override
  Widget build(BuildContext context) {
    // Only ever request allowed placements. applyColour() would refuse a
    // forbidden one outright rather than trusting the caller — see
    // palette_logic.dart's port of the same guard.
    final outcome = applyColour(swatch.id, const ['avatar_ring', 'accent_stripe']);
    final placements = outcome.ok ? outcome.placements : const <String>[];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        if (placements.contains('avatar_ring'))
          CircleAvatar(radius: 26, backgroundColor: swatch.color, child: CircleAvatar(
            radius: 22, backgroundColor: Theme.of(context).colorScheme.surface,
            child: Text(childName.isEmpty ? '?' : childName.substring(0, 1).toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: swatch.ink))))
        else
          CircleAvatar(radius: 26, child: Text(childName.isEmpty ? '?' : childName.substring(0, 1))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(childName.isEmpty ? 'You' : childName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          if (placements.contains('accent_stripe'))
            Container(height: 4, width: 64, decoration: BoxDecoration(
              color: swatch.color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 4),
          Text('${swatch.label[0].toUpperCase()}${swatch.label.substring(1)}',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      ]),
    );
  }
}
