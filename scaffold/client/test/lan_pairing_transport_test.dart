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
}
