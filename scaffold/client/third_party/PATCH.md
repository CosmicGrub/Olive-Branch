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

# Vendored patch: jitsi_meet_flutter_sdk 13.1.0

**Why this exists.** `jitsi_meet_flutter_sdk` 13.1.0 (the latest release on
pub.dev as of 2026-08-04) hardcodes `compileSdkVersion 34` in its own
`android/build.gradle`, while it transitively depends on
`org.jitsi.react:jitsi-meet-sdk:13.1.0`, which pulls in `androidx.media3:*`
at version `1.8.0`. Every `media3` 1.8.0 artifact declares in its own AAR
metadata that consumers must compile against API 35 or later. That makes
`:jitsi_meet_flutter_sdk:checkDebugAarMetadata` fail with 15 violations (13
media3 modules + `androidx.core`/`core-ktx` 1.16.0, same requirement) — the
app cannot produce **any** APK, debug or release, until this is resolved one
way or another.

This is a bug in the published package, not in this app: the plugin's own
Kotlin/Java source was never touched, only its own build metadata is
inconsistent with its own dependency. Confirmed by inspecting the cached
package directly at
`%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\jitsi_meet_flutter_sdk-13.1.0\android\build.gradle`.

**The fix.** `jitsi_meet_flutter_sdk_patched/android/build.gradle` changes
exactly one line: `compileSdkVersion 34` → `compileSdkVersion 36` (matching
this app's own `compileSdk`, `client/android/app/build.gradle.kts`). Nothing
else in the package is modified — same Kotlin/Java source, same
`jitsi-meet-sdk:13.1.0` dependency, same `media3:1.8.0` versions actually
used at runtime. `compileSdk` only controls which APIs are *visible at
compile time*; raising it is additive and cannot remove or change behavior
of code that already compiled fine at 34. There is no dependency-version
change here, unlike the `androidx.media3` force-downgrade alternative that
was considered and rejected — that would have changed the actual bytecode
Jitsi's calling code runs against, which is a real behavioral-risk change
this vendoring avoids entirely.

**Wired via** `client/pubspec.yaml`'s `dependency_overrides:` — see that
file. `flutter pub get` picks up the local path override; `pubspec.lock`
records it as a `path` source instead of `hosted`.

**When to remove this.** The moment `jitsi_meet_flutter_sdk` ships a release
with `compileSdkVersion` bumped to 35+ (or referencing
`flutter.compileSdkVersion` instead of a hardcoded literal, as this app's own
`build.gradle.kts` does), delete `jitsi_meet_flutter_sdk_patched/` and the
`dependency_overrides` entry, and bump the version pin in `pubspec.yaml`'s
main `dependencies:` block instead. No GitHub issue was found reporting this
specific defect at the time this was written — worth filing upstream against
<https://github.com/jitsi/jitsi-meet-flutter-sdk/issues>.
