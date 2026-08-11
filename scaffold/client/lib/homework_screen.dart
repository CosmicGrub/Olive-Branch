// OLIVE BRANCH — homework helper. MASTERFILE §9.1, §8.13.5, §20.2b. Renders
// MARKUP screen 'homework'. UNVERIFIED against a real device/camera — see
// the file-wide convention this codebase uses for exactly this caveat.
//
// "Photograph the sheet; the quality gate refuses blur and skew before OCR
// ever runs." The capture half is capture_gate.dart pushed from the button
// below; this file is what she sees before and after that gate passes.
//
// §20.2b's own "OCR: Homework capture specified, not built" gap is closed:
// when capture_gate.dart's REAL path ran (see that file's header — needs a
// live baseUrl/childId/sessionToken), the "recognized problems" below are
// the server's own real OCR output (packages/homework/src/capture-route.ts)
// and each hint has already been through the real, server-side guardHint()
// (packages/homework/src/capture.ts). `_demoProblems` below still exists,
// DEMOTED to exactly one job: the fallback content shown when capture ran
// on the SIMULATED path (no live backend configured, or a test's own
// [CaptureGateScreen.simulateCapture] override) — there is no server
// response to show in that case, so this file's own local guardHint() port
// (homework_quality_gate.dart) still runs against canned text, same as
// before, including the deliberately-leaking half of the pair so the guard
// stays demonstrably load-bearing on that path too.
//
// §9.1's tutor guard is an OUTPUT guard, not a prompt: whatever produced a
// hint, only a vetted hint or the same fixed safe fallback ever reaches
// her — she is never shown *that* something was refused, only ever a hint,
// because the failure mode this guards against is a tired parent reading a
// leaked answer out loud, not a curious child learning the guard exists.
// §9.1 also requires AI assistance be "logged and visible, never silent" —
// so every accepted hint is labelled "AI hint" on screen, not slipped in
// as if a person wrote it. That labelling is doubly honest on the real path:
// hints.ts's own header is explicit that the generator is rule-based
// pattern-matching, not an AI model — there is no LLM wired into this
// repository anywhere (no API key configured for one) — but the "AI HINT"
// label is kept as-is here because that is this screen's existing, tested
// vocabulary for "assistance a person didn't personally write", which a
// rule-based generator's output still is.
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
import 'package:http/http.dart' as http;
import 'api_client.dart';
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

/// Fallback-only canned "recognized problems" — see file header. Used ONLY
/// when this screen's own capture ran the simulated path, never when a real
/// server response is available.
const List<_DemoProblem> _demoProblems = <_DemoProblem>[
  _DemoProblem('6 x 7', 'Try skip-counting by 7, six times.', 'The answer is 42.'),
  _DemoProblem('3/4 + 1/4', 'What do the bottom numbers need to match before you can add?',
      "It's 1."),
  _DemoProblem('12 - 5', 'Count backwards from 12, five times, on your fingers.',
      'Just write 7.'),
];

class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({
    super.key,
    this.childName = 'Ivy',
    this.baseUrl,
    this.childId,
    this.sessionToken,
    this.httpClient,
  });
  final String childName;

  /// Real-path configuration, threaded straight through to
  /// CaptureGateScreen — see that file's header for what happens when these
  /// are null (falls back to the simulated demo cycle, same as always).
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  final http.Client? httpClient;

  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  bool _captured = false;

  /// Non-null only when capture_gate.dart's REAL path produced a real
  /// server response. Null after a SIMULATED capture — homework_screen's
  /// own _demoProblems fallback is what renders in that case.
  List<HomeworkProblemResult>? _realProblems;

  /// Which DEMO-path problems currently show a revealed hint (index ->
  /// verdict) — the real path never needs this: a real problem's hint is
  /// already guarded server-side and is shown as soon as it's tapped open,
  /// with no separate guard call to make client-side.
  final Map<int, HintVerdict> _revealed = <int, HintVerdict>{};

  /// Which REAL-path problems currently show a revealed hint (index ->
  /// visible).
  final Set<int> _realRevealed = <int>{};

  int get _problemCount => _realProblems?.length ?? _demoProblems.length;

  Future<void> _startCapture() async {
    final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => CaptureGateScreen(
        baseUrl: widget.baseUrl,
        childId: widget.childId,
        sessionToken: widget.sessionToken,
        httpClient: widget.httpClient,
        onCaptured: (outcome) => _realProblems = outcome.problems,
      )));
    if (ok == true && mounted) setState(() => _captured = true);
  }

  void _revealHint(int i, {required bool leaky}) {
    final _DemoProblem p = _demoProblems[i];
    final Problem problem = Problem(text: p.text, forbiddenAnswers: forbiddenFor(p.text));
    final String modelOutput = leaky ? p.leakyHint : p.goodHint;
    final HintVerdict verdict = guardHint(modelOutput, problem);
    setState(() => _revealed[i] = verdict);
  }

  void _revealRealHint(int i) => setState(() => _realRevealed.add(i));

  @override
  Widget build(BuildContext context) {
    final int fadeMs = durationFor(quietnessOf('homework'), crossfadeMs);
    return Scaffold(
      appBar: AppBar(title: const Text('Homework')),
      // ListView, not a fixed Column — matches emergency_card.dart's own
      // reasoning: generous text can exceed a small phone's viewport.
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Let's get your worksheet", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Take a clear photo of the page and we\'ll help you spot where '
              'to start — never the answers themselves.',
              style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft,
                        child: Text('Photo looks good — here\'s what we found:',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600))),
                      const SizedBox(height: 12),
                      for (int i = 0; i < _problemCount; i++)
                        _ProblemCard(
                          // Real path: the server's own OCR'd text. Demo
                          // fallback (simulated capture only): canned text.
                          text: _realProblems != null
                              ? _realProblems![i].text
                              : _demoProblems[i].text,
                          verdict: _realProblems != null
                              // Already guarded server-side (capture-
                              // route.ts's own guardHint() call) — wrapping
                              // it as HintVerdict.ok reuses _HintBubble's
                              // existing rendering/labelling unchanged
                              // rather than duplicating it for this path.
                              ? (_realRevealed.contains(i)
                                  ? HintVerdict.ok(_realProblems![i].hint)
                                  : null)
                              : _revealed[i],
                          fadeMs: fadeMs,
                          onHint: () => _realProblems != null
                              ? _revealRealHint(i)
                              // A visible dev toggle would leak the
                              // mechanism to a child; alternating
                              // leaky/good by index instead keeps this row
                              // exercising both guard paths without any UI
                              // that says "try to break it".
                              : _revealHint(i, leaky: i.isOdd),
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
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
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
          Text('AI HINT', style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6, fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.7))),
          const SizedBox(height: 4),
          Text(shown, style: Theme.of(context).textTheme.bodyLarge),
        ])),
      ]),
    );
  }
}
