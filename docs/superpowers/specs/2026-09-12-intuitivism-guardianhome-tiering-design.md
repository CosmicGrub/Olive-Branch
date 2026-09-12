# Intuitivism Pass — Sub-project 3b: GuardianHome warmth/tiering pass

**Status:** approved, ready for implementation
**Scope:** applying ChildHome's Hero/Featured/Standard tile hierarchy (sub-project 2) to `guardian_home.dart`'s existing 11-tile grid. No change to column-count/width scaling — confirmed already correct (`.clamp(2, 3)`, PR #43, predates this whole pass) — this is a visual-hierarchy pass, not a responsive-layout fix.

## Goal

`GuardianHome` never got the "less adult-minimalist" treatment `ChildHome` did — its 11 tiles (Message banking, Emergency card, Handover notes, Exchange, Expenses, Availability, Send-time guard, Meds & care, Morning briefing, Care note, More) render as flat, visually-equal cards today, the same symptom sub-project 2's own spec named for ChildHome's pre-hierarchy state. Sub-project 2's "explicitly out of scope" list named this file directly ("has its own `columnsAt()` call, an explicit 'floor of 2' comment — untouched") — investigating that comment for this spec found the column-scaling itself is already correct (a real floor of 2 AND a real ceiling of 3, not a hardcoded 2); the actual gap is purely visual hierarchy, not device-adaptive layout.

## Tier assignment

Based directly on the user's own answer about which tiles feel most urgent/frequent as a real guardian:

| Tier | Tiles | Fill color |
|---|---|---|
| **Hero** | Message banking | `colorScheme.tertiaryContainer` |
| **Featured** | Availability, Send-time guard, Meds & care, Emergency card | `colorScheme.secondaryContainer` |
| **Standard** | Handover notes, Exchange, Expenses, Morning briefing, Care note, More | `colorScheme.primaryContainer` (unchanged from today) |

Same tonal-role rule sub-project 2 established for ChildHome — all three colors are standard Material `ColorScheme` roles derived from the active theme (sub-project 1's `colorSchemeFor()`), never a new accent (§8.6.2's budget respected by non-use, matching sub-project 2's own precedent exactly).

## The ribbon/Hero tension, and its resolution

`GuardianHome` already has a ribbon (Ivy's day bars + the "Call Ivy" button) directly above the tile grid — real, live-wired data, not a navigation tile. Unlike `ChildHome` (which had no equivalent prominent element before My Day became Hero), this screen already has one. **Resolution: the ribbon is untouched.** Message banking becomes a visually distinct Hero tile immediately below it — two prominent things stacked, matching the exact structural precedent `ChildHome`'s own header (`Hi $childName` + `_PresenceCard`) already sets by sitting above its Hero tile untouched. The ribbon is data; the Hero tile is navigation; they aren't in tension, they're adjacent.

## Architecture

Same non-mechanism sub-project 2 chose for ChildHome, for the same reason (this codebase's `SliverGridDelegateWithFixedCrossAxisCount` is the only grid delegate ever used, uniform-cell by construction — no hero-cell/variable-span mechanism exists, and inventing one is out of this pass's "refine, don't redesign" budget): the Hero tile sits as a plain full-width band **outside** the `GridView`, exactly where `child_home.dart`'s own Hero tile sits relative to its Featured `GridView`. The existing `crossAxisCount`/`effectiveColumnWidth`/`mainAxisExtent` computation (`guardian_home.dart:173-190`) is **unchanged** — it continues to govern the Featured and Standard grids exactly as it does today; only which tiles land in which grid, and each grid's fill color, changes.

`_GTile` (this file's existing tile widget, `guardian_home.dart`) gains the same `featured`/`hero` boolean params `child_home.dart`'s own `_Tile` already carries, rather than a second, parallel tile-tiering implementation — check whether extracting a single shared tiered-tile widget both screens use is worthwhile during the plan (a real "two near-identical implementations" smell worth a look, not decided here) or whether the two screens' tiles differ enough (icon-only vs. icon+badge for Message banking's own unread-style affordance, if any) to justify staying separate.

## Fold5 cover-screen interaction

The existing per-tile height/wrap comment (`guardian_home.dart:165-170`, the Fold5 cover-screen 344px-width wrapping fix from an earlier pass) governs `mainAxisExtent` for whichever grid a tile lands in — Hero's own full-width band needs its own height check at 344px width with the longest Hero label ("Message banking," two words) to confirm it doesn't repeat that exact overflow class. A real test at that exact width, not just inspection — same discipline the original comment names as how the bug was actually found last time.

## Motion & P2 compliance

No autonomous entrance animation (§8.13, same rule sub-project 2 established) — nothing shimmers or pulses on load. Press-in feedback reuses the same `AnimatedScale` precedent already in use. P2 is not triggered — no financial data change, no analytics-derived ranking (tier assignment is a fixed, designed hierarchy from this spec, never computed from usage), no unsolicited content on the Hero tile.

## Testing

Real widget tests: each of the 11 tiles renders in its assigned tier's grid (not just "the grid renders 11 tiles," per this session's own standing lesson about assertions that pass without proving the right thing), each tier's fill color matches its assigned `ColorScheme` role, the Hero tile sits above the Featured grid and both sit above Standard, the ribbon renders completely unchanged (a regression guard, not a new behavior), and the 344px-width Hero-label wrap case from "Fold5 cover-screen interaction" above.

## Doc-sync

`MASTERFILE.md` (version bump, a short status note near ChildHome's own tiering entry or its own small note), `CHANGELOG.md`, `MARKUP.html` (`guardianHome` screen entry's `data-amended`), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- Column-count/width scaling — already correct, confirmed, untouched.
- The ribbon itself (Ivy's day bars, Call Ivy button) — untouched, real live data, not part of this visual-hierarchy pass.
- Any new tile, removed tile, or renamed tile — the same 11 destinations, same labels, same icons; only grouping and fill color change.
- A shared tiered-tile widget extraction between `ChildHome` and `GuardianHome` — flagged above as worth a look during the plan, not decided or committed to here.
