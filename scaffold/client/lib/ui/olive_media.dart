// No longer UNVERIFIED — verified by CI (client/test/ui/olive_ui_test.dart).
// OLIVE BRANCH — recording, playback and pairing.
//
//   RecordButton  <- kit `K.recordBtn(o)` (`.rec`): a big round button, idle / recording / done
//   Waveform      <- kit `K.waveform(o)`: the same deterministic bar heights as the kit, played part tinted
//   PlayerChrome  <- kit `K.player(o)`: scene backdrop, play / pause, an optional wordless scrubber and
//                    a captions button. It draws chrome only: wire the real video surface behind it.
//   QrCard        <- kit `K.qrCard(o)`: a placeholder pattern that is deliberately NOT scannable
//
// Replaces (adoption wave): the bespoke record buttons in child_record / letters screens, the
// call_screen / co_view chrome, and the raw QrImageView card in pairing screens (pass the real code
// widget through [QrCard.qr]).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'olive_art.dart';
import 'olive_base.dart';
import 'olive_palette.dart';

/// States of a [RecordButton].
enum RecordState { idle, recording, done }

/// Kit `K.recordBtn`. Idle shows a microphone, recording a red rounded square (a stop control) inside
/// a red ring, done a refresh glyph. The state is told in shape and in the semantic label, not by
/// colour alone. [size] is the outer ring; the hit area is never below 64dp.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key, this.state = RecordState.idle, this.time, this.size = 88, this.onPressed, this.semanticLabel});

  final RecordState state;
  /// Elapsed time text such as "0:12".
  final String? time;
  final double size;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final rec = state == RecordState.recording;
    final label = semanticLabel ??
        switch (state) { RecordState.idle => 'Start recording', RecordState.recording => 'Stop recording', RecordState.done => 'Record again' };
    final coreSize = rec ? size * 0.4 : size - 24;
    final ring = rec ? p.bad : p.pri;
    final core = AnimatedContainer(
      duration: OliveTiming.base(context),
      curve: OliveTiming.spring,
      width: coreSize, height: coreSize,
      decoration: BoxDecoration(
        color: rec ? p.bad : (state == RecordState.done ? p.priC : p.pri),
        borderRadius: BorderRadius.circular(rec ? coreSize * 0.22 : coreSize / 2),
        boxShadow: rec ? null : [BoxShadow(color: p.pri.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: -10, offset: const Offset(0, 10))],
      ),
      child: rec
          ? null
          : Center(
              child: OliveIcon(state == RecordState.done ? OliveIcons.refresh : OliveIcons.mic,
                  size: 30, strokeWidth: 1.9, color: state == RecordState.done ? p.onPriC : p.onPri)),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      OlivePressable(
        onTap: onPressed,
        toggled: rec,
        semanticLabel: label,
        borderRadius: size / 2,
        minWidth: 64,
        minHeight: 64,
        child: SizedBox.square(
          dimension: size,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 4)))),
            core,
          ]),
        ),
      ),
      if (time != null) ...[
        const SizedBox(height: 8),
        Text(time!, style: OliveText.mono(context, color: p.ink2, size: 15)),
      ],
    ]);
  }
}

/// Kit `K.waveform`: [bars] bars whose heights come from the kit's seeded generator (so a given
/// [seed] draws the same shape here as in the prototype). [played] (0..1) tints the played part.
class Waveform extends StatelessWidget {
  const Waveform({super.key, this.bars = 36, this.played = 0, this.seed = 7, this.height = 44, this.accent = false, this.semanticLabel = 'Audio'});

  final int bars;
  final double played;
  final int seed;
  final double height;
  /// Use the warm accent instead of the primary colour.
  final bool accent;
  final String semanticLabel;

  /// The bar heights, 0.14..1, identical to kit.js `OB.waveform`.
  static List<double> heights(int bars, int seed) {
    var s = (seed & 0xFFFFFFFF) == 0 ? 7 : (seed & 0xFFFFFFFF);
    final out = <double>[];
    for (var i = 0; i < bars; i++) {
      s = (s * 1664525 + 1013904223) & 0xFFFFFFFF;
      final env = math.sin((i + 0.5) / bars * math.pi);
      final r = ((s >> 8) & 255) / 255;
      out.add((0.18 + env * 0.5 + r * 0.38).clamp(0.14, 1.0));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final strong = accent ? p.accent : p.pri;
    return Semantics(
      image: true,
      label: semanticLabel,
      value: played > 0 ? '${(played * 100).round()} percent played' : null,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WavePainter(
              heights: heights(bars, seed), played: played,
              on: strong, off: Color.lerp(p.surface3, strong, 0.32)!),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.heights, required this.played, required this.on, required this.off});
  final List<double> heights;
  final double played;
  final Color on, off;

  @override
  void paint(Canvas canvas, Size size) {
    final n = heights.length;
    if (n == 0) return;
    const gap = 2.0;
    final bw = ((size.width - (n - 1) * gap) / n).clamp(2.0, 5.0);
    for (var i = 0; i < n; i++) {
      final h = size.height * heights[i];
      final x = i * (bw + gap);
      if (x + bw > size.width + 0.5) break;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bw, h), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = i / n < played ? on : off);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.played != played || o.on != on || o.off != off || o.heights != heights;
}

/// Kit `K.player`: the chrome of the video player over a scene backdrop. 16:10. The scrubber is
/// wordless by default (no times); the whole chrome is controls only, so a child can use it without
/// reading. [progress] is 0..1.
class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    this.scene = 'day',
    this.caption,
    this.progress = 0.35,
    this.playing = false,
    this.captionsOn = true,
    this.showScrubber = true,
    this.timeText,
    this.title = 'Video',
    this.onPlayPause,
    this.onSeek,
    this.onCaptions,
    this.onFullscreen,
    this.backdrop,
  });

  final String scene;
  final String? caption;
  final double progress;
  final bool playing;
  final bool captionsOn;
  /// Hide it for the youngest viewers; play / pause and captions remain.
  final bool showScrubber;
  /// Optional "0:24 / 1:10"; null keeps the player wordless.
  final String? timeText;
  final String title;
  final VoidCallback? onPlayPause;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onCaptions;
  final VoidCallback? onFullscreen;
  /// The real video surface. When null the [scene] illustration is the backdrop.
  final Widget? backdrop;

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final pr = progress.clamp(0.0, 1.0);
    const white = Colors.white;
    Widget ctl(String icon, String label, VoidCallback? onTap, {bool on = false, double iconSize = 18}) => OlivePressable(
          onTap: onTap,
          semanticLabel: label,
          selected: on ? true : null,
          borderRadius: 24,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? white.withValues(alpha: 0.2) : Colors.transparent),
            child: Center(child: OliveIcon(icon, size: iconSize, strokeWidth: 2, color: white)),
          ),
        );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(OliveRadius.r3), boxShadow: p.shadow(2)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(OliveRadius.r3),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: Colors.black, child: backdrop ?? OliveScene(scene, borderRadius: 0)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)])),
              ),
              if (!playing)
                Align(
                  alignment: const Alignment(0, -0.16),
                  child: OlivePressable(
                    onTap: onPlayPause,
                    semanticLabel: 'Play',
                    borderRadius: 32,
                    minWidth: 64,
                    minHeight: 64,
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                          color: white.withValues(alpha: 0.95), shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 22, spreadRadius: -6, offset: const Offset(0, 8))]),
                      child: const Center(child: OliveIcon(OliveIcons.play, size: 30, strokeWidth: 2, color: Colors.black)),
                    ),
                  ),
                ),
              if (captionsOn && caption != null)
                Positioned(
                  left: 12, right: 12, bottom: 56,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.84), borderRadius: BorderRadius.circular(8)),
                      child: Text(caption!, textAlign: TextAlign.center, style: OliveText.strong(context, color: white, size: 13).copyWith(height: 1.3)),
                    ),
                  ),
                ),
              Positioned(
                left: 4, right: 4, bottom: 4,
                child: Row(children: [
                  ctl(playing ? OliveIcons.pause : OliveIcons.play, playing ? 'Pause' : 'Play', onPlayPause),
                  if (showScrubber)
                    Expanded(child: _Scrubber(progress: pr, onSeek: onSeek))
                  else
                    const Spacer(),
                  if (timeText != null) Padding(padding: const EdgeInsets.only(right: 4), child: Text(timeText!, style: OliveText.mono(context, color: white, size: 11))),
                  ctl(OliveIcons.cc, 'Captions', onCaptions, on: captionsOn, iconSize: 18),
                  if (onFullscreen != null) ctl(OliveIcons.expand, 'Full screen', onFullscreen, iconSize: 16),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.progress, required this.onSeek});
  final double progress;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final step = 0.1;
    return Semantics(
      slider: true,
      label: 'Seek',
      value: '${(progress * 100).round()} percent',
      increasedValue: '${((progress + step).clamp(0.0, 1.0) * 100).round()} percent',
      decreasedValue: '${((progress - step).clamp(0.0, 1.0) * 100).round()} percent',
      onIncrease: onSeek == null ? null : () => onSeek!((progress + step).clamp(0.0, 1.0)),
      onDecrease: onSeek == null ? null : () => onSeek!((progress - step).clamp(0.0, 1.0)),
      child: LayoutBuilder(builder: (context, c) {
        const thumb = 16.0;
        final w = c.maxWidth.isFinite ? c.maxWidth : 120.0;
        final usable = (w - thumb).clamp(1.0, double.infinity);
        void at(double dx) => onSeek?.call(((dx - thumb / 2) / usable).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
          child: SizedBox(
            height: 48,
            child: Stack(alignment: Alignment.centerLeft, children: [
              Positioned(
                left: thumb / 2, right: thumb / 2,
                child: Container(
                  height: 4,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(4)),
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                  ),
                ),
              ),
              Positioned(
                left: progress * usable,
                child: Container(
                  width: thumb, height: thumb,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 1))]),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

/// Kit `K.qrCard`: the pairing-code card. By default it draws a PLACEHOLDER pattern from the code text
/// (kit's seeded generator) that cannot be scanned: only two of the three position markers are drawn
/// and it is labelled "sample only". Pass the real code widget as [qr] and the placeholder (and its
/// "Sample" chip) disappear.
class QrCard extends StatelessWidget {
  const QrCard({super.key, this.code = 'OLIVE-7K4P', this.title, this.sub, this.expires, this.onCopy, this.copyLabel = 'Copy code', this.qr});

  final String code;
  final String? title;
  final String? sub;
  /// "10 minutes": shown as "Expires in ...".
  final String? expires;
  /// Null hides the copy button.
  final VoidCallback? onCopy;
  final String copyLabel;
  /// A real, scannable code widget (e.g. PrettyQrView). Replaces the placeholder.
  final Widget? qr;

  /// The placeholder's module grid for [code] (kit generator). Exposed so tests can pin parity with
  /// the prototype and assert it is not a valid QR layout.
  static List<List<bool>> placeholderCells(String code) => _QrPainter.cells(code);

  /// The modules the placeholder actually DRAWS: [placeholderCells] without the bottom-left position
  /// marker block, so no scanner can read it. Exposed for the tests that pin that guarantee.
  static List<List<bool>> placeholderDrawn(String code) => _QrPainter.drawn(code);

  @override
  Widget build(BuildContext context) {
    final p = OlivePalette.of(context);
    final placeholder = qr == null;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(OliveRadius.r3), border: Border.all(color: p.line), boxShadow: p.shadow(1)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 176, maxHeight: 176),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(children: [
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line)),
                    child: placeholder
                        ? Semantics(
                            image: true,
                            label: 'Pairing code, sample only. This picture cannot be scanned.',
                            child: ExcludeSemantics(child: CustomPaint(painter: _QrPainter(code, Colors.black.withValues(alpha: 0.78)))))
                        : qr,
                  ),
                ),
                if (placeholder) const Positioned(right: 8, bottom: 8, child: OliveChip('Sample', small: true)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (title != null) Text(title!, textAlign: TextAlign.center, style: OliveText.head(context)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sub!, textAlign: TextAlign.center, style: OliveText.cap(context))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(code, textAlign: TextAlign.center, style: OliveText.mono(context, size: 22).copyWith(letterSpacing: 3)),
          ),
          if (expires != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                OliveIcon(OliveIcons.clock, size: 12, strokeWidth: 2, color: p.ink3),
                const SizedBox(width: 5),
                Flexible(child: Text('Expires in $expires', style: OliveText.cap(context))),
              ]),
            ),
          if (onCopy != null) ...[
            const SizedBox(height: 12),
            OliveButton(copyLabel, onPressed: onCopy, kind: OliveButtonKind.tonal, size: OliveButtonSize.sm, icon: OliveIcons.copy),
          ],
        ]),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.code, this.color);
  final String code;
  final Color color;

  /// The kit's generator: FNV-1a over the code, then a 32-bit LCG per module.
  static List<List<bool>> cells(String code) {
    const n = 21;
    var seed = 2166136261;
    for (final u in code.codeUnits) {
      seed ^= u;
      seed = (seed * 16777619) & 0xFFFFFFFF;
    }
    bool finder(int x, int y) => (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7);
    final out = List.generate(n, (_) => List.filled(n, false));
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (finder(x, y)) {
          final fx = x >= n - 7 ? x - (n - 7) : x, fy = y >= n - 7 ? y - (n - 7) : y;
          out[y][x] = (fx == 0 || fx == 6 || fy == 0 || fy == 6) || (fx >= 2 && fx <= 4 && fy >= 2 && fy <= 4);
        } else {
          seed = (seed * 1103515245 + 12345) & 0xFFFFFFFF;
          out[y][x] = ((seed >> 16) & 1) == 1;
        }
      }
    }
    return out;
  }

  /// [cells] minus the bottom-left position marker block, which is left out on purpose: a scanner
  /// needs all three markers, so this picture can never be read as a code.
  static List<List<bool>> drawn(String code) {
    const n = 21;
    final g = cells(code);
    return [
      for (var y = 0; y < n; y++) [for (var x = 0; x < n; x++) (x < 7 && y >= n - 7) ? false : g[y][x]],
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = drawn(code);
    const n = 21;
    final u = size.shortestSide / (n + 2);
    final paint = Paint()..color = color;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (!g[y][x]) continue;
        canvas.drawCircle(Offset((x + 1.5) * u, (y + 1.5) * u), u * 0.42, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter o) => o.code != code || o.color != color;
}
