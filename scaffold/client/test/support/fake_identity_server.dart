// An in-memory stand-in for the server's identity routes, for the family-account tests. It answers with the status
// codes and JSON shapes of server/routes.mjs, AND it checks every request against the REAL route table parsed from
// that file (test/support/real_routes.dart): the method and path must be registered, a route that needs a session must
// carry a Bearer token and one that does not must not, and every body key the client sends must be one the real
// handler reads. A client that drifts from the server therefore fails here, in the flow tests, not only in the
// dedicated contract test.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'real_routes.dart';

class FakeUser {
  FakeUser(this.id, this.name, {this.email, this.pin});
  final String id;
  String name;
  String? email;
  String? pin;
  int pinFailures = 0;
}

/// An operator-issued recovery code (migration 0053): one account, five wrong PINs and it is burned.
class FakeRecovery {
  FakeRecovery(this.userId, this.expiresAt);
  final String userId;
  final DateTime expiresAt;
  int wrong = 0;
  bool burned = false, used = false;
}

class FakeChild {
  FakeChild(this.id, this.name, this.birthDate, this.tz);
  final String id, name, birthDate, tz;
}

class FakeInvite {
  FakeInvite({required this.id, required this.childId, required this.invitedBy, required this.email,
      required this.role, required this.label, required this.expiresAt});
  final String id, childId, invitedBy, email, role, label;
  final DateTime expiresAt;
  bool accepted = false, revoked = false, declined = false, confirmed = false, bootstrapped = false;
  String? claimant;
}

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.hasAuth, this.body);
  final String method, path;
  final bool hasAuth;
  final Map<String, dynamic> body;
  @override
  String toString() => '$method $path';
}

String _uuid(int n) => '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

class FakeIdentityServer {
  FakeIdentityServer({DateTime Function()? now}) : now = now ?? DateTime.now {
    client = MockClient(_handle);
  }

  final DateTime Function() now;
  late final MockClient client;
  final List<RealRoute> _real = loadRealRoutes();
  final List<RecordedRequest> requests = <RecordedRequest>[];

  final Set<String> allowances = <String>{};
  final Map<String, FakeRecovery> recoveries = <String, FakeRecovery>{};
  final Map<String, FakeUser> users = <String, FakeUser>{};
  final Map<String, FakeChild> children = <String, FakeChild>{};
  final Map<String, Set<String>> guardianship = <String, Set<String>>{}; // childId -> userIds
  final Map<String, String> roles = <String, String>{}; // 'child|user' -> role
  final Map<String, FakeInvite> invites = <String, FakeInvite>{};
  final Map<String, String> sessions = <String, String>{}; // token -> userId
  final Map<String, ({String userId, String credential, bool revoked})> devices =
      <String, ({String userId, String credential, bool revoked})>{};

  bool signupEnabled = true;
  int _n = 0x100;
  int _tokenSeq = 0;

  /// Next response is this status with this body (once), before any routing. For failure tests.
  http.Response? failNext;
  /// Called before routing; may throw (a socket error) or return a replacement response.
  Future<http.Response?> Function(http.BaseRequest)? interceptor;

  String addAllowance(String token) {
    allowances.add(token);
    return token;
  }

  String addRecoveryCode(String userId, String token, {Duration life = const Duration(hours: 72)}) {
    recoveries[token] = FakeRecovery(userId, now().add(life));
    return token;
  }

  FakeUser addUser(String name, {String? email, String? pin}) {
    final FakeUser u = FakeUser(_uuid(_n++), name, email: email, pin: pin);
    users[u.id] = u;
    return u;
  }

  String sessionFor(String userId, {Duration life = const Duration(hours: 1)}) {
    final String payload = base64Url
        .encode(utf8.encode(jsonEncode(<String, Object>{'exp': now().add(life).millisecondsSinceEpoch, 'n': _tokenSeq++})))
        .replaceAll('=', '');
    final String token = '$payload.mac';
    sessions[token] = userId;
    return token;
  }

  String mintDevice(String userId) {
    final String id = _uuid(_n++);
    devices[id] = (userId: userId, credential: 'cred-${_n++}', revoked: false);
    return id;
  }

  http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});

  RealRoute? _match(String method, String path) {
    for (final RealRoute r in _real) {
      if (r.method != method) continue;
      final RegExp re = RegExp('^${r.path.replaceAllMapped(RegExp(r':\w+'), (Match _) => '[^/]+')}\$');
      if (re.hasMatch(path)) return r;
    }
    return null;
  }

  Future<http.Response> _handle(http.Request req) async {
    final Map<String, dynamic> body = req.body.isEmpty ? <String, dynamic>{} : (jsonDecode(req.body) as Map<String, dynamic>);
    final String? auth = req.headers['authorization'];
    requests.add(RecordedRequest(req.method, req.url.path, auth != null, body));

    // ---- the contract: this request must be one the real server registers ----
    final RealRoute? route = _match(req.method, req.url.path);
    if (route == null) {
      throw StateError('the client called ${req.method} ${req.url.path}, which server/routes.mjs does not register');
    }
    if (route.noSession && auth != null && !req.url.path.startsWith('/v1/auth/session')) {
      throw StateError('${route.method} ${route.path} takes no session, but the client sent an Authorization header');
    }
    if (!route.noSession && auth == null) {
      throw StateError('${route.method} ${route.path} needs a session, but the client sent none');
    }
    final Set<String> extra = body.keys.toSet().difference(route.bodyKeys);
    if (extra.isNotEmpty) {
      throw StateError('${route.method} ${route.path}: the client sent $extra, which the real handler never reads');
    }

    final http.Response? replaced = await interceptor?.call(req);
    if (replaced != null) return replaced;
    final http.Response? f = failNext;
    if (f != null) {
      failNext = null;
      return f;
    }

    final String path = req.url.path;
    // ---- no-session routes ----
    if (path == '/v1/auth/signup') return _signup(body);
    if (path == '/v1/auth/recover') return _recover(body);
    if (path == '/v1/auth/session/refresh') return _refresh(body);
    final RegExpMatch? inv = RegExp(r'^/v1/guardian-invites/([^/]+)(?:/(accept|bootstrap))?$').firstMatch(path);
    if (inv != null && route.noSession) return _inviteOpen(req.method, inv.group(1)!, inv.group(2), body);

    // ---- session routes ----
    final String? uid = sessions[(auth ?? '').replaceFirst('Bearer ', '')];
    if (uid == null) return _json(401, <String, Object>{'error': 'bad_signature'});
    final FakeUser me = users[uid]!;

    if (path == '/v1/me' && req.method == 'GET') {
      return _json(200, <String, Object?>{'userId': uid, 'roleName': 'guardian', 'displayName': me.name, 'hasPin': me.pin != null});
    }
    if (path == '/v1/me/pin') {
      if (me.pin != null) return _json(400, <String, Object>{'error': 'current_pin_required'});
      final Object? pin = body['pin'];
      if (pin is! String || !RegExp(r'^\d{4,8}$').hasMatch(pin)) return _json(400, <String, Object>{'error': 'invalid_pin_format'});
      me.pin = pin;
      return _json(200, <String, Object>{'ok': true});
    }
    if (path == '/v1/auth/session/sign-out') {
      return _json(200, <String, Object>{'ok': true, 'revoked': true});
    }
    if (path == '/v1/me/children') {
      return _json(200, <String, Object>{
        'children': <Map<String, Object>>[
          for (final FakeChild c in children.values)
            if (guardianship[c.id]?.contains(uid) ?? false)
              <String, Object>{'id': c.id, 'displayName': c.name, 'birthDate': c.birthDate, 'homeTz': c.tz,
                  'role': roles['${c.id}|$uid'] ?? 'guardian'},
        ]
      });
    }
    if (path == '/v1/children' && req.method == 'POST') return _createChild(me, body);
    final RegExpMatch? kid = RegExp(r'^/v1/children/([^/]+)/(guardianships|guardian-invites)$').firstMatch(path);
    if (kid != null) return _kidRoute(me, req.method, kid.group(1)!, kid.group(2)!, body);
    final RegExpMatch? act = RegExp(r'^/v1/guardian-invites/([^/]+)/(claim|confirm|decline|revoke)$').firstMatch(path);
    if (act != null) return _inviteAct(me, act.group(1)!, act.group(2)!, body);
    return _json(404, <String, Object>{'error': 'not_found'});
  }

  // ---- sign-up / sessions ----
  http.Response _signup(Map<String, dynamic> b) {
    final Object? t = b['allowanceToken'];
    if (t is! String || t.length < 20 || t.length > 128) return _json(400, <String, Object>{'error': 'allowance_token_required'});
    if (b['displayName'] is! String || (b['displayName'] as String).trim().isEmpty) {
      return _json(400, <String, Object>{'error': 'display_name_required'});
    }
    if (b['homeTz'] is! String || !(b['homeTz'] as String).contains('/')) return _json(400, <String, Object>{'error': 'invalid_home_tz'});
    if (b['pin'] is! String) return _json(400, <String, Object>{'error': 'pin_required'});
    if (!allowances.contains(t)) return _json(403, <String, Object>{'error': 'invalid_allowance'});
    if (!signupEnabled) return _json(403, <String, Object>{'error': 'signup_disabled'});
    if (!RegExp(r'^\d{4,8}$').hasMatch(b['pin'] as String)) return _json(400, <String, Object>{'error': 'invalid_pin_format'});
    allowances.remove(t);
    final FakeUser u = addUser((b['displayName'] as String).trim(), pin: b['pin'] as String);
    final String dev = mintDevice(u.id);
    return _json(201, <String, Object>{
      'token': sessionFor(u.id), 'expiresAt': now().add(const Duration(hours: 1)).toIso8601String(),
      'userId': u.id, 'deviceId': dev, 'deviceCredential': devices[dev]!.credential,
    });
  }

  // POST /v1/auth/recover, as server/routes.mjs + packages/db/src/pool.ts recoverAccount() answer it.
  http.Response _recover(Map<String, dynamic> b) {
    final Object? raw = b['recoveryCode'];
    final String code = raw is String ? raw.replaceAll(RegExp(r'\s+'), '') : '';
    if (code.length < 20 || code.length > 128) return _json(400, <String, Object>{'error': 'recovery_code_required'});
    final Object? pin = b['pin'];
    if (pin is! String || !RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) return _json(400, <String, Object>{'error': 'pin_required'});
    final FakeRecovery? r = recoveries[code];
    if (r == null || r.used || r.burned || !r.expiresAt.isAfter(now())) {
      return _json(403, <String, Object>{'error': 'invalid_recovery'});
    }
    final FakeUser u = users[r.userId]!;
    if (u.pin == null) return _json(403, <String, Object>{'error': 'pin_not_set'});
    if (u.pinFailures >= 5) return _json(403, <String, Object>{'error': 'pin_locked'});
    if (u.pin != pin) {
      u.pinFailures++;
      r.wrong++;
      if (r.wrong >= 5) {
        r.burned = true;
        return _json(423, <String, Object>{'error': 'recovery_locked'});
      }
      return _json(403, <String, Object>{'error': 'pin_incorrect'});
    }
    u.pinFailures = 0;
    r.used = true;
    int out = 0;
    for (final String id in devices.keys.toList()) {
      final ({String userId, String credential, bool revoked}) d = devices[id]!;
      if (d.userId == u.id && !d.revoked) {
        devices[id] = (userId: d.userId, credential: d.credential, revoked: true);
        out++;
      }
    }
    final String dev = mintDevice(u.id);
    return _json(201, <String, Object>{
      'token': sessionFor(u.id), 'expiresAt': now().add(const Duration(hours: 1)).toIso8601String(),
      'userId': u.id, 'deviceId': dev, 'deviceCredential': devices[dev]!.credential, 'devicesSignedOut': out,
    });
  }

  http.Response _refresh(Map<String, dynamic> b) {
    final ({String userId, String credential, bool revoked})? d = devices[b['deviceId']];
    if (d == null || d.credential != b['deviceCredential']) return _json(401, <String, Object>{'error': 'invalid_device_credential'});
    if (d.revoked) return _json(401, <String, Object>{'error': 'device_revoked'});
    return _json(200, <String, Object>{'sessionToken': sessionFor(d.userId), 'deviceId': b['deviceId'] as String, 'role': 'guardian', 'targetId': d.userId});
  }

  // ---- children ----
  http.Response? _pinGate(FakeUser me, Object? pin) {
    if (pin is! String) return _json(400, <String, Object>{'error': 'pin_required'});
    if (me.pinFailures >= 5) return _json(403, <String, Object>{'error': 'pin_locked'});
    if (me.pin == null) return _json(403, <String, Object>{'error': 'pin_not_set'});
    if (me.pin != pin) {
      me.pinFailures++;
      return _json(403, <String, Object>{'error': 'pin_incorrect'});
    }
    me.pinFailures = 0;
    return null;
  }

  http.Response _createChild(FakeUser me, Map<String, dynamic> b) {
    final Object? name = b['displayName'];
    if (name is! String || name.trim().isEmpty) return _json(400, <String, Object>{'error': 'display_name_required'});
    final Object? bd = b['birthDate'];
    final DateTime? d = bd is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(bd) ? DateTime.tryParse(bd) : null;
    if (d == null || d.isAfter(now()) || now().difference(d).inDays >= 18 * 365 + 5) {
      return _json(400, <String, Object>{'error': 'invalid_birth_date'});
    }
    if (b['homeTz'] is! String) return _json(400, <String, Object>{'error': 'invalid_home_tz'});
    final http.Response? gate = _pinGate(me, b['pin']);
    if (gate != null) return gate;
    final int mine = children.values.where((FakeChild c) => guardianship[c.id]?.contains(me.id) ?? false).length;
    if (mine >= 8) return _json(409, <String, Object>{'error': 'too_many_children'});
    final FakeChild c = FakeChild(_uuid(_n++), name.trim(), bd as String, b['homeTz'] as String);
    children[c.id] = c;
    guardianship[c.id] = <String>{me.id};
    roles['${c.id}|${me.id}'] = 'guardian';
    return _json(201, <String, Object>{'child': <String, Object>{'id': c.id, 'displayName': c.name, 'birthDate': c.birthDate, 'homeTz': c.tz, 'role': 'guardian'}});
  }

  http.Response _kidRoute(FakeUser me, String method, String childId, String what, Map<String, dynamic> b) {
    if (!(guardianship[childId]?.contains(me.id) ?? false) || roles['$childId|${me.id}'] != 'guardian') {
      return _json(403, <String, Object>{'error': 'not_a_guardian_of_child'});
    }
    if (what == 'guardian-invites') {
      return _json(200, <String, Object>{
        'invites': <Map<String, Object?>>[
          for (final FakeInvite i in invites.values.where((FakeInvite i) => i.childId == childId && i.invitedBy == me.id))
            <String, Object?>{
              'id': i.id, 'role': i.role, 'label': i.label, 'invitedEmail': i.email, 'status': _status(i),
              'createdAt': now().toIso8601String(), 'expiresAt': i.expiresAt.toIso8601String(),
              'claimantName': i.claimant == null ? null : users[i.claimant]!.name,
            }
        ]
      });
    }
    if (!<String>['guardian', 'step_parent', 'trusted_adult', 'sitter', 'coordinator'].contains(b['role'])) {
      return _json(400, <String, Object>{'error': 'invalid_role'});
    }
    if (b['label'] is! String || (b['label'] as String).trim().isEmpty) return _json(400, <String, Object>{'error': 'label_required'});
    if (b['invitedEmail'] is! String || !(b['invitedEmail'] as String).contains('@')) {
      return _json(400, <String, Object>{'error': 'invited_email_required'});
    }
    final http.Response? gate = _pinGate(me, b['pin']);
    if (gate != null) return gate;
    final FakeInvite i = FakeInvite(
        id: _uuid(_n++), childId: childId, invitedBy: me.id, email: b['invitedEmail'] as String,
        role: b['role'] as String, label: (b['label'] as String).trim(), expiresAt: now().add(const Duration(days: 14)));
    invites[i.id] = i;
    return _json(201, <String, Object>{'ok': true, 'invite': _invite(i)});
  }

  String _status(FakeInvite i) => i.confirmed
      ? 'confirmed'
      : i.declined
          ? 'declined'
          : i.revoked
              ? 'revoked'
              : !i.expiresAt.isAfter(now())
                  ? 'expired'
                  : i.claimant != null
                      ? 'waiting_for_you'
                      : i.accepted
                          ? 'accepted'
                          : 'sent';

  Map<String, Object?> _invite(FakeInvite i) => <String, Object?>{
        'id': i.id, 'childId': i.childId, 'invitedBy': i.invitedBy, 'invitedEmail': i.email, 'role': i.role,
        'label': i.label, 'createdAt': now().toIso8601String(), 'expiresAt': i.expiresAt.toIso8601String(),
        'acceptedAt': i.accepted ? now().toIso8601String() : null, 'revokedAt': i.revoked ? now().toIso8601String() : null,
      };

  // ---- invites: the sessionless half ----
  http.Response _inviteOpen(String method, String id, String? step, Map<String, dynamic> b) {
    final FakeInvite? i = invites[id];
    if (i == null) return _json(404, <String, Object>{'error': 'not_found'});
    if (step == null) return _json(200, <String, Object>{'invite': _invite(i)});
    if (step == 'accept') {
      if (i.revoked || i.declined) return _json(409, <String, Object>{'error': 'revoked'});
      if (i.accepted) return _json(409, <String, Object>{'error': 'already_accepted'});
      if (!i.expiresAt.isAfter(now())) return _json(410, <String, Object>{'error': 'expired'});
      i.accepted = true;
      return _json(200, <String, Object>{'ok': true, 'invite': _invite(i)});
    }
    // bootstrap
    final Object? name = b['displayName'];
    if (name is! String || name.trim().isEmpty) return _json(400, <String, Object>{'error': 'display_name_required'});
    if (i.revoked || i.declined) return _json(409, <String, Object>{'error': 'revoked'});
    if (!i.accepted) return _json(409, <String, Object>{'error': 'not_accepted'});
    if (!i.expiresAt.isAfter(now())) return _json(410, <String, Object>{'error': 'expired'});
    if (i.bootstrapped) return _json(409, <String, Object>{'error': 'already_bootstrapped'});
    if (users.values.any((FakeUser u) => u.email == i.email)) return _json(409, <String, Object>{'error': 'email_already_registered'});
    final FakeUser u = addUser(name.trim(), email: i.email);
    i.bootstrapped = true;
    i.claimant = u.id;
    final Map<String, Object> out = <String, Object>{'ok': true, 'token': sessionFor(u.id), 'userId': u.id, 'childId': i.childId};
    if (b['enrol'] == true || b['enrol'] is Map) {
      final String dev = mintDevice(u.id);
      out.addAll(<String, Object>{'expiresAt': now().add(const Duration(hours: 1)).toIso8601String(), 'deviceId': dev,
          'deviceCredential': devices[dev]!.credential});
    }
    return _json(201, out);
  }

  // ---- invites: the session half ----
  http.Response _inviteAct(FakeUser me, String id, String act, Map<String, dynamic> b) {
    final FakeInvite? i = invites[id];
    if (act == 'claim') {
      // An account with an email on file must match it; one with NO email (every sign-up) may claim with the
      // invite id alone (pool.ts claimGuardianInvite).
      if (i == null || (me.email != null && me.email != i.email)) return _json(404, <String, Object>{'error': 'not_found'});
      if (i.revoked) return _json(410, <String, Object>{'error': 'revoked'});
      if (i.declined) return _json(410, <String, Object>{'error': 'declined'});
      if (i.confirmed) return _json(409, <String, Object>{'error': 'already_confirmed'});
      if (!i.accepted) return _json(409, <String, Object>{'error': 'not_accepted'});
      if (!i.expiresAt.isAfter(now())) return _json(410, <String, Object>{'error': 'expired'});
      if (i.claimant != null && i.claimant != me.id) return _json(409, <String, Object>{'error': 'already_claimed'});
      if (guardianship[i.childId]?.contains(me.id) ?? false) return _json(409, <String, Object>{'error': 'already_a_member'});
      i.claimant = me.id;
      return _json(200, <String, Object>{'ok': true, 'status': 'waiting_for_confirmation'});
    }
    // confirm / decline / revoke: only the inviter sees the row at all.
    if (i == null || i.invitedBy != me.id) return _json(404, <String, Object>{'error': 'not_found'});
    if (act == 'confirm') {
      final http.Response? gate = _pinGate(me, b['pin']);
      if (gate != null) return gate;
      if (i.confirmed) return _json(409, <String, Object>{'error': 'already_confirmed'});
      if (i.revoked) return _json(410, <String, Object>{'error': 'revoked'});
      if (i.declined) return _json(410, <String, Object>{'error': 'declined'});
      if (i.claimant == null) return _json(409, <String, Object>{'error': 'not_claimed'});
      if (!i.expiresAt.isAfter(now())) return _json(410, <String, Object>{'error': 'expired'});
      i.confirmed = true;
      guardianship[i.childId]!.add(i.claimant!);
      roles['${i.childId}|${i.claimant}'] = i.role;
      return _json(200, <String, Object>{'ok': true, 'role': i.role});
    }
    if (act == 'decline') {
      if (i.confirmed) return _json(409, <String, Object>{'error': 'already_confirmed'});
      i.declined = true;
      return _json(200, <String, Object>{'ok': true});
    }
    // revoke
    if (i.accepted) return _json(409, <String, Object>{'error': 'already_accepted'});
    i.revoked = true;
    return _json(200, <String, Object>{'ok': true});
  }
}
