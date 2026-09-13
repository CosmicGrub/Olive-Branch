// OLIVE BRANCH — first run, her name. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). §8.5.1.
//
// Renders MARKUP screen 'obName'. Spelling your own name is very often the
// first thing a child learns to write, so this is the correct opening: she
// is asked for the one thing she is already certain she can do.
//
// Her spelling stands — nothing here corrects, praises, or validates what she
// types (onboarding_logic.dart's acceptName()/resolveNameStep() never reject
// input, only truncate a paste past MAX_NAME_LENGTH). The mic button is an
// honest stub: no speech-to-text engine exists in this preview build, so
// tapping it says so rather than pretending to listen.
import 'package:flutter/material.dart';
import 'onboarding_logic.dart';
import 'onboarding_shared.dart';

class ObNameScreen extends StatefulWidget {
  const ObNameScreen({super.key, required this.fallbackName, required this.onContinue});

  /// What the guardian entered at setup. Used only if she skips (§8.5.1).
  final String fallbackName;
  final ValueChanged<NameStep> onContinue;

  @override
  State<ObNameScreen> createState() => _ObNameScreenState();
}

class _ObNameScreenState extends State<ObNameScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String typed) => widget.onContinue(resolveNameStep(typed, widget.fallbackName));

  void _tapMic() => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text("Saying your name isn't ready in this preview — type it instead."),
    duration: Duration(seconds: 3)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChildOnboardingScaffold(
      title: "What's your name?",
      subtitle: 'Type it however you like. You can change it any time.',
      onContinue: () => _finish(_controller.text),
      onSkip: () => _finish(''),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
          ),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _controller,
              autofocus: true,
              maxLength: maxNameLength,
              textCapitalization: TextCapitalization.words,
              onSubmitted: _finish,
              style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: 'your name',
              ),
            )),
            IconButton(
              iconSize: 30,
              tooltip: 'Say your name',
              icon: Icon(Icons.mic_none_rounded, color: scheme.primary),
              onPressed: _tapMic,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // Every letter she types lands here too, big and warm — a consequence
        // of her own typing (§8.13.1), never an animation that runs on its own.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            // A near-maxNameLength (24 char) single "word" at this fontSize is
            // wider than any of the four required viewports, including the
            // Fold5 cover screen (344 CSS px). Text has no width to wrap
            // against inside a Column, so unconstrained it renders as several
            // giant lines rather than one legible one. SizedBox + FittedBox
            // bounds the box and shrinks the glyph to fit instead — short
            // names still render at full, unscaled size.
            child: SizedBox(
              key: ValueKey(value.text),
              width: double.infinity,
              height: 56,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value.text.trim().isEmpty ? '👋' : value.text.trim(),
                  maxLines: 1,
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: scheme.primary),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
