// OLIVE BRANCH — the live screens on the REAL session. Audit G-02 / G-06 /
// C-03 / G-13 / G-14 (widget level; the unit half is auth_session_test.dart).
//
// Every test here runs with AuthSession.devLoginEnabled == false (the
// production default) and a device-credential AuthSession installed: the
// mock server answers ONLY POST /v1/auth/session/refresh for authentication —
// POST /v1/auth/dev-login is a hard failure — so a screen that still reached
// for dev-login (the bug) would fail these tests the way production failed.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/guardian_home_live.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/guardian_setup.dart';
import 'package:olive_client/push_channel.dart';

class _MemStore implements SecureKeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

class _NoPush extends PushChannel {
  _NoPush() : super(OliveApi('http://unused', 'unused'));
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {}
}

String tokenExp(DateTime exp, String tag) {
  final p = base64Url.encode(utf8.encode(jsonEncode({'exp': exp.millisecondsSinceEpoch, 'tag': tag})));
  return '${p.replaceAll('=', '')}.mac';
}

http.Response json(int status, Map<String, dynamic> body) => http.Response(jsonEncode(body), status);

typedef MockHandler = FutureOr<http.Response> Function(http.Request req);

void main() {
  late _MemStore storage;
  late DeviceIdentityStore store;
  late List<String> hits;
  late int signedOut;

  setUp(() {
    storage = _MemStore();
    store = DeviceIdentityStore(storage: storage);
    hits = [];
    signedOut = 0;
    AuthSession.use(null);
    AuthSession.devLoginEnabled = false;
  });
  tearDown(() {
    AuthSession.use(null);
    AuthSession.devLoginEnabled = true;
  });

  /// A paired device whose stored session token ALREADY LAPSED an hour ago —
  /// the state every device was in after its first hour before this change.
  DeviceIdentity lapsed(String role, String targetId) => DeviceIdentity(
      sessionToken: tokenExp(DateTime.now().subtract(const Duration(hours: 1)), 'old'),
      deviceId: 'dev-1', role: role, targetId: targetId, deviceCredential: 'cred');

  MockClient server({required String role, Map<String, MockHandler> routes = const {}}) {
    final fresh = tokenExp(DateTime.now().add(const Duration(hours: 1)), 'fresh');
    return MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      if (req.url.path == '/v1/auth/dev-login') {
        fail('dev-login must never be called on the production session path');
      }
      if (req.url.path == '/v1/auth/session/refresh') {
        return json(200, {'sessionToken': fresh, 'expiresAt': 1, 'role': role});
      }
      // Every other route must carry the REFRESHED bearer, never the lapsed one.
      if (req.headers['authorization'] != 'Bearer $fresh') {
        return json(401, {'error': 'expired'});
      }
      final h = routes[req.url.path];
      if (h != null) return h(req);
      return json(404, {'error': 'not_found'});
    });
  }

  group('child — LiveChildHomeScreen on a paired device', () {
    Map<String, MockHandler> childRoutes() => {
      '/v1/me': (_) => json(200, {'displayName': 'Ivy'}),
      '/v1/children/child-9/inbox': (_) => json(200, {'entries': <Object>[]}),
      '/v1/children/child-9/now': (_) => json(200, {
        'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
        'sleepsUntilHandover': 3}),
    };

    testWidgets('loads with the device credential alone — refreshes a lapsed session, '
        'never calls dev-login', (t) async {
      final client = server(role: 'child', routes: childRoutes());
      AuthSession.use(AuthSession.device(baseUrl: 'http://api.test',
          identity: lapsed('child', 'child-9'), store: store, client: client));
      await t.pumpWidget(MaterialApp(home: LiveChildHomeScreen(
          baseUrl: 'http://api.test', childId: 'child-9', httpClient: client,
          pushChannel: _NoPush())));
      await t.pumpAndSettle();
      expect(find.text('Hi, Ivy'), findsOneWidget);
      expect(hits.where((h) => h.endsWith('/v1/auth/dev-login')), isEmpty);
      expect(hits.where((h) => h.endsWith('/v1/auth/session/refresh')), hasLength(1));
    });

    testWidgets('a revoked device: the child sees a plain sentence — never "401: '
        'device_revoked" — and the stored identity is cleared', (t) async {
      await store.save(lapsed('child', 'child-9'));
      final client = MockClient((req) async {
        hits.add(req.url.path);
        return json(401, {'error': 'device_revoked'});
      });
      AuthSession.use(AuthSession.device(baseUrl: 'http://api.test',
          identity: lapsed('child', 'child-9'), store: store, client: client,
          onSignedOut: () => signedOut++));
      await t.pumpWidget(MaterialApp(home: LiveChildHomeScreen(
          baseUrl: 'http://api.test', childId: 'child-9', httpClient: client,
          pushChannel: _NoPush())));
      await t.pumpAndSettle();
      // Offline-first: the child sees PICTURES (a cloud-off picture and a
      // refresh button), never a server sentence, a status code or a reason.
      expect(find.byKey(const Key('childOfflineIcon')), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(find.textContaining('device_revoked'), findsNothing);
      expect(find.textContaining('401'), findsNothing);
      expect(await store.load(), isNull);
      expect(signedOut, 1);
    });

    testWidgets('not signed in at all (no session, dev off): fails closed with a plain '
        'sentence and makes no request', (t) async {
      final client = MockClient((req) async { hits.add(req.url.path); return json(200, {}); });
      await t.pumpWidget(MaterialApp(home: LiveChildHomeScreen(
          baseUrl: 'http://api.test', childId: 'child-9', httpClient: client,
          pushChannel: _NoPush())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childOfflineIcon')), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(find.textContaining('not_signed_in'), findsNothing);
      expect(hits, isEmpty);
    });
  });

  group('guardian — LiveGuardianHomeScreen on a paired device', () {
    testWidgets('loads on the refreshed device session, never dev-login', (t) async {
      final client = server(role: 'guardian', routes: {
        '/v1/children/child-9/now': (_) => json(200, {
          'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
          'sleepsUntilHandover': null}),
        '/v1/children/child-9/ribbon': (_) => json(200, {
          'childName': 'Ivy', 'dayParts': <Object>[], 'actorWindows': <Object>[]}),
      });
      AuthSession.use(AuthSession.device(baseUrl: 'http://api.test',
          identity: lapsed('guardian', 'g-1'), store: store, client: client));
      await t.pumpWidget(MaterialApp(home: LiveGuardianHomeScreen(
          baseUrl: 'http://api.test', guardianId: 'g-1', childId: 'child-9', httpClient: client)));
      await t.pumpAndSettle();
      expect(hits.where((h) => h.endsWith('/v1/auth/dev-login')), isEmpty);
      expect(hits.any((h) => h.endsWith('/now')), isTrue);
      expect(find.textContaining('device_revoked'), findsNothing);
    });
  });

  group('sign out — GuardianMoreScreen', () {
    testWidgets('revokes the device server-side, clears the stored identity, hands control to '
        'the shell (onSignedOut), and leaves the screen', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final id = DeviceIdentity(
          sessionToken: tokenExp(DateTime.now().add(const Duration(hours: 1)), 'live'),
          deviceId: 'dev-1', role: 'guardian', targetId: 'dad-1', deviceCredential: 'cred');
      await store.save(id);
      final client = MockClient((req) async {
        hits.add('${req.method} ${req.url.path}');
        if (req.url.path == '/v1/auth/session/sign-out') {
          expect(req.headers['authorization'], 'Bearer ${id.sessionToken}');
          return json(200, {'ok': true, 'revoked': true});
        }
        return json(404, {'error': 'not_found'});
      });
      AuthSession.use(AuthSession.device(baseUrl: 'http://api.test', identity: id, store: store,
          client: client, onSignedOut: () => signedOut++));
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => GuardianMoreScreen(childName: 'Ivy', childAge: 9,
                      baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
                      availabilityHttpClient: client))),
              child: const Text('root screen')))))));
      await t.tap(find.text('root screen'));
      await t.pumpAndSettle();
      final tile = find.text('Sign out');
      await t.ensureVisible(tile);
      await t.pumpAndSettle();
      await t.tap(tile);
      await t.pumpAndSettle();

      expect(hits, contains('POST /v1/auth/session/sign-out'));
      expect(await store.load(), isNull, reason: 'secure storage wiped');
      expect(storage.data, isEmpty);
      expect(signedOut, 1);
      expect(AuthSession.current, isNull);
      expect(find.byType(GuardianMoreScreen), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('GuardianSetupScreen — changing an existing PIN needs the current PIN (G-13)', () {
    Future<void> pump(WidgetTester t, {
      required Future<bool> Function() check,
      Future<void> Function(String)? first,
      required Future<void> Function(String, String) change,
    }) async {
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: GuardianSetupScreen(
          setGuardianPin: first ?? (_) async {}, checkExistingPin: check, changeGuardianPin: change)));
      await t.pumpAndSettle();
    }

    testWidgets('no PIN yet: no Current PIN field, the first PIN goes through setGuardianPin', (t) async {
      String? firstPin;
      await pump(t, check: () async => false, first: (p) async => firstPin = p,
          change: (c, n) async => fail('must not be called for a first PIN'));
      expect(find.text('Current PIN'), findsNothing);
      await t.enterText(find.widgetWithText(TextField, 'New PIN'), '4821');
      await t.enterText(find.widgetWithText(TextField, 'Confirm PIN'), '4821');
      await t.tap(find.text('Save PIN'));
      await t.pumpAndSettle();
      expect(firstPin, '4821');
    });

    testWidgets('a PIN exists: the Current PIN field appears and the change carries both PINs', (t) async {
      (String, String)? sent;
      await pump(t, check: () async => true, first: (_) async => fail('must not set without proof'),
          change: (c, n) async => sent = (c, n));
      expect(find.text('Current PIN'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Current PIN'), '1357');
      await t.enterText(find.widgetWithText(TextField, 'New PIN'), '9753');
      await t.enterText(find.widgetWithText(TextField, 'Confirm PIN'), '9753');
      await t.tap(find.text('Save PIN'));
      await t.pumpAndSettle();
      expect(sent, ('1357', '9753'));
    });

    testWidgets('leaving Current PIN empty is refused locally, before any request', (t) async {
      await pump(t, check: () async => true, change: (c, n) async => fail('no request expected'));
      await t.enterText(find.widgetWithText(TextField, 'New PIN'), '9753');
      await t.enterText(find.widgetWithText(TextField, 'Confirm PIN'), '9753');
      await t.tap(find.text('Save PIN'));
      await t.pumpAndSettle();
      expect(find.text('Enter your current PIN.'), findsOneWidget);
    });

    testWidgets('a wrong current PIN shows a plain sentence, not the raw code', (t) async {
      await pump(t, check: () async => true,
          change: (c, n) async => throw ForbiddenException('pin_incorrect'));
      await t.enterText(find.widgetWithText(TextField, 'Current PIN'), '0000');
      await t.enterText(find.widgetWithText(TextField, 'New PIN'), '9753');
      await t.enterText(find.widgetWithText(TextField, 'Confirm PIN'), '9753');
      await t.tap(find.text('Save PIN'));
      await t.pumpAndSettle();
      expect(find.text('That is not your current PIN.'), findsOneWidget);
      expect(find.textContaining('pin_incorrect'), findsNothing);
    });

    testWidgets('the server says a PIN exists though we did not know: the field appears', (t) async {
      await pump(t, check: () async => false,
          first: (_) async => throw ForbiddenException('current_pin_required'),
          change: (c, n) async {});
      expect(find.text('Current PIN'), findsNothing);
      await t.enterText(find.widgetWithText(TextField, 'New PIN'), '9753');
      await t.enterText(find.widgetWithText(TextField, 'Confirm PIN'), '9753');
      await t.tap(find.text('Save PIN'));
      await t.pumpAndSettle();
      expect(find.text('Current PIN'), findsOneWidget);
      expect(find.text('Enter your current PIN to change it.'), findsOneWidget);
    });
  });
}
