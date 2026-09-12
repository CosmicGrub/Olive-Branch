// OLIVE BRANCH — the shared Hero/Featured/Standard tile both home shells'
// action grids render. Intuitivism pass, sub-project 3b
// (docs/superpowers/specs/2026-09-12-intuitivism-guardianhome-tiering-
// design.md) — extracted from child_home.dart's own private `_Tile`
// (sub-project 2, docs/superpowers/specs/2026-08-31-intuitivism-navigation-
// density-design.md, §3) once guardian_home.dart needed the identical shape
// for its own tiering pass, rather than adding `featured`/`hero` params to
// guardian_home.dart's `_GTile` as a second, drifting copy. Sub-project 2's
// own `_Tile` doc comment already named the reason this should be one real
// component: one set of invariants (§8.4's 64dp floor, the shared
// `borderRadius.circular(14)` convention this file now shares with
// game_picker.dart's own cards) instead of copies that can quietly diverge.
//
// This file is a pure rename plus move of that original `_Tile` — behavior
// is unchanged. child_home.dart's own migration onto `TieredTile` is
// covered by its full existing test suite continuing to pass with zero
// test-file changes, the proof this really is behavior-preserving.
//
// No longer UNVERIFIED — verified by CI (a Flutter toolchain runs for real
// in tools/verify.sh's automated pipeline, per child_home.dart's own note,
// CHANGELOG v0.49.61); this file's own tiered_tile_test.dart runs under
// that same pipeline.
import 'package:flutter/material.dart';

/// Honest acknowledgment for a feature this preview build doesn't implement
/// yet, rather than a silent no-op — the same "recorded, not glossed over"
/// posture the rest of this project already takes for unbuilt surfaces.
/// Was child_home.dart's own private copy; mirrored here rather than
/// imported, since a private top-level function can't cross a file
/// boundary (same reasoning game_navigation.dart's own copy already
/// documents) — and this is now the only file that needs it, so
/// child_home.dart's copy moved here rather than staying behind unused.
void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

/// The shared Hero/Featured/Standard tile ChildHome's and GuardianHome's own
/// action grids render. `featured` bumps icon size and label text style;
/// `hero` additionally switches the fill to `tertiaryContainer` and is only
/// ever true for a single Hero tile per screen — `hero` alone does not bump
/// icon/text size, callers wanting the full Hero look pass both flags (see
/// either screen's own Hero tile construction). `height`, when supplied,
/// replaces the InkWell child's own intrinsic sizing with an explicit
/// height — used outside a GridView, where there is no gridDelegate-driven
/// mainAxisExtent to size a tile.
class TieredTile extends StatelessWidget {
  const TieredTile({super.key, required this.icon, required this.label, this.onTap,
    this.badgeCount, this.featured = false, this.hero = false, this.height});
  final IconData icon;
  final String label;
  // Defaults to the honest not-built-yet acknowledgment; tiles with a real
  // destination override it.
  final void Function(BuildContext context)? onTap;
  // Unread-style count shown on the icon corner when positive. ChildHome's
  // own use (`unreadCount`); GuardianHome doesn't use it today. Optional —
  // null/0 renders no badge at all, not a badge showing "0".
  final int? badgeCount;
  final bool featured;
  final bool hero;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // §4 constraint compliance: hierarchy is communicated by size/width/
    // type-scale only. Every fill below is a standard Material ColorScheme
    // tonal role derived from the active theme (sub-project 1's
    // colorSchemeFor()) — never a caller's own chosen accent colour, so
    // §8.6.2's placement budget is satisfied by construction, not later
    // care.
    final Color fill = hero
        ? scheme.tertiaryContainer
        : featured
            ? scheme.secondaryContainer
            : scheme.primaryContainer;
    final Color onFill = hero
        ? scheme.onTertiaryContainer
        : featured
            ? scheme.onSecondaryContainer
            : scheme.onPrimaryContainer;
    final Widget tile = InkWell(
      onTap: () => (onTap ?? (c) => _notBuiltYet(c, label))(context),
      child: Container(
        // §8.4 — 64dp minimum touch target for pre-readers. Every tier
        // clears this floor by construction (Standard's own base height is
        // already above it even before text-scale growth); this stays the
        // hard backstop regardless of tier or the `height` override above.
        constraints: BoxConstraints(minHeight: height ?? 64),
        height: height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: fill),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: featured ? 36 : 28, color: onFill),
            if (badgeCount != null && badgeCount! > 0) ...[
              const Spacer(),
              _UnreadBadge(count: badgeCount!),
            ],
          ]),
          const Spacer(),
          Text(label,
            style: (featured
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.titleSmall)
                ?.copyWith(fontWeight: FontWeight.w600, color: onFill)),
        ]),
      ),
    );
    // The Hero tile alone renders outside any GridView (no cell to fill),
    // so it needs its own explicit width — every other tier gets width from
    // its GridView cell already.
    return hero ? SizedBox(width: double.infinity, child: tile) : tile;
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(9)),
    alignment: Alignment.center,
    child: Text(count > 9 ? '9+' : '$count',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onError, fontWeight: FontWeight.w700)));
}
