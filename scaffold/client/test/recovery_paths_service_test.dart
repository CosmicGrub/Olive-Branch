// OLIVE BRANCH — recovery_paths_service.dart: losing a phone without losing anything, against an in-memory server that
// answers like server/routes.mjs (test/support/recovery_fake.dart) and checks every request against the REAL route table.
// MASTERFILE section 7.22. Covers the two grown-up path, the one grown-up path with and without a helper, and the hostile
// cases: replay of a used code, a code after a stop, wrong guesses, a helper that reaches past its one power, a phone that
// is already signed in, a lost reply, a double tap.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/recovery_paths_logic.dart';
import 'package:olive_client/recovery_paths_service.dart';

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';
import 'support/recovery_fake.dart';

void main() {
  late DateTime clock;
  late FakeIdentityServer server;
  late RecoveryFake rf;

  setUp(() {
    clock = DateTime.utc(2026, 11, 21, 12);
    server = FakeIdentityServer(now: () => clock);
    rf = RecoveryFake(server);
    AuthSession.use(null);
  });
  tearDown(() => AuthSession.use(null));

  int n = 0;
  Future<Phone> signedUp(String name, {String pin = '4821'}) async {
    final Phone p = Phone(server);
    final String code = 'allowance-token-0123456789abcdef-${n++}';
    server.addAllowance(code);
    await p.act((s) => s.signUp(allowanceCode: code, displayName: name, homeTz: 'America/Chicago', pin: pin));
    return p;
  }

  Future<String> userIdOf(Phone p) async => (await p.identities.load())!.targetId;

  RecoveryPathsService svc(Phone p, {MemoryPendingRecoveryStore? pending, MemoryHelperKeyStore? helper}) =>
      RecoveryPathsService(
          baseUrl: kBase,
          account: p.service,
          client: server.client,
          pending: pending ?? MemoryPendingRecoveryStore(),
          helper: helper ?? MemoryHelperKeyStore(),
          now: server.now);

  Future<AccountFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on AccountFailure catch (e) {
      return e;
    }
    fail('expected an AccountFailure');
  }

  Future<({Phone phone, String id, Phone mom})> family2() async {
    final Phone mom = await signedUp('Mom');
    final Phone dad = await signedUp('Dad', pin: '2468');
    final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
    rf.makeParents(momId, dadId);
    rf.usersWithLivePhone.addAll(<String>{momId, dadId});
    return (phone: dad, id: momId, mom: mom);
  }

  group('the printed sheet', () {
    test('made with the PIN, shown in six groups of four, never kept by the phone', () async {
      final Phone sam = await signedUp('Sam');
      final RecoveryPathsService s = svc(sam);
      server.requests.clear();
      final String key = await sam.act((_) => s.makeSheet(pin: '4821'));
      expect(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){5}[0-9A-HJKMNP-TV-Z]{4}$').hasMatch(key), isTrue);
      final RecordedRequest r = server.requests.single;
      expect(r.path, '/v1/me/recovery-sheet');
      expect(r.hasAuth, isTrue);
      expect(r.body.keys.toSet(), <String>{'pin'});
      final String raw = key.replaceAll('-', '');
      expect(sam.secure.data.values.any((String v) => v.contains(raw) || v.contains(key)), isFalse,
          reason: 'the key must not be written to the phone');
      expect(await s.pending(), isNull);
    });

    test('a wrong PIN makes no sheet and the sentence is plain', () async {
      final Phone sam = await signedUp('Sam');
      final RecoveryPathsService s = svc(sam);
      final AccountFailure f = await sam.act((_) => failureOf(s.makeSheet(pin: '0000')));
      expect(f.problem.reason, 'pin_incorrect');
      expect(rf.sheets, isEmpty);
      expect(f.problem.message, isNot(contains('pin_incorrect')));
    });

    test('a PIN of the wrong shape never leaves the phone', () async {
      final Phone sam = await signedUp('Sam');
      final RecoveryPathsService s = svc(sam);
      server.requests.clear();
      await sam.act((_) => failureOf(s.makeSheet(pin: '12')));
      expect(server.requests, isEmpty);
    });

    test('typing it back: smudges and capitals are fine, a wrong key says so and confirms nothing', () async {
      final Phone sam = await signedUp('Sam');
      final RecoveryPathsService s = svc(sam);
      final String key = await sam.act((_) => s.makeSheet(pin: '4821'));
      final AccountFailure bad = await sam.act((_) => failureOf(s.checkSheet('AAAA-BBBB-CCCC-DDDD-EEEE-FFFF')));
      expect(bad.problem.reason, 'wrong_key');
      expect((await sam.act((_) => s.summary())).sheet.kept, isFalse);
      final String smudged = key.toLowerCase().replaceAll('-', ' ').replaceAll('0', 'o').replaceAll('1', 'l');
      expect(await sam.act((_) => s.checkSheet(smudged)), isTrue);
      expect((await sam.act((_) => s.summary())).sheet.kept, isTrue);
    });

    test('a double tap on make is one request', () async {
      final Phone sam = await signedUp('Sam');
      final RecoveryPathsService s = svc(sam);
      server.requests.clear();
      final List<String> keys = await sam.act((_) => Future.wait(<Future<String>>[s.makeSheet(pin: '4821'), s.makeSheet(pin: '4821')]));
      expect(keys[0], keys[1]);
      expect(server.requests.where((RecordedRequest r) => r.path == '/v1/me/recovery-sheet'), hasLength(1));
    });
  });

  group('two or more grown-ups: the other grown-up says yes, the family waits, anyone can stop it', () {
    test('the whole way back, to the SAME account', () async {
      final f = await family2();
      final Phone dad = f.phone;
      final String momId = f.id;
      final RecoveryPathsService dadSvc = svc(dad);
      final HelpStarted h = await dad.act((_) => dadSvc.startFor(targetUserId: momId, pin: '2468'));
      expect(h.targetName, 'Mom');
      expect(h.readyAt.difference(clock), const Duration(hours: 48));

      // Mom's new phone: nothing signed in, no code typed yet.
      final Phone momNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(momNew, pending: pend);
      final RecoveryStarted st = await momNew.act((_) => s.useGrownUpCode(h.code.toLowerCase()));
      expect(st.soleParent, isFalse);
      expect((await pend.load())!.code, h.code);
      expect((await momNew.act((_) => s.status()))!.phase, RecoveryPhase.waiting);

      // too early: refused, still waiting, kept
      final AccountFailure early = await momNew.act((_) => failureOf(s.finish(pin: '4821')));
      expect(early.problem.reason, 'too_early');
      expect(await pend.load(), isNotNull);

      clock = clock.add(const Duration(hours: 48, minutes: 1));
      expect((await momNew.act((_) => s.status()))!.phase, RecoveryPhase.ready);

      // a helping grown-up alone cannot take the account: no proof, no request
      server.requests.clear();
      final AccountFailure none = await momNew.act((_) => failureOf(s.finish()));
      expect(none.problem.reason, 'proof_required');
      expect(server.requests, isEmpty);
      // another grown-up's PIN is a wrong guess, not a way in
      final AccountFailure wrong = await momNew.act((_) => failureOf(s.finish(pin: '2468')));
      expect(wrong.problem.reason, 'wrong_proof');

      final RecoveredResult r = await momNew.act((_) => s.finish(pin: '4821'));
      expect(r.devicesSignedOut, 1);
      final DeviceIdentity id = (await momNew.identities.load())!;
      expect(id.targetId, momId, reason: 'the SAME account');
      expect(await pend.load(), isNull);
      expect(AuthSession.current, isNotNull);

      // replay of the used code, from a phone that is not signed in (a signed-in phone is refused before it asks)
      final Phone stranger = Phone(server);
      final AccountFailure replay = await stranger.act((_) => failureOf(svc(stranger).useGrownUpCode(h.code)));
      expect(replay.problem.reason, 'invalid_recovery');
    });

    test('a wrong PIN at the start makes nothing; a stranger\'s family cannot start one', () async {
      final f = await family2();
      final Phone eve = await signedUp('Eve', pin: '1357');
      final RecoveryPathsService e = svc(eve), d = svc(f.phone);
      final AccountFailure wrongPin = await f.phone.act((_) => failureOf(d.startFor(targetUserId: f.id, pin: '9999')));
      expect(wrongPin.problem.reason, 'pin_incorrect');
      final AccountFailure wrongFamily = await eve.act((_) => failureOf(e.startFor(targetUserId: f.id, pin: '1357')));
      expect(wrongFamily.problem.reason, 'not_family');
      expect(rf.reqs, isEmpty);
    });

    test('the owner\'s other phone stops it, and the new phone is told it was stopped', () async {
      final f = await family2();
      final HelpStarted h = await f.phone.act((_) => svc(f.phone).startFor(targetUserId: f.id, pin: '2468'));
      final Phone momNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(momNew, pending: pend);
      await momNew.act((_) => s.useGrownUpCode(h.code));
      // Mom's old phone still works: it is told, and it can stop this with her own PIN.
      final Phone momOld = f.mom;
      final RecoveryPathsService m = svc(momOld);
      final RecoverySummary told = await momOld.act((_) => m.summary());
      expect(told.open, hasLength(1));
      expect(told.open.single.aboutMe, isTrue);
      expect(told.open.single.startedByName, 'Dad');
      final AccountFailure wrong = await momOld.act((_) => failureOf(m.stop(requestId: h.requestId, pin: '0000')));
      expect(wrong.problem.reason, 'pin_incorrect');
      await momOld.act((_) => m.stop(requestId: h.requestId, pin: '4821'));
      final RecoveryStatus? st = await momNew.act((_) => s.status());
      expect(st!.phase, RecoveryPhase.stopped);
      expect(st.stoppedBy, 'owner_phone');
      clock = clock.add(const Duration(hours: 49));
      final AccountFailure f2 = await momNew.act((_) => failureOf(s.finish(pin: '4821')));
      expect(f2.problem.reason, 'invalid_recovery');
      expect(await pend.load(), isNull, reason: 'a recovery that is over is forgotten');
    });

    test('five wrong guesses end that recovery, and nothing else', () async {
      final f = await family2();
      final HelpStarted h = await f.phone.act((_) => svc(f.phone).startFor(targetUserId: f.id, pin: '2468'));
      final Phone momNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(momNew, pending: pend);
      await momNew.act((_) => s.useGrownUpCode(h.code));
      clock = clock.add(const Duration(hours: 49));
      final List<String> reasons = <String>[];
      for (int i = 0; i < 5; i++) {
        reasons.add((await momNew.act((_) => failureOf(s.finish(pin: '000$i')))).problem.reason);
      }
      expect(reasons, <String>['wrong_proof', 'wrong_proof', 'wrong_proof', 'wrong_proof', 'too_many_wrong']);
      expect(await pend.load(), isNull);
      expect(server.users[f.id]!.pinFailures, 0, reason: 'the real owner is never locked out of their own phone');
    });

    test('the new phone can give up', () async {
      final f = await family2();
      final HelpStarted h = await f.phone.act((_) => svc(f.phone).startFor(targetUserId: f.id, pin: '2468'));
      final Phone momNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(momNew, pending: pend);
      await momNew.act((_) => s.useGrownUpCode(h.code));
      await momNew.act((_) => s.giveUp());
      expect(await pend.load(), isNull);
      expect(rf.reqs[h.requestId]!.cancelledBy, 'new_phone');
    });

    test('a phone that is already signed in and works is turned back before anything is sent', () async {
      final f = await family2();
      final HelpStarted h = await f.phone.act((_) => svc(f.phone).startFor(targetUserId: f.id, pin: '2468'));
      final Phone dad = f.phone;
      server.requests.clear();
      final AccountFailure x = await dad.act((_) => failureOf(svc(dad).useGrownUpCode(h.code)));
      expect(x.problem.reason, 'already_signed_in');
      expect(server.requests.where((RecordedRequest r) => r.path.startsWith('/v1/auth/recovery')), isEmpty);
    });
  });

  group('one grown-up: the printed sheet, the wait, and a helper who can only say yes', () {
    Future<({Phone sam, String samId, String key})> sole() async {
      final Phone sam = await signedUp('Sam');
      final String samId = await userIdOf(sam);
      final String key = await sam.act((_) => svc(sam).makeSheet(pin: '4821'));
      return (sam: sam, samId: samId, key: key);
    }

    test('total loss: the sheet alone starts it, 72 hours, then it finishes with a new PIN, same account', () async {
      final s0 = await sole();
      final Phone samNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(samNew, pending: pend);
      final RecoveryStarted st = await samNew.act((_) => s.startWithSheet(s0.key.toLowerCase().replaceAll('-', '')));
      expect(st.soleParent, isTrue);
      expect(st.helperRequired, isFalse);
      expect(st.readyAt.difference(clock), const Duration(hours: 72));
      expect((await pend.load())!.soleParent, isTrue);
      expect((await samNew.act((_) => failureOf(s.finish()))).problem.reason, 'too_early');
      clock = clock.add(const Duration(hours: 72, minutes: 1));
      final AccountFailure weak = await samNew.act((_) => failureOf(s.finish(newPin: '1234')));
      expect(weak.problem.reason, 'invalid_pin_format', reason: 'an easy-to-guess new PIN is refused on the phone');
      final RecoveredResult r = await samNew.act((_) => s.finish(newPin: '7391'));
      expect(r.sheetSpent, isTrue);
      expect((await samNew.identities.load())!.targetId, s0.samId);
      expect(server.users[s0.samId]!.pin, '7391');
      // replay of the spent sheet
      final Phone again = Phone(server);
      final AccountFailure replay = await again.act((_) => failureOf(svc(again).startWithSheet(s0.key)));
      expect(replay.problem.reason, 'invalid_sheet');
    });

    test('a wrong sheet key starts nothing and keeps nothing', () async {
      await sole();
      final Phone samNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final AccountFailure f = await samNew.act((_) => failureOf(svc(samNew, pending: pend).startWithSheet('AAAA-BBBB-CCCC-DDDD-EEEE-FFFF')));
      expect(f.problem.reason, 'invalid_sheet');
      expect(await pend.load(), isNull);
      final AccountFailure typo = await samNew.act((_) => failureOf(svc(samNew).startWithSheet('too short')));
      expect(typo.problem.reason, 'recovery_key_required');
    });

    test('while another grown-up has a working phone the sheet is not enough: ask them', () async {
      final f = await family2();
      // Mom made a sheet and then lost her phone; Dad still has his.
      final String k = await f.mom.act((_) => svc(f.mom).makeSheet(pin: '4821'));
      final Phone fresh = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final AccountFailure x = await fresh.act((_) => failureOf(svc(fresh, pending: pend).startWithSheet(k)));
      expect(x.problem.reason, 'ask_other_grownup');
      expect(await pend.load(), isNull);
    });

    test('with a helper: the wait is not enough, the helper must say yes, and the helper can do nothing else', () async {
      final s0 = await sole();
      final RecoveryPathsService sam = svc(s0.sam);
      final HelperInvite inv = await s0.sam.act((_) => sam.nameHelper(name: '  Aunt Sam ', pin: '4821'));
      expect(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){3}[0-9A-HJKMNP-TV-Z]{4}$').hasMatch(inv.code), isTrue);
      expect((await s0.sam.act((_) => sam.summary())).helper.phase, HelperPhase.invited);

      // the helper's phone: no account, only a key
      final Phone helperPhone = Phone(server);
      final MemoryHelperKeyStore hk = MemoryHelperKeyStore();
      final RecoveryPathsService h = svc(helperPhone, helper: hk);
      server.requests.clear();
      final HelperKey key = await helperPhone.act((_) => h.acceptHelperInvite(inv.code.toLowerCase()));
      expect(key.accountName, 'Sam');
      expect(key.label, 'Aunt Sam');
      expect(await helperPhone.identities.load(), isNull, reason: 'a helper has no sign-in');
      expect(await helperPhone.act((_) => failureOf(svc(helperPhone).acceptHelperInvite(inv.code))), isA<AccountFailure>(),
          reason: 'the invite works once');

      // Sam, on a new phone, starts with the sheet
      final Phone samNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(samNew, pending: pend);
      final RecoveryStarted st = await samNew.act((_) => s.startWithSheet(s0.key));
      expect(st.helperRequired, isTrue);

      // the helper sees only the first name and the times
      final List<HelperRequest> list = await helperPhone.act((_) => h.helperRequests());
      expect(list, hasLength(1));
      expect(list.single.accountName, 'Sam');
      expect(list.single.confirmed, isFalse);
      // none of the helper's calls carry a session
      expect(server.requests.where((RecordedRequest r) => r.path.contains('/helper/')).every((RecordedRequest r) => !r.hasAuth), isTrue);

      clock = clock.add(const Duration(hours: 72, minutes: 1));
      final AccountFailure early = await samNew.act((_) => failureOf(s.finish()));
      expect(early.problem.reason, 'waiting_for_helper');
      expect(early.problem.message, contains('say yes'));
      expect((await samNew.act((_) => s.status()))!.phase, RecoveryPhase.waitingForHelper);

      await helperPhone.act((_) => h.answer(requestId: list.single.requestId, yes: true));
      expect((await samNew.act((_) => s.status()))!.phase, RecoveryPhase.ready);
      final RecoveredResult done = await samNew.act((_) => s.finish());
      expect(done.sheetSpent, isTrue);
      expect((await samNew.identities.load())!.targetId, s0.samId);
    });

    test('a helper who says no stops it; a helper of another family cannot touch it', () async {
      final s0 = await sole();
      final RecoveryPathsService sam = svc(s0.sam);
      final HelperInvite inv = await s0.sam.act((_) => sam.nameHelper(name: 'Jo', pin: '4821'));
      final Phone helperPhone = Phone(server);
      final RecoveryPathsService h = svc(helperPhone);
      await helperPhone.act((_) => h.acceptHelperInvite(inv.code));

      final Phone other = await signedUp('Eve', pin: '1357');
      final RecoveryPathsService e = svc(other);
      final HelperInvite einv = await other.act((_) => e.nameHelper(name: 'Kai', pin: '1357'));
      final Phone otherHelper = Phone(server);
      final RecoveryPathsService oh = svc(otherHelper);
      await otherHelper.act((_) => oh.acceptHelperInvite(einv.code));

      final Phone samNew = Phone(server);
      final MemoryPendingRecoveryStore pend = MemoryPendingRecoveryStore();
      final RecoveryPathsService s = svc(samNew, pending: pend);
      await samNew.act((_) => s.startWithSheet(s0.key));
      final String reqId = rf.reqs.keys.single;

      // Eve's helper names Sam's request: one answer, and it changes nothing
      final AccountFailure wrongFamily = await otherHelper.act((_) => failureOf(oh.answer(requestId: reqId, yes: true)));
      expect(wrongFamily.problem.reason, 'not_found');
      expect(rf.reqs[reqId]!.helperConfirmed, isFalse);
      expect((await samNew.act((_) => s.status()))!.phase, RecoveryPhase.waiting);

      await helperPhone.act((_) => h.answer(requestId: reqId, yes: false));
      final RecoveryStatus? st = await samNew.act((_) => s.status());
      expect(st!.phase, RecoveryPhase.stopped);
      expect(st.stoppedBy, 'helper');
    });

    test('taking the helper off: their key stops working and the phone forgets it', () async {
      final s0 = await sole();
      final RecoveryPathsService sam = svc(s0.sam);
      final HelperInvite inv = await s0.sam.act((_) => sam.nameHelper(name: 'Jo', pin: '4821'));
      final Phone helperPhone = Phone(server);
      final MemoryHelperKeyStore hk = MemoryHelperKeyStore();
      final RecoveryPathsService h = svc(helperPhone, helper: hk);
      await helperPhone.act((_) => h.acceptHelperInvite(inv.code));
      await s0.sam.act((_) => sam.removeHelper(pin: '4821'));
      final AccountFailure f = await helperPhone.act((_) => failureOf(h.helperRequests()));
      expect(f.problem.reason, 'invalid_helper');
      expect(await hk.load(), isNull);
      expect(f.problem.message, isNot(contains('invalid_helper')));
    });

    test('an invite with an email in the name never leaves the phone', () async {
      final s0 = await sole();
      server.requests.clear();
      final AccountFailure f = await s0.sam.act((_) => failureOf(svc(s0.sam).nameHelper(name: 'jo@example.test', pin: '4821')));
      expect(f.problem.reason, 'invalid_label');
      expect(server.requests, isEmpty);
    });
  });

  group('failures are words', () {
    test('a lost connection is one calm sentence with no technical text', () async {
      final Phone sam = await signedUp('Sam');
      final RecoveryPathsService s = svc(sam);
      server.interceptor = (_) async => throw const SocketException('Connection refused (OS Error: 61)');
      final AccountFailure f = await sam.act((_) => failureOf(s.summary()));
      expect(f.problem.reason, 'network');
      expect(f.problem.message, isNot(contains('Socket')));
      expect(f.problem.message, isNot(contains('OS Error')));
      expect(f.problem.message, contains('Nothing is lost'));
    });
  });
}
