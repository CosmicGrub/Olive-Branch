// OLIVE BRANCH — first run, who's here. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). §8.5.3.
//
// Renders MARKUP screen 'obWho'. §17.1 — with one guardian in the family
// graph, no choice is presented at all; she is TOLD who is here, never asked
// to pick between her parents. Where two have joined, both are selected by
// default and the last one cannot be deselected (§2.12 — she may never end up
// with nobody). A guardian who has not yet accepted their invitation appears
// greyed among the roster and nothing more: no nudge, no "invite them" copy.
import 'package:flutter/material.dart';
import 'onboarding_logic.dart';
import 'onboarding_shared.dart';

class ObWhoScreen extends StatefulWidget {
  const ObWhoScreen({super.key, required this.grownups, required this.onContinue});

  /// The FULL roster, joined and not — this screen itself filters to joined
  /// for the actual choice, per whoStep()'s own contract.
  final List<Grownup> grownups;
  final ValueChanged<WhoStep> onContinue;

  @override
  State<ObWhoScreen> createState() => _ObWhoScreenState();
}

class _ObWhoScreenState extends State<ObWhoScreen> {
  late WhoStep _step = whoStep(widget.grownups);

  List<Grownup> get _notYetJoined => widget.grownups.where((g) => !g.joined).toList();

  void _toggle(String userId) => setState(() => _step = toggleWho(_step, userId));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChildOnboardingScaffold(
      title: 'Who is here?',
      subtitle: _step.line,
      onContinue: () => widget.onContinue(_step),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        switch (_step.kind) {
          WhoKind.nobodyYet => _EmptyState(scheme: scheme),
          WhoKind.noChoice => _SingleGrownup(grownup: _step.only!, scheme: scheme),
          WhoKind.choose => Wrap(spacing: 12, runSpacing: 12, children: [
              for (final g in _step.options) TapChoice(
                key: ValueKey('who_${g.userId}'),
                label: g.label,
                minSide: 64,
                selected: _step.selected.contains(g.userId),
                onTap: () => _toggle(g.userId),
              ),
            ]),
        },
        if (_notYetJoined.isNotEmpty) ...[
          const SizedBox(height: 24),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final g in _notYetJoined) TapChoice(
              key: ValueKey('pending_${g.userId}'),
              label: g.label,
              minSide: 56,
              selected: false,
              dim: true,
              onTap: () {}, // not yet joined — informational only, no nudge.
            ),
          ]),
        ],
      ]),
    );
  }
}

class _SingleGrownup extends StatelessWidget {
  const _SingleGrownup({required this.grownup, required this.scheme});
  final Grownup grownup;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Center(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(radius: 34, backgroundColor: scheme.primary,
        child: Icon(Icons.favorite_rounded, color: scheme.onPrimary, size: 30)),
      const SizedBox(height: 12),
      Text(grownup.label, style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w800)),
    ]),
  ));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(children: [
      Icon(Icons.hourglass_top_rounded, size: 40, color: scheme.onSurfaceVariant),
      const SizedBox(height: 8),
      Text('Nobody is here yet.', style: Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: scheme.onSurfaceVariant)),
    ]),
  ));
}
