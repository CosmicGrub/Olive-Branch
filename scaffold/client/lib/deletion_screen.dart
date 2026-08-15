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
//
// A real backend now exists (db/migrations/0011_account_deletion.sql,
// packages/db/src/pool.ts's deactivateAccount(), POST /v1/me/delete —
// server/routes.mjs) and `_confirm()` calls it for real via
// `OliveApi.deleteAccount()`. `baseUrl`/`sessionToken` are honestly
// OPTIONAL, not because the call is fake, but because no live guardian
// entry point exists ANYWHERE in this client yet to supply a real session
// (main.dart's own header: "There is no backend behind it yet"; main_live.dart
// wires up only the CHILD side, LiveChildHomeScreen — see that file's own
// header). Until a live guardian shell exists, guardian_more.dart's existing
// `const DeletionScreen()` call site legitimately gets the built-in
// defaults below, which make a REAL network call that fails honestly (no
// session / unreachable host) rather than faking success — the same
// "genuine attempt, honest failure" posture child_home_live.dart's error
// state already takes. The moment a live guardian entry point is wired
// (mirroring main_live.dart's child-side pattern), it supplies the real
// values and every one of the widget tests in deletion_screen_test.dart
// that mock a 200 already prove the success path works end to end.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// Same convention as main_live.dart's own `_defaultBaseUrl` — the Android
/// emulator's host-loopback alias, overridable at build time.
const _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123');

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

/// Shown both in the transient success SnackBar and the persistent
/// confirmation card below the button — one string, so the two can never
/// drift, and one thing for `_confirm()` to audit rather than two.
const String deletionConfirmationCopy =
  'Your account is deactivated. Delivered messages, the parent-to-parent '
  'log, and her preserved archive are untouched.';

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
  const DeletionScreen({
    super.key,
    this.childName = 'Ivy',
    this.baseUrl = _defaultBaseUrl,
    this.sessionToken = '',
    this.httpClient,
  });
  final String childName;
  final String baseUrl;
  final String sessionToken;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient) —
  /// same pattern as child_home_live.dart's own `httpClient` field.
  final http.Client? httpClient;
  @override
  State<DeletionScreen> createState() => _DeletionScreenState();
}

class _DeletionScreenState extends State<DeletionScreen> {
  bool _acknowledged = false;
  bool _deleting = false;
  bool _done = false;

  Future<void> _confirm(BuildContext context) async {
    setState(() => _deleting = true);
    final OliveApi api =
        OliveApi(widget.baseUrl, widget.sessionToken, client: widget.httpClient);
    try {
      await api.deleteAccount();
      if (widget.httpClient == null) api.close();
      if (!context.mounted) return;
      // The confirmation copy is itself subject to the same audit as
      // whatDeletionKeeps — a real success must not slip into language
      // §2.10/§2.11/P8 forbid any more than the stub did.
      final ({bool ok, List<String> found}) audit = auditDeletionCopy(deletionConfirmationCopy);
      assert(audit.ok, 'deletion confirmation copy contradicts §2.10/§2.11/P8: ${audit.found}');
      setState(() { _deleting = false; _done = true; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(deletionConfirmationCopy), duration: Duration(seconds: 6)));
    } catch (e) {
      if (widget.httpClient == null) api.close();
      if (!context.mounted) return;
      setState(() => _deleting = false);
      // A real failure, reported honestly — never a fake success. §2.10's
      // own posture ("state before it happens") extends to "state
      // truthfully when it doesn't happen either."
      final String message = e is ApiException
        ? 'Could not delete your account (${e.error}). Nothing has changed.'
        : 'Could not reach the server. Nothing has changed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 4)));
    }
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
            onPressed: (_acknowledged && !_deleting && !_done)
              ? () => _confirm(context) : null,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer),
            child: _deleting
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_done ? 'Account deleted' : 'Delete my account'))),
        if (_done) ...[
          const SizedBox(height: 8),
          Card(color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text(deletionConfirmationCopy)),
              ]))),
        ],
      ])),
    );
  }
}
