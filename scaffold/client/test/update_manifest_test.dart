// The signed update manifest: every labelled document in tools/update/test-vectors.json (made by the release tools, in
// Node) is accepted or refused here with the SAME code; the canonical form is character for character the one Node writes;
// and every way of tampering with, forging, replaying in shape or malforming a manifest is refused with a stable code
// before anything of it is read into a model. MASTERFILE 7.24.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_policy.dart';

import 'update_support.dart';

Future<UpdateRefusalCode?> refusalOf(Future<Object?> Function() f) async {
  try {
    await f();
    return null;
  } on UpdateRefusal catch (e) {
    return e.code;
  }
}

String _hex(List<int> b) => <String>[for (final int x in b) x.toRadixString(16).padLeft(2, '0')].join();

void main() {
  // The shared truth, in the release lane's folder. `flutter test` runs from scaffold/client.
  final Map<String, Object?> vectors =
      jsonDecode(File('../tools/update/test-vectors.json').readAsStringSync()) as Map<String, Object?>;
  final UpdateTrust vectorTrust = UpdateTrust.parse(vectors['trust']! as String);

  group('the vectors made by the release tools (Node)', () {
    test('the domain tag is the one the app signs with', () {
      expect(vectors['signDomain'], kUpdateSignDomain);
    });

    test('the canonical form and the signed bytes are character for character the ones Node writes', () {
      final List<Object?> cases = vectors['canonical']! as List<Object?>;
      expect(cases, isNotEmpty);
      for (final Object? c in cases) {
        final Map<String, Object?> m = c! as Map<String, Object?>;
        final Object? parsed = parseStrictJson(m['json']! as String);
        expect(canonicalJson(parsed), m['canonical'], reason: '${m['name']}');
        expect(_hex(utf8.encode('$kUpdateSignDomain${canonicalJson(parsed)}')), m['signingBytesHex'], reason: '${m['name']}');
      }
    });

    test('every labelled document is accepted or refused exactly as the release tools say', () async {
      final List<Object?> docs = vectors['documents']! as List<Object?>;
      expect(docs.length, greaterThanOrEqualTo(30));
      int accepted = 0, refused = 0;
      for (final Object? o in docs) {
        final Map<String, Object?> d = o! as Map<String, Object?>;
        final Map<String, Object?> expect_ = d['expect']! as Map<String, Object?>;
        final Map<String, Object?> ctx = d['ctx']! as Map<String, Object?>;
        final Uint8List body = Uint8List.fromList(utf8.encode(d['text']! as String));
        UpdateRefusalCode? got;
        UpdateVerdict? verdict;
        try {
          final VerifiedManifest v = await verifyManifestDocument(body, vectorTrust);
          verdict = decideUpdate(
              v.manifest,
              UpdateContext(
                channel: ctx['channel']! as String,
                installedVersionCode: ctx['installedVersionCode']! as int,
                highestSeenSequence: ctx['highestSeenSequence'] as int?,
                now: DateTime.parse(ctx['nowIso']! as String),
                deviceAbis: const <String>['arm64-v8a', 'universal'],
              ));
        } on UpdateRefusal catch (e) {
          got = e.code;
        }
        final String why = '${d['name']}';
        if (expect_['ok'] == true) {
          accepted++;
          expect(got, isNull, reason: why);
          expect(verdict!.status == UpdateStatus.updateAvailable ? 'update' : 'up-to-date', expect_['status'], reason: why);
          expect(verdict.belowMinimum, expect_['belowMinimum'] == true, reason: why);
        } else {
          refused++;
          expect(got?.name, expect_['code'], reason: why);
        }
      }
      expect(accepted, greaterThanOrEqualTo(5));
      expect(refused, greaterThanOrEqualTo(25));
    });

    test('the stranger key in the vectors is not in the trust the app holds', () {
      final UpdateTrust stranger = UpdateTrust.parse(vectors['strangerTrust']! as String);
      expect(stranger.keys.keys, isNot(contains(vectorTrust.keys.keys.single)));
    });
  });

  group('refused before it is believed', () {
    late TestSigner s;
    late Uint8List apk;
    setUp(() async {
      s = await TestSigner.create();
      apk = fakeApk(150000);
    });

    Future<VerifiedManifest> ok([Map<String, Object?> Function(Map<String, Object?>)? tweak, bool loopback = false]) async {
      Map<String, Object?> d = await draftFor(apk);
      if (tweak != null) d = tweak(d);
      return verifyManifestDocument(encodeDoc(await s.sign(d)), s.trust, allowLoopbackHttp: loopback);
    }

    Future<UpdateRefusalCode?> refuse(Map<String, Object?> Function(Map<String, Object?>) tweak, {bool loopback = false}) async {
      Map<String, Object?> d = await draftFor(apk);
      d = tweak(d);
      final Uint8List doc = encodeDoc(await s.sign(d));
      return refusalOf(() => verifyManifestDocument(doc, s.trust, allowLoopbackHttp: loopback));
    }

    test('a well-formed signed manifest is accepted and read into the model', () async {
      final VerifiedManifest v = await ok();
      final ApkEntry a = v.manifest.apks.single;
      expect(a.size, 150000);
      expect(a.chunkCount, 3);
      expect(a.chunkLength(2), 150000 - 2 * 65536);
      expect(a.signerSha256, certHash('owner'));
      expect(a.urls.map((Uri u) => u.host).toList(), <String>['updates.example.org', 'mirror.example.net']);
      expect(v.manifest.versionCode, 5200);
      expect(v.manifest.keyId, s.kid);
      expect(v.manifest.expiresAt.isAfter(v.manifest.issuedAt), isTrue);
    });

    test('a build with no key refuses everything (the feature fails closed)', () async {
      final Uint8List doc = encodeDoc(await s.sign(await draftFor(apk)));
      expect(await refusalOf(() => verifyManifestDocument(doc, UpdateTrust(const <String, List<int>>{}))), UpdateRefusalCode.noKeyConfigured);
      expect(UpdateTrust.parse('not-base64!!, , AAAA, kid:AAAA').isEmpty, isTrue);
      expect(UpdateTrust.parse('').isEmpty, isTrue);
    });

    test('a key that is not exactly 32 bytes is never trusted', () {
      expect(UpdateTrust(<String, List<int>>{'short': List<int>.filled(31, 1)}).isEmpty, isTrue);
      expect(UpdateTrust(<String, List<int>>{'long': List<int>.filled(33, 1)}).isEmpty, isTrue);
    });

    test('an unsigned document, an unknown algorithm and an unknown key id are refused', () async {
      final Map<String, Object?> d = await draftFor(apk);
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(d), s.trust)), UpdateRefusalCode.badShape);
      final Map<String, Object?> none = await s.sign(d);
      (none['signature']! as Map<String, Object?>)['alg'] = 'none';
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(none), s.trust)), UpdateRefusalCode.badSignature);
      final Map<String, Object?> unknown = await s.sign(d, kid: '0123456789abcdef');
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(unknown), s.trust)), UpdateRefusalCode.unknownKey);
    });

    test('a signature over something else (another domain tag) is not a manifest signature', () async {
      final Map<String, Object?> d = await draftFor(apk);
      final Map<String, Object?> forged = await s.sign(d, domain: 'olive-other-thing\n');
      expect(await refusalOf(() => verifyManifestDocument(encodeDoc(forged), s.trust)), UpdateRefusalCode.badSignature);
    });

    test('a signature that is not canonical base64url, or the wrong length, is refused', () async {
      final Map<String, Object?> d = await s.sign(await draftFor(apk));
      final Map<String, Object?> sig = d['signature']! as Map<String, Object?>;
      final String good = sig['sig']! as String;
      for (final String bad in <String>[
        '${good}A', // one character too long
        good.substring(0, good.length - 2), // too short
        base64.encode(List<int>.filled(63, 1)),
        good.replaceFirst(good[3], '+'), // outside the url-safe alphabet
        '',
      ]) {
        sig['sig'] = bad;
        expect(await refusalOf(() => verifyManifestDocument(encodeDoc(d), s.trust)), UpdateRefusalCode.badSignature, reason: bad);
      }
    });

    test('a tampered member under a valid signature is refused (version, floor, address, size, notes, channel)', () async {
      final Map<String, Object?> good = await s.sign(await draftFor(apk));
      Map<String, Object?> payload(Map<String, Object?> doc) => doc['manifest']! as Map<String, Object?>;
      Map<String, Object?> file(Map<String, Object?> doc) => (payload(doc)['apks']! as List<Object?>).first! as Map<String, Object?>;
      for (final void Function(Map<String, Object?>) change in <void Function(Map<String, Object?>)>[
        (Map<String, Object?> m) => payload(m)['versionCode'] = 5300,
        (Map<String, Object?> m) => payload(m)['minSupportedVersionCode'] = 1,
        (Map<String, Object?> m) => file(m)['urls'] = <String>['https://evil.example.org/o.apk'],
        (Map<String, Object?> m) => file(m)['size'] = 1,
        (Map<String, Object?> m) => file(m)['sha256'] = 'a' * 64,
        (Map<String, Object?> m) => file(m)['signerSha256'] = 'b' * 64,
        (Map<String, Object?> m) => payload(m)['headline'] = 'Free money',
        (Map<String, Object?> m) => payload(m)['sequence'] = 9007199254740991,
        (Map<String, Object?> m) => payload(m)['channel'] = 'beta',
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

    test('the size cap is checked before the key (an oversized body is never parsed, whatever the build holds)', () async {
      expect(await refusalOf(() => verifyManifestDocument(Uint8List(kMaxManifestBytes + 1), UpdateTrust(const <String, List<int>>{}))),
          UpdateRefusalCode.tooLarge);
    });

    test('shape: a floor above the version, a wrong schema, a chunk list that does not match the size, a bad time or name', () async {
      expect(await refuse((Map<String, Object?> d) => d..['minSupportedVersionCode'] = 6000), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['schema'] = 2), UpdateRefusalCode.badShape);
      expect(
          await refuse((Map<String, Object?> d) {
            (apk0(d)['chunks']! as List<Object?>).removeLast();
            return d;
          }),
          UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['expiresAt'] = '2026-11-01T10:00:00Z'), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['publishedAt'] = '2026-02-31T10:00:00Z'), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['versionName'] = '0.52'), UpdateRefusalCode.badShape);
    });

    test('a member this version does not know is tolerated (a later schema may add one); the publisher tool is the strict one', () async {
      final VerifiedManifest v = await ok((Map<String, Object?> d) => d..['surprise'] = 1);
      expect(v.manifest.versionCode, 5200);
    });

    test('a manifest for another app is refused as wrongApp, after the signature', () async {
      expect(await refuse((Map<String, Object?> d) => d..['app'] = 'com.example.other'), UpdateRefusalCode.wrongApp);
    });

    test('versionCode is read as signed; the derivation rule is available to the publisher check', () {
      expect(versionCodeOfName('0.52.0'), 5200);
      expect(versionCodeOfName('1.2.3'), 10203);
      expect(() => versionCodeOfName('x'), throwsA(isA<UpdateRefusal>()));
    });

    test('a huge declared size (a zip-bomb style claim) is refused by the cap before anything is downloaded', () async {
      expect(
          await refuse((Map<String, Object?> d) {
            apk0(d)['size'] = kMaxApkBytes + 1;
            return d;
          }),
          UpdateRefusalCode.sizeTooLarge);
      expect(
          await refuse((Map<String, Object?> d) {
            apk0(d)['size'] = 0;
            return d;
          }),
          UpdateRefusalCode.badShape);
      expect(
          await refuse((Map<String, Object?> d) {
            apk0(d)['chunkSize'] = 1024; // many tiny chunks: a memory and time attack on the checker
            return d;
          }),
          UpdateRefusalCode.badShape);
      expect(
          await refuse((Map<String, Object?> d) {
            apk0(d)['urls'] = <String>[for (int i = 0; i < 5; i++) 'https://m$i.example.org/o.apk'];
            return d;
          }),
          UpdateRefusalCode.badShape);
    });

    test('addresses: cleartext, credentials, a fragment, an unknown scheme, no file and repeats are refused', () async {
      for (final String bad in <String>[
        'http://updates.example.org/a.apk',
        'https://user:pw@updates.example.org/a.apk',
        'https://updates.example.org/a.apk#x',
        'ftp://updates.example.org/a.apk',
        'file:///sdcard/a.apk',
        'javascript:alert(1)',
        'https://updates.example.org/',
        'https://updates.example.org',
        'https://updates.example.org/a b.apk',
        'https://updates.example.org/${'a' * 2100}',
      ]) {
        expect(
            await refuse((Map<String, Object?> d) {
              apk0(d)['urls'] = <String>[bad];
              return d;
            }),
            UpdateRefusalCode.badUrl,
            reason: bad);
      }
      expect(
          await refuse((Map<String, Object?> d) {
            apk0(d)['urls'] = <String>[kPrimary, kPrimary];
            return d;
          }),
          UpdateRefusalCode.badUrl);
    });

    test('the developer loopback define is the one cleartext exception, and only to a literal loopback address', () async {
      Future<VerifiedManifest> loop(String u, bool allow) => ok((Map<String, Object?> d) {
            apk0(d)['urls'] = <String>[u];
            return d;
          }, allow);
      expect((await loop('http://127.0.0.1:8123/a.apk', true)).manifest.apks.single.urls.single.host, '127.0.0.1');
      expect((await loop('http://[::1]:8123/a.apk', true)).manifest.apks.single.urls.single.host, '::1');
      expect(await refusalOf(() => loop('http://127.0.0.1:8123/a.apk', false)), UpdateRefusalCode.badUrl);
      expect(await refusalOf(() => loop('http://localhost:8123/a.apk', true)), UpdateRefusalCode.badUrl);
      expect(await refusalOf(() => loop('http://203.0.113.9/a.apk', true)), UpdateRefusalCode.badUrl);
      expect(await refusalOf(() => loop('http://192.168.1.5/a.apk', true)), UpdateRefusalCode.badUrl);
    });

    test('notes are plain text: markup, control and invisible characters, padding and over-long lines are refused', () async {
      for (final Object? n in <Object?>[
        <String>['<b>Hi</b>'],
        <String>['a\u0007b'],
        <String>[' padded '],
        <String>['bidi \u202e override'],
        <String>['zero\u200bwidth'],
        <String>['back`tick'],
        <String>[''],
        <String>['x' * 301],
        <String>[for (int i = 0; i < 13; i++) 'line $i'],
        <Object?>[7],
        'not a list',
      ]) {
        expect(await refuse((Map<String, Object?> d) => d..['notes'] = n), UpdateRefusalCode.badShape, reason: '$n');
      }
      expect(await refuse((Map<String, Object?> d) => d..['headline'] = '<script>'), UpdateRefusalCode.badShape);
      expect(await refuse((Map<String, Object?> d) => d..['headline'] = 'x' * 101), UpdateRefusalCode.badShape);
      expect((await ok((Map<String, Object?> d) => d..['headline'] = '')).manifest.headline, '');
    });

    test('two files for one chip are refused; the right file is chosen for the phone', () async {
      expect(
          await refuse((Map<String, Object?> d) {
            final Map<String, Object?> a = apk0(d);
            d['apks'] = <Object?>[a, Map<String, Object?>.of(a)];
            return d;
          }),
          UpdateRefusalCode.badShape);
      final UpdateManifest m = (await ok()).manifest;
      expect(m.apkFor(const <String>['arm64-v8a'])?.abi, 'arm64-v8a');
      expect(m.apkFor(const <String>['x86_64']), isNull);
      expect(m.apkFor(const <String>[]), isNull);
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
      expect(dup, isNot(signed));
      expect(await refusalOf(() => verifyManifestDocument(Uint8List.fromList(utf8.encode(dup)), s.trust)), UpdateRefusalCode.notJson);
    });

    test('the canonical form refuses what has no exact form (a float, an integer beyond 2^53)', () {
      expect(() => canonicalJson(<String, Object?>{'a': 1.5}), throwsFormatException);
      expect(() => canonicalJson(<String, Object?>{'a': 9007199254740993}), throwsFormatException);
      expect(canonicalJson(<String, Object?>{'b': '\n', 'a': '"\\'}), r'{"a":"\"\\","b":"\u000a"}');
    });
  });
}
