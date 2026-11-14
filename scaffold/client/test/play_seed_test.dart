// OLIVE BRANCH — seeded deals are for deterministic tests only, and a seed never leaves the dealing device. Verified by CI,
// headless. Rule: play_envelope.dart [neverSentKeys]; play_game.dart [PlayContext.rng]; play_session.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_envelope.dart';
import 'package:olive_client/play_game.dart';
import 'package:olive_client/play_games.dart';

import 'play_harness.dart';

class _Toy extends PlayGame {
  _Toy(super.ctx);
  Map<String, dynamic> next = <String, dynamic>{'x': 1};
  final List<Map<String, dynamic>> got = <Map<String, dynamic>>[];
  @override
  bool get started => true;
  @override
  bool get finished => false;
  @override
  Map<String, dynamic>? stateFor(String seatId) => ctx.isAuthority ? next : null;
  @override
  bool applyState(Map<String, dynamic> payload) {
    got.add(payload);
    return true;
  }

  @override
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) {
    got.add(payload);
    return PlayMoveOutcome.applied;
  }
}

final PlayGameSpec _toySpec = PlayGameSpec(
    id: 'toy_game', title: 'Toy', minAge: 5, minSeats: 2, maxSeats: 2, modes: const {PlayMode.pair}, create: (c) => _Toy(c));

void main() {
  group('a seeded deal is deterministic, so a test can rely on it', () {
    test('the same seed deals the same hand, a different one does not', () {
      List<int> deal(int seed) {
        final r = Random(seed);
        return [for (int i = 0; i < 12; i++) r.nextInt(1 << 20)];
      }

      expect(deal(7), deal(7));
      expect(deal(7), isNot(deal(8)));
    });

    test('every registered game deals the same way twice from the same seed, over the in-memory table', () async {
      for (final spec in playGameRegistry.all) {
        Future<String> run() async {
          final t = TwoDevices<PlayGame>(spec, seed: 99);
          await t.start();
          final d = t.dealerGame;
          // Each game's own dealer start (a no-op for those that start from the first state).
          final dynamic dyn = d;
          for (final start in <void Function()>[() => (dyn as dynamic).deal(), () => (dyn as dynamic).begin()]) {
            try {
              start();
              break;
            } catch (_) {}
          }
          await pumpEventQueue();
          final out = jsonEncode(d.stateFor('a') ?? d.snapshot() ?? d.publicDigestInput());
          t.dispose();
          return out;
        }

        expect(await run(), await run(), reason: spec.id);
      }
    });
  });

  group('a seed never leaves the dealing device', () {
    test('no message of any registered game, played from a seed, carries a seed-like key', () async {
      for (final spec in playGameRegistry.all) {
        final t = TwoDevices<PlayGame>(spec, seed: 12345);
        addTearDown(t.dispose);
        await t.start();
        final dynamic d = t.dealerGame;
        // ignore: avoid_dynamic_calls
        for (final start in <void Function()>[() => d.deal(), () => d.begin()]) {
          try {
            start();
            break;
          } catch (_) {}
        }
        await pumpEventQueue();
        for (final m in t.allSent) {
          final keys = keysOf(m).map((k) => k.toLowerCase()).toSet();
          for (final banned in neverSentKeys) {
            expect(keys.contains(banned.toLowerCase()), isFalse, reason: '${spec.id}: $banned in $m');
          }
          expect(jsonEncode(m).contains('12345'), isFalse, reason: '${spec.id}: the seed value itself must not appear: $m');
        }
      }
    });

    test('the session refuses to SEND a state or a move that carries a seed, in a game that is not even hidden-information', () async {
      final t = TwoDevices<_Toy>(_toySpec);
      addTearDown(t.dispose);
      await t.start();
      expect(_toySpec.hiddenInfo, isFalse);
      t.dealerGame.next = <String, dynamic>{'seed': 5};
      await t.dealer.broadcastState();
      expect(t.dealer.blockedSends, 1);
      t.dealerGame.next = <String, dynamic>{'deep': <String, dynamic>{'rngSeed': 5}};
      await t.dealer.broadcastState();
      expect(t.dealer.blockedSends, 2, reason: 'at any depth');
      await t.guest.sendMove(<String, dynamic>{'seedForTest': 1});
      expect(t.guest.blockedSends, 1);
      expect(t.allSent.where((m) => jsonEncode(m).contains('seed') || jsonEncode(m).contains('rngSeed')), isEmpty);
    });

    test('the session refuses a message that RECEIVES a seed, whichever device sent it', () async {
      final t = TwoDevices<_Toy>(_toySpec);
      addTearDown(t.dispose);
      await t.start();
      final sid = t.dealer.session.sid;
      for (final body in <Map<String, dynamic>>[
        {'seed': 1}, {'a': {'rng': 2}}, {'n': [{'rngSeed': 3}]}, {'seedForTest': 4},
      ]) {
        final before = t.guestGame.got.length;
        await t.dealerT.send(PlayEnvelope(sid: sid, n: 50, ack: 0, t: PlayKind.state, g: 'toy_game', p: body).toJson());
        await pumpEventQueue();
        expect(t.guestGame.got.length, before, reason: '$body');
        expect(t.guest.rejected.last, 'seed_key', reason: '$body');
      }
    });

    test('the dealer\'s randomness is secure and unseeded in every shipped path: a default context is not repeatable', () {
      List<int> take() {
        final c = PlayContext(mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b']);
        return [for (int i = 0; i < 8; i++) c.rng.nextInt(1 << 30)];
      }

      expect(take(), isNot(take()));
    });

    test('source guard: no shipped screen or game seeds its dealer (a seeded Random, or an rng passed in, is for tests)', () {
      final offenders = <String>[];
      // The two-device play files: the contract, the session, and every game and screen that runs on it.
      final playFiles = RegExp(r'[\\/](play_.*|.*_play|local_play_screen|game_(war|connect4|uno|pictionary|puzzle))\.dart$');
      final files = Directory('lib').listSync().whereType<File>().where((f) => playFiles.hasMatch(f.path)).toList();
      expect(files.length, greaterThan(15), reason: 'the guard must actually be looking at the play files');
      for (final f in files) {
        final src = f.readAsStringSync();
        if (RegExp(r'Random\(\s*[0-9a-zA-Z_]').hasMatch(src.replaceAll('Random()', ''))) offenders.add('${f.path}: Random(seed)');
        if (RegExp(r'PlayContext\([^)]*\brng:').hasMatch(src.replaceAll('\n', ' '))) offenders.add('${f.path}: PlayContext(rng:)');
        if (RegExp(r"'(seed|rngSeed)'\s*:").hasMatch(src) && !f.path.endsWith('play_envelope.dart')) offenders.add('${f.path}: seed key');
      }
      expect(offenders, isEmpty);
    });
  });
}
