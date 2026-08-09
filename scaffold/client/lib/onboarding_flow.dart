// OLIVE BRANCH — onboarding flow, sequenced. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). Navigation-wiring-pass
// addition, not a MARKUP screen of its own.
//
// The onboarding group's own report is explicit that every first-run screen
// it built is "fully self-contained via constructor callbacks, so it can be
// sequenced either [name -> age -> colour -> birthday -> who, per
// onboarding.ts's advance()] or [name, age, who, colour, per the assignment
// note's prose order] without any code changes" — this file is that
// sequencing glue, choosing the assignment's prose order.
//
// There is no real first-run detector in this preview build (see
// main.dart's own header on why EntryGate always renders both halves), so
// this screen is reached as a demo re-run from ChildMoreScreen ("Redo the
// welcome tour") rather than automatically on first launch.
//
// Each screen's onContinue/onComplete fires while it is still on screen; it
// does not pop itself (confirmed by reading onboarding_name.dart's
// _finish()). This file supplies that pop, once per step, so a step's
// result becomes the value its `Navigator.push` future resolves with.
import 'package:flutter/material.dart';
import 'birthday_day.dart';
import 'birthday_marked.dart';
import 'birthday_month.dart';
import 'calendar_logic.dart';
import 'colour_pick.dart';
import 'onboarding_age.dart';
import 'onboarding_logic.dart';
import 'onboarding_name.dart';
import 'onboarding_who.dart';

class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key, this.fallbackName = 'Ivy'});

  /// What the guardian entered at setup — used only if she skips the name
  /// step, matching ObNameScreen's own contract.
  final String fallbackName;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  bool _running = false;
  String? _lastChildName;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    final NavigatorState nav = Navigator.of(context);

    final NameStep? nameStep = await nav.push<NameStep>(MaterialPageRoute<NameStep>(
      builder: (c) => ObNameScreen(
        fallbackName: widget.fallbackName,
        onContinue: (step) => Navigator.of(c).pop(step),
      )));
    if (!mounted) return;
    if (nameStep == null) return setState(() => _running = false);
    final String childName = nameStep.spelled;

    final AgeStep? ageStep = await nav.push<AgeStep>(MaterialPageRoute<AgeStep>(
      builder: (c) => ObAgeScreen(
        birthDate: null,
        onContinue: (step) => Navigator.of(c).pop(step),
      )));
    if (!mounted) return;
    if (ageStep == null) return setState(() => _running = false);
    final int? age = effectiveAge(ageStep);

    final WhoStep? whoStepResult = await nav.push<WhoStep>(MaterialPageRoute<WhoStep>(
      builder: (c) => ObWhoScreen(
        grownups: const <Grownup>[
          Grownup(userId: 'dad', label: 'Dad', joined: true),
          Grownup(userId: 'mom', label: 'Mom', joined: false),
        ],
        onContinue: (step) => Navigator.of(c).pop(step),
      )));
    if (!mounted) return;
    if (whoStepResult == null) return setState(() => _running = false);

    final String? colourId = await nav.push<String?>(MaterialPageRoute<String?>(
      builder: (c) => ColourPickScreen(
        childName: childName,
        onContinue: (id) => Navigator.of(c).pop(id),
      )));
    if (!mounted) return;

    final int? month = await nav.push<int>(MaterialPageRoute<int>(
      builder: (c) => BirthdayMonthScreen(
        birthDate: null,
        age: age,
        onMonthPicked: (m) => Navigator.of(c).pop(m),
      )));
    if (!mounted) return;
    if (month == null) return setState(() => _running = false);

    final BirthdayPicker? picker = await nav.push<BirthdayPicker>(MaterialPageRoute<BirthdayPicker>(
      builder: (c) => BirthdayDayScreen(
        month: month,
        authoritative: null,
        age: age,
        onComplete: (p) => Navigator.of(c).pop(p),
        onSkip: () => Navigator.of(c).pop(),
      )));
    if (!mounted) return;
    if (picker == null) return setState(() => _running = false);

    await nav.push(MaterialPageRoute<void>(
      builder: (c) => BirthdayMarkedScreen(
        childId: 'demo-child',
        childName: childName,
        picker: picker,
        colourId: colourId,
        onDone: () => Navigator.of(c).pop(),
      )));

    if (mounted) {
      setState(() {
        _running = false;
        _lastChildName = childName;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Redo the welcome tour')),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'A demo walk through name, age, who, colour, and birthday — the '
          'same screens a brand-new family sees. There is no real first-run '
          'detector behind this preview build, so this is a re-run, not a '
          'reset of anything real.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _running ? null : _run, child: const Text('Start')),
        if (_lastChildName != null) Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('Last run finished for "$_lastChildName".',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ]),
    )),
  );
}
