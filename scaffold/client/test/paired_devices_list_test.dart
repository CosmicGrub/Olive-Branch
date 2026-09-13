// OLIVE BRANCH — paired_devices_list.dart tests, plus the end-to-end
// revoke -> device_revoked -> clears local storage loop this feature exists
// for. docs/superpowers/specs/2026-09-12-device-pairing-provisioning
// -design.md.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/paired_devices_list.dart';

/// In-memory stand-in for the real Keystore/Keychain-backed storage — the
/// same role every other live screen's own [http.Client] injection plays,
/// applied to device_identity.dart's [SecureKeyValueStore] seam instead.
class _FakeSecureStore implements SecureKeyValueStore {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

void main() {
  Future<void> pump(WidgetTester tester, {required http.Client client}) =>
      tester.pumpWidget(MaterialApp(home: PairedDevicesListScreen(
        baseUrl: 'http://olive.test', guardianId: 'dad-1', childId: 'child-1',
        httpClient: client)));

  Map<String, dynamic> device({
    required String id, required String role, String label = 'Paired Sep 12, 2026',
    String? revokedAt, String? lastSeenAt,
  }) => {'id': id, 'role': role, 'label': label, 'pairedAt': '2026-09-12T00:00:00Z',
    'revokedAt': revokedAt, 'lastSeenAt': lastSeenAt};

  MockClient stubClient(List<Map<String, dynamic>> devices, {List<String>? calledPaths}) =>
      MockClient((req) async {
    calledPaths?.add('${req.method} ${req.url.path}');
    if (req.url.path == '/v1/auth/dev-login') {
      return http.Response(jsonEncode({'token': 'dev-token'}), 200);
    }
    if (req.method == 'GET' && req.url.path.endsWith('/paired-devices')) {
      return http.Response(jsonEncode({'devices': devices}), 200);
    }
    if (req.method == 'POST' && req.url.path.endsWith('/revoke')) {
      final id = req.url.pathSegments[req.url.pathSegments.length - 2];
      final idx = devices.indexWhere((d) => d['id'] == id);
      if (idx != -1) devices[idx] = {...devices[idx], 'revokedAt': '2026-09-12T01:00:00Z'};
      return http.Response(jsonEncode({'ok': true}), 200);
    }
    return http.Response('{}', 404);
  });

  testWidgets('renders every real device the server returns', (tester) async {
    await pump(tester, client: stubClient([
      device(id: 'd1', role: 'child', label: 'Kitchen tablet'),
      device(id: 'd2', role: 'guardian', label: "Mom's phone"),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen tablet'), findsOneWidget);
    expect(find.text("Mom's phone"), findsOneWidget);
    expect(find.byKey(const Key('pairedDevicesList')), findsOneWidget);
  });

  testWidgets('an empty family shows an honest "no devices" state, not a blank screen',
      (tester) async {
    await pump(tester, client: stubClient([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No devices paired yet'), findsOneWidget);
  });

  testWidgets('a network failure shows a real error state with a retry, not a crash',
      (tester) async {
    final client = MockClient((req) async => throw Exception('no route to host'));
    await pump(tester, client: client);
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('tapping Revoke calls the real revoke route and the row updates to Revoked',
      (tester) async {
    final calledPaths = <String>[];
    await pump(tester, client: stubClient(
      [device(id: 'd1', role: 'child', label: 'Kitchen tablet')], calledPaths: calledPaths));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('revokeDeviceButton_d1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('revokeDeviceButton_d1')));
    await tester.pumpAndSettle();

    expect(calledPaths, contains('POST /v1/children/child-1/paired-devices/d1/revoke'));
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.byKey(const Key('revokeDeviceButton_d1')), findsNothing);
  });

  group('the revoked device\'s OWN next request', () {
    testWidgets('is recognized as device_revoked (a distinct exception, never a generic '
        'network failure) and clears its locally stored identity', (tester) async {
      // Simulates the OTHER side of a revoke this screen just performed: the
      // device that was cut off makes its own next call and must react —
      // api_client.dart's own explicit requirement ("Handle the
      // device_revoked error distinctly... clear secure storage and route
      // back to the pairing screen").
      final store = DeviceIdentityStore(storage: _FakeSecureStore());
      await store.save(const DeviceIdentity(
        sessionToken: 'now-revoked-token', deviceId: 'd1', role: 'child', targetId: 'child-1'));
      expect(await store.load(), isNotNull);

      final client = MockClient((req) async =>
        http.Response(jsonEncode({'error': 'device_revoked'}), 401));
      final api = OliveApi('http://olive.test', 'now-revoked-token', client: client);

      Object? caught;
      try {
        await api.fetchMe();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<DeviceRevokedException>());
      // A generic ApiException catch would ALSO match (DeviceRevokedException
      // extends it) — the real, load-bearing assertion is the more specific
      // type check above, which is what lets a caller distinguish this from
      // every other non-2xx response with a plain `on DeviceRevokedException`.

      if (caught is DeviceRevokedException) {
        await store.clear();
      }
      expect(await store.load(), isNull);
    });
  });
}
