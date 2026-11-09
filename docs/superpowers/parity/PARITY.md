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

- ~~Mono face.~~ **Done.** JetBrains Mono (SIL OFL 1.1, one variable-weight file, from github.com/google/fonts `ofl/jetbrainsmono`) is bundled as
  `assets/fonts/JetBrainsMono.ttf` with `OFL-JetBrainsMono.txt` beside it; the label and mono styles ask for `wght` 500. All three licences are on
  Flutter's licences page (`lib/font_licences.dart`, called from the app entry points).
- **Inset highlight shadows** (`inset 0 1px 0 rgba(255,255,255,.8)`) cannot be a `BoxShadow`; they are kept in the data
  (`DesignShadow.inset`) and skipped by `designShadows`. Components that want the highlight draw a 1px top border with `hiC`.
- **`backdrop-filter` blur, `color-mix()`, button gradients and the hero card** are not on `ThemeData`; components build them
  from the roles (`OliveTokens.heroGradient`, `hero1`, `hero2`, `sheen`).
- **The field focus halo** (4px at 22 percent of `pri`) is not expressible in `InputDecorationTheme`; the focused border is `pri`, 2px.
- **Icons and spot illustrations** are in the generated data as SVG shapes (`kDesignIcons`, `kDesignSpots`). Rendering them is a
  component task (an `OliveIcon` painter or an SVG package); until it lands screens keep Material icons.
- **Scenes** (full illustrations) are listed by name only.

## The behaviour harness and the parity ledger (Wave P)

Tokens prove the look; the harness proves the behaviour. The prototype's scenarios and rules become data, the real client is replayed
against that data, and the gap is counted.

```
docs/superpowers/mockups/live/*.js                       (the reference)
   |  scaffold/tools/proto-headless.mjs                   DOM-less node:vm host: fake timers, seeded Math.random, virtual clock
   |  scaffold/tools/gen-parity-scenarios.mjs             runs L.scenarios step by step, records state, probes the rules
   v
scaffold/client/test/parity/scenarios.json               { scenarios[7], rules{}, routes[] }  GENERATED, drift-guarded
   |  scenario_runner.dart                                 actions -> drivers on the REAL screens; probes -> checkers
   |  fake_server.dart + virtual_clock.dart                the routes the client calls, the prototype's semantics, tester.pump time
   |  rule_checks.dart                                     the rule table vs the Flutter rules
   v
test/parity/ledger.json (every run)  +  ledger_baseline.json (committed ratchet)
```

**A unit** is one action to perform or one state to assert (plus one per rule). It is exactly one of: `implemented` (a Flutter driver exists
and the prototype's expectation holds), `pending` (the Flutter feature is missing; the unit names the parity-matrix row ids that own it) or
`differs` (Flutter has it and behaves differently; the note says how). An assertion is evaluated only when every action in its step ran;
otherwise it is `pending: blocked`. After a step with a pending action the world adopts the prototype's expected state for the few facts
later drivers need, so one missing screen does not hide the rest of the scenario.

**The ratchet.** `scenario_parity_test.dart` fails if a unit that is `implemented` in `ledger_baseline.json` is not implemented now, or if the
pending or differs count rises. Progress lowers the counts and is allowed; lock it in with
`PARITY_UPDATE_BASELINE=1 flutter test test/parity/scenario_parity_test.dart` and commit the baseline. A wave that builds a screen adds its
driver to `scenario_runner.dart` (key `tap:<prototype action>`, `type:<path>`, `go:<screen>` or `op:...`) and its checker, and the pending
units for that screen flip to implemented. `rules_parity_test.dart` declares today's verdict for every rule, so a silent change on either
side fails until it is recorded.

**Regenerate** after the prototype changes: `cd scaffold && node tools/gen-parity-scenarios.mjs` (`--check` exits 1 if stale; `--print` prints).
The generator refuses a step whose matrix row is not in `matrix.json`.

**What the harness cannot cover** (see also SCREENSHOT-HARNESS.md): pixels and layout (separate proposal); real device behaviour (camera, push,
audio, the kiosk lock, the fold); timing that depends on real I/O; the `call` closures in scenarios are captured by what they did (clock,
network, age, API, taps), not replayed as code; the fixed UTC-6 wall clock (a play-window assertion across a daylight-saving change would be
an hour out); Flutter's own server is not the prototype's, so server-side rules are compared by reading the server source (PIN lockout) or
through the FakeServer, which is only as true as `fake_server_test.dart`.

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
| type scale | `TextTheme` + `OliveTokens` | built | |
| radii, spacing | `AppRadius`, `AppSpacing` | built | |
| motion tokens | `OliveMotion` | built | |
| focus ring | button `side` on focus, `OliveTokens.focusSide` | partial | halo on fields not drawn |
| buttons (`K.btn`) | Filled/Elevated/Outlined/TextButton themes; `OliveButton`, `OliveIconButton` (lib/ui) | built | pri gradient, tonal, ghost, danger, sm/md/lg; 48dp/64dp hit area |
| toggle, check, radio, slider | Switch/Checkbox/Radio/Slider themes | built | |
| filter chips, segmented | `FilterChips`, `SegmentedControl` (lib/ui) | built | pill track, counts, 48dp hit area |
| form field (`K.formField`) | `OliveFormField` (lib/ui) | built | label, hint, error with icon and words, focus halo |
| cards (`card`, `raised`, `sunk`, `outline`, `hero`) | `OliveCard` (lib/ui) | built | nine variants |
| state pills (`K.status`) | `StatusPill` (lib/ui) | built | adds `delivering`; shape + icon + word |
| icons (`K.ico`) | `OliveIcon` + generated `olive_art_data.dart` | built | CustomPainter; generated from the kit snapshot (`tools/gen-olive-icons.mjs`), drift-guarded |
| spot illustrations (`K.spot`) | `OliveSpot` | built | palette-aware, plate optional |
| scenes (`K.scene`) | `OliveScene` | built | all 14 kit scenes |
| bottom sheet, modal, toast | `OliveBottomSheet`, `OliveDialog`, `OliveToast`/`showOliveToast` (lib/ui) | built | scrim, spring entrance via `OliveTiming`, reduced motion honoured |
| tab bar | `NavigationBarTheme` | partial | blur not drawn |
| the remaining helpers | `OliveTile`, `OliveRow`, `KeyValueRow`, `StatTile`, `AvatarStack`, `OliveNotice`, `OfflineBanner`, `EmptyState`, `ErrorState`, `OliveSkeleton`, `PermissionPrompt`, `OliveStepper`/`OliveSteps`, `Timeline`, `ScheduleGrid`, `MonthCalendar`, `RecordButton`, `Waveform`, `PlayerChrome`, `PinPad`, `QrCard`, toggle/radio/check/slider rows | built | lib/ui; `K.swipe` not ported yet |

## The component library (lib/ui)

`scaffold/client/lib/ui/` holds the Flutter counterpart of the kit's helpers, one import (`ui/olive_ui.dart`):
primitives (`olive_base`), surfaces and identity (`olive_surfaces`), status and feedback (`olive_feedback`),
controls (`olive_controls`), progress and time (`olive_flow`), layers (`olive_layers`), media (`olive_media`),
art (`olive_art`, `olive_vector`, generated `olive_art_data`) and the token seam (`olive_palette`, which reads
`OliveTokens` and falls back to the Material scheme). Each file header names the kit helper every widget mirrors.

`OliveUiGalleryScreen` (`lib/ui/olive_ui_gallery.dart`) shows every component, scene, spot and icon in light and dark,
at text scale 1.0 and 2.0, as guardian or child, in all seven palettes. Open it from the guardian More hub
("Design (demo)", demo builds only) or `flutter run --target=lib/main_ui_gallery.dart`, next to
`docs/superpowers/mockups/live/index.html`, to compare against the prototype.

Art regeneration: `node tools/gen-olive-icons.mjs` (reads `tools/design-reference/kit.js`); `tools/test/olive_art.test.mjs`
fails if `olive_art_data.dart` is stale. `kDesignIcons` / `kDesignSpots` in the tokens stay raw SVG data; `OliveIcon` draws
the normalised geometry from the same snapshot, and a Dart test locks the two name sets together.

Known gaps: `K.swipe` (swipe-to-reveal row) and the tab bar are not ported; `t-mono` and
`t-label` use the bundled JetBrains Mono (weight 500) with tabular figures.

## Delta: adult gate and simple pairing (2026-11-08)

The live prototype (`docs/superpowers/mockups/live`) still shows the older shape: a child-side PIN keypad and a
guardian-minted 6-digit code with a countdown. The Flutter app now differs on purpose and the prototype is NOT
rebuilt here: the child shows an adult-gate card (no keypad until a grown-up taps), and connecting is a
grown-up-opened window with a PIN-based key exchange and a confirmation word and picture
(MASTERFILE section 8.5.11). The ledger rule `pairing.codeShape` still describes the server's 6-digit code, which is
unchanged and still available as the account-code option.

**Pairing-code alphabet, resolved (2026-11-08).** The owner chose 0-9. The server issues 0-9 zero-padded and the client
field accepts 0-9; the prototype's generator (`codeOf()` in live-core.js, 1-9 so a nine-key pad could type any code) is a
prototype simplification and is not the rule. `pairing.codeShape` is therefore `implemented`, and the generator note in
LIVE-API.md is superseded by this paragraph. The same change gave the adult keypad a 0 key.
