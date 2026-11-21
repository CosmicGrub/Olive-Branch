// OLIVE BRANCH — the tablet update service: installing without breaking the kiosk, repeating every check at the moment
// of installing, results in grown-up words, the "what is new" once, resuming after the app restarts, the fallback where
// the tablet fetches the update itself, and the phone's sharing. Headless.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_loopback.dart';
import 'package:olive_client/tablet_update_port.dart';
import 'package:olive_client/tablet_update_sender.dart';
import 'package:olive_client/tablet_update_service.dart';
import 'package:olive_client/tablet_update_store.dart';

import 'tablet_update_harness.dart';

class RecordingKiosk implements InstallKioskHandoff {
  final List<String> log;
  RecordingKiosk(this.log);
  @override
  Future<String> begin() async {
    log.add('kiosk.begin');
    return 'pinned';
  }

  @override
  Future<void> end() async => log.add('kiosk.end');
}

class LoggingEngine extends ReferenceEngine {
  LoggingEngine({required super.dir, required this.log, super.installedVersionCode});
  final List<String> log;
  @override
  Future<VerifiedUpdate> verify(Uint8List document, {required bool forInstall}) {
    if (forInstall) log.add('engine.verify.install');
    return super.verify(document, forInstall: forInstall);
  }

  @override
  Future<InstallOutcome> install(File apk, VerifiedUpdate update) {
    log.add('engine.install');
    return super.install(apk, update);
  }
}

class Setup {
  Setup(this.dir, this.engine, this.store, this.service, this.log, this.fixture);
  final Directory dir;
  final LoggingEngine engine;
  final MemoryStagedUpdateStore store;
  final TabletUpdateService service;
  final List<String> log;
  final Fixture fixture;
  bool adult = true;
  File get stagedFile => File('${dir.path}/update-5200.apk');

  static Future<Setup> make({int installed = 5100, bool stage = true}) async {
    final Directory dir = await Directory.systemTemp.createTemp('olive_service_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final List<String> log = <String>[];
    final LoggingEngine e = LoggingEngine(dir: dir, log: log, installedVersionCode: installed);
    final MemoryStagedUpdateStore store = MemoryStagedUpdateStore();
    final TabletUpdateService svc = TabletUpdateService(engine: e, store: store, kiosk: RecordingKiosk(log));
    final Fixture f = await makeFixture(size: 100 * 1024, chunkSize: 32 * 1024);
    final Setup s = Setup(dir, e, store, svc, log, f);
    if (stage) await s.stage();
    return s;
  }

  /// Puts a verified update on disk as the receiver would have left it.
  Future<void> stage() async {
    final VerifiedUpdate u = await engine.verify(fixture.document, forInstall: false);
    await File('${dir.path}/update-5200.apk').writeAsBytes(fixture.apk);
    await store.saveStaged(StagedUpdate(
        stage: StageState.ready,
        versionName: u.versionName,
        versionCode: u.versionCode,
        fileName: 'update-5200.apk',
        document: fixture.document,
        headline: u.headline,
        notes: u.notes));
    log.clear();
    await service.refresh();
  }
}

void main() {
  group('installing', () {
    test('every check runs first, the lock is released only then, and the system installer is shown last', () async {
      final Setup s = await Setup.make();
      expect(s.service.view, TabletUpdateView.ready);
      final TabletUpdateCode? r = await s.service.install(adultPresent: () => s.adult);
      expect(r, isNull, reason: 'Android\'s confirmation was shown');
      expect(s.log, <String>['engine.verify.install', 'kiosk.begin', 'engine.install'],
          reason: 'the notice is verified again, then the pin is let go, then the installer');
      final StagedUpdate st = (await s.store.loadStaged())!;
      expect(st.stage, StageState.installing);
      expect(st.fromVersionCode, 5100, reason: 'the "update began" marker names the version that was running');
      expect(st.installStartedAtMs, isNotNull);
      expect(s.service.view, TabletUpdateView.installing);
    });

    test('Android declining puts the lock back and the update stays ready, with calm words', () async {
      final Setup s = await Setup.make();
      s.engine.nextOutcome = InstallOutcome.declined;
      final TabletUpdateCode? r = await s.service.install(adultPresent: () => s.adult);
      expect(r, TabletUpdateCode.installDeclined);
      expect(s.log, <String>['engine.verify.install', 'kiosk.begin', 'engine.install', 'kiosk.end']);
      expect((await s.store.loadStaged())!.stage, StageState.ready);
      expect(s.stagedFile.existsSync(), isTrue, reason: 'nothing is thrown away because it was not installed');
      expect(s.service.view, TabletUpdateView.ready);
      expect(tabletUpdateAdultWords(r!), contains('still ready'));
    });

    test('"Install unknown apps" not yet allowed is reported in plain words and the lock goes back', () async {
      final Setup s = await Setup.make();
      s.engine.nextOutcome = InstallOutcome.needsPermission;
      expect(await s.service.install(adultPresent: () => s.adult), TabletUpdateCode.needsPermission);
      expect(s.log.last, 'kiosk.end');
      expect(tabletUpdateAdultWords(TabletUpdateCode.needsPermission), contains('Allow'));
    });

    test('an installer that throws is "could not install", the lock goes back, the file stays', () async {
      final Setup s = await Setup.make();
      s.engine.nextOutcome = InstallOutcome.failed;
      expect(await s.service.install(adultPresent: () => s.adult), TabletUpdateCode.installFailed);
      expect(s.log.last, 'kiosk.end');
      expect(s.stagedFile.existsSync(), isTrue);
    });

    test('a child cannot install: with no grown-up proved nothing is checked, nothing is released, nothing is shown', () async {
      final Setup s = await Setup.make();
      s.adult = false;
      expect(await s.service.install(adultPresent: () => s.adult), TabletUpdateCode.notAllowed);
      expect(s.log, isEmpty, reason: 'no verify, no kiosk release, no installer');
      expect((await s.store.loadStaged())!.stage, StageState.ready);
    });

    test('a grown-up who walks away while the checks run does not leave an install armed', () async {
      final Setup s = await Setup.make();
      int looks = 0;
      final TabletUpdateCode? r = await s.service.install(adultPresent: () => ++looks <= 1);
      expect(r, TabletUpdateCode.notAllowed);
      expect(s.log, isNot(contains('kiosk.begin')));
      expect(s.log, isNot(contains('engine.install')));
    });

    test('the file is checked again from the bytes on the disk NOW: a changed file is thrown away and never installed', () async {
      final Setup s = await Setup.make();
      final Uint8List bad = Uint8List.fromList(s.fixture.apk)..[5000] ^= 1;
      await s.stagedFile.writeAsBytes(bad);
      expect(await s.service.install(adultPresent: () => s.adult), TabletUpdateCode.changedOnDisk);
      expect(s.log, <String>['engine.verify.install']);
      expect(s.stagedFile.existsSync(), isFalse);
      expect(await s.store.loadStaged(), isNull);
    });

    test('a file cut short on the disk is refused the same way', () async {
      final Setup s = await Setup.make();
      await s.stagedFile.writeAsBytes(s.fixture.apk.sublist(0, 50 * 1024));
      expect(await s.service.install(adultPresent: () => s.adult), TabletUpdateCode.changedOnDisk);
      expect(s.log, isNot(contains('engine.install')));
    });

    test('a file swapped for another app on the disk is refused: the platform reads its own package', () async {
      final Setup s = await Setup.make();
      // Same size, so only the inspection can tell; the hash differs too, so the file is "changed".
      await s.stagedFile.writeAsBytes(makeApkBytes(size: s.fixture.apk.length, pkg: 'com.example.other'));
      expect(await s.service.install(adultPresent: () => s.adult), TabletUpdateCode.changedOnDisk);
      expect(s.log, isNot(contains('kiosk.begin')));
    });

    test('rollback at install time: if the app has meanwhile become the same version or newer, nothing is installed', () async {
      for (final int installed in <int>[5200, 5300]) {
        final Setup s = await Setup.make();
        s.engine.installedVersionCode = installed;
        final TabletUpdateCode? r = await s.service.install(adultPresent: () => s.adult);
        expect(r, installed == 5200 ? TabletUpdateCode.upToDate : TabletUpdateCode.older, reason: '$installed');
        expect(s.log, isNot(contains('engine.install')));
        expect(s.log, isNot(contains('kiosk.begin')));
      }
    });

    test('a notice that went out of date while staged is refused at install time (the engine says so)', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_service_exp_');
      addTearDown(() => dir.delete(recursive: true));
      final List<String> log = <String>[];
      // A clock after the notice's expiry.
      final LoggingEngine late = LoggingEngine(dir: dir, log: log, installedVersionCode: 5100);
      final Fixture f = await makeFixture(size: 100 * 1024, expires: DateTime.utc(2026, 12, 1));
      final MemoryStagedUpdateStore store = MemoryStagedUpdateStore();
      await File('${dir.path}/update-5200.apk').writeAsBytes(f.apk);
      await store.saveStaged(StagedUpdate(stage: StageState.ready, versionName: '0.52.0', versionCode: 5200, fileName: 'update-5200.apk', document: f.document));
      final ReferenceEngine future = ReferenceEngine(dir: dir, installedVersionCode: 5100, now: DateTime.utc(2027, 1, 1));
      final TabletUpdateService svc = TabletUpdateService(engine: future, store: store, kiosk: RecordingKiosk(log));
      expect(late.available, isTrue);
      expect(await svc.install(adultPresent: () => true), TabletUpdateCode.expired);
      expect(future.installs, isEmpty);
    });

    test('no update machinery: every action is "not set up" and nothing happens', () async {
      final Setup s = await Setup.make();
      s.engine.hasKey = false;
      expect(await s.service.install(adultPresent: () => true), TabletUpdateCode.noEngine);
      await s.service.startReceiving(adultPresent: () => true);
      expect(s.service.result, TabletUpdateCode.noEngine);
      expect(s.service.available, isFalse);
      expect(s.log, isEmpty);
    });
  });

  group('after the install, or after a restart', () {
    test('the app IS the new version: the staged file goes, a one-time "what is new" is kept for a grown-up', () async {
      final Setup s = await Setup.make();
      await s.service.install(adultPresent: () => s.adult);
      // The app was replaced and restarted: a new process, a new service, the same store and folder.
      s.engine.installedVersionCode = 5200;
      final TabletUpdateService fresh = TabletUpdateService(engine: s.engine, store: s.store, kiosk: RecordingKiosk(<String>[]));
      await fresh.refresh();
      expect(fresh.staged, isNull);
      expect(s.stagedFile.existsSync(), isFalse, reason: 'the 100 MB copy does not stay on the tablet');
      expect(fresh.whatsNew, isNotNull);
      expect(fresh.whatsNew!.versionName, '0.52.0');
      expect(fresh.whatsNew!.notes, isNotEmpty);
      expect(fresh.view, TabletUpdateView.none);
      await fresh.dismissWhatsNew();
      expect(fresh.whatsNew, isNull);
      final TabletUpdateService again = TabletUpdateService(engine: s.engine, store: s.store, kiosk: RecordingKiosk(<String>[]));
      await again.refresh();
      expect(again.whatsNew, isNull, reason: 'shown once');
    });

    test('the app is NOT the new version after a restart: the update goes back to ready, with a calm result, nothing lost', () async {
      final Setup s = await Setup.make();
      await s.service.install(adultPresent: () => s.adult);
      final TabletUpdateService fresh = TabletUpdateService(engine: s.engine, store: s.store, kiosk: RecordingKiosk(<String>[]));
      await fresh.refresh();
      expect(fresh.view, TabletUpdateView.ready);
      expect(fresh.result, TabletUpdateCode.installDeclined);
      expect(fresh.staged!.stage, StageState.ready);
      expect(s.stagedFile.existsSync(), isTrue);
      expect(fresh.whatsNew, isNull);
    });

    test('coming forward again in the same run, with the app unchanged, means the install did not happen', () async {
      DateTime t = DateTime.utc(2026, 11, 21, 10);
      final Setup s = await Setup.make();
      final TabletUpdateService svc = TabletUpdateService(engine: s.engine, store: s.store, kiosk: RecordingKiosk(s.log), now: () => t);
      await svc.refresh();
      expect(await svc.install(adultPresent: () => true), isNull);
      expect(svc.view, TabletUpdateView.installing);
      // A refresh while the installer is on screen must NOT call it a failure.
      await svc.refresh();
      expect(svc.view, TabletUpdateView.installing);
      // The app comes forward a moment later, not replaced.
      t = t.add(const Duration(seconds: 20));
      svc.appResumed();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(svc.view, TabletUpdateView.ready);
      expect(svc.result, TabletUpdateCode.installDeclined);
    });

    test('a resume in the first moments (the dialog opening) is not mistaken for a cancel', () async {
      final DateTime t = DateTime.utc(2026, 11, 21, 10);
      final Setup s = await Setup.make();
      final TabletUpdateService svc = TabletUpdateService(engine: s.engine, store: s.store, kiosk: RecordingKiosk(s.log), now: () => t);
      await svc.refresh();
      await svc.install(adultPresent: () => true);
      svc.appResumed();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(svc.view, TabletUpdateView.installing);
    });

    test('a staged record whose file has vanished is cleaned up quietly, not shown', () async {
      final Setup s = await Setup.make();
      await s.stagedFile.delete();
      await s.service.refresh();
      expect(s.service.staged, isNull);
      expect(await s.store.loadStaged(), isNull);
      expect(s.service.view, TabletUpdateView.none);
    });

    test('a half-received record from an earlier run is dropped, not offered', () async {
      final Setup s = await Setup.make(stage: false);
      await s.store.saveStaged(StagedUpdate(
          stage: StageState.receiving, versionName: '0.52.0', versionCode: 5200, fileName: 'x.part', document: s.fixture.document));
      await s.service.refresh();
      expect(s.service.staged, isNull);
    });
  });

  group('the tablet fetches it itself (the fallback)', () {
    test('an update the engine found is taken through the SAME checks and staged; then installed the same way', () async {
      final Setup s = await Setup.make(stage: false);
      s.engine.ownFixture = s.fixture;
      s.engine.own = OwnUpdateOffer(update: await s.engine.verify(s.fixture.document, forInstall: false));
      await s.service.refresh();
      expect(s.service.ownOffer, isNotNull);
      await s.service.fetchOwn(adultPresent: () => true);
      expect(s.service.view, TabletUpdateView.ready);
      expect(s.stagedFile.existsSync(), isTrue);
      expect(await s.service.install(adultPresent: () => true), isNull);
      expect(s.log, contains('kiosk.begin'));
    });

    test('a download the engine returns that does not match its notice is refused, not staged', () async {
      final Setup s = await Setup.make(stage: false);
      final Fixture other = await makeFixture(size: 100 * 1024, chunkSize: 32 * 1024, apkOverride: makeApkBytes(size: 100 * 1024, seed: 99));
      s.engine.ownFixture = other; // different bytes than the notice describes
      s.engine.own = OwnUpdateOffer(update: await s.engine.verify(s.fixture.document, forInstall: false));
      await s.service.fetchOwn(adultPresent: () => true);
      expect(s.service.result, TabletUpdateCode.hashMismatch);
      expect(await s.store.loadStaged(), isNull);
    });

    test('a child cannot start a download, and nothing is offered when there is nothing newer', () async {
      final Setup s = await Setup.make(stage: false);
      s.engine.own = null;
      await s.service.fetchOwn(adultPresent: () => false);
      expect(s.service.result, TabletUpdateCode.notAllowed);
      await s.service.fetchOwn(adultPresent: () => true);
      expect(s.service.result, TabletUpdateCode.upToDate);
    });
  });

  group('the phone shares', () {
    test('only with a held update and a grown-up proved; the sender is a grown-up-device sender', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_share_');
      addTearDown(() => dir.delete(recursive: true));
      final (LoopbackPlayTransport a, LoopbackPlayTransport b) = LoopbackPlayTransport.pair();
      expect(b, isNotNull);
      final ReferenceEngine phone = ReferenceEngine(dir: dir);
      final Fixture f = await makeFixture(size: 100 * 1024);
      final TabletUpdateService svc = TabletUpdateService(
        engine: phone,
        store: MemoryStagedUpdateStore(),
        kiosk: RecordingKiosk(<String>[]),
        linkFactory: ({required bool grownUp}) async => UpdateLink(a, () async {}),
      );
      await svc.startSharing(adultPresent: () => true);
      expect(svc.result, TabletUpdateCode.cancelled, reason: 'no update held: nothing is offered');
      phone.heldUpdate = await heldFrom(f, phone, dir);
      await svc.startSharing(adultPresent: () => false);
      expect(svc.result, TabletUpdateCode.notAllowed);
      expect(svc.sender, isNull);
      await svc.startSharing(adultPresent: () => true);
      expect(svc.sender!.phase, SenderPhase.offering);
      await svc.stopSharing();
      expect(svc.sender, isNull);
    });
  });
}
