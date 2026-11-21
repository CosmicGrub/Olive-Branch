// OLIVE BRANCH — inbox_screen.dart tests. §8.2, §9.5, §7.19 (the child's receive path).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_receive.dart';
import 'package:olive_client/form_factors.dart' as ff;
import 'package:olive_client/inbox_screen.dart';
import 'package:olive_client/message_player.dart';
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/receipt_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// A player that plays at once, with no platform behind it.
class _FakePlayback implements MessagePlaybackPort {
  @override
  final ValueNotifier<PlaybackSnapshot> state = ValueNotifier<PlaybackSnapshot>(const PlaybackSnapshot());
  @override
  Future<void> openFile(String path) async {}
  @override
  Future<void> play() async => state.value = const PlaybackSnapshot(playing: true);
  @override
  Future<void> pause() async => state.value = const PlaybackSnapshot();
  @override
  Future<void> replay() async => play();
  @override
  Widget? view() => null;
  @override
  Future<void> dispose() async {}
}

Future<LocalMedia> _fakeFetch(Uri uri) async => LocalMedia('/nowhere/olive_test_media');

Widget _fakePicture(BuildContext c, String path, VoidCallback onShown, VoidCallback onFailed) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onShown());
  return const SizedBox(key: Key('fakePicture'), width: 40, height: 40);
}

const String _mediaUrlBody =
    '{"signedUrl":"http://api.test/media/children/child-a/messages/abc?exp=1&sig=ab","absolute":true,"kind":"video_msg","ttl":300}';

/// The server's media-url answer on top of whatever else a test says.
MockClient _withMedia(Future<http.Response> Function(http.Request) inner) => MockClient((http.Request req) async {
      if (req.method == 'GET' && req.url.path.endsWith('/media-url')) {
        return http.Response(_mediaUrlBody, 200);
      }
      return inner(req);
    });

/// Taps a tile, lets the player play, and leaves it: she is then on the message's receipt, as before.
Future<void> _openTile(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pumpAndSettle();
  await t.pageBack();
  await t.pumpAndSettle();
}

const List<InboxMessage> _messages = <InboxMessage>[
  InboxMessage(id: '1', senderName: 'Dad', deliveredAtLabel: '7:04 AM', dayPartKind: 'before_school'),
  InboxMessage(id: '2', senderName: 'Dad', deliveredAtLabel: 'Yesterday, 7:58 PM',
    dayPartKind: 'wind_down', watched: true),
];

/// An in-memory receipt queue whose stored items the test can read.
class _Mem {
  List<OutboxItem> items = <OutboxItem>[];
  DateTime now = DateTime.utc(2026, 11, 15, 12);
  late final ReceiptQueue queue = ReceiptQueue.over(
    load: () async => List<OutboxItem>.of(items),
    save: (List<OutboxItem> l) async => items = List<OutboxItem>.of(l),
    now: () => now,
  );
}

Map<String, Object?> _row(String id, {String state = 'delivered', String kind = 'video_msg',
    String name = 'Dad', String label = '7:04 AM'}) =>
    <String, Object?>{'id': id, 'payload_kind': kind, 'state': state, 'sender_name': name,
      'sender_id': 'g-1', 'deliveredAtLabel': label, 'media_id': 'm-$id'};

http.Response _inbox(List<Map<String, Object?>> rows) =>
    http.Response(jsonEncode(<String, Object?>{'entries': rows}), 200);

Widget _live(MockClient mock, _Mem mem, {Duration? refreshEvery}) => wrap(InboxScreen(
      childName: 'Ivy', messages: const <InboxMessage>[],
      baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok',
      httpClient: mock, receiptQueue: mem.queue, refreshEvery: refreshEvery,
      mediaFetcher: _fakeFetch, playbackFactory: _FakePlayback.new, pictureBuilder: _fakePicture));

List<String> _allText(WidgetTester t) => <String>[
      for (final Element e in find.byType(Text).evaluate()) ((e.widget as Text).data ?? ''),
    ];

void main() {
  group('Inbox — §8.2, §9.5, §7.19', () {
    testWidgets('no greeting, no dot, no "New", no count: a quiet list of tiles (P2)', (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.textContaining('Hi Ivy'), findsNothing);
      expect(find.textContaining('something new'), findsNothing);
      expect(find.textContaining('caught up'), findsNothing);
      expect(find.textContaining('New'), findsNothing);
      expect(find.textContaining('Watched'), findsNothing);
      expect(find.byKey(const Key('newDot')), findsNothing);
      for (final String s in _allText(tester)) {
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'no digit anywhere on her inbox: "$s"');
      }
    });

    testWidgets('every message in the list renders a tile with her word for the sender', (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.textContaining('Dad sent a video'), findsNWidgets(2));
    });

    testWidgets('NO settings affordance and no price/financial/error text — P4, P6',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('price'), findsNothing);
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('badge'), findsNothing);
    });

    testWidgets('each kind has its own kid wording; a kind with no wording is not drawn', (tester) async {
      final MockClient mock = MockClient((_) async => _inbox(<Map<String, Object?>>[
            _row('a', kind: 'voice_note'), _row('b', kind: 'drawing'), _row('c', kind: 'photo'),
            _row('d', kind: 'nudge'), _row('e', kind: 'homework'), _row('f', kind: 'surprise_kind'),
          ]));
      await tester.pumpWidget(_live(mock, _Mem()));
      await tester.pumpAndSettle();
      expect(find.text('Dad sent a voice message'), findsOneWidget);
      expect(find.text('Dad sent a drawing'), findsOneWidget);
      expect(find.text('Dad sent a picture'), findsOneWidget);
      expect(find.text('Dad is thinking of you'), findsOneWidget);
      expect(find.byType(InkWell), findsNWidgets(4));
    });

    testWidgets('opening an unopened message marks it opened and opens its receipt',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      // The only difference between an unopened and an opened tile is its look: the first avatar is filled.
      Color? fill() => tester.widget<CircleAvatar>(find.byType(CircleAvatar).first).backgroundColor;
      final Color? before = fill();

      await tester.tap(find.textContaining('Dad sent a video').first);
      await tester.pumpAndSettle();

      // Landed on a real receipt, in her frame, with her name — never the
      // sender's clock, never a raw zone.
      expect(find.byType(ReceiptScreen), findsOneWidget);
      expect(find.textContaining("Ivy's time"), findsOneWidget);
      expect(find.textContaining('UTC'), findsNothing);

      // Back in the inbox the first tile now looks like the already-opened one.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(fill(), isNot(equals(before)));
      expect(find.textContaining('New'), findsNothing);
    });

    testWidgets('opening an already-opened message reopens its stored receipt honestly',
        (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      await tester.tap(find.textContaining('Dad sent a video').last);
      await tester.pumpAndSettle();
      expect(find.text("Watched at Yesterday, 7:58 PM Ivy's time — winding down."),
        findsOneWidget);
    });

    testWidgets('an empty inbox is NOTHING: no icon, no sentence, no greeting', (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: <InboxMessage>[])));
      expect(find.byType(Icon), findsNothing);
      expect(_allText(tester), <String>['Messages']);
      expect(tester.takeException(), isNull);
    });

    group('responsive — no overflow at any required viewport width', () {
      Future<void> pumpAt(WidgetTester tester, Size size) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(wrap(InboxScreen(
          childName: 'Ivy', messages: List<InboxMessage>.of(demoInboxMessages))));
        await tester.pump();
      }

      testWidgets('Fold5 cover screen (344 CSS px wide)', (tester) async {
        await pumpAt(tester, const Size(344, 900));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Fold5 unfolded main screen (~673x841, nearly square)', (tester) async {
        await pumpAt(tester, const Size(673, 841));
        expect(tester.takeException(), isNull);
      });

      testWidgets('standard phone width (~390px)', (tester) async {
        await pumpAt(tester, const Size(390, 844));
        expect(tester.takeException(), isNull);
      });

      testWidgets('tablet/desktop width (~1100px, short and wide)', (tester) async {
        await pumpAt(tester, const Size(1100, 800));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('message tiles meet the 48dp+ touch target minimum', (tester) async {
      await tester.pumpWidget(wrap(const InboxScreen(childName: 'Ivy', messages: _messages)));
      final int count = find.byType(InkWell).evaluate().length;
      expect(count, 2);
      for (int i = 0; i < count; i++) {
        expect(tester.getSize(find.byType(InkWell).at(i)).height, greaterThanOrEqualTo(48.0));
      }
    });

    group('responsive — comfortable reading width cap (form_factors.dart)', () {
      testWidgets('the cap engages only on a wide tablet/desktop viewport — '
          'never at the Fold5 cover or phone width', (tester) async {
        Future<void> pumpAt(Size size) async {
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(wrap(InboxScreen(
            childName: 'Ivy', messages: List<InboxMessage>.of(demoInboxMessages))));
          await tester.pump();
        }

        addTearDown(() => tester.binding.setSurfaceSize(null));

        await pumpAt(const Size(1100, 800));
        expect(tester.getSize(find.byType(ListView)).width, ff.comfortableReadingWidth);

        await pumpAt(const Size(344, 900)); // Fold5 cover
        expect(tester.getSize(find.byType(ListView)).width, 344);

        await pumpAt(const Size(390, 844)); // standard phone
        expect(tester.getSize(find.byType(ListView)).width, 390);
      });
    });

    group('live — what the delivery worker made ready', () {
      testWidgets('shows only what the server sent, never the example messages, and no spinner or sentence '
          'at any point', (tester) async {
        final MockClient mock = _withMedia((http.Request req) async {
          expect(req.url.path, '/v1/children/child-a/inbox');
          return _inbox(<Map<String, Object?>>[
            _row('real-1'), _row('real-2', state: 'opened', name: 'Mom', label: 'Yesterday, 3:00 PM'),
          ]);
        });
        await tester.pumpWidget(wrap(InboxScreen(
          // Even if a caller hands example messages to a live screen, they are never drawn.
          childName: 'Ivy', messages: List<InboxMessage>.of(demoInboxMessages),
          baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok',
          httpClient: mock, receiptQueue: _Mem().queue, refreshEvery: null)));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('Your grown-up'), findsNothing);
        await tester.pumpAndSettle();

        expect(find.textContaining('Dad sent a video'), findsOneWidget);
        expect(find.textContaining('Mom sent a video'), findsOneWidget);
        expect(find.textContaining('Watched'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('rows the server says are not hers yet or are gone are not drawn', (tester) async {
        final MockClient mock = _withMedia((_) async => _inbox(<Map<String, Object?>>[
              _row('a', state: 'ready'), _row('b', state: 'pending'), _row('c', state: 'expired'),
              _row('d', state: 'revoked'), _row('ok'),
            ]));
        await tester.pumpWidget(_live(mock, _Mem()));
        await tester.pumpAndSettle();
        expect(find.byType(InkWell), findsOneWidget);
      });

      testWidgets('opening a live-fetched message threads the real live params into ReceiptScreen',
          (tester) async {
        final MockClient mock = _withMedia((_) async => _inbox(<Map<String, Object?>>[_row('real-1')]));
        await tester.pumpWidget(wrap(InboxScreen(
          childName: 'Ivy', messages: const <InboxMessage>[],
          baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'real-session-tok',
          httpClient: mock, receiptQueue: _Mem().queue, refreshEvery: null,
          mediaFetcher: _fakeFetch, playbackFactory: _FakePlayback.new, pictureBuilder: _fakePicture)));
        await tester.pumpAndSettle();

        await _openTile(tester, find.textContaining('Dad sent a video'));

        final ReceiptScreen receipt = tester.widget(find.byType(ReceiptScreen));
        expect(receipt.baseUrl, 'http://api.test');
        expect(receipt.childId, 'child-a');
        expect(receipt.sessionToken, 'real-session-tok');
      });

      testWidgets('opening an unopened message tells the server through POST .../inbox/:id/opened, once',
          (tester) async {
        final List<http.Request> posts = <http.Request>[];
        final MockClient mock = _withMedia((http.Request req) async {
          if (req.method == 'POST') {
            posts.add(req);
            return http.Response(jsonEncode({'ok': true}), 200);
          }
          return _inbox(<Map<String, Object?>>[_row('real-1')]);
        });
        final _Mem mem = _Mem();
        await tester.pumpWidget(_live(mock, mem));
        await tester.pumpAndSettle();

        await _openTile(tester, find.textContaining('Dad sent a video'));

        expect(posts, hasLength(1));
        expect(posts.single.url.path, '/v1/children/child-a/inbox/real-1/opened');
        expect(posts.single.headers['authorization'], 'Bearer tok');
        expect(mem.items, isEmpty, reason: 'the server heard it: nothing waits in the outbox');
      });

      testWidgets('a failing receipt POST never delays the receipt screen and waits in the outbox, unseen',
          (tester) async {
        final MockClient mock = _withMedia((http.Request req) async {
          if (req.method == 'POST') throw http.ClientException('no route to host');
          return _inbox(<Map<String, Object?>>[_row('real-1')]);
        });
        final _Mem mem = _Mem();
        await tester.pumpWidget(_live(mock, mem));
        await tester.pumpAndSettle();

        await _openTile(tester, find.textContaining('Dad sent a video'));

        expect(find.byType(ReceiptScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(mem.items, hasLength(1));
        expect(mem.items.single.kind, OutboxKind.receipt);
        expect(mem.items.single.payload, <String, Object?>{'messageId': 'real-1'});
        // Nothing about waiting, retrying or the network is ever drawn at her.
        await tester.pageBack();
        await tester.pumpAndSettle();
        for (final String s in _allText(tester)) {
          expect(s.toLowerCase(), isNot(contains('wait')));
          expect(s.toLowerCase(), isNot(contains('retry')));
          expect(s.toLowerCase(), isNot(contains('internet')));
          expect(s.toLowerCase(), isNot(contains('error')));
        }
      });

      testWidgets('a receipt that is still waiting keeps its tile opened, and goes out BEFORE the next fetch',
          (tester) async {
        final List<String> order = <String>[];
        bool online = false;
        final MockClient mock = _withMedia((http.Request req) async {
          order.add('${req.method} ${req.url.path}');
          if (req.method == 'POST') {
            if (!online) throw http.ClientException('down');
            return http.Response('{"ok":true}', 200);
          }
          return _inbox(<Map<String, Object?>>[_row('real-1')]); // the server still says 'delivered'
        });
        final _Mem mem = _Mem();
        await tester.pumpWidget(_live(mock, mem, refreshEvery: const Duration(minutes: 1)));
        await tester.pumpAndSettle();
        await _openTile(tester, find.textContaining('Dad sent a video'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(mem.items, hasLength(1));

        // The signal comes back; the next ask sends the waiting receipt first, then reads the inbox.
        online = true;
        order.clear();
        mem.now = mem.now.add(const Duration(minutes: 3)); // past the first backoff
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(order, <String>['POST /v1/children/child-a/inbox/real-1/opened', 'GET /v1/children/child-a/inbox']);
        expect(mem.items, isEmpty);
      });

      testWidgets('a fetch that raced her tap cannot turn the tile back to unopened', (tester) async {
        // The server answers 'delivered' for the whole run, as if it had not yet processed her receipt.
        final MockClient mock = _withMedia((http.Request req) async =>
            req.method == 'POST' ? http.Response('{"ok":true}', 200) : _inbox(<Map<String, Object?>>[_row('real-1')]));
        final _Mem mem = _Mem();
        await tester.pumpWidget(_live(mock, mem, refreshEvery: const Duration(minutes: 1)));
        await tester.pumpAndSettle();
        Color? fill() => tester.widget<CircleAvatar>(find.byType(CircleAvatar).first).backgroundColor;
        final Color? before = fill();
        await _openTile(tester, find.textContaining('Dad sent a video'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        final Color? opened = fill();
        expect(opened, isNot(equals(before)));
        expect(mem.items, isEmpty); // the receipt was heard, so it is no longer pending
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(fill(), opened);
      });

      testWidgets('opening an ALREADY-opened message does not tell the server again', (tester) async {
        final List<http.Request> posts = <http.Request>[];
        final MockClient mock = _withMedia((http.Request req) async {
          if (req.method == 'POST') { posts.add(req); return http.Response('{}', 200); }
          return _inbox(<Map<String, Object?>>[_row('real-1', state: 'opened')]);
        });
        await tester.pumpWidget(_live(mock, _Mem()));
        await tester.pumpAndSettle();

        await _openTile(tester, find.textContaining('Dad sent a video'));

        expect(find.byType(ReceiptScreen), findsOneWidget);
        expect(posts, isEmpty);
      });

      for (final MapEntry<String, MockClient Function()> c in <String, MockClient Function()>{
        'a 500': () => MockClient((_) async => http.Response('boom', 500)),
        'a 503 with an html body': () => MockClient((_) async => http.Response('<html>down</html>', 503)),
        'a 401': () => MockClient((_) async => http.Response('{"error":"unauthorized"}', 401)),
        'a thrown socket error': () => MockClient((_) async => throw http.ClientException('no route')),
        'garbage that is not JSON': () => MockClient((_) async => http.Response('not json', 200)),
        'JSON that is not an object': () => MockClient((_) async => http.Response('[1,2,3]', 200)),
        'entries that are not a list': () =>
            MockClient((_) async => http.Response('{"entries":{"a":1}}', 200)),
        'entries full of junk': () =>
            MockClient((_) async => http.Response('{"entries":[1,"x",null,[],{"id":7}]}', 200)),
      }.entries) {
        testWidgets('${c.key} looks exactly like an empty inbox: no error, no retry, no cloud, no sentence',
            (tester) async {
          await tester.pumpWidget(_live(c.value(), _Mem()));
          await tester.pumpAndSettle();
          expect(_allText(tester), <String>['Messages']);
          expect(find.byType(Icon), findsNothing);
          expect(find.byType(FilledButton), findsNothing);
          expect(find.byType(IconButton), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('a failed refresh keeps what is already on the screen', (tester) async {
        int calls = 0;
        final MockClient mock = MockClient((_) async {
          calls++;
          if (calls == 1) return _inbox(<Map<String, Object?>>[_row('real-1')]);
          return http.Response('boom', 500);
        });
        await tester.pumpWidget(_live(mock, _Mem(), refreshEvery: const Duration(minutes: 1)));
        await tester.pumpAndSettle();
        expect(find.textContaining('Dad sent a video'), findsOneWidget);
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.textContaining('Dad sent a video'), findsOneWidget);
      });

      testWidgets('a new delivery appears on the next ask, and again when the app comes back to the front',
          (tester) async {
        final List<Map<String, Object?>> rows = <Map<String, Object?>>[_row('a')];
        int gets = 0;
        final MockClient mock = MockClient((_) async { gets++; return _inbox(rows); });
        await tester.pumpWidget(_live(mock, _Mem(), refreshEvery: const Duration(minutes: 1)));
        await tester.pumpAndSettle();
        expect(find.byType(InkWell), findsOneWidget);

        rows.add(_row('b', name: 'Mom'));
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(find.byType(InkWell), findsNWidgets(2));
        expect(gets, 2);

        rows.add(_row('c', kind: 'drawing'));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(find.byType(InkWell), findsNWidgets(3));
        expect(gets, 3);
      });

      testWidgets('leaving the screen stops the asking', (tester) async {
        int gets = 0;
        final MockClient mock = MockClient((_) async { gets++; return _inbox(<Map<String, Object?>>[]); });
        await tester.pumpWidget(_live(mock, _Mem(), refreshEvery: const Duration(minutes: 1)));
        await tester.pumpAndSettle();
        await tester.pumpWidget(wrap(const SizedBox()));
        final int before = gets;
        await tester.pump(const Duration(minutes: 5));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(gets, before);
      });

      testWidgets('hostile rows: extra forbidden fields, hostile names and labels reach no screen', (tester) async {
        // Bytes, not a String body: the hostile names are not Latin-1, which http.Response(String, ...) refuses.
        final MockClient mock = MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode(<String, Object?>{
              'entries': <Object?>[
                <String, Object?>{
                  ..._row('h-1', name: 'Mom'),
                  'score': 'SENTINEL-score', 'streak': 'SENTINEL-streak', 'unread': 'SENTINEL-unread',
                  'count': 'SENTINEL-count', 'url': 'https://evil.example/SENTINEL-url',
                  'caption': 'SENTINEL-caption', 'message': 'SENTINEL-message',
                },
                _row('h-2', name: 'Unread Streak Score', label: '3 unread messages'),
                _row('h-3', name: '<script>alert(1)</script>'),
                _row('h-4', name: 'A\u202Ebad\u200Bname'),
                _row('../../etc/passwd'),
                _row('h-5', name: 'x' * 5000),
              ],
              'unread': 99, 'total': 99, 'count': 99, 'nextCursor': 'SENTINEL-cursor',
            })), 200, headers: const <String, String>{'content-type': 'application/json; charset=utf-8'}));
        await tester.pumpWidget(_live(mock, _Mem()));
        await tester.pumpAndSettle();
        final String all = _allText(tester).join('|');
        expect(all, isNot(contains('SENTINEL')));
        expect(all, isNot(contains('evil.example')));
        expect(all, isNot(contains('99')));
        expect(all.toLowerCase(), isNot(contains('unread')));
        expect(all.toLowerCase(), isNot(contains('streak')));
        expect(all.toLowerCase(), isNot(contains('<')));
        expect(all, isNot(contains('\u202E')));
        expect(all, isNot(contains('\u200B')));
        // The row with the unsafe id is gone; the four others are drawn.
        expect(find.byType(InkWell), findsNWidgets(5));
        for (final String s in _allText(tester)) {
          expect(s.length, lessThan(60), reason: 'a hostile 5000-character name is capped');
        }
      });
    });

    group('a locally paired tablet (no server session) — nothing broken, nothing shown', () {
      testWidgets('the Messages tile opens to an empty screen, asks nobody, and shows no example messages',
          (t) async {
        final List<http.Request> seen = <http.Request>[];
        final MockClient mock = MockClient((http.Request r) async { seen.add(r); return http.Response('{}', 200); });
        await t.binding.setSurfaceSize(const Size(900, 3000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        // What LiveChildHomeScreen hands ChildHome on a tablet with no account: a server address from the build, a
        // child id, and NO session token.
        await t.pumpWidget(wrap(ChildHome(
          childName: 'Ivy', presence: null, sleepsUntilHandover: null,
          baseUrl: 'http://api.test', childId: 'child-a', sessionToken: null, httpClient: mock)));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('newDot')), findsNothing);
        await t.tap(find.text('Messages'));
        await t.pumpAndSettle();
        expect(find.byType(InboxScreen), findsOneWidget);
        expect(find.textContaining('sent a video'), findsNothing);
        expect(find.textContaining('grown-up'), findsNothing);
        expect(find.byType(CircleAvatar), findsNothing);
        // No tile: the one InkWell on this screen is the AppBar's own back button, and there is no list at all.
        expect(find.descendant(of: find.byType(AppBar), matching: find.byType(InkWell)), findsOneWidget);
        expect(find.descendant(of: find.byType(InboxScreen), matching: find.byType(InkWell)), findsOneWidget);
        expect(find.descendant(of: find.byType(InboxScreen), matching: find.byType(ListView)), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(seen, isEmpty);
        expect(t.takeException(), isNull);
      });

      testWidgets('the preview build (no server address at all) still shows its example messages', (t) async {
        await t.pumpWidget(wrap(const ChildHome(childName: 'Ivy', presence: null, sleepsUntilHandover: 3)));
        await t.tap(find.text('Messages'));
        await t.pumpAndSettle();
        expect(find.textContaining('sent a video'), findsWidgets);
      });
    });
  });
}
