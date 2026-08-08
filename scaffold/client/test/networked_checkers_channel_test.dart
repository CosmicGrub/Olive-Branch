// OLIVE BRANCH — NetworkedCheckersChannel. Security-review companion:
// exercises the TRANSPORT layer's own deny-by-default parsing (a malformed
// or spoofed-seat frame must never surface as a move) using a fake
// WebSocketChannel — no real socket, no real server. Defense-in-depth game
// LEGALITY re-validation is a separate concern, covered in
// game_checkers_network_test.dart against the real `playCheckers` engine.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:olive_client/game_checkers.dart';
import 'package:olive_client/networked_checkers_channel.dart';

class _FakeSink implements WebSocketSink {
  final List<dynamic> sent = [];
  final _doneCompleter = Completer<void>();
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  Future<void> get done => _doneCompleter.future;
}

class _FakeWebSocketChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
  _FakeWebSocketChannel(this._incoming, this.sink);
  final StreamController<dynamic> _incoming;
  @override
  final WebSocketSink sink;
  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  Future<void> get ready => Future.value();
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<dynamic> incoming;
  late _FakeSink sink;
  late Uri capturedUri;

  NetworkedCheckersChannel makeChannel({int mySeat = 0}) {
    incoming = StreamController<dynamic>.broadcast();
    sink = _FakeSink();
    return NetworkedCheckersChannel(
      wsUrl: 'ws://test.local/v1/game-tables/t_abc/socket',
      token: 'tok-123',
      mySeat: mySeat,
      connect: (uri) {
        capturedUri = uri;
        return _FakeWebSocketChannel(incoming, sink);
      },
    );
  }

  test('connects with the token carried as a query parameter, on the exact table path', () async {
    final ch = makeChannel();
    expect(capturedUri.queryParameters['token'], 'tok-123');
    expect(capturedUri.path, '/v1/game-tables/t_abc/socket');
    await ch.close();
  });

  test('mySide maps seat 0 -> child, seat 1 -> parent (server-assigned, never chosen here)',
      () async {
    final a = makeChannel(mySeat: 0);
    final b = makeChannel(mySeat: 1);
    expect(a.mySide, CkSide.child);
    expect(b.mySide, CkSide.parent);
    await a.close();
    await b.close();
  });

  test('sendMove writes the exact wire shape and NEVER includes a seat', () async {
    final ch = makeChannel();
    ch.sendMove((5, 0), (4, 1), continues: false);
    expect(sink.sent, hasLength(1));
    final sent = jsonDecode(sink.sent.single as String) as Map<String, dynamic>;
    expect(sent, {
      'type': 'move',
      'from': [5, 0],
      'to': [4, 1],
      'continues': false,
    });
    expect(sent.containsKey('seat'), isFalse,
        reason: 'the server assigns and trusts only the seat bound to the '
            'authenticated connection — declaring one here would be pointless '
            'even if the server accepted it');
    await ch.close();
  });

  test('a real "move" frame from the OTHER seat is surfaced as a CkRemoteMove', () async {
    final ch = makeChannel(mySeat: 0);
    final moves = <CkRemoteMove>[];
    ch.remoteMoves.listen(moves.add);
    incoming.add(jsonEncode({
      'type': 'move', 'seat': 1, 'from': [2, 3], 'to': [3, 4], 'continues': false,
    }));
    await settle();
    expect(moves, hasLength(1));
    expect(moves.single.from, (2, 3));
    expect(moves.single.to, (3, 4));
    expect(moves.single.continues, false);
    await ch.close();
  });

  test('a frame claiming to be OUR OWN seat is ignored (echo / spoofed self)', () async {
    final ch = makeChannel(mySeat: 0);
    final moves = <CkRemoteMove>[];
    ch.remoteMoves.listen(moves.add);
    incoming.add(jsonEncode({
      'type': 'move', 'seat': 0, 'from': [2, 3], 'to': [3, 4], 'continues': false,
    }));
    await settle();
    expect(moves, isEmpty);
    await ch.close();
  });

  test('malformed / out-of-shape frames are dropped — never thrown, never surfaced as a move',
      () async {
    final ch = makeChannel();
    final moves = <CkRemoteMove>[];
    ch.remoteMoves.listen(moves.add);
    final badFrames = <dynamic>[
      'not json at all {{{',
      jsonEncode('a bare string'),
      jsonEncode([1, 2, 3]),
      jsonEncode({'type': 'move', 'seat': 1, 'from': [9, 9], 'to': [0, 0], 'continues': false}),
      jsonEncode({'type': 'move', 'seat': 1, 'from': [1], 'to': [0, 0], 'continues': false}),
      jsonEncode({'type': 'move', 'seat': 'one', 'from': [1, 1], 'to': [0, 0], 'continues': false}),
      jsonEncode({'type': 'move', 'seat': 1, 'from': [1, 1], 'to': [0, 0], 'continues': 'yes'}),
      jsonEncode({'type': 'move', 'seat': 1, 'from': [1, 1], 'to': [0, 0]}),
      jsonEncode({'type': 'unknown-thing-entirely'}),
      42,
      3.14,
      true,
    ];
    for (final bad in badFrames) {
      incoming.add(bad);
    }
    await settle();
    expect(moves, isEmpty,
        reason: 'not one malformed frame out of ${badFrames.length} should ever surface as a move');
    await ch.close();
  });

  test('welcome/peer_joined/table_closed drive the status stream correctly', () async {
    final ch = makeChannel();
    final statuses = <CkNetStatus>[];
    ch.status.listen(statuses.add);

    incoming.add(jsonEncode({'type': 'welcome', 'seat': 0, 'status': 'pending', 'turnSeat': 0}));
    await settle();
    incoming.add(jsonEncode({'type': 'peer_joined'}));
    await settle();
    incoming.add(jsonEncode({'type': 'table_closed', 'reason': 'peer_left'}));
    await settle();

    expect(statuses, [CkNetStatus.waitingForPeer, CkNetStatus.active, CkNetStatus.ended]);
    await ch.close();
  });

  test('a welcome reporting status "active" (both seats already joined) goes straight to active',
      () async {
    final ch = makeChannel();
    final statuses = <CkNetStatus>[];
    ch.status.listen(statuses.add);
    incoming.add(jsonEncode({'type': 'welcome', 'seat': 1, 'status': 'active', 'turnSeat': 0}));
    await settle();
    expect(statuses, [CkNetStatus.active]);
    await ch.close();
  });

  test('a server-side "error" frame ends the connection status', () async {
    final ch = makeChannel();
    final statuses = <CkNetStatus>[];
    ch.status.listen(statuses.add);
    incoming.add(jsonEncode({'type': 'error', 'reason': 'out_of_turn'}));
    await settle();
    expect(statuses, [CkNetStatus.ended]);
    await ch.close();
  });

  test('the raw socket closing ends the status stream, without throwing', () async {
    final ch = makeChannel();
    final statuses = <CkNetStatus>[];
    ch.status.listen(statuses.add);
    await incoming.close();
    await settle();
    expect(statuses, [CkNetStatus.ended]);
  });

  test('toHook() exposes the server-assigned seat mapping and both streams', () async {
    final ch = makeChannel(mySeat: 1);
    final hook = ch.toHook();
    expect(hook.mySide, CkSide.parent);

    final moves = <CkRemoteMove>[];
    hook.remoteMoves.listen(moves.add);
    incoming.add(jsonEncode({'type': 'move', 'seat': 0, 'from': [5, 0], 'to': [4, 1], 'continues': false}));
    await settle();
    expect(moves, hasLength(1));

    hook.onLocalMove((2, 3), (3, 4), continues: false);
    expect(sink.sent, hasLength(1));
    await ch.close();
  });
}
