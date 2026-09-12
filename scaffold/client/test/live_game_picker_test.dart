// OLIVE BRANCH — live_game_picker.dart tests. MASTERFILE §9.2.
// docs/superpowers/specs/2026-09-12-intuitivism-gamepicker-recommended-
// design.md. Mirrors theme_picker_screen_test.dart's own MockClient shape:
// no real network, real GET/PUT dispatch through OliveApi.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/game_logic.dart';
import 'package:olive_client/live_game_picker.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

http.Client mockFor({
  List<String> favoriteKinds = const [],
  int? ageAtLastOpen,
  bool failGet = false,
  bool failPut = false,
  List<Map<String, dynamic>?>? capturedPuts,
}) {
  return MockClient((req) async {
    if (req.url.path == '/v1/auth/dev-login') {
      return http.Response(jsonEncode({'token': 'tok'}), 200);
    }
    if (req.method == 'GET' && req.url.path.endsWith('/game-favorites')) {
      if (failGet) return http.Response(jsonEncode({'error': 'boom'}), 500);
      return http.Response(
          jsonEncode({'favoriteKinds': favoriteKinds, 'ageAtLastOpen': ageAtLastOpen}), 200);
    }
    if (req.method == 'PUT' && req.url.path.endsWith('/game-favorites')) {
      if (failPut) return http.Response(jsonEncode({'error': 'boom'}), 500);
      final decoded = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
      capturedPuts?.add(decoded.isEmpty ? null : decoded);
      return http.Response(jsonEncode({'ok': true, 'ageAtLastOpen': 9}), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('live_game_picker — child identity (sessionToken)', () {
    testWidgets('fetches real favoriteKinds/ageAtLastOpen and renders the Recommended row', (t) async {
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childName: 'Ivy', childAge: 8,
        sessionToken: 'child-tok',
        httpClient: mockFor(favoriteKinds: const ['story'], ageAtLastOpen: 5),
      )));
      await t.pumpAndSettle();
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Make up a story'), findsNWidgets(2));
    });

    testWidgets('never shows a star — child sessions never get onToggleFavorite', (t) async {
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        sessionToken: 'child-tok',
        httpClient: mockFor(favoriteKinds: const ['story']),
      )));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.star_border_rounded), findsNothing);
    });

    testWidgets('records her own visit in the background (no dev-login mint — her real token '
        'is used directly)', (t) async {
      final puts = <Map<String, dynamic>?>[];
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        sessionToken: 'child-tok',
        httpClient: mockFor(capturedPuts: puts),
      )));
      await t.pumpAndSettle();
      expect(puts.length, 1, reason: 'exactly one PUT — recording her own open, no favoriteKinds body');
      expect(puts.first, isNull, reason: 'recordGamePickerOpen sends no body at all');
    });

    testWidgets('the Surprise-me button is wired and navigates via onPlay', (t) async {
      GameKind? tapped;
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        sessionToken: 'child-tok',
        httpClient: mockFor(),
        onPlay: (context, kind) => tapped = kind,
      )));
      await t.pumpAndSettle();
      expect(find.text('Surprise me'), findsOneWidget);
      await t.tap(find.text('Surprise me'));
      await t.pump();
      expect(tapped, isNotNull);
    });

    testWidgets('a failed fetch is an honest empty state — no row, no crash', (t) async {
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        sessionToken: 'child-tok',
        httpClient: mockFor(failGet: true),
      )));
      await t.pumpAndSettle();
      expect(find.text('Recommended'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('live_game_picker — guardian identity (guardianId, mints its own dev login)', () {
    testWidgets('fetches real favoriteKinds and shows a real star state, no Surprise-me button', (t) async {
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        guardianId: 'dad-1',
        httpClient: mockFor(favoriteKinds: const ['story']),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('star_story')), findsWidgets);
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      expect(find.text('Surprise me'), findsNothing);
    });

    testWidgets('never records ageAtLastOpen — a guardian browsing on her behalf is not her visit', (t) async {
      final puts = <Map<String, dynamic>?>[];
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        guardianId: 'dad-1',
        httpClient: mockFor(capturedPuts: puts),
      )));
      await t.pumpAndSettle();
      expect(puts, isEmpty, reason: 'no PUT at all until a guardian actually taps a star');
    });

    testWidgets('tapping a star optimistically updates, then PUTs the full new favourite list', (t) async {
      final puts = <Map<String, dynamic>?>[];
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        guardianId: 'dad-1',
        httpClient: mockFor(capturedPuts: puts),
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('star_tictactoe')));
      await t.pump();
      // Optimistic: the star already renders filled before any network
      // round trip settles (this same pump, before pumpAndSettle).
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      await t.pumpAndSettle();
      expect(puts.length, 1);
      expect(puts.first!['favoriteKinds'], ['tictactoe']);
    });

    testWidgets('a failed write reverts the optimistic toggle and gives honest feedback', (t) async {
      await t.pumpWidget(wrap(LiveGamePickerScreen(
        baseUrl: 'http://api.test', childId: 'child-1', childAge: 8,
        guardianId: 'dad-1',
        httpClient: mockFor(failPut: true),
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('star_tictactoe')));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.star_rounded), findsNothing,
          reason: 'reverted — the failed write never really happened');
      expect(find.textContaining("Couldn't save"), findsOneWidget);
    });
  });
}
