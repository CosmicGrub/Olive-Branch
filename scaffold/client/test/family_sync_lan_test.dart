// OLIVE BRANCH — the same-Wi-Fi road between grown-ups' phones: what it answers, what it refuses, and what an observer on
// the network can see. Verified by CI, headless over loopback (mDNS needs two real phones).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart' show b64;
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_sync_lan.dart';
import 'package:olive_client/pairing_limits.dart';

import 'family_sync_test_support.dart';

Future<({int status, String body})> post(
  int port,
  Object? body, {
  String path = '/f',
  String method = 'POST',
  bool raw = false,
}) async {
  final HttpClient c = HttpClient();
  try {
    final HttpClientRequest r = await c.openUrl(method, Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
    r.write(raw ? body as String : jsonEncode(body));
    final HttpClientResponse res = await r.close();
    return (status: res.statusCode, body: await utf8.decoder.bind(res).join());
  } finally {
    c.close(force: true);
  }
}

void main() {
  group('the server', () {
    late FamilyRoadServer srv;
    late List<Map<String, dynamic>> seen;
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>, String) backend = (m, s) async => null;

    Future<void> up({SourceBucket? bucket, bool loopback = true}) async {
      seen = <Map<String, dynamic>>[];
      srv = FamilyRoadServer(
        backend: (Map<String, dynamic> m, String s) {
          seen.add(m);
          return backend(m, s);
        },
        bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4],
        allowLoopback: loopback,
        bucket: bucket,
      );
      expect(await srv.start(), isTrue);
    }

    tearDown(() async => srv.stop());

    test('answers a posted object with the backend\'s answer', () async {
      backend = (m, s) async => <String, dynamic>{'echo': m['t']};
      await up();
      final r = await post(srv.port!, <String, dynamic>{'t': 'x'});
      expect(r.status, 200);
      expect(jsonDecode(r.body), <String, dynamic>{'echo': 'x'});
    });

    test('no answer from the backend is HTTP 204, the same as every other refusal', () async {
      backend = (m, s) async => null;
      await up();
      expect((await post(srv.port!, <String, dynamic>{'t': 'x'})).status, 204);
      expect((await post(srv.port!, <Object?>[1, 2])).status, 204, reason: 'not an object');
      expect((await post(srv.port!, 'null', raw: true)).status, 204);
    });

    test('wrong method, wrong path and garbage are refused without reaching the backend', () async {
      backend = (m, s) async => <String, dynamic>{'ok': 1};
      await up();
      expect((await post(srv.port!, '', method: 'GET', raw: true)).status, 404);
      expect((await post(srv.port!, <String, dynamic>{}, path: '/pair')).status, 404);
      expect((await post(srv.port!, <String, dynamic>{}, path: '/')).status, 404);
      expect((await post(srv.port!, '{not json', raw: true)).status, 400);
      expect(seen, isEmpty);
    });

    test('a body over the cap is refused (or the road hangs up on it) and never reaches the backend', () async {
      backend = (m, s) async => <String, dynamic>{'ok': 1};
      await up();
      try {
        final r = await post(srv.port!, '{"t":"x","pad":"${'a' * (kRoadMaxBody + 10)}"}', raw: true);
        expect(r.status, anyOf(413, 400));
      } on SocketException {
        // Hanging up mid-upload is also a refusal.
      } on HttpException {
        // Likewise.
      }
      expect(seen, isEmpty);
    });

    test('a backend that throws costs that request only; the road keeps answering', () async {
      int n = 0;
      backend = (m, s) async {
        if (n++ == 0) throw StateError('boom');
        return <String, dynamic>{'ok': 1};
      };
      await up();
      expect((await post(srv.port!, <String, dynamic>{'t': 'x'})).status, 400);
      expect((await post(srv.port!, <String, dynamic>{'t': 'x'})).status, 200);
    });

    test('a flood from one source is dropped before the backend', () async {
      backend = (m, s) async => <String, dynamic>{'ok': 1};
      await up(bucket: SourceBucket(limit: 3, window: const Duration(minutes: 5)));
      for (int i = 0; i < 3; i++) {
        expect((await post(srv.port!, <String, dynamic>{'t': 'x'})).status, 200);
      }
      expect((await post(srv.port!, <String, dynamic>{'t': 'x'})).status, 204);
      expect(seen.length, 3);
    });

    test('a request from outside a private network is not answered (loopback is outside, in production)', () async {
      backend = (m, s) async => <String, dynamic>{'ok': 1};
      await up(loopback: false);
      expect((await post(srv.port!, <String, dynamic>{'t': 'x'})).status, 404);
      expect(seen, isEmpty);
    });

    test('with no private address to listen on there is no road, and it says so', () async {
      final FamilyRoadServer none = FamilyRoadServer(backend: (m, s) async => null, bindAddresses: <InternetAddress>[]);
      expect(await none.start(), isFalse);
      expect(none.running, isFalse);
      srv = none;
    });

    test('stop really stops: nothing answers afterwards', () async {
      backend = (m, s) async => <String, dynamic>{'ok': 1};
      await up();
      final int p = srv.port!;
      await srv.stop();
      await expectLater(post(p, <String, dynamic>{'t': 'x'}), throwsA(anything));
    });
  });

  group('the tag', () {
    test('is stable within ten minutes, changes after, and differs between families', () async {
      final FamilyKeyring a = guardianRing(),
          b = FamilyKeyring(guardianDevice: true)
            ..putFk(0, List<int>.filled(32, 9))
            ..putGk(0, List<int>.filled(32, 8));
      const int t = 1800000000000;
      final Uint8List t1 = await roadTag(a, t),
          t2 = await roadTag(a, t + 1000),
          t3 = await roadTag(a, t + kRoadTagBucketMs);
      expect(t1.length, kRoadTagBytes);
      expect(t1, t2);
      expect(t1, isNot(t3));
      expect(await roadTag(b, t), isNot(t1));
    });

    test('a family phone recognises the neighbouring buckets (clocks differ), a stranger does not', () async {
      final FamilyKeyring a = guardianRing();
      final FamilyKeyring other = FamilyKeyring(guardianDevice: true)..putFk(0, List<int>.filled(32, 9));
      const int t = 1800000000000;
      final List<Uint8List> near = await roadTagsNear(a, t);
      expect(tagIn(await roadTag(a, t + kRoadTagBucketMs), near), isTrue);
      expect(tagIn(await roadTag(a, t - kRoadTagBucketMs), near), isTrue);
      expect(tagIn(await roadTag(a, t + 3 * kRoadTagBucketMs), near), isFalse);
      expect(tagIn(await roadTag(other, t), near), isFalse);
      expect(tagIn(Uint8List(3), near), isFalse, reason: 'a short tag is never a match');
    });

    test('a ring with no key yet advertises nothing recognisable', () async {
      expect(await roadTag(FamilyKeyring(guardianDevice: true), 1800000000000), Uint8List(kRoadTagBytes));
    });
  });

  group('what an observer on the Wi-Fi sees', () {
    test('only a version, a random handle and a tag (plus one flag for an open add-a-grown-up window)', () {
      final Uint8List h = Uint8List.fromList(List<int>.generate(16, (int i) => i)),
          t = Uint8List.fromList(List<int>.generate(8, (int i) => 50 + i));
      expect(roadTxt(h, t).keys.toSet(), <String>{'v', 'h', 't'});
      expect(roadTxt(h, t, join: true).keys.toSet(), <String>{'v', 'h', 't', 'j'});
      final String all = roadTxt(h, t, join: true).values.join();
      expect(all.contains(RegExp(r'olive|family|child|grown|mom|dad', caseSensitive: false)), isFalse);
      expect(kRoadServiceType.length, lessThanOrEqualTo(15));
      expect(kRoadServiceType.contains(RegExp(r'olive|family|child', caseSensitive: false)), isFalse);
    });

    test('a service that is not ours, or is malformed, is not a peer', () {
      final Uint8List h = Uint8List(16), t = Uint8List(8);
      RoadPeer? p(Map<String, String> a, {String? host = '192.168.1.20'}) => // privacy-gate: allow ip
          parseRoadService(host: host, port: 4000, attributes: a);
      expect(p(roadTxt(h, t)), isNotNull);
      expect(p(roadTxt(h, t, join: true))!.join, isTrue);
      expect(p(<String, String>{}), isNull);
      expect(p(<String, String>{...roadTxt(h, t), 'v': '2'}), isNull);
      expect(p(<String, String>{'v': '1', 'h': b64(Uint8List(15)), 't': b64(t)}), isNull);
      expect(p(<String, String>{'v': '1', 'h': b64(h), 't': b64(Uint8List(9))}), isNull);
      expect(p(<String, String>{'v': '1', 'h': '!!!', 't': '???'}), isNull);
      expect(p(roadTxt(h, t), host: null), isNull);
      // An advertisement that points off the home network is never a peer.
      for (final String off in <String>['8.8.8.8', '203.0.113.9', 'peer.local', '', '127.0.0.1']) { // privacy-gate: allow ip
        expect(p(roadTxt(h, t), host: off), isNull, reason: off);
      }
      expect(p(roadTxt(h, t), host: '10.0.0.4'), isNotNull); // privacy-gate: allow ip
      expect(p(roadTxt(h, t), host: 'fe80::1%wlan0'), isNotNull); // privacy-gate: allow ip
    });
  });

  group('the share road', () {
    late FamilyRoadServer srv;
    tearDown(() async => srv.stop());

    Future<List<RoadPeer>> peersOf(FamilyRoadServer s) async => <RoadPeer>[
      RoadPeer(host: '127.0.0.1', port: s.port!, handle: Uint8List(16), tag: Uint8List(8)),
    ];

    test('true only when the right phone says it took the picture', () async {
      String answer = 'kept';
      srv = FamilyRoadServer(
        backend: (m, s) async => <String, dynamic>{'o': answer},
        bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4],
        allowLoopback: true,
      );
      await srv.start();
      final LanShareTransport t = LanShareTransport(() => peersOf(srv), allowLoopback: true);
      for (final String a in <String>['kept', 'duplicate', 'putAway', 'takenBack']) {
        answer = a;
        expect(await t.deliver('aa', Uint8List.fromList(<int>[1, 2, 3])), isTrue, reason: a);
      }
      for (final String a in <String>['refused', 'full', 'nonsense']) {
        answer = a;
        expect(await t.deliver('aa', Uint8List.fromList(<int>[1, 2, 3])), isFalse, reason: a);
      }
    });

    test('with nobody in sight, or nobody listening, nothing is taken', () async {
      srv = FamilyRoadServer(
        backend: (m, s) async => null,
        bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4],
        allowLoopback: true,
      );
      expect(await LanShareTransport(() async => const <RoadPeer>[], allowLoopback: true).deliver('aa', Uint8List(3)), isFalse);
      final ServerSocket s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int dead = s.port;
      await s.close();
      final LanShareTransport t = LanShareTransport(
        () async => <RoadPeer>[RoadPeer(host: '127.0.0.1', port: dead, handle: Uint8List(16), tag: Uint8List(8))],
        timeout: const Duration(seconds: 2),
        allowLoopback: true,
      );
      expect(await t.deliver('aa', Uint8List(3)), isFalse);
    });
  });
}
