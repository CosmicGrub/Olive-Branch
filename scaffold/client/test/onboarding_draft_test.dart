// OLIVE BRANCH — onboarding_draft.dart tests: the pairing-last first run's
// local draft, its delivery through the new session, and its retry. No longer
// UNVERIFIED — verified by CI. MASTERFILE §8.5.6.
//
// Pure logic, no widgets: every path below is a real assertion about what is
// kept, what is sent, and what is never lost.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/onboarding_draft.dart';

const OnboardingDraft _done = OnboardingDraft(
    name: 'Ivy', age: 7, gender: 'girl', colourId: 'teal',
    birthdayMonth: 3, birthdayDay: 14, complete: true);

void main() {
  group('the draft', () {
    test('round-trips every answer', () {
      final OnboardingDraft back = OnboardingDraft.fromJson(_done.toJson());
      expect(back.name, 'Ivy');
      expect(back.age, 7);
      expect(back.gender, 'girl');
      expect(back.colourId, 'teal');
      expect(back.birthdayMonth, 3);
      expect(back.birthdayDay, 14);
      expect(back.complete, isTrue);
    });

    test('skipped answers are absent, never invented', () {
      const OnboardingDraft skipped = OnboardingDraft(complete: true);
      expect(skipped.toJson(), <String, Object?>{'complete': true});
      final OnboardingDraft back = OnboardingDraft.fromJson(skipped.toJson());
      expect(back.name, isNull);
      expect(back.gender, isNull);
    });

    test('decoding fails closed: a wrong-typed or unknown value is dropped', () {
      final OnboardingDraft d = OnboardingDraft.fromJson(<String, Object?>{
        'name': 5, 'age': '7', 'gender': 'robot', 'colourId': 3,
        'birthdayMonth': 'March', 'birthdayDay': 1.5, 'complete': 'yes',
      });
      expect(d.name, isNull);
      expect(d.age, isNull);
      expect(d.gender, isNull);
      expect(d.colourId, isNull);
      expect(d.birthdayMonth, isNull);
      expect(d.birthdayDay, isNull);
      expect(d.complete, isFalse);
    });

    test('keeps no score, count or streak: the stored keys are only answers and the finished bit', () {
      expect(_done.toJson().keys.toSet(),
          <String>{'name', 'age', 'gender', 'colourId', 'birthdayMonth', 'birthdayDay', 'complete'});
    });
  });

  group('the LocalStore-backed repository', () {
    test('lives under the pending-device owner, never the literal demo-child', () {
      final LocalServices s = LocalServices.memory(childId: 'x-child', isLive: true, demoSeeds: false);
      final LocalNamespace ns = s.area('onboarding', ownerId: kPendingDeviceScope);
      expect(ns.spec.name, 'child.pending-device.onboarding');
      expect(ns.spec.name, isNot(contains('demo-child')));
      expect(ns.spec.encrypted, isFalse);
    });

    test('a live build can open the scope with no child yet', () {
      final LocalServices s = LocalServices.memory(
          childId: kPendingDeviceScope, isLive: true, demoSeeds: false);
      expect(s.area('onboarding', ownerId: kPendingDeviceScope).spec.name,
          'child.pending-device.onboarding');
    });

    test('the draft survives an app restart (a fresh store over the same files)', () async {
      final MemoryStoreBackend files = MemoryStoreBackend();
      final LocalServices first = LocalServices.memory(
          childId: kPendingDeviceScope, isLive: true, demoSeeds: false, backend: files);
      await LocalOnboardingDraftRepository(first.area('onboarding', ownerId: kPendingDeviceScope))
          .save(_done);

      // "Restart": new services, same on-disk files.
      final LocalServices second = LocalServices.memory(
          childId: kPendingDeviceScope, isLive: true, demoSeeds: false, backend: files);
      final OnboardingDraft? back = await LocalOnboardingDraftRepository(
              second.area('onboarding', ownerId: kPendingDeviceScope))
          .load();
      expect(back, isNotNull);
      expect(back!.complete, isTrue);
      expect(back.gender, 'girl');
    });

    test('the draft is still readable after the real child id is known (a different scope)', () async {
      final MemoryStoreBackend files = MemoryStoreBackend();
      final LocalServices pending = LocalServices.memory(
          childId: kPendingDeviceScope, isLive: true, demoSeeds: false, backend: files);
      await LocalOnboardingDraftRepository(pending.area('onboarding', ownerId: kPendingDeviceScope))
          .save(_done);
      final LocalServices paired = LocalServices.memory(
          childId: 'real-child-id', isLive: true, demoSeeds: false, backend: files);
      final OnboardingDraft? back = await LocalOnboardingDraftRepository(
              paired.area('onboarding', ownerId: kPendingDeviceScope))
          .load();
      expect(back?.name, 'Ivy');
    });

    test('clear removes it', () async {
      final LocalServices s = LocalServices.memory(
          childId: kPendingDeviceScope, isLive: true, demoSeeds: false);
      final LocalOnboardingDraftRepository repo = LocalOnboardingDraftRepository(
          s.area('onboarding', ownerId: kPendingDeviceScope));
      await repo.save(_done);
      await repo.clear();
      expect(await repo.load(), isNull);
    });

    test('the catalogue lists the area in plain words and says no score is kept', () {
      final LocalDataEntry e = localDataEntry('onboarding');
      expect(e.scope, LocalScope.child);
      expect(e.what, contains('pending-device'));
      expect(e.what.toLowerCase(), contains('no score'));
    });
  });

  group('syncOnboardingDraft', () {
    test('nothing pending when there is no draft', () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository();
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: repo, fetchHasOnboarded: () async => false, putGender: (_) async {});
      expect(o, DraftSyncOutcome.nothingPending);
    });

    test('an unfinished draft is never sent', () async {
      final MemoryOnboardingDraftRepository repo =
          MemoryOnboardingDraftRepository(const OnboardingDraft(gender: 'boy'));
      bool sent = false;
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: repo, fetchHasOnboarded: () async => false, putGender: (_) async => sent = true);
      expect(o, DraftSyncOutcome.nothingPending);
      expect(sent, isFalse);
      expect(await repo.load(), isNotNull);
    });

    test('success sends the gender through the session, THEN clears the draft', () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      final List<String> order = <String>[];
      String? sentGender = 'unset';
      final DraftSyncOutcome o = await syncOnboardingDraft(
        repo: repo,
        fetchHasOnboarded: () async { order.add('ask'); return false; },
        putGender: (String? g) async {
          order.add('put');
          sentGender = g;
          expect(await repo.load(), isNotNull, reason: 'still kept while it is being sent');
        },
      );
      expect(o, DraftSyncOutcome.uploaded);
      expect(order, <String>['ask', 'put']);
      expect(sentGender, 'girl');
      expect(await repo.load(), isNull);
    });

    test('a skipped gender is sent as an explicit null (the "declined" answer)', () async {
      final MemoryOnboardingDraftRepository repo =
          MemoryOnboardingDraftRepository(const OnboardingDraft(complete: true));
      String? sent = 'unset';
      await syncOnboardingDraft(
          repo: repo, fetchHasOnboarded: () async => false, putGender: (g) async => sent = g);
      expect(sent, isNull);
      expect(await repo.load(), isNull);
    });

    test('the server already has a profile: its answers win, nothing is overwritten, draft discarded',
        () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      bool put = false;
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: repo, fetchHasOnboarded: () async => true, putGender: (_) async => put = true);
      expect(o, DraftSyncOutcome.serverWon);
      expect(put, isFalse);
      expect(await repo.load(), isNull);
    });

    test('offline when asking: the draft is kept untouched', () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: repo,
          fetchHasOnboarded: () async => throw Exception('SocketException: secret detail'),
          putGender: (_) async {});
      expect(o, DraftSyncOutcome.deferred);
      expect((await repo.load())?.name, 'Ivy');
    });

    test('a server error on the write: the draft is kept', () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: repo,
          fetchHasOnboarded: () async => false,
          putGender: (_) async => throw ApiException(500, 'server_error'));
      expect(o, DraftSyncOutcome.deferred);
      expect(await repo.load(), isNotNull);
    });

    test('a hang is cut off by the timeout and the draft is kept', () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: repo,
          timeout: const Duration(milliseconds: 20),
          fetchHasOnboarded: () => Future<bool>.delayed(const Duration(seconds: 5), () => false),
          putGender: (_) async {});
      expect(o, DraftSyncOutcome.deferred);
      expect(await repo.load(), isNotNull);
    });

    test('an unreadable store defers instead of throwing', () async {
      final DraftSyncOutcome o = await syncOnboardingDraft(
          repo: _BrokenRepo(), fetchHasOnboarded: () async => false, putGender: (_) async {});
      expect(o, DraftSyncOutcome.deferred);
    });

    test('sent but the clear failed: still reported as uploaded, and a repeat finds the server has it',
        () async {
      final _FlakyClearRepo repo = _FlakyClearRepo(_done);
      final DraftSyncOutcome first = await syncOnboardingDraft(
          repo: repo, fetchHasOnboarded: () async => false, putGender: (_) async {});
      expect(first, DraftSyncOutcome.uploaded);
      expect(await repo.load(), isNotNull, reason: 'the clear failed, so it is still there');
      final DraftSyncOutcome second = await syncOnboardingDraft(
          repo: repo, fetchHasOnboarded: () async => true, putGender: (_) async {});
      expect(second, DraftSyncOutcome.serverWon);
    });
  });

  group('over the real client routes (what main_live.dart wires)', () {
    test('GET /v1/me then PUT .../profile with the gender, in that order', () async {
      final List<String> calls = <String>[];
      Object? body;
      final http.Client client = MockClient((http.Request r) async {
        calls.add('${r.method} ${r.url.path}');
        if (r.method == 'PUT') body = jsonDecode(r.body);
        if (r.url.path == '/v1/me') {
          return http.Response(jsonEncode(<String, Object?>{'hasOnboarded': false}), 200);
        }
        return http.Response('{}', 200);
      });
      final OliveApi api = OliveApi('http://olive.test', 'tok', client: client);
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      final DraftSyncOutcome o = await syncOnboardingDraft(
        repo: repo,
        fetchHasOnboarded: () async => (await api.fetchMe())['hasOnboarded'] == true,
        putGender: (String? g) async { await api.putChildGender('child-9', g); },
      );
      expect(o, DraftSyncOutcome.uploaded);
      expect(calls, <String>['GET /v1/me', 'PUT /v1/children/child-9/profile']);
      expect(body, <String, Object?>{'gender': 'girl'});
    });

    test('hasOnboarded true on the first /me after pairing: no PUT is made at all', () async {
      final List<String> calls = <String>[];
      final http.Client client = MockClient((http.Request r) async {
        calls.add('${r.method} ${r.url.path}');
        return http.Response(jsonEncode(<String, Object?>{'hasOnboarded': true}), 200);
      });
      final OliveApi api = OliveApi('http://olive.test', 'tok', client: client);
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      final DraftSyncOutcome o = await syncOnboardingDraft(
        repo: repo,
        fetchHasOnboarded: () async => (await api.fetchMe())['hasOnboarded'] == true,
        putGender: (String? g) async { await api.putChildGender('child-9', g); },
      );
      expect(o, DraftSyncOutcome.serverWon);
      expect(calls, <String>['GET /v1/me']);
      expect(await repo.load(), isNull);
    });
  });

  group('DraftRetry', () {
    test('retries on its schedule until delivered, then stops', () async {
      final List<Duration> waited = <Duration>[];
      int n = 0;
      final DraftRetry r = DraftRetry(
        delays: const <Duration>[Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)],
        wait: (Duration d) async => waited.add(d),
        attempt: () async => ++n < 3 ? DraftSyncOutcome.deferred : DraftSyncOutcome.uploaded,
      );
      expect(await r.run(), DraftSyncOutcome.uploaded);
      expect(n, 3);
      expect(waited, <Duration>[
        const Duration(seconds: 1), const Duration(seconds: 2), const Duration(seconds: 4)]);
    });

    test('backs off: the default delays only grow', () {
      final DraftRetry r = DraftRetry(attempt: () async => DraftSyncOutcome.deferred);
      for (int i = 1; i < r.delays.length; i++) {
        expect(r.delays[i], greaterThan(r.delays[i - 1]));
      }
    });

    test('gives up quietly when the delays run out (the next launch tries again)', () async {
      final DraftRetry r = DraftRetry(
        delays: const <Duration>[Duration(seconds: 1), Duration(seconds: 1)],
        wait: (Duration _) async {},
        attempt: () async => DraftSyncOutcome.deferred,
      );
      expect(await r.run(), DraftSyncOutcome.deferred);
      expect(r.attempts, 2);
    });

    test('stop() ends it before the next attempt', () async {
      late DraftRetry r;
      r = DraftRetry(
        delays: const <Duration>[Duration(seconds: 1), Duration(seconds: 1)],
        wait: (Duration _) async => r.stop(),
        attempt: () async => DraftSyncOutcome.uploaded,
      );
      await r.run();
      expect(r.attempts, 0);
    });
  });

  group('deliverPendingDraft (the boot step after a successful redeem)', () {
    test('uploaded: remembers on the device that the tour is done, no retry', () async {
      int delivered = 0;
      final r = await deliverPendingDraft(
          attempt: () async => DraftSyncOutcome.uploaded, onDelivered: () async => delivered++);
      expect(r.first, DraftSyncOutcome.uploaded);
      expect(r.retrying, isNull);
      expect(delivered, 1);
    });

    test('server profile wins: also remembered as done, no retry', () async {
      int delivered = 0;
      final r = await deliverPendingDraft(
          attempt: () async => DraftSyncOutcome.serverWon, onDelivered: () async => delivered++);
      expect(r.first, DraftSyncOutcome.serverWon);
      expect(delivered, 1);
      expect(r.retrying, isNull);
    });

    test('nothing pending: no side effects (the normal tour runs as before)', () async {
      int delivered = 0;
      final r = await deliverPendingDraft(
          attempt: () async => DraftSyncOutcome.nothingPending, onDelivered: () async => delivered++);
      expect(r.first, DraftSyncOutcome.nothingPending);
      expect(delivered, 0);
      expect(r.retrying, isNull);
    });

    test('upload failure: draft kept, home still opens (first != nothingPending), '
        'retried with backoff until it lands', () async {
      final MemoryOnboardingDraftRepository repo = MemoryOnboardingDraftRepository(_done);
      bool online = false;
      int delivered = 0;
      int tries = 0;
      Future<DraftSyncOutcome> attempt() {
        tries++;
        return syncOnboardingDraft(
            repo: repo,
            fetchHasOnboarded: () async {
              if (!online) throw Exception('offline');
              return false;
            },
            putGender: (_) async {});
      }

      final List<Duration> waited = <Duration>[];
      final r = await deliverPendingDraft(
        attempt: attempt,
        onDelivered: () async => delivered++,
        retryDelays: const <Duration>[Duration(seconds: 15), Duration(minutes: 1), Duration(minutes: 5)],
        wait: (Duration d) async {
          waited.add(d);
          if (waited.length == 2) online = true; // the connection comes back
        },
      );
      expect(r.first, DraftSyncOutcome.deferred);
      expect(await repo.load(), isNotNull, reason: 'kept after the first failure');
      expect(delivered, 0);

      expect(await r.retrying, DraftSyncOutcome.uploaded);
      expect(tries, 3);
      expect(waited, <Duration>[const Duration(seconds: 15), const Duration(minutes: 1)]);
      expect(await repo.load(), isNull, reason: 'cleared once uploaded');
      expect(delivered, 1);
    });

    test('a failing onDelivered never turns a delivery into a crash', () async {
      final r = await deliverPendingDraft(
          attempt: () async => DraftSyncOutcome.uploaded,
          onDelivered: () async => throw StateError('disk full'));
      expect(r.first, DraftSyncOutcome.uploaded);
    });
  });
}

class _BrokenRepo implements OnboardingDraftRepository {
  @override
  Future<OnboardingDraft?> load() async => throw StateError('unreadable');
  @override
  Future<void> save(OnboardingDraft draft) async => throw StateError('unwritable');
  @override
  Future<void> clear() async => throw StateError('unwritable');
}

class _FlakyClearRepo extends MemoryOnboardingDraftRepository {
  _FlakyClearRepo(super.draft);
  @override
  Future<void> clear() async => throw StateError('clear failed');
}
