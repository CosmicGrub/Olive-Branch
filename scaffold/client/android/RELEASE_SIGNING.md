# Android release signing

A release build signed with Flutter's shared **debug** key is not acceptable
for a real release:

- The Play Store will not accept a debug-signed upload.
- Every device install of a debug-signed build trusts the same public debug
  key that ships with every Flutter SDK on every developer's machine
  everywhere -- it proves nothing about who actually built the app.

So `build.gradle.kts` no longer produces one by accident: with no
`key.properties` file present, `flutter build apk --release` (or
`appbundle`) **fails** with a message saying so. Debug builds, `flutter run`
and CI's debug compile are unaffected. This document is about creating and
wiring in a **real** signing key, and about producing a small, per-device
release (a 96 MB "fat" APK carries four CPU architectures; both target
devices are arm64).

## Before you start: the one irreversible part

Once you publish an app to the Play Store signed with a given key, **that
key is permanent for that app's lifetime.** Every future update must be
signed with the same key (or use Play App Signing, see below), forever, or
the Play Store will reject it as a different app. If you lose the key and
have no way to recover it, you cannot ship an update to your existing
listing ever again -- you would have to publish as a new app, and everyone
who installed the old one gets nothing.

So: **generate this yourself, keep the keystore file and its passwords
somewhere durable (a password manager, an encrypted backup) that isn't just
this one machine, and don't lose it.** This is exactly the kind of
credential Claude should never generate, hold, or see on your behalf --
you run the command below yourself, choose your own passwords, and keep
the result.

Google's own **Play App Signing** program (opt-in during your first Play
Console upload) mitigates the "lose the key, lose the app" risk: Google
holds the actual signing key and you sign your uploads with a separate
"upload key" instead, which *can* be reset if lost. If you plan to publish
on the Play Store, look into enrolling when you get there -- it doesn't
change anything below, just makes the consequence of losing this key less
final.

## 1. Generate a real keystore

Run this yourself, in a terminal, on a machine you trust -- not something
to hand to an assistant to run for you, since it will ask you to choose
real passwords:

```bash
keytool -genkeypair -v \
  -keystore olive-branch-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias olivebranch
```

`keytool` ships with any JDK (Flutter's own bundled JDK works fine --
find it via `flutter doctor -v`'s Java binary path if you don't have one
on your `PATH` separately). It will prompt you for:

- A keystore password (protects the whole file)
- Your name, organizational unit, organization, city, state, country code
  (these become part of the certificate; they don't need to be a real
  legal entity if you're not publishing under one, but should be
  something you'll recognize)
- A key password (can be the same as the keystore password)

Store the resulting `.jks` file **outside this repository** (e.g.
alongside your password manager's attachments, or an encrypted drive) --
`android/.gitignore` already blocks committing it if you leave it here by
mistake, but keeping it outside the repo entirely is safer still.

## 2. Fill in key.properties

Copy `key.properties.example` (this directory) to `key.properties` (same
directory) and fill in the four values with what you just chose:

```properties
storePassword=<your keystore password>
keyPassword=<your key password>
keyAlias=olivebranch
storeFile=/absolute/path/to/olive-branch-release.jks
```

`key.properties` is already git-ignored, same as the keystore itself --
neither should ever be committed.

## 3. Build

```bash
cd scaffold/client
flutter build apk --release --split-per-abi --target=lib/main_live.dart --dart-define=OLIVE_API_BASE_URL=<your real server URL>
```

**The `--target` flag is not optional — get it wrong and this ships the demo's
hardcoded PIN.** An untargeted `flutter build apk --release` (no `--target`)
resolves to `lib/main.dart`, this repo's **offline demo build** — its own file
header says so directly, and its kiosk gate checks a plain, unauthenticated
`_demoGuardianPin = '1273'` constant, not the real scrypt+WebAuthn check.
Only `lib/main_live.dart` wires the real guardian PIN verification (via
`main_live.dart`'s own `_verifyGuardianPin`). `tools/check-release-target.mjs`
(below) fails the build if this file's own documented command ever drifts
back to an untargeted one — verify it stays correct with `node
tools/check-release-target.mjs` before trusting any release cut from these
instructions.

`build.gradle.kts` detects `key.properties` automatically and signs with
your real key instead of the debug one. No other flag or step is needed.
To confirm which key actually signed the output:

```bash
# From an Android SDK build-tools install (bundled with Android Studio /
# the Android SDK command-line tools):
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

The printed certificate fingerprint should match `keytool -list -v
-keystore olive-branch-release.jks`'s output for your key, not Flutter's
well-known shared debug certificate.

## Size: one APK per CPU architecture, or an app bundle

`--split-per-abi` (in the command above) writes one APK per architecture
instead of one fat APK holding all four:

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk     <- Galaxy Z Fold5, Tab S9 FE
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
```

Both target devices are arm64, so `app-arm64-v8a-release.apk` is the only file
to install on them. To build only that one (fastest, smallest output), add
`--target-platform android-arm64` to the same command.

For a Play Store upload use an app bundle instead; Play then serves each
device only its own architecture and resources:

```bash
flutter build appbundle --release --target=lib/main_live.dart --dart-define=OLIVE_API_BASE_URL=<your real server URL>
```

No `splits {}` block is needed in `build.gradle.kts`; Flutter's own
`--split-per-abi` flag configures it per invocation, and leaving it out of the
file keeps debug builds for emulators (x86_64) working.

## If key.properties is missing

The release build **fails on purpose** with "Release build refused:
android/key.properties is missing". Debug builds and `flutter run` are
unaffected, and so is CI (it only compiles debug Kotlin).

If you only want to smoke-test the release pipeline locally (R8, APK size) and
are certain the output will never be distributed, opt in explicitly for that
one invocation:

```bash
cd scaffold/client
flutter build apk --release --split-per-abi --target=lib/main_live.dart --android-project-arg=olive.allowDebugSignedRelease=true
# or, straight through Gradle:
cd android && ./gradlew assembleRelease -Polive.allowDebugSignedRelease=true
```

That artifact is signed with the public debug key. Never put the property in the
repo's `gradle.properties`.
