// OLIVE BRANCH — guards for what ships in a release build (on-device
// performance pass): bundled asset size, no silent debug-signed release, no
// unguarded Jitsi trust or vendored copy, and the documented per-ABI build. Reads the repo's
// own files, so a later change that undoes any of these fails here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('bundled assets stay small', () {
    final List<File> files = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .toList();

    test('the whole assets/ tree stays under 1 MiB (it is about 0.5 MiB)', () {
      final int total = files.fold(0, (int a, File f) => a + f.lengthSync());
      expect(total, lessThan(1024 * 1024), reason: '$total bytes across ${files.length} files');
    });

    test('no single asset is over 512 KiB', () {
      for (final File f in files) {
        expect(f.lengthSync(), lessThan(512 * 1024), reason: f.path);
      }
    });
  });

  group('a release build is never silently debug-signed', () {
    final String gradle = read('android/app/build.gradle.kts');

    test('the signing config is null unless a real key or an explicit opt-in exists', () {
      expect(gradle, contains('signingConfig = when {'));
      expect(gradle, contains('hasRealSigningConfig -> signingConfigs.getByName("release")'));
      expect(gradle, contains('allowDebugSignedRelease -> signingConfigs.getByName("debug")'));
      expect(gradle, contains('else -> null'));
    });

    test('a task-graph check refuses assembleRelease/bundleRelease/packageRelease with a clear message', () {
      expect(gradle, contains('gradle.taskGraph.whenReady'));
      expect(gradle, contains('"assembleRelease", "bundleRelease", "packageRelease"'));
      expect(gradle, contains('Release build refused: android/key.properties is missing'));
    });

    test('the only escape hatch is an explicit property, and it is documented', () {
      expect(gradle, contains('olive.allowDebugSignedRelease'));
      expect(read('android/RELEASE_SIGNING.md'), contains('-Polive.allowDebugSignedRelease=true'));
    });

    test('debug is the only place the debug key is used without that opt-in', () {
      // The "debug" signing config is referenced exactly once in the release block.
      expect('signingConfigs.getByName("debug")'.allMatches(gradle).length, 1);
    });
  });

  group('release size: per-ABI builds are the documented path', () {
    final String doc = read('android/RELEASE_SIGNING.md');

    test('the documented build command splits per ABI and still targets main_live.dart', () {
      final String build = doc.substring(doc.indexOf('## 3. Build'));
      final RegExpMatch? m = RegExp(r'```bash\n([\s\S]*?)\n```').firstMatch(build);
      expect(m, isNotNull);
      expect(m!.group(1), contains('flutter build apk --release --split-per-abi --target=lib/main_live.dart'));
    });

    test('an app bundle is documented for a store upload', () {
      expect(doc, contains('flutter build appbundle --release'));
      expect(doc, contains('app-arm64-v8a-release.apk'));
    });
  });

  // MASTERFILE 16.2 #6, third reversal (2026-11-09): Jitsi is the default call provider again, so the
  // old "leftovers are gone" guard became a guard on what the comeback is allowed to bring back.
  group('the Jitsi comeback brings back only what it is allowed to', () {
    test('network-security config: no cleartext, system CAs only, one pinned cert for one LAN address', () {
      final File cfg = File('android/app/src/main/res/xml/network_security_config.xml');
      final String xml = cfg.readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      expect(xml, contains('<base-config cleartextTrafficPermitted="false">'));
      expect(xml, isNot(contains('cleartextTrafficPermitted="true"')));
      expect(xml, isNot(contains('src="user"')));
      // The ONLY @raw trust anchor is the pinned Jitsi certificate, once, inside a
      // cleartext-off domain-config for a single IPv4 address; never in the base config.
      expect('@raw/jitsi_dev_cert'.allMatches(xml).length, 1);
      expect(RegExp(r'@raw/(?!jitsi_dev_cert)').hasMatch(xml), isFalse);
      expect(
        RegExp(r'<domain-config cleartextTrafficPermitted="false">\s*<domain includeSubdomains="false">\d+\.\d+\.\d+\.\d+</domain>\s*<trust-anchors>\s*<certificates src="@raw/jitsi_dev_cert"')
            .hasMatch(xml),
        isTrue);
      final String base = xml.substring(xml.indexOf('<base-config'), xml.indexOf('</base-config>'));
      expect(base, isNot(contains('@raw')));
      expect(File('android/app/src/main/res/raw/jitsi_dev_cert.pem').readAsStringSync(), contains('BEGIN CERTIFICATE'));
      expect(File('android/app/src/main/res/raw/jitsi_dev_cert.pem').readAsStringSync(), isNot(contains('PRIVATE KEY')));
      expect(read('android/app/src/main/AndroidManifest.xml'), contains('networkSecurityConfig'));
    });

    test('the vendored jitsi_meet_flutter_sdk copy is wired, trimmed to Android, and nothing else overrides', () {
      expect(Directory('third_party/jitsi_meet_flutter_sdk_patched').existsSync(), isTrue);
      expect(Directory('third_party/jitsi_meet_flutter_sdk_patched/ios').existsSync(), isFalse);
      expect(Directory('third_party/jitsi_meet_flutter_sdk_patched/mobile-tools').existsSync(), isFalse);
      expect(read('third_party/jitsi_meet_flutter_sdk_patched/android/build.gradle'), contains('compileSdkVersion 36'));
      final String pubspec = read('pubspec.yaml');
      expect(pubspec, contains('path: third_party/jitsi_meet_flutter_sdk_patched'));
      expect(RegExp(r'^\s*jitsi_meet_flutter_sdk\s*:\s*\^', multiLine: true).hasMatch(pubspec), isTrue);
      expect(read('analysis_options.yaml'), contains('third_party/**'));
    });
  });
}
