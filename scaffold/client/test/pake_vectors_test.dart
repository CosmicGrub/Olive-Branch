// OLIVE BRANCH — the PAKE against the golden vectors the independent Node implementation produced
// (tools/gen-pake-vectors.mjs), plus the properties that matter. Verified by CI, headless.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart';

Uint8List h(String s) =>
    Uint8List.fromList(<int>[for (int i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String x(List<int> b) => b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final Map<String, dynamic> file =
      jsonDecode(File('test/vectors/pake_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  for (final Map<String, dynamic> c in (file['cases'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    test('vector: ${c['label']}', () async {
      final Uint8List sid = h(c['sid'] as String), ci = h(c['ci'] as String);
      expect(x(await cpaceGenerator(utf8.encode(c['prsC'] as String), sid, ci)), c['gC']);
      final PakeParty child = await PakeParty.start(
          isChild: true, password: utf8.encode(c['prsC'] as String), sid: sid, ci: ci, seed: h(c['yc'] as String));
      final PakeParty adult = await PakeParty.start(
          isChild: false, password: utf8.encode(c['prsA'] as String), sid: sid, ci: ci, seed: h(c['ya'] as String));
      expect(x(child.share), c['Yc']);
      expect(x(adult.share), c['Ya']);
      final PakeKey kc = await child.finish(adult.share), ka = await adult.finish(child.share);
      expect(x(kc.isk), c['iskC']);
      expect(x(ka.isk), c['iskA']);
      expect(x(await kc.tag('C')), c['tagC']);
      expect(x(await ka.tag('A')), c['tagA']);
      expect(x(await kc.sas()), c['sas']);
      expect(x(kc.isk) == x(ka.isk), c['agree']);
    });
  }

  test('property: random run, same password agrees and confirms both ways', () async {
    final Uint8List sid = Uint8List.fromList(List<int>.generate(16, (int i) => i)), ci = Uint8List.fromList(utf8.encode('ci'));
    final PakeParty c = await PakeParty.start(isChild: true, password: utf8.encode('1234'), sid: sid, ci: ci);
    final PakeParty a = await PakeParty.start(isChild: false, password: utf8.encode('1234'), sid: sid, ci: ci);
    final PakeKey kc = await c.finish(a.share), ka = await a.finish(c.share);
    expect(await ka.checkTag('C', await kc.tag('C')), isTrue);
    expect(await kc.checkTag('A', await ka.tag('A')), isTrue);
  });

  test('property: one wrong digit, a different session id or a different channel never confirms', () async {
    final Uint8List sid = Uint8List.fromList(List<int>.generate(16, (int i) => i)), ci = Uint8List.fromList(utf8.encode('ci'));
    final Uint8List sid2 = Uint8List.fromList(List<int>.generate(16, (int i) => i + 1));
    Future<bool> confirms(String pa, List<int> sidA, List<int> ciA) async {
      final PakeParty c = await PakeParty.start(isChild: true, password: utf8.encode('1234'), sid: sid, ci: ci);
      final PakeParty a = await PakeParty.start(isChild: false, password: utf8.encode(pa), sid: sidA, ci: ciA);
      final PakeKey kc = await c.finish(a.share), ka = await a.finish(c.share);
      return ka.checkTag('C', await kc.tag('C'));
    }

    expect(await confirms('1234', sid, ci), isTrue);
    expect(await confirms('1235', sid, ci), isFalse);
    expect(await confirms('1234', sid2, ci), isFalse);
    expect(await confirms('1234', sid, utf8.encode('other family')), isFalse);
  });

  test('a malformed or low-order share is refused, never accepted', () async {
    final PakeParty c = await PakeParty.start(isChild: true, password: utf8.encode('1234'), sid: <int>[1], ci: <int>[2]);
    await expectLater(c.finish(<int>[1, 2, 3]), throwsA(isA<PakeException>()));
    await expectLater(c.finish(Uint8List(32)), throwsA(isA<PakeException>()));
  });
}
