// No longer UNVERIFIED — verified by CI (client/test/ui/olive_art_test.dart).
// OLIVE BRANCH — icons and illustrations of the premium kit, as widgets.
//
//   OliveIcon   <- kit `K.ico(name, size, strokeWidth)` and the IC table (24-grid stroke icons)
//   OliveScene  <- kit `K.scene(kind, w, h)`: day, night, garden, kitchen, car, classroom, bedroom,
//                  park, sea, twohouses (plus hills, paper, letters, branch)
//   OliveSpot   <- kit `K.spot(kind, size, {plate, tone})`: family, houses, envelope, key, shield,
//                  lock, phone, tablet, video, mic, leaf (the celebration image)
//
// Soft and warm, palette-aware (they take their colours from OlivePalette, so every palette and both
// brightnesses get their own), and static: nothing here animates. There are no scores, streaks,
// trophies or stars among the illustrations (P2). The leaf is the celebration image.
import 'package:flutter/material.dart';

import 'olive_art_data.dart';
import 'olive_palette.dart';
import 'olive_vector.dart';

export 'olive_art_data.dart' show OliveIcons, kOliveSceneNames, kOliveSpotNames;

/// A 24-grid stroke icon from the kit icon set. [name] is one of [OliveIcons.all]; an unknown name
/// draws `info`, as the kit does. Decorative unless [semanticLabel] is given (the kit marks icons
/// aria-hidden and puts the words next to them).
class OliveIcon extends StatelessWidget {
  const OliveIcon(this.name, {super.key, this.size = 22, this.strokeWidth = 1.8, this.color, this.semanticLabel});

  final String name;
  final double size;
  final double strokeWidth;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final nodes = kOliveIconData[name] ?? kOliveIconData[OliveIcons.info]!;
    final c = color ?? IconTheme.of(context).color ?? OlivePalette.of(context).ink;
    final icon = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: OliveVectorPainter(
          nodes: nodes, viewW: 24, viewH: 24, palette: OlivePalette.of(context), current: c, strokeWidth: strokeWidth),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(image: true, label: semanticLabel, child: ExcludeSemantics(child: icon));
  }
}

/// A scene illustration on the kit's 300 x 150 canvas, covering its box. With neither [width] nor
/// [height] it fills the available width at 2:1.
class OliveScene extends StatelessWidget {
  const OliveScene(this.kind, {super.key, this.width, this.height, this.borderRadius = 20, this.semanticLabel});

  final String kind;
  final double? width, height;
  final double borderRadius;
  /// Scenes are decorative by default (kit aria-hidden).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final nodes = kOliveSceneData[kind] ?? kOliveSceneData['hills']!;
    final p = OlivePalette.of(context);
    Widget art = RepaintBoundary(
      child: CustomPaint(
        painter: OliveVectorPainter(
            nodes: nodes, viewW: 300, viewH: 150, palette: p, current: p.ink, fit: BoxFit.cover),
        child: const SizedBox.expand(),
      ),
    );
    if (borderRadius > 0) art = ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: art);
    final sized = (width != null || height != null)
        ? SizedBox(width: width, height: height ?? (width! / 2), child: art)
        : AspectRatio(aspectRatio: 2, child: art);
    return semanticLabel == null
        ? ExcludeSemantics(child: sized)
        : Semantics(image: true, label: semanticLabel, child: ExcludeSemantics(child: sized));
  }
}

/// A 96-grid spot illustration on a soft rounded plate. [plate] false draws the picture alone;
/// [accentPlate] uses the warm accent tint instead of the primary one (kit `{tone:"accent"}`).
class OliveSpot extends StatelessWidget {
  const OliveSpot(this.kind, {super.key, this.size = 96, this.plate = true, this.accentPlate = false, this.semanticLabel});

  final String kind;
  final double size;
  final bool plate;
  final bool accentPlate;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final nodes = kOliveSpotData[kind] ?? kOliveSpotData['leaf']!;
    final art = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: plate
            ? BoxDecoration(color: accentPlate ? p.accentC : p.priC, borderRadius: BorderRadius.circular(size * 28 / 96))
            : const BoxDecoration(),
        child: CustomPaint(
          painter: OliveVectorPainter(nodes: nodes, viewW: 96, viewH: 96, palette: p, current: p.ink),
        ),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: art)
        : Semantics(image: true, label: semanticLabel, child: ExcludeSemantics(child: art));
  }
}
