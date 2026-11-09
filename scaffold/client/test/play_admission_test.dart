// OLIVE BRANCH — admission for ad-hoc play: a hostile-peer suite over a real loopback HTTP hop. One attack per test.
// Verified by CI, headless (mDNS itself needs two devices). Research section 5.2.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_discovery.dart';
import 'package:olive_client/local_session.dart';
import 'package:olive_client/pairing_protocol.dart' show PairedKid;
import 'package:olive_client/play_admission.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

class _Rig {
  _Rig(this.adult, this.child, this.admission, this.server, this.received, this.peer);
  final DeviceKey adult, child;
  final PlayAdmission admission;
  final LocalSessionServer server;
  final List<Map<String, dynamic>> received;
  final LocalPeer peer;
}

/// The ADULT's device serves; the child's device is the sender (the confirm side is the grown-up's).
Future<_Rig> _rig({bool requireConfirm = true, bool open = true}) async {
  final DeviceKey adult = await _key(), child = await _key();
  final PlayAdmission adm = requireConfirm
      ? PlayAdmission.forAdult(adult, <PairedKid>[
          PairedKid(certId: 'c', childDeviceKey: child.publicKey, childId: 'k', deviceName: 'Tablet', issuedAtMs: 1)
        ])
      : PlayAdmission.forChild(adult, child.publicKey);
  if (open) adm.openWindow();
  final List<Map<String, dynamic>> got = <Map<String, dynamic>>[];
  final LocalSessionServer server = LocalSessionServer(onTurnReceived: got.add, admission: adm);
  await server.start();
  addTearDown(server.stop);
  final LocalPeer peer = LocalPeer(host: '127.0.0.1', port: server.port!, role: 'dad', name: 'x');
  return _Rig(adult, child, adm, server, got, peer);
}

Future<PlaySession?> _hello(_Rig r, DeviceKey as, {Uint8List? expectKey}) =>
    PlaySession.hello(own: as, peerKey: expectKey ?? r.adult.publicKey, post: LocalSessionClient(r.peer).postHello);

Future<int> _rawPost(LocalPeer p, String path, List<int> body, {Map<String, String> headers = const <String, String>{}}) async {
  final HttpClient c = HttpClient();
  try {
    final HttpClientRequest req = await c.postUrl(Uri.parse('http://${p.host}:${p.port}$path'));
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.add(body);
    final HttpClientResponse res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    c.close(force: true);
  }
}

void main() {
  group('text and labels', () {
    test('sanitizePeerText strips control, bidi and zero-width characters and limits length', () {
      expect(sanitizePeerText('Ivy\u0000\u0007'), 'Ivy');
      expect(sanitizePeerText('‮evil‬'), 'evil');
      expect(sanitizePeerText('a​b⁦c'), 'a b c');
      expect(sanitizePeerText('  lots   of\n\tspace '), 'lots of space');
      expect(sanitizePeerText('x' * 100).length, 24);
      expect(sanitizePeerText('‮\u0000'), kNeutralPeerName);
      expect(sanitizePeerText(null), kNeutralPeerName);
      expect(sanitizePeerText('Zoe \u{1F600}'), 'Zoe \u{1F600}');
      expect(sanitizePeerText('${'\u{1F600}' * 40}', max: 5).runes.length, 5, reason: 'limits characters, never splits one');
    });

    test('the neutral label is olive-xxxx and says nothing', () {
      for (int i = 0; i < 20; i++) {
        expect(neutralServiceName(), matches(RegExp(r'^olive-[0-9a-f]{4}$')));
      }
    });

    test('a resolved neutral peer shows no name, and a hostile broadcast name is cleaned', () async {
      final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya', servePort: 1);
      final List<LocalPeer> seen = <LocalPeer>[];
      d.peers.listen(seen.add);
      BonsoirDiscoveryEvent resolved(String name, Map<String, String> attrs) => BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceResolved,
          service: ResolvedBonsoirService(name: name, type: '_x._tcp', port: 9, host: '10.0.0.7', attributes: attrs));
      d.listenToEvents(Stream<BonsoirDiscoveryEvent>.fromIterable(<BonsoirDiscoveryEvent>[
        resolved('olive-ab12', <String, String>{'r': 'g'}),
        resolved('old', <String, String>{'name': '‮Mallory\u0000', 'role': 'dad'}),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.first.name, kNeutralPeerName);
      expect(seen.last.name, 'Mallory');
      await d.stop();
    });
  });

  group('the happy path', () {
    test('a paired child device is admitted after the grown-up confirms, and a signed turn arrives', () async {
      final _Rig r = await _rig();
      final PlaySession? s = await _hello(r, r.child);
      expect(s, isNotNull);
      expect(r.admission.state, PlayState.awaitingConfirm);
      expect(s!.sas.toString(), r.admission.sas.toString(), reason: 'the same word and picture on both screens');
      r.admission.confirm();
      expect(r.admission.admitted, isTrue);
      await LocalSessionClient(r.peer, session: s).sendTurn(<String, dynamic>{'move': 1});
      await LocalSessionClient(r.peer, session: s).sendTurn(<String, dynamic>{'move': 2});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.received.map((Map<String, dynamic> m) => m['move']), <int>[1, 2]);
    });

    test('the child device never asks: the pinned adult is admitted at once; a confirmed peer is remembered', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await PlaySession.hello(
          own: r.child, peerKey: r.adult.publicKey, post: LocalSessionClient(r.peer).postHello);
      expect(s, isNotNull);
      expect(r.admission.admitted, isTrue);
      // Remembered: a second session on the grown-up's device skips the tap.
      final _Rig a = await _rig();
      final PlaySession? first = await _hello(a, a.child);
      a.admission.confirm();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(first, isNotNull);
      expect(a.admission.confirmedFingerprints, hasLength(1));
      a.admission.closeWindow();
      a.admission.openWindow();
      expect(await _hello(a, a.child), isNotNull);
      expect(a.admission.admitted, isTrue, reason: 'no second confirmation for a confirmed peer');
    });
  });

  group('hostile peers (each attack fails)', () {
    test('a turn with no token is refused and never reaches the game', () async {
      final _Rig r = await _rig(requireConfirm: false);
      await _hello(r, r.child);
      expect(await _rawPost(r.peer, '/turn', utf8.encode('{"war_deal":[1,2,3]}')), HttpStatus.unauthorized);
      expect(r.received, isEmpty);
    });

    test('a stranger (a key nobody paired) cannot say hello: silence', () async {
      final _Rig r = await _rig();
      final DeviceKey stranger = await _key();
      expect(await _hello(r, stranger), isNull);
      expect(r.admission.state, PlayState.none);
    });

    test('a turn with a stale or invented session id is refused', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final Map<String, String> h = await s!.headersFor(utf8.encode('{"a":1}'));
      h['x-olive-sid'] = b64(Uint8List(16));
      expect(await _rawPost(r.peer, '/turn', utf8.encode('{"a":1}'), headers: h), HttpStatus.unauthorized);
      expect(r.received, isEmpty);
    });

    test('a forged war_deal reusing a genuine turn\'s headers on a different body is refused', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final List<int> good = utf8.encode('{"move":1}');
      final Map<String, String> h = await s!.headersFor(good);
      expect(await _rawPost(r.peer, '/turn', utf8.encode('{"war_deal":[9]}'), headers: h), HttpStatus.unauthorized);
      expect(r.received, isEmpty);
    });

    test('replaying a genuine turn (same counter) is refused the second time', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final List<int> body = utf8.encode('{"move":1}');
      final Map<String, String> h = await s!.headersFor(body);
      expect(await _rawPost(r.peer, '/turn', body, headers: h), HttpStatus.ok);
      expect(await _rawPost(r.peer, '/turn', body, headers: h), HttpStatus.unauthorized);
      expect(r.received, hasLength(1));
    });

    test('a replayed hello is silence and cannot take the seat', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      final PlaySession? s = await PlaySession.hello(
          own: r.child, peerKey: r.adult.publicKey, post: (Map<String, dynamic> b) {
        log.add(b);
        return LocalSessionClient(r.peer).postHello(b);
      });
      expect(s, isNotNull);
      expect(await r.admission.handleHello(log.single, '127.0.0.1'), isNull);
    });

    test('an oversized body gets 413, declared or chunked, and is never parsed', () async {
      final _Rig r = await _rig(requireConfirm: false);
      expect(await _rawPost(r.peer, '/turn', Uint8List(kMaxTurnBytes + 1)), HttpStatus.requestEntityTooLarge);
      // Unadmitted servers are capped too (the cap is not behind the auth).
      final LocalSessionServer open = LocalSessionServer(onTurnReceived: (_) {});
      await open.start();
      addTearDown(open.stop);
      final LocalPeer p = LocalPeer(host: '127.0.0.1', port: open.port!, role: 'x', name: 'x');
      expect(await _rawPost(p, '/turn', Uint8List(kMaxTurnBytes + 1)), HttpStatus.requestEntityTooLarge);
      expect(await _rawPost(p, '/turn', utf8.encode('{"ok":1}')), HttpStatus.ok);
    });

    test('before the grown-up confirms, turns are refused; a decline ends the session', () async {
      final _Rig r = await _rig();
      final PlaySession? s = await _hello(r, r.child);
      expect(await _rawPost(r.peer, '/turn', utf8.encode('{"a":1}'), headers: await s!.headersFor(utf8.encode('{"a":1}'))), HttpStatus.unauthorized);
      r.admission.decline();
      expect(r.admission.state, PlayState.none);
      r.admission.confirm();
      expect(r.admission.admitted, isFalse, reason: 'a late tap cannot admit a declined peer');
    });

    test('a closed lobby answers nothing; a second paired device cannot take an occupied seat', () async {
      final _Rig closed = await _rig(open: false);
      expect(await _hello(closed, closed.child), isNull);
      final _Rig r = await _rig(requireConfirm: false);
      final DeviceKey other = await _key();
      expect(await r.admission.handleHello(<String, dynamic>{'t': 'hello'}, '127.0.0.1'), isNull);
      expect(await _hello(r, r.child), isNotNull);
      expect(await _hello(r, other), isNull);
    });

    test('a turn from another address than the one that said hello is refused', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final List<int> body = utf8.encode('{"a":1}');
      final Map<String, String> h = await s!.headersFor(body);
      expect(
          await r.admission.authorizeTurn(
              sid: h['x-olive-sid'], seq: h['x-olive-seq'], mac: h['x-olive-mac'], body: body, remote: '10.9.9.9'),
          isFalse);
    });

    test('an answer not signed by the adult key the child pinned is rejected (a rogue host)', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final DeviceKey realAdult = await _key();
      expect(await _hello(r, r.child, expectKey: realAdult.publicKey), isNull, reason: 'the rogue could not sign as the real adult');
    });
  });
}
