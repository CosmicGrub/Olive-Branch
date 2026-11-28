// OLIVE BRANCH — the same-network transport for the on-device pairing protocol: the adult device serves its open
// window over a tiny HTTP endpoint and advertises it on mDNS; the child device lists the open windows nearby BY
// A PICTURE (a nameless glyph, or a scanned pairing picture), and talks to the one a grown-up picks. UNVERIFIED
// on a device (bonsoir/mDNS needs two real devices; the HTTP half is tested over loopback in
// test/lan_pairing_transport_test.dart).
// Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md section 6.4.
//
// PROXIMITY IS ENFORCED HERE, NOT HOPED FOR. The adult device answers only requests from a private, link-local
// or unique-local source address (a LAN), never from a routable one. The service exists only while the adult's
// window is open (it is stopped when the window closes).
//
// WHAT THE ADVERTISEMENT CARRIES (nothing identifying, like the play stack in local_discovery.dart): a generic
// service type, an instance name that is only a neutral seat label ("Player one" or "Player two", one random bit
// of the handle), and three TXT entries: `v` (version), `h` (a random per-window handle that is NOT the session
// id) and `t` (the recognition tag: random unless a pairing picture addresses the window). No adult name, no
// family or device id, no key, no fingerprint, no address, no session id, nothing the same from one window to the
// next. The session id reaches the child only in the answer to its first message. The child tells windows apart
// by a nameless picture tile (pairing_picture.dart), or by the pairing picture it scanned.
//
// A person on the same Wi-Fi who sends garbage is held to a per-source budget by the window itself
// (pairing_protocol.dart: kSourceMax*), so one address cannot burn the five confirmations; a crowd of addresses
// still can (a denial of service the adult cures by opening a new window in the same room). They cannot pair a
// device. The first hello still answers any same-LAN source holding the handle with the adult's name, family id
// and public key (the key exchange binds them), unless a pairing picture restricted the window to one proven
// device (then only that device is answered); moving those behind the key exchange is not done here.
//
// What it never carries: a PIN, a QR secret, a certificate in the clear. Only PAKE shares, confirmation tags and
// a credential sealed under the exchange's key.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import 'package:flutter/foundation.dart' show debugPrint;

import 'device_keys.dart' show b64, unb64;
import 'lan_bind.dart' show isNonLanInterface;
import 'pairing_limits.dart';
import 'pairing_picture.dart' show kPictureTagBytes;
import 'pairing_protocol.dart';

/// A generic type (RFC 6763: at most 15 characters): no app name, no word like "family" or "child". That some app
/// advertises it is still observable on the same network; the rest of the advertisement is random per window.
const String kPairServiceType = '_pw._tcp';
const int _kMaxBody = 8 * 1024;

/// True for the addresses a same-room LAN uses. Loopback only when [allowLoopback] (tests).
bool isLanAddress(InternetAddress a, {bool allowLoopback = false}) {
  if (a.isLoopback) return allowLoopback;
  final List<int> b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    if (b[0] == 10) return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
    if (b[0] == 192 && b[1] == 168) return true;
    if (b[0] == 169 && b[1] == 254) return true;
    return false;
  }
  if (b.length == 16) {
    if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique local
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true; // fe80::/10 link local
    // An IPv4-mapped IPv6 address (::ffff:a.b.c.d) is judged as its IPv4.
    if (b.sublist(0, 10).every((int x) => x == 0) && b[10] == 0xff && b[11] == 0xff) {
      return isLanAddress(InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))), allowLoopback: allowLoopback);
    }
  }
  return false;
}

/// The instance name a window advertises: a neutral seat label, never a name and never derived from the session id.
/// It is the label of the window's discovery handle (see [windowSeatLabel]).
String pairingSeatLabel(List<int> discoveryHandle) => windowSeatLabel(discoveryHandle);

/// The TXT record of an open window: protocol version, the window's random discovery handle and the recognition
/// tag. Nothing else: no adult name, no session id, no key, no fingerprint, no address, no family. The tag is random
/// unless a pairing picture addresses the window (see pairing_picture.dart), so it identifies nobody to a bystander.
Map<String, String> pairingTxt(List<int> discoveryHandle, List<int> tag) =>
    <String, String>{'v': '1', 'h': b64(discoveryHandle), 't': b64(tag)};

/// The key a window budgets a source by: its IPv4 address, or its FULL IPv6 address (16 raw bytes, so a scope id
/// written after '%' plays no part); an IPv4-mapped IPv6 address counts as its IPv4. The remote port is never part
/// of it.
///
/// Trade-off, chosen on purpose: an earlier version collapsed IPv6 to its /64, which put every fe80::/64 link-local
/// device (and every device on one unique-local /64) in ONE bucket, so a single hostile device could use up the
/// budget and lock a real IPv6 child out. Per-address keys cannot do that. The cost is that a device which rotates
/// its IPv6 address (privacy addresses) gets a fresh per-source budget each time; that only lets it spend more of
/// the window's SHARED five confirmations, which still end the window, so it can deny service (the adult reopens a
/// window) but never guess more than five PINs. The table of sources is LRU-bounded, so rotation cannot grow memory.
/// A dual-stack host's IPv4 and IPv6 addresses cannot be tied together from here, so the per-source failure limit is
/// kept below half the window cap (see kSourceMaxFailures) instead: two of its addresses leave a try for the child.
String sourceKey(InternetAddress a) {
  final List<int> b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) return a.address;
  if (b.length == 16) {
    if (b.sublist(0, 10).every((int x) => x == 0) && b[10] == 0xff && b[11] == 0xff) {
      return InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))).address;
    }
    return 'v6:${b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join()}';
  }
  return a.address;
}

class LanPairingHost {
  LanPairingHost(this.window, {this.allowLoopback = false, SourceBucket? bucket}) : _bucket = bucket ?? SourceBucket();
  final AdultWindow window;
  final bool allowLoopback;
  final SourceBucket _bucket;
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  bool _advertise = true;

  int? get port => _server?.port;

  /// Exactly what goes on the network. Its own method so a test can check it without any mDNS.
  BonsoirService advertisedService(int port, List<int> tag) => BonsoirService(
        name: pairingSeatLabel(window.discoveryHandle),
        type: kPairServiceType,
        port: port,
        attributes: pairingTxt(window.discoveryHandle, tag),
      );

  Future<void> start({bool advertise = true}) async {
    final HttpServer s = await HttpServer.bind(InternetAddress.anyIPv6, 0, v6Only: false);
    _server = s;
    _advertise = advertise;
    unawaited(s.forEach(_serve));
    window.addListener(_closeWithWindow);
    if (advertise) await _startBroadcast();
  }

  Future<void> _startBroadcast() async {
    final HttpServer? s = _server;
    if (s == null) return;
    final BonsoirBroadcast b = BonsoirBroadcast(service: advertisedService(s.port, await window.windowTag()));
    _broadcast = b;
    await b.ready;
    await b.start();
  }

  /// Advertises again with the window's current tag: called after the adult scans a child's picture or shows
  /// their own, so the TXT record carries the tag that picture can recognise.
  Future<void> readvertise() async {
    if (!_advertise || _server == null) return;
    final BonsoirBroadcast? old = _broadcast;
    _broadcast = null;
    try {
      await old?.stop();
    } catch (_) {}
    await _startBroadcast();
  }

  void _closeWithWindow() {
    if (window.state == WindowState.closed || window.state == WindowState.declined) unawaited(stop());
  }

  Future<void> _serve(HttpRequest r) async {
    try {
      final InternetAddress? from = r.connectionInfo?.remoteAddress;
      if (r.method != 'POST' || r.uri.path != '/pair' || from == null || !isLanAddress(from, allowLoopback: allowLoopback)) {
        r.response.statusCode = HttpStatus.notFound;
        await r.response.close();
        return;
      }
      if (r.contentLength > _kMaxBody) {
        r.response.statusCode = HttpStatus.requestEntityTooLarge;
        await r.response.close();
        return;
      }
      // A chunked body has no declared length: count what actually arrives.
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in r) {
        bytes.add(chunk);
        if (bytes.length > _kMaxBody) {
          r.response.statusCode = HttpStatus.requestEntityTooLarge;
          await r.response.close();
          return;
        }
      }
      final String body = utf8.decode(bytes.takeBytes());
      final Object? decoded = jsonDecode(body);
      // A flood of key-exchange starts from one source is dropped before it reaches the window (pairing_limits.dart).
      if (decoded is Map && decoded['t'] == 'pake1' && !_bucket.allow(from.address)) {
        r.response.statusCode = HttpStatus.noContent;
        await r.response.close();
        return;
      }
      final Map<String, dynamic>? answer =
          decoded is Map<String, dynamic> ? await window.handle(decoded, source: sourceKey(from)) : null;
      if (answer == null) {
        r.response.statusCode = HttpStatus.noContent;
      } else {
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(answer));
      }
      await r.response.close();
    } catch (_) {
      try {
        r.response.statusCode = HttpStatus.badRequest;
        await r.response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    window.removeListener(_closeWithWindow);
    final HttpServer? s = _server;
    _server = null;
    // Not forced: the answer that closed the window (the sealed credential) must finish going out.
    await s?.close();
    final BonsoirBroadcast? b = _broadcast;
    _broadcast = null;
    try {
      await b?.stop();
    } catch (_) {}
  }
}

/// A network interface by name and number, as the platform lists them.
class LanInterface {
  const LanInterface(this.name, this.index);
  final String name;
  final int index;
}

/// Where to dial a host that discovery (or a scanned picture) gave us, worked out safely.
class ConnectTarget {
  const ConnectTarget(this.dialAddress, this.urlHost, {this.scoped = false});

  /// The address to open the socket to (a link-local IPv6 address carries its interface NUMBER here).
  final InternetAddress dialAddress;

  /// The host for the request line and Host header: never carries a scope.
  final String urlHost;

  /// True when the address is link-local IPv6 and [dialAddress] had to be given an interface.
  final bool scoped;
}

/// ROOT CAUSE of "the tablet scans and disconnects but cannot connect" (see test/lan_scoped_host_test.dart): the platform's
/// resolver returns a link-local IPv6 address with its interface ("fe80::...%wlan0", the way Java prints it). Dart's Uri turned
/// that into "...%25wlan0", the lookup failed, and the transport answered null, silently, every time. This reads what a resolver
/// returns and says how to dial it, or null when it must not be dialled:
///   - only a LAN address is ever dialled (private, unique-local, link-local; loopback too, which cannot leave the device),
///     so a hostile advertisement or scanned picture cannot send the tablet's handshake to a public address;
///   - a name that is not an address is refused (nothing here resolves a name an advertisement chose);
///   - a link-local IPv6 address needs its interface: a NAME is looked up in [interfaces], a number is taken as is, a missing
///     one is not guessed, and a cellular or tunnel interface is never used.
/// Never throws.
ConnectTarget? connectTargetFor(String host, {List<LanInterface>? interfaces}) {
  try {
    final String h = host.trim().replaceAll('%25', '%');
    if (h.isEmpty || h.length > 80) return null;
    final List<String> parts = h.split('%');
    if (parts.length > 2) return null;
    final InternetAddress? a = InternetAddress.tryParse(parts[0]);
    if (a == null || !isLanAddress(a, allowLoopback: true)) return null;
    final bool linkLocal = a.type == InternetAddressType.IPv6 && a.rawAddress[0] == 0xfe && (a.rawAddress[1] & 0xc0) == 0x80;
    final String? scope = parts.length == 2 ? parts[1] : null;
    if (!linkLocal) return ConnectTarget(a, a.address);
    if (scope == null || scope.isEmpty) return null; // a link-local address means nothing without its interface
    int? index = int.tryParse(scope);
    if (index == null) {
      if (isNonLanInterface(scope)) return null;
      for (final LanInterface i in interfaces ?? const <LanInterface>[]) {
        if (i.name == scope) index = i.index;
      }
    } else if (index <= 0) {
      return null;
    }
    if (index == null) return null;
    final InternetAddress? dial = InternetAddress.tryParse('${a.address}%$index');
    if (dial == null) return null;
    return ConnectTarget(dial, a.address, scoped: true);
  } catch (_) {
    return null;
  }
}

Future<List<LanInterface>> _platformInterfaces() async {
  try {
    final List<NetworkInterface> l = await NetworkInterface.list(includeLinkLocal: true, includeLoopback: false);
    return <LanInterface>[for (final NetworkInterface i in l) LanInterface(i.name, i.index)];
  } catch (_) {
    return const <LanInterface>[];
  }
}

class LanPairingTransport implements PairingTransport {
  LanPairingTransport(this.host, this.port, {this.timeout = const Duration(seconds: 6), this.interfaces});
  final String host;
  final int port;
  final Duration timeout;

  /// Tests: the interfaces to place a link-local host on. Null = ask the platform.
  final List<LanInterface>? interfaces;

  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    final ConnectTarget? target = connectTargetFor(host, interfaces: interfaces ?? await _platformInterfaces());
    if (target == null) {
      // Not an address this device will dial. No address is logged (the app never writes where it is).
      debugPrint('[olive.pairing] that window link was not one a pairing may use');
      return null;
    }
    final HttpClient c = HttpClient()..connectionTimeout = timeout;
    if (target.scoped) {
      // A link-local IPv6 address is dialled on its interface; the request itself never carries the scope.
      c.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) => Socket.startConnect(target.dialAddress, port);
    }
    try {
      final HttpClientRequest req = await c.postUrl(Uri(scheme: 'http', host: target.urlHost, port: port, path: '/pair')).timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(message));
      final HttpClientResponse res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final Object? decoded = jsonDecode(await utf8.decoder.bind(res).join());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('[olive.pairing] could not reach the window: ${e.runtimeType}');
      return null;
    } finally {
      c.close(force: true);
    }
  }
}

/// An adult's open window seen on the network: how to address it (the random [handle] from discovery, never the
/// session id; from a QR it has the [sid]), the recognition tag and where to talk to it. No name travels: the child
/// tells windows apart by picture (pairing_picture.dart). [label] is only the neutral seat name, if any.
class NearbyWindow {
  const NearbyWindow({this.label = '', this.handle, this.sid, required this.host, required this.port, this.tag})
      : assert((handle == null) != (sid == null), 'exactly one of handle or sid');
  final String label;
  final Uint8List? handle;
  final Uint8List? sid;
  final String host;
  final int port;

  /// The 8-byte recognition tag from the advertisement; null in tests that skip it.
  final Uint8List? tag;
  String get key => b64((handle ?? sid)!);
}

/// Reads one resolved service into a window, or null when it is not one of ours (anything without version 1, a
/// 16-byte handle and an 8-byte tag). The old name-and-session-id shapes are deliberately not understood.
NearbyWindow? parseNearbyService({required String name, required String? host, required int port, required Map<String, String> attributes}) {
  final String? h = attributes['h'], tag = attributes['t'];
  if (host == null || attributes['v'] != '1' || h == null || tag == null) return null;
  try {
    final Uint8List handle = unb64(h), tagBytes = unb64(tag);
    if (handle.length != 16 || tagBytes.length != kPictureTagBytes) return null;
    return NearbyWindow(label: name, handle: handle, host: host, port: port, tag: tagBytes);
  } catch (_) {
    return null;
  }
}

class LanPairingBrowser {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final StreamController<NearbyWindow> _found = StreamController<NearbyWindow>.broadcast();
  final StreamController<String> _gone = StreamController<String>.broadcast();
  final Map<String, String> _keyByName = <String, String>{};

  Stream<NearbyWindow> get found => _found.stream;

  /// The window key ([NearbyWindow.key]) of a window that went away.
  Stream<String> get gone => _gone.stream;

  Future<void> start() async {
    final BonsoirDiscovery d = BonsoirDiscovery(type: kPairServiceType);
    _discovery = d;
    await d.ready;
    _sub = d.eventStream?.listen((BonsoirDiscoveryEvent e) {
      switch (e.type) {
        case BonsoirDiscoveryEventType.discoveryServiceFound:
          unawaited(e.service?.resolve(d.serviceResolver));
        case BonsoirDiscoveryEventType.discoveryServiceResolved:
          final BonsoirService? s = e.service;
          if (s is ResolvedBonsoirService) {
            final NearbyWindow? w = parseNearbyService(name: s.name, host: s.host, port: s.port, attributes: s.attributes);
            if (w != null && !_found.isClosed) {
              _keyByName[s.name] = w.key;
              _found.add(w);
            }
          }
        case BonsoirDiscoveryEventType.discoveryServiceLost:
          // A lost service may carry no TXT record: the instance name identifies it.
          final String? name = e.service?.name;
          final String? key = name == null ? null : _keyByName.remove(name);
          if (key != null && !_gone.isClosed) _gone.add(key);
        default:
          return;
      }
    });
    await d.start();
  }

  Future<void> stop() async {
    final StreamSubscription<BonsoirDiscoveryEvent>? s = _sub;
    _sub = null;
    await s?.cancel();
    try {
      await _discovery?.stop();
    } catch (_) {}
    await _found.close();
    await _gone.close();
  }
}
