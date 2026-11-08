// OLIVE BRANCH — contact_labels.dart tests: default labels by age, the
// nickname layer and its precedence, the age lock. No longer UNVERIFIED —
// verified by CI. MASTERFILE §8.5.7.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

const GrownupContact mom = GrownupContact(id: 'm', guardianLabel: 'Mom', kind: GrownupKind.mom);
const GrownupContact dad = GrownupContact(id: 'd', guardianLabel: 'Dad', kind: GrownupKind.dad);
const GrownupContact nana = GrownupContact(id: 'n', guardianLabel: 'Nana');

void main() {
  group('default labels by age (one constant, owner wording)', () {
    test('unlocked: neutral Mom and Dad at any age', () {
      for (final int a in <int>[3, 5, 10, 15, 17]) {
        expect(ContactLabels.ageDefault(GrownupKind.mom, AgeLockState(age: a)), 'Mom');
        expect(ContactLabels.ageDefault(GrownupKind.dad, AgeLockState(age: a)), 'Dad');
      }
      expect(ContactLabels.ageDefault(GrownupKind.mom, const AgeLockState()), 'Mom');
    });

    test('locked 5 to 15: Mommy and Daddy, on both edges', () {
      for (final int a in <int>[5, 9, 15]) {
        final AgeLockState s = AgeLockState(age: a, locked: true);
        expect(ContactLabels.ageDefault(GrownupKind.mom, s), 'Mommy', reason: '$a');
        expect(ContactLabels.ageDefault(GrownupKind.dad, s), 'Daddy', reason: '$a');
      }
    });

    test('locked at 16 and over (or under the range): Mom and Dad', () {
      for (final int a in <int>[3, 4, 16, 17]) {
        final AgeLockState s = AgeLockState(age: a, locked: true);
        expect(ContactLabels.ageDefault(GrownupKind.mom, s), 'Mom', reason: '$a');
        expect(ContactLabels.ageDefault(GrownupKind.dad, s), 'Dad', reason: '$a');
      }
    });

    test('anyone else has no age default', () {
      expect(ContactLabels.ageDefault(GrownupKind.other, const AgeLockState(age: 8, locked: true)), isNull);
    });

    test('the rule is the single constant', () {
      expect(kLittleWordsAges, (min: 5, max: 15));
    });
  });

  group('what the child sees: nickname, else age default, else guardian label', () {
    const AgeLockState locked8 = AgeLockState(age: 8, locked: true);
    test('age default beats the guardian label for a Mom or Dad', () {
      expect(ContactLabels.forChild(mom, age: locked8), 'Mommy');
      expect(ContactLabels.forChild(dad, age: locked8), 'Daddy');
    });
    test('a guardian label stands for anyone else', () {
      expect(ContactLabels.forChild(nana, age: locked8), 'Nana');
    });
    test('her nickname beats everything', () {
      expect(ContactLabels.forChild(dad, age: locked8, nicknames: <String, String>{'d': 'Dada'}), 'Dada');
      expect(ContactLabels.forChild(nana, age: locked8, nicknames: <String, String>{'n': 'Gran'}), 'Gran');
    });
    test('a blank nickname is ignored; a long one is cut', () {
      expect(ContactLabels.forChild(dad, age: locked8, nicknames: <String, String>{'d': '   '}), 'Daddy');
      expect(ContactLabels.cleanNickname('x' * 40)!.length, kMaxNicknameLength);
      expect(ContactLabels.cleanNickname('  Papa '), 'Papa');
    });
    test('the bank offers the owner\'s words', () {
      expect(kNicknameBank, containsAll(<String>['Mommy', 'Mama', 'Mum', 'Mom', 'Mummy', 'Daddy', 'Dada', 'Papa', 'Pop', 'Dad']));
    });
  });

  group('what a guardian sees: both', () {
    test('shows how she says it', () {
      expect(ContactLabels.forGuardian(dad, childName: 'Ivy', nicknames: <String, String>{'d': 'Dada'}),
          'Dad (Ivy calls you Dada)');
    });
    test('shows just their label when she has not renamed it, or used the same word', () {
      expect(ContactLabels.forGuardian(dad, childName: 'Ivy'), 'Dad');
      expect(ContactLabels.forGuardian(dad, childName: 'Ivy', nicknames: <String, String>{'d': 'Dad'}), 'Dad');
    });
  });

  group('the nickname repository is hers', () {
    test('set, rename, clear (memory)', () async {
      final MemoryNicknameRepository r = MemoryNicknameRepository();
      await r.set('d', 'Dada');
      expect(await r.load(), <String, String>{'d': 'Dada'});
      await r.set('d', 'Papa');
      expect(await r.load(), <String, String>{'d': 'Papa'});
      await r.set('d', '  ');
      expect(await r.load(), isEmpty);
    });

    test('LocalStore-backed: survives a restart, and a guardian edit of the label never changes it', () async {
      final MemoryStoreBackend files = MemoryStoreBackend();
      LocalNicknameRepository open() => LocalNicknameRepository(
          LocalServices.memory(childId: 'ivy', isLive: true, demoSeeds: false, backend: files).area('nicknames'));
      await open().set('d', 'Dada');
      final Map<String, String> back = await open().load();
      expect(back, <String, String>{'d': 'Dada'});

      const GrownupContact renamed = GrownupContact(id: 'd', guardianLabel: 'Father', kind: GrownupKind.dad);
      expect(ContactLabels.forChild(renamed, age: const AgeLockState(age: 8, locked: true), nicknames: back), 'Dada');
      expect(await open().load(), <String, String>{'d': 'Dada'});
    });

    test('is in the data catalogue as hers, unsealed, with a plain-words description', () {
      final LocalDataEntry e = localDataEntry('nicknames');
      expect(e.scope, LocalScope.child);
      expect(e.what, contains('not'));
    });

    test('a hostile stored value is dropped, not trusted', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy', isLive: true, demoSeeds: false);
      await s.area('nicknames').put('names', <String, Object?>{'a': 5, 'b': '', 'c': 'Mama'});
      expect(await LocalNicknameRepository(s.area('nicknames')).load(), <String, String>{'c': 'Mama'});
    });
  });

  group('the age lock', () {
    test('the kid picker clamps to 5 to 15 and locks', () {
      expect(lockKidAge(3).age, 5);
      expect(lockKidAge(17).age, 15);
      expect(lockKidAge(9).age, 9);
      expect(lockKidAge(9).locked, isTrue);
    });
    test('locked: no change without the guardian PIN', () {
      final AgeLockState s = lockKidAge(9);
      final AgeLockState after = changeAge(s, 12, guardianPinOk: false);
      expect(after.age, 9);
      expect(after.locked, isTrue);
    });
    test('locked: a guardian past the PIN gate may set 3 to 17', () {
      final AgeLockState s = lockKidAge(9);
      expect(changeAge(s, 3, guardianPinOk: true).age, 3);
      expect(changeAge(s, 17, guardianPinOk: true).age, 17);
      expect(changeAge(s, 99, guardianPinOk: true).age, 17);
      expect(changeAge(s, 4, guardianPinOk: true).locked, isTrue);
    });
    test('unlocked: the kid range applies until it is locked', () {
      expect(changeAge(const AgeLockState(age: 7), 2, guardianPinOk: false).age, 5);
    });
    test('age 16 set by a guardian flips the default words back to Mom and Dad', () {
      final AgeLockState s = changeAge(lockKidAge(9), 16, guardianPinOk: true);
      expect(ContactLabels.forChild(dad, age: s), 'Dad');
    });
  });
}
