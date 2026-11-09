// OLIVE BRANCH — admission and confidentiality for ad-hoc play: a hostile-peer suite over a real loopback HTTP hop,
// with a sniffing proxy that records every byte on the wire. One attack per test. Verified by CI, headless (mDNS itself
// needs two devices). Research section 5.2; owner requirements 2026-11-08.
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
import 'package:olive_client/play_frame.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

class _Wire {
  final List<int> bytes = <int>[];
  final List<String> requestHeaders = <String>[];
  final List<String> paths = <String>[];
  String get text => latin1.decode(bytes, allowInvalid: true);
}

/// A man in the middle that forwards everything and records it all.
class _Sniffer {
  _Sniffer(this.server, this.target, this.wire);
  final HttpServer server;
  final int target;
  final _Wire wire;
  int get port => server.port;

  static Future<_Sniffer> start(int target) async {
    final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final _Wire wire = _Wire();
    s.listen((HttpRequest req) async {
      final List<int> body = <int>[for (final List<int> c in await req.toList()) ...c];
      wire.bytes.addAll(body);
      wire.paths.add(req.uri.path);
      req.headers.forEach((String n, List<String> v) => wire.requestHeaders.add('$n: ${v.join(',')}'));
      final HttpClient c = HttpClient()..userAgent = null;
      try {
        final HttpClientRequest out = await c.postUrl(Uri.parse('http://127.0.0.1:$target${req.uri.path}'));
        req.headers.contentType == null ? null : out.headers.contentType = req.headers.contentType;
        out.add(body);
        final HttpClientResponse res = await out.close();
        final List<int> back = <int>[for (final List<int> x in await res.toList()) ...x];
        wire.bytes.addAll(back);
        req.response.statusCode = res.statusCode;
        req.response.add(back);
      } finally {
        c.close(force: true);
        await req.response.close();
      }
    });
    return _Sniffer(s, target, wire);
  }
}

class _Rig {
  _Rig(this.adult, this.child, this.admission, this.server, this.received, this.peer);
  final DeviceKey adult, child;
  final PlayAdmission admission;
  final LocalSessionServer server;
  final List<Map<String, dynamic>> received;
  final LocalPeer peer;
}

/// The ADULT's device serves; the child's device is the sender (the confirm side is the grown-up's).
Future<_Rig> _rig({bool requireConfirm = true, bool open = true, DateTime Function()? now}) async {
  final DeviceKey adult = await _key(), child = await _key();
  final PlayAdmission adm = requireConfirm
      ? PlayAdmission.forAdult(
          adult,
          <PairedKid>[PairedKid(certId: 'c', childDeviceKey: child.publicKey, childId: 'k', deviceName: 'Tablet', issuedAtMs: 1)],
          now: now)
      : PlayAdmission.forChild(adult, child.publicKey, now: now);
  if (open) await adm.openWindow();
  final List<Map<String, dynamic>> got = <Map<String, dynamic>>[];
  final LocalSessionServer server = LocalSessionServer(
      onTurnReceived: got.add, admission: adm, bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4], allowLoopback: true);
  await server.start();
  addTearDown(server.stop);
  return _Rig(adult, child, adm, server, got, LocalPeer(host: '127.0.0.1', port: server.port!, role: 'seat1', name: 'x', token: adm.lobbyToken));
}

Future<PlaySession?> _hello(_Rig r, DeviceKey as, {Uint8List? expectKey, String? token, LocalPeer? via}) => PlaySession.hello(
    own: as,
    peerKey: expectKey ?? r.adult.publicKey,
    lobbyToken: token ?? r.admission.lobbyToken!,
    post: LocalSessionClient(via ?? r.peer).postHello);

Future<int> _rawPost(LocalPeer p, String path, List<int> body) async {
  final HttpClient c = HttpClient();
  try {
    final HttpClientRequest req = await c.postUrl(Uri.parse('http://${p.host}:${p.port}$path'));
    req.headers.contentType = ContentType.binary;
    req.add(body);
    final HttpClientResponse res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    c.close(force: true);
  }
}

void main() {
  group('names: nothing identifying anywhere', () {
    test('seat labels are the only text, and a seat is a plain digit', () {
      expect(seatLabel(1), 'Player one');
      expect(seatLabel(2), 'Player two');
      expect(seatLabel(3), 'Player 3');
      expect(parseSeat('1'), 1);
      expect(parseSeat('2'), 2);
      for (final String? bad in <String?>[null, '', '0', '9', '01', ' 1', 'Maya', '1; DROP', '\u202e1']) {
        expect(parseSeat(bad), isNull, reason: '$bad');
      }
    });

    test('exactly one of two devices flips on a seat clash; no clash changes nothing', () {
      for (int i = 0; i < 50; i++) {
        final String a = 'tok-${i * 7}', b = 'tok-${i * 13 + 1}';
        if (a == b) continue;
        final int na = seatAfterClash(mySeat: 1, myToken: a, peerSeat: 1, peerToken: b);
        final int nb = seatAfterClash(mySeat: 1, myToken: b, peerSeat: 1, peerToken: a);
        expect(<int>{na, nb}, <int>{1, 2}, reason: 'one stays, one flips');
      }
      expect(seatAfterClash(mySeat: 1, myToken: 'a', peerSeat: 2, peerToken: 'b'), 1);
    });

    test('what a device advertises: the seat label, a seat digit and a random token. Nothing else.', () {
      final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya Smith', servePort: 4242, lobbyToken: 'LOBBYTOKEN');
      final BonsoirService s = d.advertisedService();
      expect(s.name, anyOf('Player one', 'Player two'));
      expect(s.attributes.keys.toSet(), <String>{'s', 'k'});
      expect(s.attributes['k'], 'LOBBYTOKEN');
      final String everything = '${s.name} ${s.type} ${s.attributes}';
      for (final String leak in <String>['Maya', 'Smith', 'child', 'guardian', 'olive', 'Olive', 'ivy', 'dad']) {
        expect(everything, isNot(contains(leak)), reason: leak);
      }
      expect(localServiceType, isNot(contains('olive')));
    });

    test('two devices advertise different random tokens, and no token repeats across sessions', () {
      final Set<String> seen = <String>{};
      for (int i = 0; i < 30; i++) {
        seen.add(LocalDiscovery(role: 'child', displayName: 'x', servePort: 1).advertisedService().attributes['k']!);
      }
      expect(seen.length, 30);
    });

    test('a resolved peer is shown only as its seat label, whatever it claimed', () async {
      final LocalDiscovery d = LocalDiscovery(role: 'child', displayName: 'Maya', servePort: 1);
      final List<LocalPeer> seen = <LocalPeer>[];
      d.peers.listen(seen.add);
      BonsoirDiscoveryEvent resolved(String name, Map<String, String> attrs) => BonsoirDiscoveryEvent(
          type: BonsoirDiscoveryEventType.discoveryServiceResolved,
          service: ResolvedBonsoirService(name: name, type: '_gp._tcp', port: 9, host: '10.0.0.7', attributes: attrs));
      d.listenToEvents(Stream<BonsoirDiscoveryEvent>.fromIterable(<BonsoirDiscoveryEvent>[
        resolved('Player two', <String, String>{'s': '2', 'k': 'peer-a'}),
        resolved('Hostile', <String, String>{'s': 'Mallory\u0000', 'k': 'peer-b', 'name': 'Mallory', 'role': 'dad'}),
        resolved('NoToken', <String, String>{'s': '1'}),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.map((LocalPeer p) => p.name).toList(), <String>['Player two', kNeutralPeerName]);
      expect(seen.every((LocalPeer p) => !p.name.contains('Mallory')), isTrue);
      await d.stop();
    });

    test('the confirm and the sanitiser never let peer text through', () {
      expect(sanitizePeerText('\u202eevil\u0000\u202c'), 'evil');
      expect(sanitizePeerText('x' * 100).length, 24);
      expect(sanitizePeerText(null), kNeutralPeerName);
    });
  });

  group('the happy path', () {
    test('a paired child device is admitted after the grown-up confirms, and an encrypted turn arrives', () async {
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

    test('the child device never asks; a confirmed peer is remembered', () async {
      final _Rig r = await _rig(requireConfirm: false);
      expect(await _hello(r, r.child), isNotNull);
      expect(r.admission.admitted, isTrue);
      final _Rig a = await _rig();
      expect(await _hello(a, a.child), isNotNull);
      a.admission.confirm();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(a.admission.confirmedFingerprints, hasLength(1));
      await a.admission.openWindow();
      expect(await _hello(a, a.child), isNotNull);
      expect(a.admission.admitted, isTrue, reason: 'no second confirmation for a confirmed peer');
    });
  });

  group('confidentiality: a sniffer sees only ciphertext', () {
    test('every byte on the wire (hello, answer, turns) holds no identity and no game content', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final _Sniffer sn = await _Sniffer.start(r.server.port!);
      addTearDown(() => sn.server.close(force: true));
      final LocalPeer viaProxy = LocalPeer(host: '127.0.0.1', port: sn.port, role: 'x', name: 'x');
      final PlaySession? s = await _hello(r, r.child, via: viaProxy);
      expect(s, isNotNull);
      for (final String secret in <String>['SECRETCARD-red7', 'war_deal']) {
        await LocalSessionClient(viaProxy, session: s).sendTurn(<String, dynamic>{'k': secret, 'n': 3});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.received, hasLength(2), reason: 'the receiver did get them');
      final String wire = sn.wire.text;
      final String headers = sn.wire.requestHeaders.join('\n');
      for (final String leak in <String>[
        'SECRETCARD', 'war_deal', 'red7', b64(r.child.fingerprint), b64(r.adult.fingerprint), b64(r.child.publicKey),
        b64(r.adult.publicKey), 'olive', 'Olive', 'Maya', 'Tablet',
      ]) {
        expect(wire, isNot(contains(leak)), reason: 'wire leaks $leak');
      }
      expect(headers.toLowerCase(), isNot(contains('user-agent')));
      expect(headers.toLowerCase(), isNot(contains('olive')));
      expect(sn.wire.paths.toSet(), <String>{'/h', '/t'});
    });

    test('responses carry no Server header', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final HttpClient c = HttpClient();
      final HttpClientRequest req = await c.postUrl(Uri.parse('http://127.0.0.1:${r.server.port}/t'));
      req.add(<int>[1]);
      final HttpClientResponse res = await req.close();
      await res.drain<void>();
      expect(res.headers.value('server'), isNull);
      c.close(force: true);
    });

    test('turn sizes sit on a few buckets: a small move and a bigger play are the same size on the wire', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final Uint8List a = await s!.sealTurn(utf8.encode('{"col":3}'));
      final Uint8List b = await s.sealTurn(utf8.encode('{"play":"red-7","draw":0,"say":"uno"}'));
      expect(a.length, b.length);
    });
  });

  group('hostile peers (each attack fails)', () {
    test('a turn with no valid frame is refused and never reaches the game', () async {
      final _Rig r = await _rig(requireConfirm: false);
      await _hello(r, r.child);
      expect(await _rawPost(r.peer, '/t', utf8.encode('{"war_deal":[1,2,3]}')), HttpStatus.unauthorized);
      expect(r.received, isEmpty);
    });

    test('a stranger (a key nobody paired) cannot say hello: silence', () async {
      final _Rig r = await _rig();
      expect(await _hello(r, await _key()), isNull);
      expect(r.admission.state, PlayState.none);
    });

    test('a flipped bit in a genuine frame is refused', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final Uint8List f = await s!.sealTurn(utf8.encode('{"move":1}'));
      f[f.length - 20] ^= 1;
      expect(await _rawPost(r.peer, '/t', f), HttpStatus.unauthorized);
      expect(r.received, isEmpty);
    });

    test('replaying a genuine frame is refused the second time', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final Uint8List f = await s!.sealTurn(utf8.encode('{"move":1}'));
      expect(await _rawPost(r.peer, '/t', f), HttpStatus.ok);
      expect(await _rawPost(r.peer, '/t', f), HttpStatus.unauthorized);
      expect(r.received, hasLength(1));
    });

    test('reordering is refused: frame 2 first makes frame 1 stale', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final Uint8List f1 = await s!.sealTurn(utf8.encode('{"m":1}'));
      final Uint8List f2 = await s.sealTurn(utf8.encode('{"m":2}'));
      expect(await _rawPost(r.peer, '/t', f2), HttpStatus.ok);
      expect(await _rawPost(r.peer, '/t', f1), HttpStatus.unauthorized);
      expect(r.received.map((Map<String, dynamic> m) => m['m']), <int>[2]);
    });

    test('a frame sealed with a wrong key is refused', () async {
      final _Rig r = await _rig(requireConfirm: false);
      await _hello(r, r.child);
      final Uint8List f = await sealFrame(Uint8List(32), Uint8List(16), 1, utf8.encode('{"m":1}'));
      expect(await _rawPost(r.peer, '/t', f), HttpStatus.unauthorized);
    });

    test('two sessions cannot read each other: a frame for one is refused by the other', () async {
      final _Rig a = await _rig(requireConfirm: false), b = await _rig(requireConfirm: false);
      final PlaySession? sa = await _hello(a, a.child), sb = await _hello(b, b.child);
      expect(sa, isNotNull);
      expect(sb, isNotNull);
      final Uint8List fa = await sa!.sealTurn(utf8.encode('{"for":"a"}'));
      expect(await _rawPost(b.peer, '/t', fa), HttpStatus.unauthorized);
      expect(b.received, isEmpty);
      expect(await _rawPost(a.peer, '/t', fa), HttpStatus.ok);
    });

    test('a frame from an old session is refused after the peer starts a new one', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? first = await _hello(r, r.child);
      final Uint8List old = await first!.sealTurn(utf8.encode('{"m":1}'));
      expect(await _hello(r, r.child), isNotNull);
      expect(await _rawPost(r.peer, '/t', old), HttpStatus.unauthorized);
    });

    test('a replayed hello is silence and cannot take the seat', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
      final PlaySession? s = await PlaySession.hello(
          own: r.child, peerKey: r.adult.publicKey, lobbyToken: r.admission.lobbyToken!, post: (Map<String, dynamic> b) {
        log.add(b);
        return LocalSessionClient(r.peer).postHello(b);
      });
      expect(s, isNotNull);
      expect(await r.admission.handleHello(log.single, '127.0.0.1'), isNull);
    });

    test('an oversized body gets 413, with or without admission, and is never parsed', () async {
      final _Rig r = await _rig(requireConfirm: false);
      expect(await _rawPost(r.peer, '/t', Uint8List(kMaxTurnBytes + 1)), HttpStatus.requestEntityTooLarge);
      final LocalSessionServer open = LocalSessionServer(
          onTurnReceived: (_) {}, bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4], allowLoopback: true);
      await open.start();
      addTearDown(open.stop);
      final LocalPeer p = LocalPeer(host: '127.0.0.1', port: open.port!, role: 'x', name: 'x');
      expect(await _rawPost(p, '/t', Uint8List(kMaxTurnBytes + 1)), HttpStatus.requestEntityTooLarge);
      expect(await _rawPost(p, '/t', utf8.encode('{"ok":1}')), HttpStatus.ok);
    });

    test('before the grown-up confirms, turns are refused; a decline ends the session', () async {
      final _Rig r = await _rig();
      final PlaySession? s = await _hello(r, r.child);
      expect(await _rawPost(r.peer, '/t', await s!.sealTurn(utf8.encode('{"a":1}'))), HttpStatus.unauthorized);
      r.admission.decline();
      expect(r.admission.state, PlayState.none);
      r.admission.confirm();
      expect(r.admission.admitted, isFalse, reason: 'a late tap cannot admit a declined peer');
    });

    test('a closed lobby answers nothing; an occupied seat cannot be taken by another paired device', () async {
      final _Rig closed = await _rig(open: false);
      expect(closed.admission.lobbyToken, isNull);
      final _Rig r = await _rig(requireConfirm: false);
      final DeviceKey other = await _key();
      expect(await _hello(r, r.child), isNotNull);
      expect(await _hello(r, other), isNull);
    });

    test('the lobby token rotates every lobby, and a hello against an old token fails', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final String t1 = r.admission.lobbyToken!;
      await r.admission.openWindow();
      expect(r.admission.lobbyToken, isNot(t1));
      expect(await _hello(r, r.child, token: t1), isNull);
      expect(await _hello(r, r.child), isNotNull);
    });

    test('the lobby window expires', () async {
      DateTime t = DateTime(2026, 11, 8, 10);
      final _Rig r = await _rig(requireConfirm: false, now: () => t);
      t = t.add(const Duration(minutes: 11));
      expect(r.admission.windowOpen, isFalse);
      expect(await _hello(r, r.child), isNull);
    });

    test('a turn from another address than the one that said hello is refused', () async {
      final _Rig r = await _rig(requireConfirm: false);
      final PlaySession? s = await _hello(r, r.child);
      final Uint8List f = await s!.sealTurn(utf8.encode('{"a":1}'));
      expect(await r.admission.openTurn(f, '10.9.9.9'), isNull);
      expect(await r.admission.openTurn(f, '127.0.0.1'), isNotNull);
    });

    test('an answer not from the adult key the child pinned is rejected (a rogue host)', () async {
      final _Rig r = await _rig(requireConfirm: false);
      expect(await _hello(r, r.child, expectKey: (await _key()).publicKey), isNull);
    });

    test('a non-LAN source is refused even with a valid frame (loopback is not a LAN address)', () async {
      final DeviceKey adult = await _key(), child = await _key();
      final PlayAdmission adm = PlayAdmission.forChild(adult, child.publicKey);
      await adm.openWindow();
      final LocalSessionServer s = LocalSessionServer(
          onTurnReceived: (_) {}, admission: adm, bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4]);
      await s.start();
      addTearDown(s.stop);
      final LocalPeer p = LocalPeer(host: '127.0.0.1', port: s.port!, role: 'x', name: 'x');
      expect(await _rawPost(p, '/h', utf8.encode('{}')), HttpStatus.notFound);
      expect(await _rawPost(p, '/t', Uint8List(300)), HttpStatus.notFound);
    });
  });
}
