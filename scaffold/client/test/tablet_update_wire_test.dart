// OLIVE BRANCH — the tablet update wire: every message round-trips, every message fits one sealed frame, and anything
// that is not exactly a message of the protocol is refused. Headless.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_frame.dart' show bucketFor, kMaxFramePayload;
import 'package:olive_client/tablet_update_wire.dart';

final String sid = newSessionId(List<int>.generate(16, (int i) => i * 7));

Object? viaJson(Map<String, Object?> m) => jsonDecode(jsonEncode(m));

void main() {
  test('every message round-trips through JSON exactly', () {
    final List<UpdateMsg> all = <UpdateMsg>[
      OfferMsg(sid, docLen: 4321, docSha: 'ab' * 32),
      NeedMsg(sid, obj: UpdateObject.apk, off: 131072, len: kUpdateWindowBytes),
      NeedMsg(sid, obj: UpdateObject.doc, off: 0, len: 1),
      PieceMsg(sid, obj: UpdateObject.apk, off: 16384, data: Uint8List.fromList(List<int>.generate(kUpdatePieceBytes, (int i) => i % 251))),
      PieceMsg(sid, obj: UpdateObject.doc, off: 0, data: Uint8List.fromList(<int>[1, 2, 3])),
      EndMsg(sid, EndWhy.done),
      EndMsg(sid, EndWhy.stop),
      EndMsg(sid, EndWhy.refused),
    ];
    for (final UpdateMsg m in all) {
      final UpdateMsg? back = decodeUpdateMsg(viaJson(encodeUpdateMsg(m)));
      expect(back, isNotNull, reason: '${m.runtimeType}');
      expect(jsonEncode(back!.toWire()), jsonEncode(m.toWire()));
    }
  });

  test('the biggest message of each kind fits one sealed frame (the transport pads to a bucket up to 32 KiB)', () {
    final PieceMsg biggest = PieceMsg(sid, obj: UpdateObject.apk, off: 0x7fffffff, data: Uint8List(kUpdatePieceBytes)..fillRange(0, kUpdatePieceBytes, 255));
    final int len = utf8.encode(jsonEncode(encodeUpdateMsg(biggest))).length;
    expect(len, lessThanOrEqualTo(kUpdateWireMaxChars));
    expect(len, lessThanOrEqualTo(kMaxFramePayload));
    expect(bucketFor(len), isNotNull);
  });

  test('a message over the wire cap is refused at encode time rather than sent', () {
    expect(() => encodeUpdateMsg(PieceMsg(sid, obj: UpdateObject.apk, off: 0, data: Uint8List(30000))), throwsStateError);
  });

  test('session ids are exactly 16 bytes of base64url and nothing else', () {
    expect(() => newSessionId(<int>[1, 2, 3]), throwsArgumentError);
    final Map<String, Object?> ok = encodeUpdateMsg(EndMsg(sid, EndWhy.stop));
    for (final Object? bad in <Object?>[null, 7, '', 'AAAA', '${sid}A', sid.substring(1), '$sid==', sid.replaceFirst(sid[0], '*')]) {
      expect(decodeUpdateMsg(<String, Object?>{...ok, 'sid': bad}), isNull, reason: '$bad');
    }
  });

  test('strictness: version, kind, extra keys, missing keys, types and ranges', () {
    final Map<String, Object?> need = encodeUpdateMsg(NeedMsg(sid, obj: UpdateObject.apk, off: 5, len: 9));
    expect(decodeUpdateMsg(need), isNotNull);
    final List<Map<String, Object?>> bad = <Map<String, Object?>>[
      <String, Object?>{...need, 'u': 2},
      <String, Object?>{...need, 'u': '1'},
      <String, Object?>{...need, 'k': 'NEED'},
      <String, Object?>{...need, 'k': 'bye'},
      <String, Object?>{...need, 'x': 1},
      (Map<String, Object?>.of(need)..remove('len')),
      <String, Object?>{...need, 'o': 'zip'},
      <String, Object?>{...need, 'off': -1},
      <String, Object?>{...need, 'off': 1.5},
      <String, Object?>{...need, 'off': '5'},
      <String, Object?>{...need, 'off': 0x80000000},
      <String, Object?>{...need, 'len': 0},
      <String, Object?>{...need, 'len': kUpdateWindowBytes + 1},
    ];
    for (final Map<String, Object?> b in bad) {
      expect(decodeUpdateMsg(b), isNull, reason: '$b');
    }
    expect(decodeUpdateMsg(<String, Object?>{...need, 'len': kUpdateWindowBytes}), isNotNull);
  });

  test('pieces: empty, oversized, padded or non-canonical base64 and a lying length are all refused', () {
    final Map<String, Object?> p = encodeUpdateMsg(PieceMsg(sid, obj: UpdateObject.apk, off: 0, data: Uint8List.fromList(<int>[1, 2, 3, 4])));
    expect(decodeUpdateMsg(p), isNotNull);
    expect(decodeUpdateMsg(<String, Object?>{...p, 'd': ''}), isNull);
    expect(decodeUpdateMsg(<String, Object?>{...p, 'd': '${p['d']}='}), isNull, reason: 'padding is never sent');
    expect(decodeUpdateMsg(<String, Object?>{...p, 'd': base64Url.encode(Uint8List(kUpdatePieceBytes + 1))}), isNull);
    expect(decodeUpdateMsg(<String, Object?>{...p, 'd': 'A' * 22000}), isNull);
    expect(decodeUpdateMsg(<String, Object?>{...p, 'd': 'AQID+'}), isNull, reason: 'standard-alphabet characters are not base64url');
  });

  test('offers: the notice length and hash are bounded and lower-case hex', () {
    final Map<String, Object?> o = encodeUpdateMsg(OfferMsg(sid, docLen: 10, docSha: 'a' * 64));
    expect(decodeUpdateMsg(o), isNotNull);
    for (final Map<String, Object?> b in <Map<String, Object?>>[
      <String, Object?>{...o, 'dl': 0},
      <String, Object?>{...o, 'dl': 256 * 1024 + 1},
      <String, Object?>{...o, 'ds': 'a' * 63},
      <String, Object?>{...o, 'ds': 'A' * 64},
      <String, Object?>{...o, 'ds': 'g' * 64},
    ]) {
      expect(decodeUpdateMsg(b), isNull, reason: '$b');
    }
  });

  test('a message carries no name, address, key, version of the app or reason text', () {
    final String all = <UpdateMsg>[
      OfferMsg(sid, docLen: 10, docSha: 'a' * 64),
      NeedMsg(sid, obj: UpdateObject.apk, off: 1, len: 1),
      EndMsg(sid, EndWhy.refused),
    ].map((UpdateMsg m) => jsonEncode(m.toWire())).join();
    expect(all, isNot(contains('olive')));
    expect(all, isNot(contains('version')));
    expect(RegExp(r'\d+\.\d+\.\d+\.\d+').hasMatch(all), isFalse);
  });
}
