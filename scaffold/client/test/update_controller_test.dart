// The updater end to end with a fake network, a fake installer and a fake phone: the polite schedule, every hostile
// manifest, resumable downloads with their guards, the install checks (including the signing certificate), the other
// side of a restart (what's new, an install that did not finish), the minimum-supported notice that never locks, the
// hand-over between family phones, and the Google Play flavor. MASTERFILE 7.24.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_controller.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_platform.dart';
import 'package:olive_client/update_store.dart';
import 'package:olive_client/update_transport.dart';

import 'update_support.dart';

void main() {
  late Rig rig;
  late Uint8List apk;
  const int kChunk = 65536;

  setUp(() async {
    rig = await Rig.create();
    apk = fakeApk(kChunk * 2 + 4321);
  });
  tearDown(() async => rig.dispose());

  Future<AppUpdater> started({AppUpdater? u}) async {
    final AppUpdater up = u ?? rig.updater();
    await up.start();
    return up;
  }

  group('absent unless it can work', () {
    test('no source configured: the feature is simply absent (no phase, no request)', () async {
      final Rig r = await Rig.create(manifestUrls: const <String>[]);
      addTearDown(r.dispose);
      final AppUpdater u = await started(u: r.updater());
      expect(u.phase, UpdatePhase.off);
      expect(u.enabled, isFalse);
      await u.maybeCheckAtOpen();
      await u.checkNow();
      expect(r.transport.getLog, isEmpty);
    });

    test('no key built in: absent (fails closed)', () async {
      final Rig r = await Rig.create(withKey: false);
      addTearDown(r.dispose);
      final AppUpdater u = await started(u: r.updater());
      expect(u.enabled, isFalse);
    });

    test('a source an adult typed turns it on for a build that had none', () async {
      final Rig r = await Rig.create(manifestUrls: const <String>[]);
      addTearDown(r.dispose);
      await r.repo.save(const UpdateState(manifestUrl: kManifestUrl));
      final AppUpdater u = await started(u: r.updater());
      expect(u.enabled, isTrue);
      expect(u.manifestUrls, <String>[kManifestUrl]);
    });

    test('a phone with no native side, and a build with no installer, are absent too', () async {
      final Rig r = await Rig.create(environment: wifiPhone(flavor: 'none'));
      addTearDown(r.dispose);
      expect((await started(u: r.updater())).enabled, isFalse);
      final AppUpdater noInstaller = await started(u: rig.updater(withInstaller: false));
      expect(noInstaller.enabled, isFalse);
    });

    test('an environment that cannot be read is absent, never a crash', () async {
      final AppUpdater u = rig.updater(environment: _ThrowingEnv());
      await u.start();
      expect(u.phase, UpdatePhase.off);
    });
  });

  group('finding an update', () {
    test('a signed, newer, fresh manifest becomes "an update is ready" with plain-words notes', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      expect(u.phase, UpdatePhase.idle);
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      expect(u.manifest!.versionName, '0.52.0');
      expect(u.manifest!.notes, hasLength(2));
      expect(u.belowMinimum, isFalse);
      expect(u.state.lastResult, 'ok');
      expect(u.state.lastCheckMs, kNow.millisecondsSinceEpoch);
      expect(u.state.highestSeenSequence, 1795255200);
      expect(u.state.lastSeenVersionName, '0.52.0');
      expect(u.bannerWanted, isTrue);
    });

    test('the same version installed: up to date', () async {
      rig.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.phase, UpdatePhase.upToDate);
      expect(u.bannerWanted, isFalse);
    });

    test('manifest sources are all asked and the newest signed answer wins (a stale mirror cannot hold the phone back)', () async {
      final Rig r = await Rig.create(manifestUrls: const <String>[kManifestUrl, kManifestMirror]);
      addTearDown(r.dispose);
      final Uint8List old = fakeApk(kChunk + 10, 5);
      Map<String, Object?> oldDraft = await draftFor(old, versionName: '0.51.5', minSupported: 5100, sequence: 1795255100);
      r.transport.manifests[kManifestUrl] = encodeDoc(await r.signer.sign(oldDraft));
      Map<String, Object?> newDraft = await draftFor(apk);
      r.transport.manifests[kManifestMirror] = encodeDoc(await r.signer.sign(newDraft));
      final AppUpdater u = await started(u: r.updater());
      await u.checkNow();
      expect(u.manifest!.versionName, '0.52.0');
      expect(r.transport.getLog, <String>[kManifestUrl, kManifestMirror]);
      // ... and the other way round.
      r.transport.manifests[kManifestUrl] = encodeDoc(await r.signer.sign(newDraft));
      r.transport.manifests[kManifestMirror] = encodeDoc(await r.signer.sign(oldDraft));
      await u.checkNow();
      expect(u.manifest!.versionName, '0.52.0');
      oldDraft = newDraft = <String, Object?>{};
    });

    test('a mirror that serves garbage or a forgery is ignored when another source is good', () async {
      final Rig r = await Rig.create(manifestUrls: const <String>[kManifestUrl, kManifestMirror]);
      addTearDown(r.dispose);
      await r.publish(apk);
      final TestSigner evil = await TestSigner.create(77);
      r.transport.manifests[kManifestMirror] = encodeDoc(await evil.sign(await draftFor(apk, versionName: '9.9.9')));
      final AppUpdater u = await started(u: r.updater());
      await u.checkNow();
      expect(u.manifest!.versionName, '0.52.0');
      r.transport.manifests[kManifestMirror] = Uint8List.fromList(<int>[1, 2, 3]);
      await u.checkNow();
      expect(u.manifest!.versionName, '0.52.0');
    });

    test('a check that fails never takes away an update that was already found', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      rig.transport.manifestErrors[kManifestUrl] = const UpdateRefusal(UpdateRefusalCode.offline);
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      expect(u.manifest, isNotNull);
      expect(u.failure, UpdateRefusalCode.offline);
      expect(u.state.lastResult, 'offline');
    });
  });

  group('hostile manifests are refused and say so honestly', () {
    Future<AppUpdater> checked(Uint8List doc, {UpdateEnvironment? env}) async {
      if (env != null) rig.env.value = env;
      rig.transport.manifests[kManifestUrl] = doc;
      final AppUpdater u = await started();
      await u.checkNow();
      return u;
    }

    test('a tampered document', () async {
      final Map<String, Object?> doc = await rig.signer.sign(await draftFor(apk));
      final String text = String.fromCharCodes(encodeDoc(doc)).replaceFirst('"versionCode":5200', '"versionCode":5201');
      final AppUpdater u = await checked(Uint8List.fromList(text.codeUnits));
      expect(u.phase, UpdatePhase.idle);
      expect(u.failure, UpdateRefusalCode.badSignature);
      expect(u.state.lastResult, 'refused:badSignature');
      expect(u.manifest, isNull);
    });

    test('a signature by a key this build does not trust', () async {
      final TestSigner evil = await TestSigner.create(5);
      final AppUpdater u = await checked(encodeDoc(await evil.sign(await draftFor(apk))));
      expect(u.failure, UpdateRefusalCode.unknownKey);
      expect(u.phase, UpdatePhase.idle);
    });

    test('a rollback (older than what is installed) is ignored without alarm', () async {
      final AppUpdater u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk, versionName: '0.50.0', minSupported: 5000))));
      expect(u.phase, UpdatePhase.upToDate);
      expect(u.failure, isNull);
      expect(u.manifest, isNull);
    });

    test('a replayed old manifest, after a newer one was accepted, is ignored and the newer notice stays', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      rig.transport.manifests[kManifestUrl] = encodeDoc(await rig.signer.sign(await draftFor(apk, versionName: '0.51.5', minSupported: 5100, sequence: 1795255100)));
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      expect(u.manifest!.versionName, '0.52.0');
      expect(u.state.highestSeenSequence, 1795255200);
    });

    test('a manifest for another channel', () async {
      final AppUpdater u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk, channel: 'beta'))));
      expect(u.failure, UpdateRefusalCode.wrongChannel);
      expect(u.phase, UpdatePhase.idle);
    });

    test('an expired manifest, and one dated in the future', () async {
      rig.time = DateTime.utc(2027, 6, 1);
      AppUpdater u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk))));
      expect(u.failure, UpdateRefusalCode.expired);
      rig.time = DateTime.utc(2026, 10, 1);
      u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk))));
      expect(u.failure, UpdateRefusalCode.notYetValid);
    });

    test('a manifest for another app, one for another chip, and one with a cleartext address', () async {
      AppUpdater u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk, app: 'com.example.other'))));
      expect(u.failure, UpdateRefusalCode.wrongApp);
      u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk, abi: 'x86_64'))));
      expect(u.failure, UpdateRefusalCode.noApkForDevice);
      u = await checked(encodeDoc(await rig.signer.sign(await draftFor(apk, urls: const <String>['http://updates.example.org/a.apk']))));
      expect(u.failure, UpdateRefusalCode.badUrl);
    });

    test('nothing is downloaded or installed in any of those cases', () async {
      await checked(Uint8List.fromList(<int>[0, 1, 2]));
      expect(rig.transport.openLog, isEmpty);
      expect(rig.installer.installs, isEmpty);
    });
  });

  group('polite checking', () {
    Future<AppUpdater> open() async {
      await rig.publish(apk);
      return started();
    }

    test('at app open, at most daily', () async {
      final AppUpdater u = await open();
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1));
      await u.maybeCheckAtOpen();
      rig.time = kNow.add(const Duration(hours: 23));
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1), reason: 'not again within a day');
      rig.time = kNow.add(const Duration(hours: 25));
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(2));
    });

    test('after a failed check it waits six hours, not a day, and not zero', () async {
      final AppUpdater u = await open();
      rig.transport.manifestErrors[kManifestUrl] = const UpdateRefusal(UpdateRefusalCode.httpError);
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1));
      rig.time = kNow.add(const Duration(hours: 5));
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1));
      rig.time = kNow.add(const Duration(hours: 7));
      rig.transport.manifestErrors.clear();
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(2));
      expect(u.phase, UpdatePhase.available);
    });

    test('never offline, never on mobile data, in roaming or with Data Saver on (and offline does not use up the day)', () async {
      final AppUpdater u = await open();
      for (final UpdateEnvironment e in <UpdateEnvironment>[
        wifiPhone(network: NetworkKind.none),
        wifiPhone(network: NetworkKind.cellular, metered: true),
        wifiPhone(roaming: true),
        wifiPhone(dataSaver: true),
        wifiPhone(metered: true),
      ]) {
        rig.env.value = e;
        await u.maybeCheckAtOpen();
        expect(rig.transport.getLog, isEmpty, reason: '${e.network} metered=${e.metered} roaming=${e.roaming}');
      }
      rig.env.value = wifiPhone();
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1));
    });

    test('a grown-up can turn the automatic check off, and Wi-Fi-only off (then mobile data is allowed for the small check)', () async {
      final AppUpdater u = await open();
      await u.setAutoCheck(false);
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, isEmpty);
      await u.setAutoCheck(true);
      await u.setWifiOnly(false);
      rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
      await u.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1));
    });

    test('"Check now" works on mobile data (a few kilobytes) but not offline', () async {
      final AppUpdater u = await open();
      rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      rig.env.value = wifiPhone(network: NetworkKind.none);
      await u.checkNow();
      expect(u.failure, UpdateRefusalCode.offline);
      expect(u.phase, UpdatePhase.available, reason: 'what was found stays found');
    });

    test('the saved state survives a restart: the day is not reset by closing the app', () async {
      final AppUpdater u = await open();
      await u.maybeCheckAtOpen();
      final AppUpdater again = await started(u: rig.updater());
      await again.maybeCheckAtOpen();
      expect(rig.transport.getLog, hasLength(1));
    });
  });

  group('downloading', () {
    Future<AppUpdater> found() async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      return u;
    }

    test('"Download on Wi-Fi" on Wi-Fi downloads, verifies and is ready to install', () async {
      final AppUpdater u = await found();
      await u.downloadOnWifi();
      expect(u.phase, UpdatePhase.ready);
      expect(u.progress!.fraction, 1.0);
      expect(File('${rig.staging.path}${Platform.pathSeparator}${u.apk!.sha256}.apk').existsSync(), isTrue);
      expect(u.state.queuedVersionCode, isNull);
    });

    test('on mobile data "Download on Wi-Fi" waits, and starts by itself when Wi-Fi comes back', () async {
      final AppUpdater u = await found();
      rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
      await u.downloadOnWifi();
      expect(u.phase, UpdatePhase.waitingForWifi);
      expect(rig.transport.openLog, isEmpty);
      await u.pollQueuedDownload();
      expect(u.phase, UpdatePhase.waitingForWifi);
      rig.env.value = wifiPhone();
      await u.pollQueuedDownload();
      expect(u.phase, UpdatePhase.ready);
    });

    test('a queued download is not started with Data Saver on, in roaming, or on a metered Wi-Fi', () async {
      final AppUpdater u = await found();
      rig.env.value = wifiPhone(dataSaver: true);
      await u.downloadOnWifi();
      expect(u.phase, UpdatePhase.waitingForWifi);
      rig.env.value = wifiPhone(roaming: true);
      await u.pollQueuedDownload();
      expect(u.phase, UpdatePhase.waitingForWifi);
      rig.env.value = wifiPhone(metered: true);
      await u.pollQueuedDownload();
      expect(u.phase, UpdatePhase.waitingForWifi);
      expect(rig.transport.openLog, isEmpty);
    });

    test('"Download now" is an adult\'s explicit choice: allowed on mobile data', () async {
      final AppUpdater u = await found();
      rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
    });

    test('nothing downloads unless a grown-up chose it (finding an update never starts one)', () async {
      await found();
      expect(rig.transport.openLog, isEmpty);
    });

    test('low battery (and not charging) refuses, says so, and keeps what is good; charging allows it', () async {
      final AppUpdater u = await found();
      rig.env.value = wifiPhone(battery: 9);
      await u.downloadNow();
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.lowBattery);
      expect(rig.transport.openLog, isEmpty);
      rig.env.value = wifiPhone(battery: 9, charging: true);
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
    });

    test('not enough free space refuses before a byte is fetched', () async {
      final AppUpdater u = await found();
      rig.env.value = wifiPhone(freeBytes: apk.length);
      await u.downloadNow();
      expect(u.failure, UpdateRefusalCode.noSpace);
      expect(rig.transport.openLog, isEmpty);
      rig.env.value = wifiPhone(freeBytes: null);
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready, reason: 'an unknown amount of space does not block');
    });

    test('Wi-Fi lost half way pauses ("waiting for Wi-Fi") and the next Wi-Fi continues from the last good chunk', () async {
      final AppUpdater u = await found();
      bool switched = false;
      rig.transport.files[kPrimary] = FileBehavior(apk, onPiece: (int sent) {
        if (!switched && sent > kChunk + 10) {
          switched = true;
          rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
          rig.time = kNow.add(const Duration(seconds: 30));
        }
      });
      await u.downloadOnWifi();
      expect(u.phase, UpdatePhase.waitingForWifi);
      final File part = File('${rig.staging.path}${Platform.pathSeparator}${u.apk!.sha256}.part');
      expect(await part.length(), greaterThanOrEqualTo(kChunk), reason: 'the good chunks are kept');
      rig.transport.files[kPrimary] = FileBehavior(apk);
      rig.env.value = wifiPhone();
      rig.transport.openLog.clear();
      await u.pollQueuedDownload();
      expect(u.phase, UpdatePhase.ready);
      expect(rig.transport.openLog.first.$2, greaterThanOrEqualTo(kChunk), reason: 'continued, not restarted');
    });

    test('a connection that keeps dropping while queued for Wi-Fi waits instead of failing, and finishes later', () async {
      final AppUpdater u = await found();
      rig.transport.files[kPrimary] = FileBehavior(apk, dropAfter: kChunk ~/ 2, dropTimes: 9999);
      rig.transport.files[kMirror] = FileBehavior(apk, dropAfter: kChunk ~/ 2, dropTimes: 9999);
      await u.downloadOnWifi();
      expect(u.phase, UpdatePhase.waitingForWifi);
      rig.transport.files[kPrimary] = FileBehavior(apk);
      await u.pollQueuedDownload();
      expect(u.phase, UpdatePhase.ready);
    });

    test('a corrupt file on every address ends honestly: deleted, nothing installable, can be tried again', () async {
      final AppUpdater u = await found();
      rig.transport.files[kPrimary] = FileBehavior(apk, corrupt: 20);
      rig.transport.files[kMirror] = FileBehavior(apk, corrupt: 20);
      await u.downloadNow();
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.hashMismatch);
      final String sha = u.apk!.sha256;
      expect(File('${rig.staging.path}${Platform.pathSeparator}$sha.apk').existsSync(), isFalse);
      rig.transport.files[kPrimary] = FileBehavior(apk);
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
    });

    test('Stop keeps what was downloaded and goes back to "an update is ready"', () async {
      final AppUpdater u = await found();
      u.addListener(() {
        if (u.phase == UpdatePhase.downloading && (u.progress?.doneBytes ?? 0) >= kChunk) u.stopDownload();
      });
      await u.downloadNow();
      expect(u.phase, UpdatePhase.available);
      final File part = File('${rig.staging.path}${Platform.pathSeparator}${u.apk!.sha256}.part');
      expect(part.existsSync() && await part.length() >= kChunk, isTrue);
    });
  });

  group('installing', () {
    Future<AppUpdater> ready() async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      await u.downloadNow();
      expect(u.phase, UpdatePhase.ready);
      return u;
    }

    test('the file is looked at once more, then handed to Android with its hash and size; the system asks the person', () async {
      final AppUpdater u = await ready();
      await u.install();
      expect(u.phase, UpdatePhase.installing);
      expect(rig.installer.inspects, 1);
      final Map<String, Object?> call = rig.installer.installs.single;
      expect(call['sha256'], u.apk!.sha256);
      expect(call['size'], apk.length);
      expect(call['versionCode'], 5200);
      expect(rig.flushed, <String>['flushed'], reason: 'pending writes are flushed first');
      final PendingInstall p = u.state.pending!;
      expect(p.fromVersionCode, 5100);
      expect(p.toVersionCode, 5200);
      expect(p.areaCount, 12);
      expect(p.notes, hasLength(2));
    });

    test('a different signing certificate than the installed app: deleted, never offered to Android', () async {
      final AppUpdater u = await ready();
      rig.installer.signers = <String>[certHash('someone else')];
      await u.install();
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.certMismatch);
      expect(rig.installer.installs, isEmpty);
      expect(File('${rig.staging.path}${Platform.pathSeparator}${u.apk!.sha256}.apk').existsSync(), isFalse);
    });

    test('a certificate the owner pinned in the manifest must be the one on the file', () async {
      await rig.publish(apk, tweak: (Map<String, Object?> d) {
        apk0(d)['signerSha256'] = certHash('pinned');
        return d;
      });
      final AppUpdater u = await started();
      await u.checkNow();
      await u.downloadNow();
      await u.install();
      expect(u.failure, UpdateRefusalCode.certMismatch, reason: 'the file is signed like the app, but not by the pinned certificate');
      rig.installer.signers = <String>[certHash('owner'), certHash('pinned')];
      await rig.publish(apk, tweak: (Map<String, Object?> d) {
        apk0(d)['signerSha256'] = certHash('pinned');
        return d;
      });
      await u.checkNow();
      await u.downloadNow();
      await u.install();
      expect(u.phase, UpdatePhase.installing);
    });

    test('a file with no readable certificate is not signed "like the installed app"', () {
      expect(
          const ApkInspection(packageName: kUpdateAppId, versionCode: 5200, signerSha256: <String>[], installedSignerSha256: <String>['a'])
              .signedLikeInstalled(),
          isFalse);
    });

    test('the wrong package, or a version that is not the one promised, or not newer: refused and deleted', () async {
      AppUpdater u = await ready();
      rig.installer.packageName = 'com.example.other';
      await u.install();
      expect(u.failure, UpdateRefusalCode.apkMismatch);
      rig.installer.packageName = kUpdateAppId;
      u = await ready();
      rig.installer.inspectedVersionCode = 5100;
      await u.install();
      expect(u.failure, UpdateRefusalCode.apkMismatch);
      expect(rig.installer.installs, isEmpty);
    });

    test('a file Android cannot read is refused and deleted', () async {
      final AppUpdater u = await ready();
      rig.installer.inspectError = StateError('not a package');
      await u.install();
      expect(u.failure, UpdateRefusalCode.apkMismatch);
      expect(rig.installer.installs, isEmpty);
    });

    test('"install unknown apps" not allowed yet: says what to allow, opens the settings page, and carries on after', () async {
      final AppUpdater u = await ready();
      rig.installer.canInstall = false;
      await u.install();
      expect(u.phase, UpdatePhase.needsPermission);
      expect(rig.installer.installs, isEmpty);
      expect(u.state.pending, isNull);
      await u.openInstallSettings();
      expect(rig.installer.settingsOpened, 1);
      rig.installer.canInstall = true;
      await u.recheckPermission();
      expect(u.phase, UpdatePhase.ready);
      await u.install();
      expect(u.phase, UpdatePhase.installing);
    });

    test('a locked kiosk screen would swallow the dialog: nothing is installed, the update stays ready, and it says why', () async {
      final AppUpdater u = await ready();
      rig.installer.startResult = InstallStart.kioskLocked;
      await u.install();
      expect(u.phase, UpdatePhase.ready);
      expect(u.failure, UpdateRefusalCode.kioskLocked);
      expect(u.state.pending, isNull);
    });

    test('the person says no in the system dialog: still ready, nothing changed', () async {
      final AppUpdater u = await ready();
      await u.install();
      rig.installer.events.add(const InstallEvent(InstallOutcome.declined));
      await Future<void>.delayed(Duration.zero);
      expect(u.phase, UpdatePhase.ready);
      expect(u.failure, UpdateRefusalCode.installNotFinished);
      expect(u.state.pending, isNull);
    });

    test('Android refuses (blocked, storage, conflict...): an honest failure and the note is cleared', () async {
      final AppUpdater u = await ready();
      await u.install();
      rig.installer.events.add(const InstallEvent(InstallOutcome.storage));
      await Future<void>.delayed(Duration.zero);
      expect(u.phase, UpdatePhase.failed);
      expect(u.failure, UpdateRefusalCode.installRefused);
      expect(u.state.pending, isNull);
    });

    test('low battery refuses the install step too', () async {
      final AppUpdater u = await ready();
      rig.env.value = wifiPhone(battery: 5);
      await u.install();
      expect(u.failure, UpdateRefusalCode.lowBattery);
      expect(rig.installer.installs, isEmpty);
    });

    test('a file changed on disk after it was verified is not installed', () async {
      final AppUpdater u = await ready();
      final File f = File('${rig.staging.path}${Platform.pathSeparator}${u.apk!.sha256}.apk');
      final RandomAccessFile r = await f.open(mode: FileMode.append);
      await r.writeByte(1);
      await r.close();
      await u.install();
      expect(rig.installer.installs, isEmpty);
      expect(u.failure, UpdateRefusalCode.hashMismatch);
      expect(u.phase, UpdatePhase.available);
    });

    test('the Google Play build has no way to install a file at all', () async {
      final Rig r = await Rig.create(environment: wifiPhone(flavor: 'play'));
      addTearDown(r.dispose);
      final AppUpdater u = r.updater(play: true);
      await u.start();
      await u.install();
      await u.downloadNow();
      await u.downloadOnWifi();
      expect(r.installer.installs, isEmpty);
      expect(r.transport.openLog, isEmpty);
    });
  });

  group('the other side of a restart', () {
    Future<void> installed() async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      await u.downloadNow();
      await u.install();
      expect(u.state.pending, isNotNull);
    }

    test('the app comes back as the new version: what\'s new is kept for a grown-up to see once, and the file is cleaned up', () async {
      await installed();
      rig.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
      final AppUpdater u = await started(u: rig.updater());
      expect(u.state.pending, isNull);
      expect(u.whatsNew!.versionName, '0.52.0');
      expect(u.whatsNew!.headline, 'Calmer messages');
      expect(u.whatsNew!.notes, hasLength(2));
      expect(u.whatsNew!.dataNote, isEmpty);
      expect(u.state.lastUpdatedName, '0.52.0');
      expect(rig.staging.listSync(), isEmpty, reason: 'the downloaded file is no longer needed');
      await u.dismissWhatsNew();
      expect(u.whatsNew, isNull);
      expect((await rig.repo.load()).whatsNew, isNull);
      expect(u.phase, UpdatePhase.idle);
    });

    test('fewer sealed areas than before the update are reported plainly (nothing is hidden)', () async {
      await installed();
      rig.areas = 9;
      rig.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
      final AppUpdater u = await started(u: rig.updater());
      expect(u.whatsNew!.dataNote, contains('fewer saved items'));
    });

    test('the app comes back still on the old version: it did not finish; nothing changed; the update is offered again', () async {
      await installed();
      final AppUpdater u = await started(u: rig.updater());
      expect(u.state.pending, isNull);
      expect(u.whatsNew, isNull);
      expect(u.failure, UpdateRefusalCode.installNotFinished);
      expect(u.phase, UpdatePhase.ready, reason: 'the verified file is still there');
      expect(u.manifest!.versionName, '0.52.0');
    });

    test('an update found and downloaded is restored after a restart with no network at all', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      await u.downloadNow();
      rig.transport.manifests.clear();
      rig.transport.files.clear();
      final AppUpdater again = await started(u: rig.updater());
      expect(again.phase, UpdatePhase.ready);
      expect(again.manifest!.versionCode, 5200);
      await again.install();
      expect(again.phase, UpdatePhase.installing);
    });

    test('a leftover manifest that no longer verifies is swept away, never trusted', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      final File copy = File('${rig.staging.path}${Platform.pathSeparator}manifest.json');
      await copy.writeAsString('{"not":"signed"}');
      final AppUpdater again = await started(u: rig.updater());
      expect(again.phase, UpdatePhase.idle);
      expect(again.manifest, isNull);
    });

    test('a state that cannot be saved never breaks the updater', () async {
      rig.repo.failSaves = true;
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
    });
  });

  group('the minimum-supported notice never locks anything', () {
    test('below the minimum: a clear notice, the update is offered, and the updater changes nothing else', () async {
      await rig.publish(apk, tweak: (Map<String, Object?> d) => d..['minSupportedVersionCode'] = 5150);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.belowMinimum, isTrue);
      expect(u.phase, UpdatePhase.available);
      expect(u.bannerWanted, isTrue);
      await u.later();
      expect(u.bannerWanted, isTrue, reason: '"Later" does not hide the please-update notice');
    });

    test('at or above the minimum there is no notice', () async {
      rig.env.value = wifiPhone(versionCode: 5150, versionName: '0.51.5');
      await rig.publish(apk, tweak: (Map<String, Object?> d) => d..['minSupportedVersionCode'] = 5150);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.belowMinimum, isFalse);
    });
  });

  group('"Later"', () {
    test('quiets the home-screen line for three days, then it comes back', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.bannerWanted, isTrue);
      await u.later();
      expect(u.bannerWanted, isFalse);
      rig.time = kNow.add(const Duration(days: 2));
      expect(u.bannerWanted, isFalse);
      rig.time = kNow.add(const Duration(days: 4));
      expect(u.bannerWanted, isTrue);
    });

    test('a NEWER update is not quieted by a "Later" about an older one', () async {
      await rig.publish(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      await u.later();
      final Uint8List next = fakeApk(kChunk + 9, 4);
      rig.transport.manifests[kManifestUrl] =
          encodeDoc(await rig.signer.sign(await draftFor(next, versionName: '0.52.1', minSupported: 5100)));
      await u.checkNow();
      expect(u.manifest!.versionName, '0.52.1');
      expect(u.bannerWanted, isTrue);
    });
  });

  group('a source and a channel an adult chose', () {
    test('only a secure address is taken; the build\'s own cleartext rule applies; an empty one resets', () async {
      final AppUpdater u = await started();
      expect(await u.setManifestUrl('http://updates.example.org/manifest.json'), isNotNull);
      expect(await u.setManifestUrl('https://user:pw@updates.example.org/manifest.json'), isNotNull);
      expect(await u.setManifestUrl('https://updates.example.org/manifest.json?token=1'), isNotNull);
      expect(await u.setManifestUrl('not a url'), isNotNull);
      expect(u.manifestUrls, <String>[kManifestUrl]);
      expect(await u.setManifestUrl('https://family.example.org/olive/manifest.json'), isNull);
      expect(u.manifestUrls, <String>['https://family.example.org/olive/manifest.json']);
      expect(await u.setManifestUrl(''), isNull);
      expect(u.manifestUrls, <String>[kManifestUrl]);
    });

    test('the chosen source is the one that is asked', () async {
      const String mine = 'https://family.example.org/olive/manifest.json';
      await rig.publish(apk, url: mine);
      final AppUpdater u = await started();
      await u.setManifestUrl(mine);
      await u.checkNow();
      expect(rig.transport.getLog, <String>[mine]);
      expect(u.phase, UpdatePhase.available);
    });

    test('the channel: a beta manifest is only taken when the grown-up chose the beta channel', () async {
      rig.transport.manifests[kManifestUrl] = encodeDoc(await rig.signer.sign(await draftFor(apk, channel: 'beta')));
      rig.transport.files[kPrimary] = FileBehavior(apk);
      final AppUpdater u = await started();
      await u.checkNow();
      expect(u.phase, UpdatePhase.idle);
      await u.setChannel('beta');
      expect(u.channel, 'beta');
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      await u.setChannel('stable');
      expect(u.channel, 'stable');
      expect(u.state.channel, isNull, reason: 'the default channel is stored as "no choice"');
    });
  });

  group('over the family link', () {
    test('the phone that holds a verified file can hand it on, and the tablet checks everything again for itself', () async {
      await rig.publish(apk);
      final AppUpdater phone = await started();
      await phone.checkNow();
      await phone.downloadNow();
      final StagedUpdate staged = (await phone.stagedForHandover())!;
      expect(staged.manifest.versionCode, 5200);

      // The tablet is the SAME app with the SAME built-in key, and no network at all.
      final Rig same = await Rig.create(signer: rig.signer);
      addTearDown(same.dispose);
      final AppUpdater tablet = same.updater();
      same.env.value = wifiPhone(network: NetworkKind.none);
      await tablet.start();
      expect(tablet.enabled, isTrue);
      final UpdateRefusal? r = await tablet.acceptHandedOver(staged.manifestDocument, staged.apk.openRead());
      expect(r, isNull);
      expect(tablet.phase, UpdatePhase.ready);
      expect(tablet.state.highestSeenSequence, 1795255200);
      await tablet.install();
      expect(tablet.phase, UpdatePhase.installing);
      expect(same.transport.openLog, isEmpty);
      expect(same.transport.getLog, isEmpty);
    });

    test('a forged manifest, damaged bytes and an older version are each refused by the receiving phone', () async {
      await rig.publish(apk);
      final AppUpdater phone = await started();
      await phone.checkNow();
      await phone.downloadNow();
      final StagedUpdate staged = (await phone.stagedForHandover())!;
      final Rig same = await Rig.create(signer: rig.signer);
      addTearDown(same.dispose);
      final AppUpdater tablet = same.updater();
      await tablet.start();

      final TestSigner evil = await TestSigner.create(66);
      final Uint8List forged = encodeDoc(await evil.sign(await draftFor(apk)));
      expect((await tablet.acceptHandedOver(forged, staged.apk.openRead()))!.code, UpdateRefusalCode.unknownKey);

      final Uint8List flipped = Uint8List.fromList(await staged.apk.readAsBytes())..[kChunk + 5] ^= 1;
      expect((await tablet.acceptHandedOver(staged.manifestDocument, Stream<List<int>>.value(flipped)))!.code, UpdateRefusalCode.hashMismatch);
      expect(tablet.phase, isNot(UpdatePhase.ready));

      same.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
      expect((await tablet.acceptHandedOver(staged.manifestDocument, staged.apk.openRead()))!.code, UpdateRefusalCode.rollback);
    });
  });

  group('Google Play', () {
    Future<(Rig, AppUpdater)> playRig() async {
      final Rig r = await Rig.create(environment: wifiPhone(flavor: 'play'), manifestUrls: const <String>[]);
      addTearDown(r.dispose);
      final AppUpdater u = r.updater(play: true);
      await u.start();
      return (r, u);
    }

    test('the Play build is present with no source at all, and asks Google Play', () async {
      final (Rig r, AppUpdater u) = await playRig();
      expect(u.enabled, isTrue);
      r.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true, immediateAllowed: true);
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      expect(r.transport.getLog, isEmpty);
    });

    test('nothing available: up to date; a sideloaded copy of the Play build: the feature steps aside', () async {
      final (Rig r, AppUpdater u) = await playRig();
      await u.checkNow();
      expect(u.phase, UpdatePhase.upToDate);
      r.play.info = const PlayUpdateInfo(available: false, supported: false);
      await u.checkNow();
      expect(u.phase, UpdatePhase.off);
    });

    test('flexible by default; immediate only when Play allows it and the update is critical', () async {
      final (Rig r, AppUpdater u) = await playRig();
      r.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true, immediateAllowed: true, priority: 1);
      await u.checkNow();
      await u.startPlayUpdate();
      expect(r.play.starts, <bool>[false]);
      final (Rig r2, AppUpdater u2) = await playRig();
      r2.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true, immediateAllowed: true, priority: 5);
      await u2.checkNow();
      await u2.startPlayUpdate();
      expect(r2.play.starts, <bool>[true]);
      expect(const PlayUpdateInfo(available: true, immediateAllowed: false, priority: 5).preferImmediate, isFalse);
    });

    test('progress, "ready to restart", and the restart', () async {
      final (Rig r, AppUpdater u) = await playRig();
      r.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true);
      await u.checkNow();
      await u.startPlayUpdate();
      expect(u.phase, UpdatePhase.downloading);
      expect(u.state.pending, isNotNull);
      r.play.events.add(const PlayEvent(PlayStatus.downloading, doneBytes: 10, totalBytes: 40));
      await Future<void>.delayed(Duration.zero);
      expect(u.progress!.fraction, 0.25);
      r.play.events.add(const PlayEvent(PlayStatus.downloaded));
      await Future<void>.delayed(Duration.zero);
      expect(u.phase, UpdatePhase.ready);
      await u.finishPlayUpdate();
      expect(r.play.completes, 1);
    });

    test('declined or failed in Play: back to "an update is available", or an honest failure; nothing is left pending', () async {
      final (Rig r, AppUpdater u) = await playRig();
      r.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true);
      await u.checkNow();
      r.play.startResult = false;
      await u.startPlayUpdate();
      expect(u.phase, UpdatePhase.available);
      r.play.startResult = true;
      await u.startPlayUpdate();
      r.play.events.add(const PlayEvent(PlayStatus.cancelled));
      await Future<void>.delayed(Duration.zero);
      expect(u.phase, UpdatePhase.available);
      expect(u.state.pending, isNull);
      await u.startPlayUpdate();
      r.play.events.add(const PlayEvent(PlayStatus.failed));
      await Future<void>.delayed(Duration.zero);
      expect(u.phase, UpdatePhase.failed);
    });

    test('Play unreachable: an honest "could not reach", the phone is not stuck', () async {
      final (Rig r, AppUpdater u) = await playRig();
      r.play.checkError = StateError('no play');
      await u.checkNow();
      expect(u.failure, UpdateRefusalCode.offline);
      expect(u.phase, UpdatePhase.idle);
    });

    test('a configured manifest only adds the plain-words notes and the minimum; Play still does the update', () async {
      final Rig r = await Rig.create(environment: wifiPhone(flavor: 'play'));
      addTearDown(r.dispose);
      await r.publish(apk, tweak: (Map<String, Object?> d) => d..['minSupportedVersionCode'] = 5150, files: false);
      r.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true);
      final AppUpdater u = r.updater(play: true);
      await u.start();
      await u.checkNow();
      expect(u.phase, UpdatePhase.available);
      expect(u.manifest!.notes, hasLength(2));
      expect(u.belowMinimum, isTrue);
      expect(r.transport.openLog, isEmpty, reason: 'no file is ever fetched in the Play build');
    });
  });
}

class _ThrowingEnv implements UpdateEnvironmentSource {
  @override
  Future<UpdateEnvironment> read() async => throw StateError('no native side');
}
