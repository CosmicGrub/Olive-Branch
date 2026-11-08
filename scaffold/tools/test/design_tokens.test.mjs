/**
 * Design-token drift guard. The prototype's design kit (tools/design-reference/kit.js + overhaul.css,
 * a snapshot of docs/superpowers/mockups/live) is the REFERENCE; the Flutter client is built from
 * assets/design/tokens.json and lib/design_tokens_generated.dart, both written by
 * tools/gen-design-tokens.mjs. This test fails if either committed output is stale (the same
 * "regenerate and compare" pattern as packages/palette/test/colour_day.test.mjs), and re-verifies
 * the kit's own accessibility promises so a kit refresh that breaks contrast cannot land silently.
 *
 *   regenerate: cd scaffold && node tools/gen-design-tokens.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { render, extract, toArgb, ratio, OUT_JSON, OUT_DART } from '../gen-design-tokens.mjs';

const SCAFFOLD = fileURLToPath(new URL('../../', import.meta.url));
const rd = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const fresh = render();
const T = fresh.tokens;

// ---- A · the committed outputs equal a fresh generation -----------------------------------
{
  const g = 'A drift';
  check(g, 'assets/design/tokens.json exists', existsSync(OUT_JSON), true);
  check(g, 'lib/design_tokens_generated.dart exists', existsSync(OUT_DART), true);
  check(g, 'tokens.json equals a fresh generation (run: node tools/gen-design-tokens.mjs)', rd(OUT_JSON) === fresh.json, true);
  check(g, 'design_tokens_generated.dart equals a fresh generation (run: node tools/gen-design-tokens.mjs)', rd(OUT_DART) === fresh.dart, true);
  check(g, 'the generator is deterministic (two runs, identical bytes)', render().json === fresh.json, true);
  check(g, 'tokens.json carries no hsl()/rgb() strings: every colour is #AARRGGBB', /hsl\(|rgba?\(/.test(JSON.stringify({ ...T, icons: 0, spots: 0 })), false);
}

// ---- B · the reference snapshot ------------------------------------------------------------
{
  const g = 'B reference snapshot';
  const ref = (f) => rd(SCAFFOLD + 'tools/design-reference/' + f);
  check(g, 'kit.js snapshot is committed under tools/design-reference/', ref('kit.js').includes('OB.theme=function'), true);
  check(g, 'overhaul.css snapshot is committed under tools/design-reference/', ref('overhaul.css').includes('.ob .t-display'), true);
  check(g, 'a README says where the snapshot is copied from and how to refresh it', /docs\/superpowers\/mockups\/live/.test(ref('README.md')) && /gen-design-tokens/.test(ref('README.md')), true);
  check(g, 'tokens.json records the hashes of the snapshot it was built from', T.source.kitJs.length === 16 && T.source.overhaulCss.length === 16, true);
}

// ---- C · what the generator extracts is complete ------------------------------------------
{
  const g = 'C extraction';
  const P = Object.keys(T.palettes);
  check(g, 'seven palettes', P.length, 7);
  check(g, 'palette ids match Flutter\'s ThemePalette names', P.join(','), 'olive,classic,calmModern,warmGrounded,softPlayful,deepCozy,brightBold');
  const roles0 = Object.keys(T.palettes.olive.light);
  for (const p of P) for (const m of ['light', 'dark']) {
    const r = T.palettes[p][m];
    check(g, `${p}/${m}: same role set as olive/light (${roles0.length})`, Object.keys(r).join(), roles0.join());
    check(g, `${p}/${m}: every colour is #AARRGGBB`, Object.values(r).every((c) => /^#[0-9A-F]{8}$/.test(c)), true);
  }
  for (const m of ['light', 'dark']) {
    check(g, `protected colours (${m}): ok/warn/bad/info with tints and six day-parts`, Object.keys(T.semantic[m]).length, 14);
  }
  check(g, 'protected colours are palette independent (extraction would throw otherwise)', T.semantic.light.ok, '#FF237A52');
  check(g, 'light and dark protected sets differ', T.semantic.light.ok !== T.semantic.dark.ok, true);
  check(g, 'type scale has display/title/head/body/cap/label/mono', ['display', 'title', 'head', 'body', 'cap', 'label', 'mono'].every((k) => T.type.scale[k]), true);
  check(g, 'display is 34/800 Bricolage with tight tracking', JSON.stringify([T.type.scale.display.size, T.type.scale.display.weight, T.type.scale.display.family, T.type.scale.display.letterSpacingEm]), JSON.stringify([34, 800, 'display', -0.035]));
  check(g, 'label is the uppercase mono face', T.type.scale.label.family === 'mono' && T.type.scale.label.uppercase, true);
  check(g, 'font families name Bricolage Grotesque, Atkinson Hyperlegible, JetBrains Mono', [T.type.families.display[0], T.type.families.body[0], T.type.families.mono[0]].join('|'), 'Bricolage Grotesque|Atkinson Hyperlegible|JetBrains Mono');
  check(g, 'radii r0..r5', Object.values(T.radii).join(), '8,12,16,22,28,34');
  check(g, 'spacing sp1..sp6', Object.values(T.spacing).join(), '4,8,12,16,24,32');
  check(g, 'motion: press/fast/base/slow durations', Object.values(T.motion.durationsMs).join(), '40,120,220,340');
  check(g, 'motion: three easings, each four control points', Object.values(T.motion.easings).every((e) => e.length === 4) && Object.keys(T.motion.easings).length === 3, true);
  check(g, 'motion stays under 400 ms', Math.max(...Object.values(T.motion.durationsMs)) < 400, true);
  check(g, 'focus ring is 3px, offset 2px, in the focus role', JSON.stringify([T.focusRing.width, T.focusRing.offset, T.focusRing.colorRole]), JSON.stringify([3, 2, 'focus']));
  for (const p of P) for (const m of ['light', 'dark']) {
    check(g, `${p}/${m}: four elevation levels`, Object.keys(T.elevation[p][m]).join(), 'shadow0,shadow1,shadow2,shadow3');
  }
  check(g, 'six state pills, each with a label, an icon and a shape', Object.values(T.statePills).every((s) => s.label && s.icon && s.shape) && Object.keys(T.statePills).length === 6, true);
  check(g, 'queued is dashed and failed is outlined: shape differs, not only colour', [T.statePills.queued.shape, T.statePills.failed.shape].join(), 'dashed,outline');
  check(g, 'every state pill icon exists in the icon table', Object.values(T.statePills).every((s) => T.icons.paths[s.icon]), true);
  check(g, 'icon table: 24 grid, 90+ icons, stroke style recorded', T.icons.spec.grid === 24 && Object.keys(T.icons.paths).length > 90, true);
  check(g, 'icon markup is bare shapes (no <svg> wrapper)', Object.values(T.icons.paths).every((s) => !s.includes('<svg')), true);
  check(g, 'spot illustrations: 11 shapes, plate radius recorded', Object.keys(T.spots.shapes).length === 11 && T.spots.plate.radius === 28, true);
  check(g, 'scenes are listed by name', T.scenes.length >= 14, true);
  check(g, 'device form sizes include the fold postures', 'foldMain' in T.forms && 'foldTabletop' in T.forms, true);
  check(g, 'component metrics: 48 high controls, 15 radius, 52 high fields', JSON.stringify([T.components.button.minHeight, T.components.button.radius, T.components.field.minHeight]), JSON.stringify([48, 15, 52]));
}

// ---- D · the kit's accessibility promises, re-verified -------------------------------------
{
  const g = 'D contrast';
  const kit = rd(SCAFFOLD + 'tools/design-reference/kit.js'), css = rd(SCAFFOLD + 'tools/design-reference/overhaul.css');
  const x = extract(kit, css);
  check(g, 'a re-extraction reports zero contrast failures', x.failures.length, 0);
  check(g, 'adjustments to the prototype are recorded in tokens.json (count, expected to be listed in the PR)', Array.isArray(T.adjustments), true);
  for (const p of Object.keys(T.palettes)) for (const m of ['light', 'dark']) {
    const r = T.palettes[p][m];
    check(g, `${p}/${m}: ink3 on every surface >= 4.5`, ['bg', 'surface', 'surface2', 'surface3'].every((s) => ratio(r.ink3, r[s]) >= 4.5), true);
    check(g, `${p}/${m}: edge on bg/surface/surface2 >= 3 (WCAG 1.4.11)`, ['bg', 'surface', 'surface2'].every((s) => ratio(r.edge, r[s]) >= 3), true);
  }
  // the colour converter itself
  check(g, 'toArgb: #hex', toArgb('#4A6B4F'), '#FF4A6B4F');
  check(g, 'toArgb: rgba alpha', toArgb('rgba(255,255,255,.75)'), '#BFFFFFFF');
  check(g, 'toArgb: hsl white', toArgb('hsl(0 0% 100%)'), '#FFFFFFFF');
  check(g, 'toArgb: hsl primary red', toArgb('hsl(0 100% 50%)'), '#FFFF0000');
  check(g, 'toArgb: hsl with alpha', toArgb('hsl(0 0% 0% / .5)'), '#80000000');
  let threw = false; try { toArgb('oklch(0.5 0.1 120)'); } catch { threw = true; }
  check(g, 'toArgb: an unknown colour format throws instead of guessing', threw, true);
}

// ---- E · wired in ---------------------------------------------------------------------------
{
  const g = 'E wiring';
  const pkg = JSON.parse(rd(SCAFFOLD + 'package.json'));
  check(g, 'package.json has test:design-tokens and it is part of npm test', !!pkg.scripts['test:design-tokens'] && pkg.scripts.test.includes('test:design-tokens'), true);
  check(g, 'verify.sh runs this test', rd(SCAFFOLD + 'tools/verify.sh').includes('tools/test/design_tokens.test.mjs'), true);
  const pub = rd(SCAFFOLD + 'client/pubspec.yaml');
  check(g, 'pubspec registers assets/design/', /^\s+- assets\/design\/\s*$/m.test(pub), true);
  const gen = rd(OUT_DART);
  check(g, 'the generated Dart file carries the UNVERIFIED header and a GENERATED warning', gen.includes('No longer UNVERIFIED') && gen.includes('GENERATED FILE — DO NOT EDIT'), true);
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
