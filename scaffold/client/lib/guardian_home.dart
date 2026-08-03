// OLIVE BRANCH — guardian shell, home. UNVERIFIED (no Flutter toolchain). §8.2.
//
// Renders MARKUP screen 05. The dual clock is persistent and the CHILD's time is
// dominant; the parent never performs a timezone calculation (§8.2.3). All times
// arrive pre-rendered from /now and /ribbon so the client does no zone maths.
import 'package:flutter/material.dart';

class RibbonBand {
  const RibbonBand(this.startFraction, this.widthFraction, this.color, this.label);
  final double startFraction, widthFraction;
  final Color color;
  final String label;
}

class GuardianHome extends StatelessWidget {
  const GuardianHome({super.key, required this.childName,
    required this.childLocalTime, required this.childZoneAbbr,
    required this.actorLocalTime, required this.childStateSentence,
    required this.childBands, required this.actorBands, this.overlapLabel});

  final String childName, childLocalTime, childZoneAbbr, actorLocalTime;
  final String childStateSentence;
  final List<RibbonBand> childBands, actorBands;
  final String? overlapLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
                Text(childName, style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(width: 7),
                Text(childLocalTime, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
                Text(childZoneAbbr, style: const TextStyle(fontSize: 10)),
              ]),
            // Actor time is subordinate, always.
            Text('you · $actorLocalTime', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 5),
            Text(childStateSentence, style: const TextStyle(fontSize: 12.5)),
          ])),
        _Ribbon(label: "$childName's day", bands: childBands, height: 20),
        const SizedBox(height: 8),
        _Ribbon(label: 'you', bands: actorBands, height: 13),
        if (overlapLabel != null) Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(overlapLabel!, style: const TextStyle(fontSize: 11))),
      ])),
  );
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.label, required this.bands, required this.height});
  final String label;
  final List<RibbonBand> bands;
  final double height;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, letterSpacing: 0.7)),
      const SizedBox(height: 4),
      // Explicit-width Positioned segments, NOT Row+Expanded/flex: on this engine
      // build (Flutter 3.44.8 stable, Impeller/Vulkan), Expanded children inside a
      // Row silently paint nothing -- no exception, no layout error, confirmed by
      // bisection (fixed-width Container siblings in the same Row render fine;
      // swapping only the width source to Expanded/flex reproduces the blank
      // ribbon). Root cause is upstream of this widget, so the fix routes around
      // Expanded entirely rather than trying to unblock it.
      //
      // As a side benefit this uses `startFraction` (previously computed but
      // discarded -- Expanded flex only ever consumed widthFraction), so gaps
      // between non-contiguous bands now render as gaps instead of being folded
      // into the neighbouring band's width.
      ClipRRect(borderRadius: BorderRadius.circular(2),
        child: SizedBox(height: height, width: double.infinity,
          child: LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(children: [for (final b in bands) Positioned(
              left: w * b.startFraction, width: w * b.widthFraction,
              top: 0, bottom: 0,
              child: Tooltip(message: b.label, child: ColoredBox(color: b.color)),
            )]);
          }))),
    ]));
}
