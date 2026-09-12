# Intuitivism Pass — Sub-project 3a: GamePickerScreen's Recommended tier

**Status:** approved, ready for implementation
**Scope:** a guardian-curated favorites mechanism and a new `Recommended` row on `GamePickerScreen`, surfacing them above the existing catalogue grid. Play-count/recency-based recommendation is an explicit, deferred v2 — not designed here.

## Goal

Continues the user's original framing (sub-project 1's spec, §Goal): simplify/streamline so the app feels less "adult-minimalist" for a casual/first-time user. `GamePickerScreen` is the one high-traffic screen sub-project 2 explicitly deferred ("only `columnsAt()`'s call *pattern* is reused as precedent, not the visual card design"). Unlike `ChildHome`, this screen has no natural "hero" — it's a flat catalogue, not a daily-status surface — so this pass doesn't attempt a Hero/Featured/Standard hierarchy here. Instead it adds the one thing a flat catalogue is actually missing: a way for it to feel personal rather than exhaustive.

## Why favorites, not play-history — the decision and its reasoning

Three signals were considered for what "Recommended" means:

1. **Age-appropriateness alone** (`forAge()`/`minAge`, already real, zero new code) — rejected as the *primary* signal: it doesn't recommend anything new. A game is either in her unlocked pool or it isn't; boxing the same pool differently isn't personalization.
2. **Recently/frequently played** — real personalization, but needs a new `game_play_log`-shaped table, a route to record plays, and a query for "recent." Bigger lift, and it edges toward MASTERFILE §2.1 P2 ("no scores, streaks, ranks shown to the child") in spirit even if no number is ever printed — `packages/storyteller/src/storyteller.ts`'s reread-nudge feature (CHANGELOG v0.49.68) proves this tension is solvable, but it's still a real backend investment for a v1.
3. **Guardian-curated favorites** (chosen) — a guardian actively picks games for her, the same way `packages/jokes/src/jokes.ts`'s `star`/`unstar`/`favouritesChildView()` already works for jokes. Nothing about *her own play behavior* is measured or stored, so P2 is satisfied by construction, not by later care. Reuses an already-shipped, already-tested pattern instead of inventing tracking.

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

**Persistence:** a new `guardian_game_favorite` table (`guardian_id`, `kind`, `created_at`), RLS-scoped the same `..._no_child` shape every guardian-only preference table in this schema already uses (`medication`/`care_note`/etc.) — a child session never reads or writes this table; her device receives the resolved list the same way it receives any other guardian-set preference. New `GET`/`PUT /v1/children/:childId/game-favorites` routes, guardian-write/child-read, matching the theme-preference route's own shape (sub-project 1).

**`GamePickerScreen` gains two new optional constructor params**, not a rewrite into a self-fetching live screen — matching this screen's existing `StatelessWidget` shape (`childName`/`childAge`/`onPlay`/`extraSections` are all plain data today, no live params at all):

```dart
final Set<String>? favoriteKinds;   // null = no live session; omit the row entirely
final void Function(String kind, bool nowFavorited)? onToggleFavorite;  // null = read-only view
```

A `Recommended` row renders above the existing catalogue grid **only when `favoriteKinds` is non-null and non-empty** — an empty or absent favorites list means the row doesn't render at all (this app's established "honest absence over empty-state noise" convention — see `careNotesFor()`'s own no-notes handling, `availability_screen.dart`'s own "Set a window" per-day pattern). The existing catalogue grid below is completely unchanged — same organization, same cards, same order.

**Where favoriting happens:** the star toggle only appears on `_GameCard` **when `onToggleFavorite` is non-null** — i.e., only when a guardian, not the child, opened this screen. `guardian_more.dart`'s existing `_open(context, GamePickerScreen(...))` call site (the "Play together" tile, browsing on the child's behalf) is the natural place to wire `favoriteKinds`/`onToggleFavorite` in; `child_home.dart`'s own call site passes neither, so her own view never shows a star at all — she sees the *result* of a favorite (the Recommended row), never the mechanism that created it.

## `_GameCard` change

`_GameCard` is already `StatefulWidget` (press-in animation state). Add a star `IconButton` in its top-right corner, visible only per the `onToggleFavorite != null` rule above — filled star when `meta.kind` is in `favoriteKinds`, outline otherwise. Tapping it calls `onToggleFavorite` and does **not** await a network round-trip inline (optimistic local toggle, same posture `_MyWindow`'s own note-editing already takes) — the caller's own live wrapper is responsible for persisting and for reconciling on a failed write, same shape as every other guardian-write screen in this codebase.

## Motion & P2 compliance

Star toggle is a discrete, finger-driven state change — no animation beyond the icon's own fill swap (instant, not a consequence-motion candidate per §8.13's own "nothing shimmers/pulses" rule already established for ChildHome). The Recommended row itself performs one clean fade if it starts empty and gains its first favorite, then holds still. Nothing here counts, ranks, or scores (P2) — favoriting is binary per game, no order-of-favoriting or count ever surfaces to her.

## Testing

Pure engine tests (`packages/games/test/favorites.test.mjs`): star/unstar idempotency, `favouritesFor()` dropping a stale kind cleanly, no duplicate entries. Real-DB route tests mirroring the theme-preference suite's depth: guardian writes, child reads-but-cannot-write, unset resolves to an empty (not error) list. Widget tests: the Recommended row renders only with a non-empty `favoriteKinds`, the star only renders with `onToggleFavorite` set, a child-opened `GamePickerScreen` (both null) shows neither — proven directly, not inferred.

## Doc-sync

`MASTERFILE.md` (a new small note under the games/§9.2 area, plus the version-history table), `CHANGELOG.md`, `MARKUP.html` (the `gamePicker` screen entry's own `data-amended`), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- Recency/frequency-based recommendations — real, deferred v2, needs its own scoping pass (a play-log schema, a route, a query — and its own P2 review).
- Reordering or restyling the existing catalogue grid below the Recommended row — untouched.
- A guardian-facing "games I've favorited for her" management screen beyond the star toggle itself on `GamePickerScreen` — the toggle IS the management UI for this pass; a dedicated list screen is a possible later refinement, not designed here.
