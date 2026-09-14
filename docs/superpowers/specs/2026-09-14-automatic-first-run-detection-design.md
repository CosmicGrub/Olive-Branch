# Automatic First-Run Detection

**Status:** approved, ready for implementation
**Scope:** close the last item deferred by sub-project 1's own spec — automatically routing a freshly-resolved identity (guardian or child) into required setup/onboarding, instead of relying on a manual "Guardian setup" tap or "Redo the welcome tour" tap. The fourth and final item in the onboarding/parental-controls arc; the universal single-app direction remains a separate, later-queued idea, not touched here.

## Goal

Device pairing (merged) already solved *device*-level first run — "does this physical device know which identity it is." It explicitly did not solve, and its own spec disclaimed solving, *identity*-level first run: "has THIS child ever completed onboarding, has THIS guardian ever set a PIN." Three consecutive shipped sub-projects (v0.49.73, v0.49.74, v0.49.75) each independently re-stated this exact deferral — nothing has quietly closed it.

Two real, disclosed gaps, confirmed by re-reading the current boot sequence in full:

1. **A guardian with no PIN can use the app indefinitely.** `hasPin` (added by sub-project 1's `GET /v1/me`) is real and correct, but nothing checks it until the guardian happens to open Guardian Setup herself. Sub-project 1 made the PIN a required *policy* ("a guardian PIN is now REQUIRED for every family going forward") — today that's only enforced at the point someone chooses to look.
2. **There is no signal at all for "has this child completed onboarding."** `child_profile`'s mere absence is provably ambiguous: three of the four onboarding screens (`onboarding_name.dart`, `onboarding_age.dart`, `onboarding_who.dart`) never call the network at all, and even `onboarding_gender.dart` writes nothing on a Skip. A child who fully onboarded and chose Skip is, server-side, indistinguishable from a child who has never opened the app. `child.display_name`/`birth_date` aren't usable either — they're populated at row-creation time (`seed-dev.mjs`), never by onboarding.

## Prior art considered, and why this shape

- **§8.5.0's rejected precedent** (routing device/authority-level decisions off a self-reported, unverified signal) does not apply here: the guardian identity being routed into Guardian Setup was already established through device-pairing's own re-auth gate, and Guardian Setup itself "grants nothing by itself" (its own file header) — real capability still runs through `family-graph/authorize.ts`'s `can()`. Auto-navigating there is a pure UI routing decision on top of an already-authenticated session, not a new authority grant.
- **§8.5.3** (never make a child choose between parents) isn't implicated — this spec never touches `onboarding_who.dart` or its question.
- **The pairing screen's own boot-branch shape** (`_PairingBootApp` in `main_live.dart`, a bare `MaterialApp` root that runs before `KioskShell` mounts) is reused directly for the child-side onboarding branch, rather than inventing a second, different pattern for "content that must run before lock-task engages."

## The signal fix: `child_profile` gets written on every completion, not just a chosen gender

`onboarding_gender.dart`'s `_finish()` now calls `PUT /v1/children/:childId/profile` unconditionally, whether the child tapped Boy/Girl or Skip. The route's accepted body becomes `{gender: 'boy' | 'girl' | null}` — an explicit `null` is a real, meaningful value (onboarding completed, gender declined), written as a row with `gender: NULL` and a real `set_at`. A body missing the `gender` key entirely, or carrying the wrong type, is still a `400` — the distinction is "no opinion, but a real answer" vs. "malformed request," exactly the same honest-absence discipline `child_theme_preference`'s own header already established for its two nullable columns. No schema migration is needed — `gender` was already nullable and `set_at` already exists (`0031_child_profile.sql`); this is a route-validation and client-call-site change only.

## `GET /v1/me` gains one new field

Symmetric with the existing `hasPin` (guardian-only, `null` for a child caller): a new `hasOnboarded` field, `null` for a guardian caller, `true`/`false` for a child caller — computed from `child_profile` row existence for that `childId`. Both fields live on the same response both builds already fetch near boot; no new route.

## Boot-flow changes

**Guardian side** (`main_live_guardian.dart`): after identity resolves (pairing or dart-define) and `GET /v1/me` is fetched, if `hasPin === false`, render `GuardianSetupScreen` in place of `GuardianHome` — no dismiss action, no back-navigation around it. Re-checked fresh on every launch; the moment a PIN exists, the very next boot proceeds to `GuardianHome` normally. `GuardianSetupScreen` itself is unchanged — this only changes what decides whether it's the initial screen.

**Child side** (`main_live.dart`): after identity resolves, fetch `GET /v1/me`. If `hasOnboarded === false`, run the *existing* `onboarding_flow.dart` sequence (name → age → gender — the identical sequence "Redo the welcome tour" already runs; nothing new is invented here) inside a new bare pre-`KioskShell` root, mirroring `_PairingBootApp`'s own shape exactly. Only on that flow's real completion (which now always writes the `child_profile` row, per above) does boot proceed into `_bootLiveApp` → `KioskShell` → `ChildHome`, exactly as today. A child who is mid-onboarding is never inside an engaged kiosk lock — she can only reach lock-task after finishing.

Both gates are driven purely by identity state, not by how that identity got resolved — so they apply the same way to dart-define-provisioned builds as to paired ones.

## Compatibility consequence — disclosed, not a new question

Because both gates apply uniformly, `seed-dev.mjs`'s existing dev/CI/demo data will start hitting them: the seeded guardians (Dad/Mom) currently have no PIN, and the seeded child has no `child_profile` row. Without a data-side fix, every dart-define-provisioned test/demo build would suddenly land on a setup/onboarding screen instead of GuardianHome/ChildHome, breaking any existing test that assumes immediate access. This spec requires `seed-dev.mjs` be updated in the same pass — pre-set a PIN for the seeded guardians, pre-create a `child_profile` row for the seeded child — so existing suites keep working exactly as before. Flagged explicitly so it's treated as required work, not discovered as a wave of unrelated-looking CI failures.

## Testing

- `main_live_test.dart`/`main_live_guardian_test.dart` (extended, files already exist from device-pairing): new boot-branch cases — `hasPin: false` routes to Guardian Setup, `hasOnboarded: false` routes to the pre-lock-task onboarding branch, both re-resolve to Home once true, kiosk lock-task never engages during the child-side branch.
- `child_profile_route.test.mjs` (extended, from sub-project 1): explicit `{gender: null}` now writes a real row (`set_at` populated, `gender` NULL); a body missing `gender` entirely is still `400`.
- `device_pairing_route_test.mjs` (extended — the current home of `GET /v1/me`'s own test coverage, including `hasPin`, confirmed by direct grep rather than assumed): add the equivalent cases for the new `hasOnboarded` field — present and correct for a child caller, `null` for a guardian caller.
- A new or extended seed-data test confirming `seed-dev.mjs`'s output satisfies both gates out of the box (i.e. a fresh dev/CI run never regresses into the new screens unexpectedly).

## Doc-sync

`MASTERFILE.md` (version bump, a short new note near §8.5's onboarding discussion and §11's guardian-auth discussion cross-referencing this closing the sub-project-1-era deferral), `CHANGELOG.md`, `MARKUP.html`/`scaffold/demo/shell.html` only if a genuinely new screen widget is introduced (the guardian-side gate reuses `GuardianSetupScreen` verbatim; the child-side pre-lock-task wrapper may warrant its own brief screen entry if its framing differs at all from the existing onboarding entry — implementer's call, disclose which). As always: sync the claimed assertion count only after a real full `tools/verify.sh` run reports `0 failed`, never estimate it.

## Explicitly out of scope

- **The universal single-app direction** — unrelated, already queued separately as its own future item.
- **Any change to `EntryGate`, `onboarding_who.dart`, or the offline demo build (`main.dart`)** — none of them are touched by this spec.
- **A "skip for now" or dismiss path for either gate** — considered and explicitly declined during scoping; both are hard, non-dismissible gates by design.
- **Multi-child-per-device handling** — device pairing already scopes one device to exactly one `childId`; this spec doesn't add or need any new multi-child concept.
