// OLIVE BRANCH: the family, notes and journal are sealed with an Android Keystore key that never leaves the phone
// (lib/store_cipher.dart). A platform backup or a phone-to-phone transfer would copy sealed files without the key and
// the new install would silently look empty. These guards read the manifest and the extraction rules from the repo,
// so a later change that turns platform backup back on, or drops an exclusion, fails here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

String stripComments(String xml) => xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

void main() {
  final String manifest = stripComments(read('android/app/src/main/AndroidManifest.xml'));
  final String application = manifest.substring(manifest.indexOf('<application'), manifest.indexOf('>', manifest.indexOf('<application')));

  group('platform backup is off for the sealed local store', () {
    test('the application turns allowBackup off and names both rule files', () {
      expect(application, contains('android:allowBackup="false"'));
      expect(application, isNot(contains('android:allowBackup="true"')));
      expect(application, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      expect(application, contains('android:fullBackupContent="@xml/backup_rules"'));
    });

    test('no source set turns it back on', () {
      for (final String set in <String>['debug', 'profile']) {
        final File f = File('android/app/src/$set/AndroidManifest.xml');
        if (f.existsSync()) expect(f.readAsStringSync(), isNot(contains('allowBackup="true"')), reason: set);
      }
    });
  });

  group('extraction rules exclude the local store and the secure-storage files', () {
    final String extraction = stripComments(read('android/app/src/main/res/xml/data_extraction_rules.xml'));
    final String legacy = stripComments(read('android/app/src/main/res/xml/backup_rules.xml'));

    const List<String> excluded = <String>[
      '<exclude domain="root" path="app_flutter" />',
      '<exclude domain="file" path="olive_store" />',
      '<exclude domain="sharedpref" path="FlutterSecureStorage.xml" />',
    ];

    test('Android 12+ rules exclude them from both cloud backup and device transfer', () {
      final String cloud = extraction.substring(extraction.indexOf('<cloud-backup>'), extraction.indexOf('</cloud-backup>'));
      final String transfer = extraction.substring(extraction.indexOf('<device-transfer>'), extraction.indexOf('</device-transfer>'));
      for (final String rule in excluded) {
        expect(cloud, contains(rule), reason: 'cloud-backup: $rule');
        expect(transfer, contains(rule), reason: 'device-transfer: $rule');
      }
      expect(extraction, isNot(contains('<include')), reason: 'nothing is opted back in');
    });

    test('Android 11 and older rules exclude them too', () {
      for (final String rule in excluded) {
        expect(legacy, contains(rule), reason: rule);
      }
      expect(legacy, isNot(contains('<include')));
    });

    test('the excluded folder is the one the local store really uses', () {
      final String services = read('lib/local_services.dart');
      expect(services, contains('getApplicationDocumentsDirectory'), reason: 'app_flutter is the documents directory on Android');
      expect(services, contains("olive_store"));
    });
  });
}
