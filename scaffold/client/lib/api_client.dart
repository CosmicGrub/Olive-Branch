// OLIVE BRANCH — Flutter client, API surface. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §20.2, §7.
//
// Real HTTP client as of this pass — previously endpoint-string constants
// only, with no code anywhere that actually made a request (there was no
// server for it to call, either — see server/index.mjs, the first thing in
// this repository that listens on a port). Endpoint strings below are
// contract-checked against the registered API routes by
// packages/api/test/contract.test.mjs so the two cannot drift silently. The
// server currently implements a real, narrow slice of these — /v1/me, /now,
// /inbox — not the full list; calling an unimplemented one gets a real 404
// from the real router, not a fake one.
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.error);
  final int statusCode;
  final String error;
  @override
  String toString() => 'ApiException($statusCode, $error)';
}

class OliveApi {
  OliveApi(this.baseUrl, this.sessionToken, {http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String sessionToken;
  final http.Client _client;

  // --- identity -----------------------------------------------------------
  static const mePath = '/v1/me';

  // --- time engine (§7.2) -------------------------------------------------
  static const childNow    = '/v1/children/:childId/now';
  static const childRibbon = '/v1/children/:childId/ribbon';
  static const childOverlap = '/v1/children/:childId/overlap';

  // --- async delivery (§7.3) ---------------------------------------------
  static const inbox    = '/v1/children/:childId/inbox';
  static const messages = '/v1/children/:childId/messages';
  static const batches  = '/v1/children/:childId/batches';

  // --- child agency (§7.10) ----------------------------------------------
  static const ping    = '/v1/children/:childId/ping';
  static const journal = '/v1/children/:childId/journal';

  // --- coordination (§7.7) -----------------------------------------------
  static const medications   = '/v1/children/:childId/medications';
  static const emergencyCard = '/v1/children/:childId/emergency-card';

  // --- guarded by escalation (§8.3) --------------------------------------
  static const settings = '/v1/children/:childId/settings';

  // --- real authentication (§7.1, §8.1, §8.3) -----------------------------
  // Path constants, contract-checked against the registered server routes by
  // packages/api/test/contract.test.mjs (and by transport.test.mjs's own
  // "I · CLIENT CONTRACT" section, which scans every .dart file's string
  // literals) -- see server/routes.mjs and server/index.mjs for the real,
  // already-implemented, already-tested server side of every one of these.
  // kioskPinVerify and guardianPinPath now have real Dart CALLING code below
  // (verifyKioskPin / setGuardianPin); the WebAuthn paths are still
  // path-constants-only, wired in a later phase.
  static const kioskPinVerify = '/v1/children/:childId/kiosk-pin/verify';
  // Named guardianPinPath, not setGuardianPin, so it doesn't collide with the
  // instance method of that name below -- same string value either way, and
  // contract.test.mjs/transport.test.mjs only regex-scan for the literal
  // '/v1/me/pin', never the Dart identifier.
  static const guardianPinPath = '/v1/me/pin';
  static const webauthnRegisterChallenge = '/v1/auth/webauthn/register/challenge';
  static const webauthnRegisterVerify = '/v1/auth/webauthn/register/verify';
  static const webauthnLoginChallenge = '/v1/auth/webauthn/login/challenge';
  static const webauthnLoginVerify = '/v1/auth/webauthn/login/verify';

  // --- login (dev-only — see server/index.mjs's own header comment) ------
  static const devLoginPath = '/v1/auth/dev-login';

  Uri _uri(String path, [String? childId]) => Uri.parse(
      '$baseUrl${childId != null ? path.replaceFirst(':childId', childId) : path}');

  Future<Map<String, dynamic>> _get(String path, {String? childId}) async {
    final res = await _client.get(_uri(path, childId),
        headers: {'authorization': 'Bearer $sessionToken'});
    return _decode(res);
  }

  /// Mirrors [_get]'s header/decode conventions for a JSON-body POST.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {String? childId}) async {
    final res = await _client.post(
      _uri(path, childId),
      headers: {
        'authorization': 'Bearer $sessionToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
    }
    return body;
  }

  Future<Map<String, dynamic>> fetchMe() => _get(mePath);
  Future<Map<String, dynamic>> fetchNow(String childId) => _get(childNow, childId: childId);
  Future<Map<String, dynamic>> fetchInbox(String childId) => _get(inbox, childId: childId);

  /// Checks [pin] against every LIVE guardian of [childId] -- POST
  /// kioskPinVerify, server/routes.mjs's real handler. This is the check
  /// kiosk_shell.dart's PIN gate calls after a kiosk defeat, replacing
  /// main_live.dart's former hardcoded '1273' demo stub.
  ///
  /// FAILS CLOSED, DELIBERATELY: a network error, a timeout, a malformed
  /// response body, or any non-2xx status all return `false` here, never
  /// `true` and never a thrown exception. A broken network must never be
  /// indistinguishable from "the PIN was correct" -- that would let a lost
  /// connection defeat the kiosk lock outright, which is a strictly worse
  /// failure mode than a rejected PIN a guardian can just retry.
  Future<bool> verifyKioskPin(String childId, String pin) async {
    try {
      final body = await _post(kioskPinVerify, {'pin': pin}, childId: childId);
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Sets/replaces the CALLER'S OWN guardian PIN -- POST guardianPinPath,
  /// server/routes.mjs's real handler. Requires a guardian session (the
  /// server returns 403 guardian_session_required for a child session).
  ///
  /// Unlike [verifyKioskPin] this is NOT fail-closed-to-a-bool: it's a
  /// guardian-initiated settings write, not a lock-defeat check something
  /// else's security posture depends on, so a caller needs the REAL reason a
  /// PIN couldn't be set (e.g. invalid_pin_format, guardian_session_required)
  /// rather than an opaque `false`. Throws [ApiException] on any non-2xx
  /// response, exactly like [fetchMe]/[fetchNow]/[fetchInbox] above.
  Future<void> setGuardianPin(String pin) async {
    await _post(guardianPinPath, {'pin': pin});
  }

  /// Requests a real WebAuthn REGISTRATION challenge -- POST the
  /// [webauthnRegisterChallenge] path, server/routes.mjs's real handler.
  /// Requires a guardian session (403 guardian_session_required for a child
  /// session). Named distinctly from the path constant above it calls (same
  /// disambiguation [setGuardianPin]/[guardianPinPath] already uses) so the
  /// two don't collide. Returns the raw `{challenge, rpId, userId}` body:
  /// webauthn_channel.dart's [buildRegisterPasskeyCallback] is what actually
  /// consumes it (feeds it straight to WebAuthnChannel.register()), not this
  /// class -- this class stays transport-only, matching every other method
  /// here.
  Future<Map<String, dynamic>> requestWebauthnRegisterChallenge() =>
      _post(webauthnRegisterChallenge, const {});

  /// Verifies a real WebAuthn REGISTRATION ceremony -- POST the
  /// [webauthnRegisterVerify] path, server/routes.mjs's real handler
  /// (challenge consumption, rpIdHash check, CBOR/COSE public-key
  /// extraction, credential storage). [clientDataJSON]/[attestationObject]
  /// must be the base64url strings WebAuthnBridge.kt's register() returned,
  /// untouched. Throws [ApiException] on any non-2xx response (e.g.
  /// challenge_mismatch, rpid_mismatch, origin_mismatch) -- a registration
  /// failure is a real fact the caller must see, not one to fail silently
  /// past.
  Future<void> submitWebauthnRegisterVerify({
    required String clientDataJSON,
    required String attestationObject,
  }) async {
    await _post(webauthnRegisterVerify,
        {'clientDataJSON': clientDataJSON, 'attestationObject': attestationObject});
  }

  void close() => _client.close();
}

/// Real WebAuthn LOGIN — the passkey ceremony's counterpart to [devLoginFor],
/// and free functions for the identical structural reason: server/index.mjs
/// implements both LOGIN routes outside api.register() because they
/// ESTABLISH a session (see that file's own header), so there is no existing
/// [OliveApi] instance -- which always already holds a session token -- to
/// hang these off of.
///
/// Takes a `userId` hint, not a discoverable-credential lookup -- see
/// server/index.mjs's webauthnLoginChallenge() for why (a real, deliberate
/// scope decision recorded there, not a shortcut). Returns the raw
/// `{challenge, rpId}` body.
Future<Map<String, dynamic>> webauthnLoginChallenge(
  String baseUrl,
  String userId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.webauthnLoginChallenge}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'userId': userId}),
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body;
}

/// Verifies a real WebAuthn LOGIN ceremony -- POST webauthnLoginVerify,
/// server/index.mjs's real handler (single-use challenge consume BEFORE
/// signature check, credential lookup, auth.ts's real verifyAssertion(),
/// sign-count update). All four assertion fields must be the base64url
/// strings WebAuthnBridge.kt's authenticate() returned, untouched. Returns
/// the new guardian session token on success, exactly like [devLoginFor].
Future<String> webauthnLoginVerify(
  String baseUrl, {
  required String userId,
  required String credentialId,
  required String clientDataJSON,
  required String authenticatorData,
  required String signature,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.webauthnLoginVerify}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'userId': userId,
      'credentialId': credentialId,
      'clientDataJSON': clientDataJSON,
      'authenticatorData': authenticatorData,
      'signature': signature,
    }),
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['token'] as String;
}

/// Dev-only login helper wrapping [OliveApi.devLoginPath] — see
/// server/index.mjs's own header for why this exists and its limits: no
/// credential is checked, and the server refuses this route entirely unless
/// started with DEV_LOGIN=1.
Future<String> devLoginFor(
  String baseUrl, {
  String? userId,
  String? childId,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.devLoginPath}'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({if (userId != null) 'userId': userId, if (childId != null) 'childId': childId}),
  );
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['token'] as String;
}
