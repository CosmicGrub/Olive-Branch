// OLIVE BRANCH — the recovery paths against the REAL server routes. MASTERFILE section 7.22.
//
// Reads server/routes.mjs and packages/db/src/pool.ts as text (the test runs in the client directory; the server is a
// sibling) and fails when the CLIENT drifts from what the server registers and answers:
//
//   * every call the recovery flow makes is a registered route, with the method the client uses;
//   * a route that takes no session is called with none; one that needs a session is called with a Bearer token;
//   * the body the client sends is made only of keys the real handler reads, and includes all it needs;
//   * every error reason the recovery routes (and the db functions behind them) can answer with has a sentence;
//   * the code lengths and the two waiting periods are the server's own;
//   * nothing child-side can reach the recovery screens, nothing in them logs or stores a PIN or a sheet key.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/recovery_paths_logic.dart';

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

  group('the routes the recovery flow calls exist, with the method and the session rule the client assumes', () {
    final List<(String, String, bool)> table = <(String, String, bool)>[
      ('POST', OliveApi.meRecoverySheet, false),
      ('POST', OliveApi.meRecoverySheetCheck, false),
      ('POST', OliveApi.meRecoveryHelper, false),
      ('POST', OliveApi.meRecoveryHelperRemove, false),
      ('GET', OliveApi.meRecovery, false),
      ('POST', OliveApi.meRecoveryStartFor, false),
      ('POST', OliveApi.meRecoveryCancel, false),
      ('POST', OliveApi.authRecoveryStart, true),
      ('POST', OliveApi.authRecoveryStatus, true),
      ('POST', OliveApi.authRecoveryCancel, true),
      ('POST', OliveApi.authRecoveryFinish, true),
      ('POST', OliveApi.authHelperAccept, true),
      ('POST', OliveApi.authHelperRequests, true),
      ('POST', OliveApi.authHelperAnswer, true),
    ];
    for (final (String method, String path, bool open) in table) {
      test('$method $path ${open ? '(no session)' : '(signed in)'}', () {
        expect(route(method, path).noSession, open);
      });
    }

    test('every route under the recovery prefixes on the server has a Dart constant (no route the client cannot name)', () {
      final Set<String> mine = table.map(((String, String, bool) t) => t.$2).toSet();
      for (final RealRoute r in routes) {
        final bool recovery = r.path.startsWith('/v1/me/recovery') ||
            r.path.startsWith('/v1/auth/recovery') ||
            r.path.startsWith('/v1/auth/helper');
        if (recovery) expect(mine, contains(r.path), reason: '${r.method} ${r.path} has no client constant');
      }
    });

    test('the helper routes and the new-phone routes sit under /v1/auth/ (the per-IP throttle and the small body cap)', () {
      for (final (String _, String path, bool open) in table) {
        if (open) expect(path, startsWith('/v1/auth/'));
      }
    });
  });

  group('the body the client sends is what the real handler reads', () {
    final List<_Seen> seen = <_Seen>[];
    final http.Client rec = MockClient((http.Request r) async {
      seen.add(_Seen(r.method, r.url.path, r.headers.containsKey('authorization'),
          r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>));
      return http.Response(jsonEncode(<String, Object>{'ok': true, 'token': 't', 'requests': <Object>[]}), 200);
    });
    setUp(seen.clear);

    Future<void> check(String method, String pathConst, Future<void> Function() call,
        {Set<String> optional = const <String>{}}) async {
      seen.clear();
      await call();
      final _Seen s = seen.single;
      final RealRoute r = route(method, pathConst);
      expect(s.method, method);
      expect(s.auth, !r.noSession, reason: '${r.method} ${r.path}: session rule');
      expect(s.body.keys.toSet().difference(r.bodyKeys), isEmpty, reason: '${r.path}: the client sends keys the server never reads');
      expect(r.bodyKeys.difference(optional).difference(s.body.keys.toSet()), isEmpty,
          reason: '${r.path}: the server needs keys the client does not send');
    }

    test('make the sheet', () => check('POST', OliveApi.meRecoverySheet, () async {
          await makeRecoverySheetCall(_base, 't', pin: '4821', client: rec);
        }));
    test('check the sheet', () => check('POST', OliveApi.meRecoverySheetCheck, () async {
          await checkRecoverySheetCall(_base, 't', key: 'K7Q2-M9XD', client: rec);
        }));
    test('name a helper', () => check('POST', OliveApi.meRecoveryHelper, () async {
          await nameRecoveryHelperCall(_base, 't', pin: '4821', label: 'Jo', client: rec);
        }));
    test('remove the helper', () => check('POST', OliveApi.meRecoveryHelperRemove, () async {
          await removeRecoveryHelperCall(_base, 't', pin: '4821', client: rec);
        }));
    test('read the summary', () => check('GET', OliveApi.meRecovery, () async {
          await fetchRecoverySummary(_base, 't', client: rec);
        }));
    test('help another grown-up', () => check('POST', OliveApi.meRecoveryStartFor, () async {
          await startRecoveryForCall(_base, 't', targetUserId: _id, pin: '4821', client: rec);
        }));
    test('stop one', () => check('POST', OliveApi.meRecoveryCancel, () async {
          await stopRecoveryCall(_base, 't', requestId: _id, pin: '4821', client: rec);
        }));
    test('start with the sheet', () => check('POST', OliveApi.authRecoveryStart, () async {
          await startRecoveryWithSheetCall(_base, sheetKey: 'K7Q2', deviceLabel: 'This phone', client: rec);
        }));
    test('how it is going', () => check('POST', OliveApi.authRecoveryStatus, () async {
          await recoveryStatusCall(_base, code: 'K7Q2', client: rec);
        }));
    test('the new phone gives up', () => check('POST', OliveApi.authRecoveryCancel, () async {
          await cancelRecoveryFromNewPhoneCall(_base, code: 'K7Q2', client: rec);
        }));
    test('finish', () => check('POST', OliveApi.authRecoveryFinish, () async {
          await finishRecoveryCall(_base, code: 'K7Q2', pin: '4821', sheetKey: 'K7Q2', newPin: '7391', deviceLabel: 'This phone', client: rec);
        }, optional: <String>{'pin', 'sheetKey', 'newPin', 'deviceLabel'}));
    test('a helper accepts', () => check('POST', OliveApi.authHelperAccept, () async {
          await acceptRecoveryHelperInviteCall(_base, code: 'K7Q2', client: rec);
        }));
    test('a helper looks', () => check('POST', OliveApi.authHelperRequests, () async {
          await helperRequestsCall(_base, helperKey: 'k' * 30, client: rec);
        }));
    test('a helper answers', () => check('POST', OliveApi.authHelperAnswer, () async {
          await helperAnswerCall(_base, helperKey: 'k' * 30, requestId: _id, yes: true, client: rec);
        }));
  });

  group('every answer a route can give has words', () {
    test('no reason in the recovery routes or their database functions is missing from recovery_paths_logic.dart', () {
      final String routesSrc = _read('../server/routes.mjs');
      final String pool = _read('../packages/db/src/pool.ts');
      final int rs = routesSrc.indexOf('// RECOVERY PATHS (migration 0055)');
      final int re = routesSrc.indexOf('// GET /v1/me/children', rs);
      expect(rs, greaterThan(0));
      expect(re, greaterThan(rs));
      final String routeBlock = routesSrc.substring(rs, re);
      final int ps = pool.indexOf('//  RECOVERY PATHS (migration 0055)');
      expect(ps, greaterThan(0));
      final String poolBlock = pool.substring(ps);

      final Set<String> reasons = <String>{
        for (final RegExpMatch m in RegExp(r"error: '([a-z_]+)'").allMatches(routeBlock)) m.group(1)!,
        for (final RegExpMatch m in RegExp(r"reason: '([a-z_]+)'").allMatches(poolBlock)) m.group(1)!,
        for (final RegExpMatch m in RegExp(r"\{ ok: false, reason: '([a-z_]+)'").allMatches(poolBlock)) m.group(1)!,
        // the two error unions and the status table
        for (final String union in <String>['StartRecoveryError', 'FinishRecoveryError'])
          ..._union(poolBlock, union),
        for (final RegExpMatch t in RegExp(r'const START_STATUS = \{([^}]*)\}').allMatches(routeBlock))
          for (final RegExpMatch m in RegExp(r'([a-z_]+): [0-9]{3}').allMatches(t.group(1)!)) m.group(1)!,
        // the own-PIN step-up the routes share
        'pin_required', 'pin_incorrect', 'pin_locked', 'pin_not_set',
      };
      reasons.removeWhere((String r) => r.isEmpty);
      expect(reasons.length, greaterThan(20), reason: 'the parser should have found the reasons');
      expect(reasons.difference(kRecoveryKnownReasons), isEmpty,
          reason: 'add a sentence for these in recoveryProblemFor and list them in kRecoveryKnownReasons');
    });

    test('the session answers a recovery call can meet are worded too', () {
      for (final String code in <String>['device_revoked', 'invalid_device_credential', 'account_deactivated', 'rate_limited']) {
        expect(kRecoveryKnownReasons, contains(code));
      }
    });
  });

  group('the limits are the server\'s own', () {
    test('code lengths and the groups of four', () {
      final String pool = _read('../packages/db/src/pool.ts');
      expect(pool, contains("const CODE_LENGTH: Record<RecoveryCodeKind, number> = { sheet: ${RecoveryCodeKind.sheet.length}, "
          "request: ${RecoveryCodeKind.request.length}, 'helper-invite': ${RecoveryCodeKind.helperInvite.length} };"));
      expect(pool, contains("const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';"));
      expect(pool, contains(r".match(/.{1,4}/g)!.join('-')"));
    });

    test('the waiting periods the screens say are the ones the server enforces', () {
      final String pool = _read('../packages/db/src/pool.ts');
      expect(pool, contains('RECOVERY_WAIT_SECOND_PARENT_MS = 48 * 3_600_000'));
      expect(pool, contains('RECOVERY_WAIT_SOLE_PARENT_MS = 72 * 3_600_000'));
      final String mig = _read('../db/migrations/0055_recovery_paths.sql');
      expect(mig, contains("ready_at >= created_at + interval '24 hours'"));
      final String screens = _read('lib/recovery_paths_screens.dart');
      expect(screens, contains('Olive waits 3 days'));
    });

    test('the helper name limit', () {
      final String pool = _read('../packages/db/src/pool.ts');
      expect(pool, contains('s.length > $kHelperNameMax'));
    });
  });

  group('it stays on a grown-up\'s phone and stays quiet', () {
    final List<File> lib = Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
    String name(File f) => f.path.replaceAll('\\', '/').split('/').last;

    test('only the grown-up shell imports the recovery screens', () {
      final Set<String> importers = <String>{
        for (final File f in lib)
          if (RegExp(r"import 'recovery_paths_(screens|entry|service|logic)\.dart'|import 'sheet_printer\.dart'").hasMatch(f.readAsStringSync())) name(f),
      };
      expect(importers.difference(<String>{
        'recovery_paths_screens.dart', 'recovery_paths_entry.dart', 'recovery_paths_service.dart', 'recovery_paths_logic.dart',
        'family_account_screens.dart', 'family_account_entry.dart', 'guardian_more.dart', 'guardian_boot.dart',
      }), isEmpty);
      for (final String n in importers) {
        expect(n, isNot(startsWith('child_')));
        expect(n, isNot(contains('kiosk')));
        expect(n, isNot(contains('onboarding')));
        expect(n, isNot(startsWith('main_')));
        expect(n, isNot(startsWith('game_')));
      }
    });

    test('guardian_boot opens it only through the guardian controller; the child entry point never mentions it', () {
      expect(File('lib/guardian_boot.dart').readAsStringSync(), contains('onLostPhone: _openLostPhone'));
      expect(File('lib/main_live.dart').readAsStringSync(), isNot(contains('recovery_paths')));
    });

    test('the child side keeps no recovery words', () {
      for (final File f in lib) {
        final String n = name(f);
        if (!(n.startsWith('child_') || n.contains('kiosk') || n.startsWith('game_') || n.startsWith('uno_'))) continue;
        final String src = f.readAsStringSync();
        for (final String w in <String>['recovery sheet', 'Recovery sheet', 'Lost your phone', 'trusted helper', 'Lost phone safety']) {
          expect(src, isNot(contains(w)), reason: '$n mentions "$w"');
        }
      }
    });

    test('nothing in the recovery files prints, and no key, code or PIN goes to ordinary storage', () {
      for (final File f in lib.where((File f) => name(f).startsWith('recovery_paths_') || name(f) == 'sheet_printer.dart')) {
        final String src = f.readAsStringSync();
        expect(RegExp(r'\b(print|debugPrint|log)\(').hasMatch(src), isFalse, reason: '${name(f)} prints');
        expect(src, isNot(contains('SharedPreferences')), reason: name(f));
        expect(src, isNot(contains('Clipboard')), reason: '${name(f)}: a key or code must not be copied to the clipboard');
        expect(src, isNot(contains('localDataCatalogue')), reason: name(f));
        expect(src, isNot(contains('.area(')), reason: '${name(f)}: nothing here goes in the ordinary on-device store');
      }
      final String service = _read('lib/recovery_paths_service.dart');
      // The only writes are the two secure records.
      expect(RegExp(r'_s\.write\(').allMatches(service).length, 2);
      expect(service, isNot(contains("'pin'")), reason: 'a PIN is never a stored field');
    });

    test('the sheet\'s key is never stored by the service (only shown)', () {
      final String service = _read('lib/recovery_paths_service.dart');
      final int i = service.indexOf('Future<String> makeSheet');
      final int j = service.indexOf('Future<bool> checkSheet');
      expect(service.substring(i, j), isNot(contains('_pending.save')));
      expect(service.substring(i, j), isNot(contains('_helper.save')));
    });
  });
}

Set<String> _union(String src, String name) {
  final RegExpMatch? m = RegExp('export type $name\\s*=([^;]+);').firstMatch(src);
  if (m == null) throw StateError('pool.ts has no type $name');
  return <String>{for (final RegExpMatch q in RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!)) q.group(1)!};
}
