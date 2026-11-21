// OLIVE BRANCH — the checks the tablet repeats on its own, shared by the three places a file can become "an update the
// tablet may install": received from the phone, fetched by the tablet itself, and the moment of installing. One
// implementation so the three can never drift apart. Verified headless (test/tablet_update_hostile_test.dart).
import 'dart:io';

import 'tablet_update_hash.dart';
import 'tablet_update_port.dart';

/// The most the engine's own cap on an APK; the tablet holds the same line in case an engine ever allows more.
const int kTabletMaxApkBytes = 500 * 1024 * 1024;
const int kTabletMinChunk = 16 * 1024;
const int kTabletMaxChunk = 8 * 1024 * 1024;

/// What the tablet checks about a verified notice itself, whatever the engine said: this app, strictly newer than
/// what is installed (no rollback, no reinstall), sizes inside the caps, a chunk list that fits the size, and a pinned
/// signing certificate that is the installed app's own.
void checkNoticeAgainstInstalled(VerifiedUpdate u, InstalledFacts inst) {
  if (u.packageName != inst.packageName) throw const TabletUpdateRefused(TabletUpdateCode.wrongApp);
  if (u.versionCode < inst.versionCode) throw const TabletUpdateRefused(TabletUpdateCode.older);
  if (u.versionCode == inst.versionCode) throw const TabletUpdateRefused(TabletUpdateCode.upToDate);
  final ApkFacts a = u.apk;
  if (a.size < 1 || a.size > kTabletMaxApkBytes) throw const TabletUpdateRefused(TabletUpdateCode.tooBig);
  if (a.chunkSize < kTabletMinChunk || a.chunkSize > kTabletMaxChunk) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
  if (a.chunkSha256.length != (a.size + a.chunkSize - 1) ~/ a.chunkSize) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
  if (a.signerSha256 != inst.signerSha256) throw const TabletUpdateRefused(TabletUpdateCode.wrongSigner);
}

/// What the tablet checks about the FILE: exact size, whole-file SHA-256 (pass [knownSha] when it was computed while
/// the file arrived), then the APK's own package, version and signing certificate as the platform reads them from the
/// file, against the notice and against what is installed. Throws [TabletUpdateRefused]; returns nothing.
Future<void> checkApkFileAgainstNotice({
  required UpdateEnginePort engine,
  required VerifiedUpdate update,
  required File file,
  String? knownSha,
}) async {
  final ApkFacts a = update.apk;
  if (await file.length() != a.size) throw const TabletUpdateRefused(TabletUpdateCode.truncated);
  final String sha = knownSha ?? await sha256HexOfFile(file);
  if (sha != a.sha256) throw const TabletUpdateRefused(TabletUpdateCode.hashMismatch);
  final ApkInspection i = await engine.inspect(file);
  final InstalledFacts inst = await engine.installed();
  if (i.packageName != inst.packageName) throw const TabletUpdateRefused(TabletUpdateCode.wrongPackage);
  if (i.versionCode != update.versionCode) throw const TabletUpdateRefused(TabletUpdateCode.notGenuine);
  if (i.versionCode <= inst.versionCode) throw const TabletUpdateRefused(TabletUpdateCode.older);
  if (i.signerSha256 != inst.signerSha256 || i.signerSha256 != a.signerSha256) {
    throw const TabletUpdateRefused(TabletUpdateCode.wrongSigner);
  }
}

/// Space and battery, as the engine measures them. [apkBytes] is the file size.
Future<void> checkGuards(UpdateEnginePort engine, int apkBytes, {required int margin}) async {
  final DeviceGuards g = await engine.guards();
  if (g.freeBytes < apkBytes * 2 + margin) throw const TabletUpdateRefused(TabletUpdateCode.noSpace);
  if (g.batteryPercent >= 0 && g.batteryPercent < 20 && !g.charging) throw const TabletUpdateRefused(TabletUpdateCode.lowBattery);
}
