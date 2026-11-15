// OLIVE BRANCH — the family account against a REAL running Olive server. MASTERFILE section 8.5.13.
//
// Skipped unless a server is named, so CI and a plain `flutter test` never need one:
//
//   OLIVE_LIVE_SERVER=http://127.0.0.1:8123 OLIVE_LIVE_ALLOWANCES=<code1>,<code2> flutter test test/family_account_live_server_test.dart
//
// The two codes are single-use sign-up allowances minted for a throwaway server with
// `node tools/provision-signup.mjs issue` (scaffold/docs, OPERATIONS-RUNBOOK). They are read from the environment and
// never written anywhere. The test runs the whole chain once, over real HTTP, with two phones: the first grown-up
// makes an account, adds a child and invites the second; the second makes an account from the invite and asks to
// join; the first says yes with the PIN; the second sees the child.
//
// This is the proof that the in-memory server the other tests use answers like the real one. Run it after any change
// to the identity routes or to api_client.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/family_account_service.dart';
import 'package:olive_client/family_account_store.dart';

class _Mem implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

class _Phone {
  _Phone(String base)
      : record = MemoryAccountRecordStore(),
        pending = MemoryPendingJoinStore(),
        identities = DeviceIdentityStore(storage: _Mem()) {
    service = FamilyAccountService(
        baseUrl: base, identityStore: identities, record: record, pending: pending);
  }
  final MemoryAccountRecordStore record;
  final MemoryPendingJoinStore pending;
  final DeviceIdentityStore identities;
  late final FamilyAccountService service;
  AuthSession? session;

  Future<T> act<T>(Future<T> Function(FamilyAccountService s) f) async {
    AuthSession.use(session);
    try {
      return await f(service);
    } finally {
      session = AuthSession.current ?? session;
    }
  }
}

void main() {
  final String? base = Platform.environment['OLIVE_LIVE_SERVER'];
  final List<String> codes = (Platform.environment['OLIVE_LIVE_ALLOWANCES'] ?? '')
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
  final bool ready = base != null && base.isNotEmpty && codes.length >= 2;

  test('the whole chain over real HTTP: account, child, invite, join, the inviter\'s yes', () async {
    final _Phone sam = _Phone(base!);
    final _Phone robin = _Phone(base);
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final String robinEmail = 'robin-$stamp@example.com';

    await sam.act((FamilyAccountService s) =>
        s.signUp(allowanceCode: codes[0], displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
    expect(await sam.identities.load(), isNotNull);

    final AccountChild kid = await sam.act((FamilyAccountService s) => s.addChild(
        displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
    expect(isServerId(kid.id), isTrue);

    // A wrong PIN is refused by the real server and worded.
    try {
      await sam.act((FamilyAccountService s) => s.createInvite(
          childId: kid.id, role: 'guardian', label: 'Mama', email: robinEmail, pin: '9999'));
      fail('a wrong PIN must be refused');
    } on AccountFailure catch (e) {
      expect(e.problem.message, "That PIN isn't right.");
    }

    final CreatedInvite inv = await sam.act((FamilyAccountService s) => s.createInvite(
        childId: kid.id, role: 'guardian', label: 'Mama', email: robinEmail, pin: '4821'));

    final InviteLookup seen = await robin.act((FamilyAccountService s) => s.lookUpInvite(inv.code));
    expect(seen.alreadyOpened, isFalse);
    await robin.act((FamilyAccountService s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Robin'));
    expect((await robin.act((FamilyAccountService s) => s.snapshot())).children, isEmpty,
        reason: 'no access until the inviter says yes');
    expect(await robin.act((FamilyAccountService s) => s.checkJoin()), JoinStatus.waiting);

    final AccountSnapshot ss = await sam.act((FamilyAccountService s) => s.snapshot());
    expect(ss.waitingForYou.single.claimantName, 'Robin');

    await sam.act((FamilyAccountService s) => s.confirmInvite(inv.code, '4821'));
    expect(await robin.act((FamilyAccountService s) => s.checkJoin()), JoinStatus.confirmed);
    final AccountSnapshot rs = await robin.act((FamilyAccountService s) => s.snapshot());
    expect(rs.children.single.id, kid.id);
    expect(rs.children.single.role, 'guardian');

    // Robin's account starts with no PIN; setting one works on the real server.
    expect(rs.hasPin, isFalse);
    await robin.act((FamilyAccountService s) => s.setFirstPin('7391'));
    expect((await robin.act((FamilyAccountService s) => s.snapshot())).hasPin, isTrue);

    // Sign-in check and sign-out over HTTP.
    expect(await sam.act((FamilyAccountService s) => s.checkSignIn()), isTrue);
    expect(await sam.act((FamilyAccountService s) => s.signOut()), isTrue);
    expect(await sam.identities.load(), isNull);
  }, skip: ready ? false : 'set OLIVE_LIVE_SERVER and two OLIVE_LIVE_ALLOWANCES to run against a real server');
}
