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
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';

/// RFC 6763: ASCII letters/digits/hyphens only, 1-15 chars, no leading/
/// trailing/doubled hyphen. "olivebranch" (11) fits with room to spare.
const String localServiceType = '_olivebranch._tcp';

/// A real, resolved peer on the local network — host and port this device
/// can actually open a connection to, not just a name that was seen.
class LocalPeer {
  const LocalPeer({required this.host, required this.port, required this.role, required this.name});
  final String host;
  final int port;
  /// 'dad' or 'ivy' — same real identity vocabulary call_screen.dart
  /// already uses, carried in the mDNS TXT record so each side knows who
  /// it found without a separate handshake round-trip.
  final String role;
  final String name;

  @override
  String toString() => 'LocalPeer($name, $role, $host:$port)';
}

/// Advertises THIS device on the local network and, at the same time,
/// listens for the other side. Symmetric by design — a same-room pairing
/// has no natural "server" and "client" role at the discovery layer, only
/// at the small HTTP hop local_session.dart builds on top of once a peer
/// is found.
class LocalDiscovery {
  LocalDiscovery({required this.role, required this.displayName, required this.servePort});

  final String role;
  final String displayName;
  final int servePort;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  final _peers = StreamController<LocalPeer>.broadcast();
  final _lost = StreamController<String>.broadcast();

  /// A real, resolved peer, once found. May fire more than once for the
  /// same peer (a service can be re-resolved) — callers dedupe on
  /// [LocalPeer.host] the same "not equal to what I've already seen"
  /// pattern this codebase already uses for its dev-only pending-call poll
  /// (main_live_child_call_test.dart's own `_lastSeenKey`).
  Stream<LocalPeer> get peers => _peers.stream;

  /// The peer's own [LocalPeer.name], when a previously-found service goes
  /// away (wifi dropped, the other app closed) — real, not inferred from a
  /// timeout, since bonsoir surfaces this as its own event type.
  Stream<String> get lost => _lost.stream;

  Future<void> start() async {
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: '$displayName-$role',
        type: localServiceType,
        port: servePort,
        attributes: {'role': role, 'name': displayName},
      ),
    );
    _broadcast = broadcast;
    await broadcast.ready;
    await broadcast.start();

    final discovery = BonsoirDiscovery(type: localServiceType);
    _discovery = discovery;
    await discovery.ready;
    discovery.eventStream?.listen(_handleDiscoveryEvent);
    await discovery.start();
  }

  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event.type) {
      case BonsoirDiscoveryEventType.discoveryServiceFound:
        // Not yet connectable — no host until resolved. Resolving is what
        // actually reaches the network a second time, so this is not
        // skippable busywork; a "found" event alone is not enough to dial.
        unawaited(event.service?.resolve(discovery!.serviceResolver));
      case BonsoirDiscoveryEventType.discoveryServiceResolved:
        final service = event.service;
        if (service is ResolvedBonsoirService && service.host != null) {
          // Never a peer talking to itself — this device's own broadcast is
          // visible to its own discovery browse on some platforms, and a
          // same-room pairing with exactly one other real person has no use
          // for that.
          if (service.name == '$displayName-$role') return;
          _peers.add(LocalPeer(
            host: service.host!,
            port: service.port,
            role: service.attributes['role'] ?? 'unknown',
            name: service.attributes['name'] ?? service.name,
          ));
        }
      case BonsoirDiscoveryEventType.discoveryServiceLost:
        final name = event.service?.attributes['name'];
        if (name != null) _lost.add(name);
      default:
        return;
    }
  }

  /// Exposed only so [_handleDiscoveryEvent] can reach the same
  /// [ServiceResolver] instance bonsoir minted for this discovery session —
  /// resolving through a different one is a real, documented bonsoir
  /// footgun (each platform's own resolver instance owns the in-flight
  /// resolve state), not a style preference.
  BonsoirDiscovery? get discovery => _discovery;

  Future<void> stop() async {
    await _broadcast?.stop();
    await _discovery?.stop();
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
