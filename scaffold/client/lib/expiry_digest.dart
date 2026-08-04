// OLIVE BRANCH — guardian shell, expiry digest. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §10.1b.
// Renders MARKUP screen 'expiryDigest'.
//
// 1:1 port of packages/storage/src/retention.ts: DIGEST_LEAD_DAYS,
// ExpiringArtifact, ExpiryDigest, expiringSoon(), digestVisibleTo(),
// keepForever().
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

// ============================================================== the demo ===
final DateTime _now = DateTime.utc(2026, 8, 4);
List<ArtifactSeed> _demoArtifacts() => <ArtifactSeed>[
  ArtifactSeed(id: 'c1', kind: 'call_clip', caption: 'a laugh from Tuesday\'s call',
    capturedAt: _now.subtract(const Duration(days: 20)), preserved: false,
    expiresAt: _now.add(const Duration(days: 3))),
  ArtifactSeed(id: 'c2', kind: 'screen_frame', caption: null,
    capturedAt: _now.subtract(const Duration(days: 25)), preserved: false,
    expiresAt: _now.add(const Duration(days: 9))),
  ArtifactSeed(id: 'c3', kind: 'call_clip', caption: 'her show-and-tell moment',
    capturedAt: _now.subtract(const Duration(days: 2)), preserved: false,
    expiresAt: _now.add(const Duration(days: 27))), // outside the lead window
  ArtifactSeed(id: 'c4', kind: 'session_media', caption: 'a doodle-desk snapshot',
    capturedAt: _now.subtract(const Duration(days: 1)), preserved: true,
    expiresAt: _now.add(const Duration(days: 5))), // preserved — never appears
];

class ExpiryDigestScreen extends StatefulWidget {
  const ExpiryDigestScreen({super.key});
  @override
  State<ExpiryDigestScreen> createState() => _ExpiryDigestScreenState();
}

class _ExpiryDigestScreenState extends State<ExpiryDigestScreen> {
  late List<ArtifactSeed> _artifacts = _demoArtifacts();

  void _keep(String id) => setState(() {
    final List<String> kept = keepForever(<String>[id], _artifacts);
    _artifacts = _artifacts.map((ArtifactSeed a) =>
      kept.contains(a.id)
        ? ArtifactSeed(id: a.id, kind: a.kind, caption: a.caption, capturedAt: a.capturedAt,
            preserved: true, expiresAt: a.expiresAt)
        : a).toList();
  });

  @override
  Widget build(BuildContext context) {
    final ExpiryDigest digest = expiringSoon(_artifacts, _now);
    return Scaffold(
      appBar: AppBar(title: const Text('Expiry digest')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(digest.headline, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Guardian-only, always — never shown to her.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 12),
        if (digest.byKind.isNotEmpty)
          Wrap(spacing: 8, children: [
            for (final ByKind bk in digest.byKind)
              Chip(label: Text('${_kindLabel(bk.kind)} · ${bk.count}')),
          ]),
        const SizedBox(height: 12),
        for (final ExpiringArtifact a in digest.items)
          AnimatedSize(duration: const Duration(milliseconds: 200),
            child: _ExpiringTile(artifact: a, onKeep: () => _keep(a.artifactId))),
        if (digest.items.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('All clear.', style: TextStyle(color: Colors.black45))),
      ])),
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
  'call_clip' => 'Call clips',
  'screen_frame' => 'Screenshare frames',
  'session_media' => 'Session media',
  _ => kind,
};

class _ExpiringTile extends StatelessWidget {
  const _ExpiringTile({required this.artifact, required this.onKeep});
  final ExpiringArtifact artifact;
  final VoidCallback onKeep;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      title: Text(artifact.caption ?? _kindLabel(artifact.kind)),
      subtitle: Text('${artifact.daysLeft == 1 ? '1 day' : '${artifact.daysLeft} days'} left'),
      trailing: SizedBox(height: 40, child: OutlinedButton(
        onPressed: onKeep, child: const Text('Keep forever'))),
    ));
}
