// OLIVE BRANCH — the Year Book. Verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). MASTERFILE §2.10, §9.8.2. Renders MARKUP screen 'yearbook':
// "A year of her, preserved."
//
// This screen is a thin UI over `compileYearBook()` (archive_models.dart, a
// 1:1 port of packages/archive/src/archive.ts) — every number on it, printable
// or not, is the function's real return value for the selected year, not a
// hand-tuned mock. Two of its rules are load-bearing enough to restate here:
//   - Only PRESERVED artifacts are compiled. An artifact still on a retention
//     clock might not exist by the time a book is printed, so including it
//     would promise a page that later has a hole in it.
//   - Under twelve items is a slideshow, not a book (`printable`). This
//     screen says that honestly rather than offering to print one anyway —
//     the same "recorded, not glossed over" posture the rest of the app takes
//     for anything it can't yet really do.
// A guardian surface (MARKUP §03), not the child's — see MARKUP.html's own
// section grouping, which places 'yearbook' among guardianHome/export/gallery
// rather than the child-surface block above it.
import 'package:flutter/material.dart';

import 'archive_models.dart';
import 'form_factors.dart' as ff;

// ==================================================================== demo =
// In-memory only — see api_client.dart: there is no /v1/children/:id/yearbook
// endpoint yet (it's listed as Phase 3/4 in MASTERFILE's own route table).
// Deterministic, not random, so the same run always shows the same book.

const String _childName = 'Ivy';
const List<String> _kindsCycle = <String>[
  'video_msg', 'voice_note', 'drawing', 'homework', 'photo', 'call_clip',
];

List<Artifact> _demoArtifacts() {
  final List<Artifact> out = <Artifact>[];
  int nextId = 0;

  void addYear({
    required int year,
    required int count,
    required int unpreservedCount,
    required List<String> zones,
  }) {
    for (int i = 0; i < count; i++) {
      final int month = 1 + (i * 3) % 12;
      final int day = 1 + (i * 7) % 27;
      out.add(Artifact(
        id: 'yb_${nextId++}',
        childId: 'ivy',
        kind: _kindsCycle[i % _kindsCycle.length],
        storageKey: 'demo://yearbook/$nextId',
        capturedAt: DateTime(year, month, day),
        capturedTz: zones[i % zones.length],
        preserved: i >= unpreservedCount,
        authorId: 'ivy',
      ));
    }
  }

  // 2023 — five pieces. Deliberately below the printable threshold, so the
  // "this isn't a book yet" state is a real, reachable case, not just a
  // theoretical branch.
  addYear(year: 2023, count: 5, unpreservedCount: 0, zones: <String>["Mom's — EST"]);
  // 2024 — sixteen captured, two never preserved (on their own retention
  // clock, and gone by now), fourteen make the book.
  addYear(year: 2024, count: 16, unpreservedCount: 2, zones: <String>["Mom's — EST", "Dad's — CST"]);
  // 2025 — the rich year: both households, well past the threshold.
  addYear(year: 2025, count: 24, unpreservedCount: 0, zones: <String>["Mom's — EST", "Dad's — CST"]);
  // 2026 — this year, still in progress.
  addYear(year: 2026, count: 6, unpreservedCount: 0, zones: <String>["Mom's — EST"]);

  return out;
}

IconData _iconForKind(String kind) => switch (kind) {
      'video_msg' => Icons.videocam_outlined,
      'voice_note' => Icons.mic_none_outlined,
      'drawing' => Icons.brush_outlined,
      'homework' => Icons.menu_book_outlined,
      'photo' => Icons.photo_outlined,
      'call_clip' => Icons.call_outlined,
      _ => Icons.star_border,
    };

const List<String> _monthAbbr = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _shortDate(DateTime d) => '${_monthAbbr[d.month - 1]} ${d.day}';

// ===================================================================== UI =

class YearBookScreen extends StatefulWidget {
  const YearBookScreen({super.key});

  @override
  State<YearBookScreen> createState() => _YearBookScreenState();
}

class _YearBookScreenState extends State<YearBookScreen> {
  late final List<Artifact> _all = _demoArtifacts();
  late final List<int> _years =
      (_all.map((Artifact a) => a.capturedAt.year).toSet().toList()..sort());

  // A specific, known-rich year, so the first thing a reviewer sees is the
  // success state rather than the "not a book yet" edge case.
  int _selectedYear = 2025;

  @override
  Widget build(BuildContext context) {
    final YearBook book = compileYearBook(_all, 'ivy', _selectedYear);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Year book')),
      // On a wide tablet/desktop viewport the single column is only ever
      // capped to a comfortable reading width and centered, never split —
      // the wrapper goes OUTSIDE the AnimatedSwitcher below, which keeps its
      // existing transition completely untouched. Same real columnsAt()
      // gate every other width decision in the app uses.
      body: SafeArea(
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool capWidth = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
          final Widget content = ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('A year of her, preserved.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final int y in _years)
                    ChoiceChip(
                      label: Text('$y'),
                      selected: _selectedYear == y,
                      onSelected: (_) => setState(() => _selectedYear = y),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Column(
                  key: ValueKey<int>(_selectedYear),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CoverCard(book: book, childName: _childName),
                    const SizedBox(height: 16),
                    if (book.places.isNotEmpty) ...<Widget>[
                      _PlacesCard(book.places),
                      const SizedBox(height: 16),
                    ],
                    for (final YearBookSection section in book.sections) ...<Widget>[
                      _SectionCard(section: section, artifacts: _all),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                    _PrintableCard(book: book, scheme: scheme),
                  ],
                ),
              ),
            ],
          );
          return capWidth
              ? Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                      child: content))
              : content;
        }),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({required this.book, required this.childName});
  final YearBook book;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: <Color>[scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        // A deliberate, oversized cover-hero numeral — the same one-off
        // treatment §8.2.5's sleeps-countdown documents, not a candidate for
        // a textTheme role.
        Text('${book.year}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text("$childName's year", style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text('${book.artifactCount} pieces preserved',
            style: textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
      ]),
    );
  }
}

class _PlacesCard extends StatelessWidget {
  const _PlacesCard(this.places);
  final List<YearBookPlace> places;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('WHERE THIS YEAR HAPPENED',
              style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700, letterSpacing: 0.6, color: scheme.primary)),
          const SizedBox(height: 8),
          for (final YearBookPlace p in places)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: <Widget>[
                Expanded(child: Text(p.zone, style: textTheme.bodyMedium)),
                Text('${p.days} day${p.days == 1 ? '' : 's'} captured',
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.artifacts});
  final YearBookSection section;
  final List<Artifact> artifacts;

  @override
  Widget build(BuildContext context) {
    final Map<String, Artifact> byId = <String, Artifact>{
      for (final Artifact a in artifacts) a.id: a,
    };
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text(section.title,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text('${section.artifactIds.length}',
                style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String id in section.artifactIds)
                if (byId[id] case final Artifact a) _PieceChip(a),
            ],
          ),
        ]),
      ),
    );
  }
}

class _PieceChip extends StatelessWidget {
  const _PieceChip(this.artifact);
  final Artifact artifact;

  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(_iconForKind(artifact.kind), size: 22),
          const SizedBox(height: 4),
          Text(_shortDate(artifact.capturedAt), style: Theme.of(context).textTheme.labelSmall),
        ]),
      );
}

class _PrintableCard extends StatelessWidget {
  const _PrintableCard({required this.book, required this.scheme});
  final YearBook book;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    if (book.printable) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.auto_stories_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('Ready to print — ${book.artifactCount} pieces make a proper Year Book',
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Print fulfilment isn\'t connected yet in this preview build — §9.15.'))),
              child: const Text('Order the printed Year Book'),
            ),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Icon(Icons.info_outline, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              'Not a book yet — just ${book.artifactCount} piece${book.artifactCount == 1 ? '' : 's'} so far. '
              'Under twelve, this would print as a slideshow, not a Year Book, so we say so rather than '
              'offer to print one.',
              style: textTheme.bodySmall),
        ),
      ]),
    );
  }
}
