// OLIVE BRANCH — find it (I-Spy). UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.2,
// §8.11.1, §8.13, §8.4, P2. Renders MARKUP screen 'gamePicker' catalogue
// entry 'findIt'.
//
// Play Together Phase 1, Batch C (docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md) — second of two younger-age,
// icon/color/shape-based activities, minAge 2. A curated scene (a fixed,
// in-repo arrangement of icon "objects" — never a photo, never fetched,
// never generated at runtime) with tappable hidden objects. The mechanic is
// exactly the spec's own words: "the parent describes one, the child taps
// it" — this app needs no speech recognition, no microphone, no free text
// anywhere. Its whole job is to hold curated scenes, track which objects
// have been found THIS round, and offer a real "new scene" action.
//
// CONTENT SOURCE, stated plainly per this codebase's documentation
// discipline: `findScenes` below is three hand-placed, fixed, in-repo
// constants — `yardScene`, `kitchenScene`, `toyBoxScene` — each with its
// own genuinely distinct icon set AND its own genuinely distinct object
// layout (a clean 3x3 grid, an organic scatter, and a corners-plus-
// quadrants arrangement respectively), never the same positions re-skinned
// with different icons.
//
// ICON-FORWARD, per this activity's own open design decision (the spec
// leaves it to this pass's judgment): every object's `name` exists only for
// a screen-reader `Semantics` label and a parent-facing `Tooltip`, never
// rendered as static on-screen label text — leaning toward icon-forward
// minimalism given the minAge-2 audience, matching `game_copy_pattern.dart`
// (Batch C's other activity)'s identical choice, made for the identical
// reason.
//
// DEVICE POSTURE CHANGES REAL CONTENT HERE — the one activity in the whole
// Phase 1 spec where that is true, per the spec's own words: "single column
// → fewer simultaneous hidden objects (a 344px scene has real room limits).
// 2+ columns → a richer scene with more objects." `visibleObjectsFor()`
// below takes the real, tested `form_factors.dart` `columnsAt()` result
// (text-scale-aware, §8.8, exactly like every other posture-driven screen
// this phase built) and returns either the scene's first
// [narrowObjectCount] curated objects or its full curated set — a genuinely
// different NUMBER of tappable things, not a resized layout of the same
// content, proven by a widget test asserting the actual rendered count
// differs (game_find_it_test.dart).
//
// P2 — "$found of $total found" is live gameplay state for the CURRENT
// scene only (the same category as `game_copy_pattern.dart`'s current
// pattern length): it resets to zero on every new scene and is never
// persisted, tallied across sessions, or framed as "your best."
//
// MOTION (§8.13): the only animation is a consequence check-mark pop when
// she finds something — driven strictly by her tap, settles in 180ms,
// never a loop. Nothing on this screen moves on its own.
import 'dart:math';

import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// ================================================================ engine ===

/// One hidden, tappable thing. [name] is a plain-language reference name —
/// never rendered as static on-screen label text, see this file's header.
/// [x]/[y] are fractional (0..1) positions within the scene area.
class FindObject {
  const FindObject(this.id, this.icon, this.name, this.x, this.y);
  final String id;
  final IconData icon;
  final String name;
  final double x;
  final double y;
}

class FindScene {
  const FindScene(this.id, this.title, this.objects);
  final String id;
  final String title;

  /// Curated, hand-placed, FIXED order. The first [narrowObjectCount]
  /// entries are what a narrow posture renders, and are deliberately
  /// ordered to already be well spread on their own (corners + center
  /// before any edge-midpoint), so the narrow subset never needs its own
  /// separate layout — see this file's header.
  final List<FindObject> objects;
}

/// How many objects a single-column (narrow) posture renders — a real,
/// genuine reduction from a scene's full curated set, per this activity's
/// own device-adaptive rule (this file's header).
const int narrowObjectCount = 5;

const FindScene yardScene = FindScene('yard', 'In the yard', <FindObject>[
  FindObject('yard-sun', Icons.wb_sunny, 'the sun', 0.15, 0.18),
  FindObject('yard-tree', Icons.park, 'the tree', 0.85, 0.20),
  FindObject('yard-umbrella', Icons.umbrella, 'the umbrella', 0.15, 0.85),
  FindObject('yard-droplet', Icons.water_drop, 'the water droplet', 0.85, 0.82),
  FindObject('yard-dog', Icons.pets, 'the dog', 0.50, 0.50),
  FindObject('yard-cloud', Icons.cloud, 'the cloud', 0.50, 0.12),
  FindObject('yard-flower', Icons.local_florist, 'the flower', 0.15, 0.50),
  FindObject('yard-ball', Icons.sports_soccer, 'the ball', 0.85, 0.50),
  FindObject('yard-ladybug', Icons.bug_report, 'the ladybug', 0.50, 0.85),
]);

const FindScene kitchenScene = FindScene('kitchen', 'At the kitchen table', <FindObject>[
  FindObject('kitchen-pizza', Icons.local_pizza, 'the pizza', 0.20, 0.22),
  FindObject('kitchen-mug', Icons.local_cafe, 'the mug', 0.78, 0.18),
  FindObject('kitchen-bread', Icons.bakery_dining, 'the bread', 0.12, 0.62),
  FindObject('kitchen-fish', Icons.set_meal, 'the fish', 0.83, 0.68),
  FindObject('kitchen-cake', Icons.cake, 'the cake', 0.50, 0.45),
  FindObject('kitchen-icecream', Icons.icecream, 'the ice cream', 0.35, 0.82),
  FindObject('kitchen-cookie', Icons.cookie, 'the cookie', 0.68, 0.85),
  FindObject('kitchen-egg', Icons.egg, 'the egg', 0.50, 0.14),
  FindObject('kitchen-drink', Icons.emoji_food_beverage, 'the drink', 0.90, 0.42),
]);

const FindScene toyBoxScene = FindScene('toybox', 'The toy box', <FindObject>[
  FindObject('toybox-toys', Icons.toys, 'the toy', 0.18, 0.15),
  FindObject('toybox-rocket', Icons.rocket_launch, 'the rocket', 0.82, 0.15),
  FindObject('toybox-robot', Icons.smart_toy, 'the robot', 0.18, 0.85),
  FindObject('toybox-puzzle', Icons.extension, 'the puzzle piece', 0.82, 0.85),
  FindObject('toybox-ball', Icons.sports_baseball, 'the ball', 0.50, 0.50),
  FindObject('toybox-bike', Icons.directions_bike, 'the bike', 0.35, 0.32),
  FindObject('toybox-paint', Icons.palette, 'the paint', 0.65, 0.32),
  FindObject('toybox-music', Icons.music_note, 'the music note', 0.35, 0.68),
  FindObject('toybox-videogame', Icons.videogame_asset, 'the game controller', 0.65, 0.68),
]);

const List<FindScene> findScenes = <FindScene>[yardScene, kitchenScene, toyBoxScene];

/// The real device-content-scaling rule this file's header describes: a
/// narrow (single-column) posture gets the scene's first [narrowObjectCount]
/// curated objects, a two-plus-column posture gets the FULL curated set.
List<FindObject> visibleObjectsFor(FindScene scene, int columns) =>
    columns >= 2 ? scene.objects : scene.objects.take(narrowObjectCount).toList();

/// Pure — records one more found id. Tapping an already-found object is a
/// no-op at the call site (see `_FindItScreenState._onObjectTap`), so this
/// never needs to "un-find" anything.
Set<String> markFound(Set<String> foundIds, String objectId) => <String>{...foundIds, objectId};

/// True once every object CURRENTLY VISIBLE (posture-dependent — see
/// [visibleObjectsFor]) has been found.
bool allFound(List<FindObject> visible, Set<String> foundIds) =>
    visible.every((FindObject o) => foundIds.contains(o.id));

/// Picks a different curated scene from [findScenes] — never the one
/// currently showing. `Random` is always caller-supplied so tests are fully
/// deterministic; production always uses a real, unseeded `Random()`.
FindScene nextScene(Random random, {required String excludingId}) {
  if (findScenes.length <= 1) return findScenes.first;
  FindScene picked;
  do {
    picked = findScenes[random.nextInt(findScenes.length)];
  } while (picked.id == excludingId);
  return picked;
}

// ================================================================ widget ===

/// The check-mark reveal's transition — comfortably under §8.13's 400ms
/// consequence-motion budget.
const Duration _transitionDuration = Duration(milliseconds: 180);

class FindItScreen extends StatefulWidget {
  const FindItScreen({super.key, this.random});

  /// Injectable for tests only, matching every other Play Together screen's
  /// convention — production always uses a real, unseeded `Random()`.
  final Random? random;

  @override
  State<FindItScreen> createState() => _FindItScreenState();
}

class _FindItScreenState extends State<FindItScreen> {
  late final Random _random = widget.random ?? Random();
  late FindScene _scene = findScenes[_random.nextInt(findScenes.length)];
  Set<String> _foundIds = <String>{};

  void _onObjectTap(FindObject object) {
    if (_foundIds.contains(object.id)) return; // already found — no-op, never "unfinds"
    setState(() => _foundIds = markFound(_foundIds, object.id));
  }

  void _newScene() {
    setState(() {
      _scene = nextScene(_random, excludingId: _scene.id);
      _foundIds = <String>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Find it')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          // Real §8.11.1 posture logic, not a raw width check. Unlike every
          // other Play Together screen, this number doesn't just pick a
          // LAYOUT — it changes how many objects the scene actually holds
          // (this file's header).
          final int columns = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale);
          final List<FindObject> visible = visibleObjectsFor(_scene, columns);
          final int foundCount = visible.where((FindObject o) => _foundIds.contains(o.id)).length;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text(_scene.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              // Live gameplay state only (P2) — resets on every new scene,
              // never persisted, never "your best."
              Text('$foundCount of ${visible.length} found',
                  style:
                      Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Expanded(
                child: _SceneArea(
                  key: const Key('findItScene'),
                  objects: visible,
                  foundIds: _foundIds,
                  onTap: _onObjectTap,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.tonal(onPressed: _newScene, child: const Text('New scene')),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

class _SceneArea extends StatelessWidget {
  const _SceneArea({super.key, required this.objects, required this.foundIds, required this.onTap});

  final List<FindObject> objects;
  final Set<String> foundIds;
  final ValueChanged<FindObject> onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        // fit: expand — the scene must genuinely fill its Container
        // regardless of how many objects it holds (a Stack with only
        // Align-positioned children has no intrinsic size of its own).
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            for (final FindObject o in objects)
              Align(
                alignment: Alignment(o.x * 2 - 1, o.y * 2 - 1),
                child: _ObjectTile(object: o, found: foundIds.contains(o.id), onTap: () => onTap(o)),
              ),
          ],
        ),
      );
}

class _ObjectTile extends StatelessWidget {
  const _ObjectTile({required this.object, required this.found, required this.onTap});

  final FindObject object;
  final bool found;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: object.name,
      child: Semantics(
        button: true,
        label: found ? '${object.name}, found' : object.name,
        child: Material(
          key: Key('findObject-${object.id}'),
          color: found ? scheme.tertiaryContainer : scheme.primaryContainer,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: found ? null : onTap,
            child: SizedBox(
              // §8.4 — generously above the 64dp pre-reader floor.
              width: 72,
              height: 72,
              child: Stack(alignment: Alignment.center, children: <Widget>[
                Icon(object.icon,
                    size: 36, color: found ? scheme.onTertiaryContainer : scheme.onPrimaryContainer),
                // Consequence-only reveal (§8.13) — a pop from scale 0,
                // driven strictly by her tap finding this object, never a
                // loop. Always present so the scale transition is real,
                // not a bare insert.
                Positioned(
                  right: 2,
                  top: 2,
                  child: AnimatedScale(
                    scale: found ? 1 : 0,
                    duration: _transitionDuration,
                    curve: Curves.easeOut,
                    child: Icon(Icons.check_circle, size: 20, color: scheme.primary),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
