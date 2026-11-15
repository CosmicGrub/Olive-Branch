// OLIVE BRANCH — push and calls wired into the child's connected home. MASTERFILE §11, §5.25.2, §7.18.
//
// The whole chain, with the real PushService, PushChannel, dispatcher, controller and knock screen and only Google
// and the phone's native side faked: a connected child device registers its token; a ring knocks; a hang-up
// takes the knock away; "something new" makes the home look again; and in every case she sees nothing that
// reads as a problem. Also: a build with no Firebase settings, and a locally paired tablet, do none of it.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/call_presence.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/incoming_call_channel.dart';
import 'package:olive_client/push_channel.dart';
import 'package:olive_client/push_config.dart';
import 'package:olive_client/push_service.dart';

const _session = '3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50';

FcmConfig _config() => FcmConfig.tryParse(
      projectId: 'olive-test-project',
      appId: '1:123456789012:android:0123456789abcdef',
      apiKey: 'test-only-key-not-real-0123456789',
      senderId: '123456789012',
    )!;

class _World {
  _World(this.t) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(phone, (MethodCall c) async {
      phoneCalls.add(c.method);
      return null;
    });
  }
  final WidgetTester t;
  final MethodChannel phone = const MethodChannel('test/wiring_phone');
  final List<String> phoneCalls = <String>[];
  final List<String> requests = <String>[];
  final StreamController<RemoteMessage> messages = StreamController<RemoteMessage>.broadcast();
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  int unread = 0;

  late final MockClient server = MockClient((http.Request req) async {
    requests.add('${req.method} ${req.url.path}');
    final p = req.url.path;
    if (p == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
    if (p == '/v1/me') return http.Response(jsonEncode(<String, Object?>{'displayName': 'Ivy'}), 200);
    if (p.endsWith('/inbox')) {
      return http.Response(jsonEncode(<String, Object?>{
        'entries': <Map<String, Object?>>[for (var i = 0; i < unread; i++) <String, Object?>{'id': '$i', 'state': 'delivered'}],
      }), 200);
    }
    if (p.endsWith('/now')) {
      return http.Response(jsonEncode(<String, Object?>{
        'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York', 'sleepsUntilHandover': null,
      }), 200);
    }
    if (p == '/v1/me/device-tokens') return http.Response(jsonEncode(<String, Object?>{'id': 'row-1'}), 200);
    if (p.endsWith('/join')) return http.Response(jsonEncode(<String, Object?>{'unusable': true}), 200);
    if (p.endsWith('/end')) return http.Response(jsonEncode(<String, Object?>{'ended': true, 'reason': 'declined'}), 200);
    return http.Response('not found', 404);
  });

  PushService service() => PushService(
        config: _config(),
        platformSupported: true,
        channelFactory: (api, onPointer) => PushChannel(
          api,
          onForegroundPointer: onPointer,
          deps: PushChannelDeps(
            initializeFirebase: () async {},
            getToken: () async => 'device-token-1',
            onTokenRefresh: refresh.stream,
            onMessage: messages.stream,
          ),
        ),
      );

  Future<void> pumpHome({PushService? pushService, bool localOnly = false}) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: LiveChildHomeScreen(
        baseUrl: 'http://api.test',
        childId: 'child-a',
        httpClient: server,
        navigatorKey: nav,
        pushService: pushService,
        incomingCallChannel: IncomingCallChannel(channel: phone),
        localOnly: localOnly,
        localName: localOnly ? 'Ivy' : null,
        localAge: localOnly ? 6 : null,
      ),
    ));
    await t.pumpAndSettle();
  }

  void push(Map<String, dynamic> data) => messages.add(RemoteMessage(data: data));
}

void main() {
  setUp(CallPresence.reset);

  testWidgets('a connected child device registers its token, and the home is untouched by it', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    expect(w.requests.where((r) => r == 'POST /v1/me/device-tokens').length, 1);
    expect(find.text('Hi, Ivy'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    // The ring surface is listening (attach), and nothing is on screen.
    expect(w.phoneCalls, contains(IncomingCallChannel.mAttach));
  });

  testWidgets('a ring while the app is open knocks; the words are soft and the answers are the knock\'s own', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    w.push(<String, dynamic>{'kind': 'call_incoming', 'ref': _session, 'callHandle': 'room-abc'});
    await t.pumpAndSettle();
    expect(find.text('your grown-up would like to talk.'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Just talking'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    for (final banned in <String>['decline', 'reject', 'refuse', 'dismiss', 'ignore', 'missed', 'error']) {
      expect(find.textContaining(banned, findRichText: true), findsNothing, reason: banned);
    }
  });

  testWidgets('the caller hanging up takes the knock away without a word', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    w.push(<String, dynamic>{'kind': 'call_incoming', 'ref': _session, 'callHandle': 'room-abc'});
    await t.pumpAndSettle();
    expect(find.text('Answer'), findsOneWidget);
    w.push(<String, dynamic>{'kind': 'call_cancelled', 'ref': _session});
    await t.pumpAndSettle();
    expect(find.text('Answer'), findsNothing);
    expect(find.text('Hi, Ivy'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(w.phoneCalls, contains(IncomingCallChannel.mRingFinished));
  });

  testWidgets('"Not now" closes the call\'s record on the server; the knock goes; she is told only the gentle line', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    w.push(<String, dynamic>{'kind': 'call_incoming', 'ref': _session, 'callHandle': 'room-abc'});
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Alright. He knows you are busy.'), findsOneWidget);
    expect(w.requests, contains('POST /v1/children/child-a/calls/$_session/end'));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Answer'), findsNothing);
  });

  testWidgets('"Answer" joins through a fresh session; a join that cannot be used is the calm "has ended" line, never an error', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    w.push(<String, dynamic>{'kind': 'call_incoming', 'ref': _session, 'callHandle': 'room-abc'});
    await t.pumpAndSettle();
    await t.tap(find.text('Answer'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(w.requests, contains('POST /v1/children/child-a/calls/$_session/join'));
    expect(find.text('That call has ended.'), findsOneWidget);
    expect(find.textContaining('error', findRichText: true), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
  });

  testWidgets('"something new is waiting" makes the home look again and changes nothing she can see but the quiet dot', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    final inboxBefore = w.requests.where((r) => r.endsWith('/inbox')).length;
    w.unread = 2;
    w.push(<String, dynamic>{'kind': 'message_ready', 'ref': 'opaque-intent-id', 'senderName': 'must not be read'});
    await t.pumpAndSettle();
    expect(w.requests.where((r) => r.endsWith('/inbox')).length, inboxBefore + 1);
    expect(find.text('Hi, Ivy'), findsOneWidget);
    expect(find.text('must not be read'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('kinds with no sender yet, and unknown kinds, do nothing at all', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    final before = List<String>.of(w.requests);
    for (final k in <String>['turn_ready', 'exchange_reminder', 'dose_due', 'from_the_future']) {
      w.push(<String, dynamic>{'kind': k, 'ref': _session});
    }
    await t.pumpAndSettle();
    expect(w.requests, before);
    expect(find.text('Answer'), findsNothing);
  });

  testWidgets('a hostile ref in a call push never knocks and never reaches a request', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    final before = w.requests.length;
    for (final bad in <String>['../../v1/me', '$_session/end', '<script>x</script>', '']) {
      w.push(<String, dynamic>{'kind': 'call_incoming', 'ref': bad});
    }
    w.push(<String, dynamic>{'kind': 7, 'ref': 8});
    await t.pumpAndSettle();
    expect(find.text('Answer'), findsNothing);
    expect(w.requests.length, before);
  });

  testWidgets('a build with no Firebase settings does nothing: no token, no listener, no change to the home', (t) async {
    final w = _World(t);
    await w.pumpHome(); // the real PushService; this test build has no OLIVE_FCM_* defines
    expect(w.requests.where((r) => r.contains('device-tokens')), isEmpty);
    expect(w.phoneCalls, isEmpty);
    expect(find.text('Hi, Ivy'), findsOneWidget);
  });

  testWidgets('a locally paired tablet (no session) never touches push or the server, even with a service handed to it', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service(), localOnly: true);
    expect(w.requests, isEmpty);
    expect(w.phoneCalls, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('leaving the screen stops listening', (t) async {
    final w = _World(t);
    await w.pumpHome(pushService: w.service());
    expect(w.messages.hasListener, isTrue);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pumpAndSettle();
    expect(w.messages.hasListener, isFalse);
  });
}
