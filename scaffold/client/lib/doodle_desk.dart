// OLIVE BRANCH — doodle desk. Verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — CHANGELOG v0.49.61).
// MASTERFILE §9.12.4, §8.13, §8.1. Renders MARKUP screen 'doodle'.
//
// "Free strokes plus six stamps, alongside colouring rather than replacing
// it — a blank canvas has no finish line, so there is no score or
// completion state to show." That sentence is a hard constraint, not just a
// design note: this file has no timer, no stroke counter, no "you're done!"
// state, and no code path that could grow one later without being obvious
// in review — there is simply nothing in [_DoodleDeskState] that counts
// anything.
//
// Drawing/undo runs entirely on annotation_canvas.dart's AnnotationCanvas —
// the same engine MARKUP's 0.42.0 amendment describes as "the shared
// annotation canvas, reused, not rebuilt" for live pairing. Undo is
// unlimited and scoped to this actor's own strokes (see that file's header
// for why a naive last-on-canvas undo is the wrong implementation);
// stamps ride the exact same tombstoned-undo history as freehand ink via
// [Stroke.stampGlyph], so "undo" never needs two different meanings.
//
// §8.13's one rule — "motion follows the finger, it never leads it" — shows
// up twice here: a stroke is 'driven' motion (paints exactly where the
// finger already went, no easing), and a placed stamp is 'consequence'
// motion, capped at motion_rules.dart's maxConsequenceMs so placing a stamp
// never makes her wait for a picture to finish. Nothing on this screen loops
// or moves on its own.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'annotation_canvas.dart';
import 'form_factors.dart' as ff;
import 'motion_rules.dart';

enum _Tool { draw, stamp }

class StampSpec {
  const StampSpec(this.id, this.label, this.color, {this.icon});
  final String id;
  final String label;
  final Color color;

  /// Null only for 'rainbow', which is painted rather than iconed — no
  /// single Material icon reads as a rainbow at a glance.
  final IconData? icon;
}

/// The six stamps this screen ships, exactly as specified — not a
/// configurable set, so "six stamps" stays true by construction.
const List<StampSpec> kStamps = <StampSpec>[
  StampSpec('heart', 'Heart', Color(0xFFE9598B), icon: Icons.favorite),
  StampSpec('star', 'Star', Color(0xFFF6B93B), icon: Icons.star),
  StampSpec('smiley', 'Smiley', Color(0xFFFFC93C), icon: Icons.emoji_emotions),
  StampSpec('rainbow', 'Rainbow', Color(0xFF6C5CE7)),
  StampSpec('sun', 'Sun', Color(0xFFFF9F43), icon: Icons.wb_sunny),
  StampSpec('moon', 'Moon', Color(0xFF576CBC), icon: Icons.nightlight_round),
];

const List<Color> kBrushColors = <Color>[
  Color(0xFF2D2A32), // near-black, for real drawing
  Color(0xFFE9598B),
  Color(0xFFFF9F43),
  Color(0xFFFFC93C),
  Color(0xFF4CAF50),
  Color(0xFF3F8CFF),
  Color(0xFF6C5CE7),
  Color(0xFFFFFFFF),
];

const List<double> kBrushWidths = <double>[4, 8, 14];

class DoodleDesk extends StatefulWidget {
  const DoodleDesk({super.key, this.childName = 'you', this.actorId = 'me'});

  final String childName;

  /// Local actor id. Multi-actor (live pairing) undo scoping already works
  /// in annotation_canvas.dart — there is just one actor in this preview
  /// build because there's no realtime transport yet to carry a second.
  final String actorId;

  @override
  State<DoodleDesk> createState() => _DoodleDeskState();
}

class _DoodleDeskState extends State<DoodleDesk> {
  final AnnotationCanvas _canvas = AnnotationCanvas();
  int _idCounter = 0;

  _Tool _tool = _Tool.draw;
  Color _brushColor = kBrushColors.first;
  double _brushWidth = kBrushWidths[1];
  String _stampId = kStamps.first.id;

  List<StrokePoint> _liveStroke = <StrokePoint>[];

  String _nextId() => '${widget.actorId}-${_idCounter++}';

  void _onPanStart(DragStartDetails d) {
    setState(() => _liveStroke = <StrokePoint>[StrokePoint(d.localPosition.dx, d.localPosition.dy)]);
  }

  // In-place `.add()`, not a rebuilt list — see game_draw_together.dart's
  // identical note (`_onPanStart` already reassigns `_liveStroke` to a
  // fresh list at the start of every stroke, and `_onPanEnd` below still
  // reassigns it to a NEW empty list rather than `.clear()`ing this one).
  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _liveStroke.add(StrokePoint(d.localPosition.dx, d.localPosition.dy));
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_liveStroke.isEmpty) return;
    _canvas.add(
      id: _nextId(),
      actorId: widget.actorId,
      actorKind: ActorKind.child,
      points: _liveStroke,
      color: _colorToHex(_brushColor),
      widthPx: _brushWidth,
    );
    setState(() => _liveStroke = <StrokePoint>[]);
  }

  void _onStampTap(TapUpDetails d) {
    final StampSpec spec = kStamps.firstWhere((s) => s.id == _stampId);
    _canvas.add(
      id: _nextId(),
      actorId: widget.actorId,
      actorKind: ActorKind.child,
      points: <StrokePoint>[StrokePoint(d.localPosition.dx, d.localPosition.dy)],
      color: _colorToHex(spec.color),
      widthPx: 56,
      stampGlyph: spec.id,
    );
    setState(() {});
  }

  void _undo() {
    // A no-op past the bottom of this actor's history is exactly that — no
    // error, no "nothing to undo" text. Silence is the right answer here.
    if (_canvas.undo(widget.actorId, DateTime.now().millisecondsSinceEpoch) != null) {
      setState(() {});
    }
  }

  void _redo() {
    if (_canvas.redo(widget.actorId) != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Doodle desk')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Fold5 cover (~344 CSS px) vs. its unfolded ~673x841 main screen:
          // no fixed widths anywhere below, everything derives from
          // constraints or wraps.
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool narrow = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) < 2;
          return Padding(
            padding: EdgeInsets.all(narrow ? 8 : 16),
            child: Column(children: [
              _ToolSwitch(tool: _tool, onChanged: (t) => setState(() => _tool = t)),
              SizedBox(height: narrow ? 8 : 12),
              Expanded(
                child: _Board(
                  visible: _canvas.visible(),
                  liveStroke: _liveStroke,
                  liveColor: _brushColor,
                  liveWidth: _brushWidth,
                  tool: _tool,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onStampTap: _onStampTap,
                ),
              ),
              SizedBox(height: narrow ? 8 : 12),
              AnimatedSize(
                duration: const Duration(milliseconds: crossfadeMs),
                curve: Curves.easeOut,
                child: _tool == _Tool.draw
                    ? _DrawControls(
                        color: _brushColor, width: _brushWidth,
                        onColor: (c) => setState(() => _brushColor = c),
                        onWidth: (w) => setState(() => _brushWidth = w))
                    : _StampTray(
                        selected: _stampId,
                        onSelect: (id) => setState(() => _stampId = id)),
              ),
              SizedBox(height: narrow ? 4 : 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _RoundIconButton(icon: Icons.undo, label: 'Undo', onTap: _undo),
                const SizedBox(width: 16),
                _RoundIconButton(icon: Icons.redo, label: 'Redo', onTap: _redo),
              ]),
            ]),
          );
        }),
      ),
      backgroundColor: scheme.surfaceContainerLow,
    );
  }
}

class _ToolSwitch extends StatelessWidget {
  const _ToolSwitch({required this.tool, required this.onChanged});
  final _Tool tool;
  final ValueChanged<_Tool> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<_Tool>(
        // §8.4/child-facing 48dp minimum — M3's own default segmented-button
        // height (40dp) is a hair under that, so it's raised explicitly
        // rather than trusted to the theme default.
        style: SegmentedButton.styleFrom(minimumSize: const Size(64, 48)),
        segments: const <ButtonSegment<_Tool>>[
          ButtonSegment<_Tool>(value: _Tool.draw, label: Text('Draw'), icon: Icon(Icons.brush)),
          ButtonSegment<_Tool>(value: _Tool.stamp, label: Text('Stamps'), icon: Icon(Icons.emoji_emotions_outlined)),
        ],
        selected: <_Tool>{tool},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class _Board extends StatelessWidget {
  const _Board({
    required this.visible,
    required this.liveStroke,
    required this.liveColor,
    required this.liveWidth,
    required this.tool,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onStampTap,
  });

  final List<Stroke> visible;
  final List<StrokePoint> liveStroke;
  final Color liveColor;
  final double liveWidth;
  final _Tool tool;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final GestureTapUpCallback onStampTap;

  @override
  Widget build(BuildContext context) {
    final List<Stroke> ink = visible.where((s) => s.stampGlyph == null).toList();
    final List<Stroke> stamps = visible.where((s) => s.stampGlyph != null).toList();
    return Container(
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
        key: const Key('doodleBoard'),
        behavior: HitTestBehavior.opaque,
        onPanStart: tool == _Tool.draw ? onPanStart : null,
        onPanUpdate: tool == _Tool.draw ? onPanUpdate : null,
        onPanEnd: tool == _Tool.draw ? onPanEnd : null,
        onTapUp: tool == _Tool.stamp ? onStampTap : null,
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _InkPainter(strokes: ink, live: liveStroke, liveColor: liveColor, liveWidth: liveWidth)),
          for (final Stroke s in stamps) _PlacedStamp(stroke: s),
        ]),
      ),
    );
  }
}

/// A stamp animates in once (a 'consequence' of the tap that placed it) and
/// then sits still — no loop, no idle wiggle. Keying by stroke id means
/// Flutter mounts this exactly once per stamp; later rebuilds of the parent
/// (e.g. drawing a stroke elsewhere) reuse the same element and do not
/// replay the entrance.
class _PlacedStamp extends StatelessWidget {
  const _PlacedStamp({required this.stroke});
  final Stroke stroke;

  @override
  Widget build(BuildContext context) {
    final StrokePoint p = stroke.points.first;
    final double size = stroke.widthPx;
    return Positioned(
      key: ValueKey<String>('stamp-${stroke.id}'),
      left: p.x - size / 2,
      top: p.y - size / 2,
      width: size, height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: maxConsequenceMs),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(scale: t, child: child),
        ),
        child: _stampVisual(stroke.stampGlyph!, size),
      ),
    );
  }
}

Widget _stampVisual(String id, double size) {
  final StampSpec spec = kStamps.firstWhere((s) => s.id == id, orElse: () => kStamps.first);
  if (spec.icon != null) return Icon(spec.icon, size: size, color: spec.color);
  return SizedBox(width: size, height: size, child: const CustomPaint(painter: _RainbowPainter()));
}

class _RainbowPainter extends CustomPainter {
  const _RainbowPainter();
  static const List<Color> _bands = <Color>[
    Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFFF1C40F),
    Color(0xFF2ECC71), Color(0xFF3498DB), Color(0xFF9B59B6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeW = size.width / (_bands.length * 2.4);
    final Rect base = Rect.fromLTWH(strokeW / 2, size.height * 0.25, size.width - strokeW, size.height * 1.6);
    for (int i = 0; i < _bands.length; i++) {
      final Paint paint = Paint()
        ..color = _bands[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(base.deflate(strokeW * i * 0.95), math.pi, math.pi, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RainbowPainter oldDelegate) => false;
}

class _InkPainter extends CustomPainter {
  const _InkPainter({required this.strokes, required this.live, required this.liveColor, required this.liveWidth});
  final List<Stroke> strokes;
  final List<StrokePoint> live;
  final Color liveColor;
  final double liveWidth;

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

  @override
  void paint(Canvas canvas, Size size) {
    for (final Stroke s in strokes) {
      _paintPolyline(canvas, s.points, _hexToColor(s.color), s.widthPx);
    }
    // The stroke in progress — driven motion, painted every frame exactly
    // where the finger already is, no smoothing lag.
    _paintPolyline(canvas, live, liveColor, liveWidth);
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) => true;
}

class _DrawControls extends StatelessWidget {
  const _DrawControls({required this.color, required this.width, required this.onColor, required this.onWidth});
  final Color color;
  final double width;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final Color c in kBrushColors)
            _Swatch(color: c, selected: c.toARGB32() == color.toARGB32(), onTap: () => onColor(c)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final double w in kBrushWidths) _BrushDot(diameter: w, selected: w == width, onTap: () => onWidth(w)),
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
          // 48dp minimum touch target (§8.4) — the visible dot may look
          // dainty; the tappable area does not.
          width: 48, height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
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

class _StampTray extends StatelessWidget {
  const _StampTray({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
        children: [for (final StampSpec s in kStamps) _StampChip(spec: s, selected: s.id == selected, onTap: () => onSelect(s.id))],
      );
}

class _StampChip extends StatelessWidget {
  const _StampChip({required this.spec, required this.selected, required this.onTap});
  final StampSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: spec.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: selected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
            ),
            alignment: Alignment.center,
            child: _stampVisual(spec.id, 30),
          ),
        ),
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
      );
}

String _colorToHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Color _hexToColor(String hex) {
  final String h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
