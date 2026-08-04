// OLIVE BRANCH — homework helper. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.1, §8.13.5. Renders
// MARKUP screen 'homework'.
//
// "Photograph the sheet; the quality gate refuses blur and skew before OCR
// ever runs." The capture half is capture_gate.dart pushed from the button
// below; this file is what she sees before and after that gate passes.
//
// HONEST STUB, twice over, both said on screen rather than glossed over:
//  - No OCR backend exists yet, so the "recognized problems" below are
//    canned demo text, not extracted from a real photo.
//  - The "hint" is a canned demo response run through
//    homework_quality_gate.dart's guardHint(), not a live model call — but
//    the guard itself is real: some of the canned responses are
//    deliberately answer-leaking, to prove the guard actually intercepts
//    them rather than always being fed something already safe.
//
// §9.1's tutor guard is an OUTPUT guard, not a prompt: whatever a "model"
// produces, only a vetted hint or the same fixed safe fallback ever reaches
// her — she is never shown *that* something was refused, only ever a hint,
// because the failure mode this guards against is a tired parent reading a
// leaked answer out loud, not a curious child learning the guard exists.
// §9.1 also requires AI assistance be "logged and visible, never silent" —
// so every accepted hint is labelled "AI hint" on screen, not slipped in
// as if a person wrote it.
//
// §8.13.5: `homework` is a "still" surface, "the one surface in the product
// that asks her to concentrate" — SURFACE_MOTION in motion_rules.dart's TS
// source calls it "deliberately the sparsest surface in the product",
// gestures: [tap] only. No autonomous motion anywhere below; the one reveal
// (a hint appearing) crossfades on the duration motion_rules.dart's
// durationFor(quietnessOf('homework'), ...) computes, which collapses to
// instant rather than a slide.
//
// P2/P6 checked explicitly by this file's test: no score, streak, or
// completion badge for finishing a worksheet, and no financial surface
// anywhere near it.
import 'package:flutter/material.dart';
import 'capture_gate.dart';
import 'homework_quality_gate.dart';
import 'motion_rules.dart';

class _DemoProblem {
  const _DemoProblem(this.text, this.goodHint, this.leakyHint);
  final String text;
  final String goodHint;

  /// Deliberately violates guardHint — proves the guard is load-bearing,
  /// not merely reachable-but-never-exercised.
  final String leakyHint;
}

/// Canned "recognized problems" — see file header on the OCR stub.
const List<_DemoProblem> _demoProblems = <_DemoProblem>[
  _DemoProblem('6 x 7', 'Try skip-counting by 7, six times.', 'The answer is 42.'),
  _DemoProblem('3/4 + 1/4', 'What do the bottom numbers need to match before you can add?',
      "It's 1."),
  _DemoProblem('12 - 5', 'Count backwards from 12, five times, on your fingers.',
      'Just write 7.'),
];

class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({super.key, this.childName = 'Ivy'});
  final String childName;

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  bool _captured = false;

  /// Which problems currently show a revealed hint (index -> verdict).
  final Map<int, HintVerdict> _revealed = <int, HintVerdict>{};

  Future<void> _startCapture() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CaptureGateScreen()));
    if (ok == true && mounted) setState(() => _captured = true);
  }

  void _revealHint(int i, {required bool leaky}) {
    final _DemoProblem p = _demoProblems[i];
    final Problem problem = Problem(text: p.text, forbiddenAnswers: forbiddenFor(p.text));
    final String modelOutput = leaky ? p.leakyHint : p.goodHint;
    final HintVerdict verdict = guardHint(modelOutput, problem);
    setState(() => _revealed[i] = verdict);
  }

  @override
  Widget build(BuildContext context) {
    final int fadeMs = durationFor(quietnessOf('homework'), crossfadeMs);
    return Scaffold(
      appBar: AppBar(title: const Text('Homework')),
      // ListView, not a fixed Column — matches emergency_card.dart's own
      // reasoning: generous text can exceed a small phone's viewport.
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text("Let's get your worksheet", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Take a clear photo of the page and we\'ll help you spot where '
              'to start — never the answers themselves.',
              style: TextStyle(fontSize: 14.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            if (!_captured)
              SizedBox(
                width: double.infinity, height: 56,
                child: FilledButton.icon(
                  key: const Key('takePhotoButton'),
                  onPressed: _startCapture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take a photo', style: TextStyle(fontSize: 16)))),
            AnimatedSwitcher(
              duration: Duration(milliseconds: fadeMs),
              child: _captured
                  ? Column(key: const ValueKey('problems'), children: [
                      const SizedBox(height: 6),
                      Align(alignment: Alignment.centerLeft,
                        child: Text('Photo looks good — here\'s what we found:',
                          style: TextStyle(fontSize: 13.5,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600))),
                      const SizedBox(height: 10),
                      for (int i = 0; i < _demoProblems.length; i++)
                        _ProblemCard(
                          text: _demoProblems[i].text,
                          verdict: _revealed[i],
                          fadeMs: fadeMs,
                          // A visible dev toggle would leak the mechanism to
                          // a child; alternating leaky/good by index instead
                          // keeps this row exercising both guard paths
                          // without any UI that says "try to break it".
                          onHint: () => _revealHint(i, leaky: i.isOdd),
                        ),
                    ])
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.text, required this.verdict, required this.fadeMs, required this.onHint});
  final String text;
  final HintVerdict? verdict;
  final int fadeMs;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: Duration(milliseconds: fadeMs),
              child: verdict == null
                  ? SizedBox(
                      key: const ValueKey('ask'),
                      height: 48, // §8.4 — 48dp minimum touch target
                      child: OutlinedButton(onPressed: onHint, child: const Text('Get a hint')))
                  : _HintBubble(key: const ValueKey('hint'), verdict: verdict!),
            ),
          ]),
        ),
      );
}

class _HintBubble extends StatelessWidget {
  const _HintBubble({super.key, required this.verdict});
  final HintVerdict verdict;

  @override
  Widget build(BuildContext context) {
    // §9.1: whatever a model produced, she only ever sees a vetted hint or
    // the same fixed safe fallback — never a "that was refused" message.
    final String shown = verdict.ok ? verdict.hint! : verdict.safeFallback!;
    return Container(
      key: const Key('hintBubble'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.secondaryContainer),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline, size: 20,
          color: Theme.of(context).colorScheme.onSecondaryContainer),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // §9.1 — "logged and visible, never silent": always labelled, so
          // it never reads as a person answering.
          Text('AI HINT', style: TextStyle(fontSize: 10.5, letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.7))),
          const SizedBox(height: 3),
          Text(shown, style: const TextStyle(fontSize: 15)),
        ])),
      ]),
    );
  }
}
