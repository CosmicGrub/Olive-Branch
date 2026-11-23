// OLIVE BRANCH — sending to the child from the grown-up's phone: the service and its outbox, headless, against a
// stand-in written from the real routes (support/fake_delivery_server.dart). MASTERFILE section 8.31.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/guardian_send_logic.dart';
import 'package:olive_client/guardian_send_service.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

import 'support/fake_delivery_server.dart';

const String kGuardian = 'aaaaaaaa-0000-4000-8000-000000000002';

class Rig {
  Rig({int startMs = 1000000000000, String childId = kChild, SendOutbox? outbox, FakeDeliveryServer? server})
      : server = server ?? FakeDeliveryServer(),
        outbox = outbox ?? MemorySendOutbox(),
        now = startMs {
    service = GuardianSendService(
      childId: childId,
      childName: 'Mia',
      openApi: () async => OliveApi(kBase, 'tok', client: this.server.client),
      outbox: this.outbox,
      closeApi: false,
      nowMs: () => now,
      newId: () => 'm${++n}',
    );
  }
  final FakeDeliveryServer server;
  final SendOutbox outbox;
  late final GuardianSendService service;
  int now;
  int n = 0;
  void minutes(int m) => now += m * 60000;
}

SendDraft draft({
  DeliveryChoice choice = const DeliveryChoice.atDayPart('bedtime'),
  List<int>? bytes,
  MediaKind kind = MediaKind.photo,
}) =>
    SendDraft(bytes: bytes ?? jpegBytes(), kind: kind, durationMs: 1, choice: choice);

void main() {
  group('a send that works', () {
    test('uploads once, then sends once, and the outbox is empty afterwards', () async {
      final Rig r = Rig();
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.sent);
      expect(o.intentId, isNotNull);
      expect(r.server.uploadCalls, 1);
      expect(r.server.messageCalls, 1);
      expect(await r.outbox.load(), isEmpty);
      expect(o.text, startsWith('Sent.'));
    });

    test('the request carries the session and exactly the fields the server reads', () async {
      final Rig r = Rig();
      await r.service.submit(draft(choice: const DeliveryChoice.atDayPart('wake')));
      final Seen up = r.server.where('POST', '/media').single;
      expect(up.auth, isTrue);
      expect(up.body.keys.toSet(), <String>{'bytes'});
      final Seen msg = r.server.where('POST', '/messages').single;
      expect(msg.auth, isTrue);
      expect(msg.body['delivery'], 'daypart');
      expect(msg.body['daypart'], 'wake');
      expect(msg.body.containsKey('targetLocalDate'), isFalse, reason: 'a day-part names no night');
      expect(msg.body['storageKey'], startsWith('children/$kChild/messages/'));
      expect(msg.body['durationMs'], 1);
      expect(msg.body.containsKey('preserve'), isFalse,
          reason: 'omitted so the server applies the standing rule: a grown-up\'s message is kept');
    });

    test('right away sends delivery now and no night', () async {
      final Rig r = Rig();
      await r.service.submit(draft(choice: const DeliveryChoice.now()));
      final Map<String, dynamic> b = r.server.where('POST', '/messages').single.body;
      expect(b['delivery'], 'now');
      expect(b.containsKey('targetLocalDate'), isFalse);
    });

    test('a night sends delivery date with that night', () async {
      final Rig r = Rig();
      await r.service.submit(draft(choice: const DeliveryChoice.onNight('2026-12-24')), today: DateTime(2026, 11, 15));
      final Map<String, dynamic> b = r.server.where('POST', '/messages').single.body;
      expect(b['delivery'], 'date');
      expect(b['targetLocalDate'], '2026-12-24');
      expect(b['daypart'], 'bedtime');
    });

    test('the media is sent whole and unchanged', () async {
      final Rig r = Rig();
      final List<int> bytes = <int>[...jpegBytes(300), 9, 8, 7];
      await r.service.submit(draft(bytes: bytes));
      expect(r.server.uploads.values.single, bytes);
    });

    test('the server\'s view lists it as waiting, with the choice the sender made', () async {
      final Rig r = Rig();
      await r.service.submit(draft(choice: const DeliveryChoice.now()));
      expect(r.server.sent.single.delivery, 'now');
    });
  });

  group('checked before anything is tried', () {
    test('empty, too big, no length, a night long past, a made-up part of the day', () async {
      final Rig r = Rig();
      expect((await r.service.submit(draft(bytes: <int>[]))).kind, SubmitKind.invalid);
      expect((await r.service.submit(draft(bytes: List<int>.filled(kMaxSendBytes + 1, 1)))).kind, SubmitKind.invalid);
      expect((await r.service.submit(SendDraft(bytes: jpegBytes(), kind: MediaKind.photo, durationMs: 0,
          choice: const DeliveryChoice.now()))).kind, SubmitKind.invalid);
      expect((await r.service.submit(draft(choice: const DeliveryChoice.onNight('2020-01-01')),
          today: DateTime(2026, 11, 15))).text, contains('already passed'));
      expect((await r.service.submit(draft(choice: const DeliveryChoice.atDayPart('nap')))).kind, SubmitKind.invalid);
      expect(r.server.log, isEmpty, reason: 'no request was made for any of them');
      expect(await r.outbox.load(), isEmpty);
    });
  });

  group('the server says no', () {
    test('no bedtime: refused in words, nothing kept, no retry', () async {
      final Rig r = Rig();
      r.server.dayParts = <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '19:30',
          'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true}];
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.refused);
      expect(o.text, allOf(contains('no bedtime'), contains("Mia's day")));
      expect(await r.outbox.load(), isEmpty, reason: 'a refusal is not queued to be refused again later');
      final FlushResult f = await r.service.flush(force: true);
      expect(f.sent + f.refused + f.stillWaiting, 0);
      expect(r.server.messageCalls, 1);
    });

    test('right away still works with no bedtime (it is the way out for a day not set up yet)', () async {
      final Rig r = Rig();
      r.server.dayParts = <Map<String, dynamic>>[];
      expect((await r.service.submit(draft(choice: const DeliveryChoice.now()))).kind, SubmitKind.sent);
    });

    test('a file the server does not accept (415) is refused and nothing is kept', () async {
      final Rig r = Rig();
      final SubmitOutcome o = await r.service.submit(draft(bytes: 'GIF89a....'.codeUnits));
      expect(o.kind, SubmitKind.refused);
      expect(o.text, contains("can't be sent"));
      expect(await r.outbox.load(), isEmpty);
      expect(r.server.messageCalls, 0, reason: 'it never got as far as a message');
    });

    test('a wrong child is a refusal', () async {
      final Rig r = Rig(childId: kOtherChild);
      expect((await r.service.submit(draft())).kind, SubmitKind.refused);
      expect(await r.outbox.load(), isEmpty);
    });
  });

  group('the server cannot be reached', () {
    test('no network: kept on this phone, said so, never called sent', () async {
      final Rig r = Rig();
      r.server.offline = true;
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.queued);
      expect(o.text, allOf(contains('saved on this phone'), contains('Nothing is lost')));
      expect(o.text, isNot(contains('Sent.')));
      final List<QueuedSend> q = await r.outbox.load();
      expect(q, hasLength(1));
      expect(q.single.attempts, 1);
      expect(q.single.lastCode, 'offline');
      expect(q.single.phase, QueuePhase.waiting);
      expect(q.single.statusLine('Mia', now: DateTime.now()), allOf(contains('hasn\'t reached the server'), contains('does not have it')));
    });

    test('when it comes back the same bytes go, once, and the outbox empties', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      r.server.offline = false;
      r.minutes(5);
      final FlushResult f = await r.service.flush();
      expect(f.sent, 1);
      expect(await r.outbox.load(), isEmpty);
      expect(r.server.messageCalls, 1);
      expect(r.server.sent, hasLength(1));
    });

    test('a busy server keeps it, and the upload that already went is not repeated', () async {
      final Rig r = Rig();
      r.server.failMessageTimes = 1;
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.queued);
      final QueuedSend q = (await r.outbox.load()).single;
      expect(q.storageKey, isNotNull, reason: 'the upload was kept');
      expect(q.lastCode, 'busy');
      expect(r.server.uploadCalls, 1);
      r.minutes(5);
      final FlushResult f = await r.service.flush();
      expect(f.sent, 1);
      expect(r.server.uploadCalls, 1, reason: 'no second upload');
      expect(r.server.messageCalls, 2, reason: 'one that failed, one that went');
      expect(r.server.sent, hasLength(1));
    });

    test('a 401 keeps it and says the phone needs to sign in', () async {
      final Rig r = Rig();
      r.server.unauthorizedNext = 5;
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.queued);
      expect(o.text, contains('sign in'));
      expect((await r.outbox.load()).single.lastCode, 'sign_in');
      expect((await r.outbox.load()).single.statusLine('Mia', now: DateTime.now()), contains('sign in again'));
    });

    test('a lost reply never sends twice: the retry finds the key already attached and counts as sent', () async {
      final Rig r = Rig();
      r.server.dropNextMessageReply = true;
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.queued, reason: 'the phone never heard the server say yes');
      expect(r.server.sent, hasLength(1), reason: 'but the server did take it');
      r.minutes(5);
      final FlushResult f = await r.service.flush();
      expect(f.sent, 1, reason: 'storage_key_in_use means the earlier try went through');
      expect(r.server.sent, hasLength(1), reason: 'exactly one message exists');
      expect(await r.outbox.load(), isEmpty);
    });

    test('an upload the server has since lost is uploaded again, once', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      r.server.offline = false;
      // the server forgets the upload (swept) while it waited
      (await r.outbox.load());
      final QueuedSend q = (await r.outbox.load()).single;
      await r.outbox.save(q.copyWith(storageKey: 'children/$kChild/messages/00000000-0000-4000-8000-0000000000ff'));
      r.minutes(5);
      final FlushResult f = await r.service.flush();
      expect(f.sent, 1);
      expect(r.server.uploadCalls, 1);
    });
  });

  group('waiting, patiently', () {
    test('a retry waits out its backoff: nothing is sent two seconds after a failure, then it is tried', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      final int calls = r.server.log.length;
      r.server.offline = false;
      r.now += 2000;
      expect((await r.service.flush()).sent, 0);
      expect(r.server.log.length, calls, reason: 'inside the wait there is no request at all');
      r.minutes(3);
      expect((await r.service.flush()).sent, 1);
    });

    test('Try now ignores the wait', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      r.server.offline = false;
      expect((await r.service.flush(force: true)).sent, 1);
    });

    test('after eight failed tries it stops on its own and says so; Try now still works', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      for (int i = 0; i < 12; i++) {
        r.minutes(24 * 60);
        await r.service.flush();
      }
      QueuedSend q = (await r.outbox.load()).single;
      expect(q.attempts, 8);
      expect(q.statusLine('Mia', now: DateTime.now()), contains('after several tries'));
      final int calls = r.server.log.length;
      r.minutes(24 * 60);
      await r.service.flush();
      expect(r.server.log.length, calls, reason: 'no further automatic tries');
      r.server.offline = false;
      expect((await r.service.flush(force: true)).sent, 1);
      expect(await r.outbox.load(), isEmpty);
    });

    test('the first "not now" ends the pass: the rest are not hammered', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      r.minutes(1);
      await r.service.submit(draft());
      r.minutes(10);
      final int calls = r.server.log.length;
      await r.service.flush();
      expect(r.server.log.length - calls, 1, reason: 'one failed upload, then the pass stopped');
    });

    test('two passes at once do not both run', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      r.server.offline = false;
      r.minutes(5);
      final List<FlushResult> both = await Future.wait(<Future<FlushResult>>[r.service.flush(), r.service.flush()]);
      expect(both.where((FlushResult f) => f.skipped), hasLength(1));
      expect(r.server.sent, hasLength(1));
    });
  });

  group('a "right away" that waited is not sent late on its own', () {
    test('past half an hour it asks, and sends nothing', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft(choice: const DeliveryChoice.now()));
      r.server.offline = false;
      r.minutes(31);
      final FlushResult f = await r.service.flush();
      expect(f.sent, 0);
      expect(f.needChoice, 1);
      final QueuedSend q = (await r.outbox.load()).single;
      expect(q.phase, QueuePhase.needsChoice);
      expect(q.statusLine('Mia', now: DateTime.now()), contains('meant to go right away'));
      expect(r.server.messageCalls, 0);
    });

    test('Send it now sends it, as now, with a fresh clock', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft(choice: const DeliveryChoice.now()));
      r.server.offline = false;
      r.minutes(90);
      await r.service.flush();
      final SubmitOutcome o = await r.service.resolve('m1');
      expect(o.kind, SubmitKind.sent);
      expect(r.server.where('POST', '/messages').single.body['delivery'], 'now');
    });

    test('or it can be moved to bedtime and goes as that', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft(choice: const DeliveryChoice.now()));
      r.server.offline = false;
      r.minutes(90);
      await r.service.flush();
      final SubmitOutcome o = await r.service.resolve('m1', choice: const DeliveryChoice.atDayPart('bedtime'));
      expect(o.kind, SubmitKind.sent);
      expect(r.server.where('POST', '/messages').single.body['delivery'], 'daypart');
    });

    test('but a bedtime or night message that waited long still goes as chosen', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft());
      r.server.offline = false;
      r.minutes(24 * 60);
      expect((await r.service.flush()).sent, 1);
    });

    test('a night that passed while it waited is refused in words, not delivered a night late', () async {
      final Rig r = Rig();
      r.server.offline = true;
      await r.service.submit(draft(choice: const DeliveryChoice.onNight('2026-11-15')), today: DateTime(2026, 11, 15));
      r.server.offline = false;
      // time moves on past the server's idea of "past" for that night (the fake treats before 14 Nov as past; use an older night)
      final QueuedSend q = (await r.outbox.load()).single;
      await r.outbox.save(q.copyWith(wire: const DeliveryChoice.onNight('2026-11-01').toWire()));
      r.minutes(5);
      final FlushResult f = await r.service.flush();
      expect(f.refused, 1);
      final QueuedSend after = (await r.outbox.load()).single;
      expect(after.phase, QueuePhase.refused);
      expect(after.refusedText, contains('already passed'));
      expect(after.mediaB64, isEmpty, reason: 'the bytes are let go');
      expect(after.statusLine('Mia', now: DateTime.now()), contains('already passed'));
      await r.service.discard(after.id);
      expect(await r.outbox.load(), isEmpty);
    });
  });

  group('room on the phone', () {
    test('three may wait; the fourth is not kept, and the sender is told it was not sent', () async {
      final Rig r = Rig();
      r.server.offline = true;
      for (int i = 0; i < kMaxQueued; i++) {
        expect((await r.service.submit(draft())).kind, SubmitKind.queued);
      }
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.notKept);
      expect(o.text, allOf(contains('already $kMaxQueued'), contains("wasn't sent")));
      expect(await r.outbox.load(), hasLength(kMaxQueued));
    });

    test('something too big to keep still goes when the server is there, and is not kept when it is not', () async {
      final Rig r = Rig();
      final List<int> big = <int>[...jpegBytes(), ...List<int>.filled(kMaxKeptBytes + 10, 3)];
      expect((await r.service.submit(draft(bytes: big))).kind, SubmitKind.sent);
      r.server.offline = true;
      final SubmitOutcome o = await r.service.submit(draft(bytes: big));
      expect(o.kind, SubmitKind.notKept);
      expect(o.text, contains('too big to keep'));
      expect(await r.outbox.load(), isEmpty);
    });

    test('a full phone still sends when it can, and says so when it cannot keep', () async {
      final MemorySendOutbox full = MemorySendOutbox()..failSaves = true;
      final Rig r = Rig(outbox: full);
      expect((await r.service.submit(draft())).kind, SubmitKind.sent);
      r.server.offline = true;
      final SubmitOutcome o = await r.service.submit(draft());
      expect(o.kind, SubmitKind.notKept);
      expect(o.text, contains('no room'));
    });
  });

  group('whose messages these are', () {
    test('another child\'s waiting message is neither listed nor sent', () async {
      final MemorySendOutbox shared = MemorySendOutbox();
      final Rig a = Rig(outbox: shared);
      a.server.offline = true;
      await a.service.submit(draft());
      final Rig b = Rig(childId: kOtherChild, outbox: shared);
      expect(await b.service.waiting(), isEmpty);
      b.minutes(10);
      await b.service.flush();
      expect(b.server.log, isEmpty);
      expect(await shared.load(), hasLength(1));
    });
  });

  group('the sealed on-device outbox', () {
    late LocalServices services;
    setUp(() => services = LocalServices.memory(childId: kChild, guardianId: kGuardian, isLive: true));

    LocalStoreSendOutbox over() => LocalStoreSendOutbox.forGuardian(kGuardian);

    test('survives a restart and is sealed (the file does not hold the message in the clear)', () async {
      LocalServices.install(services);
      final Rig r = Rig(outbox: over());
      r.server.offline = true;
      await r.service.submit(draft(bytes: <int>[...jpegBytes(), ...utf8.encode('VERY-IDENTIFIABLE-MARKER-1234')]));
      // a new "run" over the same storage
      final LocalStoreSendOutbox again = over();
      final List<QueuedSend> q = await again.load();
      expect(q, hasLength(1));
      expect(base64Decode(q.single.mediaB64).length, greaterThan(30));
      final MemoryStoreBackend backend = services.store.backend as MemoryStoreBackend;
      final String name = 'guardian.$kGuardian.sendoutbox';
      final List<int>? raw = await backend.read(name);
      expect(raw, isNotNull);
      expect(utf8.decode(raw!, allowMalformed: true), isNot(contains('VERY-IDENTIFIABLE')));
      expect(utf8.decode(raw, allowMalformed: true), isNot(contains(base64Encode(utf8.encode('VERY-IDENTIFIABLE')).substring(0, 12))));
    });

    test('records that are not exactly what is written are skipped, never sent', () async {
      LocalServices.install(services);
      final LocalNamespace ns = services.area('sendoutbox', ownerId: kGuardian);
      final Map<String, Object?> good = QueuedSend(
        id: 'ok1', childId: kChild, createdAtMs: 5, wire: const DeliveryChoice.now().toWire(),
        mediaKind: MediaKind.photo, durationMs: 1, mediaB64: base64Encode(jpegBytes()),
      ).toJson();
      await ns.put('q.ok1', good);
      await ns.put('q.badchild', <String, Object?>{...good, 'id': 'badchild', 'childId': '../../etc/passwd'});
      await ns.put('q.badwire', <String, Object?>{...good, 'id': 'badwire', 'wire': <String, Object?>{'delivery': 'soon'}});
      await ns.put('q.badphase', <String, Object?>{...good, 'id': 'badphase', 'phase': 'sending'});
      await ns.put('q.empty', <String, Object?>{...good, 'id': 'empty', 'media': ''});
      await ns.put('q.mismatch', <String, Object?>{...good, 'id': 'someother'});
      await ns.put('q.junk', 'not a map');
      await ns.put('q.codebad', <String, Object?>{...good, 'id': 'codebad', 'lastCode': 'x; rm -rf /'});
      await ns.put('q.attempts', <String, Object?>{...good, 'id': 'attempts', 'attempts': -4});
      await ns.put('other', <String, Object?>{'whatever': 1});
      final LocalStoreSendOutbox o = over();
      final List<QueuedSend> loaded = await o.load();
      expect(loaded.map((QueuedSend q) => q.id), <String>['ok1']);
      expect(o.skipped, 8);
    });

    test('a refused record keeps no bytes and a waiting one must have them', () {
      final Map<String, Object?> base = QueuedSend(
        id: 'a', childId: kChild, createdAtMs: 1, wire: const DeliveryChoice.now().toWire(),
        mediaKind: MediaKind.video, durationMs: 5, mediaB64: 'AAAA', phase: QueuePhase.refused, refusedText: 'no',
      ).toJson();
      expect(QueuedSend.fromJson(<String, Object?>{...base, 'media': ''}), isNotNull);
      expect(QueuedSend.fromJson(<String, Object?>{...base, 'phase': 'waiting', 'media': ''}), isNull);
    });

    test('the catalogue knows the area, seals it, and keeps it per grown-up', () {
      final LocalDataEntry e = localDataEntry('sendoutbox');
      expect(e.encrypted, isTrue);
      expect(e.scope, LocalScope.guardian);
      expect(e.what, contains('never shown in her app'));
      expect(services.namespaceName(e, ownerId: kGuardian), 'guardian.$kGuardian.sendoutbox');
    });
  });

  test('a server error text is never raw: no status code or reason string reaches the outcome', () async {
    final Rig r = Rig();
    r.server.failStatus = 500;
    r.server.failNextWith = 1;
    final SubmitOutcome o = await r.service.submit(draft());
    expect(o.text, isNot(contains('500')));
    expect(o.text, isNot(contains('unavailable')));
  });

  test('a socket error is the same as no network', () async {
    final GuardianSendService svc = GuardianSendService(
      childId: kChild, childName: 'Mia', outbox: MemorySendOutbox(), closeApi: false,
      openApi: () async => throw const SocketException('x'));
    expect((await svc.submit(draft())).kind, SubmitKind.queued);
  });
}
