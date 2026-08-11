// OLIVE BRANCH — homework capture gate. MASTERFILE §9.1, §8.13.5, §20.2b.
// Renders MARKUP screen 'capture'.
//
// "Thresholds derived from measurement, not taste." This screen owns no
// thresholds itself. Two capture paths now, chosen at runtime, not two
// copies of this file:
//
//  REAL PATH — used whenever [simulateCapture] is NOT overridden AND
//  [baseUrl]/[childId]/[sessionToken] are all supplied: takes an actual
//  photo via image_picker's camera source and POSTs the raw bytes to
//  POST /v1/children/:childId/homework/capture (api_client.dart's
//  `captureHomework`). The SERVER runs the real gate + OCR + guarded-hint
//  pipeline (packages/homework/src/capture-route.ts) and this screen just
//  renders whatever verdict comes back — no ImageStats math is duplicated
//  in Dart for this path, on purpose (that duplication is exactly what
//  homework_quality_gate.dart's own header used to warn could drift from
//  the TypeScript source of truth).
//
//  SIMULATED PATH — everything else: either a test supplies
//  [simulateCapture] directly (capture_gate_test.dart,
//  capture-route-adjacent widget tests), or no live baseUrl/session is
//  configured yet (e.g. the offline demo build, lib/main.dart, which has no
//  backend to call at all — see that file's own header). Runs
//  homework_quality_gate.dart's local port of gateImage() against the
//  supplied/demo [ImageStats] exactly as this file always has. Honestly
//  labelled on screen either way — the copy at the bottom of this screen
//  reflects which path is actually live.
//
// §8.13.5 marks `homework` (and by extension this sub-screen) "still" — the
// checking spinner is the one motion on screen, and it is classed the same
// as motion.ts's 'uploading'/'connecting' ambient surfaces: informational,
// brief, never attention-seeking, and it stops the moment the verdict is in.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';
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

/// What this screen hands back on a success, from EITHER path. `problems`
/// is null for the simulated path (there is no server response to carry —
/// the caller, homework_screen.dart, falls back to its own demo content)
/// and a real (possibly empty) list for the real path.
class HomeworkCaptureOutcome {
  const HomeworkCaptureOutcome({this.problems});
  final List<HomeworkProblemResult>? problems;
}

class CaptureGateScreen extends StatefulWidget {
  const CaptureGateScreen({
    super.key,
    this.onCaptured,
    this.simulateCapture,
    this.baseUrl,
    this.childId,
    this.sessionToken,
    this.httpClient,
    Future<Uint8List?> Function()? takePhoto,
  }) : takePhoto = takePhoto ?? _defaultTakePhoto;

  /// Called once on a successful capture, right before this screen pops
  /// itself with `true`. See [HomeworkCaptureOutcome] for what `null`
  /// problems means.
  final ValueChanged<HomeworkCaptureOutcome>? onCaptured;

  /// Test-only escape hatch: when set, this screen never touches the camera
  /// or the network, and behaves exactly as it always has (gates the
  /// returned [ImageStats] locally via homework_quality_gate.dart's port of
  /// gateImage()). capture_gate_test.dart / homework_screen_test.dart /
  /// retake_screen_test.dart all still use this.
  final ImageStats Function(int attempt)? simulateCapture;

  /// Real-path configuration. All three must be non-null for the real
  /// camera+network path to run; if [simulateCapture] is null AND any of
  /// these is missing too (e.g. this screen reached from a call site that
  /// hasn't been wired to a live session yet), this screen falls back to
  /// the same demo cycle it has always used rather than crashing on a
  /// missing baseUrl. See file header.
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;

  /// Injectable for tests of the real path (e.g. package:http/testing.dart's
  /// MockClient), matching child_home_live.dart's own pattern.
  final http.Client? httpClient;

  /// Stands in for a real camera capture; defaults to image_picker's real
  /// camera source. Returns null if the user cancels the picker.
  final Future<Uint8List?> Function() takePhoto;

  static Future<Uint8List?> _defaultTakePhoto() async {
    final XFile? file =
        await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (file == null) return null;
    return file.readAsBytes();
  }

  @override
  State<CaptureGateScreen> createState() => _CaptureGateScreenState();
}

class _CaptureGateScreenState extends State<CaptureGateScreen> {
  int _attempt = 0;
  bool _checking = false;
  String? _networkError;

  bool get _hasRealConfig =>
      widget.baseUrl != null && widget.childId != null && widget.sessionToken != null;

  Future<void> _takePhoto() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _networkError = null;
    });
    if (widget.simulateCapture == null && _hasRealConfig) {
      await _takePhotoReal();
    } else {
      await _takePhotoSimulated();
    }
  }

  Future<void> _takePhotoSimulated() async {
    // Stands in for the time a real capture + on-device measurement would
    // take — nothing is actually computed during this delay.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final ImageStats stats = (widget.simulateCapture ?? _defaultSimulateCapture)(_attempt);
    final QualityVerdict verdict = gateImage(stats);
    setState(() {
      _checking = false;
      _attempt += 1;
    });
    if (!mounted) return;
    if (verdict.ok) {
      widget.onCaptured?.call(const HomeworkCaptureOutcome());
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

  Future<void> _takePhotoReal() async {
    try {
      final Uint8List? bytes = await widget.takePhoto();
      if (bytes == null) {
        // User cancelled the picker — not a failure, just no photo taken.
        if (mounted) setState(() => _checking = false);
        return;
      }
      final OliveApi api =
          OliveApi(widget.baseUrl!, widget.sessionToken!, client: widget.httpClient);
      Map<String, dynamic> result;
      try {
        result = await api.captureHomework(widget.childId!, bytes);
      } finally {
        if (widget.httpClient == null) api.close();
      }
      if (!mounted) return;
      setState(() {
        _checking = false;
        _attempt += 1;
      });
      if (result['ok'] == true) {
        final List<HomeworkProblemResult> problems = ((result['problems'] as List?) ?? const [])
            .map((p) => HomeworkProblemResult.fromJson(p as Map<String, dynamic>))
            .toList();
        widget.onCaptured?.call(HomeworkCaptureOutcome(problems: problems));
        Navigator.of(context).pop(true);
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RetakeScreen(
          advice: (result['advice'] as String?) ?? 'One more try.',
          reason: _reasonFromWire(result['reason'] as String?),
          onRetry: () => Navigator.of(context).pop(),
        ),
      ));
    } catch (_) {
      // A real network/camera failure — surfaced plainly, not silently
      // swallowed and not pretended into a fabricated quality-gate verdict.
      if (!mounted) return;
      setState(() {
        _checking = false;
        _networkError = "Couldn't reach the server. Check your connection and try again.";
      });
    }
  }

  QualityFailure _reasonFromWire(String? reason) => switch (reason) {
        'too_small' => QualityFailure.tooSmall,
        'too_blurred' => QualityFailure.tooBlurred,
        'too_clipped' => QualityFailure.tooClipped,
        'too_skewed' => QualityFailure.tooSkewed,
        // An unrecognised reason from the server should never crash this
        // screen — falls back to the most common real-world cause rather
        // than a guessed one that would misdirect the advice shown.
        _ => QualityFailure.tooBlurred,
      };

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
            Text(
              'Hold the page flat inside the frame, then take the photo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
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
            const SizedBox(height: 16),
            Text(
              // Accurate either way, per file header: the real path only
              // ever runs when simulateCapture is unset AND a live
              // baseUrl/childId/sessionToken were actually supplied.
              widget.simulateCapture == null && _hasRealConfig
                  ? 'This photo is sent to the server for real recognition.'
                  : 'Demo capture — this preview build simulates the photo; there is '
                      'no camera wired up yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (_networkError != null) ...[
              const SizedBox(height: 8),
              Text(_networkError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
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
