// OLIVE BRANCH — the signed update manifest: what the app is allowed to believe about "a newer version exists".
// The format of record is docs/UPDATE-MANIFEST.md (the release lane); tools/update/test-vectors.json is the shared truth
// this reader must reproduce, and test/update_manifest_test.dart replays every vector in it (a signature made by Node over
// the same canonical bytes, and a labelled set of documents that must be accepted or refused with a named code).
// MASTERFILE 7.24.
//
// THE RULE: nothing that arrives over the network is believed because of where it came from. A manifest is one JSON
// document, `{"manifest": {...}, "signature": {"alg": "ed25519", "kid": "...", "sig": "..."}}`. The signature is an Ed25519
// signature, by the owner's OFFLINE key, over the domain tag `olive-update-manifest-v1` and a newline, followed by the
// CANONICAL form of the `manifest` object (keys sorted, no whitespace, integers only, every control character written as
// a six-character `u00xx` escape). The matching PUBLIC key is built into the app (--dart-define OLIVE_UPDATE_PUBKEYS, see
// [UpdateTrust.fromEnvironment]); the private key is held offline and never enters this repository, a workflow or a server
// (docs/RELEASING.md, "Publishing an update"). A mirror, a CDN, a proxy, a captive portal or GitHub itself can therefore
// not make the app believe anything.
//
// Checked here, in the order the spec gives: size cap, strict UTF-8, a key to check against, a STRICT JSON parse (no
// duplicate keys, no floats, no lone surrogates, bounded depth), the document's two parts, the signature, and only then the
// exact shape of every member. Nothing that failed the signature is ever read into a model. The app TOLERATES a signed member
// it does not know (a later schema may add one); the publisher's validator is the stricter of the two. The channel, clock,
// replay, rollback and chip rules are the next layer (update_policy.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The application id a manifest must name. A manifest for any other app is refused.
const String kUpdateAppId = 'com.olivebranch.olive_client';

/// Domain tag in front of the canonical bytes. Not secret; it only keeps this signature from meaning anything else.
const String kUpdateSignDomain = 'olive-update-manifest-v1\n';

const int kUpdateSchema = 1;

/// Hard caps: the same numbers as LIMITS in tools/update/manifest_lib.mjs. Anything above them is refused before it is
/// parsed further, hashed or downloaded.
const int kMaxManifestBytes = 256 * 1024;
const int kMaxApkBytes = 500 * 1024 * 1024;
const int kMinChunkBytes = 16 * 1024;
const int kMaxChunkBytes = 8 * 1024 * 1024;
const int kMaxChunks = 32768;
const int kMaxApks = 4;
const int kMaxUrls = 4;
const int kMaxUrlChars = 2000;
const int kMaxHeadlineChars = 100;
const int kMaxNoteChars = 300;
const int kMaxNotes = 12;
const int kMaxVersionCode = 2147483647;
const int kMaxJsonDepth = 8;
const Duration kClockSkew = Duration(hours: 24);
const Duration kMaxValidity = Duration(days: 400);

/// Why a manifest, or something derived from it, was refused. The names are shared with tools/update/manifest_lib.mjs
/// (CODES) so one log line means one thing in both; what an adult reads is chosen from them in update_screens.dart. A
/// child never sees any of it.
enum UpdateRefusalCode {
  // the document
  tooLarge,
  notJson,
  badShape,
  noKeyConfigured,
  unknownKey,
  badSignature,
  // what it says
  wrongApp,
  wrongChannel,
  notYetValid,
  expired,
  replayed,
  rollback,
  noApkForDevice,
  badUrl,
  // the download
  badRedirect,
  httpError,
  offline,
  tooMuchData,
  truncated,
  hashMismatch,
  sizeMismatch,
  sizeTooLarge,
  noSpace,
  lowBattery,
  needsWifi,
  cancelled,
  // the install
  certMismatch,
  apkMismatch,
  needsPermission,
  kioskLocked,
  installRefused,
  installNotFinished,
}

class UpdateRefusal implements Exception {
  const UpdateRefusal(this.code, [this.detail = '']);
  final UpdateRefusalCode code;

  /// Never carries a URL query, a path on the device or a key.
  final String detail;

  @override
  String toString() => 'UpdateRefusal(${code.name}${detail.isEmpty ? '' : ': $detail'})';
}

// ---- strict JSON ------------------------------------------------------------

class _StrictJson {
  _StrictJson(this.s);
  final String s;
  int i = 0;

  Never _fail(String why) => throw UpdateRefusal(UpdateRefusalCode.notJson, why);

  void _ws() {
    while (i < s.length) {
      final int c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        i++;
      } else {
        break;
      }
    }
  }

  Object? parseDocument() {
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xfeff) _fail('byte-order mark');
    final Object? v = _value(0);
    _ws();
    if (i != s.length) _fail('trailing data after the document');
    return v;
  }

  Object? _value(int depth) {
    if (depth > kMaxJsonDepth) _fail('nested too deeply');
    _ws();
    if (i >= s.length) _fail('unexpected end');
    final String c = s[i];
    if (c == '{') {
      i++;
      final Map<String, Object?> o = <String, Object?>{};
      _ws();
      if (i < s.length && s[i] == '}') {
        i++;
        return o;
      }
      while (true) {
        _ws();
        if (i >= s.length || s[i] != '"') _fail('object key must be a string');
        final String k = _string();
        if (o.containsKey(k)) _fail('duplicate key');
        _ws();
        if (i >= s.length || s[i] != ':') _fail('expected a colon');
        i++;
        o[k] = _value(depth + 1);
        _ws();
        if (i < s.length && s[i] == ',') {
          i++;
          continue;
        }
        if (i < s.length && s[i] == '}') {
          i++;
          return o;
        }
        _fail('expected a comma or a closing brace');
      }
    }
    if (c == '[') {
      i++;
      final List<Object?> a = <Object?>[];
      _ws();
      if (i < s.length && s[i] == ']') {
        i++;
        return a;
      }
      while (true) {
        a.add(_value(depth + 1));
        _ws();
        if (i < s.length && s[i] == ',') {
          i++;
          continue;
        }
        if (i < s.length && s[i] == ']') {
          i++;
          return a;
        }
        _fail('expected a comma or a closing bracket');
      }
    }
    if (c == '"') return _string();
    if (s.startsWith('true', i)) {
      i += 4;
      return true;
    }
    if (s.startsWith('false', i)) {
      i += 5;
      return false;
    }
    if (s.startsWith('null', i)) {
      i += 4;
      return null;
    }
    final Match? m = RegExp(r'^-?(0|[1-9][0-9]*)').firstMatch(s.substring(i, (i + 24).clamp(0, s.length)));
    if (m == null) _fail('unexpected character');
    i += m.group(0)!.length;
    if (i < s.length && (s[i] == '.' || s[i] == 'e' || s[i] == 'E')) _fail('numbers must be integers');
    final int? n = int.tryParse(m.group(0)!);
    if (n == null || n.abs() > 9007199254740991) _fail('number out of range');
    return n;
  }

  String _string() {
    i++; // opening quote
    final StringBuffer b = StringBuffer();
    while (true) {
      if (i >= s.length) _fail('unterminated string');
      final int code = s.codeUnitAt(i);
      if (code == 0x22) {
        i++;
        break;
      }
      if (code < 0x20) _fail('raw control character in string');
      if (code == 0x5c) {
        if (i + 1 >= s.length) _fail('bad escape');
        final String e = s[i + 1];
        const Map<String, String> simple = <String, String>{
          '"': '"', '\\': '\\', '/': '/', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', //
        };
        if (simple.containsKey(e)) {
          b.write(simple[e]);
          i += 2;
          continue;
        }
        if (e == 'u') {
          if (i + 6 > s.length) _fail('bad unicode escape');
          final String h = s.substring(i + 2, i + 6);
          if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(h)) _fail('bad unicode escape');
          b.writeCharCode(int.parse(h, radix: 16));
          i += 6;
          continue;
        }
        _fail('bad escape');
      }
      b.writeCharCode(code);
      i++;
    }
    final String out = b.toString();
    _wellFormed(out);
    return out;
  }

  void _wellFormed(String t) {
    for (int k = 0; k < t.length; k++) {
      final int c = t.codeUnitAt(k);
      if (c >= 0xd800 && c <= 0xdbff) {
        final int d = k + 1 < t.length ? t.codeUnitAt(k + 1) : 0;
        if (d < 0xdc00 || d > 0xdfff) _fail('lone surrogate in string');
        k++;
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        _fail('lone surrogate in string');
      }
    }
  }
}

/// Parses [text] as strict JSON (see the file header). Throws [UpdateRefusal] (notJson).
Object? parseStrictJson(String text) => _StrictJson(text).parseDocument();

// ---- canonical JSON ---------------------------------------------------------

/// The one byte form a signature covers: identical, character for character, to `canonicalize` in
/// tools/update/manifest_lib.mjs: object keys sorted by UTF-16 code unit, no whitespace, integers only, a string escapes
/// `"` and `\` and EVERY control character below 0x20 as a lower-case `u00xx` escape (a newline is the escape for 0x0a,
/// never the short form), and writes everything else as the character itself (UTF-8 on the wire). Deliberately not what
/// JSON.stringify does: test-vectors.json pins it.
String canonicalJson(Object? v) {
  final StringBuffer b = StringBuffer();
  _canon(v, b);
  return b.toString();
}

void _canon(Object? v, StringBuffer b) {
  if (v == null) {
    b.write('null');
  } else if (v is bool) {
    b.write(v ? 'true' : 'false');
  } else if (v is int) {
    if (v.abs() > 9007199254740991) throw const FormatException('integer beyond 2^53');
    b.write(v.toString());
  } else if (v is String) {
    _canonString(v, b);
  } else if (v is List) {
    b.write('[');
    for (int i = 0; i < v.length; i++) {
      if (i > 0) b.write(',');
      _canon(v[i], b);
    }
    b.write(']');
  } else if (v is Map) {
    final List<String> keys = <String>[
      for (final Object? k in v.keys)
        if (k is String) k else throw const FormatException('object key is not a string'),
    ]..sort();
    b.write('{');
    for (int i = 0; i < keys.length; i++) {
      if (i > 0) b.write(',');
      _canonString(keys[i], b);
      b.write(':');
      _canon(v[keys[i]], b);
    }
    b.write('}');
  } else {
    // A double, or anything else JSON could not hold exactly: refused, never rounded.
    throw FormatException('value of type ${v.runtimeType} has no canonical form');
  }
}

void _canonString(String s, StringBuffer b) {
  b.write('"');
  for (final int c in s.codeUnits) {
    if (c == 0x22) {
      b.write('\\"');
    } else if (c == 0x5c) {
      b.write('\\\\');
    } else if (c < 0x20) {
      b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
    } else {
      b.writeCharCode(c);
    }
  }
  b.write('"');
}

/// The exact bytes the owner's offline key signs for the manifest object [payload].
Uint8List signingBytes(Map<String, Object?> payload) =>
    Uint8List.fromList(utf8.encode('$kUpdateSignDomain${canonicalJson(payload)}'));

// ---- trust ------------------------------------------------------------------

/// Strict base64url: the url-safe alphabet only, padding tolerated (the publisher writes none). Null on anything else.
Uint8List? fromBase64Url(String s) {
  if (!RegExp(r'^[A-Za-z0-9_-]*={0,2}$').hasMatch(s)) return null;
  final String bare = s.replaceAll('=', '');
  if (bare.length % 4 == 1) return null;
  try {
    final Uint8List out = Uint8List.fromList(base64Url.decode(base64Url.normalize(bare)));
    return base64Url.encode(out).replaceAll('=', '') == bare ? out : null;
  } catch (_) {
    return null;
  }
}

String toBase64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// The built-in public keys, by key id (`kid`, a label). Two at a time is the rotation story: a new key ships inside a
/// release signed by the old one, then manifests switch to the new one.
class UpdateTrust {
  UpdateTrust(Map<String, List<int>> keys)
      : keys = Map<String, Uint8List>.unmodifiable(<String, Uint8List>{
          for (final MapEntry<String, List<int>> e in keys.entries)
            if (e.value.length == 32) e.key: Uint8List.fromList(e.value),
        });

  /// `kid:base64url(32-byte key)` entries separated by commas, the `--dart-define=OLIVE_UPDATE_PUBKEYS=` form. A
  /// malformed entry is ignored: a build with no usable key has the feature off, which fails closed.
  factory UpdateTrust.parse(String csv) {
    final Map<String, List<int>> out = <String, List<int>>{};
    for (final String part in csv.split(',')) {
      final String p = part.trim();
      final int at = p.indexOf(':');
      if (at < 1) continue;
      final String kid = p.substring(0, at);
      if (!RegExp(r'^[A-Za-z0-9._-]{1,32}$').hasMatch(kid)) continue;
      final Uint8List? k = fromBase64Url(p.substring(at + 1));
      if (k != null && k.length == 32) out[kid] = k;
    }
    return UpdateTrust(out);
  }

  static UpdateTrust fromEnvironment() => UpdateTrust.parse(const String.fromEnvironment('OLIVE_UPDATE_PUBKEYS'));

  final Map<String, Uint8List> keys;
  bool get isEmpty => keys.isEmpty;
}

// ---- the model ---------------------------------------------------------------

/// One downloadable file for one kind of phone.
class ApkEntry {
  const ApkEntry({
    required this.abi,
    required this.size,
    required this.sha256,
    required this.signerSha256,
    required this.chunkSize,
    required this.chunks,
    required this.urls,
  });

  /// `arm64-v8a`, `armeabi-v7a`, `x86_64` or `universal`.
  final String abi;
  final int size;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;

  /// Lower-case hex SHA-256 of the certificate the file must be signed with. The file's own certificate must be this one
  /// AND the installed app's: a build signed by anyone else is refused.
  final String signerSha256;
  final int chunkSize;

  /// Lower-case hex SHA-256 of each chunk, in order; the last chunk is the remainder.
  final List<String> chunks;

  /// The primary address first, then mirrors.
  final List<Uri> urls;

  int get chunkCount => chunks.length;

  /// The length of chunk [i] (the last one is the remainder).
  int chunkLength(int i) => i == chunkCount - 1 ? size - chunkSize * (chunkCount - 1) : chunkSize;
}

class UpdateManifest {
  const UpdateManifest({
    required this.app,
    required this.channel,
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.sequence,
    required this.issuedAt,
    required this.expiresAt,
    required this.publishedAt,
    required this.headline,
    required this.notes,
    required this.apks,
    required this.keyId,
  });

  final String app;
  final String channel;
  final String versionName;
  final int versionCode;
  final int minSupportedVersionCode;

  /// Rises with every manifest the owner signs; a lower one than one already accepted is a replay.
  final int sequence;
  final DateTime issuedAt, expiresAt, publishedAt;

  /// Plain words for a grown-up.
  final String headline;
  final List<String> notes;
  final List<ApkEntry> apks;

  /// Which built-in key signed it.
  final String keyId;

  /// The file for this phone: its own chip first (in the phone's order of preference), else `universal`, else null.
  ApkEntry? apkFor(List<String> deviceAbis) {
    for (final String abi in deviceAbis) {
      for (final ApkEntry a in apks) {
        if (a.abi == abi) return a;
      }
    }
    for (final ApkEntry a in apks) {
      if (a.abi == 'universal') return a;
    }
    return null;
  }
}

/// A manifest whose signature checked out, with the document exactly as it arrived (the family hand-over passes the
/// same bytes on, and the receiving phone verifies them again for itself).
class VerifiedManifest {
  const VerifiedManifest(this.manifest, this.document);
  final UpdateManifest manifest;
  final Uint8List document;
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _channelRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');
final RegExp _versionRe = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}(-[0-9A-Za-z.-]{1,20})?$');
final RegExp _isoUtc = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,3})?Z$');
// No markup, no code, no control, invisible or bidirectional-override characters: notes are shown to adults as plain text
// and never rendered as anything else.
final RegExp _noteForbidden =
    RegExp('[<>`\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2028\u2029\u2060-\u2064\ufeff]');

const Set<String> kUpdateAbis = <String>{'arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'};

UpdateRefusal _bad(String why) => UpdateRefusal(UpdateRefusalCode.badShape, why);

/// versionCode as docs/RELEASING.md derives it: major*10000 + minor*100 + patch (the publisher's check; the app reads
/// the signed numbers as they are).
int versionCodeOfName(String versionName) {
  final Match? m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(versionName);
  if (m == null) throw _bad('versionName');
  return int.parse(m.group(1)!) * 10000 + int.parse(m.group(2)!) * 100 + int.parse(m.group(3)!);
}

DateTime _time(Object? v, String name) {
  if (v is! String) throw _bad('$name is not a UTC time');
  final Match? m = _isoUtc.firstMatch(v);
  if (m == null) throw _bad('$name is not a UTC time');
  final List<int> p = <int>[for (int g = 1; g <= 6; g++) int.parse(m.group(g)!)];
  final int ms = m.group(7) == null ? 0 : (double.parse('0${m.group(7)}') * 1000).round();
  final DateTime t = DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5], ms);
  // DateTime.utc rolls 2026-02-31 over to March; the text must round-trip.
  if (t.year != p[0] || t.month != p[1] || t.day != p[2] || t.hour != p[3] || t.minute != p[4] || t.second != p[5]) {
    throw _bad('$name is not a real time');
  }
  return t;
}

int _intIn(Object? v, String name, int lo, int hi) {
  if (v is! int) throw _bad('$name must be an integer');
  if (v < lo || v > hi) throw _bad('$name is out of range');
  return v;
}

String _hexIn(Object? v, String name) {
  if (v is! String || !_hex64.hasMatch(v)) throw _bad('$name must be 64 lower-case hex digits');
  return v;
}

String _short(Object? v, String name, int max, {bool nonEmpty = true}) {
  if (v is! String || (nonEmpty && v.isEmpty) || v.length > max) throw _bad('$name is not a short string');
  return v;
}

String _plain(Object? v, String name, int max, {bool nonEmpty = true}) {
  final String s = _short(v, name, max, nonEmpty: nonEmpty);
  if (_noteForbidden.hasMatch(s) || s != s.trim()) throw _bad('$name must be plain text');
  return s;
}

/// Why [s] may not be fetched, or null. https always; plain http only to a literal loopback address and only when
/// [allowLoopbackHttp] (the developer lane); never credentials or a fragment. A query is allowed (a signed-URL mirror
/// needs one). [OliveTransportPolicy] is consulted again for every request and every redirect, so this is the shape
/// check, not the only one.
String? updateUrlProblem(String s, {bool allowLoopbackHttp = false}) {
  if (s.length > kMaxUrlChars) return 'too long';
  if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(s)) return 'not printable ASCII';
  final Uri? u = Uri.tryParse(s);
  if (u == null || !u.hasAuthority || u.host.isEmpty) return 'not a URL';
  if (u.userInfo.isNotEmpty) return 'credentials in the URL';
  if (u.hasFragment || s.contains('#')) return 'a fragment';
  if (u.path.isEmpty || u.path == '/') return 'no file path';
  if (u.scheme == 'https') return null;
  if (u.scheme == 'http') {
    final String h = u.host.replaceAll(RegExp(r'^\[|\]$'), '');
    if (allowLoopbackHttp && (h == '127.0.0.1' || h == '::1')) return null;
    return 'cleartext http';
  }
  return 'unsupported scheme';
}

ApkEntry _parseApk(Object? a, {required bool allowLoopbackHttp}) {
  if (a is! Map<String, Object?>) throw _bad('apk entry');
  final Object? abi = a['abi'];
  if (abi is! String || !kUpdateAbis.contains(abi)) throw _bad('abi');
  final Object? sizeRaw = a['size'];
  if (sizeRaw is int && sizeRaw > kMaxApkBytes) {
    throw const UpdateRefusal(UpdateRefusalCode.sizeTooLarge, 'declared size over the cap');
  }
  final int size = _intIn(sizeRaw, 'size', 1, kMaxApkBytes);
  final int chunkSize = _intIn(a['chunkSize'], 'chunkSize', kMinChunkBytes, kMaxChunkBytes);
  final int expect = (size + chunkSize - 1) ~/ chunkSize;
  final Object? chunksRaw = a['chunks'];
  if (chunksRaw is! List || chunksRaw.length > kMaxChunks || chunksRaw.length != expect) {
    throw _bad('chunks must hold exactly ceil(size / chunkSize) hashes');
  }
  final List<String> chunks = <String>[for (final Object? c in chunksRaw) _hexIn(c, 'chunks[]')];
  final Object? urlsRaw = a['urls'];
  if (urlsRaw is! List || urlsRaw.isEmpty || urlsRaw.length > kMaxUrls) throw _bad('urls');
  final List<Uri> urls = <Uri>[];
  final Set<String> seen = <String>{};
  for (final Object? u in urlsRaw) {
    if (u is! String || updateUrlProblem(u, allowLoopbackHttp: allowLoopbackHttp) != null || !seen.add(u)) {
      throw const UpdateRefusal(UpdateRefusalCode.badUrl);
    }
    urls.add(Uri.parse(u));
  }
  return ApkEntry(
    abi: abi,
    size: size,
    sha256: _hexIn(a['sha256'], 'sha256'),
    signerSha256: _hexIn(a['signerSha256'], 'signerSha256'),
    chunkSize: chunkSize,
    chunks: chunks,
    urls: urls,
  );
}

/// Reads the exact shape of an already-verified payload. Throws [UpdateRefusal] (badShape, badUrl, sizeTooLarge,
/// wrongApp).
UpdateManifest parseManifestObject(Map<String, Object?> m, {required String keyId, bool allowLoopbackHttp = false}) {
  if (m['schema'] != kUpdateSchema) throw _bad('unknown schema');
  final Object? app = m['app'];
  if (app is String && app != kUpdateAppId) throw UpdateRefusal(UpdateRefusalCode.wrongApp, app);
  if (app != kUpdateAppId) throw _bad('app');
  final Object? channel = m['channel'];
  if (channel is! String || !_channelRe.hasMatch(channel)) throw _bad('channel');
  final Object? versionName = m['versionName'];
  if (versionName is! String || versionName.length > 40 || !_versionRe.hasMatch(versionName)) throw _bad('versionName');
  final int versionCode = _intIn(m['versionCode'], 'versionCode', 1, kMaxVersionCode);
  final int minSupported = _intIn(m['minSupportedVersionCode'], 'minSupportedVersionCode', 1, kMaxVersionCode);
  if (minSupported > versionCode) throw _bad('minSupportedVersionCode is above versionCode');
  final int sequence = _intIn(m['sequence'], 'sequence', 1, 9007199254740991);
  final DateTime issued = _time(m['issuedAt'], 'issuedAt');
  final DateTime expires = _time(m['expiresAt'], 'expiresAt');
  final DateTime published = _time(m['publishedAt'], 'publishedAt');
  if (!expires.isAfter(issued)) throw _bad('expiresAt is not after issuedAt');
  if (expires.difference(issued) > kMaxValidity) throw _bad('validity longer than 400 days');
  final String headline = _plain(m['headline'], 'headline', kMaxHeadlineChars, nonEmpty: false);
  final Object? notesRaw = m['notes'];
  if (notesRaw is! List || notesRaw.length > kMaxNotes) throw _bad('notes');
  final List<String> notes = <String>[for (final Object? n in notesRaw) _plain(n, 'notes[]', kMaxNoteChars)];
  final Object? apksRaw = m['apks'];
  if (apksRaw is! List || apksRaw.isEmpty || apksRaw.length > kMaxApks) throw _bad('apks');
  final List<ApkEntry> apks = <ApkEntry>[for (final Object? a in apksRaw) _parseApk(a, allowLoopbackHttp: allowLoopbackHttp)];
  if (<String>{for (final ApkEntry a in apks) a.abi}.length != apks.length) throw _bad('two files for one abi');
  return UpdateManifest(
    app: app! as String,
    channel: channel,
    versionName: versionName,
    versionCode: versionCode,
    minSupportedVersionCode: minSupported,
    sequence: sequence,
    issuedAt: issued,
    expiresAt: expires,
    publishedAt: published,
    headline: headline,
    notes: notes,
    apks: apks,
    keyId: keyId,
  );
}

/// Checks a downloaded manifest document and returns it only when the signature verifies against a built-in key.
/// Order matters (and is the spec's): size, a key to check against, strict UTF-8 and JSON, the two parts, the signature,
/// and only then the shape. Throws [UpdateRefusal].
Future<VerifiedManifest> verifyManifestDocument(Uint8List body, UpdateTrust trust, {bool allowLoopbackHttp = false}) async {
  if (body.length > kMaxManifestBytes) throw const UpdateRefusal(UpdateRefusalCode.tooLarge);
  if (trust.isEmpty) throw const UpdateRefusal(UpdateRefusalCode.noKeyConfigured);
  final String text;
  try {
    text = utf8.decode(body);
  } on FormatException {
    throw const UpdateRefusal(UpdateRefusalCode.notJson, 'not valid UTF-8');
  }
  final Object? doc = parseStrictJson(text);
  if (doc is! Map<String, Object?>) throw const UpdateRefusal(UpdateRefusalCode.notJson, 'not an object');
  final Object? payload = doc['manifest'];
  final Object? sig = doc['signature'];
  if (payload is! Map<String, Object?> || sig is! Map<String, Object?>) throw _bad('missing manifest or signature');
  if (sig['alg'] != 'ed25519') throw const UpdateRefusal(UpdateRefusalCode.badSignature, 'unsupported algorithm');
  final Object? kid = sig['kid'];
  final Object? sigText = sig['sig'];
  if (kid is! String || sigText is! String) throw const UpdateRefusal(UpdateRefusalCode.badSignature);
  final Uint8List? key = trust.keys[kid];
  if (key == null) throw const UpdateRefusal(UpdateRefusalCode.unknownKey);
  final Uint8List? signature = fromBase64Url(sigText);
  if (signature == null || signature.length != 64) throw const UpdateRefusal(UpdateRefusalCode.badSignature);
  final Uint8List message;
  try {
    message = signingBytes(payload);
  } on FormatException {
    // A value with no canonical form cannot be what the owner signed.
    throw const UpdateRefusal(UpdateRefusalCode.badSignature, 'no canonical form');
  }
  bool ok = false;
  try {
    ok = await Ed25519().verify(message, signature: Signature(signature, publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)));
  } catch (_) {
    ok = false;
  }
  if (!ok) throw const UpdateRefusal(UpdateRefusalCode.badSignature);
  return VerifiedManifest(parseManifestObject(payload, keyId: kid, allowLoopbackHttp: allowLoopbackHttp), body);
}
