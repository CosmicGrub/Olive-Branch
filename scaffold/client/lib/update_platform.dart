// OLIVE BRANCH — the updater's seam to Android: what the phone says about itself, the "direct" installer (the system
// UNVERIFIED on a device; verified by CI headless (client/test).
// PackageInstaller behind a MethodChannel) and the "play" updater (Google Play In-App Updates). Mirrors
// android/app/src/{main,direct,play}/kotlin/com/olivebranch/olive_client/UpdateBridge.kt and UpdateEnvironment.kt; the
// channel and method names below are contract-checked against those files (test/update_platform_test.dart).
// MASTERFILE 7.24.
//
// TWO BUILD FLAVORS, ONE CHANNEL. The `direct` build (sideload, GitHub releases, a family's own server) can download an
// APK and hand it to Android's installer, which always asks the person to confirm: there is no silent install and no
// root. The `play` build contains NO self-install code and does NOT ask for REQUEST_INSTALL_PACKAGES (Play policy); it
// can only ask Google Play to update it. The native side of each flavor answers only its own methods: the other
// flavor's methods answer "not implemented" and this file turns that into [UpdateFlavor.none] / a refusal, never a
// crash. A build with no native side at all (the preview, Windows, `flutter test`) simply has the feature absent.
import 'dart:async';

import 'package:flutter/services.dart';

import 'update_manifest.dart';
import 'update_transport.dart';

class UpdateChannelNames {
  static const String channel = 'app.olive/update';

  // shared (both flavors)
  static const String mEnvironment = 'environment';
  // direct flavor only
  static const String mCanInstall = 'directCanInstall';
  static const String mOpenInstallSettings = 'directOpenInstallSettings';
  static const String mInspect = 'directInspect';
  static const String mInstall = 'directInstall';
  // play flavor only
  static const String mPlayCheck = 'playCheck';
  static const String mPlayStart = 'playStart';
  static const String mPlayComplete = 'playComplete';
  // native -> Dart
  static const String eInstall = 'installEvent';
  static const String ePlay = 'playEvent';
}

enum UpdateFlavor { direct, play, none }

UpdateFlavor flavorFromWord(String? w) => switch (w) {
      'direct' => UpdateFlavor.direct,
      'play' => UpdateFlavor.play,
      _ => UpdateFlavor.none,
    };

// ---- direct: the installer ---------------------------------------------------

/// What Android says about a downloaded file, read WITHOUT installing it.
class ApkInspection {
  const ApkInspection({
    required this.packageName,
    required this.versionCode,
    required this.signerSha256,
    required this.installedSignerSha256,
  });

  final String packageName;
  final int versionCode;

  /// Lower-case hex SHA-256 of each signing certificate the file carries.
  final List<String> signerSha256;

  /// The same, for the app that is installed now.
  final List<String> installedSignerSha256;

  /// The file is signed by the certificate of the installed app (Android would refuse otherwise), and, when the owner
  /// pinned one in the manifest, by that one too.
  bool signedLikeInstalled({String? pinned}) {
    if (signerSha256.isEmpty || installedSignerSha256.isEmpty) return false;
    final bool same = signerSha256.any(installedSignerSha256.contains);
    return same && (pinned == null || signerSha256.contains(pinned));
  }
}

enum InstallStart {
  /// The system confirmation is on screen (or about to be): the person decides.
  waitingForYou,

  /// "Install unknown apps" is not allowed for Olive yet.
  needsPermission,

  /// A locked kiosk screen would swallow the system dialog; a grown-up leaves the lock first.
  kioskLocked,

  /// The native side refused to start (the file did not match what it was told).
  refused,
}

enum InstallOutcome { success, declined, blocked, invalid, conflict, storage, incompatible, failed }

class InstallEvent {
  const InstallEvent(this.outcome, {this.versionCode});
  final InstallOutcome outcome;
  final int? versionCode;
}

abstract class DirectInstaller {
  Future<bool> canRequestInstalls();
  Future<void> openInstallSettings();
  Future<ApkInspection> inspect(String path);

  /// Streams [path] into an installer session, checking its SHA-256 and size as it goes against the values given (a
  /// file that changed after it was verified is refused here, a second look), then asks Android to confirm.
  Future<InstallStart> install({required String path, required String sha256, required int size, required int versionCode});
  Stream<InstallEvent> get installEvents;
}

// ---- play: Google Play In-App Updates ----------------------------------------

class PlayUpdateInfo {
  const PlayUpdateInfo({
    required this.available,
    this.supported = true,
    this.versionCode,
    this.priority = 0,
    this.staleDays,
    this.flexibleAllowed = false,
    this.immediateAllowed = false,
    this.downloaded = false,
  });

  final bool available;

  /// false when this build was not installed by Google Play (a sideloaded copy of the Play build): Play has nothing to
  /// say about it, and the updater stays out of the way.
  final bool supported;
  final int? versionCode;

  /// The in-app update priority the owner set in Play Console, 0 (low) to 5 (critical).
  final int priority;

  /// Days since Play first knew of this update on this phone.
  final int? staleDays;
  final bool flexibleAllowed;
  final bool immediateAllowed;

  /// A flexible update has already been downloaded and waits for a restart.
  final bool downloaded;

  /// Immediate (the full-screen Play flow) when Play allows it and the update is critical or has waited a long time;
  /// otherwise flexible (downloads in the background, then a calm restart).
  bool get preferImmediate => immediateAllowed && (priority >= 4 || (staleDays ?? 0) >= 60 && !flexibleAllowed);
}

enum PlayStatus { downloading, downloaded, installing, installed, failed, cancelled, pending }

class PlayEvent {
  const PlayEvent(this.status, {this.doneBytes = 0, this.totalBytes = 0});
  final PlayStatus status;
  final int doneBytes, totalBytes;
}

abstract class PlayUpdater {
  Future<PlayUpdateInfo> check();

  /// Starts the Play flow. false when the person declined or Play refused.
  Future<bool> start({required bool immediate});

  /// Restarts the app into the downloaded flexible update.
  Future<void> complete();
  Stream<PlayEvent> get playEvents;
}

// ---- the channel implementations ---------------------------------------------

/// One channel, three jobs; each flavor's native side implements its own methods only.
class UpdateNativeChannel implements UpdateEnvironmentSource, DirectInstaller, PlayUpdater {
  UpdateNativeChannel({MethodChannel? channel}) : _ch = channel ?? const MethodChannel(UpdateChannelNames.channel) {
    _ch.setMethodCallHandler(_fromNative);
  }

  final MethodChannel _ch;
  final StreamController<InstallEvent> _install = StreamController<InstallEvent>.broadcast();
  final StreamController<PlayEvent> _play = StreamController<PlayEvent>.broadcast();

  Future<dynamic> _fromNative(MethodCall c) async {
    final Object? a = c.arguments;
    if (a is! Map) return null;
    switch (c.method) {
      case UpdateChannelNames.eInstall:
        _install.add(InstallEvent(_outcome(a['status'] as String?), versionCode: a['versionCode'] as int?));
      case UpdateChannelNames.ePlay:
        _play.add(PlayEvent(_playStatus(a['status'] as String?),
            doneBytes: (a['bytes'] as num?)?.toInt() ?? 0, totalBytes: (a['total'] as num?)?.toInt() ?? 0));
    }
    return null;
  }

  static InstallOutcome _outcome(String? w) => switch (w) {
        'success' => InstallOutcome.success,
        'declined' => InstallOutcome.declined,
        'blocked' => InstallOutcome.blocked,
        'invalid' => InstallOutcome.invalid,
        'conflict' => InstallOutcome.conflict,
        'storage' => InstallOutcome.storage,
        'incompatible' => InstallOutcome.incompatible,
        _ => InstallOutcome.failed,
      };

  static PlayStatus _playStatus(String? w) => switch (w) {
        'downloading' => PlayStatus.downloading,
        'downloaded' => PlayStatus.downloaded,
        'installing' => PlayStatus.installing,
        'installed' => PlayStatus.installed,
        'cancelled' => PlayStatus.cancelled,
        'pending' => PlayStatus.pending,
        _ => PlayStatus.failed,
      };

  /// Which flavor the NATIVE side was built as; the build decides, never the manifest. `none` where there is no
  /// native side.
  Future<UpdateFlavor> flavor() async {
    try {
      final Map<Object?, Object?>? m = await _ch.invokeMapMethod<Object?, Object?>(UpdateChannelNames.mEnvironment);
      return flavorFromWord(m?['flavor'] as String?);
    } on MissingPluginException {
      return UpdateFlavor.none;
    } on PlatformException {
      return UpdateFlavor.none;
    }
  }

  @override
  Future<UpdateEnvironment> read() async {
    final Map<Object?, Object?>? m = await _ch.invokeMapMethod<Object?, Object?>(UpdateChannelNames.mEnvironment);
    if (m == null) throw MissingPluginException('no environment');
    NetworkKind net = NetworkKind.unknown;
    switch (m['network']) {
      case 'wifi':
        net = NetworkKind.wifi;
      case 'ethernet':
        net = NetworkKind.ethernet;
      case 'cellular':
        net = NetworkKind.cellular;
      case 'none':
        net = NetworkKind.none;
    }
    return UpdateEnvironment(
      installedVersionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      installedVersionName: (m['versionName'] as String?) ?? '',
      network: net,
      metered: m['metered'] as bool?,
      roaming: m['roaming'] == true,
      dataSaver: m['dataSaver'] == true,
      batteryPercent: (m['batteryPercent'] as num?)?.toInt(),
      charging: m['charging'] == true,
      freeBytes: (m['freeBytes'] as num?)?.toInt(),
      abis: <String>[for (final Object? a in (m['abis'] as List<Object?>? ?? const <Object?>[])) '$a'],
      flavor: (m['flavor'] as String?) ?? 'direct',
    );
  }

  // direct
  @override
  Future<bool> canRequestInstalls() async => await _ch.invokeMethod<bool>(UpdateChannelNames.mCanInstall) ?? false;

  @override
  Future<void> openInstallSettings() => _ch.invokeMethod<void>(UpdateChannelNames.mOpenInstallSettings);

  @override
  Future<ApkInspection> inspect(String path) async {
    final Map<Object?, Object?>? m = await _ch
        .invokeMapMethod<Object?, Object?>(UpdateChannelNames.mInspect, <String, Object?>{'path': path});
    if (m == null) throw const UpdateRefusal(UpdateRefusalCode.apkMismatch, 'the file could not be read');
    List<String> sig(Object? v) => <String>[for (final Object? s in (v as List<Object?>? ?? const <Object?>[])) '$s'];
    return ApkInspection(
      packageName: (m['packageName'] as String?) ?? '',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      signerSha256: sig(m['signers']),
      installedSignerSha256: sig(m['installedSigners']),
    );
  }

  @override
  Future<InstallStart> install({required String path, required String sha256, required int size, required int versionCode}) async {
    final String? w = await _ch.invokeMethod<String>(UpdateChannelNames.mInstall, <String, Object?>{
      'path': path,
      'sha256': sha256,
      'size': size,
      'versionCode': versionCode,
    });
    return switch (w) {
      'waiting' => InstallStart.waitingForYou,
      'needsPermission' => InstallStart.needsPermission,
      'kioskLocked' => InstallStart.kioskLocked,
      _ => InstallStart.refused,
    };
  }

  @override
  Stream<InstallEvent> get installEvents => _install.stream;

  // play
  @override
  Future<PlayUpdateInfo> check() async {
    final Map<Object?, Object?>? m = await _ch.invokeMapMethod<Object?, Object?>(UpdateChannelNames.mPlayCheck);
    if (m == null) return const PlayUpdateInfo(available: false);
    return PlayUpdateInfo(
      available: m['available'] == true,
      supported: m['supported'] != false,
      versionCode: (m['versionCode'] as num?)?.toInt(),
      priority: (m['priority'] as num?)?.toInt() ?? 0,
      staleDays: (m['staleDays'] as num?)?.toInt(),
      flexibleAllowed: m['flexibleAllowed'] == true,
      immediateAllowed: m['immediateAllowed'] == true,
      downloaded: m['downloaded'] == true,
    );
  }

  @override
  Future<bool> start({required bool immediate}) async =>
      await _ch.invokeMethod<bool>(UpdateChannelNames.mPlayStart, <String, Object?>{'immediate': immediate}) ?? false;

  @override
  Future<void> complete() => _ch.invokeMethod<void>(UpdateChannelNames.mPlayComplete);

  @override
  Stream<PlayEvent> get playEvents => _play.stream;
}
