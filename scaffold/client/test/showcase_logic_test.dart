// OLIVE BRANCH — pure-logic tests for the showcase/exchange port. §9.10.
//
// Same posture as lock_controller_test.dart: exercise the ported logic
// directly, independent of any widget tree, so the arithmetic (the ask
// cap, the collection line, the reply nudge) is pinned down before a screen
// ever renders it.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/showcase_logic.dart';

void main() {
  group('pending asks — exchange.ts §9.10.7', () {
    Ask askAt(String id, DateTime at, {String prompt = 'Show me something'}) =>
        Ask(id: id, fromUserId: 'dad', fromLabel: 'Daddy', prompt: prompt, askedAt: at);

    test('three asks fit with no displacement', () {
      final now = DateTime(2026, 8, 4, 12);
      var asks = <Ask>[];
      for (var i = 0; i < 3; i++) {
        final result = askForShow(asks, askAt('a$i', now.subtract(Duration(hours: 3 - i))));
        asks = result.asks;
        expect(result.displaced, isNull);
      }
      expect(asks.length, 3);
    });

    test('a fourth ask silently displaces the oldest, oldest-first', () {
      final now = DateTime(2026, 8, 4, 12);
      var asks = <Ask>[];
      for (var i = 0; i < 3; i++) {
        asks = askForShow(asks, askAt('a$i', now.subtract(Duration(hours: 3 - i)), prompt: 'prompt $i')).asks;
      }
      final result = askForShow(asks, askAt('a3', now, prompt: 'the newest one'));
      expect(result.asks.length, maxPendingAsks);
      expect(result.displaced?.id, 'a0');
      expect(result.asks.any((a) => a.id == 'a0'), isFalse);
      expect(result.asks.any((a) => a.id == 'a3'), isTrue);
    });

    test('answering an ask removes it from the child-visible list', () {
      final now = DateTime(2026, 8, 4, 12);
      final asks = [askAt('a0', now)];
      final answered = answerAsk(asks, 'a0', 'show-1');
      expect(asksChildView(answered), isEmpty);
    });

    test('the child view never leaks a count, age, or the word "pending"', () {
      final now = DateTime(2026, 8, 4, 12);
      final asks = [
        askAt('a0', now.subtract(const Duration(days: 4)), prompt: 'an old ask'),
        askAt('a1', now, prompt: 'a fresh ask'),
      ];
      final views = asksChildView(asks);
      expect(views.length, 2);
      for (final v in views) {
        for (final forbidden in askForbiddenWords) {
          expect(v.line.toLowerCase().contains(forbidden), isFalse, reason: '"$forbidden" leaked into "${v.line}"');
          expect(v.prompt.toLowerCase().contains(forbidden), isFalse);
        }
      }
      // The four-day-old ask and the brand new one read identically in shape.
      expect(views[0].line, 'Daddy asked you something');
      expect(views[1].line, 'Daddy asked you something');
    });

    test('reachable-hour aging is proportionally slower than wall-clock hours', () {
      final askedAt = DateTime(2026, 8, 4, 0);
      final now = DateTime(2026, 8, 5, 0); // 24 wall hours later
      final hours = askAgeInReachableHours(askAt('a0', askedAt), now, 8);
      expect(hours, closeTo(8, 0.001)); // 24h wall * (8/24 reachable ratio)
    });
  });

  group('collections — showcase.ts §9.2 / P2', () {
    test('an empty collection invites the first show, with no denominator', () {
      const c = Collection(interestId: 'dino', entries: []);
      final view = collectionChildView(c);
      expect(view.line, 'Show me your first one.');
      expect(view.shownCount, 0);
    });

    test('singular phrasing for exactly one entry', () {
      final c = Collection(interestId: 'dino', entries: [
        CollectionEntry(id: 'e1', interestId: 'dino', name: 'Stegosaurus', shownAt: DateTime(2026, 1, 1)),
      ]);
      expect(collectionChildView(c).line, 'You have shown me one so far.');
    });

    test('plural phrasing counts up, and never states a total out of anything', () {
      final c = Collection(interestId: 'dino', entries: [
        CollectionEntry(id: 'e1', interestId: 'dino', name: 'Stegosaurus', shownAt: DateTime(2026, 1, 1)),
        CollectionEntry(id: 'e2', interestId: 'dino', name: 'Triceratops', shownAt: DateTime(2026, 1, 2)),
        CollectionEntry(id: 'e3', interestId: 'dino', name: 'T. Rex', shownAt: DateTime(2026, 1, 3)),
      ]);
      final view = collectionChildView(c);
      expect(view.line, 'You have shown me 3 of them.');
      expect(view.newest, 'T. Rex');
      for (final forbidden in showcaseForbiddenWords) {
        expect(view.line.toLowerCase().contains(forbidden), isFalse);
      }
    });

    test('adding a duplicate name (case-insensitive) is rejected, not appended', () {
      final c = Collection(interestId: 'dino', entries: [
        CollectionEntry(id: 'e1', interestId: 'dino', name: 'Stegosaurus', shownAt: DateTime(2026, 1, 1)),
      ]);
      final result = addToCollection(c, CollectionEntry(
        id: 'e2', interestId: 'dino', name: 'stegosaurus', shownAt: DateTime(2026, 1, 2)));
      expect(result.ok, isFalse);
      expect(result.collection, isNull);
    });

    test('adding a genuinely new name appends it', () {
      const c = Collection(interestId: 'dino', entries: []);
      final result = addToCollection(c,
        CollectionEntry(id: 'e1', interestId: 'dino', name: 'Stegosaurus', shownAt: DateTime(2026, 1, 1)));
      expect(result.ok, isTrue);
      expect(result.collection!.entries.length, 1);
    });
  });

  group('prompts from interests — showcase.ts', () {
    test('a child with no recorded interest still gets generic prompts', () {
      final prompts = promptsFor(ShowKind.object, [], DateTime(2026, 8, 4));
      expect(prompts, isNotEmpty);
      expect(prompts, contains('Show me something you like'));
    });

    test('an interest generates parameterised, not hard-coded, prompts', () {
      final interests = [Interest(id: 'dino', label: 'dinosaurs', addedBy: Side.child,
        addedAt: DateTime(2026, 7, 1), lastShownAt: DateTime(2026, 8, 1))];
      final prompts = promptsFor(ShowKind.object, interests, DateTime(2026, 8, 4));
      expect(prompts, contains('Show me your favourite dinosaur'));
    });

    test('an interest untouched for over 120 days quietly stops prompting', () {
      final interests = [Interest(id: 'dino', label: 'dinosaurs', addedBy: Side.child,
        addedAt: DateTime(2026, 1, 1), lastShownAt: DateTime(2026, 1, 1))];
      final now = DateTime(2026, 8, 4); // well over 120 days since lastShownAt
      final prompts = promptsFor(ShowKind.object, interests, now);
      expect(prompts.any((p) => p.contains('dinosaur')), isFalse);
      // Still not worse off than a child with nothing recorded at all.
      expect(prompts, isNotEmpty);
    });
  });

  group('reply in kind — exchange.ts §9.10.8', () {
    test('a text reply to a spontaneous show is nudged, not refused', () {
      final guidance = replyGuidance(ShowKind.spontaneous, ReplyKind.text);
      expect(guidance.nudge, isNotNull);
      expect(guidance.preferred, isNot(contains(ReplyKind.text)));
    });

    test('a text reply to a knowledge show is not nudged at all', () {
      final guidance = replyGuidance(ShowKind.knowledge, ReplyKind.text);
      expect(guidance.nudge, isNull);
    });

    test('an artifact reply to a creation show needs no nudge', () {
      final guidance = replyGuidance(ShowKind.creation, ReplyKind.artifact);
      expect(guidance.nudge, isNull);
    });
  });

  group('parent shows — exchange.ts §9.10.10', () {
    test('the unannounced-new-person show is never offered by the product', () {
      final offered = offerableParentShows(10);
      expect(offered.any((s) => s.kind == ParentShowKind.someoneYouWillMeet), isFalse);
    });

    test('age gating hides shows above her rung', () {
      final forToddler = parentShowsFor(2);
      expect(forToddler.any((s) => s.kind == ParentShowKind.walkToWork), isFalse);
      expect(forToddler.any((s) => s.kind == ParentShowKind.whereYouSleep), isTrue);
    });
  });
}
