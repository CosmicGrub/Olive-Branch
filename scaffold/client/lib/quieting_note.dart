// OLIVE BRANCH — child shell, the quieting. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline). MASTERFILE §21.5. Renders MARKUP
// screen 'quieting'.
//
// A 1:1 port of the QUIETING table and its pure helpers from
// packages/maturation/src/maturation.ts, with new child-facing copy — the TS
// `why` strings are written for the engineers reading the spec, not for a
// nine-year-old, so this file carries its own `childWhy` text alongside the
// ported `feature`/`fadesAt` data rather than rendering the internal prose
// verbatim.
//
// P2, the reason this screen exists at all: a "some things got quieter"
// screen is one bad sentence away from becoming "you haven't opened this in
// N days" — punitive engagement-scoring shown to a child, which is
// permanently prohibited. So this file is built the other way around: every
// item here fades because of HER AGE, never her activity, there is no
// last-opened date anywhere in this file, and the copy states that
// explicitly rather than leaving it to be inferred.
import 'package:flutter/material.dart';

// ========= ported from packages/maturation/src/maturation.ts (QUIETING) ====
class ScaffoldItem {
  const ScaffoldItem(this.feature, this.fadesAt, this.why, this.childLabel, this.childWhy);
  final String feature;
  final int fadesAt;
  /// The TS doc-comment reasoning, kept verbatim for anyone auditing this
  /// port against maturation.ts. Not shown to the child — see childWhy.
  final String why;
  final String childLabel;
  final String childWhy;
}

const quieting = <ScaffoldItem>[
  ScaffoldItem('sleeps_countdown', 11,
    'She can read a calendar. Counting sleeps for her is talking down.',
    'Counting sleeps until visits',
    "You can read a calendar now, so that's just there when you want it."),
  ScaffoldItem('prompt_decks', 13,
    'A thirteen-year-old does not need a card telling her what to say to her father.',
    'Idea cards for what to say',
    'You always know what to say to your own family.'),
  ScaffoldItem('send_time_guard_child_side', 14,
    'She knows what time it is where he lives.',
    "Reminders about their time zone",
    'You already know what time it is where they are.'),
  ScaffoldItem('game_prominence', 14,
    'Games move to the back of the app, not out of it.',
    'Games front and center',
    "Still here — just tucked a little further back now."),
  ScaffoldItem('day_part_labels', 15,
    'Superseded by her published availability.',
    "Labels like 'school time' and 'bedtime'",
    'Replaced by the times you set yourself now.'),
  ScaffoldItem('handicap_offer', 15,
    'Offering to handicap a parent to a fifteen-year-old reads as pity.',
    'An easier version when you play games together',
    "You don't need a head start anymore."),
  ScaffoldItem('ritual_reminders', 16,
    'A ritual she still wants at sixteen is one she keeps herself.',
    'Reminders for your standing calls',
    'A ritual you still want, you keep going yourself now.'),
];

const permanentChildLabels = <String>['Your calendar', 'Your calls', 'Your archive', 'Your journal'];

List<ScaffoldItem> scaffoldsShowingAt(int age) => quieting.where((s) => age < s.fadesAt).toList();
List<ScaffoldItem> scaffoldsFadedAt(int age) => quieting.where((s) => age >= s.fadesAt).toList();

bool showsScaffold(String feature, int age) {
  for (final s in quieting) {
    if (s.feature == feature) return age < s.fadesAt;
  }
  return true;
}
// =============================================================================

class QuietingScreen extends StatelessWidget {
  const QuietingScreen({super.key, required this.childName, required this.age});
  final String childName;
  final int age;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = scaffoldsFadedAt(age);
    final showing = scaffoldsShowingAt(age);
    return Scaffold(
      appBar: AppBar(title: const Text('Growing up here')),
      // SingleChildScrollView + Column, NOT ListView — a sliver list only
      // realizes children near the viewport, which would silently drop
      // sections scrolled below the fold from the widget tree. Same fix
      // message_banking.dart already documents for the same bug class.
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.spa_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(
                "Some things in the app get quieter as you get older, $childName. That's just "
                "what happens as you grow — it isn't about anything you did or didn't do.",
                style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSecondaryContainer))),
            ])),
          if (faded.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionHeader('Quieter now'),
            for (final s in faded) _QuietingTile(item: s, faded: true),
          ],
          if (showing.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _SectionHeader('Still here for now'),
            for (final s in showing) _QuietingTile(item: s, faded: false),
          ],
          const SizedBox(height: 24),
          const _SectionHeader('Never goes away'),
          Card(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final label in permanentChildLabels)
                Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(Icons.favorite_border, size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  ])),
            ]))),
        ]),
      )),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge
      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3)));
}

class _QuietingTile extends StatelessWidget {
  const _QuietingTile({required this.item, required this.faded});
  final ScaffoldItem item;
  final bool faded;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: faded ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.childLabel, style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(item.childWhy, style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}
