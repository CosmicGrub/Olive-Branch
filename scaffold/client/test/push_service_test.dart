// OLIVE BRANCH — push_service.dart tests. MASTERFILE §11, §7.18.
//
// Two things matter and both are proved here:
//   1. PushService.start is a GUARD: with no Firebase settings, on a platform with no push plugin, or with no
//      signed-in session it does nothing at all (no plugin call, no request) and says nothing; and whatever
//      goes wrong after that, it never throws.
//   2. PushDispatcher turns the content-free pointer into the right action, and a hostile or unknown pointer
//      into no action.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
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

class _Rig {
  _Rig({this.status = 200, this.token = 'device-token-1', this.firebaseFails = false}) {
    client = MockClient((http.Request req) async {
      requests.add('${req.method} ${req.url.path}');
      if (req.url.path == '/v1/me/device-tokens' && req.method == 'POST') {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return status == 200
            ? http.Response(jsonEncode(<String, Object?>{'id': 'row-1'}), 200)
            : http.Response(jsonEncode(<String, Object?>{'error': status == 403 ? 'account_deactivated' : 'boom'}), status);
      }
      return http.Response('not found', 404);
    });
    api = OliveApi('http://api.test', 'tok', client: client);
  }

  final int status;
  final String? token;
  final bool firebaseFails;
  late final MockClient client;
  late final OliveApi api;
  final List<String> requests = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final StreamController<RemoteMessage> messages = StreamController<RemoteMessage>.broadcast();
  int firebaseStarts = 0;
  int permissionAsks = 0;
  int factoryCalls = 0;

  PushChannel build(OliveApi api, void Function(PushPointer) onPointer) {
    factoryCalls++;
    return PushChannel(
      api,
      onForegroundPointer: onPointer,
      deps: PushChannelDeps(
        initializeFirebase: () async {
          firebaseStarts++;
          if (firebaseFails) throw PushInitializationError('no app');
        },
        requestPermission: () async {
          permissionAsks++;
        },
        getToken: () async => token,
        onTokenRefresh: refresh.stream,
        onMessage: messages.stream,
      ),
    );
  }

  PushService service({FcmConfig? config, bool supported = true}) =>
      PushService(config: config, platformSupported: supported, channelFactory: build);
}

void main() {
  group('PushService.start — the guard', () {
    test('no Firebase settings in this build: nothing happens, not even a channel is built', () async {
      final r = _Rig();
      final s = r.service(config: null); // this test build has no OLIVE_FCM_* defines
      final out = await s.start(api: r.api, onPointer: (_) {});
      expect(out, PushStart.notConfigured);
      expect(r.factoryCalls, 0);
      expect(r.firebaseStarts, 0);
      expect(r.requests, isEmpty);
      expect(s.registered, isFalse);
    });

    test('a platform with no push plugin: nothing happens', () async {
      final r = _Rig();
      final out = await r.service(config: _config(), supported: false).start(api: r.api, onPointer: (_) {});
      expect(out, PushStart.unsupportedPlatform);
      expect(r.factoryCalls, 0);
      expect(r.requests, isEmpty);
    });

    test('no signed-in session (a locally paired tablet): nothing happens and nothing is asked of the server', () async {
      final r = _Rig();
      final out = await r.service(config: _config()).start(api: null, onPointer: (_) {});
      expect(out, PushStart.noSession);
      expect(r.factoryCalls, 0);
      expect(r.firebaseStarts, 0);
      expect(r.requests, isEmpty);
    });
  });

  group('PushService.start — configured, signed in', () {
    test('starts Firebase, registers the token once with the server, and never asks for the notification permission', () async {
      final r = _Rig();
      final s = r.service(config: _config());
      final out = await s.start(api: r.api, onPointer: (_) {});
      expect(out, PushStart.started);
      expect(r.firebaseStarts, 1);
      expect(r.requests, <String>['POST /v1/me/device-tokens']);
      expect(r.bodies.single['token'], 'device-token-1');
      expect(r.bodies.single['platform'], 'android');
      // Android reports no channel guess (device_channels.dart); the key is omitted, not sent as null.
      expect(r.bodies.single.containsKey('channel'), isFalse);
      // The system's "allow notifications" box is a grown-up's tap (alerts_card.dart), never the child's device.
      expect(r.permissionAsks, 0);
      expect(s.registered, isTrue);
    });

    test('a token that rotates later is registered again; the same token twice is registered once', () async {
      final r = _Rig();
      final s = r.service(config: _config());
      await s.start(api: r.api, onPointer: (_) {});
      r.refresh.add('device-token-2');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      r.refresh.add('device-token-2');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(r.bodies.map((b) => b['token']).toList(), <Object?>['device-token-1', 'device-token-2']);
    });

    test('a foreground push reaches the handler as a content-free pointer only', () async {
      final r = _Rig();
      final seen = <PushPointer>[];
      await r.service(config: _config()).start(api: r.api, onPointer: seen.add);
      r.messages.add(const RemoteMessage(data: <String, dynamic>{
        'kind': 'message_ready',
        'ref': 'opaque-1',
        'senderName': 'Someone',
        'body': 'must never be read',
      }));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.kind, 'message_ready');
      expect(seen.single.ref, 'opaque-1');
      expect(seen.single.toString().contains('Someone'), isFalse);
      expect(seen.single.toString().contains('must never'), isFalse);
    });

    test('no token from Google: nothing is registered, and it is not a failure', () async {
      final r = _Rig(token: null);
      final s = r.service(config: _config());
      expect(await s.start(api: r.api, onPointer: (_) {}), PushStart.started);
      expect(r.requests, isEmpty);
      expect(s.registered, isFalse);
    });

    test('dispose stops listening', () async {
      final r = _Rig();
      final s = r.service(config: _config());
      await s.start(api: r.api, onPointer: (_) {});
      expect(r.messages.hasListener, isTrue);
      s.dispose();
      expect(r.messages.hasListener, isFalse);
      expect(r.refresh.hasListener, isFalse);
    });
  });

  group('PushService.start — whatever goes wrong, it returns and says nothing', () {
    test('Firebase refusing to start (a malformed project)', () async {
      final r = _Rig(firebaseFails: true);
      final out = await r.service(config: _config()).start(api: r.api, onPointer: (_) {});
      expect(out, PushStart.failed);
      expect(r.requests, isEmpty);
    });

    test('the server refusing the token (500)', () async {
      final r = _Rig(status: 500);
      final s = r.service(config: _config());
      expect(await s.start(api: r.api, onPointer: (_) {}), PushStart.failed);
      expect(s.registered, isFalse);
    });

    test('a deactivated grown-up\'s account (403 account_deactivated)', () async {
      final r = _Rig(status: 403);
      final s = r.service(config: _config());
      expect(await s.start(api: r.api, onPointer: (_) {}), PushStart.failed);
      expect(s.registered, isFalse);
    });

    test('a token refresh that the server then refuses does not throw out of the stream', () async {
      final r = _Rig();
      final s = r.service(config: _config());
      await s.start(api: r.api, onPointer: (_) {});
      // The server starts refusing; the rotated token must be swallowed (logged), not an unhandled async error.
      final failing = _Rig(status: 500);
      final s2 = failing.service(config: _config());
      await s2.start(api: failing.api, onPointer: (_) {});
      failing.refresh.add('another-token');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(s2.registered, isFalse);
    });
  });

  group('PushDispatcher', () {
    PushPointer p(String kind, [String ref = _session]) => PushPointer(kind: kind, ref: ref);

    test('call_incoming rings with the session id, call_cancelled cancels it, message_ready is a quiet hint', () {
      final log = <String>[];
      final d = PushDispatcher(
        onCallIncoming: (String r) => log.add('ring $r'),
        onCallCancelled: (String r) => log.add('cancel $r'),
        onMessageReady: () => log.add('ready'),
      );
      d.handle(p('call_incoming'));
      d.handle(p('call_cancelled'));
      d.handle(p('message_ready', 'any-opaque-id'));
      expect(log, <String>['ring $_session', 'cancel $_session', 'ready']);
    });

    test('a call pointer whose ref is not a canonical session id does nothing', () {
      final log = <String>[];
      final d = PushDispatcher(onCallIncoming: log.add, onCallCancelled: log.add);
      for (final bad in <String>['', '../../v1/me', 'x', '3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f5', '<b>hi</b>', '$_session/end']) {
        d.handle(p('call_incoming', bad));
        d.handle(p('call_cancelled', bad));
      }
      expect(log, isEmpty);
    });

    test('turn_ready, exchange_reminder, dose_due, an unknown kind and an empty kind do nothing', () {
      final log = <String>[];
      final d = PushDispatcher(
        onCallIncoming: log.add,
        onCallCancelled: log.add,
        onMessageReady: () => log.add('ready'),
      );
      for (final k in <String>['turn_ready', 'exchange_reminder', 'dose_due', 'future_kind', '', 'CALL_INCOMING', 'call_incoming ']) {
        d.handle(p(k));
      }
      expect(log, isEmpty);
    });

    test('a missing handler is a quiet no-op, not a crash', () {
      final d = PushDispatcher();
      d.handle(p('call_incoming'));
      d.handle(p('call_cancelled'));
      d.handle(p('message_ready'));
    });
  });
}
