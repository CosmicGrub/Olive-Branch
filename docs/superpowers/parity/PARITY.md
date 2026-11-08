# Design parity: the prototype is the reference, Flutter must match it

**Owner decision, 2026-11-08.** The live HTML prototype and the Round 3 mockups are the REFERENCE.
The real Flutter app must look the same, with parity, and then do much more. When the two differ,
Flutter changes. The prototype changes only by a deliberate design decision, and then Flutter follows.

The reference lives in `docs/superpowers/mockups/live/` (`kit.js`, `overhaul.css`, `KIT-CHANGES.md`;
the same premium kit every Round 2/3 screen and the live prototype use). That folder is not
version-controlled with the app, so a snapshot of the two files the build needs is committed at
`scaffold/tools/design-reference/` (see its README).

## How tokens flow

```
docs/superpowers/mockups/live/kit.js + overhaul.css            (the reference, edited by designers)
        |  copy                                                   (cp ... scaffold/tools/design-reference/)
        v
scaffold/tools/design-reference/{kit.js,overhaul.css}          (committed snapshot, CI input)
        |  node tools/gen-design-tokens.mjs                       (evaluates kit.js in a DOM-less stub: OB.theme(palette, mode)
        |                                                          for 7 palettes x light/dark; parses overhaul.css; checks WCAG AA)
        v
scaffold/client/assets/design/tokens.json                      (all colours #AARRGGBB, registered in pubspec.yaml)
scaffold/client/lib/design_tokens_generated.dart               (const maps and enums, same data, GENERATED, do not edit)
        |
        v
client/lib/theme.dart          colorSchemeFor(): prototype roles -> Material ColorScheme slots
client/lib/olive_tokens.dart   OliveTokens ThemeExtension: every role, layered shadows, type styles Material has no slot for, motion
client/lib/theme_data.dart     buildThemeData(): the whole Material theme from the above (no literals)
client/lib/design_tokens.dart  AppSpacing / AppRadius (hand-written constants, asserted equal to the tokens)
```

### What the generator extracts

Palette roles per mode (`bg surface surface2 surface3 outline line edge track ink ink2 ink3 pri priD onPri priC onPriC priC2 accent accentC focus hiC hero1 hero2`)
for all seven palettes; the protected colours (ok/warn/bad/info with tints, six day-parts), identical
in every palette; the layered elevation shadows 0 to 3 per palette and mode; the type scale
(display, big, title, head, cardHead, body, cap, label, mono, button and small/large button, row, tab, pill, field)
with family, size, weight, line height, tracking; radii `r0..r5`; spacing `sp1..sp6`; component metrics
(button, field, chip, toggle, checkbox, icon button, tab item, slider); motion durations and the three
cubic-bezier easings; the focus ring; the six state pills (shape + icon + word, never colour alone);
the 24-grid stroke icon table (bare SVG shapes, 90+ icons); the spot illustrations; the scene names; the device frame sizes.

Derived, not in the kit (recorded in `tokens.json` under `derived`): `onAccent` and `onBad`, the best of
white / page background / ink on the accent and bad colours, because Flutter's `ColorScheme` needs a
`onSecondary` and `onError`.

## Regenerate

```sh
# from the repo root, after the prototype's kit changed
cp docs/superpowers/mockups/live/kit.js docs/superpowers/mockups/live/overhaul.css scaffold/tools/design-reference/
cd scaffold
node tools/gen-design-tokens.mjs            # rewrites tokens.json + design_tokens_generated.dart
node tools/test/design_tokens.test.mjs      # the TS-side drift guard (also part of npm test and tools/verify.sh)
cd client && flutter test test/design_parity_test.dart test/theme_data_test.dart
```

`node tools/gen-design-tokens.mjs --check` exits 1 if the committed outputs are stale;
`--print` prints `tokens.json` without writing.

If a refreshed kit fails WCAG AA the generator refuses to write. Fix the kit, or add a documented
entry to `ADJUSTMENTS` in `gen-design-tokens.mjs` (path, replacement, reason); it is then recorded in
`tokens.json` under `adjustments` and must be named in the PR so the owner sees every place Flutter
differs from the prototype. **Current adjustments: none.**

## The two drift guards

| guard | where | fails when |
|---|---|---|
| TS | `scaffold/tools/test/design_tokens.test.mjs` | the committed `tokens.json` or `design_tokens_generated.dart` differs from a fresh generation; the kit snapshot fails AA; the wiring (pubspec asset, verify.sh, package.json) is missing |
| Dart | `scaffold/client/test/design_parity_test.dart` | what `colorSchemeFor` / `buildThemeData` / `OliveTokens` / `AppRadius` / `AppSpacing` / `OliveMotion` produce differs from `assets/design/tokens.json` for any palette x mode |

Together: kit -> tokens is guarded by the first, tokens -> real theme by the second.

## Known, deliberate differences (CSS has it, Flutter cannot, or has not yet)

- **Mono face.** The prototype's labels and numerals use JetBrains Mono. It is not bundled
  (`assets/fonts` has Bricolage Grotesque and Atkinson Hyperlegible). `kMonoFont` names it and falls
  back to the platform monospace until the OFL font file and licence text are added. **Owner/next step.**
- **Inset highlight shadows** (`inset 0 1px 0 rgba(255,255,255,.8)`) cannot be a `BoxShadow`; they are kept in the data
  (`DesignShadow.inset`) and skipped by `designShadows`. Components that want the highlight draw a 1px top border with `hiC`.
- **`backdrop-filter` blur, `color-mix()`, button gradients and the hero card** are not on `ThemeData`; components build them
  from the roles (`OliveTokens.heroGradient`, `hero1`, `hero2`, `sheen`).
- **The field focus halo** (4px at 22 percent of `pri`) is not expressible in `InputDecorationTheme`; the focused border is `pri`, 2px.
- **Icons and spot illustrations** are in the generated data as SVG shapes (`kDesignIcons`, `kDesignSpots`). Rendering them is a
  component task (an `OliveIcon` painter or an SVG package); until it lands screens keep Material icons.
- **Scenes** (full illustrations) are listed by name only.

## Checklist: adding a component or screen

1. Find it in the prototype (`live/` modules or the Round 2/3 mockups). Note the prototype screen id.
2. Colours: take every colour from `OliveTokens` / `Theme.of(context).colorScheme` / `OliveSemantic`. No `Color(0x...)`, no
   `Colors.xxx` for meaning, no `withOpacity` to invent a tint (use the `priC` / `okC` tint roles).
3. Type: `Theme.of(context).textTheme` slots (mapped from the kit scale in `theme_data.dart`) or `OliveTokens.label/mono/big/caption`.
   No literal font sizes.
4. Shape and space: `AppRadius` / `AppSpacing` (equal to `r0..r5`, `sp1..sp6`); control sizes from `kDesignComponents`.
5. Elevation: `OliveTokens.elevation0..3`, not Material `elevation:` (use it only where a `Card` is unavoidable).
6. Motion: `OliveMotion.press/fast/base/slow` with `OliveMotion.easeOut/easeSpring/easeIn`, through `OliveMotion.resolve(context, d)` so
   reduce-motion collapses it. Nothing animates by itself.
7. State pills: shape + icon + word from `kDesignStatePills`, never colour alone.
8. Hit areas: 48 minimum (child 64). Focus ring: `OliveTokens.focusSide` (3px, offset 2).
9. Dark mode and all seven palettes: check the screen in `olive/dark` and `softPlayful/light` at least; the parity test already guards the tokens.
10. Header: every client Dart file starts with `No longer UNVERIFIED — verified by CI` (or `UNVERIFIED` until it is).
11. Add a widget test (and a row below); update the parity matrix status.
12. If the prototype itself has to change, change the prototype first, refresh the snapshot, regenerate, then build to it.

## Parity matrix (template: another agent fills it)

Status: `built` = visually and behaviourally matches the prototype and has a test; `partial` = exists but differs (say how in notes);
`missing` = no Flutter screen yet. One row per prototype screen or component.

| prototype screen id | module / file (live/) | Flutter screen / file | status | notes |
|---|---|---|---|---|
| _example: child-home_ | _mod-child.js_ | _lib/child_home.dart_ | _partial_ | _hero card uses Material Card; needs `OliveTokens.heroGradient`_ |
| | | | | |
| | | | | |

### Component rows (seeded from the kit's helper list)

| kit helper | Flutter | status | notes |
|---|---|---|---|
| theme (7 palettes x 2 modes) | `colorSchemeFor`, `OliveTokens` | built | guarded by `design_parity_test.dart` |
| type scale | `TextTheme` + `OliveTokens` | built | mono face not bundled |
| radii, spacing | `AppRadius`, `AppSpacing` | built | |
| motion tokens | `OliveMotion` | built | |
| focus ring | button `side` on focus, `OliveTokens.focusSide` | partial | halo on fields not drawn |
| buttons (`K.btn`) | Filled/Elevated/Outlined/TextButton themes | partial | primary gradient and `lg` size not themed |
| toggle, check, radio, slider | Switch/Checkbox/Radio/Slider themes | built | |
| filter chips, segmented | `ChipTheme`, `SegmentedButtonTheme` | partial | `seg2` pill track not themed |
| form field (`K.formField`) | `InputDecorationTheme` | partial | focus halo |
| cards (`card`, `raised`, `sunk`, `outline`, `hero`) | `CardTheme` | partial | variants need an `OliveCard` |
| state pills (`K.status`) | `kDesignStatePills` | missing | data only; no widget |
| icons (`K.ico`) | `kDesignIcons` | missing | data only; no painter |
| spot illustrations (`K.spot`) | `kDesignSpots` | missing | data only; no painter |
| scenes (`K.scene`) | `kDesignScenes` | missing | names only |
| bottom sheet, modal, toast | Sheet/Dialog/SnackBar themes | partial | radii and colours match; enter animation not |
| tab bar | `NavigationBarTheme` | partial | blur not drawn |
| the remaining helpers (`K.pinPad`, `K.calMonth`, `K.schedule`, `K.timeline`, `K.player`, `K.recordBtn`, `K.waveform`, `K.qrCard`, `K.swipe`, ...) | | missing | audit each |
