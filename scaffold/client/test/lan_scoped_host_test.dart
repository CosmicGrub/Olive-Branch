// OLIVE BRANCH — ROOT CAUSE of "the tablet scans and disconnects but cannot connect": the address mDNS hands the tablet.
//
// Every flow that needs only a camera (unlock, disconnect) worked on the real Fold and tablet; every flow that needs the two
// devices to talk over the Wi-Fi did not. The Wi-Fi path is: mDNS resolves the grown-up's window to a host, the tablet POSTs to
// it. Android's resolver returns an address as Java prints it, and a link-local IPv6 address is printed WITH its interface
// ("fe80::1a2b:3c4d:5e6f:7788%wlan0"). Dart's Uri turns that into "fe80::...%25wlan0", the address lookup then fails // privacy-gate: allow ip
// ("Failed host lookup"), LanPairingTransport.send swallows the exception and answers null, and the tablet ends on its calm
// "your grown-up can try again" card, every time, with nothing wrong on either screen. Nothing in a loopback test could show
// it because loopback addresses carry no scope. These tests pin the Dart behaviour and the fix.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/lan_pairing_transport.dart';

void main() {
  group('the cause, pinned', () {
    test('a scoped link-local host written the way Android prints it cannot be turned back into an address by the old path', () {
      final Uri u = Uri(scheme: 'http', host: 'fe80::1a2b:3c4d:5e6f:7788%wlan0', port: 8080, path: '/pair'); // privacy-gate: allow ip
      // What HttpClient would look up: the scope's % has become %25, which no resolver understands.
      expect(u.host, contains('%25'));
      expect(InternetAddress.tryParse(u.host), isNull, reason: 'the old transport could not connect to this host');
    });
  });

  group('the fix: connectTargetFor understands what a resolver returns', () {
    List<LanInterface> ifaces() => const <LanInterface>[LanInterface('lo', 1), LanInterface('wlan0', 7), LanInterface('rmnet_data1', 23)];

    test('IPv4 and unique-local hosts are used as they are', () {
      for (final String h in <String>['192.168.1.5', '10.0.0.9', 'fd12::5', '127.0.0.1']) { // privacy-gate: allow ip
        final ConnectTarget t = connectTargetFor(h, interfaces: ifaces())!;
        expect(t.dialAddress.address, h);
        expect(t.urlHost, h);
        expect(t.scoped, isFalse);
      }
    });

    test('a link-local host with an interface NAME is dialled on that interface\'s number', () {
      final ConnectTarget t = connectTargetFor('fe80::1a2b:3c4d:5e6f:7788%wlan0', interfaces: ifaces())!; // privacy-gate: allow ip
      expect(t.scoped, isTrue);
      expect(t.urlHost, 'fe80::1a2b:3c4d:5e6f:7788', reason: 'the request line and Host header never carry a scope'); // privacy-gate: allow ip
      expect(t.dialAddress.address, 'fe80::1a2b:3c4d:5e6f:7788%7'); // privacy-gate: allow ip
      expect(t.dialAddress.type, InternetAddressType.IPv6);
    });

    test('a link-local host with a numeric scope keeps it', () {
      final ConnectTarget t = connectTargetFor('fe80::1%12', interfaces: ifaces())!; // privacy-gate: allow ip
      expect(t.dialAddress.address, 'fe80::1%12'); // privacy-gate: allow ip
      expect(t.urlHost, 'fe80::1'); // privacy-gate: allow ip
    });

    test('the scope as the URL form writes it (%25) is read the same way', () {
      final ConnectTarget t = connectTargetFor('fe80::1%25wlan0', interfaces: ifaces())!; // privacy-gate: allow ip
      expect(t.dialAddress.address, 'fe80::1%7'); // privacy-gate: allow ip
    });

    test('Java\'s expanded form is accepted', () {
      final ConnectTarget t = connectTargetFor('fe80:0:0:0:1a2b:3c4d:5e6f:7788%wlan0', interfaces: ifaces())!; // privacy-gate: allow ip
      expect(t.dialAddress.rawAddress.length, 16);
      expect(t.dialAddress.address.endsWith('%7'), isTrue);
    });

    test('a link-local host on an interface this device does not have is not guessed: null (the tablet shows its calm card)', () {
      expect(connectTargetFor('fe80::1%nosuch0', interfaces: ifaces()), isNull); // privacy-gate: allow ip
    });

    test('a cellular or tunnel interface is never dialled for a pairing', () {
      expect(connectTargetFor('fe80::1%rmnet_data1', interfaces: ifaces()), isNull); // privacy-gate: allow ip
      expect(connectTargetFor('fe80::1%tun0', interfaces: const <LanInterface>[LanInterface('tun0', 3)]), isNull); // privacy-gate: allow ip
    });

    test('rubbish is refused, never thrown', () {
      for (final String h in <String>['', 'not a host', '%wlan0', 'fe80::zz%wlan0', 'fe80::1%', 'a%b%c', '999.1.1.1', 'example.com']) { // privacy-gate: allow ip
        expect(connectTargetFor(h, interfaces: ifaces()), isNull, reason: '"$h"');
      }
    });

    test('a public address is not a LAN address and is never dialled', () {
      expect(connectTargetFor('8.8.8.8', interfaces: ifaces()), isNull); // privacy-gate: allow ip
      expect(connectTargetFor('2001:db8::1', interfaces: ifaces()), isNull);
    });
  });

  group('the transport uses it', () {
    test('a transport for a scoped host that cannot be placed answers null at once, without a network lookup', () async {
      final LanPairingTransport t = LanPairingTransport('fe80::1%nosuch0', 9, timeout: const Duration(milliseconds: 300)); // privacy-gate: allow ip
      expect(await t.send(<String, dynamic>{'t': 'hello'}), isNull);
    });

    test('loopback (tests) and plain IPv4 still go through the ordinary path', () async {
      final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((HttpRequest r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"t":"hello-ok"}');
        await r.response.close();
      });
      final LanPairingTransport t = LanPairingTransport('127.0.0.1', s.port);
      expect((await t.send(<String, dynamic>{'t': 'hello'}))!['t'], 'hello-ok');
      await s.close(force: true);
    });
  });
}
