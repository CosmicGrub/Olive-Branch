// OLIVE BRANCH - everything around the direct ('lan-p2p') call that is not the engine itself (that is
// lan_call_engine_test.dart): the grant and availability parsing and the plain wording, the real signalling channel
// over a fake server, the foreground ring poller, the child's call start and its calm failures, the call screen's
// behaviour with a direct grant (cancel, never-connected endings for a grown-up and for a child, the notice), the
// registry and the provider switch, and the child-safety guard over every line a child can be shown.
// MASTERFILE 5.19, 5.25.2, 7.20, 16.2 #6.
import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/call_lifecycle.dart';
import 'package:olive_client/call_poller.dart';
import 'package:olive_client/call_provider.dart';
import 'package:olive_client/call_provider_registry.dart';
import 'package:olive_client/call_screen.dart';
import 'package:olive_client/call_signaling.dart';
import 'package:olive_client/child_call_start.dart';
import 'package:olive_client/lan_p2p_call_provider.dart';

Map<String, dynamic> _grantJson({Object? ice, Object? policy, String role = 'caller'}) => <String, dynamic>{
      'provider': 'lan-p2p', 'sessionId': 'a1a1a1a1-1234-4234-8234-aaaaaaaaaaa1', 'role': role,
      'displayName': 'Dad', 'iceServers': ice ?? <Object>[], 'iceTransportPolicy': policy ?? 'all',
    };

OliveApi _api(http.Client c) => OliveApi('http://127.0.0.1:8123', 'tok', client: c);

void main() {
  group('the grant', () {
    test('a lan-p2p grant parses: no token, no address, the ICE list and the policy', () {
      final g = CallGrant.fromJson(_grantJson(
        ice: <Object>[
          <String, dynamic>{'urls': <String>['stun:192.0.2.1:3478']},
          <String, dynamic>{'urls': <String>['turn:192.0.2.1:3478'], 'username': 'u', 'credential': 'c'},
        ],
        policy: 'relay'));
      expect(g.kind, CallProviderKind.lanP2p);
      expect(g.isCaller, true);
      expect(g.token, isNull);
      expect(g.serverURL, isNull);
      expect(g.relayOnly, true);
      expect(g.iceServers.length, 2);
      expect(g.iceServers[1]['username'], 'u');
    });

    test('the default grant (the home Wi-Fi) has an empty list and is not relay-only', () {
      final g = CallGrant.fromJson(_grantJson(role: 'callee'));
      expect(g.iceServers, isEmpty);
      expect(g.relayOnly, false);
      expect(g.isCaller, false);
    });

    test('a half-formed grant is refused before it can reach an engine', () {
      for (final bad in <Map<String, dynamic>>[
        <String, dynamic>{..._grantJson()}..remove('sessionId'),
        <String, dynamic>{..._grantJson(), 'role': 'admin'},
        <String, dynamic>{..._grantJson()}..remove('role'),
        <String, dynamic>{..._grantJson(), 'iceServers': 'nope'},
        <String, dynamic>{..._grantJson(), 'iceServers': <Object>[7]},
        <String, dynamic>{..._grantJson(), 'iceServers': <Object>[<String, dynamic>{'urls': <Object>[]}]},
        <String, dynamic>{..._grantJson(), 'iceServers': <Object>[<String, dynamic>{'urls': <Object>[3]}]},
        <String, dynamic>{..._grantJson(), 'provider': 'zoom'},
      ]) {
        expect(() => CallGrant.fromJson(bad), throwsFormatException, reason: '$bad');
      }
    });
  });

  group('availability and the grown-up\'s words', () {
    test('the server\'s lan-p2p answer parses, with the tablet flag only when it is a real boolean', () {
      final a = CallAvailability.tryParse(<String, dynamic>{
        'provider': 'lan-p2p', 'available': true, 'sameNetworkOnly': true, 'tabletReachable': false})!;
      expect(a.provider, CallProviderKind.lanP2p);
      expect(a.tabletReachable, false);
      for (final junk in <Object?>['false', 0, 1, null]) {
        expect(CallAvailability.tryParse(<String, dynamic>{'provider': 'lan-p2p', 'available': true, 'tabletReachable': junk})!.tabletReachable, isNull);
      }
      expect(CallAvailability.tryParse(<String, dynamic>{'provider': 'lan-p2p', 'available': false, 'tabletReachable': true})!.tabletReachable, isNull);
    });

    test('calls off and her tablet unreachable read as two different plain sentences, each with one next step', () {
      final off = availabilityLine(const CallAvailability(provider: CallProviderKind.lanP2p, available: false, sameNetworkOnly: false))!;
      final away = availabilityLine(const CallAvailability(
          provider: CallProviderKind.lanP2p, available: true, sameNetworkOnly: true, tabletReachable: false))!;
      expect(off, startsWith('Calls are not switched on here.'));
      expect(off, contains('calls-up-dev'));
      expect(away, startsWith("Her tablet can't be reached right now."));
      expect(away, contains('same Wi-Fi'));
      expect(off, isNot(equals(away)));
      expect(availabilityLine(const CallAvailability(
          provider: CallProviderKind.lanP2p, available: true, sameNetworkOnly: true, tabletReachable: true)), contains('home Wi-Fi'));
    });

    test('the ring word "tablet_unreachable" maps, and reads the same plain sentence', () {
      expect(ringStateOf('tablet_unreachable'), CallRingState.tabletUnreachable);
      expect(ringStateLine(CallRingState.tabletUnreachable), tabletUnreachableLine);
    });

    test('no line a CHILD can be shown, for any reason, has a banned word, a digit, an address or a code', () {
      for (final r in CallUnavailableReason.values) {
        final line = callUnavailableLine(r, isGuardian: false);
        for (final w in callBannedWords) {
          expect(line.toLowerCase().contains(w), false, reason: '"$line" has "$w"');
        }
        expect(RegExp(r'\d').hasMatch(line), false, reason: line);
      }
      for (final line in <String>[childCallRestingLine, childCallLaterLine]) {
        for (final w in callBannedWords) {
          expect(line.toLowerCase().contains(w), false, reason: '"$line" has "$w"');
        }
      }
    });

    test('a child call that cannot start is one of two soft lines: quiet time, or "try again in a little while"', () {
      expect(childCallFailureLine(ApiException(409, 'quiet_hours')), childCallRestingLine);
      expect(childCallFailureLine(ApiException(503, 'call_provider_unavailable')), childCallLaterLine);
      expect(childCallFailureLine(ApiException(403, 'no_approved_grownup')), childCallLaterLine);
      expect(childCallFailureLine(StateError('socket 192.168.1.5 refused')), childCallLaterLine);
    });
  });

  group('the real signalling channel, over a fake server', () {
    test('long-polls, delivers each message once and in order, and sends with the right body', () async {
      var polls = 0;
      final posted = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          posted.add(jsonDecode(req.body) as Map<String, dynamic>);
          expect(req.url.path, '/v1/children/c1/calls/s1/signal');
          return http.Response(jsonEncode(<String, dynamic>{'seq': 1}), 200);
        }
        polls++;
        expect(req.url.queryParameters['wait'], '8');
        if (polls == 1) {
          expect(req.url.queryParameters['after'], '0');
          return http.Response(jsonEncode(<String, dynamic>{'signals': <Object>[
            <String, dynamic>{'seq': 1, 'from': 'caller', 'kind': 'offer', 'payload': <String, dynamic>{'description': <String, dynamic>{'type': 'offer', 'sdp': 'x'}}},
            <String, dynamic>{'seq': 2, 'from': 'caller', 'kind': 'ice', 'payload': <String, dynamic>{'candidates': <Object>[]}},
          ], 'closed': false}), 200);
        }
        expect(req.url.queryParameters['after'], '2', reason: 'the next poll asks only for newer messages');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(jsonEncode(<String, dynamic>{'signals': <Object>[], 'closed': true}), 200);
      });
      final s = ServerCallSignaling(apiProvider: () async => _api(client), childId: 'c1', sessionId: 's1');
      final got = <String>[];
      s.signals.listen((x) => got.add('${x.seq}:${x.kind}'));
      await s.send('answer', <String, dynamic>{'description': <String, dynamic>{'type': 'answer', 'sdp': 'y'}});
      expect(await s.ended.timeout(const Duration(seconds: 2)), CallSignalingEnd.closed);
      expect(got, ['1:offer', '2:ice']);
      expect(posted.single['kind'], 'answer');
      expect((posted.single['payload'] as Map).containsKey('description'), true);
      await s.close();
    });

    test('a 404 (the call is over) or a 403 (not ours) ends the channel, quietly', () async {
      for (final status in <int>[404, 403, 401]) {
        final s = ServerCallSignaling(
          apiProvider: () async => _api(MockClient((_) async => http.Response(jsonEncode(<String, dynamic>{'error': 'x'}), status))),
          childId: 'c1', sessionId: 's1');
        expect(await s.ended.timeout(const Duration(seconds: 2)), CallSignalingEnd.closed, reason: '$status');
        await s.close();
      }
    });

    test('a network that goes away and comes back (Wi-Fi to cellular) does not end the call', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        if (n <= 3) throw http.ClientException('network is gone');
        if (n == 4) {
          return http.Response(jsonEncode(<String, dynamic>{'signals': <Object>[
            <String, dynamic>{'seq': 1, 'from': 'caller', 'kind': 'mode', 'payload': <String, dynamic>{'mode': 'video'}}], 'closed': false}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{'signals': <Object>[], 'closed': true}), 200);
      });
      final s = ServerCallSignaling(apiProvider: () async => _api(client), childId: 'c1', sessionId: 's1',
          retryEvery: const Duration(milliseconds: 5), lostAfter: const Duration(seconds: 5));
      final got = <String>[];
      s.signals.listen((x) => got.add(x.kind));
      expect(await s.ended.timeout(const Duration(seconds: 3)), CallSignalingEnd.closed);
      expect(got, ['mode'], reason: 'the message that arrived after the outage still came through');
      await s.close();
    });

    test('a server that stays out of reach for too long is reported lost, not hung', () async {
      final s = ServerCallSignaling(
        apiProvider: () async => _api(MockClient((_) async => throw http.ClientException('down'))),
        childId: 'c1', sessionId: 's1', retryEvery: const Duration(milliseconds: 5), lostAfter: const Duration(milliseconds: 60));
      expect(await s.ended.timeout(const Duration(seconds: 2)), CallSignalingEnd.lost);
      await s.close();
    });

    test('a send is retried on a server error, never on a refusal, and never throws', () async {
      var posts = 0;
      final s500 = ServerCallSignaling(
        apiProvider: () async => _api(MockClient((req) async {
          if (req.method == 'POST') { posts++; return http.Response('{"error":"boom"}', 500); }
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return http.Response('{"signals":[],"closed":false}', 200);
        })),
        childId: 'c1', sessionId: 's1');
      await s500.send('ice', <String, dynamic>{'candidates': <Object>[]});
      expect(posts, 3);
      await s500.close();

      var refused = 0;
      final s403 = ServerCallSignaling(
        apiProvider: () async => _api(MockClient((req) async {
          if (req.method == 'POST') { refused++; return http.Response('{"error":"not_a_participant"}', 403); }
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return http.Response('{"signals":[],"closed":false}', 200);
        })),
        childId: 'c1', sessionId: 's1');
      await s403.send('ice', <String, dynamic>{'candidates': <Object>[]});
      expect(refused, 1);
      await s403.close();
    });

    test('hostile messages from the server are skipped, never trusted', () async {
      var n = 0;
      final client = MockClient((req) async {
        n++;
        if (n == 1) {
          return http.Response(jsonEncode(<String, dynamic>{'signals': <Object>[
            7, <String, dynamic>{'seq': 'x', 'kind': 'offer', 'payload': <String, dynamic>{}},
            <String, dynamic>{'seq': 1, 'kind': 5, 'payload': <String, dynamic>{}},
            <String, dynamic>{'seq': 2, 'kind': 'ice', 'payload': 'str'},
            <String, dynamic>{'seq': 3, 'kind': 'mode', 'payload': <String, dynamic>{'mode': 'video'}}], 'closed': false}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{'signals': <Object>[], 'closed': true}), 200);
      });
      final s = ServerCallSignaling(apiProvider: () async => _api(client), childId: 'c1', sessionId: 's1');
      final got = <int>[];
      s.signals.listen((x) => got.add(x.seq));
      await s.ended.timeout(const Duration(seconds: 2));
      expect(got, [3]);
      await s.close();
    });
  });

  group('the foreground ring poller', () {
    test('parses defensively: wrong shapes are skipped, a blank name is null', () {
      expect(parsePendingCalls(null), isEmpty);
      expect(parsePendingCalls('x'), isEmpty);
      expect(parsePendingCalls(<String, dynamic>{'calls': 'x'}), isEmpty);
      final c = parsePendingCalls(<String, dynamic>{'calls': <Object>[
        1, <String, dynamic>{'sessionId': 5}, <String, dynamic>{'sessionId': 'a', 'from': '  '},
        <String, dynamic>{'sessionId': 'b', 'from': ' Dad '}]});
      expect(c.map((x) => '${x.sessionId}/${x.from}').toList(), ['a/null', 'b/Dad']);
    });

    test('polls on a timer, hands each call over, never overlaps itself, and a failed poll is silent', () async {
      var calls = 0;
      var inFlight = 0, maxInFlight = 0;
      final seen = <String>[];
      final p = PendingCallPoller(
        every: const Duration(milliseconds: 10),
        fetch: () async {
          calls++;
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 25));
          inFlight--;
          if (calls == 2) throw http.ClientException('radio asleep');
          return <String, dynamic>{'calls': <Object>[<String, dynamic>{'sessionId': 's$calls', 'from': 'Dad'}]};
        },
        onCall: (c) => seen.add(c.sessionId),
      )..start();
      await Future<void>.delayed(const Duration(milliseconds: 160));
      p.stop();
      final after = calls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(maxInFlight, 1, reason: 'one poll at a time');
      expect(seen, isNot(contains('s2')), reason: 'the failed poll handed nothing over and said nothing');
      expect(seen, contains('s1'));
      expect(calls, after, reason: 'stopped means stopped');
    });

    test('a stopped poller never hands a call over, even from a poll already in flight', () async {
      final seen = <String>[];
      late PendingCallPoller p;
      p = PendingCallPoller(
        every: const Duration(seconds: 1),
        fetch: () async {
          p.stop();
          return <String, dynamic>{'calls': <Object>[<String, dynamic>{'sessionId': 'late'}]};
        },
        onCall: (c) => seen.add(c.sessionId),
      )..start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen, isEmpty);
    });
  });

  group('the child starts a call', () {
    Future<void> pumpStart(WidgetTester t, http.Client client, {void Function(Route<dynamic>)? onPush, FakeCallProvider? fake}) async {
      await t.pumpWidget(MaterialApp(
        navigatorObservers: <NavigatorObserver>[_Obs(onPush ?? (_) {})],
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: ElevatedButton(
          key: const Key('go'),
          onPressed: () => startChildCall(ctx, apiProvider: () async => _api(client), childId: 'c1', childName: 'Ivy',
              providerFactory: fake == null ? null : (_) => fake),
          child: const Text('go')))))));
      await t.tap(find.byKey(const Key('go')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('server says quiet hours: one soft line, no error, no code, and she stays where she was', (t) async {
      final pushed = <Route<dynamic>>[];
      await pumpStart(t, MockClient((_) async => http.Response(jsonEncode(<String, dynamic>{'error': 'quiet_hours'}), 409)), onPush: pushed.add);
      expect(find.text(childCallRestingLine), findsOneWidget);
      expect(find.textContaining('quiet_hours'), findsNothing);
      expect(find.textContaining('409'), findsNothing);
      expect(pushed.length, 1, reason: 'only the first route; no call screen opened');
    });

    testWidgets('calls off, no approved grown-up, or no network: the same one soft line', (t) async {
      for (final c in <http.Client>[
        MockClient((_) async => http.Response(jsonEncode(<String, dynamic>{'error': 'call_provider_unavailable'}), 503)),
        MockClient((_) async => http.Response(jsonEncode(<String, dynamic>{'error': 'no_approved_grownup'}), 403)),
        MockClient((_) async => throw http.ClientException('no route to 192.168.1.5')),
      ]) {
        await pumpStart(t, c);
        expect(find.text(childCallLaterLine), findsOneWidget);
        expect(find.textContaining('192.168'), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
      }
    });

    testWidgets('success opens the call screen on the direct grant, naming the grown-up she is calling', (t) async {
      final pushed = <Route<dynamic>>[];
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/v1/children/c1/calls') {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(<String, dynamic>{..._grantJson(), 'toName': 'Dad'}), 201);
        }
        return http.Response('{"signals":[],"closed":false}', 200);
      });
      final fake = FakeCallProvider(kind: CallProviderKind.lanP2p, connectOnJoin: false);
      await pumpStart(t, client, onPush: pushed.add, fake: fake);
      expect(bodies.single.containsKey('toUserId'), false, reason: 'she names nobody; the server picks an approved grown-up');
      expect(pushed.length, 2);
      expect((fake.joinedWith!).kind, CallProviderKind.lanP2p);
      expect(fake.joinedWith!.isCaller, true);
      expect(find.text('Calling Dad…'), findsOneWidget, reason: 'she sees the grown-up name, nothing else');
      await t.pumpWidget(const SizedBox()); // tear the call screen down before the test ends
      await t.pump(const Duration(milliseconds: 200));
    });
  });

  group('the call screen with a direct grant', () {
    final grant = CallGrant.fromJson(_grantJson());

    Future<FakeCallProvider> pump(WidgetTester t, FakeCallProvider fake, {
      String who = 'dad', Future<void> Function()? onCallEnd, String? remoteLabel, CallGrant? g,
    }) async {
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
        key: const Key('open'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CallScreen(
          who: who, displayName: 'Dad', remoteLabel: remoteLabel, knownGrant: g ?? grant, onCallEnd: onCallEnd,
          providerFactory: (_) => fake))),
        child: const Text('open')))))));
      await t.tap(find.byKey(const Key('open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      return fake;
    }

    testWidgets('the caller sees "Calling <her name>" and a way to stop; stopping ends the log row once as cancelled', (t) async {
      var ended = 0;
      final fake = FakeCallProvider(kind: CallProviderKind.lanP2p, connectOnJoin: false);
      await pump(t, fake, remoteLabel: 'Ivy', onCallEnd: () async => ended++);
      expect(find.text('Calling Ivy…'), findsOneWidget);
      expect(find.byKey(const Key('callCancelButton')), findsOneWidget);
      await t.tap(find.byKey(const Key('callCancelButton')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(fake.calls, contains('leave'));
      expect(ended, 1, reason: 'the end is recorded exactly once, even though the screen is then disposed');
      expect(find.byKey(const Key('open')), findsOneWidget, reason: 'back where she started');
    });

    testWidgets('the callee sees "Joining" (she is answering), not "Calling"', (t) async {
      final fake = FakeCallProvider(kind: CallProviderKind.lanP2p, connectOnJoin: false);
      await pump(t, fake, who: 'ivy', remoteLabel: 'Dad', g: CallGrant.fromJson(_grantJson(role: 'callee')));
      expect(find.text('Joining Dad…'), findsOneWidget);
    });

    testWidgets('connected: the call is on, the all-party notice is shown, and hanging up records the end once', (t) async {
      var ended = 0;
      final fake = FakeCallProvider(kind: CallProviderKind.lanP2p);
      await pump(t, fake, onCallEnd: () async => ended++);
      expect(find.byKey(const Key('callNotRecordedNotice')), findsOneWidget);
      expect(find.text('This call is not recorded.'), findsOneWidget);
      await t.tap(find.byTooltip('Hang up'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(ended, 1);
    });

    testWidgets('a grown-up whose call never connected sees the plain line and a way to try again', (t) async {
      final fake = FakeCallProvider(kind: CallProviderKind.lanP2p, connectOnJoin: false);
      await pump(t, fake, who: 'dad');
      fake.emit(fake.state.copyWith(phase: CallPhase.ended));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text(callUnavailableLine(CallUnavailableReason.unreachable, isGuardian: true)), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a CHILD whose call never connected (nobody came, or they hung up first) is simply taken back: no screen, no words', (t) async {
      var ended = 0;
      final fake = FakeCallProvider(kind: CallProviderKind.lanP2p, connectOnJoin: false);
      await pump(t, fake, who: 'ivy', onCallEnd: () async => ended++, g: CallGrant.fromJson(_grantJson(role: 'callee')));
      fake.emit(fake.state.copyWith(phase: CallPhase.ended));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('open')), findsOneWidget, reason: 'back to where she was');
      expect(find.textContaining('Try again'), findsNothing);
      expect(find.textContaining('ready'), findsNothing);
      expect(ended, 1);
    });

    testWidgets('the existing engines keep their rule: a call that never connected is NOT recorded as ended', (t) async {
      var ended = 0;
      final fake = FakeCallProvider(connectOnJoin: false);
      await pump(t, fake, g: const CallGrant.livekit(token: 't', wsURL: 'wss://x.invalid', displayName: 'Dad'), onCallEnd: () async => ended++);
      fake.emit(fake.state.copyWith(phase: CallPhase.ended));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(const SizedBox());
      expect(ended, 0);
    });
  });

  group('the registry and the provider switch', () {
    test('a direct grant without a signalling channel is refused calmly, never a half-started call', () {
      expect(() => defaultCallProviderFor(CallGrant.fromJson(_grantJson())),
          throwsA(isA<CallUnavailableException>().having((e) => e.reason, 'reason', CallUnavailableReason.refused)));
    });

    test('with a channel it builds the direct engine, and the other grants still build theirs', () async {
      final (a, _) = MemoryCallSignaling.pair();
      final p = defaultCallProviderFor(CallGrant.fromJson(_grantJson()), signaling: a);
      expect(p, isA<LanP2pCallProvider>());
      expect(p.kind, CallProviderKind.lanP2p);
      expect(p.rendersOwnScreen, false);
      await p.dispose();
      expect(defaultCallProviderFor(const CallGrant.livekit(token: 't', wsURL: 'wss://x.invalid')).kind, CallProviderKind.livekit);
    });

    test('the direct provider refuses another engine\'s grant', () async {
      final (a, _) = MemoryCallSignaling.pair();
      final p = LanP2pCallProvider(signaling: a);
      await expectLater(p.join(const CallGrant.livekit(token: 't', wsURL: 'wss://x.invalid'),
          const CallJoinOptions(displayName: 'x', isGuardian: true)), throwsA(isA<CallUnavailableException>()));
      await p.dispose();
    });

    test('the engine is chosen by the server\'s grant: the wire names map one to one', () {
      expect(CallGrant.fromJson(_grantJson()).kind, CallProviderKind.lanP2p);
      expect(CallGrant.fromJson(<String, dynamic>{'provider': 'livekit', 'token': 't', 'wsURL': 'wss://x'}).kind, CallProviderKind.livekit);
      expect(CallGrant.fromJson(<String, dynamic>{'provider': 'jitsi', 'jwt': 'a.b.c', 'room': 'r', 'serverURL': 'https://x'}).kind, CallProviderKind.jitsi);
    });
  });

  group('child safety, a11y and source guards', () {
    test('the call UI files import no media engine (the engine files are the only ones that do)', () {
      for (final f in <String>['call_screen.dart', 'call_knock_screen.dart', 'child_call_start.dart', 'call_poller.dart', 'call_signaling.dart', 'lan_call_engine.dart']) {
        final src = File('lib/$f').readAsStringSync();
        expect(src.contains("package:flutter_webrtc"), false, reason: f);
        expect(src.contains("package:livekit_client"), false, reason: f);
        expect(src.contains("package:jitsi_meet_flutter_sdk"), false, reason: f);
      }
    });

    test('the child\'s call start shows no PIN, no count, no code and names no reason in any literal', () {
      final src = File('lib/child_call_start.dart').readAsStringSync();
      final shown = RegExp(r"Text\(([^)]*)\)|const String child\w+ =\s*([^;]*);").allMatches(src).map((m) => m.group(0)!).join(' ');
      for (final w in <String>['PIN', 'pin ', 'error', 'Error', 'failed', 'count', 'missed', 'declined']) {
        expect(shown.contains(w), false, reason: 'child_call_start.dart shows "$w"');
      }
    });

    test('the knock keeps its calm words: the three real answers, none of them a decline', () {
      final src = File('lib/call_knock.dart').readAsStringSync();
      expect(src.contains("'Not now'"), true);
      expect(src.contains("'Answer', 'Just talking', 'Not now'"), true);
    });

    test('the dev-only seams are not in a normal build: nothing outside the allow-list names a simulate define', () {
      for (final f in Directory('lib').listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        if (name == 'call_dev_sim.dart') continue;
        expect(f.readAsStringSync().contains('OLIVE_DEV_CALL_SIM'), false, reason: name);
      }
    });
  });
}

class _Obs extends NavigatorObserver {
  _Obs(this.onPushed);
  final void Function(Route<dynamic>) onPushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onPushed(route);
}
