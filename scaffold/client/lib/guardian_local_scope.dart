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
import 'device_role.dart';
import 'local_family.dart';
import 'local_pin.dart';
import 'local_services.dart';

class GuardianLocalServices {
  GuardianLocalServices({required this.roles, required this.families, required this.pin,
      AppLockPrefsRepository? lockPrefs})
      : lockPrefs = lockPrefs ?? MemoryAppLockPrefsRepository();

  final DeviceRoleRepository roles;
  final LocalFamilyRepository families;
  final LocalPinService pin;

  /// The adult-safety settings (app lock, recents, quick hide), kept beside the PIN.
  final AppLockPrefsRepository lockPrefs;

  /// One controller per run, shared by the guard above the Navigator and the settings screen.
  late final AppLockController appLock = AppLockController(pin: pin, repo: lockPrefs);

  /// Over the real (or in-memory) [LocalServices]. [pinIterations] is for tests.
  factory GuardianLocalServices.from(LocalServices s, {int? pinIterations}) => GuardianLocalServices(
        roles: LocalDeviceRoleRepository(s.area('role')),
        families: LocalStoreLocalFamilyRepository(s.area('localfamily', ownerId: kLocalGuardianScope)),
        pin: LocalPinService(
          LocalStoreLocalPinRepository(s.area('localpin', ownerId: kLocalGuardianScope)),
          iterations: pinIterations ?? kLocalPinIterations,
        ),
        lockPrefs: LocalStoreAppLockPrefsRepository.over(s),
      );

  /// Everything in memory, for tests and the preview.
  factory GuardianLocalServices.memory({int pinIterations = 1000, LocalFamily? family, DeviceRole? role}) =>
      GuardianLocalServices(
        roles: MemoryDeviceRoleRepository(role),
        families: MemoryLocalFamilyRepository(family),
        pin: LocalPinService(MemoryLocalPinRepository(), iterations: pinIterations),
      );
}

/// Holds the loaded local family (so a changed age shows everywhere at once) and the
/// optional "connect this device" action.
class GuardianLocalController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  GuardianLocalController(this.services, {LocalFamily? family, this.onConnect}) : _family = family;

  final GuardianLocalServices services;

  /// Opens the connect step. Null when this device is already connected, or when the
  /// build has no server to connect to.
  final void Function(BuildContext context)? onConnect;

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
