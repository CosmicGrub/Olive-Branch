// The signed update manifest: a signature made by Node over the same canonical bytes verifies here; every way of
// tampering with, forging, replaying in shape or malforming a manifest is refused with a stable code, and nothing
// that fails the signature is ever read into a model. MASTERFILE 7.24.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_manifest.dart';

import 'update_support.dart';

Future<UpdateRefusalCode?> refusalOf(Future<Object?> Function() f) async {
  try {
    await f();
    return null;
  } on UpdateRefusal catch (e) {
    return e.code;
  }
}

void main() {
  final Map<String, Object?> vectors =
      jsonDecode(File('test/vectors/update_manifest_vectors.json').readAsStringSync()) as Map<String, Object?>;
  final UpdateTrust vectorTrust = UpdateTrust.parse(vectors['publicKey']! as String);
  final Uint8List vectorDoc = Uint8List.fromList(utf8.encode(vectors['signed']! as String));

  group('golden vectors made by Node', () {
    test('the key id is the first 8 bytes of SHA-256 of the key, as Node computes it', () {
      expect(vectorTrust.keys.keys.single, vectors['keyId']);
    });

    test('the canonical form is character for character the one Node writes', () {
      for (final Object? c in vectors['canonicalCases']! as List<Object?>) {
        final Map<String, Object?> m = c! as Map<String, Object?>;
        expect(canonicalJson(parseStrictJson(m['json']! as String)), m['canonical']);
      }
    });

    test('the bytes that are signed are the recorded ones', () {
      final Map<String, Object?> doc = parseStrictJson(vectors['signed']! as String)! as Map<String, Object?>;
      expect(<String>[for (final int b in signingBytes(doc)) b.toRadixString(16).padLeft(2, '0')].join(), vectors['signingBytesHex']);
    });

    test('a manifest signed by Node verifies and reads into the model', () async {
      final VerifiedManifest v = await verifyManifestDocument(vectorDoc, vectorTrust);
      expect(v.manifest.versionName, '0.52.0');
      expect(v.manifest.versionCode, 5200);
      expect(v.manifest.minSupportedVersionCode, 5100);
      expect(v.manifest.channel, 'stable');
      expect(v.manifest.apk.chunkCount, 4);
      expect(v.manifest.apk.urls, hasLength(2));
      expect(v.manifest.apk.urls.first.host, 'updates.example.org');
      expect(v.manifest.headline, 'Calmer messages, and a fix for slow starts');
      expect(v.manifest.notes, hasLength(2));
      expect(v.document, vectorDoc);
    });

    test('one changed character in the signed document breaks the signature', () async {
      final String t = vectors['signed']! as String;
      final String tampered = t.replaceFirst('"versionCode":5200', '"versionCode":5201');
      expect(tampered, isNot(t));
      expect(await refusalOf(() => verifyManifestDocument(Uint8List.fromList(utf8.encode(tampered)), vectorTrust)),
          UpdateRefusalCode.badSignature);
    });

    test('a different key does not verify it', () async {
      final TestSigner other = await TestSigner.create(9);
      expect(await refusalOf(() => verifyManifestDocument(vectorDoc, other.trust)), UpdateRefusalCode.unknownKey);
    });
  });

  group('refused before it is believed', () {
    late TestSigner s;
    late Uint8List apk;
    setUp(() async {
      s = await TestSigner.create();
      apk = fakeApk(150000);
    });

    Future<VerifiedManifest> ok([Map<String, Object?> Function(Map<String, Object?>)? tweak]) async {
      Map<String, Object?> d = await draftFor(apk);
      if (tweak != null) d = tweak(d);
      return verifyManifestDocument(encodeDoc(await s.sign(d)), s.trust);
    }

    Future<UpdateRefusalCode?> refuse(Map<String, Object?> Function(Map<String, Object?>) tweak) async {
      Map<String, Object?> d = await draftFor(apk);
      d = tweak(d);
      final Uint8List doc = encodeDoc(await s.sign(d));
      return refusalOf(() => verifyManifestDocument(doc, s.trust));
    }

    test('a well-formed signed manifest is accepted', () async {
      final VerifiedManifest v = await ok();
      expect(v.manifest.apk.size, 150000);
      expect(v.manifest.apk.chunkLength(2), 150000 - 2 * 65536);
      expect(v.manifest.validUntil, isNotNull);
      expect(v.manifest.apk.signerSha256, isNull);
    });

    test('a build with no key refuses everything (the feature fails closed)', () async {
      final Uint8List doc = encodeDoc(await s.sign(await draftFor(apk)));
      expect(await refusalOf(() => verifyManifestDocument(doc, UpdateTrust(const <List<int>>[]))), UpdateRefusalCode.noKeyConfigured);
      expect(UpdateTrust.parse('not-base64!!, , AAAA').isEmpty, isTrue);
    });

    test('an unsigned document, an unknown algorithm and a missing key id are refused', () async {
      final Map<String, Object?> d = await draftFor(apk);
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(d), s.trust)), UpdateRefusalCode.badShape);
      final Map<String, Object?> none = await s.sign(d);
      (none['signature']! as Map<String, Object?>)['alg'] = 'none';
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(none), s.trust)), UpdateRefusalCode.badSignature);
      final Map<String, Object?> unknown = await s.sign(d, keyId: '0123456789abcdef');
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(unknown), s.trust)), UpdateRefusalCode.unknownKey);
    });

    test('a signature over something else (another domain tag) is not a manifest signature', () async {
      final Map<String, Object?> d = await draftFor(apk);
      final Map<String, Object?> forged = await s.sign(d, domain: 'olive-other-thing\n');
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(forged), s.trust)), UpdateRefusalCode.badSignature);
    });

    test('a signature that is not canonical base64, or the wrong length, is refused', () async {
      final Map<String, Object?> d = await s.sign(await draftFor(apk));
      final Map<String, Object?> sig = d['signature']! as Map<String, Object?>;
      sig['value'] = '${sig['value']}A';
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(d), s.trust)), UpdateRefusalCode.badSignature);
      sig['value'] = base64.encode(List<int>.filled(63, 1));
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(d), s.trust)), UpdateRefusalCode.badSignature);
    });

    test('a tampered member under a valid-looking signature is refused (size, address, notes, floor)', () async {
      final Map<String, Object?> good = await s.sign(await draftFor(apk));
      for (final void Function(Map<String, Object?>) change in <void Function(Map<String, Object?>)>[
        (Map<String, Object?> m) => m['versionCode'] = 5300,
        (Map<String, Object?> m) => m['minSupportedVersionCode'] = 1,
        (Map<String, Object?> m) => (m['apk']! as Map<String, Object?>)['urls'] = <String>['https://evil.example.org/o.apk'],
        (Map<String, Object?> m) => (m['apk']! as Map<String, Object?>)['size'] = 1,
        (Map<String, Object?> m) => (m['notes']! as Map<String, Object?>)['headline'] = 'Free money',
        (Map<String, Object?> m) => m['channel'] = 'beta',
      ]) {
        final Map<String, Object?> bad = jsonDecode(jsonEncode(good)) as Map<String, Object?>;
        change(bad);
        expect(await refusalOf(() => verifyManifestDocument(encodeDoc(bad), s.trust)), UpdateRefusalCode.badSignature);
      }
    });

    test('too large, not UTF-8, not JSON, not an object', () async {
      expect(await refusalOf(() => verifyManifestDocument(Uint8List(kMaxManifestBytes + 1), s.trust)), UpdateRefusalCode.tooLarge);
      expect(await refusalOf(() => verifyManifestDocument(Uint8List.fromList(<int>[0xff, 0xfe, 0x00]), s.trust)), UpdateRefusalCode.notJson);
      expect(await refusalOf(() => verifyManifestDocument(Uint8List.fromList(utf8.encode('nope')), s.trust)), UpdateRefusalCode.notJson);
      expect(await refusalOf(() => verifyManifestDocument(Uint8List.fromList(utf8.encode('[1,2]')), s.trust)), UpdateRefusalCode.notJson);
    });

    test('shape: an unknown member, a floor above the version, a chunk list that does not match the size', () async {
      expect(await refuse((Map<String, Object?> d) => d..['surprise'] = 1), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['minSupportedVersionCode'] = 6000), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['schema'] = 2), UpdateRefusalCode.badShape);
      expect(
          await refuse((Map<String, Object?> d) {
            ((d['apk']! as Map<String, Object?>)['chunkSha256']! as List<Object?>).removeLast();
            return d;
          }),
          UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['validUntil'] = '2026-11-01T10:00:00Z'), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['publishedAt'] = '2026-02-31T10:00:00Z'), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['versionName'] = '0.52'), UpdateRefusalCode.badShape);
    });

    test('version policy: the versionCode is derived from the name, never chosen', () async {
      expect(versionCodeOfName('0.52.0'), 5200);
      expect(versionCodeOfName('1.2.3'), 10203);
      expect(await refuse((Map<String, Object?> d) => d..['versionCode'] = 9999), UpdateRefusalCode.versionPolicy);
    });

    test('a huge declared size (a zip-bomb style claim) is refused by the cap before anything is downloaded', () async {
      expect(
          await refuse((Map<String, Object?> d) {
            (d['apk']! as Map<String, Object?>)['size'] = kMaxApkBytes + 1;
            return d;
          }),
          UpdateRefusalCode.sizeTooLarge);
      expect(
          await refuse((Map<String, Object?> d) {
            (d['apk']! as Map<String, Object?>)['chunkSize'] = 1024;
            return d;
          }),
          UpdateRefusalCode.badShape);
    });

    test('addresses: cleartext, credentials, a query, a fragment and an unknown scheme are refused', () async {
      for (final String bad in <String>[
        'http://updates.example.org/a.apk',
        'https://user:pw@updates.example.org/a.apk',
        'https://updates.example.org/a.apk?token=1',
        'https://updates.example.org/a.apk#x',
        'ftp://updates.example.org/a.apk',
        'https://updates.example.org:8443/a.apk',
        'https://updates.example.org/',
      ]) {
        expect(
            await refuse((Map<String, Object?> d) {
              (d['apk']! as Map<String, Object?>)['urls'] = <String>[bad];
              return d;
            }),
            UpdateRefusalCode.badUrl,
            reason: bad);
      }
      // The developer loopback define is the one exception, and only to a literal loopback address.
      Future<VerifiedManifest> loop(String u, bool allow) async {
        final Map<String, Object?> d = await draftFor(apk);
        (d['apk']! as Map<String, Object?>)['urls'] = <String>[u];
        return verifyManifestDocument(encodeDoc(await s.sign(d)), s.trust, allowLoopbackHttp: allow);
      }

      expect((await loop('http://127.0.0.1:8123/a.apk', true)).manifest.apk.urls.single.host, '127.0.0.1');
      expect(await refusalOf(() => loop('http://127.0.0.1:8123/a.apk', false)), UpdateRefusalCode.badUrl);
      expect(await refusalOf(() => loop('http://localhost:8123/a.apk', true)), UpdateRefusalCode.badUrl);
      expect(await refusalOf(() => loop('http://203.0.113.9/a.apk', true)), UpdateRefusalCode.badUrl);
    });

    test('notes are plain text: markup and control characters are refused', () async {
      expect(await refuse((Map<String, Object?> d) => d..['notes'] = <String, Object?>{'language': 'en', 'headline': '<b>Hi</b>', 'items': <String>[]}),
          UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['notes'] = <String, Object?>{'language': 'en', 'headline': 'Hi', 'items': <String>['a\u0007b']}),
          UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['notes'] = <String, Object?>{'language': 'en', 'headline': 'Hi', 'items': <String>[' padded ']}),
          UpdateRefusalCode.badShape);
    });
  });

  group('strict JSON (what Node refuses, Dart refuses)', () {
    test('duplicate keys, floats, a byte-order mark, trailing data, deep nesting, a lone surrogate', () {
      for (final String bad in <String>[
        '{"a":1,"a":2}',
        '{"a":1.5}',
        '{"a":1e3}',
        '\ufeff{"a":1}',
        '{"a":1} x',
        '{"a":{"a":{"a":{"a":{"a":{"a":{"a":{"a":{"a":{"a":1}}}}}}}}}}',
        '{"a":"\\ud800"}',
        '{"a":99999999999999999999}',
        '{"a":"line\nbreak"}',
        '{"a":}',
        '',
      ]) {
        expect(() => parseStrictJson(bad), throwsA(isA<UpdateRefusal>()), reason: bad);
      }
      expect(parseStrictJson('{"a":[1,-2,true,null,"x\\u00e9"]}'), <String, Object?>{
        'a': <Object?>[1, -2, true, null, 'xé']
      });
    });

    test('a manifest with a duplicated key is refused even though a lenient parser would keep the last', () async {
      final TestSigner s = await TestSigner.create();
      final String signed = jsonEncode(await s.sign(await draftFor(fakeApk(70000))));
      final String dup = signed.replaceFirst('"schema":1,', '"schema":1,"schema":1,');
      expect(await refusalOf(() => verifyManifestDocument(Uint8List.fromList(utf8.encode(dup)), s.trust)), UpdateRefusalCode.notJson);
    });
  });
}
