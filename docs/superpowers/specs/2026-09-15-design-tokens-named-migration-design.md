# Design Tokens & Named Migration (UI/UX Review Theme #4)

**Status:** approved, ready for implementation
**Scope:** a new shared spacing/radius token file, plus migrating only the specifically-named problem spots this multi-agent review found — not a retrofit of the whole app. Fourth of seven themes surfaced by the review; themes #1-3 (first-run boot polish, Revoke confirmation, hardcoded colors) already shipped.

## Goal

`theme.dart` catalogs color only (6 palettes × 2 brightness → `ColorScheme.fromSeed()`) — confirmed by direct research, and confirmed this was always the intended scope: both MASTERFILE §8.16 and the originating spec (`docs/superpowers/specs/2026-08-21-intuitivism-visual-foundation-design.md`, line 4) scope it to "the design-token foundation only," explicitly deferring spacing/radius/elevation tokens as a later pass that never happened. **This is not an enforcement problem against a documented rule** — grepped MASTERFILE in full for "spacing," "8dp," "padding convention," "corner radius," "type scale": zero hits beyond the one color-scoping line. No convention was ever written down for anyone to violate; ~110 of 167 client/lib files each independently hand-typed their own padding/radius/caption-size values because nothing constrained them.

Given that real scale, this spec deliberately does **not** propose retrofitting all 110 files. It builds the shared token file the review's own findings prove is missing, and applies it only to the concretely-named problems: one standalone bug, one real 5-file duplication, one real card-family inconsistency, and one narrow list-chrome correction. Everything else stays as-is — new code uses the tokens going forward; existing drift outside these spots is not chased down.

## The token file

New file, not an extension of `theme.dart` — `theme.dart`'s whole shape (`AppTheme`/`ThemePalette`/`ThemeBrightness`/`ThemeController`) is built around the palette-and-brightness contract; a spacing scale has nothing to do with it, and widening that file's contract for an unrelated concern is exactly the kind of undeclared scope-widening this codebase's own precedent (`child_theme_preference`'s migration header, among others) argues against. `form_factors.dart` is also confirmed the wrong home — its own doc comment on `comfortableReadingWidth` explicitly guards against being treated as a general token source.

```dart
// scaffold/client/lib/design_tokens.dart

/// Values match what's ALREADY the de facto majority across this codebase
/// (confirmed by direct grep, not invented): 16/12/24/20 dominate existing
/// EdgeInsets.all() calls, 12/16 dominate existing BorderRadius.circular()
/// calls. This codifies the existing standard, not a new arbitrary scale —
/// minimizing visual change at every site this spec actually touches.
class AppSpacing {
  const AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  const AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}
```

No new type-scale infrastructure. Material 3's existing `Theme.of(context).textTheme` ladder (`labelSmall`/`labelMedium`/etc.) already covers the caption-text role the ~19 files with ad-hoc `fontSize: 11.5`/`12.5`/`13.5` literals should be using instead — the fix at migrated spots is a convention (use the theme role), not new code.

## Fix #1 — the standalone bug: ChildHome's grid silently collapses

`guardian_home.dart` (confirmed lines 228-239) floors its column count: `ff.columnsAt(...).clamp(2, 3)`, with a comment explaining why — `columnsAt()` returns 1 below 660px effective width, which would collapse the real 7-inch `tabletSmall` posture (min 600px, "often the child's only device") down to a single stacked column. `child_home.dart`'s structurally mirrored grid (confirmed lines 122-125, used at lines 173 and 245) calls the same `columnsAt()` with no clamp at all — so ChildHome silently drops to 1 column at that same real, common width while GuardianHome does not.

Fix: add the identical `.clamp(2, 3)` to `child_home.dart`'s `cross` computation, with a comment citing `guardian_home.dart`'s own precedent. Independent of everything else in this spec — smallest, clearest, highest-value item here.

## Fix #2 — the 5-game foldTabletop duplication, de-duplicated without changing tested behavior

Confirmed exactly: `game_connect4.dart:225`, `game_war.dart:327`, `game_pictionary.dart:371`, `game_puzzle.dart:140`, `game_uno.dart:660` each hand-roll `outerPad = posture == foldTabletop ? X : Y`, copy-pasted (each site's comment cites the others as precedent), with 3 divergent pairs: `(12,24)`×2, `(10,16)`×2, `(8,16)`×1.

**The foldTabletop-specific value is not purely decorative** — each site's own comment says it was tuned after real-device testing found overflow at foldTabletop's constrained ~420dp height. Shrinking one is safe; growing one (especially Uno's already-tight 8px) risks reintroducing an overflow bug this spec has no real device to re-verify against. Per direct confirmation during scoping: **foldTabletop's own value stays exactly as each game already has it — 12/12/10/10/8 — just named instead of a bare literal, not forced to one shared constant.** Only the "else" (normal-posture, not overflow-constrained) value gets unified, to `AppSpacing.lg` (16) — 3 of 5 games already use it; connect4/war tighten 24→16, which never risks overflow in either direction.

Implementation shape: each game keeps a local, named constant for its own foldTabletop value (e.g. `const _foldTabletopPad = 12.0;` with a one-line comment pointing at this spec and explaining why it's deliberately not shared), and replaces its "else" branch with `AppSpacing.lg`. Deliberately not centralized into a shared lookup table — inventing shared infrastructure for values explicitly chosen to stay non-uniform would be a contradiction in terms.

## Fix #3 — coordination-feature card family, normalized

Confirmed across `expenses_screen.dart`, `letters_screen.dart`, `handover_notes.dart`, `meds_care.dart` (two card variants), `emergency_card.dart`, `care_note.dart`: inner padding is 2 values (12×4, 16×2 — `AppSpacing.md` is the majority, so that's the target); card margin is effectively **4 states**, worse than the original review's "3 values" claim — `meds_care.dart`'s PRN/shared cards and `emergency_card.dart` omit `margin:` entirely and silently inherit Flutter's own undocumented `Card` default (`EdgeInsets.all(4.0)`; confirmed no app-wide `CardTheme` exists anywhere to normalize this). Target: `AppSpacing.sm` (8) — the plurality among the files that do set it explicitly, and an improvement over the two that currently rely on an invisible framework default.

`care_note.dart`'s own record row uses `Card`+`ListTile` — a third chrome shape, different from its 4 siblings' `Card`+`Padding`+`Column`. Fix: convert it to match its siblings' shape, using the same new `AppSpacing` constants — for internal consistency within this one specific feature family, not a broader list-chrome ruling (see next section).

`emergency_card.dart`'s `_AllergyCard` keeps its own custom `shape`/`elevation` (already a deliberately special card per the research, not the plain pattern) — only its inner padding is migrated onto `AppSpacing.md`, its custom shape stays untouched.

## Fix #4 — list-chrome, narrowly: only genuine navigation rows adopt HubTile

`HubTile` (`hub_widgets.dart`) is already real, documented, and used in 4 files/60 call sites for exactly one role: a tappable navigation row. Confirmed via direct research: `story_library.dart` (line 252-260) and `storyteller_screen.dart` (line 549+) use a bare `Card`+`ListTile` for the identical semantic role — tap a bookmark, open a story — not a coincidence, a straightforward match to what `HubTile` already exists for. These two adopt `HubTile` directly.

The other 7 files using bare `Card`+`ListTile` for what looks similar (`exchange_screen.dart`, `expenses_screen.dart`, `expiry_digest.dart`, `message_banking.dart`, `morning_briefing.dart`, `show_guardian.dart`, and `care_note.dart` — already addressed in Fix #3) are confirmed **read-only record rows with no `onTap`** — a data-display shape, not navigation. `HubTile` is the wrong semantic fit for these; they are explicitly not migrated to it. This spec draws the line at "does this row actually navigate somewhere," not at "does it visually resemble a list row" — the two are not the same question, and conflating them was the original review's own imprecision in how it framed this finding.

Note for the implementer: `expenses_screen.dart` appears in both this list and Fix #3's coordination-card family — these are two different widgets in the same file (`_ApprovalCard`, a `Card`+`Padding`+`Column` data card, addressed in Fix #3; a separate `Card`+`ListTile` row elsewhere in the same file, read-only, addressed here by being left alone). Not a contradiction — confirm which widget is which before touching either.

## Testing

- New `design_tokens_test.dart`: sanity-checks the constants exist with their documented values (a thin, honest test — this is a constants file, not logic).
- `child_home_test.dart` (extended): a new case at the 600-660px band proving the grid no longer collapses to 1 column, mirroring `guardian_home_test.dart`'s own existing equivalent case.
- Each touched game's own test file: confirm the foldTabletop/else padding values are unchanged in behavior (foldTabletop) or intentionally shifted (else, connect4/war only) — re-run each game's own existing responsive-audit tests rather than writing new ones, since behavior is preserved except the one disclosed else-value change.
- Coordination-card test files (`expenses_screen_test.dart`, `letters_screen_test.dart`, `handover_notes_test.dart`, `meds_care_test.dart`, `emergency_card_test.dart`, `care_note_test.dart`): re-run existing suites; update any test pinned to an exact old margin/padding value that legitimately changes under the new normalized constants, matching this session's own established discipline of fixing what a real run reveals rather than assuming green.
- `story_library_test.dart`/`storyteller_screen_test.dart`: extend to confirm the migrated `HubTile` still reaches the same real destination on tap — behavior-preserving, chrome-only change.

## Doc-sync

`MASTERFILE.md` (version bump, a short new note near §8.16 cross-referencing this as the deferred spacing/radius half of the design-token foundation, now built), `CHANGELOG.md`. No `MARKUP.html`/`scaffold/demo/shell.html` changes — no new screens are introduced, this is internal consistency work on existing ones. As always: sync the claimed assertion count only after a real full `tools/verify.sh` run reports `0 failed`, never estimate it.

## Explicitly out of scope

- **Retrofitting the other ~100 files' general one-off spacing/radius/caption-size drift.** New code uses the tokens going forward; this pass does not chase down every historical instance. A future pass could revisit this with its own scoping if the drift keeps causing real problems.
- **A new type-scale system.** Material 3's existing `textTheme` ladder is judged sufficient; the fix is a usage convention, not new infrastructure.
- **`camera_controls.dart`'s own separate, unrelated `Posture`-enum duplication** — found incidentally during research (it maintains its own independent posture concept, not `form_factors.dart`'s). A different bug entirely, not part of this theme.
- **The other 7 files' bare Card+ListTile read-only rows** (see Fix #4) — correctly not `HubTile` candidates, and not migrated to anything else either; left exactly as they are.
- **Themes #5-7** (Parental Controls information architecture, motion-budget violations, Add Device wizard polish) — separate, already-queued future items.
