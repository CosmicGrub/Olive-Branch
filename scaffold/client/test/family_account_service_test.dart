// OLIVE BRANCH — family_account_service.dart: the whole optional-account flow against an in-memory server that
// answers like server/routes.mjs and checks every request against the REAL route table (test/support/). MASTERFILE
// section 8.5.13. Covers: sign-up, sign-in, adding a child, inviting, joining by invite (new person and existing
// account), the inviter's confirm and decline, resuming, and the hostile cases (typos, forged codes, double taps, a
// lost reply, a failed save of the sign-in, a proxy's HTML error page, a revoked phone).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:olive_client/api_client.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/family_account_service.dart';
import 'package:olive_client/family_account_store.dart';

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';

void main() {
  late FakeIdentityServer server;
  setUp(() {
    server = FakeIdentityServer();
    AuthSession.use(null);
  });
  tearDown(() => AuthSession.use(null));

  Future<Phone> signedUp(String name, {String pin = '4821', String code = kCode}) async {
    final Phone p = Phone(server);
    server.addAllowance(code);
    await p.act((s) => s.signUp(allowanceCode: code, displayName: name, homeTz: 'America/Chicago', pin: pin));
    return p;
  }

  Future<AccountChild> withChild(Phone p, {String pin = '4821'}) =>
      p.act((s) => s.addChild(displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: pin));

  Future<AccountFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on AccountFailure catch (e) {
      return e;
    }
    fail('expected an AccountFailure');
  }

  group('sign-up', () {
    test('makes the account, keeps the sign-in key, and sends only what the real handler reads', () async {
      final Phone p = await signedUp('Sam');
      final RecordedRequest r = server.requests.single;
      expect(r.method, 'POST');
      expect(r.path, '/v1/auth/signup');
      expect(r.hasAuth, isFalse);
      expect(r.body.keys.toSet(), <String>{'allowanceToken', 'displayName', 'homeTz', 'pin', 'deviceLabel'});
      final DeviceIdentity? id = await p.identities.load();
      expect(id, isNotNull);
      expect(id!.role, 'guardian');
      expect(id.deviceCredential, isNotNull);
      expect(AuthSession.current, isNotNull);
      expect((await p.record.load())!.stage, AccountStage.signedUp);
      expect(p.service.hasUnsavedSignIn, isFalse);
      // The allowance was single use.
      expect(server.allowances, isEmpty);
    });

    test('a wrong code is refused in plain words and leaves nothing behind', () async {
      final Phone p = Phone(server);
      final AccountFailure f = await failureOf(p.act((s) => s.signUp(
          allowanceCode: 'not-a-real-code-0123456789', displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821')));
      expect(f.problem.kind, ProblemKind.fixInput);
      expect(f.problem.message, contains("didn't work"));
      expect(f.problem.message, isNot(contains('invalid_allowance')));
      expect(await p.identities.load(), isNull);
      expect(AuthSession.current, isNull);
      expect(await p.record.load(), isNull);
    });

    test('typos and hostile input never reach the network', () async {
      final Phone p = Phone(server);
      final List<Map<String, String>> bad = <Map<String, String>>[
        <String, String>{'code': 'short', 'name': 'Sam', 'tz': 'America/Chicago', 'pin': '4821'},
        <String, String>{'code': '$kCode\u0000', 'name': 'Sam', 'tz': 'America/Chicago', 'pin': '4821'},
        <String, String>{'code': kCode, 'name': '', 'tz': 'America/Chicago', 'pin': '4821'},
        <String, String>{'code': kCode, 'name': 'Sa\u0000m', 'tz': 'America/Chicago', 'pin': '4821'},
        <String, String>{'code': kCode, 'name': 'x' * 61, 'tz': 'America/Chicago', 'pin': '4821'},
        <String, String>{'code': kCode, 'name': 'Sam', 'tz': '../etc/passwd', 'pin': '4821'},
        <String, String>{'code': kCode, 'name': 'Sam', 'tz': 'America/Chicago', 'pin': '1234'},
        <String, String>{'code': kCode, 'name': 'Sam', 'tz': 'America/Chicago', 'pin': '12'},
        <String, String>{'code': kCode, 'name': 'Sam', 'tz': 'America/Chicago', 'pin': 'abcd'},
      ];
      for (final Map<String, String> b in bad) {
        final AccountFailure f = await failureOf(p.act((s) => s.signUp(
            allowanceCode: b['code']!, displayName: b['name']!, homeTz: b['tz']!, pin: b['pin']!)));
        expect(f.problem.kind, ProblemKind.fixInput, reason: '$b');
      }
      expect(server.requests, isEmpty);
    });

    test('a pasted code with a line break in it still works', () async {
      final Phone p = Phone(server);
      server.addAllowance(kCode);
      await p.act((s) => s.signUp(
          allowanceCode: '  ${kCode.substring(0, 10)}\n${kCode.substring(10)}  ',
          displayName: '  Sam   Lee ', homeTz: 'America/Chicago', pin: '4821'));
      expect(server.requests.single.body['displayName'], 'Sam Lee');
      expect(server.requests.single.body['allowanceToken'], kCode);
    });

    test('a phone that is already signed in cannot sign up again (it would lose the first key)', () async {
      final Phone p = await signedUp('Sam');
      server.addAllowance('second-allowance-0123456789ab');
      final int before = server.requests.length;
      final AccountFailure f = await failureOf(p.act((s) => s.signUp(
          allowanceCode: 'second-allowance-0123456789ab', displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821')));
      expect(f.problem.reason, 'already_signed_in');
      expect(server.requests.length, before);
      expect(server.allowances, contains('second-allowance-0123456789ab'));
    });

    test('a closed sign-up door is said plainly', () async {
      server.signupEnabled = false;
      final Phone p = Phone(server);
      server.addAllowance(kCode);
      final AccountFailure f = await failureOf(
          p.act((s) => s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821')));
      expect(f.problem.message, contains("isn't accepting new accounts"));
    });

    test('if the sign-in key cannot be saved, the account still works this run and the phone says so', () async {
      final Phone p = Phone(server);
      p.secure.failWrites = true;
      server.addAllowance(kCode);
      await p.act((s) => s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
      expect(p.service.hasUnsavedSignIn, isTrue);
      expect(await p.identities.load(), isNull);
      // It works for this run: a child can be added.
      final AccountChild c = await withChild(p);
      expect(c.name, 'Ivy');
      // Still failing: not saved, and it says so.
      expect(await p.service.retrySaveSignIn(), isFalse);
      expect((await p.service.snapshot()).unsavedSignIn, isTrue);
      // Fixed: now it is kept.
      p.secure.failWrites = false;
      expect(await p.service.retrySaveSignIn(), isTrue);
      expect(p.service.hasUnsavedSignIn, isFalse);
      expect((await p.identities.load())!.deviceCredential, isNotNull);
    });

    test('a reply that never arrives is called what it is: the outcome is unknown', () async {
      final Phone p = Phone(server);
      server.addAllowance(kCode);
      server.interceptor = (http.BaseRequest _) async => throw TimeoutException('slow');
      final AccountFailure f = await failureOf(
          p.act((s) => s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821')));
      expect(f.problem.kind, ProblemKind.tryAgain);
      expect(f.problem.message, contains("can't be sure"));
      expect(f.problem.message, isNot(contains('TimeoutException')));
    });
  });

  group('a child on the account', () {
    test('needs the right PIN; a wrong one is said in words and counts toward the server lock', () async {
      final Phone p = await signedUp('Sam');
      final AccountFailure f = await failureOf(withChild(p, pin: '9999'));
      expect(f.problem.message, "That PIN isn't right.");
      final AccountChild c = await withChild(p);
      expect(c.id, isNotEmpty);
      expect((await p.record.load())!.childId, c.id);
      expect((await p.record.load())!.stage, AccountStage.childAdded);
    });

    test('five wrong PINs lock it and the screen says to wait', () async {
      final Phone p = await signedUp('Sam');
      for (int i = 0; i < 5; i++) {
        await failureOf(withChild(p, pin: '9999'));
      }
      final AccountFailure f = await failureOf(withChild(p));
      expect(f.problem.kind, ProblemKind.wait);
      expect(f.problem.message, contains('15 minutes'));
    });

    test('a birth date that cannot be right never reaches the server', () async {
      final Phone p = await signedUp('Sam');
      final int before = server.requests.length;
      for (final DateTime d in <DateTime>[
        server.now().add(const Duration(days: 1)),
        DateTime(server.now().year - 18, server.now().month, server.now().day - 1),
        DateTime(1900),
      ]) {
        final AccountFailure f = await failureOf(p.act((s) =>
            s.addChild(displayName: 'Ivy', birthDate: d, homeTz: 'America/Chicago', pin: '4821')));
        expect(f.problem.kind, ProblemKind.fixInput, reason: '$d');
      }
      expect(server.requests.length, before);
    });

    test('a double tap is one request', () async {
      final Phone p = await signedUp('Sam');
      final Future<AccountChild> a = p.act((s) =>
          s.addChild(displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final Future<AccountChild> b = p.act((s) =>
          s.addChild(displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final List<AccountChild> both = await Future.wait(<Future<AccountChild>>[a, b]);
      expect(both[0].id, both[1].id);
      expect(server.requests.where((RecordedRequest r) => r.path == '/v1/children' && r.method == 'POST'), hasLength(1));
      expect(server.children, hasLength(1));
    });

    test('with no sign-in at all, the screen is told to sign in, not shown an error code', () async {
      final Phone p = Phone(server);
      final AccountFailure f = await failureOf(withChild(p));
      expect(f.problem.kind, ProblemKind.needsSignIn);
      expect(server.requests, isEmpty);
    });
  });

  group('inviting and being invited', () {
    Future<({Phone inviter, AccountChild child, CreatedInvite invite})> invited() async {
      final Phone inviter = await signedUp('Sam');
      final AccountChild child = await withChild(inviter);
      final CreatedInvite invite = await inviter.act((s) => s.createInvite(
          childId: child.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
      return (inviter: inviter, child: child, invite: invite);
    }

    test('the whole chain: invite, open, join, ask, the inviter says yes, access appears', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      expect(isServerId(w.invite.code), isTrue);

      final Phone robin = Phone(server);
      final InviteLookup seen = await robin.act((s) => s.lookUpInvite(w.invite.code));
      expect(seen.maskedEmail, 'r***@example.com');
      expect(seen.alreadyOpened, isFalse);
      // Looking is free of side effects.
      expect(server.invites[w.invite.code]!.accepted, isFalse);

      await robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      expect(await robin.identities.load(), isNotNull);
      expect((await robin.pending.load())!.stage, JoinStage.waiting);

      // Robin has an account, and NO access yet.
      AccountSnapshot rs = await robin.act((s) => s.snapshot());
      expect(rs.children, isEmpty);
      expect(rs.hasPin, isFalse);

      // The inviter sees who is asking.
      AccountSnapshot ss = await w.inviter.act((s) => s.snapshot());
      expect(ss.waitingForYou.single.claimantName, 'Robin');
      expect(ss.waitingForYou.single.statusLine(), contains('Robin is asking to join'));

      expect(await robin.act((s) => s.checkJoin()), JoinStatus.waiting);

      // A wrong PIN does not add them.
      final AccountFailure wrong = await failureOf(w.inviter.act((s) => s.confirmInvite(w.invite.code, '0000')));
      expect(wrong.problem.message, "That PIN isn't right.");
      expect((await robin.act((s) => s.snapshot())).children, isEmpty);

      await w.inviter.act((s) => s.confirmInvite(w.invite.code, '4821'));
      expect(await robin.act((s) => s.checkJoin()), JoinStatus.confirmed);
      expect(await robin.pending.load(), isNull);
      rs = await robin.act((s) => s.snapshot());
      expect(rs.children.single.id, w.child.id);
      expect((await robin.record.load())!.childId, w.child.id);
      ss = await w.inviter.act((s) => s.snapshot());
      expect(ss.invites.single.state, InviteState.confirmed);
    });

    test('the inviter can turn them away; the other person is told gently and the join is forgotten', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final Phone robin = Phone(server);
      await robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      await w.inviter.act((s) => s.turnAwayInvite(w.invite.code));
      expect(await robin.act((s) => s.checkJoin()), JoinStatus.turnedAway);
      expect(await robin.pending.load(), isNull);
      expect((await robin.act((s) => s.snapshot())).children, isEmpty);
    });

    test('an invite nobody has opened can be cancelled; one that was opened cannot (turn away instead)', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      await w.inviter.act((s) => s.cancelInvite(w.invite.code));
      final AccountFailure gone = await failureOf(Phone(server).act((s) => s.lookUpInvite(w.invite.code)));
      expect(gone.problem.message, contains('no longer open'));

      final CreatedInvite second = await w.inviter.act((s) => s.createInvite(
          childId: w.child.id, role: 'sitter', label: 'Jo', email: 'jo@example.com', pin: '4821'));
      await Phone(server).act((s) => s.joinAsNew(inviteCode: second.code, displayName: 'Jo'));
      final AccountFailure f = await failureOf(w.inviter.act((s) => s.cancelInvite(second.code)));
      expect(f.problem.message, contains('Turn them away instead'));
    });

    test('resuming: if the account step is interrupted, a second try does not open the invite again', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final Phone robin = Phone(server);
      bool cut = true;
      server.interceptor = (http.BaseRequest r) async {
        if (cut && r.url.path.endsWith('/bootstrap')) throw const SocketException('lost');
        return null;
      };
      final AccountFailure f = await failureOf(robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin')));
      expect(f.problem.kind, ProblemKind.tryAgain);
      expect((await robin.pending.load())!.stage, JoinStage.accepted);
      cut = false;
      server.requests.clear();
      await robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      expect(server.requests.where((RecordedRequest r) => r.path.endsWith('/accept')), isEmpty);
      expect((await robin.pending.load())!.stage, JoinStage.waiting);
      expect(await robin.identities.load(), isNotNull);
    });

    test('a 200 that is not the server (a captive portal) is never taken for "done"', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final Phone robin = Phone(server);
      await robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      final int before = server.guardianship[w.child.id]!.length;
      server.interceptor = (http.BaseRequest r) async =>
          http.Response('<html>login to wifi</html>', 200, headers: <String, String>{'content-type': 'text/html'});
      final AccountFailure confirm = await failureOf(w.inviter.act((s) => s.confirmInvite(w.invite.code, '4821')));
      expect(confirm.problem.kind, ProblemKind.tryAgain);
      expect(confirm.problem.message, contains('did not expect'));
      expect(confirm.problem.message, isNot(contains('<html')));
      final AccountFailure decline = await failureOf(w.inviter.act((s) => s.turnAwayInvite(w.invite.code)));
      expect(decline.problem.kind, ProblemKind.tryAgain);
      // A JSON body that does not say ok is no better.
      server.interceptor = (http.BaseRequest r) async => http.Response('{"status":"fine"}', 200);
      expect((await failureOf(w.inviter.act((s) => s.confirmInvite(w.invite.code, '4821')))).problem.kind,
          ProblemKind.tryAgain);
      server.interceptor = null;
      // The server never ran either step: nobody was added, and the real answer still works.
      expect(server.guardianship[w.child.id], hasLength(before));
      await w.inviter.act((s) => s.confirmInvite(w.invite.code, '4821'));
      expect(server.guardianship[w.child.id], hasLength(before + 1));
    });

    test('a 200 that is not the server does not cancel an invite or claim one either', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      server.interceptor = (http.BaseRequest r) async => http.Response('<html>login to wifi</html>', 200);
      final AccountFailure f = await failureOf(w.inviter.act((s) => s.cancelInvite(w.invite.code)));
      expect(f.problem.kind, ProblemKind.tryAgain);
      server.interceptor = null;
      // Still open: the real cancel works afterwards.
      await w.inviter.act((s) => s.cancelInvite(w.invite.code));
    });

    test('an invite opened here but not held (the save was lost) still finishes: opening again is not a dead end',
        () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final Phone robin = Phone(server);
      bool cut = true;
      server.interceptor = (http.BaseRequest r) async {
        if (cut && r.url.path.endsWith('/bootstrap')) throw const SocketException('lost');
        return null;
      };
      await failureOf(robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin')));
      cut = false;
      await robin.pending.clear(); // as if saving "opened" had failed: the server accepted, the phone forgot
      await robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      expect((await robin.pending.load())!.stage, JoinStage.waiting);
      expect(await robin.identities.load(), isNotNull);
    });

    test('an invite someone else already opened is not silently taken over', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final Phone robin = Phone(server);
      await robin.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      final Phone mallory = Phone(server);
      final AccountFailure f = await failureOf(mallory.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Mallory')));
      expect(f.problem.message, contains('already made from this invite'));
      // No second account, no sign-in and nothing held on the second phone; the first is untouched.
      expect(await mallory.identities.load(), isNull);
      expect(await mallory.pending.load(), isNull);
      expect(await robin.identities.load(), isNotNull);
    });

    test('an email that already has an account is sent to sign in, then to use the code', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final FakeUser existing = server.addUser('Robin', email: 'robin@example.com', pin: '5921');
      final Phone fresh = Phone(server);
      final AccountFailure f = await failureOf(fresh.act((s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin')));
      expect(f.problem.message, contains('already has an Olive account'));
      // Their phone has the account: accept stays recorded, then the account claims.
      final Phone robin = Phone(server);
      final String dev = server.mintDevice(existing.id);
      final DeviceIdentity id = DeviceIdentity(
          sessionToken: server.sessionFor(existing.id), deviceId: dev, role: 'guardian', targetId: existing.id,
          deviceCredential: server.devices[dev]!.credential);
      await robin.identities.save(id);
      await robin.act((s) => s.useInviteWithAccount(w.invite.code));
      expect((await robin.pending.load())!.stage, JoinStage.waiting);
      await w.inviter.act((s) => s.confirmInvite(w.invite.code, '4821'));
      expect(await robin.act((s) => s.checkJoin()), JoinStatus.confirmed);
      expect((await robin.act((s) => s.snapshot())).children.single.id, w.child.id);
    });

    test('an account with a different email cannot claim someone else\'s invite', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final Phone other = await signedUp('Pat', code: 'another-allowance-0123456789a');
      final AccountFailure f = await failureOf(other.act((s) => s.useInviteWithAccount(w.invite.code)));
      expect(f.problem.message, contains('different email'));
      expect(server.guardianship[w.child.id], hasLength(1));
    });

    test('forged and malformed codes never reach a URL', () async {
      final Phone p = Phone(server);
      server.requests.clear();
      for (final String code in <String>[
        '../../v1/me', '3f2a9c1e', 'not a code', '', '00000000-0000-4000-8000-000000000001/../../me',
        '00000000-0000-4000-8000-00000000000g', 'x' * 400, '<script>', '?a=b#c',
      ]) {
        final AccountFailure f = await failureOf(p.act((s) => s.lookUpInvite(code)));
        expect(f.problem.kind, ProblemKind.fixInput, reason: code);
      }
      expect(server.requests, isEmpty);
    });

    test('a code pasted with quotes or a line break is cleaned, not refused', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final InviteLookup l = await Phone(server).act((s) => s.lookUpInvite('  "${w.invite.code.toUpperCase()}"\n'));
      expect(l.id, w.invite.code);
    });

    test('a code that was never issued is "not found" in words', () async {
      final AccountFailure f = await failureOf(Phone(server).act((s) => s.lookUpInvite('00000000-0000-4000-8000-0000000000ff')));
      expect(f.problem.message, contains("wasn't found"));
    });

    test('an expired invite says so', () async {
      final ({Phone inviter, AccountChild child, CreatedInvite invite}) w = await invited();
      final DateTime later = server.now().add(const Duration(days: 15));
      final FakeIdentityServer clockServer = server; // same data, a clock past the expiry
      final FamilyAccountService s = FamilyAccountService(
          baseUrl: kBase, client: clockServer.client, now: () => later,
          identityStore: DeviceIdentityStore(storage: MemSecure()));
      final AccountFailure f = await failureOf(s.lookUpInvite(w.invite.code));
      expect(f.problem.message, contains('ran out'));
    });

    test('the role, label and email are checked before anything is sent', () async {
      final Phone p = await signedUp('Sam');
      final AccountChild c = await withChild(p);
      final int before = server.requests.length;
      for (final Map<String, String> b in <Map<String, String>>[
        <String, String>{'role': 'owner', 'label': 'Nana', 'email': 'a@example.com'},
        <String, String>{'role': 'guardian', 'label': '', 'email': 'a@example.com'},
        <String, String>{'role': 'guardian', 'label': 'Nana', 'email': 'not an email'},
        <String, String>{'role': 'guardian', 'label': 'Nana', 'email': 'a@example.com\nBcc: x@example.org'},
      ]) {
        final AccountFailure f = await failureOf(p.act((s) =>
            s.createInvite(childId: c.id, role: b['role']!, label: b['label']!, email: b['email']!, pin: '4821')));
        expect(f.problem.kind, ProblemKind.fixInput, reason: '$b');
      }
      expect(server.requests.length, before);
    });
  });

  group('the sign-in', () {
    test('a stale session is renewed once, quietly, with the phone\'s key', () async {
      final Phone p = await signedUp('Sam');
      await withChild(p);
      server.sessions.clear(); // the server forgets the token
      final AccountSnapshot s = await p.act((s) => s.snapshot());
      expect(s.signedIn, isTrue);
      expect(s.children, hasLength(1));
      expect(server.requests.any((RecordedRequest r) => r.path == '/v1/auth/session/refresh'), isTrue);
    });

    test('a phone removed from the account is told to sign in again, and its key is cleared', () async {
      final Phone p = await signedUp('Sam');
      final String devId = (await p.identities.load())!.deviceId;
      server.devices[devId] = (userId: server.devices[devId]!.userId, credential: server.devices[devId]!.credential, revoked: true);
      server.sessions.clear();
      final AccountSnapshot s = await p.act((s) => s.snapshot());
      expect(s.signedIn, isFalse);
      expect(await p.identities.load(), isNull);
      expect(p.signedOutCalls, 1);
      final AccountFailure f = await failureOf(withChild(p));
      expect(f.problem.kind, ProblemKind.needsSignIn);
    });

    test('checkSignIn says yes for a working phone and no for a removed one', () async {
      final Phone p = await signedUp('Sam');
      expect(await p.act((s) => s.checkSignIn()), isTrue);
      final String devId = (await p.identities.load())!.deviceId;
      server.devices[devId] = (userId: server.devices[devId]!.userId, credential: server.devices[devId]!.credential, revoked: true);
      expect(await p.act((s) => s.checkSignIn()), isFalse);
    });

    test('sign out forgets the account on this phone, tells the server, and leaves nothing behind', () async {
      final Phone p = await signedUp('Sam');
      await withChild(p);
      expect(await p.act((s) => s.signOut()), isTrue);
      expect(await p.identities.load(), isNull);
      expect(await p.record.load(), isNull);
      expect(await p.pending.load(), isNull);
      expect(AuthSession.current, isNull);
      final AccountSnapshot s = await p.act((s) => s.snapshot());
      expect(s.signedIn, isFalse);
      expect(s.step, AccountStep.start);
    });

    test('sign out works with no connection (the phone still signs out; it says the server could not confirm)', () async {
      final Phone p = await signedUp('Sam');
      server.interceptor = (http.BaseRequest _) async => throw const SocketException('offline');
      expect(await p.act((s) => s.signOut()), isFalse);
      expect(await p.identities.load(), isNull);
    });

    test('offline, the page shows what the phone remembers and says it could not ask', () async {
      final Phone p = await signedUp('Sam');
      await withChild(p);
      server.interceptor = (http.BaseRequest _) async => throw const SocketException('offline');
      final AccountSnapshot s = await p.act((s) => s.snapshot());
      expect(s.signedIn, isTrue);
      expect(s.serverReached, isFalse);
      expect(s.step, AccountStep.family);
      expect(s.children, isEmpty);
    });

    test('a phone with no account is just a phone: the page offers the three ways in and asks nothing', () async {
      final Phone p = Phone(server);
      final AccountSnapshot s = await p.act((s) => s.snapshot());
      expect(s.signedIn, isFalse);
      expect(s.step, AccountStep.start);
      expect(server.requests, isEmpty);
    });
  });

  group('when the network or the server misbehaves', () {
    test('a proxy\'s HTML error page is a server problem, not a crash', () async {
      final Phone p = await signedUp('Sam');
      server.failNext = http.Response('<html><body>502 Bad Gateway</body></html>', 502);
      final AccountFailure f = await failureOf(withChild(p));
      expect(f.problem.kind, ProblemKind.tryAgain);
      expect(f.problem.message, contains('server had a problem'));
      expect(f.problem.message, isNot(contains('502')));
      expect(f.problem.message, isNot(contains('<html')));
    });

    test('a reply that is not an object is survived', () async {
      final Phone p = await signedUp('Sam');
      server.failNext = http.Response('[1,2,3]', 200);
      final AccountFailure f = await failureOf(withChild(p));
      expect(f.problem.kind, ProblemKind.tryAgain);
    });

    test('rate limiting is said as waiting', () async {
      final Phone p = Phone(server);
      server.addAllowance(kCode);
      server.failNext = http.Response(jsonEncode(<String, String>{'error': 'rate_limited'}), 429);
      final AccountFailure f = await failureOf(
          p.act((s) => s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821')));
      expect(f.problem.kind, ProblemKind.wait);
    });

    test('no failure leaks a code, a status or an exception name to the screen', () async {
      final Phone p = await signedUp('Sam');
      final List<Object> boom = <Object>[
        const SocketException('x'), TimeoutException('x'), const FormatException('x'), StateError('x'),
        http.ClientException('x'), ApiException(500, 'weird_code_from_the_future'), ApiException(418, 'teapot'),
      ];
      for (final Object e in boom) {
        server.interceptor = (http.BaseRequest _) async => throw e;
        final AccountFailure f = await failureOf(withChild(p));
        final String m = f.problem.message;
        expect(m, isNot(contains('weird_code')), reason: '$e');
        expect(m, isNot(contains('teapot')), reason: '$e');
        expect(RegExp(r'[a-z]+_[a-z_]+').hasMatch(m), isFalse, reason: '"$m" looks like a code ($e)');
        expect(RegExp(r'\b[1-5]\d\d\b').hasMatch(m), isFalse, reason: '"$m" has a status ($e)');
        expect(m, isNot(contains('Exception')), reason: '$e');
      }
    });
  });

  group('the PIN of an account made from an invite', () {
    test('starts without one; the first PIN can be set; an easy one is refused on the phone', () async {
      final Phone inviter = await signedUp('Sam');
      final AccountChild child = await withChild(inviter);
      final CreatedInvite inv = await inviter.act((s) => s.createInvite(
          childId: child.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
      final Phone robin = Phone(server);
      await robin.act((s) => s.joinAsNew(inviteCode: inv.code, displayName: 'Robin'));
      expect((await robin.act((s) => s.snapshot())).hasPin, isFalse);
      final AccountFailure easy = await failureOf(robin.act((s) => s.setFirstPin('1111')));
      expect(easy.problem.message, contains('easy to guess'));
      await robin.act((s) => s.setFirstPin('7391'));
      expect((await robin.act((s) => s.snapshot())).hasPin, isTrue);
    });
  });
}
