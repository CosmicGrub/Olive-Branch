// OLIVE BRANCH — sending to the child and her day-parts, held to the REAL server routes. MASTERFILE section 8.31.
//
// The server's own route-drift test (packages/api/test/contract.test.mjs) fails when a server path has no Dart
// constant. This is the other half, in the style of family_account_contract_test.dart: it reads server/routes.mjs,
// packages/messaging/src/pipeline.ts, packages/db/src/pool.ts and server/media_sniff.mjs as text and fails when the
// CLIENT drifts from what the server registers, reads and answers:
//
//   * every call the send and day-parts flow makes is a registered route with the method and the session rule the
//     client assumes;
//   * the body the client sends is made only of keys the real handler reads, and includes all it needs;
//   * every error reason a send route can answer with, including the capture pipeline's, has a sentence in
//     guardian_send_logic.dart (and none is worded that the server can no longer say);
//   * the day-part kinds, limits, time format, default schedule and delivery choices are the server's own;
//   * every field the client reads from "what I sent" is a field the route returns;
//   * the file types the phone checks are the ones the server accepts;
//   * nothing child-side can reach these screens, and nothing in them logs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/day_parts_service.dart';
import 'package:olive_client/guardian_send_logic.dart';
import 'package:olive_client/guardian_send_service.dart';

import 'support/fake_delivery_server.dart';
import 'support/real_routes.dart';

String read(String relative) => File(relative).readAsStringSync().replaceAll('\r\n', '\n');

Set<String> quoted(String s) => <String>{for (final RegExpMatch m in RegExp(r"'([A-Za-z_ ]+)'").allMatches(s)) m.group(1)!};

void main() {
  final List<RealRoute> routes = loadRealRoutes();
  final String routesSrc = read('../server/routes.mjs');
  final String pipeline = read('../packages/messaging/src/pipeline.ts');
  final String pool = read('../packages/db/src/pool.ts');

  RealRoute route(String method, String path) {
    final RealRoute? r = findRoute(routes, method, path);
    expect(r, isNotNull, reason: 'server/routes.mjs registers no $method $path');
    return r!;
  }

  group('the routes this flow calls exist, with the method and the session rule the client assumes', () {
    final List<(String, String)> table = <(String, String)>[
      ('POST', OliveApi.media),
      ('POST', OliveApi.messages),
      ('GET', OliveApi.sentMessages),
      ('GET', OliveApi.dayParts),
      ('PUT', OliveApi.dayParts),
      ('GET', OliveApi.childNow),
    ];
    for (final (String method, String path) in table) {
      test('$method $path needs a session', () {
        expect(route(method, path).noSession, isFalse);
      });
    }
  });

  group('the bodies the client sends are what the real handlers read', () {
    test('upload and message, for every delivery choice', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final MemorySendOutbox box = MemorySendOutbox();
      final GuardianSendService svc = GuardianSendService(
        childId: kChild, childName: 'Mia', closeApi: false, outbox: box,
        openApi: () async => OliveApi(kBase, 'tok', client: s.client),
      );
      for (final DeliveryChoice c in <DeliveryChoice>[
        const DeliveryChoice.now(), const DeliveryChoice.atDayPart('wake'), DeliveryChoice.onNight(
            localDateString(DateTime.now().add(const Duration(days: 30))))]) {
        expect((await svc.submit(SendDraft(bytes: jpegBytes(), kind: MediaKind.photo, durationMs: 1, choice: c))).kind,
            SubmitKind.sent, reason: c.describe());
      }
      final RealRoute media = route('POST', OliveApi.media);
      for (final Seen u in s.where('POST', '/media')) {
        expect(u.body.keys.toSet().difference(media.bodyKeys), isEmpty, reason: 'upload keys the server does not read');
        expect(media.bodyKeys.difference(u.body.keys.toSet()), isEmpty);
      }
      final RealRoute msg = route('POST', OliveApi.messages);
      // routes.mjs reads this one as `const body = c.body ?? {}` then `body.<key>`
      final Set<String> read = <String>{for (final RegExpMatch m in RegExp(r'\bbody\.(\w+)').allMatches(msg.source)) m.group(1)!};
      expect(read, containsAll(<String>{'storageKey', 'durationMs', 'targetLocalDate', 'daypart', 'delivery', 'preserve'}));
      for (final Seen m in s.where('POST', '/messages')) {
        expect(m.body.keys.toSet().difference(read), isEmpty, reason: 'message keys the server does not read: ${m.body}');
        expect(m.body.keys, containsAll(<String>{'storageKey', 'durationMs'}));
      }
    });

    test('day-parts: the whole schedule, each part with only the fields the PUT reads', () async {
      final FakeDeliveryServer s = FakeDeliveryServer();
      final DayPartsService d = DayPartsService(
          childId: kChild, closeApi: false, openApi: () async => OliveApi(kBase, 'tok', client: s.client));
      final List<DayPartSpan> base = await d.load();
      await d.save(edited: <DayPartSpan>[...base.take(3)], baseline: base);
      final RealRoute put = route('PUT', OliveApi.dayParts);
      final Seen sent = s.where('PUT', '/day-parts').single;
      expect(sent.body.keys.toSet().difference(put.bodyKeys), isEmpty);
      final Set<String> partFields = <String>{for (final RegExpMatch m in RegExp(r'\bp\.(\w+)').allMatches(put.source)) m.group(1)!};
      for (final dynamic p in sent.body['dayParts'] as List<dynamic>) {
        expect((p as Map<String, dynamic>).keys.toSet().difference(partFields), isEmpty);
        expect(partFields.difference(p.keys.toSet()), isEmpty, reason: 'a field the PUT reads that the client never sends');
      }
    });
  });

  group('every answer the send routes can give has a sentence', () {
    Set<String> union(String name) {
      final int start = pipeline.indexOf('export type $name =');
      final String body = pipeline.substring(start, pipeline.indexOf(r';' + String.fromCharCode(10), start));
      return <String>{for (final RegExpMatch m in RegExp(r"^\s*\|\s*'([a-z_]+)'", multiLine: true).allMatches(body)) m.group(1)!};
    }

    test('the capture pipeline\'s denials, the message route\'s and the upload route\'s are all worded, and nothing stale is', () {
      final Set<String> server = <String>{
        ...union('CaptureDenial'),
        ...route('POST', OliveApi.messages).reasons,
        ...route('POST', OliveApi.media).reasons,
      }..remove('forbidden');
      // reasons that are not about sending (the media route's generic ones are all about sending; the others are)
      final Set<String> missing = server.difference(kWordedSendReasons);
      expect(missing, isEmpty, reason: 'the server can answer these with no sentence for a grown-up: $missing');
      final Set<String> stale = kWordedSendReasons.difference(server);
      expect(stale, isEmpty, reason: 'worded here but the server can no longer say: $stale');
    });

    test('every worded reason produces a sentence with no code or status in it', () {
      for (final String r in kWordedSendReasons) {
        final SendFailure f = explainSendFailure(ApiException(400, r), 'Mia');
        expect(f.text, isNotEmpty, reason: r);
        expect(f.text, isNot(contains(r)), reason: r);
        expect(f.text, isNot(contains('_')), reason: r);
      }
    });

    test('the day-parts PUT\'s refusals each have their own sentence, not the fallback', () {
      final String fallback = dayPartSaveFailure(ApiException(400, 'zzz_unknown'));
      final Set<String> reasons = route('PUT', OliveApi.dayParts).reasons..remove('not_a_child_surface');
      expect(reasons, containsAll(<String>{'day_parts_required', 'bad_day_part_kind', 'bad_day_part_time',
        'empty_day_part', 'bad_days_of_week', 'reachable_required', 'day_parts_overlap', 'bad_day_part'}));
      for (final String r in reasons) {
        expect(dayPartSaveFailure(ApiException(r == 'day_parts_overlap' ? 409 : 400, r)), isNot(fallback), reason: r);
      }
    });
  });

  group('the limits and lists are the server\'s own', () {
    test('the ten kinds, in the same words', () {
      final RegExpMatch m = RegExp(r'const DAY_PART_KINDS = \[([^\]]*)\]').firstMatch(routesSrc)!;
      expect(quoted(m.group(1)!), kDayPartKinds.toSet());
      expect(quoted(m.group(1)!).length, kDayPartKinds.length);
    });

    test('at most 24 parts', () {
      expect(RegExp(r'const MAX_DAY_PARTS = (\d+)').firstMatch(routesSrc)!.group(1), '$kMaxDayParts');
    });

    test('times are HH:MM exactly as the route checks them', () {
      expect(RegExp(r'const HHMM = /(.+)/;').firstMatch(routesSrc)!.group(1), r'^([01]\d|2[0-3]):[0-5]\d$');
      for (final String t in <String>['00:00', '23:59', '12:30']) {
        expect(parseHhmm(t), isNotNull);
      }
    });

    test('the delivery choices', () {
      final RegExpMatch m = RegExp(r'const DELIVERY_CHOICES = \[([^\]]*)\]').firstMatch(routesSrc)!;
      expect(quoted(m.group(1)!), <String>{'now', 'daypart', 'date'});
      expect(<String>{
        for (final DeliveryChoice c in <DeliveryChoice>[const DeliveryChoice.now(), const DeliveryChoice.atDayPart(),
          const DeliveryChoice.onNight('2026-12-24')]) c.toWire()['delivery']! as String,
      }, quoted(m.group(1)!));
    });

    test('the schedule seeded for a new child is the placeholder the editor recognises', () {
      final RegExpMatch block = RegExp(r'export const DEFAULT_DAY_PARTS[\s\S]*?\];').firstMatch(pool)!;
      final List<DayPartSpan> server = <DayPartSpan>[
        for (final RegExpMatch m in RegExp(
                r"kind: '(\w+)',\s+startsLocal: '(\d\d:\d\d)', endsLocal: '(\d\d:\d\d)', reachable: (true|false)")
            .allMatches(block.group(0)!))
          DayPartSpan(kind: m.group(1)!, startsLocal: m.group(2)!, endsLocal: m.group(3)!, reachable: m.group(4) == 'true'),
      ];
      expect(server, hasLength(4));
      expect(isPlaceholderSchedule(server), isTrue);
      expect(sameSchedule(server, kPlaceholderDayParts), isTrue);
    });

    test('the seeded schedule passes the editor\'s own check (so a new family can save without changing a thing)', () {
      expect(checkDayParts(kPlaceholderDayParts).canSave, isTrue);
    });

    test('the kinds she can land at in the server\'s database enumeration are the same ten', () {
      final String mig = read('../db/migrations/0042_domain_correctness.sql');
      final RegExpMatch m = RegExp(r'target_daypart IN \(([^)]*)\)').firstMatch(mig)!;
      expect(quoted(m.group(1)!), kDayPartKinds.toSet());
    });
  });

  group('what the client reads from "what I sent" is what the route returns', () {
    test('every field the parser reads is a field of the route\'s answer, and the stand-in returns exactly them', () {
      final RealRoute sent = route('GET', OliveApi.sentMessages);
      final int from = sent.source.indexOf('return {\n          id: r.id');
      expect(from, greaterThan(0), reason: 'the /sent row shape moved; update this test and the parser together');
      final String row = sent.source.substring(from, sent.source.indexOf('\n        };', from));
      final Set<String> serverKeys = <String>{
        for (final RegExpMatch m in RegExp(r'(?:^|\s|,)(\w+)(?::|,\s*$)', multiLine: true).allMatches(row)) m.group(1)!,
      }..remove('return');
      const Set<String> clientReads = <String>{
        'id', 'state', 'sentAt', 'delivery', 'daypart', 'targetLocalDate', 'deliversAt', 'deliversHer', 'deliveredHer',
        'receipt',
      };
      expect(serverKeys, containsAll(clientReads));
    });

    test('the stand-in\'s /sent row carries exactly the real route\'s keys', () async {
      final RealRoute sent = route('GET', OliveApi.sentMessages);
      final int from = sent.source.indexOf('return {\n          id: r.id');
      final String row = sent.source.substring(from, sent.source.indexOf('\n        };', from));
      final Set<String> serverKeys = <String>{
        for (final RegExpMatch m in RegExp(r'(?:^|\s|,)(\w+)(?::|,\s*$)', multiLine: true).allMatches(row)) m.group(1)!,
      }..remove('return');
      final FakeDeliveryServer f = FakeDeliveryServer();
      f.sent.add(SentRow('aaaaaaaa-0000-4000-8000-000000000001', 'daypart', 'bedtime', null));
      final Map<String, dynamic> body = await OliveApi(kBase, 't', client: f.client).fetchSent(kChild);
      final Map<String, dynamic> one = (body['messages'] as List<dynamic>).single as Map<String, dynamic>;
      expect(one.keys.toSet(), serverKeys);
    });

    test('the day-parts view and the message acknowledgement have the shapes the client reads', () {
      expect(routesSrc, contains('dayParts: rows.map((r) => ({'));
      expect(routesSrc, contains('hasBedtime: rows.some('));
      expect(route('POST', OliveApi.messages).source, contains('id: persisted.intentId'));
    });

    test('a quoted moment is { day, time } on the server too', () {
      final String src = route('GET', OliveApi.sentMessages).source + routesSrc;
      expect(src, contains('return { day, time: at.toFormat('));
    });
  });

  group('the file types the phone checks are the ones the server takes', () {
    test('audio brands', () {
      final String sniff = read('../server/media_sniff.mjs');
      final RegExpMatch m = RegExp(r'FTYP_AUDIO_BRANDS = new Set\(\[([^\]]*)\]').firstMatch(sniff)!;
      final Set<String> brands = <String>{for (final RegExpMatch q in RegExp(r"'([^']*)'").allMatches(m.group(1)!)) q.group(1)!};
      expect(brands, <String>{'M4A ', 'M4B ', 'M4P '});
      for (final String b in brands) {
        expect(sniffSendKind(<int>[0, 0, 0, 24, ...'ftyp'.codeUnits, ...b.codeUnits]), MediaKind.voice, reason: b);
      }
    });

    test('a size the phone will send is one the server\'s body limit allows', () {
      final String api = read('../packages/api/src/api.ts');
      final int mb = int.parse(RegExp(r'DEFAULT_MAX_REQUEST_BODY_BYTES = (\d+) \* 1024 \* 1024').firstMatch(api)!.group(1)!);
      // base64 makes bytes 4/3 bigger, plus a little JSON around it
      expect(kMaxSendBytes * 4 / 3 + 1024, lessThan(mb * 1024 * 1024));
    });
  });

  group('child safety and quiet', () {
    final List<File> lib = Directory('lib').listSync().whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
    final List<String> mine = <String>[
      'guardian_send_logic.dart', 'guardian_send_service.dart', 'guardian_send_screen.dart',
      'day_parts_service.dart', 'day_parts_editor_screen.dart',
    ];

    String base(File f) => f.path.split(RegExp(r'[\\/]')).last;

    test('only the grown-up\'s home and More (and each other) import them: nothing child-side can reach these screens', () {
      for (final File f in lib) {
        final String text = f.readAsStringSync();
        final bool imports = mine.any((String m) => text.contains("import '$m'")) ||
            text.contains("import 'guardian_send_") || text.contains("import 'day_parts_");
        if (!imports) continue;
        expect(
            <String>{'guardian_home.dart', 'guardian_more.dart', ...mine}.contains(base(f)),
            isTrue,
            reason: '${base(f)} imports a grown-up\'s send or day-parts file');
      }
    });

    test('no child file or kiosk file names them at all', () {
      for (final File f in lib) {
        final String b = base(f);
        if (!(b.startsWith('child_') || b.startsWith('kiosk') || b.startsWith('inbox') || b.startsWith('receipt'))) continue;
        final String text = f.readAsStringSync();
        for (final String m in mine) {
          expect(text, isNot(contains(m)), reason: '$b mentions $m');
        }
      }
    });

    test('they never log (no print, no debugPrint): messages and times are not written anywhere', () {
      for (final String m in mine) {
        final String text = File('lib/$m').readAsStringSync();
        expect(text, isNot(contains('print(')), reason: m);
        expect(text, isNot(contains('debugPrint(')), reason: m);
        expect(text, isNot(contains('developer.log')), reason: m);
      }
    });

    test('they carry the UNVERIFIED marker the transport suite requires, and name no address, key or id', () {
      for (final String m in mine) {
        final String text = File('lib/$m').readAsStringSync();
        expect(text, contains('UNVERIFIED'), reason: m);
        expect(text, isNot(matches(RegExp(r'https?://[a-z0-9.-]+\.[a-z]{2,}'))), reason: m);
        expect(text, isNot(matches(RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'))), reason: m);
      }
    });

    test('the sealed area is a grown-up\'s, not hers', () {
      final String ls = File('lib/local_services.dart').readAsStringSync();
      expect(ls, contains("area: 'sendoutbox', scope: LocalScope.guardian, encrypted: true"));
    });
  });
}
