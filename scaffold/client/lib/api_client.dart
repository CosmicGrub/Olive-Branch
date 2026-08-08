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

  // --- login (dev-only — see server/index.mjs's own header comment) ------
  static const devLoginPath = '/v1/auth/dev-login';

  // --- network play (§5.14, §5.17, §5.19) ---------------------------------
  // Relayed through this app's own authenticated backend — never
  // peer-to-peer, never LAN-discovered. See scaffold/server/game_tables.mjs
  // and scaffold/packages/game-sync/src/table.ts for the server side.
  static const gameTables = '/v1/game-tables';
  static const gameTableJoin = '/v1/game-tables/:tableId/join';

  Uri _uri(String path, [String? childId]) => Uri.parse(
      '$baseUrl${childId != null ? path.replaceFirst(':childId', childId) : path}');

  Future<Map<String, dynamic>> _get(String path, {String? childId}) async {
    final res = await _client.get(_uri(path, childId),
        headers: {'authorization': 'Bearer $sessionToken'});
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'authorization': 'Bearer $sessionToken', 'content-type': 'application/json'},
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

  /// Requests a short-lived, single-use join token for a live network-play
  /// table. Exactly one of [partnerChildId] (a guardian inviting a specific
  /// child, or one sibling inviting another) or [partnerUserId] (a child
  /// inviting a specific adult) must be supplied. This call carries no
  /// authorization decision of its own — the server independently verifies
  /// the pairing against the real family graph (guardianship or
  /// sibling_link) before ever minting a token; a denial surfaces as a real
  /// [ApiException] (403) naming the reason.
  Future<GameTableTicket> requestGameTable({
    required String game,
    String? partnerChildId,
    String? partnerUserId,
  }) async {
    assert((partnerChildId == null) != (partnerUserId == null),
        'exactly one of partnerChildId/partnerUserId must be supplied');
    final body = await _post(gameTables, {
      'game': game,
      if (partnerChildId != null) 'partnerChildId': partnerChildId,
      if (partnerUserId != null) 'partnerUserId': partnerUserId,
    });
    return GameTableTicket.fromJson(body);
  }

  /// Joins an existing table by id (shared out of band by the inviting
  /// device — e.g. shown on screen as a short code). The server
  /// independently re-verifies this caller is actually one of that table's
  /// two authorized seats, re-checking the family graph fresh rather than
  /// trusting anything decided when the table was opened, before minting a
  /// token for them.
  Future<GameTableTicket> joinGameTable(String tableId) async {
    final body = await _post(gameTableJoin.replaceFirst(':tableId', tableId), const {});
    return GameTableTicket.fromJson(body);
  }

  void close() => _client.close();
}

/// A minted, short-lived, single-use credential for exactly one seat at
/// exactly one live-play table. Scoped and time-boxed server-side — see
/// packages/game-sync/src/table.ts's own header for the invariants this
/// carries (T2/T3/T5).
class GameTableTicket {
  const GameTableTicket({
    required this.tableId,
    required this.seat,
    required this.token,
    required this.ttlSeconds,
    required this.wsPath,
  });

  factory GameTableTicket.fromJson(Map<String, dynamic> json) => GameTableTicket(
        tableId: json['tableId'] as String,
        seat: json['seat'] as int,
        token: json['token'] as String,
        ttlSeconds: json['ttlSeconds'] as int,
        wsPath: json['wsPath'] as String,
      );

  final String tableId;
  final int seat;
  final String token;
  final int ttlSeconds;
  final String wsPath;
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
