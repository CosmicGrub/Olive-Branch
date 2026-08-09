// OLIVE BRANCH — her colour, guardian view. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline). §8.6.4.
//
// Renders MARKUP screen 'colourParent'. Read-only, by construction: this file
// contains no colour picker, no edit affordance, and no callback that could
// change her colour — the guardian sees what she picked and nothing more.
//
// §8.6.4 is the prohibition this screen exists to honour. parentView() (see
// palette_logic.dart) returns exactly `{label, hex, changedToday, line}` —
// there is structurally no field here for mood, sentiment, or a trend, so
// this screen cannot accidentally render one later. Calmer and denser than
// the child-facing colour screens, matching the rest of the guardian shell.
import 'package:flutter/material.dart';
import 'palette_logic.dart';

class ColourParentScreen extends StatelessWidget {
  const ColourParentScreen({super.key, required this.childName,
    required this.history, required this.today});

  final String childName;
  final List<ColourChoice> history;
  /// ISO date (yyyy-mm-dd or full timestamp) — "today" from the actor's
  /// perspective is fine here; this screen states a fact, not a schedule.
  final String today;

  @override
  Widget build(BuildContext context) {
    final view = parentView(history, today);
    return Scaffold(
      appBar: AppBar(title: Text("$childName's colour")),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: view == null ? const _EmptyState() : _ColourReadout(view: view),
      )),
    );
  }
}

class _ColourReadout extends StatelessWidget {
  const _ColourReadout({required this.view});
  final ParentColourView view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = colorFromHex(view.hex);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 56, height: 56,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // One neutral sentence. Never an interpretation — see §8.6.4.
            Text(view.line, style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('This is hers to choose — you cannot change it here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ])),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.palette_outlined, size: 40, color: scheme.onSurfaceVariant),
      const SizedBox(height: 8),
      Text('No colour chosen yet.',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
    ]));
  }
}
