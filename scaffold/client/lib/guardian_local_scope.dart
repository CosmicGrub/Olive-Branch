// OLIVE BRANCH — what the guardian shell can reach on THIS device: the role, the
// local family, the local PIN and how to connect. No longer UNVERIFIED — verified
// by CI (client/test/guardian_local_scope_test.dart). MASTERFILE §8.5.9.
//
// One small bundle ([GuardianLocalServices]) over the three on-device repositories,
// and an InheritedNotifier ([GuardianLocalScope]) that the guardian app puts above
// its Navigator so the existing screens (the More hub, the settings hub, "Data on
// this device") can ask "is there a local PIN? a local family? a way to connect?"
// without every constructor between the boot and the hub growing three parameters.
// A screen that finds no scope behaves EXACTLY as it did before this existed (that is
// how the preview build and every old test still work).
import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'device_keys.dart';
import 'device_role.dart';
import 'local_family.dart';
import 'local_pin.dart';
import 'local_pin_recovery.dart';
import 'family_hub.dart';
import 'family_state.dart';
import 'family_sync_engine.dart' show LocalStoreSyncRepository;
import 'local_services.dart';
import 'pairing_records.dart' show LocalStorePairedKidsRepository;
import 'screen_share.dart';

class GuardianLocalServices {
  GuardianLocalServices({required this.roles, required this.families, required this.pin, this.recovery,
      AppLockPrefsRepository? lockPrefs, ScreenShareService? shares, this.familyHub})
      : lockPrefs = lockPrefs ?? MemoryAppLockPrefsRepository(),
        shares = shares ?? familyHub?.shares;

  /// Everything about the family's OTHER grown-up phone: the family record, the shared emergency card, the screen shares
  /// and the same-Wi-Fi road they ride (family_hub.dart). Null in a tree built without it: the "Share with another
  /// grown-up" row then never appears and a phone behaves exactly as it did before this existed.
  final FamilyHub? familyHub;

  /// Sharing a screen with another grown-up inside the app (screen_share.dart). Null in a tree built without it: the
  /// "Share this screen" action then never appears.
  final ScreenShareService? shares;

  final DeviceRoleRepository roles;
  final LocalFamilyRepository families;
  final LocalPinService pin;

  /// The adult-safety settings (app lock, recents, quick hide), kept beside the PIN.
  final AppLockPrefsRepository lockPrefs;

  /// One controller per run, shared by the guard above the Navigator and the settings screen.
  late final AppLockController appLock = AppLockController(pin: pin, repo: lockPrefs);
  /// Linking another grown-up's phone and resetting a forgotten PIN from it (local_pin_recovery.dart). Null in a
  /// tree built without it: the forgotten-PIN path then says plainly that clearing the app is the only reset.
  final GuardianRecovery? recovery;

  /// Over the real (or in-memory) [LocalServices]. [pinIterations] is for tests.
  factory GuardianLocalServices.from(LocalServices s, {int? pinIterations}) => GuardianLocalServices(
        roles: LocalDeviceRoleRepository(s.area('role')),
        families: LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)),
        pin: LocalPinService(
          LocalStoreLocalPinRepository(s.area('localpin', ownerId: kLocalGuardianScope)),
          iterations: pinIterations ?? kLocalPinIterations,
        ),
        lockPrefs: LocalStoreAppLockPrefsRepository.over(s),
        familyHub: _familyHub(s),
        recovery: GuardianRecovery(
          peers: LocalStoreGuardianPeerRepository(s.area('localpin', ownerId: kLocalGuardianScope)),
          deviceKey: () => DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(s.area('devicekey'))),
        ),
      );

  /// Everything in memory, for tests and the preview.
  factory GuardianLocalServices.memory({int pinIterations = 1000, LocalFamily? family, DeviceRole? role, FamilyHub? familyHub}) =>
      GuardianLocalServices(
        familyHub: familyHub,
        roles: MemoryDeviceRoleRepository(role),
        families: MemoryLocalFamilyRepository(family),
        pin: LocalPinService(MemoryLocalPinRepository(), iterations: pinIterations),
        recovery: GuardianRecovery(
          peers: MemoryGuardianPeerRepository(),
          deviceKey: () => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository()),
        ),
      );
}

/// The family hub over this phone's sealed records. With no family record, or one without a second grown-up, the screen
/// share service finds nobody to send to and the action stays hidden; a record that cannot be read counts as no family.
FamilyHub _familyHub(LocalServices s) => FamilyHub(
      familyRepo: LocalStoreFamilyRepository(s.area('familyledger', ownerId: kLocalGuardianScope)),
      syncRepo: LocalStoreSyncRepository.forServices(s),
      deviceKey: () => DeviceKey.loadOrCreate(LocalStoreDeviceKeyRepository(s.area('devicekey'))),
      shareBox: LocalStoreShareBoxRepository(s.area('screenshares', ownerId: kLocalGuardianScope)),
      kidsRepo: LocalStorePairedKidsRepository(s.area('pairedkids', ownerId: kLocalGuardianScope)),
    );

/// Holds the loaded local family (so a changed age shows everywhere at once) and the
/// optional "connect this device" action.
class GuardianLocalController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  GuardianLocalController(this.services, {LocalFamily? family, this.onConnect, this.onAccount}) : _family = family;

  final GuardianLocalServices services;

  /// Opens the connect step. Null when this device is already connected, or when the
  /// build has no server to connect to.
  final void Function(BuildContext context)? onConnect;

  /// Opens the optional family account page (make an account, sign in, add a child, invite another grown-up). Null
  /// when the build has no server to reach. A phone with no account is the normal phone: nothing waits on this.
  final void Function(BuildContext context)? onAccount;

  LocalFamily? _family;
  LocalFamily? get family => _family;

  Future<void> reload() async {
    LocalFamily? f;
    try {
      f = await services.families.load();
    } catch (_) {
      f = _family;
    }
    _family = f;
    notifyListeners();
  }

  /// Saves [next] and publishes it. Throws what the store throws: the caller must not
  /// say "changed" when it was not.
  Future<void> saveFamily(LocalFamily next) async {
    await services.families.save(next);
    _family = next;
    notifyListeners();
  }
}

class GuardianLocalScope extends InheritedNotifier<GuardianLocalController> {
  const GuardianLocalScope({super.key, required GuardianLocalController controller, required super.child})
      : super(notifier: controller);

  /// The controller, or null when this tree has no local services (preview, old tests).
  static GuardianLocalController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuardianLocalScope>()?.notifier;
}
