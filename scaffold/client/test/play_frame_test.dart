// OLIVE BRANCH — the encrypted play frame against the Node golden vectors, plus the properties that matter.
// Verified by CI, headless.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_frame.dart';

Uint8List h(String s) =>
    Uint8List.fromList(<int>[for (int i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String x(List<int> b) => b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final Map<String, dynamic> v =
      jsonDecode(File('test/vectors/play_frame_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> k = v['keys'] as Map<String, dynamic>;
  final Uint8List sid = h(k['sid'] as String);
  late PlayKeys keys;

  setUpAll(() async {
    keys = await deriveSessionKeys(h(k['dh1'] as String), h(k['dh2'] as String), sid);
  });

  test('key schedule matches the Node reference', () {
    expect(x(keys.clientToServer), k['c2s']);
    expect(x(keys.serverToClient), k['s2c']);
    expect(x(keys.sas), k['sas']);
    expect(x(keys.clientToServer), isNot(x(keys.serverToClient)), reason: 'one key per direction');
  });

  for (final Map<String, dynamic> f in (v['frames'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test('frame vector: ${f['label']}', () async {
      final Uint8List frame = await sealFrame(keys.clientToServer, sid, f['seq'] as int, h(f['payload'] as String));
      expect(x(frame), f['frame']);
      expect(bucketFor(h(f['payload'] as String).length), f['bucket']);
      final OpenedFrame? back = await openFrame(keys.clientToServer, sid, frame);
      expect(x(back!.payload), f['payload']);
      expect(back.seq, f['seq']);
    });
  }

  test('a sequence number above 32 bits still matches', () async {
    final Map<String, dynamic> b = v['bigSeq'] as Map<String, dynamic>;
    expect(x(await sealFrame(keys.clientToServer, sid, b['seq'] as int, utf8.encode('{}'))), b['frame']);
  });

  test('the wire size takes only a few values: a small move and a bigger play are the same size', () async {
    final Uint8List a = await sealFrame(keys.clientToServer, sid, 1, utf8.encode('{"col":3}'));
    final Uint8List b = await sealFrame(keys.clientToServer, sid, 2, utf8.encode('{"play":"red-7","draw":0,"say":"uno"}'));
    expect(a.length, b.length);
    final Set<int> sizes = <int>{};
    for (final int n in <int>[0, 1, 100, 254, 255, 500, 1022, 1023, 4000, 16000, 32000]) {
      sizes.add((await sealFrame(keys.clientToServer, sid, 3, Uint8List(n))).length);
    }
    expect(sizes.length, lessThanOrEqualTo(kPadBuckets.length));
  });

  test('no plaintext on the wire', () async {
    final Uint8List f = await sealFrame(keys.clientToServer, sid, 1, utf8.encode('{"war_deal":"SECRETCARD"}'));
    expect(latin1.decode(f, allowInvalid: true), isNot(contains('SECRETCARD')));
    expect(latin1.decode(f, allowInvalid: true), isNot(contains('war_deal')));
  });

  test('a flipped bit anywhere, a wrong key, another direction and another session are all rejected', () async {
    final Uint8List f = await sealFrame(keys.clientToServer, sid, 5, utf8.encode('{"a":1}'));
    expect(await openFrame(keys.clientToServer, sid, f), isNotNull);
    for (final int i in <int>[0, 3, 8, 9, 40, f.length - 1]) {
      final Uint8List bad = Uint8List.fromList(f)..[i] ^= 1;
      expect(await openFrame(keys.clientToServer, sid, bad), isNull, reason: 'byte $i');
    }
    expect(await openFrame(keys.serverToClient, sid, f), isNull);
    expect(await openFrame(Uint8List(32), sid, f), isNull);
    expect(await openFrame(keys.clientToServer, Uint8List(16), f), isNull);
    expect(await openFrame(keys.clientToServer, sid, f.sublist(0, f.length - 1)), isNull);
    expect(await openFrame(keys.clientToServer, sid, Uint8List(0)), isNull);
  });

  test('two sessions cannot read each other', () async {
    final PlayKeys other = await deriveSessionKeys(Uint8List(32)..fillRange(0, 32, 7), Uint8List(32)..fillRange(0, 32, 8), Uint8List(16)..fillRange(0, 16, 9));
    final Uint8List f = await sealFrame(keys.clientToServer, sid, 1, utf8.encode('{"a":1}'));
    expect(await openFrame(other.clientToServer, Uint8List(16)..fillRange(0, 16, 9), f), isNull);
  });

  test('padding is exact: a payload that does not fit is refused, bad padding is rejected', () {
    expect(() => padPayload(Uint8List(kMaxFramePayload + 1)), throwsArgumentError);
    expect(padPayload(Uint8List(kMaxFramePayload)).length, 32768);
    final Uint8List p = padPayload(utf8.encode('{}'));
    expect(unpadPayload(p), isNotNull);
    p[100] = 1;
    expect(unpadPayload(p), isNull, reason: 'a non-zero pad byte');
    expect(unpadPayload(Uint8List(300)), isNull, reason: 'not a bucket');
  });
}
