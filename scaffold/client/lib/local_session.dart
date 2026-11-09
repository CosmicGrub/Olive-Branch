// OLIVE BRANCH — local session transport, for ad-hoc mode. UNVERIFIED by
// tools/verify.sh's own automated pipeline specifically (no Flutter
// toolchain to compile Dart at all) — a distinct claim from the real
// hardware verification below, not a contradiction of it. VERIFIED on real
// hardware (2026-08-30), after fixing a real bug this exact verification
// caught: see [LocalSessionServer.start]'s own doc comment for the VPN-
// interface failure a real two-device run surfaced, and
// local_play_screen.dart's own header for the full round-trip proof (Round
// 1 through Round 2, propagated live between a real Fold5 and a real
// Galaxy Tab) once it was fixed. Network resilience & ad-hoc mode roadmap,
// Track B Option 2.
//
// WHAT THIS IS: a small, direct HTTP exchange between two devices already
// found on the same local network (local_discovery.dart), carrying turn
// state for a game or a page-turn — plain JSON, nothing else.
//
// WHAT THIS IS NOT, and must never become: a media transport. §5.21.1 is
// "all media is relayed, always — never peer-to-peer," because a direct
// WebRTC connection lets each side learn the other's real IP, which for a
// family with a real protective order is a location fix on a protected
// party. This file carries no camera, no microphone, no video/audio frame
// of any kind, on any code path — that stays call_screen.dart's job,
// exclusively, always through LiveKit's relay. What IS true here, stated
// plainly rather than assumed safe by default: this device's local-network
// address is exposed to whatever else is on that same subnet the moment
// [LocalSessionServer.start] binds a socket — the same real exposure
// local_discovery.dart's own mDNS broadcast already carries, mitigated the
// same way: a local subnet is not a location fix (an IP a stranger could
// use to find someone), it is a room already shared with the other real
// person this session is for.
//
// The transport is deliberately dumb: one HTTP POST per turn, straight to
// the peer's own small server, no polling loop, no queue, no retry beyond
// what the caller wants to add. A turn-based game measured in seconds
// between moves has no need for anything more real-time than that, and
// "more real-time" is exactly the direction that starts requiring the kind
// of persistent negotiated connection this file exists to avoid building.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'lan_bind.dart';
import 'lan_pairing_transport.dart' show isLanAddress;
import 'local_discovery.dart';
import 'play_admission.dart';

/// A locally-received turn payload, handed to whoever is listening —
/// opaque JSON at this layer, given shape by the caller (see
/// LocalTwentyQuestionsSession below for the one real shape this session
/// currently defines).
typedef LocalTurnPayload = Map<String, dynamic>;

/// Runs on THIS device, listening for the other side's turns.
///
/// PRIVACY (owner requirement 2026-11-08). It listens ONLY on the addresses of real LAN interfaces (lan_bind.dart),
/// never on every interface, a VPN tunnel or a cellular link; it answers only a LAN source address; it is stopped by
/// [stop] when the game ends or the app leaves the foreground (play_lifecycle.dart); and its responses and requests
/// carry no `Server` or `User-Agent` header and no app-specific header or path (`/h` hello, `/t` turn).
///
/// Without an [admission] it keeps the older, open behaviour (single-device previews and legacy tests). With one, a
/// turn is accepted only as an encrypted frame from an admitted peer (play_admission.dart, play_frame.dart).
class LocalSessionServer {
  LocalSessionServer({
    required this.onTurnReceived,
    this.admission,
    this.bindAddresses,
    this.allowLoopback = false,
  });

  final void Function(LocalTurnPayload payload) onTurnReceived;
  final PlayAdmission? admission;

  /// Addresses to listen on. Null = the active LAN interfaces ([lanBindAddresses]). Tests pass loopback.
  final List<InternetAddress>? bindAddresses;

  /// Tests only: also answer loopback sources.
  final bool allowLoopback;

  final List<HttpServer> _servers = <HttpServer>[];
  int? get port => _servers.isEmpty ? null : _servers.first.port;
  bool get isListening => _servers.isNotEmpty;

  /// Binds one shared OS-assigned port on every LAN address at once (see lan_bind.dart for why every one, and only
  /// those). Throws [LocalSessionException] when the device is on no LAN: there is nothing safe to listen on.
  Future<void> start() async {
    final List<InternetAddress> addrs = bindAddresses ?? await lanBindAddresses();
    if (addrs.isEmpty) {
      throw const LocalSessionException("Can't find a local network to play on right now.");
    }
    int shared = 0;
    for (final InternetAddress a in addrs) {
      final HttpServer server = await HttpServer.bind(a, shared);
      shared = server.port;
      server.serverHeader = null;
      _servers.add(server);
      server.listen(_handle);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse res = request.response;
    try {
      final InternetAddress? from = request.connectionInfo?.remoteAddress;
      final bool hello = request.uri.path == '/h' && admission != null;
      final bool turn = request.uri.path == '/t';
      if (request.method != 'POST' || !(hello || turn) || from == null || !isLanAddress(from, allowLoopback: allowLoopback)) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      // Size cap (413) before anything is parsed: a declared length over the cap, or a chunked body that grows past
      // it, is refused without being buffered whole. The cap holds with or without admission.
      if (request.contentLength > kMaxTurnBytes) {
        res.statusCode = HttpStatus.requestEntityTooLarge;
        await res.close();
        return;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in request) {
        builder.add(chunk);
        if (builder.length > kMaxTurnBytes) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
          await res.close();
          return;
        }
      }
      final bytes = builder.takeBytes();
      final remote = from.address;
      if (hello) {
        final answer = await admission!.handleHello(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>, remote);
        if (answer == null) {
          res.statusCode = HttpStatus.noContent; // silence is indistinguishable from nobody listening
        } else {
          res.headers.contentType = ContentType.binary;
          res.write(jsonEncode(answer));
        }
        await res.close();
        return;
      }
      final List<int>? plain = admission == null ? bytes : await admission!.openTurn(bytes, remote);
      if (plain == null) {
        res.statusCode = HttpStatus.unauthorized;
        await res.close();
        return;
      }
      final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      onTurnReceived(payload);
      res.statusCode = HttpStatus.ok;
    } catch (e) {
      // A malformed payload from a genuine peer must never crash this device's own game state.
      res.statusCode = HttpStatus.badRequest;
    }
    await res.close();
  }

  Future<void> stop() async {
    final List<HttpServer> all = List<HttpServer>.of(_servers);
    _servers.clear();
    for (final HttpServer s in all) {
      await s.close(force: true);
    }
  }
}

/// Sends this device's own turn to a discovered peer. Best-effort by
/// design: a genuinely offline/no-longer-reachable peer must surface as an
/// honest, real failure to the caller (never silently swallowed — unlike
/// this codebase's many *bookkeeping* best-effort posts, a dropped turn is
/// the actual content of this feature, not metadata alongside it), but
/// this class itself stays a thin, honest transport rather than growing
/// its own retry/backoff policy — that's the caller's real decision to
/// make per activity, the same way call_screen.dart's own reconnect budget
/// is a call-specific choice, not a transport-layer default.
class LocalSessionClient {
  LocalSessionClient(this.peer, {this.session});
  final LocalPeer peer;

  /// The authenticated, encrypting session from [PlaySession.hello]; null sends the legacy plain turn.
  final PlaySession? session;

  HttpClient _client() => HttpClient()..userAgent = null;

  /// One POST of JSON to `/h` for [PlaySession.hello]: the answer, or null for silence or any failure.
  Future<Map<String, dynamic>?> postHello(Map<String, dynamic> body) async {
    final client = _client();
    try {
      final request = await client
          .postUrl(Uri.parse('http://${peer.host}:${peer.port}/h'))
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.binary;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> sendTurn(LocalTurnPayload payload) async {
    final client = _client();
    try {
      final request = await client
          .postUrl(Uri.parse('http://${peer.host}:${peer.port}/t'))
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.binary;
      final plain = utf8.encode(jsonEncode(payload));
      final s = session;
      request.add(s == null ? plain : await s.sealTurn(plain));
      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok) {
        throw LocalSessionException('Peer refused the turn (${response.statusCode}).');
      }
      await response.drain<void>();
    } on LocalSessionException {
      rethrow;
    } on ArgumentError {
      throw const LocalSessionException('That move is too big to send.');
    } catch (e) {
      throw const LocalSessionException("Couldn't reach the other player right now.");
    } finally {
      client.close();
    }
  }
}

/// Real, honest failure — see [LocalSessionClient.sendTurn]'s own doc
/// comment on why this is surfaced rather than swallowed. Message text
/// follows the same child-safe vocabulary discipline as call_screen.dart's
/// own [CallScreen] error state (no "failed", no "check your network" —
/// see MASTERFILE §5.23.2's banned-phrase list).
class LocalSessionException implements Exception {
  const LocalSessionException(this.message);
  final String message;
  @override
  String toString() => message;
}
