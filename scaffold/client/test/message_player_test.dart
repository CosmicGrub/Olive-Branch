// OLIVE BRANCH — message_player.dart: the calm player for a delivered message. Covers the address vetting
// (parseMediaTicket), the file fetch (httpMediaFetcher), the screen with a fake player, and the inbox wiring
// (opened is recorded on first play, never on the tap; nothing broken offline; nothing alarming on her screen).
// UNVERIFIED on a real device: the video_player plugin and the real file are not exercised here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/inbox_screen.dart';
import 'package:olive_client/message_player.dart';
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/receipt_screen.dart';
import 'package:olive_client/child_receive.dart';

const String _base = 'https://olive.example.test';

class _Port implements MessagePlaybackPort {
  _Port({this.autoPlay = true, this.failOpen = false});
  final bool autoPlay;
  final bool failOpen;
  int plays = 0, pauses = 0, replays = 0;
  bool disposed = false;
  @override
  final ValueNotifier<PlaybackSnapshot> state = ValueNotifier<PlaybackSnapshot>(const PlaybackSnapshot());
  @override
  Future<void> openFile(String path) async {
    if (failOpen) throw StateError('cannot decode');
  }

  @override
  Future<void> play() async {
    plays++;
    if (autoPlay) state.value = const PlaybackSnapshot(playing: true);
  }

  @override
  Future<void> pause() async {
    pauses++;
    state.value = const PlaybackSnapshot();
  }

  @override
  Future<void> replay() async {
    replays++;
    state.value = const PlaybackSnapshot(playing: true);
  }

  void finish() => state.value = const PlaybackSnapshot(completed: true);
  void breakIt() => state.value = const PlaybackSnapshot(failed: true);
  void startPlaying() => state.value = const PlaybackSnapshot(playing: true);

  @override
  Widget? view() => null;
  @override
  Future<void> dispose() async => disposed = true;
}

class _Harness {
  _Harness({this.kind = 'video_msg', this.ticket, this.fetchError, this.ticketError, this.port, this.resolveTimeout}) {
    port ??= _Port();
  }
  final String kind;
  MediaTicket? ticket;
  final Object? fetchError;
  final Object? ticketError;
  _Port? port;
  final Duration? resolveTimeout;
  int ticketCalls = 0, fetchCalls = 0, opened = 0;
  bool mediaDisposed = false;
  Completer<MediaTicket?>? hold;

  Widget screen({PictureBuilder? picture}) => MaterialApp(
        home: MessagePlayerScreen(
          line: 'Mommy sent a video',
          payloadKind: kind,
          resolveTimeout: resolveTimeout ?? const Duration(seconds: 15),
          loadTicket: () async {
            ticketCalls++;
            if (hold != null) return hold!.future;
            if (ticketError != null) throw ticketError!;
            return ticket ?? MediaTicket(Uri.parse('$_base/media/children/c/messages/x?exp=1&sig=a'), kind);
          },
          fetchMedia: (Uri u) async {
            fetchCalls++;
            if (fetchError != null) throw fetchError!;
            return LocalMedia('/nowhere/file', () async => mediaDisposed = true);
          },
          onOpened: () async => opened++,
          playbackFactory: () => port!,
          pictureBuilder: picture ??
              (BuildContext c, String path, VoidCallback shown, VoidCallback failed) {
                WidgetsBinding.instance.addPostFrameCallback((_) => shown());
                return const SizedBox(key: Key('picture'), width: 40, height: 40);
              },
        ),
      );
}

List<String> _texts(WidgetTester t) => <String>[
      for (final Element e in find.byType(Text).evaluate()) ((e.widget as Text).data ?? ''),
      for (final Element e in find.byType(IconButton).evaluate()) ((e.widget as IconButton).tooltip ?? ''),
    ];

void _expectCalm(WidgetTester t) {
  expect(find.byType(CircularProgressIndicator), findsNothing);
  for (final String s in _texts(t)) {
    final String l = s.toLowerCase();
    for (final String bad in <String>['error', 'retry', 'try again', 'wait', 'internet', 'signal', 'network', 'failed', 'loading', 'offline', 'problem']) {
      expect(l, isNot(contains(bad)), reason: '"$s"');
    }
    expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'no digit on her screen: "$s"');
  }
}

void main() {
  group('parseMediaTicket — only ever the server this client already talks to', () {
    MediaTicket? parse(Object? signed, {Object? extra, String base = _base}) =>
        parseMediaTicket(<String, Object?>{'signedUrl': signed, 'absolute': true, 'kind': 'video_msg', ...?(extra as Map<String, Object?>?)}, base);

    test('an absolute address on the same host is accepted', () {
      final MediaTicket? t = parse('$_base/media/children/c/messages/abc?exp=1&sig=ff');
      expect(t, isNotNull);
      expect(t!.uri.host, 'olive.example.test');
      expect(t.uri.path, '/media/children/c/messages/abc');
      expect(t.uri.query, 'exp=1&sig=ff');
      expect(t.kind, 'video_msg');
    });

    test('a path on the same server is joined to the origin the client already knows', () {
      final MediaTicket? t = parse('/media/children/c/messages/abc?exp=1&sig=ff');
      expect(t!.uri.toString(), '$_base/media/children/c/messages/abc?exp=1&sig=ff');
    });

    test('the host compares without case; a port must match too', () {
      expect(parse('https://OLIVE.example.test/media/x?sig=a'), isNotNull);
      expect(parse('https://olive.example.test:8443/media/x?sig=a'), isNull);
      expect(parse('http://dev.example.test:8123/media/x?sig=a', base: 'http://dev.example.test:8123'), isNotNull);
      expect(parse('http://dev.example.test:9999/media/x?sig=a', base: 'http://dev.example.test:8123'), isNull);
    });

    test('any other host, a downgrade to http, or a look-alike is refused', () {
      for (final String bad in <String>[
        'https://evil.example/media/x?sig=a',
        'http://olive.example.test/media/x?sig=a',
        'https://olive.example.test.evil.example/media/x?sig=a',
        'https://olive.example.testx/media/x?sig=a',
        'https://evil.example\\@olive.example.test/media/x',
        'https://olive.example.test@evil.example/media/x',
        'https://user:pw@olive.example.test/media/x',
        '//evil.example/media/x',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/plain,hi',
        'ftp://olive.example.test/media/x',
      ]) {
        expect(parse(bad), isNull, reason: bad);
      }
    });

    test('a path that is not under /media/, or tries to leave it, is refused', () {
      for (final String bad in <String>[
        '/v1/me', '/media', '/mediax/a', '/other/media/x', '/media/../v1/me', '/media/./x', '/media/%2e%2e/v1/me',
        '/media/%2E%2E/v1/me', '/media//x', 'media/x', '', '/', '$_base/v1/children', '$_base/media/../x',
      ]) {
        expect(parse(bad), isNull, reason: bad);
      }
    });

    test('control characters, spaces, backslashes, fragments and absurd lengths are refused', () {
      for (final String bad in <String>[
        '/media/x\n', '/media/x y', '/media/x\u0000', '/media\\x', '/media/x#frag', '$_base/media/x#frag',
        '/media/${'a' * 3000}',
      ]) {
        expect(parse(bad), isNull, reason: bad.length > 80 ? 'long' : bad);
      }
    });

    test('anything that is not the expected shape is nothing, never a throw', () {
      for (final Object? body in <Object?>[null, 1, 'x', <Object?>[], <String, Object?>{}, <String, Object?>{'signedUrl': 5},
        <String, Object?>{'signedUrl': null}, <String, Object?>{'signedUrl': <Object?>['/media/x']}]) {
        expect(parseMediaTicket(body, _base), isNull);
      }
      expect(parseMediaTicket(<String, Object?>{'signedUrl': '/media/x'}, 'not a url'), isNull);
    });

    test('only the address is read: every other field, including a word she must never see, is dropped', () {
      final MediaTicket? t = parse('/media/x?sig=a', extra: <String, Object?>{'kind': 'x' * 100, 'ttl': 300, 'score': 9, 'url': 'https://evil.example'});
      expect(t!.kind, '', reason: 'an absurd kind is ignored');
      expect(t.uri.host, 'olive.example.test');
    });
  });

  group('playerKindFor', () {
    test('what each delivery kind becomes', () {
      expect(playerKindFor('video_msg'), PlayerKind.video);
      expect(playerKindFor('call_clip'), PlayerKind.video);
      expect(playerKindFor('voice_note'), PlayerKind.audio);
      expect(playerKindFor('drawing'), PlayerKind.picture);
      expect(playerKindFor('photo'), PlayerKind.picture);
      expect(playerKindFor('nudge'), PlayerKind.text);
      expect(playerKindFor('e2e_video'), PlayerKind.text, reason: 'ciphertext to this client');
      expect(playerKindFor('homework'), PlayerKind.text);
      expect(playerKindFor('surprise'), PlayerKind.text);
      expect(recordsOnDisplay('nudge'), isTrue);
      expect(recordsOnDisplay('e2e_video'), isFalse);
      expect(recordsOnDisplay('video_msg'), isFalse);
    });
  });

  group('httpMediaFetcher — a capped, cleaned-up download through the app\'s own client', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('olive_player_test_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    MediaFetcher fetcher(MockClient c, {int max = 1024, Duration stall = const Duration(seconds: 5)}) =>
        httpMediaFetcher(c, maxBytes: max, stallTimeout: stall, tempDir: () async => dir);

    test('a 200 is written to a file, and dispose removes it', () async {
      final MockClient c = MockClient((http.Request r) async => http.Response.bytes(<int>[1, 2, 3, 4], 200));
      final LocalMedia m = await fetcher(c)(Uri.parse('$_base/media/x'));
      expect(File(m.path).readAsBytesSync(), <int>[1, 2, 3, 4]);
      await m.dispose();
      expect(File(m.path).existsSync(), isFalse);
      await m.dispose(); // twice is harmless
    });

    test('no session or token is sent: the signed address is the whole capability', () async {
      late http.Request seen;
      final MockClient c = MockClient((http.Request r) async {
        seen = r;
        return http.Response.bytes(<int>[1], 200);
      });
      await (await fetcher(c)(Uri.parse('$_base/media/x?exp=1&sig=a'))).dispose();
      expect(seen.headers.keys.map((String k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(seen.method, 'GET');
    });

    test('404, 500, 200-with-nothing and a thrown socket error all throw and leave no file behind', () async {
      for (final MockClient c in <MockClient>[
        MockClient((_) async => http.Response('gone', 404)),
        MockClient((_) async => http.Response('boom', 500)),
        MockClient((_) async => http.Response.bytes(<int>[], 200)),
        MockClient((_) async => throw http.ClientException('down')),
      ]) {
        await expectLater(fetcher(c)(Uri.parse('$_base/media/x')), throwsA(anything));
      }
      expect(dir.listSync(), isEmpty);
    });

    test('a file over the cap is refused, declared or not, and nothing is left on disk', () async {
      final MockClient declared = MockClient((_) async => http.Response.bytes(List<int>.filled(2000, 1), 200));
      await expectLater(fetcher(declared)(Uri.parse('$_base/media/x')), throwsA(anything));
      final MockClient streamed = MockClient.streaming((http.BaseRequest r, http.ByteStream b) async =>
          http.StreamedResponse(Stream<List<int>>.fromIterable(<List<int>>[List<int>.filled(700, 1), List<int>.filled(700, 1)]), 200));
      await expectLater(fetcher(streamed)(Uri.parse('$_base/media/x')), throwsA(anything));
      expect(dir.listSync(), isEmpty);
    });

    test('a connection that stalls is given up on, not waited for', () async {
      final MockClient c = MockClient.streaming((http.BaseRequest r, http.ByteStream b) async {
        final StreamController<List<int>> never = StreamController<List<int>>();
        return http.StreamedResponse(never.stream, 200);
      });
      await expectLater(fetcher(c, stall: const Duration(milliseconds: 50))(Uri.parse('$_base/media/x')), throwsA(anything));
      expect(dir.listSync(), isEmpty);
    });

    test('a redirect is never followed, and a 3xx fails with no file', () async {
      bool? follow;
      final MockClient c = MockClient.streaming((http.BaseRequest r, http.ByteStream b) async {
        follow = r.followRedirects;
        return http.StreamedResponse(const Stream<List<int>>.empty(), 302,
            headers: <String, String>{'location': 'https://elsewhere.example/x'});
      });
      await expectLater(fetcher(c)(Uri.parse('$_base/media/x')), throwsA(anything));
      expect(follow, isFalse);
      expect(dir.listSync(), isEmpty);
    });

    test('a trickle that never stalls still ends at the overall limit and leaves no file', () async {
      final MockClient c = MockClient.streaming((http.BaseRequest r, http.ByteStream b) async {
        final Stream<List<int>> slow = Stream<List<int>>.periodic(const Duration(milliseconds: 20), (_) => <int>[1]);
        return http.StreamedResponse(slow, 200);
      });
      final MediaFetcher f = httpMediaFetcher(c,
          maxBytes: 1 << 20,
          stallTimeout: const Duration(seconds: 5),
          totalTimeout: const Duration(milliseconds: 100),
          tempDir: () async => dir);
      await expectLater(f(Uri.parse('$_base/media/x')), throwsA(anything));
      expect(dir.listSync(), isEmpty);
    });

    test('old message files from an earlier run are swept, other files are kept', () async {
      final File old = File('${dir.path}${Platform.pathSeparator}olive_msg_1')..writeAsBytesSync(<int>[1]);
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 3)));
      final File fresh = File('${dir.path}${Platform.pathSeparator}olive_msg_2')..writeAsBytesSync(<int>[1]);
      final File other = File('${dir.path}${Platform.pathSeparator}keep.txt')..writeAsBytesSync(<int>[1]);
      other.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 3)));
      final MockClient c = MockClient((_) async => http.Response.bytes(<int>[1], 200));
      await (await fetcher(c)(Uri.parse('$_base/media/x'))).dispose();
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
    });
  });

  group('MessagePlayerScreen', () {
    testWidgets('a video plays by itself once it is ready, and "opened" is told exactly once, on that first play', (t) async {
      final _Harness h = _Harness();
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      expect(find.text('Mommy sent a video'), findsOneWidget);
      expect(h.port!.plays, 1);
      expect(h.opened, 1);
      // pause, play again, replay: still told once
      await t.tap(find.byKey(const Key('playerToggle')));
      await t.pumpAndSettle();
      expect(h.port!.pauses, 1);
      await t.tap(find.byKey(const Key('playerToggle')));
      await t.pumpAndSettle();
      expect(h.opened, 1);
      expect(find.byKey(const Key('playerToggle')), findsOneWidget);
      _expectCalm(t);
    });

    testWidgets('opened is NOT told while the file is still on its way, or if the player never starts', (t) async {
      final _Harness h = _Harness(port: _Port(autoPlay: false));
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      expect(h.port!.plays, 1);
      expect(h.opened, 0, reason: 'asked to play is not played');
      h.port!.startPlaying();
      await t.pumpAndSettle();
      expect(h.opened, 1);
    });

    testWidgets('played through shows "again" and "done"; again plays once more; done leaves; no count anywhere', (t) async {
      final _Harness h = _Harness();
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) => Scaffold(
          body: TextButton(onPressed: () => Navigator.of(c).push<void>(MaterialPageRoute<void>(builder: (_) => (h.screen() as MaterialApp).home!)), child: const Text('open'))))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      h.port!.finish();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('playerDone')), findsOneWidget);
      expect(find.byTooltip('Again'), findsOneWidget);
      _expectCalm(t);
      await t.tap(find.byKey(const Key('playerToggle')));
      await t.pumpAndSettle();
      expect(h.port!.replays, 1);
      expect(h.opened, 1);
      h.port!.finish();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('playerDone')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('playerLine')), findsNothing, reason: 'left the player');
    });

    testWidgets('a voice message is the sound and a soft picture of its kind', (t) async {
      final _Harness h = _Harness(kind: 'voice_note');
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('playerPicture')), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(h.opened, 1);
    });

    testWidgets('a drawing or a photo is shown, and opened is told when its first frame is up', (t) async {
      for (final String kind in <String>['drawing', 'photo']) {
        final _Harness h = _Harness(kind: kind);
        await t.pumpWidget(h.screen());
        await t.pumpAndSettle();
        expect(find.byKey(const Key('picture')), findsOneWidget, reason: kind);
        expect(h.opened, 1, reason: kind);
        expect(h.port!.plays, 0, reason: 'no audio/video player for a picture');
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a picture that cannot be drawn is the calm screen, once, with no loop and nothing recorded', (t) async {
      final _Harness h = _Harness(kind: 'photo');
      int builds = 0;
      await t.pumpWidget(h.screen(picture: (BuildContext c, String p, VoidCallback shown, VoidCallback failed) {
        builds++;
        WidgetsBinding.instance.addPostFrameCallback((_) => failed());
        return const SizedBox.shrink();
      }));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 1));
      expect(builds, lessThan(4), reason: 'a failed picture must not rebuild itself for ever');
      expect(h.opened, 0);
      expect(find.byKey(const Key('playerPicture')), findsOneWidget);
      expect(find.text('Mommy sent a video'), findsOneWidget);
      _expectCalm(t);
    });

    testWidgets('a nudge is its sentence alone, told opened when it is on screen, and asks for no file', (t) async {
      final _Harness h = _Harness(kind: 'nudge');
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      expect(find.text('Mommy sent a video'), findsOneWidget);
      expect(h.opened, 1);
      expect(h.ticketCalls, 0);
      expect(h.fetchCalls, 0);
      expect(find.byKey(const Key('playerToggle')), findsNothing);
      _expectCalm(t);
    });

    testWidgets('an end-to-end encrypted video is its sentence alone and is NOT recorded as opened', (t) async {
      final _Harness h = _Harness(kind: 'e2e_video');
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      expect(h.opened, 0, reason: 'nothing was shown');
      expect(h.ticketCalls, 0, reason: 'no point fetching ciphertext');
      expect(find.byKey(const Key('playerLine')), findsOneWidget);
    });

    for (final MapEntry<String, _Harness Function()> c in <String, _Harness Function()>{
      'the server has no file for it (a 404 becomes no ticket)': () => _Harness(ticket: null, ticketError: null)..hold = Completer<MediaTicket?>()..hold!.complete(null),
      'asking for the address throws': () => _Harness(ticketError: http.ClientException('no route to host')),
      'the download throws': () => _Harness(fetchError: const HttpException('media answered 500')),
      'the platform cannot open the file': () => _Harness(port: _Port(failOpen: true)),
    }.entries) {
      testWidgets('${c.key}: the same calm screen, no error, nothing spinning, opened not told', (t) async {
        final _Harness h = c.value();
        await t.pumpWidget(h.screen());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(h.opened, 0);
        expect(find.text('Mommy sent a video'), findsOneWidget);
        expect(find.byKey(const Key('playerPicture')), findsOneWidget);
        expect(find.byKey(const Key('playerToggle')), findsNothing, reason: 'no control that would do nothing');
        _expectCalm(t);
      });
    }

    testWidgets('a server that never answers is given up on after the timeout; the screen stays calm', (t) async {
      final _Harness h = _Harness(resolveTimeout: const Duration(seconds: 2))..hold = Completer<MediaTicket?>();
      await t.pumpWidget(h.screen());
      await t.pump(const Duration(seconds: 1));
      expect(h.opened, 0);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(h.opened, 0);
      expect(find.text('Mommy sent a video'), findsOneWidget);
      _expectCalm(t);
    });

    testWidgets('the player failing partway ends in the calm screen, not an error', (t) async {
      final _Harness h = _Harness();
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      expect(h.opened, 1);
      h.port!.breakIt();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('playerPicture')), findsOneWidget);
      _expectCalm(t);
    });

    testWidgets('leaving stops the sound, frees the player and deletes the downloaded file', (t) async {
      final _Harness h = _Harness();
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(h.port!.disposed, isTrue);
      expect(h.mediaDisposed, isTrue);
    });

    testWidgets('leaving before the file arrives still cleans up and records nothing', (t) async {
      final _Harness h = _Harness()..hold = Completer<MediaTicket?>();
      await t.pumpWidget(h.screen());
      await t.pump();
      await t.pumpWidget(const SizedBox());
      h.hold!.complete(MediaTicket(Uri.parse('$_base/media/x?sig=a'), 'video_msg'));
      await t.pumpAndSettle();
      expect(h.opened, 0);
      expect(h.port!.plays, 0);
    });

    testWidgets('the app going to the background pauses', (t) async {
      final _Harness h = _Harness();
      await t.pumpWidget(h.screen());
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pumpAndSettle();
      expect(h.port!.pauses, 1);
    });

    for (final (String, double, double, double) c in <(String, double, double, double)>[
      ('Fold5 cover screen', 344, 760, 1.0),
      ('a short landscape phone', 740, 320, 1.0),
      ('big text', 360, 640, 2.0),
      ('a tablet', 1100, 700, 1.0),
    ]) {
      testWidgets('fits on ${c.$1} with no overflow', (t) async {
        t.view.physicalSize = Size(c.$2, c.$3);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = c.$4;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearAllTestValues);
        final _Harness h = _Harness();
        await t.pumpWidget(h.screen());
        await t.pumpAndSettle();
        h.port!.finish();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('the inbox: opened is recorded on first play, never on the tap', () {
    Map<String, Object?> row(String id, {String state = 'delivered', String kind = 'video_msg'}) =>
        <String, Object?>{'id': id, 'payload_kind': kind, 'state': state, 'sender_name': 'Dad', 'sender_id': 'g-1',
          'deliveredAtLabel': '7:04 AM', 'media_id': 'm-$id'};

    http.Response inbox(List<Map<String, Object?>> rows) => http.Response(jsonEncode(<String, Object?>{'entries': rows}), 200);

    ({List<OutboxItem> items, ReceiptQueue queue}) mem() {
      final List<OutboxItem> items = <OutboxItem>[];
      final ReceiptQueue q = ReceiptQueue.over(
          load: () async => List<OutboxItem>.of(items),
          save: (List<OutboxItem> l) async {
            items
              ..clear()
              ..addAll(l);
          });
      return (items: items, queue: q);
    }

    Widget live(MockClient mock, ReceiptQueue q, {MediaFetcher? fetch, MessagePlaybackPort Function()? port}) => MaterialApp(
        home: InboxScreen(
            childName: 'Ivy', messages: const <InboxMessage>[],
            baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok',
            httpClient: mock, receiptQueue: q, refreshEvery: null,
            mediaFetcher: fetch ?? (Uri u) async => LocalMedia('/nowhere/f'),
            playbackFactory: port ?? _Port.new,
            pictureBuilder: (BuildContext c, String p, VoidCallback shown, VoidCallback f) {
              WidgetsBinding.instance.addPostFrameCallback((_) => shown());
              return const SizedBox(key: Key('picture'), width: 20, height: 20);
            }));

    MockClient server({
      required List<Map<String, Object?>> rows,
      required List<String> log,
      http.Response Function()? media,
      bool failPost = false,
    }) =>
        MockClient((http.Request r) async {
          log.add('${r.method} ${r.url.path}');
          if (r.method == 'POST') {
            if (failPost) throw http.ClientException('down');
            return http.Response('{"ok":true}', 200);
          }
          if (r.url.path.endsWith('/media-url')) {
            return (media ?? () => http.Response('{"signedUrl":"http://api.test/media/children/child-a/messages/m?exp=1&sig=a","absolute":true,"kind":"video_msg","ttl":300}', 200))();
          }
          return inbox(rows);
        });

    Color? fill(WidgetTester t) => t.widget<CircleAvatar>(find.byType(CircleAvatar).first).backgroundColor;

    testWidgets('tapping only opens the player; the server hears "opened" once the video plays, then her receipt follows', (t) async {
      final List<String> log = <String>[];
      final m = mem();
      final _Port port = _Port(autoPlay: false);
      await t.pumpWidget(live(server(rows: <Map<String, Object?>>[row('real-1')], log: log), m.queue, port: () => port));
      await t.pumpAndSettle();
      final Color? before = fill(t);
      await t.tap(find.textContaining('Dad sent a video'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('playerLine')), findsOneWidget);
      expect(log.where((String l) => l.startsWith('POST')), isEmpty, reason: 'the tap alone tells nobody');
      port.startPlaying();
      await t.pumpAndSettle();
      expect(log.where((String l) => l == 'POST /v1/children/child-a/inbox/real-1/opened'), hasLength(1));
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(fill(t), isNot(equals(before)), reason: 'now a plain, opened tile');
    });

    testWidgets('a message that could not be played stays unopened: no receipt screen, no POST, no words', (t) async {
      for (final http.Response Function() media in <http.Response Function()>[
        () => http.Response('{"error":"message_not_found"}', 404),
        () => http.Response('<html>captive portal</html>', 200),
        () => http.Response('{"signedUrl":"https://evil.example/media/x?sig=a","absolute":true}', 200),
        () => http.Response('{"signedUrl":"/v1/me"}', 200),
      ]) {
        final List<String> log = <String>[];
        final m = mem();
        int fetched = 0;
        await t.pumpWidget(live(server(rows: <Map<String, Object?>>[row('real-1')], log: log, media: media), m.queue,
            fetch: (Uri u) async {
          fetched++;
          return LocalMedia('/nowhere/f');
        }));
        await t.pumpAndSettle();
        final Color? before = fill(t);
        await t.tap(find.textContaining('Dad sent a video'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('playerLine')), findsOneWidget);
        _expectCalm(t);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byType(ReceiptScreen), findsNothing);
        expect(log.where((String l) => l.startsWith('POST')), isEmpty);
        expect(m.items, isEmpty);
        expect(fetched, 0, reason: 'a refused address is never fetched');
        expect(fill(t), before, reason: 'still unopened, can be tried again');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('no signal at all: the tap leads to the calm screen and back, nothing broken, nothing recorded', (t) async {
      final m = mem();
      final MockClient dead = MockClient((http.Request r) async {
        if (r.url.path.endsWith('/inbox')) return inbox(<Map<String, Object?>>[row('real-1')]);
        throw http.ClientException('no route to host');
      });
      await t.pumpWidget(live(dead, m.queue));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Dad sent a video'));
      await t.pumpAndSettle();
      _expectCalm(t);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsNothing);
      expect(m.items, isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('played, but the server cannot be told: it waits in the outbox, unseen, and the tile is opened', (t) async {
      final List<String> log = <String>[];
      final m = mem();
      await t.pumpWidget(live(server(rows: <Map<String, Object?>>[row('real-1')], log: log, failPost: true), m.queue));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Dad sent a video'));
      await t.pumpAndSettle();
      expect(m.items, hasLength(1));
      expect(m.items.single.payload, <String, Object?>{'messageId': 'real-1'});
      _expectCalm(t);
    });

    testWidgets('a nudge needs no file: its sentence opens it, and the server is asked for no media', (t) async {
      final List<String> log = <String>[];
      final m = mem();
      await t.pumpWidget(live(server(rows: <Map<String, Object?>>[row('n1', kind: 'nudge')], log: log), m.queue));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('is thinking of you'));
      await t.pumpAndSettle();
      expect(log.where((String l) => l.endsWith('/media-url')), isEmpty);
      expect(log.where((String l) => l == 'POST /v1/children/child-a/inbox/n1/opened'), hasLength(1));
    });

    testWidgets('a picture is shown from the same vetted address and opened on its first frame', (t) async {
      final List<String> log = <String>[];
      final m = mem();
      await t.pumpWidget(live(server(rows: <Map<String, Object?>>[row('p1', kind: 'photo')], log: log), m.queue));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('sent a picture'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('picture')), findsOneWidget);
      expect(log.where((String l) => l == 'POST /v1/children/child-a/inbox/p1/opened'), hasLength(1));
    });

    testWidgets('watching something again does not tell the server again', (t) async {
      final List<String> log = <String>[];
      final m = mem();
      await t.pumpWidget(live(server(rows: <Map<String, Object?>>[row('real-1', state: 'opened')], log: log), m.queue));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Dad sent a video'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsOneWidget, reason: 'an opened message goes on to its receipt, as before');
      expect(log.where((String l) => l.startsWith('POST')), isEmpty);
    });

    testWidgets('the preview build keeps its old behaviour: no player, the tap opens the receipt', (t) async {
      await t.pumpWidget(const MaterialApp(home: InboxScreen(childName: 'Ivy', messages: demoInboxMessages)));
      await t.tap(find.textContaining('sent a video').first);
      await t.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsOneWidget);
      expect(find.byKey(const Key('playerLine')), findsNothing);
    });
  });

  test('no adult word reaches the player: it imports nothing from the account, settings or care files', () {
    final String src = File('lib/message_player.dart').readAsStringSync();
    for (final String banned in <String>['family_account', 'guardian_', 'care_', 'settings', 'pin_', 'journal']) {
      expect(RegExp("^import .*$banned", multiLine: true).hasMatch(src), isFalse, reason: banned);
    }
  });
}
