# Intuitivism Pass — Sub-project 3c: Fold5 cover-screen and tabletop layout

**Status:** approved, ready for implementation
**Scope:** genuine posture-specific layout behavior for `Posture.foldCover` and `Posture.foldTabletop` (`form_factors.dart`) — a stripped-down single-purpose view on the cover screen, and a deliberate above/below-the-hinge content split in tabletop posture. Real hinge-angle sensing (Android's `WindowManager` `FoldingFeature` API) and any new hinge-aware *game* content are explicitly deferred to sub-project 4 — this pass keeps using `postureFor()`'s existing width/height heuristic, unchanged.

## Goal

Continues the original framing for this whole pass, which named "the Fold5" specifically, not just "wide vs. narrow." Both shipped sub-projects so far have only ever varied *column count* by width — a tablet-shaped concern. Neither has touched what a fold's two distinct extra postures (closed to a phone-narrow cover screen; half-open to a short, wide tabletop) could uniquely offer. Today, `Posture.foldCover` (≤344px logical, per `form_factors.dart`'s own `FormFactor` entry) just receives `columnsAt()`'s ordinary 1-column output — the full layout squeezed narrow, not redesigned narrow. `Posture.foldTabletop` (short + wide + landscape, hinge horizontal) receives a handful of scattered, minor per-screen tweaks today (`game_connect4.dart`'s padding adjustment is the clearest example) rather than a considered use of the two halves the hinge actually creates.

## Part 1 — Cover-screen: one thing, not everything shrunk

**Principle:** at `foldCover` width, a screen shows its single most load-bearing piece of information or action, not a compressed version of its full layout. This needs a per-screen judgment call, not a generic mechanism — scoped here to the two screens this pass actually touches (`ChildHome`, `GuardianHome`), with other screens left at today's behavior (their existing 1-column `columnsAt()` fallback) until a later pass considers them.

- **`ChildHome` at `foldCover`:** show only the day ribbon/presence area (`_PresenceCard`, if present) and the Hero tile (My day) — the Featured and Standard grids collapse into a single "More" affordance that opens the full list on its own screen, rather than stacking all 9 destinations narrow. This is the same shape `guardian_more.dart`'s own "More" tile already uses elsewhere in this codebase — reused, not invented.
- **`GuardianHome` at `foldCover`:** show the ribbon (unchanged, per sub-project 3b) and the Hero tile (Message banking) only — same collapse-to-"More" treatment for Featured/Standard.

**Detection:** a new `bool coverScreen` derived from `postureFor(viewport) == Posture.foldCover`, computed once per `LayoutBuilder` pass in each screen's existing `build()` (both screens already run a `LayoutBuilder`+`columnsAt()` computation at this exact point — this adds one more read of the same `Posture`, not a new measurement pass).

## Part 2 — Tabletop: the hinge as a real divider

**Principle:** at `foldTabletop` posture, split content deliberately across the two halves the physical hinge creates — content/viewing above, controls/actions below — rather than rendering the same single-column layout narrower.

**Scoped to two screens for this pass**, chosen as the clearest candidates for a natural above/below split (a viewing area and a distinct action area already exist conceptually in both):

- **`storyteller_screen.dart`:** the story text/illustration area above the hinge; the reveal/next/star controls below it — the screen already has this exact conceptual split (content card, then action row); tabletop posture makes it a real physical split instead of a scroll.
- **`showcase_screen.dart`** ("Show & tell"): the camera preview/captured-photo area above the hinge; the send/retake controls below it — same shape.

**Detection:** the same `postureFor(viewport) == Posture.foldTabletop` check, threaded into each screen's existing layout decision the same way `game_connect4.dart`'s own `outerPad` conditional already does it — this pass's two screens follow that established precedent rather than inventing a second way to check the same thing.

**Explicitly not a new layout primitive:** no new shared "TabletopSplit" widget is introduced in this pass — each of the two screens implements its own above/below `Column` split directly, matching this codebase's stated preference (sub-project 2's own reasoning) for "a small, deliberate duplication" over a shared abstraction serving only two call sites. Revisit as a shared widget only if a third screen needs the same shape later.

## Motion & P2 compliance

No animation change in either part — the cover-screen collapse and the tabletop split are both structural (which widgets exist, not how they move), so §8.13's motion budget isn't touched by this pass at all. P2 unaffected — no new content, scores, or counts introduced by either layout change.

## Testing

Real widget tests, using `form_factors_test.dart`'s own established pattern of pumping a widget at an exact `Viewport` size: `ChildHome`/`GuardianHome` at `foldCover`'s exact 344×841 test dimensions (the same real coordinates this codebase already tests against for the wrap-overflow regression) show only ribbon+Hero+More, never the full Featured/Standard grids; `storyteller_screen.dart`/`showcase_screen.dart` at `foldTabletop`'s dimensions show the above/below split with both halves reachable (no dead-zone under the hinge itself, since Flutter has no way to know exactly where the physical hinge sits within the reported window without the real `FoldingFeature` API this pass deliberately doesn't add yet — noted as an honest limitation, not silently assumed away). A regression test confirming every OTHER posture's behavior on all four screens is byte-for-byte unchanged.

## Doc-sync

`MASTERFILE.md` (version bump, a status note under the existing device-adaptive/form-factor discussion), `CHANGELOG.md`, `MARKUP.html` (the four touched screens' `data-amended` fields), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- Real hinge-angle sensing (`WindowManager`/`FoldingFeature`) — `postureFor()`'s existing width/height heuristic is unchanged; a real angle sensor is sub-project 4's concern, not this one's.
- Any new hinge-aware game content, and the tablet-parity requirement for it — sub-project 4, its own scoping pass, not designed here (see the sub-project 4 scope note from this brainstorm).
- Cover-screen or tabletop treatment for any screen beyond the four named above (`ChildHome`, `GuardianHome`, `storyteller_screen.dart`, `showcase_screen.dart`) — every other screen keeps today's generic `columnsAt()` fallback until a later pass considers it.
- `game_connect4.dart`'s own existing tabletop padding tweak — untouched, already shipped, not revisited here.
