// The GitHub releases update source: the pure parsing and choosing of releases (a sequence of FUTURE releases, a
// pre-release, a draft, a malformed one, hostile assets), the controller end to end on a fake network (check, notes of
// every release in between, "Later" per version, download, whole-file hash, install hand-off, silence when it fails),
// and the host pinning of the real transport (including a redirect to another host). Nothing here touches a real
// network. MASTERFILE 7.24.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:olive_client/server_transport_policy.dart';
import 'package:olive_client/update_controller.dart';
import 'package:olive_client/update_download.dart';
import 'package:olive_client/update_github.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_platform.dart';
import 'package:olive_client/update_policy.dart';
import 'package:olive_client/update_screens.dart';
import 'package:olive_client/update_store.dart';
import 'package:olive_client/update_transport.dart';

import 'update_support.dart';

const String kApi = 'https://api.github.com/repos/CosmicGrub/Olive-Branch/releases?per_page=20';

/// One release object as GitHub's API describes it.
Map<String, Object?> rel(
  String version, {
  bool draft = false,
  bool prerelease = false,
  Uint8List? apk,
  String? bodyHash,
  String? digest,
  String? body,
  String? assetName,
  String? downloadUrl,
  String? tag,
  String published = '2026-11-22T10:00:00Z',
  bool withHash = true,
}) {
  final Uint8List bytes = apk ?? fakeApk(1000, 3);
  final String hash = bodyHash ?? '';
  final String t = tag ?? 'v$version';
  final String name = assetName ?? 'olive-branch-v$version-arm64-preview.apk';
  return <String, Object?>{
    'tag_name': t,
    'draft': draft,
    'prerelease': prerelease,
    'published_at': published,
    'body': body ??
        '## Olive Branch $version (preview)\n\n**Calmer messages $version**\n\n### What this file is\n\nA debug-signed preview.\n\n'
            '### What is in it\n\n- Messages open faster\n- A quieter morning screen\n\n### The file\n\n| | |\n|---|---|\n'
            '${withHash ? '| SHA-256 | `$hash` |\n' : ''}',
    'assets': <Object?>[
      <String, Object?>{
        'name': name,
        'size': bytes.length,
        'state': 'uploaded',
        'browser_download_url': downloadUrl ?? 'https://github.com/CosmicGrub/Olive-Branch/releases/download/$t/$name',
        if (digest != null) 'digest': digest,
      },
      <String, Object?>{'name': 'SHA256SUMS', 'size': 90, 'state': 'uploaded'},
    ],
  };
}

Uint8List jsonBytes(Object? o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));

void main() {
  // ---- a few payloads whose real hashes are computed up front ----
  late Uint8List apkA, apkB;
  late String shaA, shaB;

  setUpAll(() async {
    apkA = fakeApk(200000, 11);
    apkB = fakeApk(150000, 12);
    shaA = await sha256OfBytes(apkA);
    shaB = await sha256OfBytes(apkB);
  });

  Map<String, Object?> r(String v, {Uint8List? apk, String? hash, bool prerelease = false, bool draft = false, String published = '2026-11-22T10:00:00Z', String? digest}) =>
      rel(v, apk: apk ?? apkA, bodyHash: hash ?? shaA, prerelease: prerelease, draft: draft, published: published, digest: digest);

  List<GithubRelease> parse(List<Object?> list) => parseGithubReleases(jsonBytes(list));

  group('what a version is', () {
    test('the tag vX.Y.Z and the build number major*10000 + minor*100 + patch', () {
      expect(githubVersionCode('v0.51.0'), 5100);
      expect(githubVersionCode('v0.53.1'), 5301);
      expect(githubVersionCode('v1.0.0'), 10000);
      expect(githubVersionCode('v12.34.56'), 123456);
    });

    test('anything that is not exactly that shape is not a version', () {
      for (final String t in <String>['0.51.0', 'V0.51.0', 'v0.51', 'v0.51.0-rc1', 'v0.100.0', 'v0.1.100', 'latest', 'v0.0.0', '', 'v1.0.0 ', 'v01.0.0x']) {
        expect(githubVersionCode(t), isNull, reason: t);
      }
    });

    test('the file name and address are built, never read', () {
      expect(githubApkName('0.53.0'), 'olive-branch-v0.53.0-arm64-preview.apk');
      expect(githubApkUri('v0.53.0', githubApkName('0.53.0')).toString(),
          'https://github.com/CosmicGrub/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk');
      expect(githubReleasesUri().toString(), kApi);
    });
  });

  group('a sequence of future releases', () {
    test('whatever is newest wins, today and for every release after it, pre-releases included, drafts skipped', () {
      final List<Object?> feed = <Object?>[
        r('0.53.0'),
        r('0.53.1'),
        r('1.0.0'),
        r('1.1.0', prerelease: true),
        r('2.0.0', draft: true),
        <String, Object?>{'tag_name': 'nightly', 'draft': false, 'prerelease': true},
        'not even a release',
        42,
        r('0.52.0'),
        r('0.51.0'),
      ];
      final List<GithubRelease> all = parse(feed);
      expect(all.map((GithubRelease x) => x.versionName), <String>['0.53.0', '0.53.1', '1.0.0', '1.1.0', '0.52.0', '0.51.0']);

      GithubOffer? o = pickGithubOffer(all, 5100); // installed 0.51.0
      expect(o!.newest.versionName, '1.1.0');
      expect(o.newest.prerelease, isTrue);
      expect(o.between.map((GithubRelease x) => x.versionName), <String>['1.0.0', '0.53.1', '0.53.0', '0.52.0']);

      o = pickGithubOffer(all, 5301); // installed 0.53.1: only the newer ones
      expect(o!.newest.versionName, '1.1.0');
      expect(o.between.map((GithubRelease x) => x.versionName), <String>['1.0.0']);

      o = pickGithubOffer(all, 10000); // installed 1.0.0
      expect(o!.newest.versionName, '1.1.0');
      expect(o.between, isEmpty);

      expect(pickGithubOffer(all, 10100), isNull, reason: 'equal is not newer');
      expect(pickGithubOffer(all, 10101), isNull, reason: 'older is never offered');
    });

    test('with no pre-release the stable one is the newest; a release nobody coded for is picked up automatically', () {
      final List<GithubRelease> all = parse(<Object?>[r('0.53.0'), r('0.53.1'), r('1.0.0')]);
      expect(pickGithubOffer(all, 5100)!.newest.versionName, '1.0.0');
      final List<GithubRelease> later = parse(<Object?>[r('0.53.0'), r('0.53.1'), r('1.0.0'), r('7.31.9')]);
      expect(pickGithubOffer(later, 5100)!.newest.versionName, '7.31.9');
      expect(pickGithubOffer(later, 5100)!.newest.versionCode, 73109);
    });

    test('the order of the answer does not matter, and a repeated version keeps the later publication', () {
      final List<GithubRelease> all = parse(<Object?>[
        r('1.0.0', published: '2026-12-01T00:00:00Z'),
        r('0.53.0'),
        r('1.0.0', published: '2026-12-02T00:00:00Z', apk: apkB, hash: shaB),
      ]);
      final GithubOffer o = pickGithubOffer(all, 5100)!;
      expect(o.newest.sha256, shaB);
      expect(o.between.map((GithubRelease x) => x.versionName), <String>['0.53.0']);
    });

    test('at most five releases in between are listed', () {
      final List<GithubRelease> all = parse(<Object?>[for (int p = 1; p <= 9; p++) r('0.51.$p')]);
      final GithubOffer o = pickGithubOffer(all, 5100)!;
      expect(o.newest.versionName, '0.51.9');
      expect(o.between.length, 5);
    });
  });

  group('a release is ignored unless every check passes', () {
    test('a draft, and anything where draft is not explicitly false', () {
      expect(parse(<Object?>[r('0.53.0', draft: true)]), isEmpty);
      final Map<String, Object?> odd = r('0.53.0')..remove('draft');
      expect(parse(<Object?>[odd]), isEmpty);
    });

    test('an asset not named like this app\'s file for this tag', () {
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, bodyHash: shaA, assetName: 'olive-branch-v0.53.0-x86_64-preview.apk')]), isEmpty);
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, bodyHash: shaA, assetName: 'olive-branch-v0.52.0-arm64-preview.apk')]), isEmpty);
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, bodyHash: shaA, assetName: 'evil.apk')]), isEmpty);
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, bodyHash: shaA, assetName: '../olive-branch-v0.53.0-arm64-preview.apk')]), isEmpty);
    });

    test('an asset that claims to live anywhere but the fixed repository and tag', () {
      for (final String u in <String>[
        'https://evil.example/CosmicGrub/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk',
        'https://github.com/Someone/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk',
        'http://github.com/CosmicGrub/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk',
        'https://github.com/CosmicGrub/Olive-Branch/releases/download/v0.52.0/olive-branch-v0.53.0-arm64-preview.apk',
      ]) {
        expect(parse(<Object?>[rel('0.53.0', apk: apkA, bodyHash: shaA, downloadUrl: u)]), isEmpty, reason: u);
      }
    });

    test('the address that is used is built from the fixed repository, whatever else the answer says', () {
      final GithubRelease g = parse(<Object?>[r('0.53.0')]).single;
      expect(g.apkUrl.toString(),
          'https://github.com/CosmicGrub/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk');
    });

    test('a hash that is missing, malformed, or contradicted', () {
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, withHash: false)]), isEmpty, reason: 'nothing published');
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, bodyHash: 'abc123')]), isEmpty, reason: 'not 64 hex');
      expect(parse(<Object?>[r('0.53.0', digest: 'sha256:${'0' * 64}')]), isEmpty, reason: 'the digest disagrees with the notes');
      expect(parse(<Object?>[r('0.53.0', digest: 'md5:abcdef')]), isEmpty);
      expect(parse(<Object?>[r('0.53.0', digest: 'sha256:xyz')]), isEmpty);
      expect(parse(<Object?>[r('0.53.0', digest: 'sha256:$shaA')]).single.sha256, shaA, reason: 'agreeing sources are fine');
    });

    test('GitHub\'s own digest is enough when the notes carry none, and the machine line works too', () {
      expect(parse(<Object?>[rel('0.53.0', apk: apkA, withHash: false, digest: 'sha256:$shaA')]).single.sha256, shaA);
      final GithubRelease line = parse(<Object?>[rel('0.53.0', apk: apkA, body: '## x\n\nHello\n\nsha256: $shaA\n')]).single;
      expect(line.sha256, shaA);
      expect(line.headline, 'Hello');
    });

    test('a size that is absent, zero, or beyond the cap', () {
      for (final Object? s in <Object?>[null, 0, -1, kMaxApkBytes + 1, '100', 1.5]) {
        final Map<String, Object?> x = r('0.53.0');
        ((x['assets']! as List<Object?>).first! as Map<String, Object?>)['size'] = s;
        expect(parse(<Object?>[x]), isEmpty, reason: '$s');
      }
    });

    test('an asset that is not finished uploading', () {
      final Map<String, Object?> x = r('0.53.0');
      ((x['assets']! as List<Object?>).first! as Map<String, Object?>)['state'] = 'starter';
      expect(parse(<Object?>[x]), isEmpty);
    });

    test('an answer that is not a list, or not JSON, is refused', () {
      expect(() => parseGithubReleases(jsonBytes(<String, Object?>{'message': 'API rate limit exceeded'})),
          throwsA(isA<UpdateRefusal>().having((UpdateRefusal e) => e.code, 'code', UpdateRefusalCode.badShape)));
      expect(() => parseGithubReleases(Uint8List.fromList(utf8.encode('<html>'))),
          throwsA(isA<UpdateRefusal>().having((UpdateRefusal e) => e.code, 'code', UpdateRefusalCode.notJson)));
      expect(() => parseGithubReleases(Uint8List.fromList(<int>[0xff, 0xfe, 0x00])), throwsA(isA<UpdateRefusal>()));
    });

    test('a wholly hostile entry never throws', () {
      expect(parse(<Object?>[<String, Object?>{'tag_name': 5}, <String, Object?>{'assets': 'x', 'tag_name': 'v0.60.0', 'draft': false}, null, <Object?>[]]), isEmpty);
    });
  });

  group('release notes in plain words', () {
    test('the headline is the first line of text; the notes are the "what is in it" bullets', () {
      final GithubRelease g = parse(<Object?>[r('0.53.0')]).single;
      expect(g.headline, 'Calmer messages 0.53.0');
      expect(g.notes, <String>['Messages open faster', 'A quieter morning screen']);
    });

    test('with no such section the first lines that follow are used, and markdown is dropped', () {
      final (String h, List<String> n) = githubReadableNotes('# Title\n\n**Hello** [world](https://x.example/a) `code`\n\nSecond <b>line</b>\n\n| a | b |\nThird\n');
      expect(h, 'Hello world code');
      expect(n, <String>['Second line', 'Third']);
    });

    test('length and control characters are bounded', () {
      final (String h, List<String> n) = githubReadableNotes('${'x' * 500}\n\n${'y' * 900}\u0007\u001b[2J\n');
      expect(h.length, lessThanOrEqualTo(kMaxHeadlineChars));
      expect(n.single.length, lessThanOrEqualTo(kMaxNoteChars));
      expect(n.single.contains('\u0007'), isFalse);
      expect(n.single.contains('\u001b'), isFalse);
    });

    test('the sha256 line never shows as a note', () {
      final (String _, List<String> n) = githubReadableNotes('Hi\n\nsha256: ${'a' * 64}\n\nBye\n');
      expect(n, <String>['Bye']);
    });
  });

  group('the engine\'s own decision accepts the release as a manifest, and refuses an older one', () {
    test('strictly newer only', () {
      final GithubRelease g = parse(<Object?>[r('0.53.0')]).single;
      final UpdateManifest m = githubAsManifest(g, channel: 'stable', now: kNow);
      UpdateContext ctx(int installed) => UpdateContext(channel: 'stable', installedVersionCode: installed, now: kNow, deviceAbis: const <String>['arm64-v8a']);
      expect(decideUpdate(m, ctx(5200)).status, UpdateStatus.updateAvailable);
      expect(decideUpdate(m, ctx(5300)).status, UpdateStatus.upToDate);
      expect(() => decideUpdate(m, ctx(5301)), throwsA(isA<UpdateRefusal>()));
      expect(m.keyId, 'github');
      expect(m.apks.single.chunks, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('the controller on a fake network', () {
    late Directory dir;
    late FakeTransport net;
    late FakeInstaller installer;
    late FixedEnvironment env;
    late MemoryUpdateStateRepository repo;
    late DateTime clock;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('olive_gh_test_');
      net = FakeTransport();
      installer = FakeInstaller();
      env = FixedEnvironment(wifiPhone());
      repo = MemoryUpdateStateRepository();
      clock = kNow;
    });
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    AppUpdater make({bool github = true, UpdateConfig? config, UpdateStateRepository? repository, bool installerOn = true}) => AppUpdater(
          environment: env,
          config: config ?? UpdateConfig(trust: UpdateTrust(const <String, List<int>>{}), githubEnabled: github),
          repository: repository ?? repo,
          transport: net,
          githubTransport: net,
          staging: UpdateStaging(Directory('${dir.path}${Platform.pathSeparator}olive_updates')),
          direct: installerOn ? installer : null,
          safety: UpdateSafety(),
          clock: () => clock,
          sleep: (Duration d) async {},
        );

    void feed(List<Object?> releases) => net.manifests[kApi] = jsonBytes(releases);
    void serve(Uint8List apk, String version) =>
        net.files['https://github.com/CosmicGrub/Olive-Branch/releases/download/v$version/olive-branch-v$version-arm64-preview.apk'] = FileBehavior(apk);

    test('on by default in the direct build with no setup; off when switched off; a signed source with a key wins', () async {
      AppUpdater u = make();
      await u.start();
      expect(u.enabled, isTrue);
      expect(u.usesGithub, isTrue);
      u = make(github: false);
      await u.start();
      expect(u.enabled, isFalse);
      final TestSigner who = await TestSigner.create();
      u = make(config: UpdateConfig(manifestUrls: const <String>[kManifestUrl], trust: who.trust, githubEnabled: true));
      await u.start();
      expect(u.usesGithub, isFalse, reason: 'the signed manifest is the stronger path and is used when it can be');
      expect(u.enabled, isTrue);
    });

    test('a check asks only the fixed GitHub address, finds the newest, and lists the ones in between with their notes', () async {
      feed(<Object?>[r('0.53.0'), r('0.53.1'), r('1.0.0'), r('0.51.0'), r('2.0.0', draft: true)]);
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      expect(net.getLog, <String>[kApi]);
      expect(u.phase, UpdatePhase.available);
      expect(u.manifest!.versionName, '1.0.0');
      expect(u.manifest!.headline, 'Calmer messages 1.0.0');
      expect(u.missedReleases.map((GithubRelease x) => x.versionName), <String>['0.53.1', '0.53.0']);
      expect(u.missedReleases.first.notes, isNotEmpty);
      expect(u.bannerWanted, isTrue);
      expect(u.state.lastResult, 'ok');
      expect(u.state.highestSeenSequence, isNull, reason: 'GitHub never writes the signed path\'s replay counter');
    });

    test('up to date when nothing is newer, including an equal version', () async {
      feed(<Object?>[r('0.51.0'), r('0.50.0')]);
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      expect(u.phase, UpdatePhase.upToDate);
      expect(u.bannerWanted, isFalse);
    });

    test('the next release after this one is found by the same code (nothing is listed by version)', () async {
      feed(<Object?>[r('0.53.0')]);
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      expect(u.manifest!.versionName, '0.53.0');
      feed(<Object?>[r('0.53.0'), r('0.53.1'), r('1.0.0', prerelease: true)]);
      await u.checkNow();
      expect(u.manifest!.versionName, '1.0.0');
      expect(u.offerIsPrerelease, isTrue);
      expect(u.missedReleases.map((GithubRelease x) => x.versionName), <String>['0.53.1', '0.53.0']);
    });

    test('"Later" hides one version only: a still-newer release always shows', () async {
      feed(<Object?>[r('0.53.0')]);
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      expect(u.bannerWanted, isTrue);
      await u.later();
      expect(u.bannerWanted, isFalse);
      await u.checkNow();
      expect(u.bannerWanted, isFalse, reason: 'the same release stays dismissed');
      feed(<Object?>[r('0.53.0'), r('0.53.1')]);
      await u.checkNow();
      expect(u.manifest!.versionName, '0.53.1');
      expect(u.bannerWanted, isTrue);
    });

    test('the polite schedule: at most once in six hours at start, and the button always works', () async {
      feed(<Object?>[r('0.53.0')]);
      final AppUpdater u = make();
      await u.start();
      await u.maybeCheckAtOpen();
      await u.maybeCheckAtOpen();
      expect(net.getLog.length, 1);
      clock = clock.add(const Duration(hours: 5, minutes: 59));
      await u.maybeCheckAtOpen();
      expect(net.getLog.length, 1);
      clock = clock.add(const Duration(minutes: 2));
      await u.maybeCheckAtOpen();
      expect(net.getLog.length, 2);
      await u.checkNow();
      expect(net.getLog.length, 3);
    });

    test('automatic checks never run when an adult turned them off, offline, on mobile data or with Data Saver', () async {
      feed(<Object?>[r('0.53.0')]);
      await repo.save(const UpdateState(autoCheck: false));
      AppUpdater u = make();
      await u.start();
      await u.maybeCheckAtOpen();
      expect(net.getLog, isEmpty);
      await repo.save(const UpdateState());
      for (final UpdateEnvironment e in <UpdateEnvironment>[
        wifiPhone(network: NetworkKind.none),
        wifiPhone(network: NetworkKind.cellular, metered: true),
        wifiPhone(dataSaver: true),
      ]) {
        env.value = e;
        u = make();
        await u.start();
        await u.maybeCheckAtOpen();
        expect(net.getLog, isEmpty);
      }
    });

    test('a failure in the background is silent; the button says it plainly, once, and nothing crashes', () async {
      net.manifestErrors[kApi] = const UpdateRefusal(UpdateRefusalCode.offline, 'no connection');
      final AppUpdater u = make();
      await u.start();
      await u.maybeCheckAtOpen();
      expect(u.failure, isNull, reason: 'silent unless a grown-up asked');
      expect(u.phase, UpdatePhase.idle);
      await u.checkNow();
      expect(u.failure, UpdateRefusalCode.offline);
      expect(u.phase, UpdatePhase.idle);
      net.manifests[kApi] = Uint8List.fromList(utf8.encode('rate limited'));
      net.manifestErrors.clear();
      await u.checkNow();
      expect(u.failure, UpdateRefusalCode.notJson);
      net.manifests.remove(kApi); // a 404
      await u.checkNow();
      expect(u.failure, UpdateRefusalCode.httpError);
    });

    test('a failed check never takes away an update already found', () async {
      feed(<Object?>[r('0.53.0')]);
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      net.manifestErrors[kApi] = const UpdateRefusal(UpdateRefusalCode.offline);
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      expect(u.manifest!.versionName, '0.53.0');
    });

    test('Update now: downloads with progress, checks size and SHA-256, hands over to the installer, which asks the person', () async {
      feed(<Object?>[r('0.53.0')]);
      serve(apkA, '0.53.0');
      installer.inspectedVersionCode = 5300;
      final List<double> seen = <double>[];
      final AppUpdater u = make();
      u.addListener(() {
        if (u.progress != null) seen.add(u.progress!.fraction);
      });
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
      expect(net.openLog.map(((String, int?) e) => e.$1), <String>[
        'https://github.com/CosmicGrub/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk',
      ]);
      expect(installer.installs, isEmpty, reason: 'never auto-installs');
      await u.install();
      expect(u.phase, UpdatePhase.installing);
      expect(installer.installs.single['sha256'], shaA);
      expect(installer.installs.single['size'], apkA.length);
      expect(installer.installs.single['versionCode'], 5300);
    });

    test('a file that is not what the release said is deleted and never handed over', () async {
      feed(<Object?>[r('0.53.0')]);
      final Uint8List bad = Uint8List.fromList(apkA)..[1000] ^= 0xff;
      serve(bad, '0.53.0');
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.hashMismatch);
      expect(File('${dir.path}${Platform.pathSeparator}olive_updates${Platform.pathSeparator}$shaA.apk').existsSync(), isFalse);
      expect(File('${dir.path}${Platform.pathSeparator}olive_updates${Platform.pathSeparator}$shaA.part').existsSync(), isFalse);
      await u.install();
      expect(installer.installs, isEmpty);
    });

    test('a file longer or shorter than the release said is refused', () async {
      feed(<Object?>[r('0.53.0')]);
      serve(Uint8List.fromList(<int>[...apkA, 1, 2, 3]), '0.53.0');
      AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.tooMuchData);
      serve(apkA.sublist(0, apkA.length - 10), '0.53.0');
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.failed);
      expect(installer.installs, isEmpty);
    });

    test('a dropped connection continues from where it stopped and still ends with a whole-file check', () async {
      feed(<Object?>[r('0.53.0')]);
      net.files['https://github.com/CosmicGrub/Olive-Branch/releases/download/v0.53.0/olive-branch-v0.53.0-arm64-preview.apk'] =
          FileBehavior(apkA, dropAfter: 70000);
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
      expect(net.openLog.length, 2);
      expect(net.openLog.last.$2, 70000);
    });

    test('the file must be signed like the installed app, and a bad answer from Android deletes it', () async {
      feed(<Object?>[r('0.53.0')]);
      serve(apkA, '0.53.0');
      installer.inspectedVersionCode = 5300;
      installer.signers = <String>[certHash('someone else')];
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      await u.install();
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.certMismatch);
      expect(installer.installs, isEmpty);
    });

    test('a file whose own version is not the promised one, or not newer, is refused by the last look', () async {
      feed(<Object?>[r('0.53.0')]);
      serve(apkA, '0.53.0');
      installer.inspectedVersionCode = 5100; // it is really the installed version
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      await u.install();
      expect(u.failure, UpdateRefusalCode.apkMismatch);
      expect(installer.installs, isEmpty);
    });

    test('an update found and downloaded survives a restart with no network, and is installable', () async {
      feed(<Object?>[r('0.53.0'), r('0.52.0')]);
      serve(apkA, '0.53.0');
      installer.inspectedVersionCode = 5300;
      AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
      u.dispose();
      net.manifests.clear();
      net.files.clear();
      u = make();
      await u.start();
      expect(u.phase, UpdatePhase.ready);
      expect(u.manifest!.versionName, '0.53.0');
      expect(u.missedReleases.map((GithubRelease x) => x.versionName), <String>['0.52.0']);
      expect(net.getLog.length, 1, reason: 'the restart asked nothing');
      await u.install();
      expect(installer.installs.single['sha256'], shaA);
    });

    test('a found update is dropped on restart once the installed version has caught up with it', () async {
      feed(<Object?>[r('0.53.0')]);
      AppUpdater u = make();
      await u.start();
      await u.checkNow();
      u.dispose();
      env.value = wifiPhone(versionCode: 5300, versionName: '0.53.0');
      u = make();
      await u.start();
      expect(u.phase, UpdatePhase.idle);
      expect(u.manifest, isNull);
    });

    test('nothing is handed over to another phone (that path needs a signed manifest)', () async {
      feed(<Object?>[r('0.53.0')]);
      serve(apkA, '0.53.0');
      final AppUpdater u = make();
      await u.start();
      await u.checkNow();
      await u.downloadNow();
      expect(await u.stagedForHandover(), isNull);
    });

    test('no installer in this build: the feature is absent and asks nothing', () async {
      final AppUpdater u = make(installerOn: false);
      await u.start();
      expect(u.enabled, isFalse);
      await u.checkNow();
      expect(net.getLog, isEmpty);
    });
  });


  // ---------------------------------------------------------------------------------------------------------------
  group('what a grown-up sees', () {
    Future<(AppUpdater, FakeTransport, Directory)> prepare(WidgetTester t, {List<Object?>? feedWith, UpdateRefusal? error, bool manual = true}) async {
      late AppUpdater u;
      late FakeTransport net;
      late Directory dir;
      await t.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('olive_gh_ui_');
        net = FakeTransport();
        if (feedWith != null) net.manifests[kApi] = jsonBytes(feedWith);
        if (error != null) net.manifestErrors[kApi] = error;
        u = AppUpdater(
          environment: FixedEnvironment(wifiPhone()),
          config: UpdateConfig(trust: UpdateTrust(const <String, List<int>>{}), githubEnabled: true),
          repository: MemoryUpdateStateRepository(),
          transport: net,
          githubTransport: net,
          staging: UpdateStaging(Directory('${dir.path}${Platform.pathSeparator}olive_updates')),
          direct: FakeInstaller(),
          safety: UpdateSafety(),
          clock: () => kNow,
          sleep: (Duration d) async {},
        );
        await u.start();
        await u.checkNow(manual: manual);
      });
      addTearDown(u.dispose);
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      return (u, net, dir);
    }

    Future<void> show(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(420, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: w));
      await t.pump();
    }

    testWidgets('the banner says "Update available: X.Y.Z"; the page shows its notes, those in between, and the honest words', (t) async {
      final (AppUpdater u, FakeTransport _, Directory _) = await prepare(t, feedWith: <Object?>[r('0.53.0'), r('0.53.1'), r('1.0.0', prerelease: true)]);
      await show(t, UpdateScope(updater: u, child: const Scaffold(body: UpdateBanner())));
      expect(find.text('Update available: 1.0.0'), findsOneWidget);
      await show(t, AppUpdatesScreen(updater: u, now: () => kNow));
      expect(find.byKey(const Key('updateVersionLine')), findsOneWidget);
      expect(find.text('Calmer messages 1.0.0'), findsOneWidget);
      expect(find.text('• Messages open faster'), findsWidgets);
      expect(find.byKey(const Key('updatePreviewNote')), findsOneWidget);
      expect(find.byKey(const Key('updateMissed')), findsOneWidget);
      expect(find.text('Olive 0.53.1'), findsOneWidget);
      expect(find.text('Olive 0.53.0'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.byKey(const Key('updateGithubHonesty')), findsOneWidget);
      expect(find.textContaining('as trustworthy as that GitHub account'), findsOneWidget);
      expect(find.textContaining('same way'), findsOneWidget);
      expect(find.byKey(const Key('updateSourceField')), findsNothing, reason: 'the signed-manifest source box is not for this source');
    });

    testWidgets('up to date: "Check for updates" is the button, and nothing is announced', (t) async {
      final (AppUpdater u, FakeTransport _, Directory _) = await prepare(t, feedWith: <Object?>[r('0.51.0')]);
      await show(t, UpdateScope(updater: u, child: const Scaffold(body: UpdateBanner())));
      expect(find.byType(Card), findsNothing);
      await show(t, AppUpdatesScreen(updater: u, now: () => kNow));
      expect(find.text('Olive is up to date'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
    });

    testWidgets('a check the button asked for that could not finish says so plainly; a quiet one says nothing', (t) async {
      final (AppUpdater u, FakeTransport _, Directory _) = await prepare(t, error: const UpdateRefusal(UpdateRefusalCode.offline));
      await show(t, AppUpdatesScreen(updater: u, now: () => kNow));
      expect(find.text('Could not check right now. Nothing was changed.'), findsOneWidget);
      final (AppUpdater q, FakeTransport _, Directory _) = await prepare(t, error: const UpdateRefusal(UpdateRefusalCode.offline), manual: false);
      await show(t, AppUpdatesScreen(updater: q, now: () => kNow));
      expect(find.byKey(const Key('updateFailure')), findsNothing);
      await show(t, UpdateScope(updater: q, child: const Scaffold(body: UpdateBanner())));
      expect(find.byType(Card), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('the real transport, pinned to GitHub', () {
    final Uri api = githubReleasesUri();
    final Uri file = githubApkUri('v0.53.0', githubApkName('0.53.0'));

    HttpUpdateTransport pinned(http.Client c) => HttpUpdateTransport(
          client: c,
          policy: const OliveTransportPolicy(release: true),
          getHosts: kGithubApiHosts,
          openHosts: kGithubDownloadHosts,
        );

    http.StreamedResponse reply(int status, {List<int> body = const <int>[], Map<String, String> headers = const <String, String>{}}) =>
        http.StreamedResponse(Stream<List<int>>.value(body), status, headers: headers, contentLength: body.length);

    test('the release list is read from api.github.com, and only up to the cap', () async {
      final List<Uri> asked = <Uri>[];
      final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming((http.BaseRequest q, Stream<List<int>> b) async {
        asked.add(q.url);
        expect(q.headers.containsKey('Authorization'), isFalse, reason: 'no token, no credential, ever');
        expect(q.headers.containsKey('Cookie'), isFalse);
        return reply(200, body: utf8.encode('[]'));
      }));
      final UpdateResponse res = await t.get(api, maxBytes: kMaxGithubBytes);
      expect(res.body, utf8.encode('[]'));
      expect(asked.single.host, 'api.github.com');
      final HttpUpdateTransport big = pinned(http_testing.MockClient.streaming(
          (http.BaseRequest q, Stream<List<int>> b) async => reply(200, body: List<int>.filled(300, 0x20))));
      await expectLater(big.get(api, maxBytes: 100), throwsA(isA<UpdateRefusal>().having((UpdateRefusal e) => e.code, 'code', UpdateRefusalCode.tooMuchData)));
    });

    test('a redirect of the file download to GitHub\'s own storage host is followed', () async {
      final List<Uri> asked = <Uri>[];
      final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming((http.BaseRequest q, Stream<List<int>> b) async {
        asked.add(q.url);
        if (q.url.host == 'github.com') {
          return reply(302, headers: <String, String>{'location': 'https://objects.githubusercontent.com/github-production-release-asset/abc?x=1'});
        }
        return reply(200, body: <int>[1, 2, 3]);
      }));
      final UpdateStream s = await t.open(file);
      expect(await s.body.expand((List<int> x) => x).toList(), <int>[1, 2, 3]);
      expect(asked.map((Uri u) => u.host), <String>['github.com', 'objects.githubusercontent.com']);
    });

    test('a redirect to any other host is refused, and nothing is requested from it', () async {
      final List<Uri> asked = <Uri>[];
      final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming((http.BaseRequest q, Stream<List<int>> b) async {
        asked.add(q.url);
        return reply(302, headers: <String, String>{'location': 'https://evil.example/olive.apk'});
      }));
      await expectLater(t.open(file), throwsA(isA<UpdateRefusal>().having((UpdateRefusal e) => e.code, 'code', UpdateRefusalCode.badRedirect)));
      expect(asked.map((Uri u) => u.host), <String>['github.com']);
    });

    test('a redirect to http, to a lookalike host, to another port, or with credentials is refused', () async {
      for (final String loc in <String>[
        'http://objects.githubusercontent.com/x',
        'https://objects.githubusercontent.com.evil.example/x',
        'https://notgithub.com/x',
        'https://github.com:8443/x',
        'https://user:pw@github.com/x',
        'https://api.github.com.evil.example/x',
      ]) {
        final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming(
            (http.BaseRequest q, Stream<List<int>> b) async => reply(302, headers: <String, String>{'location': loc})));
        await expectLater(t.open(file), throwsA(isA<UpdateRefusal>()), reason: loc);
      }
    });

    test('the release list may not be redirected anywhere but api.github.com', () async {
      final List<Uri> asked = <Uri>[];
      final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming((http.BaseRequest q, Stream<List<int>> b) async {
        asked.add(q.url);
        return reply(301, headers: <String, String>{'location': 'https://github.com/CosmicGrub/Olive-Branch/releases'});
      }));
      await expectLater(t.get(api, maxBytes: kMaxGithubBytes), throwsA(isA<UpdateRefusal>()));
      expect(asked.length, 1);
    });

    test('the first address must be a pinned host too', () async {
      final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming(
          (http.BaseRequest q, Stream<List<int>> b) async => reply(200, body: <int>[1])));
      await expectLater(t.get(Uri.https('evil.example', '/repos/CosmicGrub/Olive-Branch/releases'), maxBytes: 100),
          throwsA(isA<UpdateRefusal>().having((UpdateRefusal e) => e.code, 'code', UpdateRefusalCode.badUrl)));
      await expectLater(t.open(Uri.parse('http://github.com/x')), throwsA(isA<UpdateRefusal>()));
    });

    test('a server error is a refusal, never a crash', () async {
      final HttpUpdateTransport t = pinned(http_testing.MockClient.streaming(
          (http.BaseRequest q, Stream<List<int>> b) async => reply(403, body: utf8.encode('{"message":"rate limit"}'))));
      await expectLater(t.get(api, maxBytes: kMaxGithubBytes),
          throwsA(isA<UpdateRefusal>().having((UpdateRefusal e) => e.code, 'code', UpdateRefusalCode.httpError)));
    });
  });
}
