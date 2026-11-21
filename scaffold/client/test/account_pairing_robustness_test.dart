// OLIVE BRANCH — account and pairing robustness: a reply that is not the server's (a captive portal's HTML 200) is
// "unconfirmed", never a crash and never success; the first PIN that may have been set is recognised on the retry;
// sign-out forgets the account note BEFORE the shell restarts; a lost "waiting" note never traps a joined person; a
// teen's "stay in touch" choice that was not kept is put back; a family key that cannot be kept stops pairing.
// Headless; the family-account tests run against the in-memory server in test/support/.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/family_account_service.dart';
import 'package:olive_client/family_account_store.dart';
import 'package:olive_client/guardian_teen_screens.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/teen_logic.dart';
import 'package:olive_client/teen_store.dart';
import 'package:olive_client/ui/olive_controls.dart';

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';

http.Response _html(int status) =>
    http.Response('<html>sign in to the wifi</html>', status, headers: <String, String>{'content-type': 'text/html'});

http.Response _json(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});

/// A pending-join store whose Nth saves (1-based) throw.
class _FlakyPending implements PendingJoinStore {
  _FlakyPending(this.failOnSaves);
  final Set<int> failOnSaves;
  int saves = 0;
  PendingJoin? _j;
  @override
  Future<PendingJoin?> load() async => _j;
  @override
  Future<void> save(PendingJoin join) async {
    saves++;
    if (failOnSaves.contains(saves)) throw StateError('secure storage is busy');
    _j = join;
  }

  @override
  Future<void> clear() async => _j = null;
}

class _PlainCipher implements StoreCipher {
  @override
  Future<Uint8List> seal(Uint8List plain, List<int> aad) async => plain;
  @override
  Future<Uint8List> open(Uint8List box, List<int> aad) async => box;
}

class _FailingTouchRepo extends TeenRepository {
  _FailingTouchRepo(super.ns);
  int tries = 0;
  @override
  Future<void> saveTouch(StayInTouch t) async {
    tries++;
    throw StateError('could not write');
  }
}

/// A pairing-picture repository whose saves throw, or that "succeeds" without keeping the key.
class _BrokenPictures implements PairingPictureRepository {
  _BrokenPictures({this.throwing = true});
  final bool throwing;
  int saves = 0;
  PairingPictureState? kept;
  @override
  Future<PairingPictureState?> load() async => kept;
  @override
  Future<void> save(PairingPictureState state) async {
    saves++;
    if (throwing) throw StateError('disk full');
    // Keeps only the salt and epoch: the family key does not stick.
    kept = PairingPictureState(state.salt, state.epoch);
  }
}

void main() {
  setUp(() {
    OliveApi.forgetUnconfirmedPinAttempts();
    AuthSession.use(null);
  });
  tearDown(() => AuthSession.use(null));

  group('ISS-054: a reply that is not the server\'s is unconfirmed, not a crash', () {
    test('setGuardianPin: a 200 with an HTML body is unconfirmed, then the retry finds the PIN was set', () async {
      final List<String> seen = <String>[];
      int pinPosts = 0;
      final MockClient mock = MockClient((http.Request req) async {
        seen.add('${req.method} ${req.url.path}');
        if (req.url.path == '/v1/me/pin') {
          pinPosts++;
          // The first attempt DID run on the server, but the reply the phone saw was a portal's page.
          return pinPosts == 1 ? _html(200) : _json(403, <String, Object?>{'error': 'current_pin_required'});
        }
        if (req.url.path == '/v1/me') return _json(200, <String, Object?>{'userId': 'u', 'hasPin': true});
        return _json(404, <String, Object?>{'error': 'not_found'});
      });
      final OliveApi api = OliveApi('http://api.test', 'tok', client: mock);
      await expectLater(
          api.setGuardianPin('5193'),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'unexpected_reply')));
      expect(seen, <String>['POST /v1/me/pin']);
      // The retry (a new api, as the screens build one per call) is told a PIN exists: the server says it is ours.
      final OliveApi again = OliveApi('http://api.test', 'tok', client: mock);
      await expectLater(again.setGuardianPin('5193'), completes);
      expect(seen, <String>['POST /v1/me/pin', 'POST /v1/me/pin', 'GET /v1/me']);
      // The mark is spent: a later refusal is a real one again.
      await expectLater(() => again.setGuardianPin('5193'),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'current_pin_required')));
    });

    test('setGuardianPin: current_pin_required with NO unconfirmed attempt before it stays a refusal (nothing is asked)', () async {
      final List<String> seen = <String>[];
      final MockClient mock = MockClient((http.Request req) async {
        seen.add('${req.method} ${req.url.path}');
        return _json(403, <String, Object?>{'error': 'current_pin_required'});
      });
      final OliveApi api = OliveApi('http://api.test', 'tok', client: mock);
      await expectLater(api.setGuardianPin('5193'),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'current_pin_required')));
      expect(seen, <String>['POST /v1/me/pin']);
    });

    test('setGuardianPin: after an unconfirmed attempt, current_pin_required with hasPin false stays a refusal', () async {
      int posts = 0;
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/me/pin') {
          return ++posts == 1 ? _html(200) : _json(403, <String, Object?>{'error': 'current_pin_required'});
        }
        return _json(200, <String, Object?>{'userId': 'u', 'hasPin': false});
      });
      final OliveApi api = OliveApi('http://api.test', 'tok', client: mock);
      await expectLater(api.setGuardianPin('5193'), throwsA(isA<ApiException>()));
      await expectLater(api.setGuardianPin('5193'),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'current_pin_required')));
    });

    test('every _decode call site: HTML or a non-object on a 2xx is unexpected_reply; an HTML error page keeps its status', () async {
      for (final http.Response bad in <http.Response>[_html(200), http.Response('[1,2]', 200), http.Response('{"a":', 200)]) {
        final OliveApi api = OliveApi('http://api.test', 'tok', client: MockClient((_) async => bad));
        await expectLater(api.fetchMe(), throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'unexpected_reply')),
            reason: 'GET');
        await expectLater(api.changeGuardianPin('1111', '2222'),
            throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'unexpected_reply')), reason: 'POST');
      }
      final OliveApi down = OliveApi('http://api.test', 'tok', client: MockClient((_) async => _html(502)));
      await expectLater(down.fetchMe(), throwsA(isA<ApiException>().having((ApiException e) => e.statusCode, 'status', 502)));
      // An empty 2xx stays an empty answer (a 204).
      final OliveApi empty = OliveApi('http://api.test', 'tok', client: MockClient((_) async => http.Response('', 204)));
      expect(await empty.fetchMe(), isEmpty);
    });

    test('the sites that accept a 409/400/422 as an answer: HTML is unexpected_reply, JSON still returns', () async {
      final OliveApi html = OliveApi('http://api.test', 'tok', client: MockClient((_) async => _html(201)));
      await expectLater(html.recordExchangeArrival('c1'),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'unexpected_reply')));
      final OliveApi htmlConflict = OliveApi('http://api.test', 'tok', client: MockClient((_) async => _html(409)));
      await expectLater(htmlConflict.recordExchangeArrival('c1'),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'unexpected_reply')));
      final OliveApi ok = OliveApi('http://api.test', 'tok',
          client: MockClient((_) async => _json(409, <String, Object?>{'error': 'already_recorded'})));
      expect((await ok.recordExchangeArrival('c1'))['error'], 'already_recorded');
      final OliveApi bad = OliveApi('http://api.test', 'tok', client: MockClient((_) async => _html(500)));
      await expectLater(bad.recordExchangeArrival('c1'), throwsA(isA<ApiException>().having((ApiException e) => e.statusCode, 'status', 500)));
    });

    test('the pre-session sites: a sign-in reply without a token, or with HTML, is unexpected_reply', () async {
      await expectLater(
          redeemDevicePairingCode('http://api.test', 'ABC', 'guardian', client: MockClient((_) async => _html(200))),
          throwsA(isA<ApiException>().having((ApiException e) => e.error, 'error', 'unexpected_reply')));
      await expectLater(
          redeemDevicePairingCode('http://api.test', 'ABC', 'guardian', client: MockClient((_) async => _html(502))),
          throwsA(isA<ApiException>().having((ApiException e) => e.statusCode, 'status', 502)));
    });

    test('setFirstPin through the account service: a portal 200 then a retry ends with the PIN set', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      final Phone p = Phone(server, pendingStore: null);
      server.addAllowance(kCode);
      await p.act((FamilyAccountService s) =>
          s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
      // An account that has no PIN yet: sign-up made one, so clear it on the fake server.
      final String userId = (await p.identities.load())!.targetId;
      server.users[userId]!.pin = null;
      int first = 0;
      server.interceptor = (http.BaseRequest r) async {
        if (r.url.path == '/v1/me/pin' && first++ == 0) {
          server.users[userId]!.pin = '5193'; // it ran
          return _html(200); // but the reply was a portal's
        }
        return null;
      };
      Object? failure;
      try {
        await p.act((FamilyAccountService s) => s.setFirstPin('5193'));
      } on AccountFailure catch (e) {
        failure = e;
      }
      expect(failure, isA<AccountFailure>(), reason: 'not success: nobody can tell it ran');
      await p.act((FamilyAccountService s) => s.setFirstPin('5193'));
      expect(server.users[userId]!.pin, '5193');
    });
  });

  group('ISS-055: sign-out forgets the account note before the shell restarts', () {
    test('the record and the pending invite are already empty when the restart callback runs', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      PendingJoin? pendingAtRestart = const PendingJoin(inviteId: 'unset', stage: JoinStage.accepted);
      AccountRecord? recordAtRestart = AccountRecord(stage: AccountStage.signedUp, at: DateTime.utc(2026));
      late final Phone p;
      p = Phone(server, whenSignedOut: () {
        // Memory stores answer synchronously-started loads: this reads them AT the restart.
        unawaited(p.record.load().then((AccountRecord? r) => recordAtRestart = r));
        unawaited(p.pending.load().then((PendingJoin? j) => pendingAtRestart = j));
      });
      server.addAllowance(kCode);
      await p.act((FamilyAccountService s) =>
          s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
      await p.pending.save(const PendingJoin(inviteId: 'inv', stage: JoinStage.waiting));
      expect(await p.record.load(), isNotNull);
      expect(await p.act((FamilyAccountService s) => s.signOut()), isTrue);
      expect(p.signedOutCalls, 1);
      await Future<void>.delayed(Duration.zero);
      expect(recordAtRestart, isNull, reason: 'the restart must not find the old account note');
      expect(pendingAtRestart, isNull);
    });

    test('with no session installed the shell is still sent back, after the note is forgotten', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      AccountRecord? recordAtRestart = AccountRecord(stage: AccountStage.signedUp, at: DateTime.utc(2026));
      late final Phone p;
      p = Phone(server, whenSignedOut: () {
        unawaited(p.record.load().then((AccountRecord? r) => recordAtRestart = r));
      });
      await p.record.save(AccountRecord(stage: AccountStage.signedUp, at: DateTime.utc(2026)));
      AuthSession.use(null);
      expect(await p.act((FamilyAccountService s) => s.signOut()), isFalse);
      expect(p.signedOutCalls, 1);
      await Future<void>.delayed(Duration.zero);
      expect(recordAtRestart, isNull);
      expect(await p.record.load(), isNull);
    });

    test('a pending-join store that cannot be cleared does not stop the sign-out', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      final Phone p = Phone(server, pendingStore: _UnclearablePending());
      server.addAllowance(kCode);
      await p.act((FamilyAccountService s) =>
          s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
      expect(await p.act((FamilyAccountService s) => s.signOut()), isTrue);
      expect(await p.identities.load(), isNull);
    });
  });

  group('ISS-056: a lost "waiting" note does not trap a person who has joined', () {
    Future<({Phone inviter, AccountChild child, CreatedInvite invite})> invited(FakeIdentityServer server) async {
      final Phone inviter = Phone(server);
      server.addAllowance(kCode);
      await inviter.act((FamilyAccountService s) =>
          s.signUp(allowanceCode: kCode, displayName: 'Sam', homeTz: 'America/Chicago', pin: '4821'));
      final AccountChild child = await inviter.act((FamilyAccountService s) =>
          s.addChild(displayName: 'Ivy', birthDate: DateTime(2019, 3, 4), homeTz: 'America/Chicago', pin: '4821'));
      final CreatedInvite invite = await inviter.act((FamilyAccountService s) => s.createInvite(
          childId: child.id, role: 'guardian', label: 'Mama', email: 'robin@example.com', pin: '4821'));
      return (inviter: inviter, child: child, invite: invite);
    }

    test('the waiting save throws: the join still succeeds, and trying again resumes at waiting', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      final w = await invited(server);
      final _FlakyPending flaky = _FlakyPending(<int>{2}); // the 1st save ("accepted") works, the 2nd ("waiting") throws
      final Phone robin = Phone(server, pendingStore: flaky);
      await robin.act((FamilyAccountService s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      expect(await robin.identities.load(), isNotNull, reason: 'the account was made and the phone is signed in');
      expect((await flaky.load())!.stage, JoinStage.accepted);
      // The person taps Join again: signed in, with this very invite held -> carry on, do not refuse.
      server.requests.clear();
      await robin.act((FamilyAccountService s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      expect(server.requests, isEmpty, reason: 'nothing is sent again: the account is already made');
      expect((await flaky.load())!.stage, JoinStage.waiting);
      expect((await robin.record.load())!.stage, AccountStage.signedUp);
    });

    test('the first save (accepted) throwing once changes nothing for the join', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      final w = await invited(server);
      final _FlakyPending flaky = _FlakyPending(<int>{1});
      final Phone robin = Phone(server, pendingStore: flaky);
      await robin.act((FamilyAccountService s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      expect((await flaky.load())!.stage, JoinStage.waiting);
    });

    test('signed in with a DIFFERENT invite held, or none, is still refused', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      final w = await invited(server);
      final Phone robin = Phone(server);
      await robin.act((FamilyAccountService s) => s.joinAsNew(inviteCode: w.invite.code, displayName: 'Robin'));
      final CreatedInvite second = await w.inviter.act((FamilyAccountService s) => s.createInvite(
          childId: w.child.id, role: 'sitter', label: 'Jo', email: 'jo@example.com', pin: '4821'));
      Object? failure;
      try {
        await robin.act((FamilyAccountService s) => s.joinAsNew(inviteCode: second.code, displayName: 'Robin'));
      } on AccountFailure catch (e) {
        failure = e;
      }
      expect((failure as AccountFailure).problem.reason, 'already_signed_in');
    });

    test('an existing account claiming an invite: a failing waiting save does not report the claim as failed', () async {
      final FakeIdentityServer server = FakeIdentityServer();
      final w = await invited(server);
      final _FlakyPending flaky = _FlakyPending(<int>{1});
      final Phone sam2 = Phone(server, pendingStore: flaky);
      server.addAllowance('allowance-token-second-0123456789ab');
      await sam2.act((FamilyAccountService s) => s.signUp(
          allowanceCode: 'allowance-token-second-0123456789ab', displayName: 'Robin', homeTz: 'America/Chicago', pin: '4821'));
      server.users[(await sam2.identities.load())!.targetId]!.email = 'robin@example.com';
      await sam2.act((FamilyAccountService s) => s.useInviteWithAccount(w.invite.code));
      expect(flaky.saves, 1);
    });
  });

  group('ISS-052: a teen "stay in touch" choice that was not kept is put back', () {
    testWidgets('the switch returns to off and the existing snack bar says so', (WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final _FailingTouchRepo repo = _FailingTouchRepo(LocalServices(
              store: LocalStore(backend: MemoryStoreBackend(), cipher: _PlainCipher()),
              childId: 'c1', guardianId: 'g1', isLive: true, demoSeeds: false)
          .area('teen'));
      await t.pumpWidget(MaterialApp(
          home: GuardianHandoverScreen(childName: 'Ivy', guardianId: 'dad', monthDay: '12-09', repository: repo)));
      await t.pumpAndSettle();
      final Finder row = find.byKey(const Key('want.messages'));
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      bool on() => t.widget<CheckRow>(row).value;
      expect(on(), isFalse);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(repo.tries, 1);
      expect(on(), isFalse, reason: 'it did not save, so it must not look saved');
      expect(find.text("That couldn't be kept just now."), findsOneWidget);
    });
  });

  group('ISS-053: the family key is handed out only once it is kept', () {
    test('a repository whose save throws: ensureFamilyKey retries, then throws', () async {
      final _BrokenPictures repo = _BrokenPictures();
      final PairingPictureService svc = PairingPictureService(repo);
      await expectLater(svc.ensureFamilyKey(), throwsA(isA<FamilyKeyNotSaved>()));
      expect(repo.saves, greaterThanOrEqualTo(kFamilyKeySaveTries), reason: 'it tried again before giving up');
    });

    test('a save that does not stick (reads back without the key) is also an error', () async {
      final _BrokenPictures repo = _BrokenPictures(throwing: false);
      await expectLater(PairingPictureService(repo).ensureFamilyKey(), throwsA(isA<FamilyKeyNotSaved>()));
    });

    test('a store that fails once and then works keeps the key: the same key is returned next run', () async {
      final _FlakyPictures repo = _FlakyPictures();
      final PairingPictureService svc = PairingPictureService(repo);
      final Uint8List fk = await svc.ensureFamilyKey();
      expect(await PairingPictureService(repo).ensureFamilyKey(), fk);
    });

    testWidgets('the pairing screen shows the calm try-again card and seals and shares nothing', (WidgetTester t) async {
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      AdultWindow? opened;
      await t.pumpWidget(MaterialApp(
          home: ConnectChildScreen(
        pin: pin,
        deviceKeys: MemoryDeviceKeyRepository(),
        kids: MemoryPairedKidsRepository(),
        adultName: 'Mom',
        childName: 'Ivy',
        pictures: _BrokenPictures(),
        makeUnlockVerifier: (String p) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32)),
        localAddress: () async => '127.0.0.1',
        startHost: (AdultWindow w) async {
          opened = w;
          return _FakeHost();
        },
      )));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('connectOpen')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await t.pump();
      expect(opened, isNull, reason: 'no window was opened, so nothing was sealed or shared');
      expect(find.byKey(const Key('connectWaiting')), findsNothing);
      expect(find.textContaining('Nothing was shared'), findsOneWidget);
      expect(find.textContaining('Try again'), findsOneWidget);
    });

    test('the salt is still allowed to fail to save (a working state for this run)', () async {
      final _BrokenPictures repo = _BrokenPictures();
      final PairingPictureState s = await PairingPictureService(repo).state();
      expect(s.salt.length, 16);
    });
  });
}

class _FakeHost implements WindowHost {
  @override
  int? get port => 4242;
  @override
  Future<void> stop() async {}
  @override
  Future<void> readvertise() async {}
}

class _UnclearablePending implements PendingJoinStore {
  PendingJoin? _j;
  @override
  Future<PendingJoin?> load() async => _j;
  @override
  Future<void> save(PendingJoin join) async => _j = join;
  @override
  Future<void> clear() async => throw StateError('secure storage is busy');
}

/// The first save throws; later ones work.
class _FlakyPictures implements PairingPictureRepository {
  PairingPictureState? kept;
  int saves = 0;
  @override
  Future<PairingPictureState?> load() async => kept;
  @override
  Future<void> save(PairingPictureState state) async {
    if (++saves == 1) throw StateError('busy');
    kept = state;
  }
}
