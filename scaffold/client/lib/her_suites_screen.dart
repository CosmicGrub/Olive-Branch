// OLIVE BRANCH — g-suites: the one "Her suites" page. No longer UNVERIFIED — verified by CI
// (client/test/her_suites_screen_test.dart).
//
// The prototype's guardian page lists the six local suites (Rhythm, Voice, Growing, Care, Village, Compass), each
// with an "On her shelf" or "Off" chip and one switch. This is that page. Every switch here is the suite's OWN
// switch, read and written through the Compass service's ports (compass_repositories.dart), so this page, the
// Suites shelf inside Compass and each suite's own page can never disagree.
//
// ON THIS DEVICE. The prototype publishes guardian-written content to a separate child tablet through its
// server and tags each row "On her tablet" or "Waiting to send". Here the suites write the same install's local
// store, so there is nothing waiting to send: the tag says "Kept on this device" and the page says plainly that
// sending to a second device waits for a later update. Nothing is sent, and no row pretends otherwise.
//
// Compass is a guardian-only page with no child side, so it has no shelf switch: its chip says "For you".
// The page shows on or off only, never how much a suite has been used (P1).
import 'package:flutter/material.dart';

import 'compass_repositories.dart';
import 'compass_screens.dart' show compassRefusalText;
import 'family_structure_logic.dart' show FamilyPrincipal;
import 'picture_icons.dart' show QuietNote;

/// One row of the page: the prototype's six suites in its own order.
class HerSuite {
  const HerSuite(this.key, this.title, this.blurb, this.icon, {this.hasSwitch = true});
  final String key;
  final String title;
  final String blurb;
  final IconData icon;
  final bool hasSwitch;
}

const List<HerSuite> herSuites = <HerSuite>[
  HerSuite('rhythm', 'Rhythm', 'Routines, first-then, packing, new places, how the app feels', Icons.schedule_outlined),
  HerSuite('voice', 'Voice', 'My helpers, symbols, feelings check-in on or off', Icons.record_voice_over_outlined),
  HerSuite('growing', 'Growing', 'Time capsule, first times, growing marks', Icons.eco_outlined),
  HerSuite('care', 'Care', 'Picture stories for a doctor visit or feeling poorly, care binder', Icons.health_and_safety_outlined),
  HerSuite('village', 'Village', 'Sitter pass, grandparent page, school summary', Icons.diversity_3_outlined),
  HerSuite('compass', 'Compass', 'Two gentle questions, suggestions, accessibility profiles', Icons.explore_outlined, hasSwitch: false),
];

class HerSuitesScreen extends StatefulWidget {
  const HerSuitesScreen({
    super.key, required this.childName, required this.service, required this.principal, required this.open,
  });
  final String childName;
  final CompassService service;
  final FamilyPrincipal principal;

  /// Opens a suite's own page, by [HerSuite.key].
  final void Function(String key) open;
  @override
  State<HerSuitesScreen> createState() => _HerSuitesState();
}

class _HerSuitesState extends State<HerSuitesScreen> {
  Map<String, bool> _on = const <String, bool>{};
  bool _loaded = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<ShelfRow> rows = await widget.service.shelf(widget.principal);
      if (mounted) setState(() { _on = <String, bool>{for (final ShelfRow r in rows) r.suite.key: r.on}; _loaded = true; });
    } on CompassRefused {
      if (mounted) setState(() => _denied = true);
    }
  }

  String get _summary {
    final int on = herSuites.where((HerSuite s) => s.hasSwitch && (_on[s.key] ?? false)).length;
    final int of = herSuites.where((HerSuite s) => s.hasSwitch).length;
    return on == 0 ? 'None on her shelf yet' : '$on of $of on her shelf';
  }

  Future<void> _set(HerSuite s, bool v) async {
    final CompassResult r = await widget.service.setSuite(widget.principal, s.key, v);
    if (mounted && !r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(compassRefusalText(r.reason)), duration: const Duration(seconds: 2)));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Her suites')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              const QuietNote('Kept on this device. These reach her tablet by being on it; sending to a second device '
                  'waits for a later update, and nothing here is sent.', icon: Icons.phone_android_outlined),
              const SizedBox(height: 8),
              Text('What is on her shelf. Each switch is the same one on the suite\'s own page, and a suite shows ${widget.childName} '
                  'nothing until you have written something for it.', key: const Key('suitesIntro')),
              const SizedBox(height: 8),
              if (_denied) const QuietNote('Only a grown-up can change this.'),
              if (_loaded) Text(_summary, key: const Key('suitesSummary'), style: Theme.of(context).textTheme.titleSmall),
              if (_loaded)
                for (final HerSuite s in herSuites) _row(context, s),
            ]),
          ),
        ),
      );

  Widget _row(BuildContext context, HerSuite s) {
    final bool on = s.hasSwitch ? (_on[s.key] ?? false) : true;
    final String chip = !s.hasSwitch ? 'For you' : (on ? 'On her shelf' : 'Off');
    return Card(
      key: Key('suiteRow_${s.key}'),
      child: Column(children: <Widget>[
        InkWell(
          key: Key('suiteOpen_${s.key}'),
          onTap: () => widget.open(s.key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(s.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(s.title, style: Theme.of(context).textTheme.titleMedium),
                  Text(s.blurb),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(children: <Widget>[
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
                Chip(key: Key('suiteChip_${s.key}'), label: Text(chip), visualDensity: VisualDensity.compact),
                if (s.hasSwitch && on) const Chip(label: Text('Kept on this device'), visualDensity: VisualDensity.compact),
              ]),
            ),
            if (s.hasSwitch)
              Switch(key: Key('suiteSwitch_${s.key}'), value: on, onChanged: (bool v) => _set(s, v)),
          ]),
        ),
      ]),
    );
  }
}
