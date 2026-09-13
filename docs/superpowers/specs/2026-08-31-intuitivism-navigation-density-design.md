# Intuitivism Pass — Sub-project 2: ChildHome tile hierarchy (navigation/density)

**Status:** approved, ready for implementation
**Scope:** ChildHome's own tile grid only — a 3-tier visual hierarchy (Hero/Featured/Standard) replacing the current flat, equal-weight 9-tile grid, plus fixing the screen's missing posture-awareness. The ad-hoc local-play games' navigation entry point is answered (where it goes, once built) but its actual wiring is explicitly deferred — see "Deferred" below. GuardianHome's own parallel grid, GamePickerScreen's card style, and the Hub list pattern are untouched — separate, later work if ever undertaken.

## Goal

Continues the user's original framing (sub-project 1's spec, §Goal): simplify/streamline so the app feels less "adult-minimalist"/"in your face" for a casual/first-time user — specifically the user's own kid, plus other parents/kids during demos. Refine, don't redesign. This sub-project targets ChildHome specifically because it is the single highest-traffic screen and currently presents 9 destinations as visually equal weight, with no signal for what matters most.

**A real, independently-found inconsistency motivating this work:** `child_home.dart` hardcodes `crossAxisCount: 2` and imports `form_factors.dart` nowhere — unlike `game_picker.dart`, which migrated onto the real posture system (`columnsAt()`) back in v0.49.17. This sub-project closes that gap as part of the same pass, rather than leaving ChildHome as the one remaining non-posture-aware primary screen.

## Premise correction

ChildHome renders **9 tiles today, not 8** (Homework, Play together, More games, My list, Messages, My day, Storyteller, Show & tell, More for you — `child_home.dart:97-188`). Any prior framing of "8 tiles" in this thread's own earlier discussion was a miscount, corrected here.

## Research method

A 5-agent Workflow (`wf_a47bcfa5-fd1`) produced this design: independent audits of (1) every real caller/test of `ChildHome`/`_Tile`, (2) MASTERFILE/CHANGELOG's actual stated importance/frequency signals for each of the 9 destinations, (3) binding §8.4/§8.11.1/§8.13/§2.1 constraints plus `form_factors.dart`'s real mechanics, and (4) the ad-hoc local-play games' navigation placement question — synthesized into one design. Every claim below traces to a file:line citation from that research; every design decision the research did NOT settle is marked **JUDGMENT CALL**.

## 1. Information architecture — 3-tier hierarchy

A strict binary primary/secondary split was rejected: the evidence itself is uneven (one tile has an unambiguous citation; several have weaker-but-real ones; several have none), and flattening that into one bucket would erase the one unambiguous signal.

### Tier 1 — Hero (1 tile, full-width band, not inside any GridView)

| Tile | Citation |
|---|---|
| **My day** | *"This single component replaces all timezone arithmetic. **Signature element.**"* — MASTERFILE.md:1728–1729. The only tile with unqualified "signature" language. |

### Tier 2 — Featured (larger cells, posture-aware grid, directly under Hero)

| Tile | Basis |
|---|---|
| **Show & tell** | MASTERFILE explicitly self-critiques treating it as secondary ("for most children it is the native register, and every previous section of this spec has treated it as a side feature" — MASTERFILE.md:4817–4819) and calls two of its modes "load-bearing" (MASTERFILE.md:4844–4848). |
| **Storyteller** | The only tile besides My day with an explicit frequency claim: *"A story every night for eighteen years draws 6,570 of them."* — MASTERFILE.md:4914–4915. |
| **Play together** | **JUDGMENT CALL** — no MASTERFILE citation. Elevated for disclosed structural reasons: anchors 8 independent game test files that tap it directly with no scroll step today, and fronts the largest single content library on the screen (10 wired games). |
| **Messages** | **JUDGMENT CALL** — no MASTERFILE priority citation (the closest text, CHANGELOG.md:266, is code-dependency language from a bug-fix entry, not a ranking). Elevated because it is the one tile carrying live, state-dependent content (the unread badge) — a UX argument, not a documented ranking. |

### Tier 3 — Standard (current size, smaller posture-aware grid, below Featured)

| Tile | Basis |
|---|---|
| **More games** | Not a judgment call — explicitly, textually framed as subordinate: *"the second door... alongside GamePickerScreen, not a replacement for it"* — CHANGELOG.md:6352–6353. |
| **Homework** | **JUDGMENT CALL** — §9.1's "job-to-be-done" language is scoped narrowly (protecting parent authority during homework help), not a screen-level priority claim. No elevation signal found. |
| **My list** | **JUDGMENT CALL** — zero centrality or frequency language anywhere in either document. |
| **More for you** | **JUDGMENT CALL** — mechanical v0.44.0 catch-all addition, same non-ranked origin as the tile set itself. Functions as a second overflow door, parallel to "More games." |

## 2. Ad-hoc local-play games — placement answered, wiring deferred

**Where (when built):** a new top-level ChildHome tile, "Right now, together," placed in the Featured tier once it exists — not folded into `GamePickerScreen`'s `extraSections` and not a `games_hub.dart` `HubSection`. Both alternatives were evidence-ruled-out: `extraSections` (PR #87) was purpose-built for injecting the existing *async* games-hub catalogue and has zero awareness the ad-hoc games (PR #85) exist — the two PRs share a common ancestor, not a merge relationship, and independently modified the same files (`game_navigation.dart`/`GamePickerScreen`/`games_hub.dart`). 3 of the 5 ad-hoc games (War, Piece It Together, Pictionary) cannot be started by one child alone; dropping them into either existing screen (both currently "tap and it opens instantly," no discovery/pairing step) would produce the exact silent-dead-end failure mode `game_picker.dart`'s own header says this codebase deliberately avoids.

**Decision, per the user's own explicit instruction ("continue in accordance with the order you recommend"):** **Option B — defer.** This redesign ships the 9-tile hierarchy now, without resolving the PR #85/#87 merge conflict. The "Right now, together" tile is added as its own fast-follow PR once that conflict is reconciled. This design document records where it goes (§1, Featured tier) so that follow-up work has a settled destination rather than reopening the question.

## 3. Visual/layout mechanics

No hero-tile/variable-span grid mechanism exists anywhere in this codebase (`SliverGridDelegateWithFixedCrossAxisCount` is the only delegate ever used, uniform-cell by construction; no `flutter_staggered_grid_view` or equivalent dependency). Building one would be disproportionate for a "refine, don't redesign" pass. Instead, compose three separate, each-internally-uniform layout regions in the existing `Column`:

```dart
Column
  Text('Hi $childName')
  if (presence != null) _PresenceCard(...)
  _HeroTile(...)        // NEW — full width, plain Container/Card, not inside a GridView
  _FeaturedGrid(...)    // NEW — GridView, ff.columnsAt(), larger cells
  _StandardGrid(...)    // the pre-existing GridView, minus the 5 promoted tiles
  if (sleepsUntilHandover != null) _Sleeps(...)   // UNCHANGED — still last
```

**Posture-awareness — reuse `form_factors.dart` verbatim, no new breakpoints**, the exact pattern `game_picker.dart:51,66-68` already uses:

```dart
final double textScale = MediaQuery.textScalerOf(context).scale(1);
final int cross = ff.columnsAt(
    ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale);
```

`child_home.dart` imports `form_factors.dart` zero times today — this closes that gap.

**No fixed pixel heights.** The current `mainAxisExtent: 108` literal is exactly the bug class §8.11.1 documents (`_GameCard`'s 182px fix, `reviewableAt()`'s fix — both real, shipped, previously-caught bugs). Every tier's height derives from `textScale`, clamped `1.0–1.6` (chosen more conservatively than `game_picker.dart`'s `1.0–2.0`, given the added Hero band's own height risk — see below):

| Region | Base height | Scaling |
|---|---|---|
| Hero | 140dp | `× textScale.clamp(1.0, 1.6)` |
| Featured | 132dp | `× textScale.clamp(1.0, 1.6)` |
| Standard | 84dp | `× textScale.clamp(1.0, 1.6)`; `_Tile`'s existing `BoxConstraints(minHeight: 64)` stays as the hard floor |

`_Tile` gains one optional flag, not a second widget class: `const _Tile({..., this.featured = false})` — bumps icon size 28→36 and label style `titleSmall`→`titleMedium`, keeps the shared `borderRadius.circular(14)` convention with `game_picker.dart`'s cards and `guardian_home.dart`'s `_GTile`.

**Fill color per tier (resolved here, not left to implementation — §4's constraint compliance requires no new use of her accent colour, so this decision must satisfy that on its own):** Standard keeps today's `colorScheme.primaryContainer` unchanged. Featured uses `colorScheme.secondaryContainer`. Hero uses `colorScheme.tertiaryContainer` — the most visually distinct of the three, matching its singular top-of-screen position. All three are standard Material `ColorScheme` tonal roles derived from the active theme (sub-project 1's `colorSchemeFor()`), never her own chosen accent — §8.6.2 is satisfied by construction, not by later care.

**The "sleeps until" fold-line risk (this screen's own two-time-repeated bug — once from `GridView.count`'s width-scaled aspect ratio, once from tile-count growth pushing it below the fold):** `SingleChildScrollView` (not `ListView`) is preserved unchanged, so the counter stays mounted in the element tree regardless of scroll position — `find.text` keeps passing. The real remaining risk is a child having to scroll further to *see* it; the `1.0–1.6` clamp (versus `game_picker.dart`'s `2.0`) bounds how much the Hero+Featured additions can push it down even at large accessibility text. Flagged honestly as risk-reduced, not eliminated — see §5's new regression test.

## 4. Constraint compliance

| Constraint | How this design satisfies it |
|---|---|
| **§8.4 — 64dp pre-reader targets, icon-only nav, icon+label always** | `_Tile`'s `minHeight: 64` unchanged for Standard tiles; Featured (132dp)/Hero (140dp) clear it by construction even unscaled. Every tier keeps icon + label — no tier drops to icon-only or text-only. |
| **§8.11.1/§8.11.7 (text-scale/posture — the section informally, sometimes incorrectly, cited elsewhere in this codebase as "§8.8")** | No fixed pixel height anywhere in the new layout; all three regions derive from `textScale`. Columns come only from `ff.columnsAt()`, never raw device width — directly avoids the exact bug class `_GameCard`/`reviewableAt()` already paid for. |
| **§8.13 — motion** | No autonomous entrance animation on any tier (nothing shimmers/pulses on load). Any press-in feedback reuses `game_picker.dart`'s existing `AnimatedScale` precedent (≤120ms, 0.96 scale, tap-driven) if added at all. No celebration/reward flourish anywhere. |
| **P2 — no engagement scoring shown to the child** | Tier assignment is fixed at build time from documented citations or disclosed judgment calls — never from per-child tap counts, play frequency, or analytics. No "most played" label, no tile that grows over time. **Binding note:** tier assignment must never later be wired to analytics without re-reviewing this constraint. |
| **§8.6.2 — her accent-colour placement budget (max 3, forbidden on structural chrome)** | Hierarchy is communicated by size/width/type-scale only — zero new use of her personal accent colour. If Featured/Hero get a distinct fill, it uses another Material `ColorScheme` tonal role (`secondaryContainer`/`tertiaryContainer`), never her chosen accent. Satisfied by non-consumption. |
| **P6/P5/P9** | Not triggered — no financial data, no analytics-derived ranking, no unsolicited archive resurfacing on the Hero tile (no live preview content added at all — see "Out of scope"). |

## 5. Test impact

**Existing tests requiring a defensive `ensureVisible` fix** (tile repositioning moves these off-screen at the default 800×600 test viewport, which none of them currently guard against):
- `test/widget_test.dart` — 6 tap-then-assert call sites (Homework, My list, Play together, Messages).
- 8 `test/game_*_test.dart` files that each tap `'Play together'` with no prior scroll step.

**Existing tests requiring re-verification, not code change:**
- `test/invariants_test.dart`'s 4-viewport responsive group (344×882, 673×841, 390×844, 1100×750) — must confirm `takeException()` stays null now that total content height changed materially.
- `test/invariants_test.dart`'s `FilledButton.first` height assertion — implementation must keep new tiers `InkWell`/`Container`-based, never `FilledButton`, so the presence card's Call button stays first in tree order.
- `test/child_home_live_test.dart` — no structural assertions, re-run to confirm unaffected.

**New tests:**
1. Multi-grid `crossAxisCount` assertion (two `GridView`s now exist — Featured and Standard — need distinguishing `Key`s: `childHomeFeaturedGrid`, `childHomeStandardGrid`) at the same 4 canonical sizes `game_picker_test.dart`/`invariants_test.dart` already use.
2. Text-scale regression test at 2.0× scale specifically at the 344px Fold-cover floor (~325px effective width) — the exact combination that broke `_GameCard`/`reviewableAt()` before. Assert no exception and that tile height actually grew (not pinned).
3. Hierarchy-is-real smoke test — `tester.getSize` comparison confirming Hero > Featured > Standard tile height, `Key('childHomeHero')` contains `find.text('My day')`.
4. P2-compliance smoke test — negative assertion for "most played"/numeric-rank strings on any tile, mirroring `game_picker.dart`'s own documented discipline.
5. Fold-line regression test extending the 4-viewport group — confirm `_Sleeps` stays reachable via `ensureVisible` without throwing at all 4 sizes, at both 1.0× and 2.0× text scale.

## 6. Doc-parity plan

- **MASTERFILE.md:** correct the stale "8 tiles" framing to 9 (independent of this redesign — a real pre-existing staleness the research surfaced), describe the real 3-tier structure, add a status paragraph tying the hierarchy back to its citations (My day's "signature element" now visually realized; Show & tell's self-critique now reflected in its Featured placement). Note §9.2's open-options paragraph on ad-hoc games placement is answered here (§2) though not yet wired.
- **CHANGELOG.md:** new entry — 3-tier grid replacing the flat 2-column grid; posture-awareness added (previously zero `form_factors` import, hardcoded `crossAxisCount: 2`); fixed `mainAxisExtent: 108` replaced with text-scale-derived heights; "sleeps until" position preserved with a new regression test given its two-prior-bug history; `ensureVisible` added defensively; stale "8 tiles" language corrected to 9.
- **MARKUP.html:** `child_home.dart` renders MARKUP screen `childHome` (§02) — a real tracked screen. Panel description updated to describe the new hierarchy; version-history row added.
- **demo/shell.html / DEMO.html:** the offline demo path renders the real `ChildHome` widget and inherits this change automatically at the widget level once rebuilt via `node demo/build.mjs`.
- **Version number:** determined at actual ship/PR-open time by real merge order (this session's established convention across parallel branches), not hardcoded in this document.

## 7. Explicitly out of scope

- `GuardianHome`'s own parallel grid (has its own `ff.columnsAt()` call, an explicit "floor of 2" comment) — untouched.
- `GamePickerScreen`'s card style/animation, `games_hub.dart`'s `HubSection` list pattern — untouched; only `columnsAt()`'s call *pattern* is reused as precedent, not the visual card design.
- The `extraSections` mechanism and the PR #85/#87 merge conflict itself — not resolved here; flagged in §2 as separate, still-open work.
- No new data wiring — `ChildHome`'s constructor signature (`childName`, `presence`, `sleepsUntilHandover`, `unreadCount`, plus the four optional live-wiring params) is unchanged. No live preview content added to the Hero tile.
- `_PresenceCard`, the Call-Dad flow, the "Hi $childName" header — unchanged, sit above the new hierarchy exactly as today.
- `KioskShell`'s `_EscalationTrigger` overlay (bottom-right corner) — untouched; the Hero tile's position at the top of the column means no interaction occurs with it either way.
- No accent-colour/theming system changes — §8.6.2's budget is respected by non-use, not by expanding it.
- `_Sleeps`'s own bespoke typography — unchanged; only its position in total scroll height is affected.
- No new animation package or dependency.
