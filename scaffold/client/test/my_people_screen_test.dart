// OLIVE BRANCH — my_people_screen.dart, my_people_entry.dart and grownup_roster.dart tests: a
// child names her own grown-ups, the default words follow her locked age, her word wins, and a
// grown-up can see it but never write it. No longer UNVERIFIED — verified by CI. MASTERFILE §8.5.10.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart' show kChildTarget;
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/grownup_roster.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/my_people_entry.dart';
import 'package:olive_client/my_people_screen.dart';

class _FailingNicknames implements NicknameRepository {
  @override
  Future<Map<String, String>> load() async => <String, String>{};
  @override
  Future<void> set(String contactId, String? nickname) async => throw StateError('disk full');
}

const GrownupContact mom = GrownupContact(id: 'mom', guardianLabel: 'Mom', kind: GrownupKind.mom);
const GrownupContact dad = GrownupContact(id: 'dad', guardianLabel: 'Dad', kind: GrownupKind.dad);
const GrownupContact nana = GrownupContact(id: 'nana', guardianLabel: 'Nana');

void main() {
  Future<void> pump(
    WidgetTester t, {
    List<GrownupContact> contacts = const <GrownupContact>[mom, dad],
    AgeLockState age = const AgeLockState(age: 7, locked: true),
    NicknameRepository? repo,
    bool firstRun = false,
    VoidCallback? onDone,
  }) async {
    await t.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: MyPeopleScreen(
      contacts: contacts, age: age, nicknames: repo ?? MemoryNicknameRepository(), firstRun: firstRun, onDone: onDone)));
    await t.pumpAndSettle();
  }

  String shown(WidgetTester t, String id) => t.widget<Text>(find.byKey(Key('personName_$id'))).data!;

  group('the words she sees follow the locked age (default words by age)', () {
    testWidgets('a locked age of 5 to 15: Mommy and Daddy', (t) async {
      await pump(t, age: const AgeLockState(age: 5, locked: true));
      expect(shown(t, 'mom'), 'Mommy');
      expect(shown(t, 'dad'), 'Daddy');
    });

    testWidgets('a locked 15 is still Mommy; a locked 16, and an age that is not locked, stay Mom and Dad', (t) async {
      await pump(t, age: const AgeLockState(age: 15, locked: true));
      expect(shown(t, 'mom'), 'Mommy');
      await pump(t, age: const AgeLockState(age: 16, locked: true));
      expect(shown(t, 'mom'), 'Mom');
      await pump(t, age: const AgeLockState(age: 7));
      expect(shown(t, 'mom'), 'Mom');
      expect(shown(t, 'dad'), 'Dad');
      await pump(t, age: const AgeLockState(age: 4, locked: true));
      expect(shown(t, 'dad'), 'Dad');
    });

    testWidgets('anyone who is not a Mom or a Dad keeps the grown-up\'s own word', (t) async {
      await pump(t, contacts: <GrownupContact>[nana]);
      expect(shown(t, 'nana'), 'Nana');
    });
  });

  group('renaming, like renaming a contact', () {
    testWidgets('tap a face, pick from the bank: it is saved, shown at once, and survives a reload', (t) async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await pump(t, repo: repo);
      await t.tap(find.byKey(const Key('person_dad')));
      await t.pumpAndSettle();
      for (final String w in kNicknameBank) {
        expect(find.byKey(Key('bank_$w')), findsOneWidget, reason: w);
      }
      await t.tap(find.byKey(const Key('bank_Dada')));
      await t.pumpAndSettle();
      expect(shown(t, 'dad'), 'Dada');
      expect(shown(t, 'mom'), 'Mommy', reason: 'the other grown-up is untouched');
      expect(await repo.load(), <String, String>{'dad': 'Dada'});
      await pump(t, repo: repo);
      expect(shown(t, 'dad'), 'Dada');
    });

    testWidgets('the bank is exactly the owner\'s words', (t) async {
      expect(kNicknameBank, <String>['Mommy', 'Mama', 'Mum', 'Mom', 'Mummy', 'Daddy', 'Dada', 'Papa', 'Pop', 'Dad']);
    });

    testWidgets('she can type her own word', (t) async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await pump(t, repo: repo);
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('ownName')), '  Mimi  ');
      await t.tap(find.byKey(const Key('ownNameOk')));
      await t.pumpAndSettle();
      expect(shown(t, 'mom'), 'Mimi');
      expect(await repo.load(), <String, String>{'mom': 'Mimi'});
    });

    testWidgets('an empty own word does nothing; a very long one is cut to 24 letters', (t) async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await pump(t, repo: repo);
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ownNameOk')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ownName')), findsOneWidget, reason: 'the sheet stays; nothing was chosen');
      expect(await repo.load(), isEmpty);
      await t.enterText(find.byKey(const Key('ownName')), 'a' * 40);
      await t.tap(find.byKey(const Key('ownNameOk')));
      await t.pumpAndSettle();
      expect((await repo.load())['mom']!.length, lessThanOrEqualTo(kMaxNicknameLength));
    });

    testWidgets('"Use the usual word" goes back to the age default; it only shows once she has renamed', (t) async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await pump(t, repo: repo);
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('nameReset')), findsNothing);
      await t.tap(find.byKey(const Key('bank_Mama')));
      await t.pumpAndSettle();
      expect(shown(t, 'mom'), 'Mama');
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nameReset')));
      await t.pumpAndSettle();
      expect(shown(t, 'mom'), 'Mommy');
      expect(await repo.load(), isEmpty);
    });

    testWidgets('closing the sheet without choosing changes nothing', (t) async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await pump(t, repo: repo);
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(await repo.load(), isEmpty);
      expect(shown(t, 'mom'), 'Mommy');
    });

    testWidgets('a save that fails shows a short plain line, never the error, and the old word stays', (t) async {
      await pump(t, repo: _FailingNicknames());
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bank_Mama')));
      await t.pumpAndSettle();
      expect(find.text('That did not save. Try again.'), findsOneWidget);
      expect(find.textContaining('disk full'), findsNothing);
      expect(shown(t, 'mom'), 'Mommy');
    });
  });

  group('rename precedence: her word, then the age default, then the grown-up\'s label', () {
    test('every rung', () {
      const AgeLockState locked = AgeLockState(age: 7, locked: true);
      final Map<String, String> nick = <String, String>{'mom': 'Mama'};
      expect(ContactLabels.forChild(mom, age: locked, nicknames: nick), 'Mama', reason: 'hers wins');
      expect(ContactLabels.forChild(mom, age: locked), 'Mommy', reason: 'else the age default');
      expect(ContactLabels.forChild(mom, age: const AgeLockState()), 'Mom', reason: 'unlocked: plain Mom');
      expect(ContactLabels.forChild(nana, age: locked), 'Nana', reason: 'no default for her: the label');
      expect(ContactLabels.forChild(nana, age: locked, nicknames: <String, String>{'nana': 'Gran'}), 'Gran');
      expect(ContactLabels.forChild(mom, age: locked, nicknames: <String, String>{'mom': '   '}), 'Mommy',
          reason: 'a blank word is no word');
    });

    testWidgets('the screen shows exactly that, renaming one person does not touch another contact', (t) async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await repo.set('nana', 'Gran');
      await pump(t, contacts: <GrownupContact>[mom, nana], repo: repo);
      expect(shown(t, 'mom'), 'Mommy');
      expect(shown(t, 'nana'), 'Gran');
    });
  });

  group('the guardian sees both and can never overwrite a nickname', () {
    test('"Ivy calls you Dada" for the guardian; nothing a guardian screen holds can write', () async {
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await repo.set(kLocalGuardianContactId, 'Dada');
      final LocalFamily f = LocalFamily.fromAnswers(
          guardianName: 'Sam', guardianLabel: 'Dad', guardianKind: GrownupKind.dad, childName: 'Ivy', age: 7);
      // What a guardian screen is handed: a NicknameReader. It has load() and nothing else.
      final NicknameReader asGuardianSeesIt = repo;
      final Map<String, String> seen = await asGuardianSeesIt.load();
      expect(ContactLabels.forGuardian(f.guardian, childName: 'Ivy', nicknames: seen), 'Dad (Ivy calls you Dada)');
      // The guardian's own label is theirs to edit, and editing it never touches the nickname.
      final LocalFamily renamed = LocalFamily.fromAnswers(
          guardianName: 'Sam', guardianLabel: 'Papa', guardianKind: GrownupKind.other, childName: 'Ivy', age: 7);
      expect(await repo.load(), <String, String>{kLocalGuardianContactId: 'Dada'});
      expect(ContactLabels.forGuardian(renamed.guardian, childName: 'Ivy', nicknames: seen), 'Papa (Ivy calls you Dada)');
    });

    test('the guardian-side code has no path to the writer (source guard)', () {
      // Only the child's own screens import the repository interface that can write.
      final List<String> guardianFiles = <String>[
        'guardian_more.dart', 'guardian_home.dart', 'guardian_home_live.dart', 'local_guardian_home.dart',
        'guardian_boot.dart', 'guardian_onboarding.dart', 'age_lock_screens.dart', 'guardian_local_scope.dart',
      ];
      for (final String f in guardianFiles) {
        final String src = _read(f);
        expect(src, isNot(contains('NicknameRepository')), reason: '$f must only ever see a NicknameReader');
        expect(src, isNot(contains('LocalNicknameRepository')), reason: f);
        expect(src, isNot(contains('MyPeopleScreen')), reason: f);
      }
    });
  });

  group('picture-first, calm, and kind to small fingers', () {
    testWidgets('every target is at least 64dp: the faces, the bank, the own-word button', (t) async {
      await pump(t);
      for (final String id in <String>['mom', 'dad']) {
        expect(t.getSize(find.byKey(Key('person_$id'))).height, greaterThanOrEqualTo(kChildTarget));
        expect(t.getSize(find.byKey(Key('person_$id'))).width, greaterThanOrEqualTo(kChildTarget));
      }
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      for (final String w in kNicknameBank) {
        expect(t.getSize(find.byKey(Key('bank_$w'))).height, greaterThanOrEqualTo(kChildTarget), reason: w);
      }
      expect(t.getSize(find.byKey(const Key('ownNameOk'))).height, greaterThanOrEqualTo(kChildTarget));
    });

    testWidgets('it fits a Fold cover screen at 2x text with a long own word on screen', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 760));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(344, 760), textScaler: TextScaler.linear(2.0)),
          child: MyPeopleScreen(
            contacts: const <GrownupContact>[mom, dad, nana],
            age: const AgeLockState(age: 7, locked: true),
            nicknames: MemoryNicknameRepository(),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('person_mom')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('inside the first run', () {
    testWidgets('it asks "What do you call your grown-ups?", Next and Skip both move on, nothing is required', (t) async {
      int done = 0;
      await pump(t, firstRun: true, onDone: () => done++);
      expect(find.text('What do you call your grown-ups?'), findsOneWidget);
      await t.tap(find.text('Next'));
      await t.pump();
      expect(done, 1);
      await t.tap(find.text('Skip for now'));
      await t.pump();
      expect(done, 2);
    });

    testWidgets('there is no step counter and no progress', (t) async {
      await pump(t, firstRun: true, onDone: () {});
      expect(find.textContaining(RegExp(r'step \d|of \d', caseSensitive: false)), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('from her More hub (the entry)', () {
    testWidgets('with no local family: two neutral placeholders, nobody invented', (t) async {
      LocalServices.resetForTest();
      addTearDown(LocalServices.resetForTest);
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: MyPeopleEntry()));
      await t.pumpAndSettle();
      expect(find.text('My people'), findsWidgets);
      expect(shown(t, kPlaceholderGrownupOne), 'Your grown-up');
      expect(shown(t, kPlaceholderGrownupTwo), 'Your other grown-up');
      expect(find.text('Mom'), findsNothing);
      expect(find.text('Dad'), findsNothing);
      expect(find.text('Mommy'), findsNothing);
    });

    testWidgets('with a local family it names the real grown-up, with the age default from the locked age', (t) async {
      final LocalFamily f = LocalFamily.fromAnswers(
          guardianName: 'Sam', guardianLabel: 'Dad', guardianKind: GrownupKind.dad, childName: 'Ivy', age: 9);
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final MemoryNicknameRepository repo = MemoryNicknameRepository();
      await t.pumpWidget(MaterialApp(
        home: MyPeopleEntry(
          nicknames: repo,
          loadRoster: () => loadKidRoster(MemoryLocalFamilyRepository(f)),
        ),
      ));
      await t.pumpAndSettle();
      expect(shown(t, kLocalGuardianContactId), 'Daddy');
      await t.tap(find.byKey(const Key('person_$kLocalGuardianContactId')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bank_Dada')));
      await t.pumpAndSettle();
      expect(shown(t, kLocalGuardianContactId), 'Dada');
      expect(await repo.load(), <String, String>{kLocalGuardianContactId: 'Dada'});
    });

    testWidgets('with no family, the age lock cached with her profile still picks the default words', (t) async {
      LocalServices.resetForTest();
      addTearDown(LocalServices.resetForTest);
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: MyPeopleEntry(
          loadRoster: () async => const KidRoster(
              contacts: <GrownupContact>[mom], known: true, age: AgeLockState(age: 6, locked: true)),
        ),
      ));
      await t.pumpAndSettle();
      expect(shown(t, 'mom'), 'Mommy');
    });
  });

  group('the roster', () {
    test('a local family gives its real grown-ups, her name and the locked age', () async {
      final LocalFamily f = LocalFamily.fromAnswers(
          guardianName: 'Sam', guardianLabel: 'Mom', guardianKind: GrownupKind.mom, childName: 'Ivy', age: 8);
      final KidRoster r = await loadKidRoster(MemoryLocalFamilyRepository(f));
      expect(r.known, isTrue);
      expect(r.contacts.single.id, kLocalGuardianContactId);
      expect(r.contacts.single.kind, GrownupKind.mom);
      expect(r.childName, 'Ivy');
      expect(r.age.locked, isTrue);
      expect(r.age.age, 8);
    });

    test('no family: neutral placeholders (no Mom, no Dad, no invented person), unknown, the age as given', () async {
      final KidRoster r = await loadKidRoster(MemoryLocalFamilyRepository(),
          fallbackAge: const AgeLockState(age: 6, locked: true));
      expect(r.known, isFalse);
      expect(r.contacts.map((GrownupContact c) => c.guardianLabel).toList(), <String>['Your grown-up', 'Your other grown-up']);
      expect(r.contacts.every((GrownupContact c) => c.kind == GrownupKind.other), isTrue);
      expect(r.age.age, 6);
      expect(r.childName, '');
    });

    test('a null or unreadable family store never blocks a child: placeholders', () async {
      expect((await loadKidRoster(null)).known, isFalse);
      expect((await loadKidRoster(_ThrowingFamilies())).known, isFalse);
    });

    test('adopting pending names moves them to the connected child, hers win, and nothing is lost', () async {
      final MemoryNicknameRepository pending = MemoryNicknameRepository();
      final MemoryNicknameRepository hers = MemoryNicknameRepository();
      await pending.set('placeholder-1', 'Mama');
      await pending.set('placeholder-2', 'Papa');
      await hers.set('placeholder-2', 'Pop'); // already named after connecting: hers wins
      final int copied = await adoptPendingNicknames(from: pending, to: hers);
      expect(copied, 1);
      expect(await hers.load(), <String, String>{'placeholder-1': 'Mama', 'placeholder-2': 'Pop'});
      expect(await pending.load(), isEmpty, reason: 'moved, so it is done once');
      expect(await adoptPendingNicknames(from: pending, to: hers), 0);
    });

    test('adopting never throws, and a name leaves pending only after the new store has it', () async {
      final MemoryNicknameRepository pending = MemoryNicknameRepository();
      await pending.set('placeholder-1', 'Mama');
      expect(await adoptPendingNicknames(from: pending, to: _FailingNicknames()), 0);
      expect(await pending.load(), <String, String>{'placeholder-1': 'Mama'}, reason: 'nothing lost');
    });
  });
}

class _ThrowingFamilies implements LocalFamilyRepository {
  @override
  Future<LocalFamily?> load() async => throw StateError('unreadable');
  @override
  Future<void> save(LocalFamily family) async {}
  @override
  Future<void> clear() async {}
}

String _read(String name) => File('lib/$name').readAsStringSync();
