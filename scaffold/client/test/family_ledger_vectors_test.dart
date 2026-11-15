// OLIVE BRANCH — the Dart ledger against the golden vectors the independent Node implementation produced
// (tools/family_ledger.mjs, tools/gen-family-ledger-vectors.mjs). Verified by CI, headless. Both languages must agree
// byte for byte on the canonical encoding, the signature and the entry hash.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';

/// JSON in the vector file marks a byte string as `{"$b": "hex"}`.
Object? fromJsonValue(Object? j) {
  if (j is Map) {
    if (j.length == 1 && j.containsKey(r'$b')) return fromHex(j[r'$b'] as String);
    return <String, Object?>{for (final MapEntry<dynamic, dynamic> e in j.entries) e.key as String: fromJsonValue(e.value)};
  }
  if (j is List) return <Object?>[for (final Object? x in j) fromJsonValue(x)];
  return j;
}

void main() {
  final Map<String, dynamic> file =
      jsonDecode(File('test/vectors/family_ledger_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final List<Map<String, dynamic>> cases = (file['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  Future<DeviceKey> keyOf(String seedHex) =>
      DeviceKey.loadOrCreate(MemoryDeviceKeyRepository(), seedForTest: fromHex(seedHex));

  for (final Map<String, dynamic> c in cases) {
    final String label = c['label'] as String;
    switch (c['kind']) {
      case 'cert':
        test('vector: $label', () async {
          final DeviceKey k = await keyOf(c['seed'] as String);
          final Uint8List agree = fromHex(c['agree'] as String);
          expect(hexOf(await certifyAgreementKey(k, agree)), c['expectSig']);
          expect(await verifyAgreementCert(DeviceRecord(key: k.publicKey, agree: agree, cert: fromHex(c['expectSig'] as String))), isTrue);
        });
        break;
      case 'entry':
        test('vector: $label', () async {
          final DeviceKey k = await keyOf(c['seed'] as String);
          final Map<String, Object?> body = fromJsonValue(c['body']) as Map<String, Object?>;
          final LedgerEntry e = await LedgerEntry.sign(k,
              type: c['type'] as String,
              prev: <Uint8List>[for (final Object? h in c['prev'] as List<dynamic>) fromHex(h as String)],
              body: body,
              issuedAtMs: c['issuedAt'] as int);
          expect(hexOf(e.bytes), c['bytes'], reason: 'canonical bytes');
          expect(hexOf(e.signature), c['sig'], reason: 'Ed25519 is deterministic');
          expect(e.hashHex, c['hash']);
          final LedgerEntry? back = await LedgerEntry.parse(fromHex(c['bytes'] as String), fromHex(c['sig'] as String));
          expect(back!.hashHex, c['hash']);
          expect(await back.verifySignature(), isTrue);
        });
        break;
      case 'vote':
        test('vector: $label', () async {
          final DeviceKey k = await keyOf(c['seed'] as String);
          final LedgerVote v = await LedgerVote.sign(k, target: fromHex(c['target'] as String), answer: c['answer'] as String, atMs: c['at'] as int);
          expect(hexOf(LedgerVote.signedBytes(v.target, v.answer, v.voter, v.atMs)), c['bytes']);
          expect(hexOf(v.signature), c['sig']);
          expect(await v.verifySignature(), isTrue);
        });
        break;
    }
  }

  test('the vectors cover genesis, a legacy device, a proposal, a policy change and a key rotation, plus votes', () {
    final Set<Object?> types = <Object?>{for (final Map<String, dynamic> c in cases) if (c['kind'] == 'entry') c['type']};
    expect(types, <Object?>{'genesis', 'device.add', 'member.add', 'policy.set', 'key.rotate'});
    expect(cases.where((Map<String, dynamic> c) => c['kind'] == 'vote').length, 2);
  });
}
