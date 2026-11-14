// OLIVE BRANCH — the same-network transport for the on-device pairing protocol: the adult device serves its open
// window over a tiny HTTP endpoint and advertises it on mDNS; the child device lists the open windows nearby BY A
// SHORT NEUTRAL LABEL the grown-up reads off the adult's screen, and talks to the one a grown-up picks. UNVERIFIED
// on a device (bonsoir/mDNS needs two real devices; the HTTP half is tested over loopback in
// test/lan_pairing_transport_test.dart).
// Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md section 6.4.
//
// PROXIMITY IS ENFORCED HERE, NOT HOPED FOR. The adult device answers only requests from a private, link-local
// or unique-local source address (a LAN), never from a routable one. The service exists only while the adult's
// window is open (it is stopped when the window closes).
//
// WHAT THE ADVERTISEMENT CARRIES (nothing identifying, like the play stack in local_discovery.dart): a generic
// service type, an instance name that is a random per-window label such as "KT7", and one TXT entry `h`, a random
// per-window handle that is NOT the session id. No adult name, no family or device id, no session id, nothing the
// same from one window to the next. The session id reaches the child only in the answer to its first message.
// The price is plain: two grown-ups opening windows in range at once are told apart only by the label, which a
// person reads off the adult's screen and picks on the other device.
//
// A person on the same Wi-Fi who sends garbage is held to a per-source budget by the window itself
// (pairing_protocol.dart: kSourceMax*), so one address cannot burn the five confirmations; a crowd of addresses
// still can (a denial of service the adult cures by opening a new window in the same room). They cannot pair a
// device. The first hello still answers any same-LAN source holding the handle with the adult's name, family id
// and public key (the key exchange binds them); moving those behind the key exchange is not done here.
//
// What it never carries: a PIN, a QR secret, a certificate in the clear. Only PAKE shares, confirmation tags and
// a credential sealed under the exchange's key.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import 'device_keys.dart' show b64, unb64;
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

/// The key a window budgets a source by: its IPv4 address, or its IPv6 /64 (a device can rotate the rest at will);
/// an IPv4-mapped IPv6 address counts as its IPv4.
String sourceKey(InternetAddress a) {
  final List<int> b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) return a.address;
  if (b.length == 16) {
    if (b.sublist(0, 10).every((int x) => x == 0) && b[10] == 0xff && b[11] == 0xff) {
      return InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))).address;
    }
    return 'v6:${b.sublist(0, 8).map((int x) => x.toRadixString(16).padLeft(2, '0')).join()}';
  }
  return a.address;
}

class LanPairingHost {
  LanPairingHost(this.window, {this.allowLoopback = false});
  final AdultWindow window;
  final bool allowLoopback;
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;

  int? get port => _server?.port;

  /// Exactly what goes on the network. Its own method so a test can check it without any mDNS.
  BonsoirService advertisedService(int port) => BonsoirService(
        name: window.label,
        type: kPairServiceType,
        port: port,
        attributes: <String, String>{'h': b64(window.discoveryHandle)},
      );

  Future<void> start({bool advertise = true}) async {
    final HttpServer s = await HttpServer.bind(InternetAddress.anyIPv6, 0, v6Only: false);
    _server = s;
    unawaited(s.forEach(_serve));
    window.addListener(_closeWithWindow);
    if (advertise) {
      final BonsoirBroadcast b = BonsoirBroadcast(service: advertisedService(s.port));
      _broadcast = b;
      await b.ready;
      await b.start();
    }
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

class LanPairingTransport implements PairingTransport {
  LanPairingTransport(this.host, this.port, {this.timeout = const Duration(seconds: 6)});
  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    final HttpClient c = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest req = await c.postUrl(Uri(scheme: 'http', host: host, port: port, path: '/pair')).timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(message));
      final HttpClientResponse res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final Object? decoded = jsonDecode(await utf8.decoder.bind(res).join());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }
}

/// An adult's open window seen on the network: a neutral label to show, how to address it and where to talk to
/// it. Found through discovery it has a [handle] (never the session id); from a QR it has the [sid].
class NearbyWindow {
  const NearbyWindow({required this.label, this.handle, this.sid, required this.host, required this.port})
      : assert((handle == null) != (sid == null), 'exactly one of handle or sid');
  final String label;
  final Uint8List? handle;
  final Uint8List? sid;
  final String host;
  final int port;
  String get key => b64((handle ?? sid)!);
}

/// Reads one resolved service into a window, or null when it is not one of ours (anything but a label and a
/// 16-byte handle). The old name-and-session-id shape is deliberately not understood.
NearbyWindow? parseNearbyService({required String name, required String? host, required int port, required Map<String, String> attributes}) {
  final String? h = attributes['h'];
  if (host == null || h == null || name.isEmpty) return null;
  try {
    final Uint8List handle = unb64(h);
    if (handle.length != 16) return null;
    return NearbyWindow(label: name, handle: handle, host: host, port: port);
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
          // A lost service may carry no TXT record: the instance name (the label) is what identifies it.
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
