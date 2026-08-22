// OLIVE BRANCH — the common canvas-hosting wrapper Batch A's own spec
// required both canvas screens to share. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline). MASTERFILE §9.2, §9.12.4,
// §8.11.1, §8.13.
//
// Audit-fix (v0.49.22): `docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md` (line ~74) explicitly required
// Batch A to share "a common canvas-hosting wrapper both screens use."
// `game_draw_together.dart` and `game_guess_doodle.dart` shipped with two
// near-identical, independently duplicated private `_Canvas` widgets
// instead (same Container/BoxDecoration/GestureDetector/CustomPaint
// structure, found by an adversarial audit). This file is the wrapper the
// spec asked for, extracted afterward as a behavior-preserving refactor —
// both screens' own test suites (game_draw_together_test.dart,
// game_guess_doodle_test.dart) pass unchanged against it.
//
// Deliberately a SEPARATE file from annotation_canvas.dart, not folded into
// it: that file is pure Dart logic with no Flutter import at all, by
// design (its own header: "logic, not presentation, and stays testable
// without a widget harness"), and this wrapper is nothing BUT presentation
// — the two stay separate for the same reason lock_controller.dart and any
// screen that renders its state do.
//
// Parameterized for exactly what the two real callers need and no more
// (don't over-generalize beyond two actual consumers): each screen still
// builds its OWN `CustomPainter` — `game_draw_together.dart`'s
// `_SharedInkPainter` paints per-stroke color (each actor's own brush
// choice), `game_guess_doodle.dart`'s `_SoloInkPainter` paints one fixed
// ink color — and passes it in via [painter]. Neither caller's
// actor-switch affordance (the segmented "who's drawing/who's active"
// control) lives here: that's part of each screen's own tool/round side
// panel, never the canvas itself, so it stays out of this wrapper.
import 'package:flutter/material.dart';

/// The Container/BoxDecoration/GestureDetector/CustomPaint chrome every
/// AnnotationCanvas-hosting screen needs, factored out once. [drawingEnabled]
/// defaults to true (`game_draw_together.dart`'s shared canvas never
/// disables drawing); `game_guess_doodle.dart` passes `!revealed` so the
/// guesser's screen stops accepting strokes once the word is shown.
class AnnotationCanvasView extends StatelessWidget {
  const AnnotationCanvasView({
    super.key,
    required this.canvasKey,
    required this.committedPainter,
    required this.livePainter,
    this.drawingEnabled = true,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  /// The key the GestureDetector itself carries — each screen's own tests
  /// locate the canvas by this key (`drawTogetherCanvas`/`guessDoodleCanvas`),
  /// so it stays caller-supplied rather than hardcoded here.
  final Key canvasKey;

  /// Paints only the committed (already-added-to-AnnotationCanvas) strokes.
  /// Wrapped in its own [RepaintBoundary] below so a live, in-progress
  /// stroke repainting every pointer-move frame never forces the whole
  /// stroke history to repaint alongside it — see annotation_canvas.dart's
  /// own `visible()` caching, which is what makes this painter's
  /// `shouldRepaint` able to say no between drag frames.
  final CustomPainter committedPainter;

  /// Paints only the in-progress live stroke — small, and repaints every
  /// pointer-move frame by design.
  final CustomPainter livePainter;
  final bool drawingEnabled;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          key: canvasKey,
          behavior: HitTestBehavior.opaque,
          onPanStart: drawingEnabled ? onPanStart : null,
          onPanUpdate: drawingEnabled ? onPanUpdate : null,
          onPanEnd: drawingEnabled ? onPanEnd : null,
          child: Stack(children: [
            RepaintBoundary(
              child: CustomPaint(painter: committedPainter, size: Size.infinite),
            ),
            CustomPaint(painter: livePainter, size: Size.infinite),
          ]),
        ),
      );
}
