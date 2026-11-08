// Generates the design tokens the Flutter client is built from.
//
//   scaffold/tools/design-reference/{kit.js,overhaul.css}      (snapshot of the prototype's design kit)
//        |  this file: evaluates kit.js in a DOM-less stub, parses overhaul.css
//        v
//   scaffold/client/assets/design/tokens.json                  (all colours #AARRGGBB, never hsl strings)
//   scaffold/client/lib/design_tokens_generated.dart           (const maps and enums, same data)
//
// The prototype is the reference (docs/superpowers/parity/PARITY.md). Flutter must match it.
// tools/test/design_tokens.test.mjs fails if either output is stale; the Dart parity test
// (client/test/design_parity_test.dart) fails if the real theme stops matching tokens.json.
//
// usage: node tools/gen-design-tokens.mjs            (writes both files)
//        node tools/gen-design-tokens.mjs --print    (prints tokens.json, writes nothing)
//        node tools/gen-design-tokens.mjs --check    (exit 1 if the committed files are stale)
//
// ADJUSTMENTS: the kit's own contrast claims are VERIFIED here, not trusted. A pair that fails
// WCAG AA is adjusted in this file (see ADJUSTMENTS) and the adjustment is recorded in
// tokens.json under "adjustments" so the owner can see exactly what differs from the prototype.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import { fileURLToPath } from 'node:url';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const REF = HERE + 'design-reference/';
export const OUT_JSON = HERE + '../client/assets/design/tokens.json';
export const OUT_DART = HERE + '../client/lib/design_tokens_generated.dart';

const norm = (s) => s.replace(/\r\n/g, '\n');
const sha = (s) => createHash('sha256').update(s).digest('hex').slice(0, 16);

// ---- colour maths -------------------------------------------------------------------------
const h2 = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0').toUpperCase();
const hexA = (r, g, b, a = 1) => '#' + h2(a * 255) + h2(r) + h2(g) + h2(b);
function hslToRgb(h, s, l) {
  s /= 100; l /= 100;
  const k = (n) => (n + h / 30) % 12, a = s * Math.min(l, 1 - l);
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return [f(0) * 255, f(8) * 255, f(4) * 255];
}
/** Any colour the kit emits -> '#AARRGGBB'. Throws on anything it does not understand. */
export function toArgb(c) {
  c = String(c).trim();
  let m;
  if ((m = c.match(/^#([0-9a-f]{6})$/i))) return '#FF' + m[1].toUpperCase();
  if ((m = c.match(/^#([0-9a-f]{3})$/i))) return '#FF' + [...m[1]].map((x) => x + x).join('').toUpperCase();
  if ((m = c.match(/^hsl\(\s*([\d.]+)\s+([\d.]+)%\s+([\d.]+)%(?:\s*\/\s*([\d.]+))?\s*\)$/i))) {
    const [r, g, b] = hslToRgb(+m[1], +m[2], +m[3]);
    return hexA(r, g, b, m[4] === undefined ? 1 : +m[4]);
  }
  if ((m = c.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/i)))
    return hexA(+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]);
  throw new Error('gen-design-tokens: cannot convert colour ' + JSON.stringify(c));
}
const argbRgb = (a) => [parseInt(a.slice(3, 5), 16), parseInt(a.slice(5, 7), 16), parseInt(a.slice(7, 9), 16)];
const lin = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
const lum = (a) => { const [r, g, b] = argbRgb(a); return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b); };
export const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

// ---- evaluate the kit ---------------------------------------------------------------------
function loadKit(src) {
  const window = {};
  const document = { createElement: () => ({ style: {}, setAttribute() {}, appendChild() {} }), documentElement: { style: {} }, body: {} };
  // kit.js is a browser IIFE that only needs `window` at load time; document is a safety net.
  runInNewContext(src, { window, document, console }, { filename: 'kit.js' });
  if (!window.OB || typeof window.OB.theme !== 'function') throw new Error('kit.js did not attach OB.theme');
  return window.OB;
}

function parseVars(css) {
  const out = {};
  for (const m of css.matchAll(/(?:^|;)\s*--([\w-]+):([^;]+)/g)) out[m[1]] = m[2].trim();
  return out;
}

// ---- shadows ------------------------------------------------------------------------------
function splitTop(s, sep = ',') {
  const parts = []; let depth = 0, cur = '';
  for (const ch of s) {
    if (ch === '(') depth++; if (ch === ')') depth--;
    if (ch === sep && depth === 0) { parts.push(cur.trim()); cur = ''; } else cur += ch;
  }
  if (cur.trim()) parts.push(cur.trim());
  return parts;
}
function parseShadow(css) {
  return splitTop(css).map((layer) => {
    const inset = /^inset\s/.test(layer);
    const body = layer.replace(/^inset\s+/, '');
    const ci = body.search(/(hsl|rgba?)\(/);
    const nums = body.slice(0, ci).trim().split(/\s+/).map((n) => parseFloat(n));
    if (nums.length < 3 || nums.length > 4 || nums.some(Number.isNaN)) throw new Error('shadow layer not understood: ' + layer);
    return { inset, dx: nums[0], dy: nums[1], blur: nums[2], spread: nums[3] || 0, color: toArgb(body.slice(ci)) };
  });
}

// ---- css type parsing ---------------------------------------------------------------------
const FAMILY_ALIAS = { 'var(--font-display)': 'display', 'var(--font-body)': 'body', 'var(--font-mono)': 'mono' };
function ruleBody(css, selectorRe) {
  const m = css.match(new RegExp('(?:^|\\})\\s*' + selectorRe + '\\s*\\{([^}]*)\\}', 'm'));
  if (!m) throw new Error('overhaul.css: rule not found: ' + selectorRe);
  return m[1];
}
function parseFont(body, who, vars) {
  const decl = (p) => (body.match(new RegExp('(?:^|;)\\s*' + p + ':([^;]+)')) || [])[1]?.trim();
  const sub = (s) => s.replace(/var\(--([\w-]+)\)/g, (all, n) => (vars[n] !== undefined ? vars[n] : all));
  let weight, size, height, family;
  const f = decl('font');
  if (f) {
    const m = sub(f).match(/^(\d+)\s+([\d.]+)px(?:\/([\d.]+))?\s+(.+)$/);
    if (!m) throw new Error('font shorthand not understood for ' + who + ': ' + f);
    weight = +m[1]; size = +m[2]; height = m[3] === undefined ? null : +m[3];
    family = FAMILY_ALIAS[m[4].trim()] || m[4].trim();
  } else {
    size = parseFloat(decl('font-size')); weight = decl('font-weight') ? +decl('font-weight') : 400; height = decl('line-height') ? +decl('line-height') : null;
    family = 'body';
  }
  const ls = decl('letter-spacing');
  const upper = /text-transform:\s*uppercase/.test(body);
  return { family, size, weight, lineHeight: height, letterSpacingEm: ls ? parseFloat(ls) : 0, uppercase: upper };
}

// ---- main extraction ----------------------------------------------------------------------
export function extract(kitSrc, cssSrc, adjustList = []) {
  const OB = loadKit(kitSrc);
  const css = cssSrc;

  // palettes
  const KIT_TO_FLUTTER = { olive: 'olive', classic: 'classic', calm: 'calmModern', warm: 'warmGrounded', playful: 'softPlayful', cozy: 'deepCozy', bold: 'brightBold' };
  const kitKeys = Object.keys(OB.SEEDS);
  if (JSON.stringify(kitKeys) !== JSON.stringify(Object.keys(KIT_TO_FLUTTER))) throw new Error('kit palettes changed: ' + kitKeys + ' — update KIT_TO_FLUTTER and theme.dart');

  const SEMANTIC_KEYS = ['ok', 'okC', 'warn', 'warnC', 'bad', 'badC', 'info', 'infoC'];
  const DAYPART_KEYS = ['dpMorning', 'dpDay', 'dpAfternoon', 'dpEvening', 'dpBed', 'dpNight'];
  const SHADOW_KEYS = ['shadow0', 'shadow1', 'shadow2', 'shadow3'];
  const palettes = {}, semantic = { light: null, dark: null }, elevation = {}, sheen = { light: null, dark: null };

  for (const kk of kitKeys) {
    const id = KIT_TO_FLUTTER[kk];
    palettes[id] = { kitKey: kk, name: OB.SEEDS[kk].n, note: OB.SEEDS[kk].note, seed: toArgb(OB.SEEDS[kk].seed), light: {}, dark: {} };
    elevation[id] = { light: {}, dark: {} };
    for (const mode of ['light', 'dark']) {
      const v = parseVars(OB.theme(kk, mode));
      const roles = {};
      for (const [k, val] of Object.entries(v)) {
        if (SHADOW_KEYS.includes(k)) { elevation[id][mode][k] = parseShadow(val); continue; }
        if (k === 'sheen') { const s = +val; if (sheen[mode] !== null && sheen[mode] !== s) throw new Error('sheen differs per palette'); sheen[mode] = s; continue; }
        if (SEMANTIC_KEYS.includes(k) || DAYPART_KEYS.includes(k)) {
          semantic[mode] = semantic[mode] || {};
          const c = toArgb(val);
          if (semantic[mode][k] !== undefined && semantic[mode][k] !== c) throw new Error(`protected colour ${k} differs between palettes — the kit broke MASTERFILE 8.6.2`);
          semantic[mode][k] = c; continue;
        }
        roles[k] = toArgb(val);
      }
      palettes[id][mode] = roles;
    }
  }

  // documented overrides of the prototype (empty unless verification found a real AA failure)
  const adjustments = [];
  for (const a of adjustList) {
    const [pal, mode, role] = a.path.split('/');
    adjustments.push({ path: a.path, from: palettes[pal][mode][role], to: a.to, reason: a.reason });
    palettes[pal][mode][role] = a.to;
  }
  // derived roles the kit does not define but Flutter's ColorScheme needs (documented, deterministic)
  const white = '#FFFFFFFF';
  for (const id of Object.keys(palettes)) for (const mode of ['light', 'dark']) {
    const r = palettes[id][mode], sem = semantic[mode];
    // text on the accent colour and on the error colour: the best of white / the page background / the ink
    const best = (bg) => [white, r.bg, r.ink].reduce((a, b) => (ratio(b, bg) > ratio(a, bg) ? b : a));
    r.onAccent = best(r.accent);
    r.onBad = best(sem.bad);
  }

  // type
  const rootVars = parseVars(ruleBody(css, ':root').replace(/\n/g, ' '));
  const ob = parseVars(ruleBody(css, '\\.ob').replace(/\/\*[^*]*\*\//g, '').replace(/\n/g, ' ').split('font-family')[0]);
  const fsVars = {};
  for (const [k, val] of Object.entries(ob)) if (k.startsWith('fs-')) fsVars[k] = val;
  const sub = {}; for (const [k, val] of Object.entries(fsVars)) sub[k] = val;
  const SPECS = {
    display: '\\.ob \\.t-display', title: '\\.ob \\.t-title', head: '\\.ob \\.t-head', body: '\\.ob \\.t-body', cap: '\\.ob \\.t-cap',
    label: '\\.ob \\.t-label', buttonSm: '\\.ob \\.btn\\.sm', buttonLg: '\\.ob \\.btn\\.lg', mono: '\\.ob \\.t-mono', big: '\\.ob \\.big', cardHead: '\\.ob \\.card h4', button: '\\.ob \\.btn',
    rowTitle: '\\.ob \\.rtxt b', rowSub: '\\.ob \\.rtxt small', tabLabel: '\\.ob \\.tabbar small', pill: '\\.ob \\.stat-pill', pillSm: '\\.ob \\.stat-pill\\.sm',
    fieldInput: '\\.ob \\.fc input', fieldLabel: '\\.ob \\.ff label',
  };
  const scale = {};
  for (const [name, sel] of Object.entries(SPECS)) {
    const body = ruleBody(css, sel);
    const spec = parseFont(body, name, sub);
    // .btn.sm and .btn.lg only override the size; weight, family, line-height and tracking are .btn's
    if (name === 'pillSm') { spec.family = scale.pill.family; spec.weight = scale.pill.weight; spec.lineHeight = scale.pill.lineHeight; }
    if (name === 'rowTitle') { spec.lineHeight = spec.lineHeight ?? 1.25; }
    scale[name] = spec;
  }
  // .btn.sm and .btn.lg only override the size; weight, family, line-height and tracking are .btn's
  for (const n of ['buttonSm', 'buttonLg']) { const b = scale.button; Object.assign(scale[n], { family: b.family, weight: b.weight, lineHeight: b.lineHeight, letterSpacingEm: b.letterSpacingEm }); }
  // the kit's own fallbacks for a missing line-height
  for (const s of Object.values(scale)) if (s.lineHeight === null) s.lineHeight = 1.4;
  const families = {};
  for (const [k, role] of [['font-display', 'display'], ['font-body', 'body'], ['font-mono', 'mono']]) {
    families[role] = rootVars[k].split(',').map((x) => x.trim().replace(/^"|"$/g, ''));
  }

  const px = (s) => parseFloat(s);
  const radii = {}, spacing = {};
  for (const [k, val] of Object.entries(ob)) {
    if (/^r\d$/.test(k)) radii[k] = px(val);
    if (/^sp\d$/.test(k)) spacing[k] = px(val);
  }
  const motion = { durationsMs: {}, easings: {} };
  for (const [k, val] of Object.entries(ob)) {
    if (k.startsWith('d-')) motion.durationsMs[k.slice(2)] = parseFloat(val);
    if (k.startsWith('ease-')) {
      const m = val.match(/^cubic-bezier\(([^)]+)\)$/); if (!m) throw new Error('easing not understood: ' + val);
      motion.easings[k.slice(5)] = m[1].split(',').map(Number);
    }
  }
  motion.reducedMotion = { durationMs: 0.01, note: '@media (prefers-reduced-motion: reduce) collapses every animation and transition to 0.01ms; Flutter honours MediaQuery.disableAnimations' };

  const fm = css.match(/\.ob :focus-visible\{outline:(\d+)px solid var\(--(\w+)\);outline-offset:(\d+)px\}/);
  if (!fm) throw new Error('focus ring rule not found');
  const focusRing = { width: +fm[1], offset: +fm[3], colorRole: fm[2] };
  const fieldFocus = css.match(/\.ob \.fc:focus-within\{border-color:var\(--(\w+)\);box-shadow:0 0 0 (\d+)px color-mix\(in srgb,var\(--(\w+)\) (\d+)%,transparent\)\}/);
  if (!fieldFocus) throw new Error('field focus rule not found');
  focusRing.field = { borderRole: fieldFocus[1], haloWidth: +fieldFocus[2], haloRole: fieldFocus[3], haloAlpha: +fieldFocus[4] / 100 };

  // state pills: shape + icon + word, never colour alone
  const iconSvg = (n) => OB.ico(n, 14, 2.2);
  const statePills = {};
  const toneCss = {};
  for (const m of css.matchAll(/\.ob \.stat-pill\.(\w+)\{background:var\(--(\w+)\);color:var\(--(\w+)\)\}/g)) toneCss[m[1]] = { bg: m[2], fg: m[3] };
  const KINDS = ['queued', 'sent', 'delivered', 'watched', 'failed', 'banked'];
  for (const kind of KINDS) {
    const html = OB.status(kind);
    const m = html.match(/^<span class="stat-pill (\w+)" data-k="(\w+)">(<svg.*<\/svg>)(.*)<\/span>$/);
    if (!m) throw new Error('status pill markup changed for ' + kind);
    const icon = OB.ICONS.find((n) => iconSvg(n) === m[3]);
    if (!icon) throw new Error('status pill icon not found in the icon table for ' + kind);
    const tone = m[1];
    const shape = kind === 'queued' ? 'dashed' : kind === 'failed' ? 'outline' : kind === 'watched' ? 'ring' : 'solid';
    statePills[kind] = { label: m[4], icon, tone, background: toneCss[tone].bg, foreground: toneCss[tone].fg, shape };
  }
  const bg = css.match(/\.ob \.stat-pill\[data-k=queued\]\{background:transparent;border:1\.5px dashed currentColor\}/);
  if (!bg) throw new Error('queued pill shape rule changed');

  // icons: the 24-grid stroke table
  const icons = {};
  const iconStyle = OB.ico(OB.ICONS[0]).match(/viewBox="0 0 (\d+) \d+".*stroke-width="([\d.]+)" stroke-linecap="(\w+)" stroke-linejoin="(\w+)"/);
  for (const n of OB.ICONS) {
    const m = OB.ico(n).match(/^<svg[^>]*>(.*)<\/svg>$/);
    if (!m) throw new Error('icon markup changed: ' + n);
    icons[n] = m[1];
  }
  const iconSpec = { grid: +iconStyle[1], defaultSize: 22, defaultStrokeWidth: 1.8, cap: iconStyle[3], join: iconStyle[4], fill: 'none', stroke: 'currentColor' };

  // spot illustrations (the plate-less inner markup; var(--role) resolves against the palette roles)
  const spots = {};
  for (const n of OB.SPOTS) {
    const m = OB.spot(n, 96, { plate: false }).match(/^<svg[^>]*>(.*)<\/svg>$/);
    if (!m) throw new Error('spot markup changed: ' + n);
    spots[n] = m[1];
  }
  const plateM = OB.spot('leaf', 96, {}).match(/<rect width="96" height="96" rx="(\d+)" fill="var\(--(\w+)\)"\/>/);
  const plateA = OB.spot('leaf', 96, { tone: 'accent' }).match(/<rect width="96" height="96" rx="(\d+)" fill="var\(--(\w+)\)"\/>/);
  const spotPlate = { viewBox: 96, radius: +plateM[1], fillRole: plateM[2], accentFillRole: plateA[2] };

  // component metrics the theme must honour (parsed, never retyped)
  const prop = (sel, p) => { const m = ruleBody(css, sel).match(new RegExp('(?:^|;)\\s*' + p + ':\\s*([\\d.]+)(px)?')); if (!m) throw new Error('overhaul.css: ' + p + ' missing in ' + sel); return parseFloat(m[1]); };
  const components = {
    button: { minHeight: prop('\\.ob \\.btn', 'min-height'), radius: prop('\\.ob \\.btn', 'border-radius'), borderWidthGhost: 1.5 },
    buttonLarge: { minHeight: prop('\\.ob \\.btn\\.lg', 'min-height'), radius: prop('\\.ob \\.btn\\.lg', 'border-radius') },
    buttonSmall: { minHeight: prop('\\.ob \\.btn\\.sm', 'min-height'), radius: prop('\\.ob \\.btn\\.sm', 'border-radius') },
    field: { minHeight: prop('\\.ob \\.fc', 'min-height'), radius: prop('\\.ob \\.fc', 'border-radius'), borderWidth: 1.5 },
    chip: { minHeight: prop('\\.ob \\.fchip', 'min-height'), borderWidth: 1.5 },
    toggle: { width: prop('\\.ob \\.tgl', 'width'), height: prop('\\.ob \\.tgl', 'height') },
    checkbox: { size: prop('\\.ob \\.chk,\\.ob \\.rad', 'width'), radius: prop('\\.ob \\.chk', 'border-radius'), borderWidth: 2 },
    iconButton: { visual: prop('\\.ob \\.cbtn', 'width'), hit: 48 },
    tabItem: { minHeight: prop('\\.ob \\.tabbar span', 'min-height') },
    sliderTrack: { height: 6, thumb: 26 },
  };
  if (components.button.radius !== components.field.radius) throw new Error('button and field radius diverge in the kit');

  const forms = JSON.parse(JSON.stringify(OB.FORMS));

  // ---- contrast verification (the kit says it did this; we do it again, for real) ---------
  const failures = [];
  const text = (name, fg, bgc, min = 4.5) => { const r = ratio(fg, bgc); if (r < min) failures.push(`${name}: ${r.toFixed(2)}:1 < ${min}`); };
  for (const id of Object.keys(palettes)) for (const mode of ['light', 'dark']) {
    const r = palettes[id][mode], sem = semantic[mode], w = `${id}/${mode}`;
    for (const s of ['bg', 'surface', 'surface2', 'surface3']) for (const t of ['ink', 'ink2', 'ink3']) text(`${w} ${t} on ${s}`, r[t], r[s]);
    text(`${w} onPri on pri`, r.onPri, r.pri); text(`${w} onPri on priD`, r.onPri, r.priD);
    text(`${w} onPriC on priC`, r.onPriC, r.priC);
    text(`${w} onAccent on accent`, r.onAccent, r.accent); text(`${w} ink on accentC`, r.ink, r.accentC);
    text(`${w} onBad on bad`, r.onBad, sem.bad);
    for (const [fg, tint] of [['ok', 'okC'], ['warn', 'warnC'], ['bad', 'badC'], ['info', 'infoC']]) { text(`${w} ${fg} on ${tint}`, sem[fg], sem[tint]); text(`${w} ${fg} on surface`, sem[fg], r.surface); }
    for (const s of ['bg', 'surface', 'surface2']) text(`${w} edge on ${s} (non-text)`, r.edge, r[s], 3);
    for (const s of ['bg', 'surface']) text(`${w} focus on ${s} (non-text)`, r.focus, r[s], 3);
    // NOT checked: focus on pri. The kit's header comment claims it, but the ring is drawn with a 2px
    // outline-offset, so it sits against the surrounding surface (checked above), never touching pri.
  }
  return { OB, palettes, semantic, elevation, sheen, scale, families, radii, spacing, components, motion, focusRing, statePills, icons, iconSpec, spots, spotPlate, scenes: OB.SCENES.slice(), forms, failures, adjustments, fsVars };
}

// ---- adjustments (documented overrides of the prototype where it fails AA) ----------------
// Keyed 'palette/mode/role'. EMPTY unless verification finds a real failure. Every entry is
// copied into tokens.json "adjustments" with the original, the replacement and the reason.
const ADJUSTMENTS = [];

export function build() {
  const kitSrc = norm(readFileSync(REF + 'kit.js', 'utf8'));
  const cssSrc = norm(readFileSync(REF + 'overhaul.css', 'utf8'));
  const x = extract(kitSrc, cssSrc, ADJUSTMENTS);
  if (x.failures.length) throw new Error(['design tokens fail WCAG AA (add a documented entry to ADJUSTMENTS or fix the kit):', ...x.failures].join('\n  '));

  const tokens = {
    $generated: 'GENERATED by scaffold/tools/gen-design-tokens.mjs from scaffold/tools/design-reference/. DO NOT EDIT. Regenerate: node tools/gen-design-tokens.mjs',
    colorFormat: '#AARRGGBB (alpha first, the same order as Flutter 0xAARRGGBB)',
    source: { kitJs: sha(kitSrc), overhaulCss: sha(cssSrc), reference: 'docs/superpowers/mockups/live (kit.js, overhaul.css)' },
    palettes: x.palettes,
    semantic: x.semantic,
    sheen: x.sheen,
    elevation: x.elevation,
    type: { families: x.families, scale: x.scale, fontSizeVars: x.fsVars },
    radii: x.radii,
    spacing: x.spacing,
    components: x.components,
    motion: x.motion,
    focusRing: x.focusRing,
    statePills: x.statePills,
    icons: { spec: x.iconSpec, paths: x.icons },
    spots: { plate: x.spotPlate, shapes: x.spots },
    scenes: x.scenes,
    forms: x.forms,
    adjustments: x.adjustments,
    derived: {
      onAccent: 'not in the kit: the best of white, the page background and the ink on the accent colour (Flutter ColorScheme.onSecondary needs it)',
      onBad: 'not in the kit: the best of white, the page background and the ink on the bad colour (Flutter ColorScheme.onError needs it)',
    },
  };
  return tokens;
}

// ---- dart ----------------------------------------------------------------------------------
const cap = (s) => s[0].toUpperCase() + s.slice(1);
const argbInt = (s) => '0x' + s.slice(1);
const dnum = (n) => (Number.isInteger(n) ? n.toFixed(1) : String(n));
export function toDart(t) {
  const pal = Object.keys(t.palettes);
  const roles = Object.keys(t.palettes[pal[0]].light);
  const sem = Object.keys(t.semantic.light);
  const L = [];
  L.push(`// OLIVE BRANCH — design tokens generated from the prototype's design kit. No longer UNVERIFIED —`);
  L.push(`// verified by CI (tools/test/design_tokens.test.mjs regenerates and compares; test/design_parity_test.dart`);
  L.push(`// asserts the real theme equals these values).`);
  L.push(`//`);
  L.push(`// GENERATED FILE — DO NOT EDIT. Source: scaffold/tools/design-reference/{kit.js,overhaul.css}`);
  L.push(`// (a snapshot of docs/superpowers/mockups/live). Regenerate: cd scaffold && node tools/gen-design-tokens.mjs`);
  L.push(`// See docs/superpowers/parity/PARITY.md. The prototype is the reference; Flutter must match it.`);
  L.push(`// source hashes: kit.js ${t.source.kitJs}, overhaul.css ${t.source.overhaulCss}`);
  L.push(``);
  L.push(`enum DesignPalette { ${pal.join(', ')} }`);
  L.push(`enum DesignMode { light, dark }`);
  L.push(`/// Per-palette colour roles (the kit's CSS variables, same names).`);
  L.push(`enum DesignRole { ${roles.join(', ')} }`);
  L.push(`/// Protected colours: identical in every palette, never taken from one (MASTERFILE 8.6.2).`);
  L.push(`enum DesignSemantic { ${sem.join(', ')} }`);
  L.push(``);
  L.push(`const Map<DesignPalette, int> kDesignSeeds = {`);
  for (const p of pal) L.push(`  DesignPalette.${p}: ${argbInt(t.palettes[p].seed)},`);
  L.push(`};`);
  L.push(`const Map<DesignPalette, String> kDesignPaletteNames = {`);
  for (const p of pal) L.push(`  DesignPalette.${p}: '${t.palettes[p].name}',`);
  L.push(`};`);
  L.push(``);
  L.push(`const Map<DesignPalette, Map<DesignMode, Map<DesignRole, int>>> kDesignColors = {`);
  for (const p of pal) {
    L.push(`  DesignPalette.${p}: {`);
    for (const m of ['light', 'dark']) {
      L.push(`    DesignMode.${m}: {`);
      for (const r of roles) L.push(`      DesignRole.${r}: ${argbInt(t.palettes[p][m][r])},`);
      L.push(`    },`);
    }
    L.push(`  },`);
  }
  L.push(`};`);
  L.push(``);
  L.push(`const Map<DesignMode, Map<DesignSemantic, int>> kDesignSemantic = {`);
  for (const m of ['light', 'dark']) {
    L.push(`  DesignMode.${m}: {`);
    for (const s of sem) L.push(`    DesignSemantic.${s}: ${argbInt(t.semantic[m][s])},`);
    L.push(`  },`);
  }
  L.push(`};`);
  L.push(`/// The hero card's highlight strength (the kit's --sheen).`);
  L.push(`const Map<DesignMode, double> kDesignSheen = {DesignMode.light: ${t.sheen.light}, DesignMode.dark: ${t.sheen.dark}};`);
  L.push(``);
  L.push(`/// One CSS box-shadow layer. [inset] layers cannot be drawn by Flutter's BoxShadow and are`);
  L.push(`/// skipped by the theme; they are kept so the data stays a faithful copy of the kit.`);
  L.push(`class DesignShadow {`);
  L.push(`  const DesignShadow(this.dx, this.dy, this.blur, this.spread, this.color, {this.inset = false});`);
  L.push(`  final double dx, dy, blur, spread;`);
  L.push(`  final int color;`);
  L.push(`  final bool inset;`);
  L.push(`}`);
  L.push(`/// Elevation levels 0 (hairline) to 3 (modal) per palette and mode.`);
  L.push(`const Map<DesignPalette, Map<DesignMode, List<List<DesignShadow>>>> kDesignElevation = {`);
  for (const p of pal) {
    L.push(`  DesignPalette.${p}: {`);
    for (const m of ['light', 'dark']) {
      L.push(`    DesignMode.${m}: [`);
      for (let i = 0; i < 4; i++) {
        L.push(`      [` + t.elevation[p][m]['shadow' + i].map((s) => `DesignShadow(${dnum(s.dx)}, ${dnum(s.dy)}, ${dnum(s.blur)}, ${dnum(s.spread)}, ${argbInt(s.color)}${s.inset ? ', inset: true' : ''})`).join(', ') + `],`);
      }
      L.push(`    ],`);
    }
    L.push(`  },`);
  }
  L.push(`};`);
  L.push(``);
  L.push(`/// One entry of the type scale. [family] is 'display' | 'body' | 'mono'; [letterSpacingEm] is in em.`);
  L.push(`class DesignTextSpec {`);
  L.push(`  const DesignTextSpec(this.family, this.size, this.weight, this.lineHeight, this.letterSpacingEm, {this.uppercase = false});`);
  L.push(`  final String family;`);
  L.push(`  final double size, lineHeight, letterSpacingEm;`);
  L.push(`  final int weight;`);
  L.push(`  final bool uppercase;`);
  L.push(`}`);
  L.push(`const Map<String, List<String>> kDesignFontFamilies = {`);
  for (const [k, v] of Object.entries(t.type.families)) L.push(`  '${k}': [${v.map((x) => `'${x}'`).join(', ')}],`);
  L.push(`};`);
  L.push(`const Map<String, DesignTextSpec> kDesignType = {`);
  for (const [k, s] of Object.entries(t.type.scale)) L.push(`  '${k}': DesignTextSpec('${s.family}', ${dnum(s.size)}, ${s.weight}, ${dnum(s.lineHeight)}, ${dnum(s.letterSpacingEm)}${s.uppercase ? ', uppercase: true' : ''}),`);
  L.push(`};`);
  L.push(``);
  L.push(`const Map<String, double> kDesignRadii = {` + Object.entries(t.radii).map(([k, v]) => `'${k}': ${dnum(v)}`).join(', ') + `};`);
  L.push(`const Map<String, double> kDesignSpacing = {` + Object.entries(t.spacing).map(([k, v]) => `'${k}': ${dnum(v)}`).join(', ') + `};`);
  L.push(`/// Component metrics: [group][metric], logical px.`);
  L.push(`const Map<String, Map<String, double>> kDesignComponents = {`);
  for (const [g, o] of Object.entries(t.components)) L.push(`  '${g}': {` + Object.entries(o).map(([k, v]) => `'${k}': ${dnum(v)}`).join(', ') + `},`);
  L.push(`};`);
  L.push(`/// Motion durations in milliseconds (press, fast, base, slow).`);
  L.push(`const Map<String, int> kDesignDurationsMs = {` + Object.entries(t.motion.durationsMs).map(([k, v]) => `'${k}': ${Math.round(v)}`).join(', ') + `};`);
  L.push(`/// Cubic-bezier control points [x1, y1, x2, y2].`);
  L.push(`const Map<String, List<double>> kDesignEasings = {` + Object.entries(t.motion.easings).map(([k, v]) => `'${k}': [${v.map(dnum).join(', ')}]`).join(', ') + `};`);
  L.push(``);
  L.push(`const double kDesignFocusWidth = ${dnum(t.focusRing.width)};`);
  L.push(`const double kDesignFocusOffset = ${dnum(t.focusRing.offset)};`);
  L.push(`const DesignRole kDesignFocusRole = DesignRole.${t.focusRing.colorRole};`);
  L.push(`const double kDesignFieldHaloWidth = ${dnum(t.focusRing.field.haloWidth)};`);
  L.push(`const double kDesignFieldHaloAlpha = ${t.focusRing.field.haloAlpha};`);
  L.push(``);
  L.push(`/// State pills: shape + icon + word, never colour alone. [shape] is solid | dashed | outline | ring;`);
  L.push(`/// [background]/[foreground] name a DesignRole (pri tone) or a DesignSemantic.`);
  L.push(`class DesignStatePill {`);
  L.push(`  const DesignStatePill(this.label, this.icon, this.tone, this.background, this.foreground, this.shape);`);
  L.push(`  final String label, icon, tone, background, foreground, shape;`);
  L.push(`}`);
  L.push(`const Map<String, DesignStatePill> kDesignStatePills = {`);
  for (const [k, s] of Object.entries(t.statePills)) L.push(`  '${k}': DesignStatePill('${s.label}', '${s.icon}', '${s.tone}', '${s.background}', '${s.foreground}', '${s.shape}'),`);
  L.push(`};`);
  L.push(``);
  L.push(`/// Device content sizes in logical px (width, height) the prototype frames use.`);
  L.push(`const Map<String, List<double>> kDesignForms = {` + Object.entries(t.forms).map(([k, v]) => `'${k}': [${v.map(dnum).join(', ')}]`).join(', ') + `};`);
  L.push(``);
  L.push(`/// Icon shape markup (24-grid, stroke ${t.icons.spec.defaultStrokeWidth}, ${t.icons.spec.cap} caps, ${t.icons.spec.join} joins, fill none).`);
  L.push(`const double kDesignIconGrid = ${dnum(t.icons.spec.grid)};`);
  L.push(`const double kDesignIconStroke = ${dnum(t.icons.spec.defaultStrokeWidth)};`);
  L.push(`const Map<String, String> kDesignIcons = {`);
  for (const [k, v] of Object.entries(t.icons.paths)) L.push(`  '${k}': ${dq(v)},`);
  L.push(`};`);
  L.push(`/// Spot illustrations (96 x 96, plate excluded). var(--role) names a DesignRole.`);
  L.push(`const double kDesignSpotPlateRadius = ${dnum(t.spots.plate.radius)};`);
  L.push(`const Map<String, String> kDesignSpots = {`);
  for (const [k, v] of Object.entries(t.spots.shapes)) L.push(`  '${k}': ${dq(v)},`);
  L.push(`};`);
  L.push(`const List<String> kDesignScenes = [${t.scenes.map((s) => `'${s}'`).join(', ')}];`);
  L.push(``);
  return L.join('\n');
}
/** A Dart string literal for arbitrary markup. */
function dq(s) {
  return "'" + s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'";
}

export function render() {
  const tokens = build();
  return { tokens, json: JSON.stringify(tokens, null, 1) + '\n', dart: toDart(tokens) };
}

if (process.argv[1] && process.argv[1].endsWith('gen-design-tokens.mjs')) {
  const { json, dart } = render();
  if (process.argv.includes('--print')) process.stdout.write(json);
  else if (process.argv.includes('--check')) {
    const rd = (p) => (existsSync(p) ? norm(readFileSync(p, 'utf8')) : '');
    const stale = [];
    if (rd(OUT_JSON) !== json) stale.push('assets/design/tokens.json');
    if (rd(OUT_DART) !== dart) stale.push('lib/design_tokens_generated.dart');
    if (stale.length) { console.error('STALE: ' + stale.join(', ') + ' — run: node tools/gen-design-tokens.mjs'); process.exit(1); }
    console.log('design tokens are up to date');
  } else {
    mkdirSync(OUT_JSON.replace(/[\\/][^\\/]+$/, ''), { recursive: true });
    writeFileSync(OUT_JSON, json); writeFileSync(OUT_DART, dart);
    console.log('wrote assets/design/tokens.json', json.length, 'bytes and lib/design_tokens_generated.dart', dart.length, 'bytes');
  }
}
