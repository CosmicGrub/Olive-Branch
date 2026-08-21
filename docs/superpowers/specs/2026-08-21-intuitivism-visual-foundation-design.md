# Intuitivism Pass — Sub-project 1: visual foundation (theme customization suite)

**Status:** approved, ready for implementation
**Scope:** the design-token foundation only — a real, guardian-configurable theme system replacing the app's current unstyled default. Screen-level simplification (ChildHome, GamePickerScreen, navigation/density) and any other "intuitivism pass" work are separate, later specs that build on this foundation — not designed here.

## Goal

The user's own framing: simplify and warm up the app's overall design so it feels less "adult-minimalist" and "in your face" for a casual/first-time user — specifically their own kid, plus other parents and kids during demos. Explicit constraint: refine, don't redesign from scratch. Explicit non-goal, confirmed directly: this is purely about visual presentation — every real accessibility requirement (§8.4 touch targets, §8.8 text-scale support, screen-reader semantics) stays exactly as strong; nothing here weakens substance for style.

**Root cause found during scoping:** the entire app's color identity is `ColorScheme.fromSeed(seedColor: Colors.deepPurple)` in `main.dart`/`main_live.dart` — Flutter's stock starter-template default, never customized, with zero brand identity or warmth. This is the single highest-leverage place to start: every other screen already builds on `Theme.of(context).colorScheme` throughout the codebase, so fixing the seed improves everything downstream without touching per-screen layout.

## Hard constraint surfaced and resolved during scoping

MASTERFILE §8.1 — the child-facing shell has **no settings affordance anywhere, at any depth** — is not a style preference, it's a CI-enforced contract (`transport.test.mjs`'s `'child shell has no settings affordance'` check, scanning `child_home.dart`'s own source for the literal word). No settings screen exists anywhere in this codebase yet, for guardian OR child. **Resolved, confirmed directly: this customization suite is guardian-only, reachable only from `GuardianHome`, and applies app-wide** — the child's device receives whichever theme is currently active the same way it already receives other real backend data; the child never sees a settings entry point, keeping §8.1 intact exactly as every other screen already does.

## Architecture

**Two independent axes, not flat options:** a **palette** (hue identity) × **brightness** (light/dark). A guardian picks one of each — this composes correctly rather than needing a separately-designed dark variant per palette.

```dart
enum ThemePalette { classic, calmModern, warmGrounded, softPlayful, deepCozy, brightBold }
enum ThemeBrightness { light, dark }
class AppTheme {
  const AppTheme({required this.palette, required this.brightness});
  final ThemePalette palette;
  final ThemeBrightness brightness;
}
```

A real `ColorScheme` catalog function (`colorSchemeFor(AppTheme)`) replaces the hardcoded seed at the `MaterialApp` root — each palette defined by its own real seed color(s) via `ColorScheme.fromSeed`, not 12 hand-tuned schemes; light/dark handled by `ColorScheme.fromSeed(..., brightness: ...)`.

**Propagation:** a `ValueNotifier<AppTheme>` (or a small `InheritedNotifier` subclass, matching this codebase's plain-Flutter style — no new state-management dependency) held above `MaterialApp`, rebuilding `theme:`/`darkTheme:` when the guardian's selection changes or when the child's device receives an updated value from the backend at app start.

**Persistence — backend-synced:** a new nullable `theme_palette`/`theme_brightness` pair of columns (or a small JSON preference blob, whichever matches this schema's existing convention better — check `app_user`/`child` migration patterns before choosing) added via a new numbered migration, a real route (`GET`/`PUT /v1/children/:childId/theme` or similar, guardian-write/child-read, real RLS scoped the same way every other per-child preference in this app already is), and real DB tests mirroring the established `(real RLS)` suite depth. The child's device fetches the active theme at app start (`main_live.dart`'s existing session bootstrap is the natural place) and applies it before first paint where feasible, falling back to `classic`/`light` if unset or unreachable — never a broken/partial theme state.

## Palette catalog

| Palette | Feel | Note |
|---|---|---|
| `classic` | Current stock default | Kept as an explicit reset/escape-hatch, not removed |
| `calmModern` | Muted teal, soft neutral | **Default** for now |
| `warmGrounded` | Terracotta/amber + sage | Matches the app's existing warm copy tone throughout MASTERFILE |
| `softPlayful` | Coral/peach + warm yellow | Most overtly "kid app," bolder corner radii |
| `deepCozy` | Forest green + warm rust | Richer, evening-friendly, feels lived-in rather than app-like |
| `brightBold` | Confident blue + sunny yellow | Energetic without pastel — for an older kid who doesn't want "cute" |

Real seed colors and exact corner-radius/elevation tokens per palette are an implementation detail to finalize during the build (informed by the visual-companion mockups already shown and approved for `calmModern`/`warmGrounded`/`softPlayful`'s general direction) — not hand-specified line-by-line here.

## The customization suite screen

New screen (`theme_picker_screen.dart` or similar), reachable only from a new real entry point in `GuardianHome` — this session's first-ever real settings surface. Palette selection reuses the established catalogue-card visual pattern (`game_picker.dart`'s `_GameCard` shape: icon/color swatch, title, one-line description) for consistency rather than inventing a new list pattern; a light/dark toggle; a live preview of the pending selection before committing; an explicit "Apply" action that writes to the backend (not auto-saved on every tap, so browsing options never has a side effect).

**Device-adaptive tie-in:** the suite screen's own layout (card grid column count) is driven by `form_factors.dart`'s real `postureFor()`/`columnsAt()`, matching every other screen already migrated this session — but the **color identity itself is device-independent**: whichever theme is active looks the same on the Fold5 and the tablet. Device-adaptiveness here means layout, not a different palette per device — the whole point is one consistent family "look" regardless of which physical device the child is holding.

## Motion & P2 compliance

Switching themes is a real, user-initiated change (§8.13 consequence motion is fine — a brief crossfade on Apply), never automatic/looping. No score, rank, or "you've tried N themes" tracking of any kind (P2) — this is a preference, not a game.

## Testing

Real widget tests: each palette × brightness combination produces a genuinely different `ColorScheme` (not 12 visually-identical results from a broken seed function), the picker screen's own posture-driven column count, the live-preview-before-Apply behavior (selecting ≠ persisting), and — critically — a real test proving the child shell still has NO settings affordance anywhere (extending the existing contract check's own spirit, not just trusting it won't regress). Real backend tests for the new route/columns, mirroring the established `(real RLS)` suite depth: guardian can write, child can read but not write, unset falls back to `classic`/`light` cleanly.

## Doc-sync

Same lockstep requirement as every PR this session: `MASTERFILE.md` (version header, a new status note — likely its own small new §-numbered section for "theme customization," or folded into an existing settings-adjacent section if one exists; check before inventing a new §number), `CHANGELOG.md`, `MARKUP.html` (a new screen entry for the picker screen), `scaffold/demo/shell.html`.

## Explicitly out of scope for this sub-project

- Per-child themes (confirmed: app-wide for now, not per-child) — flagged as a possible future refinement, not designed here.
- Screen-level simplification (ChildHome, GamePickerScreen, navigation/density) — separate, later sub-projects per the original decomposition.
- Any reduction of real accessibility substance — explicitly ruled out, confirmed directly.
