// OLIVE BRANCH — api_client.dart tests. §7, §20.2.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';

void main() {
  group('OliveApi — real HTTP calls against a mocked transport', () {
    test('fetchMe decodes a 200 response', () async {
      final mock = MockClient((req) async {
        expect(req.url.toString(), 'http://api.test/v1/me');
        expect(req.headers['authorization'], 'Bearer tok-123');
        return http.Response(jsonEncode({'userId': 'u1', 'roleName': 'guardian'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      final body = await api.fetchMe();
      expect(body['userId'], 'u1');
      expect(body['roleName'], 'guardian');
    });

    test('fetchNow substitutes :childId into the path', () async {
      Uri? seen;
      final mock = MockClient((req) async {
        seen = req.url;
        return http.Response(jsonEncode({'childLocalTime': '4:12 PM'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      final body = await api.fetchNow('child-a');
      expect(seen.toString(), 'http://api.test/v1/children/child-a/now');
      expect(body['childLocalTime'], '4:12 PM');
    });

    test('a 403 response throws ApiException carrying the real status and reason', () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'wrong_child'}), 403));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(
        () => api.fetchInbox('someone-elses-child'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.error, 'error', 'wrong_child')),
      );
    });

    test('a 401 with no session throws ApiException(401, no_session)', () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'no_session'}), 401));
      final api = OliveApi('http://api.test', '', client: mock);
      await expectLater(() => api.fetchMe(),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)));
    });
  });

  group('verifyKioskPin — real POST, fails closed on anything but a clean 200/ok:true', () {
    test('a 200 with {ok: true} returns true', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), 'http://api.test/v1/children/child-a/kiosk-pin/verify');
        expect(req.headers['authorization'], 'Bearer tok-123');
        expect(jsonDecode(req.body), {'pin': '5193'});
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      expect(await api.verifyKioskPin('child-a', '5193'), isTrue);
    });

    test('a 200 with {ok: false} (wrong PIN, or every guardian locked out) returns false',
        () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'ok': false}), 200));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      expect(await api.verifyKioskPin('child-a', '0000'), isFalse);
    });

    test('a simulated network exception returns false, never throws', () async {
      final mock = MockClient((req) async {
        throw Exception('simulated network failure');
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(api.verifyKioskPin('child-a', '5193'), completion(isFalse));
    });

    test('a non-2xx response (e.g. 403 not_this_child) returns false, never throws',
        () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'not_this_child'}), 403));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(api.verifyKioskPin('child-a', '5193'), completion(isFalse));
    });

    test('a malformed (non-JSON) 200 body returns false, never throws', () async {
      final mock = MockClient((req) async => http.Response('not json', 200));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(api.verifyKioskPin('child-a', '5193'), completion(isFalse));
    });
  });

  group('setGuardianPin — real POST, real errors (not fail-closed-to-a-bool)', () {
    test('a 200 with {ok: true} completes normally', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), 'http://api.test/v1/me/pin');
        expect(jsonDecode(req.body), {'pin': '5193'});
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(api.setGuardianPin('5193'), completes);
    });

    test('a 400 invalid_pin_format throws ApiException carrying the real reason',
        () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'invalid_pin_format'}), 400));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(
        () => api.setGuardianPin('12'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.error, 'error', 'invalid_pin_format')),
      );
    });

    test('a 403 guardian_session_required (a child session tried this) throws',
        () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'guardian_session_required'}), 403));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(
        () => api.setGuardianPin('5193'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });

  group('captureHomework — real homework OCR capture (§9.1, §20.2b)', () {
    test('posts base64 image bytes and decodes a 200 success body', () async {
      Uri? seenUrl;
      Map<String, dynamic>? sentBody;
      final mock = MockClient((req) async {
        seenUrl = req.url;
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({
          'ok': true,
          'deskewedBy': -3.5,
          'rawText': '12 + 27 = ____',
          'problems': [
            {'text': '12 + 27 = ____', 'hint': 'Count on from the first number.', 'hintRefused': false},
          ],
        }), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      final body = await api.captureHomework('child-a', <int>[1, 2, 3]);

      expect(seenUrl.toString(), 'http://api.test/v1/children/child-a/homework/capture');
      expect(sentBody!['image'], base64Encode(<int>[1, 2, 3]));
      expect(body['ok'], true);
      final problems = (body['problems'] as List)
          .map((p) => HomeworkProblemResult.fromJson(p as Map<String, dynamic>))
          .toList();
      expect(problems.single.text, '12 + 27 = ____');
      expect(problems.single.hintRefused, false);
    });

    test('a 422 quality-gate refusal decodes as a normal body, not an exception', () async {
      final mock = MockClient((req) async => http.Response(jsonEncode({
        'ok': false, 'reason': 'too_blurred', 'advice': 'Hold still and try again.',
      }), 422));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      final body = await api.captureHomework('child-a', <int>[1, 2, 3]);
      expect(body['ok'], false);
      expect(body['reason'], 'too_blurred');
      expect(body['advice'], 'Hold still and try again.');
    });

    test('a genuinely unexpected status (500) still throws ApiException', () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'internal'}), 500));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(
        () => api.captureHomework('child-a', <int>[1, 2, 3]),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('OliveApi — device-token registration (§11)', () {
    test('registerDeviceToken POSTs {platform, token} and returns the real id',
        () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), 'http://api.test/v1/me/device-tokens');
        expect(req.headers['authorization'], 'Bearer tok-123');
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(sent['platform'], 'android');
        expect(sent['token'], 'fcm-tok-1');
        return http.Response(jsonEncode({'id': 'dt-1'}), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      final id = await api.registerDeviceToken(platform: 'android', token: 'fcm-tok-1');
      expect(id, 'dt-1');
    });

    test('unregisterDeviceToken DELETEs {token} and returns the real deleted flag',
        () async {
      final mock = MockClient((req) async {
        expect(req.method, 'DELETE');
        expect(req.url.toString(), 'http://api.test/v1/me/device-tokens');
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(sent['token'], 'fcm-tok-1');
        return http.Response(jsonEncode({'deleted': true}), 200);
      });
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      final deleted = await api.unregisterDeviceToken('fcm-tok-1');
      expect(deleted, isTrue);
    });

    test('a 400 for an invalid platform throws ApiException', () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'platform_must_be_android_or_ios'}), 400));
      final api = OliveApi('http://api.test', 'tok-123', client: mock);
      await expectLater(
        () => api.registerDeviceToken(platform: 'toaster', token: 'x'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.error, 'error', 'platform_must_be_android_or_ios')),
      );
    });
  });

  group('devLoginFor — the dev-only login shortcut', () {
    test('posts the childId and returns the issued token', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.toString(), 'http://api.test/v1/auth/dev-login');
        final sent = jsonDecode(req.body) as Map<String, dynamic>;
        expect(sent['childId'], 'child-a');
        expect(sent.containsKey('userId'), isFalse);
        return http.Response(jsonEncode({'token': 'issued-token'}), 200);
      });
      final token = await devLoginFor('http://api.test', childId: 'child-a', client: mock);
      expect(token, 'issued-token');
    });

    test('a 404 for an unknown account throws ApiException', () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'child_not_found'}), 404));
      await expectLater(
        () => devLoginFor('http://api.test', childId: 'nope', client: mock),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
