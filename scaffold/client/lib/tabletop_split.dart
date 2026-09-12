// OLIVE BRANCH — shared tabletop-posture layout. Intuitivism pass,
// sub-project 3c (docs/superpowers/specs/2026-09-12-intuitivism-fold5-
// layout-design.md, Part 2). UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session).
//
// At Posture.foldTabletop (form_factors.dart) — short, wide, landscape, the
// Fold5 standing half-open on its own hinge — a screen's single-column
// layout stops making sense: the hinge physically divides the reported
// window into two flat halves. This widget is the one, shared way every
// tabletop-posture screen in this codebase now expresses that split:
// `viewing` (content) above the hinge, `controls` (actions) below it.
//
// A widget, not a static function, so it owns its own LayoutBuilder — the
// same self-contained posture-detection shape every other posture-aware
// widget in this codebase already uses (game_connect4.dart's own `outerPad`
// conditional is the precedent this file's own detection line matches
// exactly). Reads form_factors.dart's real `postureFor()` fresh here rather
// than threading a Posture down as a constructor parameter, so a caller
// never has to duplicate the measurement itself.
//
// HONEST LIMITATION, disclosed rather than silently assumed away: Flutter
// has no way to know exactly where the physical hinge sits within the
// reported window without the real `FoldingFeature` API (Android's Jetpack
// WindowManager) — deliberately not added this pass (sub-project 4's own
// scope; see the design spec's "explicitly out of scope"). The 50/50 split
// below is an even division of the reported window, not a measurement of
// the real hinge line — this file's own tests describe "no dead-zone under
// the hinge" as "both halves are reachable," never as "the split is
// pixel-perfect to wherever the hinge actually is."
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;

/// Renders [viewing] and [controls] as a plain 50/50 [Column] split — each
/// half independently scrollable, so real content taller than half of
/// foldTabletop's own short ~420dp floor never overflows (the same real,
/// live-hardware finding game_connect4.dart's own header already documents
/// for this exact posture) — when the ambient [postureFor] reads
/// [Posture.foldTabletop]; renders [viewing] directly above [controls] in a
/// single, unsplit column otherwise. Outside foldTabletop this widget is a
/// no-op shape change, never a second layout for a caller to maintain.
class TabletopSplit extends StatelessWidget {
  const TabletopSplit({super.key, required this.viewing, required this.controls});

  /// Above the hinge at foldTabletop — the content/viewing half.
  final Widget viewing;

  /// Below the hinge at foldTabletop — the controls/action half.
  final Widget controls;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final posture =
        ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
    if (posture != ff.Posture.foldTabletop) {
      // No-op shape outside foldTabletop -- viewing above controls, in one
      // plain column, exactly the single-column arrangement this widget
      // stands in for at every other posture.
      return Column(children: [viewing, controls]);
    }
    // A real, physical split at foldTabletop -- content above the hinge,
    // controls below it. See this file's own header for why each half
    // scrolls independently rather than risking overflow in a fixed Column.
    return Column(children: [
      Expanded(child: SingleChildScrollView(child: viewing)),
      Expanded(child: SingleChildScrollView(child: controls)),
    ]);
  });
}
