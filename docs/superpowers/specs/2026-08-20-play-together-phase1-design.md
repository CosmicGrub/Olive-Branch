# Play Together — Phase 1: local pass-and-play catalogue expansion

**Status:** draft, pending user approval
**Scope:** local (same-device) play only. Async/live network play is Phase 2/3 — a separate, later spec.

## Goal

"Play together" (`GamePickerScreen`) currently offers 4 `GameKind`s (`tictactoe`, `dotsboxes`, `memory`, `story`); only `story` has a real board. This phase closes the gap the user found live on-device, then extends the catalogue with 8 new activities, all in the same established local-pass-and-play mode every other game in this codebase already uses.

**In progress already** (background build, separate from this spec): `tictactoe` and `dotsboxes` real boards, ported from `packages/games/src/games.ts`'s already-tested engine, following `game_chess.dart`'s exact structural pattern and reusing the existing `HandicapScreen`. Not re-specified here — tracked as its own PR.

**New in this spec — 8 activities**, from the visual-companion brainstorm:

| Activity | Shape | minAge | Reuses |
|---|---|---|---|
| Draw Together | co-op, shared canvas | 4 | `annotation_canvas.dart`'s `AnnotationCanvas` engine (already built, already multi-actor-safe) |
| Silly Sentence Maker | co-op, curated word banks | 4 | — |
| 20 Questions | co-op, curated category list | 5 | — |
| Copy the Pattern | solo-with-parent-prompting, self-scaling difficulty | 2 | — |
| Find It (I-Spy) | co-op, curated scenes | 2 | — |
| Would You Rather | co-op, curated prompt bank | 4 | — |
| Guess the Doodle | co-op-framed, canvas + curated word list | 5 | `annotation_canvas.dart` |
| Two Truths and a Tall Tale | co-op, curated prompt categories (not open text) | 6 | — |

## Architecture

**Catalogue extension, not a new system.** `game_logic.dart`'s `GameKind` enum and `catalogue` constant already accommodate non-competitive entries — `story` is the existing precedent: `competitive: false, handicaps: []`. All 8 new activities get real `GameKind` values and real `GameMeta` catalogue entries in that same shape (co-op, no handicap machinery). None of them need `HandicapScreen`, `setHandicap`, or the `Side.a`/`Side.b` turn-alternation the competitive board games use — §9.2's handicap system is specifically for competitive games with something to be behind at; P2's "no scores/streaks" already rules out anything score-like for these regardless.

**File structure**, one self-contained file per activity, matching this codebase's established "each group ports only what it needs" discipline (see `game_logic.dart`'s own header):

- `game_draw_together.dart`, `game_guess_doodle.dart` — thin wrappers around the existing `AnnotationCanvas` (import, don't reimplement). Guess the Doodle adds a curated word-reveal/guess state machine on top of the same canvas.
- `game_silly_sentence.dart`, `game_would_you_rather.dart`, `game_two_truths.dart`, `game_twenty_questions.dart` — content-driven: a curated, in-repo constant list of prompts/categories/word-banks (no free-text input anywhere — this is the concrete mechanism behind "safe without parental advisory"), a simple turn-taking state machine, no persistent state beyond the current session.
- `game_copy_pattern.dart`, `game_find_it.dart` — younger-age, icon/color/shape based, minimal-to-no text, self-scaling (pattern length grows; I-Spy scene difficulty is fixed per curated scene, not parent-adjustable) so §9.2 doesn't apply (nothing for a parent to set).

**Wiring:** `child_home.dart`'s `onPlay` switch gets 8 more cases, each pushing its screen. `GamePickerScreen`'s existing age-gating (`forAge()`) already handles the new catalogue entries with no changes needed there.

## Device-adaptive behavior (Fold5 / tablet), real not cosmetic

Added per explicit request: these activities must genuinely adapt to the device they're running on — not just avoid overflowing at 344px, but actually present differently at different postures. `form_factors.dart` already exists for exactly this (`postureFor(Viewport)` → a real `Posture`; `columnsAt(Viewport, textScale)` → 1/2/3 real layout columns) and is real, tested (`form_factors_test.dart`), and specifically built to replace ad hoc per-screen pixel breakpoints — its own header names that anti-pattern directly. **Every one of the 8 new screens must drive its layout from `postureFor()`/`columnsAt()`, not a hand-rolled width check.**

Concrete, per-activity difference between `foldCover` (344px, 1 column — this app's narrowest supported posture) and `foldMain`/`tabletLarge` (2-3 columns) — genuine content/layout change, not just resizing the same thing smaller:

- **Draw Together / Guess the Doodle**: single column → canvas fills the screen, tools in a bottom sheet. 2+ columns → tools sit in a persistent side panel (using `foldMain`'s own documented crease-gutter convention — "two-column gutters are placed there deliberately"), giving more actual canvas area, not just a bigger canvas.
- **Silly Sentence Maker / Would You Rather / Two Truths**: single column → one prompt at a time, full width. 2+ columns → prompt on one side, a running history of what's been played this session on the other — genuinely more content shown, not enlarged text.
- **20 Questions**: single column → question input only. 2+ columns → the running question log alongside the input, so neither of you has to remember what's already been asked.
- **Find It**: single column → fewer simultaneous hidden objects (a 344px scene has real room limits). 2+ columns → a richer scene with more objects — actual difficulty/content scaling by available space, matching `columnsAt`'s own effective-width-after-text-scale calculation (§8.8) so a large accessibility text size correctly degrades a wide device toward the simpler layout too.
- **Copy the Pattern**: single column → pattern and tap-grid stacked vertically. 2+ columns → side-by-side, so the parent narrating "what comes next" and the child's tap target are both visible without scrolling.

**Related fix, same area, found while doing this:** `game_picker.dart` itself (the hub these all launch from) still has exactly the hand-rolled breakpoint (`constraints.maxWidth >= 680 ? 3 : ... >= 420 ? 2 : 1`) `form_factors.dart`'s own header describes fixing elsewhere — never migrated when `form_factors.dart` was added, matching `court_export.dart`'s pre-fix bug from earlier this session. Migrating it to `columnsAt()` is small and belongs in this same PR wave for consistency, since every screen it launches will now be posture-driven.

**Testing addition:** each new screen needs a real widget test proving DIFFERENT rendered structure at `foldCover` width vs. a wide posture (e.g. `tabletLarge`'s ~800px+) — not just "doesn't overflow" — mirroring `court_export_test.dart`'s `reviewableAt()`/`requestableAt()` precedent from this session's own recent work.

## Content strategy (the actual safety mechanism)

Every activity's prompts/words/categories/scenes are **fixed, in-repo, curated constants** — not user-generated, not fetched, not free-text. This is what makes "appropriate for children with and without parental advisory" true by construction rather than by hoping a parent moderates in the moment. Each file's own header should state its content source explicitly (matching this codebase's documentation discipline) and the actual word/prompt lists need real drafting — not a placeholder ("some prompts") — as part of implementation, reviewed for tone (silly and warm, never a values judgment) before merge.

## Motion & P2 compliance

Consequence-only animation throughout (§8.13) — a card flip, a stroke appearing, a reveal — never a looping or idle animation. No score, streak, rank, or "you won" framing anywhere in these 8; Guess the Doodle's closest thing to an outcome is "did you get it?" (yes/no reveal), never tallied across rounds.

## Testing

Mirror `game_story_test.dart`'s depth per activity: real state-machine correctness (a would-you-rather prompt actually advances; a 20-questions guess is actually recorded; draw-together strokes actually reach the shared canvas with correct per-actor undo — reuse `annotation_canvas_test.dart`'s own assertions as the base, don't re-derive them), a narrow-width (344px, Fold5 cover screen) no-overflow widget test per screen, and a real-navigation-reachability test proving `child_home.dart`'s `onPlay` actually reaches each new screen.

## Doc-sync

Same lockstep requirement as every PR this session: `MASTERFILE.md` (§9.2 status note extended to list all activities, noting which are content-driven vs board-based), `CHANGELOG.md`, `MARKUP.html` (the `gamePicker` screen entry), `scaffold/demo/shell.html`.

## Open questions / explicitly out of scope for this phase

- **Content lists** (actual prompt/word/scene text) are not drafted in this spec — real content needs real drafting, not a stub, before merge.
- **Memory (photo-based)** remains explicitly deferred pending the separate photo-source product decision — untouched by this phase.
- **Async/live network play** for any of these — separate Phase 2/3 spec, not designed here.
- Whether to batch these 8 into one PR or ship in smaller batches (e.g., Draw Together + Guess the Doodle together since they share the canvas engine, then the content-driven ones as a second batch) — recommend batching by shared-code affinity rather than one giant PR; open to your preference.
