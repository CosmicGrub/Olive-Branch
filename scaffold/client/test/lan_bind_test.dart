// OLIVE BRANCH — the play socket's bind and lifecycle rules (owner requirement 2026-11-08: the app never exposes the
// network it is on beyond the local socket it needs). Verified by CI, headless.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/lan_bind.dart';
import 'package:olive_client/local_session.dart';
import 'package:olive_client/play_lifecycle.dart';

({String interfaceName, InternetAddress address}) f(String n, String a) => (interfaceName: n, address: InternetAddress(a));

void main() {
  test('only real LAN interfaces are bound: never a VPN, a tunnel or a cellular link, never a public address', () {
    final List<InternetAddress> got = filterLanAddresses(<({String interfaceName, InternetAddress address})>[
      f('wlan0', '192.168.1.20'),
      f('eth0', '10.0.0.4'),
      f('wlan1', '169.254.3.3'),
      f('tun0', '10.8.0.2'), // a VPN with a private address
      f('rmnet_data0', '10.50.1.1'), // cellular with a private (CGNAT) address
      f('ccmni1', '192.168.9.9'),
      f('ppp0', '172.20.0.1'),
      f('utun3', '192.168.50.1'),
      f('wg0', '10.9.0.1'),
      f('v4-rmnet0', '10.60.0.1'),
      f('wlan0', '8.8.8.8'), // a public address even on wlan
      f('lo', '127.0.0.1'),
      f('wlan0', '0.0.0.0'),
    ]);
    expect(got.map((InternetAddress a) => a.address).toList(), <String>['192.168.1.20', '10.0.0.4', '169.254.3.3']);
  });

  test('interface names: tunnel and cellular names are recognised', () {
    for (final String n in <String>['tun0', 'tap1', 'ppp0', 'ipsec0', 'utun2', 'wg0', 'vpn', 'rmnet_data3', 'ccmni0', 'wwan0', 'pdp0', 'v4-rmnet_data1']) {
      expect(isNonLanInterface(n), isTrue, reason: n);
    }
    for (final String n in <String>['wlan0', 'eth0', 'en0', 'wlp3s0', 'ap0']) {
      expect(isNonLanInterface(n), isFalse, reason: n);
    }
  });

  test('the server listens only on the addresses it is given, never 0.0.0.0, and refuses to start with none', () async {
    final LocalSessionServer none = LocalSessionServer(onTurnReceived: (_) {}, bindAddresses: <InternetAddress>[]);
    await expectLater(none.start(), throwsA(isA<LocalSessionException>()));
    expect(none.isListening, isFalse);

    final LocalSessionServer s = LocalSessionServer(onTurnReceived: (_) {}, bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4]);
    await s.start();
    expect(s.isListening, isTrue);
    // Bound to loopback only: connecting on the machine's other (non-loopback) address must fail if one exists.
    final List<NetworkInterface> ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final NetworkInterface i in ifaces) {
      for (final InternetAddress a in i.addresses) {
        await expectLater(Socket.connect(a, s.port!, timeout: const Duration(milliseconds: 500)), throwsA(anything),
            reason: 'must not be reachable on a non-bound interface');
      }
    }
    await s.stop();
  });

  test('lifecycle: the socket opens, and stop() closes it so the port refuses connections', () async {
    final LocalSessionServer s = LocalSessionServer(onTurnReceived: (_) {}, bindAddresses: <InternetAddress>[InternetAddress.loopbackIPv4]);
    await s.start();
    final int port = s.port!;
    final Socket ok = await Socket.connect(InternetAddress.loopbackIPv4, port);
    ok.destroy();
    await s.stop();
    expect(s.isListening, isFalse);
    expect(s.port, isNull);
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 500)), throwsA(anything));
  });

  testWidgets('leaving the foreground fires the guard; a passing inactive state does not; detaching stops it', (t) async {
    int left = 0;
    final PlayServerGuard g = PlayServerGuard(onLeave: () => left++)..attach();
    final TestWidgetsFlutterBinding b = t.binding;
    b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(left, 0, reason: 'a notification shade is not leaving');
    b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(left, 1);
    b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(left, 2);
    g.detach();
    b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(left, 2);
  });
}
