// OLIVE BRANCH — parental_controls_screen.dart tests, and a direct unit
// proof of activity_overrides.dart's precedence rule. docs/superpowers/
// specs/2026-09-13-parental-controls-pacing-design.md.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/activity_overrides.dart';
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
    // default so these are reachable without an extra tap.
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
    // Games is initiallyExpanded on the Pacing tab.
    expect(find.byKey(const Key('pacing_game:tictactoe')), findsOneWidget);
    expect(find.byKey(const Key('pacingMinus_game:tictactoe')), findsOneWidget);
    expect(find.byKey(const Key('pacingPlus_game:tictactoe')), findsOneWidget);
    expect(find.byKey(const Key('pacingReveal_game:tictactoe')), findsOneWidget);
    // No ChildHome tile ever appears on the Pacing tab — tiles have no age
    // concept (visibility-only).
    expect(find.byKey(const Key('pacing_tile:messages')), findsNothing);
  });

  testWidgets('the + stepper raises the effective minAge and persists minAgeOverride',
      (tester) async {
    final calledBodies = <String>[];
    await pump(tester, client: stubClient(calledBodies: calledBodies));
    await verifyPin(tester);
    await tester.tap(find.text('Pacing'));
    await tester.pumpAndSettle();

    final before = tester.widget<Text>(find.byKey(const Key('pacingAge_game:tictactoe'))).data;
    // chess sits well down a 20-game list — off the default 800x600 test
    // viewport until scrolled into view.
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
}
