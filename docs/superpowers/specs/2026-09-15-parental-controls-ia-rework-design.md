# Parental Controls Information-Architecture Rework (UI/UX Review Theme #5)

**Status:** approved, ready for implementation
**Scope:** one screen, `parental_controls_screen.dart` — sub-grouping, search, and three targeted fixes. Fifth of seven themes a multi-agent UI/UX review surfaced; themes #1-4 already shipped. Explicitly known and deferred at the time theme #4 shipped (its own spec's "Explicitly out of scope" section names this exact theme), not a fresh discovery.

## Goal

Independent research confirmed the review's core complaint and refined its numbers: the Visibility tab has **88 rows** (6 ChildHome tiles + 21 games + 59 jokes + 2 activities), the Pacing tab has **79 rows** across only 2 un-subdivided sections (tiles/activities have no `defaultMinAge`, so they never appear there at all). Both tabs are one flat `ListView` of `ExpansionTile`s — confirmed the *only* two uses of `ExpansionTile` anywhere in this app; this screen introduced the pattern standalone, with no established house convention to follow (grepped MASTERFILE.md: zero mentions, same "novel, not a regression" situation theme #4 found for spacing/radius tokens).

Three real, confirmed sub-problems, not just "it's a long list":

1. **Joke rows are titled with the raw, often near-identical setup sentence.** `59` jokes, `15` (25%) start with the literal phrase "What do you call," `30` (51%) start with "What" generally, sentences run 50-62 characters and get clipped to one line + ellipsis — roughly half the joke list visually collapses to "What do you call a..." and becomes indistinguishable at a glance.
2. **The Pacing row's trailing controls are a plausible, currently-unverified overflow risk.** `ListTile.trailing` holds an unconstrained `Row` (two `IconButton`s, a fixed-width age label, a text-scaling `TextButton`) with no `Flexible`/`Wrap`/scroll wrapper — exactly the shape this app's own established Fold5-cover (344px) + large-text-scale testing convention exists to catch, and this screen's own test file is confirmed to have none of it (no `344`, no `textScaler`, no `setSurfaceSize` anywhere in `parental_controls_screen_test.dart`).
3. **"Reveal now" has no visual separation from the age-stepper controls** despite being a persistent override, not the temporary-sounding preview its label implies — confirmed no divider, spacing, or distinct styling between the two in the trailing `Row`.

Two things already sitting in the codebase, unused, that this spec builds on rather than inventing from scratch:

- **`joke_logic.dart`'s `JokeCategory` enum** (`dadJoke, pun, wordplay, silly, knockKnock`) — already on every `Joke` object, never read by this screen.
- **`story_library.dart`'s `_SearchShelf` pattern** — a real, working search-box + live-filter + empty-state implementation for exactly this "long list, needs a way to find one item" problem, built for a different screen but structurally transplantable.

## Sub-grouping

Both tabs' existing per-category `ExpansionTile`s each gain a second grouping level, using data/distinctions that already exist rather than inventing new taxonomy:

- **Jokes** (59, currently one flat group) → 5 sub-groups by `JokeCategory`: "Dad jokes," "Puns," "Wordplay," "Silly," "Knock-knock." A straightforward label mapping from the existing enum.
- **Games** (21, currently one flat group) → 2 sub-groups matching a distinction the app already makes elsewhere, not a new one: **"Games"** (the 12 `game_logic.dart` catalogue entries — how they're already presented in the main game picker) and **"More games"** (the 8 `hubGameMinAge` entries + the standalone "Find the thing" row — matching `games_hub.dart`'s own real framing of these as a second door reached from the same "Play together" tile, confirmed via its real `HubSection` titles — "Board & strategy," "Together," "On her own," "Playing fair" — though this spec's own sub-groups stay at the coarser Games/More-games split, not all four of `games_hub.dart`'s own finer sections, to avoid over-fragmenting a controls screen).
- **ChildHome tiles** (6) and **Drawing & activities** (2) stay single flat groups — too small to meaningfully sub-divide.

Implementation shape: nested `ExpansionTile`s (a sub-group `ExpansionTile` inside the existing category `ExpansionTile`), or a flat list with sub-group header rows — implementer's call between these two, since both achieve the same real goal (browsable structure instead of one 59-item flat dump) and the spec has no strong preference between them; disclose which was chosen and why.

## Search

One search field per tab (Visibility and Pacing each get their own, since they show different controls for the same underlying items), reusing `story_library.dart`'s `_SearchShelf` pattern directly rather than a new implementation: a `TextField` (`hintText`/`prefixIcon: Icons.search_rounded` matching that file's own copy conventions), live-filtering via a case-insensitive substring match against each item's title.

**Behavior, matching the precedent's own shape**: an empty query shows the normal grouped view (categories/sub-groups, `ExpansionTile`s as designed above); a non-empty query flattens to a single filtered list across every group, matching however many real items contain the query substring, with an honest "no matches" empty state when nothing does — never a blank screen with no explanation.

## Fix — joke titles

`maxLines: 1` → `maxLines: 2` on both `_visibilityRow`'s and `_pacingRow`'s title `Text`. No new copy, no per-joke summarization — most of the 59 setups (50-62 characters) will render in full or very nearly full inside two lines instead of collapsing to a truncated fragment. Remove `dense: true` from these rows if it visually cramps the second line — implementer's call based on how it actually renders, verify visually or via a widget test asserting the full setup text is findable in the tree without truncation.

## Fix — Pacing overflow: verify first, then fix only if real

Do not restructure this layout on the assumption the review's claim is correct. First, write a real test — `parental_controls_screen_test.dart` currently has none of this app's own standard Fold5-cover/large-text-scale coverage (confirmed by direct inspection) — pumping the Pacing tab at `Size(344, ...)` (this app's established narrow-width floor, per `form_factors.dart`) with a `textScaler` around 1.6-2.0x (matching this codebase's own established convention elsewhere, e.g. `child_home_test.dart`/`care_note_test.dart`), and check for a real `RenderFlex overflowed` exception.

- **If it genuinely overflows**: fix the trailing controls' layout — likely candidates are wrapping the four elements in a `Wrap` instead of an unconstrained `Row`, or moving the Reveal/Un-reveal button to a second line below the age stepper (which also naturally serves the next fix, below). Pick whichever actually resolves the real failure the test reproduces; disclose which.
- **If it does not overflow at this app's own real-device floor**: say so plainly in the PR, keep the layout as-is, and land the new regression test anyway (a real, previously-missing gap in this screen's own coverage, worth having regardless of whether it currently catches a live bug).

Either way, the test is landing — the only open question is whether it also drives a layout change.

## Fix — Reveal-now visual separation

Add a `VerticalDivider` (or equivalent spacing/`Container` grouping — implementer's call, matching whatever this app's own nearest precedent for "two logically distinct button groups in one row" turns out to be, disclose which was used and why) between the age-stepper trio (minus/age-label/plus) and the Reveal/Un-reveal `TextButton` in the Pacing row's trailing controls, so a persistent override reads as visually distinct from a value adjustment rather than sitting at the same weight as a sibling control.

## Testing

- New Fold5-cover/large-text-scale regression test for the Pacing tab (see above) — lands regardless of outcome.
- New tests confirming sub-grouping renders correctly for both jokes (5 sub-groups) and games (2 sub-groups), and that every item still appears exactly once somewhere in the tree (no item silently dropped by the restructure).
- New tests for the search field: typing a real joke/game/tile title's substring filters to matching rows only; clearing the query returns to the grouped view; a query matching nothing shows the honest empty state, not a blank screen.
- Existing `parental_controls_screen_test.dart` suite re-run in full — fix any test that was structurally coupled to the old flat single-level grouping (e.g. a test navigating `ExpansionTile` by category alone may need updating to also open the new sub-group level).

## Doc-sync

`MASTERFILE.md` (version bump, a short note near wherever sub-project 2's parental-controls section already lives, cross-referencing this as the deferred IA half of that feature, now built), `CHANGELOG.md`. No `MARKUP.html`/`scaffold/demo/shell.html` screen-entry changes needed — this restructures an existing screen's internals, it does not add a new one; the version/assertion-count fields still need to track per this repo's own `check-markup.mjs` rules (C1/C2/C7/D1/D2, and C4c if no screen's own `data-since`/`data-amended` changes — confirm which applies and handle it, matching the exact discipline the previous theme's own PR had to correct after initially missing it). As always: sync the claimed assertion count only after a real full `tools/verify.sh` run (or, if that's not locally reachable, an honest disclosure of what could and couldn't be verified, matching this repo's own established precedent) reports `0 failed` — never estimate it.

## Explicitly out of scope

- **Bulk actions** (a "hide all"/"show all" toggle) — confirmed genuinely new UI with zero precedent anywhere in this app. Considered and explicitly declined during scoping, not merely unmentioned.
- **`games_hub.dart`'s own finer 4-way section split** (Board & strategy / Together / On her own / Playing fair) — this spec's "More games" sub-group stays coarser, to avoid over-fragmenting a controls screen; revisit only if the coarser split proves insufficient in practice.
- **Any change to the underlying visibility/pacing data model, routes, or `activity_overrides.dart`'s own logic** — this is a presentation-layer rework of one screen; the real override mechanism built in sub-project 2 is untouched.
- **Themes #6-7** (motion-budget violations, Add Device wizard polish) — separate, already-queued future items.
