# Onboarding & Guardian Access — Sub-project 1: Identity capture & required PIN setup

**Status:** approved, ready for implementation
**Scope:** a real, persisted child-side identity step (gender, alongside the existing non-authoritative age tap) on an already-provisioned device, and a required (not optional) guardian PIN as part of Guardian Setup. The first sub-project of a 3-part onboarding/parental-controls arc — sub-project 2 (PIN-gated parental controls + progressive-unlock pacing), device-pairing/provisioning UI, and automatic first-run detection are explicitly deferred to their own future scoping passes, not designed here.

## Goal

Two real, pre-existing gaps make this sub-project necessary, not cosmetic:

1. **None of today's onboarding screens persist anything.** `onboarding_name.dart`/`onboarding_age.dart`/`onboarding_who.dart` are demo-replay only (reached via `ChildMoreScreen`'s "Redo the welcome tour") — `onboarding_logic.dart`'s `outcome()` computes a real `{displayName, effectiveAge, ...}` object that no route in `server/routes.mjs` ever ingests. This sub-project builds the first real "what she tapped is actually saved" path in this whole pipeline.
2. **A guardian's kiosk PIN (`pin_credential`, real, scrypt-hashed, already wired via `POST /v1/me/pin`) is optional today.** Sub-project 2's entire premise — PIN-gated parental controls — needs a PIN to reliably exist. An optional PIN today would leave that feature unreachable for any family that skipped it.

Alongside these, the user asked for a child-side gender tap, matching the existing age-tap's low-stakes, non-judgmental pattern. Nothing in this codebase consumes gender today, and nothing here builds anything that does — it is captured honestly and left unused, the same posture `guardian_setup.dart` already takes with `registerPasskey` ("no such service exists yet in this preview build," said outright rather than faked).

## Prior art considered, and why this isn't that

MASTERFILE §8.5.0 documents a near-identical idea — one modal reading a self-reported signal to decide device authority — proposed and **explicitly rejected**: routing real guardian authority off a child's tapped, unverified age is the same failure `AgeStep` already guards against one layer down, at much higher stakes (court exports, the other guardian's private notes, the child's own emergency card). This sub-project doesn't repeat that mistake: gender is captured but drives *nothing*, and the mechanism gating the guardian side is a **PIN**, not a self-reported number.

Separately, `onboarding_who.dart` deliberately never asks a child to choose between her parents ("tactless at best," her own MASTERFILE §8.5.3) — this sub-project doesn't touch that screen or that question at all. The "who are you" framing here is the existing `EntryGate` device-role question (My child's device / The grown-up's device), already real, already granting nothing by itself — unchanged by this spec.

## Data model

A new table, not a new column on `child` — the identical precedent sub-project 3a's own migration already established for `ageAtLastOpen` (`child` has never had row-level security enabled at any point in this schema's history; a child-writable column there would be an undeclared widening of an existing table's contract):

```sql
-- db/migrations/0031_child_profile.sql
CREATE TABLE child_profile (
  child_id  uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  gender    text CHECK (gender IN ('boy', 'girl')),  -- NULL = skipped, not "unknown"
  set_at    timestamptz
);
```

Child-owned RLS — the same shape `child_game_picker_state` already uses (child writes her own row; no guardian policy at all, mirroring that table's own reasoning). **No guardian-facing read route in this pass** — nothing consumes this field yet, and a read surface for data nothing uses would be scope creep this codebase's own YAGNI convention already argues against elsewhere. The column exists, honestly captured, ready for whichever future feature needs it.

**Regulatory note, not a mechanism built here:** per MASTERFILE §10.1, this app treats its entire child-data payload as regulated PI; §10.2 requires a real dual-guardian consent state machine rather than a boolean for data-collection decisions generally. Implementation must confirm `gender` is folded into whatever retention/consent handling already governs the rest of `child`'s and `child_profile`'s sibling tables — this spec does not invent a new, bespoke consent flow specific to gender.

## Flow

**Child side** (unchanged entry point — `ChildMoreScreen`'s existing "Redo the welcome tour," the same real reachability `onboarding_age.dart` already has today):

```
onboarding_name → onboarding_age → onboarding_gender (NEW) → done
```

`onboarding_gender.dart` (new file, mirrors `onboarding_age.dart`'s structure exactly — same `ChildOnboardingScaffold`/`TapChoice` shared chrome from `onboarding_shared.dart`): two tap options, **Boy** / **Girl**, plus an explicit **Skip** — never a forced choice. On a real tap (not skip), writes once to `child_profile` via a new route (below). Skipping writes nothing — a `NULL` row is never created just to record "she skipped," matching this app's own "honest absence, not a fabricated state" convention.

New route, mirroring `child_theme_preference`'s own shape: `PUT /v1/children/:childId/profile`, child-session-only (the identical `guardian_only`-inverted posture `recordGamePickerOpen()` already uses for her own visit-recording), body `{gender: 'boy' | 'girl'}`. A malformed body is a `400`, matching every other guardian/child preference route in this app — never a silent no-op.

**Guardian side** (Guardian Setup screen, unchanged entry point — reached from wherever it already is today, e.g. Guardian More):

The existing PIN section (already real, already wired to `setGuardianPin`) becomes a required step in a small linear stepper wrapping `GuardianSetupScreen`'s existing content. A **"Finish setup"** action sits at the end, disabled until `setGuardianPin` has succeeded at least once in this session. The still-stubbed passkey section is untouched — a separate, honestly-labeled section, not blocking, not part of the required path. Re-entering Guardian Setup after a PIN already exists shows the same screen, with "Finish setup" already enabled (no re-entry of an existing PIN required to leave).

## Motion & P2 compliance

No animation beyond the existing tap-choice feedback both `onboarding_age.dart` and the stepper's own "Finish setup" enable/disable transition already use elsewhere in this codebase — a plain enabled-state change, not a celebratory reveal (§8.13's own "nothing shimmers/pulses" rule). P2 is not triggered by the gender capture — it is a bare, unscored, non-comparative fact about her, the identical shape a favourite kind or a starred game already takes: nothing here is a count, a rank, or a streak, and nothing here is ever shown back to her as a status.

## Testing

- `onboarding_gender_test.dart` (new): Boy/Girl/Skip each render and route correctly; a tap writes via the new route, a skip writes nothing; mirrors `onboarding_age.dart`'s own existing test depth for the equivalent tap-and-continue shape.
- `packages/db/test/child_profile.test.mjs` (new, real Postgres RLS): child writes her own row, a stale/no-guardian-policy is proven the same way `child_game_picker_state`'s own RLS test proves it; a `NULL` gender after skip is never coerced into a fabricated default.
- `server/test/child_profile_route.test.mjs` (new): the 400 on a malformed body, child-only write, no guardian read route exists (a guardian request 404s or is simply unrouted — confirm which, document it).
- `guardian_setup_test.dart` (extended): "Finish setup" is disabled with no PIN set, enabled immediately after a real `setGuardianPin` success, and remains enabled on a subsequent visit where a PIN already exists.

## Doc-sync

`MASTERFILE.md` (version bump, a status note near §8.5's onboarding discussion and §11's guardian-auth discussion), `CHANGELOG.md`, `MARKUP.html` (`obAge`'s neighbor gets a new `obGender` entry; `guardianSetup`'s own entry updated for the required-PIN stepper), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- **Sub-project 2 — PIN-gated parental controls (activity visibility + unlock pacing).** Depends on this sub-project's PIN requirement; its own future design pass.
- **Device-pairing/provisioning UI.** Every live build today is provisioned at build time via `--dart-define=OLIVE_CHILD_ID=...`; a real "pair a new physical device to a child through the UI, no rebuild" capability is a separate, materially larger feature — not designed here.
- **Automatic first-run detection.** This flow is reached explicitly (existing "Redo the welcome tour" / Guardian Setup entry points), by the user's own explicit choice — no new first-launch detector is built in this pass.
- Reading `child_profile.gender` back anywhere, or any behavior driven by it.
- Any change to `onboarding_who.dart` or the question it asks — untouched.
- Any change to `EntryGate`'s own "which side is this" copy or mechanism — untouched; it already grants nothing by itself, which this sub-project doesn't need to change.
