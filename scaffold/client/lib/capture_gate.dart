// OLIVE BRANCH — homework capture gate. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.1, §8.13.5. Renders
// MARKUP screen 'capture'.
//
// "Thresholds derived from measurement, not taste." This screen owns no
// thresholds itself — every number lives in homework_quality_gate.dart's
// port of packages/homework/src/capture.ts, and this file's only job is to
// run a photo through gateImage() and route to success or
// retake_screen.dart with that verdict's own advice, unchanged.
//
// HONEST STUB: there is no camera plugin wired into pubspec.yaml in this
// preview build (this group only creates new files, so it can't add one),
// so "taking a photo" is simulated — [simulateCapture] stands in for a real
// camera frame + on-device blur/skew measurement. The demo default cycles
// through a fixed too-blurred -> too-skewed -> passes sequence so the gate,
// and retake_screen.dart, are both genuinely exercised rather than always
// trivially passing. Said plainly on screen, not glossed over — the same
// posture child_home.dart's `_notBuiltYet` takes for unbuilt tiles, adapted
// here because this feature (unlike those tiles) IS functional against
// simulated input, not a no-op.
//
// §8.13.5 marks `homework` (and by extension this sub-screen) "still" — the
// checking spinner is the one motion on screen, and it is classed the same
// as motion.ts's 'uploading'/'connecting' ambient surfaces: informational,
// brief, never attention-seeking, and it stops the moment the verdict is in.
import 'package:flutter/material.dart';
import 'homework_quality_gate.dart';
import 'retake_screen.dart';

/// Cycles through a deliberately mixed sequence so a reviewer tapping the
/// shutter repeatedly sees the gate actually gate, then settles on passing —
/// matching a real retake loop rather than a coin flip that could pass first
/// try. Exposed as a default, not a hard-coded call, so tests can inject any
/// [ImageStats] they need via [CaptureGateScreen.simulateCapture].
const List<ImageStats> demoCaptureSequence = <ImageStats>[
  ImageStats(widthPx: 640, heightPx: 480, sharpness: 40, clipping: 0.10, skewDegrees: 1),
  ImageStats(widthPx: 640, heightPx: 480, sharpness: 220, clipping: 0.10, skewDegrees: 9),
  ImageStats(widthPx: 640, heightPx: 480, sharpness: 220, clipping: 0.10, skewDegrees: 1),
];

ImageStats _defaultSimulateCapture(int attempt) =>
    demoCaptureSequence[attempt.clamp(0, demoCaptureSequence.length - 1)];

class CaptureGateScreen extends StatefulWidget {
  const CaptureGateScreen({super.key, this.onCaptured, ImageStats Function(int attempt)? simulateCapture})
      : simulateCapture = simulateCapture ?? _defaultSimulateCapture;

  /// Called once with the passing photo's stats, right before this screen
  /// pops itself with `true`.
  final ValueChanged<ImageStats>? onCaptured;

  /// Stands in for a real camera + measurement pass. See file header.
  final ImageStats Function(int attempt) simulateCapture;

  @override
  State<CaptureGateScreen> createState() => _CaptureGateScreenState();
}

class _CaptureGateScreenState extends State<CaptureGateScreen> {
  int _attempt = 0;
  bool _checking = false;

  Future<void> _takePhoto() async {
    if (_checking) return;
    setState(() => _checking = true);
    // Stands in for the time a real capture + on-device measurement would
    // take — nothing is actually computed during this delay.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final ImageStats stats = widget.simulateCapture(_attempt);
    final QualityVerdict verdict = gateImage(stats);
    setState(() {
      _checking = false;
      _attempt += 1;
    });
    if (!mounted) return;
    if (verdict.ok) {
      widget.onCaptured?.call(stats);
      Navigator.of(context).pop(true);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RetakeScreen(
        advice: verdict.advice!,
        reason: verdict.reason!,
        onRetry: () => Navigator.of(context).pop(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Photograph your worksheet')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final double side = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                return Center(
                  child: SizedBox(
                    width: side, height: side,
                    child: _ViewfinderFrame(scheme: scheme, checking: _checking),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hold the page flat inside the frame, then take the photo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: 76, height: 76,
              child: FloatingActionButton(
                key: const Key('shutterButton'),
                onPressed: _checking ? null : _takePhoto,
                child: _checking
                    ? const SizedBox(width: 26, height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : const Icon(Icons.camera_alt, size: 30),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Demo capture — this preview build simulates the photo; there is '
              'no camera wired up yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame({required this.scheme, required this.checking});
  final ColorScheme scheme;
  final bool checking;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: scheme.surfaceContainerHighest,
          border: Border.all(color: scheme.outlineVariant, width: 2)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          Center(
            child: Icon(Icons.description_outlined, size: 72, color: scheme.outline)),
          CustomPaint(painter: _CornerGuidesPainter(color: scheme.primary)),
          // Still surface (§8.13.5): a static tint on "checking", no pulsing,
          // no looping shimmer — the spinner above is the only motion.
          if (checking) Container(color: scheme.scrim.withValues(alpha: 0.12)),
        ]),
      );
}

/// Static L-shaped corner marks — the same wordless "line it up here"
/// affordance a real camera viewfinder uses. Painted once, never animated.
class _CornerGuidesPainter extends CustomPainter {
  const _CornerGuidesPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final double len = size.shortestSide * 0.12;
    const double inset = 14;
    void corner(Offset origin, Offset dx, Offset dy) {
      canvas.drawLine(origin, origin + dx * len, paint);
      canvas.drawLine(origin, origin + dy * len, paint);
    }
    corner(const Offset(inset, inset), const Offset(1, 0), const Offset(0, 1));
    corner(Offset(size.width - inset, inset), const Offset(-1, 0), const Offset(0, 1));
    corner(Offset(inset, size.height - inset), const Offset(1, 0), const Offset(0, -1));
    corner(Offset(size.width - inset, size.height - inset), const Offset(-1, 0), const Offset(0, -1));
  }

  @override
  bool shouldRepaint(covariant _CornerGuidesPainter oldDelegate) => oldDelegate.color != color;
}
