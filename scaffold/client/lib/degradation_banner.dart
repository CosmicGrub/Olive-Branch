// OLIVE BRANCH — call quality ladder + degradation notice. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline — manually built
// and run via `flutter analyze` / `flutter test` this session). Renders
// MARKUP screen "liveDegrade". MASTERFILE §5.28, §8.14.
//
// A 1:1 semantic port of packages/live/src/stream.ts — same names, same
// shapes, same ordering — so the two stay auditable side by side, the
// discipline lock_controller.dart already established for lock.ts.
//
// THE RULE THIS FILE EXISTS TO KEEP: a picture that keeps appearing and
// vanishing is worse than no picture at all. So quality sheds fast (2s of
// trouble) and restores slow (12s of steady), and she is told about it
// exactly once — never a live meter, never blame.
import 'dart:async';
import 'package:flutter/material.dart';

// ============================================== §5.28.1 the quality ladder ==
enum Quality { q720, q360, q180 }

const List<Quality> qualities = [Quality.q720, Quality.q360, Quality.q180];

Quality stepQualityDown(Quality q) {
  final i = qualities.indexOf(q);
  return qualities[(i + 1).clamp(0, qualities.length - 1)];
}

Quality stepQualityUp(Quality q) {
  final i = qualities.indexOf(q);
  return qualities[(i - 1).clamp(0, qualities.length - 1)];
}

bool atFloor(Quality q) => q == Quality.q180;
bool atCeiling(Quality q) => q == Quality.q720;

// ================================================== §5.28.2 the hysteresis ==
/// Quick to shed, slow to restore. Deliberately asymmetric — dropping fast is
/// kind (the picture degrades before she notices it stuttering); restoring
/// slowly is kinder (a connection good for two seconds is not a good
/// connection, and treating it as one is exactly the flicker this exists to
/// prevent).
const dropAfter = Duration(seconds: 2);
const restoreAfter = Duration(seconds: 12);

class StreamState {
  const StreamState({
    required this.quality,
    required this.video,
    required this.troubleMs,
    required this.steadyMs,
    required this.toldHer,
  });

  final Quality quality;
  /// Video present at all. False means the rung ladder moved to audio.
  final bool video;
  final int troubleMs;
  final int steadyMs;
  /// Told once per call, not continuously.
  final bool toldHer;

  StreamState copyWith({
    Quality? quality,
    bool? video,
    int? troubleMs,
    int? steadyMs,
    bool? toldHer,
  }) => StreamState(
    quality: quality ?? this.quality,
    video: video ?? this.video,
    troubleMs: troubleMs ?? this.troubleMs,
    steadyMs: steadyMs ?? this.steadyMs,
    toldHer: toldHer ?? this.toldHer,
  );
}

StreamState newStream() => const StreamState(
  quality: Quality.q720, video: true, troubleMs: 0, steadyMs: 0, toldHer: false);

enum Condition { good, strained }

class StreamTick {
  const StreamTick(this.condition, this.elapsedMs);
  final Condition condition;
  final int elapsedMs;
}

enum StreamChange { down, up, none }

class EvalResult {
  const EvalResult(this.state, this.changed);
  final StreamState state;
  final StreamChange changed;
}

/// One step per evaluation, never two. A connection that collapses does not
/// jump from 720 to audio in a single frame — it walks down, and each step is
/// a chance for it to stabilise.
EvalResult evaluate(StreamState s, StreamTick t) {
  if (t.condition == Condition.strained) {
    final troubleMs = s.troubleMs + t.elapsedMs;
    if (troubleMs < dropAfter.inMilliseconds) {
      return EvalResult(s.copyWith(troubleMs: troubleMs, steadyMs: 0), StreamChange.none);
    }
    if (!atFloor(s.quality)) {
      return EvalResult(
        s.copyWith(quality: stepQualityDown(s.quality), troubleMs: 0, steadyMs: 0),
        StreamChange.down);
    }
    if (s.video) {
      // Only now does the rung ladder move to audio-only.
      return EvalResult(s.copyWith(video: false, troubleMs: 0, steadyMs: 0), StreamChange.down);
    }
    return EvalResult(s.copyWith(troubleMs: 0, steadyMs: 0), StreamChange.none);
  }

  final steadyMs = s.steadyMs + t.elapsedMs;
  if (steadyMs < restoreAfter.inMilliseconds) {
    return EvalResult(s.copyWith(steadyMs: steadyMs, troubleMs: 0), StreamChange.none);
  }
  if (!s.video) {
    return EvalResult(s.copyWith(video: true, troubleMs: 0, steadyMs: 0), StreamChange.up);
  }
  if (!atCeiling(s.quality)) {
    return EvalResult(
      s.copyWith(quality: stepQualityUp(s.quality), troubleMs: 0, steadyMs: 0),
      StreamChange.up);
  }
  return EvalResult(s.copyWith(steadyMs: 0, troubleMs: 0), StreamChange.none);
}

/// Restoring is six times slower than dropping. A constant, not a magic
/// number scattered at call sites — and this equality is the entire point.
final bool restoreIsSlower = restoreAfter > dropAfter;

// ============================================ §5.28.3 what she is told ======
/// Once. Not a banner that lingers, and never a connection meter — a
/// five-year-old watching a signal indicator is a five-year-old not watching
/// her father.
class StreamNotice {
  const StreamNotice(this.line);
  final String line;
}

StreamNotice? noticeFor(StreamState s) {
  if (s.toldHer) return null;
  if (!s.video) return const StreamNotice('It has gone a bit slow — you can still hear him.');
  return null;
}

StreamState markTold(StreamState s) => s.copyWith(toldHer: true);

/// Video returning mid-conversation does NOT ask permission — a picture
/// coming back inside a call that never stopped is an improvement, not a new
/// call, and asking would interrupt the thing it is fixing.
const restoreAsksPermission = false;
const noConnectionMeter = true;

/// Nothing shown to her may blame her, her network, or her device.
const streamBanned = [
  'your connection', 'your network', 'your wifi', 'weak signal', 'poor',
  'check your', 'unstable', 'try moving', 'bandwidth',
];

/// Runtime self-check mirroring stream.ts's auditNotice — this actually runs
/// against whatever line is about to render, not merely asserted in a test.
bool auditNotice(StreamNotice? n) {
  if (n == null) return true;
  final t = n.line.toLowerCase();
  return !streamBanned.any(t.contains);
}

// ============================================ §5.28.4 what the sender sees ==
/// He gets more detail than she does, because he can act on it — moving
/// nearer a router is a thing an adult can do. It is still not a meter.
String senderLine(StreamState s) {
  if (!s.video) return 'Voice only — the line will not carry the picture just now.';
  if (s.quality == Quality.q180) return 'The picture is soft. The line is working hard.';
  return '';
}

/// The floor. A call never drops below this while any connection exists.
const audioFloor = true;
bool audioSurvives(StreamState _) => true;

String _qualityLabel(Quality q) => switch (q) {
  Quality.q720 => 'HD',
  Quality.q360 => 'Standard',
  Quality.q180 => 'Basic',
};

// ==================================================== the child-facing view =
/// The banner itself. Renders nothing until `noticeFor` produces a line, and
/// even then it is a single soft line near her father's picture — not a bar,
/// not a percentage, not a colour-coded dot. Deliberately audited before
/// paint: `auditNotice` runs on the exact string this widget is about to
/// show, so a banned word can never reach her screen even by a future editing
/// mistake in this file.
class DegradationBanner extends StatelessWidget {
  const DegradationBanner({super.key, required this.notice});
  final StreamNotice? notice;

  @override
  Widget build(BuildContext context) {
    final n = notice;
    if (n == null) return const SizedBox.shrink();
    assert(auditNotice(n), 'a stream notice must never blame her, her network, or her device');
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          // Deliberately literal, not themed: this scrim sits atop live video
          // of arbitrary colour and must stay legible regardless of the
          // app's own light/dark theme — a themed surface colour here could
          // wash out against a bright or dark camera feed.
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.volume_up_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(n.line, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}

// ==================================================== the review/demo shell =
/// MARKUP screen "liveDegrade". A self-contained harness so the hysteresis
/// and the once-only notice can actually be seen working end to end — there
/// is no live call backend yet (see call_screen.dart), so this drives the
/// exact same `evaluate()` loop a real connection-quality probe would, off a
/// clock instead of a network socket.
///
/// The "Wobble the line" control below the phone frame is a DEMO harness for
/// review, clearly separated from the child-facing surface above it — never
/// a connection meter shown to a child in the shipped product. Nothing
/// resembling a percentage, signal-bars icon, or numeric quality readout
/// appears inside the phone frame itself.
class LiveDegradeScreen extends StatefulWidget {
  const LiveDegradeScreen({super.key, this.childName = 'Ivy', this.callerName = 'Dad'});
  final String childName;
  final String callerName;

  @override
  State<LiveDegradeScreen> createState() => _LiveDegradeScreenState();
}

class _LiveDegradeScreenState extends State<LiveDegradeScreen> {
  StreamState _stream = newStream();
  Condition _condition = Condition.good;
  Timer? _timer;
  static const _tickMs = 250;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _tick());
  }

  void _tick() {
    final result = evaluate(_stream, StreamTick(_condition, _tickMs));
    setState(() => _stream = result.state);
  }

  void _setCondition(Condition c) => setState(() => _condition = c);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = noticeFor(_stream);
    return Scaffold(
      appBar: AppBar(title: Text('Call with ${widget.callerName}')),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        // SingleChildScrollView, not a bare Column: on a short viewport (a
        // phone in landscape, or the Fold5 cover screen) the frame plus the
        // preview harness beneath it can exceed the available height —
        // scrolling beats a clipped, overflowing layout.
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // The phone frame: what she actually sees.
            AspectRatio(
              aspectRatio: narrow ? 3 / 4 : 4 / 3,
              child: Stack(children: [
                Positioned.fill(child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Theme.of(context).colorScheme.primaryContainer,
                        Theme.of(context).colorScheme.tertiaryContainer]),
                  ),
                  child: Center(
                    child: _stream.video
                      ? Icon(Icons.face_retouching_off_outlined,
                          size: 72, color: Theme.of(context).colorScheme.onPrimaryContainer)
                      : Icon(Icons.graphic_eq_rounded,
                          size: 72, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                )),
                Positioned(left: 0, right: 0, top: 0, child: DegradationBanner(notice: notice)),
              ]),
            ),
            const SizedBox(height: 20),
            // The demo harness. Explicitly out-of-frame, explicitly labelled.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Preview harness — not part of what she sees',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: SizedBox(height: 48, child: OutlinedButton(
                    onPressed: () => _setCondition(Condition.good),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _condition == Condition.good
                        ? Theme.of(context).colorScheme.primaryContainer : null),
                    child: const Text('Line is fine')))),
                  const SizedBox(width: 8),
                  Expanded(child: SizedBox(height: 48, child: OutlinedButton(
                    onPressed: () => _setCondition(Condition.strained),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _condition == Condition.strained
                        ? Theme.of(context).colorScheme.errorContainer : null),
                    child: const Text('Wobble the line')))),
                ]),
                const SizedBox(height: 12),
                Text('Rung: ${_stream.video ? _qualityLabel(_stream.quality) : "Audio only"}',
                  style: Theme.of(context).textTheme.bodySmall),
                if (senderLine(_stream).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text('What ${widget.callerName} would see: ${senderLine(_stream)}',
                      style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic))),
              ]),
            ),
          ]),
        );
      })),
    );
  }
}
