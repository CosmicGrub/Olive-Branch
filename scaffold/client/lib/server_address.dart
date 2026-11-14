// OLIVE BRANCH — which server address this install talks to. No longer
// UNVERIFIED — verified by CI (client/test/server_address_test.dart).
//
// WHY. The address used to be a build-time constant only (--dart-define=
// OLIVE_API_BASE_URL). That is fine for a stable domain; it is a trap for a
// server reached through a free quick tunnel, whose https address changes every
// time the tunnel restarts. So a GROWN-UP can now type a new address on the
// phone ("Server address", More > This device), and it is remembered.
//
//  - The built-in address is the build-time define, unchanged. Everything that
//    worked before (flutter run --dart-define=..., the CI defaults) still works.
//  - A saved address wins over the built-in one; "Use the built-in address"
//    removes it.
//  - https ONLY. The setting never accepts cleartext http, not even for a LAN
//    host: a typed address is exactly where a typo would otherwise send a
//    session over the wire in the clear. (Debug builds keep their own http
//    allowance through the define, via server_transport_policy.dart; that is
//    not widened here.) An origin only: no path, query, fragment or login.
//  - It is stored in LocalStore (namespace device.serveraddress, in the
//    catalogue) as a plain, non-secret string. It is read ONCE at start-up,
//    before any screen or session is built, so a change takes effect after the
//    app is restarted (the screen says so).
//  - Certificate pinning is NOT used for this address: a quick-tunnel
//    certificate rotates, and pins need a stable domain (see
//    docs/operators/certificate-pinning.md). With no pins configured an https
//    address is accepted by OliveTransport in release builds; the http refusal
//    is unchanged.
//  - Only the guardian screen (server_address_screen.dart) writes it. No child
//    screen reads or shows it.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_store.dart';
import 'server_transport_policy.dart';

/// The build-time address (the dart-define), with the emulator default.
const String kBuiltInBaseUrl = String.fromEnvironment('OLIVE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8123'); // Android emulator's host-loopback alias

/// Namespace + key under which the choice is stored (device scope).
const String kServerAddressArea = 'serveraddress';
const String _kKey = 'url';

class ServerAddress {
  ServerAddress._();

  static String? _override;

  /// The saved, validated address, or null when the built-in one is in use.
  static String? get override => _override;

  /// What every live screen should talk to right now.
  static String get current => _override ?? kBuiltInBaseUrl;

  static bool get usingOverride => _override != null;

  /// Test seam and wipe hook: forget any in-memory choice.
  static void resetInMemory() => _override = null;

  /// null when [input] is an acceptable server address, else a plain-words
  /// reason. Accepts surrounding spaces and one trailing slash.
  static String? problem(String input) => _parse(input).$2;

  /// The normalised origin (scheme://host[:port]) for [input], or null.
  static String? normalise(String input) => _parse(input).$1;

  static (String?, String?) _parse(String input) {
    var s = input.trim();
    if (s.isEmpty) return (null, 'Type the address, starting with https://');
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    final Uri u;
    try {
      u = Uri.parse(s);
    } catch (_) {
      return (null, 'That does not look like an address.');
    }
    if (u.scheme != 'https') {
      return (null, 'The address must start with https:// (a plain http:// address is never used).');
    }
    if (u.host.isEmpty || !u.host.contains('.')) {
      return (null, 'The address needs a host name, like example.com.');
    }
    if (u.hasQuery || u.hasFragment || u.userInfo.isNotEmpty || (u.path.isNotEmpty && u.path != '/')) {
      return (null, 'Use just the address, with no path, login or extra parts.');
    }
    if (!RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(u.host)) {
      return (null, 'That is not a valid host name.');
    }
    if (u.hasPort && (u.port < 1 || u.port > 65535)) return (null, 'That port is not valid.');
    // The one transport policy has the last word (a release-mode check, so the
    // rule is the strict one whatever mode this runs in).
    final why = const OliveTransportPolicy(release: true).violation(u);
    if (why != null) return (null, 'That address cannot be used.');
    final origin = Uri(scheme: 'https', host: u.host.toLowerCase(), port: u.hasPort ? u.port : null)
        .toString();
    return (origin, null);
  }

  static LocalNamespace _ns(LocalStore store) => store.open(const NamespaceSpec(
      name: 'device.$kServerAddressArea', schema: 1, encrypted: false, maxBytes: 4 * 1024));

  /// Reads the saved address from [ns] into memory. A stored value that no
  /// longer validates is ignored (the built-in address is used), never trusted.
  static Future<void> load(LocalNamespace ns) async {
    try {
      final Object? v = await ns.get(_kKey);
      _override = v is String ? normalise(v) : null;
    } catch (_) {
      _override = null;
    }
  }

  /// Validates and saves [input]. Returns the reason it was refused, or null
  /// when it was saved. Takes effect for sessions built after the next start.
  static Future<String?> save(LocalNamespace ns, String input) async {
    final String? origin = normalise(input);
    if (origin == null) return problem(input);
    await ns.put(_kKey, origin);
    _override = origin;
    return null;
  }

  /// "Use the built-in address".
  static Future<void> reset(LocalNamespace ns) async {
    await ns.delete(_kKey);
    _override = null;
  }

  /// Start-up read, before LocalServices exists (pairing screens need the
  /// address first). Opens the same directory LocalServices.boot uses.
  /// Never throws: any failure leaves the built-in address in force.
  static Future<void> bootLoad({Directory? rootOverride}) async {
    try {
      final Directory docs = rootOverride ?? await getApplicationDocumentsDirectory();
      final Directory root =
          rootOverride ?? Directory('${docs.path}${Platform.pathSeparator}olive_store');
      await load(_ns(LocalStore(backend: DirectoryStoreBackend(root))));
    } catch (_) {
      _override = null;
    }
  }
}
