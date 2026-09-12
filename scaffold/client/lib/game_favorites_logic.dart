// OLIVE BRANCH — GamePickerScreen's Recommended row, pure logic. UNVERIFIED
// (no Flutter toolchain in tools/verify.sh's automated pipeline — manually
// built and run via `flutter analyze`/`flutter test` this session).
// MASTERFILE §9.2. docs/superpowers/specs/2026-09-12-intuitivism-gamepicker
// -recommended-design.md.
//
// A 1:1 semantic port of packages/games/src/favorites.ts — same names, same
// shapes, same reasoning — the identical discipline lock_controller.dart
// applies to lock.ts, joke_logic.dart to jokes.ts, and this package's own
// game_logic.dart to games.ts. A separate file from game_logic.dart on
// purpose, mirroring favorites.ts's own separateness from games.ts in the
// TS package: this is new logic layered on top of the existing catalogue
// port, not a rewrite of it, and `GameMeta`/`GameKind`/`forAge` are imported
// from game_logic.dart rather than redeclared here.
//
// P2 governs the whole file, identically to favorites.ts's own header: a
// favourite is a bare kind string and nothing else — no count, no order, no
// streak. `star`/`unstar` share their names with joke_logic.dart's own
// functions of the same purpose; nothing in this codebase imports both
// files directly (jokebook_screen.dart is the only importer of
// joke_logic.dart), so the shared names never collide in practice, the
// identical bet game_logic.dart/joke_logic.dart already both make with
// their own `Side` enum.
library;

import 'dart:math' as math;

import 'game_logic.dart';

/// Idempotent — starring an already-starred kind is a no-op, not a
/// duplicate. Mirrors favorites.ts's `star()` exactly.
List<String> star(List<String> current, String kind) =>
    current.contains(kind) ? current : [...current, kind];

/// Mirrors favorites.ts's `unstar()` exactly.
List<String> unstar(List<String> current, String kind) =>
    current.where((k) => k != kind).toList();

/// Resolves stored favourite kinds against the live catalogue. A kind no
/// longer in [all] (a game removed from the catalogue) silently drops out —
/// never a dangling reference the UI has to guard against separately. Order
/// follows [all]'s own order, never `starred`'s (P2 — no
/// order-of-favouriting signal).
List<GameMeta> favouritesFor(List<GameMeta> all, Set<String> starred) =>
    all.where((g) => starred.contains(g.kind.name)).toList();

/// Games she has newly grown into since her last visit to this screen. A
/// null [ageAtLastOpen] (first-ever open, or no live session at all) returns
/// nothing — there is no real "since last time" to measure, and showing her
/// entire starting catalogue as "new" would be a fabrication, not a
/// recommendation. Mirrors favorites.ts's `newlyUnlocked()` exactly.
List<GameMeta> newlyUnlocked(List<GameMeta> all, int age, int? ageAtLastOpen) {
  if (ageAtLastOpen == null) return const [];
  return all.where((g) => g.minAge <= age && g.minAge > ageAtLastOpen).toList();
}

/// "Surprise me" — one age-appropriate game she isn't currently looking at,
/// never the one she just came from. Identical contract to
/// favorites.ts's/joke_logic.dart's own `randomGame()`/`randomJoke()`:
/// [pick] is injectable so a test can drive it deterministically; production
/// passes nothing and gets a real [math.Random]. Returns null only if the
/// age floor (and, if given, the excluded kind) leaves nothing to pick from.
GameMeta? randomGame(
  List<GameMeta> all,
  int age,
  GameKind? excludeKind, {
  double Function()? pick,
}) {
  final pool = all.where((g) => g.minAge <= age && g.kind != excludeKind).toList();
  if (pool.isEmpty) return null;
  final draw = pick ?? math.Random().nextDouble;
  return pool[(draw() * pool.length).floor() % pool.length];
}
