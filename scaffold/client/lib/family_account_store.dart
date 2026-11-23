// OLIVE BRANCH — what the phone remembers about the optional family account, so a half-finished setup can be
// picked up again. Verified headless (client/test/family_account_store_test.dart). MASTERFILE sections 8.5.13 and
// 8.16.4.
//
// Two small pieces, kept apart on purpose:
//
//   * [AccountRecord], in the device-scoped catalogue area `account` (device.account): which step was reached and
//     the id of the child that was added to the account. NOT secret and NOT personal: no name, no PIN, no code.
//     It lets the connected shell open on the right child without asking the server first, and lets this
//     screen say "pick up where you left off" with no signal.
//   * [PendingJoin], in the phone's secure storage beside the device identity: the invite a grown-up opened on
//     this phone and has not finished joining. The invite code is a bearer secret until the person is in, so it
//     does not go in the ordinary store. It is deleted the moment the join is confirmed, turned away or
//     abandoned.
//
// A sign-in key (the device credential) is NOT here: it lives only in [DeviceIdentityStore]. A PIN is never
// stored by this app on this path at all.
import 'dart:convert';

import 'device_identity.dart';
import 'family_account_logic.dart' show isServerId;
import 'local_services.dart' show LocalServices;
import 'local_store.dart';

/// How far the account setup got. Words, not numbers.
enum AccountStage { signedUp, childAdded }

class AccountRecord {
  const AccountRecord({required this.stage, this.childId, required this.at});

  final AccountStage stage;

  /// The server id of the child added to the account. Null before one is added.
  final String? childId;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
        'stage': stage.name,
        'childId': childId,
        'at': at.toUtc().toIso8601String(),
      };

  /// Reads a stored record, refusing a damaged one (unknown stage, an id that is not a server id, no time).
  static AccountRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final Object? stage = raw['stage'];
    final AccountStage? s = AccountStage.values.where((AccountStage v) => v.name == stage).firstOrNull;
    if (s == null) return null;
    final Object? child = raw['childId'];
    if (child != null && (child is! String || !isServerId(child))) return null;
    final Object? at = raw['at'];
    final DateTime? when = at is String ? DateTime.tryParse(at) : null;
    if (when == null) return null;
    return AccountRecord(stage: s, childId: child as String?, at: when);
  }
}

abstract class AccountRecordStore {
  Future<AccountRecord?> load();
  Future<void> save(AccountRecord record);
  Future<void> clear();
}

class MemoryAccountRecordStore implements AccountRecordStore {
  AccountRecord? _r;
  @override
  Future<AccountRecord?> load() async => _r;
  @override
  Future<void> save(AccountRecord record) async => _r = record;
  @override
  Future<void> clear() async => _r = null;
}

/// The durable one: the `account` area of the on-device store (see localDataCatalogue).
class LocalAccountRecordStore implements AccountRecordStore {
  LocalAccountRecordStore(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'record';

  @override
  Future<AccountRecord?> load() async => AccountRecord.tryParse(await _ns.get(_key));

  @override
  Future<void> save(AccountRecord record) => _ns.put(_key, record.toJson());

  @override
  Future<void> clear() => _ns.delete(_key);
}

/// Where joining by invite had got to on this phone.
enum JoinStage {
  /// The invite was accepted on the server; the account is not made yet.
  accepted,

  /// An account was made from it and this phone is signed in. Waiting for the inviter's yes.
  waiting,
}

class PendingJoin {
  const PendingJoin({required this.inviteId, required this.stage});
  final String inviteId;
  final JoinStage stage;
}

abstract class PendingJoinStore {
  Future<PendingJoin?> load();
  Future<void> save(PendingJoin join);
  Future<void> clear();
}

class MemoryPendingJoinStore implements PendingJoinStore {
  PendingJoin? _j;
  @override
  Future<PendingJoin?> load() async => _j;
  @override
  Future<void> save(PendingJoin join) async => _j = join;
  @override
  Future<void> clear() async => _j = null;
}

/// In the phone's secure storage (Keystore), beside the device identity.
class SecurePendingJoinStore implements PendingJoinStore {
  SecurePendingJoinStore({SecureKeyValueStore? storage}) : _s = storage ?? const FlutterSecureKeyValueStore();
  final SecureKeyValueStore _s;
  static const String _kInvite = 'olive_pending_join_invite';
  static const String _kStage = 'olive_pending_join_stage';

  @override
  Future<PendingJoin?> load() async {
    final String? id = await _s.read(_kInvite);
    final String? stage = await _s.read(_kStage);
    if (id == null || stage == null || !isServerId(id)) return null;
    final JoinStage? st = JoinStage.values.where((JoinStage v) => v.name == stage).firstOrNull;
    return st == null ? null : PendingJoin(inviteId: id, stage: st);
  }

  @override
  Future<void> save(PendingJoin join) async {
    await _s.write(_kInvite, join.inviteId);
    await _s.write(_kStage, join.stage.name);
  }

  @override
  Future<void> clear() async {
    await _s.delete(_kInvite);
    await _s.delete(_kStage);
  }
}

/// The durable record store on this phone's on-device storage (the catalogue area `account`).
AccountRecordStore accountRecordStoreFor(LocalServices services) =>
    LocalAccountRecordStore(services.area('account'));

/// Which child the connected shell opens on. A build provisioned with a child id (a development build) keeps
/// it; otherwise the child recorded when this phone's account added one; otherwise [fallback]. Never throws.
Future<String> resolveLiveChildId({
  required String fallback,
  required bool buildNamesChild,
  required AccountRecordStore record,
}) async {
  if (buildNamesChild) return fallback;
  try {
    final String? id = (await record.load())?.childId;
    if (id != null && isServerId(id)) return id;
  } catch (_) {
    // A damaged store must never stop the shell opening.
  }
  return fallback;
}

/// Compact, ASCII-safe form of an [AccountRecord] for logs and tests. Never includes an id.
String describeRecord(AccountRecord? r) =>
    r == null ? 'none' : jsonEncode(<String, Object?>{'stage': r.stage.name, 'hasChild': r.childId != null});
