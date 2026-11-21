// OLIVE BRANCH — the grown-up's backup screens, driven headless: setup (keep your recovery sheet), "last backup" in plain
// words, the restore wizard, and the replacement-tablet flow. Plus the guard that keeps all of it out of her screens.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_keys.dart';
import 'package:olive_client/backup_places.dart';
import 'package:olive_client/backup_screens.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_tablet_screens.dart';
import 'package:olive_client/guardian_escalation_screen.dart';
import 'package:olive_client/local_services.dart';

import 'support/backup_rig.dart';

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

String _joined(List<String> w) => w.join(' ');

void main() {
  group('making the recovery sheet', () {
    testWidgets('shows the words, checks the first and last, and only THEN keeps the public half', (t) async {
      final LocalServices s = LocalServices.memory();
      final BackupService svc = BackupService(services: s);
      final RecoverySheet expected = await RecoverySheet.make(BackupPurpose.family, random: Random(1));
      await _pump(t, RecoverySheetScreen(service: svc, random: Random(1)));
      await _settle(t);
      expect(find.byKey(const Key('sheetWords')), findsOneWidget);
      for (final String w in expected.words) {
        expect(find.textContaining(w), findsWidgets);
      }
      expect(find.textContaining('Sheet ${expected.sheetId}'), findsOneWidget);
      expect(find.byKey(const Key('neverAskCard')), findsOneWidget, reason: 'said every time the words are shown');
      expect(find.textContaining('never ask for them by call, text or email'), findsOneWidget);
      expect(await svc.journal.familySheet(), isNull, reason: 'nothing is kept before the paper is checked');

      await t.tap(find.byKey(const Key('writtenDownButton')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('echoFirst')), 'wrong');
      await t.enterText(find.byKey(const Key('echoLast')), 'words');
      await t.tap(find.byKey(const Key('echoCheckButton')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('echoWrong')), findsOneWidget);
      expect(await svc.journal.familySheet(), isNull);

      await t.enterText(find.byKey(const Key('echoFirst')), ' ${expected.firstWord.toUpperCase()} ');
      await t.enterText(find.byKey(const Key('echoLast')), expected.lastWord);
      await t.tap(find.byKey(const Key('echoCheckButton')));
      await _settle(t);
      expect(find.byKey(const Key('sheetReady')), findsOneWidget);
      final SheetRecord rec = (await svc.journal.familySheet())!;
      expect(rec.publicKey, expected.publicKey);
      expect(rec.sheetId, expected.sheetId);
      expect(rec.confirmedMs, isNotNull);
      // The phone holds the public half and the id, never the words.
      final String dump = (await s.area('backup').snapshot()).toString();
      expect(dump.contains(_joined(expected.words.take(3).toList())), isFalse);
    });

    testWidgets('leaving before the check keeps nothing, so a backup is never locked to words nobody wrote down', (t) async {
      final LocalServices s = LocalServices.memory();
      final BackupService svc = BackupService(services: s);
      await _pump(t, Builder(builder: (BuildContext c) => Center(child: TextButton(
          key: const Key('open'),
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => RecoverySheetScreen(service: svc, random: Random(2)))),
          child: const Text('open')))));
      await t.tap(find.byKey(const Key('open')));
      await _settle(t);
      await t.tap(find.byKey(const Key('writtenDownButton')));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(await svc.journal.familySheet(), isNull);
      expect(await runFamilyBackupIfDue(s, MemoryBackupPlaces()), isEmpty);
    });

    testWidgets('a grown-up who does not pass the PIN is sent back and sees no words', (t) async {
      final LocalServices s = LocalServices.memory();
      await _pump(t, Builder(builder: (BuildContext c) => Center(child: TextButton(
          key: const Key('open'),
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
              builder: (_) => RecoverySheetScreen(service: BackupService(services: s), confirmAdult: () async => false))),
          child: const Text('open')))));
      await t.tap(find.byKey(const Key('open')));
      await _settle(t);
      expect(find.byKey(const Key('sheetWords')), findsNothing);
      expect(find.byKey(const Key('open')), findsOneWidget, reason: 'back where they were');
    });
  });

  group('the hub and the last backup in plain words', () {
    testWidgets('with nothing yet it says so, offers set up, and keeps the not-in-a-backup list', (t) async {
      final LocalServices s = LocalServices.memory();
      await _pump(t, BackupHubScreen(services: s, places: MemoryBackupPlaces()));
      expect(find.text('No backup yet'), findsOneWidget);
      expect(find.text('Set up backup'), findsOneWidget);
      expect(find.byKey(const Key('noSheetText')), findsOneWidget);
      expect(find.byKey(const Key('makeSheetButton')), findsOneWidget);
      expect(find.byKey(const Key('placeServer')), findsOneWidget);
      expect(find.textContaining('Not available. It needs a server of your own'), findsOneWidget);
      await t.tap(find.byKey(const Key('leftOutTile')));
      await t.pumpAndSettle();
      for (final String w in kLeftOutWords) {
        expect(find.text(w), findsOneWidget);
      }
    });

    testWidgets('after a backup it says when, where, and the sheet; Back up now makes another', (t) async {
      final LocalServices s = LocalServices.memory();
      await populate(s, BackupKind.family);
      final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(3));
      final BackupService svc = BackupService(services: s);
      await svc.rememberFamilySheet(sheet);
      await svc.confirmFamilySheet();
      final MemoryBackupPlaces places = MemoryBackupPlaces();
      await _pump(t, BackupHubScreen(services: s, places: places));
      expect(find.text('No backup yet'), findsOneWidget);
      await t.tap(find.byKey(const Key('backupNowButton')));
      await _settle(t);
      expect(find.byKey(const Key('backupNote')), findsOneWidget);
      expect(find.textContaining('Backed up, and read back to check it.'), findsOneWidget);
      expect(find.textContaining('Backed up just now'), findsOneWidget);
      expect(find.textContaining('in the backup folder on this phone'), findsOneWidget);
      expect(find.textContaining('Sheet ${sheet.sheetId}'), findsOneWidget);
      expect((await places.folder.committed(BackupKind.family)).length, 1);
    });

    testWidgets('a failed try says the old backup is safe and nothing was changed, in plain words', (t) async {
      final LocalServices s = LocalServices.memory();
      await populate(s, BackupKind.family);
      final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(4));
      final BackupService svc = BackupService(services: s);
      await svc.rememberFamilySheet(sheet);
      await svc.confirmFamilySheet();
      final MemoryBackupPlaces places = MemoryBackupPlaces();
      await svc.run(BackupKind.family, places.destinations(const BackupSettings())['folder']!, sheet.publicKey);
      await svc.journal.recordTry(BackupLast(kind: BackupKind.family, ok: false, atMs: DateTime.now().millisecondsSinceEpoch, dest: 'folder', code: 'io'));
      await _pump(t, BackupHubScreen(services: s, places: places));
      expect(find.textContaining('newest try did not finish'), findsOneWidget);
      expect(find.textContaining('Your last good backup'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('turning a place off or on is remembered', (t) async {
      final LocalServices s = LocalServices.memory();
      await _pump(t, BackupHubScreen(services: s, places: MemoryBackupPlaces()));
      await t.tap(find.byKey(const Key('placeAuto')));
      await _settle(t);
      expect((await BackupService(services: s).journal.settings()).auto, isFalse);
      await t.tap(find.byKey(const Key('placeFolder')));
      await _settle(t);
      expect(find.text('Backup is off'), findsOneWidget);
    });
  });

  group('the restore wizard', () {
    Future<(MemoryBackupPlaces, RecoverySheet)> backedUp() async {
      final LocalServices old = LocalServices.memory(childId: 'mia', guardianId: 'gid-one');
      await populate(old, BackupKind.family);
      final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(5));
      final MemoryBackupPlaces places = MemoryBackupPlaces();
      final BackupOutcome o = await BackupService(services: old)
          .run(BackupKind.family, places.destinations(const BackupSettings())['folder']!, sheet.publicKey);
      expect(o.ok, isTrue);
      return (places, sheet);
    }

    testWidgets('where, the words, a plain review, the restore, and the proof', (t) async {
      final (MemoryBackupPlaces places, RecoverySheet sheet) = await backedUp();
      final LocalServices fresh = LocalServices.memory(childId: 'mia', guardianId: 'gid-one');
      await _pump(t, RestoreWizardScreen(services: fresh, places: places));
      expect(find.text('Where is the backup?'), findsOneWidget);
      await t.tap(find.byKey(const Key('whereNext')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('neverAskCard')), findsOneWidget);

      // A typo is caught before anything is tried, and says which word.
      await t.enterText(find.byKey(const Key('restoreWords')), 'baba bebe');
      await t.tap(find.byKey(const Key('wordsNext')));
      await _settle(t);
      expect(find.byKey(const Key('restoreProblem')), findsOneWidget);
      expect(find.textContaining('words in a row'), findsOneWidget);

      // Real words that are not this family's.
      final RecoverySheet other = await RecoverySheet.make(BackupPurpose.family, random: Random(99));
      await t.enterText(find.byKey(const Key('restoreWords')), _joined(other.words));
      await t.tap(find.byKey(const Key('wordsNext')));
      await _settle(t);
      expect(find.textContaining('do not open this backup'), findsOneWidget);
      expect(find.byKey(const Key('reviewTitle')), findsNothing);

      // The right words.
      await t.enterText(find.byKey(const Key('restoreWords')), _joined(sheet.words));
      await t.tap(find.byKey(const Key('wordsNext')));
      await _settle(t);
      expect(find.byKey(const Key('reviewTitle')), findsOneWidget);
      expect(find.byKey(const Key('reviewPlan')), findsOneWidget);
      expect(find.textContaining('does not add this phone to your family'), findsOneWidget);
      for (final String raw in <String>['child.', 'guardian.', 'namespace', 'chunk']) {
        expect(find.textContaining(raw), findsNothing, reason: raw);
      }
      await t.tap(find.byKey(const Key('putBackButton')));
      await _settle(t);
      expect(find.byKey(const Key('doneTitle')), findsOneWidget);
      expect(find.textContaining('checked it matches. Nothing was lost.'), findsOneWidget);
      expect(await fresh.area('care').get('k0'), isNotNull);
    });

    testWidgets('an empty place says there is no backup, in plain words, and changes nothing', (t) async {
      final LocalServices fresh = LocalServices.memory();
      await _pump(t, RestoreWizardScreen(services: fresh, places: MemoryBackupPlaces()));
      await t.tap(find.byKey(const Key('whereNext')));
      await t.pumpAndSettle();
      final RecoverySheet any = await RecoverySheet.make(BackupPurpose.family, random: Random(6));
      await t.enterText(find.byKey(const Key('restoreWords')), _joined(any.words));
      await t.tap(find.byKey(const Key('wordsNext')));
      await _settle(t);
      expect(find.textContaining('There is no backup in that place'), findsOneWidget);
      expect(await fresh.store.namespaces(), isEmpty);
    });

    testWidgets('the file choice asks where the file is, and a missing file is a gentle message', (t) async {
      final LocalServices fresh = LocalServices.memory();
      await _pump(t, RestoreWizardScreen(services: fresh, places: MemoryBackupPlaces()));
      await t.tap(find.byKey(const Key('fromFile')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('filePath')), 'nowhere.olivebackup');
      await t.tap(find.byKey(const Key('whereNext')));
      await t.pumpAndSettle();
      final RecoverySheet any = await RecoverySheet.make(BackupPurpose.family, random: Random(7));
      await t.enterText(find.byKey(const Key('restoreWords')), _joined(any.words));
      await t.tap(find.byKey(const Key('wordsNext')));
      await _settle(t);
      expect(find.textContaining('Could not read that place'), findsOneWidget);
    });
  });

  group('the replacement tablet', () {
    Future<(MemoryBackupPlaces, ChildSecrets)> oldTablet() async {
      final LocalServices old = LocalServices.memory(childId: 'mia');
      await ChildKeyKeeper(old.area('childkeys')).ensure(random: Random(8));
      await populate(old, BackupKind.hersKeep);
      await populate(old, BackupKind.hersPrivate);
      final MemoryBackupPlaces places = MemoryBackupPlaces();
      await runChildBackupsIfDue(old, places);
      expect((await places.folder.committed(BackupKind.hersKeep)).length, 1);
      expect((await places.folder.committed(BackupKind.hersPrivate)).length, 1);
      return (places, (await ChildKeyKeeper(old.area('childkeys')).read())!);
    }

    testWidgets('the old tablet shows nothing until a grown-up asks, then 28 hand-over words, and the keepsake words only if asked', (t) async {
      final LocalServices s = LocalServices.memory(childId: 'mia');
      await _pump(t, HerKeysScreen(services: s));
      await _settle(t);
      expect(find.byKey(const Key('handoverWords')), findsNothing);
      expect(find.byKey(const Key('keepsakeWords')), findsNothing);
      await t.tap(find.byKey(const Key('showHandover')));
      await t.pumpAndSettle();
      final ChildSecrets sec = (await ChildKeyKeeper(s.area('childkeys')).read())!;
      for (final String w in sec.handoverWords.take(3)) {
        expect(find.textContaining(w), findsWidgets);
      }
      expect(find.byKey(const Key('keepsakeWords')), findsNothing);
      expect(find.textContaining('whoever holds that paper'), findsOneWidget, reason: 'the cost of a keepsake sheet is said plainly');
      await t.tap(find.byKey(const Key('showKeepsake')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('keepsakeWords')), findsOneWidget);
    });

    testWidgets('a failed grown-up check shows no words and leaves', (t) async {
      final LocalServices s = LocalServices.memory(childId: 'mia');
      await _pump(t, Builder(builder: (BuildContext c) => Center(child: TextButton(
          key: const Key('open'),
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
              builder: (_) => HerKeysScreen(services: s, confirmAdult: () async => false))),
          child: const Text('open')))));
      await t.tap(find.byKey(const Key('open')));
      await _settle(t);
      expect(find.byKey(const Key('showHandover')), findsNothing);
      expect(await s.area('childkeys').get('secrets'), isNull, reason: 'not even made for someone who did not pass');
    });

    testWidgets('the hand-over words bring back her home, drawings, memories AND private areas, and hand over the keys', (t) async {
      final (MemoryBackupPlaces places, ChildSecrets secrets) = await oldTablet();
      final LocalServices fresh = LocalServices.memory(childId: 'mia');
      await _pump(t, ReplacementTabletScreen(services: fresh, places: places));
      await _settle(t);
      await t.tap(find.byKey(const Key('tWhereNext')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('tWords')), _joined(secrets.handoverWords));
      await t.tap(find.byKey(const Key('tOpen')));
      await _settle(t);
      expect(find.byKey(const Key('tReviewTitle')), findsOneWidget);
      expect(find.byKey(const Key('tReviewPrivate')), findsOneWidget);
      await t.tap(find.byKey(const Key('tPutBack')));
      await _settle(t);
      expect(find.byKey(const Key('tDoneTitle')), findsOneWidget);
      expect(find.textContaining('Nothing was lost'), findsOneWidget);
      expect(await fresh.area('pictures').get('k0'), isNotNull);
      expect(await fresh.area('memorybox').get('k0'), isNotNull);
      expect(await fresh.area('journal').get('k0'), isNotNull);
      expect(await fresh.area('access').get('k0'), isNotNull, reason: 'her home settings');
      expect((await ChildKeyKeeper(fresh.area('childkeys')).read())!.private, secrets.private);
    });

    testWidgets('a keepsake sheet alone brings back pictures and memories and says plainly her private areas are not coming back', (t) async {
      final (MemoryBackupPlaces places, ChildSecrets secrets) = await oldTablet();
      final LocalServices fresh = LocalServices.memory(childId: 'mia');
      await _pump(t, ReplacementTabletScreen(services: fresh, places: places));
      await _settle(t);
      await t.tap(find.byKey(const Key('tWhereNext')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('tWords')), _joined(secretToWords(secrets.keep)));
      await t.tap(find.byKey(const Key('tOpen')));
      await _settle(t);
      expect(find.byKey(const Key('tReviewNoPrivate')), findsOneWidget);
      expect(find.textContaining('no grown-up can open them'), findsOneWidget);
      await t.tap(find.byKey(const Key('tPutBack')));
      await _settle(t);
      expect(find.byKey(const Key('tDoneTitle')), findsOneWidget);
      expect(await fresh.area('pictures').get('k0'), isNotNull);
      expect(await fresh.area('journal').get('k0'), isNull);
      final ChildSecrets now = (await ChildKeyKeeper(fresh.area('childkeys')).read())!;
      expect(now.keep, secrets.keep, reason: 'later keepsake backups share the key');
      expect(now.private, isNot(secrets.private), reason: 'her private secret was on no sheet, so this tablet makes its own');
    });

    testWidgets('wrong words never open it, and say so without naming a key', (t) async {
      final (MemoryBackupPlaces places, _) = await oldTablet();
      final LocalServices fresh = LocalServices.memory(childId: 'mia');
      await _pump(t, ReplacementTabletScreen(services: fresh, places: places));
      await _settle(t);
      await t.tap(find.byKey(const Key('tWhereNext')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('tWords')), _joined(ChildSecrets.make(Random(55)).handoverWords));
      await t.tap(find.byKey(const Key('tOpen')));
      await _settle(t);
      expect(find.byKey(const Key('tProblem')), findsOneWidget);
      expect(find.byKey(const Key('tReviewTitle')), findsNothing);
      expect(await fresh.area('pictures').list(), isEmpty);
    });
  });

  group('her screens never see any of it', () {
    final Directory lib = Directory('lib');

    test('no file that draws what she sees imports a backup or recovery file', () {
      final List<File> files = lib
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .where((File f) {
        final String n = f.uri.pathSegments.last;
        return n.startsWith('child_') || n.startsWith('colour_') || n.startsWith('game_') || n.startsWith('doodle');
      }).toList();
      expect(files, isNotEmpty);
      for (final File f in files) {
        final String src = f.readAsStringSync();
        expect(RegExp(r"import\s+'(backup_|restore_engine)").hasMatch(src), isFalse, reason: f.path);
      }
    });

    test('the family-side screens (hub, sheet, restore wizard) are imported by the grown-up settings only', () {
      final List<String> importers = <String>[
        for (final FileSystemEntity f in lib.listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart') && f.readAsStringSync().contains("import 'backup_screens.dart'")) f.uri.pathSegments.last
      ];
      expect(importers, <String>['guardian_more.dart']);
    });

    test('the tablet-side screens never touch the family recovery sheet', () {
      final String src = File('lib/backup_tablet_screens.dart').readAsStringSync();
      expect(src.contains('BackupPurpose.family'), isFalse);
      expect(src.contains('RecoverySheet'), isFalse);
      expect(src.contains('rememberFamilySheet'), isFalse);
    });

    test('the tablet reaches them only through the grown-up page, which a child cannot open', () {
      final String kiosk = File('lib/kiosk_shell.dart').readAsStringSync();
      expect(kiosk.contains("import 'backup_screens.dart'"), isFalse);
      final String esc = File('lib/guardian_escalation_screen.dart').readAsStringSync();
      expect(esc.contains('onNewTablet'), isTrue);
    });

    testWidgets('the grown-up page offers the two actions only when they are wired, and plain words with no count', (t) async {
      await _pump(t, const GuardianEscalationScreen(escalatedUntil: null, onExitKiosk: _noop));
      expect(find.byKey(const Key('movingToNewTabletButton')), findsNothing);
      await _pump(t, const GuardianEscalationScreen(escalatedUntil: null, onExitKiosk: _noop, onNewTablet: _noop, onBringBack: _noop));
      expect(find.byKey(const Key('movingToNewTabletButton')), findsOneWidget);
      expect(find.byKey(const Key('bringHerBackButton')), findsOneWidget);
    });
  });
}

void _noop() {}
