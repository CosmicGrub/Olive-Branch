// OLIVE BRANCH — the lost or stolen phone or tablet against the REAL server routes. MASTERFILE section 7.23.
//
// Reads server/routes.mjs and packages/db/src/pool.ts as text (the test runs in the client directory; the server is a
// sibling) and fails when the CLIENT drifts from what the server registers and answers:
//
//   * every call the flow makes is a registered route, with the method the client uses;
//   * a route that takes no session is called with none; one that needs a session is called with a Bearer token;
//   * the body the client sends is made only of keys the real handler reads, and includes all it needs;
//   * every error reason these routes (and the db functions behind them) can answer with has a sentence;
//   * the 3 day notice the screens say is the server's own;
//   * nothing child-side can reach these screens, nothing in them logs or stores a PIN.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/lost_device_logic.dart';

import 'support/real_routes.dart';

const String _id = '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5f';
const String _base = 'https://olive.test';

class _Seen {
  _Seen(this.method, this.path, this.auth, this.body);
  final String method, path;
  final bool auth;
  final Map<String, dynamic> body;
}

String _read(String relative) => File(relative).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final List<RealRoute> routes = loadRealRoutes();

  RealRoute route(String method, String path) {
    final RealRoute? r = findRoute(routes, method, path);
    expect(r, isNotNull, reason: 'server/routes.mjs registers no $method $path');
    return r!;
  }

  group('the routes the flow calls exist, with the method and the session rule the client assumes', () {
    final List<(String, String, bool)> table = <(String, String, bool)>[
      ('GET', OliveApi.meDevices, false),
      ('POST', OliveApi.meDeviceMarkLost, false),
      ('POST', OliveApi.meDeviceFound, false),
      ('POST', OliveApi.meDeviceConfirmLost, false),
      ('POST', OliveApi.meDeviceOrderWipe, false),
      ('POST', OliveApi.meDeviceCancelWipe, false),
      ('POST', OliveApi.authDeviceWiped, true),
    ];
    for (final (String method, String path, bool open) in table) {
      test('$method $path ${open ? '(no session: the phone\'s own proof)' : '(signed in)'}', () {
        expect(route(method, path).noSession, open);
      });
    }

    test('every route the server registers for devices has a Dart constant (no route the client cannot name)', () {
      final Set<String> mine = table.map(((String, String, bool) t) => t.$2).toSet();
      for (final RealRoute r in routes) {
        if (r.path.startsWith('/v1/me/devices') || r.path == '/v1/auth/device/wiped') {
          expect(mine, contains(r.path), reason: '${r.method} ${r.path} has no client constant');
        }
      }
    });

    test('the one call a lost phone makes for itself sits under /v1/auth/ (per-IP throttle, small body cap)', () {
      expect(OliveApi.authDeviceWiped, startsWith('/v1/auth/'));
    });
  });

  group('the body the client sends is what the real handler reads', () {
    final List<_Seen> seen = <_Seen>[];
    final http.Client rec = MockClient((http.Request r) async {
      seen.add(_Seen(r.method, r.url.path, r.headers.containsKey('authorization'),
          r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>));
      return http.Response(jsonEncode(<String, Object>{'ok': true, 'devices': <Object>[]}), 200);
    });
    setUp(seen.clear);

    Future<void> check(String method, String pathConst, Future<void> Function() call) async {
      seen.clear();
      await call();
      final _Seen s = seen.single;
      final RealRoute r = route(method, pathConst);
      expect(s.method, method);
      expect(s.auth, !r.noSession, reason: '${r.method} ${r.path}: session rule');
      expect(s.body.keys.toSet().difference(r.bodyKeys), isEmpty, reason: '${r.path}: the client sends keys the server never reads');
      expect(r.bodyKeys.difference(s.body.keys.toSet()), isEmpty, reason: '${r.path}: the server needs keys the client does not send');
    }

    test('list', () => check('GET', OliveApi.meDevices, () async {
          await fetchFamilyDevices(_base, 't', client: rec);
        }));
    test('mark as lost', () => check('POST', OliveApi.meDeviceMarkLost, () async {
          await markDeviceLostCall(_base, 't', deviceId: _id, pin: '4821', client: rec);
        }));
    test('I have it', () => check('POST', OliveApi.meDeviceFound, () async {
          await deviceFoundCall(_base, 't', deviceId: _id, incidentId: _id, pin: '4821', client: rec);
        }));
    test('it is lost', () => check('POST', OliveApi.meDeviceConfirmLost, () async {
          await confirmDeviceLostCall(_base, 't', deviceId: _id, incidentId: _id, pin: '4821', client: rec);
        }));
    test('erase it when it connects', () => check('POST', OliveApi.meDeviceOrderWipe, () async {
          await orderDeviceWipeCall(_base, 't', deviceId: _id, pin: '4821', client: rec);
        }));
    test('cancel the erase', () => check('POST', OliveApi.meDeviceCancelWipe, () async {
          await cancelDeviceWipeCall(_base, 't', deviceId: _id, pin: '4821', client: rec);
        }));
    test('the lost phone says it erased', () => check('POST', OliveApi.authDeviceWiped, () async {
          await deviceWipedCall(_base, deviceId: _id, deviceCredential: 'c' * 43, client: rec);
        }));

    test('a device id is put in the path escaped, never raw', () async {
      seen.clear();
      await markDeviceLostCall(_base, 't', deviceId: '../x?y', pin: '4821', client: rec);
      expect(seen.single.path, isNot(contains('..')));
      expect(seen.single.path.split('/').length, OliveApi.meDeviceMarkLost.split('/').length);
    });
  });

  group('every answer the server can give has a sentence', () {
    test('the db functions and the routes together', () {
      final String routesSrc = _read('../server/routes.mjs');
      final String pool = _read('../packages/db/src/pool.ts');
      final int rs = routesSrc.indexOf('// LOST OR STOLEN DEVICE');
      final int re = routesSrc.indexOf('// PARENTAL CONTROLS');
      expect(rs, greaterThan(0));
      expect(re, greaterThan(rs));
      final String routeBlock = routesSrc.substring(rs, re);
      final int ps = pool.indexOf('export type LostFailure');
      final int pe = pool.indexOf('// IDENTITY LANE');
      expect(ps, greaterThan(0));
      expect(pe, greaterThan(ps));
      final String poolBlock = pool.substring(ps, pe);

      final Set<String> reasons = <String>{
        for (final RegExpMatch m in RegExp(r"error: '([a-z_]+)'").allMatches(routeBlock)) m.group(1)!,
        for (final RegExpMatch m in RegExp(r"reason: '([a-z_]+)'").allMatches(poolBlock)) m.group(1)!,
        ..._union(pool, 'LostFailure'),
        'pin_required', 'pin_incorrect', 'pin_locked', 'pin_not_set',
        // the refresh answer a paused phone meets
        'device_paused',
      };
      expect(reasons.length, greaterThan(12), reason: 'the parser should have found the reasons');
      expect(reasons.difference(kLostKnownReasons), isEmpty,
          reason: 'add a sentence for these in lostProblemFor and list them in kLostKnownReasons');
    });
  });

  group('the limits are the server\'s own', () {
    test('the notice the screens say (3 days) and the daily limit', () {
      final String pool = _read('../packages/db/src/pool.ts');
      expect(pool, contains('LOST_NOTICE_MS = 72 * 60 * 60 * 1000'));
      expect(_read('lib/lost_device_logic.dart'), contains('3 days'));
    });

    test('the erase order rides on the refusal of a lost phone, and only after its own credential was proved', () {
      final String routesSrc = _read('../server/routes.mjs');
      expect(routesSrc, contains('result.wipe ? { error: result.reason, wipe: true }'));
      final String pool = _read('../packages/db/src/pool.ts');
      final int i = pool.indexOf('export async function refreshPairedDeviceSession');
      final int cred = pool.indexOf("if (!credentialOk) return { ok: false, reason: 'invalid_device_credential' };", i);
      final int wipe = pool.indexOf('const wipe = cur.wipe_ordered_at != null', i);
      expect(cred, greaterThan(i));
      expect(wipe, greaterThan(cred), reason: 'the instruction must come after the credential check');
      expect(_read('lib/auth_session.dart'), contains("body['wipe'] == true"));
    });

    test('a child\'s tablet can never be erased: the server refuses it and the table says no too', () {
      expect(_read('../packages/db/src/pool.ts'), contains("if (d.role !== 'guardian') return { ok: false, reason: 'not_a_grown_up_phone' };"));
      expect(_read('../db/migrations/0057_lost_device.sql'), contains("(wipe_ordered_at IS NULL OR role = 'guardian')"));
    });
  });

  group('it stays on a grown-up\'s phone and stays quiet', () {
    final List<File> lib = Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
    String name(File f) => f.path.replaceAll('\\', '/').split('/').last;

    test('only the grown-up screens import the lost-device files', () {
      final Set<String> importers = <String>{
        for (final File f in lib)
          if (RegExp(r"import 'lost_device_(screens|service|logic)\.dart'").hasMatch(f.readAsStringSync())) name(f),
      };
      expect(importers.difference(<String>{
        'lost_device_screens.dart', 'lost_device_service.dart', 'lost_device_logic.dart',
        'recovery_paths_screens.dart', 'recovery_paths_service.dart',
      }), isEmpty);
      for (final String n in importers) {
        expect(n, isNot(startsWith('child_')));
        expect(n, isNot(contains('kiosk')));
        expect(n, isNot(startsWith('main_')));
        expect(n, isNot(startsWith('game_')));
      }
    });

    test('the child side keeps no lost-device words', () {
      for (final File f in lib) {
        final String n = name(f);
        if (!(n.startsWith('child_') || n.contains('kiosk') || n.startsWith('game_') || n.startsWith('uno_'))) continue;
        final String src = f.readAsStringSync();
        for (final String w in <String>['Mark as lost', 'marked as lost', 'Lost or stolen', 'Erase it when it connects']) {
          expect(src, isNot(contains(w)), reason: '$n mentions "$w"');
        }
      }
    });

    test('nothing in the lost-device files prints or stores, and a PIN is never a field', () {
      for (final File f in lib.where((File f) => name(f).startsWith('lost_device_'))) {
        final String src = f.readAsStringSync();
        expect(RegExp(r'\b(print|debugPrint|log)\(').hasMatch(src), isFalse, reason: '${name(f)} prints');
        expect(src, isNot(contains('SharedPreferences')), reason: name(f));
        expect(src, isNot(contains('Clipboard')), reason: name(f));
        expect(src, isNot(contains('localDataCatalogue')), reason: name(f));
        expect(src, isNot(contains('.area(')), reason: '${name(f)}: nothing here goes in the ordinary on-device store');
        expect(src, isNot(contains('SecureKeyValueStore')), reason: '${name(f)}: nothing here is written to secure storage');
      }
      final String service = _read('lib/lost_device_service.dart');
      expect(RegExp(r'final String _?pin\b').hasMatch(service), isFalse, reason: 'a PIN is held for one call, never a field');
    });

    test('the erase on this phone is wired once, in the grown-up boot, and reports done only after it ran', () {
      final String boot = _read('lib/guardian_boot.dart');
      expect(boot, contains('AuthSession.eraseOnOrder = _eraseThisPhone;'));
      expect(boot, contains('await LocalServices.current.wipeAll();'));
      expect(_read('lib/main_live.dart'), isNot(contains('eraseOnOrder')), reason: 'a child\'s tablet is never erased');
      final String session = _read('lib/auth_session.dart');
      final int i = session.indexOf('Future<bool> _eraseAndReport');
      final int a = session.indexOf('await erase();', i);
      final int b = session.indexOf('authDeviceWiped', i);
      expect(a, greaterThan(i));
      expect(b, greaterThan(a), reason: 'say "erased" only after erasing');
    });
  });
}

Set<String> _union(String src, String name) {
  final RegExpMatch? m = RegExp('export type $name\\s*=([^;]+);').firstMatch(src);
  if (m == null) throw StateError('pool.ts has no type $name');
  return <String>{for (final RegExpMatch q in RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!)) q.group(1)!};
}
