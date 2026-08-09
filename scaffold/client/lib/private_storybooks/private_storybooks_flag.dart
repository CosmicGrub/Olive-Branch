// PRIVATE BUILD ONLY -- DO NOT SHIP -- see
// scaffold/client/lib/private_storybooks/README.md before ever merging this
// branch anywhere near a release.
//
// This is the one switch every other file in this directory answers to. It
// is a compile-time constant, not a runtime setting: `bool.fromEnvironment`
// is resolved by the Dart compiler at build time, using whatever
// `--dart-define` values were passed on the command line. A normal
// `flutter build ... --release` (or any store-pipeline build) never passes
// `ENABLE_PRIVATE_STORYBOOKS`, so [kPrivateStorybooksEnabled] folds to
// `false` in every such build, with no runtime check, no remote flag, and no
// way to flip it after the fact. Every call site that gates on this constant
// (see child_more.dart) becomes dead code the compiler can and does strip --
// so even if this whole directory were accidentally left in a shipped
// build, nothing it contains renders, and nothing about it is visible.
//
// To explicitly turn the feature on for local development only:
//   flutter run --dart-define=ENABLE_PRIVATE_STORYBOOKS=true
library private_storybooks_flag;

/// True only when a build explicitly opts in via
/// `--dart-define=ENABLE_PRIVATE_STORYBOOKS=true`. Defaults to false, and
/// stays false unless that flag is passed at build/run time.
const bool kPrivateStorybooksEnabled =
    bool.fromEnvironment('ENABLE_PRIVATE_STORYBOOKS', defaultValue: false);
