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
  // Path constants only, contract-checked against the registered server
  // routes by packages/api/test/contract.test.mjs (and by transport.test.mjs's
  // own "I · CLIENT CONTRACT" section, which scans every .dart file's string
  // literals) -- the Dart CALLING code that actually uses these lands in a
  // later phase; see server/routes.mjs and server/index.mjs for the real,
  // already-implemented, already-tested server side of every one of these.
  static const kioskPinVerify = '/v1/children/:childId/kiosk-pin/verify';
  static const setGuardianPin = '/v1/me/pin';
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

  void close() => _client.close();
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
