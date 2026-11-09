# Screenshot harness: pixel-level comparison (proposal, not built)

Status: PROPOSAL. No browser dependency is added by Wave P. The repo has no Puppeteer or Playwright today (`scaffold/package.json`,
`package-lock.json`), so the "small working script" the plan allowed for is deliberately not included; a script that cannot run in CI
proves nothing. This document says what would be built, what CI would need and what it would and would not prove.

Layers 2.1 (scenarios) and 2.2 (tokens) of `BUILD-PLAN.md` are exact. This is layer 2.4: look parity, perceptual and advisory first.

## What it compares

| Reference (the prototype) | Candidate (the real app) |
|---|---|
| `docs/superpowers/mockups/live/index.html` in headless Chromium, one PNG per prototype screen id | Flutter golden test of the same screen, one PNG per screen id |
| device frames from the kit: Fold5 cover 344x882, phone 390x844, tablet 800x1280 | the same logical sizes at devicePixelRatio 2 |
| light and dark, palette `olive` first (then the other six) | `buildThemeData` for the same palette and mode |
| `prefers-reduced-motion`, virtual clock paused (`L.setClock({paused:true})`) | animations settled, `VirtualClock` fixed |

## Reference side (node, Playwright)

1. `tools/parity-shots/render.mjs` (new, dev-only): `playwright` as a `devDependency` of a NEW `scaffold/tools/parity-shots/package.json`, so
   `npm ci` in `scaffold/` and the existing suites do not download a browser. `npx playwright install chromium --with-deps` runs only in the
   parity-shots CI job.
2. Fonts: the prototype loads Google Fonts. The render script intercepts those requests and serves the SAME files Flutter bundles
   (`client/assets/fonts`: Bricolage Grotesque, Atkinson Hyperlegible), so neither side depends on the network and both use identical glyphs.
   JetBrains Mono is now bundled (`assets/fonts/JetBrainsMono.ttf`), so mono text needs no diff mask.
3. Drive: open `index.html`, `L.reset({scenario})` or call `L.fastFamily()`, then `L.go(dev, screenId)` for each id in `scenarios.json` and
   in `matrix.json` (`kind: screen`), wait for `requestAnimationFrame` twice, screenshot the `.dframe` element. Output
   `build/parity/reference/<screenId>.<size>.<mode>.png`.
4. The script can reuse `tools/proto-headless.mjs`'s boot order; only the DOM is real instead of stubbed.

## Flutter side (goldens)

- `test/parity/golden/<screenId>_test.dart`, `matchesGoldenFile('golden/<id>.<size>.<mode>.png')`, fonts through `loadAppFonts()`,
  `FakeServer` and `VirtualClock` from Wave P for state, `ScenarioRunner` drivers to reach the screen (so the screen is reached the way a
  person reaches it, not by constructing it with magic arguments).
- Goldens differ by platform (text hinting, Skia vs Impeller). Generate and compare ONLY on the pinned Linux CI runner
  (`ubuntu-24.04`, one Flutter version from `FLUTTER_VERSION`); never commit goldens made on Windows or macOS.

## Comparison

`tools/parity-shots/compare.mjs`: resize to a common size, compute SSIM (and a 3x3 block mean-difference map), write a side-by-side PNG
and `build/parity/report.json` `{screenId, size, mode, ssim}` for every pair. Pixel-exact comparison across Chromium and Skia is rejected:
anti-aliasing and hinting differ by renderer, so exact diffs are noise.

- Phase 1 (report only): upload `build/parity/` as the artifact `parity-report`; never fails.
- Phase 2 (per-screen gate): `matrix.json` gains `lookScore` per screen; a wave may not lower a screen's score; the four child homes gate first
  (wave 2), then the guardian home, then the rest.

## What CI would need

| Need | Detail |
|---|---|
| A job `parity-shots` in `.github/workflows/verify.yml`, Linux only | Node 20+, Flutter (already installed for the client job), `playwright install chromium --with-deps` (about 150 MB, cached by `actions/cache` on the Playwright version) |
| Fonts present | already in `client/assets/fonts` |
| Runtime | roughly 3 to 6 minutes for 143 screens x 3 sizes x 2 modes if sharded; start with 12 screens (the child homes and the onboarding) |
| Artifact storage | `parity-report` (PNG pairs, 5 to 20 MB) with 14-day retention |
| Failure policy | Phase 1 none; Phase 2 only the ratcheted screens, and a GitHub release-download outage re-runs that job only |

## What it would not prove

Motion, focus order, real text input, platform widgets (system keyboard, share sheet), and anything inside a native view; those stay with the
scenario ledger and the hardware passes. It also cannot tell a deliberate difference (PARITY.md, known differences) from a bug: the mask and the
per-screen threshold are where that decision is written down.

## Order of work

1. Add `tools/parity-shots/` with `render.mjs` for the 12 starter screens and run it locally; commit nothing generated.
2. Add the goldens for the same 12 under `test/parity/golden/` and the Linux-only CI job (report only).
3. Add `compare.mjs`, the artifact, and the `lookScore` field; open Phase 2 per screen as wave owners ask for it.
