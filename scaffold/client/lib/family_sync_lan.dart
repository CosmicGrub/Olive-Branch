// OLIVE BRANCH — the same-Wi-Fi road between two grown-ups' phones (road A of docs/planning/FAMILY-SYNC-DESIGN.md): a
// small HTTP service that exists only while the grown-up app is open, answers only addresses on a private network, and
// carries the hand-carried update text, a sealed screen share and the "add a grown-up" messages. UNVERIFIED on a device
// (bonsoir/mDNS needs two real phones; the HTTP half is tested over loopback in client/test/family_sync_lan_test.dart).
//
// WHAT IT CARRIES IS ALREADY PROTECTED, SO THE ROAD NEEDS NO TRUST.
//  * An update (family_sync_bundle.dart) is sealed under the guardian key and its header is signed by the sending phone.
//    The service ANSWERS an update only after it opened one: a stranger who cannot open one gets no answer at all
//    (HTTP 204, the same for every failure, so the road is not an oracle). The reply is another update.
//  * A screen share (screen_share.dart) is sealed to ONE phone's key and signed; the receiving phone says what it did
//    with it and the sender keeps the picture only until that phone has taken it.
//  * The "add a grown-up" messages (family_join.dart) are the password-authenticated exchange.
//
// PROXIMITY IS ENFORCED HERE, NOT HOPED FOR (the same rule as the pairing window, lan_pairing_transport.dart): a request
// from a routable address is not answered; the server listens only on real LAN interfaces (lan_bind.dart: never a VPN,
// tunnel or cellular address, never 0.0.0.0); it exists only while the app is open and the grown-up has a use for it.
//
// WHAT AN OBSERVER ON THE WI-FI SEES: that some app advertises a generic service of type [kRoadServiceType]; a neutral
// two-word label; a random handle; an 8-byte tag. The tag is a keyed hash that changes every ten minutes and only the
// family's own phones (who hold the family key) can recognise. No name, no family id, no key, no address beyond the
// socket itself. A phone with an open "add a grown-up" window adds one flag (j=1) so the other phone can list it.
//
// A child's device never builds any of this: it has no guardian key to answer with, and the road is only ever created
// by the grown-up app's services (guardian_local_scope.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show b64, unb64;
import 'family_join.dart' show joinWindowLabel;
import 'family_keys.dart';
import 'lan_bind.dart';
import 'lan_pairing_transport.dart' show isLanAddress, sourceKey;
import 'pairing_limits.dart';
import 'pairing_protocol.dart' show PairingTransport;
import 'screen_share.dart' show ShareTransport;

/// A generic type, like the pairing window's: no app name, no word like "family". (At most 15 characters.)
const String kRoadServiceType = '_pq._tcp';
const int kRoadMaxBody = 3 * 1024 * 1024;

/// A request that is still sending after this long is closed at its next chunk (a stalled one at the 20 s idle limit).
const Duration kRoadBodyDeadline = Duration(seconds: 15);
const int kRoadMaxReply = 4 * 1024 * 1024;
const int kRoadTagBytes = 8;
const int kRoadTagBucketMs = 10 * 60 * 1000;
const int kRoadMaxInFlight = 8;

/// A phone seen on the network. [tag] is compared with [roadTagsNear]; [join] is true for an open "add a grown-up"
/// window. Never stored.
class RoadPeer {
  const RoadPeer({required this.host, required this.port, required this.handle, required this.tag, this.join = false});
  final String host;
  final int port;
  final Uint8List handle, tag;
  final bool join;
  String get key => b64(handle);
  String get label => joinWindowLabel(handle);
}

/// The 8-byte tag a family phone advertises now: HMAC of the ten-minute bucket under a key derived from the family key.
Future<Uint8List> roadTag(FamilyKeyring ring, int nowMs, {int bucketOffset = 0}) async {
  final int epoch = ring.newestEpoch;
  if (epoch < 0) return Uint8List(kRoadTagBytes);
  final Uint8List k = await ring.familySubkey(epoch, kFkDiscovery);
  final int bucket = nowMs ~/ kRoadTagBucketMs + bucketOffset;
  final Mac m = await Hmac.sha256().calculateMac(
    cat(<List<int>>[lv(utf8.encode('olive-road-tag-v1')), lv(ascii.encode('$bucket'))]),
    secretKey: SecretKey(k),
  );
  return Uint8List.fromList(m.bytes.sublist(0, kRoadTagBytes));
}

/// The tags a phone of this family may be advertising right now (this bucket and its neighbours: clocks differ).
Future<List<Uint8List>> roadTagsNear(FamilyKeyring ring, int nowMs) async => <Uint8List>[
  for (final int o in <int>[-1, 0, 1]) await roadTag(ring, nowMs, bucketOffset: o),
];

bool tagIn(List<int> tag, List<Uint8List> tags) {
  for (final Uint8List t in tags) {
    if (t.length != tag.length) continue;
    int d = 0;
    for (int i = 0; i < t.length; i++) {
      d |= t[i] ^ tag[i];
    }
    if (d == 0) return true;
  }
  return false;
}

/// The TXT record of an advertisement: exactly this and nothing else.
Map<String, String> roadTxt(List<int> handle, List<int> tag, {bool join = false}) => <String, String>{
  'v': '1',
  'h': b64(handle),
  't': b64(tag),
  if (join) 'j': '1',
};

/// True for a literal address on the home network (a name, a public address or an empty string is not).
bool isHomeNetworkHost(String? host, {bool allowLoopback = false}) {
  if (host == null || host.isEmpty) return false;
  final int zone = host.indexOf('%');
  final InternetAddress? a = InternetAddress.tryParse(zone < 0 ? host : host.substring(0, zone));
  return a != null && isLanAddress(a, allowLoopback: allowLoopback);
}

RoadPeer? parseRoadService({
  required String? host,
  required int port,
  required Map<String, String> attributes,
  bool allowLoopback = false,
}) {
  final String? h = attributes['h'], t = attributes['t'];
  if (host == null || attributes['v'] != '1' || h == null || t == null) return null;
  // An advertisement that points anywhere but the home network is never a peer, so nothing is ever sent off it.
  if (!isHomeNetworkHost(host, allowLoopback: allowLoopback)) return null;
  try {
    final Uint8List handle = unb64(h), tag = unb64(t);
    if (handle.length != 16 || tag.length != kRoadTagBytes) return null;
    return RoadPeer(host: host, port: port, handle: handle, tag: tag, join: attributes['j'] == '1');
  } catch (_) {
    return null;
  }
}

/// How phones find each other. The real one uses mDNS; tests use a fake.
abstract class RoadDiscovery {
  Future<void> advertise({required int port, required Uint8List handle, required Uint8List tag, bool join = false});
  Future<void> stopAdvertising();
  Future<void> startBrowsing();
  Future<void> stopBrowsing();
  Stream<RoadPeer> get found;
  Stream<String> get gone;
}

class BonsoirRoadDiscovery implements RoadDiscovery {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  StreamController<RoadPeer> _found = StreamController<RoadPeer>.broadcast();
  StreamController<String> _gone = StreamController<String>.broadcast();
  final Map<String, String> _keyByName = <String, String>{};

  @override
  Stream<RoadPeer> get found => _found.stream;
  @override
  Stream<String> get gone => _gone.stream;

  @override
  Future<void> advertise({
    required int port,
    required Uint8List handle,
    required Uint8List tag,
    bool join = false,
  }) async {
    await stopAdvertising();
    final BonsoirBroadcast b = BonsoirBroadcast(
      service: BonsoirService(
        name: joinWindowLabel(handle),
        type: kRoadServiceType,
        port: port,
        attributes: roadTxt(handle, tag, join: join),
      ),
    );
    _broadcast = b;
    await b.ready;
    await b.start();
  }

  @override
  Future<void> stopAdvertising() async {
    final BonsoirBroadcast? b = _broadcast;
    _broadcast = null;
    try {
      await b?.stop();
    } catch (_) {}
  }

  @override
  Future<void> startBrowsing() async {
    if (_discovery != null) return;
    if (_found.isClosed) _found = StreamController<RoadPeer>.broadcast();
    if (_gone.isClosed) _gone = StreamController<String>.broadcast();
    final BonsoirDiscovery d = BonsoirDiscovery(type: kRoadServiceType);
    _discovery = d;
    await d.ready;
    _sub = d.eventStream?.listen((BonsoirDiscoveryEvent e) {
      switch (e.type) {
        case BonsoirDiscoveryEventType.discoveryServiceFound:
          unawaited(e.service?.resolve(d.serviceResolver));
        case BonsoirDiscoveryEventType.discoveryServiceResolved:
          final BonsoirService? s = e.service;
          if (s is ResolvedBonsoirService) {
            final RoadPeer? p = parseRoadService(host: s.host, port: s.port, attributes: s.attributes);
            if (p != null && !_found.isClosed) {
              _keyByName[s.name] = p.key;
              _found.add(p);
            }
          }
        case BonsoirDiscoveryEventType.discoveryServiceLost:
          final String? name = e.service?.name;
          final String? key = name == null ? null : _keyByName.remove(name);
          if (key != null && !_gone.isClosed) _gone.add(key);
        default:
          return;
      }
    });
    await d.start();
  }

  @override
  Future<void> stopBrowsing() async {
    final StreamSubscription<BonsoirDiscoveryEvent>? s = _sub;
    final BonsoirDiscovery? d = _discovery;
    _sub = null;
    _discovery = null;
    await s?.cancel();
    try {
      await d?.stop();
    } catch (_) {}
  }
}

/// The server half. [backend] gets a parsed JSON object and the request's source; it answers an object, or null for
/// "no answer" (HTTP 204 for every refusal, so nothing can be told apart from outside).
class FamilyRoadServer {
  FamilyRoadServer({required this.backend, this.bindAddresses, this.allowLoopback = false, SourceBucket? bucket})
    : _bucket = bucket ?? SourceBucket(limit: 240, window: const Duration(minutes: 1));

  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> message, String source) backend;

  /// Null = the real LAN interfaces ([lanBindAddresses]). Tests pass loopback.
  final List<InternetAddress>? bindAddresses;
  final bool allowLoopback;
  final SourceBucket _bucket;
  final List<HttpServer> _servers = <HttpServer>[];
  int _inFlight = 0;

  int? get port => _servers.isEmpty ? null : _servers.first.port;
  bool get running => _servers.isNotEmpty;

  /// Starts listening. False when there is no LAN address (the caller says so in words).
  Future<bool> start() async {
    if (running) return true;
    final List<InternetAddress> addrs = bindAddresses ?? await lanBindAddresses();
    if (addrs.isEmpty) return false;
    int port = 0;
    for (final InternetAddress a in addrs) {
      try {
        final HttpServer s = await HttpServer.bind(a, port);
        port = s.port;
        _servers.add(s);
        unawaited(s.forEach(_serve));
      } catch (_) {
        // One interface that will not bind does not stop the others.
      }
    }
    return running;
  }

  Future<void> stop() async {
    final List<HttpServer> all = List<HttpServer>.of(_servers);
    _servers.clear();
    for (final HttpServer s in all) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }

  Future<void> _end(HttpRequest r, int code) async {
    try {
      r.response.statusCode = code;
      await r.response.close();
    } catch (_) {}
  }

  Future<void> _serve(HttpRequest r) async {
    _inFlight++;
    try {
      final InternetAddress? from = r.connectionInfo?.remoteAddress;
      if (r.method != 'POST' ||
          r.uri.path != '/f' ||
          from == null ||
          !isLanAddress(from, allowLoopback: allowLoopback)) {
        return await _end(r, HttpStatus.notFound);
      }
      if (_inFlight > kRoadMaxInFlight) return await _end(r, HttpStatus.serviceUnavailable);
      if (r.contentLength > kRoadMaxBody) return await _end(r, HttpStatus.requestEntityTooLarge);
      if (!_bucket.allow(sourceKey(from))) return await _end(r, HttpStatus.noContent);
      final BytesBuilder bytes = BytesBuilder(copy: false);
      // One deadline for the whole body: Stream.timeout alone restarts on every chunk, so a trickle would hold the slot.
      final Stopwatch clock = Stopwatch()..start();
      await for (final List<int> chunk in r.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
        if (bytes.length > kRoadMaxBody) return await _end(r, HttpStatus.requestEntityTooLarge);
        if (clock.elapsed > kRoadBodyDeadline) return await _end(r, HttpStatus.requestTimeout);
      }
      final Object? decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      final Map<String, dynamic>? answer = decoded is Map<String, dynamic>
          ? await backend(decoded, sourceKey(from))
          : null;
      if (answer == null) return await _end(r, HttpStatus.noContent);
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(answer));
      await r.response.close();
    } catch (_) {
      await _end(r, HttpStatus.badRequest);
    } finally {
      _inFlight--;
    }
  }
}

/// The client half: one POST to one phone. Null for any failure or "no answer".
class RoadHttpTransport implements PairingTransport {
  RoadHttpTransport(this.host, this.port, {this.timeout = const Duration(seconds: 8), this.allowLoopback = false});
  final String host;
  final int port;
  final Duration timeout;
  final bool allowLoopback;

  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    // Checked at the last moment too: whatever a peer list says, nothing leaves the home network.
    if (!isHomeNetworkHost(host, allowLoopback: allowLoopback)) return null;
    final HttpClient c = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest req = await c
          .postUrl(Uri(scheme: 'http', host: host, port: port, path: '/f'))
          .timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(message));
      final HttpClientResponse res = await req.close().timeout(timeout);
      if (res.statusCode != HttpStatus.ok || res.contentLength > kRoadMaxReply) {
        await res.drain<void>();
        return null;
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in res.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > kRoadMaxReply) return null;
      }
      final Object? decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }
}

/// A screen share's road to another grown-up's phone: tried against each family phone currently seen. The phone the
/// share is addressed to opens it and says what it did; any other phone, or a stranger, says "refused" and the share
/// stays sealed in the outbox. True only when the right phone has taken it.
class LanShareTransport implements ShareTransport {
  LanShareTransport(this.peers, {this.timeout = const Duration(seconds: 12), this.allowLoopback = false});

  /// The family phones seen right now.
  final Future<List<RoadPeer>> Function() peers;
  final Duration timeout;
  final bool allowLoopback;

  static const Set<String> taken = <String>{'kept', 'duplicate', 'putAway', 'takenBack'};

  @override
  Future<bool> deliver(String recipientKeyHex, Uint8List bytes) async {
    final List<RoadPeer> seen = await peers();
    for (final RoadPeer p in seen.take(4)) {
      final Map<String, dynamic>? r = await RoadHttpTransport(
        p.host,
        p.port,
        timeout: timeout,
        allowLoopback: allowLoopback,
      ).send(<String, dynamic>{'t': 'sh', 's': b64(bytes)});
      if (r != null && taken.contains(r['o'])) return true;
    }
    return false;
  }
}
