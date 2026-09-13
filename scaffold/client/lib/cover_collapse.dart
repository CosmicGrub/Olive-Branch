// OLIVE BRANCH — shared cover-screen layout. Intuitivism pass, sub-project
// 3c (docs/superpowers/specs/2026-09-12-intuitivism-fold5-layout-design.md,
// Part 1). UNVERIFIED (no Flutter toolchain in tools/verify.sh's automated
// pipeline — manually built and run via `flutter analyze` / `flutter test`
// this session).
//
// At Posture.foldCover (form_factors.dart) — the Fold5 closed to its
// narrowest, 344 CSS px cover screen — a screen's full layout squeezed
// narrow is the wrong move; it should show its single most load-bearing
// piece of information or action instead (the design spec's own Part 1
// principle). This widget is the shared, generic mechanism: swap a
// screen's ordinary [full] layout for a stripped-down [collapsed] one, at
// exactly this one posture, and nowhere else.
//
// A widget, not a static function, so it owns its own LayoutBuilder — the
// identical shape tabletop_split.dart's own TabletopSplit already
// establishes for the same reason (see that file's own header). Reads
// form_factors.dart's real `postureFor()` fresh here rather than threading
// a Posture down as a constructor parameter.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;

/// Renders [collapsed] when the ambient [postureFor] reads
/// [Posture.foldCover]; renders [full] — the caller's own, otherwise
/// completely unchanged, existing layout — at every other posture. Both
/// [full] and [collapsed] are ordinary, already-fully-built widget
/// descriptions supplied by the caller; this widget decides only which one
/// is shown, never what either one contains.
class CoverCollapse extends StatelessWidget {
  const CoverCollapse({super.key, required this.full, required this.collapsed});

  /// The screen's ordinary layout — shown at every posture except foldCover.
  final Widget full;

  /// The stripped-down, single-most-load-bearing-thing layout — shown only
  /// at foldCover.
  final Widget collapsed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final posture =
        ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
    return posture == ff.Posture.foldCover ? collapsed : full;
  });
}
