// OLIVE BRANCH — Puzzle together and Twenty Questions on the shared play contract, over the in-memory transport.
// Verified by CI, headless.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/live_games.dart' show Side, liveForbidden;
import 'package:olive_client/play_game.dart';
import 'package:olive_client/play_save.dart';
import 'package:olive_client/puzzle_play.dart';
import 'package:olive_client/together_puzzle.dart';
import 'package:olive_client/twenty_questions_play.dart';

import 'play_harness.dart';

Future<TwoDevices<PuzzlePlayGame>> puzzleTable({PlaySaveStore? store}) async {
  final t = TwoDevices<PuzzlePlayGame>(puzzleSpec, seed: 3, storeForDealer: store);
  await t.start();
  t.dealerGame.begin();
  await pumpEventQueue();
  return t;
}

void main() {
  group('Puzzle together', () {
    test('the dealer opens it, the guest is given the board, and pieces go in turn, each side asking the dealer', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      expect(g.started, isTrue);
      expect(d.state!.mover, Side.b);
      expect(d.myTurn, isTrue);
      expect(g.myTurn, isFalse);

      d.place('cow', 'slot1');
      await pumpEventQueue();
      expect(g.state!.placedPieces, {'cow'});
      expect(g.myTurn, isTrue);

      t.guestT.hold = true; // the ask is on its way
      g.place('barn', 'slot2');
      expect(g.awaiting, isTrue, reason: 'the asking device waits for the answer');
      expect(g.state!.placedPieces, {'cow'}, reason: 'its own piece does not appear before the dealer says so');
      t.guestT.hold = false;
      t.guestT.release();
      await pumpEventQueue();
      expect(g.awaiting, isFalse);
      expect(d.state!.placedPieces, {'cow', 'barn'});
      expect(g.state!.placedPieces, {'cow', 'barn'});
    });

    test('a whole puzzle is solved on both devices and the dealer offers a rematch', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      final def = farmyardPuzzle;
      for (var i = 0; i < def.pieces.length; i++) {
        final piece = def.pieces[i];
        final me = d.myTurn ? d : g;
        me.place(piece.id, piece.correctSlotId);
        await pumpEventQueue();
      }
      expect(d.finished, isTrue);
      expect(g.finished, isTrue);
      await t.guest.askRematch();
      await pumpEventQueue();
      await t.dealer.acceptRematch();
      await pumpEventQueue();
      expect(d.state!.placedPieces, isEmpty);
      expect(g.state!.placedPieces, isEmpty);
    });

    test('a wrong spot is dropped where it is made: nothing is sent, nothing is recorded', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      final sent = t.dealerT.sent.length;
      t.dealerGame.place('cow', 'slot3');
      await pumpEventQueue();
      expect(t.dealerT.sent.length, sent);
      final guestSent = t.guestT.sent.length;
      t.dealerGame.place('cow', 'slot1');
      await pumpEventQueue();
      t.guestGame.place('barn', 'slot5'); // wrong spot
      await pumpEventQueue();
      expect(t.guestT.sent.length, guestSent);
      expect(t.guestGame.awaiting, isFalse);
    });

    test('a move out of turn, a repeat, a junk body or a self-addressed one is refused by the dealer', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      final d = t.dealerGame;
      expect(d.onMove('a', {'piece': 'cow', 'slot': 'slot1'}), PlayMoveOutcome.refused, reason: 'it is the dealer\'s turn');
      d.place('cow', 'slot1');
      expect(d.onMove('a', {'piece': 'cow', 'slot': 'slot1'}), PlayMoveOutcome.refused, reason: 'already placed');
      expect(d.onMove('a', {'piece': 'barn', 'slot': 'slot3'}), PlayMoveOutcome.refused, reason: 'wrong spot');
      expect(d.onMove('a', {'piece': 5, 'slot': 'slot2'}), PlayMoveOutcome.refused);
      expect(d.onMove('a', {}), PlayMoveOutcome.refused);
      expect(d.onMove('b', {'piece': 'barn', 'slot': 'slot2'}), PlayMoveOutcome.refused, reason: 'from itself');
      expect(d.onMove('z', {'piece': 'barn', 'slot': 'slot2'}), PlayMoveOutcome.refused);
      expect(d.state!.placedPieces, {'cow'});
    });

    test('a bad state is refused and changes nothing', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      final g = t.guestGame;
      final before = jsonEncode(g.publicDigestInput());
      for (final bad in <Map<String, dynamic>>[
        {}, {'puzzleId': 'nope', 'mover': 'a', 'placedPieces': <String>[], 'solved': false},
        {'puzzleId': 'farmyard', 'mover': 'q', 'placedPieces': <String>[], 'solved': false},
        {'puzzleId': 'farmyard', 'mover': 'a', 'placedPieces': ['dragon'], 'solved': false},
        {'puzzleId': 'farmyard', 'mover': 'a', 'placedPieces': [3], 'solved': false},
        {'puzzleId': 'farmyard', 'mover': 'a', 'placedPieces': 'cow', 'solved': false},
      ]) {
        expect(g.applyState(bad), isFalse, reason: '$bad');
      }
      expect(jsonEncode(g.publicDigestInput()), before);
    });

    test('away and back: a placement made while away is kept and lands in order', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      t.dealerGame.place('cow', 'slot1');
      await pumpEventQueue();
      t.guestT.setLinked(false);
      t.guestGame.place('barn', 'slot2');
      await pumpEventQueue();
      expect(t.dealerGame.state!.placedPieces, {'cow'});
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.dealerGame.state!.placedPieces, {'cow', 'barn'});
      expect(t.guestGame.state!.placedPieces, {'cow', 'barn'});
    });

    test('the dealer\'s save carries the pieces and never an outcome; a finished puzzle is cleared, not kept', () async {
      final store = MemoryPlaySaveStore();
      final t = await puzzleTable(store: store);
      addTearDown(t.dispose);
      t.dealerGame.place('cow', 'slot1');
      await pumpEventQueue();
      final saved = await store.load('puzzle');
      expect(saved, isNotNull);
      expect(saved!['placedPieces'], ['cow']);
      expect(playSaveAcceptable(saved), isTrue);

      final fresh = PuzzlePlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      expect(fresh.restore(saved), isTrue);
      expect(fresh.state!.placedPieces, {'cow'});
      expect(fresh.restore({'puzzleId': 'farmyard', 'mover': 'a', 'placedPieces': ['dragon']}), isFalse);
      expect(fresh.restore({}), isFalse);
    });

    test('nothing on the wire is a count, a score or a result word other than the one fact "solved"', () async {
      final t = await puzzleTable();
      addTearDown(t.dispose);
      t.dealerGame.place('cow', 'slot1');
      await pumpEventQueue();
      for (final m in t.allSent.where((m) => m['t'] == 'state')) {
        final keys = keysOf(m['p']);
        expect(keys.intersection({...liveForbidden, 'count', 'tally', 'rounds', 'round', 'placedCount'}), isEmpty);
      }
    });

    test('the registry takes it at the age the hub already uses', () {
      expect(puzzleSpec.minAge, 4);
      expect(PlayRegistry.validate(puzzleSpec, liveForbidden), isEmpty);
    });
  });

  group('Twenty questions', () {
    Future<TwoDevices<TwentyQuestionsPlayGame>> table() async {
      final t = TwoDevices<TwentyQuestionsPlayGame>(twentyQuestionsSpec, seed: 5);
      await t.start();
      t.dealerGame.begin();
      await pumpEventQueue();
      return t;
    }

    test('the dealer starts it and draws; the guest is given the prompt; the leader moves on, alternating', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      expect(g.started, isTrue);
      expect(g.prompt, d.prompt);
      expect(d.iAmLeader, isTrue);
      expect(g.iAmLeader, isFalse);

      d.next();
      await pumpEventQueue();
      expect(g.iAmLeader, isTrue);
      expect(g.prompt, d.prompt);

      g.next(); // the guest leads now and asks the dealer to draw
      await pumpEventQueue();
      expect(d.iAmLeader, isTrue);
      expect(d.prompt, g.prompt);
    });

    test('only the leader can move on: a guest that is not leading is refused, and nothing is sent', () async {
      final t = await table();
      addTearDown(t.dispose);
      final sent = t.guestT.sent.length;
      t.guestGame.next();
      await pumpEventQueue();
      expect(t.guestT.sent.length, sent);
      expect(t.dealerGame.onMove('a', {'t': 'next'}), PlayMoveOutcome.refused, reason: 'the dealer is leading');
      expect(t.dealerGame.onMove('b', {'t': 'next'}), PlayMoveOutcome.refused, reason: 'from itself');
      expect(t.dealerGame.onMove('a', {'t': 'jump'}), PlayMoveOutcome.refused);
    });

    test('a bad state or prompt is refused and changes nothing', () async {
      final t = await table();
      addTearDown(t.dispose);
      final g = t.guestGame;
      final before = g.prompt;
      for (final bad in <Map<String, dynamic>>[
        {}, {'prompt': 'x', 'leader': 'z'}, {'prompt': 5, 'leader': 'a'}, {'prompt': 'a\u0000b', 'leader': 'a'},
        {'prompt': 'y' * 300, 'leader': 'a'}, {'prompt': '', 'leader': 'a'},
      ]) {
        expect(g.applyState(bad), isFalse, reason: '$bad');
      }
      expect(g.prompt, before);
    });

    test('there is no round counter on the wire, and the spec is a clean one', () async {
      final t = await table();
      addTearDown(t.dispose);
      dealerNext(t);
      await pumpEventQueue();
      for (final m in t.allSent.where((m) => m['t'] == 'state')) {
        expect(keysOf(m['p']).intersection({'rounds', 'round', 'score', 'count'}), isEmpty);
      }
      expect(PlayRegistry.validate(twentyQuestionsSpec, liveForbidden), isEmpty);
      expect(twentyQuestionsSpec.minAge, 8);
    });

    test('away and back: the guest\'s ask to move on is kept and the dealer draws when it returns', () async {
      final t = await table();
      addTearDown(t.dispose);
      t.dealerGame.next();
      await pumpEventQueue();
      t.guestT.setLinked(false);
      final lead = t.guestGame.prompt;
      t.guestGame.next();
      await pumpEventQueue();
      expect(t.dealerGame.prompt, lead, reason: 'nothing reached the dealer while away');
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.dealerGame.iAmLeader, isTrue);
      expect(t.guestGame.prompt, t.dealerGame.prompt);
    });
  });
}

void dealerNext(TwoDevices<TwentyQuestionsPlayGame> t) => t.dealerGame.next();
