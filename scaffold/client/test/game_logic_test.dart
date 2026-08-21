// OLIVE BRANCH — pure logic tests for the ported handicap/catalogue rules in
// game_logic.dart. Mirrors the same behaviors packages/games/src/games.ts
// asserts, against the Dart port actually used by game_picker.dart and
// handicap_screen.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_logic.dart';

void main() {
  group('CATALOGUE — §9.2', () {
    test('twelve games — the ported four, batch A\'s two canvas activities, '
        'batch B\'s four curated-prompt activities, and batch C\'s two '
        'younger-age visual activities (Play Together Phase 1, complete)', () {
      expect(catalogue.length, 12);
      for (final g in catalogue) {
        expect(g.title, isNotEmpty);
        expect(g.blurb, isNotEmpty);
      }
    });

    test('draw together and guess the doodle are real, co-op catalogue entries', () {
      final drawTogether = catalogueFor(GameKind.drawTogether);
      expect(drawTogether.competitive, isFalse);
      expect(drawTogether.handicaps, isEmpty);
      expect(drawTogether.minAge, 4);

      final guessDoodle = catalogueFor(GameKind.guessDoodle);
      expect(guessDoodle.competitive, isFalse);
      expect(guessDoodle.handicaps, isEmpty);
      expect(guessDoodle.minAge, 5);
    });

    test('batch B\'s four curated-prompt activities are real, co-op catalogue entries', () {
      final expectations = <GameKind, int>{
        GameKind.sillySentence: 4,
        GameKind.wouldYouRather: 4,
        GameKind.twoTruths: 6,
        GameKind.twentyQuestions: 5,
      };
      for (final entry in expectations.entries) {
        final meta = catalogueFor(entry.key);
        expect(meta.competitive, isFalse, reason: '${entry.key} must be co-op — nothing to be behind at');
        expect(meta.handicaps, isEmpty, reason: '${entry.key} must carry no handicap');
        expect(meta.minAge, entry.value, reason: '${entry.key} minAge mismatch');
      }
    });

    test('batch C\'s two younger-age visual activities are real, co-op, minAge-2 catalogue '
        'entries — self-scaling difficulty means nothing for a handicap to apply to', () {
      final expectations = <GameKind, int>{
        GameKind.copyPattern: 2,
        GameKind.findIt: 2,
      };
      for (final entry in expectations.entries) {
        final meta = catalogueFor(entry.key);
        expect(meta.competitive, isFalse, reason: '${entry.key} must be co-op — nothing to be behind at');
        expect(meta.handicaps, isEmpty, reason: '${entry.key} must carry no handicap');
        expect(meta.minAge, entry.value, reason: '${entry.key} minAge mismatch');
      }
    });

    test('the co-op game (story) carries no handicaps — nothing to be behind at', () {
      final story = catalogueFor(GameKind.story);
      expect(story.competitive, isFalse);
      expect(story.handicaps, isEmpty);
    });

    test('competitive games each carry at least one handicap the child may impose', () {
      for (final g in catalogue.where((g) => g.competitive)) {
        expect(g.handicaps, isNotEmpty, reason: '${g.title} is competitive but offers no handicap');
      }
    });

    test('forAge filters by minAge without reordering or duplicating', () {
      final atFour = forAge(4).map((g) => g.kind).toSet();
      expect(atFour, {
        GameKind.tictactoe, GameKind.memory, GameKind.drawTogether,
        GameKind.sillySentence, GameKind.wouldYouRather,
        GameKind.copyPattern, GameKind.findIt,
      });
      final atSix = forAge(6).map((g) => g.kind).toSet();
      expect(atSix, GameKind.values.toSet());
    });

    test('at age 2, only batch C\'s two younger-age visual activities are old enough to show — '
        'the youngest gate this catalogue has ever had', () {
      final atTwo = forAge(2).map((g) => g.kind).toSet();
      expect(atTwo, {GameKind.copyPattern, GameKind.findIt});
    });
  });

  group('setHandicap — §9.2 child-only', () {
    test('refuses a parent handicapping themselves', () {
      final r = setHandicap(bySide: Side.b, kind: GameKind.tictactoe, handicapId: 'no_centre');
      expect(r.ok, isFalse);
      expect(r.refusal, HandicapRefusal.childOnly);
    });

    test('refuses a parent even when asking to clear a handicap', () {
      final r = setHandicap(bySide: Side.b, kind: GameKind.tictactoe, handicapId: null);
      expect(r.ok, isFalse);
      expect(r.refusal, HandicapRefusal.childOnly);
    });

    test('the child can set a known handicap for that game', () {
      final r = setHandicap(bySide: Side.a, kind: GameKind.tictactoe, handicapId: 'no_centre');
      expect(r.ok, isTrue);
      expect(r.handicapId, 'no_centre');
    });

    test('the child can clear a handicap', () {
      final r = setHandicap(bySide: Side.a, kind: GameKind.tictactoe, handicapId: null);
      expect(r.ok, isTrue);
      expect(r.handicapId, isNull);
    });

    test('refuses a handicap id that does not belong to that game', () {
      final r = setHandicap(bySide: Side.a, kind: GameKind.story, handicapId: 'no_centre');
      expect(r.ok, isFalse);
      expect(r.refusal, HandicapRefusal.unknown);
    });
  });

  group('handicapBanner — never "Dad is worse"', () {
    test('null handicap renders no banner', () {
      expect(handicapBanner(GameKind.tictactoe, null), isNull);
    });

    test('an unknown id for that game renders no banner', () {
      expect(handicapBanner(GameKind.story, 'no_centre'), isNull);
    });

    test('phrases the handicap as the hard way, never as a deficiency', () {
      final banner = handicapBanner(GameKind.tictactoe, 'no_centre');
      expect(banner, "Dad's playing the hard way — dad can't use the middle square");
      expect(banner, isNot(contains('worse')));
      expect(banner, isNot(contains('lost')));
    });
  });

  group('shouldOfferHandicap — surfaces after three straight parent wins', () {
    test('true after exactly a 3-in-a-row parent win streak', () {
      expect(
        shouldOfferHandicap([GameOutcome.b, GameOutcome.b, GameOutcome.b], GameKind.tictactoe),
        isTrue,
      );
    });

    test('a single child win anywhere in the last three resets it', () {
      expect(
        shouldOfferHandicap([GameOutcome.b, GameOutcome.a, GameOutcome.b], GameKind.tictactoe),
        isFalse,
      );
    });

    test('draws are skipped, not counted as a break — only the last three decided games matter', () {
      expect(
        shouldOfferHandicap(
          [GameOutcome.b, GameOutcome.b, GameOutcome.draw, GameOutcome.b],
          GameKind.tictactoe,
        ),
        isTrue,
      );
    });

    test('never offered for a co-op game — there is no "behind" to relieve', () {
      expect(
        shouldOfferHandicap([GameOutcome.b, GameOutcome.b, GameOutcome.b], GameKind.story),
        isFalse,
      );
    });

    test('fewer than three decided games is never enough', () {
      expect(shouldOfferHandicap([GameOutcome.b, GameOutcome.b], GameKind.tictactoe), isFalse);
    });
  });

  group('handicapOffer — her choice, her framing', () {
    test('the prompt asks her and states no record or number', () {
      final offer = handicapOffer(GameKind.tictactoe);
      expect(offer.prompt, contains('Want to make it harder'));
      expect(offer.prompt, isNot(matches(RegExp(r'[0-9]'))));
      expect(offer.options, catalogueFor(GameKind.tictactoe).handicaps);
    });
  });
}
