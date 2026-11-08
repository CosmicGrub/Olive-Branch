// OLIVE BRANCH — the one authenticated session every live guardian/child
// screen shares. No longer UNVERIFIED — verified by CI (flutter test:
// auth_session_test.dart; server side: server/test/auth_session_route_test.mjs
// and packages/db/test/device_credential.test.mjs).
//
// Audit G-02 / G-06 / C-03 / G-14. Before this file, 27 screens each called
// the dev-only POST /v1/auth/dev-login (404 in production, DEV_LOGIN=0) for a
// fresh token on every load, a paired device's real session token was stored
// and then ignored, sessions silently died after one hour with no refresh,
// and "Sign out" cleared nothing. Now:
//
//   * A paired device holds {deviceId, deviceCredential} in secure storage
//     (DeviceIdentityStore). [AuthSession.device] trades them at
//     POST /v1/auth/session/refresh for a short (1 h) session, caches it, and
//     refreshes it shortly before it lapses. Concurrent callers share one
//     in-flight refresh.
//   * [OliveApi] built with a session retries a 401 exactly once after
//     refreshing (see OliveApi._authed). A second 401 is surfaced as a typed
//     [UnauthorizedException], never retried again.
//   * A revoked/unknown device (device_revoked / invalid_device_credential)
//     clears the stored identity and fires [onSignedOut] so the shell can go
//     back to pairing; the caller gets a [DeviceRevokedException].
//   * [signOut] revokes the device server-side (best effort), clears storage,
//     and fires [onSignedOut].
//
// DEV LOGIN is an explicit, opt-in path, never a fallback: [devLoginEnabled]
// defaults to false (release builds can never reach POST /v1/auth/dev-login
// through this class) and is switched on only by (a) a build that was
// provisioned with the dev --dart-define identity (OLIVE_CHILD_ID /
// OLIVE_GUARDIAN_ID / OLIVE_DEV_LOGIN=1 — see main_live*.dart), or (b)
// test/flutter_test_config.dart for the widget-test suite. With the flag off
// and no session installed, [apiFor] throws [UnauthorizedException]
// ('not_signed_in') — fail closed.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'device_identity.dart';

typedef Clock = DateTime Function();

/// A cached token is refreshed this long before it actually lapses, so a
/// request already in flight cannot land on the server a hair after expiry.
const Duration kSessionRefreshSkew = Duration(seconds: 60);

class AuthSession {
  AuthSession.device({
    required this.baseUrl,
    required DeviceIdentity identity,
    DeviceIdentityStore? store,
    http.Client? client,
    Clock? now,
    this.onSignedOut,
  })  : _identity = identity,
        _store = store ?? DeviceIdentityStore(),
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _token = identity.sessionToken,
        userId = null,
        childId = null,
        _refreshableDev = false,
        _dev = false;

  /// The explicit dev-login session. Throws [StateError] unless
  /// [devLoginEnabled] — constructing one in a build that never opted in is a
  /// programming error, not a runtime fallback.
  AuthSession.dev({
    required this.baseUrl,
    this.userId,
    this.childId,
    http.Client? client,
    Clock? now,
    bool refreshable = false,
    this.onSignedOut,
  })  : _identity = null,
        _store = null,
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _token = null,
        _refreshableDev = refreshable,
        _dev = true {
    if (!devLoginEnabled) {
      throw StateError('dev login is not enabled in this build '
          '(AuthSession.devLoginEnabled is false)');
    }
  }

  // ---- process-wide wiring --------------------------------------------------

  /// Dev login (POST /v1/auth/dev-login) is reachable through this class only
  /// when this is true. See this file's header. Default false.
  static bool devLoginEnabled = false;

  /// The session the live shell installed; [apiFor] uses it for every screen.
  static AuthSession? current;

  /// Install [session] as the process's session (null clears).
  static void use(AuthSession? session) => current = session;

  // ---- state ------------------------------------------------------------------

  final String baseUrl;
  final String? userId;
  final String? childId;
  final DeviceIdentity? _identity;
  final DeviceIdentityStore? _store;
  final http.Client _client;
  final Clock _now;
  final bool _dev;
  final bool _refreshableDev;

  /// Fired once when the session ends for good (revoked, unknown device,
  /// deactivated account, or [signOut]) — the shell returns to pairing.
  final void Function()? onSignedOut;

  String? _token;
  Future<String>? _refreshing;
  bool _ended = false;

  bool get isDev => _dev;
  bool get hasEnded => _ended;
  DeviceIdentity? get identity => _identity;

  /// Whether a 401 can be answered with a fresh token. Dev sessions created
  /// per call (the legacy behaviour) deliberately cannot — their token is the
  /// whole session. A paired device can iff it holds a credential (an identity
  /// stored before the credential existed has none and must re-pair).
  bool get canRefresh => _dev ? _refreshableDev : (_identity?.deviceCredential != null);

  // ---- tokens ------------------------------------------------------------------

  /// When [token] lapses, read from its own signed payload (`exp`, epoch ms).
  /// Unreadable => treated as already expired, so it gets refreshed rather
  /// than trusted.
  static DateTime? expiryOf(String token) {
    try {
      final dot = token.lastIndexOf('.');
      if (dot < 1) return null;
      var payload = token.substring(0, dot);
      payload = base64Url.normalize(payload);
      final body = jsonDecode(utf8.decode(base64Url.decode(payload)));
      final exp = body is Map ? body['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt());
    } catch (_) {
      return null;
    }
  }

  /// A token valid for at least [kSessionRefreshSkew], refreshing first when
  /// the cached one is about to lapse.
  Future<String> token() async {
    if (_ended) throw DeviceRevokedException();
    final t = _token;
    if (t != null) {
      final exp = expiryOf(t);
      final fresh = exp != null && exp.isAfter(_now().add(kSessionRefreshSkew));
      // A non-refreshable dev session has nothing better to offer; hand it
      // back and let the server's answer stand.
      if (fresh || (_dev && !_refreshableDev)) return t;
    }
    if (!canRefresh && !_dev) {
      // A legacy identity (no device credential) whose token lapsed: there is
      // no way to get another, so the device must re-pair.
      await _end();
      throw DeviceRevokedException();
    }
    return refresh();
  }

  /// Force a new token (the 401 path). Concurrent calls share one request.
  Future<String> refresh() {
    if (_ended) return Future<String>.error(DeviceRevokedException());
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _doRefresh() async {
    if (_dev) {
      final t = await devLoginFor(baseUrl, userId: userId, childId: childId, client: _client);
      return _token = t;
    }
    final id = _identity!;
    final cred = id.deviceCredential;
    if (cred == null) {
      await _end();
      throw DeviceRevokedException();
    }
    final res = await _client
        .post(
          Uri.parse('$baseUrl${OliveApi.sessionRefreshPath}'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'deviceId': id.deviceId, 'deviceCredential': cred}),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decodeBody(res);
    if (res.statusCode == 200) {
      final t = body['sessionToken'] as String;
      _token = t;
      // Persisted so a cold boot starts from a live token; a storage failure
      // must never fail the refresh itself (the in-memory session is fine).
      try {
        await _store!.save(id.withSessionToken(t));
      } catch (_) {}
      return t;
    }
    final error = body['error'] as String? ?? 'error';
    if (res.statusCode == 401 &&
        (error == 'device_revoked' || error == 'invalid_device_credential')) {
      await _end();
      throw DeviceRevokedException();
    }
    if (res.statusCode == 403 && error == 'account_deactivated') {
      await _end();
      throw ForbiddenException(error);
    }
    throw ApiException.fromStatus(res.statusCode, error);
  }

  /// A request came back 401 device_revoked: this device was cut off. Called by
  /// [OliveApi] so ANY call surfacing it ends the session, not only a refresh.
  Future<void> handleRevoked() => _end();

  // ---- sign out ------------------------------------------------------------------

  /// Revokes this device on the server (best effort — offline sign-out must
  /// still sign out), clears the stored identity, and fires [onSignedOut].
  /// Returns whether the server confirmed the revocation; false means the
  /// device credential is still valid server-side until a guardian revokes the
  /// device from another device (Settings > Paired devices).
  Future<bool> signOut() async {
    var revoked = false;
    if (!_dev && !_ended) {
      try {
        final t = await token();
        final res = await _client.post(
          Uri.parse('$baseUrl${OliveApi.sessionSignOutPath}'),
          headers: {'authorization': 'Bearer $t', 'content-type': 'application/json'},
          body: '{}',
        ).timeout(const Duration(seconds: 10));
        revoked = res.statusCode == 200 && _decodeBody(res)['revoked'] == true;
      } catch (_) {
        // offline / already revoked / expired beyond refresh: still sign out locally.
      }
    }
    await _end();
    return revoked;
  }

  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    _token = null;
    if (identical(current, this)) current = null;
    try {
      await _store?.clear();
    } catch (_) {}
    onSignedOut?.call();
  }

  static Map<String, dynamic> _decodeBody(http.Response res) {
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      final d = jsonDecode(res.body);
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

/// An [OliveApi] bound to the process's [AuthSession] — the replacement for
/// every `devLoginFor(...)` + `OliveApi(baseUrl, token, ...)` pair.
///
/// [userId]/[childId]/[client] only matter on the explicit dev path (and
/// [client] is also the transport the returned api uses): with a session
/// installed the identity comes from the session, never from the arguments.
/// With no session installed and dev login not enabled this fails closed with
/// an [UnauthorizedException] ('not_signed_in').
Future<OliveApi> apiFor(
  String baseUrl, {
  String? userId,
  String? childId,
  http.Client? client,
}) async {
  var session = AuthSession.current;
  if (session == null) {
    if (!AuthSession.devLoginEnabled) throw UnauthorizedException('not_signed_in');
    session = AuthSession.dev(baseUrl: baseUrl, userId: userId, childId: childId, client: client);
  }
  final token = await session.token();
  return OliveApi(baseUrl, token, client: client, session: session);
}
