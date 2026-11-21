// OLIVE BRANCH — family sync, the event: one signed, sealed, hash-linked record that one grown-up's phone hands to
// another. UNVERIFIED on a device; pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-SYNC-DESIGN.md sections
// 3, 5.1 and 5.2 (first slice, "S1").
//
// WHAT THIS IS. An event says "this grown-up phone, at this point in this stream, recorded this fact". It is
// authenticated by an Ed25519 signature of the writing device (so "who wrote it" cannot be forged by another
// grown-up, which a shared-key MAC alone could not promise) and sealed under the guardian-only key GK, so the server,
// a courier, a copied file and a child device see only ciphertext. The child device never holds GK
// ([FamilyKeyring.putGk] refuses it), so it cannot open one.
//
// NO NEW PRIMITIVES. The inner bytes use the family ledger's canonical value codec (encodeValue/decodeValue, strict
// re-encode check), the signature is DeviceKey's Ed25519, the seal is [guardianSeal] (ChaCha20-Poly1305 under an HKDF
// subkey of GK), the id is SHA-256. What is new is the COMPOSITION (field layout, domain strings, padding, the
// outer header as associated data). It has had no outside review: see the crypto-review addendum in
// docs/planning/EXTERNAL-CRYPTO-REVIEW-BRIEF.md ("Family sync layer"). Two deliberate differences from the design
// text, both listed there: the seal is ChaCha20-Poly1305 with a random 96-bit nonce (the design prefers a 192-bit
// XChaCha20 nonce, whose availability in the pinned package was not checked) and the stream id is derived, not minted.
//
// WIRE LAYOUT.
//   outer = lv("olive-evt-v1") | epoch (u32 big-endian) | bucket (u32 big-endian)
//   inner = encodeValue({ fid, sid, dev, seq, hlc, hc, prev[], kind, schema, payload })
//   sig   = Ed25519( dev, lv("olive/evt-sig/v1") | inner )
//   plain = lv(inner) | lv(sig) | zero padding up to `bucket` (256, 1024, 4096, 16384 or 32768)
//   wire  = outer | guardianSeal( GK[epoch], plain, aad = outer )          // nonce(12) | ciphertext | tag(16)
//   id    = SHA-256( lv(inner) | lv(sig) )         // what `prev` names; the same whichever epoch it is sealed under
// Outside the encryption an observer sees only: the version label, the key epoch, and the bucket size. Not the family,
// the writer, the stream, the kind or what it links to.
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey;
import 'family_keys.dart';
import 'family_ledger.dart' show bytesEqual, decodeValue, encodeValue, hexOf;

const String kSyncOuterLabel = 'olive-evt-v1';
const String kSyncSigDomain = 'olive/evt-sig/v1';
const String kSyncStreamDomain = 'olive/sync/stream/v1';

/// The sizes a sealed event may be padded to, so that a small edit and a larger one look alike on the wire.
const List<int> kSyncBuckets = <int>[256, 1024, 4096, 16384, 32768];

/// The most an encoded payload may be. Chosen so a payload plus its framing always fits the largest bucket.
const int kSyncMaxPayloadBytes = 24 * 1024;

/// Most `prev` links one event may carry (the ledger's own bound).
const int kSyncMaxPrev = 8;

/// An event whose clock is more than this far ahead of the receiving phone is not taken yet (design question 12).
const int kSyncMaxFutureMs = 24 * 60 * 60 * 1000;

/// One entry of the closed table of things that may be synced. A kind not listed here is refused on both ends.
class SyncKind {
  const SyncKind(this.name, this.area, this.schema);
  final String name;

  /// The data area this kind belongs to. A test checks no entry belongs to a never-leaves-the-device area.
  final String area;
  final int schema;
}

/// First slice: one area, the emergency card (guardian-written, never lockable, design 3.1).
const Map<String, SyncKind> kSyncKinds = <String, SyncKind>{
  'emergency.set': SyncKind('emergency.set', 'emergencycard', 1),
};

/// Areas the design classes "N, never leaves this device" (design 3.1 and 3.2). No sync kind may name one; a test
/// holds the table to that. The list is deliberately a superset of what a child device keeps.
const List<String> kSyncNeverAreas = <String>[
  'journal', 'worries', 'feelings', 'teen', 'mymarks', 'memorybox', 'lists', 'pictures', 'stories', 'jokes', 'lessons',
  'collections', 'ladder', 'nicknames', 'homegrowth', 'onboarding', 'profile', 'playsave', 'daytime', 'outbox',
  'localpin', 'devicekey', 'adultunlock', 'childpairing', 'role', 'pairedkids', 'learn', 'compass', 'updatestage',
];

Uint8List _u32(int v) => Uint8List.fromList(<int>[(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
int _readU32(List<int> b, int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

Future<Uint8List> _sha256(List<int> b) async => Uint8List.fromList((await Sha256().hash(b)).bytes);

/// The stream id for [area] and [child] in family [fid]: derived, so two grown-ups who both start a stream at the
/// same moment (offline) are in the SAME stream and the conflict is visible, instead of two streams that never meet.
/// It lives only inside sealed events and is the same whichever key epoch seals them.
Future<Uint8List> syncStreamId(List<int> fid, String area, String childId) async => Uint8List.fromList((await _sha256(cat(<List<int>>[
      lv(utf8.encode(kSyncStreamDomain)), lv(fid), lv(utf8.encode(area)), lv(utf8.encode(childId)),
    ])))
        .sublist(0, 16));

/// Why an event could not be opened. Short stable codes; never shown to a child, worded for grown-ups elsewhere.
class SyncOpenResult {
  const SyncOpenResult.ok(this.event) : reason = null;
  const SyncOpenResult.no(this.reason) : event = null;
  final SyncEvent? event;
  final String? reason;
}

class SyncEvent {
  SyncEvent._({
    required this.epoch, required this.fid, required this.streamId, required this.author, required this.seq,
    required this.hlcMs, required this.hlcC, required this.prev, required this.kind, required this.schema,
    required this.payload, required this.signature, required this.inner, required this.id, required this.wire,
  });

  /// The key epoch it is sealed under (the only thing about it that is not encrypted, besides its size).
  final int epoch;
  final Uint8List fid, streamId;

  /// The writing device's full Ed25519 public key.
  final Uint8List author;

  /// The writing device's own counter in this stream: 1, 2, 3, ... A reader that has 1, 2 and 4 knows 3 is missing.
  final int seq;

  /// A hybrid logical clock: wall milliseconds and a counter. It orders the list on screen and NEVER chooses a winner.
  final int hlcMs, hlcC;

  /// The ids of the events the writer had seen at the stream's ends. Two events neither reaches through `prev` are
  /// concurrent.
  final List<Uint8List> prev;
  final String kind;
  final int schema;
  final Map<String, Object?> payload;
  final Uint8List signature, inner, id, wire;

  String get idHex => hexOf(id);
  String get streamHex => hexOf(streamId);
  String get authorHex => hexOf(author);

  static Uint8List _outer(int epoch, int bucket) =>
      cat(<List<int>>[lv(utf8.encode(kSyncOuterLabel)), _u32(epoch), _u32(bucket)]);

  static Uint8List _sigMessage(List<int> inner) => cat(<List<int>>[lv(utf8.encode(kSyncSigDomain)), inner]);

  /// Builds, signs and seals one event. Throws [ArgumentError] for a kind outside [kinds], a payload that is too
  /// large, an unusable link list or a device that is not a grown-up's (no guardian key).
  static Future<SyncEvent> create({
    required DeviceKey device,
    required FamilyKeyring ring,
    required int epoch,
    required List<int> fid,
    required List<int> streamId,
    required int seq,
    required int hlcMs,
    required int hlcC,
    required List<List<int>> prev,
    required String kind,
    required Map<String, Object?> payload,
    Map<String, SyncKind> kinds = kSyncKinds,
    Random? random,
  }) async {
    final SyncKind? k = kinds[kind];
    if (k == null) throw ArgumentError('kind is not in the closed table');
    if (fid.length != 16 || streamId.length != 16) throw ArgumentError('ids must be 16 bytes');
    if (seq < 1 || hlcMs < 0 || hlcC < 0 || hlcC > 0xffff || epoch < 0) throw ArgumentError('counters out of range');
    if (prev.length > kSyncMaxPrev) throw ArgumentError('too many links');
    final List<Uint8List> links = <Uint8List>[for (final List<int> p in prev) Uint8List.fromList(p)];
    for (int i = 0; i < links.length; i++) {
      if (links[i].length != 32) throw ArgumentError('link must be 32 bytes');
      if (i > 0 && _cmp(links[i - 1], links[i]) >= 0) throw ArgumentError('links must be strictly ascending');
    }
    final Uint8List payloadBytes = encodeValue(payload);
    if (payloadBytes.length > kSyncMaxPayloadBytes) throw ArgumentError('payload too large');
    final Uint8List inner = encodeValue(<String, Object?>{
      'fid': Uint8List.fromList(fid), 'sid': Uint8List.fromList(streamId), 'dev': device.publicKey, 'seq': seq,
      'hlc': hlcMs, 'hc': hlcC, 'prev': links, 'kind': kind, 'schema': k.schema, 'payload': payload,
    });
    final Uint8List sig = await device.sign(_sigMessage(inner));
    final Uint8List framed = cat(<List<int>>[lv(inner), lv(sig)]);
    final int bucket = kSyncBuckets.firstWhere((int b) => b >= framed.length, orElse: () => throw ArgumentError('too large'));
    final Uint8List plain = Uint8List(bucket)..setRange(0, framed.length, framed);
    final Uint8List outer = _outer(epoch, bucket);
    final Uint8List sealed = await guardianSeal(ring, epoch, plain, aad: outer, random: random);
    return SyncEvent._(
      epoch: epoch, fid: Uint8List.fromList(fid), streamId: Uint8List.fromList(streamId), author: device.publicKey,
      seq: seq, hlcMs: hlcMs, hlcC: hlcC, prev: links, kind: kind, schema: k.schema,
      payload: decodeValue(payloadBytes)! as Map<String, Object?>, signature: sig, inner: inner,
      id: await _sha256(framed), wire: cat(<List<int>>[outer, sealed]),
    );
  }

  /// Opens and fully checks one wire event: size, header, key, seal, canonical form, family, kind, schema and the
  /// writer's signature. It does NOT decide whether the writer is a member now (the engine checks that against the
  /// ledger). Never throws.
  static Future<SyncOpenResult> open(
    List<int> wire, {
    required FamilyKeyring ring,
    required List<int> fid,
    Map<String, SyncKind> kinds = kSyncKinds,
  }) async {
    try {
      return await _open(wire, ring, fid, kinds);
    } catch (_) {
      return const SyncOpenResult.no('malformed');
    }
  }

  static Future<SyncOpenResult> _open(List<int> wire, FamilyKeyring ring, List<int> fid, Map<String, SyncKind> kinds) async {
    final Uint8List label = lv(utf8.encode(kSyncOuterLabel));
    final int outerLen = label.length + 8;
    if (wire.length < outerLen + 12 + 16 || wire.length > outerLen + 12 + kSyncBuckets.last + 16) {
      return const SyncOpenResult.no('size');
    }
    if (!bytesEqual(wire.sublist(0, label.length), label)) return const SyncOpenResult.no('outer');
    final int epoch = _readU32(wire, label.length), bucket = _readU32(wire, label.length + 4);
    if (!kSyncBuckets.contains(bucket) || wire.length != outerLen + 12 + bucket + 16) return const SyncOpenResult.no('size');
    if (!ring.guardianDevice || ring.gk(epoch) == null) return const SyncOpenResult.no('no_key');
    final Uint8List outer = Uint8List.fromList(wire.sublist(0, outerLen));
    final Uint8List? plain = await guardianOpen(ring, epoch, wire.sublist(outerLen), aad: outer);
    if (plain == null || plain.length != bucket) return const SyncOpenResult.no('seal');
    // Two length-prefixed fields, then nothing but zeros.
    int i = 0;
    Uint8List take() {
      int n = 0;
      for (int k = 0; k < 3; k++) {
        if (i >= plain.length) throw const FormatException('eof');
        final int x = plain[i++];
        n |= (x & 0x7f) << (7 * k);
        if ((x & 0x80) == 0) {
          if (i + n > plain.length) throw const FormatException('short');
          final Uint8List out = Uint8List.fromList(plain.sublist(i, i + n));
          i += n;
          return out;
        }
      }
      throw const FormatException('varint');
    }

    final Uint8List inner = take(), sig = take();
    final Uint8List framed = cat(<List<int>>[lv(inner), lv(sig)]);
    for (int j = i; j < plain.length; j++) {
      if (plain[j] != 0) return const SyncOpenResult.no('inner');
    }
    final Object? v = decodeValue(inner);
    if (v is! Map<String, Object?> || v.length != 10) return const SyncOpenResult.no('inner');
    if (!bytesEqual(encodeValue(v), inner)) return const SyncOpenResult.no('inner');
    final Object? efid = v['fid'], sid = v['sid'], dev = v['dev'], seq = v['seq'], hlc = v['hlc'], hc = v['hc'];
    final Object? prev = v['prev'], kind = v['kind'], schema = v['schema'], payload = v['payload'];
    if (efid is! Uint8List || efid.length != 16 || sid is! Uint8List || sid.length != 16) return const SyncOpenResult.no('inner');
    if (dev is! Uint8List || dev.length != 32 || sig.length != 64) return const SyncOpenResult.no('inner');
    if (seq is! int || seq < 1 || hlc is! int || hc is! int || hc > 0xffff || hlc > 0x3ffffffffffff) return const SyncOpenResult.no('inner');
    if (kind is! String || schema is! int || payload is! Map<String, Object?> || prev is! List) return const SyncOpenResult.no('inner');
    if (!bytesEqual(efid, fid)) return const SyncOpenResult.no('family');
    final SyncKind? k = kinds[kind];
    if (k == null || k.schema != schema) return const SyncOpenResult.no('kind');
    if (prev.length > kSyncMaxPrev) return const SyncOpenResult.no('inner');
    final List<Uint8List> links = <Uint8List>[];
    for (final Object? p in prev) {
      if (p is! Uint8List || p.length != 32) return const SyncOpenResult.no('inner');
      if (links.isNotEmpty && _cmp(links.last, p) >= 0) return const SyncOpenResult.no('inner');
      links.add(p);
    }
    if (encodeValue(payload).length > kSyncMaxPayloadBytes) return const SyncOpenResult.no('inner');
    if (!await DeviceKey.verify(dev, _sigMessage(inner), sig)) return const SyncOpenResult.no('signature');
    return SyncOpenResult.ok(SyncEvent._(
      epoch: epoch, fid: efid, streamId: sid, author: dev, seq: seq, hlcMs: hlc, hlcC: hc, prev: links, kind: kind,
      schema: schema, payload: payload, signature: sig, inner: inner, id: await _sha256(framed),
      wire: Uint8List.fromList(wire),
    ));
  }

  static int _cmp(List<int> a, List<int> b) {
    final int n = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
