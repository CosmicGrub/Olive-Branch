// OLIVE BRANCH — local session transport, for ad-hoc mode. VERIFIED on real
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
import 'local_discovery.dart';

/// A locally-received turn payload, handed to whoever is listening —
/// opaque JSON at this layer, given shape by the caller (see
/// LocalTwentyQuestionsSession below for the one real shape this session
/// currently defines).
typedef LocalTurnPayload = Map<String, dynamic>;

/// Runs on THIS device, listening for the other side's turns. One real
/// endpoint, `POST /turn`, matching this file's own "deliberately dumb"
/// posture — no auth beyond "you found this device on the local network
/// you are both physically on," the same trust boundary a same-room
/// hand-off already carries.
class LocalSessionServer {
  LocalSessionServer({required this.onTurnReceived});

  final void Function(LocalTurnPayload payload) onTurnReceived;

  HttpServer? _server;
  int? get port => _server?.port;

  /// Binds to port 0 (OS-assigned) on every local interface at once —
  /// deliberately not scoped to whichever single address the caller thinks
  /// is "this device's own." Confirmed real, on real hardware, why that
  /// matters: a device can have more than one active network path
  /// simultaneously (real Wi-Fi plus, say, an always-on personal VPN's own
  /// tunnel interface), and there is no reliable way to know in advance
  /// which one local_discovery.dart's mDNS broadcast will end up advertising
  /// as this device's reachable host — that choice is bonsoir/the OS's mDNS
  /// stack's own, made independently of whatever local_play_screen.dart
  /// might separately guess via ownLocalIPv4(). The two disagreeing is
  /// exactly the failure this two-device test caught: the server bound only
  /// to a VPN tunnel address while mDNS kept advertising the real Wi-Fi
  /// address, so the peer's POST to that real, advertised address hit a
  /// closed port — "Connection refused", confirmed via a direct curl probe
  /// from the other device, not guessed. Binding to every interface at once
  /// means whichever address mDNS ends up advertising, this server is
  /// already listening there — nothing here has to guess right.
  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/turn') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      try {
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        onTurnReceived(payload);
        request.response.statusCode = HttpStatus.ok;
      } catch (e) {
        // A malformed payload from a genuine peer must never crash this
        // device's own game state — same "never blame a foreign payload"
        // posture call_screen.dart's own DataReceivedEvent handler already
        // holds itself to.
        request.response.statusCode = HttpStatus.badRequest;
      }
      await request.response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
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
  LocalSessionClient(this.peer);
  final LocalPeer peer;

  Future<void> sendTurn(LocalTurnPayload payload) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('http://${peer.host}:${peer.port}/turn'))
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok) {
        throw LocalSessionException('Peer refused the turn (${response.statusCode}).');
      }
      await response.drain<void>();
    } on LocalSessionException {
      rethrow;
    } catch (e) {
      throw LocalSessionException("Couldn't reach ${peer.name} right now.");
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
