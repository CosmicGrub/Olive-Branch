// OLIVE BRANCH — motion_rules.dart tests. MASTERFILE §8.13.
//
// This is a partial port (see that file's header), so the tests are scoped
// to the subset actually ported rather than mirroring motion.ts's full
// suite wholesale.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/motion_rules.dart';

void main() {
  test('homework is the still surface this group cares about', () {
    expect(quietnessOf('homework'), Quietness.still);
    expect(whyQuiet('homework'), isNotNull);
  });

  test('an unlisted surface (doodle/colouring) defaults to full motion', () {
    expect(quietnessOf('doodle'), Quietness.full);
    expect(quietnessOf('colouring'), Quietness.full);
  });

  test('a still surface collapses any duration to zero', () {
    expect(durationFor(Quietness.still, 400), 0);
  });

  test('reduced motion shortens but does not zero a full duration', () {
    expect(durationFor(Quietness.reduced, 400), 180);
  });

  test('full motion passes the base duration through unchanged', () {
    expect(durationFor(Quietness.full, 400), 400);
  });

  test('reduced-motion accessibility setting can only make a surface quieter, never louder', () {
    // homework is already 'still'; the accessibility toggle must not
    // "upgrade" it back toward motion.
    expect(effectiveQuietness('homework', true), Quietness.still);
    expect(effectiveQuietness('homework', false), Quietness.still);
    // A full surface WITH the toggle on is only ever reduced, never still.
    expect(effectiveQuietness('doodle', true), Quietness.reduced);
    expect(effectiveQuietness('doodle', false), Quietness.full);
  });

  test('still never means a hard cut', () {
    expect(stillMeansCrossfadeNotCut, isTrue);
    expect(crossfadeMs, greaterThan(0));
  });

  test('driven motion has no duration — it is the finger itself', () {
    expect(maxDrivenMs, 0);
  });

  test('consequence motion is capped so a picture never makes her wait', () {
    expect(maxConsequenceMs, lessThanOrEqualTo(400));
  });

  test('autonomous motion is flagged as never allowed', () {
    expect(autonomousIsNeverAllowed, isTrue);
  });

  test('the concurrent-motion budget matches the colour-placement budget construction', () {
    expect(admitConcurrent(0), isTrue);
    expect(admitConcurrent(1), isTrue);
    expect(admitConcurrent(2), isFalse);
    expect(maxConcurrentMotions, 2);
  });
}
