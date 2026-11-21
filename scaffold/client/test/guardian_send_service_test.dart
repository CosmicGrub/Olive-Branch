// OLIVE BRANCH — guardian_send_service.dart tests. Run by CI; nothing here has run on a device.
// MASTERFILE §8.31. A fake server and the real on-device store: no device, no network.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_send_logic.dart';
import 'package:olive_client/guardian_send_service.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

import 'guardian_send_fakes.dart';

const DeliveryChoice kBedtime = DeliveryChoice.atDayPart('bedtime');
final List<int> kVideo = List<int>.generate(2048, (int i) => i % 251);
final DateTime kToday = DateTime(2026, 11, 20);

void main() {
  late FakeSendApi api;
  late FakeClock clock;
  late LocalServices services;
  late GuardianSendService svc;

  setUp(() {
    api = FakeSendApi();
    clock = FakeClock();
    services = LocalServices.memory(childId: 'ivy', guardianId: 'dad-a');
    svc = serviceWith(api, services: services, clock: clock);
  });

  Future<ComposeResult> send({DeliveryChoice d = kBedtime, List<int>? bytes}) =>
      svc.compose(bytes: bytes ?? kVideo, durationMs: 4000, delivery: d, today: kToday);

  group('compose: the happy path goes through the real two-step sequence', () {
    test('uploads the bytes, then posts the key, the duration and the day-part, and leaves nothing waiting', () async {
      final ComposeResult r = await send();
      expect(r.outcome, ComposeOutcome.sent);
      expect(r.words, 'Sent. It will arrive at bedtime.');
      expect(api.calls, <String>['upload', 'send']);
      expect(api.uploads.single, kVideo);
      expect(api.sends.single['daypart'], 'bedtime');
      expect(api.sends.single['durationMs'], 4000);
      expect(api.sends.single.containsKey('targetLocalDate'), isFalse, reason: 'next-bedtime carries no date');
      expect(api.sends.single['storageKey'], startsWith('children/child-a/messages/'));
      expect(await svc.queued(), isEmpty);
      expect(api.closed, greaterThan(0), reason: 'the client is released');
    });

    test('a named night sends the date and the part', () async {
      final ComposeResult r = await send(d: const DeliveryChoice.onNight('2026-12-24', dayPart: 'wake'));
      expect(r.outcome, ComposeOutcome.sent);
      expect(api.sends.single['targetLocalDate'], '2026-12-24');
      expect(api.sends.single['daypart'], 'wake');
      expect(r.words, contains('the night of Thu 24 Dec'));
    });

    test('what it was set for is remembered against the server id, for the status list', () async {
      api.onSent = () => <String, dynamic>{
            'messages': <Object?>[
              <String, Object?>{'id': 'intent-00001', 'kind': 'video_msg', 'state': 'waiting', 'sentAt': '2026-11-20T10:00:00.000Z'},
              <String, Object?>{'id': 'someone-elses-1', 'kind': 'video_msg', 'state': 'delivered'},
            ],
          };
      await send();
      final SentView v = await svc.fetchSent();
      expect(v.setFor['intent-00001'], 'at bedtime');
      expect(v.setFor.containsKey('someone-elses-1'), isFalse, reason: 'another phone\'s message has no remembered phrase');
      expect(sentStatusWords(v.rows.first, setFor: v.setFor[v.rows.first.id]), startsWith('Waiting to arrive at bedtime.'));
    });
  });

  group('right away', () {
    const DeliveryChoice now = DeliveryChoice.now();

    test('sends delivery=now with no night, and says "right away" only because the server said now', () async {
      final ComposeResult r = await send(d: now);
      expect(r.outcome, ComposeOutcome.sent);
      expect(r.words, 'Sent. It will arrive right away.');
      expect(api.sends.single['delivery'], 'now');
      expect(api.sends.single.containsKey('targetLocalDate'), isFalse);
      expect(await svc.queued(), isEmpty);
    });

    test('a part or a night never sends a delivery field (an older server reads them as it always did)', () async {
      await send();
      await send(d: const DeliveryChoice.onNight('2026-12-24'));
      expect(api.sends.any((Map<String, Object?> b) => b.containsKey('delivery')), isFalse);
    });

    test('a server that does not know the field (no echo) is never described as having sent it right away', () async {
      api.echoDelivery = false;
      final ComposeResult r = await send(d: now);
      expect(r.outcome, ComposeOutcome.sent, reason: 'the server did take it');
      expect(r.words, 'Sent. It is scheduled.', reason: 'but it did not promise right away, and neither do we');
      expect(r.words, isNot(contains('right away')));
      final SentView v = await svc.fetchSent();
      expect(v.setFor, isEmpty, reason: 'nothing untrue is remembered about it either');
    });

    test('works with no day-parts known (offline composer) and with a day that has no bedtime', () async {
      final List<DayPartEntry> noBed = DayPartsView.parse(<String, Object?>{
        'dayParts': <Object?>[
          <String, Object?>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '19:00', 'reachable': true},
        ],
      }).parts;
      final ComposeResult r = await svc.compose(
          bytes: kVideo, durationMs: 100, delivery: now, parts: noBed, today: kToday);
      expect(r.outcome, ComposeOutcome.sent);
      final ComposeResult empty = await svc.compose(
          bytes: kVideo, durationMs: 100, delivery: now, parts: const <DayPartEntry>[], today: kToday);
      expect(empty.outcome, ComposeOutcome.sent);
    });

    test('offline it is saved on the phone and goes by itself while it is still recent', () async {
      api.onUpload = (int n) => n == 1 ? throw const _NoNetwork() : null;
      final ComposeResult r = await send(d: now);
      expect(r.outcome, ComposeOutcome.savedWaiting);
      expect((await svc.queued()).single.delivery, now);
      clock.ms += 5 * 60 * 1000;
      expect(await svc.flush(), 1);
      expect(api.sends.single['delivery'], 'now');
    });

    test('one that has waited past the limit is NOT sent late: it waits for the grown-up, in words', () async {
      api.onUpload = (int n) => throw const _NoNetwork();
      await send(d: now);
      api.onUpload = null;
      clock.ms += kStaleNowAfter.inMilliseconds + 1000;
      expect(await svc.flush(force: true), 0, reason: 'even a forced pass does not send a stale "now"');
      expect(api.sends, isEmpty);
      final QueuedSend q = (await svc.queued()).single;
      expect(q.phase, SendPhase.needsAttention);
      expect(queuedStatusWords(q), staleNowWords);
      expect((await svc.retry(q.id)).outcome, ComposeOutcome.needsAttention, reason: 'Try again does not make it fresh');
      expect(api.sends, isEmpty);
    });

    test('choosing a part instead sends it as chosen; choosing Right away again starts its clock again', () async {
      api.onUpload = (int n) => throw const _NoNetwork();
      await send(d: now);
      api.onUpload = null;
      clock.ms += kStaleNowAfter.inMilliseconds + 1000;
      await svc.flush(force: true);
      final String id = (await svc.queued()).single.id;
      final ComposeResult again = await svc.changeDelivery(id, now);
      expect(again.outcome, ComposeOutcome.sent, reason: 'chosen again, so it is right away from this moment');
      expect(api.sends.single['delivery'], 'now');

      api.onUpload = (int n) => throw const _NoNetwork();
      await send(d: now);
      api.onUpload = null;
      clock.ms += kStaleNowAfter.inMilliseconds + 1000;
      await svc.flush(force: true);
      final String id2 = (await svc.queued()).single.id;
      final ComposeResult part = await svc.changeDelivery(id2, kBedtime);
      expect(part.outcome, ComposeOutcome.sent);
      expect(api.sends.last.containsKey('delivery'), isFalse);
      expect(api.sends.last['daypart'], 'bedtime');
    });

    test('the server refusing it (a child account, a bad combination) is a "needs your attention", never retried', () async {
      api.onSend = (int n, Map<String, Object?> b) => throw answer(400, 'now_has_no_date');
      final ComposeResult r = await send(d: now);
      expect(r.outcome, ComposeOutcome.needsAttention);
      expect(r.words, isNot(contains('_')));
      expect(await svc.flush(force: true), 0);
      expect(api.sends.length, 1);
    });
  });

  group('compose: refused before anything is written or sent', () {
    test('an empty recording or a zero duration', () async {
      expect((await send(bytes: <int>[])).outcome, ComposeOutcome.refused);
      expect((await svc.compose(bytes: kVideo, durationMs: 0, delivery: kBedtime)).outcome, ComposeOutcome.refused);
      expect(api.calls, isEmpty);
      expect(await svc.queued(), isEmpty);
    });

    test('a recording over the hold limit', () async {
      final ComposeResult r = await send(bytes: List<int>.filled(kMaxHeldBytes + 1, 1));
      expect(r.outcome, ComposeOutcome.refused);
      expect(r.words, contains('too large'));
      expect(api.calls, isEmpty);
      expect(await svc.queued(), isEmpty);
    });

    test('a night that has gone, or a part she does not have, when her day is known', () async {
      final List<DayPartEntry> day = DayPartsView.parse(api.dayPartsBody).parts;
      final ComposeResult past = await svc.compose(
          bytes: kVideo, durationMs: 100, delivery: const DeliveryChoice.onNight('2026-11-01'), parts: day, today: kToday);
      expect(past.outcome, ComposeOutcome.refused);
      expect(past.words, contains('already gone by'));
      final ComposeResult none = await svc.compose(
          bytes: kVideo, durationMs: 100, delivery: const DeliveryChoice.atDayPart('dinner'), parts: day, today: kToday);
      expect(none.outcome, ComposeOutcome.refused);
      expect(api.calls, isEmpty);
    });

    test('a store with no room refuses honestly rather than sending something it could lose', () async {
      final LocalServices tiny = LocalServices.memory(childId: 'ivy', guardianId: 'dad-a');
      // A namespace opened at a tiny ceiling under the same name the service will use.
      final LocalNamespace ns = tiny.store.open(NamespaceSpec(
          name: tiny.namespaceName(localDataEntry('sendoutbox'), ownerId: 'dad-a'), encrypted: true, maxBytes: 1024));
      final GuardianSendService s = GuardianSendService(
          childId: 'child-a', outbox: ns, open: () async => api, nowMs: clock.call);
      final ComposeResult r = await s.compose(bytes: kVideo, durationMs: 100, delivery: kBedtime);
      expect(r.outcome, ComposeOutcome.refused);
      expect(r.words, contains('not enough room on this phone'));
      expect(api.calls, isEmpty, reason: 'never send what could not be kept if it failed');
    });
  });

  group('compose: the message is on this phone BEFORE the network is asked', () {
    test('mid-upload the item is already in the sealed store, and a crash then loses nothing', () async {
      final Completer<void> gate = Completer<void>();
      api.onUpload = (int n) => gate.future;
      final Future<ComposeResult> pending = send();
      await _until(() => api.calls.contains('upload'));
      // A second service over the SAME store (what a restarted app sees):
      final GuardianSendService fresh = serviceWith(FakeSendApi(), services: services, clock: clock);
      final List<QueuedSend> held = await fresh.queued();
      expect(held.length, 1, reason: 'saved before the upload finished');
      expect(base64Decode(held.single.mediaB64), kVideo);
      gate.complete();
      expect((await pending).outcome, ComposeOutcome.sent);
      expect(await svc.queued(), isEmpty);
    });

    test('the stored file is sealed: the recording is not readable in it', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'ivy', guardianId: 'dad-a', backend: backend);
      final FakeSendApi down = FakeSendApi()..onUpload = (int n) => throw const _NoNetwork();
      final GuardianSendService sv = serviceWith(down, services: s, clock: clock);
      await sv.compose(bytes: kVideo, durationMs: 100, delivery: kBedtime);
      final String name = s.namespaceName(localDataEntry('sendoutbox'), ownerId: 'dad-a');
      final List<int>? raw = await backend.read(name);
      expect(raw, isNotNull);
      expect(utf8.decode(raw!, allowMalformed: true), isNot(contains(base64Encode(kVideo).substring(0, 40))));
      expect(utf8.decode(raw, allowMalformed: true), isNot(contains('bedtime')));
    });
  });

  group('offline: no answer keeps the message and says so', () {
    test('a dropped connection on the upload is saved-and-waiting, and goes by itself later, uploading once', () async {
      api.onUpload = (int n) => n == 1 ? throw const _NoNetwork() : null;
      final ComposeResult r = await send();
      expect(r.outcome, ComposeOutcome.savedWaiting);
      expect(r.words, contains('saved on this phone'));
      final QueuedSend q = (await svc.queued()).single;
      expect(q.phase, SendPhase.waiting);
      expect(q.attempts, 1);
      expect(q.storageKey, isNull);

      // Too soon: the doubling wait has not passed, so an automatic pass does nothing.
      clock.ms += 30 * 1000;
      expect(await svc.flush(), 0);
      expect(api.uploads.length, 1);

      clock.ms += 60 * 1000;
      expect(await svc.flush(), 1);
      expect(await svc.queued(), isEmpty);
      expect(api.sends.length, 1);
    });

    test('a failure on the SECOND half caches the upload, so the retry never uploads twice', () async {
      api.onSend = (int n, Map<String, Object?> b) => n == 1 ? throw const _NoNetwork() : <String, dynamic>{'id': 'intent-0000$n'};
      final ComposeResult r = await send();
      expect(r.outcome, ComposeOutcome.savedWaiting);
      expect((await svc.queued()).single.storageKey, isNotNull);
      clock.ms += 10 * 60 * 1000;
      expect(await svc.flush(), 1);
      expect(api.uploads.length, 1, reason: 'one upload for two sends');
      expect(api.sends.length, 2);
      expect(api.sends[0]['storageKey'], api.sends[1]['storageKey']);
    });

    test('a signed-out phone (no session) is waiting, not refused: nothing is thrown away', () async {
      final GuardianSendService signedOut = serviceWith(api, services: services, clock: clock,
          openError: answer(401, 'not_signed_in'));
      final ComposeResult r = await signedOut.compose(bytes: kVideo, durationMs: 100, delivery: kBedtime);
      expect(r.outcome, ComposeOutcome.savedWaiting);
      expect(r.words, contains('sign in again'));
      expect((await signedOut.queued()).single.phase, SendPhase.waiting);
      expect(api.calls, isEmpty);
    });

    test('503 and 429 are waiting; a down server is asked once per pass, not once per message', () async {
      api.onUpload = (int n) => throw answer(503, 'unavailable');
      await send();
      await send();
      await send();
      expect(api.uploads.length, 3);
      clock.ms += 60 * 60 * 1000;
      api.uploads.clear();
      await svc.flush();
      expect(api.uploads.length, 1, reason: 'the pass stopped at the first "no answer"');
      expect((await svc.queued()).length, 3);
    });

    test('after the attempt ceiling automatic tries stop, the message stays, and Try again still works', () async {
      api.onUpload = (int n) => throw const _NoNetwork();
      await send();
      for (int i = 0; i < 12; i++) {
        clock.ms += 7 * 60 * 60 * 1000;
        await svc.flush();
      }
      final QueuedSend q = (await svc.queued()).single;
      expect(q.attempts, 8);
      expect(q.gaveUpAutomatically, isTrue);
      expect(queuedStatusWords(q), contains('Try again'));
      final int before = api.uploads.length;
      clock.ms += 100 * 60 * 60 * 1000;
      await svc.flush();
      expect(api.uploads.length, before, reason: 'no more automatic tries');
      // The grown-up taps Try again and the network is back.
      api.onUpload = null;
      final ComposeResult r = await svc.retry(q.id);
      expect(r.outcome, ComposeOutcome.sent);
      expect(await svc.queued(), isEmpty);
    });

    test('an empty outbox costs no network at all', () async {
      expect(await svc.flush(), 0);
      expect(await svc.flush(force: true), 0);
      expect(api.calls, isEmpty);
    });
  });

  group('the server says no: kept, explained, never retried blindly', () {
    test('daypart_undefined (no bedtime set) is needs-attention, in words, and the recording is kept', () async {
      api.onSend = (int n, Map<String, Object?> b) => throw answer(400, 'daypart_undefined');
      final ComposeResult r = await send();
      expect(r.outcome, ComposeOutcome.needsAttention);
      expect(r.words, contains('Set her day first'));
      expect(r.words, isNot(contains('daypart_undefined')));
      final QueuedSend q = (await svc.queued()).single;
      expect(q.phase, SendPhase.needsAttention);
      expect(q.failureCode, 'daypart_undefined');
      // Automatic passes never touch it.
      api.calls.clear();
      clock.ms += 1000 * 60 * 60 * 24;
      expect(await svc.flush(), 0);
      expect(api.calls, isEmpty);
    });

    test('changing when it arrives resets it and sends it for the new time', () async {
      api.onSend = (int n, Map<String, Object?> b) =>
          b['daypart'] == 'bedtime' ? throw answer(400, 'daypart_undefined') : <String, dynamic>{'id': 'intent-00002'};
      await send();
      final QueuedSend q = (await svc.queued()).single;
      final ComposeResult r = await svc.changeDelivery(q.id, const DeliveryChoice.atDayPart('free'));
      expect(r.outcome, ComposeOutcome.sent);
      expect(api.sends.last['daypart'], 'free');
      expect(await svc.queued(), isEmpty);
      expect(api.uploads.length, 1, reason: 'the upload from the first try is reused');
    });

    test('changeDelivery checks the new time against her day first', () async {
      api.onSend = (int n, Map<String, Object?> b) => throw answer(400, 'daypart_undefined');
      await send();
      final QueuedSend q = (await svc.queued()).single;
      final List<DayPartEntry> day = DayPartsView.parse(api.dayPartsBody).parts;
      final ComposeResult r = await svc.changeDelivery(q.id, const DeliveryChoice.atDayPart('dinner'), parts: day);
      expect(r.outcome, ComposeOutcome.refused);
      expect((await svc.queued()).single.delivery, kBedtime, reason: 'unchanged');
    });

    test('every refusal is told in words with no raw code, for the codes the route can give', () async {
      for (final String code in <String>[
        'target_date_in_past', 'already_expired', 'delivery_unresolvable', 'empty_recording', 'unsupported_media_type',
        'media_quota_exceeded', 'not_authorized', 'child_not_found', 'storage_key_not_yours', 'something_new',
      ]) {
        final FakeSendApi a = FakeSendApi()..onSend = (int n, Map<String, Object?> b) => throw answer(400, code);
        final GuardianSendService s = serviceWith(a, services: LocalServices.memory(childId: 'ivy', guardianId: 'dad-a'), clock: clock);
        final ComposeResult r = await s.compose(bytes: kVideo, durationMs: 9, delivery: kBedtime);
        expect(r.outcome, ComposeOutcome.needsAttention, reason: code);
        expect(r.words, isNot(contains('_')), reason: code);
        expect(r.words, isNotEmpty);
      }
    });

    test('discarding is the grown-up\'s choice and removes only that message', () async {
      api.onSend = (int n, Map<String, Object?> b) => throw answer(400, 'daypart_undefined');
      await send();
      await send();
      final List<QueuedSend> two = await svc.queued();
      expect(two.length, 2);
      await svc.discard(two.first.id);
      expect((await svc.queued()).single.id, two.last.id);
    });
  });

  group('double sends are impossible', () {
    test('the answer was lost: the retry gets storage_key_in_use and treats the server as having it', () async {
      api.onSend = (int n, Map<String, Object?> b) => n == 1
          ? throw const _NoNetwork() // the request reached the server but the answer was lost
          : throw answer(409, 'storage_key_in_use');
      expect((await send()).outcome, ComposeOutcome.savedWaiting);
      clock.ms += 10 * 60 * 1000;
      expect(await svc.flush(), 1);
      expect(await svc.queued(), isEmpty, reason: 'dropped, not stuck and not resent as a new message');
      expect(api.uploads.length, 1);
    });

    test('two screens flushing at once send one message once', () async {
      api.onUpload = (int n) => n == 1 ? throw const _NoNetwork() : Future<void>.delayed(const Duration(milliseconds: 20));
      await send();
      clock.ms += 10 * 60 * 1000;
      final GuardianSendService other = serviceWith(api, services: services, clock: clock);
      final List<int> got = await Future.wait(<Future<int>>[svc.flush(), other.flush()]);
      expect(got.reduce((int a, int b) => a + b), 1);
      expect(api.sends.length, 1);
      expect(await svc.queued(), isEmpty);
    });

    test('a message discarded while its attempt is in flight is not brought back by a failure', () async {
      final Completer<void> gate = Completer<void>();
      api.onUpload = (int n) async {
        await gate.future;
        throw const _NoNetwork();
      };
      final Future<ComposeResult> pending = send();
      await _until(() => api.calls.contains('upload'));
      final List<QueuedSend> held = await svc.queued();
      await svc.discard(held.single.id);
      gate.complete();
      await pending;
      expect(await svc.queued(), isEmpty);
    });

    test('the server forgot the upload: the key is dropped and the next try uploads again', () async {
      api.onSend = (int n, Map<String, Object?> b) => n == 1 ? throw answer(400, 'storage_key_unknown') : <String, dynamic>{'id': 'intent-00002'};
      final ComposeResult first = await send();
      expect(first.outcome, ComposeOutcome.savedWaiting);
      expect((await svc.queued()).single.storageKey, isNull);
      clock.ms += 10 * 60 * 1000;
      expect(await svc.flush(), 1);
      expect(api.uploads.length, 2);
    });
  });

  group('hostile store contents', () {
    test('an item this build cannot read is left alone and not listed, and does not stop others', () async {
      final LocalNamespace ns = services.area('sendoutbox', ownerId: 'dad-a');
      await ns.put('s.mbroken-0001', <String, Object?>{'id': 'mbroken-0001', 'child': 5});
      await ns.put('s.mnotmap-0001', 'a string');
      await send();
      api.calls.clear();
      // Make the good one wait so something is listed.
      expect(await svc.queued(), isEmpty);
      expect(await ns.get('s.mbroken-0001'), isNotNull, reason: 'never deleted');
      expect(await ns.get('s.mnotmap-0001'), 'a string');
    });

    test('another child\'s waiting message is never sent through this child\'s service', () async {
      final FakeSendApi down = FakeSendApi()..onUpload = (int n) => throw const _NoNetwork();
      final GuardianSendService other = serviceWith(down, childId: 'child-b', services: services, clock: clock);
      await other.compose(bytes: kVideo, durationMs: 5, delivery: kBedtime);
      expect(await svc.queued(), isEmpty);
      clock.ms += 10 * 60 * 1000;
      expect(await svc.flush(), 0);
      expect(api.calls, isEmpty);
      expect((await other.queued()).length, 1);
    });

    test('a server id with odd characters is not used as a store key', () async {
      api.onSend = (int n, Map<String, Object?> b) => <String, dynamic>{'id': '../../x y'};
      final ComposeResult r = await send();
      expect(r.outcome, ComposeOutcome.sent);
      expect(await services.area('sendoutbox', ownerId: 'dad-a').list(), isEmpty);
    });

    test('the remembered-phrase list is bounded', () async {
      for (int i = 0; i < 75; i++) {
        final FakeSendApi a = FakeSendApi()..onSend = (int n, Map<String, Object?> b) => <String, dynamic>{'id': 'intent-${1000 + i}'};
        clock.ms += 1000;
        await serviceWith(a, services: services, clock: clock).compose(bytes: kVideo, durationMs: 5, delivery: kBedtime);
      }
      final List<String> keys = (await services.area('sendoutbox', ownerId: 'dad-a').list()).where((String k) => k.startsWith('l.')).toList();
      expect(keys.length, 60);
      expect(keys, contains('l.intent-1074'), reason: 'the newest are kept');
      expect(keys, isNot(contains('l.intent-1000')));
    });
  });

  group('the sent list', () {
    test('rows the server sends that cannot be read are counted, not hidden', () async {
      api.onSent = () => <String, dynamic>{'messages': <Object?>['x', <String, Object?>{'id': 'okid-001', 'state': 'opened'}]};
      final SentView v = await svc.fetchSent();
      expect(v.rows.length, 1);
      expect(v.skipped, 1);
    });

    test('a server that cannot be reached throws, so the screen can say so', () async {
      api.onSent = () => throw const _NoNetwork();
      await expectLater(svc.fetchSent(), throwsA(isA<_NoNetwork>()));
      expect(api.closed, greaterThan(0));
    });

    test('her clock for the header is read from /now and optional', () async {
      final ({String? localTime, String? dayPart, bool? reachable}) n = await svc.fetchNow();
      expect(n.localTime, '9:14 PM');
      expect(n.reachable, isFalse);
      api.onNow = () => <String, dynamic>{'childLocalTime': 5, 'reachable': 'x'};
      final ({String? localTime, String? dayPart, bool? reachable}) odd = await svc.fetchNow();
      expect(odd.localTime, isNull);
      expect(odd.reachable, isNull);
    });
  });

  group('day-parts save: validation, the per-child lock, and not overwriting a day you have not seen', () {
    late List<DayPartEntry> base;
    setUp(() => base = DayPartsView.parse(api.dayPartsBody).parts);

    test('a valid edit is read back first, written whole, and the server\'s answer becomes the truth', () async {
      final List<DayPartEntry> edited = <DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00');
      final DayPartsSaveResult r = await svc.saveDayParts(edited, baseline: base);
      expect(r.status, DayPartsSaveStatus.saved);
      expect(api.calls, <String>['getDayParts', 'putDayParts'], reason: 'read first, then write');
      expect(api.putBodies.single.length, 4, reason: 'the WHOLE schedule is replaced');
      expect(api.putBodies.single.firstWhere((Map<String, Object?> p) => p['kind'] == 'bedtime')['startsLocal'], '19:00');
      expect(r.view!.parts.firstWhere((DayPartEntry p) => p.kind == 'bedtime').startsLocal, '19:00');
      expect(r.words, contains('re-timed'));
    });

    test('an invalid schedule is refused on this phone, and the server is not asked', () async {
      final DayPartsSaveResult r = await svc.saveDayParts(<DayPartEntry>[], baseline: base);
      expect(r.status, DayPartsSaveStatus.invalid);
      expect(api.calls, isEmpty);
      final DayPartsSaveResult o = await svc.saveDayParts(<DayPartEntry>[...base, base[1]], baseline: base);
      expect(o.status, DayPartsSaveStatus.invalid);
      expect(o.problems.single.code, 'day_parts_overlap');
      expect(api.calls, isEmpty);
    });

    test('if another grown-up changed her day, nothing is written and the new day comes back', () async {
      api.dayPartsBody = <String, dynamic>{
        'dayParts': <Object?>[
          <String, Object?>{'kind': 'bedtime', 'startsLocal': '18:00', 'endsLocal': '19:00', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
        ],
      };
      final DayPartsSaveResult r = await svc.saveDayParts(<DayPartEntry>[...base]..removeLast(), baseline: base);
      expect(r.status, DayPartsSaveStatus.changedElsewhere);
      expect(api.calls, <String>['getDayParts'], reason: 'no PUT');
      expect(r.view!.parts.single.startsLocal, '18:00');
      expect(r.words, contains('Another grown-up'));
    });

    test('two saves for one child from this phone at once: the second is told to wait, only one writes', () async {
      final Completer<void> gate = Completer<void>();
      api.onGetDayParts = () async {
        await gate.future;
        return api.dayPartsBody;
      };
      final List<DayPartEntry> edited = <DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00');
      final Future<DayPartsSaveResult> a = svc.saveDayParts(edited, baseline: base);
      await Future<void>.delayed(Duration.zero);
      final DayPartsSaveResult b = await serviceWith(api, services: services, clock: clock).saveDayParts(edited, baseline: base);
      expect(b.status, DayPartsSaveStatus.busy);
      gate.complete();
      expect((await a).status, DayPartsSaveStatus.saved);
      expect(api.putBodies.length, 1);
      // And the lock is released afterwards.
      api.onGetDayParts = null;
      final DayPartsView now = await svc.loadDayParts();
      expect((await svc.saveDayParts(now.parts, baseline: now.parts)).status, DayPartsSaveStatus.saved);
    });

    test('the server refuses (409 overlap or 400): told in words, nothing claimed saved, lock released', () async {
      api.onPutDayParts = (List<Map<String, Object?>> p) => throw answer(409, 'day_parts_overlap');
      final List<DayPartEntry> edited = <DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00');
      final DayPartsSaveResult r = await svc.saveDayParts(edited, baseline: base);
      expect(r.status, DayPartsSaveStatus.refused);
      expect(r.words, contains('overlap'));
      expect(r.words, isNot(contains('_')));
      api.onPutDayParts = null;
      expect((await svc.saveDayParts(edited, baseline: base)).status, DayPartsSaveStatus.saved);
    });

    test('a save that times out is checked by reading the schedule back: it did land', () async {
      final FakeSendApi a = FakeSendApi();
      final List<DayPartEntry> edited = <DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00');
      a.onPutDayParts = (List<Map<String, Object?>> p) async {
        // The server applied it, but the answer never arrives in time.
        a.dayPartsBody = <String, dynamic>{'dayParts': p, 'hasBedtime': true};
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return a.dayPartsBody;
      };
      final GuardianSendService s = serviceWith(a, services: services, clock: clock, saveTimeout: const Duration(milliseconds: 20));
      final DayPartsSaveResult r = await s.saveDayParts(edited, baseline: base);
      expect(r.status, DayPartsSaveStatus.saved);
      expect(r.view!.parts.firstWhere((DayPartEntry p) => p.kind == 'bedtime').startsLocal, '19:00');
    });

    test('a save that times out and did NOT land says so, and the edits stay', () async {
      final FakeSendApi a = FakeSendApi();
      a.onPutDayParts = (List<Map<String, Object?>> p) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return a.dayPartsBody;
      };
      final List<DayPartEntry> edited = <DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00');
      final GuardianSendService s = serviceWith(a, services: services, clock: clock, saveTimeout: const Duration(milliseconds: 20));
      final DayPartsSaveResult r = await s.saveDayParts(edited, baseline: base);
      expect(r.status, DayPartsSaveStatus.refused);
      expect(r.words, contains('did not go through'));
    });

    test('no way to tell whether it saved (read-back also fails): unknown, not a false "saved"', () async {
      final FakeSendApi a = FakeSendApi();
      int gets = 0;
      a.onGetDayParts = () {
        gets++;
        if (gets == 1) return a.dayPartsBody;
        throw const _NoNetwork();
      };
      a.onPutDayParts = (List<Map<String, Object?>> p) => throw const _NoNetwork();
      final List<DayPartEntry> edited = <DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00');
      final DayPartsSaveResult r = await serviceWith(a, services: services, clock: clock).saveDayParts(edited, baseline: base);
      expect(r.status, DayPartsSaveStatus.unknown);
      expect(r.words, contains('could not tell'));
    });

    test('a day with a row this build cannot read is never overwritten (it would be lost)', () async {
      api.dayPartsBody = <String, dynamic>{
        'dayParts': <Object?>[...(api.dayPartsBody['dayParts'] as List<Object?>), <String, Object?>{'kind': 'from_the_future', 'startsLocal': 'x'}],
      };
      final DayPartsSaveResult r = await svc.saveDayParts(<DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00'), baseline: base);
      expect(r.status, DayPartsSaveStatus.refused);
      expect(r.words, contains('cannot read'));
      expect(api.putBodies, isEmpty);
    });

    test('no network at all: nothing changed, edits kept', () async {
      final GuardianSendService off = serviceWith(api, services: services, clock: clock, openError: const _NoNetwork());
      final DayPartsSaveResult r = await off.saveDayParts(<DayPartEntry>[...base]..[2] = base[2].copyWith(startsLocal: '19:00'), baseline: base);
      expect(r.status, DayPartsSaveStatus.unknown);
      expect(r.words, contains('Nothing was changed'));
    });
  });
}

/// Waits (bounded) for something asynchronous to have happened.
Future<void> _until(bool Function() done) async {
  for (int i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'the awaited step never happened');
}

class _NoNetwork implements Exception {
  const _NoNetwork();
}
