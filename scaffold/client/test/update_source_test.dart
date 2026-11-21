// What the updater is NOT allowed to be, read from the real source files: adult-only (the child's shell never reaches
// it), the install permission lives in the direct flavor only, the Play flavor has no install code at all, the native
// and Dart halves agree on every channel and method name, and the app can verify a signature but never make one.
// MASTERFILE 7.24.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_platform.dart';

String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String stripComments(String s) => s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

Map<String, String> constants(String kotlin) => <String, String>{
      for (final RegExpMatch m in RegExp(r'const val (\w+)\s*=\s*"([^"]*)"').allMatches(kotlin)) m.group(1)!: m.group(2)!,
    };

void main() {
  final List<File> lib = Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
  String name(File f) => f.uri.pathSegments.last;

  group('adult-only: the child never reaches an update screen, count, prompt or error', () {
    // The ONLY files outside the updater's own that may import it: the grown-up's boot, home and settings.
    const Set<String> allowedImporters = <String>{'guardian_boot.dart', 'guardian_home.dart', 'guardian_more.dart'};

    test('only the grown-up shell imports the updater', () {
      final List<String> offenders = <String>[];
      for (final File f in lib) {
        final String n = name(f);
        if (n.startsWith('update_') || allowedImporters.contains(n)) continue;
        if (RegExp(r"import\s+'(package:olive_client/)?update_[a-z_]+\.dart'").hasMatch(read(f.path))) offenders.add(n);
      }
      expect(offenders, isEmpty, reason: 'imports the updater: $offenders');
    });

    test('the child\'s shell, the kiosk and every child screen mention no updater at all', () {
      for (final File f in lib) {
        final String n = name(f);
        final bool childSide = n.startsWith('child_') || n.startsWith('kiosk_') || n == 'main_live.dart' || n == 'lock_controller.dart' || n == 'adult_gate.dart';
        if (!childSide) continue;
        final String src = stripComments(read(f.path));
        expect(src.contains('AppUpdater') || src.contains('UpdateBanner') || src.contains('AppUpdatesScreen') || src.contains('UpdateScope'), isFalse, reason: n);
      }
    });

    test('the updater is started only from the grown-up boot, never from the unified role chooser or the child boot', () {
      final String live = read('lib/main_live.dart');
      expect(live.contains('AppUpdater'), isFalse);
      expect(live.contains('UpdateHost'), isFalse);
      final String boot = read('lib/guardian_boot.dart');
      expect(RegExp(r'unawaited\(_startUpdater\(\)\)').allMatches(boot).length, 2, reason: 'the live grown-up boot and the local one');
    });

    test('the home banner and the settings row appear only where the updater exists', () {
      expect(read('lib/guardian_home.dart'), contains('const UpdateBanner()'));
      expect(read('lib/guardian_more.dart'), contains("UpdateScope.maybeOf(context)?.enabled ?? false"));
    });
  });

  group('the install permission is the direct flavor\'s alone', () {
    final String main = stripComments(read('android/app/src/main/AndroidManifest.xml'));
    final String direct = stripComments(read('android/app/src/direct/AndroidManifest.xml'));
    final String play = read('android/app/src/play/AndroidManifest.xml');

    test('the shared manifest has no install permission and no file provider', () {
      expect(main.contains('REQUEST_INSTALL_PACKAGES'), isFalse);
      expect(main.contains('INSTALL_PACKAGES'), isFalse);
      expect(main.contains('FileProvider'), isFalse);
      expect(main.contains('UpdateStatusReceiver'), isFalse);
    });

    test('the direct manifest declares it exactly once, and its receiver is not exported', () {
      expect('REQUEST_INSTALL_PACKAGES'.allMatches(direct).length, 1);
      expect(direct, contains('<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>'));
      expect(direct, contains('android:name=".UpdateStatusReceiver"'));
      expect(RegExp(r'UpdateStatusReceiver"\s+android:exported="false"').hasMatch(direct), isTrue);
      expect(direct.contains('FileProvider'), isFalse, reason: 'a session install streams from the private folder; no content URI is shared');
    });

    test('the play manifest REMOVES it, so no library can add it back', () {
      expect(play, contains('android.permission.REQUEST_INSTALL_PACKAGES" tools:node="remove"'));
      expect(play.contains('<receiver'), isFalse);
    });

    test('exactly two flavors exist, one application id, and the Play library is linked into Play only', () {
      final String gradle = stripComments(read('android/app/build.gradle.kts'));
      expect(RegExp(r'create\("(\w+)"\)').allMatches(gradle.substring(gradle.indexOf('productFlavors'), gradle.indexOf('signingConfigs'))).map((RegExpMatch m) => m.group(1)).toList(),
          <String?>['direct', 'play']);
      expect(gradle.contains('applicationIdSuffix'), isFalse);
      expect(gradle, contains('"playImplementation"("com.google.android.play:app-update:2.1.0")'));
      expect(RegExp(r'^\s*implementation\("com\.google\.android\.play', multiLine: true).hasMatch(gradle), isFalse);
      expect(read('pubspec.yaml'), contains('default-flavor: direct'));
    });
  });

  group('the Play flavor has no install code at all', () {
    test('no PackageInstaller, no install intent, no downloaded file, no unknown-sources page', () {
      final String play = stripComments(read('android/app/src/play/kotlin/com/olivebranch/olive_client/UpdateBridge.kt'));
      for (final String banned in <String>[
        'PackageInstaller', 'ACTION_VIEW', 'ACTION_INSTALL_PACKAGE', 'package-archive', 'canRequestPackageInstalls',
        'ACTION_MANAGE_UNKNOWN_APP_SOURCES', 'FileProvider', 'HttpURLConnection', 'openWrite', 'java.io.File', //
      ]) {
        expect(play.contains(banned), isFalse, reason: banned);
      }
      expect(play, contains('AppUpdateManagerFactory'));
      expect(play, contains('AppUpdateType.FLEXIBLE'));
      expect(play, contains('AppUpdateType.IMMEDIATE'));
    });

    test('the shared Kotlin (used by both flavors) has no installer code either', () {
      final String env = read('android/app/src/main/kotlin/com/olivebranch/olive_client/UpdateEnvironment.kt');
      expect(env.contains('PackageInstaller'), isFalse);
      expect(env.contains('REQUEST_INSTALL'), isFalse);
    });
  });

  group('the direct flavor installs only the way Android intends', () {
    final String direct = stripComments(read('android/app/src/direct/kotlin/com/olivebranch/olive_client/UpdateBridge.kt'));
    final String receiver = read('android/app/src/direct/kotlin/com/olivebranch/olive_client/UpdateStatusReceiver.kt');

    test('a PackageInstaller session, the system confirmation required, never silent', () {
      expect(direct, contains('PackageInstaller.SessionParams.MODE_FULL_INSTALL'));
      expect(direct, contains('USER_ACTION_REQUIRED'));
      expect(receiver, contains('STATUS_PENDING_USER_ACTION'));
      for (final String banned in <String>['INSTALL_PACKAGES"', 'pm install', 'Runtime.getRuntime', 'ProcessBuilder', 'su -c', 'DevicePolicyManager', 'setPackageInstaller']) {
        expect(direct.contains(banned), isFalse, reason: banned);
      }
    });

    test('the file is checked again while it is copied into the session (size and SHA-256), and only from the update folder', () {
      expect(direct, contains('MessageDigest.getInstance("SHA-256")'));
      expect(direct, contains('copied != size'));
      expect(direct, contains('canonicalFile'));
      expect(direct, contains('f.parentFile == dir'));
    });

    test('a locked kiosk screen is never disturbed: it answers kioskLocked and does nothing', () {
      expect(direct, contains('lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE'));
      expect(direct, contains('result.success("kioskLocked")'));
    });

    test('the signing certificates of the file and of the installed app are read for the Dart side to compare', () {
      expect(direct, contains('GET_SIGNING_CERTIFICATES'));
      expect(direct, contains('"installedSigners"'));
      expect(direct, contains('"signers"'));
    });

    test('the installer\'s own message text is never forwarded (it can name paths)', () {
      expect(receiver.contains('EXTRA_STATUS_MESSAGE'), isFalse);
    });
  });

  group('the Dart and native halves agree', () {
    final Map<String, String> d = constants(read('android/app/src/direct/kotlin/com/olivebranch/olive_client/UpdateBridge.kt'));
    final Map<String, String> p = constants(read('android/app/src/play/kotlin/com/olivebranch/olive_client/UpdateBridge.kt'));

    test('one channel name, in both flavors and in Dart', () {
      expect(d['CHANNEL'], UpdateChannelNames.channel);
      expect(p['CHANNEL'], UpdateChannelNames.channel);
      expect(d['FLAVOR'], 'direct');
      expect(p['FLAVOR'], 'play');
    });

    test('the shared call and each flavor\'s own calls exist natively under the names Dart uses', () {
      expect(d['M_ENVIRONMENT'], UpdateChannelNames.mEnvironment);
      expect(p['M_ENVIRONMENT'], UpdateChannelNames.mEnvironment);
      expect(d['M_CAN_INSTALL'], UpdateChannelNames.mCanInstall);
      expect(d['M_OPEN_INSTALL_SETTINGS'], UpdateChannelNames.mOpenInstallSettings);
      expect(d['M_INSPECT'], UpdateChannelNames.mInspect);
      expect(d['M_INSTALL'], UpdateChannelNames.mInstall);
      expect(d['E_INSTALL'], UpdateChannelNames.eInstall);
      expect(p['M_PLAY_CHECK'], UpdateChannelNames.mPlayCheck);
      expect(p['M_PLAY_START'], UpdateChannelNames.mPlayStart);
      expect(p['M_PLAY_COMPLETE'], UpdateChannelNames.mPlayComplete);
      expect(p['E_PLAY'], UpdateChannelNames.ePlay);
    });

    test('neither flavor answers the other\'s calls', () {
      expect(d.keys.where((String k) => k.startsWith('M_PLAY')), isEmpty);
      expect(p.keys.where((String k) => k.startsWith('M_CAN') || k.startsWith('M_INSTALL') || k.startsWith('M_INSPECT') || k.startsWith('M_OPEN')), isEmpty);
    });

    test('the folder the native side will read from is the folder Dart writes to', () {
      expect(d['STAGING_DIR'], 'olive_updates');
      expect(read('lib/update_controller.dart'), contains("'olive_updates'"));
    });

    test('the words native sends for results are the words Dart reads', () {
      final String receiver = read('android/app/src/direct/kotlin/com/olivebranch/olive_client/UpdateStatusReceiver.kt');
      final Set<String> sent = RegExp(r'emit\("(\w+)"').allMatches(receiver).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(sent, <String>{'failed', 'success', 'declined', 'blocked', 'invalid', 'conflict', 'storage', 'incompatible'});
      final String dart = read('lib/update_platform.dart');
      for (final String w in sent.where((String s) => s != 'failed')) {
        expect(dart, contains("'$w' =>"), reason: w);
      }
      final String playKt = read('android/app/src/play/kotlin/com/olivebranch/olive_client/UpdateBridge.kt');
      for (final String w in RegExp(r'emit\("(\w+)"').allMatches(playKt).map((RegExpMatch m) => m.group(1)!).toSet().where((String s) => s != 'failed')) {
        expect(dart, contains("'$w' =>"), reason: 'play: $w');
      }
    });

    test('the shared activity registers the bridge and forwards the two lifecycle hooks', () {
      final String main = read('android/app/src/main/kotlin/com/olivebranch/olive_client/MainActivity.kt');
      expect(main, contains('UpdateBridge.register(this, MethodChannel(messenger, UpdateBridge.CHANNEL))'));
      expect(main, contains('UpdateBridge.onActivityResult(requestCode, resultCode)'));
      expect(main, contains('UpdateBridge.onResume(this)'));
    });
  });

  group('the app can check a signature and can never make one', () {
    test('no signing, no key generation and no private key material in any updater file', () {
      for (final File f in lib) {
        if (!name(f).startsWith('update_')) continue;
        final String src = stripComments(read(f.path));
        for (final String banned in <String>['newKeyPair', '.sign(', 'PRIVATE KEY', 'privateKey', 'extractPrivateKey', 'Hmac']) {
          expect(src.contains(banned), isFalse, reason: '${name(f)} contains $banned');
        }
      }
    });

    test('the only key the app takes is a PUBLIC key from a build define', () {
      final String src = read('lib/update_manifest.dart');
      expect(src, contains("String.fromEnvironment('OLIVE_UPDATE_PUBKEYS')"));
      expect(read('lib/update_controller.dart'), contains("String.fromEnvironment('OLIVE_UPDATE_MANIFEST_URL')"));
    });

    test('no certificate check is switched off anywhere in the updater', () {
      for (final File f in lib) {
        if (!name(f).startsWith('update_')) continue;
        final String src = read(f.path);
        expect(src.contains('badCertificateCallback'), isFalse, reason: name(f));
        expect(src.contains('allowLegacyUnsafeRenegotiation'), isFalse);
      }
    });

    test('the network layer imports nothing that carries a family, a child, a session or a pin', () {
      for (final String n in <String>['update_manifest.dart', 'update_policy.dart', 'update_transport.dart', 'update_download.dart']) {
        final String src = read('lib/$n');
        for (final String banned in <String>['api_client', 'auth_session', 'local_family', 'family_', 'device_keys', 'device_identity', 'local_pin']) {
          expect(RegExp("import\\s+'$banned").hasMatch(src), isFalse, reason: '$n imports $banned');
        }
      }
    });
  });
}
