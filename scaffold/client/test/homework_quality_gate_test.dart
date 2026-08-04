// OLIVE BRANCH — homework_quality_gate.dart tests. MASTERFILE §9.1.
//
// Mirrors packages/homework/test/homework.test.mjs's coverage (sections J
// and L) against the Dart port, so the two stay provably in sync rather
// than just visually similar — same discipline as lock_controller_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/homework_quality_gate.dart';

void main() {
  ImageStats stats({
    int widthPx = 1200, int heightPx = 800,
    double sharpness = 400, double clipping = 0.05, double skewDegrees = 0,
  }) => ImageStats(
      widthPx: widthPx, heightPx: heightPx, sharpness: sharpness,
      clipping: clipping, skewDegrees: skewDegrees);

  group('J — quality gate: thresholds derived from measurement', () {
    test('a clean photo passes', () {
      expect(gateImage(stats()).ok, isTrue);
    });

    test('deskew is the negation of measured skew', () {
      expect(gateImage(stats(skewDegrees: 4)).deskewBy, -4);
    });

    test('skew beyond maxSkewDeg is refused', () {
      expect(gateImage(stats(skewDegrees: 9)).reason, QualityFailure.tooSkewed);
    });

    test('6deg still accepted (67% recovery, deskew fixes it)', () {
      expect(gateImage(stats(skewDegrees: 6)).ok, isTrue);
    });

    test('edge under minEdgePx is refused', () {
      expect(gateImage(stats(widthPx: 200, heightPx: 200)).reason, QualityFailure.tooSmall);
    });

    test('400px accepted — measured 100% recovery', () {
      expect(gateImage(stats(widthPx: 600, heightPx: 400)).ok, isTrue);
    });

    test('sharpness under minSharpness is refused', () {
      expect(gateImage(stats(sharpness: 20)).reason, QualityFailure.tooBlurred);
    });

    test('blown highlights refused', () {
      expect(gateImage(stats(clipping: 0.8)).reason, QualityFailure.tooClipped);
    });

    test('advice is plain and actionable', () {
      expect(gateImage(stats(sharpness: 20)).advice, 'Hold still and try again.');
    });

    test('advice contains no jargon', () {
      final String advice = gateImage(stats(sharpness: 20)).advice!;
      expect(RegExp('threshold|resolution|variance|px|sigma', caseSensitive: false)
          .hasMatch(advice), isFalse);
    });
  });

  group('L — the tutor guard: hint, don\'t solve, as a control', () {
    test('answer derived server-side', () {
      final List<String> forbidden = forbiddenFor('12 + 27 = ______');
      expect(forbidden, contains('39'));
    });

    test('a good hint passes', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('Ask what happens if you add the tens first.', p).ok, isTrue);
    });

    test('a bare answer is refused', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('It should come to 39.', p).reason, HintRefusal.containsAnswer);
    });

    test('"the answer is" is refused', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('The answer is what you get by adding.', p).reason, HintRefusal.tooDirective);
    });

    test('an equals-result is refused', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('So you end up with = 40 roughly.', p).reason, HintRefusal.containsEqualsResult);
    });

    test('"just write" is refused', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('Just write it down.', p).reason, HintRefusal.tooDirective);
    });

    test('an empty hint is refused', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('', p).reason, HintRefusal.empty);
    });

    test('every refusal offers a safe fallback', () {
      final Problem p = Problem(text: '12 + 27 = ______', forbiddenAnswers: forbiddenFor('12 + 27 = ______'));
      expect(guardHint('It is 39.', p).safeFallback!.length, greaterThan(10));
    });

    test('common denominator treated as an answer', () {
      final List<String> forbidden = forbiddenFor('2/3 + 1/5 = ______');
      expect(forbidden, contains('15'));
    });

    test('leaking the denominator is refused', () {
      final Problem f = Problem(text: '2/3 + 1/5 = ______', forbiddenAnswers: forbiddenFor('2/3 + 1/5 = ______'));
      expect(guardHint('Use 15 as the bottom number.', f).reason, HintRefusal.containsAnswer);
    });

    test('pointing at it without saying it passes', () {
      final Problem f = Problem(text: '2/3 + 1/5 = ______', forbiddenAnswers: forbiddenFor('2/3 + 1/5 = ______'));
      expect(guardHint('What number can both 3 and 5 divide into?', f).ok, isTrue);
    });

    test('a substring match does not false-positive', () {
      final Problem f = Problem(text: '2/3 + 1/5 = ______', forbiddenAnswers: forbiddenFor('2/3 + 1/5 = ______'));
      expect(guardHint('There are 159 ways to think about this.', f).ok, isTrue);
    });

    test('negative results are derived', () {
      expect(forbiddenFor('4 - 9 = ___'), contains('-5'));
    });

    test('never emits the reason as text a child would read (no enum leak)', () {
      // The gate returns a typed enum, not a string a screen could
      // accidentally interpolate — retake_screen.dart only ever renders
      // `advice`.
      final QualityVerdict v = gateImage(stats(sharpness: 20));
      expect(v.reason, isA<QualityFailure>());
      expect(v.advice!.toLowerCase(), isNot(contains('too_blurred')));
    });
  });
}
