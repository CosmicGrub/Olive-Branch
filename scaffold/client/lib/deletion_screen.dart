// OLIVE BRANCH — guardian shell, deletion. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §2.10, §2.11,
// §9.8, prohibition P8. Renders MARKUP screen 'deletion'.
//
// No TS package in this codebase names a "deletion" module — §15 Safety and
// §16.1 #3 state the principles (the archive belongs to the child, raw
// export is free/unlimited/never held hostage, parent<->parent log entries
// are permanently undeletable) in prose, not in a function. Rather than
// invent unaudited copy, this file follows the audit-function pattern
// already established elsewhere in the ported logic (`auditStagger` in
// maturation/family.ts, `auditBriefing` in guardian.ts): the facts a
// deletion screen must state are data (`whatDeletionKeeps` /
// `whatDeletionRemoves`), and `auditDeletionCopy` asserts the copy never
// slips into language that contradicts §2.10/§2.11/P8.
//
// THE RULE THIS SCREEN EXISTS TO ENFORCE: what deletion means is stated
// BEFORE any destructive control is reachable. The confirm button is
// disabled — not hidden, disabled, so its existence is never in doubt —
// until the guardian has explicitly acknowledged the retained-items list.
// And because no backend exists to actually delete anything yet, tapping
// confirm reports itself honestly rather than claiming a deletion that
// never happened — the same posture child_home.dart's `_notBuiltYet` takes.
import 'package:flutter/material.dart';

// ============================================================ the facts ===
enum RetainedReason { deliveredToChild, parentLog, childArchive }

class RetentionFact {
  const RetentionFact({required this.item, required this.reason, required this.why});
  final String item;
  final RetainedReason reason;
  final String why;
}

/// What survives your own account deletion, regardless of tier or lapse.
const List<RetentionFact> whatDeletionKeeps = <RetentionFact>[
  RetentionFact(item: 'Messages and videos already delivered to her',
    reason: RetainedReason.deliveredToChild,
    why: 'Delivered messages belong to her, not to the account that sent them — §2.10.'),
  RetentionFact(item: 'The parent-to-parent handover log',
    reason: RetainedReason.parentLog,
    why: 'Cannot be deleted or edited by either guardian, ever — P8, court-tier integrity.'),
  RetentionFact(item: 'Her preserved archive — drawings, homework, the Year Book material',
    reason: RetainedReason.childArchive,
    why: 'Parents are custodians of her archive, not owners of it — §2.10, §9.8.'),
];

/// What actually goes when you delete your own account.
const List<String> whatDeletionRemoves = <String>[
  'Your login and session',
  'Messages you had queued or banked but not yet delivered',
  'Your future participation — calls, calendar edits, new messages',
];

const List<String> deletionForbiddenClaims = <String>[
  'deleted forever', 'gone permanently', 'wipes her archive', 'erases everything',
  'removes the log', 'clears the handover', 'pay to export', 'export fee',
  'unlock your data',
];

({bool ok, List<String> found}) auditDeletionCopy(String text) {
  final String t = text.toLowerCase();
  final List<String> found = deletionForbiddenClaims.where((String c) => t.contains(c)).toList();
  return (ok: found.isEmpty, found: found);
}

// ============================================================== the demo ===
class DeletionScreen extends StatefulWidget {
  const DeletionScreen({super.key, this.childName = 'Ivy'});
  final String childName;
  @override
  State<DeletionScreen> createState() => _DeletionScreenState();
}

class _DeletionScreenState extends State<DeletionScreen> {
  bool _acknowledged = false;

  void _confirm(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Account deletion — not built yet. Nothing has been deleted.'),
      duration: Duration(seconds: 3)));
  }

  void _export(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Raw export — not built yet. When it exists it is free, on every '
        'tier, including after cancellation.'),
      duration: Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    for (final RetentionFact f in whatDeletionKeeps) {
      final ({bool ok, List<String> found}) audit = auditDeletionCopy(f.why);
      assert(audit.ok, 'deletion copy contradicts §2.10/§2.11/P8: ${audit.found}');
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Delete your account')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('What stays', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Stated before anything happens — not after.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final RetentionFact f in whatDeletionKeeps)
          Card(margin: const EdgeInsets.only(bottom: 8),
            child: Padding(padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.item, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(f.why, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ])),
              ]))),
        const SizedBox(height: 16),
        Text('What goes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final String r in whatDeletionRemoves)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.remove_circle_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r)),
                ])),
          ]))),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: () => _export(context),
          icon: const Icon(Icons.download_outlined),
          label: Text("Download ${widget.childName}'s raw export first — "
            'free, unlimited, every tier')),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _acknowledged,
          onChanged: (bool? v) => setState(() => _acknowledged = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I understand delivered messages and the handover log are '
            'not deleted.'),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 48,
          child: FilledButton.tonal(
            onPressed: _acknowledged ? () => _confirm(context) : null,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer),
            child: const Text('Delete my account'))),
      ])),
    );
  }
}
