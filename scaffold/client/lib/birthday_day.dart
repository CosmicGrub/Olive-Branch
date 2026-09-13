// OLIVE BRANCH — she places her birthday, the day. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). §8.7.2, §8.7.4.
//
// Renders MARKUP screen 'bdDay'. The real month grid (calendar_logic.dart's
// monthGrid() — the ONE month renderer in the product, §8.7.1), so she taps a
// day on a grid she can count rather than a bare number list.
//
// The year is the hard part, so she is never asked for it directly. Where a
// guardian's birth date is already on file the year is simply known and this
// screen resolves immediately. Otherwise it asks exactly one yes/no question
// inline — "Have you had your birthday this year?" — a question a
// five-year-old can answer with certainty (§8.7.2), rather than sending her
// to a separate screen this group was not asked to build.
//
// §8.7.4 — she is never told her tap was wrong. pickDay()'s 'no_such_day' is
// unreachable from the UI (only real day cells are tappable) and
// answerYearCheck()'s 'in_the_future' is handled silently: no error copy, she
// simply remains on the same question and may answer again.
import 'package:flutter/material.dart';
import 'calendar_logic.dart';
import 'onboarding_shared.dart';

class BirthdayDayScreen extends StatefulWidget {
  const BirthdayDayScreen({super.key, required this.month, required this.authoritative,
    required this.age, required this.onComplete, this.onSkip, this.now});

  final int month;
  /// Guardian-entered birth date, if any — authoritative for the record.
  final String? authoritative;
  final int? age;
  /// Fires once the picker reaches PickerStep.done.
  final ValueChanged<BirthdayPicker> onComplete;
  final VoidCallback? onSkip;
  final DateTime? now;

  @override
  State<BirthdayDayScreen> createState() => _BirthdayDayScreenState();
}

class _BirthdayDayScreenState extends State<BirthdayDayScreen> {
  late BirthdayPicker _picker = pickMonth(
    beginPicker(widget.authoritative, widget.age), widget.month);

  DateTime get _now => widget.now ?? DateTime.now();

  void _tapDay(int day) {
    final r = pickDay(_picker, day, _now);
    if (!r.ok) return; // no_such_day is unreachable from the grid; no_age has
                        // no display of blame either way — see file header.
    setState(() => _picker = r.picker!);
    if (_picker.step == PickerStep.done) widget.onComplete(_picker);
  }

  void _answerYearCheck(bool hadBirthdayThisYear) {
    final r = answerYearCheck(_picker, hadBirthdayThisYear, _now);
    if (!r.ok) return; // in_the_future — silently stays on the question.
    setState(() => _picker = r.picker!);
    if (_picker.step == PickerStep.done) widget.onComplete(_picker);
  }

  @override
  Widget build(BuildContext context) {
    final grid = monthGrid(2024, widget.month, today: _now); // leap-year ceiling, see calendar_logic.dart
    return ChildOnboardingScaffold(
      title: _picker.step == PickerStep.yearCheck ? 'One more thing' : 'Which day?',
      subtitle: _picker.step == PickerStep.yearCheck
        ? 'Have you already had your birthday this year?'
        : 'Tap the day.',
      // No continue button on this screen: tapping a day (or answering the
      // year check) resolves the step directly, so there is nothing for a
      // separate button to do.
      showContinueButton: false,
      onSkip: widget.onSkip,
      body: _picker.step == PickerStep.yearCheck ? _YearCheck(onAnswer: _answerYearCheck)
        : _DayGrid(grid: grid, onTap: _tapDay),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.grid, required this.onTap});
  final MonthGridResult grid;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Row(children: [for (final d in dowShort) Expanded(child: Center(
        child: Text(d, style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))))]),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        children: [for (final c in grid.cells) c.day == null
          ? const SizedBox.shrink()
          : _DayCell(day: c.day!, onTap: () => onTap(c.day!))],
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.onTap});
  final int day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      // §8.4's 48dp floor, declared to match the rest of the app — though on
      // a 7-column GridView.count, SliverGridRegularTileLayout.getBoxConstraints
      // hands every cell a *tight* BoxConstraints (min == max), so this
      // minWidth/minHeight can only ever raise the floor when the grid's own
      // per-cell math already clears it; it cannot force a wider cell than
      // the grid computed. On the narrowest audited viewport (Fold5 cover,
      // 344px) seven columns for a calendar week genuinely produce cells
      // under 48dp — the same trade-off already accepted for dense grids
      // elsewhere, not something a local constraint tweak can fix without
      // dropping to fewer columns (an information-architecture change this
      // pass isn't authorised to make).
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        alignment: Alignment.center,
        child: Text('$day', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ),
  );
}

class _YearCheck extends StatelessWidget {
  const _YearCheck({required this.onAnswer});
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: SizedBox(height: 56, child: OutlinedButton(
      onPressed: () => onAnswer(false), child: const Text('Not yet')))),
    const SizedBox(width: 16),
    Expanded(child: SizedBox(height: 56, child: FilledButton(
      onPressed: () => onAnswer(true), child: const Text('Yes')))),
  ]);
}
