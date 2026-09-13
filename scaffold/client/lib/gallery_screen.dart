// OLIVE BRANCH — the gallery. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — CHANGELOG v0.49.61).
// MASTERFILE §9.10.11. Renders MARKUP screen 'gallery': "Year-grouped
// works; past two thousand, paginate by era."
//
// "A five-year-old's best work is usually made of cardboard and glue." The
// gallery is medium-agnostic on purpose: a photographed cardboard dragon and
// a digital painting hang in an IDENTICAL frame, at the same size, with no
// badge ranking one above the other. `frameFor()` below is that guarantee
// made testable rather than aspirational, exactly as MASTERFILE names it —
// see gallery_screen_test.dart's "identical frame for every medium" case,
// which compares the actual BoxDecoration objects, not a screenshot.
//
// It compiles OLDEST-FIRST ("reads as a growing-up rather than a best-of"),
// and uses `Artifact` from archive_models.dart — the same ported archive.ts
// data model year_book.dart compiles from, since both screens render slices
// of one archive.
//
// Two rules this file holds itself to:
//   - From sixteen, she can hide a work; a guardian never can, in either
//     direction. So a hidden piece is not merely uneditable here — it is
//     entirely ABSENT from this view: no tile, no "1 hidden" count, no trace.
//     Surfacing even a count would leak the fact of a hidden work back to the
//     one person the hide is *from*.
//   - Past two thousand VISIBLE pieces, this screen stops trying to lay out
//     the whole archive at once and paginates by era (`eraForYear()`) instead
//     — a `SliverGrid` per year inside one `CustomScrollView`, so only the
//     selected era's slivers are ever built, not two thousand widgets.
import 'package:flutter/material.dart';

import 'archive_models.dart';

// ==================================================================== demo =
// In-memory only — see api_client.dart: nothing backs this yet. Deterministic
// generation (a tiny linear congruential generator, not `dart:math`'s
// `Random`) so the same seed always produces the same collection, the same
// way packages/storyteller's `generate(seed)` does for its own demo content.

class GalleryPiece {
  const GalleryPiece({required this.artifact, this.hiddenFromGuardian = false});
  final Artifact artifact;
  /// §21.2 — from sixteen, hiding a work is HERS alone to do or undo. This
  /// flag exists only so the demo can prove the guardian view honors that;
  /// there is no UI anywhere in this file that can set or clear it.
  final bool hiddenFromGuardian;
}

const List<String> galleryKinds = <String>[
  'drawing', 'digital_paint', 'colouring', 'collage', 'photo', 'photo_of_object',
];

class _Lcg {
  _Lcg(this._state);
  int _state;
  int _next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state;
  }

  int nextInt(int max) => _next() % max;
}

/// Deterministic demo collection. [count] past 2,000 is exactly the case
/// §9.10.11 asks this screen to handle, so the default build uses one.
List<GalleryPiece> generateGalleryDemo({required int count, required int seed}) {
  final _Lcg rng = _Lcg(seed);
  const List<int> years = <int>[2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026];
  final List<GalleryPiece> out = <GalleryPiece>[];
  for (int i = 0; i < count; i++) {
    final int year = years[rng.nextInt(years.length)];
    final int month = 1 + rng.nextInt(12);
    final int day = 1 + rng.nextInt(28);
    final String kind = galleryKinds[rng.nextInt(galleryKinds.length)];
    // Rare, and only meaningful from age sixteen in the real product — kept
    // rare here too, so the "never a trace" assertion has a real needle to
    // find in the haystack rather than an empty case.
    final bool hidden = rng.nextInt(400) == 0;
    out.add(GalleryPiece(
      artifact: Artifact(
        id: 'gal_$i',
        childId: 'ivy',
        kind: kind,
        storageKey: 'demo://gallery/$i',
        capturedAt: DateTime(year, month, day),
        capturedTz: 'local',
        preserved: true,
        authorId: 'ivy',
      ),
      hiddenFromGuardian: hidden,
    ));
  }
  return out;
}

// =============================================================== grouping =

const int galleryPaginationThreshold = 2000;

String eraForYear(int year) {
  if (year <= 2020) return 'Little one';
  if (year <= 2023) return 'Growing up';
  return 'These days';
}

const List<String> eraOrder = <String>['Little one', 'Growing up', 'These days'];

List<GalleryPiece> visiblePieces(List<GalleryPiece> all) {
  final List<GalleryPiece> out =
      all.where((GalleryPiece p) => !p.hiddenFromGuardian).toList();
  out.sort((GalleryPiece a, GalleryPiece b) =>
      a.artifact.capturedAt.compareTo(b.artifact.capturedAt));
  return out;
}

Map<String, List<GalleryPiece>> groupByEra(List<GalleryPiece> pieces) {
  final Map<String, List<GalleryPiece>> out = <String, List<GalleryPiece>>{};
  for (final GalleryPiece p in pieces) {
    (out[eraForYear(p.artifact.capturedAt.year)] ??= <GalleryPiece>[]).add(p);
  }
  return out;
}

Map<int, List<GalleryPiece>> groupByYear(List<GalleryPiece> pieces) {
  final Map<int, List<GalleryPiece>> out = <int, List<GalleryPiece>>{};
  for (final GalleryPiece p in pieces) {
    (out[p.artifact.capturedAt.year] ??= <GalleryPiece>[]).add(p);
  }
  for (final List<GalleryPiece> list in out.values) {
    list.sort((GalleryPiece a, GalleryPiece b) =>
        a.artifact.capturedAt.compareTo(b.artifact.capturedAt));
  }
  return out;
}

String yearRangeLabel(List<GalleryPiece> pieces) {
  if (pieces.isEmpty) return '';
  final List<int> years = pieces.map((GalleryPiece p) => p.artifact.capturedAt.year).toList()
    ..sort();
  return years.first == years.last ? '${years.first}' : '${years.first}–${years.last}';
}

// ================================================================== frame =

// 16, not the home-tile-specific 14 — the codebase's corner-radius audit
// reserves 14 exclusively for the child_home/guardian_home action-tile
// pairing, and assigns 16 to photo/image frames specifically.
const double _frameRadius = 16;

/// MASTERFILE §9.10.11 names this exact function and treats its existence as
/// the difference between an aspiration and a testable claim: "frameFor()
/// returns an identical frame for every medium." [kind] is intentionally
/// unused in the body — that IS the guarantee, not an oversight.
BoxDecoration frameFor(ColorScheme scheme, String kind) => BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(_frameRadius),
      border: Border.all(color: scheme.outlineVariant),
      boxShadow: const <BoxShadow>[
        BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Color(0x22000000)),
      ],
    );

IconData iconForGalleryKind(String kind) => switch (kind) {
      'drawing' => Icons.brush_outlined,
      'digital_paint' => Icons.palette_outlined,
      'colouring' => Icons.format_color_fill_outlined,
      'collage' => Icons.auto_awesome_mosaic_outlined,
      'photo' => Icons.photo_camera_outlined,
      'photo_of_object' => Icons.emoji_objects_outlined,
      _ => Icons.image_outlined,
    };

const List<String> _monthAbbr = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String shortDate(DateTime d) => '${_monthAbbr[d.month - 1]} ${d.day}';

// ===================================================================== UI =

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.debugPieces});

  /// Testing hook only — production call sites should omit this and let the
  /// screen generate its own seeded demo collection (same convention as
  /// MaturationLadderScreen's [now]). Exists because the seeded RNG datasets
  /// below can never deterministically land on zero visible pieces, and the
  /// honest empty state deserves real coverage like any other state.
  final List<GalleryPiece>? debugPieces;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final List<GalleryPiece> _full = generateGalleryDemo(count: 2200, seed: 20260804);
  final List<GalleryPiece> _small = generateGalleryDemo(count: 42, seed: 7);

  bool _fullDemo = true;
  String? _selectedEra;

  List<GalleryPiece> get _dataset => widget.debugPieces ?? (_fullDemo ? _full : _small);

  @override
  void initState() {
    super.initState();
    _selectedEra = _defaultEra(visiblePieces(_dataset));
  }

  String? _defaultEra(List<GalleryPiece> visible) {
    if (visible.length <= galleryPaginationThreshold) return null;
    final Map<String, List<GalleryPiece>> grouped = groupByEra(visible);
    // Oldest era first — the exhibition reads as a growing-up, so pagination
    // opens on the beginning of it, not the most recent page.
    return eraOrder.firstWhere(grouped.containsKey, orElse: () => grouped.keys.first);
  }

  void _setFullDemo(bool value) {
    setState(() {
      _fullDemo = value;
      _selectedEra = _defaultEra(visiblePieces(_dataset));
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<GalleryPiece> visible = visiblePieces(_dataset);
    final bool paginated = visible.length > galleryPaginationThreshold;
    final Map<String, List<GalleryPiece>> byEra = paginated ? groupByEra(visible) : const <String, List<GalleryPiece>>{};
    final List<GalleryPiece> toRender =
        paginated ? (byEra[_selectedEra] ?? const <GalleryPiece>[]) : visible;

    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: SafeArea(
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('Everything she has ever made, in one room.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('${visible.length} pieces, oldest first',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _DemoSizeToggle(fullDemo: _fullDemo, onChanged: _setFullDemo),
          ),
          if (paginated)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _EraSelector(
                counts: <String, int>{
                  for (final MapEntry<String, List<GalleryPiece>> e in byEra.entries)
                    e.key: e.value.length,
                },
                yearRanges: <String, String>{
                  for (final MapEntry<String, List<GalleryPiece>> e in byEra.entries)
                    e.key: yearRangeLabel(e.value),
                },
                selected: _selectedEra,
                onSelected: (String era) => setState(() => _selectedEra = era),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _GalleryGrid(key: ValueKey<String>('$_fullDemo-$_selectedEra'), pieces: toRender),
            ),
          ),
          const _FootNote(),
        ]),
      ),
    );
  }
}

class _DemoSizeToggle extends StatelessWidget {
  const _DemoSizeToggle({required this.fullDemo, required this.onChanged});
  final bool fullDemo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        // Wrap, not Row+Spacer: at the Fold5 cover width (344px) the label's
        // natural width plus both chips overflowed a Row by 348px — even
        // after the label alone was made flexible, the two chips ALONE still
        // didn't fit the available ~312px (still 42px over), so this needs a
        // real second line on narrow screens, not just a shrinking label.
        // Wrap never overflows: it drops to a second line instead.
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text('PREVIEW COLLECTION (demo data)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700, letterSpacing: 0.4,
                  color: Theme.of(context).colorScheme.outline)),
          ChoiceChip(label: const Text('Small'), selected: !fullDemo, onSelected: (_) => onChanged(false)),
          ChoiceChip(label: const Text('Full (2,200+)'), selected: fullDemo, onSelected: (_) => onChanged(true)),
        ],
      );
}

class _EraSelector extends StatelessWidget {
  const _EraSelector({
    required this.counts, required this.yearRanges, required this.selected, required this.onSelected,
  });
  final Map<String, int> counts;
  final Map<String, String> yearRanges;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String era in eraOrder)
            if (counts.containsKey(era))
              ChoiceChip(
                label: Text('$era (${yearRanges[era]}) · ${counts[era]}'),
                selected: selected == era,
                onSelected: (_) => onSelected(era),
              ),
        ],
      );
}

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({super.key, required this.pieces});
  final List<GalleryPiece> pieces;

  @override
  Widget build(BuildContext context) {
    if (pieces.isEmpty) {
      final ColorScheme scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(Icons.photo_outlined, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Nothing here yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      );
    }
    final Map<int, List<GalleryPiece>> byYear = groupByYear(pieces);
    final List<int> years = byYear.keys.toList()..sort();
    return CustomScrollView(slivers: <Widget>[
      for (final int year in years) ...<Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('$year',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) => _Tile(byYear[year]![i]),
              childCount: byYear[year]!.length,
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.piece);
  final GalleryPiece piece;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Artifact a = piece.artifact;
    return Semantics(
      label: "Something she made, ${shortDate(a.capturedAt)}",
      child: Container(
        decoration: frameFor(scheme, a.kind),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(iconForGalleryKind(a.kind), size: 26, color: scheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(shortDate(a.capturedAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _FootNote extends StatelessWidget {
  const _FootNote();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Cardboard counts. It always did.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.outline)),
      );
}
