// A grown-up's phone for the family-account tests: its own secure storage, record, pending-join and service, wired to a
// FakeIdentityServer. The process-wide session is swapped in by [Phone.act], so two phones can share one test.
import 'dart:io';

import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/family_account_service.dart';
import 'package:olive_client/family_account_store.dart';

import 'fake_identity_server.dart';

const String kBase = 'https://olive.test';
const String kCode = 'allowance-token-0123456789abcdef';

class MemSecure implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw const FileSystemException('disk full');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// One grown-up's phone: its own storage and its own service. The process-wide session is swapped in by [act].
class Phone {
  /// [pendingStore] swaps the invite-being-joined store (to make it fail); [whenSignedOut] runs, synchronously, at the
  /// moment the shell would be restarted.
  Phone(this.server, {PendingJoinStore? pendingStore, void Function()? whenSignedOut})
      : secure = MemSecure(),
        record = MemoryAccountRecordStore(),
        pending = pendingStore ?? MemoryPendingJoinStore() {
    identities = DeviceIdentityStore(storage: secure);
    service = FamilyAccountService(
      baseUrl: kBase,
      client: server.client,
      identityStore: identities,
      record: record,
      pending: pending,
      now: server.now,
      onSignedOut: () {
        signedOutCalls++;
        whenSignedOut?.call();
      },
    );
  }

  final FakeIdentityServer server;
  final MemSecure secure;
  final MemoryAccountRecordStore record;
  final PendingJoinStore pending;
  late final DeviceIdentityStore identities;
  late final FamilyAccountService service;
  AuthSession? session;
  int signedOutCalls = 0;

  /// Makes this phone the one whose session is installed process-wide, then runs [f].
  Future<T> act<T>(Future<T> Function(FamilyAccountService s) f) async {
    AuthSession.use(session);
    try {
      return await f(service);
    } finally {
      session = AuthSession.current ?? session;
    }
  }
}
