# Jokebook — design

**Date:** 2026-09-01 · **Status:** approved in conversation, built same evening under a
deadline; see "What v1 deliberately leaves out" · **MASTERFILE:** §9.2 · **Prohibitions:** P2

## What it is

A fixed, hand-written library of kid-friendly jokes — dad jokes, puns, wordplay, plain
silliness, knock-knocks — that she reaches for when she wants a quick one. She reads the
setup, taps for the punchline, asks for another. She can star the ones she likes and hold
one up to tell a parent.

## Decisions, and why

| Question | Decision | Why |
|---|---|---|
| Where does it live? | A new **"Just for laughs"** block in "Play together"'s `extraSections`, next to (not inside) the Checkers/Chess/Battleship cluster. No new ChildHome tile. | `extraSections` is the mechanism this codebase already built and hardware-verified for "one more catalogue reachable from the one door" (v0.49.66). A 4th Standard-tier tile would reopen the tile-count question v0.49.65/.66 just closed at 3. It is a general `List<Widget>?` slot, not a games-only one. |
| Curated or generated? | **Fixed, hand-written.** ~58 jokes at v1. | Every joke is read by a person before it ships. No unbounded supply means no safety sweep to build (Storyteller needs a whole screen for its). Adding jokes is a one-line edit to a list. |
| How is it organised by age? | **Invisible floor by her real age** — `forAge(age)` keeps jokes with `minAge <= age`, exactly `game_logic.dart`'s mechanic. No age-range picker. | She asked for a joke, not a settings screen. The floor is a *comprehension* floor, not a content rating: every joke is appropriate for every age; the floor only stops a joke she can't get yet (a spelling gag before she spells) from landing flat. Nothing is gated above 12; a teenager keeps the whole book. |
| How does she experience one? | **Setup, then tap to reveal the punchline.** One joke at a time, large. | The tap *is* the comic timing. A list with both lines visible has no beat. |
| Categories? | An internal `category` tag (dadJoke / pun / wordplay / silly / knockKnock) — **not surfaced** as a picker. | For whoever writes the list, so the mix stays honest (a test refuses any one category exceeding half the book). She doesn't need a genre menu. |
| Favourites? | Yes — star/unstar, a "Your starred jokes" shelf, newest first. In-memory for v1. | Same shape as `library_logic.dart`'s `Favourite`, deliberately **without** its `timesRead` — P2. Same honest-stub posture as Storyteller's own favourites (reset on restart, disclosed). |
| Share with a parent? | **"Tell Dad this one"** opens a sheet showing the whole joke large, with the copy *"Read it out on your next call, or hold your screen up to the camera."* Nothing is sent, and it never says anything is. | There is no child→guardian message send anywhere in this client yet — `showcase_screen.dart`'s own "she shows; he sees" is a disclosed UI-only stand-in for the same reason. Faking a send would teach her a message arrived when it didn't. Wiring a real send is a separate follow-up once that channel exists. |

## Shape

Mirrors the games catalogue's canonical-TS-plus-Dart-port pattern exactly:

- `packages/jokes/src/jokes.ts` — `CATALOGUE`, `forAge()`, `byId()`, `randomJoke(age, excludeId, pick)`,
  favourites (`star`/`unstar`/`isStarred`/`favouritesChildView`), and the same runtime
  `auditChildView()` P2 check `library.ts` keeps. `pick` is injectable so tests are deterministic.
- `packages/jokes/test/jokes.test.mjs` — registered in `package.json` (`build`, `test:jokes`, `test`)
  and `tools/verify.sh`.
- `scaffold/client/lib/joke_logic.dart` — 1:1 port. No Flutter import, same as `storyteller_logic.dart`.
- `scaffold/client/lib/jokebook_screen.dart` — `JokebookSection` (a `HubSection` + one `HubTile`, the
  same chrome `games_hub.dart` uses, so it reads as part of the same list) and `JokebookScreen`
  (ask card → joke card with hidden punchline → revealed card with star / another / tell-a-parent;
  starred shelf beneath, or beside on wide postures via `form_factors.dart`'s `columnsAt()`).
- Wired at both real call sites — `child_home.dart` and `guardian_more.dart` — as the second
  `extraSections` entry, after `MoreGamesSections`.
- Tests: `joke_logic_test.dart` (catalogue invariants, floor, no-repeat, favourites, P2 audit) and
  `jokebook_screen_test.dart` (the beat — punchline genuinely absent from the tree until tapped;
  the age floor across 25 draws at age 4; favourites shelf round-trip; a P2 vocabulary sweep at
  every stage; the tell-a-parent sheet never uses "sent/sending/delivered/message"; §8.1 no
  settings affordance; §8.4 48dp star; the responsive sweep at all four canonical widths).

`childAge` defaults to 7 at both call sites, the same default `GamePickerScreen` itself already
uses — this pass threads no new age source; when a real one is threaded into the picker, the
jokebook picks it up from the same place.

## What v1 deliberately leaves out

- A real send to a parent (see above).
- Persistence of favourites (same as Storyteller today).
- A "which parent" choice — `parentName` is passed through, defaulting to the same `'Dad'` demo
  value `MoreGamesSections` already uses.
- Sound, animation beyond the two fades already on Storyteller (§8.13 motion budget).
- A guardian-facing safety statement screen — there is nothing generated to make one about.
