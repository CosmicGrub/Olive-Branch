// OLIVE BRANCH — find the thing. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.12.2,
// §8.14. Renders MARKUP screen 'findThing'.
//
// A 1:1 semantic port of the find-the-thing section of
// packages/activities/src/activities.ts (FindTarget, FindScene,
// FindDifficulty, FIND_LEVELS, buildFindScene, tapFind, findHint) — same
// shapes, same function names, same decoy-placement algorithm, kept close
// enough to audit side by side.
//
// §8.14 calls this "the heaviest activity, and the budget knows it" — the
// assignment note for this group asks explicitly for the asset count to stay
// reasonable. Every item on the scene here, target included, is a single
// Unicode glyph rendered as `Text` — there is no image asset, no sprite
// sheet, and no decode cost per item, at any difficulty, including
// 'fiendish' at 320 items. That is the deliberate answer to the budget
// concern for this screen: zero bitmap assets rather than a smaller number
// of expensive ones. §8.14's actual capability-budget gate (device tier vs.
// declared cost) has no implementation in this preview build — there is no
// backend or device-tier signal to gate against yet — so difficulty
// selection here is a plain, honest choice with no live budget check behind
// it, unlike the real product's `admit()`.
//
// §9.12.2's difficulty table is DECOY COUNT and DECOY SIMILARITY, never a
// timer: "the child who is slower is not worse at looking — she is five." A
// miss does nothing at all — no buzz, no shake, no counter, exactly as with
// a paper puzzle — and a hint gives a quadrant, never the answer.
import 'dart:math';
import 'package:flutter/material.dart';

// =========================================================== ported logic ===
// packages/activities/src/activities.ts — the find-the-thing section.

enum FindDifficulty { gentle, normal, tricky, fiendish }

class FindLevel {
  const FindLevel({required this.decoys, required this.similarGlyphs, required this.maxZoom});
  final int decoys;
  final int similarGlyphs;
  final double maxZoom;
}

const Map<FindDifficulty, FindLevel> findLevels = <FindDifficulty, FindLevel>{
  FindDifficulty.gentle: FindLevel(decoys: 24, similarGlyphs: 2, maxZoom: 2),
  FindDifficulty.normal: FindLevel(decoys: 80, similarGlyphs: 5, maxZoom: 3),
  FindDifficulty.tricky: FindLevel(decoys: 180, similarGlyphs: 9, maxZoom: 4),
  FindDifficulty.fiendish: FindLevel(decoys: 320, similarGlyphs: 14, maxZoom: 5),
};

class FindTarget {
  const FindTarget({required this.label, required this.glyph});
  final String label;
  final String glyph;
}

class FindItem {
  const FindItem({required this.id, required this.glyph, required this.x, required this.y,
    required this.scale, required this.isTarget});
  final String id;
  final String glyph;
  /// Fractions of the canvas, [0, 1] — never a real-world coordinate (P3
  /// governs GPS location, not puzzle layout, but the habit of keeping every
  /// position purely local and relative is deliberate throughout this file).
  final double x, y;
  final double scale;
  final bool isTarget;
}

class FindScene {
  const FindScene({required this.id, required this.target, required this.items,
    required this.maxZoom, required this.difficulty});
  final String id;
  final FindTarget target;
  final List<FindItem> items;
  final double maxZoom;
  final FindDifficulty difficulty;
}

class BuildSceneResult {
  const BuildSceneResult.ok(this.scene) : ok = true;
  const BuildSceneResult.err() : ok = false, scene = null;
  final bool ok;
  final FindScene? scene;
}

/// Difficulty is decoy COUNT and decoy SIMILARITY, never a timer. Similar
/// decoys are placed first — they are what makes it hard, rather than sheer
/// volume — mirroring the TS loop exactly, including its own use of the
/// growing `items` list length as the upper bound for the target's insertion
/// index (so the target can never land strictly after the last decoy).
BuildSceneResult buildFindScene(String id, FindTarget target, List<String> decoyGlyphs,
    FindDifficulty difficulty, Random rand) {
  if (decoyGlyphs.isEmpty) return const BuildSceneResult.err();
  final FindLevel level = findLevels[difficulty]!;
  final List<FindItem> items = <FindItem>[];
  void place(String glyph, bool isTarget, int i) => items.add(FindItem(
    id: '$id-$i', glyph: glyph,
    x: 0.03 + rand.nextDouble() * 0.94, y: 0.03 + rand.nextDouble() * 0.94,
    scale: 0.7 + rand.nextDouble() * 0.6, isTarget: isTarget));

  final List<String> similar = decoyGlyphs.take(level.similarGlyphs).toList();
  for (int i = 0; i < level.decoys; i++) {
    final bool useSimilar = i < level.similarGlyphs * 4 && similar.isNotEmpty;
    final List<String> pool = useSimilar ? similar : decoyGlyphs;
    place(pool[rand.nextInt(pool.length)], false, i);
  }
  // The target goes in last, at a random index, so it is not always on top.
  final int at = rand.nextInt(items.length);
  final FindItem targetItem = FindItem(id: '$id-target', glyph: target.glyph,
    x: 0.05 + rand.nextDouble() * 0.9, y: 0.05 + rand.nextDouble() * 0.9,
    scale: 1, isTarget: true);
  items.insert(at, targetItem);
  return BuildSceneResult.ok(FindScene(
    id: id, target: target, items: items, maxZoom: level.maxZoom, difficulty: difficulty));
}

class TapFindResult {
  const TapFindResult({required this.found, this.nudge});
  final bool found;
  /// Always null in the TS source too — kept for shape fidelity. A miss does
  /// nothing at all: no buzz, no shake, no counter.
  final String? nudge;
}

TapFindResult tapFind(FindScene scene, String itemId) {
  FindItem? item;
  for (final FindItem i in scene.items) {
    if (i.id == itemId) { item = i; break; }
  }
  if (item != null && item.isTarget) return const TapFindResult(found: true);
  return const TapFindResult(found: false);
}

/// A hint, if she asks. Quadrant only — never the answer.
String findHint(FindScene scene) {
  FindItem target = scene.items.first;
  for (final FindItem i in scene.items) {
    if (i.isTarget) { target = i; break; }
  }
  final String vert = target.y < 0.5 ? 'top' : 'bottom';
  final String horiz = target.x < 0.5 ? 'left' : 'right';
  return 'Try the $vert $horiz.';
}

// ================================================================= widget ===

/// §9.10.3 — what gets hidden follows what she is into now. This preview
/// build has no real interests feed (no backend — see api_client.dart), so
/// the target below is a fixed, honest stand-in for "the thing Dad chose
/// this morning," not a claim that personalisation is wired up.
const FindTarget _demoTarget = FindTarget(label: 'her dinosaur', glyph: '🦕');

/// Reptile-and-dinosaur-flavoured glyphs sit first, so they double as the
/// "similar" decoy pool buildFindScene() draws on for the harder levels —
/// never the exact target glyph itself.
const List<String> _demoDecoyGlyphs = <String>[
  '🦖', '🐊', '🦎', '🐢', '🐉', '🐍', '🦴', '🥚',
  '🚗', '⚽', '🌟', '🍎', '🎈', '📚', '🐱', '🚀', '🧸', '🍪',
  '🌈', '🎨', '🐰', '🦋', '🍉', '🌻', '🥕', '🎵', '🧦', '🐌',
  '🪀', '🧩', '🎯', '🥎', '🍩', '🎀', '🐬', '🦔', '🐸', '🦆',
];

class GameFindThingScreen extends StatefulWidget {
  const GameFindThingScreen({super.key, this.debugSeed});

  /// Test-only hook, mirroring the `rand` parameter buildFindScene() already
  /// takes above — real play always uses a fresh, unseeded Random() below.
  /// A packed scene can legitimately place a decoy's tap area over the
  /// target's (§9.12.2's own comment: the target is inserted "at a random
  /// index, so it is not always on top"), which makes an unseeded scene an
  /// unreliable thing to drive a widget test's tap coordinates against. This
  /// lets a test pin a scene layout it has already verified is
  /// non-overlapping, without weakening the real gameplay randomness at all.
  @visibleForTesting
  final int? debugSeed;

  @override
  State<GameFindThingScreen> createState() => _GameFindThingScreenState();
}

class _GameFindThingScreenState extends State<GameFindThingScreen> {
  FindDifficulty _difficulty = FindDifficulty.gentle;
  late FindScene _scene;
  int _sceneCounter = 0;
  bool _found = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _scene = _build();
  }

  FindScene _build() {
    final Random rand = widget.debugSeed != null ? Random(widget.debugSeed) : Random();
    final BuildSceneResult r = buildFindScene(
      'scene-${_sceneCounter++}', _demoTarget, _demoDecoyGlyphs, _difficulty, rand);
    return r.scene!;
  }

  void _newScene({FindDifficulty? difficulty}) => setState(() {
    _difficulty = difficulty ?? _difficulty;
    _scene = _build();
    _found = false;
    _hint = null;
  });

  void _tap(String itemId) {
    if (_found) return;
    final TapFindResult r = tapFind(_scene, itemId);
    // A miss does nothing at all — no buzz, no shake, no counter (§9.12.2).
    if (!r.found) return;
    setState(() { _found = true; _hint = null; });
  }

  void _askForHint() => setState(() => _hint = findHint(_scene));

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Find the thing')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(children: [
            Text(_scene.target.glyph, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 8),
            Expanded(child: Text('Find ${_scene.target.label}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(spacing: 8, children: [
            for (final FindDifficulty d in FindDifficulty.values)
              ChoiceChip(
                label: Text(_label(d)),
                selected: _difficulty == d,
                onSelected: (_) => _newScene(difficulty: d),
              ),
          ])),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(borderRadius: BorderRadius.circular(16),
            child: ColoredBox(color: scheme.surfaceContainerHighest,
              child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                final double w = constraints.maxWidth;
                final double h = constraints.maxHeight;
                return InteractiveViewer(
                  minScale: 1, maxScale: _scene.maxZoom,
                  boundaryMargin: const EdgeInsets.all(40),
                  child: SizedBox(width: w, height: h, child: Stack(children: [
                    for (final FindItem item in _scene.items)
                      Positioned(
                        left: item.x * w - 16, top: item.y * h - 16,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tap(item.id),
                          // A generous tap buffer around a small glyph — a
                          // five-year-old aims with a whole finger (§9.12.3).
                          child: SizedBox(width: 32, height: 32, child: Center(
                            child: Text(item.glyph,
                              style: TextStyle(fontSize: 20 * item.scale)))),
                        ),
                      ),
                  ])),
                );
              })))),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          if (_found)
            _FoundBanner(label: _scene.target.label, onAgain: () => _newScene())
          else
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _askForHint,
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Need a hint?'))),
            ]),
          if (_hint != null && !_found) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_hint!, style: TextStyle(color: scheme.onSurfaceVariant))),
        ])),
      ])),
    );
  }

  String _label(FindDifficulty d) => switch (d) {
    FindDifficulty.gentle => 'Gentle',
    FindDifficulty.normal => 'Normal',
    FindDifficulty.tricky => 'Tricky',
    FindDifficulty.fiendish => 'Fiendish',
  };
}

class _FoundBanner extends StatelessWidget {
  const _FoundBanner({required this.label, required this.onAgain});
  final String label;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text('You found $label!',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 48,
          child: FilledButton.tonal(onPressed: onAgain, child: const Text('Find something new'))),
      ]),
    );
    // A one-shot celebration, not a loop — §8.13.1, §8.13.6.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double t, Widget? child) =>
        Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: 0.9 + 0.1 * t, child: child)),
      child: content,
    );
  }
}
