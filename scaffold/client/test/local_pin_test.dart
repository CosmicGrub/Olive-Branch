// OLIVE BRANCH — local_pin.dart tests: the LOCAL guardian PIN as a salted slow hash, a
// constant-time compare and a 5-attempt / 15-minute lockout. No longer UNVERIFIED — verified by
// CI. MASTERFILE §8.5.9.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

class Clock {
  DateTime now = DateTime.utc(2026, 11, 8, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// A repository whose writes can be switched off, to prove an unwritable store is no way round the lockout.
class _FlakyRepo implements LocalPinRepository {
  LocalPinRecord? record;
  bool failWrites = false;
  int saves = 0;
  @override
  Future<LocalPinRecord?> load() async => record;
  @override
  Future<void> save(LocalPinRecord r) async {
    if (failWrites) throw const LocalStoreFull('x', 1);
    saves++;
    record = r;
  }

  @override
  Future<void> clear() async => record = null;
}

LocalPinService svc(LocalPinRepository repo, Clock clock, {int iterations = 1000}) =>
    LocalPinService(repo, now: clock.call, iterations: iterations, random: Random(7));

void main() {
  group('what is stored', () {
    test('the PIN itself is never stored: not in the record, not in the JSON, not in the sealed file', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'x', backend: backend);
      final LocalPinService service = LocalPinService(
          LocalStoreLocalPinRepository(s.area('localpin', ownerId: kLocalGuardianScope)), iterations: 1000);
      await service.setPin('480516');
      final Object? raw = await s.area('localpin', ownerId: kLocalGuardianScope).get('pin');
      final String json = jsonEncode(raw);
      expect(json, isNot(contains('480516')));
      expect(json, contains('pbkdf2-hmac-sha256'));
      final Map<Object?, Object?> m = raw! as Map<Object?, Object?>;
      expect(base64.decode(m['salt']! as String).length, 16);
      expect(base64.decode(m['hash']! as String).length, 32);
      expect(m['iter'], 1000);
      // The area is sealed on the device as well.
      expect(s.area('localpin', ownerId: kLocalGuardianScope).spec.encrypted, isTrue);
      expect(s.area('localpin', ownerId: kLocalGuardianScope).spec.name, 'guardian.local-guardian.localpin');
      final String onDisk = utf8.decode(await backend.read('guardian.local-guardian.localpin') ?? <int>[], allowMalformed: true);
      expect(onDisk, isNot(contains('480516')));
      expect(onDisk, isNot(contains('pbkdf2')), reason: 'sealed: even the algorithm name is not readable');
    });

    test('a fresh random salt each time: the same PIN set twice gives two different hashes', () async {
      final _FlakyRepo a = _FlakyRepo(), b = _FlakyRepo();
      final Clock c = Clock();
      await LocalPinService(a, now: c.call, iterations: 500).setPin('1234');
      await LocalPinService(b, now: c.call, iterations: 500).setPin('1234');
      expect(a.record!.salt, isNot(equals(b.record!.salt)));
      expect(a.record!.hash, isNot(equals(b.record!.hash)));
    });

    test('the number of rounds is remembered with the hash, so an old PIN still checks after the default changes', () async {
      final _FlakyRepo repo = _FlakyRepo();
      final Clock c = Clock();
      await LocalPinService(repo, now: c.call, iterations: 700).setPin('2468');
      // A new service with a different default for NEW pins:
      final LocalPinService later = LocalPinService(repo, now: c.call, iterations: 5000);
      expect((await later.verify('2468')).ok, isTrue);
      expect((await later.verify('2469')).outcome, PinOutcome.wrong);
    });

    test('production rounds run in a background isolate and give the same bytes as the inline hash', () async {
      expect(kLocalPinIterations, greaterThanOrEqualTo(kLocalPinOffThreadRounds));
      final _FlakyRepo repo = _FlakyRepo();
      final LocalPinService service = LocalPinService(repo, random: Random(3)); // default rounds: the isolate path
      await service.setPin('480516');
      final LocalPinRecord rec = repo.record!;
      expect(rec.iterations, kLocalPinIterations);
      // Same function, run right here on this isolate: byte-identical (deterministic, not isolate-dependent).
      expect(await localPinDerive('480516', rec.salt, rec.iterations), rec.hash);
      expect((await service.verify('480516')).ok, isTrue);
      expect((await service.verify('480517')).outcome, PinOutcome.wrong);
    });

    test('small test rounds stay inline (a widget test fake clock cannot await an isolate)', () async {
      expect(1000, lessThan(kLocalPinOffThreadRounds));
      final _FlakyRepo repo = _FlakyRepo();
      await LocalPinService(repo, iterations: 1000, random: Random(3)).setPin('1357');
      expect(repo.record!.hash, await localPinDerive('1357', repo.record!.salt, 1000));
    });

    test('the default is a slow hash, not a fast one', () {
      expect(kLocalPinIterations, greaterThanOrEqualTo(100000));
    });

    test('the record decodes fail-closed: anything unexpected is "no PIN", never a PIN that accepts anything', () {
      expect(LocalPinRecord.fromJson(null), isNull);
      expect(LocalPinRecord.fromJson('x'), isNull);
      expect(LocalPinRecord.fromJson(<String, Object?>{}), isNull);
      expect(LocalPinRecord.fromJson(<String, Object?>{'v': 2, 'algo': 'pbkdf2-hmac-sha256'}), isNull);
      expect(LocalPinRecord.fromJson(<String, Object?>{
        'v': 1, 'algo': 'plain', 'iter': 1, 'salt': base64.encode(List<int>.filled(16, 1)),
        'hash': base64.encode(List<int>.filled(32, 1)),
      }), isNull);
      expect(LocalPinRecord.fromJson(<String, Object?>{
        'v': 1, 'algo': 'pbkdf2-hmac-sha256', 'iter': 1, 'salt': '!!!', 'hash': '!!!',
      }), isNull);
      expect(LocalPinRecord.fromJson(<String, Object?>{
        'v': 1, 'algo': 'pbkdf2-hmac-sha256', 'iter': 1, 'salt': base64.encode(List<int>.filled(16, 1)),
        'hash': base64.encode(List<int>.filled(5, 1)),
      }), isNull, reason: 'a short hash is not a hash');
    });
  });

  group('setting and checking', () {
    test('a PIN is 4 to 8 digits; anything else is refused', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      for (final String bad in <String>['', '123', '123456789', 'abcd', '12 34', '12.34', '１２３４']) {
        await expectLater(s.setPin(bad), throwsArgumentError, reason: '"$bad"');
      }
      expect(await s.isSet(), isFalse);
      for (final String ok in <String>['1234', '00000', '12345678']) {
        await s.setPin(ok);
        expect((await s.verify(ok)).ok, isTrue, reason: ok);
      }
    });

    test('the right PIN checks out; a wrong one does not; before any PIN is set the answer is notSet', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      expect((await s.verify('1234')).outcome, PinOutcome.notSet);
      expect(await s.isSet(), isFalse);
      await s.setPin('1234');
      expect(await s.isSet(), isTrue);
      expect((await s.verify('1234')).ok, isTrue);
      expect((await s.verify('1235')).outcome, PinOutcome.wrong);
      expect(await s.verifyBool('1234'), isTrue);
      expect(await s.verifyBool('9999'), isFalse);
    });

    test('a badly shaped guess is simply wrong (and counts), never an error', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      await s.setPin('1234');
      for (final String g in <String>['', 'abcd', '12', '1234567890']) {
        expect((await s.verify(g)).outcome, PinOutcome.wrong, reason: '"$g"');
      }
    });

    test('changing the PIN needs the current one; the old one stops working', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      await s.setPin('1111');
      expect((await s.change('0000', '2222')).outcome, PinOutcome.wrong);
      expect((await s.verify('2222')).outcome, PinOutcome.wrong, reason: 'a failed change changes nothing');
      expect((await s.change('1111', '2222')).ok, isTrue);
      expect((await s.verify('1111')).outcome, PinOutcome.wrong);
      expect((await s.verify('2222')).ok, isTrue);
    });

    test('clear removes it', () async {
      final _FlakyRepo repo = _FlakyRepo();
      final LocalPinService s = svc(repo, Clock());
      await s.setPin('1234');
      await s.clear();
      expect(await s.isSet(), isFalse);
      expect(repo.record, isNull);
    });
  });

  group('constant-time compare', () {
    test('equal and unequal byte lists, including different lengths', () {
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[1, 2, 3]), isTrue);
      expect(constantTimeEquals(<int>[], <int>[]), isTrue);
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[1, 2, 4]), isFalse);
      expect(constantTimeEquals(<int>[0, 2, 3], <int>[1, 2, 3]), isFalse);
      expect(constantTimeEquals(<int>[1, 2, 3], <int>[1, 2]), isFalse);
      expect(constantTimeEquals(<int>[1, 2], <int>[1, 2, 0]), isFalse, reason: 'a padded zero is still a different length');
    });

    test('it never short-circuits: the source has no early return inside the comparison loop', () {
      // The comparison accumulates the difference and decides once, at the end.
      final String src = _libSource('local_pin.dart');
      final String fn = src.substring(src.indexOf('bool constantTimeEquals('), src.indexOf('class LocalPinRecord'));
      expect(fn, contains('diff |='));
      expect(fn, isNot(contains('return false')));
      expect(fn, isNot(contains('break')));
    });

    test('verify uses it (and never ==) on the derived hash', () {
      final String src = _libSource('local_pin.dart');
      expect(src, contains('constantTimeEquals(got, rec.hash)'));
      expect(src, isNot(contains('got == rec.hash')));
    });
  });

  group('lockout: 5 wrong tries lock it for 15 minutes, in the server\'s words', () {
    test('the wording is the server\'s', () {
      expect(kLocalPinLockedMessage, 'Too many wrong tries. Try again in 15 minutes.');
      expect(kLocalPinMaxAttempts, 5);
      expect(kLocalPinLockout, const Duration(minutes: 15));
    });

    test('attempts left count down, and the fifth wrong try locks', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      await s.setPin('1234');
      for (int left = 4; left >= 1; left--) {
        final PinCheck r = await s.verify('0000');
        expect(r.outcome, PinOutcome.wrong);
        expect(r.attemptsLeft, left);
      }
      final PinCheck fifth = await s.verify('0000');
      expect(fifth.outcome, PinOutcome.locked);
      expect(fifth.lockedFor, const Duration(minutes: 15));
      expect(await s.lockedFor(), const Duration(minutes: 15));
    });

    test('while locked even the RIGHT PIN is refused, and nothing is counted', () async {
      final Clock c = Clock();
      final LocalPinService s = svc(_FlakyRepo(), c);
      await s.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await s.verify('0000');
      }
      c.advance(const Duration(minutes: 14, seconds: 59));
      final PinCheck r = await s.verify('1234');
      expect(r.outcome, PinOutcome.locked);
      expect(r.lockedFor, const Duration(seconds: 1));
    });

    test('after 15 minutes it opens again, with a fresh count of five', () async {
      final Clock c = Clock();
      final LocalPinService s = svc(_FlakyRepo(), c);
      await s.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await s.verify('0000');
      }
      c.advance(kLocalPinLockout);
      expect(await s.lockedFor(), isNull);
      final PinCheck wrong = await s.verify('0000');
      expect(wrong.outcome, PinOutcome.wrong);
      expect(wrong.attemptsLeft, 4, reason: 'the count starts again at zero when a lock is imposed (as on the server)');
      expect((await s.verify('1234')).ok, isTrue);
    });

    test('a correct PIN resets the count', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      await s.setPin('1234');
      for (int i = 0; i < 4; i++) {
        await s.verify('0000');
      }
      expect((await s.verify('1234')).ok, isTrue);
      expect((await s.verify('0000')).attemptsLeft, 4);
    });

    test('the lock survives a restart (the counter is stored, not just remembered)', () async {
      final _FlakyRepo repo = _FlakyRepo();
      final Clock c = Clock();
      final LocalPinService first = svc(repo, c);
      await first.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await first.verify('0000');
      }
      final LocalPinService second = svc(repo, c); // a new process over the same store
      expect((await second.verify('1234')).outcome, PinOutcome.locked);
      c.advance(const Duration(minutes: 16));
      expect((await second.verify('1234')).ok, isTrue);
    });

    test('wrong tries toward the lock also survive a restart', () async {
      final _FlakyRepo repo = _FlakyRepo();
      final Clock c = Clock();
      final LocalPinService first = svc(repo, c);
      await first.setPin('1234');
      await first.verify('0000');
      await first.verify('0000');
      final LocalPinService second = svc(repo, c);
      expect((await second.verify('0000')).attemptsLeft, 2);
    });

    test('a store that cannot be written is NOT a way to try forever during one run', () async {
      final _FlakyRepo repo = _FlakyRepo();
      final Clock c = Clock();
      final LocalPinService s = svc(repo, c);
      await s.setPin('1234');
      repo.failWrites = true;
      PinCheck last = const PinCheck(PinOutcome.wrong);
      for (int i = 0; i < 5; i++) {
        last = await s.verify('0000');
      }
      expect(last.outcome, PinOutcome.locked);
      expect((await s.verify('1234')).outcome, PinOutcome.locked);
    });

    test('setting a new PIN clears a lock and the count (a deliberate act by whoever passed the gate)', () async {
      final LocalPinService s = svc(_FlakyRepo(), Clock());
      await s.setPin('1234');
      for (int i = 0; i < 5; i++) {
        await s.verify('0000');
      }
      await s.setPin('5678');
      expect(await s.lockedFor(), isNull);
      expect((await s.verify('5678')).ok, isTrue);
    });
  });

  group('it is not the server PIN', () {
    test('nothing in local_pin.dart or local_pin_screens.dart talks to a server', () {
      for (final String f in <String>['local_pin.dart', 'local_pin_screens.dart', 'local_family.dart']) {
        final String src = _libSource(f);
        for (final String bad in <String>['api_client', 'package:http', 'apiFor(', '/v1/me', 'AuthSession']) {
          expect(src, isNot(contains(bad)), reason: '$f must not touch $bad');
        }
      }
    });
  });
}

String _libSource(String name) => File('lib/$name')
    .readAsStringSync()
    .split('\n')
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');
