// OLIVE BRANCH — lost_device_service.dart: a lost or stolen phone or tablet, against an in-memory server that answers like
// server/routes.mjs (test/support/lost_fake.dart) and checks every request against the REAL route table.
// MASTERFILE section 7.23. Covers mark, found, confirm, the erase order and its withdrawal, and the hostile cases: a
// wrong PIN, a stale answer after a second loss, a grown-up undoing the owner's own report, a child's tablet erased, a
// reply that is not the shape the server sends, a double tap, a lost connection.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/family_account_logic.dart';
import 'package:olive_client/lost_device_logic.dart';
import 'package:olive_client/lost_device_service.dart';

import 'support/account_rig.dart';
import 'support/fake_identity_server.dart';
import 'support/lost_fake.dart';

void main() {
  late DateTime clock;
  late FakeIdentityServer server;
  late LostFake lf;

  setUp(() {
    clock = DateTime.utc(2026, 11, 21, 12);
    server = FakeIdentityServer(now: () => clock);
    lf = LostFake(server);
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

  LostDeviceService svc(Phone p) =>
      LostDeviceService(baseUrl: kBase, account: p.service, client: server.client);

  Future<AccountFailure> failureOf(Future<Object?> f) async {
    try {
      await f;
    } on AccountFailure catch (e) {
      return e;
    }
    fail('expected an AccountFailure');
  }

  Future<({Phone mom, Phone dad, String momId, String dadId, FakeDev momOther, FakeDev tablet})> family() async {
    final Phone mom = await signedUp('Mom');
    final Phone dad = await signedUp('Dad', pin: '2468');
    final String momId = await userIdOf(mom), dadId = await userIdOf(dad);
    lf.names[momId] = 'Mom';
    lf.names[dadId] = 'Dad';
    final FakeDev other = lf.add('guardian', momId, 'Old phone', ownerName: 'Mom');
    final FakeDev tab = lf.add('child', 'child-1', 'Kitchen tablet');
    return (mom: mom, dad: dad, momId: momId, dadId: dadId, momOther: other, tablet: tab);
  }

  group('the list', () {
    test('every device the grown-up may see, in words, with only the actions that are true', () async {
      final f = await family();
      final List<FamilyDevice> list = await f.mom.act((_) => svc(f.mom).devices());
      final FamilyDevice mine = list.firstWhere((FamilyDevice d) => d.id == f.momOther.id);
      expect(mine.isOwn, isTrue);
      expect(mine.title, 'Your phone: Old phone');
      expect(mine.canMarkLost, isTrue);
      expect(mine.canOrderWipe, isFalse, reason: 'a working phone is never offered an erase');
      final FamilyDevice tab = list.firstWhere((FamilyDevice d) => d.id == f.tablet.id);
      expect(tab.isTablet, isTrue);
      expect(tab.canOrderWipe, isFalse);
    });

    test('no credential, token, hash or id ever reaches a sentence', () async {
      final f = await family();
      final List<FamilyDevice> list = await f.mom.act((_) => svc(f.mom).devices());
      for (final FamilyDevice d in list) {
        final String text = '${d.title} ${deviceStatusLine(d, clock)} ${wipeStatusLine(d) ?? ''}';
        expect(text, isNot(contains(d.id)));
        expect(text.toLowerCase(), isNot(matches(RegExp(r'token|credential|hash|session|revoke|encrypt'))));
      }
    });

    test('a reply that is not a list is "not sure it went through", never an empty list', () async {
      final f = await family();
      server.failNext = http.Response(jsonEncode(<String, Object>{'oops': true}), 200);
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).devices()));
      expect(e.problem.reason, 'unexpected_reply');
    });
  });

  group('mark, found, confirm', () {
    test('mark: own PIN only, the body is just the PIN, the device is paused and nothing else changes', () async {
      final f = await family();
      server.requests.clear();
      final DeviceActionResult r = await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
      expect(r.standing, DeviceStanding.paused);
      expect(r.incidentId, isNotNull);
      expect(server.requests.single.body.keys.toSet(), <String>{'pin'});
      expect(server.requests.single.hasAuth, isTrue);
      expect(f.momOther.state, 'paused');
      expect(f.tablet.state, 'active');
    });

    test('a wrong PIN says so in words and changes nothing', () async {
      final f = await family();
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '9999')));
      expect(e.problem.message, contains("isn't right"));
      expect(f.momOther.state, 'active');
    });

    test('a PIN that is not 4 to 8 digits never leaves the phone', () async {
      final f = await family();
      server.requests.clear();
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '12')));
      expect(e.problem.kind, ProblemKind.fixInput);
      expect(server.requests, isEmpty);
    });

    test('a device id that cannot be one never leaves the phone', () async {
      final f = await family();
      server.requests.clear();
      await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: '../../x', pin: '4821')));
      expect(server.requests, isEmpty);
    });

    test('found quotes the incident; a stale one after a second loss does nothing', () async {
      final f = await family();
      final DeviceActionResult m1 = await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
      await f.mom.act((_) => svc(f.mom).found(deviceId: f.momOther.id, incidentId: m1.incidentId!, pin: '4821'));
      expect(f.momOther.state, 'active');
      final DeviceActionResult m2 = await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
      expect(m2.incidentId, isNot(m1.incidentId));
      final AccountFailure e =
          await failureOf(f.mom.act((_) => svc(f.mom).found(deviceId: f.momOther.id, incidentId: m1.incidentId!, pin: '4821')));
      expect(e.problem.reason, 'stale_incident');
      expect(f.momOther.state, 'paused', reason: 'the old answer did not undo the new loss');
    });

    test('dad cannot undo mom\'s own report, and cannot make her phone final', () async {
      final f = await family();
      final DeviceActionResult m = await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
      final AccountFailure undo =
          await failureOf(f.dad.act((_) => svc(f.dad).found(deviceId: f.momOther.id, incidentId: m.incidentId!, pin: '2468')));
      expect(undo.problem.reason, 'owner_only');
      expect(undo.problem.message, contains('owner'));
      final AccountFailure fin =
          await failureOf(f.dad.act((_) => svc(f.dad).confirmLost(deviceId: f.momOther.id, incidentId: m.incidentId!, pin: '2468')));
      expect(fin.problem.reason, 'owner_only');
      expect(f.momOther.state, 'paused');
    });

    test('any grown-up may make a lost child\'s tablet final; mom may make her own phone final', () async {
      final f = await family();
      final DeviceActionResult t = await f.dad.act((_) => svc(f.dad).markLost(deviceId: f.tablet.id, pin: '2468'));
      final DeviceActionResult done =
          await f.mom.act((_) => svc(f.mom).confirmLost(deviceId: f.tablet.id, incidentId: t.incidentId!, pin: '4821'));
      expect(done.standing, DeviceStanding.revoked);
      final DeviceActionResult m = await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
      expect((await f.mom.act((_) => svc(f.mom).confirmLost(deviceId: f.momOther.id, incidentId: m.incidentId!, pin: '4821'))).standing,
          DeviceStanding.revoked);
    });

    test('after the cut-off, marking again or "I have it" is said in words, and nothing is deleted', () async {
      final f = await family();
      final DeviceActionResult m = await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
      await f.mom.act((_) => svc(f.mom).confirmLost(deviceId: f.momOther.id, incidentId: m.incidentId!, pin: '4821'));
      final AccountFailure again = await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821')));
      expect(again.problem.message, contains('Nothing was deleted'));
      final AccountFailure late =
          await failureOf(f.mom.act((_) => svc(f.mom).found(deviceId: f.momOther.id, incidentId: m.incidentId!, pin: '4821')));
      expect(late.problem.message, contains('added'));
    });

    test('an unknown device is "not on your list", the same for a stranger\'s', () async {
      final f = await family();
      final AccountFailure e = await failureOf(
          f.mom.act((_) => svc(f.mom).markLost(deviceId: '00000000-0000-4000-a000-ffffffffffff', pin: '4821')));
      expect(e.problem.reason, 'not_found');
    });
  });

  group('erase it when it connects', () {
    Future<void> lose(dynamic f) async {
      await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821'));
    }

    test('only after it was marked as lost, only by the owner, and only for a grown-up\'s phone', () async {
      final f = await family();
      final AccountFailure working = await failureOf(f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.momOther.id, pin: '4821')));
      expect(working.problem.reason, 'not_paused');
      expect(working.problem.message, contains('marked as lost'));
      await lose(f);
      final AccountFailure dad = await failureOf(f.dad.act((_) => svc(f.dad).orderWipe(deviceId: f.momOther.id, pin: '2468')));
      expect(dad.problem.reason, 'owner_only');
      expect(f.momOther.wipe, 'none');
      final DeviceActionResult ok = await f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.momOther.id, pin: '4821'));
      expect(ok.standing, DeviceStanding.paused);
      expect(f.momOther.wipe, 'ordered');
      // a child's tablet is never erased by a grown-up, however it is asked
      await f.mom.act((_) => svc(f.mom).markLost(deviceId: f.tablet.id, pin: '4821'));
      final AccountFailure tab = await failureOf(f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.tablet.id, pin: '4821')));
      expect(tab.problem.reason, 'not_a_grown_up_phone');
      expect(tab.problem.message, contains('hers'));
      expect(f.tablet.wipe, 'none');
    });

    test('asking twice is one order; it can be taken back; taking back what is not there is said plainly', () async {
      final f = await family();
      await lose(f);
      await f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.momOther.id, pin: '4821'));
      final DeviceActionResult twice = await f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.momOther.id, pin: '4821'));
      expect(twice.already, isTrue);
      await f.mom.act((_) => svc(f.mom).cancelWipe(deviceId: f.momOther.id, pin: '4821'));
      expect(f.momOther.wipe, 'none');
      final AccountFailure none = await failureOf(f.mom.act((_) => svc(f.mom).cancelWipe(deviceId: f.momOther.id, pin: '4821')));
      expect(none.problem.reason, 'no_wipe_ordered');
    });

    test('"I have it" withdraws an order that was not carried out; a phone that already erased cannot be found back', () async {
      final f = await family();
      await lose(f);
      final String inc = f.momOther.incident!;
      await f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.momOther.id, pin: '4821'));
      await f.mom.act((_) => svc(f.mom).found(deviceId: f.momOther.id, incidentId: inc, pin: '4821'));
      expect(f.momOther.wipe, 'none');
      await lose(f);
      final String inc2 = f.momOther.incident!;
      f.momOther.wipe = 'done'; // the phone reported it had erased itself
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).found(deviceId: f.momOther.id, incidentId: inc2, pin: '4821')));
      expect(e.problem.reason, 'already_wiped');
      expect(e.problem.message, contains('added'));
    });

    test('the list offers "erase" only to the owner of a lost phone, and "cancel" only while it is waiting', () async {
      final f = await family();
      await lose(f);
      FamilyDevice mine(List<FamilyDevice> l) => l.firstWhere((FamilyDevice d) => d.id == f.momOther.id);
      expect(mine(await f.mom.act((_) => svc(f.mom).devices())).canOrderWipe, isTrue);
      expect(mine(await f.dad.act((_) => svc(f.dad).devices())).canOrderWipe, isFalse);
      await f.mom.act((_) => svc(f.mom).orderWipe(deviceId: f.momOther.id, pin: '4821'));
      final FamilyDevice waiting = mine(await f.mom.act((_) => svc(f.mom).devices()));
      expect(waiting.canOrderWipe, isFalse);
      expect(waiting.canCancelWipe, isTrue);
      expect(wipeStatusLine(waiting), contains('Waiting to erase'));
      f.momOther.wipe = 'done';
      final FamilyDevice done = mine(await f.mom.act((_) => svc(f.mom).devices()));
      expect(done.canCancelWipe, isFalse);
      expect(wipeStatusLine(done), contains('safe'));
    });
  });

  group('trouble in the post', () {
    test('a double tap on "Mark as lost" is one request', () async {
      final f = await family();
      server.requests.clear();
      final LostDeviceService s = svc(f.mom);
      final List<DeviceActionResult> both = await f.mom.act((_) => Future.wait(<Future<DeviceActionResult>>[
            s.markLost(deviceId: f.momOther.id, pin: '4821'),
            s.markLost(deviceId: f.momOther.id, pin: '4821'),
          ]));
      expect(both.first.incidentId, both.last.incidentId);
      expect(server.requests.where((RecordedRequest r) => r.path.endsWith('/mark-lost')).length, 1);
    });

    test('a lost connection is "not sure it went through", with advice to look again, never a success', () async {
      final f = await family();
      server.interceptor = (http.BaseRequest r) async => throw const SocketException('no route');
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821')));
      expect(e.problem.reason, 'network');
      expect(e.problem.message, contains('look again'));
    });

    test('an answer in the wrong shape is not a success', () async {
      final f = await family();
      server.failNext = http.Response(jsonEncode(<String, Object>{'state': 'paused'}), 201);
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821')));
      expect(e.problem.reason, 'unexpected_reply');
    });

    test('a server error is worded, and no status or code is in it', () async {
      final f = await family();
      server.failNext = http.Response(jsonEncode(<String, Object>{'error': 'boom'}), 503);
      final AccountFailure e = await failureOf(f.mom.act((_) => svc(f.mom).markLost(deviceId: f.momOther.id, pin: '4821')));
      expect(e.problem.message, isNot(matches(RegExp(r'503|boom'))));
    });

    test('a signed-out phone is told to sign in, in words', () async {
      final Phone nobody = Phone(server);
      final AccountFailure e = await failureOf(nobody.act((_) => svc(nobody).devices()));
      expect(e.problem.kind, ProblemKind.needsSignIn);
    });
  });
}
