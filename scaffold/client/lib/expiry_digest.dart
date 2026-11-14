// OLIVE BRANCH — guardian shell, expiry digest. No longer UNVERIFIED — verified
// by CI (`flutter analyze` and `flutter test` run for real in tools/verify.sh
// and .github/workflows/verify.yml). MASTERFILE §10.1b. Renders MARKUP screen
// 'expiryDigest'.
//
// 1:1 port of packages/storage/src/retention.ts: DIGEST_LEAD_DAYS,
// ExpiringArtifact, ExpiryDigest, expiringSoon(), digestVisibleTo(),
// keepForever().
//
// THE READER (daily-time lane): [ExpiryDigestScreen] shows what the server's scheduler job
// (`expiry-digest`, migration 0044) recorded, read from GET /v1/children/:id/expiry-digests
// (guardian only). A plain list: what it is and how long is left. It is quiet by design: no
// badge, no count on the More row, no push. It never invents rows: with no server to ask it says
// plainly that this is a later thing, and when the server cannot be reached it says that
// instead and offers Try again, never an empty "All clear" that could be a lie. The records
// hold ids, kinds and dates only (never a caption). Keeping one needs the network and the
// archive's keep route, which are not built; the screen says so and offers no fake button.
//
// §10.1b: preservation is a standing rule, not an election — anything a
// guardian sends is kept by default. This digest is the ONLY reminder
// surface for the narrow category that is NOT covered by that rule
// (incidental capture: call clips, screenshare frames, transient session
// media), given with a 14-day lead and one tap to keep it, so nothing is
// ever lost without the guardian having had the chance to say otherwise.
//
// THE RULE THIS FILE MUST NEVER BREAK: `digestVisibleTo('child')` is false.
// "These memories are about to be deleted" is a sentence no eight-year-old
// should read about her own life — the decision is an adult's; the child
// experiences only the outcome. This screen is never navigated to from any
// child-facing widget in this codebase.
import 'package:flutter/material.dart';

// =========================================================== retention.ts ==
const int digestLeadDays = 14;

class ArtifactSeed {
  const ArtifactSeed({required this.id, required this.kind, this.caption,
    required this.capturedAt, required this.preserved, this.expiresAt});
  final String id;
  final String kind;
  final String? caption;
  final DateTime capturedAt;
  final bool preserved;
  final DateTime? expiresAt;
}

class ExpiringArtifact {
  const ExpiringArtifact({required this.artifactId, required this.kind, this.caption,
    required this.capturedAt, required this.expiresAt, required this.daysLeft});
  final String artifactId;
  final String kind;
  final String? caption;
  final DateTime capturedAt;
  final DateTime expiresAt;
  final int daysLeft;
}

class ByKind {
  const ByKind({required this.kind, required this.count});
  final String kind;
  final int count;
}

class ExpiryDigest {
  const ExpiryDigest({required this.items, required this.byKind, required this.headline});
  final List<ExpiringArtifact> items;
  final List<ByKind> byKind;
  String get audience => 'guardian';
  final String headline;
}

/// Artifacts inside the lead window, soonest first. Preserved artifacts never
/// appear — they have no clock. Anything already past expiry is excluded
/// too: offering to save something the reaper has already taken would be a
/// lie.
ExpiryDigest expiringSoon(List<ArtifactSeed> artifacts, DateTime now, {int leadDays = digestLeadDays}) {
  final DateTime horizon = now.add(Duration(days: leadDays));
  final List<ExpiringArtifact> items = artifacts
    .where((ArtifactSeed a) => !a.preserved && a.expiresAt != null)
    .map((ArtifactSeed a) => ExpiringArtifact(artifactId: a.id, kind: a.kind, caption: a.caption,
      capturedAt: a.capturedAt, expiresAt: a.expiresAt!,
      daysLeft: (a.expiresAt!.difference(now).inHours / 24).ceil()))
    .where((ExpiringArtifact a) => a.daysLeft > 0 && !a.expiresAt.isAfter(horizon))
    .toList()
    ..sort((ExpiringArtifact x, ExpiringArtifact y) => x.daysLeft.compareTo(y.daysLeft));

  final Map<String, int> counts = <String, int>{};
  for (final ExpiringArtifact i in items) {
    counts[i.kind] = (counts[i.kind] ?? 0) + 1;
  }
  final List<ByKind> byKind = counts.entries.map((MapEntry<String, int> e) =>
    ByKind(kind: e.key, count: e.value)).toList()
    ..sort((ByKind a, ByKind b) => b.count.compareTo(a.count));

  final String headline = items.isEmpty ? 'Nothing is due to be cleared.'
    : items.length == 1 ? 'One thing will be cleared soon unless you keep it.'
    : '${items.length} things will be cleared soon unless you keep them.';
  return ExpiryDigest(items: items, byKind: byKind, headline: headline);
}

/// THE RULE: a child is never shown this digest.
bool digestVisibleTo(String role) => role != 'child';

/// One tap. Preserving is always allowed and never reversible by the product.
List<String> keepForever(List<String> ids, List<ArtifactSeed> all) => all
  .where((ArtifactSeed a) => ids.contains(a.id) && !a.preserved)
  .map((ArtifactSeed a) => a.id).toList();

// ============================================================ the reader ===
/// One thing the server recorded as about to be cleared. Ids, kinds and dates only.
class DigestEntry {
  const DigestEntry({required this.artifactId, required this.kind, required this.expiresAt, required this.daysLeft});
  final String artifactId;
  final String kind;
  final DateTime expiresAt;
  final int daysLeft;
}

/// Reads the server's `{digests: [...]}` body into one plain list: every still-future item across the
/// recorded digests, each artifact once (the soonest date wins), soonest first. Tolerant: a malformed
/// row is skipped, never thrown. Already-passed items are dropped (offering to save what the reaper has
/// taken would be a lie).
List<DigestEntry> readExpiryDigests(Object? body, DateTime now) {
  final Map<String, DigestEntry> byId = <String, DigestEntry>{};
  final Object? digests = body is Map ? body['digests'] : null;
  if (digests is! List) return <DigestEntry>[];
  for (final Object? d in digests) {
    final Object? items = d is Map ? d['items'] : null;
    if (items is! List) continue;
    for (final Object? i in items) {
      if (i is! Map) continue;
      final Object? id = i['artifactId'], kind = i['kind'], at = i['expiresAt'];
      if (id is! String || kind is! String || at is! String) continue;
      final DateTime? exp = DateTime.tryParse(at);
      if (exp == null) continue;
      final int left = (exp.difference(now).inHours / 24).ceil();
      if (left <= 0) continue;
      final DigestEntry? seen = byId[id];
      if (seen == null || exp.isBefore(seen.expiresAt)) {
        byId[id] = DigestEntry(artifactId: id, kind: kind, expiresAt: exp, daysLeft: left);
      }
    }
  }
  return byId.values.toList()
    ..sort((DigestEntry a, DigestEntry b) => a.expiresAt.compareTo(b.expiresAt));
}

String digestHeadline(int n) => n == 0 ? 'Nothing is due to be cleared.'
    : n == 1 ? 'One thing is due to be cleared soon.'
    : '$n things are due to be cleared soon.';

/// Asks the server for the recorded digests (OliveApi.fetchExpiryDigests). Throws when it cannot.
typedef ExpiryDigestLoader = Future<Map<String, dynamic>> Function();

class ExpiryDigestScreen extends StatefulWidget {
  const ExpiryDigestScreen({super.key, this.load, this.clock});

  /// Null means this device is not connected to a server: the screen says so, plainly.
  final ExpiryDigestLoader? load;

  /// Now (null = the device clock). Injected by tests.
  final DateTime Function()? clock;

  @override
  State<ExpiryDigestScreen> createState() => _ExpiryDigestScreenState();
}

enum _Phase { loading, later, offline, ready }

class _ExpiryDigestScreenState extends State<ExpiryDigestScreen> {
  late _Phase _phase = widget.load == null ? _Phase.later : _Phase.loading;
  List<DigestEntry> _items = <DigestEntry>[];

  @override
  void initState() {
    super.initState();
    if (widget.load != null) _fetch();
  }

  Future<void> _fetch() async {
    final ExpiryDigestLoader load = widget.load!;
    setState(() => _phase = _Phase.loading);
    try {
      final Map<String, dynamic> body = await load();
      final List<DigestEntry> items = readExpiryDigests(body, (widget.clock ?? DateTime.now)().toUtc());
      if (!mounted) return;
      setState(() { _items = items; _phase = _Phase.ready; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.offline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color quiet = theme.colorScheme.onSurfaceVariant;
    final Widget body;
    switch (_phase) {
      case _Phase.loading:
        body = const Center(child: CircularProgressIndicator());
      case _Phase.later:
        body = const _Note(
          key: Key('digestLater'),
          icon: Icons.cloud_off_outlined,
          title: 'Later',
          text: 'This list comes from your family’s server, and this device is not connected to one yet. '
              'Nothing is lost by waiting: anything a grown-up sends is kept by default.',
        );
      case _Phase.offline:
        body = _Note(
          key: const Key('digestOffline'),
          icon: Icons.cloud_off_outlined,
          title: 'Could not reach the server',
          text: 'Nothing was cleared by that. Try again when you are connected.',
          action: FilledButton(
            key: const Key('digestRetry'),
            onPressed: _fetch,
            child: const Text('Try again'),
          ),
        );
      case _Phase.ready:
        body = ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Text(digestHeadline(_items.length), key: const Key('digestHeadline'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('For grown-ups only. Never shown to her.', style: theme.textTheme.bodySmall?.copyWith(color: quiet)),
          const SizedBox(height: 12),
          for (final DigestEntry e in _items)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: Key('digest-${e.artifactId}'),
                title: Text(_kindLabel(e.kind)),
                subtitle: Text(e.daysLeft == 1 ? 'Clears tomorrow' : 'Clears in ${e.daysLeft} days'),
              ),
            ),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: <Widget>[
                Icon(Icons.check_circle_outline, size: 40, color: quiet),
                const SizedBox(height: 12),
                Text('All clear.', style: theme.textTheme.bodyMedium?.copyWith(color: quiet)),
              ]),
            ),
          const SizedBox(height: 12),
          Text('Anything a grown-up sends is kept by default; this list is only for incidental capture that is not. '
              'Keeping one from here needs the network, which is not built yet.',
              key: const Key('digestKeepLater'), style: theme.textTheme.bodySmall?.copyWith(color: quiet)),
        ]);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Expiry digest')),
      body: SafeArea(child: body),
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
  'call_clip' => 'Call clip',
  'screen_frame' => 'Screenshare frame',
  'session_media' => 'Session media',
  _ => 'Other',
};

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...<Widget>[const SizedBox(height: 16), action!],
      ]),
    ),
  );
}
