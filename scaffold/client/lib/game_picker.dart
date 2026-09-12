// OLIVE BRANCH — child shell, game hub. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). MASTERFILE §9.2. Renders MARKUP screen 'gamePicker'.
//
// The central hub every other game screen is reached from. MARKUP's line for
// this surface is "shipped means rendered" — every catalogue entry gets a
// real, tappable card here even though the per-game boards themselves
// (tic-tac-toe, dots-and-boxes, memory, story) are other groups' builds. A
// tap on a kind with no destination wired up yet falls back to an honest
// not-built-yet acknowledgment — the same posture child_home.dart already
// takes for its own unbuilt tiles — rather than a silent no-op or a
// fabricated board. [onPlay] is how the navigation pass wires in the real
// screens without this file ever needing to import them.
//
// P2 governs every card: CATALOGUE carries a title and a blurb, never a
// score, rank, or win/loss record, and nothing here computes one.
//
// §8.4 age-gating: [childAge] runs the ported forAge() so a younger child
// sees fewer boards, never a harder version of the same one.
//
// §8.13 motion: the only animation on this screen is the card's own
// press-in, driven 1:1 by her finger and settling well under the 400ms
// "consequence" budget. Nothing here loops or moves on its own.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'game_favorites_logic.dart' as fav;
import 'game_logic.dart';

class GamePickerScreen extends StatelessWidget {
  const GamePickerScreen({
    super.key,
    this.childName,
    this.childAge = 7,
    this.onPlay,
    this.extraSections,
    this.favoriteKinds,
    this.ageAtLastOpen,
    this.onToggleFavorite,
    this.onSurpriseMe,
  });

  /// Her own name, not an id — used only for a warm greeting. Optional so
  /// this screen is usable standalone.
  final String? childName;

  /// Gates which games render via the ported [forAge]. Default of 7 matches
  /// MASTERFILE §9.2's own worked example ("a parent who plays properly
  /// against a seven-year-old…") and shows the full demo catalogue.
  final int childAge;

  /// Wired by the navigation pass once each game screen exists. Left null
  /// here — falling back to an honest not-built-yet acknowledgment — so this
  /// file never has to import another group's screen to compile.
  final void Function(BuildContext context, GameKind kind)? onPlay;

  /// Rendered below the age-gated grid, inside the same scroll view — the
  /// real seam that lets "all the kid's choices" live in this ONE screen
  /// rather than split across "Play together" and a separate "More games"
  /// door. Null by default (every existing call site, and every test in
  /// game_picker_test.dart, renders exactly as before this field existed).
  /// A `List<Widget>` rather than a single child so a caller (child_home
  /// .dart, guardian_more.dart) can pass games_hub.dart's own
  /// [MoreGamesSections] straight through without this file ever having to
  /// import the individual game screens that live behind it — the same
  /// import-decoupling this file's own header already commits to for the
  /// grid above.
  final List<Widget>? extraSections;

  // ==================== Intuitivism pass, sub-project 3a ====================
  // docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-
  // design.md. Four new optional constructor params, not a rewrite into a
  // self-fetching live screen — this stays a plain StatelessWidget fed by
  // plain data, matching every field above. A caller with a live session
  // (live_game_picker.dart) fetches/persists; this file only renders.

  /// Her guardian-curated favourite game kinds (by `GameKind.name`) — null
  /// means no live session at all, and the Recommended row is omitted
  /// entirely rather than rendered against fabricated data. An empty (but
  /// non-null) set is a real, live session that simply has no favourites
  /// yet — distinguishable on purpose, the same "honest absence" posture
  /// child_theme_preference's own null-vs-chosen split already uses.
  final Set<String>? favoriteKinds;

  /// Her age the last time this screen was open — null means a first-ever
  /// open, or no live session. Feeds [fav.newlyUnlocked] for the age-unlock
  /// half of the Recommended row; never a play-history log (see
  /// game_favorites_logic.dart's own header).
  final int? ageAtLastOpen;

  /// Non-null ONLY when a GUARDIAN opened this screen (guardian_more.dart's
  /// "Play together" tile) — the star toggle on [_GameCard] renders
  /// precisely when this is non-null, never for a child session. Called
  /// with the tapped game's kind name and whether it is NOW favourited
  /// (post-toggle); the caller's own live wrapper does the optimistic local
  /// update and the real PUT, reconciling on a failed write — this widget
  /// never awaits a network round trip itself.
  final void Function(String kind, bool nowFavorited)? onToggleFavorite;

  /// Non-null whenever a live session can compute a random pick — real for
  /// BOTH child and guardian sessions (unlike favoriting, there is nothing
  /// guardian-only about asking for a random game). Called with no
  /// arguments; the caller's own closure already holds whatever `age`/
  /// `excludeKind` state [fav.randomGame] needs and returns its result
  /// directly, so this widget can navigate to it via [onPlay] without
  /// importing the favorites engine's own randomization concerns.
  final GameMeta? Function()? onSurpriseMe;

  void _surpriseMe(BuildContext context) {
    final picked = onSurpriseMe?.call();
    if (picked != null) (onPlay ?? _notBuiltYet)(context, picked.kind);
  }

  @override
  Widget build(BuildContext context) {
    final games = forAge(childAge);
    final recommended = favoriteKinds == null
        ? const <GameMeta>[]
        : _recommendedFor(games, favoriteKinds!, childAge, ageAtLastOpen);
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: SafeArea(
        // LayoutBuilder wraps the WHOLE scroll view, not just the grid —
        // deliberately. A GridView (or anything else) that reads its own
        // constraints from a LayoutBuilder nested INSIDE a ListView sees an
        // unbounded main-axis extent (that is what makes the list
        // scrollable at all), not the real viewport height — columnsAt()
        // fed that would compute the wrong posture. Measuring out here,
        // before the scroll view exists, is what keeps this the same real
        // viewport size/textScale the rest of this file's own comments
        // already describe, regardless of how much [extraSections] content
        // now scrolls below the grid.
        child: LayoutBuilder(builder: (context, constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final int cross = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(
              childName == null ? 'What do you want to play?' : 'What do you want to play, $childName?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text('Something to play, just the two of you.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _RecommendedSection(
              recommended: recommended,
              favoriteKinds: favoriteKinds,
              onToggleFavorite: onToggleFavorite,
              onSurpriseMe: onSurpriseMe == null ? null : () => _surpriseMe(context),
              onPlay: onPlay,
              textScale: textScale,
            ),
            GameCatalogueGrid(
              games: games, onPlay: onPlay, crossAxisCount: cross, textScale: textScale,
              favoriteKinds: favoriteKinds, onToggleFavorite: onToggleFavorite,
            ),
            ...?extraSections,
          ]);
        }),
      ),
    );
  }
}

/// Favourites first (an intentional guardian choice earns top billing),
/// age-unlock games filling any remaining slots, each game appearing at
/// most once even if it qualifies both ways — the design spec's own exact
/// combination rule. `games` (already [forAge]-filtered by the caller) is
/// passed as BOTH engines' own catalogue so a favourited-but-not-yet-
/// age-eligible game can never surface here, the same age-safety every
/// other render on this screen already holds itself to.
List<GameMeta> _recommendedFor(
  List<GameMeta> games, Set<String> favoriteKinds, int age, int? ageAtLastOpen,
) {
  final favourites = fav.favouritesFor(games, favoriteKinds);
  final unlocked = fav.newlyUnlocked(games, age, ageAtLastOpen);
  final already = favourites.map((g) => g.kind).toSet();
  return [...favourites, ...unlocked.where((g) => !already.contains(g.kind))];
}

/// The Recommended row itself, plus the "Surprise me" button beside its own
/// header — rendered as one unit because the button sits beside whichever
/// header the row currently has (or, with no row to render, stands alone).
/// Absent entirely when there is nothing to show at all (this app's
/// established "honest absence over empty-state noise" convention).
class _RecommendedSection extends StatelessWidget {
  const _RecommendedSection({
    required this.recommended,
    required this.favoriteKinds,
    required this.onToggleFavorite,
    required this.onSurpriseMe,
    required this.onPlay,
    required this.textScale,
  });

  final List<GameMeta> recommended;
  final Set<String>? favoriteKinds;
  final void Function(String kind, bool nowFavorited)? onToggleFavorite;
  final VoidCallback? onSurpriseMe;
  final void Function(BuildContext context, GameKind kind)? onPlay;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final bool showRow = favoriteKinds != null && recommended.isNotEmpty;
    if (!showRow && onSurpriseMe == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (showRow)
            Expanded(
              child: Text('Recommended', style: Theme.of(context).textTheme.titleMedium))
          else
            const Spacer(),
          if (onSurpriseMe != null)
            TextButton.icon(
              key: const Key('surpriseMeButton'),
              onPressed: onSurpriseMe,
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Surprise me'),
            ),
        ]),
        if (showRow) ...[
          const SizedBox(height: 8),
          // One clean fade IN when the row first gains content — keyed on
          // `showRow` alone (not on `recommended`'s own length/contents), so
          // a favourite added later while the row is already visible never
          // re-triggers it (§8.13's own "consequence motion... then holds
          // still", the identical posture the design spec's own Motion
          // section states for this row specifically).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              key: const ValueKey('recommendedRowShown'),
              height: 182 * textScale.clamp(1.0, 2.0),
              child: ListView.separated(
                key: const Key('recommendedRow'),
                scrollDirection: Axis.horizontal,
                itemCount: recommended.length,
                separatorBuilder: (context, i) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final meta = recommended[i];
                  return SizedBox(
                    width: 160,
                    child: _GameCard(
                      meta: meta,
                      favoriteKinds: favoriteKinds,
                      onToggleFavorite: onToggleFavorite,
                      onTap: () => (onPlay ?? _notBuiltYet)(context, meta.kind),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The age-gated grid itself, factored out of [GamePickerScreen] so
/// games_hub.dart's own consolidated section can render the identical real
/// grid rather than a second, hand-copied one. Pure extraction — same
/// widget tree this file always produced, just reachable by a second
/// caller now.
///
/// Takes [crossAxisCount]/[textScale] as plain values rather than measuring
/// them itself via its own LayoutBuilder — see [GamePickerScreen.build]'s
/// own comment for why self-measuring here would silently break the moment
/// this widget is used inside a scroll view (which every real caller does).
class GameCatalogueGrid extends StatelessWidget {
  const GameCatalogueGrid({
    super.key, required this.games, required this.crossAxisCount, required this.textScale, this.onPlay,
    this.favoriteKinds, this.onToggleFavorite,
  });
  final List<GameMeta> games;
  final int crossAxisCount;
  final double textScale;
  final void Function(BuildContext context, GameKind kind)? onPlay;

  /// Threaded straight through to every [_GameCard] below — the star toggle
  /// belongs on EVERY card in the full catalogue, not only the ones already
  /// in the Recommended row: this grid is the actual mechanism a guardian
  /// uses to ADD a new favourite in the first place (see the design spec's
  /// own "the toggle IS the management UI for this pass"). Both null by
  /// default, so games_hub.dart's own [MoreGamesSections] caller (which has
  /// no live favourites session) renders exactly as before this migration.
  final Set<String>? favoriteKinds;
  final void Function(String kind, bool nowFavorited)? onToggleFavorite;

  @override
  Widget build(BuildContext context) => GridView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    // Explicit mainAxisExtent, not an aspect ratio — see child_home.dart's
    // note on GridView.count scaling tile height with device width on this
    // engine build. Found while adding this same migration's
    // textScale-aware column test: a FIXED 182 regardless of textScale is
    // a real, pre-existing §8.8 bug — at 1 column / 2.0x text the five
    // lines of card content (icon, title up to 2 lines, blurb up to 2
    // lines, the competitive/co-op row) genuinely need more vertical room
    // than 1x text does, and a bigger accessibility text size is exactly
    // the case columnsAt() already degrades WIDTH for two lines above —
    // this closes the matching HEIGHT gap rather than leaving it
    // half-fixed.
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      mainAxisExtent: 182 * textScale.clamp(1.0, 2.0),
    ),
    children: [
      for (final g in games)
        _GameCard(
          meta: g,
          favoriteKinds: favoriteKinds,
          onToggleFavorite: onToggleFavorite,
          onTap: () => (onPlay ?? _notBuiltYet)(context, g.kind),
        ),
    ],
  );
}

void _notBuiltYet(BuildContext context, GameKind kind) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('${catalogueFor(kind).title} — not built yet.'),
    duration: const Duration(seconds: 2),
  ));
}

Color _cardColor(ColorScheme cs, GameKind kind) => switch (kind) {
      GameKind.tictactoe => cs.primaryContainer,
      GameKind.dotsboxes => cs.tertiaryContainer,
      GameKind.memory => cs.secondaryContainer,
      GameKind.story => cs.surfaceContainerHighest,
      GameKind.drawTogether => cs.primaryContainer,
      GameKind.guessDoodle => cs.tertiaryContainer,
      // Batch B — cycles the same four house container roles above rather
      // than introducing new ones.
      GameKind.sillySentence => cs.primaryContainer,
      GameKind.wouldYouRather => cs.tertiaryContainer,
      GameKind.twoTruths => cs.secondaryContainer,
      GameKind.twentyQuestions => cs.surfaceContainerHighest,
      // Batch C — cycles the same four house container roles once more.
      GameKind.copyPattern => cs.primaryContainer,
      GameKind.findIt => cs.tertiaryContainer,
    };

Color _onCardColor(ColorScheme cs, GameKind kind) => switch (kind) {
      GameKind.tictactoe => cs.onPrimaryContainer,
      GameKind.dotsboxes => cs.onTertiaryContainer,
      GameKind.memory => cs.onSecondaryContainer,
      GameKind.story => cs.onSurfaceVariant,
      GameKind.drawTogether => cs.onPrimaryContainer,
      GameKind.guessDoodle => cs.onTertiaryContainer,
      GameKind.sillySentence => cs.onPrimaryContainer,
      GameKind.wouldYouRather => cs.onTertiaryContainer,
      GameKind.twoTruths => cs.onSecondaryContainer,
      GameKind.twentyQuestions => cs.onSurfaceVariant,
      GameKind.copyPattern => cs.onPrimaryContainer,
      GameKind.findIt => cs.onTertiaryContainer,
    };

const _kindIcon = {
  GameKind.tictactoe: Icons.grid_3x3_rounded,
  GameKind.dotsboxes: Icons.border_all_rounded,
  GameKind.memory: Icons.photo_library_rounded,
  GameKind.story: Icons.auto_stories_rounded,
  GameKind.drawTogether: Icons.brush_rounded,
  GameKind.guessDoodle: Icons.psychology_alt_rounded,
  GameKind.sillySentence: Icons.emoji_emotions_rounded,
  GameKind.wouldYouRather: Icons.compare_arrows_rounded,
  GameKind.twoTruths: Icons.visibility_off_rounded,
  GameKind.twentyQuestions: Icons.live_help_rounded,
  GameKind.copyPattern: Icons.grid_view_rounded,
  GameKind.findIt: Icons.search_rounded,
};

class _GameCard extends StatefulWidget {
  const _GameCard({
    required this.meta, required this.onTap, this.favoriteKinds, this.onToggleFavorite,
  });
  final GameMeta meta;
  final VoidCallback onTap;

  /// Star rendering only — see [onToggleFavorite]'s own doc comment for why
  /// the star's PRESENCE is gated on that field, not this one.
  final Set<String>? favoriteKinds;

  /// The star `IconButton` renders ONLY when this is non-null — i.e. only
  /// when a GUARDIAN, not the child, opened GamePickerScreen (the design
  /// spec's own "Where favoriting happens" section). Filled when
  /// `meta.kind.name` is in [favoriteKinds], outline otherwise.
  final void Function(String kind, bool nowFavorited)? onToggleFavorite;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final cs = Theme.of(context).colorScheme;
    final onColor = _onCardColor(cs, meta.kind);
    return Semantics(
      button: true,
      label: '${meta.title}. ${meta.blurb}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        // Consequence motion only — driven by her tap, settles in 120ms,
        // never a loop (§8.13.1/§8.13.6).
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64), // §8.4 touch target
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardColor(cs, meta.kind),
              // 14, not a one-off radius: the canonical action-grid tile
              // radius shared with child_home.dart's _Tile and
              // guardian_home.dart's _GTile, so a new tile component here
              // matches the house pairing instead of reinventing its own.
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_kindIcon[meta.kind], size: 30, color: onColor),
                const Spacer(),
                // Guardian-only, per [onToggleFavorite]'s own doc comment —
                // a null callback means this rendered from a child session
                // (or no live session at all), and no star exists at any
                // size, not merely a disabled one (P2 — favoriting is not
                // something to dangle in front of her, it is not hers to
                // do). Instant fill-swap only on tap, no animation beyond
                // it (§8.13.1's own "nothing shimmers/pulses" rule).
                if (widget.onToggleFavorite != null)
                  IconButton(
                    key: Key('star_${meta.kind.name}'),
                    tooltip: (widget.favoriteKinds?.contains(meta.kind.name) ?? false)
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      (widget.favoriteKinds?.contains(meta.kind.name) ?? false)
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: onColor,
                    ),
                    onPressed: () => widget.onToggleFavorite!(
                        meta.kind.name, !(widget.favoriteKinds?.contains(meta.kind.name) ?? false)),
                  ),
              ]),
              const Spacer(),
              Text(meta.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: onColor)),
              const SizedBox(height: 4),
              Text(meta.blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: onColor)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(meta.competitive ? Icons.emoji_people_rounded : Icons.diversity_3_rounded,
                    size: 15, color: onColor),
                const SizedBox(width: 4),
                // Flexible + ellipsis rather than mainAxisSize.min: at three
                // columns on a wide unfolded screen the card can be narrow
                // enough that "Just for fun, together" doesn't fit, and this
                // must never overflow rather than relying on tuning copy
                // length to a specific breakpoint.
                Flexible(
                  child: Text(meta.competitive ? 'Play against Dad' : 'Just for fun, together',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.w600, color: onColor)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
