// OLIVE BRANCH — "What changes at each age": the planner (the prototype's
// g-planner). No longer UNVERIFIED — verified by CI
// (client/test/guardian_hub_parity_test.dart). MASTERFILE §8.1, §8.6.
//
// For each age her home grows (5, 8 and 13): what opens, whether her home should
// wait until a grown-up has told her, and a note to the grown-up a week before.
// A plan, not a schedule: nothing here moves until she reaches the age and a
// grown-up says so. The bullets come from the real band table
// (family_structure_logic.dart), so the planner can never describe a home the app
// does not build.
//
// HONEST ABOUT WHAT IS LIVE. The choices are kept on this device (home_plan_store.dart).
// The hold that acts today is the single one on the Age bands screen; these per-age
// choices are the plan beside it, and the card says so. A reminder note needs
// notifications, which are not built yet, and says so. Nothing is sent, and nothing
// here is shown to her.
import 'package:flutter/material.dart';

import 'family_structure_logic.dart';
import 'home_plan_store.dart';
import 'ui/olive_ui.dart';

class AgePlannerScreen extends StatefulWidget {
  const AgePlannerScreen({super.key, required this.childName, required this.childAge, this.repository});

  final String childName;
  final int childAge;
  final HomePlanRepository? repository;

  @override
  State<AgePlannerScreen> createState() => _AgePlannerScreenState();
}

class _AgePlannerScreenState extends State<AgePlannerScreen> {
  late final HomePlanRepository _repo = widget.repository ?? LocalStoreHomePlanRepository.shared();
  HomePlan? _plan;
  String? _note;

  @override
  void initState() {
    super.initState();
    _repo.load().then((HomePlan p) {
      if (mounted) setState(() => _plan = p);
    });
  }

  Future<void> _set(HomePlan next) async {
    setState(() { _plan = next; _note = null; });
    try {
      await _repo.save(next);
      if (mounted) setState(() => _note = 'Saved on this device.');
    } catch (_) {
      if (mounted) setState(() => _note = 'Changed for now, but this device could not keep it.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final HomePlan? p = _plan;
    final String name = widget.childName;
    final String here = bandForYears(widget.childAge);
    return Scaffold(
      appBar: AppBar(title: const Text('What changes at each age')),
      body: SafeArea(
        child: p == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  const OliveNotice(
                    key: Key('plannerBanner'),
                    tone: OliveTone.info,
                    text: 'A plan, not a schedule. Nothing here moves until she reaches the age and you say so.',
                  ),
                  const SizedBox(height: 12),
                  for (final int age in plannerAges) ...<Widget>[
                    _bandCard(context, p, age, here, name),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Her age is chosen once by her and then locked. Bands follow the age. The hold that acts '
                    'today is the one on the Age bands screen; these choices are the plan beside it. '
                    'A reminder needs notifications, which are not built yet.',
                    key: const Key('plannerNote'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_note != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_note!, key: const Key('plannerSaved')),
                  ),
                ]),
              ),
      ),
    );
  }

  Widget _bandCard(BuildContext context, HomePlan p, int age, String here, String name) {
    final BandDef b = bandDef(plannerBandOfAge[age]!);
    return OliveCard(
      key: Key('plannerBand_$age'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(b.label, style: Theme.of(context).textTheme.titleMedium),
        Text('From age $age', style: Theme.of(context).textTheme.bodySmall),
        if (here == b.id)
          Text('$name is here', key: Key('plannerHere_$age'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (final String line in b.summary)
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('• $line', style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(height: 4),
        ToggleRow(
          key: Key('plannerHold_$age'),
          title: 'Hold when she arrives',
          sub: 'Her home stays until you release it',
          icon: OliveIcons.hourglass,
          value: p.holdWhenArrives(age),
          onChanged: (bool v) => _set(p.copyWith(holdAt: <int, bool>{...p.holdAt, age: v})),
        ),
        ToggleRow(
          key: Key('plannerRemind_$age'),
          title: 'Remind me a week before',
          sub: 'A note to you. Nothing goes to $name.',
          icon: OliveIcons.bell,
          value: p.remindBefore(age),
          onChanged: (bool v) => _set(p.copyWith(remind: <int, bool>{...p.remind, age: v})),
        ),
      ]),
    );
  }
}
