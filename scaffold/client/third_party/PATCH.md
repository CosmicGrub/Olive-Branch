# Vendored patches

This directory holds locally-patched copies of published packages whose own
build metadata is broken in a way that blocks this app from building at all —
never the plugin's own Kotlin/Java source, only a `compileSdkVersion` literal
that predates a transitive dependency's own newer requirement. See each
patch's own entry below for the specific defect and fix.

## bonsoir_android 5.1.6

**Why this exists.** `bonsoir_android` 5.1.6 (the version `bonsoir ^5.1.11`
resolved to as of 2026-08-30) hardcodes `compileSdkVersion 33` in its own
`android/build.gradle`, while it transitively depends on
`androidx.fragment:fragment:1.7.1`, which itself requires compiling against
API 34 or later. That makes `:bonsoir_android:checkDebugAarMetadata` fail —
the same class of defect, and the same real build failure on this exact repo
(`client/lib/main_live_local_play_test.dart`'s own first real build attempt),
as the `jitsi_meet_flutter_sdk` entry below.

Confirmed by inspecting the cached package directly at
`%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\bonsoir_android-5.1.6\android\build.gradle`,
not guessed — the same discipline the jitsi patch below already established
for this file.

**The fix.** `bonsoir_android_patched/android/build.gradle` changes exactly
one line: `compileSdkVersion 33` → `compileSdkVersion 36` (matching this
app's own `compileSdk`). Same reasoning as the jitsi patch below on why this
is additive and behavior-preserving, not a real code change.

**Wired via** `client/pubspec.yaml`'s `dependency_overrides:`.

**When to remove this.** The moment `bonsoir`/`bonsoir_android` ships a
release with `compileSdkVersion` bumped to 34+ (or referencing
`flutter.compileSdkVersion` instead of a hardcoded literal), delete
`bonsoir_android_patched/` and the `dependency_overrides` entry, and bump the
version pin in `pubspec.yaml`'s main `dependencies:` block instead. No GitHub
issue was found reporting this specific defect at the time this was written —
worth filing upstream against <https://github.com/Skyost/Bonsoir/issues>.

---

# Removed: jitsi_meet_flutter_sdk 13.1.0 patch

The vendored `jitsi_meet_flutter_sdk_patched/` copy (a one-line
`compileSdkVersion 34` -> `36` build-metadata fix) was deleted by the on-device
performance pass. The LiveKit migration had already removed the
`dependency_overrides` entry, so nothing in `pubspec.yaml` or the Gradle build
referenced it. It remains in git history (the commit before the deletion).
