// OLIVE BRANCH — how the app is allowed to talk to the Olive server
// (server-snoop hardening, docs/superpowers/specs/2026-11-08-server-snoop-
// hardening-design.md section 4.1; operator side: docs/operators/).
//
// Three rules, all enforced in Dart because `dart:io` does NOT read Android's
// network_security_config.xml (that file covers WebViews and platform plugins;
// this file covers the API client):
//
//   1. Release builds speak https only. Debug builds may speak http only to a
//      loopback / emulator-host / private-LAN / .local address, so a typo that
//      points a debug build at a public host over cleartext is refused too.
//   2. Public-key pinning (optional until the real host and pins exist): the
//      SHA-256 of the server certificate's SubjectPublicKeyInfo, base64, must
//      be one of the configured pins. The check runs on the connection's
//      leaf certificate BEFORE the HTTP request is written, so a mismatch
//      never sends the bearer token. dart:io exposes only the leaf, so pins
//      name the LEAF key; rotate with a backup pin (docs/operators/
//      certificate-pinning.md). A release build asking for pinning with fewer
//      than two pins fails closed.
//   3. Pins and the base URL are build-time values (--dart-define), never
//      committed: OLIVE_API_PINS=pin1,pin2.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Thrown (or surfaced as a failed request) when a request would break the
/// transport policy. Never carries a URL query, token or credential.
class TransportPolicyViolation implements Exception {
  const TransportPolicyViolation(this.reason);
  final String reason;
  @override
  String toString() => 'TransportPolicyViolation: $reason';
}

/// Pure scheme/host policy. No sockets, no globals: [release] is injected.
class OliveTransportPolicy {
  const OliveTransportPolicy({required this.release});
  final bool release;

  /// null when [base] is allowed, otherwise the reason it is refused.
  String? violation(Uri base) {
    if (!base.hasScheme || base.host.isEmpty) return 'base URL has no scheme or host';
    if (base.hasQuery || base.hasFragment || base.userInfo.isNotEmpty) {
      return 'base URL must not carry a query, fragment or credentials';
    }
    if (base.scheme == 'https') return null;
    if (base.scheme != 'http') return 'unsupported scheme "${base.scheme}"';
    if (release) return 'cleartext http is refused in release builds';
    if (isDevHost(base.host)) return null;
    return 'cleartext http to a public host is refused (debug builds may use http only for loopback, 10.0.2.2, private LAN or .local hosts)';
  }

  /// Loopback, the Android emulator's host alias, private LAN ranges,
  /// link-local and mDNS names: the only places debug builds may use http.
  static bool isDevHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h.endsWith('.local')) return true;
    if (h == '10.0.2.2') return true;
    final ip = InternetAddress.tryParse(h.replaceAll(RegExp(r'^\[|\]$'), ''));
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final r = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return r[0] == 10 ||
          (r[0] == 172 && r[1] >= 16 && r[1] <= 31) ||
          (r[0] == 192 && r[1] == 168);
    }
    if (ip.type == InternetAddressType.IPv6) return (r[0] & 0xfe) == 0xfc; // fc00::/7
    return false;
  }
}

/// A set of SPKI SHA-256 pins (base64 of 32 bytes).
class PinSet {
  PinSet(Iterable<String> pins) : pins = List.unmodifiable(pins.toSet());

  /// Parses "pin1,pin2" (the --dart-define form). Blank entries are ignored.
  factory PinSet.parse(String csv) => PinSet(
      csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));

  static final PinSet empty = PinSet(const []);

  final List<String> pins;
  bool get isEmpty => pins.isEmpty;
  bool get isNotEmpty => pins.isNotEmpty;

  static bool isWellFormed(String pin) {
    try {
      return base64.decode(pin).length == 32 && base64.encode(base64.decode(pin)) == pin;
    } catch (_) {
      return false;
    }
  }

  /// null when usable, otherwise why not. A release build needs at least two
  /// well-formed pins: a single pin that is lost bricks every installed app.
  String? validate({required bool release}) {
    if (pins.any((p) => !isWellFormed(p))) return 'a pin is not base64 of a 32-byte SHA-256';
    if (release && pins.length < 2) {
      return 'release builds need a primary pin AND a backup pin (got ${pins.length})';
    }
    return null;
  }

  bool contains(String pin) => pins.contains(pin);
}

// ---- DER / SPKI -------------------------------------------------------------

class _Tlv {
  _Tlv(this.tag, this.start, this.headerLen, this.len);
  final int tag, start, headerLen, len;
  int get bodyStart => start + headerLen;
  int get end => start + headerLen + len;
}

_Tlv _readTlv(Uint8List b, int off) {
  if (off + 2 > b.length) throw const FormatException('truncated DER');
  final tag = b[off];
  var len = b[off + 1];
  var hl = 2;
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    if (n == 0 || n > 4 || off + 2 + n > b.length) throw const FormatException('bad DER length');
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | b[off + 2 + i];
    }
    hl = 2 + n;
  }
  if (off + hl + len > b.length) throw const FormatException('DER length past end');
  return _Tlv(tag, off, hl, len);
}

/// The DER bytes of a certificate's SubjectPublicKeyInfo.
Uint8List extractSpki(Uint8List certDer) {
  final cert = _readTlv(certDer, 0);
  if (cert.tag != 0x30) throw const FormatException('certificate is not a SEQUENCE');
  final tbs = _readTlv(certDer, cert.bodyStart);
  if (tbs.tag != 0x30) throw const FormatException('tbsCertificate is not a SEQUENCE');
  var off = tbs.bodyStart;
  var el = _readTlv(certDer, off);
  if (el.tag == 0xA0) { // optional [0] version
    off = el.end;
    el = _readTlv(certDer, off);
  }
  // serial, signature alg, issuer, validity, subject: five elements to skip.
  for (var i = 0; i < 5; i++) {
    off = el.end;
    el = _readTlv(certDer, off);
  }
  // `el` is now subjectPublicKeyInfo.
  if (el.tag != 0x30) throw const FormatException('SPKI is not a SEQUENCE');
  return Uint8List.sublistView(certDer, el.start, el.end);
}

/// base64(SHA-256(SPKI)) of a DER certificate: the pin format.
Future<String> spkiPin(Uint8List certDer) async {
  final h = await Sha256().hash(extractSpki(certDer));
  return base64.encode(h.bytes);
}

/// True when [certDer]'s SPKI pin is in [pins]. Never throws: a certificate
/// that cannot be parsed does not match.
Future<bool> certificateMatchesPins(Uint8List? certDer, PinSet pins) async {
  if (certDer == null || pins.isEmpty) return false;
  try {
    return pins.contains(await spkiPin(certDer));
  } on FormatException {
    return false;
  }
}

// ---- clients ------------------------------------------------------------

/// Builds an [http.Client] whose every TLS connection is pin-checked before a
/// byte of the request is written. [context] is a test seam (a context that
/// trusts a throwaway certificate); production passes none.
http.Client createPinnedClient(PinSet pins,
    {SecurityContext? context, Duration? connectionTimeout}) {
  final hc = HttpClient(context: context)
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = connectionTimeout;
  hc.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
    final socket = SecureSocket.connect(uri.host, uri.port, context: context)
        .then<Socket>((SecureSocket s) async {
      if (!await certificateMatchesPins(s.peerCertificate?.der, pins)) {
        s.destroy();
        throw const HandshakeException('server key does not match a pinned key');
      }
      return s;
    });
    return ConnectionTask.fromSocket<Socket>(socket, () {});
  };
  return IOClient(hc);
}

/// A client that refuses every request: what a policy violation turns into,
/// so a bad base URL is a failed request, not a crash at construction.
class RefusingClient extends http.BaseClient {
  RefusingClient(this.reason);
  final String reason;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(TransportPolicyViolation(reason));
}

/// The one place the app obtains an HTTP client for the Olive server.
class OliveTransport {
  OliveTransport._();

  static OliveTransportPolicy policy = const OliveTransportPolicy(release: kReleaseMode);
  static PinSet pins = PinSet.parse(const String.fromEnvironment('OLIVE_API_PINS'));

  /// Test seam: restore the build-time defaults.
  static void resetForTesting() {
    policy = const OliveTransportPolicy(release: kReleaseMode);
    pins = PinSet.parse(const String.fromEnvironment('OLIVE_API_PINS'));
  }

  /// Why [baseUrl] cannot be used with the current policy and pins, or null.
  static String? refusalFor(String baseUrl) {
    final Uri u;
    try {
      u = Uri.parse(baseUrl);
    } catch (_) {
      return 'base URL is not a URL';
    }
    final v = policy.violation(u);
    if (v != null) return v;
    if (_shouldPin(u)) return pins.validate(release: policy.release);
    return null;
  }

  static bool _shouldPin(Uri u) =>
      pins.isNotEmpty && u.scheme == 'https' && !OliveTransportPolicy.isDevHost(u.host);

  /// An [http.Client] for [baseUrl]: pinned when pins are configured and the
  /// host is not a dev host, plain otherwise, refusing when the URL breaks the
  /// policy.
  static http.Client clientFor(String baseUrl) {
    final why = refusalFor(baseUrl);
    if (why != null) return RefusingClient(why);
    final u = Uri.parse(baseUrl);
    return _shouldPin(u) ? createPinnedClient(pins) : http.Client();
  }
}
