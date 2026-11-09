// OLIVE BRANCH — the encrypted frame and key schedule for ad-hoc play. UNVERIFIED on a device; byte-for-byte
// parity with the Node reference (tools/play_frame.mjs) is locked by test/vectors/play_frame_vectors.json
// (tools/gen-play-frame-vectors.mjs, tools/test/play_frame_vectors.test.mjs, test/play_frame_test.dart).
// Spec/PR: play admission (research section 5.2), owner requirement 2026-11-08 "security against those that may
// try to peek into the games".
//
// NOTHING IS NEW CRYPTOGRAPHY. ChaCha20-Poly1305 (RFC 8439) and HKDF-SHA256 (RFC 5869) from the maintained
// `cryptography` package (Apache-2.0). What is ours is only the layout:
//
//   frame   = version (1 byte, 0x01) || seq (8 bytes, big endian) || ciphertext || tag (16)
//   nonce   = 4 zero bytes || seq        (unique per key because seq strictly rises; one key per direction)
//   aad     = lv("olive-play-frame-v1") || lv(session id) || version || seq
//   plain   = length (2 bytes, big endian) || payload || zero padding, padded to a bucket
//   buckets = 256, 1024, 4096, 16384, 32768 bytes of plain text
//
// PADDING. Which card or move was played must not show in the size of the message, so every plain text is padded
// up to the next of a few fixed buckets: a Connect 4 drop and a Uno play look the same on the wire (both 256).
// The tag and header are constant, so the on-wire size takes only these few values.
//
// KEYS. The session has three independent 32-byte keys (HKDF-SHA256 over both Diffie-Hellman results, salted
// with the session id): one per direction, and one that only makes the confirmation word and picture. No key is
// reused for another purpose and no MAC is used beside the AEAD.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;

const int kFrameVersion = 1;
const List<int> kPadBuckets = <int>[256, 1024, 4096, 16384, 32768];

/// The most payload one frame can carry (largest bucket minus the 2 length bytes).
const int kMaxFramePayload = 32768 - 2;

class PlayKeys {
  const PlayKeys({required this.clientToServer, required this.serverToClient, required this.sas});
  final Uint8List clientToServer, serverToClient, sas;
}

Future<Uint8List> _hkdf(List<int> ikm, List<int> salt, String info) async {
  final SecretKey k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(secretKey: SecretKey(ikm), nonce: salt, info: info.codeUnits);
  return Uint8List.fromList(await k.extractBytes());
}

/// Session keys from the two Diffie-Hellman results (ephemeral-ephemeral, ephemeral-lobby key).
Future<PlayKeys> deriveSessionKeys(List<int> dhEphemeral, List<int> dhLobby, List<int> sid) async {
  final Uint8List ikm = cat(<List<int>>[lv(dhEphemeral), lv(dhLobby)]);
  return PlayKeys(
    clientToServer: await _hkdf(ikm, sid, 'olive-play-c2s-v1'),
    serverToClient: await _hkdf(ikm, sid, 'olive-play-s2c-v1'),
    sas: await _hkdf(ikm, sid, 'olive-play-sas-v1'),
  );
}

/// Keys that protect only the hello exchange (so identities are not on the wire in the clear).
Future<({Uint8List clientToServer, Uint8List serverToClient})> deriveHelloKeys(
    List<int> dh, List<int> lobbyKey, List<int> ephemeralKey) async {
  final Uint8List salt = cat(<List<int>>[lv(lobbyKey), lv(ephemeralKey)]);
  return (
    clientToServer: await _hkdf(dh, salt, 'olive-play-hello-c2s-v1'),
    serverToClient: await _hkdf(dh, salt, 'olive-play-hello-s2c-v1'),
  );
}

/// The bucket size a [payloadLength] byte payload is padded to, or null when it does not fit.
int? bucketFor(int payloadLength) {
  final int need = payloadLength + 2;
  for (final int b in kPadBuckets) {
    if (need <= b) return b;
  }
  return null;
}

Uint8List _seqBytes(int seq) {
  final Uint8List b = Uint8List(8);
  final ByteData d = ByteData.view(b.buffer);
  d.setUint32(0, seq ~/ 0x100000000);
  d.setUint32(4, seq & 0xffffffff);
  return b;
}

int _seqFrom(List<int> b) {
  final ByteData d = ByteData.view(Uint8List.fromList(b).buffer);
  return d.getUint32(0) * 0x100000000 + d.getUint32(4);
}

Uint8List _aad(List<int> sid, List<int> seq) =>
    cat(<List<int>>[lv('olive-play-frame-v1'.codeUnits), lv(sid), <int>[kFrameVersion], seq]);

Uint8List _nonce(List<int> seq) => Uint8List.fromList(<int>[0, 0, 0, 0, ...seq]);

/// Pads [payload] to its bucket (length prefix, payload, zeros).
Uint8List padPayload(List<int> payload) {
  final int? bucket = bucketFor(payload.length);
  if (bucket == null) throw ArgumentError('payload too large for one frame');
  final Uint8List out = Uint8List(bucket);
  out[0] = payload.length >> 8;
  out[1] = payload.length & 0xff;
  out.setRange(2, 2 + payload.length, payload);
  return out;
}

/// Reverses [padPayload]; null if the padding is not exactly zeros of a legal bucket.
Uint8List? unpadPayload(List<int> plain) {
  if (!kPadBuckets.contains(plain.length)) return null;
  final int n = (plain[0] << 8) | plain[1];
  if (n + 2 > plain.length) return null;
  for (int i = 2 + n; i < plain.length; i++) {
    if (plain[i] != 0) return null;
  }
  return Uint8List.fromList(plain.sublist(2, 2 + n));
}

/// Seals one payload. [seq] must be strictly higher than any used before with this [key].
Future<Uint8List> sealFrame(List<int> key, List<int> sid, int seq, List<int> payload) async {
  final Uint8List seqB = _seqBytes(seq);
  final SecretBox box = await Chacha20.poly1305Aead().encrypt(
      padPayload(payload), secretKey: SecretKey(key), nonce: _nonce(seqB), aad: _aad(sid, seqB));
  return cat(<List<int>>[<int>[kFrameVersion], seqB, box.cipherText, box.mac.bytes]);
}

class OpenedFrame {
  const OpenedFrame(this.seq, this.payload);
  final int seq;
  final Uint8List payload;
}

/// The sequence number a frame claims (no decryption), or null when it is not a well-formed frame.
int? frameSeq(List<int> frame) {
  if (frame.length < 1 + 8 + 16 + kPadBuckets.first || frame[0] != kFrameVersion) return null;
  return _seqFrom(frame.sublist(1, 9));
}

/// Opens a frame; null for ANY problem (wrong key, a flipped bit, a different session, a bad length, a bad pad).
Future<OpenedFrame?> openFrame(List<int> key, List<int> sid, List<int> frame) async {
  try {
    final int? seq = frameSeq(frame);
    if (seq == null) return null;
    final List<int> seqB = frame.sublist(1, 9);
    final int ctLen = frame.length - 9 - 16;
    if (!kPadBuckets.contains(ctLen)) return null;
    final SecretBox box = SecretBox(frame.sublist(9, 9 + ctLen), nonce: _nonce(seqB), mac: Mac(frame.sublist(9 + ctLen)));
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(box, secretKey: SecretKey(key), aad: _aad(sid, seqB));
    final Uint8List? payload = unpadPayload(plain);
    return payload == null ? null : OpenedFrame(seq, payload);
  } catch (_) {
    return null;
  }
}

/// Seals/opens a small blob with a fresh-key-per-use nonce of zero (the hello keys are used exactly once each).
Future<Uint8List> sealOnce(List<int> key, List<int> aad, List<int> plain) async {
  final SecretBox box = await Chacha20.poly1305Aead()
      .encrypt(plain, secretKey: SecretKey(key), nonce: Uint8List(12), aad: aad);
  return cat(<List<int>>[box.cipherText, box.mac.bytes]);
}

Future<Uint8List?> openOnce(List<int> key, List<int> aad, List<int> sealed) async {
  try {
    if (sealed.length < 17) return null;
    final int n = sealed.length - 16;
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
        SecretBox(sealed.sublist(0, n), nonce: Uint8List(12), mac: Mac(sealed.sublist(n))),
        secretKey: SecretKey(key), aad: aad);
    return Uint8List.fromList(plain);
  } catch (_) {
    return null;
  }
}
