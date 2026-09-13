// OLIVE BRANCH — shared chrome for the child's first-run flow. UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline). §8.5.
//
// One background, one continue-button pattern, one skip-link pattern, reused
// by onboarding_name.dart / onboarding_age.dart / onboarding_who.dart /
// colour_pick.dart / birthday_month.dart / birthday_day.dart /
// birthday_marked.dart so the seven steps of one flow don't each reinvent
// their own chrome and drift apart visually. Not itself a MARKUP screen.
//
// §8.1 — no settings affordance lives here, and none should ever be added:
// every screen built on this scaffold inherits that absence for free.
// §8.4 — the continue button and skip link are both sized to at least 48dp.
import 'package:flutter/material.dart';

class ChildOnboardingScaffold extends StatelessWidget {
  const ChildOnboardingScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.onContinue,
    this.continueLabel = 'Next',
    this.onSkip,
    this.continueEnabled = true,
    this.showContinueButton = true,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  /// Required unless [showContinueButton] is false — a screen that advances
  /// itself on every tap (e.g. birthday_day.dart) hides this entirely rather
  /// than showing a button that does nothing.
  final VoidCallback? onContinue;
  final String continueLabel;
  final VoidCallback? onSkip;
  final bool continueEnabled;
  final bool showContinueButton;
  /// Her colour, if already chosen upstream — a `header_flourish`, one of the
  /// allowed placements under §8.6.2's budget.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [scheme.primaryContainer.withValues(alpha: 0.55), scheme.surface])),
        child: SafeArea(child: LayoutBuilder(builder: (context, constraints) =>
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 44, height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: (accent ?? scheme.primary).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3)))),
                Text(title, style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 24),
                body,
                if (showContinueButton) ...[
                  const SizedBox(height: 28),
                  SizedBox(height: 56, child: FilledButton(
                    onPressed: continueEnabled ? onContinue : null,
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
                    child: Text(continueLabel,
                      // Deliberately not a textTheme role: FilledButton relies on
                      // no explicit color here so its own disabled-state styling
                      // (dimmed foreground) still applies. A themed TextStyle's
                      // baked-in onSurface color (Typography.material2021) would
                      // override that and make a disabled button look active.
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
                ],
                if (onSkip != null) ...[
                  const SizedBox(height: 8),
                  Center(child: TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    child: const Text('Skip for now'))),
                ],
              ])))),
        ),
      ),
    );
  }
}

/// A round, tappable choice tile — the shared shape behind the age numbers,
/// the month names, and the day grid. 48dp+ minimum on every axis (§8.4).
class TapChoice extends StatelessWidget {
  const TapChoice({super.key, required this.label, required this.selected,
    required this.onTap, this.minSide = 52, this.dim = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double minSide;
  /// Greyed presentation for e.g. a not-yet-joined grownup (§8.5.3) — shown,
  /// never nudged.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minSide, minHeight: minSide),
          child: Center(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Opacity(opacity: dim ? 0.45 : 1, child: Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? scheme.onPrimary : scheme.onSurface))))),
        ),
      ),
    );
  }
}
