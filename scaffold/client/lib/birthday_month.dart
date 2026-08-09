// OLIVE BRANCH — she places her birthday, month first. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). §8.7.2.
//
// Renders MARKUP screen 'bdMonth'. Twelve named tiles, not a scroller — a
// six-year-old finding a date six years in the past is genuinely hard, but
// she almost certainly knows the month. When a guardian's birth date is on
// file, the right tile carries a static highlight (never a pulsing one:
// §8.13.1 permits ambient motion only on four named "the movement IS the
// information" surfaces, and a birthday hint isn't one of them). shouldHint()
// withdraws the highlight entirely from age nine — scaffolding that fades,
// per §21.5.
import 'package:flutter/material.dart';
import 'calendar_logic.dart';
import 'onboarding_shared.dart';

class BirthdayMonthScreen extends StatefulWidget {
  const BirthdayMonthScreen({super.key, required this.birthDate, required this.age,
    required this.onMonthPicked});

  /// Guardian-entered birth date, if any (authoritative — §8.5.2).
  final String? birthDate;
  final int? age;
  final ValueChanged<int> onMonthPicked;

  @override
  State<BirthdayMonthScreen> createState() => _BirthdayMonthScreenState();
}

class _BirthdayMonthScreenState extends State<BirthdayMonthScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final hinted = shouldHint(widget.birthDate, widget.age) ? hintMonth(widget.birthDate) : null;
    return ChildOnboardingScaffold(
      title: 'When is your birthday?',
      subtitle: "Find the month you were born.",
      continueEnabled: _selected != null,
      onContinue: () => widget.onMonthPicked(_selected!),
      body: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [for (final m in months) _MonthTile(
          key: ValueKey('month_${m.index}'),
          meta: m,
          selected: _selected == m.index,
          hinted: hinted == m.index,
          onTap: () => setState(() => _selected = m.index),
        )],
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({super.key, required this.meta, required this.selected,
    required this.hinted, required this.onTap});

  final MonthMeta meta;
  final bool selected;
  final bool hinted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color fill = selected ? scheme.primary
      : hinted ? scheme.primaryContainer
      : scheme.surfaceContainerHighest;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          decoration: hinted && !selected
            ? BoxDecoration(borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary, width: 2))
            : null,
          alignment: Alignment.center,
          child: Text(meta.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? scheme.onPrimary : scheme.onSurface)),
        ),
      ),
    );
  }
}
