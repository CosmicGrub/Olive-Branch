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
// A real backend now exists for deletion (db/migrations/0011_account_deletion
// .sql, packages/db/src/pool.ts's deactivateAccount(), POST /v1/me/delete —
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
//
// RAW EXPORT IS ALSO REAL (server/routes.mjs's `GET /v1/children/:childId
// /export`, packages/db/src/pool.mjs's rawExportBundleFor — see that file's
// own header for the RLS/scoping this button relies on). `_export()` below
// makes a real network call, real file write, and shows the real result —
// success with a real path and an independently-verified hash, or a real,
// honest failure — never a "not built yet" placeholder, because it no
// longer is one. Deletion and export authenticate differently on this same
// screen: deletion takes a pre-supplied `sessionToken` (a live guardian
// entry point will thread one through once it exists), while export mints
// its own via `devLoginFor`/`guardianUserId` — the only real ceremony this
// codebase has for a guardian today outside the passkey flow's own honest
// stub. Both are genuine, just at different points on the road to a real
// guardian shell.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api_client.dart';
import 'sha256.dart';

/// Same convention as main_live.dart's own `_defaultBaseUrl` — the Android
/// emulator's host-loopback alias, overridable at build time.
const String _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123');
const String _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy
const String _defaultGuardianUserId = String.fromEnvironment('OLIVE_GUARDIAN_USER_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000002'); // seed-dev.mjs's Dad

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
    this.childId = _defaultChildId,
    this.guardianUserId = _defaultGuardianUserId,
    this.httpClient,
    this.documentsDirectory,
  });
  final String childName;
  /// Real network target for both `_confirm()` and `_export()`. Defaults
  /// match main_live.dart's own `--dart-define`s so this screen talks to the
  /// same dev server/seed data when run live, without requiring every call
  /// site to thread them through.
  final String baseUrl;
  /// Pre-supplied session for `_confirm()` (deletion) — see this file's own
  /// header for why this is honestly optional today.
  final String sessionToken;
  final String childId;
  /// dev-login is the only real ceremony this codebase has for a guardian
  /// today (guardian_setup.dart's passkey flow is its own honest stub —
  /// see guardian_more.dart's tile for it) — matches server/index.mjs's own
  /// `POST /v1/auth/dev-login {userId}` contract. Used only by `_export()`,
  /// which mints its own session rather than relying on `sessionToken`.
  final String guardianUserId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient) —
  /// same pattern as child_home_live.dart's own `httpClient` field.
  final http.Client? httpClient;
  /// Injectable for tests. The real default reaches the platform's actual
  /// documents directory via path_provider, which (like wear_sync_channel
  /// .dart's platform channel) has no native handler under `flutter test`.
  final Future<Directory> Function()? documentsDirectory;
  @override
  State<DeletionScreen> createState() => _DeletionScreenState();
}

class _DeletionScreenState extends State<DeletionScreen> {
  bool _acknowledged = false;
  bool _deleting = false;
  bool _done = false;
  bool _exporting = false;

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

  Future<void> _export(BuildContext context) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    OliveApi? api;
    try {
      final String token = await devLoginFor(widget.baseUrl,
          userId: widget.guardianUserId, client: widget.httpClient);
      api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final Map<String, dynamic> result = await api.fetchRawExport(widget.childId);

      // `bundleJson` is the EXACT string the server hashed (see api_client
      // .dart's own doc comment on fetchRawExport) — hashed and written
      // verbatim here, not a Dart-side re-encoding of the parsed `bundle`,
      // so a sha256 run against the SAVED FILE reproduces `bundleHash`
      // exactly. Same "verify from the file alone" ethos court_export.dart's
      // certified-export attestation already promises, extended to raw.
      final String bundleJson = result['bundleJson'] as String;
      final String serverHash = result['bundleHash'] as String;
      final String exportRecordId = result['exportRecordId'] as String;
      final bool verified = sha256Hex(bundleJson) == serverHash;

      final Directory dir = await (widget.documentsDirectory ?? getApplicationDocumentsDirectory)();
      final File file = File(
          '${dir.path}${Platform.pathSeparator}olive-raw-export-${widget.childId}-$exportRecordId.json');
      // Sync, deliberately: a real ASYNC dart:io call made from inside a
      // widget's own async callback hangs indefinitely under the plain
      // `flutter test` widget-test binding (confirmed directly this
      // session — Flutter's own docs name `tester.runAsync(...)` as the
      // fix for a test that needs the real-async version; the sync
      // variant sidesteps the whole question and is more than fast enough
      // for a one-shot local JSON write this size).
      file.writeAsStringSync(bundleJson);

      if (!context.mounted) return;
      setState(() => _exporting = false);
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(verified ? 'Raw export saved' : 'Saved — hash did not verify'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Saved to:'),
              SelectableText(file.path,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 12),
              Text(verified
                  ? 'SHA-256 of the saved file, verified against the server on this '
                    'device (not just trusted):'
                  : "SHA-256 of the saved file did NOT match what the server "
                    'reported — treat this copy as unverified:'),
              SelectableText(serverHash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          )),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Raw export failed: '
          '${e is ApiException ? '${e.statusCode} ${e.error}' : e}'),
        duration: const Duration(seconds: 4)));
    } finally {
      if (widget.httpClient == null) api?.close();
    }
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
        OutlinedButton.icon(
          onPressed: _exporting ? null : () => _export(context),
          icon: _exporting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined),
          label: Text(_exporting
              ? 'Exporting…'
              : "Download ${widget.childName}'s raw export first — "
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
