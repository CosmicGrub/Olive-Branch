// OLIVE BRANCH — guardian-set visibility & pacing overrides, the shared
// client-side read path. UNVERIFIED (no Flutter toolchain in tools/verify
// .sh's automated pipeline). docs/superpowers/specs/2026-09-13-parental-
// controls-pacing-design.md ("sub-project 2: visibility & pacing").
// db/migrations/0033_guardian_activity_override.sql, server/routes.mjs's
// GET/PUT/DELETE .../activity-overrides[/:activityKey].
//
// ONE shared place for the precedence rule the design spec's own Routes
// section states explicitly, so it is computed identically everywhere
// rather than reimplemented per screen — child_home.dart (tiles),
// game_picker.dart/games_hub.dart (games), jokebook_screen.dart (jokes),
// and child_more.dart (drawing/activities) all call [effectiveVisibility]/
// [isTileVisible] rather than inlining this logic a fifth time:
//
//   - `visible == false` always wins, regardless of age/reveal state.
//   - Otherwise (visible is null/true): a set `revealedAt` always shows the
//     item from now on; failing that, the effective age gate is
//     `minAgeOverride ?? defaultMinAge`.
//
// Deliberately NOT implemented server-side (packages/db/src/pool.ts), even
// though the design spec offers that as an alternative location: only the
// Dart-side catalogues (game_logic.dart, joke_logic.dart) — not the TS-side
// games2.ts's `Kind2`/games3.ts, which have no minAge/CATALOGUE concept at
// all (confirmed by grep; see this feature's own PR description) — actually
// hold each item's own default minAge today, so the server has nothing real
// to fold most overrides against. pool.ts's job stays "store/serve the
// override rows as-is" (activityOverridesFor()); this file is where an
// override and its catalogue default actually meet, in the one place both
// are already known to the caller.
//
// House style, reconfirmed by the design spec itself: an item [
// effectiveVisibility]/[isTileVisible] says "no" to must simply not appear
// — never a lock icon, never a "back at age N" countdown. Every call site
// below wraps a widget in a plain `if (...)`, the same shape `forAge()`'s
// own filtered list already produces.

class ActivityOverride {
  const ActivityOverride({
    required this.activityKey,
    this.visible,
    this.minAgeOverride,
    this.revealedAt,
  });

  /// e.g. 'tile:storyteller', 'game:chess', 'joke:knock_knock',
  /// 'activity:doodle' — namespaced, matching 0033's own column comment.
  final String activityKey;

  /// NULL = default (shown); explicit false = hidden. The only field a tile
  /// or age-concept-free activity ever has set.
  final bool? visible;

  /// NULL = use the catalogue's own default minAge.
  final int? minAgeOverride;

  /// Once set, this item shows regardless of age from now on.
  final DateTime? revealedAt;

  factory ActivityOverride.fromWire(Map<String, dynamic> wire) => ActivityOverride(
        activityKey: wire['activityKey'] as String,
        visible: wire['visible'] as bool?,
        minAgeOverride: (wire['minAgeOverride'] as num?)?.toInt(),
        revealedAt: wire['revealedAt'] == null
            ? null
            : DateTime.parse(wire['revealedAt'] as String),
      );
}

/// GET .../activity-overrides' real response, decoded once per screen
/// load/session — the design spec's own "each fetches this child's
/// overrides once per session/load" line, never refetched mid-screen (see
/// this feature's own PR description on the "never retroactive" rule being
/// a reload-time filter, not a live one). A key with no row at all is
/// absent from this map entirely — the same honest absence
/// activityOverridesFor() already returns, never a fabricated default entry.
Map<String, ActivityOverride> decodeActivityOverrides(Map<String, dynamic> wire) {
  final List<dynamic> list = (wire['overrides'] as List?) ?? const [];
  return {
    for (final raw in list)
      (raw as Map<String, dynamic>)['activityKey'] as String: ActivityOverride.fromWire(raw),
  };
}

/// THE shared precedence rule (see file header) for an age-gateable item —
/// a game, joke, or drawing/activity that already has a real
/// [defaultMinAge] somewhere in its own catalogue. [overrides] is the whole
/// fetched map, or null when there is no live session at all (no
/// [OliveApi.fetchActivityOverrides] call was ever made — every item then
/// shows at its catalogue default, exactly the behavior this feature did
/// not change for a caller that hasn't wired it in yet).
bool effectiveVisibility({
  required Map<String, ActivityOverride>? overrides,
  required String activityKey,
  required int childAge,
  required int defaultMinAge,
}) {
  final override = overrides?[activityKey];
  if (override?.visible == false) return false;
  if (override?.revealedAt != null) return true;
  final effectiveMinAge = override?.minAgeOverride ?? defaultMinAge;
  return childAge >= effectiveMinAge;
}

/// The visibility-only half of the same rule, for a ChildHome tile or a
/// drawing/activity that has never had an age concept at all (Explicitly
/// out of scope, per the design spec: "this pass does not invent a minAge
/// for surfaces that have never had one") — checks ONLY the `visible`
/// column, the design spec's own "the only column tiles with no age
/// concept ever use" line. Any [minAgeOverride]/[revealedAt] on such a key
/// (nothing in this app's UI ever sets one for a visibility-only item) is
/// simply irrelevant here, by construction — not a bug, since
/// [effectiveVisibility] with `defaultMinAge: 0` would compute the exact
/// same true/false either way.
bool isTileVisible(Map<String, ActivityOverride>? overrides, String tileKey) =>
    overrides?[tileKey]?.visible != false;
