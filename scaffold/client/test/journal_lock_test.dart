// OLIVE BRANCH — the journal lock, taking a page out, and the P7 structure around them. No longer UNVERIFIED
// (this file is the check). Parity rows 316-318; prototype scenarios kid.jKey / kid.jLockOn / kid.jUnlockOff.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/journal_lock.dart';
import 'package:olive_client/journal_screen.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 7));

LocalServices _device(MemoryStoreBackend b) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: 'ivy', isLive: false, demoSeeds: false);

JournalLock _lock({DateTime Function()? now}) => JournalLock.forChild(iterations: 1000, now: now);

Future<void> _show(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(700, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String code) async {
  for (final String d in code.split('')) {
    await t.tap(find.byKey(Key('journalKey$d')));
    await t.pump();
  }
  await t.pumpAndSettle();
}

Widget _journal({int age = 13, JournalLock? lock}) =>
    JournalScreen(childName: 'Ivy', childAge: age, lock: lock ?? _lock());

void main() {
  setUp(() => LocalServices.install(_device(MemoryStoreBackend())));

  group('the lock service', () {
    test('four numbers only; a wrong shape is refused and nothing is kept', () async {
      final JournalLock l = _lock();
      for (final String bad in <String>['123', '12345', 'abcd', '']) {
        expect(() => l.turnOn(bad), throwsArgumentError, reason: bad);
      }
      expect(await l.isOn(), isFalse);
    });

    test('opens with the right code, not the wrong one, and rests after five wrong tries', () async {
      DateTime t = DateTime(2026, 11, 13, 9);
      final JournalLock l = _lock(now: () => t);
      await l.turnOn('2580');
      expect(await l.tryOpen('2580'), JournalOpen.opened);
      for (int i = 0; i < 4; i++) {
        expect(await l.tryOpen('1111'), JournalOpen.wrong);
      }
      expect(await l.tryOpen('1111'), JournalOpen.resting);
      expect(await l.tryOpen('2580'), JournalOpen.resting, reason: 'even the right code waits out the rest');
      t = t.add(const Duration(minutes: 16));
      expect(await l.tryOpen('2580'), JournalOpen.opened);
    });

    test('the four numbers are never written down: the sealed record holds only a salted hash', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      await _lock().turnOn('2580');
      final LocalNamespace ns = LocalServices.current.area('journal');
      final String record = (await ns.get('pin')).toString();
      expect(record.contains('2580'), isFalse);
      expect(record, contains('salt'));
      expect(record, contains('hash'));
    });

    test('turning it off leaves no lock', () async {
      final JournalLock l = _lock();
      await l.turnOn('2580');
      await l.turnOff();
      expect(await l.isOn(), isFalse);
      expect(await l.tryOpen('2580'), JournalOpen.notLocked);
    });
  });

  group('the screen', () {
    testWidgets('a journal with no lock opens at once and offers a lock from 13, not before', (WidgetTester t) async {
      await _show(t, _journal());
      expect(find.byKey(const Key('journalLockRow')), findsOneWidget);
      expect(find.text('Add a lock'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await _show(t, _journal(age: 12));
      expect(find.byKey(const Key('journalLockRow')), findsNothing);
    });

    testWidgets('picking a code twice locks it; a different second code starts over in gentle words', (WidgetTester t) async {
      await _show(t, _journal());
      await t.ensureVisible(find.byKey(const Key('journalLockRow')));
      await t.tap(find.byKey(const Key('journalLockRow')));
      await t.pumpAndSettle();
      expect(find.text('Pick a code'), findsOneWidget);
      await _type(t, '2580');
      expect(find.text('Pick it again'), findsOneWidget);
      await _type(t, '9999');
      expect(find.text('Pick a code'), findsOneWidget);
      expect(find.textContaining("Let's try that again"), findsOneWidget);
      await _type(t, '2580');
      await _type(t, '2580');
      expect(find.text('Locked with my code'), findsOneWidget);
      expect(await _lock().isOn(), isTrue);
    });

    testWidgets('a locked journal shows only the keypad: no pages, no privacy line, until the right code', (WidgetTester t) async {
      await _lock().turnOn('2580');
      await JournalRepository.forChild().add(
          JournalEntry(id: 'j1', childId: 'ivy', body: 'a secret page', createdAt: DateTime(2026, 11, 1)));
      await _show(t, _journal());
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.text('a secret page'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await _type(t, '1111');
      // A wrong code just empties the dots: no message, no count.
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.textContaining('wrong', findRichText: true), findsNothing);
      expect(find.textContaining('attempt'), findsNothing);
      await _type(t, '2580');
      expect(find.text('a secret page'), findsOneWidget);
    });

    testWidgets('five wrong tries rest calmly, with no error word', (WidgetTester t) async {
      await _lock().turnOn('2580');
      await _show(t, _journal());
      for (int i = 0; i < 5; i++) {
        await _type(t, '1111');
      }
      expect(find.text("Let's try again in a little while."), findsOneWidget);
    });

    testWidgets('I forgot my code: the way out is a new journal, said plainly, and the old pages go for good', (WidgetTester t) async {
      await _lock().turnOn('2580');
      await JournalRepository.forChild().add(
          JournalEntry(id: 'j1', childId: 'ivy', body: 'old page', createdAt: DateTime(2026, 11, 1)));
      await _show(t, _journal());
      await t.tap(find.byKey(const Key('journalForgot')));
      await t.pumpAndSettle();
      expect(find.textContaining('Not even a grown-up'), findsOneWidget);
      expect(find.textContaining('go for good'), findsOneWidget);
      await t.tap(find.byKey(const Key('journalKeepTrying')));
      await t.pumpAndSettle();
      expect(find.text('Enter your code'), findsOneWidget);
      await t.tap(find.byKey(const Key('journalForgot')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('journalStartNew')));
      await t.pumpAndSettle();
      expect(find.text('old page'), findsNothing);
      expect(find.text('Add a lock'), findsOneWidget);
      expect(await JournalRepository.forChild().load(), isEmpty);
      expect(await _lock().isOn(), isFalse);
    });

    testWidgets('taking the lock off from inside the open journal', (WidgetTester t) async {
      final JournalLock l = _lock();
      await l.turnOn('2580');
      await _show(t, _journal(lock: l));
      await _type(t, '2580');
      await t.ensureVisible(find.byKey(const Key('journalLockRow')));
      await t.tap(find.byKey(const Key('journalLockRow')));
      await t.pumpAndSettle();
      expect(find.text('Add a lock'), findsOneWidget);
      expect(await l.isOn(), isFalse);
    });

    testWidgets('taking a page out asks once, says it goes for good, and removes it from the disk too', (WidgetTester t) async {
      await JournalRepository.forChild().add(
          JournalEntry(id: 'j1', childId: 'ivy', body: 'page one', createdAt: DateTime(2026, 11, 1)));
      await _show(t, _journal());
      await t.ensureVisible(find.byKey(const ValueKey<String>('takeOut-j1')));
      await t.tap(find.byKey(const ValueKey<String>('takeOut-j1')));
      await t.pumpAndSettle();
      expect(find.text('It goes for good.'), findsOneWidget);
      await t.tap(find.byKey(const Key('journalPageKeep')));
      await t.pumpAndSettle();
      expect(find.text('page one'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('takeOut-j1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('journalPageTakeOut')));
      await t.pumpAndSettle();
      expect(find.text('page one'), findsNothing);
      expect(await JournalRepository.forChild().load(), isEmpty);
    });
  });

  group('P7 structure', () {
    test('every place the app builds a JournalScreen passes a lock, so no door skips the code', () {
      final RegExp call = RegExp(r'JournalScreen\(([^;]*?)\)\)?[;,]', dotAll: true);
      int found = 0;
      for (final File f in Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('journal_screen.dart')) continue;
        final String src = f.readAsStringSync();
        for (final Match m in call.allMatches(src)) {
          found++;
          expect(m.group(0), contains('lock:'), reason: '${f.path} builds a JournalScreen without a lock');
        }
      }
      expect(found, greaterThanOrEqualTo(2));
    });

    test('no guardian-side file reaches the journal, its lock, her door marks or her weather', () {
      final List<String> guardianSide = <String>[
        for (final File f in Directory('lib').listSync().whereType<File>())
          if (RegExp(r'(guardian_|g_|parent_|family_agreement|expenses_|care_|meds_|emergency_|court_)').hasMatch(f.uri.pathSegments.last)) f.path,
      ];
      expect(guardianSide, isNotEmpty);
      for (final String p in guardianSide) {
        final String src =
            File(p).readAsLinesSync().where((String l) => !l.trimLeft().startsWith('//')).join(' ');
        for (final String banned in <String>['journal_screen.dart', 'journal_lock.dart', 'my_marks.dart', 'JournalRepository', 'MyMarksRepository']) {
          expect(src.contains(banned), isFalse, reason: '$p mentions $banned');
        }
      }
    });

    test('the lock and the marks have no reader, role or guardian argument anywhere', () {
      for (final String p in <String>['lib/journal_lock.dart', 'lib/my_marks.dart']) {
        final String code = File(p)
            .readAsLinesSync()
            .where((String l) => !l.trimLeft().startsWith('//'))
            .join('\n')
            .toLowerCase();
        expect(code.contains('guardian'), isFalse, reason: p);
        expect(code.contains('readerrole'), isFalse, reason: p);
      }
    });
  });
}
