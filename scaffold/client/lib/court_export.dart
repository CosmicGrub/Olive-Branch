// OLIVE BRANCH — court export. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §2.11, §16.1 #3, P8.
// Renders MARKUP screen 'export': "The archive assembled for the one reader
// who must trust it; chunked under the transfer ceiling."
//
// Two widgets live in this file now. `CourtExportScreen` (below) is the
// original, still-real preview build described in the rest of this header —
// its synthetic demo chain is untouched, and every existing test of it still
// passes unmodified. `LiveCourtExportScreen` (bottom of this file) is the
// real backend wiring this header used to say didn't exist:
// packages/db/src/pool.ts's certifiedExportBundleFor(), reached over
// GET /v1/children/:childId/export?kind=certified (server/routes.mjs),
// which reads the REAL message_log chain for a REAL child, runs it through
// the REAL verifyChain()/certify()/authorizeExport() (packages/ledger/src/
// ledger.ts), and returns either a real, verified Attestation or a real,
// specific denial reason (tier_required / annual_allowance_used /
// chain_broken / not-a-guardian-of-this-child) — never a silent failure,
// never a fabricated success. `main.dart`'s offline preview build has no
// reason to construct `LiveCourtExportScreen` (there is nothing live behind
// it there); `guardian_more.dart` opens it instead of the demo screen only
// when live config (baseUrl/guardianId/childId) is actually supplied,
// mirroring child_home_live.dart's own "live only when configured, demo
// otherwise" posture — see that file's header for the same pattern applied
// to the child side.
//
// §2.11 is the one rule this whole screen exists to make visible in the UI,
// not just in a pricing table: "the archive is never held hostage." RAW
// export is free, unlimited, on every tier, INCLUDING after cancellation —
// so the raw-export half of this screen carries no lock icon, no upgrade
// prompt, no tier badge, nothing that could be mistaken for a paywall. Only
// the CERTIFIED export — tamper-evident, hash-chained, court-formatted, with
// one free copy per guardian per rolling year — is gated, per §16.1 #3.
//
// The ledger subset below (`ExportKind` .. `certify()`) is a 1:1 port of the
// export/attestation half of packages/ledger/src/ledger.ts, the same
// close-to-the-original discipline lock_controller.dart applies to lock.ts.
// The hash-chain half of ledger.ts (append-only §12 Phase 3 log itself) is
// already built as UI in handover_notes.dart, which enforces P8 by giving the
// log exactly one mutation (add). This screen doesn't re-litigate that: the
// demo chain below is its own small, clearly-synthetic stand-in for "the log
// this export would contain," used only to make certification real rather
// than a label with nothing behind it. There is no edit control on it anywhere
// — the "preview a tampered copy" switch swaps between two READ-ONLY
// precomputed chains, it does not expose a way to alter either one from the UI.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'form_factors.dart' as ff;
import 'sha256.dart';

// ===================================================== posture width rule =
// Ported from packages/devices/src/postures.ts's §8.12.3 "the degraded
// court export" section. Real spec this screen never actually implemented:
// before this pass, `CourtExportScreen` rendered the full certified-export
// review UI (tamper preview, "Generate certified export," the attestation
// panel) at ANY width, including a 344px Fold-cover phone screen —
// directly contradicting `requestConfirmation()`'s own copy below, which
// tells the guardian reviewing needs "a computer or a tablet." The old
// `constraints.maxWidth >= 760` toggle only ever chose Row-vs-Column
// arrangement for the two cards; it never actually gated the review
// capability the spec describes. This is that gate, for real.
const int requestMinWidth = 320;
const int reviewMinWidth = 600;

bool reviewableAt(double width) => width >= reviewMinWidth;
bool requestableAt(double width) => width >= requestMinWidth;

/// What he is told on a phone. It does not pretend he can review it there —
/// the honest version is better than a cramped one.
const String requestConfirmation =
    'We are putting it together. It needs a bigger screen to check through, '
    'so open Olive on a computer or a tablet when you are ready — it will be '
    'waiting.';

// ============================================================ ledger subset =
// Ported from packages/ledger/src/ledger.ts.

enum ExportKind { raw, certified }

enum ExportDenial { tierRequired, annualAllowanceUsed }

/// §2.11 / §16.1 #3 — mirrors `FREE_CERTIFIED_PER_YEAR` in ledger.ts exactly.
const int freeCertifiedPerYear = 1;

class ExportRequest {
  const ExportRequest({
    required this.kind,
    required this.courtTier,
    required this.certifiedInLast12Months,
  });
  final ExportKind kind;
  final bool courtTier;
  final int certifiedInLast12Months;
}

class ExportAuthorization {
  const ExportAuthorization({required this.ok, this.free = false, this.denial});
  final bool ok;
  final bool free;
  final ExportDenial? denial;
}

/// 1:1 port of `authorizeExport()`. RAW is always free; CERTIFIED is free
/// until the yearly allowance is spent, then requires Court tier.
ExportAuthorization authorizeExport(ExportRequest r) {
  if (r.kind == ExportKind.raw) return const ExportAuthorization(ok: true, free: true);
  if (r.certifiedInLast12Months < freeCertifiedPerYear) {
    return const ExportAuthorization(ok: true, free: true);
  }
  if (!r.courtTier) return const ExportAuthorization(ok: false, denial: ExportDenial.tierRequired);
  return const ExportAuthorization(ok: true, free: false);
}

final String genesisHash = ''.padLeft(64, '0');

class LogEntry {
  const LogEntry({
    required this.seq,
    required this.childId,
    required this.authorId,
    required this.at,
    required this.body,
    required this.prevHash,
    required this.hash,
  });
  final int seq;
  final String childId;
  final String authorId;
  final String at;
  final String body;
  final String prevHash;
  final String hash;
}

String _framed(Object value) {
  final String s = value.toString();
  return '${s.length}:$s';
}

/// 1:1 port of `entryHash()`. Length-prefixed framing so a byte moved across
/// a field boundary changes the hash — naive concatenation would not catch
/// author "ab" + body "c" colliding with author "a" + body "bc".
String computeEntryHash({
  required int seq,
  required String childId,
  required String authorId,
  required String at,
  required String body,
  required String prevHash,
}) =>
    sha256Hex(_framed(seq) + _framed(childId) + _framed(authorId) + _framed(at) +
        _framed(body) + _framed(prevHash));

/// 1:1 port of `append()`.
LogEntry appendEntry(
  List<LogEntry> chain, {
  required String childId,
  required String authorId,
  required String at,
  required String body,
}) {
  final LogEntry? prev = chain.isEmpty ? null : chain.last;
  final int seq = prev == null ? 0 : prev.seq + 1;
  final String prevHash = prev?.hash ?? genesisHash;
  final String hash = computeEntryHash(
      seq: seq, childId: childId, authorId: authorId, at: at, body: body, prevHash: prevHash);
  return LogEntry(
      seq: seq, childId: childId, authorId: authorId, at: at, body: body,
      prevHash: prevHash, hash: hash);
}

enum ChainFaultKind { contentAltered, chainBroken, sequenceGap, badGenesis, timeTravel }

class ChainFault {
  const ChainFault(this.kind, [this.seq]);
  final ChainFaultKind kind;
  final int? seq;
}

class ChainVerification {
  const ChainVerification({required this.ok, this.faults = const <ChainFault>[]});
  final bool ok;
  final List<ChainFault> faults;
}

/// 1:1 port of `verifyChain()`. Every fault is detectable from the file
/// alone — no faults, no database lookup, just recomputing hashes.
ChainVerification verifyChain(List<LogEntry> chain) {
  final List<ChainFault> faults = <ChainFault>[];
  if (chain.isEmpty) return const ChainVerification(ok: true);
  if (chain.first.prevHash != genesisHash) faults.add(const ChainFault(ChainFaultKind.badGenesis));

  for (int i = 0; i < chain.length; i++) {
    final LogEntry e = chain[i];
    final String recomputed = computeEntryHash(
        seq: e.seq, childId: e.childId, authorId: e.authorId, at: e.at,
        body: e.body, prevHash: e.prevHash);
    if (recomputed != e.hash) faults.add(ChainFault(ChainFaultKind.contentAltered, e.seq));
    if (i > 0) {
      final LogEntry prev = chain[i - 1];
      if (e.prevHash != prev.hash) faults.add(ChainFault(ChainFaultKind.chainBroken, e.seq));
      if (e.seq != prev.seq + 1) faults.add(ChainFault(ChainFaultKind.sequenceGap, e.seq));
      if (e.at.compareTo(prev.at) < 0) faults.add(ChainFault(ChainFaultKind.timeTravel, e.seq));
    }
  }
  return ChainVerification(ok: faults.isEmpty, faults: faults);
}

class Attestation {
  const Attestation({
    required this.childId,
    required this.generatedAt,
    required this.entryCount,
    required this.firstSeq,
    required this.lastSeq,
    required this.headHash,
    required this.bundleHash,
    required this.chainVerified,
    required this.statement,
  });
  final String childId;
  final String generatedAt;
  final int entryCount;
  final int? firstSeq;
  final int? lastSeq;
  final String headHash;
  final String bundleHash;
  final bool chainVerified;
  final String statement;
}

/// 1:1 port of `certify()`. The attestation carries everything a reader needs
/// to recompute the chain themselves — head hash, count, and a hash over the
/// whole serialized bundle — so nobody has to take our word for it.
Attestation certify(List<LogEntry> chain, String childId, String at) {
  final ChainVerification v = verifyChain(chain);
  final String bundle = chain
      .map((LogEntry e) => '${e.seq}|${e.childId}|${e.authorId}|${e.at}|${e.body}|'
          '${e.prevHash}|${e.hash}')
      .join('\n');
  return Attestation(
    childId: childId,
    generatedAt: at,
    entryCount: chain.length,
    firstSeq: chain.isEmpty ? null : chain.first.seq,
    lastSeq: chain.isEmpty ? null : chain.last.seq,
    headHash: chain.isEmpty ? genesisHash : chain.last.hash,
    bundleHash: sha256Hex(bundle),
    chainVerified: v.ok,
    statement: v.ok
        ? 'Each entry carries a SHA-256 hash over its own contents and the hash '
            'of the entry before it. Recomputing the chain from this file '
            'reproduces the head hash shown above. Any alteration, deletion, '
            'reordering, or insertion changes it.'
        : 'VERIFICATION FAILED. This export does not form an unbroken chain '
            'and must not be relied upon.',
  );
}

// ============================================================== chunk plan =
// Not ported from any package. MARKUP's one-line description of this screen
// ("chunked under the transfer ceiling") named a behavior no backing package
// implements yet, so this is honestly new: split a total export size into
// parts no bigger than a ceiling a family could actually attach to an email
// or upload to a court e-filing portal.

/// 25 MB — a common attachment / upload ceiling. A demo-reasonable default,
/// not a value read from any spec; see the class doc above.
const int transferCeilingBytes = 25 * 1024 * 1024;

class ExportChunkPlan {
  const ExportChunkPlan({required this.totalBytes, required this.ceilingBytes, required this.chunkSizes});
  final int totalBytes;
  final int ceilingBytes;
  final List<int> chunkSizes;
  int get chunkCount => chunkSizes.length;
}

ExportChunkPlan planChunks(int totalBytes, {int ceilingBytes = transferCeilingBytes}) {
  if (totalBytes <= 0) {
    return ExportChunkPlan(totalBytes: 0, ceilingBytes: ceilingBytes, chunkSizes: const <int>[]);
  }
  final int count = (totalBytes / ceilingBytes).ceil();
  final List<int> sizes = <int>[];
  int remaining = totalBytes;
  for (int i = 0; i < count; i++) {
    final int size = remaining < ceilingBytes ? remaining : ceilingBytes;
    sizes.add(size);
    remaining -= size;
  }
  return ExportChunkPlan(totalBytes: totalBytes, ceilingBytes: ceilingBytes, chunkSizes: sizes);
}

String formatBytes(int bytes) {
  const double kb = 1024;
  const double mb = kb * 1024;
  const double gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / kb).toStringAsFixed(0)} KB';
}

// ==================================================================== demo =
// In-memory demo data only — see api_client.dart: no backend exists yet to
// actually assemble or transfer these files. Matches the honest-stub posture
// main.dart already takes for /now and /ribbon.

const String _demoChildName = 'Ivy';
// A few years of a real family's shared archive: photos, videos, messages.
const int _demoArchiveBytes = 3 * 1024 * 1024 * 1024 + 400 * 1024 * 1024; // ~3.4 GB

const List<String> _rawManifest = <String>[
  'messages.json',
  'calendar.ics',
  'medication_log.csv',
  'handover_notes.json  (the parent↔parent log, P8, in full)',
  'photos/  (1,842 files)',
  'videos/  (96 files)',
];

List<LogEntry> _buildDemoChain() {
  final List<LogEntry> chain = <LogEntry>[];
  chain.add(appendEntry(chain,
      childId: 'ivy', authorId: 'mom',
      at: '2026-06-01T16:00:00Z',
      body: 'Pickup moved to 4:30 today — meeting ran long.'));
  chain.add(appendEntry(chain,
      childId: 'ivy', authorId: 'dad',
      at: '2026-06-01T16:05:00Z',
      body: 'Got it, we\'ll wait inside where it\'s warm.'));
  chain.add(appendEntry(chain,
      childId: 'ivy', authorId: 'mom',
      at: '2026-06-14T08:00:00Z',
      body: 'Field trip permission slip is in her folder, due Friday.'));
  chain.add(appendEntry(chain,
      childId: 'ivy', authorId: 'dad',
      at: '2026-07-02T19:00:00Z',
      body: 'She left her retainer case here — I\'ll bring it Sunday.'));
  return chain;
}

/// A read-only alternate copy standing in for "a file altered after export" —
/// see the file header. Not derived from any UI edit control.
List<LogEntry> _tamperedCopy(List<LogEntry> chain) {
  final List<LogEntry> copy = List<LogEntry>.from(chain);
  final LogEntry target = copy[1];
  copy[1] = LogEntry(
    seq: target.seq, childId: target.childId, authorId: target.authorId, at: target.at,
    body: '${target.body} Actually, never mind, I\'ll bring her myself.',
    prevHash: target.prevHash, hash: target.hash, // hash NOT recomputed: exactly what tampering looks like
  );
  return copy;
}

// ===================================================================== UI =

class CourtExportScreen extends StatefulWidget {
  const CourtExportScreen({super.key});

  @override
  State<CourtExportScreen> createState() => _CourtExportScreenState();
}

class _CourtExportScreenState extends State<CourtExportScreen> {
  bool _rawPrepared = false;

  // Demo-only account state — a real build would read this from the session
  // (see api_client.dart), which doesn't exist yet in this preview build.
  bool _courtTier = false;
  int _certifiedUsed = 0;
  bool _previewTampered = false;
  Attestation? _attestation;

  late final List<LogEntry> _goodChain = _buildDemoChain();
  late final List<LogEntry> _tamperedChain = _tamperedCopy(_goodChain);

  List<LogEntry> get _activeChain => _previewTampered ? _tamperedChain : _goodChain;

  ExportAuthorization get _certifiedAuth => authorizeExport(ExportRequest(
        kind: ExportKind.certified,
        courtTier: _courtTier,
        certifiedInLast12Months: _certifiedUsed,
      ));

  void _generateCertified() {
    final ExportAuthorization auth = _certifiedAuth;
    if (!auth.ok) return;
    setState(() {
      _attestation = certify(_activeChain, _demoChildName, DateTime.now().toIso8601String());
      _certifiedUsed += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ExportChunkPlan plan = planChunks(_demoArchiveBytes);
    return Scaffold(
      appBar: AppBar(title: const Text('Court export')),
      body: SafeArea(
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          // Real §8.11.1 posture logic (form_factors.dart), not a made-up
          // number: the two cards sit side by side once the viewport can
          // genuinely afford two real columns at the current text scale.
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool wide = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
          // The real §8.12.3 rule (postures.ts, ported above): reviewing a
          // certified export needs real width. Requesting one never did.
          final bool reviewable = reviewableAt(constraints.maxWidth);
          final TextTheme textTheme = Theme.of(context).textTheme;
          final ColorScheme scheme = Theme.of(context).colorScheme;
          final Widget rawCard = _RawExportCard(
            plan: plan,
            prepared: _rawPrepared,
            onPrepare: () => setState(() => _rawPrepared = true),
          );
          final Widget certifiedCard = _CertifiedExportCard(
            reviewable: reviewable,
            courtTier: _courtTier,
            certifiedUsed: _certifiedUsed,
            previewTampered: _previewTampered,
            authorization: _certifiedAuth,
            attestation: _attestation,
            onTierChanged: (bool v) => setState(() => _courtTier = v),
            onUsedChanged: (int v) => setState(() => _certifiedUsed = v.clamp(0, 3)),
            onTamperedChanged: (bool v) => setState(() {
              _previewTampered = v;
              _attestation = null; // a stale attestation for the other chain would mislead
            }),
            onGenerate: _generateCertified,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text("$_demoChildName's archive, for the one reader who must trust it",
                  style: textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                  'Two different files, for two different jobs. One of them is never behind a paywall.',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Expanded(child: rawCard),
                  const SizedBox(width: 16),
                  Expanded(child: certifiedCard),
                ])
              else
                Column(children: <Widget>[rawCard, const SizedBox(height: 16), certifiedCard]),
              const SizedBox(height: 20),
              const _FootNote(),
            ],
          );
        }),
      ),
    );
  }
}

class _RawExportCard extends StatelessWidget {
  const _RawExportCard({required this.plan, required this.prepared, required this.onPrepare});
  final ExportChunkPlan plan;
  final bool prepared;
  final VoidCallback onPrepare;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.lock_open_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            // Expanded + ellipsis, not a bare Text: at the Fold5 cover width
            // (344px) the sibling "Certified export" header overflowed its
            // Row by 18px with this exact shape — fixed there and mirrored
            // here so this card doesn't regress the same way later.
            Expanded(child: Text('Raw export', style: textTheme.titleMedium,
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          const Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            _Badge('FREE'),
            _Badge('EVERY TIER'),
            _Badge('EVEN AFTER CANCELLATION'),
          ]),
          const SizedBox(height: 12),
          Text(
              'Every message, calendar entry, medication log, and photo in her archive, '
              'as plain files you keep. This never requires a paid plan, and letting your '
              'subscription lapse never locks it away — that is a standing rule here, not a promotion.',
              style: textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text('WHAT’S INCLUDED', style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 0.6, color: scheme.primary)),
          const SizedBox(height: 8),
          for (final String item in _rawManifest)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                const Text('•  '),
                Expanded(child: Text(item, style: textTheme.bodyMedium)),
              ]),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: scheme.surface, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${formatBytes(plan.totalBytes)} total — chunked under the transfer ceiling',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'Split into ${plan.chunkCount} files of ${formatBytes(plan.ceilingBytes)} or less, '
                  'so it can actually be attached to an email or uploaded to a portal with a size limit.',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onPrepare,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Prepare raw export'),
            ),
          ),
          if (prepared) ...<Widget>[
            const SizedBox(height: 12),
            Text('Part 1 of ${plan.chunkCount} — ${formatBytes(plan.chunkSizes.first)}',
                style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 4),
            Text(
                plan.chunkCount > 1
                    ? '…and ${plan.chunkCount - 1} more, generated the same way.'
                    : 'That’s the whole export — it fits under the ceiling in one file.',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
                'No backend exists yet to actually generate these files in this preview build — '
                'this is exactly what you’d receive.',
                style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: scheme.outline)),
          ],
        ]),
      ),
    );
  }
}

class _CertifiedExportCard extends StatelessWidget {
  const _CertifiedExportCard({
    required this.reviewable,
    required this.courtTier,
    required this.certifiedUsed,
    required this.previewTampered,
    required this.authorization,
    required this.attestation,
    required this.onTierChanged,
    required this.onUsedChanged,
    required this.onTamperedChanged,
    required this.onGenerate,
  });

  /// §8.12.3's real width rule (`reviewableAt()`, ported above). Below it,
  /// this card shows ONLY the description and the honest
  /// `requestConfirmation` copy — no preview controls, no generate button,
  /// no attestation panel. Rendering the full review UI on a 344px Fold-
  /// cover screen would directly contradict that copy's own promise.
  final bool reviewable;

  final bool courtTier;
  final int certifiedUsed;
  final bool previewTampered;
  final ExportAuthorization authorization;
  final Attestation? attestation;
  final ValueChanged<bool> onTierChanged;
  final ValueChanged<int> onUsedChanged;
  final ValueChanged<bool> onTamperedChanged;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.verified_outlined, color: scheme.tertiary),
            const SizedBox(width: 8),
            // Expanded + ellipsis: at the Fold5 cover width (344px) this Row
            // overflowed by 18px with a bare Text here — "Certified export"
            // plus the icon didn't fit the card's ~272px inner width.
            Expanded(child: Text('Certified export', style: textTheme.titleMedium,
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          Text(
              'Tamper-evident, hash-chained, court-formatted, with an attestation page a reader '
              'can verify without taking our word for it. One free copy per guardian every rolling '
              'year; Court tier covers any more than that.',
              style: textTheme.bodyMedium),
          if (reviewable) ...<Widget>[
            const SizedBox(height: 16),
            _PreviewControls(
              courtTier: courtTier, certifiedUsed: certifiedUsed, previewTampered: previewTampered,
              onTierChanged: onTierChanged, onUsedChanged: onUsedChanged,
              onTamperedChanged: onTamperedChanged,
            ),
            const SizedBox(height: 16),
            _AuthorizationBanner(authorization),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: authorization.ok ? onGenerate : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Generate certified export'),
              ),
            ),
            if (attestation != null) ...<Widget>[
              const SizedBox(height: 16),
              _AttestationPanel(attestation!),
            ],
          ] else ...<Widget>[
            const SizedBox(height: 16),
            Container(
              key: const Key('needsBiggerScreenNotice'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Icon(Icons.desktop_windows_outlined, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(requestConfirmation, style: textTheme.bodySmall)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PreviewControls extends StatelessWidget {
  const _PreviewControls({
    required this.courtTier,
    required this.certifiedUsed,
    required this.previewTampered,
    required this.onTierChanged,
    required this.onUsedChanged,
    required this.onTamperedChanged,
  });
  final bool courtTier;
  final int certifiedUsed;
  final bool previewTampered;
  final ValueChanged<bool> onTierChanged;
  final ValueChanged<int> onUsedChanged;
  final ValueChanged<bool> onTamperedChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('PREVIEW CONTROLS (this build only — not a real setting)',
              style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700, letterSpacing: 0.4, color: scheme.outline)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            Text('Plan:', style: textTheme.bodySmall),
            ChoiceChip(label: const Text('Not Court'), selected: !courtTier,
                onSelected: (_) => onTierChanged(false)),
            ChoiceChip(label: const Text('Court'), selected: courtTier,
                onSelected: (_) => onTierChanged(true)),
          ]),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(child: Text('Certified exports used this year',
                style: textTheme.bodySmall)),
            IconButton(
                onPressed: () => onUsedChanged(certifiedUsed - 1),
                icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(width: 24, child: Text('$certifiedUsed', textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(
                onPressed: () => onUsedChanged(certifiedUsed + 1),
                icon: const Icon(Icons.add_circle_outline)),
          ]),
          // Wrapped in its own transparent Material: the surrounding
          // Container above carries a background color, and a ListTile's ink
          // splashes paint on the nearest Material ancestor — without this,
          // Flutter's own debug check flags them as invisible against it.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Preview: a file altered after export',
                  style: textTheme.bodySmall),
              value: previewTampered,
              onChanged: onTamperedChanged,
            ),
          ),
        ]),
      );
  }
}

class _AuthorizationBanner extends StatelessWidget {
  const _AuthorizationBanner(this.auth);
  final ExportAuthorization auth;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    late final Color bg;
    late final IconData icon;
    late final String text;
    if (auth.ok && auth.free) {
      bg = scheme.secondaryContainer;
      icon = Icons.check_circle_outline;
      text = 'Included — this one is free.';
    } else if (auth.ok) {
      bg = scheme.tertiaryContainer;
      icon = Icons.workspace_premium_outlined;
      text = 'Included with Court tier.';
    } else {
      bg = scheme.errorContainer;
      icon = Icons.info_outline;
      text = "This year's free certified export is already used. Court tier covers "
          'any additional ones — upgrading is never required to keep any of her files, '
          'only to certify more than one copy a year.';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class _AttestationPanel extends StatelessWidget {
  const _AttestationPanel(this.att);
  final Attestation att;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: att.chainVerified ? scheme.outlineVariant : scheme.error, width: att.chainVerified ? 1 : 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(att.chainVerified ? Icons.verified : Icons.error_outline,
              color: att.chainVerified ? scheme.primary : scheme.error, size: 20),
          const SizedBox(width: 8),
          Text(att.chainVerified ? 'Chain verified' : 'VERIFICATION FAILED',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700,
                  color: att.chainVerified ? null : scheme.error)),
        ]),
        const SizedBox(height: 8),
        Text('${att.entryCount} entries · seq ${att.firstSeq ?? '—'}–${att.lastSeq ?? '—'}',
            style: textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('HEAD HASH', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        SelectableText(att.headHash, style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 8),
        Text('BUNDLE HASH', style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        SelectableText(att.bundleHash, style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 8),
        Text(att.statement, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: 0.4, color: scheme.onPrimary)),
    );
  }
}

class _FootNote extends StatelessWidget {
  const _FootNote();
  @override
  Widget build(BuildContext context) => Text(
      'Pricing the evidence of your own life behind a paywall was ruled out on principle here — '
      'raw export stays free and unlimited, on every tier, whether or not a subscription is active. '
      'Only the certified copy, and only past the first free one each year, ever asks for a plan.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline));
}

// ================================================================ live =====
// The real network call. Mirrors child_home_live.dart's own shape exactly
// (required baseUrl/childId, injectable httpClient, devLoginFor -> OliveApi,
// loading/error/ready states with a retry affordance) with one addition this
// screen actually needs and child_home_live.dart's endpoints don't: a
// DENIED state, distinct from a network/server error, because
// authorizeExport() saying no is an expected, correctly-functioning outcome
// of this screen's own business rule — not a failure to render honestly
// around.
enum _LiveExportState { loading, error, denied, ready }

class LiveCourtExportScreen extends StatefulWidget {
  const LiveCourtExportScreen({
    super.key,
    required this.baseUrl,
    required this.guardianId,
    required this.childId,
    this.httpClient,
  });

  final String baseUrl;
  /// The app_user id logging in AS the requesting guardian — devLoginFor's
  /// `userId`, distinct from [childId] (whose export is being requested).
  final String guardianId;
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient).
  final http.Client? httpClient;

  @override
  State<LiveCourtExportScreen> createState() => _LiveCourtExportScreenState();
}

class _LiveCourtExportScreenState extends State<LiveCourtExportScreen> {
  _LiveExportState _state = _LiveExportState.loading;
  String _errorMessage = '';
  String _denialReason = '';
  String _denialMessage = '';
  bool _free = false;
  Attestation? _attestation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LiveExportState.loading);
    try {
      final token = await devLoginFor(widget.baseUrl,
          userId: widget.guardianId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final result = await api.fetchCertifiedExport(widget.childId);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      final Map<String, dynamic> att = result['attestation'] as Map<String, dynamic>;
      setState(() {
        _free = result['free'] as bool? ?? false;
        _attestation = Attestation(
          childId: att['childId'] as String,
          generatedAt: att['generatedAt'] as String,
          entryCount: att['entryCount'] as int,
          firstSeq: att['firstSeq'] as int?,
          lastSeq: att['lastSeq'] as int?,
          headHash: att['headHash'] as String,
          bundleHash: att['bundleHash'] as String,
          chainVerified: att['chainVerified'] as bool,
          statement: att['statement'] as String,
        );
        _state = _LiveExportState.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        // A real, specific denial from authorizeExport() (or the
        // guardianship check ahead of it) — honest, not a crash, not
        // treated the same as an unreachable server.
        setState(() {
          _denialReason = e.error;
          _denialMessage = e.message ?? 'Certified export was not authorized.';
          _state = _LiveExportState.denied;
        });
      } else {
        setState(() {
          _errorMessage = '${e.statusCode}: ${e.error}';
          _state = _LiveExportState.error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _state = _LiveExportState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Court export')),
      // LayoutBuilder, not MediaQuery.sizeOf — the ACTUAL available width
      // for this widget subtree is what §8.12.3's review gate cares about,
      // matching CourtExportScreen's own already-correct approach above.
      // (MediaQuery.sizeOf reflects the whole app window, which happens to
      // equal this most of the time but is a different, less precise
      // question — and, found the hard way while testing this exact gate,
      // does not reliably track a test's own `setSurfaceSize` the way a
      // real device rotation/resize would; LayoutBuilder's constraints do.)
      body: SafeArea(child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            _buildBody(context, scheme, textTheme, constraints.maxWidth)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme, TextTheme textTheme, double width) {
    switch (_state) {
      case _LiveExportState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LiveExportState.error:
        return Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(Icons.cloud_off, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_errorMessage, textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ));
      case _LiveExportState.denied:
        return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Icon(Icons.info_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(child: Text('Certified export not authorized',
                    style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: scheme.onErrorContainer))),
              ]),
              const SizedBox(height: 12),
              Text(_denialMessage,
                  style: textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer)),
              const SizedBox(height: 8),
              Text('REASON: $_denialReason',
                  style: textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace', color: scheme.onErrorContainer)),
            ]),
          ),
          const SizedBox(height: 16),
          Text(
              'Raw export is unaffected by this — it stays free, unlimited, on every '
              'tier, whether or not this denial applies.',
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Check again')),
        ]);
      case _LiveExportState.ready:
        final Attestation att = _attestation!;
        return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Container(width: double.infinity,
              color: scheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                  'Live: this attestation is real, generated just now from her actual '
                  'handover log.',
                  style: textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _free ? scheme.secondaryContainer : scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: <Widget>[
              Icon(_free ? Icons.check_circle_outline : Icons.workspace_premium_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  _free ? 'Included — this one is free.' : 'Included with Court tier.',
                  style: textTheme.bodySmall)),
            ]),
          ),
          const SizedBox(height: 16),
          // Same real §8.12.3 width rule as the demo build's
          // _CertifiedExportCard above — this is the production-wired
          // screen, so it is the one that actually matters. A real
          // attestation was already fetched by the time this state is
          // reached (see _load()); it is just not RENDERED narrow, per
          // requestConfirmation's own honest copy.
          if (reviewableAt(width))
            _AttestationPanel(att)
          else
            Container(
              key: const Key('needsBiggerScreenNotice'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Icon(Icons.desktop_windows_outlined, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(requestConfirmation, style: textTheme.bodySmall)),
              ]),
            ),
        ]);
    }
  }
}
