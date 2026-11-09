// OLIVE BRANCH — which local addresses the play server may listen on, and which senders it will answer. UNVERIFIED
// on a device (the interface names differ per phone); the filters are unit-tested headless (test/lan_bind_test.dart).
// Owner requirement 2026-11-08: the app never exposes or records the network it is on beyond the local socket it needs.
//
// BIND. Only the addresses of real LAN interfaces: private IPv4 (10/8, 172.16/12, 192.168/16) or link-local, on an
// interface whose name is not a tunnel, VPN or cellular one (tun, tap, ppp, ipsec, utun, wg, vpn, rmnet, ccmni, wwan,
// pdp, v4-). Never 0.0.0.0, never a cellular address, never a VPN tunnel. All of them are bound on ONE shared port,
// because mDNS may advertise whichever address the OS chooses (the hardware-found VPN race in local_session.dart); the
// answer to that race is "every LAN address", not "any address". If there is no LAN address there is nothing to listen on
// and the caller says so.
// ANSWER. Only requests whose source is a LAN address are answered (lan_pairing_transport.dart `isLanAddress`).
//
// This file never records, logs or sends an address. The addresses live in the sockets and nowhere else.
import 'dart:io';

import 'lan_pairing_transport.dart' show isLanAddress;

final RegExp _notLan = RegExp(r'(^|[^a-z])(tun|tap|ppp|ipsec|utun|wg|vpn|rmnet|ccmni|wwan|pdp|v4-)', caseSensitive: false);

/// True for an interface name that is a tunnel, VPN or cellular link.
bool isNonLanInterface(String name) => _notLan.hasMatch(name);

/// Filters raw (interface name, address) pairs down to the addresses the play server may bind.
List<InternetAddress> filterLanAddresses(Iterable<({String interfaceName, InternetAddress address})> found) => <InternetAddress>[
      for (final ({String interfaceName, InternetAddress address}) f in found)
        if (f.address.type == InternetAddressType.IPv4 && !isNonLanInterface(f.interfaceName) && isLanAddress(f.address)) f.address,
    ];

/// The addresses to bind right now (empty when the device is on no LAN).
Future<List<InternetAddress>> lanBindAddresses() async {
  try {
    final List<NetworkInterface> ifaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: true);
    return filterLanAddresses(<({String interfaceName, InternetAddress address})>[
      for (final NetworkInterface i in ifaces)
        for (final InternetAddress a in i.addresses) (interfaceName: i.name, address: a),
    ]);
  } catch (_) {
    return <InternetAddress>[];
  }
}
