# Intuitivism Pass — Sub-project 3c: Fold5 cover-screen and tabletop layout

**Status:** approved, ready for implementation
**Scope:** genuine posture-specific layout behavior for `Posture.foldCover` and `Posture.foldTabletop` (`form_factors.dart`) — a stripped-down single-purpose view on the cover screen, and a deliberate above/below-the-hinge content split in tabletop posture, via a new shared `TabletopSplit`/`CoverCollapse` widget pair. Real hinge-angle sensing (Android's `WindowManager` `FoldingFeature` API) and any new hinge-aware *game* content are explicitly deferred to sub-project 4 — this pass keeps using `postureFor()`'s existing width/height heuristic, though see "A lighter-weight step" below for a real, smaller improvement to that heuristic worth considering inside this same pass.

## Goal

Continues the original framing for this whole pass, which named "the Fold5" specifically, not just "wide vs. narrow." Both shipped sub-projects so far have only ever varied *column count* by width — a tablet-shaped concern. Neither has touched what a fold's two distinct extra postures (closed to a phone-narrow cover screen; half-open to a short, wide tabletop) could uniquely offer. Today, `Posture.foldCover` (≤344px logical, per `form_factors.dart`'s own `FormFactor` entry) just receives `columnsAt()`'s ordinary 1-column output — the full layout squeezed narrow, not redesigned narrow. `Posture.foldTabletop` (short + wide + landscape, hinge horizontal) receives a handful of scattered, minor per-screen tweaks today (`game_connect4.dart`'s padding adjustment is the clearest example) rather than a considered use of the two halves the hinge actually creates.

## Part 1 — Cover-screen: one thing, not everything shrunk

**Principle:** at `foldCover` width, a screen shows its single most load-bearing piece of information or action, not a compressed version of its full layout. This needs a per-screen judgment call, not a generic mechanism — scoped here to the two screens this pass actually touches (`ChildHome`, `GuardianHome`), with other screens left at today's behavior (their existing 1-column `columnsAt()` fallback) until a later pass considers them.

- **`ChildHome` at `foldCover`:** show only the day ribbon/presence area (`_PresenceCard`, if present) and the Hero tile (My day) — the Featured and Standard grids collapse into a single "More" affordance that opens the full list on its own screen, rather than stacking all 9 destinations narrow. This is the same shape `guardian_more.dart`'s own "More" tile already uses elsewhere in this codebase — reused, not invented.
- **`GuardianHome` at `foldCover`:** show the ribbon (unchanged, per sub-project 3b) and the Hero tile (Message banking) only — same collapse-to-"More" treatment for Featured/Standard.

**Detection:** the shared `CoverCollapse` widget (see Part 2's `TabletopSplit` for the identical shape) derives `postureFor(viewport) == Posture.foldCover` internally via its own `LayoutBuilder` — both screens already run a `LayoutBuilder`+`columnsAt()` computation at this exact point, so this adds one more read of the same `Posture`, not a new measurement pass.

## Part 2 — Tabletop: the hinge as a real divider

**Principle:** at `foldTabletop` posture, split content deliberately across the two halves the physical hinge creates — content/viewing above, controls/actions below — rather than rendering the same single-column layout narrower.

**Scoped to four screens for this pass**, chosen as the clearest candidates for a natural above/below split (a viewing area and a distinct action area already exist conceptually in each):

- **`storyteller_screen.dart`:** the story text/illustration area above the hinge; the reveal/next/star controls below it — the screen already has this exact conceptual split (content card, then action row); tabletop posture makes it a real physical split instead of a scroll.
- **`showcase_screen.dart`** ("Show & tell"): the camera preview/captured-photo area above the hinge; the send/retake controls below it — same shape.
- **`homework_screen.dart`:** the photographed worksheet/hint area above the hinge; the reveal-hint/next-problem controls below it — same viewing/acting split as Storyteller.
- **`call_screen.dart`:** video above the hinge, call controls (mute, end, etc.) below it — arguably the single most natural real-world tabletop use case on a Fold5: propped up hands-free on a table during a call, which a phone-shaped single column actively fights against today.

**Detection:** the same `postureFor(viewport) == Posture.foldTabletop` check, threaded into each screen's existing layout decision the same way `game_connect4.dart`'s own `outerPad` conditional already does it — this pass's screens follow that established precedent rather than inventing a second way to check the same thing.

**A shared `TabletopSplit` widget (new `client/lib/tabletop_split.dart`), not four separate hand-rolled splits.** With four consumers rather than the two this pass originally scoped, sub-project 2's own "small, deliberate duplication beats a shared abstraction for two call sites" reasoning no longer holds — four near-identical `Column`s split at the same posture boundary is exactly the kind of drift risk a shared widget prevents.

```dart
class TabletopSplit extends StatelessWidget {
  const TabletopSplit({super.key, required this.viewing, required this.controls});
  final Widget viewing;   // above the hinge
  final Widget controls;  // below the hinge
  // Renders viewing/controls as a plain 50/50 Column split when the
  // ambient postureFor() (via a LayoutBuilder this widget owns internally,
  // same pattern every other posture-aware screen already uses) reads
  // foldTabletop; renders viewing above controls in the screen's EXISTING
  // single-column arrangement otherwise -- this widget is a no-op shape
  // change outside foldTabletop, never a second layout to maintain for
  // every other posture.
}
```

Each of the four screens supplies its own `viewing`/`controls` widgets unchanged from what it renders today — `TabletopSplit` only decides HOW to arrange them, never what they contain, keeping each screen's own real content logic untouched. A matching `CoverCollapse(full: Widget, collapsed: Widget)` covers Part 1's cover-screen behavior with the identical shape, used by `ChildHome`/`GuardianHome`.

## A lighter-weight step toward real hinge detection, considered and left for the plan to decide

Android's Jetpack `WindowManager` exposes a simple `isTableTopPosture` convenience boolean — real hinge state, well short of sub-project 4's full angle-based `FoldingFeature` data. Wiring just that boolean into `postureFor()`'s `foldTabletop` branch (as a real signal alongside, not instead of, the existing width/height heuristic — a device that reports `isTableTopPosture` confirms the guess; one that doesn't report it at all, e.g. the tablet, simply falls back to the heuristic exactly as today) would make this pass's detection genuinely accurate on the one device that can report it, without taking on sub-project 4's full scope. This is a real, bounded option worth a look during the implementation plan, not a requirement of this spec — the width/height heuristic this spec already describes is a reasonable, already-proven-elsewhere v1 on its own.

## Motion & P2 compliance

No animation change in either part — the cover-screen collapse and the tabletop split are both structural (which widgets exist, not how they move), so §8.13's motion budget isn't touched by this pass at all. P2 unaffected — no new content, scores, or counts introduced by either layout change.

## Testing

`TabletopSplit`/`CoverCollapse` each get their own small unit test suite, independent of any screen: the 50/50 split (or collapsed/full swap) renders correctly at the target posture, and the widget is a byte-for-byte no-op (renders `viewing`-then-`controls` in the caller's own existing single-column shape) at every other posture — proven directly for the shared widget once, rather than re-proven per screen. Real widget tests per screen, using `form_factors_test.dart`'s own established pattern of pumping a widget at an exact `Viewport` size: `ChildHome`/`GuardianHome` at `foldCover`'s exact 344×841 test dimensions (the same real coordinates this codebase already tests against for the wrap-overflow regression) show only ribbon+Hero+More, never the full Featured/Standard grids; `storyteller_screen.dart`/`showcase_screen.dart`/`homework_screen.dart`/`call_screen.dart` at `foldTabletop`'s dimensions show the above/below split with both halves reachable (no dead-zone under the hinge itself, since Flutter has no way to know exactly where the physical hinge sits within the reported window without the real `FoldingFeature` API this pass deliberately doesn't add yet — noted as an honest limitation, not silently assumed away). A regression test confirming every OTHER posture's behavior on all six screens (the four tabletop screens plus ChildHome/GuardianHome's own cover-screen behavior) is byte-for-byte unchanged.

## Doc-sync

`MASTERFILE.md` (version bump, a status note under the existing device-adaptive/form-factor discussion), `CHANGELOG.md`, `MARKUP.html` (the six touched screens' `data-amended` fields), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- Real hinge-angle sensing (`WindowManager`/`FoldingFeature`) — `postureFor()`'s existing width/height heuristic is unchanged (aside from the OPTIONAL `isTableTopPosture` boolean noted above, left for the plan to decide, not committed here); a real angle sensor is sub-project 4's concern, not this one's.
- Any new hinge-aware game content, and the tablet-parity requirement for it — sub-project 4, its own scoping pass, not designed here (see the sub-project 4 scope note from this brainstorm).
- Cover-screen or tabletop treatment for any screen beyond the six named above (`ChildHome`, `GuardianHome` for cover-screen; `storyteller_screen.dart`, `showcase_screen.dart`, `homework_screen.dart`, `call_screen.dart` for tabletop) — every other screen keeps today's generic `columnsAt()` fallback until a later pass considers it.
- `game_connect4.dart`'s own existing tabletop padding tweak — untouched, already shipped, not revisited or migrated onto `TabletopSplit` here.
