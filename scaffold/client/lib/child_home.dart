// OLIVE BRANCH — child shell, home. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). §8.1.
//
// Renders MARKUP screen 'childHome' (§02). Three invariants the widget tree
// must preserve:
//   - Availability is stated in HER frame; his time is the aside. (§4.1)
//   - Countdown is in sleeps, computed on her local day boundary. (§8.2.5)
//   - No settings affordance exists at any depth. (§8.1)
//
// The kiosk lock (§5.20) that used to be a dev-preview-only stub here is now
// real — see kiosk_shell.dart, which wraps this widget from entry_gate.dart
// rather than living inside it. ChildHome itself stays lock-agnostic.
//
// TILE HIERARCHY — intuitivism pass, sub-project 2 (docs/superpowers/specs/
// 2026-08-31-intuitivism-navigation-density-design.md). This screen renders
// 8 real tile destinations (Homework, Play together, My list, Messages,
// My day, Storyteller, Show & tell, More for you) — previously a single
// flat, equal-weight 2-column grid with a HARDCODED crossAxisCount
// (form_factors.dart's postureFor()/columnsAt() were imported nowhere in
// this file, unlike game_picker.dart, which migrated onto the real posture
// system back in v0.49.17 — a real, independently-found inconsistency this
// pass closes). Now a real 3-tier hierarchy — Hero / Featured / Standard —
// each tier's placement traced to a MASTERFILE/CHANGELOG citation where one
// exists, and disclosed as a JUDGMENT CALL in the spec's own §1 table where
// it doesn't:
//   Hero (1, full-width, not a grid at all): My day — the only tile
//     MASTERFILE calls a "signature element" (MASTERFILE.md:1728-1729).
//   Featured (larger cells, posture-aware): Play together, Messages,
//     Storyteller, Show & tell. Storyteller/Show & tell both carry real
//     centrality citations; Play together/Messages are disclosed judgment
//     calls (structural — the most-tapped surface / the one with live
//     unread state — not a MASTERFILE ranking).
//   Standard (current size, posture-aware): Homework, My list, More for
//     you. No citation either way for any of the three — they default
//     here.
// "More games" is deliberately NOT one of the 8 tiles above — PR #87's own
// real nav consolidation (v0.49.66, merged into this same reconciliation)
// folded it into "Play together"'s own `extraSections`, the same one door
// guardian_more.dart's own mirrored tile already uses, rather than keeping
// a second Standard-tier tile that would just relocate the exact redundant
// split PR #87 was written to close. The ad-hoc local-play games' own
// placement (Featured tier, once built) is a real, separate, still-open
// question — answered in the spec's §2 but deliberately NOT wired here.
//
// TieredTile — sub-project 3b (docs/superpowers/specs/2026-09-12-
// intuitivism-guardianhome-tiering-design.md). This screen's own former
// private `_Tile` now lives in tiered_tile.dart, unchanged, once
// guardian_home.dart became a second real consumer of the exact same
// shape rather than a second, drifting `_GTile` copy. This file's own
// migration onto it is a pure rename plus move — no behavior change,
// proven by this file's full existing test suite passing with zero
// test-file edits.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'calendar_day_logic.dart';
import 'call_screen.dart';
import 'child_more.dart';
import 'form_factors.dart' as ff;
import 'game_navigation.dart';
import 'game_picker.dart';
import 'games_hub.dart';
import 'homework_screen.dart';
import 'inbox_screen.dart';
import 'jokebook_screen.dart';
import 'live_game_picker.dart';
import 'my_day.dart';
import 'showcase_screen.dart';
import 'storyteller_screen.dart';
import 'tiered_tile.dart';
import 'wants_needs.dart';

class ChildHome extends StatelessWidget {
  const ChildHome({super.key, required this.childName, required this.presence,
    required this.sleepsUntilHandover, required this.unreadCount,
    this.baseUrl, this.childId, this.sessionToken, this.httpClient});

  final String childName;
  final ParentPresence? presence;
  // Nullable for the same reason `presence` is: no live custody-schedule
  // source exists yet for a screen fetching real data (see
  // child_home_live.dart), and a fabricated number would look exactly as
  // real as the two fields that genuinely are. Absent, not guessed.
  final int? sleepsUntilHandover;
  final int unreadCount;

  // Real homework-capture wiring (§9.1, §20.2b) — optional and additive, so
  // every existing caller (the offline demo build's ChildHome() with no
  // arguments, and every existing test) keeps behaving exactly as before.
  // Only child_home_live.dart supplies these today; when null, the
  // Homework tile pushed below still works, just against
  // capture_gate.dart's own honest simulated fallback (see that file's own
  // header) rather than a real server.
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  final http.Client? httpClient;

  @override
  Widget build(BuildContext context) => Scaffold(
    // LayoutBuilder sits ABOVE the scrollable, the same structural position
    // game_picker.dart's own posture migration (v0.49.17) already
    // established — inside it, `constraints` are the Scaffold body's real
    // bounded size, not the scrollable's own unbounded scroll-axis extent.
    body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final double textScale = MediaQuery.textScalerOf(context).scale(1);
      final int cross = ff.columnsAt(
          ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale);
      // Deliberately more conservative than game_picker.dart's own 1.0-2.0
      // clamp (its _GameCard fixed-182px bug is exactly the class of thing
      // this clamp exists to prevent repeating — see this file's own header
      // and the design spec's §3): this screen ALSO carries the "sleeps
      // until" counter below everything else, and that counter has been
      // pushed below the fold by grid growth twice before. Bounding how
      // much the new Hero+Featured bands can grow at large accessibility
      // text keeps that risk smaller, not eliminated — see child_home_test
      // .dart's own fold-line regression coverage.
      final double heightScale = textScale.clamp(1.0, 1.6);

      return SingleChildScrollView(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hi $childName', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        if (presence != null) _PresenceCard(presence!, childName: childName),
        const SizedBox(height: 12),

        // ================================================== Hero — My day
        // Not inside any GridView — a plain full-width band, always
        // spanning available width regardless of posture. No hero-cell/
        // variable-span grid mechanism exists anywhere in this codebase
        // (SliverGridDelegateWithFixedCrossAxisCount is the only delegate
        // ever used, uniform-cell by construction) — composing a separate
        // region sidesteps needing one, matching the spec's own §3
        // reasoning for staying inside a "refine, don't redesign" budget.
        TieredTile(key: const Key('childHomeHero'),
          icon: Icons.wb_sunny_outlined, label: 'My day', featured: true,
          hero: true, height: 140 * heightScale,
          onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => MyDayScreen(
              childName: childName, parts: demoDayParts, nowLocal: hhmmNow()))),
        ),
        const SizedBox(height: 10),

        // ============================================= Featured — larger,
        // posture-aware grid, directly under Hero.
        GridView(key: const Key('childHomeFeaturedGrid'),
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross, mainAxisSpacing: 10, crossAxisSpacing: 10,
            mainAxisExtent: 132 * heightScale),
          children: [
            // ONE door onto every real choice she has — the age-gated Play
            // Together grid AND the rest of the catalogue (checkers, chess,
            // battleship, word search…) that used to sit behind a separate
            // "More games" tile, now folded in as extraSections instead of
            // a second Standard-tier tile — see game_navigation.dart's own
            // header for why onPlay is one real shared function, not two
            // hand-copied switches (guardian_more.dart's own mirrored tile
            // uses the exact same one).
            TieredTile(icon: Icons.extension, label: 'Play together', featured: true,
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) {
                  final gameSections = [
                    MoreGamesSections(childName: childName),
                    JokebookSection(childName: childName),
                  ];
                  final onPlay = buildGameNavigator(childName);
                  // Intuitivism pass, sub-project 3a (docs/superpowers/specs/
                  // 2026-09-12-intuitivism-gamepicker-recommended-design.md)
                  // — her own Recommended row/Surprise-me button need a real
                  // session (baseUrl/childId/sessionToken, exactly the same
                  // trio InboxScreen's own call site above already threads
                  // through); without one, this renders exactly as it always
                  // has. NEVER onToggleFavorite here — she sees the result
                  // of a favorite, never the mechanism (the design spec's
                  // own "Where favoriting happens").
                  if (baseUrl != null && childId != null && sessionToken != null) {
                    return LiveGamePickerScreen(
                      baseUrl: baseUrl!, childId: childId!, sessionToken: sessionToken!,
                      childName: childName, httpClient: httpClient,
                      onPlay: onPlay, extraSections: gameSections,
                    );
                  }
                  return GamePickerScreen(
                    childName: childName, onPlay: onPlay, extraSections: gameSections,
                  );
                }))),
            TieredTile(icon: Icons.mail_outline, label: 'Messages', featured: true,
              badgeCount: unreadCount,
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => InboxScreen(
                  childName: childName, messages: List<InboxMessage>.of(demoInboxMessages),
                  baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                  httpClient: httpClient)))),
            TieredTile(icon: Icons.auto_stories_outlined, label: 'Storyteller', featured: true,
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StorytellerScreen(childName: childName)))),
            TieredTile(icon: Icons.photo_camera_outlined, label: 'Show & tell', featured: true,
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ShowcaseScreen(childName: childName)))),
          ],
        ),
        const SizedBox(height: 10),

        // ============================================= Standard — current
        // size, posture-aware grid, below Featured. Same GridView shape the
        // whole screen used to use for all 9 tiles, now scoped to the 3
        // without an elevation signal. "More games" no longer has its own
        // tile here — the same real, avoidable split this file's own header
        // used to describe (a second door onto part of the same catalogue)
        // is now closed the other way: it's folded into "Play together"'s
        // own extraSections above, not kept as a second Standard entry that
        // would just move the redundancy rather than remove it (matching
        // guardian_more.dart's own identical consolidation).
        GridView(key: const Key('childHomeStandardGrid'),
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross, mainAxisSpacing: 10, crossAxisSpacing: 10,
            mainAxisExtent: 84 * heightScale),
          children: [
            TieredTile(icon: Icons.edit, label: 'Homework',
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => HomeworkScreen(childName: childName,
                  baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                  httpClient: httpClient)))),
            TieredTile(icon: Icons.star_border, label: 'My list',
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const WantsNeedsScreen()))),
            TieredTile(icon: Icons.more_horiz, label: 'More for you',
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ChildMoreScreen(childName: childName,
                  baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                  httpClient: httpClient)))),
          ],
        ),

        if (sleepsUntilHandover != null) ...[
          const SizedBox(height: 12),
          _Sleeps(sleepsUntilHandover!),
        ],
      ]));
    })),
  );
}

class ParentPresence {
  const ParentPresence(this.name, this.theirLocalTime, this.freeUntilHerTime);
  final String name, theirLocalTime, freeUntilHerTime;
}

class _PresenceCard extends StatelessWidget {
  const _PresenceCard(this.p, {required this.childName});
  final ParentPresence p;
  final String childName;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${p.name} is free right now',
        style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600)),
      // HER frame first; his time is the aside.
      Text("It's ${p.theirLocalTime} where ${p.name} is · "
           'until ${p.freeUntilHerTime}',
        style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: 48,
        child: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CallScreen(who: 'ivy', displayName: childName))),
          child: Text('Call ${p.name}'))),
    ]),
  ));
}

class _Sleeps extends StatelessWidget {
  const _Sleeps(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Row(children: [
    // Hand-set hero numeral, not a textTheme role — documented exception
    // (§8.2.5; kept bespoke per the UI/UX design-token audit's typography
    // finding).
    Text('$n', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
    const SizedBox(width: 12),
    // Real, pre-existing §8.11.1-class bug found by the intuitivism
    // sub-project 2 pass's own new text-scale regression coverage — this
    // widget's own two-line caption had no Expanded/Flexible wrapper, so at
    // large accessibility text on a narrow screen (2.0x @ 344px Fold-cover)
    // it overflowed the Row horizontally. Fixed here rather than left as
    // one more instance of the class of bug this whole pass exists to
    // avoid repeating; the fix is `Expanded`, not a hand-tuned width, so it
    // holds at every posture, not just the two sizes this bug happened to
    // be caught at.
    Expanded(
      // "sleeps", never hours. Children do not think in hours (§8.2.5).
      child: Text(n == 1 ? 'sleep until\nthe handover' : 'sleeps until\nthe handover',
        style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ),
  ]);
}
