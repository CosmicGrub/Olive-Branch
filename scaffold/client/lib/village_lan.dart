// OLIVE BRANCH — the same-Wi-Fi road for the village welcome: a grown-up's phone answers a small HTTP endpoint and
// advertises itself on mDNS while a village screen is open, and another grown-up's (or a new person's) phone finds it.
// UNVERIFIED on a device (mDNS needs two real phones); the HTTP half is tested over loopback in
// client/test/village_lan_test.dart. It reuses the pairing transport's pieces rather than inventing a second set:
// [isLanAddress] and [sourceKey] (lan_pairing_transport.dart), [SourceBucket] (pairing_limits.dart), the generic
// service type [kPairServiceType] and the random-handle idea.
//
// PROXIMITY IS ENFORCED HERE. The endpoint answers only a private, link-local or unique-local source address. It exists
// only while a village screen that needs it is open (it is stopped when the screen goes), and nothing it advertises
// names a person, a family or a key: an instance name that is a neutral seat label, the protocol label `vl1` and a
// random per-start handle. The pairing browser for child tablets ignores these (it understands only `v=1`).
//
// WHAT IT CARRIES: the meet window's messages (village_meet.dart) and the door's sealed updates (village_link.dart).
// Never a PIN, a code or a key in the clear. A flood from one source is held to a budget; garbage gets silence.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import 'device_keys.dart' show b64, unb64;
import 'lan_pairing_transport.dart' show isLanAddress, sourceKey;
import 'pairing_limits.dart' show SourceBucket;
import 'pairing_protocol.dart' show PairingTransport, windowSeatLabel;
import 'village_link.dart';
import 'village_meet.dart';

/// The pairing transport's generic service type, so this adds nothing new for a bystander to notice.
const String kVillageServiceType = '_pw._tcp';
const String kVillageTxtVersion = 'vl1';

/// The TXT record: the label and a random handle. Nothing else (no name, no family, no key, no address).
Map<String, String> villageTxt(List<int> handle) => <String, String>{'v': kVillageTxtVersion, 'h': b64(handle)};

class VillageLanHost {
  VillageLanHost({this.meet, this.door, this.allowLoopback = false, SourceBucket? bucket, Random? random})
      : _bucket = bucket ?? SourceBucket(limit: 60),
        handle = meet?.discoveryHandle ?? Uint8List.fromList(List<int>.generate(16, (_) => (random ?? Random.secure()).nextInt(256)));

  /// The meet window this host fronts, if a grown-up opened one.
  final VillageMeetWindow? meet;

  /// The door to the family record, if this phone has a family.
  final VillageDoor? door;
  final bool allowLoopback;
  final SourceBucket _bucket;

  /// The random handle advertised (the meet window’s own when there is one).
  final Uint8List handle;
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;

  int? get port => _server?.port;

  BonsoirService advertisedService(int port) =>
      BonsoirService(name: windowSeatLabel(handle), type: kVillageServiceType, port: port, attributes: villageTxt(handle));

  Future<void> start({bool advertise = true}) async {
    final HttpServer s = await HttpServer.bind(InternetAddress.anyIPv6, 0, v6Only: false);
    _server = s;
    unawaited(s.forEach(_serve));
    meet?.addListener(_closeWithWindow);
    if (advertise) {
      final BonsoirBroadcast b = BonsoirBroadcast(service: advertisedService(s.port));
      _broadcast = b;
      await b.ready;
      await b.start();
    }
  }

  void _closeWithWindow() {
    final MeetState? st = meet?.state;
    // The meeting window ending ends the meeting; a host with a door stays up for the screen’s lifetime.
    if (door == null && (st == MeetState.closed || st == MeetState.declined)) unawaited(stop());
  }

  Future<void> _serve(HttpRequest r) async {
    try {
      final InternetAddress? from = r.connectionInfo?.remoteAddress;
      if (r.method != 'POST' || r.uri.path != '/v' || from == null || !isLanAddress(from, allowLoopback: allowLoopback)) {
        r.response.statusCode = HttpStatus.notFound;
        await r.response.close();
        return;
      }
      if (r.contentLength > kVillageMaxDoorBytes) {
        r.response.statusCode = HttpStatus.requestEntityTooLarge;
        await r.response.close();
        return;
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in r) {
        bytes.add(chunk);
        if (bytes.length > kVillageMaxDoorBytes) {
          r.response.statusCode = HttpStatus.requestEntityTooLarge;
          await r.response.close();
          return;
        }
      }
      final Object? decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      Map<String, dynamic>? answer;
      if (decoded is Map<String, dynamic>) {
        final String src = sourceKey(from);
        final Object? t = decoded['t'];
        if (t == 'door') {
          if (door != null && _bucket.allow(src)) answer = await door!.handle(decoded);
        } else if (meet != null) {
          answer = await meet!.handle(decoded, source: src);
        }
      }
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
    meet?.removeListener(_closeWithWindow);
    final HttpServer? s = _server;
    _server = null;
    await s?.close();
    final BonsoirBroadcast? b = _broadcast;
    _broadcast = null;
    try {
      await b?.stop();
    } catch (_) {}
  }
}

/// The client half: posts one JSON message to a village endpoint and returns the JSON answer, or null for silence.
class VillageLanTransport implements PairingTransport {
  VillageLanTransport(this.host, this.port, {this.timeout = const Duration(seconds: 8)});
  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async {
    final HttpClient c = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest req = await c.postUrl(Uri(scheme: 'http', host: host, port: port, path: '/v')).timeout(timeout);
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

/// A village endpoint seen on the network.
class NearbyVillage {
  const NearbyVillage({required this.handle, required this.host, required this.port});
  final Uint8List handle;
  final String host;
  final int port;
  String get key => b64(handle);
}

/// Reads one resolved service, or null when it is not a village endpoint.
NearbyVillage? parseVillageService({required String? host, required int port, required Map<String, String> attributes}) {
  final String? h = attributes['h'];
  if (host == null || attributes['v'] != kVillageTxtVersion || h == null) return null;
  try {
    final Uint8List handle = unb64(h);
    return handle.length == 16 ? NearbyVillage(handle: handle, host: host, port: port) : null;
  } catch (_) {
    return null;
  }
}

class VillageLanBrowser {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final StreamController<NearbyVillage> _found = StreamController<NearbyVillage>.broadcast();

  Stream<NearbyVillage> get found => _found.stream;

  Future<void> start() async {
    final BonsoirDiscovery d = BonsoirDiscovery(type: kVillageServiceType);
    _discovery = d;
    await d.ready;
    _sub = d.eventStream?.listen((BonsoirDiscoveryEvent e) {
      switch (e.type) {
        case BonsoirDiscoveryEventType.discoveryServiceFound:
          unawaited(e.service?.resolve(d.serviceResolver));
        case BonsoirDiscoveryEventType.discoveryServiceResolved:
          final BonsoirService? s = e.service;
          if (s is ResolvedBonsoirService) {
            final NearbyVillage? n = parseVillageService(host: s.host, port: s.port, attributes: s.attributes);
            if (n != null && !_found.isClosed) _found.add(n);
          }
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
  }
}
