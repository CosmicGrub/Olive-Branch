// OLIVE BRANCH — family_account_store.dart: what the phone remembers about the optional account. MASTERFILE sections
// 8.5.13 and 8.16.4.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/family_account_store.dart';
import 'package:olive_client/local_services.dart';

const String _id = '3f2a9c1e-4b7d-4c1a-9e3f-0a1b2c3d4e5f';

class _Mem implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

class _Broken implements AccountRecordStore {
  @override
  Future<AccountRecord?> load() async => throw StateError('store is damaged');
  @override
  Future<void> save(AccountRecord record) async => throw StateError('store is damaged');
  @override
  Future<void> clear() async => throw StateError('store is damaged');
}

void main() {
  group('the account record (device.account)', () {
    test('is catalogued, sealed, small, and holds no name and no secret', () {
      final LocalDataEntry e = localDataEntry('account');
      expect(e.scope, LocalScope.device);
      expect(e.encrypted, isTrue);
      expect(e.maxBytes, lessThanOrEqualTo(8 * 1024));
      expect(e.what, contains('Never a PIN'));
    });

    test('round-trips through the real on-device store and survives a "restart"', () async {
      final LocalServices a = LocalServices.memory();
      final AccountRecordStore store = accountRecordStoreFor(a);
      expect(await store.load(), isNull);
      await store.save(AccountRecord(stage: AccountStage.childAdded, childId: _id, at: DateTime.utc(2026, 11, 15)));
      final AccountRecord? r = await accountRecordStoreFor(a).load();
      expect(r!.stage, AccountStage.childAdded);
      expect(r.childId, _id);
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('holds an id and a stage, nothing a person typed', () async {
      final LocalServices a = LocalServices.memory();
      await accountRecordStoreFor(a)
          .save(AccountRecord(stage: AccountStage.signedUp, at: DateTime.utc(2026, 11, 15)));
      final Object? raw = await a.area('account').get('record');
      expect((raw! as Map<String, Object?>).keys.toSet(), <String>{'stage', 'childId', 'at'});
    });

    test('a damaged or forged record is treated as no record', () {
      expect(AccountRecord.tryParse(null), isNull);
      expect(AccountRecord.tryParse('x'), isNull);
      expect(AccountRecord.tryParse(<String, Object?>{'stage': 'root', 'at': '2026-11-15T00:00:00Z'}), isNull);
      expect(AccountRecord.tryParse(<String, Object?>{'stage': 'signedUp', 'at': 'yesterday'}), isNull);
      expect(AccountRecord.tryParse(<String, Object?>{'stage': 'signedUp', 'at': '2026-11-15T00:00:00Z', 'childId': '../x'}), isNull);
      expect(AccountRecord.tryParse(<String, Object?>{'stage': 'signedUp', 'at': '2026-11-15T00:00:00Z', 'childId': 7}), isNull);
      expect(AccountRecord.tryParse(<String, Object?>{'stage': 'signedUp', 'at': '2026-11-15T00:00:00Z'}), isNotNull);
    });

    test('a device wipe removes it with the rest of the on-device data', () async {
      final LocalServices a = LocalServices.memory();
      await accountRecordStoreFor(a).save(AccountRecord(stage: AccountStage.signedUp, at: DateTime.utc(2026, 11, 15)));
      await a.wipeAll();
      expect(await accountRecordStoreFor(a).load(), isNull);
    });
  });

  group('an invite opened here and not finished (secure storage)', () {
    test('is kept in the secure store, under its own keys, and cleared with one call', () async {
      final _Mem m = _Mem();
      final SecurePendingJoinStore s = SecurePendingJoinStore(storage: m);
      expect(await s.load(), isNull);
      await s.save(const PendingJoin(inviteId: _id, stage: JoinStage.waiting));
      expect(m.data.keys, everyElement(startsWith('olive_pending_join_')));
      final PendingJoin? p = await SecurePendingJoinStore(storage: m).load();
      expect(p!.inviteId, _id);
      expect(p.stage, JoinStage.waiting);
      await s.clear();
      expect(m.data, isEmpty);
      expect(await s.load(), isNull);
    });

    test('a half-written or tampered entry is "nothing pending"', () async {
      final _Mem m = _Mem();
      final SecurePendingJoinStore s = SecurePendingJoinStore(storage: m);
      m.data['olive_pending_join_invite'] = _id;
      expect(await s.load(), isNull, reason: 'no stage');
      m.data['olive_pending_join_stage'] = 'root';
      expect(await s.load(), isNull, reason: 'unknown stage');
      m.data['olive_pending_join_stage'] = 'waiting';
      m.data['olive_pending_join_invite'] = '../../me';
      expect(await s.load(), isNull, reason: 'not an id');
    });

    test('the sign-in key is never in this store', () async {
      final _Mem m = _Mem();
      await SecurePendingJoinStore(storage: m).save(const PendingJoin(inviteId: _id, stage: JoinStage.accepted));
      expect(m.data.keys.where((String k) => k.contains('credential') || k.contains('token') || k.contains('pin')), isEmpty);
    });
  });

  group('which child the connected shell opens on', () {
    const String fallback = 'aaaaaaaa-0000-4000-8000-000000000001';
    test('a build that names a child keeps it', () async {
      final AccountRecordStore s = MemoryAccountRecordStore();
      await s.save(AccountRecord(stage: AccountStage.childAdded, childId: _id, at: DateTime.utc(2026)));
      expect(await resolveLiveChildId(fallback: fallback, buildNamesChild: true, record: s), fallback);
    });

    test('otherwise the child added to this phone\'s account', () async {
      final AccountRecordStore s = MemoryAccountRecordStore();
      await s.save(AccountRecord(stage: AccountStage.childAdded, childId: _id, at: DateTime.utc(2026)));
      expect(await resolveLiveChildId(fallback: fallback, buildNamesChild: false, record: s), _id);
    });

    test('with no account, the default; a damaged store never stops the shell opening', () async {
      expect(await resolveLiveChildId(fallback: fallback, buildNamesChild: false, record: MemoryAccountRecordStore()), fallback);
      expect(await resolveLiveChildId(fallback: fallback, buildNamesChild: false, record: _Broken()), fallback);
    });
  });

  group('forgetting the account on this phone', () {
    test('clears the recorded child and any invite being joined, and the shell then opens on the default', () async {
      const String fallback = 'aaaaaaaa-0000-4000-8000-000000000001';
      final AccountRecordStore rec = MemoryAccountRecordStore();
      final PendingJoinStore pend = MemoryPendingJoinStore();
      await rec.save(AccountRecord(stage: AccountStage.childAdded, childId: _id, at: DateTime.utc(2026)));
      await pend.save(const PendingJoin(inviteId: _id, stage: JoinStage.waiting));
      await forgetAccountOnThisPhone(record: rec, pending: pend);
      expect(await rec.load(), isNull);
      expect(await pend.load(), isNull);
      expect(await resolveLiveChildId(fallback: fallback, buildNamesChild: false, record: rec), fallback);
    });

    test('a store that cannot be cleared never stops it, and the other one is still cleared', () async {
      final PendingJoinStore pend = MemoryPendingJoinStore();
      await pend.save(const PendingJoin(inviteId: _id, stage: JoinStage.accepted));
      await forgetAccountOnThisPhone(record: _Broken(), pending: pend);
      expect(await pend.load(), isNull);
    });
  });

  test('describing a record never includes an id', () {
    final AccountRecord r = AccountRecord(stage: AccountStage.childAdded, childId: _id, at: DateTime.utc(2026));
    expect(describeRecord(r), isNot(contains(_id)));
    expect(describeRecord(null), 'none');
  });
}
