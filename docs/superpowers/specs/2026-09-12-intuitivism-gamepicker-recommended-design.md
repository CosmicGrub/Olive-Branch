# Intuitivism Pass — Sub-project 3a: GamePickerScreen's Recommended tier

**Status:** approved, ready for implementation
**Scope:** a guardian-curated favorites mechanism, a complementary age-unlock signal, a "surprise me" random pick, and a new `Recommended` row on `GamePickerScreen` fed by the first two. Play-count/recency-based recommendation is an explicit, deferred v2 — not designed here.

## Goal

Continues the user's original framing (sub-project 1's spec, §Goal): simplify/streamline so the app feels less "adult-minimalist" for a casual/first-time user. `GamePickerScreen` is the one high-traffic screen sub-project 2 explicitly deferred ("only `columnsAt()`'s call *pattern* is reused as precedent, not the visual card design"). Unlike `ChildHome`, this screen has no natural "hero" — it's a flat catalogue, not a daily-status surface — so this pass doesn't attempt a Hero/Featured/Standard hierarchy here. Instead it adds the things a flat catalogue is actually missing: a way for it to feel personal rather than exhaustive, and a way to feel unstuck when she doesn't know what she wants.

## Why favorites and age-unlock, not play-history — the decision and its reasoning

Three signals were considered for what "Recommended" means:

1. **Age-appropriateness alone** (`forAge()`/`minAge`, already real, zero new code) — rejected as the *primary* signal: it doesn't recommend anything new. A game is either in her unlocked pool or it isn't; boxing the same pool differently isn't personalization.
2. **Recently/frequently played** — real personalization, but needs a new `game_play_log`-shaped table, a route to record plays, and a query for "recent." Bigger lift, and it edges toward MASTERFILE §2.1 P2 ("no scores, streaks, ranks shown to the child") in spirit even if no number is ever printed — `packages/storyteller/src/storyteller.ts`'s reread-nudge feature (CHANGELOG v0.49.68) proves this tension is solvable, but it's still a real backend investment for a v1.
3. **Guardian-curated favorites** (chosen) — a guardian actively picks games for her, the same way `packages/jokes/src/jokes.ts`'s `star`/`unstar`/`favouritesChildView()` already works for jokes. Nothing about *her own play behavior* is measured or stored, so P2 is satisfied by construction, not by later care. Reuses an already-shipped, already-tested pattern instead of inventing tracking.

**A fourth signal, added alongside favorites rather than instead of it: age-unlock.** When her age crosses a game's `minAge`, that game is genuinely new to her — derivable purely from `child.birth_date` and `games.ts`'s existing `minAge` field, with no usage tracking of any kind. It satisfies P2 the identical way favorites does (nothing about her behavior is measured), and it means the Recommended row has real content even for a guardian who hasn't favorited anything yet, rather than being empty until she does. The two signals are complementary, not competing: favorites fill the row first (an intentional guardian choice deserves top billing), age-unlock fills any remaining slots.

Recency-based recommendation is real, deferred v2 work — noted here so it isn't silently forgotten, not designed.

## Architecture

**New pure engine (`packages/games/src/favorites.ts`), mirroring `jokes.ts`'s shape exactly** rather than a new one invented from scratch:

```ts
export function star(current: string[], kind: string): string[]   // idempotent, no duplicate
export function unstar(current: string[], kind: string): string[]
export function favouritesFor(all: GameMeta[], starred: string[]): GameMeta[]
  // filters to starred kinds that still exist in CATALOGUE (a game removed
  // from the catalogue silently drops from favourites, never a dangling ref)
```

**Age-unlock, in the same engine file** — a pure function of her current age against `minAge`, needing a reference point for "recently" so it doesn't perpetually recommend her whole unlocked pool:

```ts
export function newlyUnlocked(
  all: GameMeta[], age: number, ageAtLastOpen: number | null,
): GameMeta[]
  // games where minAge <= age but minAge > (ageAtLastOpen ?? age) --
  // i.e. crossed the threshold since she last opened this screen. A null
  // ageAtLastOpen (first-ever open) returns nothing -- there is no "since
  // last time" for a first visit, and showing her entire starting catalogue
  // as "new" would be a lie, not a recommendation. `ageAtLastOpen` is a
  // simple, small piece of state to persist (see Persistence below) --
  // NOT a play-history log; it records when this SCREEN was last viewed,
  // nothing about which games were played or how often.
```

**"Surprise me,"** reusing `jokes.ts`'s own `randomJoke(age, excludeId, pick)` shape verbatim rather than inventing a second randomization convention:

```ts
export function randomGame(
  all: GameMeta[], age: number, excludeKind: string | null, pick: number,
): GameMeta | null
  // forAge(age) pool, excludeKind never repeats her last pick, pick is
  // injectable so tests are deterministic -- identical contract to
  // randomJoke(), same reasoning, same file's own header can say so.
```

**Persistence:** a new `guardian_game_favorite` table (`guardian_id`, `kind`, `created_at`), RLS-scoped the same `..._no_child` shape every guardian-only preference table in this schema already uses (`medication`/`care_note`/etc.) — a child session never reads or writes this table; her device receives the resolved list the same way it receives any other guardian-set preference. New `GET`/`PUT /v1/children/:childId/game-favorites` routes, guardian-write/child-read, matching the theme-preference route's own shape (sub-project 1).

**`ageAtLastOpen` persistence, for the age-unlock signal:** one nullable integer column on `child` (or a small per-child preference row, whichever this migration's own review finds matches the schema's existing convention better — same open choice sub-project 1's spec left for its own theme columns). Written by the CHILD's own session on `GamePickerScreen` open (it's her age, her screen visit — no guardian involvement needed to record it, unlike favorites), read by the same route that resolves the Recommended row. This is the entire extent of new state age-unlock needs — one integer, overwritten on every open, never a log or history of opens.

**`GamePickerScreen` gains four new optional constructor params**, not a rewrite into a self-fetching live screen — matching this screen's existing `StatelessWidget` shape (`childName`/`childAge`/`onPlay`/`extraSections` are all plain data today, no live params at all):

```dart
final Set<String>? favoriteKinds;       // null = no live session; omit the row entirely
final int? ageAtLastOpen;               // null = first-ever open, or no live session
final void Function(String kind, bool nowFavorited)? onToggleFavorite;  // null = read-only view
final GameMeta? Function()? onSurpriseMe;  // null = no surprise-me button at all
```

A `Recommended` row renders above the existing catalogue grid **whenever `favoriteKinds` is non-null** and the combined favorites + `newlyUnlocked()` result is non-empty — favorites listed first, age-unlock games filling any remaining slots, each game appearing at most once even if it qualifies both ways. An empty combined result means the row doesn't render at all (this app's established "honest absence over empty-state noise" convention — see `careNotesFor()`'s own no-notes handling, `availability_screen.dart`'s own "Set a window" per-day pattern). A **"Surprise me" button** sits beside the row's own header, visible whenever `onSurpriseMe` is non-null (both child and guardian sessions — unlike favoriting, there's nothing guardian-only about asking for a random pick), calling `randomGame()` and navigating straight to the result via the existing `onPlay` callback. The existing catalogue grid below is completely unchanged — same organization, same cards, same order.

**Where favoriting happens:** the star toggle only appears on `_GameCard` **when `onToggleFavorite` is non-null** — i.e., only when a guardian, not the child, opened this screen. `guardian_more.dart`'s existing `_open(context, GamePickerScreen(...))` call site (the "Play together" tile, browsing on the child's behalf) is the natural place to wire `onToggleFavorite` in. `child_home.dart`'s own call site wires `favoriteKinds`/`ageAtLastOpen`/`onSurpriseMe` (so her own Recommended row and Surprise-me button are real) but never `onToggleFavorite` — she sees the *result* of a favorite, and can ask for a surprise, but the favoriting mechanism itself stays guardian-only.

## `_GameCard` change

`_GameCard` is already `StatefulWidget` (press-in animation state). Add a star `IconButton` in its top-right corner, visible only per the `onToggleFavorite != null` rule above — filled star when `meta.kind` is in `favoriteKinds`, outline otherwise. Tapping it calls `onToggleFavorite` and does **not** await a network round-trip inline (optimistic local toggle, same posture `_MyWindow`'s own note-editing already takes) — the caller's own live wrapper is responsible for persisting and for reconciling on a failed write, same shape as every other guardian-write screen in this codebase.

## Motion & P2 compliance

Star toggle is a discrete, finger-driven state change — no animation beyond the icon's own fill swap (instant, not a consequence-motion candidate per §8.13's own "nothing shimmers/pulses" rule already established for ChildHome). The Recommended row itself performs one clean fade if it starts empty and gains its first entry, then holds still. "Surprise me" navigates immediately on tap — no spin/shuffle animation pretending to "search," which would be exactly the kind of looping/autonomous motion §8.13 already rules out elsewhere. Nothing here counts, ranks, or scores (P2) — favoriting is binary per game, age-unlock is a one-time crossing with no count of how many times, no order-of-favoriting or count ever surfaces to her.

## Testing

Pure engine tests (`packages/games/test/favorites.test.mjs`): star/unstar idempotency, `favouritesFor()` dropping a stale kind cleanly, no duplicate entries, `newlyUnlocked()` correctly gated on the age-crossed-since-last-open rule (including the null-`ageAtLastOpen` "nothing on first visit" case), `randomGame()` never repeating `excludeKind` across many draws (same two-hundred-draw shape `jokes.test.mjs` already proves for `randomJoke()`). Real-DB route tests mirroring the theme-preference suite's depth: guardian writes favorites, child reads-but-cannot-write, child writes her own `ageAtLastOpen`, unset resolves to an empty (not error) list. Widget tests: the Recommended row renders with favorites alone, age-unlock alone, both combined with no duplicates, and neither (row absent); the star only renders with `onToggleFavorite` set; the Surprise-me button only renders with `onSurpriseMe` set; a child-opened `GamePickerScreen` shows the row and the button but never a star.

## Doc-sync

`MASTERFILE.md` (a new small note under the games/§9.2 area, plus the version-history table), `CHANGELOG.md`, `MARKUP.html` (the `gamePicker` screen entry's own `data-amended`), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- Recency/frequency-based recommendations — real, deferred v2, needs its own scoping pass (a play-log schema, a route, a query — and its own P2 review).
- Reordering or restyling the existing catalogue grid below the Recommended row — untouched.
- A guardian-facing "games I've favorited for her" management screen beyond the star toggle itself on `GamePickerScreen` — the toggle IS the management UI for this pass; a dedicated list screen is a possible later refinement, not designed here.
- **Unifying jokes' and games' favorite mechanisms** under one generic `guardian_favorite(kind_namespace, kind)` table instead of two near-identical ones — real, genuine architectural cleanup, but jokes' own mechanism already shipped and works; touching it now would be scope creep on a design pass rather than a fix for an actual problem. Noted for a future consideration, not designed or committed to here.
