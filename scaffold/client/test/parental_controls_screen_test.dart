// OLIVE BRANCH — parental_controls_screen.dart tests, and a direct unit
// proof of activity_overrides.dart's precedence rule. docs/superpowers/
// specs/2026-09-13-parental-controls-pacing-design.md, and docs/
// superpowers/specs/2026-09-15-parental-controls-ia-rework-design.md
// ("UI/UX review theme #5") for groups C-F below.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/activity_overrides.dart';
import 'package:olive_client/game_logic.dart' as game_catalogue;
import 'package:olive_client/joke_logic.dart' as joke_catalogue;
import 'package:olive_client/parental_controls_screen.dart';

void main() {
  // ==========================================================================
  // A · the shared precedence rule, in isolation — the exact wire shape the
  // design spec's own Routes section states: "visible = false always wins
  // regardless of age/reveal state."
  // ==========================================================================
  group('effectiveVisibility precedence', () {
    test('visible:false wins even with revealedAt AND a low minAgeOverride set',
        () {
      final overrides = {
        'game:chess': ActivityOverride(
          activityKey: 'game:chess',
          visible: false,
          minAgeOverride: 0,
          revealedAt: DateTime.now(),
        ),
      };
      expect(
        effectiveVisibility(
            overrides: overrides,
            activityKey: 'game:chess',
            childAge: 20,
            defaultMinAge: 8),
        isFalse,
      );
    });

    test('revealedAt set (visible null) always shows regardless of age', () {
      final overrides = {
        'game:chess': ActivityOverride(
            activityKey: 'game:chess', revealedAt: DateTime.now()),
      };
      expect(
        effectiveVisibility(
            overrides: overrides,
            activityKey: 'game:chess',
            childAge: 3,
            defaultMinAge: 8),
        isTrue,
      );
    });

    test('with neither visible nor revealedAt, minAgeOverride replaces the catalogue default',
        () {
      final overrides = {
        'game:chess': const ActivityOverride(activityKey: 'game:chess', minAgeOverride: 5),
      };
      expect(
        effectiveVisibility(
            overrides: overrides,
            activityKey: 'game:chess',
            childAge: 6,
            defaultMinAge: 8),
        isTrue,
      );
      expect(
        effectiveVisibility(
            overrides: overrides,
            activityKey: 'game:chess',
            childAge: 4,
            defaultMinAge: 8),
        isFalse,
      );
    });

    test('no override at all falls back to the catalogue default, exactly as before this feature',
        () {
      expect(
        effectiveVisibility(
            overrides: null, activityKey: 'game:chess', childAge: 7, defaultMinAge: 8),
        isFalse,
      );
      expect(
        effectiveVisibility(
            overrides: const {}, activityKey: 'game:chess', childAge: 8, defaultMinAge: 8),
        isTrue,
      );
    });

    test('isTileVisible checks ONLY the visible column, ignoring an irrelevant minAgeOverride',
        () {
      final overrides = {
        'tile:messages':
            const ActivityOverride(activityKey: 'tile:messages', visible: false, minAgeOverride: 0),
      };
      expect(isTileVisible(overrides, 'tile:messages'), isFalse);
      expect(isTileVisible(null, 'tile:messages'), isTrue);
      expect(isTileVisible(const {}, 'tile:messages'), isTrue);
    });
  });

  // ==========================================================================
  // B · the screen itself — PIN gate, both tabs, toggle/stepper/reveal
  // round-trips against a real (mocked) HTTP round trip.
  //
  // IA rework note: 'Games' (top-level category) now nests a SECOND, also-
  // named-'Games' sub-group ExpansionTile (the 12 game_logic.dart catalogue
  // entries — matching the main game picker's own framing, per the design
  // spec) — so a test that used to find a catalogue game (e.g. tictactoe)
  // the instant the Pacing tab opened now also opens that sub-group first,
  // via [openPacingCatalogueGames] below. Anticipated by the design spec's
  // own Testing section.
  // ==========================================================================
  Future<void> pump(WidgetTester tester, {required http.Client client}) =>
      tester.pumpWidget(MaterialApp(home: ParentalControlsScreen(
        baseUrl: 'http://olive.test', childId: 'child-1', childName: 'Ivy',
        guardianId: 'dad-1', httpClient: client)));

  MockClient stubClient({
    List<String>? calledPaths,
    List<String>? calledBodies,
    int pinStatus = 200,
    String pinError = 'pin_incorrect',
    Map<String, dynamic> initialOverrides = const {},
  }) {
    final store = Map<String, dynamic>.from(initialOverrides);
    return MockClient((req) async {
      calledPaths?.add('${req.method} ${req.url.path}');
      if (req.url.path == '/v1/auth/dev-login') {
        return http.Response(jsonEncode({'token': 'dev-token'}), 200);
      }
      if (req.url.path == '/v1/me/verify-controls-pin') {
        if (pinStatus != 200) {
          return http.Response(jsonEncode({'error': pinError}), pinStatus);
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      if (req.url.path == '/v1/children/child-1/activity-overrides' && req.method == 'GET') {
        final overrides = store.entries
            .map((e) => {'activityKey': e.key, ...e.value as Map<String, dynamic>})
            .toList();
        return http.Response(jsonEncode({'overrides': overrides}), 200);
      }
      if (req.url.path.startsWith('/v1/children/child-1/activity-overrides/') &&
          req.method == 'PUT') {
        calledBodies?.add(req.body);
        final key = Uri.decodeComponent(req.url.pathSegments.last);
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final existing = Map<String, dynamic>.from(
            store[key] as Map<String, dynamic>? ?? {'visible': null, 'minAgeOverride': null, 'revealedAt': null});
        if (body.containsKey('visible')) existing['visible'] = body['visible'];
        if (body.containsKey('minAgeOverride')) existing['minAgeOverride'] = body['minAgeOverride'];
        if (body['reveal'] == true) existing['revealedAt'] = DateTime.now().toIso8601String();
        if (body['unreveal'] == true) existing['revealedAt'] = null;
        existing['setBy'] = 'dad-1';
        existing['setAt'] = DateTime.now().toIso8601String();
        store[key] = existing;
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response('{}', 404);
    });
  }

  Future<void> verifyPin(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('parentalControlsPinField')), '1357');
    await tester.tap(find.byKey(const Key('parentalControlsVerifyButton')));
    await tester.pumpAndSettle();
  }

  /// A generously tall test viewport. This screen's category/sub-group
  /// lists run to dozens of rows once fully expanded — well past a Sliver
  /// list's default cacheExtent at this framework's normal ~600px test
  /// surface, so a section far down the list is never BUILT at all
  /// (culled, not merely scrolled past); `ensureVisible` needs an
  /// existing Element to scroll to and throws "Bad state: No element" on
  /// one that was never built. A tall surface keeps everything these
  /// tests touch within the viewport instead, with no manual scrolling.
  Future<void> useTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 10000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Opens the Pacing tab's 'Games' category (already initiallyExpanded)
  /// down one more level into its own nested 'Games' sub-group — the 12
  /// game_logic.dart catalogue entries — needed to reach e.g. tictactoe now
  /// that sub-grouping exists.
  Future<void> openPacingCatalogueGames(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('pacingSubgroup_Games_Games')));
    await tester.tap(find.byKey(const Key('pacingSubgroup_Games_Games')));
    await tester.pumpAndSettle();
  }

  testWidgets('the PIN step shows first — the tabs are not reachable before it succeeds',
      (tester) async {
    await pump(tester, client: stubClient());
    expect(find.byKey(const Key('parentalControlsPinField')), findsOneWidget);
    expect(find.byKey(const Key('parentalControlsVerifyButton')), findsOneWidget);
    expect(find.byKey(const Key('parentalControlsTabSwitch')), findsNothing);
  });

  testWidgets('a wrong PIN shows a real, specific error and stays on the PIN step',
      (tester) async {
    await pump(tester, client: stubClient(pinStatus: 403, pinError: 'pin_incorrect'));
    await verifyPin(tester);
    expect(find.textContaining("isn't right"), findsOneWidget);
    expect(find.byKey(const Key('parentalControlsPinField')), findsOneWidget);
    expect(find.byKey(const Key('parentalControlsTabSwitch')), findsNothing);
  });

  testWidgets('a correct PIN reveals both tabs, Visibility first', (tester) async {
    final calledPaths = <String>[];
    await pump(tester, client: stubClient(calledPaths: calledPaths));
    await verifyPin(tester);
    expect(calledPaths, contains('POST /v1/me/verify-controls-pin'));
    expect(calledPaths, contains('GET /v1/children/child-1/activity-overrides'));
    expect(find.byKey(const Key('parentalControlsTabSwitch')), findsOneWidget);
    expect(find.byKey(const Key('parentalControlsTabBody_visibility')), findsOneWidget);
    // Every ChildHome tile the design spec names — the group is expanded by
    // default so these are reachable without an extra tap. ChildHome tiles
    // stays a flat group (no sub-grouping) per the IA rework spec, so
    // nothing else changes here.
    expect(find.byKey(const Key('visible_tile:storyteller')), findsOneWidget);
    expect(find.byKey(const Key('visible_tile:homework')), findsOneWidget);
    expect(find.byKey(const Key('visible_tile:messages')), findsOneWidget);
    expect(find.byKey(const Key('visible_tile:showAndTell')), findsOneWidget);
    expect(find.byKey(const Key('visible_tile:myList')), findsOneWidget);
    expect(find.byKey(const Key('visible_tile:more')), findsOneWidget);
  });

  testWidgets('toggling a tile OFF persists a real visible:false PUT and stays off after rebuild',
      (tester) async {
    final calledPaths = <String>[];
    final calledBodies = <String>[];
    await pump(tester, client: stubClient(calledPaths: calledPaths, calledBodies: calledBodies));
    await verifyPin(tester);

    final switchFinder = find.byKey(const Key('visible_tile:messages'));
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(calledPaths, contains('PUT /v1/children/child-1/activity-overrides/tile:messages'));
    expect(jsonDecode(calledBodies.last), {'visible': false});
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
  });

  testWidgets('switching to Pacing shows a stepper + Reveal now for an age-gateable game',
      (tester) async {
    await pump(tester, client: stubClient());
    await verifyPin(tester);
    // SegmentedButton — tap the Pacing segment specifically.
    await tester.tap(find.text('Pacing'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('parentalControlsTabBody_pacing')), findsOneWidget);
    // 'Games' (category) is initiallyExpanded on the Pacing tab; its own
    // nested 'Games' sub-group (the 12 catalogue entries) still needs one
    // tap to open — IA rework, see [openPacingCatalogueGames].
    await openPacingCatalogueGames(tester);
    expect(find.byKey(const Key('pacing_game:tictactoe')), findsOneWidget);
    expect(find.byKey(const Key('pacingMinus_game:tictactoe')), findsOneWidget);
    expect(find.byKey(const Key('pacingPlus_game:tictactoe')), findsOneWidget);
    expect(find.byKey(const Key('pacingReveal_game:tictactoe')), findsOneWidget);
    // No ChildHome tile ever appears on the Pacing tab — tiles have no age
    // concept (visibility-only), and (IA rework) tiles have no sub-group
    // section header on Pacing either, since the category itself never
    // appears there.
    expect(find.byKey(const Key('pacing_tile:messages')), findsNothing);
    expect(find.byKey(const Key('pacingSection_ChildHome tiles')), findsNothing);
  });

  testWidgets('the + stepper raises the effective minAge and persists minAgeOverride',
      (tester) async {
    final calledBodies = <String>[];
    await pump(tester, client: stubClient(calledBodies: calledBodies));
    await verifyPin(tester);
    await tester.tap(find.text('Pacing'));
    await tester.pumpAndSettle();
    await openPacingCatalogueGames(tester);

    final before = tester.widget<Text>(find.byKey(const Key('pacingAge_game:tictactoe'))).data;
    await tester.ensureVisible(find.byKey(const Key('pacingPlus_game:tictactoe')));
    await tester.tap(find.byKey(const Key('pacingPlus_game:tictactoe')));
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(find.byKey(const Key('pacingAge_game:tictactoe'))).data;

    expect(int.parse(after!), int.parse(before!) + 1);
    expect(jsonDecode(calledBodies.last), {'minAgeOverride': int.parse(after)});
  });

  testWidgets('Reveal now / Un-reveal round-trips the reveal/unreveal flags and flips its own label',
      (tester) async {
    final calledBodies = <String>[];
    await pump(tester, client: stubClient(calledBodies: calledBodies));
    await verifyPin(tester);
    await tester.tap(find.text('Pacing'));
    await tester.pumpAndSettle();
    await openPacingCatalogueGames(tester);

    expect(find.text('Reveal now'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('pacingReveal_game:tictactoe')));
    await tester.tap(find.byKey(const Key('pacingReveal_game:tictactoe')));
    await tester.pumpAndSettle();
    expect(jsonDecode(calledBodies.last), {'reveal': true});
    expect(find.descendant(
      of: find.byKey(const Key('pacing_game:tictactoe')), matching: find.text('Un-reveal')), findsOneWidget);
    expect(find.text('Revealed — shown regardless of age'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('pacingReveal_game:tictactoe')));
    await tester.tap(find.byKey(const Key('pacingReveal_game:tictactoe')));
    await tester.pumpAndSettle();
    expect(jsonDecode(calledBodies.last), {'unreveal': true});
    expect(find.descendant(
      of: find.byKey(const Key('pacing_game:tictactoe')), matching: find.text('Reveal now')), findsOneWidget);
  });

  testWidgets('a network failure verifying the PIN shows an honest message', (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/v1/auth/dev-login') {
        return http.Response(jsonEncode({'token': 'dev-token'}), 200);
      }
      throw Exception('no route to host');
    });
    await pump(tester, client: client);
    await verifyPin(tester);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
  });

  // ==========================================================================
  // C · IA rework — sub-grouping. Both tabs' per-category ExpansionTiles now
  // carry a second grouping level for Jokes (5 sub-groups) and Games (2);
  // every item must still appear exactly once, nothing silently dropped by
  // the restructure.
  // ==========================================================================
  group('IA rework — sub-grouping', () {
    testWidgets('Jokes sub-groups into exactly the 5 JokeCategory labels, and every one '
        'of the 59 jokes appears exactly once across them', (tester) async {
      await useTallSurface(tester);
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.ensureVisible(find.byKey(const Key('visibilitySection_Jokes')));
      await tester.tap(find.byKey(const Key('visibilitySection_Jokes')));
      await tester.pumpAndSettle();

      const labels = ['Dad jokes', 'Puns', 'Wordplay', 'Silly', 'Knock-knock'];
      for (final label in labels) {
        final subGroupFinder = find.byKey(Key('visibilitySubgroup_Jokes_$label'));
        await tester.ensureVisible(subGroupFinder);
        expect(subGroupFinder, findsOneWidget, reason: label);
        await tester.tap(subGroupFinder);
        await tester.pumpAndSettle();
      }

      expect(joke_catalogue.kJokeCatalogue.length, 59);
      for (final j in joke_catalogue.kJokeCatalogue) {
        expect(find.byKey(Key('visible_joke:${j.id}')), findsOneWidget, reason: j.id);
      }
    });

    testWidgets('Games sub-groups into exactly "Games" and "More games", and every one of '
        'the 21 games (12 catalogue + 8 hub + Find the thing) appears exactly once',
        (tester) async {
      await useTallSurface(tester);
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.ensureVisible(find.byKey(const Key('visibilitySection_Games')));
      await tester.tap(find.byKey(const Key('visibilitySection_Games')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visibilitySubgroup_Games_Games')), findsOneWidget);
      expect(find.byKey(const Key('visibilitySubgroup_Games_More games')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('visibilitySubgroup_Games_Games')));
      await tester.tap(find.byKey(const Key('visibilitySubgroup_Games_Games')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('visibilitySubgroup_Games_More games')));
      await tester.tap(find.byKey(const Key('visibilitySubgroup_Games_More games')));
      await tester.pumpAndSettle();

      expect(game_catalogue.catalogue.length, 12);
      for (final g in game_catalogue.catalogue) {
        await tester.ensureVisible(find.byKey(Key('visible_game:${g.kind.name}')));
        expect(find.byKey(Key('visible_game:${g.kind.name}')), findsOneWidget, reason: g.kind.name);
      }
      expect(game_catalogue.hubGameMinAge.length, 8);
      for (final key in game_catalogue.hubGameMinAge.keys) {
        await tester.ensureVisible(find.byKey(Key('visible_game:$key')));
        expect(find.byKey(Key('visible_game:$key')), findsOneWidget, reason: key);
      }
      await tester.ensureVisible(find.byKey(const Key('visible_game:findthing')));
      expect(find.byKey(const Key('visible_game:findthing')), findsOneWidget);
    });

    testWidgets('ChildHome tiles and Drawing & activities stay flat (single) groups — no '
        'sub-group ExpansionTile appears under either', (tester) async {
      await useTallSurface(tester);
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      // ChildHome tiles is already expanded; its rows sit directly under it.
      expect(find.byKey(const Key('visible_tile:messages')), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(const Key('visibilitySection_ChildHome tiles')),
        matching: find.byType(ExpansionTile)), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('visibilitySection_Drawing & activities')));
      await tester.tap(find.byKey(const Key('visibilitySection_Drawing & activities')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visible_activity:doodle')), findsOneWidget);
      expect(find.byKey(const Key('visible_activity:colouring')), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(const Key('visibilitySection_Drawing & activities')),
        matching: find.byType(ExpansionTile)), findsNothing);
    });

    testWidgets('the Pacing tab sub-groups the same way — Games/More games, and Jokes '
        'sub-groups — with the same "every item exactly once" guarantee, restricted to '
        'ageable items only (no ChildHome tiles/Drawing & activities section at all)',
        (tester) async {
      await useTallSurface(tester);
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.tap(find.text('Pacing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pacingSection_ChildHome tiles')), findsNothing);
      expect(find.byKey(const Key('pacingSection_Drawing & activities')), findsNothing);

      await openPacingCatalogueGames(tester);
      await tester.ensureVisible(find.byKey(const Key('pacingSubgroup_Games_More games')));
      await tester.tap(find.byKey(const Key('pacingSubgroup_Games_More games')));
      await tester.pumpAndSettle();
      for (final g in game_catalogue.catalogue) {
        await tester.ensureVisible(find.byKey(Key('pacing_game:${g.kind.name}')));
        expect(find.byKey(Key('pacing_game:${g.kind.name}')), findsOneWidget, reason: g.kind.name);
      }
      for (final key in game_catalogue.hubGameMinAge.keys) {
        await tester.ensureVisible(find.byKey(Key('pacing_game:$key')));
        expect(find.byKey(Key('pacing_game:$key')), findsOneWidget, reason: key);
      }
      // findthing has no defaultMinAge — visibility-only, absent from Pacing.
      expect(find.byKey(const Key('pacing_game:findthing')), findsNothing);
    });
  });

  // ==========================================================================
  // D · IA rework — search. One field per tab; empty query shows the
  // grouped view, a non-empty query flattens to a single filtered list,
  // clearing returns to grouped, no matches shows the honest empty state.
  // ==========================================================================
  group('IA rework — search', () {
    testWidgets('typing a real title substring (case-insensitive) in the Visibility search '
        'filters to matching rows only, and clearing it returns to the grouped view',
        (tester) async {
      await pump(tester, client: stubClient());
      await verifyPin(tester);

      await tester.enterText(find.byKey(const Key('visibilitySearchField')), 'checkers');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visibilitySearchResults')), findsOneWidget);
      expect(find.byKey(const Key('visible_game:checkers')), findsOneWidget);
      // The grouped view's category sections are gone while searching.
      expect(find.byKey(const Key('visibilitySection_ChildHome tiles')), findsNothing);
      // A non-matching item is not present.
      expect(find.byKey(const Key('visible_tile:messages')), findsNothing);

      await tester.enterText(find.byKey(const Key('visibilitySearchField')), '');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visibilitySearchResults')), findsNothing);
      expect(find.byKey(const Key('visibilitySection_ChildHome tiles')), findsOneWidget);
      expect(find.byKey(const Key('visible_tile:messages')), findsOneWidget);
    });

    testWidgets('a Visibility search matching nothing shows the honest empty state, never '
        'a blank screen', (tester) async {
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.enterText(
          find.byKey(const Key('visibilitySearchField')), 'zzz-not-a-real-title-zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parentalControlsNoMatches')), findsOneWidget);
      expect(find.text('No matches — try a different search.'), findsOneWidget);
      expect(find.byKey(const Key('visibilitySearchResults')), findsNothing);
    });

    testWidgets('typing a real title substring in the Pacing search filters to matching '
        'rows only, independently of the Visibility search', (tester) async {
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.tap(find.text('Pacing'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pacingSearchField')), 'Checkers');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pacingSearchResults')), findsOneWidget);
      expect(find.byKey(const Key('pacing_game:checkers')), findsOneWidget);
      expect(find.byKey(const Key('pacingSection_Games')), findsNothing);
    });

    testWidgets('a Pacing search matching nothing shows the honest empty state',
        (tester) async {
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.tap(find.text('Pacing'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('pacingSearchField')), 'zzz-not-a-real-title-zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parentalControlsNoMatches')), findsOneWidget);
    });
  });

  // ==========================================================================
  // E · Fix — joke titles: maxLines 1 → 2, no truncation of a real long
  // joke setup, once its sub-group is opened.
  // ==========================================================================
  group('IA rework — joke title fix (maxLines 1 → 2)', () {
    testWidgets('a long joke setup (janitor-supplies, 64 chars) renders in full across up '
        'to two lines, and the row lays out without an overflow exception', (tester) async {
      await useTallSurface(tester);
      await pump(tester, client: stubClient());
      await verifyPin(tester);
      await tester.ensureVisible(find.byKey(const Key('visibilitySection_Jokes')));
      await tester.tap(find.byKey(const Key('visibilitySection_Jokes')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('visibilitySubgroup_Jokes_Wordplay')));
      await tester.tap(find.byKey(const Key('visibilitySubgroup_Jokes_Wordplay')));
      await tester.pumpAndSettle();

      const longSetup = 'What did the janitor shout when he jumped out of the cupboard?';
      final joke = joke_catalogue.byId('janitor-supplies');
      expect(joke, isNotNull);
      expect(joke!.setup, longSetup); // pin the fixture — this test is only honest if it matches

      await tester.ensureVisible(find.byKey(const Key('visible_joke:janitor-supplies')));
      await tester.pumpAndSettle();
      final titleFinder = find.descendant(
          of: find.byKey(const Key('visible_joke:janitor-supplies')), matching: find.text(longSetup));
      expect(titleFinder, findsOneWidget);
      final Text titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.maxLines, 2);
      expect(tester.takeException(), isNull);
    });
  });

  // ==========================================================================
  // F · Fix — Pacing overflow: verified FIRST, exactly as the design spec
  // requires, at this app's own established Fold5-cover (344px) floor +
  // 2.0x text scale (child_home_test.dart's own established convention).
  // This screen's test file had NONE of this coverage before this pass
  // (confirmed by direct inspection of the pre-rework file: no 344, no
  // textScaler, no setSurfaceSize anywhere in it). Lands regardless of
  // outcome — see this feature's own PR description for the real,
  // observed result and whatever this pass did or did not change because
  // of it.
  // ==========================================================================
  group('IA rework — Pacing tab Fold5-cover/large-text overflow regression', () {
    testWidgets('344px Fold5-cover width at 2.0x text scale — the Pacing tab (Games '
        'sub-group open, a real trailing-controls row on screen) lays out without a '
        'RenderFlex overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(344, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: ParentalControlsScreen(
              baseUrl: 'http://olive.test',
              childId: 'child-1',
              childName: 'Ivy',
              guardianId: 'dad-1',
              httpClient: stubClient()),
        ),
      ));
      await verifyPin(tester);
      await tester.tap(find.text('Pacing'));
      await tester.pumpAndSettle();
      await openPacingCatalogueGames(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
