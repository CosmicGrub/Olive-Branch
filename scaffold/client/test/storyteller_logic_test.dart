// OLIVE BRANCH — storyteller pure-logic tests. MASTERFILE §9.11.
//
// Same posture as lock_controller_test.dart: assert the same properties the
// TS suite (packages/storyteller/src/*.test.ts) asserts, against the ported
// Dart logic, not against a widget tree.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/storyteller_logic.dart';

void main() {
  group('codes and seeds are exact inverses — §9.11.2', () {
    test('round-trips across a spread of seeds', () {
      for (final seed in [0, 1, 42, 594823320, 123456789, maxSeed - 1]) {
        final code = codeFromSeed(seed);
        expect(code.length, codeLength);
        expect(seedFromCode(code), seed);
      }
    });

    test('every character of a code is in the confusable-free alphabet', () {
      final code = codeFromSeed(123456);
      for (final ch in code.split('')) {
        expect(alphabet.contains(ch), isTrue, reason: '$ch not in alphabet');
      }
      expect(code.contains('0'), isFalse);
      expect(code.contains('O'), isFalse);
      expect(code.contains('1'), isFalse);
      expect(code.contains('I'), isFalse);
      expect(code.contains('U'), isFalse);
    });

    test('code space matches 29^6', () {
      expect(maxSeed, 594823321);
    });
  });

  group('a story is a seed — re-readability, §9.11.2', () {
    test('generate() is a pure function of its seed: identical output twice', () {
      final a = generate(777);
      final b = generate(777);
      expect(a.code, b.code);
      expect(a.title, b.title);
      expect(a.lines.map((l) => l.text).toList(), b.lines.map((l) => l.text).toList());
    });

    test('reread(code) reproduces generate(seed) exactly — "the octopus one again"', () {
      final original = generate(90210);
      final again = reread(original.code);
      expect(again.lines.map((l) => l.text).toList(), original.lines.map((l) => l.text).toList());
      expect(again.code, original.code);
    });

    test('freshStory draws a real, in-range seed from the supplied Random', () {
      final s = freshStory(const Personal(), math.Random(1));
      expect(seedFromCode(s.code), lessThan(maxSeed));
      expect(seedFromCode(s.code), greaterThanOrEqualTo(0));
    });

    test('freshStory with different Random seeds is not always the same story', () {
      final codes = {for (int i = 0; i < 8; i++) freshStory(const Personal(), math.Random(i)).code};
      expect(codes.length, greaterThan(1));
    });
  });

  group('never repeats — §9.11.1', () {
    test('the combinatorial floor is astronomically larger than a childhood of stories', () {
      // A story every night for 18 years is 6,570 of them (§9.11.1's own
      // arithmetic). The floor here is smaller than the full TS grammar
      // (this port draws one lexicon rather than crossing per-shape
      // sentence order), but it must still dwarf that by many orders of
      // magnitude for the "never twice" promise to mean anything.
      expect(spaceSize(), greaterThan(6570.0 * 1e9));
    });
  });

  group('shaped for a voice, not an eye — §9.11.3', () {
    test('the refrain is HER line, and appears exactly three times', () {
      final s = generate(4242);
      final refrainLines = s.lines.where((l) => l.isRefrain).toList();
      expect(refrainLines.length, 3);
      for (final l in refrainLines) {
        expect(l.text, s.refrain);
      }
    });

    test('forReadingAloud marks the same lines herLine, and gives a pause hint', () {
      final s = generate(4242);
      final read = forReadingAloud(s);
      expect(read.blocks.where((b) => b.herLine).length, 3);
      for (final b in read.blocks) {
        expect(b.pauseAfter, b.herLine || read.blocks.indexOf(b) == read.blocks.length - 2);
      }
      expect(read.hint, contains('her'));
    });

    test('read time is under two minutes, per the bedtime-deciding parent', () {
      for (final seed in [1, 2, 3, 4, 5]) {
        final s = generate(seed);
        expect(s.readSeconds, lessThan(120));
        expect(s.readSeconds, greaterThanOrEqualTo(30));
      }
    });
  });

  group('personalisation is a light touch — §9.11.3', () {
    test('no personal info: zero touches', () {
      expect(generate(1).personalTouches, 0);
    });

    test('name only: one touch', () {
      expect(generate(1, const Personal(childName: 'Ivy')).personalTouches, 1);
    });

    test('name and colour: two touches, never more (MAX_PERSONAL_TOUCHES)', () {
      final s = generate(1, const Personal(childName: 'Ivy', colour: 'teal'));
      expect(s.personalTouches, 2);
      expect(s.personalTouches, lessThanOrEqualTo(maxPersonalTouches));
    });

    test('her name actually appears in the generated text when supplied', () {
      final s = generate(1, const Personal(childName: 'Zephyrine'));
      expect(s.lines.map((l) => l.text).join(' '), contains('Zephyrine'));
    });
  });

  group('safe for five, and never about her parents — §9.11.4', () {
    test('a clean generated story passes the audit', () {
      final s = generate(55);
      expect(auditStory(s).ok, isTrue);
    });

    test('flags an explicitly banned single word on a word boundary', () {
      const dirty = Story(code: 'ZZZZZZ', seed: 0, shape: 'the_swap', title: 'Test',
        lines: [StoryLine('There was a monster in the garden.', false)],
        refrain: 'x', readSeconds: 30, personalTouches: 0);
      final result = auditStory(dirty);
      expect(result.ok, isFalse);
      expect(result.found, contains('monster'));
    });

    test('flags a banned phrase about her parents', () {
      const dirty = Story(code: 'ZZZZZZ', seed: 0, shape: 'the_swap', title: 'Test',
        lines: [StoryLine('She lived with mummy and daddy.', false)],
        refrain: 'x', readSeconds: 30, personalTouches: 0);
      expect(auditStory(dirty).ok, isFalse);
    });

    test('does NOT flag "begun" as containing "gun" — word-boundary, not substring', () {
      const clean = Story(code: 'ZZZZZZ', seed: 0, shape: 'the_swap', title: 'Test',
        lines: [StoryLine('The day had begun so well.', false)],
        refrain: 'x', readSeconds: 30, personalTouches: 0);
      expect(auditStory(clean).ok, isTrue);
    });

    test('a sweep of generated stories across many seeds all pass', () {
      for (int seed = 0; seed < 500; seed++) {
        final result = auditStory(generate(seed));
        expect(result.ok, isTrue, reason: 'seed $seed produced: ${result.found}');
      }
    });

    test('corpus() is non-empty and contains no banned word by itself', () {
      final words = corpus();
      expect(words, isNotEmpty);
      for (final phrase in bannedContent) {
        expect(words, isNot(contains(phrase)));
      }
    });
  });

  group('a story worth keeping — §9.8', () {
    test('is not preserved on a first read', () {
      expect(storyArtifact(generate(1), 1), isNull);
    });

    test('is preserved from the second read onward', () {
      final artifact = storyArtifact(generate(1), 2);
      expect(artifact, isNotNull);
      expect(artifact!.code, generate(1).code);
    });
  });
}
