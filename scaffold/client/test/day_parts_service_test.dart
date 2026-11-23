// OLIVE BRANCH — reading and saving her day-parts (day_parts_service.dart), headless, against a stand-in written from
// the real routes (support/fake_delivery_server.dart). MASTERFILE section 8.31.
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/day_parts_service.dart';
import 'package:olive_client/guardian_send_logic.dart';

import 'support/fake_delivery_server.dart';

DayPartsService svc(FakeDeliveryServer s) => DayPartsService(
    childId: kChild, openApi: () async => OliveApi(kBase, 'tok', client: s.client), closeApi: false);

DayPartSpan p(String kind, String s, String e,
        {List<int> days = const <int>[0, 1, 2, 3, 4, 5, 6], bool reachable = true}) =>
    DayPartSpan(kind: kind, startsLocal: s, endsLocal: e, daysOfWeek: days, reachable: reachable);

void main() {
  group('reading her day', () {
    test('the seeded schedule comes back as the placeholder', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final List<DayPartSpan> parts = await svc(s).load();
      expect(parts, hasLength(4));
      expect(isPlaceholderSchedule(parts), isTrue);
      expect(s.where('GET', '/day-parts').single.auth, isTrue);
    });

    test('a reply that is not a schedule is an error, not an empty schedule you could then save over the real one', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      s.dayParts = <Map<String, dynamic>>[<String, dynamic>{'kind': 'free'}];
      await expectLater(svc(s).load(), throwsFormatException);
    });

    test('no network and a refusal surface as they are', () async {
      final FakeDeliveryServer s = FakeDeliveryServer()..offline = true;
      await expectLater(svc(s).load(), throwsA(isNot(isA<ApiException>())));
      final FakeDeliveryServer t = FakeDeliveryServer();
      final DayPartsService other = DayPartsService(
          childId: kOtherChild, openApi: () async => OliveApi(kBase, 't', client: t.client), closeApi: false);
      await expectLater(other.load(), throwsA(isA<ApiException>()));
    });
  });

  group('saving her day', () {
    test('a good edit is sent whole, in the shape the route reads, and the server\'s answer is what comes back', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final DayPartsService d = svc(s);
      final List<DayPartSpan> base = await d.load();
      final List<DayPartSpan> edited = <DayPartSpan>[
        for (final DayPartSpan x in base) x.kind == 'bedtime' ? x.copyWith(startsLocal: '19:45') : x,
      ];
      final SaveResult r = await d.save(edited: edited, baseline: base);
      expect(r.kind, SaveKind.saved);
      expect(r.text, contains('timed again'));
      expect(r.parts!.firstWhere((DayPartSpan x) => x.kind == 'bedtime').startsLocal, '19:45');
      final Seen put = s.where('PUT', '/day-parts').single;
      expect(put.auth, isTrue);
      expect(put.body.keys.toSet(), <String>{'dayParts'});
      final List<dynamic> sentParts = put.body['dayParts'] as List<dynamic>;
      expect(sentParts, hasLength(4));
      expect((sentParts.first as Map<String, dynamic>).keys.toSet(),
          <String>{'kind', 'startsLocal', 'endsLocal', 'daysOfWeek', 'reachable'});
    });

    test('it reads the schedule again first and will not write over what someone else saved meanwhile', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final DayPartsService d = svc(s);
      final List<DayPartSpan> base = await d.load();
      // the other parent saves a different bedtime while this editor is open
      s.dayParts = <Map<String, dynamic>>[
        for (final Map<String, dynamic> x in s.dayParts)
          x['kind'] == 'bedtime' ? <String, dynamic>{...x, 'startsLocal': '19:00'} : x,
      ];
      final SaveResult r = await d.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base) x.kind == 'asleep' ? x.copyWith(startsLocal: '21:00') : x],
          baseline: base);
      expect(r.kind, SaveKind.changedElsewhere);
      expect(r.text, contains('Someone changed her day'));
      expect(r.parts!.firstWhere((DayPartSpan x) => x.kind == 'bedtime').startsLocal, '19:00');
      expect(s.putCount, 0, reason: 'nothing was written');
    });

    test('a schedule the server would refuse is told in words with no request made', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final DayPartsService d = svc(s);
      final List<DayPartSpan> base = await d.load();
      final SaveResult r = await d.save(edited: <DayPartSpan>[...base, p('bedtime', '20:00', '21:00')], baseline: base);
      expect(r.kind, SaveKind.invalid);
      expect(r.text, contains('Bedtime is set twice'));
      final SaveResult e = await d.save(edited: <DayPartSpan>[], baseline: base);
      expect(e.kind, SaveKind.invalid);
      expect(s.log.where((Seen x) => x.method == 'PUT'), isEmpty);
      expect(s.log, isEmpty, reason: 'not even the re-read');
    });

    test('only one save at a time: a second tap while one runs is told so and sends nothing', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      s.holdPut = Completer<void>();
      final DayPartsService d = svc(s);
      final List<DayPartSpan> base = await d.load();
      final List<DayPartSpan> edited = <DayPartSpan>[
        for (final DayPartSpan x in base) x.kind == 'wake' ? x.copyWith(endsLocal: '08:30') : x];
      final Future<SaveResult> first = d.save(edited: edited, baseline: base);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(d.saving, isTrue);
      final SaveResult second = await d.save(edited: edited, baseline: base);
      expect(second.kind, SaveKind.busy);
      s.holdPut!.complete();
      expect((await first).kind, SaveKind.saved);
      expect(s.putCount, 1);
      expect(s.maxConcurrentPuts, 1);
      expect(d.saving, isFalse);
    });

    test('two phones saving together reach the server one after the other, never merged', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      s.holdPut = Completer<void>();
      final DayPartsService a = svc(s), b = svc(s);
      final List<DayPartSpan> base = await a.load();
      final Future<SaveResult> ra = a.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base) x.kind == 'wake' ? x.copyWith(endsLocal: '08:30') : x],
          baseline: base);
      final Future<SaveResult> rb = b.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base) x.kind == 'wake' ? x.copyWith(endsLocal: '07:45') : x],
          baseline: base);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      s.holdPut!.complete();
      final List<SaveResult> both = await Future.wait(<Future<SaveResult>>[ra, rb]);
      // both pass the re-read (neither had written yet) so both PUTs reach the server; the server's per-child lock
      // serialises them and the last one wins WHOLE. The schedule is one of the two, never a blend.
      expect(both.every((SaveResult r) => r.kind == SaveKind.saved), isTrue);
      final List<DayPartSpan> now = await svc(s).load();
      expect(now, hasLength(4), reason: 'never a union of the two (two wakes)');
      expect(now.where((DayPartSpan x) => x.kind == 'wake'), hasLength(1));
    });

    test('a refusal from the server changes nothing, says why, and is not retried', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final DayPartsService d = svc(s);
      final List<DayPartSpan> base = await d.load();
      final SaveResult r = await d.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base) x.kind == 'wake' ? x.copyWith(endsLocal: '09:00') : x],
          baseline: base);
      expect(r.kind, SaveKind.saved);
      // now a 503 on the PUT: the re-read passes, the PUT is unavailable
      final DayPartsService d2 = svc(s);
      final List<DayPartSpan> base2 = await d2.load();
      int puts = 0;
      final DayPartsService flaky = DayPartsService(
        childId: kChild, closeApi: false,
        openApi: () async => OliveApi(kBase, 'tok', client: InterceptingClient(s.client, (http.BaseRequest q) {
          if (q.method != 'PUT') return null;
          puts++;
          return streamedJson(503, '{"error":"unavailable"}');
        })),
      );
      final SaveResult f = await flaky.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base2) x.kind == 'wake' ? x.copyWith(endsLocal: '09:15') : x],
          baseline: base2);
      expect(f.kind, SaveKind.failed);
      expect(f.text, contains('Nothing was changed'));
      expect(puts, 1, reason: 'one attempt: a repeated PUT could overwrite someone else\'s newer schedule');
      expect((await svc(s).load()).firstWhere((DayPartSpan x) => x.kind == 'wake').endsLocal, '09:00');
    });

    test('no network is "could not reach the server", and nothing is claimed saved', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final DayPartsService d = svc(s);
      final List<DayPartSpan> base = await d.load();
      s.offline = true;
      final SaveResult r = await d.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base) x.kind == 'wake' ? x.copyWith(endsLocal: '09:00') : x],
          baseline: base);
      expect(r.kind, SaveKind.failed);
      expect(r.text, contains('could not reach the server'));
      expect(d.saving, isFalse);
    });

    test('an answer to the PUT that cannot be read is not called a success', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      bool putSeen = false;
      final DayPartsService d = DayPartsService(
        childId: kChild, closeApi: false,
        openApi: () async => OliveApi(kBase, 'tok', client: InterceptingClient(s.client, (http.BaseRequest q) {
          if (q.method == 'PUT') {
            putSeen = true;
            return streamedJson(200, '<html>login</html>');
          }
          if (putSeen) throw const SocketException('offline after');
          return null;
        })),
      );
      final List<DayPartSpan> base = await svc(s).load();
      final SaveResult r = await d.save(
          edited: <DayPartSpan>[for (final DayPartSpan x in base) x.kind == 'wake' ? x.copyWith(endsLocal: '09:00') : x],
          baseline: base);
      expect(r.kind, SaveKind.failed);
      expect(r.text, contains('not certain'));
    });
  });
}
