// What a grown-up sees: Settings > App updates in every state, and the gentle line on the home screen. Plain words,
// honest results, nothing that locks, and nothing at all where there is no updater. MASTERFILE 7.24.
//
// The controller does real file work, so each test first brings it to the state under test inside runAsync, then pumps
// the screen.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_controller.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_platform.dart';
import 'package:olive_client/update_screens.dart';
import 'package:olive_client/update_transport.dart';

import 'update_support.dart';

/// The words for "now" in THIS machine's own time zone (the screen shows local time; a test must not assume one).
String _todayAt(DateTime t) {
  final DateTime l = t.toLocal();
  return 'today at ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

void main() {
  late Rig rig;
  late Uint8List apk;
  const int kChunk = 65536;

  setUp(() async {
    rig = (await Rig.create());
    apk = fakeApk(kChunk * 2 + 999);
  });

  Future<void> pumpScreen(WidgetTester t, AppUpdater u, {Size size = const Size(400, 1400), Widget? child}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      // The scope sits above the Navigator, as in the app, so a page pushed from a card can still reach the updater.
      builder: (BuildContext context, Widget? page) => UpdateScope(updater: u, child: page!),
      home: child ?? AppUpdatesScreen(updater: u, now: () => kNow),
    ));
    await t.pump();
  }

  AppUpdater? current;

  /// A started updater brought to [then] with real I/O.
  Future<AppUpdater> prepared(WidgetTester t, {Future<void> Function(AppUpdater u)? then, Rig? r}) async {
    final Rig use = r ?? rig;
    late AppUpdater u;
    await t.runAsync(() async {
      u = use.updater();
      await u.start();
      if (then != null) await then(u);
    });
    addTearDown(u.dispose);
    current = u;
    return u;
  }

  /// Lets the real file work of the controller finish (it is real I/O, so it runs inside runAsync), then redraws. Waits
  /// until the updater is no longer busy, so a slow disk makes a test slower, never flaky.
  Future<void> settle(WidgetTester t) async {
    // The controller's file work is real I/O whose continuations run in the test's fake-async zone, so the zone is
    // pumped between every real wait; otherwise a chain of awaits would never advance.
    int quiet = 0;
    for (int i = 0; i < 400 && quiet < 3; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump(const Duration(milliseconds: 25));
      quiet = (current?.busy ?? false) ? 0 : quiet + 1;
    }
    await t.pump();
  }

  Future<void> publish() async => rig.publish(apk);

  testWidgets('a build with no updater shows a plain "not set up" page and the home line is absent', (t) async {
    final Rig none = await t.runAsync(() => Rig.create(manifestUrls: const <String>[])) as Rig;
    final AppUpdater u = await prepared(t, r: none);
    await pumpScreen(t, u);
    expect(find.byKey(const Key('updatesOff')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: UpdateScope(updater: u, child: const UpdateBanner()))));
    expect(find.byType(Card), findsNothing);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: UpdateBanner())));
    expect(find.byType(Card), findsNothing, reason: 'no scope at all: nothing');
  });

  testWidgets('before the first check: the version, "Check now", and the last-check line says "not yet"', (t) async {
    final AppUpdater u = await prepared(t);
    await pumpScreen(t, u);
    expect(find.text('Olive has not checked yet'), findsOneWidget);
    expect(find.text('Version 0.51.0'), findsOneWidget);
    expect(find.text('Last checked: not yet'), findsOneWidget);
    expect(find.byKey(const Key('updateCheckNow')), findsOneWidget);
  });

  testWidgets('up to date: says so, with the time of the check', (t) async {
    rig.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
    await publish();
    final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
    await pumpScreen(t, u);
    expect(find.text('Olive is up to date'), findsOneWidget);
    expect(find.text('Last checked: ${_todayAt(kNow)}'), findsOneWidget);
    expect(find.byKey(const Key('updateDownloadWifi')), findsNothing);
  });

  testWidgets('"Check now" finds the update and shows it in plain words with release notes', (t) async {
    await publish();
    final AppUpdater u = await prepared(t);
    await pumpScreen(t, u);
    await t.tap(find.byKey(const Key('updateCheckNow')));
    await settle(t);
    expect(find.text('An update is ready'), findsOneWidget);
    expect(find.text('Olive 0.52.0 · about 0 MB'.replaceFirst('about 0 MB', 'under 1 MB')), findsOneWidget);
    expect(find.text('Calmer messages'), findsOneWidget);
    expect(find.text('• Messages open a little faster.'), findsOneWidget);
    expect(find.text('• A quieter morning screen.'), findsOneWidget);
    expect(find.byKey(const Key('updateDownloadWifi')), findsOneWidget);
    expect(find.byKey(const Key('updateDownloadNow')), findsOneWidget);
    expect(find.byKey(const Key('updateLater')), findsOneWidget);
    // Plain words: none of the engineer's words reaches the screen.
    for (final String jargon in <String>['APK', 'apk', 'sha', 'SHA', 'signature', 'manifest', 'hash', 'sideload']) {
      expect(find.textContaining(jargon), findsNothing, reason: jargon);
    }
  });

  testWidgets('the size is in words an adult understands', (t) async {
    expect(updateSizeWords(85 * 1024 * 1024), 'about 85 MB');
    expect(updateSizeWords(100), 'under 1 MB');
    expect(updateTimeWords(null, kNow), 'not yet');
  });

  testWidgets('"Download on Wi-Fi" on Wi-Fi downloads and offers "Install"; the system asks next', (t) async {
    await publish();
    final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
    await pumpScreen(t, u);
    await t.tap(find.byKey(const Key('updateDownloadWifi')));
    await settle(t);
    await settle(t);
    expect(find.text('Ready to install'), findsOneWidget);
    expect(find.textContaining('Android will ask you to confirm'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateInstall')));
    await settle(t);
    expect(find.text('Waiting for Android'), findsOneWidget);
    expect(rig.installer.installs, hasLength(1));
  });

  testWidgets('on mobile data "Download on Wi-Fi" waits and says exactly what will happen', (t) async {
    await publish();
    final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
    rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
    await pumpScreen(t, u);
    await t.tap(find.byKey(const Key('updateDownloadWifi')));
    await settle(t);
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    expect(find.textContaining('next time this phone is on Wi-Fi'), findsOneWidget);
    expect(rig.transport.openLog, isEmpty);
  });

  testWidgets('"Download now" off Wi-Fi asks first (the size, mobile data), and "Not now" changes nothing', (t) async {
    await publish();
    final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
    rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true);
    await t.runAsync(() => u.checkNow());
    await pumpScreen(t, u);
    await t.tap(find.byKey(const Key('updateDownloadNow')));
    await t.pump();
    expect(find.byKey(const Key('updateMobileDataDialog')), findsOneWidget);
    expect(find.textContaining('may use your mobile data'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateMobileDataNo')));
    await t.pumpAndSettle();
    expect(rig.transport.openLog, isEmpty);
    await t.tap(find.byKey(const Key('updateDownloadNow')));
    await t.pump();
    await t.tap(find.byKey(const Key('updateMobileDataYes')));
    await t.pump();
    await settle(t);
    await settle(t);
    expect(find.text('Ready to install'), findsOneWidget);
  });

  testWidgets('roaming is named in the question', (t) async {
    await publish();
    final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
    rig.env.value = wifiPhone(network: NetworkKind.cellular, metered: true, roaming: true);
    await t.runAsync(() => u.checkNow());
    await pumpScreen(t, u);
    await t.tap(find.byKey(const Key('updateDownloadNow')));
    await t.pump();
    expect(find.textContaining('roaming'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateMobileDataNo')));
    await t.pumpAndSettle();
  });

  testWidgets('while it downloads: a progress bar, "N MB of M MB", and Stop (which keeps what was fetched)', (t) async {
    await publish();
    rig.transport.pieceDelay = const Duration(milliseconds: 40);
    final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
    await pumpScreen(t, u);
    late Future<void> running;
    await t.runAsync(() async {
      running = u.downloadNow();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await t.pump();
    expect(find.text('Downloading the update'), findsOneWidget);
    expect(find.byKey(const Key('updateProgress')), findsOneWidget);
    expect(find.byKey(const Key('updateProgressText')), findsOneWidget);
    expect(find.textContaining(' MB of '), findsOneWidget);
    await t.tap(find.byKey(const Key('updateStop')));
    await t.runAsync(() => running);
    await t.pump();
    expect(find.text('An update is ready'), findsOneWidget, reason: 'stopped: back to the offer, nothing lost');
  });

  testWidgets('"Install unknown apps" not allowed yet: says why and opens Android\'s page', (t) async {
    await publish();
    final AppUpdater u = await prepared(t, then: (AppUpdater u) async {
      await u.checkNow();
      await u.downloadNow();
    });
    rig.installer.canInstall = false;
    await pumpScreen(t, u);
    await t.tap(find.byKey(const Key('updateInstall')));
    await settle(t);
    expect(find.text('One thing to allow first'), findsOneWidget);
    expect(find.textContaining('Nothing is installed until you confirm'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateOpenSettings')));
    await settle(t);
    expect(rig.installer.settingsOpened, 1);
  });

  group('honest failures (each says what was NOT done)', () {
    testWidgets('a download that did not match: deleted, nothing installed, try again', (t) async {
      await publish();
      rig.transport.files[kPrimary] = FileBehavior(apk, corrupt: 9);
      rig.transport.files[kMirror] = FileBehavior(apk, corrupt: 9);
      final AppUpdater u = await prepared(t, then: (AppUpdater u) async {
        await u.checkNow();
        await u.downloadNow();
      });
      await pumpScreen(t, u);
      expect(find.text('That did not work'), findsOneWidget);
      expect(find.byKey(const Key('updateFailure')), findsOneWidget);
      expect(find.textContaining('Nothing was installed'), findsOneWidget);
      expect(find.byKey(const Key('updateCheckNow')), findsOneWidget);
    });

    testWidgets('a wrong signing certificate: says the file was not made by the same maker, and that nothing was installed', (t) async {
      await publish();
      rig.installer.signers = <String>[certHash('someone else')];
      final AppUpdater u = await prepared(t, then: (AppUpdater u) async {
        await u.checkNow();
        await u.downloadNow();
        await u.install();
      });
      await pumpScreen(t, u);
      expect(find.textContaining('not made by the same maker'), findsOneWidget);
      expect(find.textContaining('Nothing was installed'), findsOneWidget);
    });

    testWidgets('offline: an honest "could not reach", the found update stays on screen', (t) async {
      await publish();
      final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
      rig.env.value = wifiPhone(network: NetworkKind.none);
      await t.runAsync(() => u.checkNow());
      await pumpScreen(t, u);
      expect(find.text('An update is ready'), findsOneWidget);
      expect(find.textContaining('may have no connection'), findsOneWidget);
    });

    testWidgets('the install did not finish: says nothing changed and offers it again', (t) async {
      await publish();
      final AppUpdater u = await prepared(t, then: (AppUpdater u) async {
        await u.checkNow();
        await u.downloadNow();
        await u.install();
      });
      rig.installer.events.add(const InstallEvent(InstallOutcome.declined));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await pumpScreen(t, u);
      expect(find.text('Ready to install'), findsOneWidget);
      expect(find.textContaining('did not finish. Nothing was changed'), findsOneWidget);
      expect(find.byKey(const Key('updateInstall')), findsOneWidget);
    });

    testWidgets('every failure code has words, and none of them leaks a URL, a path or a code name', (t) async {
      for (final UpdateRefusalCode c in UpdateRefusalCode.values) {
        final String w = updateFailureWords(c);
        expect(w.trim(), isNotEmpty, reason: c.name);
        expect(w, isNot(contains('http')), reason: c.name);
        expect(w, isNot(contains('/')), reason: c.name);
        expect(w, isNot(contains(c.name)), reason: c.name);
        expect(w.length, lessThan(220), reason: c.name);
      }
    });
  });

  group('below the minimum: a kind notice, and nothing locked', () {
    testWidgets('the card says please update and that nothing is lost or locked; every button still works', (t) async {
      await rig.publish(apk, tweak: (Map<String, Object?> d) => d..['minSupportedVersionCode'] = 5150);
      final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
      await pumpScreen(t, u);
      expect(find.byKey(const Key('updateBelowMinimum')), findsOneWidget);
      expect(find.textContaining('Please update'), findsOneWidget);
      expect(find.textContaining('nothing will be lost or locked'), findsOneWidget);
      expect(find.byKey(const Key('updateDownloadNow')), findsOneWidget);
      expect(find.byKey(const Key('updateLater')), findsOneWidget);
      expect(find.byKey(const Key('updateAutoCheck')), findsOneWidget);
    });

    testWidgets('on the home screen: the line is there, the rest of the home is untouched, and "Later" does not hide it', (t) async {
      await rig.publish(apk, tweak: (Map<String, Object?> d) => d..['minSupportedVersionCode'] = 5150);
      final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
      await pumpScreen(t, u, child: const Scaffold(body: Column(children: <Widget>[UpdateBanner(), Text('Everything else on the home screen')])));
      expect(find.byKey(const Key('updateBannerPlease')), findsOneWidget);
      expect(find.text('Please update Olive'), findsOneWidget);
      expect(find.text('Everything else on the home screen'), findsOneWidget);
      expect(find.byKey(const Key('updateBannerLater')), findsNothing);
    });
  });

  group('the gentle line on the home screen', () {
    Widget home() => const Scaffold(body: Column(children: <Widget>[UpdateBanner(), Text('home content')]));

    testWidgets('"An update is ready" with Later; Later puts it away; See opens the page', (t) async {
      await publish();
      final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
      await pumpScreen(t, u, child: home());
      expect(find.byKey(const Key('updateBannerReady')), findsOneWidget);
      expect(find.text('An update is ready'), findsOneWidget);
      expect(find.text('Olive 0.52.0 is available.'), findsOneWidget);
      await t.tap(find.byKey(const Key('updateBannerLater')));
      await settle(t);
      expect(find.byKey(const Key('updateBannerReady')), findsNothing);
      expect(find.text('home content'), findsOneWidget);
    });

    testWidgets('See the update opens Settings > App updates', (t) async {
      await publish();
      final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
      await pumpScreen(t, u, child: Builder(builder: (BuildContext c) => const Scaffold(body: Column(children: <Widget>[UpdateBanner()]))));
      await t.tap(find.text('See the update'));
      await t.pumpAndSettle();
      expect(find.text('App updates'), findsWidgets);
      expect(find.byKey(const Key('updateDownloadWifi')), findsOneWidget);
    });

    testWidgets('nothing when there is nothing to say (up to date, or not checked)', (t) async {
      final AppUpdater u = await prepared(t);
      await pumpScreen(t, u, child: home());
      expect(find.byType(Card), findsNothing);
      expect(find.text('home content'), findsOneWidget);
    });

    testWidgets('after an update: "Olive was updated to 0.52.0", Got it clears it, and the page shows the notes until then', (t) async {
      await publish();
      await t.runAsync(() async {
        final AppUpdater first = rig.updater();
        await first.start();
        await first.checkNow();
        await first.downloadNow();
        await first.install();
      });
      rig.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
      final AppUpdater u = await prepared(t);
      await pumpScreen(t, u, child: home());
      expect(find.byKey(const Key('updateBannerWhatsNew')), findsOneWidget);
      expect(find.text('Olive was updated to 0.52.0'), findsOneWidget);
      expect(find.text('Calmer messages'), findsOneWidget);
      await t.tap(find.byKey(const Key('updateBannerGotIt')));
      await settle(t);
      expect(find.byKey(const Key('updateBannerWhatsNew')), findsNothing);
      expect(u.whatsNew, isNull);
    });

    testWidgets('the page shows the notes and the data note, and Got it clears them', (t) async {
      await publish();
      await t.runAsync(() async {
        final AppUpdater first = rig.updater();
        await first.start();
        await first.checkNow();
        await first.downloadNow();
        await first.install();
      });
      rig.areas = 3;
      rig.env.value = wifiPhone(versionCode: 5200, versionName: '0.52.0');
      final AppUpdater u = await prepared(t);
      await pumpScreen(t, u);
      expect(find.text("What's new in 0.52.0"), findsOneWidget);
      expect(find.text('• Messages open a little faster.'), findsOneWidget);
      expect(find.byKey(const Key('updateDataNote')), findsOneWidget);
      expect(find.text('Last updated to 0.52.0 ${_todayAt(kNow)}'), findsOneWidget);
      await t.tap(find.byKey(const Key('updateWhatsNewGotIt')));
      await settle(t);
      expect(find.byKey(const Key('updateWhatsNew')), findsNothing);
    });
  });

  group('choices', () {
    testWidgets('the switches change the saved choices (Wi-Fi only starts ON)', (t) async {
      final AppUpdater u = await prepared(t);
      await pumpScreen(t, u);
      expect(u.state.wifiOnly, isTrue);
      expect(u.state.autoCheck, isTrue);
      await t.tap(find.byKey(const Key('updateWifiOnly')));
      await settle(t);
      expect(u.state.wifiOnly, isFalse);
      await t.tap(find.byKey(const Key('updateAutoCheck')));
      await settle(t);
      expect(u.state.autoCheck, isFalse);
    });

    testWidgets('a source: an insecure address is refused with a plain reason; a secure one is taken and shown by host; reset', (t) async {
      final AppUpdater u = await prepared(t);
      await pumpScreen(t, u);
      expect(find.text('Where updates come from: updates.example.org'), findsOneWidget);
      await t.enterText(find.byKey(const Key('updateSourceField')), 'http://updates.example.org/manifest.json');
      await t.ensureVisible(find.byKey(const Key('updateSourceSave')));
      await t.tap(find.byKey(const Key('updateSourceSave')));
      await settle(t);
      expect(find.textContaining('secure web address'), findsOneWidget);
      expect(u.manifestUrls, <String>[kManifestUrl]);
      await t.enterText(find.byKey(const Key('updateSourceField')), 'https://family.example.org/olive/manifest.json');
      await t.tap(find.byKey(const Key('updateSourceSave')));
      await settle(t);
      expect(find.text('Where updates come from: family.example.org'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('updateSourceReset')));
      await t.tap(find.byKey(const Key('updateSourceReset')));
      await settle(t);
      expect(find.text('Where updates come from: updates.example.org'), findsOneWidget);
    });

    testWidgets('the channel: Stable by default; Early (beta) can be chosen and the page says what that means', (t) async {
      final AppUpdater u = await prepared(t);
      await pumpScreen(t, u);
      expect(find.textContaining('Early versions come sooner'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('updateChannel')));
      await t.tap(find.text('Early (beta)'));
      await settle(t);
      expect(u.channel, 'beta');
      await t.tap(find.text('Stable'));
      await settle(t);
      expect(u.channel, 'stable');
    });

    test('source words: a host, and "and N more" for mirrors', () {
      expect(updateSourceHost(<String>[kManifestUrl]), 'updates.example.org');
      expect(updateSourceHost(<String>[kManifestUrl, kManifestMirror]), 'updates.example.org and 1 more');
      expect(updateSourceHost(const <String>[]), 'none');
      expect(updateChannelWords('beta'), 'Early (beta)');
    });
  });

  group('Google Play build', () {
    testWidgets('"Update" starts Play (no download buttons, no source, no install), then "Restart to finish"', (t) async {
      final Rig r = await t.runAsync(() => Rig.create(environment: wifiPhone(flavor: 'play'), manifestUrls: const <String>[])) as Rig;
      r.play.info = const PlayUpdateInfo(available: true, versionCode: 5200, flexibleAllowed: true);
      late AppUpdater u;
      await t.runAsync(() async {
        u = r.updater(play: true);
        await u.start();
        await u.checkNow();
      });
      addTearDown(u.dispose);
      await pumpScreen(t, u);
      expect(find.text('An update is ready'), findsOneWidget);
      expect(find.byKey(const Key('updatePlayStart')), findsOneWidget);
      expect(find.byKey(const Key('updateDownloadWifi')), findsNothing);
      expect(find.byKey(const Key('updateDownloadNow')), findsNothing);
      expect(find.byKey(const Key('updateSourceField')), findsNothing);
      expect(find.byKey(const Key('updateWifiOnly')), findsNothing);
      await t.tap(find.byKey(const Key('updatePlayStart')));
      await settle(t);
      expect(r.play.starts, <bool>[false]);
      r.play.events.add(const PlayEvent(PlayStatus.downloaded));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
      expect(find.text('Ready to finish'), findsOneWidget);
      await t.tap(find.byKey(const Key('updatePlayFinish')));
      await settle(t);
      expect(r.play.completes, 1);
    });
  });

  group('it fits every phone', () {
    for (final Size size in <Size>[const Size(320, 640), const Size(344, 800), const Size(900, 600)]) {
      testWidgets('no overflow at ${size.width.toInt()} x ${size.height.toInt()} with large text', (t) async {
        await publish();
        final AppUpdater u = await prepared(t, then: (AppUpdater u) => u.checkNow());
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpScreen(t, u, size: size);
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView), const Offset(0, -800));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });
}
