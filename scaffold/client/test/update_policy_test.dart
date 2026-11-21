// What a verified manifest means for the app that is installed: app, channel, clock, replay, rollback, chip, and the
// minimum-supported notice. MASTERFILE 7.24.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_policy.dart';

import 'update_support.dart';

void main() {
  late TestSigner s;
  setUp(() async => s = await TestSigner.create());

  Future<UpdateManifest> manifest(Map<String, Object?> Function(Map<String, Object?>)? tweak, {Map<String, Object?>? base}) async {
    Map<String, Object?> d = base ?? await draftFor(fakeApk(70000));
    if (tweak != null) d = tweak(d);
    return (await verifyManifestDocument(encodeDoc(await s.sign(d)), s.trust)).manifest;
  }

  UpdateContext ctx({
    int installed = 5100,
    String channel = 'stable',
    int? seen,
    DateTime? seenAt,
    DateTime? now,
    List<String> abis = const <String>['arm64-v8a'],
    bool requireApk = true,
  }) =>
      UpdateContext(
        appId: kUpdateAppId,
        channel: channel,
        installedVersionCode: installed,
        now: now ?? kNow,
        highestSeenVersionCode: seen,
        highestSeenPublishedAt: seenAt,
        deviceAbis: abis,
        requireApk: requireApk,
      );

  UpdateRefusalCode? refusal(UpdateManifest m, UpdateContext c) {
    try {
      decideUpdate(m, c);
      return null;
    } on UpdateRefusal catch (e) {
      return e.code;
    }
  }

  test('a strictly newer version is an update; the same version is "up to date"', () async {
    final UpdateManifest m = await manifest(null);
    expect(decideUpdate(m, ctx()).status, UpdateStatus.updateAvailable);
    expect(decideUpdate(m, ctx(installed: 5200)).status, UpdateStatus.upToDate);
  });

  test('rollback: a manifest older than what is installed is refused', () async {
    final UpdateManifest m = await manifest(null);
    expect(refusal(m, ctx(installed: 5300)), UpdateRefusalCode.rollback);
  });

  test('replay: a manifest older than one already accepted is refused, however well signed', () async {
    final UpdateManifest m = await manifest(null);
    expect(refusal(m, ctx(seen: 5300)), UpdateRefusalCode.replayed);
    expect(refusal(m, ctx(seen: 5200)), isNull);
    // The same version served again, but an OLDER copy of it than the one already accepted.
    expect(refusal(m, ctx(seen: 5200, seenAt: m.publishedAt.add(const Duration(days: 1)))), UpdateRefusalCode.replayed);
    expect(refusal(m, ctx(seen: 5200, seenAt: m.publishedAt)), isNull);
  });

  test('a manifest from a different channel is refused', () async {
    final UpdateManifest beta = await manifest((Map<String, Object?> d) => d..['channel'] = 'beta');
    expect(refusal(beta, ctx()), UpdateRefusalCode.wrongChannel);
    expect(refusal(beta, ctx(channel: 'beta')), isNull);
  });

  test('a manifest for another app is refused', () async {
    final UpdateManifest other = await manifest((Map<String, Object?> d) => d..['appId'] = 'com.example.other');
    expect(refusal(other, ctx()), UpdateRefusalCode.wrongApp);
  });

  test('the clock: not from the future (a day of slack), not past validUntil', () async {
    final UpdateManifest m = await manifest(null);
    expect(refusal(m, ctx(now: DateTime.utc(2026, 11, 20, 11))), isNull, reason: 'within the day of slack');
    expect(refusal(m, ctx(now: DateTime.utc(2026, 11, 19))), UpdateRefusalCode.future);
    expect(refusal(m, ctx(now: DateTime.utc(2027, 5, 22))), UpdateRefusalCode.expired);
    final UpdateManifest forever = await manifest((Map<String, Object?> d) => d..remove('validUntil'));
    expect(refusal(forever, ctx(now: DateTime.utc(2030))), isNull);
  });

  test('a file for another chip is refused; a universal file runs anywhere; Play needs no file', () async {
    final UpdateManifest x86 = await manifest((Map<String, Object?> d) {
      (d['apk']! as Map<String, Object?>)['abi'] = 'x86_64';
      return d;
    });
    expect(refusal(x86, ctx()), UpdateRefusalCode.noApkForDevice);
    expect(refusal(x86, ctx(requireApk: false)), isNull);
    final UpdateManifest uni = await manifest((Map<String, Object?> d) {
      (d['apk']! as Map<String, Object?>)['abi'] = 'universal';
      return d;
    });
    expect(refusal(uni, ctx(abis: const <String>[])), isNull);
    expect(abiAccepted('arm64-v8a', const <String>[]), isFalse);
  });

  test('the minimum: below it the verdict says so; at or above it does not; an update is still an update', () async {
    final UpdateManifest m = await manifest((Map<String, Object?> d) => d..['minSupportedVersionCode'] = 5150);
    final UpdateVerdict below = decideUpdate(m, ctx(installed: 5100));
    expect(below.belowMinimum, isTrue);
    expect(below.status, UpdateStatus.updateAvailable);
    expect(decideUpdate(m, ctx(installed: 5150)).belowMinimum, isFalse);
    expect(decideUpdate(m, ctx(installed: 5200)).belowMinimum, isFalse);
  });

  test('strictlyNewer', () {
    expect(strictlyNewer(5201, 5200), isTrue);
    expect(strictlyNewer(5200, 5200), isFalse);
    expect(strictlyNewer(5199, 5200), isFalse);
  });
}
