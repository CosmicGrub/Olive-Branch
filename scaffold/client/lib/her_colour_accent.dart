// OLIVE BRANCH — her colour as a placement-budgeted accent. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline). MASTERFILE §8.6.2.
//
// §8.6.2 made code. Her colour may appear in at most three of the eight allowed
// places on one screen (palette_logic.dart's applyColour() is the guard and is
// the only thing that decides), and never as a surface fill, a background, body
// text, an error, a warning or a ribbon band. A screen asks for the placements
// it would like; [HerColourAccent] hands back only those that survived the
// budget, so a fourth request is dropped rather than drawn.
//
// There is deliberately no "theme" here: nothing in this file can colour a
// scaffold, a card or a line of text with her colour, and the only widgets it
// offers (a thin stripe, a ring) are thin by construction.
import 'package:flutter/material.dart';
import 'palette_logic.dart';

class HerColourAccent {
  HerColourAccent._(this.swatch, this.placements);

  /// No colour chosen: the app looks exactly as it did before she picked one.
  static final HerColourAccent none = HerColourAccent._(null, const []);

  /// Her colour, asking for [requested] places (budget applied). An unknown
  /// colour id, or a request that includes a forbidden place, yields [none] —
  /// fail closed, never draw it somewhere it must not go.
  factory HerColourAccent.of(String? colourId, List<String> requested) {
    final s = swatchFor(colourId);
    if (s == null) return none;
    final out = applyColour(s.id, requested);
    if (!out.ok) return none;
    return HerColourAccent._(s, List.unmodifiable(out.placements));
  }

  final Swatch? swatch;
  /// What survived the budget, in the order asked.
  final List<String> placements;

  bool has(String placement) => swatch != null && placements.contains(placement);

  /// The pure hue, for a fill that carries no text.
  Color? get color => swatch?.color;
}

/// A thin rule under a header: the `accent_stripe` placement. Four logical
/// pixels tall — it cannot be mistaken for a surface — and nothing when her
/// colour is not allowed here.
class AccentStripe extends StatelessWidget {
  const AccentStripe({super.key, required this.accent});
  final HerColourAccent accent;

  @override
  Widget build(BuildContext context) {
    if (!accent.has('accent_stripe')) return const SizedBox.shrink();
    return Container(key: const Key('accentStripe'), height: 4, color: accent.color);
  }
}

/// A ring around something of hers (the swatch, her initial): the `avatar_ring`
/// placement. A border, never a fill.
class AccentRing extends StatelessWidget {
  const AccentRing({super.key, required this.accent, required this.child, this.width = 4});
  final HerColourAccent accent;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (!accent.has('avatar_ring')) return child;
    return Container(
      key: const Key('accentRing'),
      padding: EdgeInsets.all(width),
      decoration: BoxDecoration(shape: BoxShape.circle, color: accent.color),
      child: child);
  }
}
