// OLIVE BRANCH — her birthday, marked. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). §8.7.5, §8.7.6, MASTERFILE P2.
//
// Renders MARKUP screen 'bdMarked'. Confirms the permanent calendar marker
// markBirthday() just created — `deletableByGuardian: false`, because a
// birthday is a fact, not a preference (§8.7.5).
//
// P2 — celebrated without a score. There is deliberately no streak, no
// counter, no "day X of Y", and no countdown on this screen: this is the
// confirmation moment itself, not the ongoing "sleeps until" surface that
// belongs on her calendar elsewhere. Motion is a single consequence of her
// just having placed the date (a 300ms pop, once) — never a loop, per
// §8.13.1; the sparkles around the card are static, not animated confetti.
import 'package:flutter/material.dart';
import 'calendar_logic.dart';

class BirthdayMarkedScreen extends StatefulWidget {
  const BirthdayMarkedScreen({super.key, required this.childId, required this.childName,
    required this.picker, required this.colourId, required this.onDone, this.now});

  final String childId;
  final String childName;
  /// Resolved picker (PickerStep.done) from birthday_month.dart / birthday_day.dart.
  final BirthdayPicker picker;
  /// Her colour, if chosen — an allowed placement under §8.6.2's budget.
  final String? colourId;
  final VoidCallback onDone;
  final DateTime? now;

  @override
  State<BirthdayMarkedScreen> createState() => _BirthdayMarkedScreenState();
}

class _BirthdayMarkedScreenState extends State<BirthdayMarkedScreen> with SingleTickerProviderStateMixin {
  // Built eagerly in initState, not as a lazy `late` field initializer: the
  // _Incomplete branch below never reads _pop, and a lazy initializer left
  // untouched until dispose() tries to construct a fresh AnimationController
  // against an already-deactivated element — "Looking up a deactivated
  // widget's ancestor is unsafe." Caught by birthday_marked_test.dart's
  // unresolved-picker case, not by inspection.
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = (widget.now ?? DateTime.now()).toIso8601String();
    final outcome = markBirthday(widget.childId, widget.picker, widget.colourId, at);
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.colourId != null ? scheme.primary : scheme.tertiary;

    return Scaffold(
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: outcome.ok
          ? ScaleTransition(
              scale: CurvedAnimation(parent: _pop, curve: Curves.easeOutBack),
              child: _Marked(event: outcome.event!, childName: widget.childName,
                accent: accent, onDone: widget.onDone))
          // Honest fallback: reachable only if this screen is wired without a
          // resolved picker, which shouldn't happen — but nothing here may
          // pretend a birthday was marked when it was not (MASTERFILE §0).
          : _Incomplete(onDone: widget.onDone),
      ))),
    );
  }
}

class _Marked extends StatelessWidget {
  const _Marked({required this.event, required this.childName, required this.accent,
    required this.onDone});
  final BirthdayEvent event;
  final String childName;
  final Color accent;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Stack(alignment: Alignment.center, children: [
      // Static sparkle decorations — festive, not looping (§8.13.1).
      const Positioned(top: -6, left: 8, child: Icon(Icons.auto_awesome, size: 20, color: Colors.amber)),
      const Positioned(top: 4, right: 4, child: Icon(Icons.auto_awesome, size: 14, color: Colors.amber)),
      Container(
        width: 168, height: 168,
        decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.15),
          border: Border.all(color: accent, width: 4)), // avatar_ring placement
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${event.day}', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: accent)),
          Text(months[event.month - 1].name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ])),
      ),
    ]),
    const SizedBox(height: 24),
    Text('My birthday', style: Theme.of(context).textTheme.headlineSmall
      ?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    Text('Every year, this day is $childName\'s.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    const SizedBox(height: 32),
    SizedBox(width: double.infinity, height: 56, child: FilledButton(
      onPressed: onDone,
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16))),
      // Deliberately not a textTheme role — see onboarding_shared.dart's
      // continue button for why button labels keep a plain, colorless
      // TextStyle rather than one with Typography.material2021's baked-in
      // onSurface color.
      child: const Text('All done!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
  ]);
}

class _Incomplete extends StatelessWidget {
  const _Incomplete({required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.cake_outlined, size: 40, color: scheme.onSurfaceVariant),
      const SizedBox(height: 8),
      Text("We don't have your birthday yet.",
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      FilledButton(onPressed: onDone, child: const Text('Continue')),
    ]);
  }
}
