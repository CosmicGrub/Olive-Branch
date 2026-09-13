// OLIVE BRANCH — push_channel.dart tests. MASTERFILE §11.
//
// Three things this file exists to prove, per the task that produced it:
//   1. firebaseMessagingBackgroundHandler is a REAL top-level function, not
//      a closure -- the well-known Flutter/Firebase pitfall where a closure
//      compiles fine and then silently never fires in the background.
//   2. The foreground handler never surfaces raw payload text (notification
//      title/body, or any data key besides kind/ref/callHandle) as if it
//      were real message content.
//   3. Token registration is real -- including onTokenRefresh triggering a
//      fresh registration, not just the first-launch token.
//
// FirebaseMessaging itself has no simple mock-platform story to drive from
// a black-box widget test in this environment (unlike KioskChannel/
// WearSyncChannel, thin MethodChannel wrappers this app owns end to end).
// So most tests here drive PushChannel through its own PushChannelDeps
// injection seam (push_channel.dart's own doc comment explains why it
// exists) rather than FirebaseMessaging.instance. One test deliberately
// does NOT use that seam -- proving the real, unmocked
// Firebase.initializeApp() failure path this environment genuinely
// produces (no google-services.json -- see pubspec.yaml).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/push_channel.dart';

void main() {
  group('firebaseMessagingBackgroundHandler — must be a real top-level '
      'function, not a closure', () {
    test(
        'is assignable to a const function reference -- only a top-level or '
        'static function tear-off can be a compile-time constant; a closure '
        'or instance method fails to COMPILE here, not just misbehave at '
        'runtime', () {
      // This is the actual mechanical property Android's background isolate
      // relies on: a stable, context-free callback handle. If a future edit
      // ever turned this into a closure (e.g. moved inside a class, or
      // captured a variable), THIS LINE would stop compiling -- the
      // strongest test available for "not a closure" in Dart, which has no
      // dart:mirrors under flutter test.
      const Future<void> Function(RemoteMessage) ref =
          firebaseMessagingBackgroundHandler;
      expect(ref, isNotNull);
    });

    test(
        'is declared at column 0 (true top level, not nested in a class) '
        'with @pragma(\'vm:entry-point\') directly above it', () {
      // Belt-and-suspenders alongside the const-reference check above: that
      // check proves "not a closure captured in a variable" but a `static`
      // method tear-off would also pass it, and a static method is NOT
      // enough here (Android's engine looks up this specific entry-point
      // annotation on registration). Reading the source is the only way to
      // confirm BOTH the annotation and the true top-level placement.
      // `\r?\n` -- NOT a bare `\n` -- deliberately, so this check stays
      // about the STRUCTURE (top-level, pragma directly above) and not
      // about which line-ending convention the checkout happens to use.
      // A bare `\n` here false-fails on any Windows checkout with
      // core.autocrlf on: git converts this file's LF to CRLF on checkout
      // (no .gitattributes rule pins *.dart to LF), so the byte right
      // after the pragma's `)` is `\r`, not `\n`, and a literal `\n`
      // regex never matches even though the declaration is genuinely
      // correct. Confirmed CI (ubuntu-latest, LF checkout) was never
      // affected -- this was a local-only false negative.
      final source =
          File('lib/push_channel.dart').readAsStringSync();
      final declaration = RegExp(
        r"@pragma\('vm:entry-point'\)\r?\n"
        r'Future<void> firebaseMessagingBackgroundHandler\(RemoteMessage message\) async \{',
      );
      expect(declaration.hasMatch(source), isTrue,
          reason: 'firebaseMessagingBackgroundHandler must be a top-level '
              'declaration (column 0, no indentation -- i.e. not inside a '
              'class body) immediately preceded by @pragma(\'vm:entry-point\'). '
              'A closure or instance method compiles fine and then never '
              'fires in Android\'s separate background isolate.');
    });

    test('is directly callable as a bare function value with no receiver',
        () async {
      // A closure bound to an object needs that object to exist; an
      // instance method tear-off carries an implicit receiver. Calling this
      // with nothing but a RemoteMessage argument -- no object, no `this`
      // -- is exactly what Android's background isolate does.
      //
      // It throws here (PushInitializationError) because Firebase is
      // genuinely unconfigured in this environment (see pubspec.yaml) --
      // that failure is itself real, expected, and asserted below.
      await expectLater(
        firebaseMessagingBackgroundHandler(
            const RemoteMessage(data: {'kind': 'message_ready', 'ref': 'r1'})),
        throwsA(isA<PushInitializationError>()),
      );
    });
  });

  group('PushPointer.fromData — reads only kind/ref/callHandle', () {
    test('extracts kind and ref, callHandle absent -> null', () {
      final p = PushPointer.fromData(const {'kind': 'turn_ready', 'ref': 'r-9', 'v': '1'});
      expect(p.kind, 'turn_ready');
      expect(p.ref, 'r-9');
      expect(p.callHandle, isNull);
    });

    test('call_incoming carries callHandle through', () {
      final p = PushPointer.fromData(
          const {'kind': 'call_incoming', 'ref': 'r-1', 'callHandle': 'h-1', 'v': '1'});
      expect(p.callHandle, 'h-1');
    });

    test('toString() redacts callHandle -- never logs it verbatim', () {
      final p = PushPointer.fromData(
          const {'kind': 'call_incoming', 'ref': 'r-1', 'callHandle': 'h-1'});
      expect(p.toString(), isNot(contains('h-1')));
      expect(p.toString(), contains('<redacted>'));
    });

    // Regression: adversarial-review finding -- APNs (unlike FCM v1's
    // server-enforced map<string,string>) carries arbitrary JSON with no
    // type constraint on custom keys, so a malformed/adversarial payload
    // could hand this a non-String value for kind/ref/callHandle. A bare
    // `as String?` cast throws an uncaught TypeError in that case; this
    // must degrade to '' / null instead, never throw -- especially for
    // call_incoming, which MASTERFILE §11 says must ring rather than fail
    // silently.
    test('a non-String kind (e.g. a malformed/adversarial APNs payload) '
        'degrades to an empty kind instead of throwing', () {
      final p = PushPointer.fromData(const {'kind': 7, 'ref': 'r-1'});
      expect(p.kind, '');
      expect(p.ref, 'r-1');
    });

    test('a non-String ref degrades to an empty ref instead of throwing',
        () {
      final p = PushPointer.fromData(
          const {'kind': 'message_ready', 'ref': <String, int>{'x': 1}});
      expect(p.kind, 'message_ready');
      expect(p.ref, '');
    });

    test('a non-String callHandle degrades to null instead of throwing -- '
        'the call_incoming case this file\'s own header says must ring '
        'rather than crash', () {
      final p = PushPointer.fromData(const {
        'kind': 'call_incoming',
        'ref': 'r-1',
        'callHandle': <String, int>{'x': 1},
      });
      expect(p.kind, 'call_incoming');
      expect(p.callHandle, isNull);
    });

    test('constructing from a message.data map with mixed valid/invalid '
        'types never throws end to end, through the real foreground '
        'handler', () async {
      final captured = <PushPointer>[];
      final onMessageController = StreamController<RemoteMessage>();
      final api = OliveApi('http://api.test', 'tok',
          client: MockClient((_) async => http.Response('{}', 200)));
      final channel = PushChannel(
        api,
        onForegroundPointer: captured.add,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => null,
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: onMessageController.stream,
        ),
      );
      await channel.initialize();

      onMessageController.add(const RemoteMessage(
        data: {'kind': 'call_incoming', 'ref': 'r-1', 'callHandle': 42},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      expect(captured.single.kind, 'call_incoming');
      expect(captured.single.callHandle, isNull);

      channel.dispose();
      await onMessageController.close();
    });
  });

  group('PushChannel — foreground handler never surfaces raw payload text '
      'as if it were content', () {
    test('a push carrying push.ts\'s own FORBIDDEN_DATA_KEYS-shaped leak '
        '(senderName, body) plus a real notification title/body still '
        'produces ONLY a bare kind/ref/callHandle pointer', () async {
      final captured = <PushPointer>[];
      final onMessageController = StreamController<RemoteMessage>();
      final api = OliveApi('http://api.test', 'tok',
          client: MockClient((_) async => http.Response('{}', 200)));
      final channel = PushChannel(
        api,
        onForegroundPointer: captured.add,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => null,
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: onMessageController.stream,
        ),
      );
      await channel.initialize();

      // Simulates exactly the disclosure push.ts's own auditPush() exists to
      // block server-side (see that file's header: "Goodnight video from
      // Dad" is the canonical example). This proves the client wouldn't
      // surface it even if that server-side guard ever regressed --
      // defense in depth, not reliance on the guard holding forever.
      onMessageController.add(const RemoteMessage(
        notification:
            RemoteNotification(title: 'Dad', body: 'Goodnight video from Dad'),
        data: {
          'kind': 'message_ready',
          'ref': 'ref-123',
          'v': '1',
          'senderName': 'Dad',
          'body': 'Goodnight video from Dad',
          'childName': 'Ivy',
        },
      ));
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      final pointer = captured.single;
      expect(pointer.kind, 'message_ready');
      expect(pointer.ref, 'ref-123');
      expect(pointer.callHandle, isNull);
      // Structural, not just behavioral: PushPointer has no field 'Dad' or
      // 'Goodnight video from Dad' could even be assigned to, but confirm
      // the handler's actual output contains neither string anywhere.
      expect(pointer.toString(), isNot(contains('Dad')));
      expect(pointer.toString(), isNot(contains('Goodnight')));

      channel.dispose();
      await onMessageController.close();
    });

    test('no foreground handler wired -> the default fallback runs and '
        'still never touches notification title/body (smoke test that the '
        'default path itself does not throw)', () async {
      final onMessageController = StreamController<RemoteMessage>();
      final api = OliveApi('http://api.test', 'tok');
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => null,
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: onMessageController.stream,
        ),
      );
      await channel.initialize();

      onMessageController.add(const RemoteMessage(
        notification: RemoteNotification(title: 'Olive', body: 'Something new.'),
        data: {'kind': 'dose_due', 'ref': 'ref-7'},
      ));
      await Future<void>.delayed(Duration.zero);

      channel.dispose();
      await onMessageController.close();
    });
  });

  group('PushChannel — real token registration', () {
    test('initialize() registers the real fetched token via '
        'POST /v1/me/device-tokens', () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => 'token-abc',
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: const Stream<RemoteMessage>.empty(),
        ),
      );

      await channel.initialize();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/v1/me/device-tokens');
      expect(requests.single.headers['authorization'], 'Bearer tok');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['token'], 'token-abc');
      expect(body['platform'], anyOf('android', 'ios'));

      channel.dispose();
    });

    test('§8.11.4 (v0.49.11): on a non-iOS test host, no channel key is '
        'sent at all -- omitted, not a guessed value', () async {
      // This test host is not forced to iOS, so defaultTargetPlatform here
      // reflects flutter test's own default -- android, per this file's
      // established anyOf('android','ios') platform assertion above. That
      // is exactly the case device_channels.dart's own header says this
      // client cannot yet resolve a real channel for.
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => 'token-abc',
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: const Stream<RemoteMessage>.empty(),
        ),
      );

      await channel.initialize();

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body.containsKey('channel'), isFalse);
      expect(channel.registrationAdvice, isNull,
        reason: 'no known channel means nothing to advise on');

      channel.dispose();
    });

    test('§8.11.4 (v0.49.11): on iOS, the real channel is reported, and '
        'registrationAdvice is null (iOS always pushes)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => 'token-abc',
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: const Stream<RemoteMessage>.empty(),
        ),
      );

      await channel.initialize();

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['channel'], 'ios');
      expect(channel.registrationAdvice, isNull,
        reason: 'iOS is always push-capable, so channelAdvice(ios) is null');

      channel.dispose();
    });

    test('a null token from getToken() registers nothing (no crash, no '
        'request)', () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => null,
          onTokenRefresh: const Stream<String>.empty(),
          onMessage: const Stream<RemoteMessage>.empty(),
        ),
      );

      await channel.initialize();

      expect(requests, isEmpty);
      channel.dispose();
    });

    test('onTokenRefresh triggers a fresh POST with the new token -- a '
        'token can rotate at any time, not only at first launch', () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final refreshController = StreamController<String>();
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => 'token-first',
          onTokenRefresh: refreshController.stream,
          onMessage: const Stream<RemoteMessage>.empty(),
        ),
      );

      await channel.initialize();
      expect(requests, hasLength(1));
      expect((jsonDecode(requests[0].body) as Map)['token'], 'token-first');

      refreshController.add('token-rotated');
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(2));
      expect((jsonDecode(requests[1].body) as Map)['token'], 'token-rotated');

      channel.dispose();
      await refreshController.close();
    });

    test('re-registering the exact same token (e.g. a redundant refresh '
        'event) does not re-POST', () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final refreshController = StreamController<String>();
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => 'same-token',
          onTokenRefresh: refreshController.stream,
          onMessage: const Stream<RemoteMessage>.empty(),
        ),
      );

      await channel.initialize();
      expect(requests, hasLength(1));

      refreshController.add('same-token');
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(1)); // no redundant re-POST

      channel.dispose();
      await refreshController.close();
    });

    test('registerToken is directly callable (used by the real '
        'onTokenRefresh.listen(registerToken) wiring in initialize())',
        () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final channel = PushChannel(api);

      await channel.registerToken('direct-token');

      expect(requests, hasLength(1));
      expect((jsonDecode(requests.single.body) as Map)['token'], 'direct-token');
      channel.dispose();
    });
  });

  group('PushChannel — platform guard around the real firebase_messaging '
      'plugin (mirrors wear_sync_channel_test.dart\'s own convention)', () {
    test(
        'with Firebase.initializeApp() itself mocked to succeed but no '
        'other deps overridden, the real messaging-specific calls no-op on '
        'this non-Android/iOS test host instead of throwing '
        'MissingPluginException -- firebase_messaging ships no Windows '
        'implementation at all (unlike firebase_core, which does), and '
        '`flutter test` runs on this actual host OS, exactly the situation '
        'wear_sync_channel_test.dart already documents for a different '
        'plugin', () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok', client: mock);
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(initializeFirebase: () async {}),
      );

      await channel.initialize(); // must not throw MissingPluginException

      expect(requests, isEmpty); // no real token available on this host
      channel.dispose();
    });

    test('pushSupportedOnThisPlatform reflects this actual test host '
        '(false here -- this suite runs on Windows, not Android/iOS)', () {
      expect(pushSupportedOnThisPlatform, isFalse);
    });
  });

  group('PushChannel — honest Firebase-unconfigured failure', () {
    test('initialize() throws a named PushInitializationError when Firebase '
        'is unconfigured -- the REAL, unmocked failure this environment '
        'produces (no android/app/google-services.json exists here)',
        () async {
      final api = OliveApi('http://api.test', 'tok');
      final channel = PushChannel(api); // no deps override -- real Firebase path
      await expectLater(
          channel.initialize(), throwsA(isA<PushInitializationError>()));
    });

    test('PushInitializationError.toString() names the real cause, never '
        'pretends push registration succeeded', () {
      final err = PushInitializationError('no google-services.json');
      expect(err.toString(), contains('PushInitializationError'));
      expect(err.toString(), contains('no google-services.json'));
    });
  });

  group('PushChannel — dispose', () {
    test('cancels both stream subscriptions without throwing, including '
        'when called twice', () async {
      final onMessageController = StreamController<RemoteMessage>();
      final refreshController = StreamController<String>();
      final api = OliveApi('http://api.test', 'tok',
          client: MockClient((_) async => http.Response('{}', 200)));
      final channel = PushChannel(
        api,
        deps: PushChannelDeps(
          initializeFirebase: () async {},
          requestPermission: () async {},
          getToken: () async => null,
          onTokenRefresh: refreshController.stream,
          onMessage: onMessageController.stream,
        ),
      );
      await channel.initialize();

      channel.dispose();
      expect(channel.dispose, returnsNormally);

      await onMessageController.close();
      await refreshController.close();
    });
  });
}
