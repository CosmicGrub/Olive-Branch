// OLIVE BRANCH — local device discovery, for ad-hoc mode. UNVERIFIED by
// tools/verify.sh's own automated pipeline specifically (no Flutter
// toolchain to compile Dart at all) — a distinct claim from the real
// hardware verification below, not a contradiction of it. VERIFIED on real
// hardware (2026-08-30) — real bidirectional mDNS discovery between a real
// Fold5 and a real Galaxy Tab on the same LAN, each resolving the other's
// real broadcast (host, port, role, name) and correctly filtering out its
// own. See local_play_screen.dart's own header for the full two-device
// run this class was proven in, including a real, reproducible bonsoir/
// Android TXT-record hiccup this discovery layer surfaces honestly as a
// genuine "lost" event rather than hiding it. Network resilience & ad-hoc
// mode roadmap, Track B Option 2.
//
// Finds the other device when there is NO usable path to the internet at
// all — no WAN, a captive-portal wifi, or literally no shared network
// infrastructure — but both devices ARE on the same local subnet. This is
// deliberately NOT a latency optimization for the already-working case
// (two devices with real internet already get a fast, safe call for free
// via LiveKit's own nearest-edge routing) — see local_session.dart's own
// header for what this transport carries and, just as importantly, what
// it never does.
//
// mDNS via `bonsoir` — confirmed real, actively maintained, does BOTH
// halves of discovery (this device broadcasting its own presence AND
// browsing for the other side's), which a query-only package would not.
// Spiked against the installed package version before writing this, not
// guessed: `BonsoirBroadcast`/`BonsoirDiscovery` share one `start()`/
// `stop()`/`eventStream` shape (`BonsoirActionHandler`), and a discovered
// service only carries a real, connectable `host` once resolved via
// `service.resolve(discovery.serviceResolver)` — `ResolvedBonsoirService`
// is a distinct type from the bare `BonsoirService` a "found" event
// carries, not an automatic upgrade.
library;

import 'dart:async';
import 'dart:convert' show base64Url;
import 'dart:io';
import 'dart:math' show Random;
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'play_admission.dart';

/// The mDNS service type. RFC 6763: ASCII letters, digits and hyphens, 1-15 characters. Chosen to reveal as little as a
/// type can: no app or brand name, no word like "family" or "child" (it was `_olivebranch._tcp`). It is still a constant,
/// so "some app advertises this type" remains unavoidably observable to anyone on the same network; everything else
/// about a session is a seat label and a random per-lobby token that changes every time.
const String localServiceType = '_gp._tcp';

/// A real, resolved peer on the local network — host and port this device can actually open a connection to.
/// Nothing in it is a name: [name] is only a seat label ("Player one"), [token] the peer's per-lobby random key.
class LocalPeer {
  const LocalPeer({required this.host, required this.port, required this.role, required this.name, this.token});
  final String host;
  final int port;

  /// 'seat1' / 'seat2' (older callers compared against 'ivy' / 'dad'; nothing identifying travels any more).
  final String role;
  final String name;

  /// The peer's lobby token (random, per lobby, rotates): what tells two nearby lobbies apart. Null for a test peer.
  final String? token;

  @override
  String toString() => 'LocalPeer($name)';
}

/// Advertises THIS device on the local network and, at the same time, listens for the other side. Symmetric by design.
///
/// WHAT IT BROADCASTS (owner requirement 2026-11-08): the instance name is the seat label "Player one" or "Player two";
/// the TXT record has exactly two entries, `s` (the seat digit) and `k` (a random per-lobby token, the lobby's public key
/// from play_admission.dart when there is one). No name, no model, no family or device id, no role, and nothing that is
/// the same from one session to the next. Peers disambiguate by token and the admission handshake, never by names.
/// The seat is random per lobby; if two nearby devices show the same seat, the one with the smaller token flips.
/// What a pairing controller needs from discovery: peers found, peers lost, start and stop. [LocalDiscovery] is the
/// real one (mDNS); a test supplies a fake so two controllers can find each other over loopback.
abstract class PeerDiscovery {
  Stream<LocalPeer> get peers;
  Stream<String> get lost;
  Future<void> start();
  Future<void> stop();
}

class LocalDiscovery implements PeerDiscovery {
  LocalDiscovery({required this.role, required this.displayName, required this.servePort, this.lobbyToken, int? seat})
      : _seat = seat ?? randomSeat();

  /// Kept for call compatibility; NEVER put on the wire.
  final String role;
  final String displayName;
  final int servePort;

  /// The lobby's public key token (play_admission.dart). Null makes a random one (no admission configured).
  final String? lobbyToken;
  int _seat;
  late final String _token = lobbyToken ?? _randomToken();

  static String _randomToken() => base64Url.encode(List<int>.generate(24, (_) => Random.secure().nextInt(256))).replaceAll('=', '');

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _eventSub;
  final _peers = StreamController<LocalPeer>.broadcast();
  final _lost = StreamController<String>.broadcast();
  final Map<String, String> _shown = <String, String>{};

  int get seat => _seat;
  String get seatName => seatLabel(_seat);

  /// A real, resolved peer, once found. May fire more than once for the same peer.
  @override
  Stream<LocalPeer> get peers => _peers.stream;

  /// The seat label of a previously-found peer that went away.
  @override
  Stream<String> get lost => _lost.stream;

  /// What this device puts on the network, exposed so a test can prove it names nothing.
  @visibleForTesting
  BonsoirService advertisedService() => _service();

  BonsoirService _service() => BonsoirService(
        name: seatLabel(_seat),
        type: localServiceType,
        port: servePort,
        attributes: <String, String>{'s': '$_seat', 'k': _token},
      );

  @override
  Future<void> start() async {
    final broadcast = BonsoirBroadcast(service: _service());
    _broadcast = broadcast;
    await broadcast.ready;
    await broadcast.start();

    final discovery = BonsoirDiscovery(type: localServiceType);
    _discovery = discovery;
    await discovery.ready;
    listenToEvents(discovery.eventStream);
    await discovery.start();
  }

  /// Subscribes to a discovery event stream and KEEPS the subscription so [stop] can cancel it. Public only so a test
  /// can feed it a fake stream.
  @visibleForTesting
  void listenToEvents(Stream<BonsoirDiscoveryEvent>? events) {
    unawaited(_eventSub?.cancel());
    _eventSub = events?.listen(_handleDiscoveryEvent);
  }

  Future<void> _flipSeat(int next) async {
    _seat = next;
    try {
      await _broadcast?.stop();
      final broadcast = BonsoirBroadcast(service: _service());
      _broadcast = broadcast;
      await broadcast.ready;
      await broadcast.start();
    } catch (_) {
      // Advertising again failed; the next lobby starts clean.
    }
  }

  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        // Not yet connectable — no host until resolved.
        unawaited(event.service?.resolve(discovery!.serviceResolver));
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service;
        if (service is ResolvedBonsoirService && service.host != null) {
          final token = service.attributes['k'];
          // Never a peer talking to itself: our own token is how we recognise our own broadcast.
          if (token == null || token == _token) return;
          // Everything a peer sends is untrusted: only a plain digit seat and an opaque token are read, and the only
          // text ever shown is OUR seat label for that digit.
          final peerSeat = parseSeat(service.attributes['s']) ?? 0;
          final shown = peerSeat == 0 ? kNeutralPeerName : seatLabel(peerSeat);
          _shown[service.name] = shown;
          if (peerSeat != 0) {
            final next = seatAfterClash(mySeat: _seat, myToken: _token, peerSeat: peerSeat, peerToken: token);
            if (next != _seat) unawaited(_flipSeat(next));
          }
          _peers.add(LocalPeer(
            host: service.host!,
            port: service.port,
            role: 'seat$peerSeat',
            name: shown,
            token: token,
          ));
        }
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final svc = event.service;
        final name = svc == null ? null : _shown.remove(svc.name);
        if (name != null && !_lost.isClosed) _lost.add(name);
      default:
        return;
    }
  }

  /// Exposed only so [_handleDiscoveryEvent] can reach the same ServiceResolver instance bonsoir minted for this
  /// discovery session.
  BonsoirDiscovery? get discovery => _discovery;

  @override
  Future<void> stop() async {
    // First: nothing may deliver into the controllers closed below.
    final StreamSubscription<BonsoirDiscoveryEvent>? sub = _eventSub;
    _eventSub = null;
    await sub?.cancel();
    try {
      await _broadcast?.stop();
    } catch (_) {
      // Nothing to stop (never started, or the platform is gone).
    }
    try {
      await _discovery?.stop();
    } catch (_) {
      // Same.
    }
    await _peers.close();
    await _lost.close();
  }
}

/// Best-effort local IP discovery. NOT used to pick a bind address anymore
/// — local_session.dart's own [LocalSessionServer.start] binds every
/// interface at once now, precisely because guessing a single "right" one
/// here turned out to be unreliable on real hardware (see that function's
/// own doc comment for the real failure this caused). What's left is purely
/// an honest existence check: is there any non-loopback network interface
/// at all, so local_play_screen.dart can fail fast with a real "no network"
/// message instead of spinning in "Looking nearby…" forever on a device
/// that was never on a LAN to begin with. Never transmitted anywhere as a
/// claimed location (P3 has nothing to do with a device knowing its own LAN
/// address; this is purely "is there a NIC to listen on").
Future<String?> ownLocalIPv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: false);
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {
    // No real interface reachable — the honest "nothing local to bind"
    // case local_session.dart's own caller must handle either way.
  }
  return null;
}
