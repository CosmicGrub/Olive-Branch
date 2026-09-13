// OLIVE BRANCH — the real, reachable entry point for network play.
// MASTERFILE §5.14, §5.17, §5.19.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:olive_client/game_checkers.dart';
import 'package:olive_client/networked_checkers_lobby_screen.dart';

class _FakeSink implements WebSocketSink {
  final List<dynamic> sent = [];
  @override
  void add(dynamic data) => sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  Future<void> get done => Future<void>.value();
}

class _FakeWebSocketChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
  _FakeWebSocketChannel() : sink = _FakeSink();
  @override
  final WebSocketSink sink;
  final _incoming = StreamController<dynamic>.broadcast();
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  Future<void> get ready => Future.value();
}

Widget wrap(Widget child) => MaterialApp(home: child);

/// The form (server address, sign-in, partner fields, table code, start
/// button) runs taller than flutter_test's default 600px surface — see
/// game_checkers_test.dart's own `useTallSurface` for the same reasoning.
void useTallSurface(WidgetTester t) {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('sign in, open a table, and start playing navigates to a live GameCheckers',
      (t) async {
    useTallSurface(t);
    var loginCalls = 0, tableCalls = 0;
    final mock = MockClient((req) async {
      if (req.url.path == '/v1/auth/dev-login') {
        loginCalls++;
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(sent['userId'], 'dad-1');
        return http.Response(jsonEncode({'token': 'sess-tok'}), 200);
      }
      if (req.url.path == '/v1/game-tables') {
        tableCalls++;
        expect(req.headers['authorization'], 'Bearer sess-tok');
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(sent, {'game': 'checkers', 'partnerChildId': 'ivy-1'});
        return http.Response(jsonEncode({
          'tableId': 't_1', 'seat': 1, 'token': 'jointok', 'ttlSeconds': 180,
          'wsPath': '/v1/game-tables/t_1/socket',
        }), 200);
      }
      return http.Response('not found', 404);
    });

    final fakeWs = _FakeWebSocketChannel();
    await t.pumpWidget(wrap(NetworkedCheckersLobbyScreen(
      httpClientForTesting: mock,
      wsConnectForTesting: (_) => fakeWs,
    )));

    await t.enterText(find.byKey(const Key('lobbyUserId')), 'dad-1');
    await t.tap(find.byKey(const Key('lobbySignIn')));
    await t.pumpAndSettle();
    expect(loginCalls, 1);
    expect(find.text('Signed in'), findsOneWidget);

    await t.enterText(find.byKey(const Key('lobbyPartnerChildId')), 'ivy-1');
    await t.tap(find.byKey(const Key('lobbyOpenTable')));
    await t.pumpAndSettle();
    expect(tableCalls, 1);
    expect(find.textContaining('Table code to share: t_1'), findsOneWidget);
    expect(find.text('You are seat 1.'), findsOneWidget);

    await t.tap(find.byKey(const Key('lobbyStartPlaying')));
    await t.pumpAndSettle();

    expect(find.byType(GameCheckers), findsOneWidget);
    final checkers = t.widget<GameCheckers>(find.byType(GameCheckers));
    expect(checkers.network?.mySide, CkSide.parent, reason: 'seat 1 -> parent side');
  });

  testWidgets('a denied table-open (e.g. no sibling_link) surfaces the real reason, does not crash',
      (t) async {
    useTallSurface(t);
    final mock = MockClient((req) async {
      if (req.url.path == '/v1/auth/dev-login') {
        return http.Response(jsonEncode({'token': 'sess-tok'}), 200);
      }
      if (req.url.path == '/v1/game-tables') {
        return http.Response(jsonEncode({'error': 'no_sibling_link'}), 403);
      }
      return http.Response('not found', 404);
    });

    await t.pumpWidget(wrap(NetworkedCheckersLobbyScreen(httpClientForTesting: mock)));
    await t.tap(find.byKey(const Key('lobbyAsChild')));
    await t.pump();
    await t.enterText(find.byKey(const Key('lobbyChildId')), 'nora-1');
    await t.tap(find.byKey(const Key('lobbySignIn')));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('lobbyPartnerChildId')), 'ivy-1');
    await t.tap(find.byKey(const Key('lobbyOpenTable')));
    await t.pumpAndSettle();

    expect(find.textContaining('no_sibling_link'), findsOneWidget);
    expect(find.byKey(const Key('lobbyStartPlaying')), findsNothing);
  });

  testWidgets('joining an existing table by code works the same way', (t) async {
    useTallSurface(t);
    final mock = MockClient((req) async {
      if (req.url.path == '/v1/auth/dev-login') {
        return http.Response(jsonEncode({'token': 'sess-tok'}), 200);
      }
      if (req.url.path == '/v1/game-tables/t_shared/join') {
        return http.Response(jsonEncode({
          'tableId': 't_shared', 'seat': 0, 'token': 'jointok2', 'ttlSeconds': 180,
          'wsPath': '/v1/game-tables/t_shared/socket',
        }), 200);
      }
      return http.Response('not found', 404);
    });
    final fakeWs = _FakeWebSocketChannel();

    await t.pumpWidget(wrap(NetworkedCheckersLobbyScreen(
      httpClientForTesting: mock,
      wsConnectForTesting: (_) => fakeWs,
    )));
    await t.enterText(find.byKey(const Key('lobbyUserId')), 'dad-1');
    await t.tap(find.byKey(const Key('lobbySignIn')));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('lobbyJoinTableId')), 't_shared');
    await t.tap(find.byKey(const Key('lobbyJoin')));
    await t.pumpAndSettle();

    expect(find.text('You are seat 0.'), findsOneWidget);
    await t.tap(find.byKey(const Key('lobbyStartPlaying')));
    await t.pumpAndSettle();
    final checkers = t.widget<GameCheckers>(find.byType(GameCheckers));
    expect(checkers.network?.mySide, CkSide.child, reason: 'seat 0 -> child side');
  });
}
