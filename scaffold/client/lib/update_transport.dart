// OLIVE BRANCH — how the updater reaches the network, and what it knows about the phone it runs on. Verified
// headless (test/update_transport_test.dart: a real local HTTP server for ranges, redirects, caps and cleartext).
// MASTERFILE 7.24.
//
// TRANSPORT RULES (docs/operators, server_transport_policy.dart): release builds speak https only; the developer-only
// loopback define of that policy is the one cleartext exception and is judged by the SAME
// [OliveTransportPolicy] the API client uses. Every redirect hop is judged again, so an https address that redirects
// to http is refused; a redirect to another host is allowed (GitHub redirects its downloads to a storage host) because
// nothing about a download is trusted for where it came from: the manifest is signed and the file is checked against
// signed hashes. No credential, cookie or token is ever sent, and no pin of the Olive server is applied to a download.
//
// BYTE CAPS. A response is read only up to the cap the caller names (the manifest cap, or exactly one chunk). More
// than that is refused as soon as it is seen, so a server cannot make the phone read a zip bomb or an endless stream.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;

import 'server_transport_policy.dart';
import 'update_manifest.dart';

/// One small answer. [body] is at most the cap the request named.
class UpdateResponse {
  const UpdateResponse({required this.status, required this.body, required this.finalUrl});
  final int status;
  final Uint8List body;
  final Uri finalUrl;
}

/// A way to stop a download that is already running.
class UpdateCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// An open file download: the status line has been read and the body has not.
class UpdateStream {
  const UpdateStream({
    required this.status,
    required this.body,
    required this.finalUrl,
    this.contentLength,
    this.contentRangeStart,
  });
  final int status;
  final Stream<List<int>> body;
  final Uri finalUrl;
  final int? contentLength;

  /// From a 206's Content-Range: where in the file the body starts. Null for a plain 200.
  final int? contentRangeStart;
}

abstract class UpdateTransport {
  /// GET [url] and read at most [maxBytes] (a manifest). Throws [UpdateRefusal]: offline, httpError, badUrl,
  /// badRedirect, tooMuchData or cancelled.
  Future<UpdateResponse> get(Uri url, {required int maxBytes, UpdateCancel? cancel});

  /// GET [url] for a file, from byte [rangeStart] when given. A server that ignores the range answers 200 with the
  /// whole file and the caller skips what it already has. The caller reads the body and stops when it has enough.
  Future<UpdateStream> open(Uri url, {int? rangeStart, UpdateCancel? cancel});
}

/// The real transport: dart:io through package:http, redirects followed by hand.
class HttpUpdateTransport implements UpdateTransport {
  HttpUpdateTransport({
    http.Client? client,
    OliveTransportPolicy? policy,
    this.maxRedirects = 5,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _policy = policy ?? const OliveTransportPolicy(release: kReleaseMode);

  final http.Client _client;
  final OliveTransportPolicy _policy;
  final int maxRedirects;
  final Duration timeout;

  Future<http.StreamedResponse> _send(Uri url, int? rangeStart, UpdateCancel? cancel, List<Uri> finalUrl) async {
    Uri at = url;
    for (int hop = 0; hop <= maxRedirects; hop++) {
      if (cancel?.isCancelled ?? false) throw const UpdateRefusal(UpdateRefusalCode.cancelled);
      final String? why = _policy.violation(at);
      if (why != null || at.userInfo.isNotEmpty) {
        throw UpdateRefusal(hop == 0 ? UpdateRefusalCode.badUrl : UpdateRefusalCode.badRedirect, why ?? 'credentials');
      }
      final http.Request req = http.Request('GET', at)
        ..followRedirects = false
        ..headers['Accept-Encoding'] = 'identity'
        ..headers['User-Agent'] = 'OliveBranch-updater';
      if (rangeStart != null && rangeStart > 0) req.headers['Range'] = 'bytes=$rangeStart-';
      final http.StreamedResponse res;
      try {
        res = await _client.send(req).timeout(timeout);
      } on TransportPolicyViolation catch (e) {
        throw UpdateRefusal(UpdateRefusalCode.badUrl, e.reason);
      } on TimeoutException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'no answer');
      } on SocketException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'no connection');
      } on HandshakeException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'the secure connection failed');
      } on http.ClientException {
        throw const UpdateRefusal(UpdateRefusalCode.offline, 'no connection');
      }
      final int s = res.statusCode;
      if (s == 301 || s == 302 || s == 303 || s == 307 || s == 308) {
        final String? loc = res.headers['location'];
        // Drained so the connection is released; a redirect body is never read.
        unawaited(res.stream.drain<void>().catchError((Object _) {}));
        if (loc == null || loc.isEmpty || loc.length > 2048) {
          throw const UpdateRefusal(UpdateRefusalCode.badRedirect, 'no target');
        }
        final Uri? next = Uri.tryParse(loc);
        if (next == null) throw const UpdateRefusal(UpdateRefusalCode.badRedirect, 'not a URL');
        at = at.resolveUri(next);
        continue;
      }
      if (s != 200 && s != 206) {
        unawaited(res.stream.drain<void>().catchError((Object _) {}));
        throw UpdateRefusal(UpdateRefusalCode.httpError, 'status $s');
      }
      finalUrl.add(at);
      return res;
    }
    throw const UpdateRefusal(UpdateRefusalCode.badRedirect, 'too many redirects');
  }

  @override
  Future<UpdateResponse> get(Uri url, {required int maxBytes, UpdateCancel? cancel}) async {
    final List<Uri> fin = <Uri>[];
    final http.StreamedResponse res = await _send(url, null, cancel, fin);
    final int? declared = res.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(res.stream.drain<void>().catchError((Object _) {}));
      throw UpdateRefusal(UpdateRefusalCode.tooMuchData, 'declared $declared bytes');
    }
    final BytesBuilder b = BytesBuilder(copy: false);
    try {
      await for (final List<int> part in res.stream.timeout(timeout)) {
        if (cancel?.isCancelled ?? false) throw const UpdateRefusal(UpdateRefusalCode.cancelled);
        b.add(part);
        if (b.length > maxBytes) throw UpdateRefusal(UpdateRefusalCode.tooMuchData, 'more than $maxBytes bytes');
      }
    } on TimeoutException {
      throw const UpdateRefusal(UpdateRefusalCode.offline, 'the connection stalled');
    } on SocketException {
      throw const UpdateRefusal(UpdateRefusalCode.offline, 'the connection dropped');
    } on http.ClientException {
      throw const UpdateRefusal(UpdateRefusalCode.offline, 'the connection dropped');
    }
    return UpdateResponse(status: res.statusCode, body: b.takeBytes(), finalUrl: fin.single);
  }

  @override
  Future<UpdateStream> open(Uri url, {int? rangeStart, UpdateCancel? cancel}) async {
    final List<Uri> fin = <Uri>[];
    final http.StreamedResponse res = await _send(url, rangeStart, cancel, fin);
    int? start;
    if (res.statusCode == 206) {
      final Match? m = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$').firstMatch(res.headers['content-range'] ?? '');
      start = m == null ? null : int.tryParse(m.group(1)!);
    }
    return UpdateStream(
      status: res.statusCode,
      body: res.stream,
      finalUrl: fin.single,
      contentLength: res.contentLength,
      contentRangeStart: start,
    );
  }
}

// ---- the phone ---------------------------------------------------------------

enum NetworkKind { none, wifi, ethernet, cellular, unknown }

/// What the phone says about itself. Every field may be unknown (null), and unknown never blocks: the guards below
/// only act on what is known.
class UpdateEnvironment {
  const UpdateEnvironment({
    required this.installedVersionCode,
    required this.installedVersionName,
    this.network = NetworkKind.unknown,
    this.metered,
    this.roaming = false,
    this.dataSaver = false,
    this.batteryPercent,
    this.charging = false,
    this.freeBytes,
    this.abis = const <String>[],
    this.flavor = 'direct',
  });

  final int installedVersionCode;
  final String installedVersionName;
  final NetworkKind network;

  /// The system's own word for "this connection may cost money". Null when it does not say.
  final bool? metered;
  final bool roaming;

  /// Android's Data Saver is on for this app (background data restricted).
  final bool dataSaver;
  final int? batteryPercent;
  final bool charging;

  /// Free space where the update would be kept.
  final int? freeBytes;
  final List<String> abis;

  /// `direct` or `play`: what THIS build is (the build decides, never the manifest).
  final String flavor;

  bool get isOffline => network == NetworkKind.none;

  /// On a connection that does not cost per byte: Wi-Fi or a cable, and the system does not call it metered.
  bool get onUnmeteredWifi =>
      (network == NetworkKind.wifi || network == NetworkKind.ethernet) && metered != true && !roaming;
}

abstract class UpdateEnvironmentSource {
  Future<UpdateEnvironment> read();
}

/// A fixed answer, for tests and for builds with no native side (the preview, Windows).
class FixedEnvironment implements UpdateEnvironmentSource {
  FixedEnvironment(this.value);
  UpdateEnvironment value;
  @override
  Future<UpdateEnvironment> read() async => value;
}
