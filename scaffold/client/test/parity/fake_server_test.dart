// OLIVE BRANCH — the parity harness's FakeServer behaves like the prototype's simulated server. No longer
// UNVERIFIED — verified by CI. The server is only trustworthy as a replay target if its own rules are tested.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_server.dart';
import 'virtual_clock.dart';

void main() {
  const String base = 'http://olive.test';
  Future<http.Response> post(http.Client c, String path, Map<String, dynamic> body) =>
      c.post(Uri.parse('$base$path'), headers: <String, String>{'content-type': 'application/json'}, body: jsonEncode(body));
  Map<String, dynamic> j(http.Response r) => jsonDecode(r.body) as Map<String, dynamic>;

  testWidgets('the clock is driven by tester.pump and starts Monday 9 Nov 2026 17:30 in Chicago', (WidgetTester tester) async {
    final VirtualClock clock = VirtualClock(tester);
    expect(clock.herLocal, DateTime(2026, 11, 9, 17, 30));
    await clock.advance(const Duration(hours: 2));
    expect(clock.herLocal, DateTime(2026, 11, 9, 19, 30));
    await clock.advance(const Duration(days: 210));
    expect(clock.nowUtc.difference(DateTime.utc(2026, 11, 9, 23, 30)), const Duration(days: 210, hours: 2));
  });

  testWidgets('five wrong PINs lock the gate for 15 virtual minutes, then it opens; a right PIN resets the count', (WidgetTester tester) async {
    final FakeServer s = FakeServer(VirtualClock(tester));
    final http.Client c = s.clientFor('g');
    final List<String> errors = <String>[];
    for (int i = 0; i < 5; i++) {
      errors.add(j(await post(c, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '0000'}))['error'] as String);
    }
    expect(errors, <String>['pin_incorrect', 'pin_incorrect', 'pin_incorrect', 'pin_incorrect', 'pin_locked']);
    expect(s.pinLockMinutesLeft, 15);
    expect((await post(c, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '2468'})).statusCode, 403, reason: 'a right PIN is refused while locked');
    await tester.pump(const Duration(minutes: 14));
    expect((await post(c, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '2468'})).statusCode, 403);
    await tester.pump(const Duration(minutes: 2));
    expect((await post(c, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '2468'})).statusCode, 200);

    final FakeServer s2 = FakeServer(VirtualClock(tester));
    final http.Client c2 = s2.clientFor('g');
    for (int i = 0; i < 4; i++) {
      await post(c2, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '0000'});
    }
    expect((await post(c2, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '2468'})).statusCode, 200);
    for (int i = 0; i < 4; i++) {
      await post(c2, '/v1/me/verify-controls-pin', <String, dynamic>{'pin': '0000'});
    }
    expect(s2.pinLockMinutesLeft, 0, reason: 'four wrong after a success is not five in a row');
  });

  testWidgets('a pairing code is 6 digits 1 to 9, lives 10 virtual minutes, and a new one revokes the old', (WidgetTester tester) async {
    final FakeServer s = FakeServer(VirtualClock(tester));
    final http.Client g = s.clientFor('g'), k = s.clientFor('k');
    final Map<String, dynamic> a = j(await post(g, '/v1/children/child-1/device-pairing-codes', <String, dynamic>{'pin': '2468'}));
    expect(RegExp(r'^[1-9]{6}$').hasMatch(a['numericCode'] as String), isTrue);
    final Map<String, dynamic> b = j(await post(g, '/v1/children/child-1/device-pairing-codes', <String, dynamic>{'pin': '2468'}));
    expect(j(await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': a['numericCode'], 'role': 'child'}))['error'], 'revoked');
    await tester.pump(const Duration(minutes: 9));
    expect(s.openCode, b['numericCode']);
    await tester.pump(const Duration(minutes: 2));
    expect(s.openCode, isNull);
    expect(j(await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': b['numericCode'], 'role': 'child'}))['error'], 'expired');
  });

  testWidgets('redeem: the right role pairs once; the wrong role is role_mismatch; five wrong codes lock the device for 5 minutes', (WidgetTester tester) async {
    final FakeServer s = FakeServer(VirtualClock(tester));
    final http.Client g = s.clientFor('g'), k = s.clientFor('k');
    final Map<String, dynamic> a = j(await post(g, '/v1/children/child-1/device-pairing-codes', <String, dynamic>{'pin': '2468'}));
    expect(j(await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': a['numericCode'], 'role': 'guardian'}))['error'], 'role_mismatch');
    final http.Response ok = await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': a['numericCode'], 'role': 'child'});
    expect(ok.statusCode, 201);
    expect(j(ok)['role'], 'child');
    expect(j(await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': a['numericCode'], 'role': 'child'}))['error'], 'already_redeemed');
    final List<int> st = <int>[];
    for (int i = 0; i < 6; i++) {
      st.add((await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': '999999', 'role': 'child'})).statusCode);
    }
    expect(st, <int>[404, 404, 404, 404, 404, 429]);
    await tester.pump(const Duration(minutes: 6));
    expect((await post(k, '/v1/device-pairing/redeem', <String, dynamic>{'code': '999999', 'role': 'child'})).statusCode, 404);
  });

  testWidgets('a child device can never make a pairing code', (WidgetTester tester) async {
    final FakeServer s = FakeServer(VirtualClock(tester));
    final http.Response r = await post(s.clientFor('k'), '/v1/children/child-1/device-pairing-codes', <String, dynamic>{'pin': '2468'});
    expect(r.statusCode, 403);
    expect(j(r)['error'], 'forbidden');
  });

  testWidgets('offline throws like a dropped socket; failNext fires once; latency is virtual', (WidgetTester tester) async {
    final FakeServer s = FakeServer(VirtualClock(tester));
    final http.Client k = s.clientFor('k');
    s.setOnline('k', false);
    await expectLater(post(k, '/v1/auth/dev-login', <String, dynamic>{}), throwsA(isA<http.ClientException>()));
    expect(s.log.last.status, 0);
    s.setOnline('k', true);
    s.failNext('k', 503, 'server_unavailable');
    expect((await post(k, '/v1/auth/dev-login', <String, dynamic>{})).statusCode, 503);
    expect((await post(k, '/v1/auth/dev-login', <String, dynamic>{})).statusCode, 200);
    s.latency = const Duration(milliseconds: 350);
    bool done = false;
    unawaited(post(k, '/v1/auth/dev-login', <String, dynamic>{}).then((_) => done = true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, isTrue);
  });

  testWidgets('Messages can never be hidden; another tile can', (WidgetTester tester) async {
    final FakeServer s = FakeServer(VirtualClock(tester));
    final http.Client g = s.clientFor('g');
    Future<http.Response> put(String key, Map<String, dynamic> b) => g.put(
        Uri.parse('$base/v1/children/child-1/activity-overrides/${Uri.encodeComponent(key)}'),
        headers: <String, String>{'content-type': 'application/json'}, body: jsonEncode(b));
    final http.Response bad = await put('tile:messages', <String, dynamic>{'visible': false});
    expect((bad.statusCode, j(bad)['error']), (403, 'cannot_hide_messages'));
    expect((await put('tile:storyteller', <String, dynamic>{'visible': false})).statusCode, 200);
  });
}
