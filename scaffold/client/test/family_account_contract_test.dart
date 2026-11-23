// OLIVE BRANCH — the family account against the REAL server routes. MASTERFILE section 8.5.13.
//
// The server's own route-drift test (packages/api/test/contract.test.mjs) fails when a server path has no Dart
// constant. This is the other half: it reads server/routes.mjs and packages/db/src/pool.ts as text and fails when the
// CLIENT drifts from what the server registers and answers:
//
//   * every call the account flow makes is a registered route, with the method the client uses;
//   * a route that takes no session is called with none, and one that needs a session is called with a Bearer token;
//   * the body the client sends is made only of keys the real handler reads, and includes all it needs;
//   * every error reason a route can answer with has a sentence in family_account_logic.dart (a new server answer
//     cannot reach a grown-up as a bare code);
//   * the limits (invite-code length, name length, the age ceiling), the invitable roles, the invite states and the
//     fields the client reads from a child or an invite are the server's own;
//   * nothing child-side can reach the account screens, and nothing in them logs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/family_account_logic.dart';

import 'support/real_routes.dart';

const String _id = '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5f';
const String _base = 'https://olive.test';

/// One request the client made, as the server would see it.
class _Seen {
  _Seen(this.method, this.path, this.auth, this.body);
  final String method, path;
  final bool auth;
  final Map<String, dynamic> body;
}

void main() {
  final List<RealRoute> routes = loadRealRoutes();

  RealRoute route(String method, String path) {
    final RealRoute? r = findRoute(routes, method, path);
    expect(r, isNotNull, reason: 'server/routes.mjs registers no $method $path');
    return r!;
  }

  group('the routes the account flow calls exist, with the method and the session rule the client assumes', () {
    // method, path constant, takes no session
    final List<(String, String, bool)> table = <(String, String, bool)>[
      ('POST', OliveApi.authSignup, true),
      ('POST', OliveApi.sessionRefreshPath, true),
      ('POST', OliveApi.sessionSignOutPath, false),
      ('GET', OliveApi.mePath, false),
      ('POST', OliveApi.guardianPinPath, false),
      ('GET', OliveApi.meChildren, false),
      ('POST', OliveApi.children, false),
      ('POST', OliveApi.guardianships, false),
      ('GET', OliveApi.childGuardianInvites, false),
      ('GET', OliveApi.guardianInvite, true),
      ('POST', OliveApi.guardianInviteAccept, true),
      ('POST', OliveApi.guardianInviteBootstrap, true),
      ('POST', OliveApi.guardianInviteClaim, false),
      ('POST', OliveApi.guardianInviteConfirm, false),
      ('POST', OliveApi.guardianInviteDecline, false),
      ('POST', OliveApi.guardianInviteRevoke, false),
      ('POST', OliveApi.devicePairingRedeem, true),
    ];
    for (final (String method, String path, bool open) in table) {
      test('$method $path ${open ? '(no session)' : '(signed in)'}', () {
        final RealRoute r = route(method, path);
        expect(r.noSession, open, reason: open ? 'the server wants a session here' : 'the server takes no session here');
      });
    }
  });

  group('the body the client sends is what the real handler reads', () {
    final List<_Seen> seen = <_Seen>[];
    final http.Client rec = MockClient((http.Request r) async {
      seen.add(_Seen(r.method, r.url.path, r.headers.containsKey('authorization'),
          r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>));
      // A reply shaped well enough for every client function to finish.
      return http.Response(
          jsonEncode(<String, Object>{
            'token': 't.m', 'userId': _id, 'deviceId': _id, 'deviceCredential': 'c', 'child': <String, Object>{'id': _id},
            'children': <Object>[], 'invites': <Object>[], 'invite': <String, Object>{'id': _id}, 'ok': true,
          }),
          200);
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
      expect(s.body.keys.toSet().difference(r.bodyKeys), isEmpty,
          reason: '${r.path}: the client sends keys the server never reads');
      expect(r.bodyKeys.difference(optional).difference(s.body.keys.toSet()), isEmpty,
          reason: '${r.path}: the server needs keys the client does not send');
    }

    test('sign-up', () => check('POST', OliveApi.authSignup, () => signUpWithAllowance(_base,
        allowanceToken: 'a' * 24, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821', deviceLabel: 'This phone', client: rec)));
    test('add a child', () => check('POST', OliveApi.children, () => createChild(_base, 't',
        displayName: 'Ivy', birthDate: '2019-03-04', homeTz: 'America/Chicago', pin: '4821', client: rec)));
    test('list children', () => check('GET', OliveApi.meChildren, () => fetchMyChildren(_base, 't', client: rec)));
    test('list my invites', () => check('GET', OliveApi.childGuardianInvites,
        () => fetchGuardianInvitesForChild(_base, _id, 't', client: rec)));
    test('make an invite', () => check('POST', OliveApi.guardianships, () => OliveApi(_base, 't', client: rec)
        .createGuardianInvite(_id, role: 'guardian', label: 'Mama', invitedEmail: 'a@example.com', pin: '4821')));
    test('look up an invite', () => check('GET', OliveApi.guardianInvite, () => fetchGuardianInvite(_base, _id, client: rec)));
    test('open an invite', () => check('POST', OliveApi.guardianInviteAccept, () => acceptGuardianInvite(_base, _id, client: rec)));
    test('make an account from an invite', () => check('POST', OliveApi.guardianInviteBootstrap,
        () => bootstrapGuardianInvite(_base, _id, 'Robin', enrol: true, client: rec)));
    test('claim with an existing account', () => check('POST', OliveApi.guardianInviteClaim,
        () => claimGuardianInvite(_base, _id, 't', client: rec)));
    test('the inviter says yes', () => check('POST', OliveApi.guardianInviteConfirm,
        () => confirmGuardianInvite(_base, _id, 't', '4821', client: rec)));
    test('the inviter turns them away', () => check('POST', OliveApi.guardianInviteDecline,
        () => declineGuardianInvite(_base, _id, 't', client: rec)));
    test('the inviter cancels', () => check('POST', OliveApi.guardianInviteRevoke,
        () => revokeGuardianInvite(_base, _id, 't', client: rec)));
    test('first PIN', () => check('POST', OliveApi.guardianPinPath,
        () => OliveApi(_base, 't', client: rec).setGuardianPin('4821'), optional: <String>{'currentPin', 'assertion'}));
  });

  group('every answer a route can give has words', () {
    test('no reason in the account routes is missing from family_account_logic.dart', () {
      final List<String> paths = <String>[
        OliveApi.authSignup, OliveApi.children, OliveApi.meChildren, OliveApi.guardianships, OliveApi.childGuardianInvites,
        OliveApi.guardianInvite, OliveApi.guardianInviteAccept, OliveApi.guardianInviteBootstrap,
        OliveApi.guardianInviteClaim, OliveApi.guardianInviteConfirm, OliveApi.guardianInviteDecline,
        OliveApi.guardianInviteRevoke,
      ];
      final Set<String> reasons = <String>{};
      for (final RealRoute r in routes) {
        if (paths.contains(r.path)) reasons.addAll(r.reasons);
      }
      expect(reasons.length, greaterThan(25), reason: 'the parser should have found the reasons');
      expect(reasons.difference(kKnownServerReasons), isEmpty,
          reason: 'add a sentence for these in problemFor and list them in kKnownServerReasons');
    });

    test('the session answers the account flow can meet are worded too', () {
      final String src = File('../server/routes.mjs').readAsStringSync();
      for (final String code in <String>['device_revoked', 'invalid_device_credential', 'account_deactivated']) {
        expect(src, contains(code));
        expect(kKnownServerReasons, contains(code));
      }
      expect(File('../server/index.mjs').readAsStringSync(), contains("'rate_limited'"));
      expect(kKnownServerReasons, contains('rate_limited'));
    });
  });

  group('the limits and vocabularies are the server\'s own', () {
    test('invite code length, name lengths and the age ceiling', () {
      final String routesSrc = File('../server/routes.mjs').readAsStringSync();
      expect(routesSrc, contains('token.length < $kAllowanceCodeMin || token.length > $kAllowanceCodeMax'));
      expect(routesSrc, contains('cleanName(b.displayName, $kAdultNameMax)'));
      expect(routesSrc, contains('cleanName(b.displayName, $kChildNameMax)'));
      final String input = File('../server/identity_input.mjs').readAsStringSync();
      expect(input, contains('MAX_NAME_CHARS = $kAdultNameMax'));
      expect(input, contains('MAX_CHILD_AGE_YEARS = $kMaxChildAgeYears'));
    });

    test('the roles an invite may carry', () {
      expect(kInvitableRoles.toSet(), poolConstList('INVITABLE_ROLES').toSet());
    });

    test('the invite states, and the fields read from a child and an invite', () {
      final String pool = File('../packages/db/src/pool.ts').readAsStringSync();
      final RegExpMatch m = RegExp(r'export type InviteStatus =([^;]+);').firstMatch(pool)!;
      final Set<String> wire = <String>{for (final RegExpMatch q in RegExp(r"'([a-z_]+)'").allMatches(m.group(1)!)) q.group(1)!};
      for (final String w in wire) {
        expect(inviteStateFromWire(w), isNot(InviteState.unknown), reason: 'the client does not know the state "$w"');
      }
      expect(poolInterfaceFields('OwnChild'), containsAll(<String>['id', 'displayName', 'birthDate', 'role']));
      expect(poolInterfaceFields('InviteListing'),
          containsAll(<String>['id', 'role', 'label', 'invitedEmail', 'status', 'expiresAt', 'claimantName']));
      expect(poolInterfaceFields('GuardianInvite'),
          containsAll(<String>['id', 'role', 'label', 'invitedEmail', 'expiresAt', 'acceptedAt', 'revokedAt']));
    });

    test('what sign-up and joining hand back is what the client reads', () {
      String block(String method, String path) => route(method, path).source;
      for (final String k in <String>['token', 'userId', 'deviceId', 'deviceCredential']) {
        expect(block('POST', OliveApi.authSignup), contains(k), reason: 'sign-up no longer returns $k');
        expect(block('POST', OliveApi.guardianInviteBootstrap), contains(k), reason: 'bootstrap no longer returns $k');
      }
      expect(block('POST', OliveApi.children), contains('child:'));
      expect(block('POST', OliveApi.guardianships), contains('invite:'));
      expect(block('GET', OliveApi.childGuardianInvites), contains('invites:'));
      expect(block('GET', OliveApi.meChildren), contains('children:'));
      expect(block('POST', OliveApi.sessionRefreshPath), contains('sessionToken'));
    });
  });

  group('it stays on a grown-up\'s phone and stays quiet', () {
    final List<File> lib = Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
    String name(File f) => f.path.replaceAll('\\', '/').split('/').last;

    test('only the grown-up shell imports the account screens', () {
      final Set<String> importers = <String>{
        for (final File f in lib)
          if (RegExp(r"import 'family_account_(screens|entry|service)\.dart'").hasMatch(f.readAsStringSync())) name(f),
      };
      expect(importers.difference(<String>{
        'family_account_screens.dart', 'family_account_entry.dart', 'family_account_service.dart', 'guardian_more.dart',
        'guardian_boot.dart',
      }), isEmpty);
      for (final String n in importers) {
        expect(n, isNot(startsWith('child_')));
        expect(n, isNot(contains('kiosk')));
        expect(n, isNot(contains('onboarding')));
        expect(n, isNot(startsWith('main_')));
      }
    });

    test('guardian_boot opens it only through the guardian controller', () {
      final String boot = File('lib/guardian_boot.dart').readAsStringSync();
      expect(boot, contains('onAccount: _openAccount'));
      expect(File('lib/main_live.dart').readAsStringSync(), isNot(contains('family_account')));
    });

    test('nothing in the account files prints, and nothing holds a PIN beyond a call', () {
      for (final File f in lib.where((File f) => name(f).startsWith('family_account_'))) {
        final String src = f.readAsStringSync();
        expect(RegExp(r'\b(print|debugPrint|log)\(').hasMatch(src), isFalse, reason: '${name(f)} prints');
        expect(src, isNot(contains('SharedPreferences')), reason: name(f));
      }
      final String service = File('lib/family_account_service.dart').readAsStringSync();
      // Only the sign-in key is written to secure storage, and only through DeviceIdentityStore.
      expect(RegExp(r"\.write\(").hasMatch(service), isFalse);
      final String store = File('lib/family_account_store.dart').readAsStringSync();
      expect(store, isNot(contains('deviceCredential')));
      expect(store, isNot(contains("'pin'")));
    });

    test('the child side keeps no account words', () {
      for (final File f in lib) {
        final String n = name(f);
        if (!(n.startsWith('child_') || n.contains('kiosk') || n.startsWith('game_') || n.startsWith('uno_'))) continue;
        final String src = f.readAsStringSync();
        expect(src, isNot(contains('Family account')), reason: n);
        expect(src, isNot(contains('invite code')), reason: n);
      }
    });
  });
}
