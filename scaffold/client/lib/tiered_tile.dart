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

import 'access_scope.dart';
import 'read_aloud.dart';

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
class TieredTile extends StatefulWidget {
  const TieredTile({super.key, required this.icon, required this.label, this.onTap,
    this.badgeCount, this.unreadDot = false, this.featured = false, this.hero = false, this.height,
    this.readAloud = true});
  final IconData icon;
  final String label;
  // Defaults to the honest not-built-yet acknowledgment; tiles with a real
  // destination override it.
  final void Function(BuildContext context)? onTap;
  // Unread-style count shown on the icon corner when positive. ChildHome's
  // own use (`unreadCount`); GuardianHome doesn't use it today. Optional —
  // null/0 renders no badge at all, not a badge showing "0".
  final int? badgeCount;
  // C-24: a plain dot, no number, no alarm colour — for the CHILD's own
  // surfaces, where a red "3" reads as a debt and a count of unread things is
  // exactly the guilt-pressure framing §8.4/P2 forbid. Says "something new is
  // here" by shape alone (and by a spoken label for a screen reader), never
  // how much. Wins over [badgeCount] if both are given.
  final bool unreadDot;
  final bool featured;
  final bool hero;
  final double? height;

  /// Whether this tile takes part in read-aloud (the speaker and the long-press).
  /// True for a child's tiles; the guardian's own home passes false, since read-aloud
  /// is for her, not for the grown-up's screens that share this widget.
  final bool readAloud;
  @override
  State<TieredTile> createState() => _TieredTileState();
}

class _TieredTileState extends State<TieredTile> {
  ReadAloudController? _ra;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ra = ReadAloudScope.maybeOf(context);
  }

  @override
  void dispose() {
    // Leaving the screen ends a reading that this tile started.
    _ra?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon, label = widget.label, onTap = widget.onTap, badgeCount = widget.badgeCount,
        unreadDot = widget.unreadDot, featured = widget.featured, hero = widget.hero, height = widget.height;
    // Read-aloud (§8.8.5): null when it is off for her or there is no scope, in
    // which case this tile is exactly what it always was.
    final ReadAloudController? ra = widget.readAloud ? ReadAloudScope.enabledOf(context) : null;
    final double floor = childTargetOf(context);
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
      // Long-press reads the label; a plain tap still opens. Never on its own.
      onLongPress: ra == null ? null : () => ra.speak(label, owner: this),
      child: Container(
        // §8.4 — 64dp minimum touch target for pre-readers. Every tier
        // clears this floor by construction (Standard's own base height is
        // already above it even before text-scale growth); this stays the
        // hard backstop regardless of tier or the `height` override above.
        constraints: BoxConstraints(minHeight: height ?? floor),
        height: height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: fill),
        child: _withSpeaker(ra, label, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: featured ? 36 : 28, color: onFill),
            if (unreadDot) ...[
              const Spacer(),
              const _NewDot(),
            ] else if (badgeCount != null && badgeCount > 0) ...[
              const Spacer(),
              _UnreadBadge(count: badgeCount),
            ],
          ]),
          const Spacer(),
          Padding(
            // Room for the speaker, so the label never runs under it.
            padding: EdgeInsets.only(right: ra == null ? 0 : 44),
            child: Text(label,
              style: (featured
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleSmall)
                  ?.copyWith(fontWeight: FontWeight.w600, color: onFill)),
          ),
        ])),
      ),
    );
    // The Hero tile alone renders outside any GridView (no cell to fill),
    // so it needs its own explicit width — every other tier gets width from
    // its GridView cell already.
    return hero ? SizedBox(width: double.infinity, child: tile) : tile;
  }

  /// The speaker sits in the bottom corner, drawn quietly, so it neither
  /// competes with the icon and label nor shares the badge's corner. It is a
  /// 48dp touch target; with no read-aloud the tile is returned untouched.
  Widget _withSpeaker(ReadAloudController? ra, String label, Widget body) {
    if (ra == null) return body;
    return Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
      body,
      Positioned(right: -8, bottom: -8, child: SpeakerButton(text: label, label: 'Read "$label" out loud')),
    ]);
  }
}

class _NewDot extends StatelessWidget {
  const _NewDot();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Something new',
    child: Container(
      key: const Key('newDot'),
      width: 14, height: 14,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2))));
}

/// A count on a guardian's tile. Was the error (alarm red) colour; an unread
/// thing is not an error, and red reads as a debt (§8.4/P2's own reasoning for
/// the child's plain dot). Now the theme's calm primary, which stays legible on
/// every tile fill because primary/onPrimary are a contrast-checked pair.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(9)),
    alignment: Alignment.center,
    child: Text(count > 9 ? '9+' : '$count',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w700)));
}
