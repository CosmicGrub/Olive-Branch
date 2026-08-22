// OLIVE BRANCH — draw together. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.2, §9.12.4,
// §8.11.1, §8.13, P2. Renders MARKUP screen 'gamePicker' catalogue entry
// 'drawTogether'.
//
// A thin wrapper around annotation_canvas.dart's AnnotationCanvas — the
// SAME shared engine doodle_desk.dart already uses (see that file's own
// header and §9.12.4's "Live pairing added v0.42.0" note: "the shared
// annotation canvas, reused, not rebuilt"). This is the second real
// consumer of that engine, and the first with TWO real actors drawing on
// the SAME canvas at once rather than one child drawing alone — 'child' and
// 'parent' actorIds, mirroring game_logic.dart's "A = child, B = parent"
// convention (Side.a/Side.b) without importing game_logic.dart itself: this
// screen is co-op with no handicap/turn-order machinery, so nothing in that
// file applies here.
//
// Co-op, no winner, minAge 4 (game_logic.dart's catalogue). Both people can
// draw whenever they like — this is a shared canvas, not a turn-based board,
// so there is no turn gate. What DOES need scoping is undo: each person may
// only undo their OWN strokes, never the other's — exactly the property
// AnnotationCanvas.undo() already guarantees (see its own header for why a
// naive "pop the last stroke" implementation is wrong). The small "who's
// drawing" switch below exists only to attribute the next stroke to the
// right actorId on a SHARED device with one touchscreen — it is not a turn
// lock, and either person may flip it at any time.
//
// P2, applied the same way doodle_desk.dart's own header states it: "there
// is simply nothing in this file that counts anything." No stroke count, no
// timer, no "finished" state — a shared blank canvas has no finish line
// either, so there is nothing to add beyond what doodle_desk.dart already
// declined to build.
//
// Reuses doodle_desk.dart's `kBrushColors`/`kBrushWidths` (both public)
// rather than re-authoring a second color palette — "reused, not rebuilt"
// applies to content, not just engines. Stamps are NOT reused: the spec for
// this screen asks for color choice (plus a trivial width choice), not the
// six-stamp tray doodle_desk.dart carries. `_InkPainter`/`_Swatch`/
// `_BrushDot` there are private to that file (Dart library privacy is
// per-file), so the small painter and swatch widgets below are this file's
// own, following the identical structure rather than making doodle_desk.dart
// export internals for one other caller.
//
// Device-adaptive layout (§8.11.1, real posture logic, not a hand-rolled
// width check): below two columns (`form_factors.dart`'s `columnsAt()`), the
// tool panel is a slim bar under the canvas; at two columns or more (Fold5
// unfolded, tablets) it becomes a persistent side panel next to the canvas,
// with the gutter placed on the crease per `foldMain`'s own documented
// convention — court_export.dart's wide/narrow Row-vs-Column split is the
// precedent this follows.
import 'package:flutter/material.dart';
import 'annotation_canvas.dart';
import 'annotation_canvas_view.dart';
import 'doodle_desk.dart' show kBrushColors, kBrushWidths;
import 'form_factors.dart' as ff;

// ================================================================ state ===
class DrawTogetherScreen extends StatefulWidget {
  const DrawTogetherScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad'});
  final String childName;
  final String parentName;

  @override
  State<DrawTogetherScreen> createState() => _DrawTogetherScreenState();
}

class _DrawTogetherScreenState extends State<DrawTogetherScreen> {
  final AnnotationCanvas _canvas = AnnotationCanvas();
  int _idCounter = 0;

  /// 'child' or 'parent' — whose stroke the touch surface currently attributes
  /// to. Not a turn lock: either person may flip this any time, including
  /// mid-drawing-session, since this is collaborative, not turn-based.
  String _activeActorId = 'child';
  Color _brushColor = kBrushColors.first;
  double _brushWidth = kBrushWidths[1];

  List<StrokePoint> _liveStroke = <StrokePoint>[];

  ActorKind get _activeActorKind =>
      _activeActorId == 'child' ? ActorKind.child : ActorKind.guardian;
  String get _activeActorName =>
      _activeActorId == 'child' ? widget.childName : widget.parentName;

  String _nextId() => '$_activeActorId-${_idCounter++}';

  void _onPanStart(DragStartDetails d) =>
      setState(() => _liveStroke = <StrokePoint>[StrokePoint(d.localPosition.dx, d.localPosition.dy)]);

  // In-place `.add()`, not a rebuilt list: `_liveStroke` is a growable,
  // non-const list, and `_onPanStart` already reassigns it to a brand-new
  // list at the start of every stroke, so this only ever mutates a fresh
  // buffer not yet handed to `AnnotationCanvas.add()`. Avoids an O(n²)
  // point-list copy across a long drag (see `_onPanEnd`, which still
  // reassigns `_liveStroke` to a NEW empty list rather than `.clear()`ing
  // this one -- required, since `_onPanEnd` passes this exact list by
  // reference into `_canvas.add()` with no defensive copy there).
  void _onPanUpdate(DragUpdateDetails d) => setState(() {
        _liveStroke.add(StrokePoint(d.localPosition.dx, d.localPosition.dy));
      });

  void _onPanEnd(DragEndDetails d) {
    if (_liveStroke.isEmpty) return;
    _canvas.add(
      id: _nextId(),
      actorId: _activeActorId,
      actorKind: _activeActorKind,
      points: _liveStroke,
      color: _colorToHex(_brushColor),
      widthPx: _brushWidth,
    );
    setState(() => _liveStroke = <StrokePoint>[]);
  }

  // A no-op past the bottom of THIS actor's history is silence, not an error
  // or a "nothing to undo" message — same posture as doodle_desk.dart's own
  // _undo(). Scoped to _activeActorId, so switching who's drawing before
  // undoing correctly changes whose stroke comes back.
  void _undo() {
    if (_canvas.undo(_activeActorId, DateTime.now().millisecondsSinceEpoch) != null) {
      setState(() {});
    }
  }

  void _redo() {
    if (_canvas.redo(_activeActorId) != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draw together')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          // Real §8.11.1 posture logic, not a raw width check — matches
          // court_export.dart's own already-established use of columnsAt().
          final bool wide = ff.columnsAt(
                ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >=
              2;

          final Widget canvas = AnnotationCanvasView(
            canvasKey: const Key('drawTogetherCanvas'),
            committedPainter: _CommittedInkPainter(strokes: _canvas.visible()),
            livePainter: _LiveInkPainter(
              live: _liveStroke,
              liveColor: _brushColor,
              liveWidth: _brushWidth,
            ),
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
          );

          final Widget panel = _ToolPanel(
            activeActorId: _activeActorId,
            activeActorName: _activeActorName,
            childName: widget.childName,
            parentName: widget.parentName,
            onActorChanged: (id) => setState(() => _activeActorId = id),
            color: _brushColor,
            width: _brushWidth,
            onColor: (c) => setState(() => _brushColor = c),
            onWidth: (w) => setState(() => _brushWidth = w),
            onUndo: _undo,
            onRedo: _redo,
          );

          if (wide) {
            // A genuinely different widget tree, not a resized copy of the
            // narrow one: Row, canvas Expanded, a fixed-width side panel with
            // the gutter on the crease (foldMain's own documented
            // convention — "two-column gutters are placed there
            // deliberately") rather than a bottom bar squeezed to full width.
            return Padding(
              padding: const EdgeInsets.all(16),
              // Keyed so a widget test can assert the runtime TYPE of this
              // node directly (Row here, Column below) rather than counting
              // Row/Column widgets anywhere in the tree — Material buttons
              // and SegmentedButton already use Row internally, which makes
              // "no Row exists" the wrong assertion to make.
              child: Row(key: const Key('layoutRoot'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: canvas),
                const SizedBox(width: 16), // the crease gutter
                SizedBox(
                  key: const Key('toolSidePanel'),
                  width: 260,
                  child: SingleChildScrollView(child: panel),
                ),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(key: const Key('layoutRoot'), children: [
              Expanded(child: canvas),
              const SizedBox(height: 8),
              Container(key: const Key('toolBottomBar'), child: panel),
            ]),
          );
        }),
      ),
    );
  }
}

// ================================================================ widget ===

/// A minimal, typed test seam: lets a widget test read what was actually
/// painted (multi-actor stroke attribution, per-actor undo) without a
/// `dynamic` cast — this repo's analysis_options.yaml opts into
/// `avoid_dynamic_calls`, so that's not just style. `_SharedInkPainter`
/// itself stays private; only this narrow, public getter contract is
/// exposed.
abstract class InkPainterStrokes {
  List<Stroke> get strokes;
}

/// Shared by both painters below — follows _InkPainter's own shape in
/// doodle_desk.dart exactly (that class is private to its own file, so this
/// is a small, independent copy rather than an export change to an
/// unrelated screen) — driven motion only, no smoothing lag, §8.13's
/// "motion follows the finger, it never leads it."
void _paintPolyline(Canvas canvas, List<StrokePoint> pts, Color color, double width) {
  if (pts.isEmpty) return;
  final Paint paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (pts.length == 1) {
    canvas.drawCircle(Offset(pts.first.x, pts.first.y), width / 2, paint..style = PaintingStyle.fill);
    return;
  }
  final Path path = Path()..moveTo(pts.first.x, pts.first.y);
  for (final StrokePoint p in pts.skip(1)) {
    path.lineTo(p.x, p.y);
  }
  canvas.drawPath(path, paint);
}

/// Paints only the committed strokes — see annotation_canvas_view.dart's own
/// header for why this is split from the live layer and wrapped in a
/// [RepaintBoundary]: `strokes` comes from `AnnotationCanvas.visible()`,
/// which returns a cached, `identical()` list between drag frames unless a
/// real mutation happened, so `shouldRepaint` below can actually say no
/// during a live pointer-move instead of repainting the whole stroke
/// history every frame.
class _CommittedInkPainter extends CustomPainter implements InkPainterStrokes {
  const _CommittedInkPainter({required this.strokes});
  @override
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final Stroke s in strokes) {
      _paintPolyline(canvas, s.points, _hexToColor(s.color), s.widthPx);
    }
  }

  @override
  bool shouldRepaint(covariant _CommittedInkPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes);
}

/// Paints only the in-progress live stroke — small, and expected to repaint
/// every pointer-move frame; isolated by the committed layer's
/// [RepaintBoundary] so that repainting never drags the full stroke history
/// along with it.
class _LiveInkPainter extends CustomPainter {
  const _LiveInkPainter({required this.live, required this.liveColor, required this.liveWidth});
  final List<StrokePoint> live;
  final Color liveColor;
  final double liveWidth;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPolyline(canvas, live, liveColor, liveWidth);
  }

  // DEVIATION from the originally-proposed `oldDelegate.live.length !=
  // live.length || !identical(oldDelegate.live, live)` check: Fix 11 (see
  // `_onPanUpdate`) mutates `_liveStroke` IN PLACE via `.add()` rather than
  // reassigning it every point, so by the time this runs, `oldDelegate.live`
  // and `live` are the SAME List<StrokePoint> object (Dart lists are
  // reference types) -- both `identical()` and a length comparison read the
  // object's current, already-mutated state either way, so that check can
  // never observe a change mid-stroke and would silently freeze the live
  // ink trail after its first point. Verified directly (not assumed): a
  // throwaway `dart` probe mutating a list in place after aliasing it
  // confirmed `identical(ref1, ref2)` and `ref1.length == ref2.length` both
  // read true post-mutation. Unconditional repaint is the correct fix here,
  // not a missed optimization -- this layer is intentionally small (one
  // in-progress stroke) and isolated by the committed layer's own
  // RepaintBoundary in annotation_canvas_view.dart, so repainting it every
  // frame was always the point of splitting it out, not a cost to avoid.
  @override
  bool shouldRepaint(covariant _LiveInkPainter oldDelegate) => true;
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.activeActorId,
    required this.activeActorName,
    required this.childName,
    required this.parentName,
    required this.onActorChanged,
    required this.color,
    required this.width,
    required this.onColor,
    required this.onWidth,
    required this.onUndo,
    required this.onRedo,
  });

  final String activeActorId;
  final String activeActorName;
  final String childName;
  final String parentName;
  final ValueChanged<String> onActorChanged;
  final Color color;
  final double width;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<String>(
          style: SegmentedButton.styleFrom(minimumSize: const Size(64, 48)),
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'child', label: Text(childName)),
            ButtonSegment<String>(value: 'parent', label: Text(parentName)),
          ],
          selected: <String>{activeActorId},
          onSelectionChanged: (s) => onActorChanged(s.first),
        ),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final Color c in kBrushColors) _Swatch(color: c, selected: c.toARGB32() == color.toARGB32(), onTap: () => onColor(c)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final double w in kBrushWidths) _BrushDot(diameter: w, selected: w == width, onTap: () => onWidth(w)),
        ]),
        const SizedBox(height: 8),
        // Expanded, not natural sizing: the same two-button row must fit a
        // full-width bottom bar AND a ~240px side panel without overflowing
        // either — sharing the available width, rather than a fixed
        // intrinsic size, is what makes that true regardless of container
        // width. Short "Undo"/"Redo" labels (matching doodle_desk.dart's own
        // proven-safe convention) carry the WHO in a tooltip instead of the
        // visible text — the segmented switch just above already shows which
        // actor is active.
        Row(children: [
          Expanded(
              child: _RoundIconButton(
                  icon: Icons.undo, label: 'Undo',
                  tooltip: "Undoes $activeActorName's own last stroke only", onTap: onUndo)),
          const SizedBox(width: 12),
          Expanded(
              child: _RoundIconButton(
                  icon: Icons.redo, label: 'Redo',
                  tooltip: "Redoes $activeActorName's own last undo", onTap: onRedo)),
        ]),
      ]);
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          // 48dp minimum touch target (§8.4) even though the visible dot is
          // smaller — same discipline as doodle_desk.dart's own _Swatch.
          width: 48, height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 3 : 1),
            ),
          ),
        ),
      );
}

class _BrushDot extends StatelessWidget {
  const _BrushDot({required this.diameter, required this.selected, required this.onTap});
  final double diameter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48, height: 48,
          alignment: Alignment.center,
          child: Container(
            width: diameter + 8, height: diameter + 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.label, required this.tooltip, required this.onTap});
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
        ),
      );
}

String _colorToHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Color _hexToColor(String hex) {
  final String h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
