// OLIVE BRANCH — who is using this device: the role every first run starts from.
// No longer UNVERIFIED — verified by CI (client/test/device_role_test.dart).
// MASTERFILE §8.5.8.
//
// Owner requirement, 2026-11-08: "the onboarding has to follow the logic of ROLES:
// it has to ask if you are a kid, a mom, or a dad". Step 0 of a first run on a
// device with no identity and no stored role is that question
// (role_picker_screen.dart); the answer is kept HERE, once per device, and decides
// which onboarding and which shell open (live_boot_plan.dart).
//
// Four roles, not three: Kid, Mom, Dad, and "Someone else" (a grandparent or
// another guardian). The fourth is the coordinator's addition beyond the owner's
// three; it exists so that a grown-up who is neither does not have to pick a role
// that is not true.
//
// A role is a QUESTION, not authority (§8.5.0): picking Mom, Dad or Someone else
// grants nothing on any server. The guardian shell a role opens is the same shell
// a paired guardian gets, and everything server-side is still gated by the
// family-graph authorizer. On the device the role only picks which screens open.
//
// Storage: the device-scoped `role` area of the on-device catalogue
// (local_services.dart) holds ONE word. It is not personal data; a device wipe
// removes it, after which the device asks again.
import 'contact_labels.dart' show GrownupKind;
import 'local_store.dart';

enum DeviceRole { kid, mom, dad, other }

extension DeviceRoleX on DeviceRole {
  /// The stored word.
  String get wire => name;

  /// Kid opens the child shell; the other three open the guardian shell.
  bool get isGuardian => this != DeviceRole.kid;

  /// How a Mom or a Dad is treated by [ContactLabels] (the age-default words).
  GrownupKind get kind => switch (this) {
        DeviceRole.mom => GrownupKind.mom,
        DeviceRole.dad => GrownupKind.dad,
        _ => GrownupKind.other,
      };

  /// The guardian label offered first. Empty for "someone else": a grown-up who is
  /// not a Mom or a Dad chooses their own word (Grandma, Nana, Uncle Sam...).
  String get defaultLabel => switch (this) {
        DeviceRole.mom => 'Mom',
        DeviceRole.dad => 'Dad',
        _ => '',
      };

  /// Plain words for the picker, the screen reader and read-aloud.
  String get title => switch (this) {
        DeviceRole.kid => 'Kid',
        DeviceRole.mom => 'Mom',
        DeviceRole.dad => 'Dad',
        DeviceRole.other => 'Someone else',
      };
}

/// Fail-closed decode: anything that is not one of the four words is "no role".
DeviceRole? deviceRoleFromWire(Object? raw) {
  if (raw is! String) return null;
  for (final DeviceRole r in DeviceRole.values) {
    if (r.wire == raw) return r;
  }
  return null;
}

abstract class DeviceRoleRepository {
  Future<DeviceRole?> load();
  Future<void> save(DeviceRole role);
  Future<void> clear();
}

class MemoryDeviceRoleRepository implements DeviceRoleRepository {
  MemoryDeviceRoleRepository([this._role]);
  DeviceRole? _role;
  @override
  Future<DeviceRole?> load() async => _role;
  @override
  Future<void> save(DeviceRole role) async => _role = role;
  @override
  Future<void> clear() async => _role = null;
}

class LocalDeviceRoleRepository implements DeviceRoleRepository {
  LocalDeviceRoleRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'role';

  @override
  Future<DeviceRole?> load() async => deviceRoleFromWire(await _ns.get(_key));

  @override
  Future<void> save(DeviceRole role) => _ns.put(_key, role.wire);

  @override
  Future<void> clear() => _ns.delete(_key);
}
