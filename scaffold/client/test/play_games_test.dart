// OLIVE BRANCH — War, Connect 4 and Uno played start to finish by two devices over the in-memory transport, and the
// registry sweep over every game that runs on the shared contract. These are the vs-peer paths that game_uno_test.dart
// says "need a genuine mDNS pairing handshake between two real devices" (so could not be tested at all before).
//
// Device 'a' is the guest, device 'b' is the dealer (the authority).
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect4_engine.dart';
import 'package:olive_client/connect4_play.dart';
import 'package:olive_client/game_logic.dart' show localPlayMinAge;
import 'package:olive_client/game_war.dart';
import 'package:olive_client/live_games.dart' show Side, liveForbidden;
import 'package:olive_client/play_envelope.dart';
import 'package:olive_client/play_game.dart';
import 'package:olive_client/play_games.dart';
import 'package:olive_client/play_save.dart';
import 'package:olive_client/uno_deck.dart';
import 'package:olive_client/uno_play.dart';
import 'package:olive_client/uno_session.dart';

import 'play_harness.dart';

void main() {
  group('Connect 4, two devices', () {
    test('a whole game, alternating, ends the same on both screens', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      for (var i = 0; i < 3; i++) {
        t.dealerGame.tapColumn(0);
        await pumpEventQueue();
        t.guestGame.tapColumn(1);
        await pumpEventQueue();
      }
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      expect(t.dealerGame.outcome, Connect4Outcome.win);
      expect(t.guestGame.outcome, Connect4Outcome.win);
      expect(t.guestGame.winner, Side.b);
      expect(t.guestGame.board.columns.map((c) => c.length).toList(), t.dealerGame.board.columns.map((c) => c.length).toList());
      expect(t.guestGame.canPlay, isFalse);
    });

    test("a tap that is not this seat's turn does nothing and sends nothing", () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      final before = t.guestT.sent.length;
      t.guestGame.tapColumn(3); // the dealer opens
      await pumpEventQueue();
      expect(t.guestT.sent.length, before);
      expect(t.guestGame.awaiting, isFalse);
    });

    test('the state on the wire carries the board and the turn, never a score or a count of games', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(2);
      await pumpEventQueue();
      final bad = liveForbidden.map((s) => s.toLowerCase()).toSet();
      for (final m in t.allSent) {
        expect(keysOf(m).map((k) => k.toLowerCase()).toSet().intersection(bad), isEmpty);
        expect(m['v'], 1);
      }
    });

    test('a refused ask still gets the board back, so the asker is not stranded on waiting', () async {
      final t = TwoDevices<Connect4PlayGame>(connect4Spec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.tapColumn(0);
      await pumpEventQueue();
      // Fill column 5 so the guest's ask for it is illegal by the time it lands.
      for (var i = 0; i < 6; i++) {
        t.dealerGame.board = t.dealerGame.board.withMove(5, i.isEven ? Side.a : Side.b);
      }
      t.guestGame.tapColumn(5);
      await pumpEventQueue();
      expect(t.guestGame.awaiting, isFalse, reason: 'the refusal came back as a state');
    });
  });

  group('War, two devices', () {
    test('the dealer deals; each side holds 26 and flips; both end up with a consistent game', () async {
      final t = TwoDevices<WarPlayGame>(warSpec);
      addTearDown(t.dispose);
      await t.start();
      expect(t.guestGame.started, isFalse);
      t.dealerGame.deal();
      await pumpEventQueue();
      expect(t.dealerGame.war!.myPile.length, 26);
      expect(t.guestGame.war!.myPile.length, 26);
      final all = {...t.dealerGame.war!.myPile.map((c) => c.code), ...t.guestGame.war!.myPile.map((c) => c.code)};
      expect(all.length, 52, reason: 'two halves of one real deck');
      for (var i = 0; i < 20; i++) {
        t.dealerGame.flip();
        t.guestGame.flip();
        await pumpEventQueue();
      }
      final d = t.dealerGame.war!, g = t.guestGame.war!;
      expect(d.myPile.length + g.myPile.length + d.pot.length + (d.myPending?.length ?? 0) + (g.myPending?.length ?? 0), 52,
          reason: 'no card is ever lost or doubled');
    });

    test('a reveal made while the other device is away is kept and delivered when they find each other (the vanishing-turn bug)', () async {
      final t = TwoDevices<WarPlayGame>(warSpec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      t.guestT.setLinked(false);
      await pumpEventQueue();
      t.guestGame.flip();
      await pumpEventQueue();
      expect(t.dealerGame.war!.theirPending, isNull);
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(t.dealerGame.war!.theirPending, isNotNull, reason: 'the reveal arrived after they found each other');
    });

    test('a repeated deal does not replace a game that is under way', () async {
      final t = TwoDevices<WarPlayGame>(warSpec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      t.guestGame.flip();
      await pumpEventQueue();
      final pileAfterFlip = t.guestGame.war!.myPile.map((c) => c.code).toList();
      // A stray deal (a replay, or a hostile device) arrives with new cards, from the dealer's seat and from any other.
      final other = dealWar(Random(99)).forPeer;
      final deal = <String, dynamic>{'deal': [for (final c in other) c.code]};
      expect(t.guestGame.onMove('b', deal), PlayMoveOutcome.refused, reason: 'a game is under way');
      expect(t.guestGame.onMove('a', deal), PlayMoveOutcome.refused);
      expect(t.guestGame.war!.myPile.map((c) => c.code).toList(), pileAfterFlip);
    });

    test('a malformed deal or reveal is refused and changes nothing', () async {
      final t = TwoDevices<WarPlayGame>(warSpec);
      addTearDown(t.dispose);
      await t.start();
      expect(t.guestGame.onMove('b', <String, dynamic>{'deal': ['XX']}), PlayMoveOutcome.refused);
      expect(t.guestGame.onMove('b', <String, dynamic>{'deal': List.filled(25, '2C')}), PlayMoveOutcome.refused);
      expect(t.guestGame.onMove('a', <String, dynamic>{'deal': List.filled(26, '2C')}), PlayMoveOutcome.refused, reason: 'only the dealer deals');
      expect(t.guestGame.war, isNull);
      t.dealerGame.deal();
      await pumpEventQueue();
      expect(t.dealerGame.onMove('a', <String, dynamic>{'played': ['nope']}), PlayMoveOutcome.refused);
      expect(t.dealerGame.onMove('a', <String, dynamic>{'played': <String>[]}), PlayMoveOutcome.refused);
      expect(t.dealerGame.onMove('b', <String, dynamic>{'played': ['2C']}), PlayMoveOutcome.refused, reason: 'our own seat is not the other device');
    });

    test('rematch after a finished game deals afresh on both', () async {
      final t = TwoDevices<WarPlayGame>(warSpec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      // Fast-forward both engines to a finished state.
      t.dealerGame.war = WarState(myPile: t.dealerGame.war!.myPile, roundNumber: 5, pot: const [], myPending: null, theirPending: null, phase: WarPhase.drawnOut, lastRoundNote: null);
      t.guestGame.war = WarState(myPile: t.guestGame.war!.myPile, roundNumber: 5, pot: const [], myPending: null, theirPending: null, phase: WarPhase.drawnOut, lastRoundNote: null);
      await t.guest.askRematch();
      await pumpEventQueue();
      await t.dealer.acceptRematch();
      await pumpEventQueue();
      expect(t.dealerGame.finished, isFalse);
      expect(t.guestGame.finished, isFalse);
      expect(t.guestGame.war!.myPile.length, 26);
    });
  });

  group('Uno, two devices', () {
    test('the other device sees its own hand and only a COUNT of the dealer\'s; nothing hidden is ever on the wire', () async {
      final t = TwoDevices<UnoPlayGame>(unoSpec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      final dealer = t.dealerGame.session!;
      expect(t.guestGame.view!.myHand.map((c) => c.code).toList(), dealer.hands['a']!.map((c) => c.code).toList());
      expect(t.guestGame.view!.opponentHandCount, dealer.hands['b']!.length);
      final forbidden = {...unoSpec.allHiddenKeys};
      for (final m in t.allSent) {
        expect(keysOf(m).intersection(forbidden), isEmpty, reason: 'no hands map, draw pile or seed on the wire: $m');
      }
      // And the dealer's own hand is not in any state it sent (compare as a multiset against the guest-bound lists).
      final dealerHand = dealer.hands['b']!.map((c) => c.code).toList()..sort();
      for (final m in t.allSent.where((m) => m['t'] == 'state')) {
        final p = m['p'] as Map<String, dynamic>;
        for (final v in p.values) {
          if (v is List) {
            final l = v.map((e) => '$e').toList()..sort();
            expect(l.length == dealerHand.length && l.join() == dealerHand.join(), isFalse);
          }
        }
      }
      expect(t.dealer.blockedSends, 0);
    });

    test('the digest of the public view agrees on both devices after every move', () async {
      final t = TwoDevices<UnoPlayGame>(unoSpec, seed: 3);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      for (var i = 0; i < 12 && !t.dealerGame.finished; i++) {
        final s = t.dealerGame.session!;
        final seat = s.turnSeatId;
        if (s.pendingWildDrawFour != null) {
          if (seat == 'b') {
            t.dealerGame.acceptWd4AsAuthority();
          } else {
            t.guestGame.request(special: 'acceptWD4');
          }
        } else if (seat == 'b') {
          _dealerPlaysSomething(t.dealerGame);
        } else {
          _guestPlaysSomething(t.guestGame);
        }
        await pumpEventQueue();
        expect(stateDigest(t.guestGame.publicDigestInput()), stateDigest(t.dealerGame.publicDigestInput()), reason: 'move $i');
        expect(t.guest.rejected.where((r) => r != 'duplicate' && r != 'stale'), isEmpty, reason: '${t.guest.rejected}');
      }
    });

    test("an ask is always answered: a play that is refused still gets the table back (the stranded-on-Sending bug)", () async {
      final t = TwoDevices<UnoPlayGame>(unoSpec);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      // Make it the dealer's turn, then the guest asks to draw out of turn: refused, and answered.
      t.dealerGame.session = t.dealerGame.session!.copyWith(turnSeatId: 'b');
      t.guestGame.request(draw: true);
      await pumpEventQueue();
      expect(t.guestGame.awaiting, isFalse);
      expect(t.dealer.rejected, contains('move_refused'));
    });

    test('rapid state updates cannot be overtaken by a late one', () async {
      final t = TwoDevices<UnoPlayGame>(unoSpec, seed: 5);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      t.dealerT.hold = true;
      // Several quick changes in a row, as when one tap causes a draw and a declare.
      t.dealerGame.declareAsAuthority();
      t.dealerGame.declareAsAuthority();
      await t.dealer.broadcastState();
      final latest = t.dealerGame.session!.hands['a']!.length;
      t.dealerT.release(reversed: true); // they arrive back to front
      await pumpEventQueue();
      expect(t.guestGame.view!.myHand.length, latest);
      expect(t.guest.rejected, anyOf(contains('stale'), contains('duplicate')));
    });

    test('the dealer\'s game is saved after each change and rebuilt exactly after a kill', () async {
      final store = MemoryPlaySaveStore();
      final t = TwoDevices<UnoPlayGame>(unoSpec, storeForDealer: store, seed: 11);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      expect(await store.load('uno'), isNotNull);
      final before = jsonEncode(unoSessionToJson(t.dealerGame.session!));
      final restored = UnoPlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      expect(restored.restore((await store.load('uno'))!), isTrue);
      expect(jsonEncode(unoSessionToJson(restored.session!)), before);
      // Nothing about who is winning is in the save.
      final saved = jsonEncode(await store.load('uno')).toLowerCase();
      for (final w in ['winner', 'score', 'outcome', 'streak']) {
        expect(saved.contains(w), isFalse, reason: w);
      }
    });

    test('a damaged save is refused: wrong card count, a card that does not parse, an impossible turn', () {
      final good = unoSessionToJson(dealUno(const ['a', 'b'], Random(1)));
      final g = UnoPlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      expect(g.restore(good), isTrue);
      final g2 = UnoPlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      Map<String, dynamic> copy() => jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
      final shortDeck = copy()..['draw'] = (good['draw'] as List).sublist(1);
      expect(g2.restore(shortDeck), isFalse);
      final badCard = copy()..['discard'] = ['ZZZ', ...(good['discard'] as List).skip(1)];
      expect(g2.restore(badCard), isFalse);
      final badTurn = copy()..['turn'] = 'nobody';
      expect(g2.restore(badTurn), isFalse);
      final extraSeat = copy()..['seats'] = ['a', 'b', 'c', 'd', 'e'];
      expect(g2.restore(extraSeat), isFalse);
      final dupCard = copy();
      final hands = Map<String, dynamic>.from(dupCard['hands'] as Map);
      hands['a'] = [...(hands['a'] as List).skip(1), (hands['a'] as List).first, (hands['a'] as List).first];
      dupCard['hands'] = hands;
      expect(g2.restore(dupCard), isFalse);
      expect(g2.session, isNull, reason: 'nothing half-applied');
      expect(g2.restore(<String, dynamic>{}), isFalse);
    });

    test('a finished game is not saved and the save is cleared', () async {
      final store = MemoryPlaySaveStore();
      final t = TwoDevices<UnoPlayGame>(unoSpec, storeForDealer: store, seed: 2);
      addTearDown(t.dispose);
      await t.start();
      t.dealerGame.deal();
      await pumpEventQueue();
      expect(await store.load('uno'), isNotNull);
      t.dealerGame.session = t.dealerGame.session!.copyWith(winner: 'b');
      expect(t.dealerGame.snapshot(), isNull);
      await t.dealer.broadcastState();
      expect(await store.load('uno'), isNull);
    });
  });

  group('the registry: every game on the contract', () {
    test('War, Connect 4 and Uno are registered with the ages the hub already uses', () {
      final specs = playGameRegistry.all;
      expect(specs.map((s) => s.id).toSet(), {'war', 'connect4', 'uno'});
      for (final s in specs) {
        expect(s.minAge, localPlayMinAge[s.id], reason: s.id);
      }
    });

    test('no spec uses a forbidden child-facing word, and every hiddenInfo spec names its hidden keys', () {
      for (final s in playGameRegistry.all) {
        expect(PlayRegistry.validate(s, liveForbidden), isEmpty, reason: s.id);
        if (s.hiddenInfo) expect(s.allHiddenKeys, containsAll(alwaysHiddenKeys), reason: s.id);
      }
    });

    test('a bad spec is refused at registration', () {
      final r = PlayRegistry();
      PlayGameSpec spec({String id = 'toy', bool hidden = false, List<String> keys = const [], int min = 2, int max = 2}) => PlayGameSpec(
          id: id, title: 'Toy', minAge: 5, minSeats: min, maxSeats: max, modes: const {PlayMode.pair},
          create: (c) => Connect4PlayGame(c), hiddenInfo: hidden, hiddenKeys: keys);
      expect(() => r.register(spec(id: 'Bad Id'), forbidden: liveForbidden), throwsArgumentError);
      expect(() => r.register(spec(hidden: true), forbidden: liveForbidden), throwsArgumentError, reason: 'hidden info with no hidden keys');
      expect(() => r.register(spec(keys: ['hands']), forbidden: liveForbidden), throwsArgumentError, reason: 'keys without hidden info');
      expect(() => r.register(spec(id: 'score'), forbidden: liveForbidden), throwsArgumentError, reason: 'a forbidden word as the id');
      expect(() => r.register(spec(min: 3, max: 2), forbidden: liveForbidden), throwsArgumentError);
      r.register(spec(), forbidden: liveForbidden);
      expect(() => r.register(spec(), forbidden: liveForbidden), throwsArgumentError, reason: 'twice');
    });

    for (final s in playGameRegistry.all.where((s) => s.modes.contains(PlayMode.pair))) {
      test('${s.id}: starts, syncs, and nothing hidden crosses the transport (sweep)', () async {
        final t = TwoDevices<PlayGame>(s, seed: 21);
        addTearDown(t.dispose);
        await t.start();
        if (t.dealerGame is UnoPlayGame) (t.dealerGame as UnoPlayGame).deal();
        if (t.dealerGame is WarPlayGame) (t.dealerGame as WarPlayGame).deal();
        if (t.dealerGame is Connect4PlayGame) (t.dealerGame as Connect4PlayGame).tapColumn(3);
        await pumpEventQueue();
        expect(t.guestGame.started, isTrue);
        expect(t.dealer.blockedSends, 0);
        for (final m in t.allSent) {
          expect(keysOf(m).intersection(s.allHiddenKeys.toSet()), isEmpty, reason: '${s.id}: $m');
          expect(utf8.encode(jsonEncode(m)).length, lessThanOrEqualTo(maxEnvelopeBytes));
        }
      });

      test('${s.id}: the other device vanishing mid-match leaves a calm notice, not an error', () async {
        final t = TwoDevices<PlayGame>(s, seed: 22);
        addTearDown(t.dispose);
        await t.start();
        t.guestT.setLinked(false);
        await pumpEventQueue();
        expect(t.guest.notice.name, 'away');
        expect(t.dealer.notice.name, 'away');
        expect(t.guest.endedForGood, isFalse);
      });
    }
  });
}

void _dealerPlaysSomething(UnoPlayGame g) {
  final s = g.session!;
  for (final c in s.hands['b']!) {
    final color = (c.type == UnoCardType.wild || c.type == UnoCardType.wildDrawFour) ? UnoColor.red : null;
    if (g.playAsAuthority(c, color)) return;
  }
  g.drawAsAuthority();
}

void _guestPlaysSomething(UnoPlayGame g) {
  final v = g.view!;
  for (final c in v.myHand) {
    final isWild = c.type == UnoCardType.wild || c.type == UnoCardType.wildDrawFour;
    final matches = isWild || c.color == v.currentColor || c.code.substring(1) == v.discardTop.code.substring(1);
    if (matches) {
      g.request(card: c, color: isWild ? UnoColor.red : null);
      return;
    }
  }
  g.request(draw: true);
}
