// OLIVE BRANCH — the guardian Settings hub. No longer UNVERIFIED — verified by
// CI (a Flutter toolchain runs for real in tools/verify.sh's automated
// pipeline). MASTERFILE §8.1, §8.6.7.
//
// Everything configurable, in five plainly named groups: Her (colour and art,
// how her app looks, her age band), Family (adults, devices), Safety (PIN,
// parental controls, play window), Learn (Parent Learn choices) and Account.
// Each row opens the real screen that already exists for it; this file builds
// no setting of its own and adds nothing online — the rows that reach online
// screens (devices, adults) simply open those screens as they always did.
//
// The child's app has no equivalent of this screen, at any depth (§8.1): the
// banner at the top says so, and child_no_settings_contract_test.dart holds
// the child shell to it.
//
// It is a HUB, not a tab bar. The overhaul proposed Today / Messages / Together
// / Family / Settings as a bottom bar; re-plumbing the guardian shell around one
// would touch every guardian route and test, so for now this hub is reached from
// "More" (guardian_more.dart), which is where the settings already lived.
import 'package:flutter/material.dart';
import 'hub_widgets.dart';

/// One row: where it goes, and a short line saying what it is.
class SettingsRow {
  const SettingsRow({required this.id, required this.icon, required this.title,
    required this.subtitle, required this.onTap});
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class SettingsGroup {
  const SettingsGroup(this.title, this.rows);
  final String title;
  final List<SettingsRow> rows;
}

class GuardianSettingsHubScreen extends StatefulWidget {
  const GuardianSettingsHubScreen({super.key, required this.childName, required this.groups});

  final String childName;
  final List<SettingsGroup> groups;

  @override
  State<GuardianSettingsHubScreen> createState() => _GuardianSettingsHubScreenState();
}

class _GuardianSettingsHubScreenState extends State<GuardianSettingsHubScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final theme = Theme.of(context);
    final shown = [
      for (final g in widget.groups)
        SettingsGroup(g.title, [
          for (final r in g.rows)
            if (q.isEmpty || r.title.toLowerCase().contains(q) || r.subtitle.toLowerCase().contains(q)
                || g.title.toLowerCase().contains(q)) r,
        ]),
    ].where((g) => g.rows.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(key: const Key('settingsSearch'),
            decoration: const InputDecoration(hintText: 'Search settings', prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: 10),
          Card(color: theme.colorScheme.secondaryContainer, child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.lock_outline), const SizedBox(width: 10),
              Expanded(child: Text('${widget.childName} never sees these settings. Her app has none.',
                key: const Key('noSettingsForHer'))),
            ]))),
          const SizedBox(height: 8),
          if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24),
            child: Center(child: Text('Nothing matches “$_q”.', key: const Key('settingsNoMatch')))),
          for (final g in shown) HubSection(title: g.title, children: [
            for (final r in g.rows) HubTile(key: Key('settingsRow_${r.id}'),
              icon: r.icon, title: r.title, subtitle: r.subtitle, onTap: r.onTap),
          ]),
        ]),
      )),
    );
  }
}
