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
// /inbox, and (as of this pass) GET .../availability + PUT /v1/me/availability
// — not the full list; calling an unimplemented one gets a real 404 from the
// real router, not a fake one.
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.error, {this.message});
  final int statusCode;
  final String error;
  /// Plain-language explanation, when the server sent one (e.g. a certified
  /// export denial reason — see server/routes.mjs's EXPORT_DENIAL_MESSAGES).
  /// Null for endpoints that don't send one.
  final String? message;
  @override
  String toString() => 'ApiException($statusCode, $error)';
}

/// One recognized homework problem, as returned by POST
/// [OliveApi.homeworkCapture] on success. `hint` has already been through
/// the server's real guardHint() (packages/homework/src/capture.ts) — it is
/// always safe to show a parent verbatim, never a raw model/generator
/// output. §9.1's "hint, don't solve" is the SAME server-side guard on
/// every path (real capture and homework_screen.dart's demo fallback both
/// end up calling guardHint before anything reaches the screen), just
/// applied server-side here instead of client-side.
class HomeworkProblemResult {
  const HomeworkProblemResult({required this.text, required this.hint, required this.hintRefused});

  /// OCR'd text of this one problem (see packages/homework/src/split.ts's
  /// numbered-list heuristic for how the server broke the page up).
  final String text;

  /// Already guarded — safe to render as-is.
  final String hint;

  /// True when the rule-based generator's own hint (packages/homework/src/
  /// hints.ts — NOT an AI model, see that file's header) was refused by the
  /// guard and [hint] is the guard's safe fallback instead. Kept for tests/
  /// analytics; never itself rendered as a "this was refused" message to
  /// her (§9.1 — she only ever sees a hint, not a refusal notice).
  final bool hintRefused;

  factory HomeworkProblemResult.fromJson(Map<String, dynamic> j) => HomeworkProblemResult(
    text: j['text'] as String? ?? '',
    hint: j['hint'] as String? ?? '',
    hintRefused: j['hintRefused'] as bool? ?? false,
  );
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

  // --- custody schedule (§5.4, §9.4) --------------------------------------
  // Read-only view of the real custody_order row -- see
  // family_agreement_screen.dart's own header for why this is deliberately
  // NOT a bespoke "agreement" document endpoint.
  static const custodyOrder = '/v1/children/:childId/custody-order';

  // --- async delivery (§7.3) ---------------------------------------------
  static const inbox    = '/v1/children/:childId/inbox';
  static const messages = '/v1/children/:childId/messages';
  static const batches  = '/v1/children/:childId/batches';

  // --- child agency (§7.10) ----------------------------------------------
  static const ping    = '/v1/children/:childId/ping';
  static const journal = '/v1/children/:childId/journal';

  // --- archive (§7.9) ------------------------------------------------------
  /// §16.1 #3, §2.11 — free, unlimited, every tier. Backs deletion_screen
  /// .dart's "Download raw export" button. GET, matching MASTERFILE §7.9's
  /// own documented shape (`GET .../export  full portable bundle`) and
  /// server/routes.mjs's real registration.
  static const export_ = '/v1/children/:childId/export';

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

  // --- guardian availability (§9, MARKUP screen 'availability') ----------
  // Real as of this pass — server/routes.mjs, packages/db/src/pool.mjs's
  // setAvailabilityWindows()/availabilityFor(), db/migrations/0010_availability.sql.
  static const childAvailability = '/v1/children/:childId/availability';
  static const meAvailability    = '/v1/me/availability';
  // --- homework OCR capture (§9.1, §20.2b) --------------------------------
  static const homeworkCapture = '/v1/children/:childId/homework/capture';
  // --- account lifecycle (§2.10, §2.11, §9.8, P8) -------------------------
  static const deleteAccountPath = '/v1/me/delete';
  // --- court export (§2.11, §16.1 #3) -------------------------------------
  // Certified export reuses `export_` above (same route, `?kind=certified`)
  // rather than a second path constant for the identical URL — server/
  // routes.mjs's single GET .../export handler dispatches on that query
  // param, not on a second registration (api.ts's register() has no
  // duplicate-route guard; a second registration for the same method+path
  // would just be silently unreachable dead code behind the first).

  // --- login (dev-only — see server/index.mjs's own header comment) ------
  static const devLoginPath = '/v1/auth/dev-login';

  // --- push notifications (MASTERFILE §11) --------------------------------
  // Real routes as of this pass — scaffold/server/routes.mjs, backed by
  // packages/db/src/pool.ts's registerDeviceToken/unregisterDeviceToken.
  // Never carries content: just {platform, token}. See push_channel.dart for
  // the real caller (permission request, token fetch, refresh listener).
  static const deviceTokens = '/v1/me/device-tokens';

  // --- guardian invitation (§11, §8.5) -------------------------------------
  // Create requires a real guardian session (this class's own [_post]);
  // the invited party has none yet, so read/accept below are free functions
  // matching webauthnLoginChallenge/Verify's own shape, not instance methods.
  static const guardianships = '/v1/children/:childId/guardianships';
  static const guardianInvite = '/v1/guardian-invites/:inviteId';
  static const guardianInviteAccept = '/v1/guardian-invites/:inviteId/accept';
  static const guardianInviteRevoke = '/v1/guardian-invites/:inviteId/revoke';

  Uri _uri(String path, [String? childId, Map<String, String>? query]) => Uri.parse(
      '$baseUrl${childId != null ? path.replaceFirst(':childId', childId) : path}')
          .replace(queryParameters: query);

  Future<Map<String, dynamic>> _get(
    String path, {
    String? childId,
    Map<String, String>? query,
  }) async {
    final res = await _client.get(_uri(path, childId, query),
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

  /// Mirrors [_post]'s header/decode conventions for a JSON-body PUT
  /// (replace-all semantics — see [setAvailability]).
  Future<Map<String, dynamic>> _put(String path, {String? childId, required Object body}) async {
    final res = await _client.put(_uri(path, childId),
        headers: {
          'authorization': 'Bearer $sessionToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body));
    return _decode(res);
  }

  /// Mirrors [_post]'s header/decode conventions for a JSON-body DELETE —
  /// MASTERFILE §11's `DELETE /v1/me/device-tokens` (unregistering a device
  /// on sign-out/uninstall), the one caller that needs it.
  Future<Map<String, dynamic>> _delete(String path, Map<String, dynamic> body) async {
    final res = await _client.delete(_uri(path),
        headers: {
          'authorization': 'Bearer $sessionToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(body));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error'] as String? ?? 'error',
          message: body['message'] as String?);
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

  /// Invites a new guardian/adult into [childId]'s family graph -- POST
  /// guardianships, server/routes.mjs's real handler. Requires a live
  /// guardian session already holding a guardian edge to this exact child
  /// (checked server-side; a 403 not_a_guardian_of_child or
  /// child_cannot_invite comes back as [ApiException] like any other
  /// non-2xx response here). Does NOT create a guardianship row for the
  /// invited party -- see 0014_guardian_invite.sql's own header for why:
  /// this route closes invite creation, not account creation, which this
  /// codebase has never built for a brand-new guardian.
  Future<Map<String, dynamic>> createGuardianInvite(
    String childId, {
    required String role,
    required String label,
    required String invitedEmail,
  }) => _post(guardianships, {'role': role, 'label': label, 'invitedEmail': invitedEmail},
      childId: childId);

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

  /// `{windows: [{guardianId, weekday, startLocal, endLocal, note}, ...]}` —
  /// every co-guardian's windows for `childId`, INCLUDING the caller's own
  /// (see pool.mjs's availabilityFor() header for why). Decoding into a
  /// domain shape is left to the caller, matching fetchNow/fetchInbox above.
  Future<Map<String, dynamic>> getAvailability(String childId) =>
      _get(childAvailability, childId: childId);

  /// Replace-all: `windows` is the caller's ENTIRE new set for every call,
  /// never a delta — omitting a day clears it. Each map is
  /// `{weekday, startLocal, endLocal, note}`; no `guardianId` field — the
  /// server always uses the authenticated caller's own identity
  /// (server/routes.mjs's PUT /v1/me/availability), never anything the body
  /// could redirect.
  Future<Map<String, dynamic>> setAvailability(List<Map<String, dynamic>> windows) =>
      _put(meAvailability, body: windows);

  /// Posts a raw homework photo (PNG or JPEG bytes — server/routes.mjs's
  /// handler sniffs real magic bytes, not a filename or content-type) as
  /// base64 in a JSON body, and runs it through the real quality gate + OCR
  /// + guarded-hint pipeline (packages/homework/src/capture-route.ts).
  ///
  /// Unlike [_get]'s all-4xx/5xx-throw contract, a 422 quality-gate refusal
  /// is a normal, expected outcome here — the exact same "one more try" flow
  /// retake_screen.dart already renders for a failing *simulated* verdict
  /// (see capture_gate.dart) — so this decodes and returns that body
  /// directly instead of throwing, and only throws [ApiException] for a
  /// genuinely unexpected status.
  Future<Map<String, dynamic>> captureHomework(String childId, List<int> imageBytes) async {
    final res = await _client.post(
      _uri(homeworkCapture, childId),
      headers: {'authorization': 'Bearer $sessionToken', 'content-type': 'application/json'},
      body: jsonEncode({'image': base64Encode(imageBytes)}),
    );
    final body =
        res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 || res.statusCode == 422) return body;
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }

  /// `{ order: {...} }` for a real custody order, or `{ order: null }` when
  /// this child has none on file yet -- an honest absence server/routes.mjs
  /// returns rather than a 404, see that route's own comment.
  Future<Map<String, dynamic>> getCustodyOrder(String childId) =>
      _get(custodyOrder, childId: childId);

  /// POST /v1/me/delete — MASTERFILE §2.10, §2.11, §9.8, P8. Deactivates the
  /// CALLING guardian's own account (server/routes.mjs resolves the target
  /// from the verified session; nothing this method sends can widen or
  /// redirect it). See packages/db/src/pool.ts's deactivateAccount() for
  /// exactly what survives (delivered messages, the parent-to-parent log,
  /// the child's preserved archive) and what does not (queued/undelivered
  /// delivery_intent rows, PIN/passkey credentials, the login itself). On
  /// success the response body carries `ok: true` plus counts of what was
  /// removed; on failure this throws [ApiException] with the server's real
  /// reason (`already_deactivated`, `account_not_found`, `no_user_identity`,
  /// or a transport/auth failure) — deletion_screen.dart's `_confirm()` is
  /// the caller responsible for turning that into honest on-screen copy.
  /// No real body to send — server resolves the target from the session,
  /// same empty-map convention [requestWebauthnRegisterChallenge] already
  /// uses for a POST with nothing to carry.
  Future<Map<String, dynamic>> deleteAccount() => _post(deleteAccountPath, const {});

  /// Response shape (server/routes.mjs, packages/db/src/pool.mjs's
  /// rawExportBundleFor): `{bundle, bundleJson, exportRecordId, bundleHash}`.
  /// `bundleJson` is the EXACT string `bundleHash` was computed over — a
  /// caller that wants to verify the hash should hash/persist that field,
  /// not re-encode `bundle` itself (see routes.mjs's own comment on why).
  Future<Map<String, dynamic>> fetchRawExport(String childId) =>
      _get(export_, childId: childId);

  /// GET /v1/children/:childId/export?kind=certified — §2.11, §16.1 #3.
  /// Same route as [fetchRawExport], distinguished by the `kind` query
  /// param server-side (routes.mjs's single handler dispatches on it, not a
  /// second registration — see `export_`'s own doc comment above). A denial
  /// (annual allowance used / tier required / a broken chain / not a
  /// guardian of this child) surfaces as an [ApiException] with the real
  /// server-reported `error` reason and plain-language `message`, never a
  /// silent failure or a fabricated success.
  Future<Map<String, dynamic>> fetchCertifiedExport(String childId) =>
      _get(export_, childId: childId, query: const {'kind': 'certified'});

  /// POST .../messages — server/routes.mjs's real counterpart to
  /// [fetchInbox], and the real backend for receipt_screen.dart's "Send one
  /// back". Runs through captureMessage() server-side for validation before
  /// anything is persisted (see that route's own header): a rejection —
  /// wrong sender, an empty recording, a night already past — comes back as
  /// a real [ApiException], not a fake 200. Returns the created intent's id,
  /// its media artifact id, and its starting state ('pending').
  Future<Map<String, dynamic>> sendMessage(
    String childId, {
    required String storageKey,
    required int durationMs,
    String? captionKey,
    String? targetLocalDate,
    String daypart = 'bedtime',
    bool preserve = false,
  }) =>
      _post(messages, {
        'storageKey': storageKey,
        'durationMs': durationMs,
        if (captionKey != null) 'captionKey': captionKey,
        if (targetLocalDate != null) 'targetLocalDate': targetLocalDate,
        'daypart': daypart,
        'preserve': preserve,
      }, childId: childId);

  /// POST /v1/me/device-tokens — {platform, token[, channel]} in, the new
  /// device_token row's real id out. `platform` must be 'android' or 'ios'
  /// (server-side DEVICE_PLATFORMS check, routes.mjs). Content-free by
  /// construction — there is nothing else this call could carry.
  ///
  /// `channel` (§8.11.4, v0.49.11) is OPTIONAL and OMITTED from the request
  /// body entirely when null — never sent as a literal `"channel": null`.
  /// The server's own 0015 migration treats omission and an explicit null
  /// identically (NULL, "unknown," never a guessed default), but omitting
  /// the key is the more honest wire shape: this call genuinely does not
  /// know the value, rather than asserting a null fact about it.
  Future<String> registerDeviceToken({
    required String platform,
    required String token,
    String? channel,
  }) async {
    final body = await _post(deviceTokens, {
      'platform': platform,
      'token': token,
      if (channel != null) 'channel': channel,
    });
    return body['id'] as String;
  }

  /// DELETE /v1/me/device-tokens — {token} in, whether a row actually
  /// existed to delete out. No call site in this client yet (no sign-out
  /// flow exists in lib/ as of this pass — see push_channel.dart's own
  /// `unregister()` doc comment); kept symmetric with the server route so
  /// wiring a future sign-out is a one-line call, not a new endpoint.
  Future<bool> unregisterDeviceToken(String token) async {
    final body = await _delete(deviceTokens, {'token': token});
    return body['deleted'] as bool;
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

/// Reads a pending guardian invitation by its own id -- GET guardianInvite,
/// server/routes.mjs's real handler. No session: the invite's own long,
/// random id is what authorizes reading it (mirrors [webauthnLoginChallenge]'s
/// single-use-challenge posture for a not-yet-authenticated caller). Returns
/// `null` for a 404 (never existed) rather than throwing, since "no such
/// invite" is an ordinary, expected outcome here -- invitation_screen.dart's
/// real path reads this the same honest way [OliveApi.verifyKioskPin] treats
/// its own "false" as data, not an error.
Future<Map<String, dynamic>?> fetchGuardianInvite(
  String baseUrl,
  String inviteId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.get(
    Uri.parse('$baseUrl${OliveApi.guardianInvite.replaceFirst(':inviteId', inviteId)}'));
  if (res.statusCode == 404) return null;
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['invite'] as Map<String, dynamic>;
}

/// Records the real accept decision -- POST guardianInvite/accept, server/
/// routes.mjs's real handler. No session, same reasoning as
/// [fetchGuardianInvite]. Does NOT create a guardianship row -- see
/// 0014_guardian_invite.sql's own header. Throws [ApiException] on any
/// non-2xx response (expired/already_accepted/revoked/not_found are all
/// real, distinguishable failures a caller needs, not an opaque bool).
Future<Map<String, dynamic>> acceptGuardianInvite(
  String baseUrl,
  String inviteId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.guardianInviteAccept.replaceFirst(':inviteId', inviteId)}'),
    headers: {'content-type': 'application/json'},
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
  return body['invite'] as Map<String, dynamic>;
}

/// Cancels a pending invite before it's accepted -- POST guardianInviteRevoke,
/// server/routes.mjs's real handler. Requires a guardian session (only the
/// inviting guardian may revoke, checked server-side via RLS -- see
/// 0014_guardian_invite.sql's own header). No client screen calls this yet
/// (no "manage sent invites" surface exists) -- the route and this wiring
/// are real and tested regardless, ready for whenever one does, matching
/// this codebase's own convention of a real client constant sometimes
/// arriving ahead of the screen that will use it.
Future<void> revokeGuardianInvite(
  String baseUrl,
  String inviteId,
  String sessionToken, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final res = await c.post(
    Uri.parse('$baseUrl${OliveApi.guardianInviteRevoke.replaceFirst(':inviteId', inviteId)}'),
    headers: {
      'authorization': 'Bearer $sessionToken',
      'content-type': 'application/json',
    },
  );
  final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw ApiException(res.statusCode, body['error'] as String? ?? 'error');
  }
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
