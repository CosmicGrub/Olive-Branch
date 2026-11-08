// No longer UNVERIFIED — verified by CI (client/test/ui/olive_art_test.dart).
// OLIVE BRANCH — the tiny vector model and CustomPainter the kit's icons, scenes and spot
// illustrations are drawn with. The DATA (olive_art_data.dart) is generated from the kit by
// tools/gen-olive-icons.mjs: rect/circle/ellipse/polygon/arc are already normalised to absolute
// move / line / quad / cubic commands, so no SVG parser ships in the app and nothing here can fail
// at runtime on a malformed string.
//
// Colours are palette-aware ([OCol] tokens resolved through [OlivePalette]), so every palette and
// both brightnesses get their own illustration colours, exactly like the kit's `var(--pri)` scenes.
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'olive_palette.dart';

export 'olive_palette.dart' show OTok;

/// A paint source in the generated art.
sealed class OPaint {
  const OPaint();
}

/// A colour: a palette token, a fixed colour, `currentColor`, or a mix of two (CSS color-mix in srgb).
class OCol extends OPaint {
  const OCol.v(OTok this.tok)
      : _kind = 0, argb = 0, a = null, b = null, pct = 0;
  const OCol.h(this.argb)
      : _kind = 1, tok = null, a = null, b = null, pct = 0;
  const OCol.mix(OCol this.a, this.pct, OCol this.b)
      : _kind = 2, tok = null, argb = 0;
  const OCol._current()
      : _kind = 3, tok = null, argb = 0, a = null, b = null, pct = 0;

  static const OCol current = OCol._current();

  final int _kind;
  final OTok? tok;
  final int argb;
  final OCol? a, b;
  final double pct;

  /// Resolves to a concrete colour.
  Color resolve(OlivePalette p, Color currentColor) {
    switch (_kind) {
      case 0:
        return p.tok(tok!);
      case 1:
        return Color(argb);
      case 2:
        return Color.lerp(b!.resolve(p, currentColor), a!.resolve(p, currentColor), pct / 100)!;
      default:
        return currentColor;
    }
  }
}

/// A vertical two-stop gradient across the shape's bounds (the only gradient the kit uses).
class OGrad extends OPaint {
  const OGrad(this.top, this.bottom);
  final OCol top, bottom;
}

/// One node of a drawing: a [OPath] or an [OGroup].
sealed class ONode {
  const ONode();
}

/// A shape. [d] is a flat opcode list: 0 M x y | 1 L x y | 2 Q cx cy x y | 3 C x1 y1 x2 y2 x y | 4 Z.
class OPath extends ONode {
  const OPath(this.d, {this.f, this.s, this.sw = 1, this.cap = 0, this.join = 0, this.dash,
      this.so = 1, this.fo = 1, this.opacity = 1});
  final List<double> d;
  final OPaint? f;
  final OCol? s;
  final double sw;
  /// 0 butt, 1 round, 2 square.
  final int cap;
  /// 0 miter, 1 round, 2 bevel.
  final int join;
  final List<double>? dash;
  final double so, fo, opacity;
}

/// A group with an optional composited opacity and a 2x3 affine matrix [m] (a b c d e f).
class OGroup extends ONode {
  const OGroup(this.children, {this.opacity = 1, this.m});
  final List<ONode> children;
  final double opacity;
  final List<double>? m;
}

final Expando<Path> _pathCache = Expando<Path>('olivePaths');
final Expando<Path> _dashCache = Expando<Path>('oliveDashedPaths');

Path _buildPath(OPath n) {
  final cached = _pathCache[n];
  if (cached != null) return cached;
  final p = Path();
  final d = n.d;
  var i = 0;
  while (i < d.length) {
    switch (d[i].toInt()) {
      case 0:
        p.moveTo(d[i + 1], d[i + 2]);
        i += 3;
      case 1:
        p.lineTo(d[i + 1], d[i + 2]);
        i += 3;
      case 2:
        p.quadraticBezierTo(d[i + 1], d[i + 2], d[i + 3], d[i + 4]);
        i += 5;
      case 3:
        p.cubicTo(d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5], d[i + 6]);
        i += 7;
      default:
        p.close();
        i += 1;
    }
  }
  _pathCache[n] = p;
  return p;
}

Path _dashed(OPath n, Path src) {
  final cached = _dashCache[n];
  if (cached != null) return cached;
  final pat = n.dash!;
  final out = Path();
  for (final metric in src.computeMetrics()) {
    var dist = 0.0;
    var k = 0;
    var draw = true;
    while (dist < metric.length) {
      final len = pat[k % pat.length];
      if (draw) out.addPath(metric.extractPath(dist, (dist + len).clamp(0, metric.length)), Offset.zero);
      dist += len <= 0 ? 0.01 : len;
      draw = !draw;
      k++;
    }
  }
  _dashCache[n] = out;
  return out;
}

/// Paints [nodes] (authored on a [viewW] x [viewH] canvas) into the widget's box.
class OliveVectorPainter extends CustomPainter {
  OliveVectorPainter({
    required this.nodes,
    required this.viewW,
    required this.viewH,
    required this.palette,
    required this.current,
    this.strokeWidth,
    this.fit = BoxFit.contain,
  });

  final List<ONode> nodes;
  final double viewW, viewH;
  final OlivePalette palette;
  /// What `currentColor` means (icons).
  final Color current;
  /// When set, every stroke is drawn at this width (icons: the requested stroke weight).
  final double? strokeWidth;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final sx = size.width / viewW, sy = size.height / viewH;
    final scale = fit == BoxFit.cover ? (sx > sy ? sx : sy) : (sx < sy ? sx : sy);
    final dx = (size.width - viewW * scale) / 2, dy = (size.height - viewH * scale) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(dx, dy);
    canvas.scale(scale);
    _paintNodes(canvas, nodes);
    canvas.restore();
  }

  void _paintNodes(Canvas canvas, List<ONode> list) {
    for (final n in list) {
      switch (n) {
        case final OGroup g:
          canvas.save();
          if (g.m != null) {
            final m = g.m!;
            canvas.transform(Float64List.fromList(<double>[
              m[0], m[1], 0, 0, m[2], m[3], 0, 0, 0, 0, 1, 0, m[4], m[5], 0, 1]));
          }
          if (g.opacity < 1) {
            canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, g.opacity));
            _paintNodes(canvas, g.children);
            canvas.restore();
          } else {
            _paintNodes(canvas, g.children);
          }
          canvas.restore();
        case final OPath p:
          _paintPath(canvas, p);
      }
    }
  }

  void _paintPath(Canvas canvas, OPath n) {
    final path = _buildPath(n);
    final fill = n.f;
    if (fill != null) {
      final paint = Paint()..style = PaintingStyle.fill..isAntiAlias = true;
      final a = n.fo * n.opacity;
      switch (fill) {
        case final OCol c:
          final col = c.resolve(palette, current);
          paint.color = col.withValues(alpha: col.a * a);
        case final OGrad g:
          final t = g.top.resolve(palette, current), b = g.bottom.resolve(palette, current);
          paint.shader = ui.Gradient.linear(path.getBounds().topCenter, path.getBounds().bottomCenter,
              [t.withValues(alpha: t.a * a), b.withValues(alpha: b.a * a)]);
      }
      canvas.drawPath(path, paint);
    }
    final stroke = n.s;
    if (stroke != null) {
      final col = stroke.resolve(palette, current);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..color = col.withValues(alpha: col.a * n.so * n.opacity)
        ..strokeWidth = strokeWidth ?? n.sw
        ..strokeCap = switch (n.cap) { 1 => StrokeCap.round, 2 => StrokeCap.square, _ => StrokeCap.butt }
        ..strokeJoin = switch (n.join) { 1 => StrokeJoin.round, 2 => StrokeJoin.bevel, _ => StrokeJoin.miter };
      canvas.drawPath(n.dash == null ? path : _dashed(n, path), paint);
    }
  }

  @override
  bool shouldRepaint(OliveVectorPainter old) =>
      old.nodes != nodes || old.palette != palette || old.current != current ||
      old.strokeWidth != strokeWidth || old.fit != fit || old.viewW != viewW || old.viewH != viewH;
}
