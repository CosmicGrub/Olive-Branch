// OLIVE BRANCH — the play session controller, tested with two devices over the in-memory transport.
// These are the cases the report found could not be tested before ("the vs-peer path needs a genuine mDNS
// pairing"): a move while the other device is away, a duplicated or reordered message, a hostile sender, a game
// that survives its dealer being killed, a rematch, and the calm notice at every step.
//
// Device 'a' is the guest, device 'b' is the dealer (the authority) and moves first in Connect 4.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_modes.dart' show troubleBanned;
import 'package:olive_client/connect4_play.dart';
import 'package:olive_client/live_games.dart' show Side, liveForbidden;
import 'package:olive_client/play_game.dart';
import 'package:olive_client/play_notice.dart';
import 'package:olive_client/play_save.dart';
import 'package:olive_client/play_session.dart';

import 'play_harness.dart';

const _sid = '0102030405060708';

Map<String, dynamic> _env({required String t, required int n, int ack = 0, String sid = _sid, Map<String, dynamic>? p, String? d, String g = 'connect4'}) =>
    <String, dynamic>{'v': 1, 'sid': sid, 'n': n, 'ack': ack, 't': t, 'g': g, 'p': ?p, 'd': ?d};

int _discs(Connect4PlayGame g) => g.board.discCount;

/// A save store that remembers every snapshot it was ever offered.
class _RecordingStore extends MemoryPlaySaveStore {
  final List<Map<String, dynamic>> offered = [];
  @override
  Future<bool> save(String gameId, Map<String, dynamic> snapshot) {
    offered.add(snapshot);
    return super.save(gameId, snapshot);
  }
}

void main() {
  group('hello and the first state', () {
    test('the guest adopts the dealer session and both see an empty board', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      expect(t.guest.session.sid, _sid);
      expect(_discs(t.guestGame), 0);
      expect(t.guest.notice, PlayNoticeKind.none);
      expect(t.dealer.notice, PlayNoticeKind.none);
      expect(t.guest.hasMetPeer, isTrue);
    });

    test("the dealer's move reaches the guest, in order, with a state each time", () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      expect(t.guestGame.board.columns[3], [Side.b]);
      expect(t.guestGame.toMove, Side.a);
    });
  });

  group('a move is not applied until it is answered (no more local-first desync)', () {
    test("the guest's own board does not change when it asks; it changes when the dealer answers", () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      t.dealerT.hold = true; // the dealer's answer is on its way but has not arrived
      t.guestGame.tapColumn(4);
      await pumpEventQueue();
      expect(t.guestGame.board.columns[4], isEmpty, reason: 'asked, not yet answered');
      expect(t.guestGame.awaiting, isTrue);
      expect(t.guestGame.canPlay, isFalse, reason: 'a second tap while waiting does nothing');
      t.dealerT.release();
      await pumpEventQueue();
      expect(t.guestGame.board.columns[4], [Side.a]);
      expect(t.guestGame.awaiting, isFalse);
    });

    test('a move that is not that seat\'s turn is refused and the guest is still answered with the board', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      // It is the dealer's turn. A stray move from the guest is refused, and the guest is told where things stand.
      final before = t.dealerT.sent.length;
      await t.guest.sendMove(<String, dynamic>{'column': 2});
      await pumpEventQueue();
      expect(_discs(t.dealerGame), 0);
      expect(t.dealer.rejected, contains('move_refused'));
      expect(t.dealerT.sent.length, greaterThan(before), reason: 'the refused ask still gets a state back');
    });
  });

  group('the other device away and back (the sendTurn no-op bug)', () {
    test('a move made while away is kept and goes through when they find each other again', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      t.guestT.setLinked(false);
      await pumpEventQueue();
      expect(t.guest.notice, PlayNoticeKind.away);
      expect(t.dealer.notice, PlayNoticeKind.away);
      t.guestGame.tapColumn(2);
      await pumpEventQueue();
      expect(t.guestT.refused, greaterThan(0), reason: 'the send was not possible');
      expect(_discs(t.dealerGame), 1, reason: 'nothing arrived while away');
      expect(t.guest.session.unacked, hasLength(1), reason: 'but the move was kept, not dropped');
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.dealerGame.board.columns[2], [Side.a]);
      expect(t.guestGame.board.columns[2], [Side.a]);
      expect(t.guest.notice, PlayNoticeKind.none);
      expect(t.dealer.notice, PlayNoticeKind.none);
      expect(t.guest.session.unacked, isEmpty, reason: 'and it was acknowledged');
    });

    test('a state the dealer could not send is not kept; the guest gets a fresh one on return', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.guestT.setLinked(false);
      await pumpEventQueue();
      t.dealerGame.tapColumn(4);
      await pumpEventQueue();
      expect(t.guestGame.board.columns[4], isEmpty);
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.guestGame.board.columns[4], [Side.b], reason: 'nothing resyncing after the peer returned was the report\'s bug');
    });

    test('the game is still on screen while away: the notice never replaces or resets it', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(1);
      await pumpEventQueue();
      t.guestT.setLinked(false);
      await pumpEventQueue();
      expect(t.guestGame.board.columns[1], [Side.b]);
      expect(t.guest.endedForGood, isFalse);
    });
  });

  group('order, duplicates, replay (E3)', () {
    test('a duplicated move is applied once', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      t.guestT.duplicateNext = 1;
      t.guestGame.tapColumn(5);
      await pumpEventQueue();
      expect(_discs(t.dealerGame), 2);
      expect(t.dealer.rejected, contains('duplicate'));
    });

    test('a replay of an old state does not roll the board back', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      final old = jsonDecode(t.dealerT.sent.last) as Map<String, dynamic>;
      t.guestGame.tapColumn(1);
      await pumpEventQueue();
      expect(_discs(t.guestGame), 2);
      t.guestT.inject(old, asSeat: 'b'); // an old packet turning up late
      await pumpEventQueue();
      expect(_discs(t.guestGame), 2);
      expect(t.guest.rejected, anyOf(contains('stale'), contains('duplicate')));
    });

    test('states delivered out of order: the newest wins, the older one is dropped', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerT.hold = true;
      t.dealerGame.tapColumn(3); // state n
      await t.dealer.broadcastState(); // state n+1, same board
      t.dealerT.release(reversed: true);
      await pumpEventQueue();
      expect(t.guestGame.board.columns[3], [Side.b]);
      expect(t.guest.rejected, anyOf(contains('stale'), contains('duplicate')));
    });

    test('a lost ordered message is noticed by the gap and repaired by the state', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      t.guestT.dropNext = 1; // the guest's first move is eaten after a "successful" send
      t.guestGame.tapColumn(1);
      await pumpEventQueue();
      expect(_discs(t.dealerGame), 1);
      // The guest asks again later (its screen is still waiting); the dealer's own next ordered message exposes the loss.
      expect(t.guest.session.unacked, hasLength(1));
      await t.guest.sendMove(<String, dynamic>{'column': 1});
      await pumpEventQueue();
      expect(t.dealer.rejected, contains('gap'), reason: 'the second move skipped one: held back, not misapplied');
      // The dealer asked again; the guest resent what was never acknowledged, in order, and the lost move landed.
      expect(t.dealerGame.board.columns[1], [Side.a]);
      expect(_discs(t.dealerGame), 2);
      expect(_discs(t.guestGame), 2);
    });
  });

  group('who sent it is never read from the body (E1, E5)', () {
    test('a state from some other seat is refused and the board is untouched', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      final forged = _env(t: 'state', n: 50, p: <String, dynamic>{
        'columns': ['a', '', '', '', '', '', ''], 'toMove': 'b', 'outcome': 'none', 'winner': null,
      });
      t.guestT.inject(forged, asSeat: 'c');
      await pumpEventQueue();
      expect(_discs(t.guestGame), 0);
      expect(t.guest.rejected, contains('wrong_sender'));
    });

    test('a guest cannot send a state to the dealer', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerT.inject(_env(t: 'state', n: 90, p: <String, dynamic>{'columns': ['b', '', '', '', '', '', ''], 'toMove': 'a', 'outcome': 'none', 'winner': null}), asSeat: 'a');
      await pumpEventQueue();
      expect(_discs(t.dealerGame), 0);
      expect(t.dealer.rejected, contains('wrong_sender'));
    });

    test('a "from" field in the body is ignored: a move still counts as the seat the transport says', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      // It is the dealer's turn (seat b). A message that CLAIMS to be from b but arrives from seat a is a's move: refused.
      final claim = _env(t: 'move', n: 2, p: <String, dynamic>{'column': 1, 'from': 'b', 'seat': 'b'});
      claim['from'] = 'b';
      t.dealerT.inject(claim, asSeat: 'a');
      await pumpEventQueue();
      expect(_discs(t.dealerGame), 0);
    });

    test('a message for an unknown session is dropped', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerT.inject(_env(t: 'move', n: 2, sid: 'ffffffffffffffff', p: <String, dynamic>{'column': 1}), asSeat: 'a');
      await pumpEventQueue();
      expect(t.dealer.rejected, contains('unknown_sid'));
    });
  });

  group('untrusted input is refused quietly (E2)', () {
    test('oversized, malformed, forbidden-key and wrong-game messages change nothing and show nothing', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.guestT.inject('x' * 9000, asSeat: 'b');
      t.guestT.inject('{nope', asSeat: 'b');
      t.guestT.inject(<String, dynamic>{'v': 1, 't': 'move'}, asSeat: 'b');
      t.guestT.inject(_env(t: 'state', n: 60, p: <String, dynamic>{'columns': ['', '', '', '', '', '', ''], 'toMove': 'b', 'outcome': 'none', 'winner': null, 'score': 10}), asSeat: 'b');
      t.guestT.inject(_env(t: 'state', n: 61, g: 'uno', p: <String, dynamic>{'x': 1}), asSeat: 'b');
      await pumpEventQueue();
      expect(t.guest.rejected, containsAll(['too_large', 'not_json', 'bad_field', 'forbidden_key', 'wrong_game']));
      expect(t.guest.notice, PlayNoticeKind.none);
      expect(_discs(t.guestGame), 0);
    });

    test('a bad state shape is refused without changing the board', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(2);
      await pumpEventQueue();
      t.guestT.inject(_env(t: 'state', n: 70, p: <String, dynamic>{'columns': 'nope', 'toMove': 'a', 'outcome': 'none', 'winner': null}), asSeat: 'b');
      await pumpEventQueue();
      expect(t.guest.rejected, contains('bad_state'));
      expect(t.guestGame.board.columns[2], [Side.b]);
    });
  });

  group('unknown version and the old dialect', () {
    test('a newer protocol version ends the game calmly with no error words', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.guestT.inject(<String, dynamic>{..._env(t: 'state', n: 3, p: <String, dynamic>{}), 'v': 2}, asSeat: 'b');
      await pumpEventQueue();
      expect(t.guest.endedForGood, isTrue);
      expect(t.guest.notice, PlayNoticeKind.ended);
      expect(playNoticeLine(t.guest.notice).toLowerCase(), isNot(contains('version')));
    });

    test('the old un-enveloped dialect is handed to the one-release shim and never touches the game', () async {
      final seen = <Map<String, dynamic>>[];
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      final shimmed = PlaySessionController(spec: connect4Spec, game: t.dealerGame, transport: t.dealerT, onLegacy: seen.add);
      addTearDown(shimmed.dispose);
      shimmed.start();
      t.dealerT.inject(<String, dynamic>{'type': 'connect4_move', 'column': 3}, asSeat: 'a');
      await pumpEventQueue();
      expect(seen, hasLength(1));
      expect(_discs(t.dealerGame), 0);
    });
  });

  group('quiet desync check (no alarm)', () {
    test('a state whose digest does not match what the guest sees quietly asks again, at most three times in a row', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      final before = t.guestT.sent.length;
      for (var i = 0; i < 6; i++) {
        t.guestT.inject(_env(t: 'state', n: 100 + i, d: '00000000', p: <String, dynamic>{
          'columns': ['', '', '', 'b', '', '', ''], 'toMove': 'a', 'outcome': 'none', 'winner': null}), asSeat: 'b');
      }
      await pumpEventQueue();
      final asked = t.guestT.sent.skip(before).where((s) => (jsonDecode(s) as Map)['t'] == 'req_state').length;
      expect(asked, 3);
      expect(t.guest.notice, PlayNoticeKind.none, reason: 'nothing is shown to anyone');
    });

    test('a matching digest never asks', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      final askedAtStart = t.guestT.sent.length;
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      expect(t.guestT.sent.skip(askedAtStart).where((s) => (jsonDecode(s) as Map)['t'] == 'req_state'), isEmpty);
      final withDigest = t.dealerT.sent.map((s) => jsonDecode(s) as Map).where((m) => m['t'] == 'state');
      expect(withDigest, isNotEmpty);
      expect(withDigest.every((m) => m['d'] is String), isTrue);
    });
  });

  group('the dealer\'s save: a game survives the OS killing the app', () {
    test('after a kill the dealer carries on from the save, the guest adopts the new session, and both boards agree', () async {
      final store = _RecordingStore();
      final t = TwoDevices<Connect4PlayGame>(connect4Spec, storeForDealer: store);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      t.guestGame.tapColumn(2);
      await pumpEventQueue();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      expect(await store.load('connect4'), isNotNull);

      // The OS kills the dealer's app: its controller and game are gone. The guest is still running.
      t.dealer.dispose();
      t.guestT.setLinked(false);
      await pumpEventQueue();

      // The dealer relaunches: fresh game, fresh session id, same store.
      final game2 = Connect4PlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      final dealer2 = PlaySessionController(spec: connect4Spec, game: game2, transport: t.dealerT, store: store,
          sidBytes: () => const [9, 9, 9, 9, 9, 9, 9, 9]);
      addTearDown(dealer2.dispose);
      dealer2.start();
      expect(await dealer2.hasSavedGame(), isTrue);
      expect(await dealer2.resumeSavedGame(), isTrue);
      expect(game2.board.discCount, 3);
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.guest.session.sid, '0909090909090909', reason: 'the guest adopted the restored session');
      expect(t.guestGame.board.columns.map((c) => c.length).toList(), game2.board.columns.map((c) => c.length).toList());
      expect(t.guestGame.toMove, game2.toMove);
      // And play carries on in order after the restart.
      t.guestGame.tapColumn(0);
      await pumpEventQueue();
      expect(game2.board.columns[0], [Side.a]);
    });

    test('a snapshot never carries an outcome, a winner or a score, and a finished game is cleared, not saved', () async {
      final store = _RecordingStore();
      final t = TwoDevices<Connect4PlayGame>(connect4Spec, storeForDealer: store);
      addTearDown(t.dispose);
      await t.start();
      for (var i = 0; i < 3; i++) {
        t.dealerGame.tapColumn(0);
        await pumpEventQueue();
        t.guestGame.tapColumn(1);
        await pumpEventQueue();
      }
      expect(await store.load('connect4'), isNotNull);
      t.dealerGame.tapColumn(0); // four in the column: the dealer wins
      await pumpEventQueue();
      expect(t.dealerGame.finished, isTrue);
      expect(await store.load('connect4'), isNull, reason: 'a finished game is cleared');
      final banned = {...playSaveBannedKeys, ...liveForbidden.map((s) => s.toLowerCase())};
      for (final snap in store.offered) {
        expect(keysOf(snap).map((k) => k.toLowerCase()).toSet().intersection(banned), isEmpty);
      }
    });

    test('a damaged or impossible save is refused, never half-applied', () async {
      final g = Connect4PlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      expect(g.restore(<String, dynamic>{'columns': 'x', 'toMove': 'a', 'first': 'b'}), isFalse);
      expect(g.restore(<String, dynamic>{'columns': ['bbbb', '', '', '', '', '', ''], 'toMove': 'a', 'first': 'b'}), isFalse, reason: 'five discs would be impossible, and four in a row is a finished game');
      expect(g.restore(<String, dynamic>{'columns': ['b', '', '', '', '', '', ''], 'toMove': 'b', 'first': 'b'}), isFalse, reason: 'wrong turn for the disc count');
      expect(g.board.discCount, 0);
    });

    test('the guest saves nothing', () async {
      final store = _RecordingStore();
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      final guestWithStore = PlaySessionController(spec: connect4Spec, game: t.guestGame, transport: t.guestT, store: store);
      addTearDown(() { guestWithStore.dispose(); t.dispose(); });
      await t.start();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      expect(store.offered, isEmpty);
    });
  });

  group('Finish for now', () {
    test('tells the other device, ends both calmly and clears the save', () async {
      final store = _RecordingStore();
      final t = TwoDevices<Connect4PlayGame>(connect4Spec, storeForDealer: store);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(3);
      await pumpEventQueue();
      expect(await store.load('connect4'), isNotNull);
      await t.guest.finishForNow();
      await pumpEventQueue();
      expect(t.guest.notice, PlayNoticeKind.ended);
      expect(t.dealer.notice, PlayNoticeKind.ended);
      expect(await store.load('connect4'), isNull);
    });
  });

  group('rematch: either side asks, the other chooses', () {
    Future<TwoDevices<Connect4PlayGame>> finished() async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      await t.start();
      for (var i = 0; i < 3; i++) {
        t.dealerGame.tapColumn(0);
        await pumpEventQueue();
        t.guestGame.tapColumn(1);
        await pumpEventQueue();
      }
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      return t;
    }

    test('the guest asks, the dealer says yes: a fresh game on both', () async {
      final t = await finished();
      addTearDown(t.dispose);
      expect(t.guestGame.finished, isTrue);
      await t.guest.askRematch();
      await pumpEventQueue();
      expect(t.guest.rematch, PlayRematch.asked);
      expect(t.dealer.rematch, PlayRematch.offered);
      await t.dealer.acceptRematch();
      await pumpEventQueue();
      expect(t.dealerGame.finished, isFalse);
      expect(t.guestGame.finished, isFalse);
      expect(_discs(t.guestGame), 0);
      expect(t.guest.rematch, PlayRematch.none);
      expect(t.dealer.rematch, PlayRematch.none);
      expect(t.dealerGame.toMove, Side.a, reason: 'the opening seat alternates');
    });

    test('the dealer asks, the guest says yes', () async {
      final t = await finished();
      addTearDown(t.dispose);
      await t.dealer.askRematch();
      await pumpEventQueue();
      expect(t.guest.rematch, PlayRematch.offered);
      await t.guest.acceptRematch();
      await pumpEventQueue();
      expect(_discs(t.guestGame), 0);
      expect(_discs(t.dealerGame), 0);
      expect(t.guestGame.finished, isFalse);
    });

    test('both ask at once: that is a yes', () async {
      final t = await finished();
      addTearDown(t.dispose);
      t.dealerT.hold = true;
      await t.dealer.askRematch();
      await t.guest.askRematch();
      await pumpEventQueue();
      t.dealerT.release();
      await pumpEventQueue();
      expect(_discs(t.dealerGame), 0);
      expect(t.guestGame.finished, isFalse);
    });

    test('"Not now" and "Never mind" are quiet: the other side is told nothing', () async {
      final t = await finished();
      addTearDown(t.dispose);
      await t.guest.askRematch();
      await pumpEventQueue();
      final sentBefore = t.dealerT.sent.length + t.guestT.sent.length;
      t.dealer.declineRematch();
      t.guest.cancelRematchAsk();
      await pumpEventQueue();
      expect(t.dealerT.sent.length + t.guestT.sent.length, sentBefore);
      expect(t.dealer.rematch, PlayRematch.none);
      expect(t.guest.rematch, PlayRematch.none);
      expect(t.dealerGame.finished, isTrue, reason: 'the finished game is left as it was');
    });

    test('a rematch before the game is finished is ignored', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerT.inject(_env(t: 'rematch', n: 1), asSeat: 'a');
      await pumpEventQueue();
      expect(t.dealer.rematch, PlayRematch.none);
      expect(t.dealer.rejected, contains('rematch_not_finished'));
      await t.guest.askRematch();
      expect(t.guest.rematch, PlayRematch.none, reason: 'cannot ask while the game is still going');
    });

    test('a rematch ask is honoured once, not twice, when it arrives twice', () async {
      final t = await finished();
      addTearDown(t.dispose);
      t.guestT.duplicateNext = 1;
      await t.guest.askRematch();
      await pumpEventQueue();
      expect(t.dealer.rejected, contains('duplicate'));
      expect(t.dealer.rematch, PlayRematch.offered);
    });
  });

  group('the calm notice', () {
    test('away, then back: nothing alarming at any point', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      final seen = <PlayNoticeKind>[];
      t.guest.addListener(() => seen.add(t.guest.notice));
      t.guestT.setLinked(false);
      await pumpEventQueue();
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(seen, contains(PlayNoticeKind.away));
      expect(seen.last, PlayNoticeKind.none);
      expect(seen, isNot(contains(PlayNoticeKind.ended)));
    });

    test('a long quiet ends it for now, silently; the game is kept; and it comes back when they find each other', () async {
      final timers = <ManualTimer>[];
      final t = TwoDevices<Connect4PlayGame>(connect4Spec, quietEndAfter: const Duration(minutes: 30),
          timerFactory: (d, cb) { final m = ManualTimer(d, cb); timers.add(m); return m; });
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(2);
      await pumpEventQueue();
      t.guestT.setLinked(false);
      await pumpEventQueue();
      expect(t.guest.notice, PlayNoticeKind.away);
      expect(timers.where((m) => m.isActive).map((m) => m.duration), everyElement(const Duration(minutes: 30)));
      timers.where((m) => m.isActive).toList().forEach((m) => m.fire());
      expect(t.guest.notice, PlayNoticeKind.ended);
      expect(t.guest.endedForGood, isFalse, reason: 'a quiet is not a choice: the game is kept');
      expect(t.guestGame.board.columns[2], [Side.b]);
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.guest.notice, PlayNoticeKind.none);
    });

    test('every string the feature can show is free of error words, names, digits and pressure', () {
      final banned = [
        ...troubleBanned, 'sorry', 'oops', 'quit', 'gave up', 'timed out', 'hurry', 'wait',
        'seconds', 'minutes', 'remaining',
      ];
      for (final s in playNoticeStrings()) {
        final lower = s.toLowerCase();
        for (final b in banned) {
          expect(lower.contains(b), isFalse, reason: '"$b" in "$s"');
        }
        expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'no digits in "$s"');
      }
    });
  });

  group('hidden information never crosses (E6) and bots act only on the dealer', () {
    test('a state that would carry hidden keys is refused and never sent', () async {
      final spec = PlayGameSpec(
        id: 'toy', title: 'Toy', minAge: 5, minSeats: 2, maxSeats: 2, modes: const {PlayMode.pair},
        create: (ctx) => _LeakyGame(ctx), hiddenInfo: true, hiddenKeys: const ['hands'],
      );
      final t = TwoDevices<_LeakyGame>(spec);
      addTearDown(t.dispose);
      await t.start();
      final before = t.dealerT.sent.length;
      await t.dealer.broadcastState();
      expect(t.dealer.blockedSends, greaterThan(0));
      expect(t.dealerT.sent.where((s) => (jsonDecode(s) as Map)['t'] == 'state'), isEmpty);
      expect(t.dealerT.sent.skip(before).where((s) => (jsonDecode(s) as Map)['t'] == 'state'), isEmpty);
    });

    test('a seed can never be sent from a hiddenInfo game, even if the game does not list it', () async {
      final spec = PlayGameSpec(
        id: 'toy', title: 'Toy', minAge: 5, minSeats: 2, maxSeats: 2, modes: const {PlayMode.pair},
        create: (ctx) => _LeakyGame(ctx, key: 'seed'), hiddenInfo: true, hiddenKeys: const ['hands'],
      );
      final t = TwoDevices<_LeakyGame>(spec);
      addTearDown(t.dispose);
      await t.start();
      await t.dealer.broadcastState();
      expect(t.dealer.blockedSends, greaterThan(0));
      expect(t.dealerT.sent.where((s) => (jsonDecode(s) as Map)['t'] == 'state'), isEmpty);
    });

    test('a state with a forbidden child-facing key is refused on send too', () async {
      final spec = PlayGameSpec(
        id: 'toy', title: 'Toy', minAge: 5, minSeats: 2, maxSeats: 2, modes: const {PlayMode.pair},
        create: (ctx) => _LeakyGame(ctx, key: 'streak'),
      );
      final t = TwoDevices<_LeakyGame>(spec);
      addTearDown(t.dispose);
      await t.start();
      await t.dealer.broadcastState();
      expect(t.dealer.blockedSends, greaterThan(0));
      expect(t.dealerT.sent.where((s) => (jsonDecode(s) as Map)['t'] == 'state'), isEmpty);
    });

    test('only the dealer may run bots; a computer seat cannot be moved by the other device', () async {
      final spec = PlayGameSpec(
        id: 'toy', title: 'Toy', minAge: 5, minSeats: 2, maxSeats: 3, modes: const {PlayMode.pair},
        create: (ctx) => _LeakyGame(ctx),
      );
      final t = TwoDevices<_LeakyGame>(spec);
      addTearDown(t.dispose);
      await t.start();
      expect(t.dealer.mayRunBots, isTrue);
      expect(t.guest.mayRunBots, isFalse);
    });
  });
}

/// A game that sends whatever it is told to, to prove the controller's guards.
class _LeakyGame extends PlayGame {
  _LeakyGame(super.ctx, {this.key = 'hands'});
  final String key;
  @override
  bool get started => true;
  @override
  bool get finished => false;
  @override
  Map<String, dynamic>? stateFor(String seatId) => <String, dynamic>{key: <String, dynamic>{'a': <String>['R7']}, 'ok': 1};
}
