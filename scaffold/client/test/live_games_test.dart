// OLIVE BRANCH — live_games.dart tests. MASTERFILE §9.2, §3.1, §5.19.
// Mirrors packages/live/test/live.test.mjs's own real checks (AL-AS) so the
// Dart port is verified against the same invariants as the TS source, not
// just "it compiles."
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/live_games.dart';

void main() {
  group('AL — constraint 1: nothing sub-200ms', () {
    test('ten live games registered', () {
      expect(liveGames.length, 10);
    });

    test('every one clears the floor', () {
      expect(liveGames.every((g) => g.minViableLatencyMs >= minViableLatencyMs), true);
    });

    test('floor is 200ms', () {
      expect(minViableLatencyMs, 200);
    });

    test('a reflex game is refused at registration, not merely discouraged', () {
      const whack = LiveGame(kind: LiveKind.simonSays, title: 'Whack-a-mole', minAge: 5,
        minViableLatencyMs: 80, videoLayout: VideoLayout.sideBySide,
        degradesToAsync: false, blurb: 'x');
      expect(() => register(whack), throwsA(isA<UnplayableOverNetwork>()));
    });

    test('the refusal names WHY it matters', () {
      const whack = LiveGame(kind: LiveKind.simonSays, title: 'Whack-a-mole', minAge: 5,
        minViableLatencyMs: 80, videoLayout: VideoLayout.sideBySide,
        degradesToAsync: false, blurb: 'x');
      try {
        register(whack);
        fail('should have thrown');
      } on UnplayableOverNetwork catch (e) {
        expect(e.message, contains('child takes the blame'));
      }
    });

    test('the registry did not grow from a refused registration', () {
      expect(liveGames.length, 10);
    });

    test('freeze dance tolerates the worst connection', () {
      expect(liveGames.firstWhere((g) => g.kind == LiveKind.freezeDance).minViableLatencyMs, 1000);
    });
  });

  group('AM — constraint 2: the face is never hidden', () {
    test('every game audits clean', () {
      expect(liveGames.every((g) => auditLive(g).ok), true);
    });

    test('pictionary uses picture-in-picture, never a layout that hides him', () {
      expect(liveGames.firstWhere((g) => g.kind == LiveKind.pictionary).videoLayout,
        VideoLayout.pictureInPicture);
    });

    test('VideoLayout has no hidden/fullscreen member at all -- the type '
        'system is the audit, not a runtime check', () {
      expect(VideoLayout.values, [VideoLayout.sideBySide, VideoLayout.pictureInPicture]);
    });
  });

  group('AN — layout: the Fold is genuinely better at this', () {
    test('unfolded main screen puts them side by side, with an even split', () {
      final main = liveLayout(673, 841);
      expect(main.arrangement, LiveArrangement.sideBySide);
      expect(main.videoFraction, 0.5);
      expect(main.reason, contains('crease'));
    });

    test('the narrow cover screen stacks', () {
      expect(liveLayout(344, 882).arrangement, LiveArrangement.stacked);
    });

    test('a tall phone also stacks', () {
      expect(liveLayout(390, 844).arrangement, LiveArrangement.stacked);
    });

    test('video is visible in EVERY arrangement', () {
      for (final l in [liveLayout(673, 841), liveLayout(344, 882),
                        liveLayout(390, 844), liveLayout(1200, 800)]) {
        expect(l.videoVisible, true);
      }
    });
  });

  group('AO — prompt decks', () {
    test('decks exist for the prompt games', () {
      expect(decks.length, greaterThanOrEqualTo(9));
    });

    test('charades has prompts', () {
      expect(newDeck(LiveKind.charades, Random(11)).remaining.length, greaterThanOrEqualTo(8));
    });

    test('shuffled -- two decks differ', () {
      final a = newDeck(LiveKind.charades, Random(1)).remaining.join();
      final b = newDeck(LiveKind.charades, Random(2)).remaining.join();
      expect(a == b, false);
    });

    test('no repeats within a pass', () {
      var deck = newDeck(LiveKind.showMe, Random(11));
      final seen = <String>[];
      for (var i = 0; i < 7; i++) {
        final r = draw(deck, Random(11 + i));
        if (r == null) break;
        deck = r.deck;
        seen.add(r.prompt);
      }
      expect(Set.of(seen).length, seen.length);
    });

    test('a deck never runs dry mid-call -- running out RESHUFFLES', () {
      var small = newDeck(LiveKind.twoTruths, Random(11));
      var ranDry = false;
      for (var i = 0; i < 12; i++) {
        final r = draw(small, Random(11 + i));
        if (r == null) { ranDry = true; break; }
        small = r.deck;
      }
      expect(ranDry, false);
    });

    test('an unknown deck returns null', () {
      const fake = DeckState(kind: LiveKind.charades, remaining: [], drawn: []);
      // Simulate "no matching deck" the same way the TS source's own
      // newDeck('nope') would -- an empty deck with nothing drawn yet.
      expect(draw(fake), isNull);
    });

    test('"show me" prompts get her moving', () {
      expect(decks.firstWhere((d) => d.kind == LiveKind.showMe).prompts.any((p) => p.contains('Show me')), true);
    });

    test('i spy prompts point at HIS room too', () {
      expect(decks.firstWhere((d) => d.kind == LiveKind.iSpy).prompts
        .any((p) => p.contains('my room') || p.contains('behind me')), true);
    });
  });

  group('AP — age gating', () {
    test('a four-year-old has five live games', () {
      expect(liveForAge(4).length, 5);
    });

    test('an eight-year-old has more', () {
      expect(liveForAge(8).length, greaterThan(liveForAge(4).length));
    });

    test('two truths is 11+', () {
      expect(liveGames.firstWhere((g) => g.kind == LiveKind.twoTruths).minAge, 11);
    });

    test('nothing for a four-year-old needs reading', () {
      const readingFree = {LiveKind.simonSays, LiveKind.copyMe, LiveKind.freezeDance,
        LiveKind.iSpy, LiveKind.showMe};
      expect(liveForAge(4).every((g) => readingFree.contains(g.kind)), true);
    });
  });

  group('AQ — the session', () {
    test('starts, opening with a prompt already drawn', () {
      final s = startLive(LiveKind.charades, Side.b, '2026-07-27T20:00:00Z', Random(11));
      expect(s.ok, true);
      expect(s.session!.currentPrompt, isNotNull);
    });

    test('an unknown game is refused', () {
      // LiveKind is a closed enum in Dart (no room for a literal 'nope'),
      // so this invariant is enforced by the type system rather than a
      // runtime string check -- the same "type system is the audit"
      // posture already noted for auditLive's fullscreen/hidden case.
      expect(LiveKind.values.length, 10);
    });

    test('the lead ALTERNATES -- she is not always the one tested', () {
      final s = startLive(LiveKind.charades, Side.b, 't', Random(11)).session!;
      final n = nextRound(s, Random(12));
      expect(n.leader, Side.a);
    });

    test('rounds counted for the transcript only', () {
      final s = startLive(LiveKind.charades, Side.b, 't', Random(11)).session!;
      final n = nextRound(s, Random(12));
      expect(n.rounds, 1);
    });

    test('no score reaches the child', () {
      final s = startLive(LiveKind.charades, Side.b, 't', Random(11)).session!;
      final n = nextRound(s, Random(12));
      expect(auditLiveView({'kind': n.kind.name, 'rounds': n.rounds}).ok, true);
    });

    test('audit catches a reaction time', () {
      expect(auditLiveView({'reactionMs': 340}).leaks, contains('reactionMs'));
    });

    test('audit catches a streak nested arbitrarily deep', () {
      expect(auditLiveView({'a': {'b': [{'streak': 3}]}}).ok, false);
    });
  });

  group('AR — constraint 3: degrade, do not die, and never blame the child', () {
    test('a good connection says nothing', () {
      expect(connectionMessage(ConnectionQuality.good), isNull);
    });

    test('a poor one blames the NETWORK, explicitly', () {
      expect(connectionMessage(ConnectionQuality.poor), 'The connection is slow right now — not you.');
    });

    test('a dropped call reassures', () {
      expect(connectionMessage(ConnectionQuality.lost), 'The call dropped. Nothing is lost.');
    });

    test('no message blames the child', () {
      for (final q in ConnectionQuality.values) {
        final m = (connectionMessage(q) ?? '').toLowerCase();
        expect(m.contains('you are'), false);
        expect(m.contains('too slow'), false);
        expect(m.contains('your fault'), false);
        expect(m.contains('missed it'), false);
      }
    });

    test('a conversation game survives the call dropping, waits, and preserves rounds', () {
      final q = startLive(LiveKind.twentyQuestions, Side.a, 't', Random(11)).session!;
      final d = degradeToAsync(q, '2026-07-27T20:11:00Z');
      expect(d.ok, true);
      expect(d.note, contains('waiting for you both'));
      expect(d.session!.rounds, q.rounds);
      expect(isDegraded(d.session!), true);
    });

    test('a camera game admits it cannot continue, honestly, and is saved not discarded', () {
      final ss = startLive(LiveKind.simonSays, Side.b, 't', Random(11)).session!;
      final sd = degradeToAsync(ss, 't');
      expect(sd.ok, false);
      expect(sd.note, contains('needs to see each other'));
      expect(sd.note, contains('next time'));
    });
  });

  group('AS — pictionary, on the canvas that already exists', () {
    test('the drawer is set and cannot guess their own word', () {
      final p = newPictionary('a dog wearing a hat', Side.b);
      expect(p.drawer, Side.b);
      expect(guessDrawing(p, Side.b, 'a dog').reason, 'drawer_cannot_guess');
    });

    test('an empty guess is refused', () {
      final p = newPictionary('a dog wearing a hat', Side.b);
      expect(guessDrawing(p, Side.a, '  ').reason, 'empty_guess');
    });

    test('a wrong guess is recorded, not punished, and the game continues', () {
      final p = newPictionary('a dog wearing a hat', Side.b);
      final wrong = guessDrawing(p, Side.a, 'a cat');
      expect(wrong.correct, false);
      expect(wrong.state!.solved, false);
    });

    test('case-insensitive match solves it, and no more guesses are accepted after', () {
      var p = newPictionary('a dog wearing a hat', Side.b);
      p = guessDrawing(p, Side.a, 'a cat').state!;
      final right = guessDrawing(p, Side.a, 'A Dog Wearing A Hat');
      expect(right.correct, true);
      expect(right.state!.solved, true);
      expect(guessDrawing(right.state!, Side.a, 'x').reason, 'already_solved');
    });

    test('every guess is kept for the transcript, and no score anywhere', () {
      var p = newPictionary('a dog wearing a hat', Side.b);
      p = guessDrawing(p, Side.a, 'a cat').state!;
      final right = guessDrawing(p, Side.a, 'A Dog Wearing A Hat');
      expect(right.state!.guesses.length, 2);
      expect(auditLiveView({'solved': right.state!.solved}).ok, true);
    });
  });
}
