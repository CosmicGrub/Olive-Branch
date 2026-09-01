// OLIVE BRANCH — shared layout for Batch B's four curated-prompt activities.
// No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs for real in tools/verify.sh's
// automated pipeline — also manually built and run via `flutter analyze` /
// `flutter test` this session; CHANGELOG v0.49.61). MASTERFILE §9.2,
// §8.11.1, P2.
//
// Play Together Phase 1, Batch B — Silly Sentence Maker, Would You Rather,
// Two Truths and a Tall Tale, and 20 Questions (game_silly_sentence.dart,
// game_would_you_rather.dart, game_two_truths.dart,
// game_twenty_questions.dart) all share the exact same real shape the spec
// names explicitly: a curated prompt/category presented one at a time, a
// simple turn-taking state machine, and — at wide postures only — a running
// history of what's been played this session sitting alongside it. Rather
// than four screens each re-deriving the same `LayoutBuilder` +
// `columnsAt()` split (and risking three subtly different "side panel"
// conventions the way `court_export.dart`'s and `game_picker.dart`'s
// breakpoints drifted apart before `form_factors.dart` unified them — see
// that file's own header), this one small widget is the shared base the
// spec's batching plan floats as optional. It carries ONLY layout: each
// screen still owns its own state machine and curated content in full,
// matching this codebase's "each group ports only what it needs,
// self-contained" discipline — `game_draw_together.dart`'s and
// `game_guess_doodle.dart`'s own header note on why Dart library privacy is
// per-file, not shared, applies here too for anything besides this layout
// shell.
//
// Device-adaptive behavior, matching Batch A's now-proven convention
// (`game_draw_together.dart`/`game_guess_doodle.dart`, v0.49.18) but with a
// genuinely different shape at narrow width, per the spec's own words for
// this batch specifically: "single column → one prompt at a time, full
// width. 2+ columns → prompt on one side, a running history of what's been
// played this session on the other." Unlike Batch A's tools panel (which
// moves to a bottom bar when narrow, never disappearing), Batch B's history
// panel simply ISN'T THERE at narrow width — there is nothing to move
// because a session history is genuinely extra content, not a relocated
// control a narrow screen still needs. `historySidePanel` therefore has no
// narrow-width counterpart key; its absence at `foldCover` IS the asserted
// structural difference, proven by `layoutRoot` itself being a `Column` at
// narrow and a `Row` at wide (the same widget-tree-shape assertion
// `game_draw_together_test.dart` already established).
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

/// Splits [main] (the current prompt/round, always shown) from [history] (a
/// running log of this session, shown only once there is real room for it)
/// by the SAME posture math every other Play Together screen now uses —
/// never a hand-rolled width check.
class CuratedActivityLayout extends StatelessWidget {
  const CuratedActivityLayout({super.key, required this.main, required this.history});

  final Widget main;
  final Widget history;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale,
            ) >=
            2;

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(key: const Key('layoutRoot'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: main),
              const SizedBox(width: 16), // the crease gutter, same as Batch A
              SizedBox(key: const Key('historySidePanel'), width: 280, child: history),
            ]),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(key: const Key('layoutRoot'), children: [Expanded(child: main)]),
        );
      });
}

/// The running-session-history list every Batch B screen's side panel
/// renders, factored out once rather than four times. Newest entry first —
/// nobody wants to scroll to see what just happened.
class SessionHistoryPanel extends StatelessWidget {
  const SessionHistoryPanel({super.key, required this.title, required this.entries, required this.emptyHint});

  final String title;
  final List<String> entries;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(emptyHint, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
        else
          // Expanded + a REAL scrollable, not shrinkWrap — a session can run
          // long, and unlike game_picker.dart's grid (nested inside an outer
          // ListView, so its own scroll would be redundant), this list IS
          // the panel's only scrollable content, so it must actually scroll
          // rather than silently clip past the panel's stretched height.
          Expanded(
            child: ListView.separated(
              key: const Key('sessionHistoryList'),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (BuildContext context, int i) => Text(
                entries[entries.length - 1 - i],
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ]),
    );
  }
}
