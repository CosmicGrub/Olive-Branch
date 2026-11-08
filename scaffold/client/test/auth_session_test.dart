// OLIVE BRANCH — auth_session.dart tests. Audit G-02 / G-06 / C-03 / G-14.
//
// Proves the production session path with NO dev login anywhere: a paired
// device's {deviceId, deviceCredential} -> short sessions, one automatic retry
// on 401, typed 401/403 errors, revocation ending the session, sign-out
// clearing the stored identity, and the dev path failing CLOSED unless opted
// in. Mock http clients only — the server half is
// server/test/auth_session_route_test.mjs and packages/db/test/
// device_credential.test.mjs.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';

class _MemStore implements SecureKeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// A real-shaped session token: `base64url(payload).mac` with the server's
/// `exp` (epoch ms) claim — the only part the client reads.
String tokenExp(DateTime exp, {String tag = 'a'}) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp.millisecondsSinceEpoch, 'tag': tag})));
  return '${payload.replaceAll('=', '')}.mac';
}

final DateTime t0 = DateTime.utc(2026, 11, 7, 12);

DeviceIdentity identity({String? token, String? credential = 'cred-1'}) => DeviceIdentity(
    sessionToken: token ?? tokenExp(t0.add(const Duration(hours: 1))),
    deviceId: 'dev-1', role: 'guardian', targetId: 'g-1', deviceCredential: credential);

http.Response json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  late _MemStore storage;
  late DeviceIdentityStore store;
  late DateTime clock;
  late List<http.Request> seen;
  var signedOut = 0;

  setUp(() {
    storage = _MemStore();
    store = DeviceIdentityStore(storage: storage);
    clock = t0;
    seen = [];
    signedOut = 0;
    AuthSession.use(null);
    AuthSession.devLoginEnabled = false; // the production default, for this whole file
  });
  tearDown(() {
    AuthSession.use(null);
    AuthSession.devLoginEnabled = true; // flutter_test_config.dart's value for other files
  });

  AuthSession deviceSession(http.Client client, {DeviceIdentity? id}) => AuthSession.device(
      baseUrl: 'http://api.test', identity: id ?? identity(), store: store, client: client,
      now: () => clock, onSignedOut: () => signedOut++);

  group('expiryOf', () {
    test('reads exp from the token payload', () {
      expect(AuthSession.expiryOf(tokenExp(t0))!.millisecondsSinceEpoch, t0.millisecondsSinceEpoch);
    });
    test('garbage is null (treated as expired, never trusted)', () {
      expect(AuthSession.expiryOf('nonsense'), isNull);
      expect(AuthSession.expiryOf('###.mac'), isNull);
    });
  });

  group('device session — token()', () {
    test('a token with time left is used as-is, no network', () async {
      final s = deviceSession(MockClient((r) async { seen.add(r); return json(500, {}); }));
      expect(await s.token(), identity().sessionToken);
      expect(seen, isEmpty);
    });

    test('a token inside the 60s skew is refreshed with the device credential, and '
        'the new session is persisted for the next cold boot', () async {
      final fresh = tokenExp(t0.add(const Duration(hours: 2)), tag: 'fresh');
      final s = deviceSession(MockClient((r) async {
        seen.add(r);
        return json(200, {'sessionToken': fresh, 'expiresAt': 1, 'deviceId': 'dev-1'});
      }), id: identity(token: tokenExp(t0.add(const Duration(seconds: 30)))));
      expect(await s.token(), fresh);
      expect(seen, hasLength(1));
      expect(seen.single.url.path, '/v1/auth/session/refresh');
      expect(jsonDecode(seen.single.body), {'deviceId': 'dev-1', 'deviceCredential': 'cred-1'});
      expect((seen.single.headers['authorization']), isNull,
          reason: 'refresh authenticates by the credential, never a bearer');
      expect((await store.load())!.sessionToken, fresh);
      expect((await store.load())!.deviceCredential, 'cred-1');
    });

    test('an expired token is refreshed; an unreadable one too', () async {
      final fresh = tokenExp(t0.add(const Duration(hours: 1)), tag: 'f');
      for (final stale in [tokenExp(t0.subtract(const Duration(hours: 1))), 'garbage']) {
        final s = deviceSession(MockClient((r) async => json(200, {'sessionToken': fresh})),
            id: identity(token: stale));
        expect(await s.token(), fresh);
      }
    });

    test('concurrent callers share ONE refresh request', () async {
      final fresh = tokenExp(t0.add(const Duration(hours: 1)), tag: 'one');
      final s = deviceSession(MockClient((r) async {
        seen.add(r);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return json(200, {'sessionToken': fresh});
      }), id: identity(token: 'garbage'));
      final results = await Future.wait([s.token(), s.token(), s.token()]);
      expect(results, [fresh, fresh, fresh]);
      expect(seen, hasLength(1));
    });

    test('a storage failure while persisting never fails the refresh', () async {
      final fresh = tokenExp(t0.add(const Duration(hours: 1)));
      final failing = DeviceIdentityStore(storage: _ThrowingStore());
      final s = AuthSession.device(baseUrl: 'http://api.test', identity: identity(token: 'x'),
          store: failing, client: MockClient((r) async => json(200, {'sessionToken': fresh})),
          now: () => clock);
      expect(await s.token(), fresh);
    });
  });

  group('device session — refresh failures end the session', () {
    for (final c in [
      (401, 'device_revoked'),
      (401, 'invalid_device_credential'),
    ]) {
      test('${c.$1} ${c.$2}: DeviceRevokedException, stored identity cleared, '
          'onSignedOut fired once, later calls refused', () async {
        await store.save(identity());
        final s = deviceSession(MockClient((r) async { seen.add(r); return json(c.$1, {'error': c.$2}); }),
            id: identity(token: 'garbage'));
        await expectLater(s.token(), throwsA(isA<DeviceRevokedException>()));
        expect(await store.load(), isNull, reason: 'credential and token wiped from secure storage');
        expect(signedOut, 1);
        expect(s.hasEnded, isTrue);
        await expectLater(s.token(), throwsA(isA<DeviceRevokedException>()));
        await expectLater(s.refresh(), throwsA(isA<DeviceRevokedException>()));
        expect(seen, hasLength(1), reason: 'an ended session never calls the server again');
        expect(signedOut, 1);
      });
    }

    test('403 account_deactivated: typed ForbiddenException, session ended', () async {
      await store.save(identity());
      final s = deviceSession(MockClient((r) async => json(403, {'error': 'account_deactivated'})),
          id: identity(token: 'garbage'));
      await expectLater(s.token(), throwsA(isA<ForbiddenException>()));
      expect(await store.load(), isNull);
      expect(signedOut, 1);
    });

    test('a 5xx / network failure does NOT end the session (the device is not revoked)', () async {
      await store.save(identity());
      final s = deviceSession(MockClient((r) async => json(503, {'error': 'down'})),
          id: identity(token: 'garbage'));
      await expectLater(s.token(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)));
      expect(await store.load(), isNotNull);
      expect(signedOut, 0);
      expect(s.hasEnded, isFalse);
      final s2 = deviceSession(MockClient((r) async => throw http.ClientException('offline')),
          id: identity(token: 'garbage'));
      await expectLater(s2.token(), throwsA(isA<http.ClientException>()));
      expect(signedOut, 0);
    });

    test('a legacy identity (no credential): valid token still works, expired one '
        'ends the session and the device must re-pair', () async {
      await store.save(identity(credential: null));
      final ok = deviceSession(MockClient((r) async { seen.add(r); return json(500, {}); }),
          id: identity(credential: null));
      expect(ok.canRefresh, isFalse);
      expect(await ok.token(), identity().sessionToken);
      final lapsed = deviceSession(MockClient((r) async { seen.add(r); return json(500, {}); }),
          id: identity(credential: null, token: tokenExp(t0.subtract(const Duration(minutes: 1)))));
      await expectLater(lapsed.token(), throwsA(isA<DeviceRevokedException>()));
      expect(await store.load(), isNull);
      expect(signedOut, 1);
      expect(seen, isEmpty);
    });
  });

  group('OliveApi + session — one automatic retry on 401', () {
    test('401 -> refresh -> retry succeeds, with the NEW bearer', () async {
      final fresh = tokenExp(t0.add(const Duration(hours: 3)), tag: 'retry');
      final bearers = <String?>[];
      final client = MockClient((r) async {
        if (r.url.path == '/v1/auth/session/refresh') {
          seen.add(r);
          return json(200, {'sessionToken': fresh});
        }
        bearers.add(r.headers['authorization']);
        return bearers.length == 1 ? json(401, {'error': 'expired'}) : json(200, {'displayName': 'Dad'});
      });
      final session = deviceSession(client);
      final api = OliveApi('http://api.test', await session.token(), client: client, session: session);
      final me = await api.fetchMe();
      expect(me['displayName'], 'Dad');
      expect(bearers, ['Bearer ${identity().sessionToken}', 'Bearer $fresh']);
      expect(seen, hasLength(1), reason: 'exactly one refresh');
    });

    test('a SECOND 401 is surfaced as UnauthorizedException — never retried again', () async {
      var calls = 0, refreshes = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/v1/auth/session/refresh') {
          refreshes++;
          return json(200, {'sessionToken': tokenExp(t0.add(const Duration(hours: 1)))});
        }
        calls++;
        return json(401, {'error': 'expired'});
      });
      final session = deviceSession(client);
      final api = OliveApi('http://api.test', 'x', client: client, session: session);
      await expectLater(api.fetchMe(), throwsA(isA<UnauthorizedException>()));
      expect(calls, 2);
      expect(refreshes, 1);
    });

    test('POST bodies are re-sent intact on the retry', () async {
      final bodies = <String>[];
      var n = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/v1/auth/session/refresh') {
          return json(200, {'sessionToken': tokenExp(t0.add(const Duration(hours: 1)))});
        }
        bodies.add(r.body);
        return ++n == 1 ? json(401, {'error': 'expired'}) : json(200, {'ok': true});
      });
      final session = deviceSession(client);
      final api = OliveApi('http://api.test', 'x', client: client, session: session);
      await api.changeGuardianPin('1111', '2222');
      expect(bodies, hasLength(2));
      expect(bodies[0], bodies[1]);
      expect(jsonDecode(bodies[1]), {'pin': '2222', 'currentPin': '1111'});
    });

    test('device_revoked on a normal call is NOT retried: it ends the session '
        '(identity cleared, shell notified) and surfaces DeviceRevokedException', () async {
      await store.save(identity());
      var calls = 0;
      final client = MockClient((r) async { calls++; return json(401, {'error': 'device_revoked'}); });
      final session = deviceSession(client);
      final api = OliveApi('http://api.test', 'x', client: client, session: session);
      await expectLater(api.fetchMe(), throwsA(isA<DeviceRevokedException>()));
      expect(calls, 1);
      expect(await store.load(), isNull);
      expect(signedOut, 1);
    });

    test('403 is typed ForbiddenException and never retried', () async {
      var calls = 0;
      final client = MockClient((r) async { calls++; return json(403, {'error': 'pin_incorrect'}); });
      final api = OliveApi('http://api.test', 'x', client: client, session: deviceSession(client));
      await expectLater(api.fetchMe(), throwsA(isA<ForbiddenException>().having((e) => e.error, 'error', 'pin_incorrect')));
      expect(calls, 1);
    });

    test('without a session a 401 is typed and not retried (legacy behaviour)', () async {
      var calls = 0;
      final client = MockClient((r) async { calls++; return json(401, {'error': 'expired'}); });
      final api = OliveApi('http://api.test', 'tok', client: client);
      await expectLater(api.fetchMe(), throwsA(isA<UnauthorizedException>()));
      expect(calls, 1);
    });

    test('a 404/500 stays a plain ApiException; userMessage never leaks the raw reason', () async {
      final client = MockClient((r) async => json(500, {'error': 'boom_internal_detail'}));
      final api = OliveApi('http://api.test', 'tok', client: client);
      try {
        await api.fetchMe();
        fail('should throw');
      } on ApiException catch (e) {
        expect(e, isNot(isA<UnauthorizedException>()));
        expect(e.userMessage, isNot(contains('boom')));
        expect(e.userMessage, isNot(contains('500')));
      }
      expect(ApiException.fromStatus(401, 'expired').userMessage, isNot(contains('expired')));
      expect(ApiException.fromStatus(403, 'wrong_child').userMessage, isNot(contains('wrong_child')));
      expect(userMessageFor(StateError('internal')), isNot(contains('internal')));
    });
  });

  group('signOut', () {
    test('revokes the device server-side with a bearer, clears storage, tells the shell', () async {
      await store.save(identity());
      final client = MockClient((r) async { seen.add(r); return json(200, {'ok': true, 'revoked': true}); });
      final s = deviceSession(client);
      AuthSession.use(s);
      expect(await s.signOut(), isTrue);
      expect(seen.single.url.path, '/v1/auth/session/sign-out');
      expect(seen.single.headers['authorization'], 'Bearer ${identity().sessionToken}');
      expect(await store.load(), isNull);
      expect(signedOut, 1);
      expect(AuthSession.current, isNull, reason: 'the ambient session is uninstalled');
      await expectLater(s.token(), throwsA(isA<DeviceRevokedException>()));
      expect(await s.signOut(), isFalse, reason: 'idempotent');
      expect(signedOut, 1);
    });

    test('offline: still signs out locally and says the server could not confirm', () async {
      await store.save(identity());
      final s = deviceSession(MockClient((r) async => throw http.ClientException('offline')));
      expect(await s.signOut(), isFalse);
      expect(await store.load(), isNull);
      expect(signedOut, 1);
    });

    test('an expired session refreshes first so the revoke can authenticate', () async {
      await store.save(identity());
      final fresh = tokenExp(t0.add(const Duration(hours: 1)), tag: 'so');
      final s = deviceSession(MockClient((r) async {
        seen.add(r);
        if (r.url.path.endsWith('/refresh')) return json(200, {'sessionToken': fresh});
        return json(200, {'revoked': true});
      }), id: identity(token: 'garbage'));
      expect(await s.signOut(), isTrue);
      expect(seen.map((r) => r.url.path), ['/v1/auth/session/refresh', '/v1/auth/session/sign-out']);
      expect(seen.last.headers['authorization'], 'Bearer $fresh');
    });
  });

  group('apiFor and the dev flag — fail closed', () {
    test('no session installed and dev login not enabled -> not_signed_in, no network', () async {
      var calls = 0;
      final client = MockClient((r) async { calls++; return json(200, {'token': 't'}); });
      await expectLater(apiFor('http://api.test', userId: 'u', client: client),
          throwsA(isA<UnauthorizedException>().having((e) => e.error, 'error', 'not_signed_in')));
      expect(calls, 0, reason: 'never even tries POST /v1/auth/dev-login');
    });

    test('devLoginFor itself refuses when the flag is off', () async {
      var calls = 0;
      final client = MockClient((r) async { calls++; return json(200, {'token': 't'}); });
      await expectLater(devLoginFor('http://api.test', userId: 'u', client: client),
          throwsA(isA<UnauthorizedException>().having((e) => e.error, 'error', 'dev_login_disabled')));
      expect(calls, 0);
    });

    test('constructing a dev session with the flag off is a programming error', () {
      expect(() => AuthSession.dev(baseUrl: 'http://api.test', userId: 'u'), throwsStateError);
    });

    test('with a session installed, apiFor uses ITS token and never calls dev-login', () async {
      final paths = <String>[];
      final client = MockClient((r) async { paths.add(r.url.path); return json(200, {'displayName': 'Dad'}); });
      AuthSession.use(deviceSession(client));
      final api = await apiFor('http://api.test', userId: 'someone-else', client: client);
      expect(api.sessionToken, identity().sessionToken);
      await api.fetchMe();
      expect(paths, ['/v1/me']);
    });

    test('flag on (the explicit dev path): a dev session logs in once, per call, no retry', () async {
      AuthSession.devLoginEnabled = true;
      var logins = 0, me = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/v1/auth/dev-login') { logins++; return json(200, {'token': 'dev-tok'}); }
        me++;
        return json(401, {'error': 'expired'});
      });
      final api = await apiFor('http://api.test', userId: 'u', client: client);
      expect(api.sessionToken, 'dev-tok');
      await expectLater(api.fetchMe(), throwsA(isA<UnauthorizedException>()));
      expect(logins, 1);
      expect(me, 1, reason: 'a per-call dev session cannot refresh, so no retry (legacy behaviour)');
    });
  });
}

class _ThrowingStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore unavailable');
  @override
  Future<void> write(String key, String value) async => throw StateError('keystore unavailable');
  @override
  Future<void> delete(String key) async => throw StateError('keystore unavailable');
}
