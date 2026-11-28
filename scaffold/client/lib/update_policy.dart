// OLIVE BRANCH — what a verified manifest MEANS for the app that is installed: is it for this app and this channel,
// is it fresh, is it newer, may it be taken, which file is for this phone's chip, is this build still supported. Pure
// functions; no network, no storage. Verified headless (test/update_policy_test.dart, and the vectors in
// test/update_manifest_test.dart). MASTERFILE 7.24.
//
// The order is the spec's (docs/UPDATE-MANIFEST.md, "What the app does with a manifest, in order"), and the same as
// `verifyDocument` in tools/update/manifest_lib.mjs, so the two cannot disagree about a document: app, channel, clock
// (not issued in the future, not past expiresAt), replay (a sequence lower than one already accepted), rollback (a
// versionCode lower than what is installed), then whether there is a file for this phone's chip. Equal is not an error:
// an equal versionCode is "up to date", and the same sequence again is a harmless re-fetch.
import 'update_manifest.dart';

/// Everything about this phone and this run that the decision needs.
class UpdateContext {
  const UpdateContext({
    required this.channel,
    required this.installedVersionCode,
    required this.now,
    this.highestSeenSequence,
    this.deviceAbis = const <String>[],
    this.requireApk = true,
  });

  final String channel;
  final int installedVersionCode;

  /// The largest sequence of any manifest this phone has already accepted. A manifest with a lower one is a replay,
  /// however well it is signed.
  final int? highestSeenSequence;
  final DateTime now;

  /// The chips this phone runs, best first (`arm64-v8a`, ...). Empty means "unknown": only a universal file is taken.
  final List<String> deviceAbis;

  /// The Play flavor never downloads the file, so it does not need one for its chip.
  final bool requireApk;
}

enum UpdateStatus {
  /// The installed version is the newest one the manifest knows.
  upToDate,

  /// The manifest names a strictly newer version.
  updateAvailable,
}

class UpdateVerdict {
  const UpdateVerdict(this.status, this.manifest, this.apk, {required this.belowMinimum});
  final UpdateStatus status;
  final UpdateManifest manifest;

  /// The file for this phone (null for the Play flavor, which never downloads one).
  final ApkEntry? apk;

  /// The installed build is older than the manifest's minSupportedVersionCode. Adults are asked, kindly, to update.
  /// Nothing is ever locked or removed because of it (update_controller.dart only ever adds a notice).
  final bool belowMinimum;
}

/// Decides what [m] means. Throws [UpdateRefusal] with a stable code for everything that must be ignored.
UpdateVerdict decideUpdate(UpdateManifest m, UpdateContext c) {
  if (m.app != kUpdateAppId) throw UpdateRefusal(UpdateRefusalCode.wrongApp, m.app);
  if (m.channel != c.channel) throw UpdateRefusal(UpdateRefusalCode.wrongChannel, m.channel);
  if (m.issuedAt.isAfter(c.now.toUtc().add(kClockSkew))) {
    throw const UpdateRefusal(UpdateRefusalCode.notYetValid, 'issued in the future');
  }
  if (m.expiresAt.isBefore(c.now.toUtc())) {
    throw const UpdateRefusal(UpdateRefusalCode.expired, 'past expiresAt');
  }
  final int? seen = c.highestSeenSequence;
  if (seen != null && m.sequence < seen) {
    throw UpdateRefusal(UpdateRefusalCode.replayed, '${m.sequence} < $seen');
  }
  if (m.versionCode < c.installedVersionCode) {
    throw UpdateRefusal(UpdateRefusalCode.rollback, '${m.versionCode} < ${c.installedVersionCode}');
  }
  final ApkEntry? apk = m.apkFor(c.deviceAbis);
  if (c.requireApk && apk == null && m.versionCode > c.installedVersionCode) {
    throw const UpdateRefusal(UpdateRefusalCode.noApkForDevice, 'no file for this chip');
  }
  return UpdateVerdict(
    m.versionCode > c.installedVersionCode ? UpdateStatus.updateAvailable : UpdateStatus.upToDate,
    m,
    apk,
    belowMinimum: c.installedVersionCode < m.minSupportedVersionCode,
  );
}

/// The versionCode the app was built with can only go up; this is the one place that says "strictly greater" for the
/// installer's last look at the file it is about to install (the manifest was already checked, the file must agree).
bool strictlyNewer(int candidate, int installed) => candidate > installed;
