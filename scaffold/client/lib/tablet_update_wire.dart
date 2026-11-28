// OLIVE BRANCH — the wire for handing an update from a grown-up's phone to the paired tablet. Verified headless
// UNVERIFIED on a device; verified by CI headless (client/test).
// (test/tablet_update_wire_test.dart). MASTERFILE section 7.25.
//
// It rides the existing authenticated LAN transport (play_transport.dart: sealed hello between the two PAIRED device
// keys, ChaCha20-Poly1305 frames padded to fixed sizes, a rising counter that refuses replay and reorder, bound to the
// private LAN and only while a screen is open). Nothing here is a second security layer; it is a small, strict,
// RESUMABLE request-and-answer protocol on top of that one, and every number in it is capped.
//
//   phone  -> tablet   offer  {docLen, docSha}      "I hold a signed update notice of this size and hash"
//   tablet -> phone    need   {o, off, len}         "send me len bytes from off of the notice (o=doc) or the file (o=apk)"
//   phone  -> tablet   piece  {o, off, d}           up to 16 KiB of that range, base64
//   either             end    {why}                 done | stop | refused (no reason text crosses the wire)
//
// The TABLET drives (it asks for each window), so a transfer that is interrupted for any reason resumes by asking
// again from the last byte it has verified. The phone only ever answers, never pushes, and never says why anything was
// refused. The signed notice is a plain document; the tablet verifies it with the update engine before it asks for a
// single byte of the file. Messages are strict: exact key sets, exact types, capped sizes; anything else is dropped.
import 'dart:convert';
import 'dart:typed_data';

import 'device_keys.dart' show b64, unb64;

const int kUpdateWireVersion = 1;

/// The most bytes of a file in one piece message (base64 makes it 21,848 characters, inside one 32 KiB frame).
const int kUpdatePieceBytes = 16 * 1024;

/// The most one `need` may ask for (eight pieces).
const int kUpdateWindowBytes = 128 * 1024;

/// A whole message as JSON text may never be longer than this (the frame's own payload limit is 32,766).
const int kUpdateWireMaxChars = 30000;

/// A session id is 16 random bytes, base64url without padding.
const int kUpdateSidBytes = 16;

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

enum UpdateObject {
  doc('doc'),
  apk('apk');

  const UpdateObject(this.wire);
  final String wire;

  static UpdateObject? from(Object? s) {
    for (final UpdateObject o in UpdateObject.values) {
      if (o.wire == s) return o;
    }
    return null;
  }
}

enum EndWhy {
  done('done'),
  stop('stop'),
  refused('refused');

  const EndWhy(this.wire);
  final String wire;

  static EndWhy? from(Object? s) {
    for (final EndWhy w in EndWhy.values) {
      if (w.wire == s) return w;
    }
    return null;
  }
}

sealed class UpdateMsg {
  const UpdateMsg(this.sid);

  /// The session id, base64url. Chosen by the phone when its offer starts.
  final String sid;

  Map<String, Object?> toWire();
}

class OfferMsg extends UpdateMsg {
  const OfferMsg(super.sid, {required this.docLen, required this.docSha});
  final int docLen;
  final String docSha;

  @override
  Map<String, Object?> toWire() => <String, Object?>{'u': kUpdateWireVersion, 'k': 'offer', 'sid': sid, 'dl': docLen, 'ds': docSha};
}

class NeedMsg extends UpdateMsg {
  const NeedMsg(super.sid, {required this.obj, required this.off, required this.len});
  final UpdateObject obj;
  final int off;
  final int len;

  @override
  Map<String, Object?> toWire() => <String, Object?>{'u': kUpdateWireVersion, 'k': 'need', 'sid': sid, 'o': obj.wire, 'off': off, 'len': len};
}

class PieceMsg extends UpdateMsg {
  const PieceMsg(super.sid, {required this.obj, required this.off, required this.data});
  final UpdateObject obj;
  final int off;
  final Uint8List data;

  @override
  Map<String, Object?> toWire() =>
      <String, Object?>{'u': kUpdateWireVersion, 'k': 'piece', 'sid': sid, 'o': obj.wire, 'off': off, 'd': b64(data)};
}

class EndMsg extends UpdateMsg {
  const EndMsg(super.sid, this.why);
  final EndWhy why;

  @override
  Map<String, Object?> toWire() => <String, Object?>{'u': kUpdateWireVersion, 'k': 'end', 'sid': sid, 'why': why.wire};
}

/// A fresh session id from [fill] (the caller's CSPRNG).
String newSessionId(List<int> randomBytes) {
  if (randomBytes.length != kUpdateSidBytes) throw ArgumentError('a session id is $kUpdateSidBytes bytes');
  return b64(randomBytes);
}

bool _validSid(Object? s) {
  if (s is! String || s.length != 22) return false;
  try {
    return unb64(s).length == kUpdateSidBytes && b64(unb64(s)) == s;
  } catch (_) {
    return false;
  }
}

bool _sameKeys(Map<Object?, Object?> m, Set<String> keys) => m.length == keys.length && keys.every(m.containsKey);

/// The wire text a message becomes, checked against the cap.
Map<String, Object?> encodeUpdateMsg(UpdateMsg m) {
  final Map<String, Object?> w = m.toWire();
  if (jsonEncode(w).length > kUpdateWireMaxChars) throw StateError('update message over the wire cap');
  return w;
}

/// Reads one untrusted decoded-JSON message. Null for anything that is not exactly a well-formed message of this
/// protocol: wrong version, unknown kind, extra or missing keys, wrong types, out-of-range numbers, a bad session id,
/// bad base64, or a piece over [kUpdatePieceBytes].
UpdateMsg? decodeUpdateMsg(Object? raw) {
  if (raw is! Map || raw['u'] != kUpdateWireVersion) return null;
  final Object? sid = raw['sid'];
  if (!_validSid(sid)) return null;
  final String s = sid! as String;
  switch (raw['k']) {
    case 'offer':
      if (!_sameKeys(raw, <String>{'u', 'k', 'sid', 'dl', 'ds'})) return null;
      final Object? dl = raw['dl'], ds = raw['ds'];
      if (dl is! int || dl < 1 || dl > 256 * 1024 || ds is! String || !_hex64.hasMatch(ds)) return null;
      return OfferMsg(s, docLen: dl, docSha: ds);
    case 'need':
      if (!_sameKeys(raw, <String>{'u', 'k', 'sid', 'o', 'off', 'len'})) return null;
      final UpdateObject? o = UpdateObject.from(raw['o']);
      final Object? off = raw['off'], len = raw['len'];
      if (o == null || off is! int || len is! int || off < 0 || off > 0x7fffffff || len < 1 || len > kUpdateWindowBytes) return null;
      return NeedMsg(s, obj: o, off: off, len: len);
    case 'piece':
      if (!_sameKeys(raw, <String>{'u', 'k', 'sid', 'o', 'off', 'd'})) return null;
      final UpdateObject? o = UpdateObject.from(raw['o']);
      final Object? off = raw['off'], d = raw['d'];
      if (o == null || off is! int || off < 0 || off > 0x7fffffff || d is! String || d.isEmpty) return null;
      // 16 KiB of bytes is at most 21,846 base64 characters; refuse a longer string before decoding it.
      if (d.length > ((kUpdatePieceBytes + 2) ~/ 3) * 4) return null;
      final Uint8List bytes;
      try {
        bytes = unb64(d);
      } catch (_) {
        return null;
      }
      if (bytes.isEmpty || bytes.length > kUpdatePieceBytes || b64(bytes) != d) return null;
      return PieceMsg(s, obj: o, off: off, data: bytes);
    case 'end':
      if (!_sameKeys(raw, <String>{'u', 'k', 'sid', 'why'})) return null;
      final EndWhy? why = EndWhy.from(raw['why']);
      return why == null ? null : EndMsg(s, why);
  }
  return null;
}
