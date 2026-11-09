// Server-snoop hardening, client half (spec 4.1): the scheme/host policy, the
// SPKI pin extraction against an openssl-computed vector, pin-set rules, the
// refusing client, and a REAL TLS handshake against a throwaway local server
// proving a pin mismatch fails before a request byte is written.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:olive_client/server_transport_policy.dart';

// A public, self-signed certificate (CN=olive-test-vector) and its SPKI pin as
// computed by: openssl x509 -pubkey -noout | openssl pkey -pubin -outform der
//   | openssl dgst -sha256 -binary | base64.  No private key is committed.
const _vectorDerB64 = 'MIIDGzCCAgOgAwIBAgIUQy9WrfQZCPiDrj9/3QtjC4YROwwwDQYJKoZIhvcNAQELBQAwHDEaMBgGA1UEAwwRb2xpdmUtdGVzdC12ZWN0b3IwIBcNMjYxMTA5MDI0MjUxWhgPMjEyNjEwMTYwMjQyNTFaMBwxGjAYBgNVBAMMEW9saXZlLXRlc3QtdmVjdG9yMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp+bn9LY/ctgbqc0tO1G5ZmeIAdFzP/uMKjy9ltVR5WyW9zz9v5OUzue+tRsgoHwecp3ifX2TkIk657zxM9ucAKxgb/fyOrFhKFTJ84J1oaUWKUamlQXVlDNpDGzl9K3uQQ/qVlRvvt0Qfh5kmtuf/3Evj0W8ByojrPHtrfVhSimYm84ATLVECweHl84GXwpa7LmhKotHhzFaHtm3gZ/zSE0k/LlfmLQXrpTsrCAO3nnSP3+I4/PyFOmBf1vXHXHpA7UDr2w7XCT7njCFOaCbTmIeQ3K/jWcVIXSz1wx0F6/dhkUYcfuBv2Md6d90NZc36Zr2R3nimoIlwLKZT7Qm6wIDAQABo1MwUTAdBgNVHQ4EFgQULb3EhuRFEdhLZzV0As2BQ5juswcwHwYDVR0jBBgwFoAULb3EhuRFEdhLZzV0As2BQ5juswcwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAo8SL4C9MaAa5oYg9FflQWUr7VHybdXn64248cZvSy2Yw//CohXRql4qYovwRTVSnog+18LxGf7RH1Ix6Q1wXw1vB5/SyXJVX3S/iuu6xaqZ8aEeLg6eVt0z9vCzGcMBhmTJz+YDPyf2XRQ1+gwUrOG05p6aLhF2gVUn0UXHdk6JIRjhrie8f1tOms0eaeYk7PAvIBjGNRlhrhKV88WbFIKEu/NM8gHvOpRF+o561aQnRf3FmjNN4g5q2TTu0I5zpmY04QOnC1TzCNBhgNprKt777//7cL5MFJTIAGiqYSLiBg+9awYNsxsaU2DMK2UCyhFRI9rEIlxw9Lsp710LKQg==';
const _vectorPin = 'xSkoVEwM5bbFGj4FBc2Qi5YrCfgkPf4cg2tCNQGc3/E=';
final _otherPin = base64.encode(List<int>.filled(32, 7));
final _thirdPin = base64.encode(List<int>.filled(32, 9));

void main() {
  const dbg = OliveTransportPolicy(release: false);
  const rel = OliveTransportPolicy(release: true);
  Uri u(String s) => Uri.parse(s);

  group('scheme and host policy', () {
    test('release: https is allowed, any http is refused (loopback included)', () {
      expect(rel.violation(u('https://api.example.com')), isNull);
      expect(rel.violation(u('https://api.example.com:8443')), isNull);
      expect(rel.violation(u('http://api.example.com')), contains('release'));
      expect(rel.violation(u('http://127.0.0.1:8123')), contains('release'));
      expect(rel.violation(u('http://10.0.2.2:8080')), contains('release'));
      expect(rel.violation(u('http://localhost:8080')), contains('release'));
    });
    test('debug: http only for loopback, the emulator host, private LAN and .local', () {
      for (final ok in [
        'http://localhost:8080', 'http://127.0.0.1:8123', 'http://10.0.2.2:8080', 'http://[::1]:8080',
        'http://192.168.1.20:8123', 'http://172.16.0.5', 'http://172.31.255.1', 'http://10.4.5.6',
        'http://169.254.10.10', 'http://olive-dev.local:8080', 'http://[fd12:3456::1]:8080',
      ]) {
        expect(dbg.violation(u(ok)), isNull, reason: ok);
      }
    });
    test('debug: cleartext to a public host is refused (a typo cannot leak a token)', () {
      for (final bad in [
        'http://api.example.com', 'http://8.8.8.8', 'http://172.32.0.1', 'http://172.15.0.1',
        'http://192.169.1.1', 'http://11.0.0.1', 'http://[2001:db8::1]', 'http://localhost.evil.com',
      ]) {
        expect(dbg.violation(u(bad)), isNotNull, reason: bad);
      }
    });
    test('other schemes, missing hosts, queries, fragments and credentials are refused', () {
      for (final bad in [
        'ftp://example.com', 'file:///etc/passwd', 'ws://example.com', 'example.com',
        'https://', 'https://u:p@example.com', 'https://example.com?x=1', 'https://example.com#f',
      ]) {
        expect(dbg.violation(u(bad)), isNotNull, reason: bad);
        expect(rel.violation(u(bad)), isNotNull, reason: bad);
      }
    });
  });

  group('DER and SPKI pins', () {
    final der = Uint8List.fromList(base64.decode(_vectorDerB64));
    test('the SPKI pin matches the openssl-computed vector', () async {
      expect(await spkiPin(der), _vectorPin);
    });
    test('extractSpki returns a SEQUENCE that is smaller than the certificate', () {
      final spki = extractSpki(der);
      expect(spki.first, 0x30);
      expect(spki.length, lessThan(der.length));
    });
    test('a truncated or garbage certificate does not match and does not throw', () async {
      final pins = PinSet([_vectorPin, _otherPin]);
      expect(await certificateMatchesPins(Uint8List.fromList([1, 2, 3]), pins), isFalse);
      expect(await certificateMatchesPins(Uint8List.sublistView(der, 0, 40), pins), isFalse);
      expect(await certificateMatchesPins(null, pins), isFalse);
    });
    test('matching is on any configured pin', () async {
      expect(await certificateMatchesPins(der, PinSet([_otherPin, _vectorPin])), isTrue);
      expect(await certificateMatchesPins(der, PinSet([_otherPin, _thirdPin])), isFalse);
      expect(await certificateMatchesPins(der, PinSet.empty), isFalse);
    });
  });

  group('pin sets', () {
    test('parse splits on commas, trims, drops blanks and duplicates', () {
      final p = PinSet.parse(' $_vectorPin , ,$_otherPin,$_vectorPin ');
      expect(p.pins, [_vectorPin, _otherPin]);
      expect(PinSet.parse('').isEmpty, isTrue);
    });
    test('well-formed means base64 of exactly 32 bytes, canonically encoded', () {
      expect(PinSet.isWellFormed(_vectorPin), isTrue);
      expect(PinSet.isWellFormed('short'), isFalse);
      expect(PinSet.isWellFormed(base64.encode(List<int>.filled(31, 1))), isFalse);
      expect(PinSet.isWellFormed('!!!notbase64!!!'), isFalse);
    });
    test('release needs a primary AND a backup pin; debug accepts one', () {
      expect(PinSet([_vectorPin]).validate(release: true), contains('backup'));
      expect(PinSet([_vectorPin, _otherPin]).validate(release: true), isNull);
      expect(PinSet([_vectorPin]).validate(release: false), isNull);
      expect(PinSet([_vectorPin, 'bad']).validate(release: false), isNotNull);
    });
  });

  group('OliveTransport', () {
    tearDown(OliveTransport.resetForTesting);

    test('a policy violation becomes a client that refuses, not a crash', () async {
      OliveTransport.policy = rel;
      final c = OliveTransport.clientFor('http://api.example.com');
      expect(c, isA<RefusingClient>());
      await expectLater(c.get(u('http://api.example.com/v1/me')), throwsA(isA<TransportPolicyViolation>()));
    });
    test('release with pinning requested but only one pin refuses (fails closed)', () {
      OliveTransport.policy = rel;
      OliveTransport.pins = PinSet([_vectorPin]);
      expect(OliveTransport.refusalFor('https://api.example.com'), contains('backup'));
      expect(OliveTransport.clientFor('https://api.example.com'), isA<RefusingClient>());
    });
    test('release with two pins builds a pinned client; with none, a plain one', () {
      OliveTransport.policy = rel;
      OliveTransport.pins = PinSet([_vectorPin, _otherPin]);
      expect(OliveTransport.refusalFor('https://api.example.com'), isNull);
      expect(OliveTransport.clientFor('https://api.example.com'), isNot(isA<RefusingClient>()));
      OliveTransport.pins = PinSet.empty;
      expect(OliveTransport.refusalFor('https://api.example.com'), isNull);
    });
    test('pins never apply to a dev base URL (debug http to localhost stays usable)', () {
      OliveTransport.policy = dbg;
      OliveTransport.pins = PinSet([_vectorPin, _otherPin]);
      expect(OliveTransport.refusalFor('http://10.0.2.2:8080'), isNull);
      expect(OliveTransport.refusalFor('https://192.168.1.20:8443'), isNull);
    });
    test('an unparseable base URL is refused', () {
      expect(OliveTransport.refusalFor('http://exa mple.com'), isNotNull);
    });
  });

  group('a real TLS handshake', () {
    late Directory tmp;
    var haveOpenssl = false;
    HttpServer? server;
    var hits = 0;
    late SecurityContext clientCtx;
    late String goodPin;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('olive-pin-');
      try {
        final r = await Process.run('openssl', [
          'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', '${tmp.path}/k.pem',
          '-out', '${tmp.path}/c.pem', '-days', '2', '-subj', '/CN=localhost',
          '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
        ]);
        haveOpenssl = r.exitCode == 0;
      } catch (_) {
        haveOpenssl = false;
      }
      if (!haveOpenssl) return;
      final srvCtx = SecurityContext()
        ..useCertificateChain('${tmp.path}/c.pem')
        ..usePrivateKey('${tmp.path}/k.pem');
      server = await HttpServer.bindSecure('127.0.0.1', 0, srvCtx);
      server!.listen((req) {
        hits++;
        req.response
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
        req.response.close();
      });
      clientCtx = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${tmp.path}/c.pem');
      final pem = await File('${tmp.path}/c.pem').readAsString();
      final derBytes = base64.decode(pem.replaceAll(RegExp(r'-----[A-Z ]+-----|\s'), ''));
      goodPin = await spkiPin(Uint8List.fromList(derBytes));
    });
    tearDownAll(() async {
      await server?.close(force: true);
      await tmp.delete(recursive: true);
    });

    test('openssl is available to mint the throwaway certificate', () {
      expect(haveOpenssl, isTrue,
          reason: 'this test needs the openssl CLI; it is on every CI image and in Git for Windows');
    });

    test('a matching pin lets the request through and the server answers', () async {
      if (!haveOpenssl) return;
      hits = 0;
      final c = createPinnedClient(PinSet([_otherPin, goodPin]), context: clientCtx);
      final r = await c.get(Uri.parse('https://localhost:${server!.port}/v1/me'));
      expect(r.statusCode, 200);
      expect(hits, 1);
      c.close();
    });

    test('a mismatching pin fails the handshake BEFORE the server sees any request', () async {
      if (!haveOpenssl) return;
      hits = 0;
      final c = createPinnedClient(PinSet([_otherPin, _thirdPin]), context: clientCtx);
      await expectLater(
        c.get(Uri.parse('https://localhost:${server!.port}/v1/me'),
            headers: {'authorization': 'Bearer SECRET'}),
        throwsA(anyOf(isA<HandshakeException>(), isA<http.ClientException>())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(hits, 0, reason: 'the bearer token must never be written to an unpinned server');
      c.close();
    });

    test('a context that does not trust the certificate fails even with a matching pin', () async {
      if (!haveOpenssl) return;
      final c = createPinnedClient(PinSet([goodPin, _otherPin]),
          context: SecurityContext(withTrustedRoots: false));
      await expectLater(
          c.get(Uri.parse('https://localhost:${server!.port}/v1/me')), throwsA(isA<Exception>()));
      c.close();
    });
  });
}
