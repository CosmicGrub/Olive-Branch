// OLIVE BRANCH — the guardian send path against the REAL route shapes. No longer UNVERIFIED —
// run by CI. MASTERFILE §8.31, §7.
//
// Two halves, neither needing a device:
//
//  A. The real OliveApi, through the real adapter and service, against a mock HTTP server: the
//     exact method, path, headers and JSON body of every call, and the real response shapes read
//     back. If the client drifts from the routes (a renamed field, a different path), this fails.
//  B. The server's own SOURCE read from the repository: the day-part kinds, the limits, the time
//     format, every error word the client maps, and the body fields POST .../messages reads. If
//     the server changes one of them, this fails here, not on a family's phone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/guardian_send_logic.dart';
import 'package:olive_client/guardian_send_service.dart';
import 'package:olive_client/local_services.dart';

const String kChild = 'aaaaaaaa-0000-4000-8000-000000000001';
const String kKey = 'children/aaaaaaaa-0000-4000-8000-000000000001/messages/11111111-1111-4111-8111-111111111111';

class _Wire {
  final List<http.Request> seen = <http.Request>[];
  Map<String, Object?> dayParts = <String, Object?>{
    'dayParts': <Object?>[
      <String, Object?>{'kind': 'bedtime', 'startsLocal': '19:30', 'endsLocal': '20:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
      <String, Object?>{'kind': 'asleep', 'startsLocal': '20:30', 'endsLocal': '06:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': false},
    ],
    'hasBedtime': true,
  };
  int? mediaStatus;
  String mediaError = 'x';
  int? messageStatus;
  String messageError = 'x';

  MockClient client() => MockClient((http.Request req) async {
        seen.add(req);
        final String m = req.method, p = req.url.path;
        http.Response json(int s, Object? b) =>
            http.Response(jsonEncode(b), s, headers: <String, String>{'content-type': 'application/json'});
        if (m == 'POST' && p == '/v1/children/$kChild/media') {
          if (mediaStatus != null) return json(mediaStatus!, <String, Object?>{'error': mediaError});
          return json(201, <String, Object?>{'storageKey': kKey, 'etag': 'abc', 'mime': 'video/mp4'});
        }
        if (m == 'POST' && p == '/v1/children/$kChild/messages') {
          if (messageStatus != null) return json(messageStatus!, <String, Object?>{'error': messageError});
          return json(201, <String, Object?>{'id': '22222222-2222-4222-8222-222222222222', 'artifactId': '33333333-3333-4333-8333-333333333333', 'state': 'ready'});
        }
        if (m == 'GET' && p == '/v1/children/$kChild/sent') {
          return json(200, <String, Object?>{
            'messages': <Object?>[
              <String, Object?>{'id': 'a1a1a1a1', 'kind': 'video_msg', 'state': 'waiting', 'sentAt': '2026-11-20T10:00:00.000Z', 'deliversAt': '2026-11-21T01:30:00.000Z', 'deliveredAt': null, 'openedAt': null, 'receipt': null},
              <String, Object?>{'id': 'b2b2b2b2', 'kind': 'video_msg', 'state': 'opened', 'sentAt': '2026-11-19T10:00:00.000Z', 'deliversAt': null, 'deliveredAt': '2026-11-20T01:30:00.000Z', 'openedAt': '2026-11-20T01:42:00.000Z', 'receipt': <String, Object?>{'localTime': '7:42 PM', 'zone': 'America/New_York', 'phrase': 'Watched at 7:42 PM her time — at bedtime.'}},
            ],
          });
        }
        if (p == '/v1/children/$kChild/day-parts') {
          if (m == 'GET') return json(200, dayParts);
          if (m == 'PUT') {
            final Map<String, dynamic> b = jsonDecode(req.body) as Map<String, dynamic>;
            dayParts = <String, Object?>{'dayParts': b['dayParts'], 'hasBedtime': (b['dayParts'] as List<dynamic>).any((dynamic x) => (x as Map<String, dynamic>)['kind'] == 'bedtime')};
            return json(200, dayParts);
          }
        }
        if (m == 'GET' && p == '/v1/children/$kChild/now') {
          return json(200, <String, Object?>{'childLocalTime': '9:14 PM', 'zoneAbbr': 'EST', 'zone': 'America/New_York', 'dayPart': 'asleep', 'reachable': false, 'dayParts': <Object?>[]});
        }
        return json(404, <String, Object?>{'error': 'not_found'});
      });
}

void main() {
  group('A. the client on the wire', () {
    late _Wire wire;

    setUp(() => wire = _Wire());

    // OliveApi built straight, because a live GuardianSendService reaches it through apiFor(), which
    // needs a signed-in session. The adapter and the service use exactly these methods.
    OliveApi direct() => OliveApi('http://api.test', 'tok', client: wire.client());

    test('upload then send: paths, auth, and the exact JSON fields the route reads', () async {
      final OliveApi api = direct();
      final String key = await api.uploadMedia(kChild, <int>[1, 2, 3]);
      expect(key, kKey);
      final Map<String, dynamic> r = await api.sendMessage(kChild,
          storageKey: key, durationMs: 4000, daypart: 'bedtime', targetLocalDate: '2026-12-24');
      expect(r['id'], isA<String>());
      expect(r['state'], 'ready');

      final http.Request up = wire.seen[0], send = wire.seen[1];
      expect(up.method, 'POST');
      expect(up.url.path, '/v1/children/$kChild/media');
      expect(up.headers['authorization'], 'Bearer tok');
      expect(up.headers['content-type'], contains('application/json'));
      expect(jsonDecode(up.body), <String, Object?>{'bytes': base64Encode(<int>[1, 2, 3])});

      expect(send.method, 'POST');
      expect(send.url.path, '/v1/children/$kChild/messages');
      final Map<String, dynamic> body = jsonDecode(send.body) as Map<String, dynamic>;
      expect(body['storageKey'], kKey);
      expect(body['durationMs'], 4000);
      expect(body['daypart'], 'bedtime');
      expect(body['targetLocalDate'], '2026-12-24');
      expect(body.containsKey('preserve'), isFalse,
          reason: 'omitted so the server applies the standing rule: a grown-up\'s message is kept');
      expect(body.containsKey('senderId') || body.containsKey('childId'), isFalse,
          reason: 'identity is the session, never the body');
    });

    test('a next-bedtime send carries no date at all', () async {
      final OliveApi api = direct();
      await api.sendMessage(kChild, storageKey: kKey, durationMs: 1, daypart: 'wake');
      final Map<String, dynamic> body = jsonDecode(wire.seen.single.body) as Map<String, dynamic>;
      expect(body.containsKey('targetLocalDate'), isFalse);
      expect(body['daypart'], 'wake');
    });

    test('the sent list: GET path, and the real response shape is read into plain sentences', () async {
      final OliveApi api = direct();
      final ({List<SentRow> rows, int skipped}) p = parseSent(await api.fetchSentMessages(kChild));
      expect(wire.seen.single.method, 'GET');
      expect(wire.seen.single.url.path, '/v1/children/$kChild/sent');
      expect(p.skipped, 0);
      expect(p.rows.map((SentRow r) => r.state), <String>['waiting', 'opened']);
      expect(sentStatusWords(p.rows[0], setFor: 'at bedtime'), startsWith('Waiting to arrive at bedtime.'));
      expect(sentStatusWords(p.rows[1]), 'Watched at 7:42 PM her time — at bedtime.');
    });

    test('day-parts: GET reads the real shape; PUT sends {dayParts:[...]} with the wire keys and gets the new schedule', () async {
      final OliveApi api = direct();
      final DayPartsView v = DayPartsView.parse(await api.fetchDayParts(kChild));
      expect(v.parts.length, 2);
      expect(v.hasBedtime, isTrue);
      expect(wire.seen.single.url.path, '/v1/children/$kChild/day-parts');

      final List<DayPartEntry> edited = <DayPartEntry>[v.parts[0].copyWith(startsLocal: '19:00'), v.parts[1].copyWith(startsLocal: '20:30')];
      final Map<String, dynamic> res = await api.putDayParts(kChild, <Map<String, Object?>>[for (final DayPartEntry e in edited) e.toWire()]);
      final http.Request put = wire.seen.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/v1/children/$kChild/day-parts');
      expect(put.headers['authorization'], 'Bearer tok');
      final Map<String, dynamic> body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body.keys.toList(), <String>['dayParts']);
      final List<dynamic> parts = body['dayParts'] as List<dynamic>;
      expect((parts[0] as Map<String, dynamic>).keys.toSet(), <String>{'kind', 'startsLocal', 'endsLocal', 'daysOfWeek', 'reachable'});
      expect((parts[0] as Map<String, dynamic>)['daysOfWeek'], <int>[0, 1, 2, 3, 4, 5, 6]);
      expect(DayPartsView.parse(res).parts.first.startsLocal, '19:00');
    });

    test('the real adapter hits the same paths (OliveGuardianSendApi over OliveApi)', () async {
      final OliveGuardianSendApi adapter = OliveGuardianSendApi(direct(), ownsClient: false);
      await adapter.fetchDayParts(kChild);
      await adapter.fetchSent(kChild);
      await adapter.fetchNow(kChild);
      expect(wire.seen.map((http.Request r) => '${r.method} ${r.url.path}').toList(), <String>[
        'GET /v1/children/$kChild/day-parts',
        'GET /v1/children/$kChild/sent',
        'GET /v1/children/$kChild/now',
      ]);
    });

    test('a 400 from the media route is an ApiException with the server\'s word, then told in plain words', () async {
      wire.mediaStatus = 415;
      wire.mediaError = 'unsupported_media_type';
      try {
        await direct().uploadMedia(kChild, <int>[9]);
        fail('should throw');
      } on ApiException catch (e) {
        expect(e.statusCode, 415);
        expect(e.error, 'unsupported_media_type');
        final SendFailure f = classifyFailure(statusCode: e.statusCode, error: e.error);
        expect(f.cls, FailureClass.needsAttention);
        expect(f.words, contains('format'));
      }
    });

    test('a 403 not_a_child_surface on the sent list is a ForbiddenException, not a crash', () async {
      final MockClient m = MockClient((http.Request r) async => http.Response(jsonEncode(<String, Object?>{'error': 'not_a_child_surface'}), 403));
      await expectLater(OliveApi('http://api.test', 'tok', client: m).fetchSentMessages(kChild), throwsA(isA<ForbiddenException>()));
    });

    test('the path constants are the routes', () {
      expect(OliveApi.sentMessages, '/v1/children/:childId/sent');
      expect(OliveApi.dayParts, '/v1/children/:childId/day-parts');
      expect(OliveApi.messages, '/v1/children/:childId/messages');
      expect(OliveApi.media, '/v1/children/:childId/media');
    });
  });

  group('B. the server\'s own source', () {
    final String routes = File('../server/routes.mjs').readAsStringSync();
    final String pipeline = File('../packages/messaging/src/pipeline.ts').readAsStringSync();
    final String materialize = File('../packages/delivery-engine/src/materialize.ts').readAsStringSync();
    final String migration = File('../db/migrations/0001_phase0_init.sql').readAsStringSync();
    final String all = '$routes\n$pipeline\n$materialize';

    test('the routes this feature calls exist, with these methods', () {
      for (final String r in <String>[
        r"method: 'GET', path: '/v1/children/:childId/day-parts'",
        r"method: 'PUT', path: '/v1/children/:childId/day-parts'",
        r"method: 'GET', path: '/v1/children/:childId/sent'",
        r"method: 'POST', path: '/v1/children/:childId/messages'",
        r"method: 'POST', path: '/v1/children/:childId/media'",
        r"method: 'GET', path: '/v1/children/:childId/now'",
      ]) {
        expect(routes, contains(r), reason: r);
      }
    });

    test('the day-part kinds, the limit and the time format are the server\'s', () {
      final Match kinds = RegExp(r'const DAY_PART_KINDS = \[([^\]]*)\]').firstMatch(routes)!;
      final List<String> server = RegExp(r"'([a-z_]+)'").allMatches(kinds.group(1)!).map((Match m) => m.group(1)!).toList();
      expect(kDayPartKinds, server);
      expect(RegExp(r'const MAX_DAY_PARTS = (\d+)').firstMatch(routes)!.group(1), '$kMaxDayParts');
      expect(routes, contains(r'const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;'));
    });

    test('PUT reads {dayParts} and refuses an empty list; the overlap constraint is half-open with the next-day wrap', () {
      expect(routes, contains('c.body?.dayParts'));
      expect(routes, contains("error: 'day_parts_required'"));
      expect(File('../db/migrations/0042_domain_correctness.sql').readAsStringSync(),
          contains("WHEN ends_local < starts_local THEN interval '1 day'"));
    });

    test('POST .../messages reads exactly the body fields the client sends', () {
      for (final String f in <String>['body.storageKey', 'body.durationMs', 'body.targetLocalDate', 'body.daypart', 'body.preserve']) {
        expect(routes, contains(f), reason: f);
      }
      expect(routes, contains('c.principal.userId'), reason: 'sender is the session');
    });

    test('the delivery policy follows targetLocalDate, and no route can pick the immediate policy (so none is offered)', () {
      expect(pipeline, contains("policy: input.targetLocalDate ? 'on_local_date' : 'at_daypart'"));
      expect(pipeline, isNot(contains("'immediate'")), reason: 'if this changes, "send now" can finally be offered');
      expect(routes, isNot(contains("policy: 'immediate'")));
    });

    test('a named night falls back to 20:30 when the part does not run that day (the client says so)', () {
      expect(materialize, contains("part?.startsLocal ?? '20:30'"));
    });

    test('every error word the client turns into a sentence exists on the server', () {
      for (final String code in <String>[
        'daypart_undefined', 'target_date_in_past', 'already_expired', 'delivery_unresolvable', 'empty_recording',
        'not_authorized', 'child_sender_mismatch', 'unsupported_media_type', 'media_quota_exceeded', 'image_too_large',
        'bytes_required', 'bad_bytes', 'child_not_found', 'storage_key_not_yours', 'storage_key_in_use',
        'storage_key_unknown', 'bad_storage_key', 'day_parts_required', 'bad_day_part_kind', 'bad_day_part_time',
        'empty_day_part', 'bad_days_of_week', 'reachable_required', 'day_parts_overlap', 'bad_day_part',
        'not_a_child_surface',
      ]) {
        expect(all, contains(code), reason: 'the server no longer says "$code"');
      }
    });

    test('the sender\'s list states are the database\'s, and the client has a sentence for each', () {
      for (final String s in <String>['pending', 'ready', 'delivered', 'opened', 'expired', 'revoked']) {
        expect(migration, contains("'$s'"), reason: s);
      }
      expect(routes, contains("r.state === 'pending' || r.state === 'ready' ? 'waiting' : r.state"));
      for (final String s in <String>['waiting', 'delivered', 'opened', 'expired', 'revoked']) {
        expect(sentStatusWords(SentRow(id: 'zzzzzz1', state: s)), isNot(contains('cannot tell')), reason: s);
      }
    });

    test('the unreachable-night gap is real: no route takes a message back (so none is offered)', () {
      expect(RegExp(r"method: 'DELETE', path: '/v1/children/:childId/(messages|sent)").hasMatch(routes), isFalse);
    });

    test('the outbox area is catalogued sealed, guardian-scoped, and says nothing is shown to her', () {
      final LocalDataEntry e = localDataEntry('sendoutbox');
      expect(e.scope, LocalScope.guardian);
      expect(e.encrypted, isTrue);
      expect(e.what, contains('Nothing is ever shown to her'));
    });
  });
}
