// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — child_receive.dart: the child's receive path.
// MASTERFILE §7.19. Parsing what the delivery worker made ready, the global child-payload sweep, and the receipt
// queue that rides on the existing offline outbox.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/child_receive.dart';
import 'package:olive_client/inbox_screen.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/offline_outbox.dart';

/// The words of packages/globalaudit/src/globalaudit.ts GLOBAL_CHILD_FORBIDDEN, read from the TypeScript source so
/// this test and the product cannot drift from the server's own sweep.
Set<String> _tsForbidden() {
  final File f = File('../packages/globalaudit/src/globalaudit.ts');
  final String s = f.readAsStringSync();
  final int a = s.indexOf('export const GLOBAL_CHILD_FORBIDDEN = [');
  final int b = s.indexOf('] as const;', a);
  expect(a, greaterThan(-1));
  expect(b, greaterThan(a));
  final String body = s
      .substring(a, b)
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  return <String>{for (final RegExpMatch m in RegExp(r"'([^']+)'").allMatches(body)) m.group(1)!};
}

/// The sweep itself, in Dart: every key at any depth whose lower-cased name is on the list.
List<String> _leaks(Object? payload, Set<String> banned, [String path = '']) {
  final List<String> out = <String>[];
  if (payload is List) {
    for (int i = 0; i < payload.length; i++) {
      out.addAll(_leaks(payload[i], banned, '$path[$i]'));
    }
  } else if (payload is Map) {
    for (final MapEntry<dynamic, dynamic> e in payload.entries) {
      final String here = path.isEmpty ? '${e.key}' : '$path.${e.key}';
      if (banned.contains('${e.key}'.toLowerCase())) out.add(here);
      out.addAll(_leaks(e.value, banned, here));
    }
  }
  return out;
}

Map<String, Object?> _row(String id, {String state = 'delivered', String? kind = 'video_msg',
    Object? name = 'Dad', Object? label = '7:04 AM', Object? sid = 'g-1'}) =>
    <String, Object?>{'id': id, 'payload_kind': kind, 'state': state, 'sender_name': name,
      'sender_id': sid, 'deliveredAtLabel': label};

class _Mem {
  List<OutboxItem> items = <OutboxItem>[];
  DateTime now = DateTime.utc(2026, 11, 15, 12);
  late final ReceiptQueue queue = ReceiptQueue.over(
    load: () async => List<OutboxItem>.of(items),
    save: (List<OutboxItem> l) async => items = List<OutboxItem>.of(l),
    now: () => now,
  );
}

OutboxItem _receipt(String id, {int attempts = 1, DateTime? at, Object? payload}) => OutboxItem(
    id: 'receipt:$id', kind: OutboxKind.receipt, createdAt: at ?? DateTime.utc(2026, 11, 15, 11),
    payload: payload ?? <String, Object?>{'messageId': id}, attempts: attempts);

void main() {
  group('the mirror of the global child-payload sweep', () {
    test('kChildForbiddenWords equals GLOBAL_CHILD_FORBIDDEN in globalaudit.ts, in both directions', () {
      final Set<String> ts = _tsForbidden();
      final Set<String> dart = kChildForbiddenWords.toSet();
      expect(ts.length, greaterThan(100));
      expect(dart.difference(ts), isEmpty, reason: 'in Dart but not in the TypeScript list');
      expect(ts.difference(dart), isEmpty, reason: 'in the TypeScript list but missing from Dart');
      expect(kChildForbiddenWords.length, dart.length, reason: 'no duplicates');
    });
  });

  group('parseInbox — a whitelist, not a blacklist', () {
    test('the happy path: delivered and opened rows, in the server\'s order, with her-frame labels', () {
      final List<InboxMessage> m = parseInbox(<String, Object?>{
        'entries': <Object?>[_row('a'), _row('b', state: 'opened', name: 'Mom', label: 'Yesterday, 3:00 PM')]
      });
      expect(m.map((InboxMessage x) => x.id), <String>['a', 'b']);
      expect(m[0].watched, isFalse);
      expect(m[1].watched, isTrue);
      expect(m[1].senderName, 'Mom');
      expect(m[1].deliveredAtLabel, 'Yesterday, 3:00 PM');
      expect(m[0].senderId, 'g-1');
      expect(m[0].dayPartKind, isNull, reason: 'the server sends none; the client never invents one');
    });

    test('only delivered and opened are hers: ready, pending, expired, revoked and anything else are not', () {
      for (final Object? s in <Object?>['ready', 'pending', 'expired', 'revoked', 'DELIVERED', '', null, 3, true]) {
        expect(parseInbox(<String, Object?>{'entries': <Object?>[_row('a', state: '$s')..['state'] = s]}), isEmpty,
            reason: 'state $s');
      }
    });

    test('a missing payload_kind is a video (older servers); an unknown or homework kind is not drawn', () {
      expect(parseInbox(<String, Object?>{'entries': <Object?>[_row('a', kind: null)]}).single.kind, 'video_msg');
      for (final String k in <String>['homework', 'surprise', '', 'VIDEO_MSG', 'video_msg ']) {
        expect(parseInbox(<String, Object?>{'entries': <Object?>[_row('a', kind: k)]}), isEmpty, reason: k);
      }
    });

    test('every id that could change a URL or a path is refused (the id goes into POST .../inbox/:id/opened)', () {
      for (final Object? id in <Object?>[
        '../../etc/passwd', 'a/b', 'a?x=1', 'a#frag', 'a b', 'a\nb', 'a%2Fb', '', ' ', 'x' * 65, 'аbc', 'a.b',
        'a;b', '..', '/', r'a\b', 7, null, true, <String>['a'], <String, Object?>{'id': 'a'},
      ]) {
        expect(parseInbox(<String, Object?>{'entries': <Object?>[_row('a')..['id'] = id]}), isEmpty,
            reason: 'id ${jsonEncode(id.toString())}');
      }
      expect(parseInbox(<String, Object?>{'entries': <Object?>[_row('3f2c9a10-aaaa-bbbb-cccc-0123456789ab')]}),
          hasLength(1));
    });

    test('a sender id that is not a plain id is dropped, the row stays', () {
      final InboxMessage m = parseInbox(<String, Object?>{'entries': <Object?>[_row('a', sid: '../x')]}).single;
      expect(m.senderId, isNull);
    });

    test('duplicates are drawn once; the list is capped at 50', () {
      expect(parseInbox(<String, Object?>{'entries': <Object?>[_row('a'), _row('a'), _row('a')]}), hasLength(1));
      final List<Object?> many = <Object?>[for (int i = 0; i < 400; i++) _row('id$i')];
      expect(parseInbox(<String, Object?>{'entries': many}), hasLength(kMaxReceivedRows));
    });

    test('anything that is not the expected shape is an empty list, never a throw', () {
      for (final Object? b in <Object?>[
        null, 'x', 7, true, <Object?>[], <Object?>[1, 2], <String, Object?>{}, <String, Object?>{'entries': null},
        <String, Object?>{'entries': 'x'}, <String, Object?>{'entries': <String, Object?>{'a': 1}},
        <String, Object?>{'messages': <Object?>[_row('a')]},
        <String, Object?>{'entries': <Object?>[null, 1, 'x', <Object?>[], <String, Object?>{}, <String, Object?>{'id': 'a'}]},
      ]) {
        expect(parseInbox(b), isEmpty, reason: '$b');
      }
    });

    test('extra fields, including every word on the global sweep list, never reach the model', () {
      final Set<String> banned = _tsForbidden();
      final Map<String, Object?> hostile = _row('a');
      for (final String w in banned) {
        hostile[w] = 'SENTINEL-$w';
        hostile[w.toUpperCase()] = 'SENTINEL-$w';
      }
      final InboxMessage m = parseInbox(<String, Object?>{
        'entries': <Object?>[hostile],
        for (final String w in banned) w: 'SENTINEL-$w',
      }).single;
      final String shown = '${m.id}|${m.senderName}|${m.senderId}|${m.deliveredAtLabel}|${m.kind}|${m.dayPartKind}';
      expect(shown, isNot(contains('SENTINEL')));
      expect(shown, 'a|Dad|g-1|7:04 AM|video_msg|null');
    });
  });

  group('childSafeName / childSafeWhen — the two strings from the wire that are drawn to her', () {
    test('ordinary names pass unchanged, in any script', () {
      for (final String n in <String>['Mom', 'Dad', 'Grandma Joy', "O'Brien", 'Anne-Marie', 'María', '王芳',
        'محمد', 'Алексей']) {
        expect(childSafeName(n), n);
      }
    });

    test('digits, symbols, markup, links, control and direction characters, emoji are all stripped', () {
      expect(childSafeName('Mom 2'), 'Mom');
      expect(childSafeName('<b>Mom</b>'), 'b Mom b');
      expect(childSafeName('A\u202Ebc\u200Bd\u0000e'), 'A bc d e');
      expect(childSafeName('Mom \u{1F495}'), 'Mom');
      expect(childSafeName('http://evil.example/x'), 'http evil example x');
      expect(childSafeName('\$\$\$ 100% !!!'), isNull);
      expect(childSafeName("'-'"), isNull, reason: 'no letter left');
      expect(childSafeName(''), isNull);
      expect(childSafeName(null), isNull);
      expect(childSafeName(7), isNull);
      expect(childSafeName(<String>['Mom']), isNull);
    });

    test('a name is capped at 24 characters, by characters not bytes', () {
      expect(childSafeName('x' * 5000)!.length, 24);
      expect(childSafeName('王' * 100)!.runes.length, 24);
    });

    test('EVERY word on the global sweep list, alone, shouted, inside a name, or with underscores, is refused', () {
      for (final String w in _tsForbidden()) {
        expect(childSafeName(w), isNull, reason: w);
        expect(childSafeName(w.toUpperCase()), isNull, reason: w.toUpperCase());
        expect(childSafeName('Mom $w'), isNull, reason: 'Mom $w');
        expect(childSafeName('Mom $w Dad'), isNull, reason: 'Mom $w Dad');
        expect(childSafeWhen('7:04 AM $w'), '', reason: w);
      }
    });

    test('a hostile name falls back to the neutral grown-up word through parseInbox', () {
      final List<InboxMessage> m = parseInbox(<String, Object?>{'entries': <Object?>[
        _row('a', name: 'Unread Streak Score'), _row('b', name: 'days_in_a_row'), _row('c', name: 12345),
        _row('d', name: null),
      ]});
      expect(m.map((InboxMessage x) => x.senderName), everyElement('your grown-up'));
    });

    test('times keep their shape; anything else is empty', () {
      expect(childSafeWhen('7:04 AM'), '7:04 AM');
      expect(childSafeWhen('Yesterday, 7:58 PM'), 'Yesterday, 7:58 PM');
      expect(childSafeWhen('2 days ago, 6:10 PM'), '2 days ago, 6:10 PM');
      expect(childSafeWhen('<script>x</script>'), 'script x script');
      expect(childSafeWhen('3 unread messages'), '');
      expect(childSafeWhen('x' * 41), '');
      expect(childSafeWhen(''), '');
      expect(childSafeWhen(null), '');
      expect(childSafeWhen(<String>['7:04']), '');
    });
  });

  group('ReceiptQueue — "she opened it" rides on the existing offline outbox', () {
    test('a receipt the server hears is sent once and leaves nothing behind', () async {
      final _Mem mem = _Mem();
      final List<String> sent = <String>[];
      await mem.queue.record('m1', (String id) async => sent.add(id));
      expect(sent, <String>['m1']);
      expect(mem.items, isEmpty);
    });

    test('no signal: the receipt waits (a plain id, nothing else), is never thrown, and is never duplicated', () async {
      final _Mem mem = _Mem();
      Future<void> down(String id) async => throw http.ClientException('connection refused to api.test:3000');
      await mem.queue.record('m1', down);
      await mem.queue.record('m1', down);
      expect(mem.items, hasLength(1));
      final OutboxItem i = mem.items.single;
      expect(i.kind, OutboxKind.receipt);
      expect(i.payload, <String, Object?>{'messageId': 'm1'});
      expect(i.lastError, 'network', reason: 'a fixed word: no address, no URL, no message text is ever stored');
      expect(_leaks(i.payload, _tsForbidden()), isEmpty, reason: 'the stored payload passes the global sweep');
      expect(await mem.queue.pendingIds(), <String>{'m1'});
    });

    test('a server that is down or asking for a fresh session keeps the receipt; a final answer drops it', () async {
      for (final int code in <int>[401, 408, 429, 500, 502, 503, 504]) {
        final _Mem mem = _Mem();
        await mem.queue.record('m1', (String id) async => throw ApiException.fromStatus(code, 'later'));
        expect(mem.items, hasLength(1), reason: 'HTTP $code is "not now"');
        expect(mem.items.single.lastError, 'server');
      }
      for (final int code in <int>[400, 403, 404, 409, 410, 422]) {
        final _Mem mem = _Mem();
        await mem.queue.record('m1', (String id) async => throw ApiException.fromStatus(code, 'no'));
        expect(mem.items, isEmpty, reason: 'HTTP $code is "never": retrying cannot help');
      }
    });

    test('an id that is not a plain id is never sent and never stored', () async {
      final _Mem mem = _Mem();
      final List<String> sent = <String>[];
      for (final String bad in <String>['../x', 'a/b', '', 'a b', 'x' * 99]) {
        await mem.queue.record(bad, (String id) async => sent.add(id));
      }
      expect(sent, isEmpty);
      expect(mem.items, isEmpty);
    });

    test('drain sends oldest first and removes what the server heard', () async {
      final _Mem mem = _Mem()
        ..items = <OutboxItem>[
          _receipt('new', at: DateTime.utc(2026, 11, 15, 11, 30)),
          _receipt('old', at: DateTime.utc(2026, 11, 15, 9)),
        ];
      final List<String> sent = <String>[];
      await mem.queue.drain((String id) async => sent.add(id));
      expect(sent, <String>['old', 'new']);
      expect(mem.items, isEmpty);
    });

    test('drain stops at the first "not now" so a server that is down is not asked again and again', () async {
      final _Mem mem = _Mem()
        ..items = <OutboxItem>[
          _receipt('a', at: DateTime.utc(2026, 11, 15, 8)),
          _receipt('b', at: DateTime.utc(2026, 11, 15, 9)),
          _receipt('c', at: DateTime.utc(2026, 11, 15, 10)),
        ];
      final List<String> asked = <String>[];
      await mem.queue.drain((String id) async {
        asked.add(id);
        throw ApiException.fromStatus(503, 'down');
      });
      expect(asked, <String>['a']);
      expect(mem.items, hasLength(3));
      expect(mem.items.firstWhere((OutboxItem i) => i.id == 'receipt:a').attempts, 2);
      expect(mem.items.firstWhere((OutboxItem i) => i.id == 'receipt:b').attempts, 1);
    });

    test('ten 60-second polls against a dead server do not use up the tries: the receipt survives and is sent later',
        () async {
      final _Mem mem = _Mem();
      int asked = 0;
      await mem.queue.record('m1', (String id) async {
        asked++;
        throw http.ClientException('no signal');
      });
      expect(asked, 1);
      for (int i = 0; i < 10; i++) {
        mem.now = mem.now.add(const Duration(seconds: 60));
        await mem.queue.drain((String id) async {
          asked++;
          throw http.ClientException('no signal');
        });
      }
      // Ten minutes: at most the first retry (2 minutes of backoff) and the second (4 more) were due.
      expect(asked, lessThanOrEqualTo(3));
      expect(mem.items, hasLength(1));
      expect(mem.items.single.attempts, lessThan(maxAttempts));
      // Hours later the signal is back and the receipt goes out.
      mem.now = mem.now.add(const Duration(hours: 6));
      final List<String> sentIds = <String>[];
      await mem.queue.drain((String id) async => sentIds.add(id));
      expect(sentIds, <String>['m1']);
      expect(mem.items, isEmpty);
    });

    test('drain drops a final answer and carries on with the rest', () async {
      final _Mem mem = _Mem()
        ..items = <OutboxItem>[
          _receipt('gone', at: DateTime.utc(2026, 11, 15, 8)),
          _receipt('ok', at: DateTime.utc(2026, 11, 15, 9)),
        ];
      final List<String> asked = <String>[];
      await mem.queue.drain((String id) async {
        asked.add(id);
        if (id == 'gone') throw ApiException.fromStatus(404, 'message_not_found_or_not_yet_delivered');
      });
      expect(asked, <String>['gone', 'ok']);
      expect(mem.items, isEmpty);
    });

    test('exhausted, stale and poisoned receipts are let go without a single request; other kinds are untouched',
        () async {
      final OutboxItem drawing = OutboxItem(
          id: 'd1', kind: OutboxKind.drawing, createdAt: DateTime.utc(2020), payload: 'keep me', attempts: 99);
      final _Mem mem = _Mem()
        ..items = <OutboxItem>[
          drawing,
          _receipt('tried', attempts: maxAttempts),
          _receipt('stale', at: DateTime.utc(2026, 9, 1)),
          _receipt('x', payload: <String, Object?>{'messageId': '../../etc/passwd'}),
          _receipt('y', payload: 'not a map'),
          _receipt('z', payload: <String, Object?>{'messageId': 7}),
        ];
      final List<String> sent = <String>[];
      await mem.queue.drain((String id) async => sent.add(id));
      expect(sent, isEmpty);
      expect(mem.items.map((OutboxItem i) => i.id), <String>['d1']);
    });

    test('a receipt and a drain at the same moment never lose each other\'s work', () async {
      final _Mem mem = _Mem();
      final List<Future<void>> all = <Future<void>>[];
      for (int i = 0; i < 20; i++) {
        all.add(mem.queue.record('m$i', (String id) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          throw http.ClientException('down');
        }));
        if (i % 5 == 0) all.add(mem.queue.drain((String id) async => throw http.ClientException('down')));
      }
      await Future.wait(all);
      expect((await mem.queue.pendingIds()).length, 20);
      expect(mem.items.where((OutboxItem i) => i.kind == OutboxKind.receipt), hasLength(20));
    });

    test('a store that throws never breaks the screen: record, drain and pendingIds all swallow it', () async {
      final ReceiptQueue q = ReceiptQueue.over(
          load: () async => throw StateError('disk'), save: (List<OutboxItem> l) async => throw StateError('disk'));
      await q.record('m1', (String id) async => throw http.ClientException('x'));
      await q.drain((String id) async {});
      expect(await q.pendingIds(), isEmpty);
    });

    group('on the real on-device outbox area', () {
      test('a waiting receipt survives a restart, is scoped to its child, and sits beside other outbox kinds', () async {
        final MemoryStoreBackend backend = MemoryStoreBackend();
        LocalServices.install(LocalServices.memory(childId: 'child-a', isLive: true, backend: backend));
        addTearDown(LocalServices.resetForTest);
        // Something else already waits in the same area.
        await OutboxRepository(LocalServices.current.area('outbox', ownerId: 'child-a')).save(<OutboxItem>[
          OutboxItem(id: 'd1', kind: OutboxKind.drawing, createdAt: DateTime.utc(2026), payload: 'keep'),
        ]);

        await ReceiptQueue.forChild('child-a').record('m1', (String id) async => throw http.ClientException('x'));
        await ReceiptQueue.forChild('child-b').record('m9', (String id) async => throw http.ClientException('x'));

        // "Restart": a new LocalServices over the same files, so a fresh queue object.
        LocalServices.install(LocalServices.memory(childId: 'child-a', isLive: true, backend: backend));
        expect(await ReceiptQueue.forChild('child-a').pendingIds(), <String>{'m1'});
        expect(await ReceiptQueue.forChild('child-b').pendingIds(), <String>{'m9'});
        final List<OutboxItem> stored =
            await OutboxRepository(LocalServices.current.area('outbox', ownerId: 'child-a')).load();
        expect(stored.map((OutboxItem i) => i.id).toSet(), <String>{'d1', 'receipt:m1'});

        final List<String> sent = <String>[];
        await ReceiptQueue.forChild('child-a').drain((String id) async => sent.add(id));
        expect(sent, <String>['m1']);
        final List<OutboxItem> after =
            await OutboxRepository(LocalServices.current.area('outbox', ownerId: 'child-a')).load();
        expect(after.map((OutboxItem i) => i.id), <String>['d1']);
      });

      test('the preview scope in a live build is refused by the store, so the queue works in memory for the run', () async {
        LocalServices.install(LocalServices.memory(childId: 'child-a', isLive: true));
        addTearDown(LocalServices.resetForTest);
        final ReceiptQueue q = ReceiptQueue.forChild('demo-child');
        await q.record('m1', (String id) async => throw http.ClientException('x'));
        expect(await q.pendingIds(), <String>{'m1'});
      });
    });
  });

  group('the receipt route', () {
    test('markInboxOpened encodes the id into the path and posts an empty object', () async {
      final List<http.Request> seen = <http.Request>[];
      final MockClient mock = MockClient((http.Request r) async {
        seen.add(r);
        return http.Response('{"ok":true}', 200);
      });
      final OliveApi api = OliveApi('http://api.test', 'tok', client: mock);
      await api.markInboxOpened('child-a', 'msg-1');
      await api.markInboxOpened('child-a', '../x?y=1');
      expect(seen[0].method, 'POST');
      expect(seen[0].url.path, '/v1/children/child-a/inbox/msg-1/opened');
      expect(seen[0].body, '{}');
      expect(seen[1].url.path, isNot(contains('/x')), reason: 'the id cannot climb out of its segment');
      expect(seen[1].url.query, isEmpty);
    });
  });
}
