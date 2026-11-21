// OLIVE BRANCH — reading the optional proximity QR (olive://pair/1?s=..&k=..&q=..&a=..). UNVERIFIED on a device; headless in CI.
// The payload holds only an open window's session id, the adult device's key fingerprint, a one-time secret and
// LAN address hints: never a PIN, never a credential. It is useless once the window closes or is used.
import 'dart:typed_data';

import 'device_keys.dart';

class PairingQr {
  const PairingQr({required this.sid, required this.adultFingerprint, required this.secret, required this.hints});
  final Uint8List sid, adultFingerprint;

  /// The one-time secret as sent (base64url text); it is the PAKE password in QR mode.
  final String secret;

  /// `host:port` strings, LAN only.
  final List<String> hints;
}

/// Null for anything that is not exactly a well-formed pairing QR. Fails closed.
PairingQr? parsePairingQr(String raw) {
  try {
    final Uri u = Uri.parse(raw.trim());
    if (u.scheme != 'olive' || u.host != 'pair' || u.path != '/1') return null;
    final String? s = u.queryParameters['s'], k = u.queryParameters['k'], q = u.queryParameters['q'];
    if (s == null || k == null || q == null) return null;
    final Uint8List sid = unb64(s), fp = unb64(k);
    if (sid.length != 16 || fp.length != 16 || unb64(q).length != 16) return null;
    final List<String> hints = (u.queryParameters['a'] ?? '')
        .split(',')
        .where((String h) => RegExp(r'^[0-9a-fA-F:.\[\]-]+:\d{1,5}$').hasMatch(h))
        .toList();
    return PairingQr(sid: sid, adultFingerprint: fp, secret: q, hints: hints);
  } catch (_) {
    return null;
  }
}

/// What a string handed to the account-code screen is. The account's code is a 6-digit number or the id in its QR
/// (a UUID); anything else is NOT sent to the server. A picture made for pairing a tablet on this wifi
/// (`olive://pair/1` from a phone, `olive://id/1` from a tablet) is recognised and sent nowhere.
enum ScanShape { serverCode, localPairingPicture, unknown }

final RegExp _kSixDigits = RegExp(r'^\d{6}$');
final RegExp _kUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

ScanShape classifyScan(String raw) {
  final String t = raw.trim();
  if (parsePairingQr(t) != null || t.toLowerCase().startsWith('olive://')) return ScanShape.localPairingPicture;
  if (_kSixDigits.hasMatch(t) || _kUuid.hasMatch(t)) return ScanShape.serverCode;
  return ScanShape.unknown;
}

/// Splits `host:port` (the last colon), or null.
({String host, int port})? splitHint(String hint) {
  final int i = hint.lastIndexOf(':');
  if (i <= 0) return null;
  final int? port = int.tryParse(hint.substring(i + 1));
  if (port == null || port < 1 || port > 65535) return null;
  return (host: hint.substring(0, i).replaceAll(RegExp(r'^\[|\]$'), ''), port: port);
}
