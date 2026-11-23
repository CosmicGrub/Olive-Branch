// The updater's real transport against a real local HTTP server: ranges, redirects judged hop by hop, byte caps, the
// cleartext rule, and what is (not) sent. Only loopback is ever contacted. MASTERFILE 7.24.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/server_transport_policy.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_transport.dart';

void main() {
  late HttpServer server;
  late Uri base;
  final List<HttpHeaders> seen = <HttpHeaders>[];
  final Uint8List body = Uint8List.fromList(List<int>.generate(5000, (int i) => i % 251));

  HttpUpdateTransport transport({bool allowDev = true, int redirects = 5, Duration timeout = const Duration(seconds: 5)}) =>
      HttpUpdateTransport(
          policy: OliveTransportPolicy(release: true, allowDevCleartext: allowDev), maxRedirects: redirects, timeout: timeout);

  Future<UpdateRefusalCode?> failure(Future<Object?> Function() f) async {
    try {
      await f();
      return null;
    } on UpdateRefusal catch (e) {
      return e.code;
    }
  }

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((HttpRequest req) async {
      seen.add(req.headers);
      final HttpResponse res = req.response;
      final String p = req.uri.path;
      if (p == '/file') {
        final String? range = req.headers.value('range');
        if (range != null) {
          final int from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          res.statusCode = 206;
          res.headers.set('content-range', 'bytes $from-${body.length - 1}/${body.length}');
          res.add(body.sublist(from));
        } else {
          res.add(body);
        }
      } else if (p == '/norange') {
        res.add(body);
      } else if (p == '/to-file') {
        res.statusCode = 302;
        res.headers.set('location', '/file');
      } else if (p == '/chain') {
        res.statusCode = 301;
        res.headers.set('location', '/to-file');
      } else if (p == '/loop') {
        res.statusCode = 302;
        res.headers.set('location', '/loop');
      } else if (p == '/to-cleartext') {
        res.statusCode = 302;
        res.headers.set('location', 'http://203.0.113.9/olive.apk');
      } else if (p == '/to-localhost-name') {
        res.statusCode = 302;
        res.headers.set('location', 'http://localhost:${server.port}/file');
      } else if (p == '/to-ftp') {
        res.statusCode = 302;
        res.headers.set('location', 'ftp://203.0.113.9/olive.apk');
      } else if (p == '/to-credentials') {
        res.statusCode = 302;
        res.headers.set('location', 'http://user:pw@127.0.0.1:${server.port}/file');
      } else if (p == '/no-location') {
        res.statusCode = 302;
      } else if (p == '/big-declared') {
        res.contentLength = 10 * 1024 * 1024;
        res.add(Uint8List(10));
      } else if (p == '/big-chunked') {
        res.headers.chunkedTransferEncoding = true;
        for (int i = 0; i < 60; i++) {
          res.add(Uint8List(1024));
        }
      } else if (p == '/stall') {
        res.headers.chunkedTransferEncoding = true;
        res.add(Uint8List(10));
        await res.flush();
        await Future<void>.delayed(const Duration(seconds: 3));
      } else if (p == '/gone') {
        res.statusCode = 404;
      } else if (p == '/boom') {
        res.statusCode = 500;
      } else {
        res.statusCode = 404;
      }
      try {
        await res.close();
      } catch (_) {}
    });
  });

  tearDown(() async => server.close(force: true));

  test('get returns a small body; no credential, cookie or token is ever sent; identity encoding is asked for', () async {
    final UpdateResponse r = await transport().get(base.replace(path: '/file'), maxBytes: 100000);
    expect(r.body, body);
    expect(r.status, 200);
    final HttpHeaders h = seen.single;
    expect(h.value('authorization'), isNull);
    expect(h.value('cookie'), isNull);
    expect(h.value('accept-encoding'), 'identity');
    expect(h.value('user-agent'), isNot(contains('Dart')));
  });

  test('a ranged open: 206 with the start the server named', () async {
    final UpdateStream s = await transport().open(base.replace(path: '/file'), rangeStart: 1000);
    final List<int> got = <int>[await for (final List<int> p in s.body) ...p];
    expect(s.status, 206);
    expect(s.contentRangeStart, 1000);
    expect(got, body.sublist(1000));
    expect(seen.single.value('range'), 'bytes=1000-');
  });

  test('a server that ignores the range answers 200 and the caller can see it', () async {
    final UpdateStream s = await transport().open(base.replace(path: '/norange'), rangeStart: 1000);
    final List<int> got = <int>[await for (final List<int> p in s.body) ...p];
    expect(s.status, 200);
    expect(s.contentRangeStart, isNull);
    expect(got.length, body.length);
  });

  test('redirects on the same host are followed, and the final address is reported', () async {
    final UpdateResponse r = await transport().get(base.replace(path: '/chain'), maxBytes: 100000);
    expect(r.body, body);
    expect(r.finalUrl.path, '/file');
  });

  group('redirects are judged at every hop', () {
    test('to cleartext http on another host: refused before any request is made to it', () async {
      expect(await failure(() => transport().get(base.replace(path: '/to-cleartext'), maxBytes: 1000)), UpdateRefusalCode.badRedirect);
    });

    test('to a NAME for loopback, to ftp, or to an address with credentials: refused', () async {
      expect(await failure(() => transport().get(base.replace(path: '/to-localhost-name'), maxBytes: 1000)), UpdateRefusalCode.badRedirect);
      expect(await failure(() => transport().get(base.replace(path: '/to-ftp'), maxBytes: 1000)), UpdateRefusalCode.badRedirect);
      expect(await failure(() => transport().get(base.replace(path: '/to-credentials'), maxBytes: 1000)), UpdateRefusalCode.badRedirect);
    });

    test('a loop ends (after the allowed number of hops), and a redirect with no target is refused', () async {
      expect(await failure(() => transport(redirects: 3).get(base.replace(path: '/loop'), maxBytes: 1000)), UpdateRefusalCode.badRedirect);
      expect(seen.length, 4);
      expect(await failure(() => transport().get(base.replace(path: '/no-location'), maxBytes: 1000)), UpdateRefusalCode.badRedirect);
    });
  });

  group('the cleartext rule is the transport policy\'s', () {
    test('without the developer define, even loopback http is refused in a release build', () async {
      expect(await failure(() => transport(allowDev: false).get(base.replace(path: '/file'), maxBytes: 100000)), UpdateRefusalCode.badUrl);
      expect(seen, isEmpty);
    });

    test('credentials in the address are refused', () async {
      expect(await failure(() => transport().get(Uri.parse('http://user:pw@127.0.0.1:${server.port}/file'), maxBytes: 1000)), UpdateRefusalCode.badUrl);
    });

    test('a public address over http is refused even with the developer define', () async {
      expect(await failure(() => transport().get(Uri.parse('http://203.0.113.9/olive.apk'), maxBytes: 1000)), UpdateRefusalCode.badUrl);
    });
  });

  group('byte caps', () {
    test('a declared length above the cap is refused before the body is read', () async {
      expect(await failure(() => transport().get(base.replace(path: '/big-declared'), maxBytes: 1000)), UpdateRefusalCode.tooMuchData);
    });

    test('a body that grows past the cap with no declared length is cut off', () async {
      expect(await failure(() => transport().get(base.replace(path: '/big-chunked'), maxBytes: 4000)), UpdateRefusalCode.tooMuchData);
    });

    test('a body exactly at the cap is accepted', () async {
      final UpdateResponse r = await transport().get(base.replace(path: '/file'), maxBytes: body.length);
      expect(r.body.length, body.length);
    });
  });

  group('failures are named, not thrown raw', () {
    test('404 and 500 are an HTTP error; a closed port and a stalled body are "offline"', () async {
      expect(await failure(() => transport().get(base.replace(path: '/gone'), maxBytes: 1000)), UpdateRefusalCode.httpError);
      expect(await failure(() => transport().get(base.replace(path: '/boom'), maxBytes: 1000)), UpdateRefusalCode.httpError);
      final int port = server.port;
      await server.close(force: true);
      expect(await failure(() => transport().get(Uri.parse('http://127.0.0.1:$port/file'), maxBytes: 1000)), UpdateRefusalCode.offline);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest r) async {
        r.response.headers.chunkedTransferEncoding = true;
        r.response.add(Uint8List(10));
        await r.response.flush();
        await Future<void>.delayed(const Duration(seconds: 3));
        try {
          await r.response.close();
        } catch (_) {}
      });
      expect(
          await failure(() => transport(timeout: const Duration(milliseconds: 300))
              .get(Uri.parse('http://127.0.0.1:${server.port}/stall'), maxBytes: 100000)),
          UpdateRefusalCode.offline);
    });

    test('cancelling stops a transfer', () async {
      final UpdateCancel c = UpdateCancel()..cancel();
      expect(await failure(() => transport().get(base.replace(path: '/file'), maxBytes: 100000, cancel: c)), UpdateRefusalCode.cancelled);
    });
  });
}
