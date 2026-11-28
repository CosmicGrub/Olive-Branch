// OLIVE BRANCH — the "GitHub releases" update source of the direct (sideload) build. Pure functions: no network, no
// storage. Verified headless (test/update_github_test.dart, with a sequence of future releases, a pre-release, a draft,
// a malformed one and hostile assets). MASTERFILE 7.24.
//
// WHAT IT TRUSTS, AND WHAT IT DOES NOT. The repository owner and name are fixed HERE, in code. The only address the app
// ever asks for a list is https://api.github.com/repos/<owner>/<repo>/releases (no token, no credential, ever). A file
// address is never taken from the answer: it is built from the fixed repository, the release tag and the exact asset
// name `olive-branch-v<version>-arm64-preview.apk`; any other asset is ignored. The file's SHA-256 must be published by
// the release itself (a `sha256: <hex>` line in its notes, the file table of the notes, or the digest GitHub computed
// for the asset); a release that publishes none, or two that disagree, is ignored. A version is the tag `vMAJOR.MINOR.PATCH`
// and its build number is major*10000 + minor*100 + patch, the same formula tools/release_lib.mjs (buildNumber) uses.
//
// HONEST LIMIT. Anyone who can publish a release in that repository can publish an update the app will offer. This is
// as trustworthy as the repository account, and the signed-manifest path (update_manifest.dart) remains the stronger one
// when an owner signing key exists. Android additionally refuses any file that is not signed by the same certificate as
// the installed app, so a debug-signed preview only ever upgrades a build signed with the same debug key.
import 'dart:convert';
import 'dart:typed_data';

import 'update_manifest.dart';

const String kGithubOwner = 'CosmicGrub';
const String kGithubRepo = 'Olive-Branch';

/// The host that answers the release list, and the hosts a file download may touch (GitHub hands release files to its
/// own storage hosts through a redirect). Nothing else is ever contacted.
const String kGithubApiHost = 'api.github.com';
const Set<String> kGithubApiHosts = <String>{kGithubApiHost};
const Set<String> kGithubDownloadHosts = <String>{
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
  'github-releases.githubusercontent.com',
};

/// The answer to the release list is never read past this (a few kilobytes per release).
const int kMaxGithubBytes = 2 * 1024 * 1024;

/// How often the app looks by itself (a manual "Check for updates" is always allowed).
const Duration kGithubCheckEvery = Duration(hours: 6);

const int kGithubPerPage = 20;
const int kGithubMaxBetween = 5;

Uri githubReleasesUri({String owner = kGithubOwner, String repo = kGithubRepo}) =>
    Uri.https(kGithubApiHost, '/repos/$owner/$repo/releases', <String, String>{'per_page': '$kGithubPerPage'});

/// `olive-branch-v0.53.0-arm64-preview.apk`.
String githubApkName(String version) => 'olive-branch-v$version-arm64-preview.apk';

/// The one address a release's file is fetched from. Built, never read from the answer.
Uri githubApkUri(String tag, String name, {String owner = kGithubOwner, String repo = kGithubRepo}) =>
    Uri.https('github.com', '/$owner/$repo/releases/download/$tag/$name');

final RegExp _tagRe = RegExp(r'^v(\d{1,4})\.(\d{1,2})\.(\d{1,2})$');

/// The build number for a tag like `v0.53.0`, or null when the tag is not exactly that shape (minor and patch are 0 to 99).
int? githubVersionCode(String tag) {
  final Match? m = _tagRe.firstMatch(tag);
  if (m == null) return null;
  final int code = int.parse(m.group(1)!) * 10000 + int.parse(m.group(2)!) * 100 + int.parse(m.group(3)!);
  return code >= 1 && code <= kMaxVersionCode ? code : null;
}

/// One release that passed every check: it has a file of the right name, a size and a published hash.
class GithubRelease {
  const GithubRelease({
    required this.tag,
    required this.versionName,
    required this.versionCode,
    required this.prerelease,
    required this.publishedAt,
    required this.headline,
    required this.notes,
    required this.apkName,
    required this.apkUrl,
    required this.apkSize,
    required this.sha256,
  });

  final String tag;
  final String versionName;
  final int versionCode;
  final bool prerelease;
  final DateTime publishedAt;

  /// Plain words for a grown-up: the first line of the release notes, and a few of the lines that follow it.
  final String headline;
  final List<String> notes;
  final String apkName;
  final Uri apkUrl;
  final int apkSize;
  final String sha256;
}

/// What a check found: the newest release strictly newer than the installed build, and every other release that is
/// newer than the installed build (newest first), so a grown-up who skipped some sees what they missed.
class GithubOffer {
  const GithubOffer(this.newest, this.between);
  final GithubRelease newest;
  final List<GithubRelease> between;
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// A single-line `sha256: <hex>` in the notes (the machine-readable line tools/cut-release.mjs writes) or the file
/// table's `| SHA-256 | `hex` |` row. Returns every distinct value found, lower-cased.
Set<String> githubBodyHashes(String body) {
  final Set<String> out = <String>{};
  for (final RegExpMatch m in RegExp(r'^\s*sha256:\s*`?([0-9a-fA-F]{64})`?\s*$', multiLine: true).allMatches(body)) {
    out.add(m.group(1)!.toLowerCase());
  }
  for (final RegExpMatch m in RegExp(r'^\|\s*SHA-256\s*\|\s*`?([0-9a-fA-F]{64})`?\s*\|\s*$', multiLine: true).allMatches(body)) {
    out.add(m.group(1)!.toLowerCase());
  }
  return out;
}

String _plainLine(String s) {
  String t = s.trim();
  t = t.replaceAll(RegExp(r'^#{1,6}\s*'), '').replaceAll(RegExp(r'^[-*+]\s+'), '');
  t = t.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (Match m) => m.group(1)!);
  t = t.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'[*_`]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';

/// (headline, notes) from a release's notes, for people. The headline is the first line of text (a title like
/// "Olive Branch 0.53.0 (preview)" is skipped for the bold line under it when there is one); the notes are the bullets
/// of a "What is in it" section when there is one, else the first lines that follow. Never longer than the manifest's
/// own caps. Control characters are dropped, so a note cannot paint over the screen.
(String, List<String>) githubReadableNotes(String body) {
  final List<String> lines = const LineSplitter()
      .convert(body.replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]'), ''))
      .where((String l) => !RegExp(r'^\s*sha256:', caseSensitive: false).hasMatch(l))
      .toList();
  String headline = '';
  int after = 0;
  for (int i = 0; i < lines.length; i++) {
    final String raw = lines[i].trim();
    if (raw.isEmpty) continue;
    if (raw.startsWith('#')) continue; // a title: the first real line is what people read
    headline = _clip(_plainLine(raw), kMaxHeadlineChars);
    after = i + 1;
    break;
  }
  final List<String> notes = <String>[];
  final int inIt = lines.indexWhere((String l) => RegExp(r'^#{1,6}\s*what is in it', caseSensitive: false).hasMatch(l.trim()));
  if (inIt >= 0) {
    for (int i = inIt + 1; i < lines.length && notes.length < kMaxNotes; i++) {
      final String raw = lines[i].trim();
      if (raw.startsWith('#')) break;
      if (!RegExp(r'^[-*+]\s+').hasMatch(raw)) continue;
      final String n = _plainLine(raw);
      if (n.isNotEmpty) notes.add(_clip(n, kMaxNoteChars));
    }
  } else {
    for (int i = after; i < lines.length && notes.length < 4; i++) {
      final String raw = lines[i].trim();
      if (raw.isEmpty || raw.startsWith('#') || raw.startsWith('|')) continue;
      final String n = _plainLine(raw);
      if (n.isNotEmpty) notes.add(_clip(n, kMaxNoteChars));
    }
  }
  return (headline, notes);
}

DateTime? _time(Object? v) {
  if (v is! String) return null;
  return DateTime.tryParse(v)?.toUtc();
}

/// One entry of the answer, or null when it is a draft, malformed, or has nothing this phone could use. Never throws.
GithubRelease? parseGithubRelease(Object? o, {String owner = kGithubOwner, String repo = kGithubRepo}) {
  try {
    if (o is! Map) return null;
    if (o['draft'] != false) return null; // a draft is not published; anything but an explicit false is not trusted
    final Object? tagRaw = o['tag_name'];
    if (tagRaw is! String) return null;
    final int? code = githubVersionCode(tagRaw);
    if (code == null) return null;
    final String version = tagRaw.substring(1);
    final Object? pre = o['prerelease'];
    if (pre is! bool) return null;
    final DateTime? published = _time(o['published_at']) ?? _time(o['created_at']);
    if (published == null) return null;
    final Object? assets = o['assets'];
    if (assets is! List) return null;
    final String want = githubApkName(version);
    final Uri url = githubApkUri(tagRaw, want, owner: owner, repo: repo);
    Map<Object?, Object?>? asset;
    for (final Object? a in assets) {
      if (a is Map && a['name'] == want) {
        asset = a;
        break;
      }
    }
    if (asset == null) return null; // no file named like this app's file: ignored
    final Object? state = asset['state'];
    if (state != null && state != 'uploaded') return null;
    final Object? bdu = asset['browser_download_url'];
    if (bdu != null && bdu != url.toString()) return null; // the asset must live exactly where the tag says
    final Object? size = asset['size'];
    if (size is! int || size < 1 || size > kMaxApkBytes) return null;
    final Set<String> hashes = githubBodyHashes(o['body'] is String ? o['body'] as String : '');
    final Object? digest = asset['digest'];
    if (digest is String) {
      final String d = digest.toLowerCase();
      if (!d.startsWith('sha256:') || !_hex64.hasMatch(d.substring(7))) return null;
      hashes.add(d.substring(7));
    } else if (digest != null) {
      return null;
    }
    if (hashes.length != 1) return null; // none published, or they disagree
    final (String headline, List<String> notes) = githubReadableNotes(o['body'] is String ? o['body'] as String : '');
    return GithubRelease(
      tag: tagRaw,
      versionName: version,
      versionCode: code,
      prerelease: pre,
      publishedAt: published,
      headline: headline,
      notes: notes,
      apkName: want,
      apkUrl: url,
      apkSize: size,
      sha256: hashes.single,
    );
  } catch (_) {
    return null;
  }
}

/// Every usable release in an answer (JSON text as bytes). Bad entries are skipped one by one; an answer that is not a
/// JSON list is a refusal.
List<GithubRelease> parseGithubReleases(Uint8List body, {String owner = kGithubOwner, String repo = kGithubRepo}) {
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(body));
  } catch (_) {
    throw const UpdateRefusal(UpdateRefusalCode.notJson, 'not JSON');
  }
  if (doc is! List) throw const UpdateRefusal(UpdateRefusalCode.badShape, 'not a list');
  final List<GithubRelease> out = <GithubRelease>[];
  for (final Object? e in doc) {
    final GithubRelease? r = parseGithubRelease(e, owner: owner, repo: repo);
    if (r != null) out.add(r);
  }
  return out;
}

/// The newest release strictly newer than [installedVersionCode], pre-releases included, or null when there is none.
/// Nothing is listed by version: whatever is newest wins, today and for every release after it. Releases newer than the
/// installed build but older than the newest come back as [GithubOffer.between], newest first (at most five).
GithubOffer? pickGithubOffer(List<GithubRelease> releases, int installedVersionCode) {
  final Map<int, GithubRelease> byCode = <int, GithubRelease>{};
  for (final GithubRelease r in releases) {
    if (r.versionCode <= installedVersionCode) continue;
    final GithubRelease? have = byCode[r.versionCode];
    if (have == null || r.publishedAt.isAfter(have.publishedAt)) byCode[r.versionCode] = r;
  }
  if (byCode.isEmpty) return null;
  final List<int> codes = byCode.keys.toList()..sort((int a, int b) => b.compareTo(a));
  return GithubOffer(byCode[codes.first]!, <GithubRelease>[for (final int c in codes.skip(1).take(kGithubMaxBetween)) byCode[c]!]);
}

/// The same release as the engine's own manifest type, so the one download / check / install path serves both sources.
/// It is NOT signed and says so: [UpdateManifest.keyId] is `github`. The file entry has no per-chunk hashes (the
/// whole-file hash is what is checked) and no pinned certificate (Android's same-certificate rule still applies).
UpdateManifest githubAsManifest(GithubRelease r, {required String channel, required DateTime now}) => UpdateManifest(
      app: kUpdateAppId,
      channel: channel,
      versionName: r.versionName,
      versionCode: r.versionCode,
      minSupportedVersionCode: 1,
      sequence: r.versionCode,
      issuedAt: now.toUtc(),
      expiresAt: now.toUtc().add(const Duration(days: 1)),
      publishedAt: r.publishedAt,
      headline: r.headline,
      notes: r.notes,
      apks: <ApkEntry>[
        ApkEntry(
          abi: 'arm64-v8a',
          size: r.apkSize,
          sha256: r.sha256,
          signerSha256: '',
          chunkSize: 0,
          chunks: const <String>[],
          urls: <Uri>[r.apkUrl],
        ),
      ],
      keyId: 'github',
    );
