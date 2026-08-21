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

**Wiring:** `child_home.dart`'s `onPlay` switch gets 8 more cases, each pushing its screen. `GamePickerScreen`'s existing age-gating (`forAge()`) and breakpoint grid already handle the new catalogue entries with no changes needed there.

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
