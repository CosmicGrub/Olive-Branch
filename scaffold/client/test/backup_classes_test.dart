// OLIVE BRANCH — backup_classes.dart: every catalogued area is classified, and her private areas stay under no
// grown-up key. A new area added to the catalogue without a decision here fails this file.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/clear_local_data_screen.dart' show kLocalDataAreaNames;
import 'package:olive_client/local_services.dart';

void main() {
  final Set<String> catalogued = <String>{for (final LocalDataEntry e in localDataCatalogue) e.area};

  test('every catalogued area is classified, and the table has no stale extras', () {
    expect(kBackupRules.keys.toSet().difference(catalogued), isEmpty, reason: 'stale rows');
    expect(catalogued.difference(kBackupRules.keys.toSet()), isEmpty,
        reason: 'add a decision to kBackupRules for each new area');
  });

  test('her private areas are in her private backup only: never the family backup, never her keepsake backup', () {
    const Set<String> priv = <String>{'journal', 'worries', 'feelings', 'teen', 'mymarks'};
    expect(areasOfBackup(BackupKind.hersPrivate).toSet(), priv);
    for (final String a in priv) {
      expect(areaInBackup(a, BackupKind.family), isFalse, reason: a);
      expect(areaInBackup(a, BackupKind.hersKeep), isFalse, reason: a);
    }
  });

  test('anything sealed on her tablet that a grown-up may read is never under the key a keepsake sheet could hold', () {
    // The keepsake key can be written on a sheet (an owner choice), so nothing private may be under it.
    for (final String a in areasOfBackup(BackupKind.hersKeep)) {
      expect(<String>{'journal', 'worries', 'feelings', 'teen', 'mymarks'}, isNot(contains(a)));
    }
  });

  test('keys, pairing, PIN checks and the backup notes themselves are in no backup', () {
    for (final String a in <String>['devicekey', 'childpairing', 'adultunlock', 'localpin', 'account', 'role', 'childkeys',
        'backup', 'backupkept', 'screenshares', 'playsave', 'daytime', 'onboarding', 'learn']) {
      for (final BackupKind k in BackupKind.values) {
        expect(areaInBackup(a, k), isFalse, reason: '$a in ${k.word}');
      }
    }
  });

  test('settings she needs on a new tablet are in the family backup AND her keepsake backup', () {
    for (final String a in <String>['access', 'plan', 'rhythm', 'voice', 'profile', 'colour']) {
      expect(areaInBackup(a, BackupKind.family), isTrue, reason: a);
      expect(areaInBackup(a, BackupKind.hersKeep), isTrue, reason: a);
    }
  });

  test('what the grown-ups wrote (care, emergency card, medicines, ledger) is in the family backup only', () {
    for (final String a in <String>['care', 'emergencycard', 'coordination', 'aboutchild', 'familyledger', 'familysync']) {
      expect(areaInBackup(a, BackupKind.family), isTrue, reason: a);
      expect(areaInBackup(a, BackupKind.hersKeep), isFalse, reason: a);
      expect(areaInBackup(a, BackupKind.hersPrivate), isFalse, reason: a);
    }
  });

  test('signed records are never rewritten from another copy', () {
    for (final String a in <String>['familyledger', 'familysync', 'trust', 'pairedkids']) {
      expect(kBackupRules[a]!.merge, MergeRule.keyUnion, reason: a);
    }
  });

  test('every rule explains itself in plain words, and the new areas have plain display names', () {
    for (final BackupAreaRule r in kBackupRules.values) {
      expect(r.why.trim(), isNotEmpty);
    }
    for (final String a in <String>['backup', 'backupkept', 'childkeys']) {
      expect(kLocalDataAreaNames[a], isNotEmpty);
      expect(kLocalDataAreaNames[a], isNot(a));
      expect(localDataEntry(a).encrypted, isTrue, reason: '$a is sealed');
    }
  });

  test('the kinds round-trip by their wire words', () {
    for (final BackupKind k in BackupKind.values) {
      expect(BackupKind.fromWord(k.word), k);
    }
    expect(BackupKind.fromWord('nope'), isNull);
    expect(BackupKind.fromWord(null), isNull);
  });
}
