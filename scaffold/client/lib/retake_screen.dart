// OLIVE BRANCH — homework retake. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). MASTERFILE §9.1, §8.13.5. Renders MARKUP screen 'retake'.
//
// "Plain, actionable advice — 'Hold still and try again.' No jargon." The
// copy shown here is EXACTLY homework_quality_gate.dart's `advice` string —
// this screen has no business inventing its own wording, same discipline
// capture.ts states for itself ("the advice is the gate's own, unchanged").
// It never renders the QualityFailure enum value, never says "blur",
// "skew", "resolution", or "threshold" — those are this file's business,
// not a nine-year-old's.
//
// §8.13.5 marks `homework` a "still" surface — "the one surface in the
// product that asks her to concentrate" — so nothing here moves on its own.
// The only motion is the crossfade-in on arrival, sized by
// motion_rules.dart's durationFor(quietnessOf('homework'), ...), which
// collapses to a plain instant appearance rather than a slide or a bounce.
import 'package:flutter/material.dart';
import 'homework_quality_gate.dart';
import 'motion_rules.dart';

class RetakeScreen extends StatefulWidget {
  const RetakeScreen({super.key, required this.advice, required this.reason, required this.onRetry});

  /// homework_quality_gate.dart's own advice string. Rendered verbatim.
  final String advice;

  /// Kept for tests and analytics — never rendered as text on this screen.
  final QualityFailure reason;
  final VoidCallback onRetry;

  @override
  State<RetakeScreen> createState() => _RetakeScreenState();
}

class _RetakeScreenState extends State<RetakeScreen> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    // A still surface never cuts, per motion_rules.dart — it crossfades in,
    // even when that crossfade collapses toward 0ms.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final int fadeMs = durationFor(quietnessOf('homework'), crossfadeMs);
    return Scaffold(
      body: SafeArea(
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: Duration(milliseconds: fadeMs),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primaryContainer),
                    child: Icon(Icons.camera_alt_outlined, size: 44,
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 24),
                  Text('One more try', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(widget.advice, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, height: 1.4)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: FilledButton(
                      key: const Key('retakeTryAgain'),
                      onPressed: widget.onRetry,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                      child: const Text('Try again', style: TextStyle(fontSize: 17)))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
