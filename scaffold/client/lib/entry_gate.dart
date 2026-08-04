// OLIVE BRANCH — the entry gate. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). §8.5.0.
//
// Renders MARKUP screen "welcome". A role question, NOT an age gate —
// AgeStep (§8.5, onboarding.dart's TS sibling) already guards against a
// six-year-old typing a big number to unlock a privacy tier; routing full
// guardian authority off a self-reported age would be the same mistake one
// layer up. Choosing a side here GRANTS NOTHING BY ITSELF: real guardian
// capability is still gated entirely by family-graph/authorize.ts's can(),
// which has never heard of this screen (see packages/onboarding/src/
// onboarding.ts's chooseEntry/suggestEntryRole/routeFromEntry and
// ENTRY_CHOICE_GRANTS_NO_AUTHORITY for the canonical, tested version of
// this same rule).
//
// This is what stitches the two previously-separate preview builds
// (formerly lib/main.dart and lib/main_guardian.dart, two APKs sharing one
// applicationId that could never both be installed at once) into the two
// reachable halves of a single app.
import 'package:flutter/material.dart';

enum EntryRole { child, grownup }

class EntryGate extends StatelessWidget {
  const EntryGate({super.key, required this.childDestination,
    required this.grownupDestination});

  final Widget childDestination;
  final Widget grownupDestination;

  // Navigator.of(context) needs a context that is itself a DESCENDANT of the
  // Navigator being pushed onto — the context MaterialApp's own builder
  // receives (one level further out, above `home:`) is not. EntryGate is
  // rendered AS `home:`, so its own build context qualifies; routing lives
  // here rather than being handed in as a callback from further out, so
  // this can't be gotten wrong the same way twice. Caught by
  // test/widget_test.dart's real navigation coverage, not by inspection.
  void _go(BuildContext context, Widget destination) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => destination));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text("Which side is this?",
          style: TextStyle(fontSize: 15, color: Colors.black54)),
        const SizedBox(height: 32),
        _RoleButton(
          icon: Icons.child_care,
          label: "My child's device",
          onTap: () => _go(context, childDestination),
        ),
        const SizedBox(height: 14),
        _RoleButton(
          icon: Icons.person,
          label: "The grown-up's device",
          onTap: () => _go(context, grownupDestination),
        ),
        const SizedBox(height: 20),
        // Neither choice grants anything by itself — real guardian
        // capability is still gated by the family-graph authorizer.
        const Text('Choosing a side here unlocks nothing by itself.',
          style: TextStyle(fontSize: 11, color: Colors.black38)),
      ]))),
  );
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(height: 64,
    child: FilledButton.icon(
      onPressed: onTap, icon: Icon(icon), label: Text(label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))));
}
