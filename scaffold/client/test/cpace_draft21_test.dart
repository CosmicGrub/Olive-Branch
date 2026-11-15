// OLIVE BRANCH — CPace as in draft-irtf-cfrg-cpace-21 (CPACE-X25519-SHA512): the draft's published appendix B.1
// vectors against lib/cpace.dart, byte for byte. The vectors are in test/vectors/cpace_draft21_vectors.json
// (copied from the draft text by a script that also checked them against the draft's own BASE64 JSON); the Node
// reference (tools/test/cpace_draft21.test.mjs) is held to the SAME file. UNVERIFIED on a device; headless in CI.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart';

Uint8List h(String s) =>
    Uint8List.fromList(<int>[for (int i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String x(List<int> b) => b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final Map<String, dynamic> v =
      jsonDecode(File('test/vectors/cpace_draft21_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> g11 = v['b11_generator'] as Map<String, dynamic>;
  final Map<String, dynamic> a = v['b12_messageA'] as Map<String, dynamic>;
  final Map<String, dynamic> b = v['b13_messageB'] as Map<String, dynamic>;
  final Map<String, dynamic> ir = v['b15_iskIr'] as Map<String, dynamic>;
  final Map<String, dynamic> oc = v['b16_iskOc'] as Map<String, dynamic>;
  final Map<String, dynamic> low = v['b110_lowOrder'] as Map<String, dynamic>;
  final Uint8List prs = h(g11['prs'] as String), ci = h(g11['ci'] as String), sid = h(g11['sid'] as String);

  test('suite constants: DSI CPace255 and the SHA-512 block size', () {
    expect(kPakeDsi, 'CPace255');
    expect(utf8.encode(kPakeDsi), h(g11['dsi'] as String));
    expect(kPakeHashBlockBytes, 128);
  });

  test('B.1.1 generator: string, its hash, the decoded field element and g', () async {
    final Uint8List gs = cpaceGeneratorString(prs, sid, ci);
    expect(x(gs), g11['generatorString']);
    expect(gs.length, 170);
    expect(gs[18], g11['zpadLength'], reason: 'the zero padding is length-prefixed (0x6d)');
    expect(x(await cpaceGeneratorHash(prs, sid, ci)), g11['generatorStringHash']);
    expect(x(decodeUCoordinate(h(g11['generatorStringHash'] as String))), g11['decodedFieldElement']);
    expect(x(await cpaceGenerator(prs, sid, ci)), g11['g']);
  });

  test('B.1.2 and B.1.3 shares, B.1.4 K', () async {
    final Uint8List g = h(g11['g'] as String);
    final Uint8List ya = h(a['ya'] as String), yb = h(b['yb'] as String);
    final Uint8List ysA = await cpaceScalarMultVfy(ya, g), ysB = await cpaceScalarMultVfy(yb, g);
    expect(x(ysA), a['Ya']);
    expect(x(ysB), b['Yb']);
    expect(x(await cpaceScalarMultVfy(ya, ysB)), v['b14_K']);
    expect(x(await cpaceScalarMultVfy(yb, ysA)), v['b14_K']);
  });

  test('B.1.5 initiator/responder transcript and ISK, B.1.6 parallel execution, B.1.7 sid output', () async {
    final Uint8List ya = h(a['Ya'] as String), yb = h(b['Yb'] as String), ada = h(a['adA'] as String), adb = h(b['adB'] as String);
    final Uint8List k = h(v['b14_K'] as String);
    final Uint8List tir = cpaceTranscriptIr(ya, ada, yb, adb);
    expect(x(tir), ir['transcriptIr']);
    expect(x(cat(<List<int>>[lvCat(<List<int>>['CPace255_ISK'.codeUnits, sid, k]), tir])), ir['iskInput']);
    expect(x(await cpaceIskFromTranscript(sid, k, tir)), ir['isk']);

    final Uint8List toc = cpaceTranscriptOc(ya, ada, yb, adb);
    expect(x(toc), oc['transcriptOc']);
    expect(x(cat(<List<int>>[lvCat(<List<int>>['CPace255_ISK'.codeUnits, sid, k]), toc])), oc['iskInput']);
    expect(x(await cpaceIskFromTranscript(sid, k, toc)), oc['isk']);

    expect(x(await cpaceSidOutput(tir)), (v['b17_sidOutput'] as Map<String, dynamic>)['ir']);
    expect(x(await cpaceSidOutput(toc)), (v['b17_sidOutput'] as Map<String, dynamic>)['oc']);
  });

  test('a whole PakeParty run on the draft inputs reaches the draft ISK on both sides', () async {
    final Uint8List ada = h(a['adA'] as String), adb = h(b['adB'] as String);
    // The Olive child is the draft's initiator A, the adult is the responder B.
    final PakeParty child = await PakeParty.start(
        isChild: true, password: prs, sid: sid, ci: ci, seed: h(a['ya'] as String), adInitiator: ada, adResponder: adb);
    final PakeParty adult = await PakeParty.start(
        isChild: false, password: prs, sid: sid, ci: ci, seed: h(b['yb'] as String), adInitiator: ada, adResponder: adb);
    expect(x(child.share), a['Ya']);
    expect(x(adult.share), b['Yb']);
    final PakeKey kc = await child.finish(adult.share), ka = await adult.finish(child.share);
    expect(x(kc.isk), ir['isk']);
    expect(x(ka.isk), ir['isk']);
    expect(await ka.checkTag('C', await kc.tag('C')), isTrue, reason: 'Olive confirmation layer sits on top');
  });

  group('B.1.10 low-order points and non-canonical encodings', () {
    final Uint8List s = h(low['s'] as String);
    final List<String> us = (low['u'] as List<dynamic>).cast<String>(), qs = (low['q'] as List<dynamic>).cast<String>();
    final List<int> mustAbort = (low['mustAbortIndices'] as List<dynamic>).cast<int>();
    test('the file holds all twelve points and seven abort cases', () {
      expect(us.length, 12);
      expect(qs.length, 12);
      expect(mustAbort, <int>[0, 1, 2, 3, 4, 5, 7]);
    });
    for (int i = 0; i < us.length; i++) {
      final String n = i.toRadixString(16);
      test('q$n = scalar_mult_vfy(s, u$n)', () async {
        expect(x(await cpaceScalarMultVfy(s, h(us[i]))), qs[i]);
      });
      if (mustAbort.contains(i)) {
        test('u$n aborts the exchange when it is the peer\'s message', () async {
          final PakeParty c = await PakeParty.start(isChild: true, password: prs, sid: sid, ci: ci);
          await expectLater(c.finish(h(us[i])), throwsA(isA<PakeException>()));
          final PakeParty ad = await PakeParty.start(isChild: false, password: prs, sid: sid, ci: ci);
          await expectLater(ad.finish(h(us[i])), throwsA(isA<PakeException>()));
        });
      } else {
        test('u$n is non-canonical or high-order but NOT a low-order point: no abort, the draft\'s result', () async {
          final PakeParty c = await PakeParty.start(isChild: true, password: prs, sid: sid, ci: ci, seed: s);
          final PakeKey k = await c.finish(h(us[i]));
          expect(k.isk.length, 64);
          // The DH output is the draft's q; the ISK must equal the one derived from that q and this transcript.
          final Uint8List want = await cpaceIskFromTranscript(
              sid, h(qs[i]), cpaceTranscriptIr(c.share, const <int>[], h(us[i]), const <int>[]));
          expect(x(k.isk), x(want));
        });
      }
    }
  });

  test('cpaceScalarMultVfy rejects a wrong length instead of mapping it to the neutral element', () async {
    final Uint8List ok = Uint8List(32)..[0] = 9;
    await expectLater(cpaceScalarMultVfy(Uint8List(31), ok), throwsA(isA<PakeException>()));
    await expectLater(cpaceScalarMultVfy(ok, Uint8List(31)), throwsA(isA<PakeException>()));
    await expectLater(cpaceScalarMultVfy(ok, Uint8List(33)), throwsA(isA<PakeException>()));
  });

  group('the map', () {
    test('blinding changes no output: elligator2 equals the unblinded map on the draft input and 300 random inputs', () {
      expect(x(elligator2(h(g11['generatorStringHash'] as String))), g11['g']);
      final Random r = Random(7);
      for (int n = 0; n < 300; n++) {
        final Uint8List u = Uint8List.fromList(List<int>.generate(32, (int _) => r.nextInt(256)));
        expect(x(elligator2(u)), x(elligator2Unblinded(u)));
      }
    });

    test('bit 255 of the input is ignored (decodeUCoordinate), as the draft requires', () {
      final Uint8List u = h(g11['generatorStringHash'] as String);
      final Uint8List flipped = Uint8List.fromList(u)..[31] ^= 0x80;
      expect(x(elligator2(flipped)), x(elligator2(u)));
    });

    test('the output is a u-coordinate below p and a point the ladder accepts', () async {
      final Random r = Random(11);
      final BigInt p = (BigInt.one << 255) - BigInt.from(19);
      for (int n = 0; n < 30; n++) {
        final Uint8List u = Uint8List.fromList(List<int>.generate(32, (int _) => r.nextInt(256)));
        final Uint8List gen = elligator2(u);
        BigInt big = BigInt.zero;
        for (int i = 31; i >= 0; i--) {
          big = (big << 8) | BigInt.from(gen[i]);
        }
        expect(big < p, isTrue);
        final Uint8List y = await cpaceScalarMultVfy(Uint8List.fromList(List<int>.filled(32, 5)), gen);
        expect(y.every((int e) => e == 0), isFalse);
      }
    });
  });

  group('compatibility with the pre-draft layout', () {
    test('the old generator string (OliveCPace255, unprefixed pad) gives a different generator: old and new builds cannot agree', () async {
      final Uint8List dsi = lv(utf8.encode('OliveCPace255')), p = lv(prs);
      final int zpad = (128 - 1 - p.length - dsi.length).clamp(0, 1 << 20);
      final Uint8List old = cat(<List<int>>[dsi, p, Uint8List(zpad), lv(ci), lv(sid)]);
      expect(old.length, 169, reason: 'the brief records this length for the old layout');
      final Uint8List oldG = elligator2((await sha512(old)).sublist(0, 32));
      expect(x(oldG), isNot(g11['g']));
    });
  });

  group('shares and encodings', () {
    test('a share of the wrong length is refused', () async {
      final PakeParty c = await PakeParty.start(isChild: true, password: prs, sid: sid, ci: ci);
      for (final int n in <int>[0, 1, 31, 33, 64]) {
        await expectLater(c.finish(Uint8List(n)), throwsA(isA<PakeException>()), reason: 'length $n');
      }
    });

    test('two sides with different associated data derive different keys (the transcript carries ADa and ADb)', () async {
      final PakeParty c = await PakeParty.start(
          isChild: true, password: prs, sid: sid, ci: ci, seed: h(a['ya'] as String), adInitiator: utf8.encode('x'));
      final PakeParty ad = await PakeParty.start(isChild: false, password: prs, sid: sid, ci: ci, seed: h(b['yb'] as String));
      expect(x((await c.finish(ad.share)).isk), isNot(x((await ad.finish(c.share)).isk)));
    });

    test('lv is LEB128: 127 bytes take one prefix byte, 128 take two', () {
      expect(lv(Uint8List(127))[0], 127);
      expect(lv(Uint8List(127)).length, 128);
      expect(lv(Uint8List(128)).sublist(0, 2), <int>[0x80, 0x01]);
      expect(lv(const <int>[]), <int>[0]);
    });
  });
}
