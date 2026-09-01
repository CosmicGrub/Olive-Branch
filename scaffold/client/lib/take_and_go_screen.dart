// OLIVE BRANCH — child shell, take-and-go. Verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// also manually built and run via `flutter analyze` / `flutter test` this
// session; CHANGELOG v0.49.61). MASTERFILE §2.10, §2.11, §9.8/§9.8.4, §21.2
// rung 17, §21.7, prohibitions P6/P7/P8.
//
// A GENUINE MIRROR of deletion_screen.dart — same rigor (a real backend call,
// a real acknowledgment gate, a real audited-copy discipline, a real
// save-to-file-and-verify flow), same "state it before it happens, never
// fake success" posture — built for the OTHER side of the same relationship:
// deletion_screen.dart is a GUARDIAN closing HER OWN account (deactivation —
// nothing of the child's is touched); this screen is the CHILD, at majority,
// closing the family's ACCESS TO HER. §9.8.4 is explicit about what that
// means: guardian read access ends, every guardianship edge closes, and she
// leaves with a full, real copy of everything — never with less than she
// walked in with. There is nothing here for her to "lose".
//
// NO COOLING-OFF PERIOD, DELIBERATELY — §21.7's own words, quoted because
// they are the whole design brief for this file: "A delay is a soft refusal
// dressed as care, and every product that has ever added one added it to
// reduce the number of people who go through with it. Confirmation is
// legitimate; delay is not." The confirm button below is disabled only until
// she has acknowledged what closes — never on a timer, never behind a second
// screen, never softened with "are you sure" or "you can always change your
// mind" — packages/maturation/src/rungs.ts's own DELETION_FORBIDDEN_COPY
// names that exact language as forbidden for the sibling feature (her full
// deletion request at eighteen); takeAndGoForbiddenCopy below is this
// screen's own hand-written list in the same spirit — deletion_screen.dart's
// own header explains why this is written by hand rather than imported: no
// TS package in this codebase names a module for THIS screen's copy either,
// and inventing unaudited prose would be worse than auditing real prose.
//
// A real backend exists for this as of this pass (db/migrations/
// 0016_child_take_and_go.sql, packages/db/src/pool.ts's takeAndGo(), POST
// /v1/children/:childId/take-and-go — server/routes.mjs) and `_takeAndGo()`
// calls it for real via `OliveApi.takeAndGo()`. `baseUrl`/`childId` are
// honestly OPTIONAL, not because the call is fake, but for the identical
// reason deletion_screen.dart's own `sessionToken`/`childId` are: no live
// child entry point threads a real session into child_more.dart yet
// (main_live.dart wires up LiveChildHomeScreen, but child_more.dart itself —
// this screen's real call site — is still reached only through the demo
// ChildHome/ChildMoreScreen path). The defaults below mint a REAL child
// session via dev-login (matching deletion_screen.dart's own `_export()`,
// which does the identical thing for a guardian) and make a REAL network
// call that fails honestly (no such child / not yet of age / unreachable
// host) rather than faking success.
//
// Dead-wire fix (2026-08-24, following v0.49.15's own sweep): `_takeAndGo()`
// read `result['bundleJson']` -- copied from deletion_screen.dart's
// `_export()` without noticing that method calls a DIFFERENT route (GET
// .../export, which renames pool.ts's `serialized` to `bundleJson`) than
// this screen's own POST .../handover (which spreads TakeAndGoResult
// verbatim -- the real key is `serialized`). `result['bundleJson']` was
// simply absent from every real response this screen ever received, so the
// `as String` cast would have thrown on every genuine success. Fixed to
// read the field this response actually carries. Separately,
// `guardianshipsClosed`/`artifactsTransferred`/`journalEntriesTransferred`/
// `handedOverAt` -- real, computed by takeAndGo() and present in the same
// response `_takeAndGo()` already had in hand -- were parsed into nothing:
// the exact "what closes" facts this screen's own pre-confirm copy
// (whatTakeAndGoCloses above) already promises abstractly, now stated as
// the real numbers this handover actually produced.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api_client.dart';
import 'sha256.dart';

/// Same convention as deletion_screen.dart's own `_defaultBaseUrl`/
/// `_defaultChildId` — the Android emulator's host-loopback alias,
/// overridable at build time.
const String _defaultBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123');
const String _defaultChildId = String.fromEnvironment('OLIVE_CHILD_ID',
    defaultValue: 'aaaaaaaa-0000-4000-8000-000000000001'); // seed-dev.mjs's Ivy

// ============================================================ the facts ===
/// What she takes with her, every time, no exceptions. §9.8.4's own promise:
/// she never leaves with less than a full copy of what was hers.
const List<String> whatTakeAndGoIncludes = <String>[
  'Every message and video already delivered to you',
  'Your own journal — private, and it stays that way',
  'Your preserved archive — drawings, homework, the Year Book material',
  'The parent-to-parent handover log — a copy of it, not the right to change it',
];

/// What closes, permanently, the moment this succeeds.
const List<String> whatTakeAndGoCloses = <String>[
  "Every guardian's access to read your account",
  'Their ability to see anything you do here from now on',
];

/// Shown both in the confirmation dialog and the persistent confirmation
/// card below the button — one string, so the two can never drift, and one
/// thing for `_takeAndGo()` to audit rather than two.
const String takeAndGoConfirmationCopy =
  'Your data is yours. Every guardian\'s access to your account has closed — '
  'for good.';

/// Hand-written for this screen, same posture deletion_screen.dart's own
/// `deletionForbiddenClaims` already takes (see this file's header) — but
/// leaning on rungs.ts's DELETION_FORBIDDEN_COPY as the actual design
/// precedent, since that list is the one other place in this codebase that
/// specifies tone for an irreversible action an eighteen-year-old takes on
/// her own account: no guilt, no "are you sure", no offer of a lesser option.
const List<String> takeAndGoForbiddenCopy = <String>[
  'are you sure', 'you will lose', 'think about it', 'sleep on it',
  'you can come back', 'reconsider', 'instead you could', 'we are sorry to see',
  'before you go', 'take a break', 'remember when', 'years of memories',
  'lost access', 'goodbye', 'sorry to see',
];

({bool ok, List<String> found}) auditTakeAndGoCopy(String text) {
  final String t = text.toLowerCase();
  final List<String> found = takeAndGoForbiddenCopy.where((String c) => t.contains(c)).toList();
  return (ok: found.isEmpty, found: found);
}

/// Minimal, no-intl formatting of a UTC ISO-8601 instant into
/// 'YYYY-MM-DD HH:mm UTC' — matches this app's own no-intl-dependency
/// convention (see calendar_day_logic.dart's own hand-rolled 'HH:mm'
/// formatter) rather than pulling in the `intl` package for one field.
/// Returns [iso] itself, unparsed, on anything malformed — an honest
/// fallback, never a crash on a real server response.
String formatHandedOverAt(String iso) {
  final DateTime? dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final DateTime utc = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)} UTC';
}

// ============================================================== the demo ===
class TakeAndGoScreen extends StatefulWidget {
  const TakeAndGoScreen({
    super.key,
    this.childName = 'Ivy',
    this.baseUrl = _defaultBaseUrl,
    this.childId = _defaultChildId,
    this.httpClient,
    this.documentsDirectory,
  });
  final String childName;
  /// Real network target for `_takeAndGo()` — see this file's own header for
  /// why this is honestly optional today, mirroring deletion_screen.dart's
  /// own `baseUrl`.
  final String baseUrl;
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient) —
  /// same pattern as deletion_screen.dart's own `httpClient` field.
  final http.Client? httpClient;
  /// Injectable for tests. The real default reaches the platform's actual
  /// documents directory via path_provider.
  final Future<Directory> Function()? documentsDirectory;
  @override
  State<TakeAndGoScreen> createState() => _TakeAndGoScreenState();
}

class _TakeAndGoScreenState extends State<TakeAndGoScreen> {
  bool _acknowledged = false;
  bool _working = false;
  bool _done = false;
  String? _savedPath;
  String? _serverHash;
  bool _hashVerified = false;
  // Real, fetched from POST .../handover's own response body (packages/db/
  // src/pool.ts's takeAndGo(), TakeAndGoResult) and, before this pass,
  // parsed into nothing at all -- `result` held these the whole time but
  // only bundleHash/exportRecordId (and a WRONG key for the bundle text
  // itself, see below) were ever read out of it. These are exactly the
  // "what closes" facts this screen's own pre-confirm copy already promises
  // abstractly (whatTakeAndGoCloses above) made concrete with the real
  // numbers this handover actually produced -- same "state the real count,
  // not just the abstract promise" fix v0.49.15 already made for
  // deletion_screen.dart's cancelledDeliveryIntents.
  int? _guardianshipsClosed;
  int? _artifactsTransferred;
  int? _journalEntriesTransferred;
  String? _handedOverAt;

  Future<void> _takeAndGo(BuildContext context) async {
    if (_working || _done) return;
    setState(() => _working = true);
    try {
      final String token = await devLoginFor(widget.baseUrl,
          childId: widget.childId, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final Map<String, dynamic> result = await api.takeAndGo(widget.childId);
      if (widget.httpClient == null) api.close();

      // Same "verify from the file alone" contract fetchRawExport's own
      // caller (deletion_screen.dart's `_export()`) already relies on --
      // but NOT the same wire shape. deletion_screen.dart's `_export()`
      // calls GET .../export, whose route renames pool.ts's own
      // `serialized` key to `bundleJson` for the client (see routes.mjs's
      // own comment on that route). POST .../handover, which THIS screen
      // calls, spreads TakeAndGoResult verbatim instead -- `serialized`,
      // never renamed. Before this pass this read `result['bundleJson']`
      // (copied from deletion_screen.dart's own pattern without noticing
      // the two routes' shapes differ), which is simply absent from this
      // response -- a `null` that would have thrown `as String` on every
      // real call this screen ever made. Fixed to read the field this
      // response actually carries.
      final String bundleJson = result['serialized'] as String;
      final String serverHash = result['bundleHash'] as String;
      final String exportRecordId = result['exportRecordId'] as String;
      final bool verified = sha256Hex(bundleJson) == serverHash;

      final Directory dir = await (widget.documentsDirectory ?? getApplicationDocumentsDirectory)();
      final File file = File('${dir.path}${Platform.pathSeparator}'
          'olive-take-and-go-${widget.childId}-$exportRecordId.json');
      // Sync — see deletion_screen.dart's own `_export()` comment on why a
      // real async dart:io write hangs under the plain widget-test binding.
      file.writeAsStringSync(bundleJson);

      if (!context.mounted) return;
      final ({bool ok, List<String> found}) audit = auditTakeAndGoCopy(takeAndGoConfirmationCopy);
      assert(audit.ok, 'take-and-go confirmation copy uses forbidden language: ${audit.found}');
      setState(() {
        _working = false;
        _done = true;
        _savedPath = file.path;
        _serverHash = serverHash;
        _hashVerified = verified;
        // Real closure facts -- see these fields' own doc comments above.
        _guardianshipsClosed = (result['guardianshipsClosed'] as num?)?.toInt();
        _artifactsTransferred = (result['artifactsTransferred'] as num?)?.toInt();
        _journalEntriesTransferred = (result['journalEntriesTransferred'] as num?)?.toInt();
        _handedOverAt = result['handedOverAt'] as String?;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(takeAndGoConfirmationCopy), duration: Duration(seconds: 6)));
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _working = false);
      // A real failure, reported honestly — never a fake success, and never
      // softened into "something went wrong". §21.7: age isn't negotiable
      // and the copy should say so plainly, not apologetically.
      final String message = e is ApiException
        ? switch (e.error) {
            'not_yet_of_age' =>
              "You're not old enough yet — this opens up when you reach the age this "
              'family has on file for you.',
            'already_handed_over' => 'This has already been done. Nothing has changed.',
            'child_deceased' => 'This could not be completed.',
            _ => 'Could not complete this (${e.error}). Nothing has changed.',
          }
        : 'Could not reach the server. Nothing has changed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 5)));
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final String line in <String>[...whatTakeAndGoIncludes, ...whatTakeAndGoCloses,
        takeAndGoConfirmationCopy]) {
      final ({bool ok, List<String> found}) audit = auditTakeAndGoCopy(line);
      assert(audit.ok, 'take-and-go copy uses forbidden language: ${audit.found}');
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Take your data and go')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('What you take with you', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Stated before anything happens — not after.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final String item in whatTakeAndGoIncludes)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.shield_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ])),
          ]))),
        const SizedBox(height: 16),
        Text('What closes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final String item in whatTakeAndGoCloses)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.remove_circle_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ])),
          ]))),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _acknowledged,
          onChanged: (bool? v) => setState(() => _acknowledged = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I understand every guardian\'s access closes, and this '
            "can't be undone."),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 48,
          child: FilledButton(
            onPressed: (_acknowledged && !_working && !_done)
              ? () => _takeAndGo(context) : null,
            child: _working
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_done ? 'Done' : 'Take my data and close guardian access'))),
        if (_done) ...[
          const SizedBox(height: 8),
          Card(color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(takeAndGoConfirmationCopy)),
                ]),
                // Real closure facts from the server's own response --
                // see _guardianshipsClosed/_artifactsTransferred/
                // _journalEntriesTransferred/_handedOverAt's own doc
                // comments above. This app's own "null/0 renders nothing"
                // convention (deletion_screen.dart's cancelledDeliveryIntents,
                // child_home.dart's badgeCount) applies to each count
                // independently, so a genuinely-zero count states nothing
                // rather than a confusing "0 items transferred."
                if ((_guardianshipsClosed ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    _guardianshipsClosed == 1
                      ? "1 guardian's access closed with it."
                      : "$_guardianshipsClosed guardians' access closed with it.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                if ((_artifactsTransferred ?? 0) > 0 || (_journalEntriesTransferred ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_artifactsTransferred ?? 0} preserved '
                    '${_artifactsTransferred == 1 ? 'item' : 'items'} and '
                    '${_journalEntriesTransferred ?? 0} journal '
                    '${_journalEntriesTransferred == 1 ? 'entry' : 'entries'} came with you.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                if (_handedOverAt != null) ...[
                  const SizedBox(height: 4),
                  Text('Closed ${formatHandedOverAt(_handedOverAt!)}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
                if (_savedPath != null) ...[
                  const SizedBox(height: 12),
                  const Text('Saved to:'),
                  SelectableText(_savedPath!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(_hashVerified
                      ? 'SHA-256 of the saved file, verified against the server on this '
                        'device (not just trusted):'
                      : "SHA-256 of the saved file did NOT match what the server "
                        'reported — treat this copy as unverified:'),
                  if (_serverHash != null)
                    SelectableText(_serverHash!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ]))),
        ],
      ])),
    );
  }
}
