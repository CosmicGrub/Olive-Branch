// OLIVE BRANCH — first run, her age. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). §8.5.2.
//
// Renders MARKUP screen 'obAge'. Age sets the §21 capability rungs and the
// ping band (§9.9) — it is not a reading test, so she taps a number rather
// than typing one.
//
// She taps; onboarding_logic.dart's acceptAge() decides what it means. A
// guardian-entered birth date is ALWAYS authoritative — nothing tapped here
// can raise a gate, and this screen never surfaces `disagrees` to her, never
// shows her the guardian's date, and carries no path to any guardian
// capability. Tapping a big number is a UX convenience, never
// self-authorization — the same principle §8.5.0's ENTRY_CHOICE_GRANTS_NO_AUTHORITY
// applies one screen earlier.
import 'package:flutter/material.dart';
import 'onboarding_logic.dart';
import 'onboarding_shared.dart';

class ObAgeScreen extends StatefulWidget {
  const ObAgeScreen({super.key, required this.birthDate, required this.onContinue, this.now});

  /// Guardian-entered birth date, if any. Authoritative — see acceptAge().
  final String? birthDate;
  final ValueChanged<AgeStep> onContinue;
  /// Injectable for deterministic tests; defaults to the real clock.
  final DateTime? now;

  @override
  State<ObAgeScreen> createState() => _ObAgeScreenState();
}

class _ObAgeScreenState extends State<ObAgeScreen> {
  int? _tapped;

  @override
  Widget build(BuildContext context) {
    return ChildOnboardingScaffold(
      title: 'How old are you?',
      subtitle: 'Tap the number.',
      continueEnabled: true,
      onContinue: () => widget.onContinue(
        acceptAge(_tapped, widget.birthDate, widget.now ?? DateTime.now())),
      onSkip: () => widget.onContinue(
        acceptAge(null, widget.birthDate, widget.now ?? DateTime.now())),
      body: Wrap(
        spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
        children: [for (var a = minAge; a <= maxAge; a++) TapChoice(
          key: ValueKey('age_$a'),
          label: '$a',
          selected: _tapped == a,
          minSide: 56,
          onTap: () => setState(() => _tapped = a),
        )],
      ),
    );
  }
}
