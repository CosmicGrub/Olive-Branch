// OLIVE BRANCH — device_role.dart tests: the role is one word per device, kept in the
// device-scoped `role` area, and survives a restart. No longer UNVERIFIED — verified by
// CI. MASTERFILE §8.5.8.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/device_role.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

void main() {
  group('the four roles', () {
    test('Kid opens the child shell; Mom, Dad and Someone else open the guardian shell', () {
      expect(DeviceRole.kid.isGuardian, isFalse);
      expect(DeviceRole.mom.isGuardian, isTrue);
      expect(DeviceRole.dad.isGuardian, isTrue);
      expect(DeviceRole.other.isGuardian, isTrue);
      expect(DeviceRole.values.length, 4);
    });

    test('only a Mom and a Dad carry the age-default words; someone else does not', () {
      expect(DeviceRole.mom.kind, GrownupKind.mom);
      expect(DeviceRole.dad.kind, GrownupKind.dad);
      expect(DeviceRole.other.kind, GrownupKind.other);
      expect(DeviceRole.kid.kind, GrownupKind.other);
    });

    test('the label offered first: Mom, Dad, and nothing for someone else (they choose their own word)', () {
      expect(DeviceRole.mom.defaultLabel, 'Mom');
      expect(DeviceRole.dad.defaultLabel, 'Dad');
      expect(DeviceRole.other.defaultLabel, '');
    });

    test('the words on the picker', () {
      expect(DeviceRole.values.map((DeviceRole r) => r.title).toList(),
          <String>['Kid', 'Mom', 'Dad', 'Someone else']);
    });

    test('the stored word round-trips, and anything else is "no role" (fail closed)', () {
      for (final DeviceRole r in DeviceRole.values) {
        expect(deviceRoleFromWire(r.wire), r);
      }
      expect(deviceRoleFromWire('admin'), isNull);
      expect(deviceRoleFromWire('Kid'), isNull, reason: 'the stored word is lower case');
      expect(deviceRoleFromWire(3), isNull);
      expect(deviceRoleFromWire(null), isNull);
      expect(deviceRoleFromWire(<String, Object?>{'role': 'mom'}), isNull);
    });
  });

  group('the repository', () {
    test('memory: save, load, clear', () async {
      final MemoryDeviceRoleRepository repo = MemoryDeviceRoleRepository();
      expect(await repo.load(), isNull);
      await repo.save(DeviceRole.dad);
      expect(await repo.load(), DeviceRole.dad);
      await repo.clear();
      expect(await repo.load(), isNull);
    });

    test('the role is persisted per DEVICE in the catalogued `device.role` namespace, and survives a restart',
        () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices first = LocalServices.memory(childId: 'pending-device', isLive: true, demoSeeds: false, backend: backend);
      final LocalNamespace ns = first.area('role');
      expect(ns.spec.name, 'device.role');
      expect(ns.spec.encrypted, isFalse);
      await LocalDeviceRoleRepository(ns).save(DeviceRole.mom);
      expect(await backend.names(), contains('device.role'));

      // The "restart": a brand-new LocalServices over the same files, with a DIFFERENT child scope.
      final LocalServices second = LocalServices.memory(childId: 'another-child', isLive: true, demoSeeds: false, backend: backend);
      expect(await LocalDeviceRoleRepository(second.area('role')).load(), DeviceRole.mom,
          reason: 'a device-scoped area does not depend on whose profile is open');
    });

    test('a damaged stored value reads as no role rather than throwing, so she is asked again', () async {
      final LocalServices s = LocalServices.memory(childId: 'x');
      await s.area('role').put('role', 'banana');
      expect(await LocalDeviceRoleRepository(s.area('role')).load(), isNull);
      await s.area('role').put('role', 42);
      expect(await LocalDeviceRoleRepository(s.area('role')).load(), isNull);
    });

    test('clear removes it (a device wipe has the same effect by deleting the area)', () async {
      final LocalServices s = LocalServices.memory(childId: 'x');
      final LocalDeviceRoleRepository repo = LocalDeviceRoleRepository(s.area('role'));
      await repo.save(DeviceRole.other);
      await repo.clear();
      expect(await repo.load(), isNull);
      await repo.save(DeviceRole.kid);
      await s.wipeAll();
      expect(await LocalDeviceRoleRepository(s.area('role')).load(), isNull);
    });
  });
}
