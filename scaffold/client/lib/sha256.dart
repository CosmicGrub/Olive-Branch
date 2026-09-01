// OLIVE BRANCH — portable SHA-256, the primitive the court export's
// tamper-evident chain is built on. Verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). MASTERFILE §16.1 #3.
//
// A 1:1 port of packages/ledger/src/sha256.ts. That file exists in the first
// place because packages/ledger/src/ledger.ts originally called `node:crypto`,
// and §16.1 #3 promises a certified export a reader can verify FROM THE FILE
// ALONE — a verifier that only runs on our own runtime is one the other side
// has to take on trust. This port carries the same reasoning into the client:
// the hashes court_export.dart shows a guardian are computed here, for real,
// not strings standing in for a computation that never actually happens.
//
// Checked against the TS implementation's own two NIST vectors in
// sha256_test.dart (the empty string and "abc").
import 'dart:convert';
import 'dart:typed_data';

const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const int _mask32 = 0xFFFFFFFF;

int _rotr(int x, int n) {
  final int v = x & _mask32;
  return ((v >> n) | ((v << (32 - n)) & _mask32)) & _mask32;
}

/// The raw 32-byte digest. Most callers want [sha256Hex] below instead.
Uint8List sha256Bytes(Uint8List data) {
  final List<int> h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  final int bitLen = data.length * 8;
  final int padLen = (data.length + 9 + 63) & ~63;
  final Uint8List m = Uint8List(padLen);
  m.setRange(0, data.length, data);
  m[data.length] = 0x80;
  // 64-bit big-endian length. Dart ints are 64-bit (native) or arbitrary
  // precision (web), so unlike the TS original — which has to split this via
  // division to dodge a 32-bit float wraparound — a plain shift is exact here.
  final int hi = (bitLen >> 32) & _mask32;
  final int lo = bitLen & _mask32;
  m[padLen - 8] = (hi >> 24) & 0xff;
  m[padLen - 7] = (hi >> 16) & 0xff;
  m[padLen - 6] = (hi >> 8) & 0xff;
  m[padLen - 5] = hi & 0xff;
  m[padLen - 4] = (lo >> 24) & 0xff;
  m[padLen - 3] = (lo >> 16) & 0xff;
  m[padLen - 2] = (lo >> 8) & 0xff;
  m[padLen - 1] = lo & 0xff;

  final List<int> w = List<int>.filled(64, 0);
  for (int off = 0; off < padLen; off += 64) {
    for (int i = 0; i < 16; i++) {
      w[i] = (m[off + i * 4] << 24) |
          (m[off + i * 4 + 1] << 16) |
          (m[off + i * 4 + 2] << 8) |
          m[off + i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
      final int s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final int s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _mask32;
    }
    int a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
      final int bigS1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int ch = (e & f) ^ ((~e & _mask32) & g);
      final int t1 = (hh + bigS1 + ch + _k[i] + w[i]) & _mask32;
      final int bigS0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int t2 = (bigS0 + maj) & _mask32;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _mask32;
    }
    h[0] = (h[0] + a) & _mask32;
    h[1] = (h[1] + b) & _mask32;
    h[2] = (h[2] + c) & _mask32;
    h[3] = (h[3] + d) & _mask32;
    h[4] = (h[4] + e) & _mask32;
    h[5] = (h[5] + f) & _mask32;
    h[6] = (h[6] + g) & _mask32;
    h[7] = (h[7] + hh) & _mask32;
  }

  final Uint8List out = Uint8List(32);
  for (int i = 0; i < 8; i++) {
    out[i * 4] = (h[i] >> 24) & 0xff;
    out[i * 4 + 1] = (h[i] >> 16) & 0xff;
    out[i * 4 + 2] = (h[i] >> 8) & 0xff;
    out[i * 4 + 3] = h[i] & 0xff;
  }
  return out;
}

/// Lowercase hex digest of the UTF-8 encoding of [s] — what every caller in
/// this codebase actually wants (entry hashes, bundle hashes, attestations).
String sha256Hex(String s) {
  final Uint8List bytes = sha256Bytes(Uint8List.fromList(utf8.encode(s)));
  final StringBuffer buf = StringBuffer();
  for (final int b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}
