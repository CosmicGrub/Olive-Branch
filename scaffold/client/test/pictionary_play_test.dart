// OLIVE BRANCH — Draw and guess on the shared play contract: the whole conversation between two devices over the in-memory
// transport, the compact picture wire, and the rule that the drawer's word never crosses. Verified by CI, headless.
// (Replaces game_pictionary_wire_test.dart, which tested the old one-map-per-point wire.)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/annotation_canvas.dart';
import 'package:olive_client/live_games.dart' show auditLiveView, liveForbidden;
import 'package:olive_client/pictionary_play.dart';
import 'package:olive_client/play_envelope.dart';
import 'package:olive_client/play_game.dart';

import 'play_harness.dart';

void draw(PictionaryPlayGame g, {int points = 12, String id = 's1'}) {
  g.canvas!.add(
    id: id, actorId: 'dad', actorKind: ActorKind.guardian,
    points: <StrokePoint>[for (int i = 0; i < points; i++) StrokePoint(10.0 + i * 3, 20.0 + (i % 5) * 7)],
    color: '#B8863B', widthPx: 6.0);
}

Future<TwoDevices<PictionaryPlayGame>> table() async {
  final t = TwoDevices<PictionaryPlayGame>(pictionarySpec, seed: 4);
  await t.start();
  t.dealerGame.begin();
  t.guestGame.begin();
  await pumpEventQueue();
  return t;
}

void main() {
  group('the picture wire', () {
    test('a stroke survives encode then decode, whole numbers only', () {
      final s = Stroke(
        id: 'a-1', actorId: 'ivy', actorKind: ActorKind.child, seq: 1,
        points: const [StrokePoint(1.4, 2.6), StrokePoint(30, 40)], color: '#3A7CA5', widthPx: 6.0);
      final c = encodeStrokeCompact(s);
      expect(c['p'], [1, 3, 30, 40]);
      final back = decodeStrokeCompact(c, 0)!;
      expect([for (final p in back.points) (p.x, p.y)], [(1.0, 3.0), (30.0, 40.0)]);
      expect(back.color, '#3A7CA5');
    });

    test('a real picture passes the shared audit (the old wire once named a field "points" and every drawing was refused)', () {
      final s = Stroke(
        id: 'a-1', actorId: 'ivy', actorKind: ActorKind.child, seq: 1,
        points: const [StrokePoint(1, 2), StrokePoint(3, 4)], color: '#3A7CA5', widthPx: 6.0);
      final audit = auditLiveView(<String, dynamic>{'t': 'draw', 'r': 0, 's': encodeDrawing([s])});
      expect(audit.ok, isTrue, reason: '${audit.leaks}');
    });

    test('a malformed or hostile stroke is refused whole, never half-applied', () {
      Map<String, dynamic> ok() => {'c': '#112233', 'w': 6, 'p': [1, 2, 3, 4]};
      expect(decodeStrokeCompact(ok(), 0), isNotNull);
      for (final bad in <Object?>[
        null, 'x', <String, dynamic>{}, {...ok(), 'c': 'red'}, {...ok(), 'c': '#12345'}, {...ok(), 'w': 0}, {...ok(), 'w': 99},
        {...ok(), 'w': 2.5}, {...ok(), 'p': [1, 2, 3]}, {...ok(), 'p': [1, 'a']}, {...ok(), 'p': [1.5, 2]}, {...ok(), 'p': [9999, 1]},
        {...ok(), 'p': List<int>.filled(maxStrokePoints * 2 + 2, 5)}, {...ok(), 'p': 'nope'},
      ]) {
        expect(decodeStrokeCompact(bad, 0), isNull, reason: '$bad');
      }
      expect(decodeDrawing(List<Object?>.filled(maxPictureStrokes + 1, ok())), isNull);
      expect(decodeDrawing([ok(), 'bad']), isNull);
    });

    test('a huge scribble is thinned until it fits, and the line keeps its ends', () {
      final big = Stroke(
        id: 'b', actorId: 'dad', actorKind: ActorKind.guardian, seq: 1,
        points: [for (int i = 0; i < 20000; i++) StrokePoint((i % 300).toDouble(), ((i * 7) % 300).toDouble())],
        color: '#B8863B', widthPx: 6.0);
      final out = encodeDrawing([big, big, big], maxBytes: 20 * 1024);
      expect(utf8.encode(jsonEncode(out)).length, lessThanOrEqualTo(20 * 1024));
      expect(decodeDrawing(out), isNotNull);
      final first = decodeStrokeCompact(out.first, 0)!;
      expect(first.points.first.x, 0);
    });

    test('a guess is made safe: control and bidi characters become spaces, trimmed, limited', () {
      expect(cleanGuess('  a \u202e bike\n'), 'a bike');
      expect(cleanGuess('x' * 500).length, maxGuessChars);
      expect(cleanGuess('\u0000\u0007'), '');
    });

    test('the spec asks for a bigger message than a move, within one frame', () {
      expect(pictionarySpec.maxMessageBytes, greaterThan(maxEnvelopeBytes));
      expect(pictionarySpec.maxMessageBytes, lessThanOrEqualTo(maxEnvelopeBytesCeiling));
      expect(PlayRegistry.validate(pictionarySpec, liveForbidden), isEmpty);
    });
  });

  group('two devices', () {
    test('the dealer draws first; the picture appears on the guest; a wrong guess changes nothing; a right one swaps the roles', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      expect(d.iAmDrawer, isTrue);
      expect(g.iAmDrawer, isFalse);
      expect(d.word, isNotNull);
      expect(g.word, isNull, reason: 'the guesser never has the word');

      draw(d);
      d.showThem();
      await pumpEventQueue();
      expect(g.pictureShown, isTrue);
      expect(g.shownStrokes, hasLength(1));

      g.guess('definitely not it');
      await pumpEventQueue();
      expect(g.lastGuessWasWrong, isTrue);
      expect(g.awaitingVerdict, isFalse);
      expect(d.lastGuessWasWrong, isTrue);
      expect(g.iAmDrawer, isFalse);

      final word = d.word!;
      g.guess(word);
      await pumpEventQueue();
      expect(d.iAmDrawer, isFalse);
      expect(g.iAmDrawer, isTrue);
      expect(g.word, isNotNull, reason: 'now the guest draws, so it has its own word');
      expect(d.word, isNull);
      expect(g.pictureShown, isFalse);
      expect(d.pictureShown, isFalse);
    });

    test('the guest draws a round and the dealer guesses it (the word is judged on the guest, never sent)', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      draw(d);
      d.showThem();
      await pumpEventQueue();
      g.guess(d.word!);
      await pumpEventQueue();
      expect(g.iAmDrawer, isTrue);

      draw(g, id: 'g1');
      g.showThem();
      await pumpEventQueue();
      expect(d.pictureShown, isTrue, reason: 'the dealer accepted the guest\'s picture');
      expect(d.shownStrokes, hasLength(1));
      expect(g.pictureSent, isTrue);

      d.guess('nope');
      await pumpEventQueue();
      expect(d.lastGuessWasWrong, isTrue);
      expect(g.lastGuessWasWrong, isTrue);
      expect(d.awaitingVerdict, isFalse);

      d.guess(g.word!);
      await pumpEventQueue();
      expect(d.iAmDrawer, isTrue, reason: 'the roles swapped back');
      expect(g.iAmDrawer, isFalse);
      expect(g.pictureShown, isFalse);
    });

    test('the word never appears on the wire, in any message, in either direction, over a whole two-round game', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      final words = <String>{d.word!};
      draw(d);
      d.showThem();
      await pumpEventQueue();
      g.guess('wrong');
      await pumpEventQueue();
      g.guess(d.word!);
      await pumpEventQueue();
      words.add(g.word!);
      draw(g, id: 'g1');
      g.showThem();
      await pumpEventQueue();
      d.guess(g.word!);
      await pumpEventQueue();
      final wire = t.allSent;
      expect(wire, isNotEmpty);
      for (final m in wire) {
        expect(keysOf(m).contains('word'), isFalse, reason: 'no "word" key anywhere: $m');
        // The only place the right answer appears is a guess typed by the guesser, which is the guesser's own text.
        if (m['t'] == 'state') {
          for (final w in words) {
            expect(jsonEncode(m['p']).toLowerCase().contains(w.toLowerCase()), isFalse, reason: 'state carried "$w"');
          }
        }
      }
      expect(t.dealer.blockedSends + t.guest.blockedSends, 0);
    });

    test('the wire has no round count, no score and nothing to tally', () async {
      final t = await table();
      addTearDown(t.dispose);
      draw(t.dealerGame);
      t.dealerGame.showThem();
      await pumpEventQueue();
      for (final m in t.allSent.where((m) => m['t'] == 'state')) {
        final keys = keysOf(m['p']);
        for (final banned in <String>['rounds', 'round', 'score', 'points', 'streak', 'count', 'tally', 'best']) {
          expect(keys.contains(banned), isFalse, reason: banned);
        }
      }
    });

    test('a picture with nothing drawn is not sent; the guest cannot show a picture when it is not drawing', () async {
      final t = await table();
      addTearDown(t.dispose);
      final before = t.dealerT.sent.length;
      t.dealerGame.showThem();
      await pumpEventQueue();
      expect(t.dealerT.sent.length, before);
      expect(t.guestGame.pictureShown, isFalse);
      final guestBefore = t.guestT.sent.length;
      t.guestGame.showThem(); // not the drawer, no canvas
      await pumpEventQueue();
      expect(t.guestT.sent.length, guestBefore);
    });

    test('hostile moves are refused: draw from the wrong seat, a stale round, junk strokes, guess before the picture', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame;
      Map<String, dynamic> stroke() => {'c': '#112233', 'w': 6, 'p': [1, 2, 3, 4]};
      // The guest is NOT the drawer in round 0.
      expect(d.onMove('a', {'t': 'draw', 'r': 0, 's': [stroke()]}), PlayMoveOutcome.refused);
      expect(d.pictureShown, isFalse);
      // Own seat is never a peer.
      expect(d.onMove('b', {'t': 'draw', 'r': 0, 's': [stroke()]}), PlayMoveOutcome.refused);
      // A message for another round is old, not an error.
      expect(d.onMove('a', {'t': 'guess', 'r': 7, 'x': 'cow'}), PlayMoveOutcome.ignored);
      // No picture shown yet: a guess is refused.
      expect(d.onMove('a', {'t': 'guess', 'r': 0, 'x': 'cow'}), PlayMoveOutcome.refused);
      // A verdict is the drawer's, and the dealer is the drawer here, so a guest's verdict is refused.
      expect(d.onMove('a', {'t': 'verdict', 'r': 0, 'ok': true, 'x': 'cow'}), PlayMoveOutcome.refused);
      // Junk.
      expect(d.onMove('a', {'t': 'nonsense', 'r': 0}), PlayMoveOutcome.refused);
      expect(d.onMove('a', {'t': 1, 'r': 0}), PlayMoveOutcome.refused);
      expect(d.onMove('x', {'t': 'draw', 'r': 0, 's': [stroke()]}), PlayMoveOutcome.refused);
    });

    test('a guest that restarted and lost its word asks for the round to start over, quietly', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      draw(d);
      d.showThem();
      await pumpEventQueue();
      g.guess(d.word!);
      await pumpEventQueue();
      expect(g.iAmDrawer, isTrue);
      draw(g, id: 'g1');
      g.showThem();
      await pumpEventQueue();
      expect(d.pictureShown, isTrue);
      // The guest app restarts: a fresh game object that is given the dealer's state.
      final (ta, tb) = (t.guestT, t.dealerT);
      expect(ta, isNotNull);
      expect(tb, isNotNull);
      final fresh = PictionaryPlayGame(PlayContext(mode: PlayMode.pair, localSeatId: 'a', authoritySeatId: 'b', seatIds: const ['a', 'b']));
      final sent = <Map<String, dynamic>>[];
      fresh.link = _CaptureLink(sent);
      expect(fresh.applyState(d.stateFor('a')!), isTrue);
      expect(fresh.iAmDrawer, isTrue);
      expect(sent.single['t'], 'redo');
      // The dealer honours it: the picture is withdrawn so the round can be drawn again.
      expect(fresh.word, isNull, reason: 'it must not make up a new word for a picture that was drawn for another');
      expect(d.onMove('a', sent.single), PlayMoveOutcome.applied);
      expect(d.pictureShown, isFalse);
      // The dealer's new state reaches the fresh guest: it gets a word and a canvas for the round started over.
      expect(fresh.applyState(d.stateFor('a')!), isTrue);
      expect(fresh.word, isNotNull);
      expect(fresh.canvas, isNotNull);
    });

    test('a bad state is refused and changes nothing', () async {
      final t = await table();
      addTearDown(t.dispose);
      final g = t.guestGame;
      final before = jsonEncode(g.publicDigestInput());
      for (final bad in <Map<String, dynamic>>[
        {}, {'r': -1, 'd': 'a', 'sh': false, 's': <String>[], 'g': null, 'gw': false},
        {'r': 0, 'd': 'z', 'sh': false, 's': <String>[], 'g': null, 'gw': false},
        {'r': 0, 'd': 'a', 'sh': true, 's': <String>[], 'g': null, 'gw': false},
        {'r': 0, 'd': 'a', 'sh': true, 's': <String>['junk'], 'g': null, 'gw': false},
        {'r': 0, 'd': 'a', 'sh': false, 's': <String>[], 'g': 5, 'gw': false},
      ]) {
        expect(g.applyState(bad), isFalse, reason: '$bad');
      }
      expect(jsonEncode(g.publicDigestInput()), before);
    });

    test('an away and back mid-picture: the move is kept and the picture still arrives', () async {
      final t = await table();
      addTearDown(t.dispose);
      final d = t.dealerGame, g = t.guestGame;
      draw(d);
      d.showThem();
      await pumpEventQueue();
      g.guess(d.word!);
      await pumpEventQueue();
      draw(g, id: 'g1');
      t.guestT.setLinked(false);
      g.showThem();
      await pumpEventQueue();
      expect(d.pictureShown, isFalse);
      t.guestT.setLinked(true);
      await pumpEventQueue();
      expect(d.pictureShown, isTrue);
    });
  });

  test('the registry takes it, at the age the hub already uses', () {
    expect(pictionarySpec.minAge, 5);
    expect(pictionarySpec.hiddenKeys, contains('word'));
  });
}

class _CaptureLink implements PlayLink {
  _CaptureLink(this.sent);
  final List<Map<String, dynamic>> sent;
  @override
  Future<void> broadcastState() async {}
  @override
  Future<void> sendMove(Map<String, dynamic> payload) async => sent.add(payload);
}
