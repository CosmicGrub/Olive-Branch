// OLIVE BRANCH — parity harness: an in-memory server for the real client to talk to. No longer
// UNVERIFIED — verified by CI (client/test/parity/fake_server_test.dart).
//
// It answers the routes the CLIENT calls today (the real server's wire shapes, the ones the existing screen
// tests stub by hand) with the SEMANTICS of the prototype's simulated server (docs/superpowers/mockups/live,
// LIVE-API.md): the PIN gate locks after 5 wrong tries in 15 virtual minutes, a pairing code is 6 digits 1 to 9
// and lives 10 virtual minutes, a new code revokes the older open ones, five wrong redeems lock a device for
// 5 virtual minutes, a child can never make a code, Messages can never be hidden, and an emergency card
// refuses a stale base. Where the real server's error NAME differs from the prototype's (pin_incorrect vs
// invalid_pin) the client's name is used and the difference is recorded in rule_checks.dart, not hidden here.
//
// Injection: per-device online flag (offline = the request throws ClientException, like a dropped socket),
// latency (virtual: the tester pumps it), failNext(status, error), and a request log. The clock is the
// harness's VirtualClock, so expiry and lockout are driven by tester.pump.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'virtual_clock.dart';

class LoggedRequest {
  LoggedRequest(this.dev, this.method, this.path, this.status, this.error);
  final String dev;
  final String method;
  final String path;
  final int status;
  final String? error;
  @override
  String toString() => '$dev $method $path -> $status${error == null ? '' : ' $error'}';
}

class FakeServer {
  FakeServer(this.clock, {this.pin = '2468', this.childId = 'child-1'});

  final VirtualClock clock;
  final String pin;
  final String childId;

  final Map<String, bool> _online = <String, bool>{'g': true, 'k': true};
  Duration latency = Duration.zero;
  final Map<String, ({int status, String error})?> _failNext = <String, ({int status, String error})?>{};
  final List<LoggedRequest> log = <LoggedRequest>[];

  // PIN gate.
  final List<DateTime> _pinFails = <DateTime>[];
  DateTime? _pinLockUntil;
  // Pairing codes.
  final List<PairingCodeRecord> codes = <PairingCodeRecord>[];
  final Map<String, int> _redeemFails = <String, int>{};
  final Map<String, DateTime> _redeemLock = <String, DateTime>{};
  int _seq = 0;
  // Overrides (parental controls).
  final Map<String, Map<String, dynamic>> overrides = <String, Map<String, dynamic>>{};
  // Emergency card (kept here for the wire-level test; the screens use a local service).
  int emergencyVersion = 1;
  final List<String> pairedDevices = <String>[];

  // ---- injection ---------------------------------------------------------------------------------------
  void setOnline(String dev, bool on) => _online[dev] = on;
  bool isOnline(String dev) => _online[dev] ?? true;
  void failNext(String dev, int status, String error) => _failNext[dev] = (status: status, error: error);

  /// Minutes of lock left, or 0.
  int get pinLockMinutesLeft {
    final DateTime? u = _pinLockUntil;
    if (u == null || !u.isAfter(clock.nowUtc)) return 0;
    return (u.difference(clock.nowUtc).inSeconds / 60).ceil();
  }

  /// The most recent code that is still open (what a grown-up would read off the phone).
  String? get openCode {
    for (final PairingCodeRecord c in codes.reversed) {
      if (c.open(clock.nowUtc)) return c.numeric;
    }
    return null;
  }

  // ---- the client ---------------------------------------------------------------------------------------
  http.Client clientFor(String dev) => MockClient((http.Request req) async {
        if (!isOnline(dev)) {
          _record(dev, req, 0, 'offline');
          throw http.ClientException('offline', req.url);
        }
        if (latency > Duration.zero) await Future<void>.delayed(latency);
        final ({int status, String error})? f = _failNext.remove(dev);
        if (f != null) return _reply(dev, req, f.status, <String, dynamic>{'error': f.error});
        return _route(dev, req);
      });

  http.Response _reply(String dev, http.Request req, int status, Map<String, dynamic> body) {
    _record(dev, req, status, body['error'] as String?);
    return http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});
  }

  void _record(String dev, http.Request req, int status, String? error) =>
      log.add(LoggedRequest(dev, req.method, req.url.path, status, error));

  Map<String, dynamic> _body(http.Request r) => r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;

  /// True when [pin] is right; counts the wrong ones. Null = allowed to try, otherwise the refusal.
  ({int status, String error})? _pinGate(String entered) {
    final DateTime now = clock.nowUtc;
    if (_pinLockUntil != null && _pinLockUntil!.isAfter(now)) return (status: 403, error: 'pin_locked');
    if (entered == pin) {
      _pinFails.clear();
      return null;
    }
    _pinFails.add(now);
    _pinFails.removeWhere((DateTime t) => now.difference(t) >= const Duration(minutes: 15));
    if (_pinFails.length >= 5) {
      _pinLockUntil = _pinFails[_pinFails.length - 5].add(const Duration(minutes: 15));
      return (status: 403, error: 'pin_locked');
    }
    return (status: 403, error: 'pin_incorrect');
  }

  String _newCode() {
    // Digits 1 to 9 only, six of them, deterministic per server (a counter walks the alphabet).
    int n = 100003 * (++_seq) + 7919;
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < 6; i++) {
      b.write(1 + n % 9);
      n ~/= 9;
      n += 13 * (i + 1) + _seq;
    }
    return b.toString();
  }

  http.Response _route(String dev, http.Request req) {
    final String p = req.url.path, m = req.method;
    final DateTime now = clock.nowUtc;
    if (p == '/v1/auth/dev-login' && m == 'POST') return _reply(dev, req, 200, <String, dynamic>{'token': 'dev-token'});

    if (p == '/v1/me/verify-controls-pin' && m == 'POST') {
      final ({int status, String error})? refusal = _pinGate('${_body(req)['pin']}');
      return refusal == null ? _reply(dev, req, 200, <String, dynamic>{'ok': true}) : _reply(dev, req, refusal.status, <String, dynamic>{'error': refusal.error});
    }

    final bool childCode = RegExp(r'^/v1/children/[^/]+/device-pairing-codes$').hasMatch(p);
    if ((childCode || p == '/v1/me/device-pairing-codes') && m == 'POST') {
      if (dev == 'k') return _reply(dev, req, 403, <String, dynamic>{'error': 'forbidden'}); // a child can never make a code
      final ({int status, String error})? refusal = _pinGate('${_body(req)['pin']}');
      if (refusal != null) return _reply(dev, req, refusal.status, <String, dynamic>{'error': refusal.error});
      for (final PairingCodeRecord c in codes) {
        if (c.open(now)) c.revoked = true; // a new code replaces older open ones
      }
      final PairingCodeRecord c = PairingCodeRecord('code-${codes.length + 1}', _newCode(), now.add(const Duration(minutes: 10)), childCode ? 'child' : 'guardian');
      codes.add(c);
      // expiresAt is what the screen's own countdown reads (real wall clock); validity here is virtual.
      return _reply(dev, req, 201, <String, dynamic>{
        'id': c.id, 'numericCode': c.numeric, 'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
      });
    }
    final RegExpMatch? cancel = RegExp(r'^/v1/device-pairing-codes/([^/]+)/cancel$').firstMatch(p);
    if (cancel != null && m == 'POST') {
      for (final PairingCodeRecord c in codes) {
        if (c.id == cancel.group(1)) c.revoked = true;
      }
      return _reply(dev, req, 200, <String, dynamic>{'ok': true});
    }

    if (p == '/v1/device-pairing/redeem' && m == 'POST') {
      final DateTime? lock = _redeemLock[dev];
      if (lock != null && lock.isAfter(now)) return _reply(dev, req, 429, <String, dynamic>{'error': 'locked'});
      final Map<String, dynamic> b = _body(req);
      final String code = '${b['code']}';
      PairingCodeRecord? rec;
      for (final PairingCodeRecord c in codes) {
        if (c.numeric == code || c.id == code) rec = c;
      }
      void bad() {
        final int n = (_redeemFails[dev] ?? 0) + 1;
        _redeemFails[dev] = n;
        if (n >= 5) {
          _redeemFails[dev] = 0;
          _redeemLock[dev] = now.add(const Duration(minutes: 5));
        }
      }

      if (rec == null) {
        bad();
        return _reply(dev, req, 404, <String, dynamic>{'error': 'not_found'});
      }
      if (rec.revoked) return _reply(dev, req, 409, <String, dynamic>{'error': 'revoked'});
      if (rec.redeemed) return _reply(dev, req, 409, <String, dynamic>{'error': 'already_redeemed'});
      if (!rec.expires.isAfter(now)) {
        bad();
        return _reply(dev, req, 410, <String, dynamic>{'error': 'expired'});
      }
      if (rec.role != b['role']) {
        return _reply(dev, req, 409, <String, dynamic>{'error': 'role_mismatch'});
      }
      rec.redeemed = true;
      pairedDevices.add(dev);
      return _reply(dev, req, 201, <String, dynamic>{
        'sessionToken': 'tok-$dev', 'deviceId': 'device-${pairedDevices.length}', 'role': rec.role, 'targetId': childId,
      });
    }

    final RegExpMatch? ov = RegExp(r'^/v1/children/([^/]+)/activity-overrides(?:/(.+))?$').firstMatch(p);
    if (ov != null) {
      if (m == 'GET') {
        return _reply(dev, req, 200, <String, dynamic>{
          'overrides': <Map<String, dynamic>>[for (final MapEntry<String, Map<String, dynamic>> e in overrides.entries) <String, dynamic>{'activityKey': e.key, ...e.value}],
        });
      }
      if (m == 'PUT' && ov.group(2) != null) {
        final String key = Uri.decodeComponent(ov.group(2)!);
        final Map<String, dynamic> b = _body(req);
        // The prototype's rule: Messages can never be hidden (family must always be able to reach her).
        if (key == 'tile:messages' && b['visible'] == false) return _reply(dev, req, 403, <String, dynamic>{'error': 'cannot_hide_messages'});
        overrides[key] = <String, dynamic>{...?overrides[key], ...b};
        return _reply(dev, req, 200, <String, dynamic>{'ok': true});
      }
    }

    if (RegExp(r'^/v1/children/[^/]+/emergency-card$').hasMatch(p) && m == 'PUT') {
      final int base = (_body(req)['base'] as num?)?.toInt() ?? -1;
      if (base != emergencyVersion) return _reply(dev, req, 409, <String, dynamic>{'error': 'stale_version', 'current': emergencyVersion});
      emergencyVersion++;
      return _reply(dev, req, 200, <String, dynamic>{'v': emergencyVersion});
    }

    return _reply(dev, req, 404, <String, dynamic>{'error': 'not_found'});
  }
}

class PairingCodeRecord {
  PairingCodeRecord(this.id, this.numeric, this.expires, this.role);
  final String id;
  final String numeric;
  final DateTime expires;
  final String role;
  bool revoked = false;
  bool redeemed = false;
  bool open(DateTime now) => !revoked && !redeemed && expires.isAfter(now);
}
