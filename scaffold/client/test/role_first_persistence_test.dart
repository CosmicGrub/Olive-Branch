// OLIVE BRANCH — what survives a restart in the role-first first run: the role, the locked age
// cached with her profile, the names she gave before connecting, and the carry-over once a device
// is connected. No longer UNVERIFIED — verified by CI. MASTERFILE §8.5.8, §8.5.10.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/device_role.dart';
import 'package:olive_client/grownup_roster.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/onboarding_draft.dart';
import 'package:olive_client/store_cipher.dart';

class _BrokenDraft implements OnboardingDraftRepository {
  @override
  Future<OnboardingDraft?> load() async => throw StateError('unreadable');
  @override
  Future<void> save(OnboardingDraft draft) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  late MemoryStoreBackend backend;
  late AesGcmStoreCipher cipher;

  LocalServices boot({String child = 'pending-device'}) => LocalServices(
      store: LocalStore(backend: backend, cipher: cipher), childId: child, isLive: true, demoSeeds: false);

  setUp(() {
    backend = MemoryStoreBackend();
    cipher = AesGcmStoreCipher(AesGcmStoreCipher.newKey());
  });

  group('the role, the local family and the local PIN survive a restart together', () {
    test('a Mom device restarts into the same role, family and PIN; nothing is asked again', () async {
      final LocalServices first = boot();
      await LocalDeviceRoleRepository(first.area('role')).save(DeviceRole.mom);
      await LocalStoreLocalFamilyRepository(first.area('localfamily', ownerId: kLocalGuardianScope)).save(
          LocalFamily.fromAnswers(
              guardianName: 'Sam', guardianLabel: 'Mom', guardianKind: GrownupKind.mom, childName: 'Ivy', age: 7));
      await LocalPinService(
        LocalStoreLocalPinRepository(first.area('localpin', ownerId: kLocalGuardianScope)), iterations: 500,
      ).setPin('4821');

      final LocalServices second = boot();
      expect(await LocalDeviceRoleRepository(second.area('role')).load(), DeviceRole.mom);
      expect((await LocalStoreLocalFamilyRepository(second.area('localfamily', ownerId: kLocalGuardianScope)).load())?.childName,
          'Ivy');
      final LocalPinService pin = LocalPinService(
          LocalStoreLocalPinRepository(second.area('localpin', ownerId: kLocalGuardianScope)), iterations: 500);
      expect(await pin.isSet(), isTrue);
      expect((await pin.verify('4821')).ok, isTrue);
      expect((await pin.verify('0000')).ok, isFalse);
    });

    test('the lock count survives the restart too (five wrong tries, then a new process, still locked)', () async {
      final LocalServices first = boot();
      final LocalPinService a = LocalPinService(
          LocalStoreLocalPinRepository(first.area('localpin', ownerId: kLocalGuardianScope)), iterations: 500);
      await a.setPin('4821');
      for (int i = 0; i < 5; i++) {
        await a.verify('0000');
      }
      final LocalPinService b = LocalPinService(
          LocalStoreLocalPinRepository(boot().area('localpin', ownerId: kLocalGuardianScope)), iterations: 500);
      expect((await b.verify('4821')).outcome, PinOutcome.locked);
    });

    test('a device wipe removes the role, the family and the PIN, and the device asks "who is using this?" again', () async {
      final LocalServices s = boot();
      await LocalDeviceRoleRepository(s.area('role')).save(DeviceRole.dad);
      await LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)).save(
          LocalFamily.fromAnswers(
              guardianName: 'Sam', guardianLabel: 'Dad', guardianKind: GrownupKind.dad, childName: 'Ivy', age: 7));
      await LocalPinService(LocalStoreLocalPinRepository(s.area('localpin', ownerId: kLocalGuardianScope)), iterations: 500)
          .setPin('4821');
      await s.wipeAll();
      expect(await LocalDeviceRoleRepository(s.area('role')).load(), isNull);
      expect(await LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)).load(), isNull);
      expect(await LocalPinService(LocalStoreLocalPinRepository(s.area('localpin', ownerId: kLocalGuardianScope)), iterations: 500).isSet(),
          isFalse);
    });
  });

  group('her locked age is cached with her profile', () {
    test('lockAge records it, locked, and keeps everything else', () async {
      final ProfileCacheRepository repo = ProfileCacheRepository(boot(child: 'ivy').area('profile'));
      await repo.rememberHome(displayName: 'Ivy', overrides: <String, Object?>{'hide': <Object?>[]});
      await repo.markOnboarded();
      await repo.lockAge(8);
      final ProfileCache c = (await repo.load())!;
      expect(c.yearsOld, 8);
      expect(c.ageLocked, isTrue);
      expect(c.displayName, 'Ivy');
      expect(c.hasOnboarded, isTrue);
      expect(c.overrides, isNotNull);
    });

    test('it survives a restart and the other writers keep it (markOnboarded, resolveHasOnboarded)', () async {
      final ProfileCacheRepository a = ProfileCacheRepository(boot(child: 'ivy').area('profile'));
      await a.lockAge(8);
      final ProfileCacheRepository b = ProfileCacheRepository(boot(child: 'ivy').area('profile'));
      expect((await b.load())!.ageLocked, isTrue);
      await b.markOnboarded();
      expect((await b.load())!.ageLocked, isTrue);
      await resolveHasOnboarded(fetch: () async => true, cache: b);
      expect((await b.load())!.ageLocked, isTrue);
      expect((await b.load())!.yearsOld, 8);
    });

    test('what the server last said about her age does NOT overwrite a locked age; it does overwrite an unlocked one',
        () async {
      final ProfileCacheRepository locked = ProfileCacheRepository(boot(child: 'ivy').area('profile'));
      await locked.lockAge(8);
      await locked.rememberHome(yearsOld: 12);
      expect((await locked.load())!.yearsOld, 8);

      final ProfileCacheRepository free = ProfileCacheRepository(boot(child: 'wren').area('profile'));
      await free.rememberHome(yearsOld: 10);
      await free.rememberHome(yearsOld: 11);
      expect((await free.load())!.yearsOld, 11);
      expect((await free.load())!.ageLocked, isFalse);
    });

    test('a lock with no age is not a lock', () async {
      final LocalServices s = boot(child: 'ivy');
      await s.area('profile').put('cache', <String, Object?>{'hasOnboarded': true, 'ageLocked': true});
      expect((await ProfileCacheRepository(s.area('profile')).load())!.ageLocked, isFalse);
    });
  });

  group('carryOverFirstRun: what she decided before connecting stays hers', () {
    Future<void> setUpDraft(OnboardingDraftRepository d, {bool locked = true, bool complete = true}) =>
        d.save(OnboardingDraft(age: 7, ageLocked: locked, complete: complete));

    test('a finished draft with a locked age locks it in her profile', () async {
      final LocalServices s = boot();
      final ProfileCacheRepository profile = ProfileCacheRepository(s.area('profile', ownerId: 'child-1'));
      final LocalOnboardingDraftRepository draft = LocalOnboardingDraftRepository(s.area('onboarding', ownerId: kPendingDeviceScope));
      await setUpDraft(draft);
      await carryOverFirstRun(
        childId: 'child-1', profile: profile, draftRepo: draft,
        pendingNicknames: MemoryNicknameRepository(), hersNicknames: MemoryNicknameRepository());
      final ProfileCache c = (await profile.load())!;
      expect(c.yearsOld, 7);
      expect(c.ageLocked, isTrue);
    });

    test('an unlocked age, an unfinished draft and no draft lock nothing', () async {
      final LocalServices s = boot();
      final ProfileCacheRepository profile = ProfileCacheRepository(s.area('profile', ownerId: 'child-1'));
      final MemoryOnboardingDraftRepository draft = MemoryOnboardingDraftRepository();
      Future<void> run() => carryOverFirstRun(
          childId: 'child-1', profile: profile, draftRepo: draft,
          pendingNicknames: MemoryNicknameRepository(), hersNicknames: MemoryNicknameRepository());
      await run();
      expect(await profile.load(), isNull);
      await setUpDraft(draft, locked: false);
      await run();
      expect(await profile.load(), isNull);
      await setUpDraft(draft, complete: false);
      await run();
      expect(await profile.load(), isNull);
    });

    test('the names she gave move to her connected profile, hers win, and the pending store is emptied', () async {
      final MemoryNicknameRepository pending = MemoryNicknameRepository();
      final MemoryNicknameRepository hers = MemoryNicknameRepository();
      await pending.set(kLocalGuardianContactId, 'Dada');
      await hers.set('placeholder-1', 'Pop');
      await pending.set('placeholder-1', 'Mama');
      await carryOverFirstRun(
        childId: 'child-1', profile: ProfileCacheRepository(boot().area('profile', ownerId: 'child-1')),
        draftRepo: MemoryOnboardingDraftRepository(), pendingNicknames: pending, hersNicknames: hers);
      expect(await hers.load(), <String, String>{'placeholder-1': 'Pop', kLocalGuardianContactId: 'Dada'});
      expect(await pending.load(), isEmpty);
    });

    test('an unreadable draft never throws and never stops the boot', () async {
      final LocalServices s = boot();
      await carryOverFirstRun(
        childId: 'child-1', profile: ProfileCacheRepository(s.area('profile', ownerId: 'child-1')),
        draftRepo: _BrokenDraft(), pendingNicknames: MemoryNicknameRepository(), hersNicknames: MemoryNicknameRepository());
    });

    test('the pending-device scope itself is never a connected child: nothing is moved', () async {
      final MemoryNicknameRepository pending = MemoryNicknameRepository();
      await pending.set('placeholder-1', 'Mama');
      await carryOverFirstRun(
        childId: kPendingDeviceScope, profile: ProfileCacheRepository(boot().area('profile', ownerId: kPendingDeviceScope)),
        draftRepo: MemoryOnboardingDraftRepository(), pendingNicknames: pending, hersNicknames: MemoryNicknameRepository());
      expect(await pending.load(), <String, String>{'placeholder-1': 'Mama'});
    });
  });
}
