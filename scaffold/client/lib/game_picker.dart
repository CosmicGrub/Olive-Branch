// OLIVE BRANCH — child shell, game hub. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.2. Renders MARKUP
// screen 'gamePicker'.
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
import 'game_logic.dart';

class GamePickerScreen extends StatelessWidget {
  const GamePickerScreen({super.key, this.childName, this.childAge = 7, this.onPlay});

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

  @override
  Widget build(BuildContext context) {
    final games = forAge(childAge);
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // v0.49.17 — migrated off a hand-rolled 420/680px breakpoint onto
          // form_factors.dart's real, tested posture system (columnsAt()),
          // the same fix court_export.dart already got and this exact file's
          // own header used to cite as the anti-pattern still standing here.
          // One real, intentional behavior change this migration carries:
          // the old breakpoint gave 3 columns from 680px (any Fold-unfolded
          // or tablet width); columnsAt() reserves 3 for genuine desktop
          // width (>=1024px, matching FORM_FACTORS' own `desktop` row) and
          // gives a 10-inch tablet (800px, `tabletLarge`) 2 columns, same as
          // the Fold5's unfolded main screen — which also gives each card
          // more real width for its blurb, not less. textScale-aware for the
          // same §8.8 reason court_export.dart's columnsAt() call already is:
          // a large accessibility text size on a nominally-wide screen should
          // still degrade toward fewer columns.
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
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Explicit mainAxisExtent, not an aspect ratio — see
              // child_home.dart's note on GridView.count scaling tile
              // height with device width on this engine build. Found while
              // adding this same migration's textScale-aware column test: a
              // FIXED 182 regardless of textScale is a real, pre-existing
              // §8.8 bug — at 1 column / 2.0x text the five lines of card
              // content (icon, title up to 2 lines, blurb up to 2 lines, the
              // competitive/co-op row) genuinely need more vertical room
              // than 1x text does, and a bigger accessibility text size is
              // exactly the case columnsAt() already degrades WIDTH for two
              // lines above — this closes the matching HEIGHT gap rather
              // than leaving it half-fixed.
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 182 * textScale.clamp(1.0, 2.0),
              ),
              children: [
                for (final g in games)
                  _GameCard(meta: g, onTap: () => (onPlay ?? _notBuiltYet)(context, g.kind)),
              ],
            ),
          ]);
        }),
      ),
    );
  }
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
};

class _GameCard extends StatefulWidget {
  const _GameCard({required this.meta, required this.onTap});
  final GameMeta meta;
  final VoidCallback onTap;
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
              Icon(_kindIcon[meta.kind], size: 30, color: onColor),
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
