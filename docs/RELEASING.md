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

## Rollback

- **Before publishing:** nothing left the machine. Delete `scaffold/out/release/X.Y.Z/`, fix the cause, run the dry run again.
- **A published release is wrong** (bad notes, wrong file): `gh release delete vX.Y.Z --cleanup-tag --yes` removes the release
  and the tag; fix the cause on `main`; cut **the next patch** (`X.Y.Z+1`), never the same version again. Anyone who installed
  the bad file reinstalls the new one over it (the build number is higher, so it updates in place).
- **A bad build is on a device:** `adb install -r` the previous release's APK only works for a *higher* version code; an earlier
  code needs `adb uninstall com.olivebranch.olive_client` first, which erases that device's app data. Prefer fixing forward.
- **The merged cut PR itself is wrong** (a number or a claim): fix it in a normal PR; the tool does not need the tag for that.
