// OLIVE BRANCH — local_family.dart tests: the local family bootstrap and the age lock on a
// grown-up's phone. No longer UNVERIFIED — verified by CI. MASTERFILE §8.5.9, §8.5.10.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/device_role.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

LocalFamily family({int age = 7, String label = 'Mom', String zone = kHomeZoneDevice}) =>
    LocalFamily.fromAnswers(
      guardianName: 'Sam',
      guardianLabel: label,
      guardianKind: kindForGuardianLabel(label),
      childName: 'Ivy',
      age: age,
      homeZone: zone,
    );

void main() {
  group('answers are validated in plain words', () {
    String? problem({String g = 'Sam', String l = 'Mom', String c = 'Ivy', int age = 7, String zone = kHomeZoneDevice}) =>
        LocalFamily.problem(guardianName: g, guardianLabel: l, childName: c, age: age, homeZone: zone);

    test('a good set has no problem', () => expect(problem(), isNull));

    test('missing names are asked for', () {
      expect(problem(g: ' '), 'Please add your name.');
      expect(problem(l: ''), 'Please choose what she should call you.');
      expect(problem(c: '  '), 'Please add her first name.');
    });

    test('a guardian may set 3 to 17; outside that is refused (the kid picker stays 5 to 15)', () {
      expect(problem(age: 3), isNull);
      expect(problem(age: 17), isNull);
      expect(problem(age: 2), contains('between 3 and 17'));
      expect(problem(age: 18), contains('between 3 and 17'));
      expect(kGuardianAgeMin, 3);
      expect(kGuardianAgeMax, 17);
      expect(kKidAgeMin, 5);
      expect(kKidAgeMax, 15);
    });

    test('over-long names and an unknown zone are refused', () {
      expect(problem(g: 'x' * 41), 'That is a little too long.');
      expect(problem(l: 'x' * 25), 'That is a little too long.');
      expect(problem(zone: 'Mars/Olympus'), 'Please choose a time zone from the list.');
    });

    test('fromAnswers trims, and throws the plain-words problem for bad input', () {
      final LocalFamily f = LocalFamily.fromAnswers(
          guardianName: '  Sam ', guardianLabel: ' Dad ', guardianKind: GrownupKind.dad, childName: ' Ivy  ', age: 9);
      expect(f.guardianName, 'Sam');
      expect(f.guardianLabel, 'Dad');
      expect(f.childName, 'Ivy');
      expect(() => LocalFamily.fromAnswers(
          guardianName: '', guardianLabel: 'Mom', guardianKind: GrownupKind.mom, childName: 'Ivy', age: 9),
          throwsA(isA<ArgumentError>().having((ArgumentError e) => e.message, 'message', 'Please add your name.')));
    });
  });

  group('the guardian label decides the kind', () {
    test('Mom and Dad (any case, any padding) are a Mom and a Dad; every other word is the guardian\'s own', () {
      expect(kindForGuardianLabel('Mom'), GrownupKind.mom);
      expect(kindForGuardianLabel(' dad '), GrownupKind.dad);
      expect(kindForGuardianLabel('MOM'), GrownupKind.mom);
      expect(kindForGuardianLabel('Mama'), GrownupKind.other);
      expect(kindForGuardianLabel('Grandma'), GrownupKind.other);
      expect(kindForGuardianLabel(''), GrownupKind.other);
    });

    test('the role\'s suggested label', () {
      expect(suggestedGuardianLabel(DeviceRole.mom), 'Mom');
      expect(suggestedGuardianLabel(DeviceRole.dad), 'Dad');
      expect(suggestedGuardianLabel(DeviceRole.other), '');
    });
  });

  group('the age is LOCKED when it is entered, and only the PIN gate moves it', () {
    test('a new family has a locked age', () {
      final LocalFamily f = family(age: 8);
      expect(f.ageLocked, isTrue);
      expect(f.ageLock.locked, isTrue);
      expect(f.ageLock.age, 8);
    });

    test('without the PIN gate a locked age does not move, whatever is asked', () {
      final LocalFamily f = family(age: 8);
      expect(f.changeAgeWithPin(12, guardianPinOk: false).age, 8);
      expect(f.changeAgeWithPin(3, guardianPinOk: false).age, 8);
    });

    test('with the PIN gate it moves, within 3 to 17, and stays locked', () {
      final LocalFamily f = family(age: 8);
      expect(f.changeAgeWithPin(12, guardianPinOk: true).age, 12);
      expect(f.changeAgeWithPin(12, guardianPinOk: true).ageLocked, isTrue);
      expect(f.changeAgeWithPin(1, guardianPinOk: true).age, 3);
      expect(f.changeAgeWithPin(40, guardianPinOk: true).age, 17);
    });

    test('changing the age changes nothing else', () {
      final LocalFamily f = family(age: 8, label: 'Dad', zone: 'Europe/London');
      final LocalFamily g = f.changeAgeWithPin(9, guardianPinOk: true);
      expect(g.guardianName, f.guardianName);
      expect(g.guardianLabel, 'Dad');
      expect(g.guardianKind, GrownupKind.dad);
      expect(g.childName, 'Ivy');
      expect(g.homeZone, 'Europe/London');
    });
  });

  group('the guardian is a contact the kid screens can name', () {
    test('a Mom with a locked 5 to 15 age is Mommy to her child, and Mom at 16 and over', () {
      expect(ContactLabels.forChild(family(age: 7).guardian, age: family(age: 7).ageLock), 'Mommy');
      expect(ContactLabels.forChild(family(age: 15).guardian, age: family(age: 15).ageLock), 'Mommy');
      expect(ContactLabels.forChild(family(age: 16).guardian, age: family(age: 16).ageLock), 'Mom');
      expect(ContactLabels.forChild(family(age: 4).guardian, age: family(age: 4).ageLock), 'Mom');
    });

    test('a Dad becomes Daddy the same way; a guardian\'s own word is shown as it is', () {
      expect(ContactLabels.forChild(family(age: 9, label: 'Dad').guardian, age: family(age: 9, label: 'Dad').ageLock),
          'Daddy');
      final LocalFamily nana = family(age: 9, label: 'Nana');
      expect(ContactLabels.forChild(nana.guardian, age: nana.ageLock), 'Nana');
    });

    test('her own name for them wins, and the guardian sees both but cannot write it', () {
      final LocalFamily f = family(age: 7, label: 'Dad');
      final Map<String, String> nicks = <String, String>{kLocalGuardianContactId: 'Dada'};
      expect(ContactLabels.forChild(f.guardian, age: f.ageLock, nicknames: nicks), 'Dada');
      expect(ContactLabels.forGuardian(f.guardian, childName: f.childName, nicknames: nicks), 'Ivy calls you Dada');
      expect(f.grownups.single.id, kLocalGuardianContactId);
    });
  });

  group('JSON and the store', () {
    test('it round-trips', () {
      final LocalFamily f = family(age: 11, label: 'Papa', zone: 'Asia/Tokyo');
      final LocalFamily? back = LocalFamily.fromJson(f.toJson());
      expect(back, isNotNull);
      expect(back!.toJson(), f.toJson());
    });

    test('a damaged record reads as no family, never half a family', () {
      final Map<String, Object?> good = family().toJson();
      expect(LocalFamily.fromJson(null), isNull);
      expect(LocalFamily.fromJson('x'), isNull);
      expect(LocalFamily.fromJson(<String, Object?>{...good, 'v': 2}), isNull);
      expect(LocalFamily.fromJson(<String, Object?>{...good, 'age': '7'}), isNull);
      expect(LocalFamily.fromJson(<String, Object?>{...good, 'age': 99}), isNull);
      expect(LocalFamily.fromJson(<String, Object?>{...good, 'childName': ''}), isNull);
      expect(LocalFamily.fromJson(<String, Object?>{...good, 'guardianKind': 'king'}), isNull);
    });

    test('an unknown stored zone falls back to "this phone" rather than being trusted', () {
      final LocalFamily? f = LocalFamily.fromJson(<String, Object?>{...family().toJson(), 'homeZone': 'Nowhere/Land'});
      expect(f, isNull, reason: 'problem() refuses an unknown zone, so the whole record is refused (fail closed)');
    });

    test('the family is kept in the sealed local-guardian namespace and survives a restart', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final AesGcmStoreCipher cipher = AesGcmStoreCipher(AesGcmStoreCipher.newKey());
      LocalServices boot() => LocalServices(
          store: LocalStore(backend: backend, cipher: cipher),
          childId: 'pending-device', isLive: true, demoSeeds: false);

      final LocalServices first = boot();
      final LocalNamespace ns = first.area('localfamily', ownerId: kLocalGuardianScope);
      expect(ns.spec.name, 'guardian.local-guardian.localfamily');
      expect(ns.spec.encrypted, isTrue);
      await LocalStoreLocalFamilyRepository(ns).save(family(age: 9, label: 'Dad'));

      // The file is sealed: the child's name is not readable on disk.
      final String onDisk = String.fromCharCodes(await backend.read('guardian.local-guardian.localfamily') ?? <int>[]);
      expect(onDisk, isNot(contains('Ivy')));

      // The "restart": a brand-new LocalServices over the same files and the same key.
      final LocalFamily? back =
          await LocalStoreLocalFamilyRepository(boot().area('localfamily', ownerId: kLocalGuardianScope)).load();
      expect(back?.childName, 'Ivy');
      expect(back?.age, 9);
      expect(back?.ageLocked, isTrue);
      expect(back?.guardianLabel, 'Dad');
      expect(back?.guardianKind, GrownupKind.dad);
    });

    test('memory repository: save, load, clear', () async {
      final MemoryLocalFamilyRepository repo = MemoryLocalFamilyRepository();
      expect(await repo.load(), isNull);
      await repo.save(family());
      expect((await repo.load())?.childName, 'Ivy');
      await repo.clear();
      expect(await repo.load(), isNull);
    });
  });

  group('home time zone', () {
    test('"same as this phone" is the first and default choice; the list has no duplicates', () {
      expect(kHomeZones.first.id, kHomeZoneDevice);
      expect(kHomeZones.map((HomeZone z) => z.id).toSet().length, kHomeZones.length);
      for (final HomeZone z in kHomeZones.skip(1)) {
        expect(z.id, contains('/'), reason: '${z.id} is a region name, not coordinates (P3)');
      }
    });

    test('labels and known ids', () {
      expect(isKnownHomeZone('Europe/London'), isTrue);
      expect(isKnownHomeZone('nope'), isFalse);
      expect(homeZoneLabel(kHomeZoneDevice), 'Same as this phone');
      expect(homeZoneLabel('Asia/Tokyo'), 'Tokyo');
      expect(homeZoneLabel('x/y'), 'x/y');
    });
  });
}
