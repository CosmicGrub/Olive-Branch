// OLIVE BRANCH — network transport for live checkers play. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline) — manually run
// via `flutter analyze`/`flutter test` as part of this feature's own
// security review; see networked_checkers_channel_test.dart. Extends the
// existing local pass-and-play checkers (game_checkers.dart) to two paired
// devices, relayed through this app's own authenticated backend server —
// see scaffold/packages/game-sync/src/table.ts and scaffold/server/
// game_tables.mjs for the server-side half of this contract. This is
// explicitly NOT peer-to-peer and NOT LAN-discovered: every byte crosses
// the same backend every other real feature in this app already trusts.
//
// SECURITY NOTE — defense in depth: this class is TRANSPORT ONLY. It parses
// and shape-checks incoming frames (never trusting a frame just because it
// arrived over the socket at all — a malformed one is dropped, not passed
// on), but it never decides whether a MOVE is legal. Every incoming remote
// move is re-validated by game_checkers.dart's `_applyRemoteMove` through
// checkers' own existing pure engine (`playCheckers`) before it is ever
// applied to the local board. See that method's own doc comment.
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'game_checkers.dart';

/// One live WebSocket connection to ONE table, already authenticated by the
/// short-lived, single-use join token minted via
/// `OliveApi.requestGameTable`/`OliveApi.joinGameTable`. `wsUrl` is this
/// app's own backend (wss:// in any real deployment); the class never
/// connects anywhere else and never accepts a connection FROM anywhere —
/// there is no listening/discovery side to this at all.
class NetworkedCheckersChannel {
  NetworkedCheckersChannel({
    required String wsUrl,
    required String token,
    required this.mySeat,
    WebSocketChannel Function(Uri)? connect,
  }) {
    final uri = Uri.parse(wsUrl).replace(queryParameters: {'token': token});
    _channel = (connect ?? WebSocketChannel.connect)(uri);
    // No initial 'connecting' event here: `_statusController` is a broadcast
    // stream, so anything added before a consumer subscribes (e.g. before
    // GameCheckers.initState runs on the next frame) would just be dropped,
    // not buffered. The receiving widget already defaults to `connecting`
    // on its own (see CkNetStatus's use in game_checkers.dart), so the
    // narrower, honest contract here is: this stream only ever emits a
    // state CHANGE, never the implicit starting one.
    _sub = _channel.stream.listen(
      _onData,
      onDone: () => _closeWith(CkNetStatus.ended),
      onError: (Object _) => _closeWith(CkNetStatus.ended),
      cancelOnError: true,
    );
  }

  /// Which seat (0 or 1) the SERVER minted this device's token for — never
  /// chosen by the client. Seat 0 is always the side that moves first
  /// (`CkSide.child` in the local engine's own board setup).
  final int mySeat;
  CkSide get mySide => mySeat == 0 ? CkSide.child : CkSide.parent;

  late final WebSocketChannel _channel;
  late final StreamSubscription<dynamic> _sub;
  final _moveController = StreamController<CkRemoteMove>.broadcast();
  final _statusController = StreamController<CkNetStatus>.broadcast();
  bool _ended = false;

  Stream<CkRemoteMove> get remoteMoves => _moveController.stream;
  Stream<CkNetStatus> get status => _statusController.stream;

  void _closeWith(CkNetStatus s) {
    if (_ended) return;
    _ended = true;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Deny-by-default parsing, mirroring the server's own posture
  /// (table.ts's `parseClientMessage`): anything not exactly the expected
  /// shape is dropped silently rather than guessed at or allowed to crash
  /// the UI. This server is our own, so a malformed frame here would be a
  /// server bug, not an attack — but the client still never trusts it blind.
  void _onData(dynamic raw) {
    if (raw is! String) return; // this server only ever sends text frames
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final msg = decoded;

    switch (msg['type']) {
      case 'welcome':
        _statusController.add(
          msg['status'] == 'active' ? CkNetStatus.active : CkNetStatus.waitingForPeer,
        );
        return;
      case 'peer_joined':
        _statusController.add(CkNetStatus.active);
        return;
      case 'move':
        final seat = msg['seat'];
        if (seat is! int || seat == mySeat) return; // malformed, or our own echo
        final from = _cell(msg['from']);
        final to = _cell(msg['to']);
        final continues = msg['continues'];
        if (from == null || to == null || continues is! bool) return;
        _moveController.add(CkRemoteMove(from, to, continues));
        return;
      case 'table_closed':
      case 'error':
        _closeWith(CkNetStatus.ended);
        return;
      default:
        return; // unrecognized message type — ignore, never guess
    }
  }

  CkCell? _cell(dynamic v) {
    if (v is! List || v.length != 2) return null;
    final r = v[0], c = v[1];
    if (r is! int || c is! int || r < 0 || r > 7 || c < 0 || c > 7) return null;
    return (r, c);
  }

  /// Sends a move THIS device's own player already made and already had
  /// validated locally via `playCheckers` — see game_checkers.dart's
  /// `_applyMove`. Never sends a seat: the server trusts only the seat
  /// bound to this authenticated connection (table.ts's own T3), so
  /// declaring one here would be pointless even if the server accepted it.
  void sendMove(CkCell from, CkCell to, {required bool continues}) {
    _channel.sink.add(jsonEncode({
      'type': 'move',
      'from': [from.$1, from.$2],
      'to': [to.$1, to.$2],
      'continues': continues,
    }));
  }

  /// Wires this channel into a [GameCheckers] screen — see that widget's
  /// `network` parameter. game_checkers.dart never imports this file; this
  /// is the only direction the dependency runs.
  CkNetworkHook toHook() => CkNetworkHook(
        mySide: mySide,
        onLocalMove: sendMove,
        remoteMoves: remoteMoves,
        status: status,
      );

  Future<void> close() async {
    await _sub.cancel();
    await _channel.sink.close();
    await _moveController.close();
    await _statusController.close();
  }
}
