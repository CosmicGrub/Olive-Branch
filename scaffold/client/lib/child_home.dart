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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'access_scope.dart';
import 'activity_overrides.dart';
import 'calendar_day_logic.dart';
import 'call_screen.dart';
import 'child_home_bands.dart';
import 'child_home_bands_ui.dart';
import 'child_home_growth.dart';
import 'child_more.dart';
import 'colouring_screen.dart';
import 'contact_labels.dart';
import 'doodle_desk.dart';
import 'cover_collapse.dart';
import 'family_structure_screens.dart';
import 'family_structure_store.dart';
import 'form_factors.dart' as ff;
import 'game_logic.dart' show neutralGrownUp;
import 'grownup_labels.dart' show GrownupLabelScope, GrownupLabels, asSubject;
import 'game_navigation.dart';
import 'game_picker.dart';
import 'games_hub.dart';
import 'growing_care_logic.dart';
import 'growing_care_store.dart';
import 'growing_screens.dart';
import 'her_colour_home.dart';
import 'homework_screen.dart';
import 'inbox_screen.dart';
import 'jokebook_screen.dart';
import 'journal_screen.dart';
import 'letters_screen.dart';
import 'live_game_picker.dart';
import 'local_services.dart';
import 'maturation_ladder.dart';
import 'my_day.dart';
import 'play_window_gate.dart';
import 'showcase_screen.dart';
import 'storyteller_screen.dart';
import 'tiered_tile.dart';
import 'wants_needs.dart';
import 'weeks_screen.dart';

class ChildHome extends StatelessWidget {
  const ChildHome({super.key, required this.childName, required this.presence,
    required this.sleepsUntilHandover, required this.unreadCount,
    this.baseUrl, this.childId, this.sessionToken, this.httpClient,
    this.childAge = 7, this.overrides, this.dayParts, this.guardianName,
    this.family, this.speak, this.growth, this.clock, this.nicknames});

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

  // Parental controls, visibility & pacing (docs/superpowers/specs/2026-09-
  // 13-parental-controls-pacing-design.md). [childAge] defaults to 7 —
  // matching game_picker.dart's/games_hub.dart's own pre-existing default —
  // for the same reason those already do: no real, live child-age source is
  // threaded into this screen yet (a separate, pre-existing gap this
  // feature does not newly create). [overrides] is this child's guardian-
  // set overrides, fetched ONCE by child_home_live.dart and handed down as
  // plain data, matching every field above; null (every existing caller,
  // including every pre-existing test) renders exactly as before this
  // feature existed — activity_overrides.dart's [isTileVisible] with a null
  // map never hides anything.
  final int childAge;
  final Map<String, ActivityOverride>? overrides;

  /// Today's real day parts in HER zone, from GET .../now (C-10). Null means
  /// "not supplied": the offline/demo build (no [baseUrl]) then shows the
  /// demo hours, while a live build with none supplied shows an honest empty
  /// day rather than invented hours.
  final List<DayPartLite>? dayParts;

  /// The real display name of the grown-up the child talks to (C-13), when a
  /// live session knows one. Null falls back to who is free right now
  /// ([presence]) and finally to [neutralGrownUp] — never a guessed "Dad".
  final String? guardianName;
  /// Her own word for her grown-up when a [GrownupLabelScope] knows one (nickname, then the age default,
  /// then the guardian's label); otherwise the live name, then who is free, then the neutral phrase.
  String _grownUpIn(BuildContext context) {
    final GrownupLabels labels = GrownupLabelScope.read(context);
    return labels.hasPrimary ? labels.nameFor() : (guardianName ?? presence?.name ?? neutralGrownUp);
  }

  /// Age bands and family structure (suites J and K): her derived home, from what a guardian
  /// built and released on this device. Null (every existing caller) renders exactly as before.
  final FamilyChildSnapshot? family;
  /// Read-aloud for the youngest band's icon-only home. Null = no spoken names.
  final Future<void> Function(String)? speak;

  /// Wave 2a: the 'your home grows' state (birthday growth page and the Later card). Null = never shown.
  final ChildGrowth? growth;

  /// Her local clock for greetings (null = the device clock). Injected by tests and the parity replay.
  final DateTime Function()? clock;

  /// Hers (the only writer of what she calls her grown-ups). Null = this device's own store.
  final NicknameRepository? nicknames;
  bool _fam(String tile) => family == null || family!.view.hasTile(tile);
  String get _greeting => family?.view.plainGreeting == true ? 'Hey $childName' : 'Hi $childName';

  /// ONE door onto every real choice she has — the age-gated Play Together grid AND the rest of the catalogue
  /// (checkers, chess, battleship, word search…), see game_navigation.dart's header for why onPlay is one shared
  /// function. Used by the plain home's Play together tile and by the band homes' Play / Games / Downtime tile.
  Widget _playScreen(BuildContext context) {
    final gameSections = [
      MoreGamesSections(childName: childName, parentName: _grownUpIn(context),
        childAge: childAge, overrides: overrides),
      JokebookSection(childName: childName, parentName: _grownUpIn(context),
        childAge: childAge, overrides: overrides),
    ];
    final onPlay = buildGameNavigator(childName, parentName: _grownUpIn(context));
    // Intuitivism pass, sub-project 3a (docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-design.md)
    // — her own Recommended row/Surprise-me button need a real session (baseUrl/childId/sessionToken, exactly the
    // same trio InboxScreen's own call site also threads through); without one, this renders exactly as it always
    // has. NEVER onToggleFavorite here — she sees the result of a favorite, never the mechanism.
    if (baseUrl != null && childId != null && sessionToken != null) {
      return PlayWindowGate(child: LiveGamePickerScreen(
        baseUrl: baseUrl!, childId: childId!, sessionToken: sessionToken!,
        childName: childName, childAge: childAge, httpClient: httpClient,
        onPlay: onPlay, extraSections: gameSections, overrides: overrides,
      ));
    }
    return PlayWindowGate(child: GamePickerScreen(
      childName: childName, childAge: childAge, onPlay: onPlay,
      extraSections: gameSections, overrides: overrides,
    ));
  }

  // ===================================================== wave 2a: the per-age homes ==
  /// The band whose home is drawn from the table (child_home_bands.dart), or null for every other case. Only with
  /// a family snapshot (a guardian built and released this home); with none the plain home above is what she gets.
  String? get _bandHomeBand {
    final FamilyChildSnapshot? f = family;
    if (f == null) return null;
    return kBandsDrawnHere.contains(f.view.band) ? f.view.band : null;
  }

  /// Tile ids a guardian hid with a switch (Messages is never one of them).
  Set<String> get _hiddenIds => <String>{
        for (final MapEntry<String, String> e in kTileOverrideKey.entries)
          if (!isTileVisible(overrides, e.value) && tileHideable(e.key)) e.key,
      };

  NicknameRepository _nicknameRepo() {
    final NicknameRepository? given = nicknames;
    if (given != null) return given;
    try {
      return LocalNicknameRepository(LocalServices.current.area('nicknames'));
    } catch (_) {
      return MemoryNicknameRepository();
    }
  }

  Widget _inbox() => InboxScreen(
        childName: childName, messages: List<InboxMessage>.of(demoInboxMessages),
        baseUrl: baseUrl, childId: childId, sessionToken: sessionToken, httpClient: httpClient);

  /// Where each band-home tile goes. Null = no destination (the tile is not drawn anywhere).
  Widget? _bandDestination(BuildContext context, String id, FamilyChildSnapshot f, String band) {
    switch (id) {
      case 'day':
        return MyDayScreen(
            childName: childName,
            parts: dayParts ?? (baseUrl == null ? demoDayParts : const <DayPartLite>[]),
            nowLocal: hhmmNow());
      case 'play':
        return _playScreen(context);
      case 'msgs':
        return _inbox();
      case 'stories':
      case 'storyteller':
        return StorytellerScreen(childName: childName);
      case 'showtell':
        return ShowcaseScreen(childName: childName);
      case 'people':
        final GrownupLabels labels = GrownupLabelScope.read(context);
        return MyPeopleScreen(
          snapshot: f, childName: childName, nicknames: _nicknameRepo(),
          age: labels.age.age == null ? AgeLockState(age: childAge) : labels.age,
          onCall: (BuildContext c, String personId, String name) => Navigator.of(c).push(MaterialPageRoute<void>(
              builder: (_) => CallScreen(who: 'ivy', displayName: childName))),
          onMessage: (BuildContext c, String personId, String name) =>
              Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => _inbox())),
        );
      case 'colour':
        return HerColourScreen(childName: childName, childAge: childAge);
      case 'more':
        return _bandMore(context, f, band);
      case 'list':
        return const WantsNeedsScreen();
      case 'weeks':
        final List<String> names = GrownupLabelScope.read(context).twoNames();
        return WeeksScreen(
            childName: childName, nights: demoCustodyNights(names: names), guardianColors: demoGuardianColorsFor(names));
      case 'journal':
        return JournalScreen(childName: childName);
      case 'memory':
        return MemoryBoxScreen(childName: childName);
      case 'capsule':
        return LettersScreen(
            childName: childName, currentAge: childAge, childId: childId ?? 'demo-child',
            baseUrl: baseUrl, sessionToken: sessionToken, httpClient: httpClient);
      case 'growth':
        return GrowthPictureScreen(childName: childName);
      case 'jokes':
        return JokebookScreen(
            childName: childName, childAge: childAge, parentName: _grownUpIn(context), overrides: overrides);
      case 'draw':
        return DrawChoiceScreen(
            title: bandTileTitle('draw', band), doodle: DoodleDesk(childName: childName), colouring: const ColouringScreen());
      case 'birthday':
        final ChildBirthday? b = f.birthday;
        return b == null ? null : BirthdayScreen(birthday: b);
      case 'ladder':
        return MaturationLadderScreen(childName: childName, childAgeYears: childAge, viewer: LadderViewer.child);
    }
    return null;
  }

  Future<Set<String>> _suiteHidden() async {
    try {
      final GrowingCareStores s = GrowingCareStores.forChild();
      final ChildSuites suites =
          childSuitesFor(view: family?.view, yearsOld: childAge, switches: await s.switches.load());
      final bool marks = suites.pencilMarks && (await s.childLens().growth()).isNotEmpty;
      return <String>{if (!suites.memoryBox) 'memory', if (!marks) 'growth'};
    } catch (_) {
      return <String>{'memory', 'growth'}; // fail closed: an unreadable store shows neither
    }
  }

  Widget _bandMore(BuildContext context, FamilyChildSnapshot f, String band) => ChildBandMoreScreen(
        band: band, age: childAge, hasBirthday: f.birthday != null, hidden: _hiddenIds,
        loadHidden: _suiteHidden,
        destination: (BuildContext c, String id) => _bandDestination(c, id, f, band),
        speak: null,
        extras: <BandMoreExtra>[
          // The prototype's 8-12 home has no My day tile (it has the weeks strip), but My day shipped and carries her
          // real day parts: it stays one tap away, here.
          if (band == 't812' && _fam('myDay'))
            BandMoreExtra(
              key: 'moreMyDay', icon: Icons.wb_sunny_outlined, label: 'My day',
              build: (BuildContext c) => _bandDestination(c, 'day', f, band)!),
          if (isTileVisible(overrides, 'tile:homework') && _fam('homework'))
            BandMoreExtra(
              key: 'moreHomework', icon: Icons.edit, label: 'Homework',
              build: (BuildContext c) => HomeworkScreen(childName: childName,
                  baseUrl: baseUrl, childId: childId, sessionToken: sessionToken, httpClient: httpClient)),
          BandMoreExtra(
            key: 'moreEverything', icon: Icons.apps_outlined, label: 'Everything else',
            build: (BuildContext c) => ChildMoreScreen(childName: childName,
                baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                httpClient: httpClient, childAge: childAge, overrides: overrides,
                guardianName: _grownUpIn(c), family: family, speak: speak)),
        ],
      );

  Widget _bandHome(BuildContext context, FamilyChildSnapshot f, String band) {
    final ChildGrowth? gr = growth;
    return BandHome(
      band: band, age: childAge, childName: childName,
      tileIds: visibleHomeIds(band, childAge, viewTiles: f.view.tiles, hidden: _hiddenIds),
      destination: (BuildContext x, String id) => _bandDestination(x, id, f, band),
      unreadDot: unreadCount > 0, clock: clock,
      presence: presence == null ? null : _PresenceCard(presence!, childName: childName),
      footer: sleepsUntilHandover == null ? null : _Sleeps(sleepsUntilHandover!),
      birthdayLine: (f.birthday?.lineShown ?? false) ? birthdayLine(f.birthday!) : null,
      onBirthday: f.birthday == null ? null : () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BirthdayScreen(birthday: f.birthday!)))),
      onGrewTap: gr != null && gr.laterCard ? () => unawaited(gr.reopen()) : null,
    );
  }

  /// The quiet 'Your home grew' row on a home that is not drawn from the table (13 and up, until wave 2b).
  Widget? _grewRow() {
    final ChildGrowth? gr = growth;
    if (gr == null || !gr.laterCard) return null;
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: GrewCard(onTap: () => unawaited(gr.reopen())));
  }

  Widget _growPage(BuildContext context, FamilyChildSnapshot f, String band, ChildGrowth g, GrowthMark m) {
    final GrowPage page = kGrowPages[m.key]!;
    final String? tileId = kGrowDestTile[page.dest];
    final bool exists = tileId != null && kTilesWithDestination.contains(tileId) && _bandDestination(context, tileId, f, band) != null;
    final GrownupLabels labels = GrownupLabelScope.read(context);
    return ChildGrowScreen(
      page: page, destinationExists: exists, speak: speak,
      fromName: labels.hasPrimary ? labels.nameFor() : null,
      onLater: () => unawaited(g.markLater()),
      onShow: () async {
        await g.markSeen();
        if (!context.mounted || !exists) return;
        final Widget? to = _bandDestination(context, tileId, f, band);
        if (to != null) unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => to)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final FamilyChildSnapshot? f = family;
    final ChildGrowth? g = growth;
    // Wave 2a, render order (prototype renderHome): the 'your home grows' page, when it is ready, comes before
    // any band's home, and a home with none ready is drawn as it always was.
    if (f != null && g != null) {
      return ListenableBuilder(listenable: g, builder: (BuildContext c, Widget? _) {
        final GrowthMark? m = g.pageReady;
        return m != null ? _growPage(c, f, protoBand(f.view.band), g, m) : _home(c);
      });
    }
    return _home(context);
  }

  Widget _home(BuildContext context) {
    final FamilyChildSnapshot? f = family;
    if (f != null && f.view.homeVariant == 'icons3') {
      return AgeHome34(
        snapshot: f, childName: childName, speak: speak,
        onCall: (BuildContext c, String who) => Navigator.of(c).push(MaterialPageRoute<void>(
            builder: (_) => CallScreen(who: 'ivy', displayName: childName))),
        onStories: (BuildContext c) => Navigator.of(c).push(MaterialPageRoute<void>(
            builder: (_) => StorytellerScreen(childName: childName))),
        onColour: (BuildContext c) => Navigator.of(c).push(MaterialPageRoute<void>(
            builder: (_) => const ColouringScreen())),
      );
    }
    final String? band = _bandHomeBand;
    if (band != null) return _bandHome(context, f!, band);
    return _standard(context);
  }

  Widget _standard(BuildContext context) => Scaffold(
    // LayoutBuilder sits ABOVE the scrollable, the same structural position
    // game_picker.dart's own posture migration (v0.49.17) already
    // established — inside it, `constraints` are the Scaffold body's real
    // bounded size, not the scrollable's own unbounded scroll-axis extent.
    body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final double textScale = MediaQuery.textScalerOf(context).scale(1);
      final int rawCross = ff.columnsAt(
          ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale);
      // Floor of 2, not columnsAt()'s raw output — the identical fix
      // guardian_home.dart's own build() already applies to its Featured/
      // Standard grids (see that file's own comment): columnsAt() returns 1
      // below 660px effective width, which would collapse the real 7-inch
      // tabletSmall posture (min 600px, "often the child's only device")
      // down to a single stacked column here too. Design spec: docs/
      // superpowers/specs/2026-09-15-design-tokens-named-migration-design.md,
      // Fix #1.
      //
      // Only from 600px physical width up (tabletSmall's own floor, per
      // guardian_home.dart's own comment), confirmed by two real local
      // `flutter test` failures, not assumed: below 600px (foldCover at
      // 344/390px, AND a genuinely narrow non-foldCover phone at 360x740 —
      // neither foldCover-classified, both real) this screen's own 'More'
      // tile (below) reopens this exact `full` layout at the SAME narrow
      // physical width captured here, and unlike guardian_home.dart this
      // screen's Featured grid has no adaptive per-width mainAxisExtent
      // bump (that file's own 108/136 effectiveColumnWidth breakpoint is
      // what actually lets ITS clamped 2-narrow-columns fit at 344px
      // without overflow) — so flooring to 2 there overflowed for real, a
      // new bug, not the one this fix targets. FoldCover already gets its
      // own dedicated, deliberately single-column `collapsed` layout below
      // regardless of `cross`'s value, so excluding narrow widths here
      // changes nothing about what actually renders there.
      final int cross = constraints.maxWidth >= 600 ? rawCross.clamp(2, 3) : rawCross;
      // Deliberately more conservative than game_picker.dart's own 1.0-2.0
      // clamp (its _GameCard fixed-182px bug is exactly the class of thing
      // this clamp exists to prevent repeating — see this file's own header
      // and the design spec's §3): this screen ALSO carries the "sleeps
      // until" counter below everything else, and that counter has been
      // pushed below the fold by grid growth twice before. Bounding how
      // much the new Hero+Featured bands can grow at large accessibility
      // text keeps that risk smaller, not eliminated — see child_home_test
      // .dart's own fold-line regression coverage.
      // Roomier reading (a guardian option) lifts the line height from ~1.2 to 1.5,
      // so a tile's label needs a quarter more room; the tiles grow with it.
      final double roomy = AccessScope.of(context).roomierReading ? roomyLineHeight / 1.2 : 1.0;
      final double heightScale = textScale.clamp(1.0, 1.6) * roomy;

      // Shared between `full` and the foldCover `collapsed` layout below —
      // built once, mounted in whichever of the two CoverCollapse actually
      // renders (never both at once, so reusing this one Key is safe; see
      // cover_collapse_test.dart's own header for the general pattern).
      final Widget heroTile = TieredTile(key: const Key('childHomeHero'),
        icon: Icons.wb_sunny_outlined, label: 'My day', featured: true,
        hero: true, height: 140 * heightScale,
        onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MyDayScreen(
            childName: childName,
            parts: dayParts ?? (baseUrl == null ? demoDayParts : const <DayPartLite>[]),
            nowLocal: hhmmNow()))),
      );

      final Widget full = SingleChildScrollView(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting, style: Theme.of(context).textTheme.headlineMedium),
        if (family?.birthday?.lineShown ?? false)
          TextButton(
            key: const Key('birthdayLine'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => BirthdayScreen(birthday: family!.birthday!))),
            child: Text(birthdayLine(family!.birthday!))),
        const SizedBox(height: 12),
        if (presence != null) _PresenceCard(presence!, childName: childName),
        const SizedBox(height: 12),
        ?_grewRow(),

        // ================================================== Hero — My day
        // Not inside any GridView — a plain full-width band, always
        // spanning available width regardless of posture. No hero-cell/
        // variable-span grid mechanism exists anywhere in this codebase
        // (SliverGridDelegateWithFixedCrossAxisCount is the only delegate
        // ever used, uniform-cell by construction) — composing a separate
        // region sidesteps needing one, matching the spec's own §3
        // reasoning for staying inside a "refine, don't redesign" budget.
        heroTile,
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
            if (_fam('play')) TieredTile(icon: Icons.extension, label: 'Play together', featured: true,
              onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _playScreen(context)))),
            if (isTileVisible(overrides, 'tile:messages') && _fam('messages'))
              TieredTile(icon: Icons.mail_outline, label: 'Messages', featured: true,
                unreadDot: unreadCount > 0,
                onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => InboxScreen(
                    childName: childName, messages: List<InboxMessage>.of(demoInboxMessages),
                    baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                    httpClient: httpClient)))),
            if (isTileVisible(overrides, 'tile:storyteller') && _fam('stories'))
              TieredTile(icon: Icons.auto_stories_outlined, label: 'Storyteller', featured: true,
                onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => StorytellerScreen(childName: childName)))),
            if (isTileVisible(overrides, 'tile:showAndTell') && _fam('showTell'))
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
            if (family != null && _fam('myPeople'))
              TieredTile(key: const Key('childHomeMyPeople'), icon: Icons.people_outline, label: 'My people',
                onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => MyPeopleScreen(snapshot: family!, childName: childName)))),
            if (isTileVisible(overrides, 'tile:homework') && _fam('homework'))
              TieredTile(icon: Icons.edit, label: 'Homework',
                onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => HomeworkScreen(childName: childName,
                    baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                    httpClient: httpClient)))),
            if (isTileVisible(overrides, 'tile:myList') && _fam('myList'))
              TieredTile(icon: Icons.star_border, label: 'My list',
                onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const WantsNeedsScreen()))),
            if (isTileVisible(overrides, 'tile:more') && _fam('more'))
              TieredTile(icon: Icons.more_horiz, label: 'More for you',
                onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChildMoreScreen(childName: childName,
                    baseUrl: baseUrl, childId: childId, sessionToken: sessionToken,
                    httpClient: httpClient, childAge: childAge, overrides: overrides,
                    guardianName: _grownUpIn(context), family: family, speak: speak)))),
          ],
        ),

        if (sleepsUntilHandover != null) ...[
          const SizedBox(height: 12),
          _Sleeps(sleepsUntilHandover!),
        ],
      ]));

      // ==================================================== foldCover only
      // Intuitivism pass, sub-project 3c, Part 1 — at the Fold5's 344px
      // cover screen, this screen shows its single most load-bearing thing
      // (the ribbon/presence area, and the Hero tile) rather than the full
      // layout squeezed narrow. Featured and Standard collapse into a
      // single "More" tile — the exact same icon/label/push-a-full-screen
      // shape guardian_home.dart's own pre-existing "More" tile already
      // uses to reach GuardianMoreScreen, reused here rather than invented,
      // except this "More" opens `full` itself (this screen's own complete,
      // otherwise-unchanged layout) rather than a different hub screen — the
      // literal "full list" Featured/Standard collapsed away from, not a
      // second catalogue.
      final Widget collapsed = SingleChildScrollView(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting, style: Theme.of(context).textTheme.headlineMedium),
        if (family?.birthday?.lineShown ?? false)
          TextButton(
            key: const Key('birthdayLine'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => BirthdayScreen(birthday: family!.birthday!))),
            child: Text(birthdayLine(family!.birthday!))),
        const SizedBox(height: 12),
        if (presence != null) _PresenceCard(presence!, childName: childName),
        const SizedBox(height: 12),
        ?_grewRow(),
        heroTile,
        const SizedBox(height: 10),
        // Standard tier's own un-scaled height (84), not Hero's — this
        // tile stands in for the whole collapsed Featured/Standard tier,
        // not a second Hero. Explicit `height:` and an outer full-width
        // SizedBox, the same two things the Hero tile above gets for the
        // same reason (`TieredTile.hero`'s own width-stretch is gated on
        // `hero: true`, which would also change this tile's colour to
        // Hero's tertiaryContainer — not wanted for "More"): outside a
        // GridView's own mainAxisExtent, TieredTile's inner Column (its Spacer
        // needs a bounded height) has nothing else to size itself against.
        SizedBox(width: double.infinity, child: TieredTile(
          icon: Icons.more_horiz, label: 'More', height: 84 * heightScale,
          onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('More')),
              body: SafeArea(child: full),
            ))))),
      ]));

      return CoverCollapse(full: full, collapsed: collapsed);
    })),
  );
}

class ParentPresence {
  const ParentPresence(this.name, this.theirLocalTime, this.freeUntilHerTime, {this.userId});
  final String name, theirLocalTime, freeUntilHerTime;

  /// The grown-up's id, when known: lets the card show HER word for them (nickname, age default)
  /// through a [GrownupLabelScope] instead of the grown-up's own display name.
  final String? userId;
}

class _PresenceCard extends StatelessWidget {
  const _PresenceCard(this.p, {required this.childName});
  final ParentPresence p;
  final String childName;
  @override
  Widget build(BuildContext context) {
    final GrownupLabels labels = GrownupLabelScope.of(context);
    final String name = p.userId != null && labels.contact(p.userId) != null
        ? labels.nameFor(p.userId)
        : p.name;
    return _card(context, name);
  }

  Widget _card(BuildContext context, String name) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${asSubject(name)} is free right now',
        style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600)),
      // HER frame first; his time is the aside.
      Text("It's ${p.theirLocalTime} where $name is · "
           'until ${p.freeUntilHerTime}',
        style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: kChildTarget,
        child: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CallScreen(who: 'ivy', displayName: childName))),
          child: Text('Call $name'))),
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
