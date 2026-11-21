// OLIVE BRANCH — the lost-phone logic with no screens: how a device row is read, how a lost phone remembers it (the local
// auto-lock across a restart), what an erase order does and refuses, and what a child's tablet does NOT do. Verified by
// CI, headless. The server half is server/test/lost_device_route.test.mjs and lost_device_erase_route.test.mjs.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/auth_session.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/device_standing.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/lost_device_boot.dart';
import 'package:olive_client/lost_device_logic.dart';

class _BrokenStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('keystore locked');
  @override
  Future<void> write(String key, String value) async => throw StateError('keystore locked');
  @override
  Future<void> delete(String key) async => throw StateError('keystore locked');
}

class _MemStore implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});

Map<String, Object?> _row(String id, {String role = 'guardian', String state = 'active', Map<String, Object?> more = const <String, Object?>{}}) =>
    <String, Object?>{'id': id, 'role': role, 'label': 'Phone', 'state': state, ...more};

void main() {
  tearDown(DeviceStanding.reset);

  group('reading what the server sends', () {
    test('a row is read; a malformed one is dropped, never half shown', () {
      final List<FamilyDeviceView> l = FamilyDeviceView.listFromJson(<String, Object?>{
        'devices': <Object?>[
          _row('a', more: <String, Object?>{'ownerName': 'Alex', 'canMarkLost': true}),
          <String, Object?>{'id': 'b', 'role': 'guardian', 'state': 'exploded'},
          <String, Object?>{'role': 'guardian', 'state': 'active'},
          'nonsense',
          null,
        ],
      });
      expect(l.map((FamilyDeviceView d) => d.id), <String>['a']);
      expect(l.single.canMarkLost, isTrue);
      expect(l.single.displayName(), "Alex's phone");
      expect(FamilyDeviceView.listFromJson(<String, Object?>{'devices': 'x'}), isEmpty);
      expect(FamilyDeviceView.listFromJson(null), isEmpty);
    });

    test('a tablet is NEVER offered an erase, whatever the server said', () {
      final FamilyDeviceView t = FamilyDeviceView.fromJson(_row('t', role: 'child', state: 'paused',
          more: <String, Object?>{'canOrderErase': true, 'canCancelErase': true, 'incidentId': 'i'}))!;
      expect(t.isChild, isTrue);
      expect(t.canOrderErase, isFalse);
      expect(t.canCancelErase, isFalse);
      final FamilyDeviceView p = FamilyDeviceView.fromJson(_row('p', state: 'paused',
          more: <String, Object?>{'canOrderErase': true, 'canCancelErase': true, 'incidentId': 'i'}))!;
      expect(p.canOrderErase, isTrue);
      expect(p.canCancelErase, isTrue);
    });

    test('dates are read; a date that is not a date is just absent', () {
      final FamilyDeviceView d = FamilyDeviceView.fromJson(_row('d', state: 'paused', more: <String, Object?>{
        'revokeDueAt': '2026-11-24T12:00:00.000Z', 'eraseDueAt': 'not a date'}))!;
      expect(d.revokeDueAt!.toUtc(), DateTime.utc(2026, 11, 24, 12));
      expect(d.eraseDueAt, isNull);
    });
  });

  group('the local auto-lock: the standing survives a restart', () {
    test('paused is kept and read back before any network call', () async {
      final _MemStore secure = _MemStore();
      await DeviceStanding.restore(DeviceStandingStore(secure));
      DeviceStanding.set(DeviceStandingState.paused);
      await Future<void>.delayed(Duration.zero);
      // a "restart": the same secure storage, a new process-wide state
      final DeviceStandingStore kept = DeviceStandingStore(secure);
      DeviceStanding.state.value = DeviceStandingState.active;
      expect(await kept.load(), DeviceStandingState.paused);
      DeviceStanding.store = null;
      await DeviceStanding.restore(kept);
      expect(DeviceStanding.value, DeviceStandingState.paused, reason: 'covered before it asked anybody');
    });

    test('every standing round-trips as one word, and an unreadable word fails OPEN (the owner is never locked out for good by garbage)', () {
      for (final DeviceStandingState s in DeviceStandingState.values) {
        expect(standingFromWord(standingWord(s)), s);
      }
      expect(standingFromWord('garbage'), DeviceStandingState.active);
      expect(standingFromWord(42), DeviceStandingState.active);
      expect(standingFromWord(null), DeviceStandingState.active);
    });

    test('brought back clears the kept word, so the next start is normal', () async {
      final DeviceStandingStore st = DeviceStandingStore(_MemStore());
      await DeviceStanding.restore(st);
      DeviceStanding.set(DeviceStandingState.paused);
      await Future<void>.delayed(Duration.zero);
      DeviceStanding.set(DeviceStandingState.active);
      await Future<void>.delayed(Duration.zero);
      expect(await st.load(), DeviceStandingState.active);
    });

    test('an erased phone stays erased: a later "paused" or "cut off" cannot change it, only adding the phone again does', () async {
      DeviceStanding.set(DeviceStandingState.erased);
      DeviceStanding.set(DeviceStandingState.paused);
      DeviceStanding.set(DeviceStandingState.cutOff);
      DeviceStanding.set(DeviceStandingState.active);
      expect(DeviceStanding.value, DeviceStandingState.erased);
      DeviceStanding.addedAgain();
      expect(DeviceStanding.value, DeviceStandingState.active);
    });

    test('a broken secure storage never stops the lock itself (the in-memory standing still covers the app)', () async {
      await DeviceStanding.restore(DeviceStandingStore(_BrokenStore()));
      DeviceStanding.set(DeviceStandingState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(DeviceStanding.value, DeviceStandingState.paused);
    });
  });

  group('erase on next contact: what a lost grown-up phone does', () {
    late List<String> calls;
    late LostPhoneCoordinator Function({List<bool> acks, bool wipeFails}) make;

    setUp(() {
      calls = <String>[];
      make = ({List<bool> acks = const <bool>[true], bool wipeFails = false}) {
        int i = 0;
        return LostPhoneCoordinator(
          wipeLocal: () async {
            calls.add('wipe');
            if (wipeFails) throw StateError('disk');
          },
          tellServer: (String id, String cred) async {
            calls.add('tell:$id');
            final bool ok = acks[i < acks.length ? i : acks.length - 1];
            i++;
            return ok;
          },
          clearIdentity: () async => calls.add('forget'),
        );
      };
    });

    test('it wipes, remembers "erased", tells the server, then forgets its own sign-in, in that order', () async {
      final LostPhoneCoordinator c = make();
      expect(await c.erase('dev', 'cred'), isTrue);
      expect(calls, <String>['wipe', 'tell:dev', 'forget']);
      expect(DeviceStanding.value, DeviceStandingState.erased);
    });

    test('a failed wipe tells nobody and forgets nothing (it never says "done" for something it did not do)', () async {
      final LostPhoneCoordinator c = make(wipeFails: true);
      await expectLater(c.erase('dev', 'cred'), throwsStateError);
      expect(calls, <String>['wipe']);
      expect(DeviceStanding.value, isNot(DeviceStandingState.erased));
    });

    test('no signal: it keeps its sign-in so it can tell the server later, and tries three times, no more', () async {
      final LostPhoneCoordinator c = make(acks: <bool>[false]);
      await c.erase('dev', 'cred');
      expect(calls, <String>['wipe', 'tell:dev', 'tell:dev', 'tell:dev']);
      expect(calls, isNot(contains('forget')));
      expect(DeviceStanding.value, DeviceStandingState.erased);
      // the next start tries again, and this time it gets through
      calls.clear();
      final LostPhoneCoordinator later = make(acks: <bool>[true]);
      await later.retryTelling('dev', 'cred');
      expect(calls, <String>['tell:dev', 'forget']);
    });

    test('REPLAY: hearing the word again after it erased does not wipe a second time, it only tries to tell the server', () async {
      final LostPhoneCoordinator c = make(acks: <bool>[false]);
      await c.erase('dev', 'cred');
      calls.clear();
      await c.heardErase('dev', 'cred');
      expect(calls.where((String x) => x == 'wipe'), isEmpty);
      expect(calls.where((String x) => x.startsWith('tell')), isNotEmpty);
    });

    test('RACE: two contacts hearing the word at the same instant wipe once', () async {
      final LostPhoneCoordinator c = make();
      final List<bool> r = await Future.wait(<Future<bool>>[c.erase('dev', 'cred'), c.erase('dev', 'cred')]);
      expect(r.where((bool b) => b), hasLength(1));
      expect(calls.where((String x) => x == 'wipe'), hasLength(1));
    });

    test('a phone that was never erased does not "retry telling" anything', () async {
      final LostPhoneCoordinator c = make();
      await c.retryTelling('dev', 'cred');
      await c.retryTelling(null, null);
      expect(calls, isEmpty);
    });
  });

  group('AuthSession: what a phone does with the words from the server', () {
    final DateTime t0 = DateTime.utc(2026, 11, 20, 12);
    late _MemStore storage;
    late DeviceIdentityStore ids;
    late List<String> hookCalls;

    setUp(() {
      storage = _MemStore();
      ids = DeviceIdentityStore(storage: storage);
      hookCalls = <String>[];
      AuthSession.use(null);
    });
    tearDown(() {
      AuthSession.use(null);
      AuthSession.devLoginEnabled = true;
    });

    DeviceIdentity identity(String role) => DeviceIdentity(
        sessionToken: 'x.y', deviceId: 'dev-1', role: role, targetId: 't-1', deviceCredential: 'cred-1');

    AuthSession session(http.Client c, String role) => AuthSession.device(
        baseUrl: 'http://api.test', identity: identity(role), store: ids, client: c, now: () => t0);

    test('paused: the app is covered, nothing is cleared, and the phone does not keep asking', () async {
      int asks = 0;
      final AuthSession s = session(MockClient((http.Request r) async {
        asks++;
        return _json(401, <String, dynamic>{'error': 'device_paused'});
      }), 'guardian');
      await ids.save(identity('guardian'));
      await expectLater(s.refresh(), throwsA(isA<Exception>()));
      expect(DeviceStanding.value, DeviceStandingState.paused);
      expect((await ids.load()), isNotNull, reason: 'nothing is cleared');
      final int before = asks;
      await expectLater(s.token(), throwsA(isA<Exception>()));
      expect(asks, before, reason: 'a paused phone does not hammer the server');
    });

    test('brought back: it must show its owner PIN once, and the PIN travels only inside the refresh body', () async {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
      final AuthSession s = session(MockClient((http.Request r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        if (bodies.last['pin'] == null) return _json(403, <String, dynamic>{'error': 'pin_required'});
        return _json(200, <String, dynamic>{'sessionToken': 'new.tok'});
      }), 'guardian');
      await s.checkBack();
      expect(DeviceStanding.value, DeviceStandingState.needsOwnerPin);
      await s.checkBack(ownerPin: '4821');
      expect(DeviceStanding.value, DeviceStandingState.active);
      expect(bodies.last['pin'], '4821');
      expect(bodies.last.keys.toSet(), <String>{'deviceId', 'deviceCredential', 'pin'});
    });

    test('cut off: the standing says so and the sign-in is cleared as before (a real revoke, never a voluntary sign-out)', () async {
      final AuthSession s = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'device_revoked'})), 'guardian');
      await ids.save(identity('guardian'));
      await expectLater(s.refresh(), throwsA(isA<DeviceRevokedException>()));
      expect(DeviceStanding.value, DeviceStandingState.cutOff);
      expect(await ids.load(), isNull);
    });

    test('the erase word on a GROWN-UP phone reaches the hook with the device id and credential, before the sign-in is cleared', () async {
      DeviceStanding.onEraseOrdered = (String id, String cred) async {
        hookCalls.add('$id/$cred/identityStillThere=${await ids.load() != null}');
      };
      final AuthSession s = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'device_revoked', 'wipe': true})), 'guardian');
      await ids.save(identity('guardian'));
      await expectLater(s.refresh(), throwsA(isA<DeviceRevokedException>()));
      expect(hookCalls, <String>['dev-1/cred-1/identityStillThere=true']);
    });

    test('...on a paused phone too', () async {
      DeviceStanding.onEraseOrdered = (String id, String cred) async => hookCalls.add(id);
      final AuthSession s = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'device_paused', 'wipe': true})), 'guardian');
      await expectLater(s.refresh(), throwsA(isA<Exception>()));
      expect(hookCalls, <String>['dev-1']);
    });

    test('A CHILD\'S TABLET IGNORES THE ERASE WORD: no hook is called, nothing is erased, and it shows no standing change it cannot hide', () async {
      DeviceStanding.onEraseOrdered = (String id, String cred) async => hookCalls.add(id);
      final AuthSession s = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'device_paused', 'wipe': true})), 'child');
      await expectLater(s.refresh(), throwsA(isA<Exception>()));
      expect(hookCalls, isEmpty);
    });

    test('a hook that fails does not stop the cut-off', () async {
      DeviceStanding.onEraseOrdered = (String id, String cred) async => throw StateError('disk full');
      final AuthSession s = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'device_revoked', 'wipe': true})), 'guardian');
      await ids.save(identity('guardian'));
      await expectLater(s.refresh(), throwsA(isA<DeviceRevokedException>()));
      expect(await ids.load(), isNull);
    });

    test('the word "wipe: true" with any other error is ignored (only a lost phone is told)', () async {
      DeviceStanding.onEraseOrdered = (String id, String cred) async => hookCalls.add(id);
      final AuthSession s = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'invalid_device_credential', 'wipe': true})), 'guardian');
      await ids.save(identity('guardian'));
      await expectLater(s.refresh(), throwsA(isA<Exception>()));
      expect(hookCalls, isEmpty);
    });

    test('sayErased posts only the device id and credential, no session, and says false (never throws) with no signal', () async {
      http.Request? seen;
      final AuthSession ok = session(MockClient((http.Request r) async {
        seen = r;
        return _json(200, <String, dynamic>{'erased': true});
      }), 'guardian');
      expect(await ok.sayErased('dev-1', 'cred-1'), isTrue);
      expect(seen!.url.path, '/v1/auth/session/erased');
      expect(seen!.headers['authorization'], isNull);
      expect(jsonDecode(seen!.body), <String, dynamic>{'deviceId': 'dev-1', 'deviceCredential': 'cred-1'});
      final AuthSession down = session(MockClient((http.Request r) async => throw http.ClientException('offline')), 'guardian');
      expect(await down.sayErased('dev-1', 'cred-1'), isFalse);
      final AuthSession no = session(MockClient((http.Request r) async => _json(401, <String, dynamic>{'error': 'invalid_device_credential'})), 'guardian');
      expect(await no.sayErased('dev-1', 'cred-1'), isFalse);
    });
  });

  group('startLostDeviceWatch: wired for a grown-up phone', () {
    test('it reads the kept standing back and installs the erase hook', () async {
      final LocalServices a = LocalServices.memory();
      final _MemStore secure = _MemStore();
      await DeviceStandingStore(secure).save(DeviceStandingState.paused);
      await startLostDeviceWatch(a, identityStore: DeviceIdentityStore(storage: _MemStore()), secure: secure);
      expect(DeviceStanding.value, DeviceStandingState.paused);
      expect(DeviceStanding.onEraseOrdered, isNotNull);
    });

    test('an erase wipes the real on-device store and the key that opens it, and keeps only the word "erased" (in secure storage, which the wipe does not touch)', () async {
      final LocalServices a = LocalServices.memory();
      await a.area('coordination').put('dose', 'x');
      await a.area('journal').put('entry', 'private');
      final _MemStore mem = _MemStore();
      final DeviceIdentityStore ids = DeviceIdentityStore(storage: mem);
      await ids.save(DeviceIdentity(sessionToken: 'x.y', deviceId: 'dev-1', role: 'guardian', targetId: 'g', deviceCredential: 'cred-1'));
      final _MemStore secure = _MemStore();
      await startLostDeviceWatch(a, identityStore: ids, secure: secure);
      await DeviceStanding.onEraseOrdered!('dev-1', 'cred-1');
      expect(await a.area('coordination').get('dose'), isNull);
      expect(await a.area('journal').get('entry'), isNull);
      expect(DeviceStanding.value, DeviceStandingState.erased);
      expect(await DeviceStandingStore(secure).load(), DeviceStandingState.erased);
      // no signal in this test (no AuthSession installed): it kept its sign-in to tell the server later
      expect(await ids.load(), isNotNull);
    });
  });
}
