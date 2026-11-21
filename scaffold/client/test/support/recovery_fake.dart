// An in-memory stand-in for the recovery routes of server/routes.mjs (migration 0055), for the client tests. It plugs into
// [FakeIdentityServer.interceptor], so every request is still checked against the REAL route table (method, path, session
// rule, body keys) before it gets here; this class only supplies the answers, with the same status codes, reasons and rules
// as the real handlers: own-PIN step-up, the 48 and 72 hour waits, the helper's single power, one answer for anything
// unknown, five wrong guesses end THAT request.
//
// It is a model of the server for the client's sake, not a second server: the real rules are proved against a real
// Postgres in server/test/recovery_paths_route.test.mjs.
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:olive_client/recovery_paths_logic.dart';

import 'fake_identity_server.dart';

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final Random _rng = Random(7);
String _code(int n) => List<String>.generate(n, (int _) => _alphabet[_rng.nextInt(32)]).join();
String _grouped(String s) => groupRecoveryCode(s);

class FakeReq {
  FakeReq(this.id, this.userId, this.soleParent, this.secret, this.created, this.ready,
      {this.helperId, this.helperRequired = false, this.startedBy});
  final String id;
  final String userId;
  final bool soleParent;
  final String secret;
  DateTime created, ready;
  final String? helperId;
  final bool helperRequired;
  final String? startedBy;
  bool helperConfirmed = false;
  String? cancelledBy;
  bool completed = false;
  int wrong = 0;
}

class RecoveryFake {
  RecoveryFake(this.server) {
    server.interceptor = _intercept;
  }
  final FakeIdentityServer server;

  /// userId -> the other parents of that account (symmetric when set with [makeParents]).
  final Map<String, Set<String>> parents = <String, Set<String>>{};
  final Set<String> usersWithLivePhone = <String>{};
  final Map<String, String> sheets = <String, String>{}; // userId -> normalised key
  final Map<String, DateTime?> sheetConfirmed = <String, DateTime?>{};
  final Set<String> spentSheetFor = <String>{};
  final Map<String, ({String id, String label, String invite, String? key})> helpers =
      <String, ({String id, String label, String invite, String? key})>{};
  final Map<String, FakeReq> reqs = <String, FakeReq>{};
  final List<String> log = <String>[];
  int _n = 0x9000;

  String _id() => '00000000-0000-4000-9000-${(_n++).toRadixString(16).padLeft(12, '0')}';

  void makeParents(String a, String b) {
    parents.putIfAbsent(a, () => <String>{}).add(b);
    parents.putIfAbsent(b, () => <String>{}).add(a);
  }

  /// Moves a request's clock back, the way an elapsed waiting period would.
  void age(String requestId, Duration d) {
    final FakeReq r = reqs[requestId]!;
    r.created = r.created.subtract(d);
    r.ready = r.ready.subtract(d);
  }

  http.Response _json(int s, Object b) =>
      http.Response(jsonEncode(b), s, headers: <String, String>{'content-type': 'application/json'});
  http.Response _err(int s, String e) => _json(s, <String, Object>{'error': e});

  String? _phase(FakeReq r) {
    final DateTime now = server.now();
    if (r.completed) return 'done';
    if (r.cancelledBy != null) return r.cancelledBy == 'expired' ? 'expired' : 'stopped';
    if (r.ready.isAfter(now)) return 'waiting';
    if (r.helperRequired && !r.helperConfirmed) return 'waiting_for_helper';
    return 'ready';
  }

  FakeReq? _byCode(Object? raw) {
    if (raw is! String) return null;
    final String? n = normaliseRecoveryCode(RecoveryCodeKind.request, raw);
    if (n == null) return null;
    for (final FakeReq r in reqs.values) {
      if (r.secret == n) return r;
    }
    return null;
  }

  Future<http.Response?> _intercept(http.BaseRequest base) async {
    final http.Request req = base as http.Request;
    final String path = req.url.path;
    if (!path.startsWith('/v1/me/recovery') && !path.startsWith('/v1/auth/recovery') && !path.startsWith('/v1/auth/helper')) {
      return null;
    }
    final Map<String, dynamic> b = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    final String? tok = req.headers['authorization']?.replaceFirst('Bearer ', '');
    final String? uid = tok == null ? null : server.sessions[tok];
    log.add('${req.method} $path');
    final DateTime now = server.now();

    bool pinOk() => uid != null && server.users[uid]?.pin != null && server.users[uid]!.pin == b['pin'];

    // ---- a signed-in grown-up
    if (path.startsWith('/v1/me/')) {
      if (uid == null) return _err(401, 'bad_signature');
      if (path == '/v1/me/recovery' && req.method == 'GET') return _summary(uid);
      if (path == '/v1/me/recovery-sheet/check') {
        final String? n = normaliseRecoveryCode(RecoveryCodeKind.sheet, '${b['key']}');
        if (!sheets.containsKey(uid)) return _err(404, 'no_sheet');
        if (n == null || n != sheets[uid]) return _err(403, 'wrong_key');
        sheetConfirmed[uid] ??= now;
        return _json(200, <String, Object>{'ok': true, 'confirmedAt': now.toUtc().toIso8601String()});
      }
      if (!pinOk()) return _err(403, 'pin_incorrect');
      switch (path) {
        case '/v1/me/recovery-sheet':
          final String k = _code(24);
          final bool had = sheets.containsKey(uid);
          sheets[uid] = k;
          sheetConfirmed[uid] = null;
          spentSheetFor.remove(uid);
          return _json(201, <String, Object>{'key': _grouped(k), 'replacedOlder': had, 'stoppedRecoveries': 0});
        case '/v1/me/recovery-helper':
          final String label = '${b['label']}'.trim();
          if (label.isEmpty || label.length > 40 || label.contains('@')) return _err(400, 'invalid_label');
          final String inv = _code(16);
          final bool had = helpers.containsKey(uid);
          helpers[uid] = (id: _id(), label: label, invite: inv, key: null);
          return _json(201, <String, Object>{
            'code': _grouped(inv), 'expiresAt': now.add(const Duration(hours: 72)).toUtc().toIso8601String(), 'replacedOlder': had});
        case '/v1/me/recovery-helper/remove':
          final bool had = helpers.remove(uid) != null;
          return _json(200, <String, Object>{'ok': true, 'removed': had});
        case '/v1/me/recovery/start-for':
          final String target = '${b['targetUserId']}';
          if (uid == target || !(parents[uid]?.contains(target) ?? false)) return _err(403, 'not_family');
          final String secret = _code(20);
          final FakeReq r = FakeReq(_id(), target, false, secret, now, now.add(const Duration(hours: 48)), startedBy: uid);
          reqs[r.id] = r;
          return _json(201, <String, Object?>{
            'requestId': r.id, 'code': _grouped(secret), 'readyAt': r.ready.toUtc().toIso8601String(),
            'expiresAt': now.add(const Duration(days: 10)).toUtc().toIso8601String(), 'targetName': server.users[target]?.name ?? ''});
      }
      final RegExpMatch? c = RegExp(r'^/v1/me/recovery/([^/]+)/cancel$').firstMatch(path);
      if (c != null) {
        final FakeReq? r = reqs[c.group(1)!];
        if (r == null || r.completed || r.cancelledBy != null) return _err(404, 'not_found');
        final bool own = r.userId == uid;
        if (!own && !(parents[uid]?.contains(r.userId) ?? false)) return _err(404, 'not_found');
        r.cancelledBy = own ? 'owner_phone' : 'other_parent';
        return _json(200, <String, Object>{'ok': true});
      }
      return _err(404, 'not_found');
    }

    // ---- no session
    switch (path) {
      case '/v1/auth/recovery/start':
        final String? n = normaliseRecoveryCode(RecoveryCodeKind.sheet, '${b['sheetKey']}');
        final String? who = n == null ? null : sheets.entries.where((MapEntry<String, String> e) => e.value == n).map((MapEntry<String, String> e) => e.key).firstOrNull;
        if (who == null) return _err(403, 'invalid_sheet');
        if ((parents[who] ?? <String>{}).any(usersWithLivePhone.contains)) return _err(403, 'ask_other_grownup');
        final String secret = _code(20);
        final MapEntry<String, ({String id, String label, String invite, String? key})>? h =
            helpers.entries.where((MapEntry<String, ({String id, String label, String invite, String? key})> e) => e.key == who && e.value.key != null).firstOrNull;
        final FakeReq r = FakeReq(_id(), who, true, secret, now, now.add(const Duration(hours: 72)),
            helperId: h?.value.id, helperRequired: h != null);
        reqs[r.id] = r;
        return _json(201, <String, Object?>{
          'code': _grouped(secret), 'readyAt': r.ready.toUtc().toIso8601String(),
          'expiresAt': now.add(const Duration(days: 10)).toUtc().toIso8601String(), 'helperRequired': h != null,
          'accountName': server.users[who]?.name ?? ''});
      case '/v1/auth/recovery/status':
        final FakeReq? r = _byCode(b['code']);
        if (r == null) return _err(404, 'invalid_recovery');
        return _json(200, <String, Object?>{
          'requestId': r.id, 'phase': _phase(r), 'mode': r.soleParent ? 'sole_parent' : 'second_parent',
          'accountName': server.users[r.userId]?.name ?? '', 'createdAt': r.created.toUtc().toIso8601String(),
          'readyAt': r.ready.toUtc().toIso8601String(), 'expiresAt': now.add(const Duration(days: 9)).toUtc().toIso8601String(),
          'helperRequired': r.helperRequired, 'helperConfirmed': r.helperConfirmed, 'stoppedBy': r.cancelledBy});
      case '/v1/auth/recovery/cancel':
        final FakeReq? r = _byCode(b['code']);
        if (r == null || r.completed || r.cancelledBy != null) return _err(404, 'invalid_recovery');
        r.cancelledBy = 'new_phone';
        return _json(200, <String, Object>{'ok': true});
      case '/v1/auth/recovery/finish':
        final FakeReq? r = _byCode(b['code']);
        if (r == null || r.completed || r.cancelledBy != null) return _err(403, 'invalid_recovery');
        if (r.ready.isAfter(now)) return _json(409, <String, Object>{'error': 'too_early', 'readyAt': r.ready.toUtc().toIso8601String()});
        if (r.helperRequired && !r.helperConfirmed) return _err(409, 'waiting_for_helper');
        String proof = 'sheet_at_start';
        if (!r.soleParent) {
          final bool hasPin = b['pin'] is String;
          final String? keyN = b['sheetKey'] is String ? normaliseRecoveryCode(RecoveryCodeKind.sheet, b['sheetKey'] as String) : null;
          if (!hasPin && keyN == null) return _err(400, 'proof_required');
          final bool ok = (keyN != null && sheets[r.userId] == keyN) || (hasPin && server.users[r.userId]?.pin == b['pin']);
          if (!ok) {
            r.wrong++;
            if (r.wrong >= 5) {
              r.cancelledBy = 'too_many_wrong';
              return _err(423, 'too_many_wrong');
            }
            return _err(403, 'wrong_proof');
          }
          proof = keyN != null ? 'sheet' : 'pin';
        }
        r.completed = true;
        final int out = server.devices.entries.where((e) => e.value.userId == r.userId && !e.value.revoked).length;
        for (final String k in server.devices.keys.toList()) {
          if (server.devices[k]!.userId == r.userId) {
            server.devices[k] = (userId: r.userId, credential: server.devices[k]!.credential, revoked: true);
          }
        }
        final String dev = server.mintDevice(r.userId);
        if (b['newPin'] is String) server.users[r.userId]!.pin = b['newPin'] as String;
        final bool spent = proof != 'pin' && sheets.remove(r.userId) != null;
        if (spent) spentSheetFor.add(r.userId);
        return _json(201, <String, Object?>{
          'token': server.sessionFor(r.userId), 'expiresAt': now.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          'userId': r.userId, 'deviceId': dev, 'deviceCredential': server.devices[dev]!.credential,
          'devicesSignedOut': out, 'sheetSpent': spent,
          'children': server.guardianship.values.where((Set<String> s) => s.contains(r.userId)).length});
      case '/v1/auth/helper/accept':
        final String? n = normaliseRecoveryCode(RecoveryCodeKind.helperInvite, '${b['code']}');
        for (final MapEntry<String, ({String id, String label, String invite, String? key})> e in helpers.entries) {
          if (n != null && e.value.invite == n && e.value.key == null) {
            final String key = base64Url.encode(List<int>.generate(32, (int _) => _rng.nextInt(256))).replaceAll('=', '');
            helpers[e.key] = (id: e.value.id, label: e.value.label, invite: e.value.invite, key: key);
            return _json(201, <String, Object>{'helperKey': key, 'accountName': server.users[e.key]?.name ?? '', 'label': e.value.label});
          }
        }
        return _err(403, 'invalid_invite');
      case '/v1/auth/helper/requests':
      case '/v1/auth/helper/answer':
        final MapEntry<String, ({String id, String label, String invite, String? key})>? me =
            helpers.entries.where((MapEntry<String, ({String id, String label, String invite, String? key})> e) => e.value.key != null && e.value.key == b['helperKey']).firstOrNull;
        if (me == null) return _err(403, 'invalid_helper');
        if (path.endsWith('/requests')) {
          return _json(200, <String, Object>{
            'requests': <Map<String, Object?>>[
              for (final FakeReq r in reqs.values)
                if (r.helperId == me.value.id && !r.completed && r.cancelledBy == null)
                  <String, Object?>{'requestId': r.id, 'accountName': server.users[r.userId]?.name ?? '',
                    'startedAt': r.created.toUtc().toIso8601String(), 'readyAt': r.ready.toUtc().toIso8601String(),
                    'confirmed': r.helperConfirmed}
            ]
          });
        }
        final FakeReq? r = reqs['${b['requestId']}'];
        if (r == null || r.helperId != me.value.id || r.completed || r.cancelledBy != null) return _err(404, 'not_found');
        if (b['answer'] == 'yes') {
          r.helperConfirmed = true;
          return _json(200, <String, Object>{'ok': true, 'result': 'confirmed'});
        }
        r.cancelledBy = 'helper';
        return _json(200, <String, Object>{'ok': true, 'result': 'stopped'});
    }
    return _err(404, 'not_found');
  }

  http.Response _summary(String uid) {
    final DateTime now = server.now();
    Map<String, Object?> view(FakeReq r) => <String, Object?>{
          'requestId': r.id, 'phase': _phase(r), 'mode': r.soleParent ? 'sole_parent' : 'second_parent',
          'accountUserId': r.userId, 'accountName': server.users[r.userId]?.name ?? '', 'aboutMe': r.userId == uid,
          'startedByName': r.startedBy == null ? null : server.users[r.startedBy]?.name, 'startedByMe': r.startedBy == uid,
          'createdAt': r.created.toUtc().toIso8601String(), 'readyAt': r.ready.toUtc().toIso8601String(),
          'helperRequired': r.helperRequired, 'helperConfirmed': r.helperConfirmed,
          'endedAt': null, 'stoppedBy': r.cancelledBy};
    final Set<String> ids = <String>{uid, ...?parents[uid]};
    final List<FakeReq> mine = reqs.values.where((FakeReq r) => ids.contains(r.userId)).toList();
    bool open(FakeReq r) => !r.completed && r.cancelledBy == null;
    final h = helpers[uid];
    return _json(200, <String, Object?>{
      'sheet': <String, Object?>{
        'exists': sheets.containsKey(uid), 'createdAt': sheets.containsKey(uid) ? now.toUtc().toIso8601String() : null,
        'confirmedAt': sheetConfirmed[uid]?.toUtc().toIso8601String(), 'lastCheckedAt': null,
        'spentNeedsNew': spentSheetFor.contains(uid)},
      'helper': h == null
          ? <String, Object?>{'state': 'none'}
          : <String, Object?>{'state': h.key == null ? 'invited' : 'active', 'label': h.label,
              'inviteExpiresAt': h.key == null ? now.add(const Duration(hours: 70)).toUtc().toIso8601String() : null},
      'open': <Object?>[for (final FakeReq r in mine.where(open)) view(r)],
      'recentEnded': <Object?>[for (final FakeReq r in mine.where((FakeReq r) => !open(r))) view(r)],
      'canHelp': <Object?>[for (final String p in parents[uid] ?? <String>{}) <String, Object?>{'userId': p, 'name': server.users[p]?.name ?? ''}],
      'waits': <String, Object>{'secondParentHours': 48, 'soleParentHours': 72},
    });
  }
}
