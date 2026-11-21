// OLIVE BRANCH — auth_session.dart and a phone that was marked as lost (migration 0057). MASTERFILE section 7.23.
//
// A paused phone is NOT signed out: its sign-in is kept so it can come back when "I have it" is said and its owner types
// their own PIN once. An erase order (the owner's, for their own lost phone) rides on the refusal, is carried out here, is
// reported only AFTER it ran, and lets the sign-in go only when the server has heard it. Mock http clients only; the server
// half is server/test/lost_device_route.test.mjs.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';

class _MemStore implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

String _tokenExp(DateTime exp) {
  final String payload = base64Url.encode(utf8.encode(jsonEncode(<String, Object>{'exp': exp.millisecondsSinceEpoch})));
  return '${payload.replaceAll('=', '')}.mac';
}

final DateTime _t0 = DateTime.utc(2026, 11, 21, 12);

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});

void main() {
  late _MemStore storage;
  late DeviceIdentityStore store;
  late List<http.Request> seen;
  late List<String> order; // what happened, in order
  var signedOut = 0;

  setUp(() async {
    storage = _MemStore();
    store = DeviceIdentityStore(storage: storage);
    seen = <http.Request>[];
    order = <String>[];
    signedOut = 0;
    AuthSession.use(null);
    AuthSession.devLoginEnabled = false;
    AuthSession.eraseOnOrder = null;
    await store.save(DeviceIdentity(
        sessionToken: _tokenExp(_t0.subtract(const Duration(hours: 1))),
        deviceId: 'dev-1',
        role: 'guardian',
        targetId: 'g-1',
        deviceCredential: 'cred-1'));
  });
  tearDown(() {
    AuthSession.use(null);
    AuthSession.devLoginEnabled = true;
    AuthSession.eraseOnOrder = null;
  });

  AuthSession session(http.Client client) => AuthSession.device(
      baseUrl: 'http://api.test',
      identity: DeviceIdentity(
          sessionToken: _tokenExp(_t0.subtract(const Duration(hours: 1))),
          deviceId: 'dev-1',
          role: 'guardian',
          targetId: 'g-1',
          deviceCredential: 'cred-1'),
      store: store,
      client: client,
      now: () => _t0,
      onSignedOut: () => signedOut++);

  http.Client server(Future<http.Response> Function(http.Request r) refresh, {int ackStatus = 200}) =>
      MockClient((http.Request r) async {
        seen.add(r);
        if (r.url.path == '/v1/auth/session/refresh') {
          order.add('refresh');
          return refresh(r);
        }
        if (r.url.path == '/v1/auth/device/wiped') {
          order.add('ack');
          return _json(ackStatus, <String, dynamic>{'ok': ackStatus == 200});
        }
        return _json(404, <String, dynamic>{'error': 'not_found'});
      });

  Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  group('marked as lost: paused, not signed out', () {
    test('a paused phone gets its own exception, keeps its sign-in and does not fire the sign-out', () async {
      final AuthSession s = session(server((_) async => _json(401, <String, dynamic>{'error': 'device_paused'})));
      await expectLater(s.refresh(), throwsA(isA<DevicePausedException>()));
      expect(s.hasEnded, isFalse);
      expect(signedOut, 0);
      expect(await store.load(), isNotNull, reason: 'the identity is kept so the phone can come back');
    });

    test('it is still an UnauthorizedException, so every existing handler still catches it', () async {
      final AuthSession s = session(server((_) async => _json(401, <String, dynamic>{'error': 'device_paused'})));
      await expectLater(s.refresh(), throwsA(isA<UnauthorizedException>()));
    });

    test('back from a pause: the owner\'s PIN rides on this one refresh, and on no other', () async {
      int n = 0;
      final AuthSession s = session(server((http.Request r) async {
        n++;
        return _json(200, <String, dynamic>{'sessionToken': _tokenExp(_t0.add(const Duration(hours: 1)))});
      }));
      await s.refresh(pin: '4821');
      expect(bodyOf(seen.last)['pin'], '4821');
      await s.refresh();
      expect(bodyOf(seen.last).containsKey('pin'), isFalse, reason: 'a PIN is never kept for the next call');
      expect(n, 2);
    });

    test('a call with a PIN is never shared with another caller\'s refresh', () async {
      final AuthSession s = session(server((http.Request r) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return _json(200, <String, dynamic>{'sessionToken': _tokenExp(_t0.add(const Duration(hours: 1)))});
      }));
      await Future.wait(<Future<String>>[s.refresh(), s.refresh(pin: '4821')]);
      expect(seen.where((http.Request r) => r.url.path.endsWith('/refresh')).length, 2);
      expect(seen.where((http.Request r) => r.body.contains('4821')).length, 1);
    });

    test('a wrong or missing PIN is a 403 that keeps everything, and the next try can still work', () async {
      final AuthSession s = session(server((_) async => _json(403, <String, dynamic>{'error': 'pin_required'})));
      await expectLater(s.refresh(), throwsA(isA<ForbiddenException>()));
      expect(s.hasEnded, isFalse);
      expect(signedOut, 0);
    });
  });

  group('erase on next contact', () {
    http.Response told(String why) => _json(401, <String, dynamic>{'error': why, 'wipe': true});

    test('paused + order: erase first, say so second, then let the sign-in go', () async {
      AuthSession.eraseOnOrder = () async => order.add('erase');
      final AuthSession s = session(server((_) async => told('device_paused')));
      await expectLater(s.refresh(), throwsA(isA<DeviceRevokedException>()));
      expect(order, <String>['refresh', 'erase', 'ack']);
      final http.Request ack = seen.last;
      expect(bodyOf(ack), <String, dynamic>{'deviceId': 'dev-1', 'deviceCredential': 'cred-1'});
      expect(ack.headers.containsKey('authorization'), isFalse, reason: 'it has no session; its own credential is the proof');
      expect(s.hasEnded, isTrue);
      expect(signedOut, 1);
      expect(await store.load(), isNull, reason: 'the sign-in is gone only once the server has heard it');
    });

    test('cut off for good + order: the same', () async {
      AuthSession.eraseOnOrder = () async => order.add('erase');
      final AuthSession s = session(server((_) async => told('device_revoked')));
      await expectLater(s.refresh(), throwsA(isA<DeviceRevokedException>()));
      expect(order, <String>['refresh', 'erase', 'ack']);
    });

    test('a build with nothing wired to erase never says it erased, and stays paused', () async {
      final AuthSession s = session(server((_) async => told('device_paused')));
      await expectLater(s.refresh(), throwsA(isA<DevicePausedException>()));
      expect(order, <String>['refresh'], reason: 'no erase, so no acknowledgement');
      expect(s.hasEnded, isFalse);
      expect(await store.load(), isNotNull);
    });

    test('an erase that fails is not reported, and the sign-in stays so the order is told again', () async {
      AuthSession.eraseOnOrder = () async => throw StateError('disk');
      final AuthSession s = session(server((_) async => told('device_paused')));
      await expectLater(s.refresh(), throwsA(isA<DevicePausedException>()));
      expect(order, <String>['refresh']);
      expect(await store.load(), isNotNull);
    });

    test('an acknowledgement that does not get through keeps the sign-in; the next contact does it again', () async {
      int erased = 0;
      AuthSession.eraseOnOrder = () async => erased++;
      final AuthSession s = session(server((_) async => told('device_paused'), ackStatus: 503));
      await expectLater(s.refresh(), throwsA(isA<DevicePausedException>()));
      expect(s.hasEnded, isFalse);
      expect(await store.load(), isNotNull);
      // the server still says "erase" (it never heard); a second contact erases again (harmless) and says so
      final AuthSession s2 = session(server((_) async => told('device_paused')));
      await expectLater(s2.refresh(), throwsA(isA<DeviceRevokedException>()));
      expect(erased, 2);
      expect(await store.load(), isNull);
    });

    test('an acknowledgement over a dead connection is the same: kept, not lost', () async {
      AuthSession.eraseOnOrder = () async {};
      final http.Client c = MockClient((http.Request r) async {
        if (r.url.path.endsWith('/refresh')) return told('device_paused');
        throw http.ClientException('offline');
      });
      final AuthSession s = session(c);
      await expectLater(s.refresh(), throwsA(isA<DevicePausedException>()));
      expect(await store.load(), isNotNull);
    });

    test('only a literal true counts: "true", 1 or a nested object is no order', () async {
      int erased = 0;
      AuthSession.eraseOnOrder = () async => erased++;
      for (final Object? v in <Object?>['true', 1, <String, Object>{'a': 1}, null, false]) {
        final AuthSession s = session(server((_) async => _json(401, <String, dynamic>{'error': 'device_paused', 'wipe': v})));
        await expectLater(s.refresh(), throwsA(isA<DevicePausedException>()));
      }
      expect(erased, 0);
    });

    test('an order on a 200 (a session that worked) or on any other error is ignored', () async {
      int erased = 0;
      AuthSession.eraseOnOrder = () async => erased++;
      final AuthSession ok = session(server((_) async => _json(200, <String, dynamic>{
            'sessionToken': _tokenExp(_t0.add(const Duration(hours: 1))), 'wipe': true})));
      await ok.refresh();
      final AuthSession bad = session(server((_) async => _json(401, <String, dynamic>{'error': 'invalid_device_credential', 'wipe': true})));
      await expectLater(bad.refresh(), throwsA(isA<DeviceRevokedException>()));
      final AuthSession pin = session(server((_) async => _json(403, <String, dynamic>{'error': 'pin_required', 'wipe': true})));
      await expectLater(pin.refresh(), throwsA(isA<ForbiddenException>()));
      expect(erased, 0, reason: 'only a lost phone that proved its credential is ever told');
    });

    test('a child\'s tablet session is never wired to erase (the shell sets the hook only for a grown-up)', () {
      expect(AuthSession.eraseOnOrder, isNull);
    });
  });
}
