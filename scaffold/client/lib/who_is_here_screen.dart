// OLIVE BRANCH — who is here. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — also manually built
// and run via `flutter analyze` / `flutter test` this session; CHANGELOG
// v0.49.61). MASTERFILE §17.1, §8.5.3.
//
// Closes the one line in MASTERFILE's own status table that named a real
// gap: "Single-guardian mode (§17.1) | PREDICATE | isSingleGuardianViable()
// tested; no UI to exercise it." This screen is that UI.
//
// Ports the one function that matters from
// packages/family-graph/src/authorize.ts — isSingleGuardianViable(), same
// name, same predicate (a "live" edge is unclosed, unrestricted, off the
// 'none' ladder rung, unexpired, and role == guardian). The rest of that
// file governs ACTIONS (can(), the Deny enum) and has no business here —
// this screen answers a much smaller, child-facing question: not "what can
// they do", but "who does she see".
//
// §8.5.3, in full, is the spec this screen exists to satisfy:
//  - One live guardian → no choice presented at all. Not a shortcut: asking
//    a child to pick between Mummy and Daddy on a co-parenting product's
//    first screen would be tactless, and §2.4 keeps her away from the
//    machinery of conflict. She is not choosing which parent exists; she is
//    being told who is already here.
//  - A parent who has not accepted the invitation appears greyed, and
//    nothing more. No nudge, no "invite them", no empty state implying
//    something is missing (§2.12, §17.5).
//  - Nobody has joined yet → a supported state with neutral copy: "Nobody is
//    here yet. We will let you know when they are."
//  - Two have joined → both are selected by default, and the LAST one
//    cannot be deselected. She may never end up with nobody.
//  - Labels are each guardian's OWN word — Daddy, Papa, Baba, Mum, Mama,
//    Nana — never hard-coded "Mommy"/"Daddy".
import 'package:flutter/material.dart';

// ======================================================== authorize.ts port =
/// A guardian's edge into one child's graph, trimmed to exactly the fields
/// isSingleGuardianViable() and this screen need. Not the full
/// family-graph Edge shape (role/scope/Action) — that stays TS-side.
class GuardianEdge {
  const GuardianEdge({
    required this.userId,
    required this.label,
    this.acceptedAt,
    this.closedAt,
    this.restricted = false,
    this.ladderStep = 'open',
    this.expiresAt,
  });

  final String userId;
  /// Her own word for them — never hard-coded. See file header.
  final String label;
  /// Null while the invitation is outstanding.
  final DateTime? acceptedAt;
  final DateTime? closedAt;
  final bool restricted;
  final String ladderStep;
  final DateTime? expiresAt;
}

bool _isLive(GuardianEdge e, DateTime now) =>
    e.closedAt == null &&
    !e.restricted &&
    e.ladderStep != 'none' &&
    (e.expiresAt == null || e.expiresAt!.isAfter(now));

/// 1:1 port of packages/family-graph/src/authorize.ts's
/// isSingleGuardianViable(edges, childId, now) — same semantics: is at
/// least one live, accepted guardian present. (childId is implicit here —
/// the caller already filtered edges to one child, same as every other
/// screen in this codebase that ports a pure function rather than a route.)
bool isSingleGuardianViable(List<GuardianEdge> edges, DateTime now) =>
    edges.where((e) => e.acceptedAt != null && _isLive(e, now)).isNotEmpty;

List<GuardianEdge> _accepted(List<GuardianEdge> edges, DateTime now) =>
    edges.where((e) => e.acceptedAt != null && _isLive(e, now)).toList();

List<GuardianEdge> _pending(List<GuardianEdge> edges, DateTime now) =>
    edges.where((e) => e.acceptedAt == null && _isLive(e, now)).toList();

// ================================================================ the demo ===
final List<GuardianEdge> _demoTwoGuardians = <GuardianEdge>[
  GuardianEdge(userId: 'dad', label: 'Daddy', acceptedAt: DateTime.utc(2024, 1, 1)),
  GuardianEdge(userId: 'mum', label: 'Mama', acceptedAt: DateTime.utc(2024, 1, 3)),
];

final DateTime _demoNow = DateTime.utc(2028, 1, 10);

/// Child-facing. Never a settings affordance, never a nudge to invite anyone
/// — see file header. [edges] defaults to a two-guardian demo family so the
/// screen is meaningful to open on its own; real callers pass the child's
/// actual resolved edges (§5.1).
class WhoIsHereScreen extends StatefulWidget {
  WhoIsHereScreen({super.key, List<GuardianEdge>? edges, DateTime? now,
    this.onSelectionChanged})
    : edges = edges ?? _demoTwoGuardians, now = now ?? _demoNow;

  final List<GuardianEdge> edges;
  final DateTime now;
  /// Fires with the set of userIds currently selected — e.g. who a show or
  /// a message goes to. Never called for the solo-guardian case: there is
  /// no selection to report, only a fact to state.
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<WhoIsHereScreen> createState() => _WhoIsHereScreenState();
}

class _WhoIsHereScreenState extends State<WhoIsHereScreen> {
  late final Set<String> _selected =
      _accepted(widget.edges, widget.now).map((e) => e.userId).toSet();

  void _toggle(String userId) {
    if (_selected.contains(userId)) {
      // The last selected guardian can never be deselected — §8.5.3.
      if (_selected.length <= 1) return;
      setState(() => _selected.remove(userId));
    } else {
      setState(() => _selected.add(userId));
    }
    widget.onSelectionChanged?.call(Set<String>.of(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final List<GuardianEdge> accepted = _accepted(widget.edges, widget.now);
    final List<GuardianEdge> pending = _pending(widget.edges, widget.now);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Who is here')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (accepted.isEmpty)
          const _EmptyState()
        else if (accepted.length == 1)
          // §17.1 — one live guardian: no CHOOSER is presented, ever — a
          // pending second guardian (below, greyed) is informational, not a
          // choice, and does not change this.
          _SoloGuardianCard(key: const Key('soloGuardian'), guardian: accepted.single)
        else
          for (final GuardianEdge g in accepted)
            _GuardianChip(
              key: ValueKey('guardianChipWrap_${g.userId}'),
              guardian: g,
              selected: _selected.contains(g.userId),
              onTap: () => _toggle(g.userId),
              scheme: scheme,
            ),
        for (final GuardianEdge g in pending)
          _PendingGuardianChip(key: Key('pendingChip_${g.userId}'), guardian: g),
      ])),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Text('Nobody is here yet. We will let you know when they are.',
      key: const Key('nobodyHereYet'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant)));
}

class _SoloGuardianCard extends StatelessWidget {
  const _SoloGuardianCard({super.key, required this.guardian});
  final GuardianEdge guardian;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(20),
    child: Row(children: [
      CircleAvatar(radius: 24, child: Text(guardian.label.substring(0, 1))),
      const SizedBox(width: 16),
      Expanded(child: Text(guardian.label,
        style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700))),
    ])));
}

class _GuardianChip extends StatelessWidget {
  const _GuardianChip({super.key, required this.guardian, required this.selected,
    required this.onTap, required this.scheme});
  final GuardianEdge guardian;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: FilterChip(
      // The key lives here, on the actual interactive chip, not on this
      // wrapper — a test taps/inspects the FilterChip directly.
      key: Key('guardianChip_${guardian.userId}'),
      // 48dp minimum tap target (§8.13.2's family of rules).
      label: SizedBox(height: 32, child: Align(alignment: Alignment.centerLeft,
        child: Text(guardian.label))),
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: CircleAvatar(radius: 12, backgroundColor: selected
        ? scheme.primary.withValues(alpha: 0.2) : scheme.surfaceContainerHighest,
        child: Text(guardian.label.substring(0, 1), style: const TextStyle(fontSize: 11))),
    ));
}

/// Greyed, and nothing more — no nudge, no "invite them" affordance, no
/// empty-state implying something is missing. §2.12, §17.5, §8.5.3.
class _PendingGuardianChip extends StatelessWidget {
  const _PendingGuardianChip({super.key, required this.guardian});
  final GuardianEdge guardian;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Opacity(opacity: 0.4, child: Chip(
      label: SizedBox(height: 32, child: Align(alignment: Alignment.centerLeft,
        child: Text(guardian.label))),
      avatar: const CircleAvatar(radius: 12, child: Icon(Icons.hourglass_empty, size: 14)),
    )));
}
