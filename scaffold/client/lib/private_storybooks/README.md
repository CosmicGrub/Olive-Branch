# Private storybooks — PRIVATE BUILD ONLY, DO NOT SHIP

This directory is a private-build-only feature: a small HTML-storybook
reader for testing/demo purposes on this branch. **It must never reach a
build that goes anywhere near a public app store.** That is not a
preference or a comment to remember to delete later — it is enforced
structurally, in three independent layers, so that even a careless merge
cannot ship it by accident.

## The three layers of isolation

1. **All of this feature's code lives here, in one directory.**
   `scaffold/client/lib/private_storybooks/`, plus its two supporting
   asset files under `scaffold/client/assets/private_storybooks/`, are the
   *entire* feature. Every file in this directory carries this same "DO
   NOT SHIP" header. There is no code belonging to this feature anywhere
   else in `lib/`, with the single, unavoidable exception of one gated call
   site in `child_more.dart` (see layer 2) — that is the wiring, not the
   feature.

2. **The entry point is gated behind a compile-time constant.**
   `private_storybooks_flag.dart` defines:

   ```dart
   const bool kPrivateStorybooksEnabled =
       bool.fromEnvironment('ENABLE_PRIVATE_STORYBOOKS', defaultValue: false);
   ```

   `bool.fromEnvironment` is resolved by the Dart compiler at build time
   from `--dart-define` flags on the build command — not read at runtime,
   not a remote flag, not a settings toggle. A normal `flutter build ...`
   (debug, profile, or release; the kind any store pipeline runs) never
   passes `ENABLE_PRIVATE_STORYBOOKS`, so the constant folds to `false`,
   the single `if (kPrivateStorybooksEnabled)` guard in `child_more.dart`
   becomes dead code, and the compiler strips it. **Nothing renders, and
   nothing is reachable**, even if this entire directory were accidentally
   left in a shipped build. To turn the feature on for local testing only:

   ```
   flutter run --dart-define=ENABLE_PRIVATE_STORYBOOKS=true
   ```

3. **This branch never merges into `main` or any release branch.**
   The feature stays on `feature/private-storybooks`. If a PR is ever
   opened from this branch, its title and body must make unmistakably
   clear that it must not be merged into a release branch.

## How to add a real book later

Nothing here is hardcoded to a specific book — adding one is data, not
code:

1. Drop the book's HTML file into
   `scaffold/client/assets/private_storybooks/` (plain markup only — see
   "Why `flutter_html`" below).
2. Add one entry to
   `scaffold/client/assets/private_storybooks/manifest.json`:
   ```json
   { "id": "some-id", "title": "…", "description": "…", "assetPath": "assets/private_storybooks/your_file.html" }
   ```
3. That's it. `private_storybook_shelf.dart` reads the manifest at
   runtime and lists whatever is in it; no Dart code changes, no switch
   statement to extend.

The one sample entry checked into this branch (`sample_story.html`) is a
short, self-authored, obviously-placeholder 2-4 sentence story invented
for this task. It contains no real book content and exists only so the
reader can be verified end to end without touching anyone's copyright.

## Why `flutter_html`, not `webview_flutter`

This reader renders on a child-facing surface. `webview_flutter` embeds a
real browser engine that executes JavaScript; `flutter_html` only parses
and renders markup and has no script engine at all. That is a real
security boundary, not a style choice — nothing dropped into
`assets/private_storybooks/` should ever be able to run script against
this app. Any future replacement library must keep that same "markup
only, no script execution" property.

## Plain-language summary

This is scaffolding for testing a feature idea. It has no real content,
it is invisible in any normal build, and it must stay that way until (and
unless) a deliberate, separate decision is made to ship a real version of
it — at which point it should be rebuilt with real content review, not
promoted as-is from this branch.
