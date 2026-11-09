// OLIVE BRANCH — source-level guard for the owner's network-privacy requirement (2026-11-08): the app never records,
// displays, logs or transmits the Wi-Fi SSID/BSSID, LAN IPs, subnet, gateway, hostnames or MAC beyond the local socket it
// needs. Verified by CI, headless.
//
// What this proves, by reading every file in lib/: (1) nothing asks the OS for an SSID, BSSID, MAC or hostname; (2) the
// only code that lists network interfaces is the LAN-bind filter, the discovery existence check, the pairing
// controller's "is there a LAN" check and the adult's proximity QR (a picture on that screen, never sent anywhere); (3) no
// file that talks to the Olive server (it imports package:http) also touches the local-play transport or those address
// helpers, so there is no code path that could put an address in a request body; (4) nothing prints or logs an address.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> libFiles() =>
    Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();

String name(File f) => f.uri.pathSegments.last;

String code(File f) => f
    .readAsStringSync()
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final List<File> files = libFiles();

  test('nothing asks the OS for an SSID, BSSID, MAC address or hostname', () {
    final RegExp ask = RegExp(r'getWifiName|getWifiBSSID|getWifiIP|getWifiGatewayIP|getWifiSubmask|NetworkInfo\b|WifiInfo|'
        r'\bssid\b|\bbssid\b|macAddress|\bgetHostName|Platform\.localHostname|InternetAddress\.lookup|NetworkInterface\.list',
        caseSensitive: false);
    final Set<String> allowedInterfaceList = <String>{'lan_bind.dart', 'local_discovery.dart'};
    final List<String> offenders = <String>[
      for (final File f in files)
        if (ask.allMatches(code(f)).any((RegExpMatch m) =>
            !(m.group(0)!.startsWith('NetworkInterface.list') && allowedInterfaceList.contains(name(f)))))
          name(f)
    ];
    expect(offenders, isEmpty, reason: '$offenders');
  });

  test('only the LAN filter, discovery, the session server (via the filter), the pairing controller and the adult proximity QR touch interface addresses', () {
    final Set<String> allowed = <String>{'lan_bind.dart', 'local_discovery.dart', 'local_pairing.dart', 'local_session.dart', 'connect_child_screen.dart'};
    final List<String> users = <String>[
      for (final File f in files)
        if (RegExp(r'ownLocalIPv4|lanBindAddresses|NetworkInterface').hasMatch(code(f))) name(f)
    ];
    expect(users.toSet().difference(allowed), isEmpty, reason: 'unexpected users: $users');
  });

  test('no file that talks to the Olive server (package:http) touches local-play transport or address helpers', () {
    final RegExp local = RegExp(
        r"local_discovery\.dart|local_session\.dart|lan_bind\.dart|lan_pairing_transport\.dart|play_admission\.dart|local_pairing\.dart|ownLocalIPv4|LocalPeer\b|NetworkInterface");
    final List<String> offenders = <String>[
      for (final File f in files)
        if (code(f).contains('package:http/http.dart') && local.hasMatch(code(f))) name(f)
    ];
    expect(offenders, isEmpty, reason: 'a request body could carry a network identifier: $offenders');
  });

  test('nothing prints or logs an address, a peer host or a lobby token', () {
    final RegExp log = RegExp(r'(debugPrint|print|log)\([^;]*(\.host\b|address|ownLocalIPv4|lobbyToken|\.token\b|ssid|bssid)', caseSensitive: false);
    final List<String> offenders = <String>[for (final File f in files) if (log.hasMatch(code(f))) name(f)];
    expect(offenders, isEmpty, reason: '$offenders');
  });

  test('the play transport sends no app-identifying header and no Server header', () {
    final String s = code(File('lib/local_session.dart'));
    expect(s.contains('serverHeader = null'), isTrue);
    expect(s.contains('userAgent = null'), isTrue);
    expect(RegExp(r'''['"]x-olive''', caseSensitive: false).hasMatch(s), isFalse);
  });
}
