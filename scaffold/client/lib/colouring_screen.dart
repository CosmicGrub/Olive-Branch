// OLIVE BRANCH — colouring page. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). MASTERFILE §8.13. Renders MARKUP screen 'colouring'.
//
// "Vector, cheap for what it is; her finger's motion is never shed." The
// scene below is entirely vector Paths built from the canvas size, not a
// raster image — it costs almost nothing to keep at full quality even under
// §8.14's capability budget, which is the property that MARKUP line is
// about.
//
// motion.ts's own per-surface note for this screen: "The fill is a
// consequence — it spreads from the tap rather than cutting." That is
// implemented literally: a tapped region animates from its old colour to
// the new one over motion_rules.dart's maxConsequenceMs, driven by a
// [Ticker] rather than a hard `setState` colour swap, so a fill is always
// seen arriving rather than appearing already finished.
//
// No score, timer, streak, or "you finished the page!" state — a picture
// with twelve regions colourable in any order, any number of times, has no
// natural finish line either, same posture as doodle_desk.dart takes for a
// blank canvas.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'form_factors.dart' as ff;
import 'motion_rules.dart';

const List<Color> _kPalette = <Color>[
  Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFFF1C40F),
  Color(0xFF2ECC71), Color(0xFF3498DB), Color(0xFF9B59B6),
  Color(0xFFE9598B), Color(0xFF6D4C41),
];

/// Bottom-to-top paint order; hit-testing walks this reversed so the
/// topmost shape under a finger wins.
const List<String> _kRegionOrder = <String>[
  'sky', 'ground', 'sunRays', 'sunCore',
  'stem', 'leafLeft', 'leafRight',
  'petal0', 'petal1', 'petal2', 'petal3', 'petal4', 'center',
];

class ColouringScreen extends StatefulWidget {
  const ColouringScreen({super.key});

  @override
  State<ColouringScreen> createState() => _ColouringScreenState();
}

class _RegionAnim {
  _RegionAnim(this.from, this.to, this.start);
  final Color from;
  final Color to;
  final DateTime start;
}

class _ColouringScreenState extends State<ColouringScreen> with SingleTickerProviderStateMixin {
  final Map<String, Color> _filled = <String, Color>{};
  final Map<String, _RegionAnim> _animating = <String, _RegionAnim>{};
  Color _selected = _kPalette.first;
  Size _lastSize = Size.zero;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Started only while something is mid-fade, stopped the instant nothing
    // is (see below) — an always-on ticker would keep the engine scheduling
    // frames forever, which is both wasteful on a still picture and exactly
    // what makes `pumpAndSettle` in a widget test hang: the whole point of
    // "settled" is "no more frames pending".
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_animating.isEmpty) {
      _ticker.stop();
      return;
    }
    final DateTime now = DateTime.now();
    final List<String> finished = <String>[];
    for (final MapEntry<String, _RegionAnim> e in _animating.entries) {
      final double t = now.difference(e.value.start).inMilliseconds / maxConsequenceMs;
      if (t >= 1) finished.add(e.key);
    }
    setState(() {
      for (final String id in finished) {
        _animating.remove(id);
      }
    });
    if (_animating.isEmpty) _ticker.stop();
  }

  void _handleTapUp(TapUpDetails d) {
    if (_lastSize == Size.zero) return;
    final Map<String, Path> regions = _buildRegions(_lastSize);
    for (final String id in _kRegionOrder.reversed) {
      if (regions[id]!.contains(d.localPosition)) {
        final Color from = _filled[id] ?? Colors.white;
        if (from.toARGB32() == _selected.toARGB32()) return;
        setState(() {
          _animating[id] = _RegionAnim(from, _selected, DateTime.now());
          _filled[id] = _selected;
        });
        if (!_ticker.isTicking) _ticker.start();
        return;
      }
    }
  }

  void _startOver() => setState(() {
        _filled.clear();
        _animating.clear();
        _ticker.stop();
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Colouring'), actions: [
          TextButton(onPressed: _startOver, child: const Text('Start over')),
        ]),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final double textScale = MediaQuery.textScalerOf(context).scale(1);
            final bool narrow = ff.columnsAt(
                ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) < 2;
            return Padding(
              padding: EdgeInsets.all(narrow ? 8 : 16),
              child: Column(children: [
                Expanded(
                  child: LayoutBuilder(builder: (context, inner) {
                    final Size boardSize = Size(inner.maxWidth, inner.maxHeight);
                    _lastSize = boardSize;
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4FAFF),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _handleTapUp,
                        child: CustomPaint(
                          size: boardSize,
                          painter: _ColouringPainter(filled: _filled, animating: _animating),
                        ),
                      ),
                    );
                  }),
                ),
                SizedBox(height: narrow ? 8 : 12),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  for (final Color c in _kPalette)
                    _PaletteSwatch(
                      color: c,
                      selected: c.toARGB32() == _selected.toARGB32(),
                      onTap: () => setState(() => _selected = c)),
                ]),
              ]),
            );
          }),
        ),
      );
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.color, required this.selected, required this.onTap});
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
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 3.5 : 1),
            ),
          ),
        ),
      );
}

class _ColouringPainter extends CustomPainter {
  const _ColouringPainter({required this.filled, required this.animating});
  final Map<String, Color> filled;
  final Map<String, _RegionAnim> animating;

  Color _colorFor(String id) {
    final _RegionAnim? anim = animating[id];
    if (anim != null) {
      final double t = (DateTime.now().difference(anim.start).inMilliseconds / maxConsequenceMs)
          .clamp(0.0, 1.0);
      return Color.lerp(anim.from, anim.to, t) ?? anim.to;
    }
    return filled[id] ?? Colors.white;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final Map<String, Path> regions = _buildRegions(size);
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    for (final String id in _kRegionOrder) {
      fillPaint.color = _colorFor(id);
      canvas.drawPath(regions[id]!, fillPaint);
    }
    final Paint linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF37414F);
    for (final String id in _kRegionOrder) {
      canvas.drawPath(regions[id]!, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColouringPainter oldDelegate) => true;
}

Map<String, Path> _buildRegions(Size s) {
  final double w = s.width;
  final double h = s.height;
  final Map<String, Path> regions = <String, Path>{};

  regions['sky'] = Path()..addRect(Rect.fromLTWH(0, 0, w, h * 0.78));
  regions['ground'] = Path()
    ..moveTo(0, h * 0.78)
    ..quadraticBezierTo(w * 0.5, h * 0.66, w, h * 0.78)
    ..lineTo(w, h)
    ..lineTo(0, h)
    ..close();

  final Offset sunCenter = Offset(w * 0.76, h * 0.20);
  final double sunR = w * 0.10;
  regions['sunCore'] = Path()..addOval(Rect.fromCircle(center: sunCenter, radius: sunR));

  final Path rays = Path();
  for (int i = 0; i < 8; i++) {
    final double angle = (i / 8) * 2 * math.pi;
    final Offset dir = Offset(math.cos(angle), math.sin(angle));
    final Offset inner = sunCenter + dir * (sunR * 1.25);
    final Offset outer = sunCenter + dir * (sunR * 1.95);
    final Offset perp = Offset(-dir.dy, dir.dx) * (sunR * 0.14);
    rays.addPolygon(<Offset>[inner - perp, inner + perp, outer], true);
  }
  regions['sunRays'] = rays;

  final Offset flowerBase = Offset(w * 0.32, h * 0.90);
  final double stemHalf = w * 0.012;
  regions['stem'] = Path()
    ..moveTo(flowerBase.dx - stemHalf, flowerBase.dy)
    ..lineTo(flowerBase.dx - stemHalf, h * 0.52)
    ..lineTo(flowerBase.dx + stemHalf, h * 0.52)
    ..lineTo(flowerBase.dx + stemHalf, flowerBase.dy)
    ..close();

  regions['leafLeft'] = _leafPath(Offset(flowerBase.dx, h * 0.74), w * 0.11, math.pi * 0.92);
  regions['leafRight'] = _leafPath(Offset(flowerBase.dx, h * 0.68), w * 0.11, -math.pi * 0.10);

  final Offset center = Offset(flowerBase.dx, h * 0.46);
  final double petalLen = w * 0.13;
  final double petalW = w * 0.09;
  for (int i = 0; i < 5; i++) {
    final double angle = -90 + i * 72.0;
    regions['petal$i'] = _petalPath(center, angle, petalLen, petalW);
  }
  regions['center'] = Path()..addOval(Rect.fromCircle(center: center, radius: w * 0.05));

  return regions;
}

Path _petalPath(Offset center, double angleDeg, double length, double width) {
  final double rad = angleDeg * math.pi / 180;
  final Offset dir = Offset(math.cos(rad), math.sin(rad));
  final Offset perp = Offset(-dir.dy, dir.dx) * (width / 2);
  final Offset tip = center + dir * length;
  final Offset base1 = center + perp * 0.4;
  final Offset base2 = center - perp * 0.4;
  final Offset ctrl1 = center + dir * (length * 0.55) + perp;
  final Offset ctrl2 = center + dir * (length * 0.55) - perp;
  return Path()
    ..moveTo(base1.dx, base1.dy)
    ..quadraticBezierTo(ctrl1.dx, ctrl1.dy, tip.dx, tip.dy)
    ..quadraticBezierTo(ctrl2.dx, ctrl2.dy, base2.dx, base2.dy)
    ..close();
}

Path _leafPath(Offset base, double length, double angleRad) {
  final Offset dir = Offset(math.cos(angleRad), math.sin(angleRad));
  final Offset perp = Offset(-dir.dy, dir.dx) * (length * 0.4);
  final Offset tip = base + dir * length;
  final Offset mid = Offset((base.dx + tip.dx) / 2, (base.dy + tip.dy) / 2);
  return Path()
    ..moveTo(base.dx, base.dy)
    ..quadraticBezierTo(mid.dx + perp.dx, mid.dy + perp.dy, tip.dx, tip.dy)
    ..quadraticBezierTo(mid.dx - perp.dx, mid.dy - perp.dy, base.dx, base.dy)
    ..close();
}
