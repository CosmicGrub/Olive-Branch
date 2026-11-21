// An in-memory stand-in for the lost-device routes of server/routes.mjs (migration 0057), for the client tests. It plugs
// into [FakeIdentityServer.interceptor], so every request is still checked against the REAL route table (method, path,
// session rule, body keys) before it gets here; this class only supplies the answers, with the same status codes,
// reasons and rules as the real handlers: own-PIN step-up, a report the owner made cannot be undone by another
// grown-up, only the owner makes a grown-up's phone final, an erase order is for a lost grown-up's phone only.
//
// It is a model of the server for the client's sake, not a second server: the real rules are proved against a real
// Postgres in server/test/lost_device_route.test.mjs.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fake_identity_server.dart';

class FakeDev {
  FakeDev(this.id, this.role, this.target, this.label);
  final String id;
  final String role; // 'guardian' | 'child'
  final String target; // owner's user id, or the child's id
  final String label;
  String state = 'active'; // active | paused | revoked
  String? incident;
  DateTime? due;
  String? markedBy;
  String wipe = 'none'; // none | ordered | done
}

class LostFake {
  LostFake(this.server) {
    server.interceptor = _intercept;
  }
  final FakeIdentityServer server;
  final Map<String, FakeDev> devs = <String, FakeDev>{};
  final Map<String, String> names = <String, String>{};
  final List<String> log = <String>[];
  int _n = 0xa000;

  String _id() => '00000000-0000-4000-a000-${(_n++).toRadixString(16).padLeft(12, '0')}';

  FakeDev add(String role, String target, String label, {String? ownerName}) {
    final FakeDev d = FakeDev(_id(), role, target, label);
    devs[d.id] = d;
    if (ownerName != null) names[target] = ownerName;
    return d;
  }

  http.Response _json(int s, Object b) =>
      http.Response(jsonEncode(b), s, headers: <String, String>{'content-type': 'application/json'});
  http.Response _err(int s, String e) => _json(s, <String, Object>{'error': e});

  Map<String, Object?> _view(FakeDev d, String uid) {
    final bool own = d.role == 'guardian' && d.target == uid;
    final bool paused = d.state == 'paused';
    return <String, Object?>{
      'id': d.id,
      'role': d.role,
      'label': d.label,
      'ownerName': d.role == 'guardian' ? names[d.target] : null,
      'isThisDevice': false,
      'isOwn': own,
      'state': d.state,
      'pausedAt': paused ? server.now().toUtc().toIso8601String() : null,
      'revokeDueAt': paused ? d.due?.toUtc().toIso8601String() : null,
      'incidentId': paused ? d.incident : null,
      'markedByName': paused && d.markedBy != null ? names[d.markedBy] : null,
      'markedByMe': paused && d.markedBy == uid,
      'canMarkLost': d.state == 'active',
      'canFound': paused && !(d.markedBy == d.target && d.role == 'guardian' && !own),
      'canConfirmLost': paused && (d.role == 'child' || own),
      'wipe': d.wipe,
      'canOrderWipe': d.role == 'guardian' && own && d.state != 'active' && d.incident != null && d.wipe == 'none',
      'canCancelWipe': d.role == 'guardian' && own && d.wipe == 'ordered',
    };
  }

  Map<String, Object?> _answer(FakeDev d) => <String, Object?>{
        'deviceId': d.id,
        'state': d.state,
        'incidentId': d.incident,
        'already': false,
        'revokeDueAt': d.due?.toUtc().toIso8601String(),
      };

  Future<http.Response?> _intercept(http.BaseRequest base) async {
    final http.Request req = base as http.Request;
    final String path = req.url.path;
    if (!path.startsWith('/v1/me/devices')) return null;
    final Map<String, dynamic> b = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    final String? tok = req.headers['authorization']?.replaceFirst('Bearer ', '');
    final String? uid = tok == null ? null : server.sessions[tok];
    log.add('${req.method} $path');
    if (uid == null) return _err(401, 'bad_signature');
    if (path == '/v1/me/devices' && req.method == 'GET') {
      return _json(200, <String, Object>{
        'devices': <Map<String, Object?>>[for (final FakeDev d in devs.values) _view(d, uid)],
      });
    }
    final RegExpMatch? m = RegExp(r'^/v1/me/devices/([^/]+)/(mark-lost|found|confirm-lost|order-wipe|cancel-wipe)$').firstMatch(path);
    if (m == null) return null;
    final FakeUser? me = server.users[uid];
    if (me == null || me.pin == null || me.pin != b['pin']) return _err(403, 'pin_incorrect');
    final FakeDev? d = devs[m.group(1)];
    if (d == null) return _err(404, 'not_found');
    final bool own = d.role == 'guardian' && d.target == uid;
    final String incident = b['incidentId'] is String ? b['incidentId'] as String : '';
    switch (m.group(2)) {
      case 'mark-lost':
        if (d.state == 'revoked') return _err(409, 'already_revoked');
        if (d.state == 'paused') return _json(200, <String, Object?>{..._answer(d), 'already': true});
        d
          ..state = 'paused'
          ..incident = _id()
          ..due = server.now().add(const Duration(hours: 72))
          ..markedBy = uid;
        return _json(201, _answer(d));
      case 'found':
        if (incident.isEmpty) return _err(400, 'incident_required');
        if (d.state == 'revoked') return _err(409, 'too_late');
        if (d.state != 'paused') return _err(409, 'not_paused');
        if (d.incident != incident) return _err(409, 'stale_incident');
        if (d.wipe == 'done') return _err(409, 'already_wiped');
        if (d.markedBy == d.target && d.role == 'guardian' && !own) return _err(403, 'owner_only');
        d
          ..state = 'active'
          ..incident = null
          ..due = null
          ..markedBy = null
          ..wipe = 'none';
        return _json(200, _answer(d));
      case 'confirm-lost':
        if (incident.isEmpty) return _err(400, 'incident_required');
        if (d.state == 'revoked') return _err(409, 'already_revoked');
        if (d.state != 'paused') return _err(409, 'not_paused');
        if (d.incident != incident) return _err(409, 'stale_incident');
        if (d.role == 'guardian' && !own) return _err(403, 'owner_only');
        d.state = 'revoked';
        return _json(200, _answer(d));
      case 'order-wipe':
        if (d.role != 'guardian') return _err(403, 'not_a_grown_up_phone');
        if (!own) return _err(403, 'owner_only');
        if (d.state == 'active' || d.incident == null) return _err(409, 'not_paused');
        if (d.wipe != 'none') return _json(200, <String, Object?>{..._answer(d), 'already': true});
        d.wipe = 'ordered';
        return _json(201, _answer(d));
      case 'cancel-wipe':
        if (!own) return _err(403, 'owner_only');
        if (d.wipe == 'done') return _err(409, 'already_wiped');
        if (d.wipe != 'ordered') return _err(409, 'no_wipe_ordered');
        d.wipe = 'none';
        return _json(200, _answer(d));
    }
    return null;
  }
}
