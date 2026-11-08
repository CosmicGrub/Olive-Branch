// OLIVE BRANCH — her colour: code-drawn art in seven styles. No longer
// UNVERIFIED — verified by CI (a Flutter toolchain runs for real in
// tools/verify.sh's automated pipeline). MASTERFILE §8.6.5.
//
// Every picture in the colour activities (a banana, a fox, a whale) is a short
// list of primitives — circles, ellipses, paths, strokes — drawn on a
// CustomPainter. No commissioned image, no asset file: the art is code, and one
// recipe becomes seven styles (paper cut, sticker, crayon, watercolour, felt,
// line art, pixel) by changing how the same primitives are painted. Real
// artwork can replace this later without touching any screen, because the
// screens only know [ColourArt].
//
// The drawing is tinted with HER colour of the day (a fill, never a surface and
// never a placement — §8.6.2 is about the app's own chrome, not about a picture
// she colours). In line-art style each primitive is a region a child can tap to
// fill; [onRegionTap] reports its index and nothing else.
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// One primitive of a drawing, in a 100 x 100 box.
class ArtPrim {
  const ArtPrim.circle(this.x, this.y, double r, this.fill, {this.opacity})
      : kind = 'c', rx = r, ry = r, rot = 0, d = null, stroke = null, width = 0, isLine = false;
  const ArtPrim.ellipse(this.x, this.y, this.rx, this.ry, this.fill, {this.rot = 0, this.opacity})
      : kind = 'e', d = null, stroke = null, width = 0, isLine = false;
  const ArtPrim.path(this.d, this.fill, {this.opacity})
      : kind = 'p', x = 0, y = 0, rx = 0, ry = 0, rot = 0, stroke = null, width = 0, isLine = false;
  /// A stroked line (a stem, a mouth). Not a fillable region.
  const ArtPrim.line(this.d, this.stroke, this.width, {this.opacity})
      : kind = 'l', x = 0, y = 0, rx = 0, ry = 0, rot = 0, fill = 'none', isLine = true;

  final String kind;
  final double x, y, rx, ry, rot;
  final String? d;
  /// Role in the palette: main, light, dark, leaf, black, white, beak, blush.
  final String fill;
  final String? stroke;
  final double width;
  final double? opacity;
  final bool isLine;
}

// ------------------------------------------------------------------ recipes --
ArtPrim _c(double x, double y, double r, String f, {double? opacity}) => ArtPrim.circle(x, y, r, f, opacity: opacity);
ArtPrim _e(double x, double y, double rx, double ry, String f, {double rot = 0, double? opacity}) =>
    ArtPrim.ellipse(x, y, rx, ry, f, rot: rot, opacity: opacity);
ArtPrim _p(String d, String f, {double? opacity}) => ArtPrim.path(d, f, opacity: opacity);
ArtPrim _l(String d, String s, double w, {double? opacity}) => ArtPrim.line(d, s, w, opacity: opacity);

final Map<String, List<ArtPrim>> _recipes = {
  'round': [
    _c(50, 58, 32, 'main'), _e(38, 46, 7, 11, 'light', rot: -20, opacity: .55),
    _l('M50 27 Q50 16 57 11', 'dark', 4), _e(63, 20, 11, 6, 'leaf', rot: -25),
  ],
  'banana': [
    _p('M18 70 Q30 24 78 18 Q84 18 82 26 Q52 34 36 74 Q30 84 18 70Z', 'main'),
    _p('M18 70 Q24 80 36 74 Q30 70 22 66Z', 'dark'), _p('M78 18 Q84 18 82 26 L76 24Z', 'dark'),
  ],
  'cluster': [
    _l('M50 32 Q50 18 59 12', 'dark', 4), _e(66, 18, 11, 6, 'leaf', rot: -20),
    _c(34, 44, 12, 'main'), _c(50, 44, 12, 'main'), _c(66, 44, 12, 'main'),
    _c(42, 60, 12, 'main'), _c(58, 60, 12, 'main'), _c(50, 76, 12, 'main'),
    _c(30, 40, 3.5, 'light', opacity: .7), _c(46, 40, 3.5, 'light', opacity: .7), _c(62, 40, 3.5, 'light', opacity: .7),
  ],
  'longveg': [
    _e(36, 20, 6, 13, 'leaf', rot: -30), _e(48, 14, 6, 14, 'leaf'), _e(60, 20, 6, 13, 'leaf', rot: 30),
    _e(50, 60, 16, 34, 'main', rot: 18), _l('M42 52 L50 56', 'dark', 2.5), _l('M46 70 L54 74', 'dark', 2.5),
    _e(42, 48, 4, 11, 'light', rot: 18, opacity: .5),
  ],
  'leafy': [
    _p('M42 64 L58 64 L61 92 Q50 96 39 92Z', 'light'),
    _c(32, 48, 17, 'main'), _c(50, 36, 19, 'main'), _c(68, 48, 17, 'main'),
    _c(44, 56, 14, 'main'), _c(58, 56, 14, 'main'),
    _c(46, 32, 3, 'dark', opacity: .5), _c(64, 46, 3, 'dark', opacity: .5), _c(34, 46, 3, 'dark', opacity: .5),
  ],
  'bird': [
    _l('M30 88 L30 96 M52 88 L52 96', 'beak', 3),
    _e(48, 66, 30, 24, 'main'), _c(64, 38, 19, 'main'), _p('M80 36 L97 41 L80 47Z', 'beak'),
    _c(68, 34, 3.2, 'black'), _c(69, 33, 1, 'white'), _e(42, 68, 15, 10, 'dark', rot: -20, opacity: .55),
    _p('M62 20 Q58 10 66 8 Q64 15 70 19Z', 'dark', opacity: .8),
  ],
  'fish': [
    _p('M12 56 Q20 24 56 28 Q84 32 90 56 Q80 80 50 80 Q24 80 12 56Z', 'main'),
    _p('M86 56 L99 38 L99 74Z', 'dark'), _e(46, 66, 28, 10, 'light', opacity: .7),
    _c(30, 48, 4, 'black'), _c(31, 47, 1.3, 'white'),
    _l('M44 28 Q44 16 36 12 M44 28 Q48 16 56 12', 'light', 3), _l('M58 52 Q66 56 62 66', 'dark', 2.5),
  ],
  'round-critter': [
    _e(50, 60, 30, 26, 'main'), _l('M30 50 Q50 44 70 50 M28 62 Q50 56 72 62', 'black', 6, opacity: .55),
    _c(50, 34, 15, 'main'), _c(44, 32, 3, 'black'), _c(56, 32, 3, 'black'),
    _e(30, 30, 10, 7, 'white', rot: -30, opacity: .85), _e(70, 30, 10, 7, 'white', rot: 30, opacity: .85),
    _l('M44 20 Q40 10 36 8 M56 20 Q60 10 64 8', 'black', 2),
  ],
};

/// The four "face" animals share one head, differing only in their ears.
List<ArtPrim> _faceCritter(String ears) => [
  if (ears == 'round') ...[_c(26, 28, 12, 'main'), _c(74, 28, 12, 'main'), _c(26, 28, 6, 'light'), _c(74, 28, 6, 'light')],
  if (ears == 'pointy') ...[
    _p('M22 44 L26 10 L46 28Z', 'main'), _p('M78 44 L74 10 L54 28Z', 'main'),
    _p('M28 36 L29 20 L38 29Z', 'dark'), _p('M72 36 L71 20 L62 29Z', 'dark')],
  if (ears == 'frog') ...[
    _c(32, 30, 13, 'main'), _c(68, 30, 13, 'main'), _c(32, 30, 8, 'white'), _c(68, 30, 8, 'white'),
    _c(33, 31, 4, 'black'), _c(67, 31, 4, 'black')],
  if (ears == 'elephant') ...[
    _c(18, 52, 17, 'main'), _c(82, 52, 17, 'main'), _c(18, 52, 10, 'light', opacity: .7), _c(82, 52, 10, 'light', opacity: .7)],
  _c(50, 56, 30, 'main'),
  if (ears == 'elephant') _p('M43 62 Q43 92 62 88 Q54 84 56 62Z', 'dark', opacity: .9),
  _e(50, 66, 14, 10, 'light', opacity: .7),
  if (ears != 'frog') ...[_c(40, 52, 3.6, 'black'), _c(60, 52, 3.6, 'black'), _c(41, 51, 1.1, 'white'), _c(61, 51, 1.1, 'white')],
  if (ears != 'elephant') _e(50, 63, 6, 4.5, 'dark'),
  _l('M44 71 Q50 76 56 71', 'black', 2.6),
  _e(32, 66, 6, 4, 'blush', opacity: .6), _e(68, 66, 6, 4, 'blush', opacity: .6),
];

const Map<String, String> _faceKinds = {'bear': 'round', 'fox': 'pointy', 'frog': 'frog', 'elephant': 'elephant'};

/// Every recipe key a picture can use.
const List<String> artKeys = [
  'round', 'banana', 'cluster', 'longveg', 'leafy', 'bird', 'fish', 'round-critter',
  'bear', 'fox', 'frog', 'elephant',
];

List<ArtPrim> primsFor(String key) {
  final face = _faceKinds[key];
  if (face != null) return _faceCritter(face);
  return _recipes[key] ?? _recipes['round']!;
}

// ------------------------------------------------------------------ palette --
Color _mix(Color c, double t) {
  final k = t > 0 ? 255.0 : 0.0, a = t.abs();
  int ch(double v) => (v + (k - v) * a).round().clamp(0, 255);
  return Color.fromARGB(255, ch(c.r * 255), ch(c.g * 255), ch(c.b * 255));
}

/// Light, main and dark tints of one colour — what a child fills with.
List<Color> tintsOf(Color main) => [_mix(main, .5), main, _mix(main, -.38)];

Map<String, Color> _roles(Color main) => {
  'main': main, 'dark': _mix(main, -.38), 'light': _mix(main, .5),
  'leaf': const Color(0xFF5AA84A), 'black': const Color(0xFF22282B), 'white': Colors.white,
  'beak': const Color(0xFFF2A33A), 'blush': const Color(0xFFF6A5A9), 'ink': const Color(0xFF2B3A2F),
};

// --------------------------------------------------------------------- paths --
Path _parse(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLQZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m[0]!).toList();
  var i = 0;
  double n() => double.parse(tokens[i++]);
  String cmd = 'M';
  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'[MLQZ]').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        path.moveTo(n(), n());
        cmd = 'L';
      case 'L':
        path.lineTo(n(), n());
      case 'Q':
        path.quadraticBezierTo(n(), n(), n(), n());
      default:
        i++;
    }
  }
  return path;
}

Path pathOf(ArtPrim p) {
  switch (p.kind) {
    case 'c':
      return Path()..addOval(Rect.fromCircle(center: Offset(p.x, p.y), radius: p.rx));
    case 'e':
      final base = Path()..addOval(Rect.fromCenter(center: Offset(p.x, p.y), width: p.rx * 2, height: p.ry * 2));
      if (p.rot == 0) return base;
      final r = p.rot * math.pi / 180;
      final c = math.cos(r), s = math.sin(r);
      return base.transform(Float64List.fromList([
        c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0,
        p.x - p.x * c + p.y * s, p.y - p.x * s - p.y * c, 0, 1,
      ]));
    default:
      return _parse(p.d!);
  }
}

// ------------------------------------------------------------------- widget --
/// A picture. [style] is one of the seven art styles; [regions] fills
/// individual primitives in line-art style (index -> colour).
class ColourArt extends StatelessWidget {
  const ColourArt({
    super.key, required this.recipe, required this.color, required this.style,
    this.size = 96, this.regions = const {}, this.onRegionTap, this.semanticLabel = 'Drawing',
  });

  final String recipe;
  final Color color;
  final String style;
  final double size;
  final Map<int, Color> regions;
  final ValueChanged<int>? onRegionTap;
  final String semanticLabel;

  /// Index of the topmost fillable primitive at [local] (0..100 space), or null.
  static int? regionAt(String recipe, Offset local) {
    final prims = primsFor(recipe);
    for (var i = prims.length - 1; i >= 0; i--) {
      if (prims[i].isLine) continue;
      if (pathOf(prims[i]).contains(local)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final art = CustomPaint(
      size: Size.square(size),
      painter: _ArtPainter(recipe, color, style, regions),
    );
    return Semantics(
      label: semanticLabel, image: true,
      child: SizedBox(width: size, height: size,
        child: onRegionTap == null ? art : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final hit = regionAt(recipe, d.localPosition * (100 / size));
            if (hit != null) onRegionTap!(hit);
          },
          child: art)),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.recipe, this.color, this.style, this.regions);
  final String recipe;
  final Color color;
  final String style;
  final Map<int, Color> regions;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final prims = primsFor(recipe);
    final roles = _roles(color);
    if (style == 'pixel') {
      _paintPixels(canvas, prims, roles);
      canvas.restore();
      return;
    }
    if (style == 'paper' || style == 'sticker') {
      final shadow = Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
      for (final p in prims) {
        if (!p.isLine) canvas.drawPath(pathOf(p).shift(const Offset(0, 2)), shadow);
      }
    }
    if (style == 'sticker') {
      final edge = Paint()..color = Colors.white..style = PaintingStyle.stroke
        ..strokeWidth = 7..strokeJoin = StrokeJoin.round;
      final fillW = Paint()..color = Colors.white;
      for (final p in prims) {
        if (p.isLine) continue;
        canvas.drawPath(pathOf(p), edge);
        canvas.drawPath(pathOf(p), fillW);
      }
    }
    for (var i = 0; i < prims.length; i++) {
      final p = prims[i];
      final path = pathOf(p);
      final strokeColor = p.stroke != null ? roles[p.stroke]! : roles['dark']!;
      if (p.isLine) {
        canvas.drawPath(path, Paint()
          ..color = (style == 'line' ? const Color(0xFF26352B) : strokeColor).withValues(alpha: p.opacity ?? 1)
          ..style = PaintingStyle.stroke..strokeWidth = p.width == 0 ? 3 : p.width
          ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
        continue;
      }
      final fill = style == 'line' ? (regions[i] ?? Colors.white) : (roles[p.fill] ?? color);
      var alpha = p.opacity ?? 1.0;
      if (style == 'watercolour' && p.opacity == null) alpha = .78;
      canvas.drawPath(path, Paint()..color = fill.withValues(alpha: alpha));
      switch (style) {
        case 'crayon':
          canvas.drawPath(path, Paint()..color = roles['dark']!..style = PaintingStyle.stroke
            ..strokeWidth = 2.2..strokeJoin = StrokeJoin.round);
        case 'watercolour':
          canvas.drawPath(path, Paint()..color = roles['dark']!.withValues(alpha: .35)
            ..style = PaintingStyle.stroke..strokeWidth = 1.6);
        case 'felt':
          _dashed(canvas, path, Paint()..color = roles['light']!..style = PaintingStyle.stroke
            ..strokeWidth = 1.6..strokeCap = StrokeCap.round);
        case 'line':
          canvas.drawPath(path, Paint()..color = const Color(0xFF26352B)..style = PaintingStyle.stroke
            ..strokeWidth = 2.6..strokeJoin = StrokeJoin.round);
      }
    }
    if (style == 'sticker') {
      canvas.save();
      canvas.translate(38, 26);
      canvas.rotate(-24 * math.pi / 180);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 28, height: 10),
        Paint()..color = Colors.white.withValues(alpha: .35));
      canvas.restore();
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 2.5, m.length)), paint);
        d += 5.7;
      }
    }
  }

  /// Pixel style: a coarse grid, each cell the topmost primitive at its centre.
  void _paintPixels(Canvas canvas, List<ArtPrim> prims, Map<String, Color> roles) {
    const n = 20;
    const cell = 100 / n;
    final paths = [for (final p in prims) p.isLine ? null : pathOf(p)];
    for (var gy = 0; gy < n; gy++) {
      for (var gx = 0; gx < n; gx++) {
        final centre = Offset((gx + .5) * cell, (gy + .5) * cell);
        Color? out;
        for (var i = 0; i < prims.length; i++) {
          final path = paths[i];
          if (path == null || !path.contains(centre)) continue;
          final c = roles[prims[i].fill] ?? color;
          final a = prims[i].opacity ?? 1.0;
          out = out == null ? c.withValues(alpha: a) : Color.alphaBlend(c.withValues(alpha: a), out);
        }
        if (out != null) {
          canvas.drawRect(Rect.fromLTWH(gx * cell, gy * cell, cell + .2, cell + .2), Paint()..color = out);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      old.recipe != recipe || old.color != color || old.style != style || old.regions != regions;
}
