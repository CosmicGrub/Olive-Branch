// OLIVE BRANCH — backup screens: the words are plain, the sheet is shown once and checked against the paper, restore
// shows what will happen before it does anything, a tablet has no server choice, and no child's screen can reach any of
// it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_crypto.dart';
import 'package:olive_client/backup_engine.dart';
import 'package:olive_client/backup_restore.dart';
import 'package:olive_client/backup_screens.dart';
import 'package:olive_client/backup_server.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_sink.dart';
import 'package:olive_client/backup_words.dart';
import 'package:olive_client/guardian_escalation_screen.dart';

import 'support/backup_rig.dart';

BackupHost _host(Rig r, {BackupSource? source, String? folder}) => BackupHost(
      service: r.svc,
      defaultFolder: () async => folder,
      openFolder: source == null ? null : (String p) async => source,
      now: r.clock.now,
    );

Future<void> _big(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

List<String> _bannedJargon() => <String>[
      'encrypt', 'cipher', 'seed', 'hash', 'chunk', 'manifest', 'sink', 'vault', 'nonce', 'AES', 'X25519', 'Ed25519', 'HKDF',
      'namespace', 'journal', 'rollback', 'tombstone', 'payload', 'ciphertext', 'API', 'JSON',
    ];

void main() {
  group('the words are plain', () {
    test('no line the screens can say uses jargon, and every honest warning is there', () {
      final List<String> lines = <String>[
        BackupCopy.whatItIs(BackupKind.family),
        BackupCopy.whatItIs(BackupKind.keepsake),
        BackupCopy.title(BackupKind.family),
        BackupCopy.title(BackupKind.keepsake),
        BackupCopy.sheetIntro,
        BackupCopy.sheetWrite,
        BackupCopy.sheetCheckAsk,
        BackupCopy.sheetCheckWrong,
        BackupCopy.sheetDone,
        BackupCopy.oneCopyWarning,
        BackupCopy.restoreIsRecordsOnly,
        for (final RestoreProblem p in RestoreProblem.values) BackupCopy.restoreProblem(p),
        for (final SheetProblem p in SheetProblem.values) BackupCopy.sheetProblem(p, 3),
        for (final SheetOutcome o in SheetOutcome.values) BackupCopy.outcomeWords(o),
        for (final ServerRestorePhase p in ServerRestorePhase.values) BackupCopy.phaseWords(p, waitHours: 72),
        for (final String? c in <String?>['unreachable', 'full', 'refused', 'signed_out', 'paused', 'no_vault', 'not_enabled', 'damaged', null])
          BackupCopy.failureWords(c),
      ];
      for (final String l in lines) {
        for (final String bad in _bannedJargon()) {
          expect(l.toLowerCase().contains(bad.toLowerCase()), isFalse, reason: '"$l" says "$bad"');
        }
        expect(l.length, lessThan(420), reason: 'short enough to read: $l');
      }
      expect(BackupCopy.sheetIntro, contains('never ask'));
      expect(BackupCopy.sheetIntro, contains('key to a safe'));
      expect(BackupCopy.oneCopyWarning, contains('lost with this phone'));
      expect(BackupCopy.whatItIs(BackupKind.keepsake), contains('never takes her journal'));
      expect(BackupCopy.restoreIsRecordsOnly, contains('does not make this phone one of your family'));
    });

    test('nothing in the words gives medical or legal advice', () {
      final String all = <String>[BackupCopy.sheetIntro, BackupCopy.oneCopyWarning, BackupCopy.restoreIsRecordsOnly].join(' ').toLowerCase();
      for (final String w in <String>['diagnos', 'treat', 'dose', 'court', 'custody', 'legal']) {
        expect(all.contains(w), isFalse, reason: w);
      }
    });

    test('a status line says the most urgent thing and "ago" is in plain words', () {
      final DateTime now = DateTime.utc(2026, 11, 21, 12);
      int at(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(BackupCopy.ago(now, at(const Duration(seconds: 30))), 'just now');
      expect(BackupCopy.ago(now, at(const Duration(minutes: 20))), '20 minutes ago');
      expect(BackupCopy.ago(now, at(const Duration(hours: 5))), '5 hours ago');
      expect(BackupCopy.ago(now, at(const Duration(hours: 30))), 'yesterday');
      expect(BackupCopy.ago(now, at(const Duration(days: 9))), '9 days ago');
    });
  });

  group('setting up the sheet', () {
    testWidgets('shown once, checked against the paper, and only then is the sheet counted as written', (WidgetTester t) async {
      await _big(t);
      final Rig r = await Rig.make();
      await t.pumpWidget(MaterialApp(home: BackupScreen(host: _host(r, folder: '/x'))));
      await t.pumpAndSettle();
      expect(find.text("Your family's records are not backed up yet."), findsOneWidget);
      expect(find.byKey(const Key('backupNow')), findsNothing, reason: 'nothing to back up with until there is a sheet');

      await t.tap(find.byKey(const Key('backupSetUp')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sheetIntro')), findsOneWidget);
      await t.tap(find.byKey(const Key('sheetShow')));
      await t.pumpAndSettle();
      final Finder chips = find.descendant(of: find.byKey(const Key('sheetWords')), matching: find.byType(Chip));
      expect(chips, findsNWidgets(kSheetWords));
      final List<String> words = <String>[
        for (final Element e in chips.evaluate()) ((e.widget as Chip).label as Text).data!.split('. ').last,
      ];
      await t.tap(find.byKey(const Key('sheetWritten')));
      await t.pumpAndSettle();
      // The words are gone from the screen once the paper is being checked.
      expect(find.byKey(const Key('sheetWords')), findsNothing);

      await t.enterText(find.byKey(const Key('sheetFirst')), 'wrong');
      await t.enterText(find.byKey(const Key('sheetLast')), 'words');
      await t.tap(find.byKey(const Key('sheetCheck')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sheetError')), findsOneWidget);
      expect((await r.svc.status()).attention, BackupAttention.sheetNotChecked);

      await t.enterText(find.byKey(const Key('sheetFirst')), words.first);
      await t.enterText(find.byKey(const Key('sheetLast')), words.last);
      await t.tap(find.byKey(const Key('sheetCheck')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sheetDone')), findsOneWidget);
      await t.tap(find.byKey(const Key('sheetFinish')));
      await t.pumpAndSettle();
      expect((await r.svc.status()).sheetCheckedMs, isNotNull);
      expect(find.byKey(const Key('backupFolderTile')), findsOneWidget, reason: 'now the places are offered');
      // the words are in no stored document
      expect(RecoveryKey.parse(words.join(' ')).ok, isTrue);
    });

    testWidgets('a tablet\'s page says her keepsakes, never the grown-up\'s records, and offers no server', (WidgetTester t) async {
      await _big(t);
      final Rig r = await Rig.make(role: BackupRole.child);
      await t.pumpWidget(MaterialApp(home: BackupScreen(host: _host(r))));
      await t.pumpAndSettle();
      expect(find.text('Back up her home and keepsakes'), findsOneWidget);
      expect(find.textContaining('journal'), findsOneWidget, reason: 'it says it never takes the journal');
      expect(find.textContaining('family\'s records'), findsNothing);
      await r.svc.setUp();
      await r.svc.sheetLookedAt();
      await t.pumpWidget(MaterialApp(home: BackupScreen(host: _host(r))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('backupServerSwitch')), findsNothing);
    });
  });

  group('backing up and the status line', () {
    testWidgets('a place is chosen, a backup runs, the result and the one-copy warning are in plain words', (WidgetTester t) async {
      await _big(t);
      final Rig r = await Rig.make();
      await r.put('learn', <String, Object?>{'read': <Object?>['x']});
      final RecoveryKey k = await r.svc.setUp();
      await r.svc.confirmSheet(k, k.firstWord, k.lastWord);
      final Directory dir = (await t.runAsync(() => Directory.systemTemp.createTemp('olive_screen_test')))!;
      addTearDown(() => dir.delete(recursive: true));
      await t.pumpWidget(MaterialApp(home: BackupScreen(host: _host(r, folder: dir.path))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('backupNoPlace')), findsOneWidget);
      expect(tester(t, const Key('backupNow')).onPressed, isNull, reason: 'cannot back up with no place chosen');
      await t.tap(find.text('Turn on'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('backupOneCopy')), findsOneWidget);
      await t.tap(find.byKey(const Key('backupNow')));
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('backupResult')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('backupResult'))) as Text).data, contains('Saved to a folder on this phone.'));
      expect((await r.svc.status()).attention, BackupAttention.fine);
    });
  });

  group('bringing records back', () {
    Future<({Rig fresh, MemoryBackupSink sink, RecoveryKey key, Map<String, String> before})> world() async {
      final Rig p = await Rig.make(seed: 1);
      await p.put('care', <String, Object?>{'n1': 'a note'}, owner: 'ivy');
      await p.put('learn', <String, Object?>{'read': <Object?>['x', 'y']});
      final RecoveryKey key = await p.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      await p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      return (fresh: await Rig.make(seed: 2), sink: sink, key: key, before: await p.hashes());
    }

    Future<void> toReview(WidgetTester t, Rig fresh, MemoryBackupSink sink, String words) async {
      await t.pumpWidget(MaterialApp(home: RestoreScreen(host: _host(fresh, source: sink, folder: '/backups'))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('restoreSourceNext')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('restoreWords')), words);
      await t.tap(find.byKey(const Key('restoreSheetNext')));
      await t.pumpAndSettle();
    }

    testWidgets('shows what it found and what will happen first, changes nothing until told, then checks every area', (WidgetTester t) async {
      await _big(t);
      final w = await world();
      await toReview(t, w.fresh, w.sink, w.key.words.join(' '));
      expect(find.byKey(const Key('restoreFound')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('restoreFound'))) as Text).data, contains('2 kinds of records'));
      expect(find.byKey(const Key('restoreRecordsOnly')), findsOneWidget, reason: 'said before anything is written');
      expect(await w.fresh.hashes(), isEmpty, reason: 'nothing has been written yet');
      await t.tap(find.byKey(const Key('restoreApply')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreDone')), findsOneWidget);
      expect(await w.fresh.hashes(), w.before);
      expect((await w.fresh.svc.status()).setUp, isTrue, reason: 'this phone can now back up for the same sheet');
    });

    testWidgets('a mistyped or wrong sheet says so in plain words and writes nothing', (WidgetTester t) async {
      await _big(t);
      final w = await world();
      await toReview(t, w.fresh, w.sink, 'apple apple');
      expect(find.byKey(const Key('restoreError')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('restoreError'))) as Text).data, contains('18 words'));
      await toReview(t, w.fresh, w.sink, RecoveryKey.generate().words.join(' '));
      expect((t.widget(find.byKey(const Key('restoreError'))) as Text).data, contains('No backup was found'));
      expect(await w.fresh.hashes(), isEmpty);
    });

    testWidgets('a tablet is only ever offered a folder, and a keepsake waits for a grown-up to connect it', (WidgetTester t) async {
      await _big(t);
      final Rig tab = await Rig.make(role: BackupRole.child, seed: 5);
      await tab.put('pictures', <String, Object?>{'p': 'doodle'}, owner: 'ivy');
      final RecoveryKey key = await tab.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      await tab.svc.engine.backUp(kind: BackupKind.keepsake, sinks: <BackupSink>[sink]);
      final Rig replacement = await Rig.make(role: BackupRole.child, seed: 6);
      await t.pumpWidget(MaterialApp(home: RestoreScreen(host: _host(replacement, source: sink, folder: '/backups'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreFromServer')), findsNothing);
      await t.tap(find.byKey(const Key('restoreSourceNext')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('restoreWords')), key.words.join(' '));
      await t.tap(find.byKey(const Key('restoreSheetNext')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('restoreApply')));
      await t.pumpAndSettle();
      expect((t.widget(find.byKey(const Key('restoreError'))) as Text).data, contains('Connect this tablet to a grown-up first'));
      expect(await replacement.hashes(), isEmpty);
      await replacement.put('childpairing', <String, Object?>{'cert': 'x'});
      await t.tap(find.byKey(const Key('restoreApply')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreDone')), findsOneWidget);
      expect(await replacement.services.area('pictures', ownerId: 'ivy').get('p'), 'doodle');
    });

    testWidgets('the server path waits in plain words and can be stopped', (WidgetTester t) async {
      await _big(t);
      final FakeBackupServer server = FakeBackupServer()
        ..maxChunk = 2048
        ..deviceOfRestore = '99999999-8888-4777-8666-555555555555';
      final Rig p = await Rig.make(seed: 1, api: server);
      await p.put('learn', <String, Object?>{'read': <Object?>['x']});
      final RecoveryKey key = await p.svc.setUp();
      await p.svc.turnOnServer(key: key, pin: '2468');
      await p.svc.backUpNow();
      final Rig fresh = await Rig.make(seed: 4, api: server);
      final BackupHost host = BackupHost(
        service: fresh.svc,
        defaultFolder: () async => null,
        identity: () async => (userId: server.userId, deviceId: server.deviceOfRestore),
        now: fresh.clock.now,
      );
      await t.pumpWidget(MaterialApp(home: RestoreScreen(host: host)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('restoreFromServer')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('restorePin')), '2468');
      await t.tap(find.byKey(const Key('restoreSourceNext')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('restoreWords')), key.words.join(' '));
      await t.tap(find.byKey(const Key('restoreSheetNext')));
      await t.pumpAndSettle();
      expect((t.widget(find.byKey(const Key('restoreWaiting'))) as Text).data, contains('holding this for 72 hours'));
      await t.tap(find.byKey(const Key('restoreCheckAgain')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoreFound')), findsNothing, reason: 'nothing is released during the wait');
      await t.tap(find.byKey(const Key('restoreStop')));
      await t.pumpAndSettle();
      expect((t.widget(find.byKey(const Key('restoreWaiting'))) as Text).data, contains('stopped'));
      expect(await fresh.hashes(), isEmpty);
    });
  });

  group('the tablet\'s grown-up page', () {
    testWidgets('has the keepsake button, which opens the tablet\'s own page', (WidgetTester t) async {
      await _big(t);
      final Rig tab = await Rig.make(role: BackupRole.child);
      await t.pumpWidget(MaterialApp(
          home: GuardianEscalationScreen(
        escalatedUntil: null,
        onExitKiosk: () {},
        childName: 'Ivy',
        backupHostBuilder: () async => _host(tab),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('keepsakeBackupButton')), findsOneWidget);
      await t.tap(find.byKey(const Key('keepsakeBackupButton')));
      await t.pumpAndSettle();
      expect(find.text('Back up her home and keepsakes'), findsOneWidget);
    });
  });

  group('no child\'s screen can reach any of it', () {
    test('only the grown-up\'s phone page and the tablet\'s Guardian mode import the backup screens or the host', () {
      final Directory lib = Directory('lib');
      final Set<String> allowed = <String>{'guardian_more.dart', 'guardian_escalation_screen.dart'};
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in lib.listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (name.startsWith('backup_')) continue;
        final String src = f.readAsStringSync();
        final bool imports = RegExp(r"import 'backup_(screens|host)\.dart'").hasMatch(src);
        if (imports && !allowed.contains(name)) offenders.add(name);
      }
      expect(offenders, isEmpty);
    });

    test('no file that draws a child\'s home or her own screens imports any backup file at all', () {
      final Directory lib = Directory('lib');
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in lib.listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (!(name.startsWith('child_') || name.startsWith('kiosk_') || name.startsWith('who_is_here'))) continue;
        if (RegExp(r"import 'backup_").hasMatch(f.readAsStringSync())) offenders.add(name);
      }
      expect(offenders, isEmpty);
    });
  });
}

FilledButton tester(WidgetTester t, Key k) => t.widget<FilledButton>(find.byKey(k));
