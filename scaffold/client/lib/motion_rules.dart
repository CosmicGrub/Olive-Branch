// OLIVE BRANCH — motion rules. No longer UNVERIFIED — verified by CI (a Flutter toolchain now runs
// for real in tools/verify.sh's automated pipeline — CHANGELOG v0.49.61).
// MASTERFILE §8.13.
//
// A partial port of packages/motion/src/motion.ts — only the subset this
// group's screens actually consult, per the project's own "port what you
// need" convention (see lock_controller.dart's header for the precedent).
// The principle the whole TS module rests on, copied verbatim because it is
// the one sentence every screen in this file answers to:
//
//   **Motion follows the finger. It never leads it.**
//
// Nothing here may move on its own to attract a child. homework/capture/
// retake are "still" surfaces (§8.13.5) — homework is "the one surface in
// the product that asks her to concentrate" — so animated transitions there
// use durationFor(quietnessOf('homework'), ...), which resolves to a
// crossfade-only 120ms, never a slide, bounce, or autonomous motion.
// doodle_desk.dart and colouring_screen.dart are NOT quiet surfaces: strokes
// are 'driven' motion (1:1 with the finger, no duration by definition) and a
// placed stamp or a colouring-page fill is 'consequence' motion, capped at
// [maxConsequenceMs] so she is never made to wait for a picture to finish.
// This file is pure Dart, no Flutter import, same posture as
// lock_controller.dart.

enum MotionKind {
  /// 1:1 with her finger. A card that follows a swipe, or ink that follows a
  /// stroke. Always allowed.
  driven,

  /// A result of an action she took. Capped in duration.
  consequence,

  /// Slow, informational, never attention-seeking. Allowed on named surfaces
  /// only (not reproduced here — this group's screens don't use it).
  ambient,

  /// Moves on its own to attract attention. NEVER.
  autonomous,
}

const bool autonomousIsNeverAllowed = true;

/// Longer than this and she has been made to wait for a picture to finish.
const int maxConsequenceMs = 400;

/// Driven motion has no duration; it is her finger.
const int maxDrivenMs = 0;

enum Quietness { full, reduced, still }

/// The subset of motion.ts's QUIET_SURFACES table this group's screens
/// touch. `homework` (and by extension its capture/retake sub-screens) is
/// the one surface here marked 'still'; doodle and colouring are absent from
/// the source table, which defaults them to 'full' — exactly right, since
/// both are built around driven, finger-following motion.
const Map<String, Quietness> _quietSurfaces = <String, Quietness>{
  'homework': Quietness.still,
};

const Map<String, String> _whyQuiet = <String, String>{
  'homework': 'This is the one surface in the product that asks her to concentrate.',
};

Quietness quietnessOf(String surface) => _quietSurfaces[surface] ?? Quietness.full;

String? whyQuiet(String surface) => _whyQuiet[surface];

/// Reduced motion (§8.8) and a quiet surface compose — whichever is quieter
/// wins, and an accessibility setting is never overridden by a surface
/// default.
Quietness effectiveQuietness(String surface, bool reducedMotionOn) {
  final Quietness s = quietnessOf(surface);
  if (!reducedMotionOn) return s;
  return s == Quietness.still ? Quietness.still : Quietness.reduced;
}

int durationFor(Quietness q, int base) => switch (q) {
      Quietness.still => 0,
      Quietness.reduced => (base * 0.45).round(),
      Quietness.full => base,
    };

/// "Still" never means a hard cut. A cut is disorienting in its own way — it
/// is a crossfade with no travel, which reads as calm rather than broken.
const bool stillMeansCrossfadeNotCut = true;
const int crossfadeMs = 120;

/// Two moving things at once is a scene. Three is a distraction.
const int maxConcurrentMotions = 2;

bool admitConcurrent(int running) => running < maxConcurrentMotions;
