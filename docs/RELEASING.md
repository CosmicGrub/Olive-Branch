# Releasing Olive Branch

How a version is cut, what a cut may claim, and how to repeat it as the remaining waves land. The tool is
`scaffold/tools/cut-release.mjs`; the test that keeps the version honest is `scaffold/tools/test/version_sync.test.mjs`
(runs in `npm test`, `tools/verify.sh` and CI). `scaffold/client/android/RELEASE_SIGNING.md` §3 is the only build
instruction and `tools/check-release-target.mjs` enforces that it targets `lib/main_live.dart`.

## What a release is, today

A **debug-signed preview APK** (arm64, `lib/main_live.dart`) for hands-on testing on the Galaxy Z Fold 5 and the Tab S9 FE,
plus a git tag `vX.Y.Z` and a GitHub release whose notes are generated from the CHANGELOG. It is not a Play Store build and
not a build for a real family's data. A real-key signed release needs an owner-held keystore
(`RELEASE_SIGNING.md` §1 to §2); no release has ever been signed with one, and this tool does not attempt it.

**In-app updates** are a separate, owner-run step on top of a cut: a signed manifest and the APK it describes, published so an
installed app can find and download the update. Everything for that is below: "The versionCode policy", "Two flavors", "The
signing key" and "Publishing an update". Nothing in this file's checklist signs a manifest, and CI never does.

## Versioning (one rule)

The version is the **specification** version. It is written in five places, which must agree (CI fails otherwise):

| Place | Where |
|---|---|
| CHANGELOG | newest numbered entry, `## [X.Y.Z] — YYYY-MM-DD — title` |
| MASTERFILE | header table, `Version`, and `Last amended` = the entry's date |
| MARKUP | header line (version and spec), the newest row of the version table, the `screens` count |
| DEMO manifest | `tl-manifest` in `scaffold/demo/shell.html`: `version` and `spec` |
| the app | `scaffold/client/pubspec.yaml`: `version: X.Y.Z+BUILD` |

`BUILD` is derived: **`major*10000 + minor*100 + patch`** (0.51.0 is `5100`, 0.51.1 is `5101`, 0.52.0 is `5200`). Flutter
makes it the Android `versionCode`, so a later cut always updates an earlier install in place and an earlier one can never
overwrite a later one. Minor and patch stay under 100. Never edit the build number by hand; change the version.

Use **minor** (`0.52.0`) for a cut that gathers feature or wave work, **patch** (`0.51.1`) for a fix-only re-cut. A version is
never reused or moved: if a published cut is bad, cut the next patch.

## When to cut

Cut when a coherent wave has merged **and** `[Unreleased]` holds something an owner or tester would want on a device, or
before handing the app to someone else. Do not cut per pull request. A cut is cheap now, but each one is a claim, and the
CHANGELOG paragraph below has to be true.

## Checklist

1. **Start clean.** `git fetch --tags`, a worktree from `origin/main`: `git worktree add ../wt-cutNNN origin/main -b chore/cut-X.Y.Z`.
2. **Gather.** Read `git log <last tag or last cut>..origin/main`. Every merged change needs a CHANGELOG entry; add the missing
   ones (a PR with no entry is a documentation-parity bug). Entries go under `## [Unreleased]`, nowhere else (a second
   `[Unreleased]` heading is a failure; the test checks).
3. **Cut the CHANGELOG.** Rename the block to `## [X.Y.Z] — YYYY-MM-DD — <title>`, leave an empty `## [Unreleased]` above it, and
   write the two lead paragraphs (see "What verified means"). Nothing before the first `###` heading is cut off: the release
   notes quote it.
4. **Bump the five places** in the table above. The MARKUP `screens` count and DEMO `notDemoed` list must stay consistent with
   the screens that exist (`node tools/check-markup.mjs` says what is wrong).
5. **Documentation parity.** MASTERFILE, MARKUP and the DEMO manifest must describe what the code does, not just carry the number
   (the standing rule): check §22 *What is not built yet* against reality; add MARKUP cards for screens added since the last
   cut; correct any "not built" line that later work built.
6. **Assertion total.** Adding a test changes the computed total (`verify.sh` sums every suite). Push, read CI's
   `COMPUTED TOTAL` from the verify job log (`gh api --allow-escape-sequences repos/CosmicGrub/Olive-Branch/actions/jobs/<id>/logs`),
   and set it in `MARKUP.html` line 20 (the `assertions` figure), `scaffold/demo/shell.html` (`"assertions"`) and
   `scaffold/package.json` (`check:markup --total`). Never guess it. A cut that adds no test leaves it unchanged.
7. **Pull request** titled `Cut X.Y.Z ...`, CI green (rerun only transient infrastructure failures: the postgresql.org key
   download, a GitHub download). **Merge.**
8. **Dry run, from the merge commit.** In a worktree of `origin/main` (or `main` pulled):
   `cd scaffold && node tools/cut-release.mjs X.Y.Z`. It checks the tree, the version sync and the release-target guard, builds
   the APK, prints the **SHA-256** and size, and writes `scaffold/out/release/X.Y.Z/` (the APK, `SHA256SUMS`, `release-notes.md`;
   git-ignored). Read `release-notes.md`.
9. **Publish.** Only when the dry run is clean and the notes are true: `node tools/cut-release.mjs X.Y.Z --publish`. It needs a
   clean `main` at `origin/main`, no existing tag, an authenticated `gh`; it builds again, creates the release (GitHub creates the
   tag on that commit), and uploads the APK and `SHA256SUMS`. Do not publish from a branch; the tool refuses.
10. **After publishing.** Install on a device only if you also intend to test it (`adb install -r`); record any device finding in
    the next `[Unreleased]`. Update the Olive Branch PR-pipeline memory/notes with the tag and the APK hash.

### What the tool builds, and refuses to

`flutter build apk --release --target-platform android-arm64 --target=lib/main_live.dart
--android-project-arg=olive.allowDebugSignedRelease=true`, from a checkout with **no dart-defines**:

- No `OLIVE_API_BASE_URL`: the app falls back to the Android emulator's loopback alias (`10.0.2.2`), which a real phone cannot
  reach. The public file therefore carries no LAN address, no `127.0.0.1` development assumption and no secret, and its
  server-dependent features (pairing, delivery, calls, push) are unavailable; the on-device half is what it exercises. If a
  cut should talk to a real server, pass `--base-url https://<public name>` (https, public name, no credentials, no query);
  the tool refuses anything else.
- **Pre-release by default.** Every cut is debug-signed, so `--publish` creates a GitHub *pre-release*; `--stable` opts out
  (only for a release-signed build, which this tool does not yet make). A release with no base URL is a preview in any case:
  it cannot reach a server. v0.51.0 was published as a normal release before this rule; it is left as it is.
- No `OLIVE_DEV_LOGIN`, `OLIVE_CHILD_ID` or `OLIVE_GUARDIAN_ID`: a shipped file can never reach the credential-free dev login.
- It refuses if `android/key.properties` exists (a real keystore would sign the file, and the notes would be wrong) or if
  `android/app/google-services.json` exists (it would be compiled into a public file).
- The build number comes from `pubspec.yaml`, so the install reports `X.Y.Z` and version code `BUILD`.

## What "verified" means (the paragraph every cut carries)

The CHANGELOG entry opens with a lead paragraph and a **"What this release has, and has not, been verified by."** paragraph.
`version_sync.test.mjs` requires the heading text and a statement of what was not verified. Write it from evidence only:

- **CI-verified** is a true claim for: the server and package suites against real Postgres, `flutter analyze`, the full
  `flutter test` suite, the MARKUP, CHANGELOG and DEMO drift checks. Say which, and that they ran on the merged commits.
- **Device-verified** is a claim only for something a person (or a recorded run) exercised on the Fold 5 or the tablet in that
  version: say the device, the build, the date and what was done. Installing a build is **not** exercising it. Without a
  record, write "not run on hardware".
- **Never claim**: calls, push or delivery working (no LiveKit, FCM or APNs credentials exist), TalkBack or read-aloud on a
  device, a real-key signature, or anything about a server that was only run in CI.
- The release notes repeat the lead and this paragraph verbatim, so a tester reads the same caveat the CHANGELOG makes.

## Repeating the cut as the app is built out

Each later wave (the remaining `docs/superpowers/parity/BUILD-PLAN.md` waves, the offline wave, owner-delegated work) follows
the same checklist; it costs one PR plus a dry run and a publish. The cut is cheap because everything repeatable is a test or a
tool now: the version places are guarded, the build is one command, the notes are generated. What stays a person's job is the
CHANGELOG paragraph and the parity check in step 5. When a wave changes what is not built, update MASTERFILE §22.2 in the same
PR, not at the cut.

## The versionCode policy (what makes an update safe)

The Android `versionCode` is the number Android compares to decide "newer". It is **derived from the version, never chosen**:
`major*10000 + minor*100 + patch` (0.52.0 is `5200`), written into `pubspec.yaml` as the `+BUILD` part and checked by
`version_sync.test.mjs`. The update pipeline leans on three consequences, so they are rules, not habits:

1. **Strictly increasing.** Every published version has a higher code than every version before it. Nothing is ever re-published
   under an old or equal code, and a code is never moved. A bad release is fixed **forward**: cut the next patch.
2. **The manifest's `versionCode` is the file's `versionCode`.** `build-update-package.mjs` refuses an APK whose embedded
   `versionCode` or `versionName` differs from the version it was asked to package (when `aapt2` is available), the signing script
   refuses a draft whose code is not the derived one, and the verifier re-checks both on the published bytes.
3. **No rollback, anywhere.** Android refuses a lower code; the app refuses a manifest below the installed code (`rollback`) and a
   manifest whose `sequence` is below one it already accepted (`replayed`); `sign-update-manifest.mjs --prev` refuses to sign
   a manifest that is older than the one live. If a release must be withdrawn, publish a higher one that fixes it, and raise
   `minSupportedVersionCode` only for a security fix (adults then see "Please update"; the child never sees anything and loses no
   data, whatever the floor says).

`minSupportedVersionCode` defaults to `1` in the package script: nobody is nudged. Raise it deliberately, for one reason only: a
build older than this has a defect that makes it unsafe to keep running.

## Two flavors: `direct` and `play`

One code base, one application id (`com.olivebranch.olive_client`), two ways to be updated. `android/app/build.gradle.kts`
declares them; `tools/check-flavors.mjs` (run in `verify`) holds the split.

| | `direct` | `play` |
|---|---|---|
| Distribution | sideload, GitHub release, a family's own server | Google Play |
| Updates | the app's own checker: downloads a verified APK, hands it to Android's installer, the system confirmation always appears | Google Play only (the In-App Updates API); the build never installs a package itself |
| `REQUEST_INSTALL_PACKAGES` | declared (`src/direct/AndroidManifest.xml`) | **removed** (`src/play/AndroidManifest.xml`, `tools:node="remove"`, so a plugin cannot add it back) |
| Build | `flutter build apk --release --flavor direct ...` (the default: `pubspec.yaml` sets `default-flavor: direct`) | `flutter build appbundle --release --flavor play ...` |
| Output | `build/app/outputs/flutter-apk/app-direct-release.apk` (single `--target-platform`) | `build/app/outputs/bundle/playRelease/app-play-release.aab` |

There is **no `applicationIdSuffix` and no `versionNameSuffix`**: a direct build must replace the installed app in place, and the
Play application id is permanent. Flavor-only code lives in `src/direct/kotlin` and `src/play/kotlin` (the same class name in
both, the real installer in direct and an inert stub in play), so `src/main` never names `PackageInstaller`. Dart reads the
flavor as `appFlavor`. CI compiles both (`verify.sh`) and `release-smoke.yml` assembles and launches both.

## The signing key (offline, owner-held)

The update-signing key is the one thing that can make every installed app believe an update exists. It is separate from the
Android release keystore (which signs the APK; `android/RELEASE_SIGNING.md`) and it is **never** in a repository, a workflow, a
server or a chat.

```bash
# once, on a machine you control (the folder must exist and must not be inside any git working tree)
cd scaffold
OLIVE_UPDATE_KEY_PASSPHRASE='<a few ordinary words, at least 14 characters>' \
  node tools/update/gen-update-key.mjs --out /absolute/path/outside/any/repo/olive-update.key --passphrase-env OLIVE_UPDATE_KEY_PASSPHRASE
```

The passphrase is required (`--no-passphrase` is the explicit, discouraged alternative: a plain key file). The file is encrypted with
AES-256-GCM under a key derived by scrypt, so guessing it offline is costly. The tool also refuses a folder that OneDrive, Dropbox,
iCloud Drive or Google Drive syncs, because the key would be copied to a third party's servers: use a local folder or a removable
drive. `.gitignore` and the privacy gate also treat `*.key` and `olive-update*` as files that never belong in the repository.

It prints the **public** entry (`kid:key`) and writes it beside the key as `olive-update.key.pub`. The private key is written
only to the path you named; the tool refuses a path inside any git working tree (this repository included), refuses a relative
path, and never overwrites a file. Then:

- **Back it up**, offline, in a second place (a drive in a drawer, a password manager's file store). Losing it means no installed app
  can be updated in place by a manifest again; people would have to reinstall a build carrying a new public key.
- Build the public entry into every direct build: `--dart-define=OLIVE_UPDATE_PUBKEYS=<kid:key>` (the package script does).
- **Rotation / suspected leak.** The app holds a list of keys. Ship a release signed by the old key that also carries the new public
  entry (`OLIVE_UPDATE_PUBKEYS=<old>,<new>`), wait until it is widely installed, then sign manifests with the new key and drop the
  old entry from the next build. A key that has ever been in a working tree, a chat or a CI secret is treated as leaked.

## Publishing an update (the offline procedure)

Everything below runs on **your** machine. CI builds artifacts (next section) but signs nothing and holds no secret.

1. **Cut the version** with the checklist above (CHANGELOG, the five places, the merge). The version in `pubspec.yaml` is the version
   the update carries.
2. **Write the notes in plain words.** `node tools/update/draft-release-notes.mjs X.Y.Z` makes `docs/release-notes/X.Y.Z.txt` from the
   CHANGELOG section (one line per heading) and stamps it `# DRAFT`. A person rewrites it for a grown-up on a phone (what changes
   for them, not what changed in the code; at most a 100-character headline and 12 notes of 300 characters) and deletes the DRAFT
   paragraph. The package script refuses a file that still says DRAFT. Format: `docs/release-notes/README.md`.
3. **Build and package** (needs your keystore in `android/key.properties`, the Android SDK for `apksigner`, and your public key):

   ```bash
   cd scaffold
   node tools/update/build-update-package.mjs \
     --pubkeys "$(cat /absolute/path/outside/any/repo/olive-update.key.pub)" \
     --manifest-url https://github.com/<owner>/<repo>/releases/download/updates/update-manifest.json \
     --download-base https://github.com/<owner>/<repo>/releases/download/vX.Y.Z \
     --download-base https://<your mirror>/olive
   ```

   It checks the version places agree, reads the notes, builds the direct APK for each `--abi` (default `arm64-v8a`) with the public
   key and the manifest address baked in, refuses a debug-signed build, reads the APK's signing certificate with `apksigner`, checks the
   package and `versionCode` inside the file with `aapt2`, inspects the zip (no duplicate entries, no zip bomb), computes the size,
   SHA-256 and a per-1-MiB chunk hash list, and writes `scaffold/out/update/X.Y.Z/`: the APK, `SHA256SUMS.direct`,
   **`update-manifest.draft.json`** (not signed) and `NEXT-STEPS.txt`. It never reads a private key and uploads nothing. A prebuilt,
   already release-signed file can be packaged instead with `--apk arm64-v8a=<file> --has-update-key`, but only if that file was built
   with the same `OLIVE_UPDATE_PUBKEYS` and `OLIVE_UPDATE_MANIFEST_URL` defines: the script cannot look inside an app, and one built
   without them has no update feature (phones that took it could never be updated in place again). The CI artifact is such a file
   (see "Using the CI build" below). Every address it is given is checked: the manifest address is compiled into the app, so it must
   be https, public and free of characters a command line reads specially (`&`, `%`, quotes), and `--pubkeys` must hold only valid entries.
4. **Read the draft.** The version, the notes, every address, the sizes. This is the last chance to catch a wrong word. `node tools/update/validate-manifest.mjs <draft>` checks it against the published format and the policy.
5. **Sign the manifest, offline:**

   ```bash
   node tools/update/sign-update-manifest.mjs --draft out/update/X.Y.Z/update-manifest.draft.json \
     --key /absolute/path/outside/any/repo/olive-update.key --passphrase-env OLIVE_UPDATE_KEY_PASSPHRASE \
     --out out/update/X.Y.Z/update-manifest.json --prev <the manifest that is live now>
   ```

   It validates the draft against the same rules the app applies, signs the canonical form, then verifies its own output before
   writing it, against this machine's real clock. `--prev` is required: it makes the tool refuse a `sequence` that does not rise and a
   `versionCode` that falls. The very first manifest of a channel has nothing to compare with and is signed with `--first` instead,
   which says so out loud. It also refuses a `sequence` above the issue time in seconds plus a day and an `issuedAt` ahead of the
   clock (one such manifest, accepted by a phone, would make that phone refuse every later one as replayed: updates would be dead for
   good), and a key inside a git working tree.
6. **Upload**: the APK and `SHA256SUMS.direct` to every download address you listed (they are named so they never collide with the
   `SHA256SUMS` that `cut-release.mjs` puts on the same `vX.Y.Z` release), then the **manifest last** (so no phone sees a
   manifest whose files are not there yet). For GitHub, keep one long-lived release tagged `updates` that holds only the manifests,
   so the manifest address never changes and does not depend on what GitHub calls "latest" (which skips pre-releases). Create it
   **once**: `gh release create updates --prerelease --title "Update manifests" --notes "The signed update manifest only."`.
   Then, for every update: `gh release upload updates out/update/X.Y.Z/update-manifest.json --clobber` (the one place replacing a
   file is the point).
7. **Verify what is really published**, with the same checks the app makes:

   ```bash
   node tools/update/verify-update-release.mjs --manifest https://github.com/<owner>/<repo>/releases/download/updates/update-manifest.json \
     --pubkeys "$(cat /absolute/path/outside/any/repo/olive-update.key.pub)" --installed-apk <an APK of the build now installed>
   ```

   It downloads the manifest and every file at every address (primary and mirrors), and fails on a bad signature, a rollback or replay, an
   expired or wrong-channel manifest, a size or chunk or SHA-256 mismatch at any address, a zip that is not sound, a signing certificate
   that is not the pinned one or not the installed build's, a redirect to cleartext or outside the trusted hosts. Do not announce
   anything before it says `VERIFIED`.
8. **Keep the manifest fresh.** It expires (180 days by default, 400 at most) so an old copy cannot be replayed for ever. Re-sign the
   same release with a higher `sequence` and a new `expiresAt` before then (`--prev` allows a higher sequence at the same version).
   A manifest that has expired is simply ignored by apps; nothing breaks and the child is never told.

**Never edit a published manifest.** To change anything, build, sign and publish a new one with a higher `sequence`.

### Using the CI build (no Flutter toolchain on your machine)

`.github/workflows/release-artifacts.yml` runs on a `vX.Y.Z` tag (or by hand for an existing tag), builds the direct APK and the
play bundle with **no secret and no signing step**, and attaches `olive-X.Y.Z-direct-arm64-v8a.ci-build.apk`, `SHA256SUMS.ci-build` and
`build-info.txt` to the release for the tag (a draft pre-release is created if you have not made one; a file whose name is already on
the release, which `cut-release.mjs` normally creates first, is left alone, and none of the names equals one `cut-release.mjs` uploads). Its first step runs
`tools/update/check-release-tag.mjs`, which refuses a tag that does not name the version the checkout really is. Because CI holds no
keystore these files carry Flutter's public debug key: they prove the release compiles and give you the bytes to re-sign,
**never** something to install over a real install or to tell a phone to download. They are for people with no toolchain who want
the bytes to re-sign for a hand-made sideload:

```bash
zipalign -p -f 4 olive-X.Y.Z-direct-arm64-v8a.ci-build.apk aligned.apk
apksigner sign --ks /absolute/path/to/your-release.jks --out olive-X.Y.Z-direct-arm64-v8a.apk aligned.apk
```

**Do not make an update package from the CI bytes.** The CI build has **no update public key and no manifest address built in**
(those are yours), so the app inside it has no update feature: every phone that installed it would have to be updated by hand,
forever. `build-update-package.mjs --apk` therefore refuses unless you pass `--has-update-key`, your statement that the file was built
with both defines. For a build that updates itself, use the full package script (step 3), which bakes both in.

## When something goes wrong with an update

| Situation | What to do |
|---|---|
| A published release is bad | Fix forward: cut the next patch, package, sign with a higher `sequence`, upload, verify. Do not lower anything. If it is unsafe to keep running, raise `minSupportedVersionCode` in that new manifest. |
| A file at one address is wrong or missing | Apps try the next address and verify the bytes, so a wrong file is never installed; fix the address, then run the verifier. |
| The manifest expired | Re-sign with a higher `sequence` and a new `expiresAt` (step 8). |
| The update-signing key is lost | No manifest can be trusted by installed apps. Ship a new build with a new public key by hand (reinstall); this is why the offline backup matters. |
| The update-signing key may have leaked | Treat as lost for trust purposes: rotate (see "The signing key"), and tell the people who installed by hand to reinstall. |
| The Android release keystore is lost | Android will not update an installed app with a different certificate, and the app refuses it too (`certMismatch`). Reinstalling erases that device's app data; see `android/RELEASE_SIGNING.md`. |

## Optional: a family's own server can serve the files

The manifest does not change: only the addresses inside it. A server that serves a directory of static files (no authentication, rate
limited) lets a family run entirely without GitHub; that is a separate piece of work with its own operator note, and the app does
not know or care where an address points, because everything is verified against the signed manifest.

## Rollback

- **Before publishing:** nothing left the machine. Delete `scaffold/out/release/X.Y.Z/`, fix the cause, run the dry run again.
- **A published release is wrong** (bad notes, wrong file): `gh release delete vX.Y.Z --cleanup-tag --yes` removes the release
  and the tag; fix the cause on `main`; cut **the next patch** (`X.Y.Z+1`), never the same version again. Anyone who installed
  the bad file reinstalls the new one over it (the build number is higher, so it updates in place).
- **A bad build is on a device:** `adb install -r` the previous release's APK only works for a *higher* version code; an earlier
  code needs `adb uninstall com.olivebranch.olive_client` first, which erases that device's app data. Prefer fixing forward.
- **The merged cut PR itself is wrong** (a number or a claim): fix it in a normal PR; the tool does not need the tag for that.
