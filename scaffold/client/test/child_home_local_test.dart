// OLIVE BRANCH — the home of a tablet a grown-up approved on the same network. That tablet has NO server account
// and NO session, so her home is drawn from what the pairing delivered and what the device remembers, and it
// never asks a server. Hostile cases: no network at all, no session, nothing delivered, and the connected path
// staying exactly as it was. She never sees a cloud picture, a retry button or any error sentence on this path.
// UNVERIFIED on a real device (see docs/planning/ANDROID-ROADMAP.md); these tests run headless.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/push_channel.dart';
import 'package:olive_client/wear_sync_channel.dart';

class _NoPush extends PushChannel {
  _NoPush() : super(OliveApi('http://unused', 'unused'));
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}

class _NoWear extends WearSyncChannel {
  @override
  Future<void> syncSleepsUntilHandover(int sleepsUntilHandover) async {}
  @override
  void listenForCallDad(void Function() onCallDadRequested) {}
}

/// A network that records every request and refuses all of them: any call is a failure of the local path.
class _Tripwire {
  final List<String> requests = <String>[];
  late final MockClient client = MockClient((http.Request r) async {
    requests.add('${r.method} ${r.url.path}');
    throw http.ClientException('no route to host');
  });
}

Widget _local(_Tripwire net, {String? name = 'Ivy', int? age = 8, String id = 'kid-1'}) => MaterialApp(
    home: LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: id, httpClient: net.client, wearSync: _NoWear(), pushChannel: _NoPush(),
        localOnly: true, localName: name, localAge: age));

final Finder _ivyGreeting = find.byWidgetPredicate((Widget w) =>
    w is Text && RegExp(r'^(Hi|Hey) Ivy$|^Hi, Ivy$|^Good (morning|afternoon|evening), Ivy$').hasMatch(w.data ?? ''));

/// Every word on screen, so "no error text" is checked against all of it, in any state.
String _allText(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? w.textSpan?.toPlainText() ?? '').join(' | ').toLowerCase();

void _noChildErrorAnywhere(WidgetTester t) {
  expect(find.byKey(const Key('childOfflineIcon')), findsNothing, reason: 'no crossed-out cloud');
  expect(find.byKey(const Key('childOfflineRetry')), findsNothing, reason: 'no retry button');
  expect(find.byIcon(Icons.cloud_off), findsNothing);
  expect(find.byIcon(Icons.refresh), findsNothing);
  final String text = _allText(t);
  for (final String bad in <String>[
    '401', 'not_signed_in', 'apiexception', 'exception', 'error', 'failed', 'wrong', "couldn't", 'could not', 'try again', 'offline', 'server', 'sign in', 'signed in',
  ]) {
    expect(text.contains(bad), isFalse, reason: 'child-visible text must not contain "$bad": $text');
  }
}

void main() {
  setUp(() {
    LocalServices.install(LocalServices.memory(childId: 'kid-1', isLive: true, demoSeeds: false));
  });

  testWidgets('no network, no session: her home opens from what the pairing delivered, and asks nobody', (t) async {
    final _Tripwire net = _Tripwire();
    await t.pumpWidget(_local(net));
    await t.pumpAndSettle();
    expect(_ivyGreeting, findsOneWidget, reason: 'her name, from the pairing');
    expect(net.requests, isEmpty, reason: 'a locally paired tablet never calls a server: ${net.requests}');
    _noChildErrorAnywhere(t);
  });

  testWidgets('what the pairing delivered is kept on the device, so the next start needs nothing', (t) async {
    final _Tripwire net = _Tripwire();
    await t.pumpWidget(_local(net, age: 6));
    await t.pumpAndSettle();
    final ProfileCache c = (await ProfileCacheRepository(LocalServices.current.area('profile', ownerId: 'kid-1')).load())!;
    expect(c.displayName, 'Ivy');
    expect(c.yearsOld, 6);

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_local(net, name: null, age: null)); // a later start with nothing passed in
    await t.pumpAndSettle();
    expect(_ivyGreeting, findsOneWidget, reason: 'her name, from the device');
    expect(net.requests, isEmpty);
    _noChildErrorAnywhere(t);
  });

  testWidgets('an old pairing that delivered no name or age still opens a calm home, never an error picture', (t) async {
    final _Tripwire net = _Tripwire();
    await t.pumpWidget(_local(net, name: null, age: null));
    await t.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
    expect(net.requests, isEmpty);
    _noChildErrorAnywhere(t);
    // The stand-in name and the fail-closed age are not written down as if they were hers.
    final ProfileCache? c = await ProfileCacheRepository(LocalServices.current.area('profile', ownerId: 'kid-1')).load();
    expect(c?.displayName, isNull);
    expect(c?.yearsOld, isNull);
  });

  testWidgets('a grown-up\'s locked age on the device wins over the age the pairing delivered', (t) async {
    final ProfileCacheRepository repo = ProfileCacheRepository(LocalServices.current.area('profile', ownerId: 'kid-1'));
    await repo.rememberHome(displayName: 'Ivy', yearsOld: 4);
    await repo.lockAge(4);
    final _Tripwire net = _Tripwire();
    await t.pumpWidget(_local(net, age: 12));
    await t.pumpAndSettle();
    final ProfileCache c = (await repo.load())!;
    expect(c.yearsOld, 4);
    expect(c.ageLocked, isTrue);
    expect(net.requests, isEmpty);
  });

  testWidgets('the same home for a long time on a dead network: no state ever shows an error', (t) async {
    final _Tripwire net = _Tripwire();
    await t.pumpWidget(_local(net));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 20));
      _noChildErrorAnywhere(t);
    }
    expect(net.requests, isEmpty);
  });

  testWidgets('a device with a server session behaves as before: it asks the server and shows the cloud picture offline', (t) async {
    final _Tripwire net = _Tripwire();
    await t.pumpWidget(MaterialApp(
        home: LiveChildHomeScreen(
            baseUrl: 'http://api.test', childId: 'kid-1', httpClient: net.client, wearSync: _NoWear(), pushChannel: _NoPush())));
    await t.pumpAndSettle();
    expect(net.requests, isNotEmpty, reason: 'the connected path still asks the server');
    expect(find.byKey(const Key('childOfflineIcon')), findsOneWidget);

    // And with a server that answers, the connected home is the same as it always was.
    final MockClient up = MockClient((http.Request r) async {
      final String p = r.url.path;
      if (p == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
      if (p == '/v1/me') return http.Response(jsonEncode(<String, Object?>{'displayName': 'Ivy', 'yearsOld': 8}), 200);
      if (p.endsWith('/inbox')) return http.Response(jsonEncode(<String, Object?>{'entries': <Object?>[]}), 200);
      if (p.endsWith('/now')) return http.Response(jsonEncode(<String, Object?>{'dayParts': <Object?>[]}), 200);
      if (p.endsWith('/presence')) return http.Response(jsonEncode(<String, Object?>{'free': null}), 200);
      if (p.endsWith('/activity-overrides')) return http.Response(jsonEncode(<String, Object?>{'overrides': <Object?>[]}), 200);
      return http.Response('not found', 404);
    });
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(
        home: LiveChildHomeScreen(
            baseUrl: 'http://api.test', childId: 'kid-1', httpClient: up, wearSync: _NoWear(), pushChannel: _NoPush())));
    await t.pumpAndSettle();
    expect(_ivyGreeting, findsOneWidget);
    expect(find.byKey(const Key('childOfflineIcon')), findsNothing);
  });
}
