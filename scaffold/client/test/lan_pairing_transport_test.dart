// OLIVE BRANCH — the LAN transport's HTTP half over real loopback sockets (mDNS needs two devices and is not
// covered here). Verified by CI, headless.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));

void main() {
  test('isLanAddress: private and link-local yes; public and (by default) loopback no', () {
    bool ok(String a, {bool lo = false}) => isLanAddress(InternetAddress(a), allowLoopback: lo);
    expect(ok('192.168.1.20'), isTrue);
    expect(ok('10.0.0.5'), isTrue);
    expect(ok('172.16.4.4'), isTrue);
    expect(ok('172.32.0.1'), isFalse);
    expect(ok('169.254.1.1'), isTrue);
    expect(ok('8.8.8.8'), isFalse);
    expect(ok('127.0.0.1'), isFalse);
    expect(ok('127.0.0.1', lo: true), isTrue);
    expect(ok('fe80::1'), isTrue);
    expect(ok('fd12::1'), isTrue);
    expect(ok('2001:db8::1'), isFalse);
    expect(ok('::ffff:192.168.1.9'), isTrue);
    expect(ok('::ffff:8.8.8.8'), isFalse);
  });

  test('a full pairing over a real local HTTP hop; a non-LAN source gets nothing', () async {
    final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final AdultWindow w = await AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'f', childId: 'c', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap);
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final LanPairingHost refusing = LanPairingHost(w); // loopback is NOT a LAN address
    await refusing.start(advertise: false);
    expect(await LanPairingTransport('127.0.0.1', refusing.port!).send(<String, dynamic>{'t': 'hello', 'sid': b64(w.sid)}), isNull);
    await refusing.stop();

    final LanPairingHost host = LanPairingHost(w, allowLoopback: true);
    await host.start(advertise: false);
    final ChildPairingClient client = ChildPairingClient(
        childKey: ck, transport: LanPairingTransport('127.0.0.1', host.port!), delay: (Duration d) async {});
    final PairingResult r = await client.pair(sid: w.sid, password: '4829');
    expect(r.ok, isTrue, reason: '${r.failure}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(host.port, isNull, reason: 'the service stops with the window');
  });

  test('garbage, wrong paths and oversized bodies get no answer', () async {
    final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final AdultWindow w = await AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'f', childId: 'c', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap);
    final LanPairingHost host = LanPairingHost(w, allowLoopback: true);
    await host.start(advertise: false);
    final HttpClient c = HttpClient();
    HttpClientRequest req = await c.postUrl(Uri.parse('http://127.0.0.1:${host.port}/pair'));
    req.write('not json');
    expect((await req.close()).statusCode, 400);
    req = await c.getUrl(Uri.parse('http://127.0.0.1:${host.port}/pair'));
    expect((await req.close()).statusCode, 404);
    req = await c.postUrl(Uri.parse('http://127.0.0.1:${host.port}/pair'));
    req.write('x' * 20000);
    expect((await req.close()).statusCode, 413);
    c.close(force: true);
    await host.stop();
  });

  group('the advertisement is neutral', () {
    test('it carries a generic type, a neutral seat name and a random handle: no adult name, no session id, no fingerprint', () async {
      final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      final AdultWindow w = await AdultWindow.open(
          adultKey: ak, adultName: 'Margaret Okafor', familyId: 'the-okafor-family', childId: 'c', childName: 'Ivy',
          pin: '4829', makeUnlockVerifier: _cheap);
      final LanPairingHost host = LanPairingHost(w);
      final s = host.advertisedService(4242, await w.windowTag());
      final String everything = '${s.name}|${s.type}|${s.attributes.entries.map((e) => '${e.key}=${e.value}').join('|')}';
      expect(s.type, kPairServiceType);
      expect(s.type.length - '._tcp'.length - 1, lessThanOrEqualTo(15), reason: 'RFC 6763 service name length');
      for (final String leak in <String>[
        'Margaret', 'Okafor', 'okafor', 'Ivy', 'olive', 'Olive', 'family', 'child', 'pair', 'kid',
        b64(w.sid), b64(w.sid).substring(0, 6), b64(ak.fingerprint), b64(ak.publicKey),
      ]) {
        expect(everything, isNot(contains(leak)), reason: 'the advertisement must not contain "$leak"');
      }
      expect(s.attributes.keys.toSet(), <String>{'v', 'h', 't'}, reason: 'version, handle and recognition tag only');
      expect(s.attributes['h'], b64(w.discoveryHandle));
      expect(s.attributes['t'], b64(await w.windowTag()));
      expect(s.name, w.label);
      expect(<String>['Player one', 'Player two'], contains(s.name), reason: 'a neutral seat name, never a word that identifies');
      // The session id in any form (raw bytes, base64, hex) is nowhere in what goes on the network.
      expect(everything, isNot(contains(b64(w.sid))));
      expect(everything.toLowerCase(), isNot(contains(w.sid.map((int x) => x.toRadixString(16).padLeft(2, '0')).join())));
    });

    test('two windows for the same adult advertise nothing in common', () async {
      final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      Future<AdultWindow> open() => AdultWindow.open(
          adultKey: ak, adultName: 'Mom', familyId: 'f', childId: 'c', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap);
      final AdultWindow a = await open(), b = await open();
      final s1 = LanPairingHost(a).advertisedService(1, await a.windowTag());
      final s2 = LanPairingHost(b).advertisedService(1, await b.windowTag());
      expect(s1.attributes['h'], isNot(s2.attributes['h']));
      expect(s1.attributes['t'], isNot(s2.attributes['t']), reason: 'with no picture the tag is random per window');
    });

    test('the browser reads a version, a 16-byte handle and an 8-byte tag, and nothing else', () {
      final Uint8List h = Uint8List.fromList(List<int>.generate(16, (int i) => i));
      final Uint8List tag = Uint8List.fromList(List<int>.generate(8, (int i) => 100 + i));
      Map<String, String> txt({String v = '1', String? hh, String? t}) =>
          <String, String>{'v': v, 'h': hh ?? b64(h), 't': t ?? b64(tag)};
      final NearbyWindow? ok = parseNearbyService(name: 'Player one', host: '192.168.1.5', port: 9, attributes: txt());
      expect(ok!.label, 'Player one');
      expect(ok.handle, h);
      expect(ok.tag, tag);
      expect(ok.sid, isNull, reason: 'discovery never yields a session id');
      expect(ok.key, b64(h));
      // The old shapes (name and session id in clear; the picture branch's session-id TXT) are not understood, and
      // a short handle, a short tag, a wrong version or no host are refused.
      expect(parseNearbyService(name: 'olive-pair-abc', host: 'x', port: 1, attributes: <String, String>{'s': b64(h), 'n': 'Mom'}), isNull);
      expect(parseNearbyService(name: 'Player one', host: 'x', port: 1, attributes: <String, String>{'v': '1', 'w': b64(h), 't': b64(tag)}), isNull);
      expect(parseNearbyService(name: 'Player one', host: 'x', port: 1, attributes: txt(hh: b64(Uint8List(8)))), isNull);
      expect(parseNearbyService(name: 'Player one', host: 'x', port: 1, attributes: txt(t: b64(Uint8List(3)))), isNull);
      expect(parseNearbyService(name: 'Player one', host: 'x', port: 1, attributes: txt(v: '2')), isNull);
      expect(parseNearbyService(name: 'Player one', host: null, port: 1, attributes: txt()), isNull);
      expect(parseNearbyService(name: 'Player one', host: 'x', port: 1, attributes: txt(hh: '!!!')), isNull);
    });

    test('a full pairing over a real local HTTP hop that starts from the handle alone', () async {
      final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      final AdultWindow w = await AdultWindow.open(
          adultKey: ak, adultName: 'Mom', familyId: 'f', childId: 'c', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap);
      w.addListener(() async {
        if (w.state == WindowState.awaitingApproval) await w.approve();
      });
      final LanPairingHost host = LanPairingHost(w, allowLoopback: true);
      await host.start(advertise: false);
      final PairingResult r = await ChildPairingClient(
              childKey: ck, transport: LanPairingTransport('127.0.0.1', host.port!), delay: (Duration d) async {})
          .pair(handle: w.discoveryHandle, password: '4829');
      expect(r.ok, isTrue, reason: '${r.failure}');
      await host.stop();
    });
  });

  group('sourceKey', () {
    test('IPv4 as is; IPv4-mapped IPv6 as its IPv4; port plays no part', () {
      expect(sourceKey(InternetAddress('192.168.1.20')), '192.168.1.20');
      expect(sourceKey(InternetAddress('::ffff:192.168.1.20')), '192.168.1.20');
      expect(sourceKey(InternetAddress('::ffff:192.168.1.20')), sourceKey(InternetAddress('192.168.1.20')));
    });

    test('IPv6 is keyed by the full address: two link-local or two same-/64 devices never share a budget', () {
      expect(sourceKey(InternetAddress('fe80::1')), isNot(sourceKey(InternetAddress('fe80::2'))));
      expect(sourceKey(InternetAddress('fe80::aaaa:bbbb:cccc:dddd')), isNot(sourceKey(InternetAddress('fe80::1'))));
      expect(sourceKey(InternetAddress('fd12:3456:789a:1::5')), isNot(sourceKey(InternetAddress('fd12:3456:789a:1:aaaa:bbbb:cccc:dddd'))));
      expect(sourceKey(InternetAddress('fd12:3456:789a:1::5')), isNot(sourceKey(InternetAddress('fd12:3456:789a:2::5'))));
    });

    test('the same IPv6 device is one source however its scope is written', () {
      expect(sourceKey(InternetAddress('fe80::1')), sourceKey(InternetAddress('fe80::0001')));
      expect(sourceKey(InternetAddress('fe80::1%1')), sourceKey(InternetAddress('fe80::1')));
    });
  });

  test('the host hands the window the real source: one address cannot burn the five confirmations over HTTP', () async {
    final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final AdultWindow w = await AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'f', childId: 'c', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap);
    final LanPairingHost host = LanPairingHost(w, allowLoopback: true);
    await host.start(advertise: false);
    final ChildPairingClient wrong = ChildPairingClient(
        childKey: ck, transport: LanPairingTransport('127.0.0.1', host.port!), delay: (Duration d) async {});
    for (int i = 0; i < kSourceMaxFailures; i++) {
      expect((await wrong.pair(sid: w.sid, password: '0000')).failure, PairingFailure.notMatched);
    }
    expect(w.attemptsLeft, kWindowMaxAttempts - kSourceMaxFailures);
    // From the same address everything is now met with silence, whatever the PIN.
    expect((await wrong.pair(sid: w.sid, password: '4829')).failure, PairingFailure.unreachable);
    expect(w.attemptsLeft, kWindowMaxAttempts - kSourceMaxFailures);
    expect(w.isOpen, isTrue);
    await host.stop();
  });
}
