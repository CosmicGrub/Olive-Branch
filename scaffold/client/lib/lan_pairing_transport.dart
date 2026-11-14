// OLIVE BRANCH — the same-network transport for the on-device pairing protocol: the adult device serves its open
// window over a tiny HTTP endpoint and advertises it on mDNS; the child device lists the open windows nearby BY
// A PICTURE (a nameless glyph, or a scanned pairing picture), and talks to the one a grown-up picks. UNVERIFIED on a device (bonsoir/mDNS needs two real
// devices; the HTTP half is tested over loopback in test/lan_pairing_transport_test.dart).
// Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md section 6.4.
//
// PROXIMITY IS ENFORCED HERE, NOT HOPED FOR. The adult device answers only requests from a private, link-local
// or unique-local source address (a LAN), never from a routable one. The service exists only while the adult's
// window is open (it is stopped when the window closes), and it advertises nothing but a seat label ("Player one"
// or "Player two"), a version, the window's session id and a recognition tag (none of it grants anything: the
// PIN key exchange does; no name, key, fingerprint or address is advertised). A person on the same Wi-Fi who
// sends garbage can burn the window's five attempts (a denial of service the adult cures by opening a new window
// in the same room); they cannot pair a device. Written down in the spec's threat model.
//
// What it never carries: a PIN, a QR secret, a certificate in the clear. Only PAKE shares, confirmation tags and
// a credential sealed under the exchange's key.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import 'device_keys.dart' show b64, unb64;
import 'pairing_limits.dart';
import 'pairing_picture.dart' show kPictureTagBytes;
import 'pairing_protocol.dart';

const String kPairServiceType = '_olivepair._tcp';
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

/// The instance name a window advertises: a seat label, never a name and never derived from the session id's text.
String pairingSeatLabel(List<int> sid) => (sid[2] & 1) == 0 ? 'Player one' : 'Player two';

/// The TXT record of an open window: protocol version, the window's public session id and the recognition tag.
/// Nothing else: no adult name, no key, no fingerprint, no address, no family. The tag is random unless a pairing
/// picture addresses the window (see pairing_picture.dart), so it identifies nobody to a bystander.
Map<String, String> pairingTxt(List<int> sid, List<int> tag) =>
    <String, String>{'v': '1', 'w': b64(sid), 't': b64(tag)};

class LanPairingHost {
  LanPairingHost(this.window, {this.allowLoopback = false, SourceBucket? bucket}) : _bucket = bucket ?? SourceBucket();
  final AdultWindow window;
  final bool allowLoopback;
  final SourceBucket _bucket;
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  bool _advertise = true;

  int? get port => _server?.port;

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
    final BonsoirBroadcast b = BonsoirBroadcast(
      service: BonsoirService(
        name: pairingSeatLabel(window.sid),
        type: kPairServiceType,
        port: s.port,
        attributes: pairingTxt(window.sid, await window.windowTag()),
      ),
    );
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
          decoded is Map<String, dynamic> ? await window.handle(decoded) : null;
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

/// An adult's open window seen on the network: its public session id, the recognition tag and where to talk to
/// it. No name travels: the child tells windows apart by picture (pairing_picture.dart).
class NearbyWindow {
  const NearbyWindow({required this.sid, required this.host, required this.port, this.tag});
  final Uint8List sid;
  final String host;
  final int port;

  /// The 8-byte recognition tag from the advertisement; null in tests that skip it.
  final Uint8List? tag;
  String get key => b64(sid);
}

class LanPairingBrowser {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final StreamController<NearbyWindow> _found = StreamController<NearbyWindow>.broadcast();
  final StreamController<String> _gone = StreamController<String>.broadcast();

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
          if (s is ResolvedBonsoirService && s.host != null) {
            final String? sid = s.attributes['w'], tag = s.attributes['t'];
            if (s.attributes['v'] != '1' || sid == null || tag == null) return;
            try {
              final Uint8List sidBytes = unb64(sid), tagBytes = unb64(tag);
              if (sidBytes.length != 16 || tagBytes.length != kPictureTagBytes) return;
              if (!_found.isClosed) _found.add(NearbyWindow(sid: sidBytes, host: s.host!, port: s.port, tag: tagBytes));
            } catch (_) {}
          }
        case BonsoirDiscoveryEventType.discoveryServiceLost:
          final String? sid = e.service?.attributes['w'];
          if (sid != null && !_gone.isClosed) _gone.add(sid);
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
