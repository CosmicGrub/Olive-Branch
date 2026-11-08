// Generates client/lib/ui/olive_art_data.dart: the premium kit's 24-grid stroke icon set (the IC
// table in kit.js), its scene illustrations and its spot illustrations, as DATA the Flutter
// CustomPainter (client/lib/ui/olive_vector.dart) draws. Nothing is hand-copied: the kit's own
// JavaScript is executed in a sandbox (OB.ico / OB.scene / OB.spot), the SVG it emits is parsed and
// normalised (rect/circle/ellipse/polygon/arcs all become absolute move/line/quad/cubic path
// commands), and that is written out as const Dart.
//
// The reference kit lives OUTSIDE git (docs/superpowers/mockups/live/kit.js is untracked work), so the
// committed snapshot tools/design-reference/kit.js (shared with gen-design-tokens.mjs, see PARITY.md)
// is the input. tools/test/olive_art.test.mjs fails if the committed Dart is stale against it.
//
// usage: node tools/gen-olive-icons.mjs          (writes client/lib/ui/olive_art_data.dart)
//        node tools/gen-olive-icons.mjs --print  (prints, writes nothing)
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const HERE = fileURLToPath(new URL('.', import.meta.url));
/** The committed snapshot of the reference kit (shared with gen-design-tokens.mjs, see PARITY.md). */
export const SNAPSHOT_PATH = HERE + 'design-reference/kit.js';
export const OUT_PATH = HERE + '../client/lib/ui/olive_art_data.dart';

/** Palette tokens the Dart side knows (OTok in olive_vector.dart). Anything else is a generator error. */
export const TOKENS = ['bg', 'surface', 'surface2', 'surface3', 'line', 'edge', 'ink', 'ink2', 'ink3', 'pri', 'priD', 'priC', 'priC2',
  'onPri', 'onPriC', 'accent', 'accentC', 'ok', 'okC', 'warn', 'warnC', 'bad', 'badC', 'info', 'infoC',
  'dpMorning', 'dpDay', 'dpAfternoon', 'dpEvening', 'dpBed', 'dpNight'];

// ------------------------------------------------------------------ kit source
/** The icon table + illustration code of kit.js: the OB initialiser line and the icons-to-components block. */
export function extractBody(kitSource) {
  const lines = kitSource.replace(/\r\n/g, '\n').split('\n');
  const init = lines.findIndex((l) => l.startsWith('var OB=window.OB='));
  const a = lines.findIndex((l) => /^\/\* -+ icons -+ \*\/$/.test(l));
  const b = lines.findIndex((l) => /^\/\* -+ components -+ \*\/$/.test(l));
  if (init < 0 || a < 0 || b < 0 || !(a < b)) throw new Error('kit.js layout changed: cannot find the icon/illustration block');
  return [lines[init], ...lines.slice(a, b)].join('\n');
}

function loadKit() {
  const body = extractBody(readFileSync(SNAPSHOT_PATH, 'utf8'));
  const ctx = { window: {} };
  vm.createContext(ctx);
  vm.runInContext('(function(){"use strict";' + body + '\n})();', ctx);
  return ctx.window.OB;
}

// ------------------------------------------------------------------- numbers
const num = (v) => { const r = Math.round(v * 1000) / 1000; return Object.is(r, -0) ? 0 : r; };
const fmt = (v) => { const s = String(num(v)); return s.includes('.') || s.includes('e') ? s : s + '.0'; };

// -------------------------------------------------------------- path parsing
const ARGC = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
function tokenisePath(d) {
  // Returns [{cmd, args}] with arc flags handled the SVG way (a flag is exactly one character).
  const out = []; let i = 0; const n = d.length;
  const skip = () => { while (i < n && /[\s,]/.test(d[i])) i++; };
  const readNum = () => {
    skip(); const m = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/.exec(d.slice(i));
    if (!m) throw new Error('bad number at ' + i + ' in ' + d);
    i += m[0].length; return parseFloat(m[0]);
  };
  const readFlag = () => { skip(); const c = d[i]; if (c !== '0' && c !== '1') throw new Error('bad arc flag in ' + d); i++; return Number(c); };
  while (true) {
    skip(); if (i >= n) break;
    const c = d[i]; if (!/[a-zA-Z]/.test(c)) throw new Error('expected command at ' + i + ' in ' + d);
    i++;
    const up = c.toUpperCase(); const argc = ARGC[up];
    if (argc === 0) { out.push({ cmd: c, args: [] }); continue; }
    let first = true;
    while (true) {
      skip();
      if (i >= n || /[a-zA-Z]/.test(d[i])) { if (first) throw new Error('missing args for ' + c); break; }
      const args = [];
      for (let k = 0; k < argc; k++) args.push(up === 'A' && (k === 3 || k === 4) ? readFlag() : readNum());
      // after the first pair, M/m continues as L/l
      let cmd = c; if (!first && (c === 'M')) cmd = 'L'; if (!first && c === 'm') cmd = 'l';
      out.push({ cmd, args }); first = false;
    }
  }
  return out;
}

function arcToCubics(x1, y1, rx, ry, phiDeg, fa, fs, x2, y2) {
  if (rx === 0 || ry === 0 || (x1 === x2 && y1 === y2)) return [['L', x2, y2]];
  rx = Math.abs(rx); ry = Math.abs(ry);
  const phi = (phiDeg * Math.PI) / 180, cp = Math.cos(phi), sp = Math.sin(phi);
  const dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  const x1p = cp * dx + sp * dy, y1p = -sp * dx + cp * dy;
  const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lam > 1) { const s = Math.sqrt(lam); rx *= s; ry *= s; }
  const num2 = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  const den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  let co = Math.sqrt(Math.max(0, num2 / den)); if (fa === fs) co = -co;
  const cxp = (co * rx * y1p) / ry, cyp = (-co * ry * x1p) / rx;
  const cx = cp * cxp - sp * cyp + (x1 + x2) / 2, cy = sp * cxp + cp * cyp + (y1 + y2) / 2;
  const ang = (ux, uy, vx, vy) => { const a = Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy); return a; };
  const th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
  if (!fs && dth > 0) dth -= 2 * Math.PI; else if (fs && dth < 0) dth += 2 * Math.PI;
  const segs = Math.max(1, Math.ceil(Math.abs(dth) / (Math.PI / 2) - 1e-9));
  const delta = dth / segs, t = (4 / 3) * Math.tan(delta / 4); const out = [];
  let th = th1;
  const pt = (a) => { const ex = rx * Math.cos(a), ey = ry * Math.sin(a); return [cp * ex - sp * ey + cx, sp * ex + cp * ey + cy]; };
  const dv = (a) => { const ex = -rx * Math.sin(a), ey = ry * Math.cos(a); return [cp * ex - sp * ey, sp * ex + cp * ey]; };
  for (let s = 0; s < segs; s++) {
    const a0 = th, a1 = th + delta; const p0 = pt(a0), p1 = pt(a1), d0 = dv(a0), d1 = dv(a1);
    out.push(['C', p0[0] + t * d0[0], p0[1] + t * d0[1], p1[0] - t * d1[0], p1[1] - t * d1[1], p1[0], p1[1]]);
    th = a1;
  }
  out[out.length - 1][5] = x2; out[out.length - 1][6] = y2;
  return out;
}

/** d -> flat opcode list: 0 M x y | 1 L x y | 2 Q cx cy x y | 3 C ... | 4 Z. */
function pathToOps(d) {
  const ops = []; let cx = 0, cy = 0, sx = 0, sy = 0, lastC = null, lastQ = null;
  for (const { cmd, args } of tokenisePath(d)) {
    const rel = cmd === cmd.toLowerCase(), up = cmd.toUpperCase(); const a = args.slice();
    const ox = rel ? cx : 0, oy = rel ? cy : 0;
    let newC = null, newQ = null;
    if (up === 'M') { cx = a[0] + ox; cy = a[1] + oy; sx = cx; sy = cy; ops.push(0, cx, cy); }
    else if (up === 'L') { cx = a[0] + ox; cy = a[1] + oy; ops.push(1, cx, cy); }
    else if (up === 'H') { cx = a[0] + ox; ops.push(1, cx, cy); }
    else if (up === 'V') { cy = a[0] + oy; ops.push(1, cx, cy); }
    else if (up === 'C') { const p = [a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy, a[4] + ox, a[5] + oy]; ops.push(3, ...p); newC = [p[2], p[3]]; cx = p[4]; cy = p[5]; }
    else if (up === 'S') { const r = lastC ? [2 * cx - lastC[0], 2 * cy - lastC[1]] : [cx, cy]; const p = [a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy]; ops.push(3, r[0], r[1], ...p); newC = [p[0], p[1]]; cx = p[2]; cy = p[3]; }
    else if (up === 'Q') { const p = [a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy]; ops.push(2, ...p); newQ = [p[0], p[1]]; cx = p[2]; cy = p[3]; }
    else if (up === 'T') { const r = lastQ ? [2 * cx - lastQ[0], 2 * cy - lastQ[1]] : [cx, cy]; const p = [a[0] + ox, a[1] + oy]; ops.push(2, r[0], r[1], ...p); newQ = r; cx = p[0]; cy = p[1]; }
    else if (up === 'A') {
      const ex = a[5] + ox, ey = a[6] + oy;
      for (const seg of arcToCubics(cx, cy, a[0], a[1], a[2], a[3], a[4], ex, ey)) {
        if (seg[0] === 'L') ops.push(1, seg[1], seg[2]); else ops.push(3, ...seg.slice(1));
      }
      cx = ex; cy = ey;
    } else if (up === 'Z') { ops.push(4); cx = sx; cy = sy; }
    lastC = newC; lastQ = newQ;
  }
  return ops;
}

const K = 0.5522847498;
function ellipseOps(cx, cy, rx, ry) {
  return [0, cx + rx, cy,
    3, cx + rx, cy + K * ry, cx + K * rx, cy + ry, cx, cy + ry,
    3, cx - K * rx, cy + ry, cx - rx, cy + K * ry, cx - rx, cy,
    3, cx - rx, cy - K * ry, cx - K * rx, cy - ry, cx, cy - ry,
    3, cx + K * rx, cy - ry, cx + rx, cy - K * ry, cx + rx, cy, 4];
}
function rectOps(x, y, w, h, rx, ry) {
  rx = Math.min(rx, w / 2); ry = Math.min(ry, h / 2);
  if (!rx || !ry) return [0, x, y, 1, x + w, y, 1, x + w, y + h, 1, x, y + h, 4];
  const kx = K * rx, ky = K * ry;
  return [0, x + rx, y, 1, x + w - rx, y,
    3, x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry,
    1, x + w, y + h - ry,
    3, x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h,
    1, x + rx, y + h,
    3, x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry,
    1, x, y + ry,
    3, x, y + ry - ky, x + rx - kx, y, x + rx, y, 4];
}

// ----------------------------------------------------------- colours / paint
function parseColour(s, ctx) {
  s = s.trim();
  if (s === 'none') return 'none';
  if (s === 'currentColor') return { kind: 'current' };
  let m = /^var\(--(\w+)\)$/.exec(s);
  if (m) { if (!TOKENS.includes(m[1])) throw new Error('unknown token --' + m[1]); return { kind: 'tok', name: m[1] }; }
  m = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.exec(s);
  if (m) { let h = m[1]; if (h.length === 3) h = [...h].map((c) => c + c).join(''); return { kind: 'hex', v: parseInt(h, 16) }; }
  m = /^color-mix\(in srgb,\s*(.+?)\s+(\d+(?:\.\d+)?)%\s*,\s*(.+)\)$/.exec(s);
  if (m) return { kind: 'mix', a: parseColour(m[1]), pct: parseFloat(m[2]), b: parseColour(m[3]) };
  m = /^url\(#([\w-]+)\)$/.exec(s);
  if (m) { const g = ctx && ctx.grads[m[1]]; if (!g) throw new Error('missing gradient ' + m[1]); return { kind: 'grad', top: g[0], bottom: g[1] }; }
  throw new Error('unsupported colour: ' + s);
}
function dartColour(c) {
  if (c === 'none' || c == null) return 'null';
  if (c.kind === 'current') return 'OCol.current';
  if (c.kind === 'tok') return `OCol.v(OTok.${c.name})`;
  if (c.kind === 'hex') return `OCol.h(0xFF${c.v.toString(16).padStart(6, '0').toUpperCase()})`;
  if (c.kind === 'mix') return `OCol.mix(${dartColour(c.a)}, ${fmt(c.pct)}, ${dartColour(c.b)})`;
  if (c.kind === 'grad') return `OGrad(${dartColour(c.top)}, ${dartColour(c.bottom)})`;
  throw new Error('bad colour');
}

// ----------------------------------------------------------------- transform
const IDENT = [1, 0, 0, 1, 0, 0];
const mul = (m, n) => [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
  m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]];
function parseTransform(t) {
  let m = IDENT; const re = /(\w+)\(([^)]*)\)/g; let r;
  while ((r = re.exec(t))) {
    const a = r[2].trim().split(/[\s,]+/).map(Number);
    if (r[1] === 'translate') m = mul(m, [1, 0, 0, 1, a[0], a[1] || 0]);
    else if (r[1] === 'scale') m = mul(m, [a[0], 0, 0, a.length > 1 ? a[1] : a[0], 0, 0]);
    else if (r[1] === 'rotate') { const c = Math.cos((a[0] * Math.PI) / 180), s = Math.sin((a[0] * Math.PI) / 180); const cx = a[1] || 0, cy = a[2] || 0;
      m = mul(m, [1, 0, 0, 1, cx, cy]); m = mul(m, [c, s, -s, c, 0, 0]); m = mul(m, [1, 0, 0, 1, -cx, -cy]); }
    else throw new Error('unsupported transform ' + r[1]);
  }
  return m;
}

// ----------------------------------------------------------------- svg parse
const INHERIT = ['fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin', 'stroke-dasharray', 'fill-opacity', 'stroke-opacity', 'fill-rule'];
function parseAttrs(s) { const o = {}; const re = /([\w:-]+)="([^"]*)"/g; let m; while ((m = re.exec(s))) o[m[1]] = m[2]; return o; }

export function parseSvg(svg, { iconMode = false } = {}) {
  const tagRe = /<(\/?)([A-Za-z][\w:-]*)((?:\s+[\w:-]+="[^"]*")*)\s*(\/?)>/g;
  const root = { children: [] }; const stack = [{ node: root, style: {} }];
  const grads = {}; let curGrad = null; let viewBox = null; let m;
  // Pass 1: gradients (defs precede use, but resolve in order anyway).
  while ((m = tagRe.exec(svg))) {
    const [, close, name, attrStr, selfClose] = m; const at = parseAttrs(attrStr);
    if (close) { if (name === 'linearGradient') curGrad = null; if (name === 'g') stack.pop(); continue; }
    if (name === 'svg') {
      viewBox = (at.viewBox || '0 0 24 24').split(/\s+/).map(Number);
      const st = {}; for (const k of INHERIT) if (at[k] != null) st[k] = at[k];
      stack[0].style = st; continue;
    }
    if (name === 'defs') continue;
    if (name === 'linearGradient') { curGrad = { id: at.id, stops: [] }; if (!(at.x1 === '0' && at.y1 === '0' && at.x2 === '0' && at.y2 === '1')) throw new Error('only vertical gradients are supported'); if (selfClose) curGrad = null; continue; }
    if (name === 'stop') { curGrad.stops.push(at['stop-color']); if (curGrad.stops.length === 2) grads[curGrad.id] = curGrad.stops.map((c) => parseColour(c)); continue; }
    const top = stack[stack.length - 1];
    const style = { ...top.style }; for (const k of INHERIT) if (at[k] != null) style[k] = at[k];
    if (name === 'g') {
      const needsGroup = at.opacity != null || at.transform != null;
      const node = needsGroup ? { group: true, opacity: at.opacity != null ? parseFloat(at.opacity) : 1, m: at.transform ? parseTransform(at.transform) : null, children: [] } : top.node;
      if (needsGroup) top.node.children.push(node);
      if (!selfClose) stack.push({ node, style });
      continue;
    }
    let ops;
    if (name === 'path') ops = pathToOps(at.d);
    else if (name === 'rect') { const rx = at.rx != null ? +at.rx : (at.ry != null ? +at.ry : 0); const ry = at.ry != null ? +at.ry : rx; ops = rectOps(+(at.x || 0), +(at.y || 0), +at.width, +at.height, rx, ry); }
    else if (name === 'circle') ops = ellipseOps(+at.cx, +at.cy, +at.r, +at.r);
    else if (name === 'ellipse') ops = ellipseOps(+at.cx, +at.cy, +at.rx, +at.ry);
    else if (name === 'polygon') { const p = at.points.trim().split(/[\s,]+/).map(Number); ops = []; for (let i = 0; i < p.length; i += 2) ops.push(i ? 1 : 0, p[i], p[i + 1]); ops.push(4); }
    else throw new Error('unsupported element <' + name + '>');
    // SVG's default fill is black. Every kit shape names its fill except open stroke-only lines (the
    // garden stems), whose black fill is degenerate (zero area); those are treated as fill none.
    const stroke = style.stroke != null ? parseColour(style.stroke, { grads }) : 'none';
    let fill;
    if (style.fill != null) fill = parseColour(style.fill, { grads });
    else if (stroke !== 'none') fill = 'none';
    else throw new Error('shape with neither fill nor stroke: ' + JSON.stringify(at));
    if (fill === 'none' && stroke === 'none') continue; // draws nothing (the kit has one such no-op circle)
    const shape = {
      ops, fill, stroke,
      sw: style['stroke-width'] != null ? parseFloat(style['stroke-width']) : 1,
      cap: style['stroke-linecap'] === 'round' ? 1 : style['stroke-linecap'] === 'square' ? 2 : 0,
      join: style['stroke-linejoin'] === 'round' ? 1 : style['stroke-linejoin'] === 'bevel' ? 2 : 0,
      dash: style['stroke-dasharray'] ? style['stroke-dasharray'].split(/[\s,]+/).map(Number) : null,
      fo: style['fill-opacity'] != null ? parseFloat(style['fill-opacity']) : 1,
      so: style['stroke-opacity'] != null ? parseFloat(style['stroke-opacity']) : 1,
      opacity: at.opacity != null ? parseFloat(at.opacity) : 1,
    };
    if (iconMode && fill === 'none' && stroke !== 'none') shape.sw = 1;
    if (at.transform) top.node.children.push({ group: true, opacity: 1, m: parseTransform(at.transform), children: [shape] });
    else top.node.children.push(shape);
  }
  return { viewBox, nodes: root.children };
}

// ---------------------------------------------------------------- dart emit
function emitNode(n, ind) {
  const pad = ' '.repeat(ind);
  if (n.group) {
    const opts = [];
    if (n.opacity !== 1) opts.push(`opacity: ${fmt(n.opacity)}`);
    if (n.m) opts.push(`m: [${n.m.map(fmt).join(', ')}]`);
    return `${pad}OGroup([\n${n.children.map((c) => emitNode(c, ind + 2)).join(',\n')},\n${pad}]${opts.length ? ', ' + opts.join(', ') : ''})`;
  }
  const o = [];
  if (n.fill !== 'none') o.push(`f: ${dartColour(n.fill)}`);
  if (n.stroke !== 'none') {
    o.push(`s: ${dartColour(n.stroke)}`);
    if (n.sw !== 1) o.push(`sw: ${fmt(n.sw)}`);
    if (n.cap) o.push(`cap: ${n.cap}`);
    if (n.join) o.push(`join: ${n.join}`);
    if (n.dash) o.push(`dash: [${n.dash.map(fmt).join(', ')}]`);
    if (n.so !== 1) o.push(`so: ${fmt(n.so)}`);
  }
  if (n.fo !== 1) o.push(`fo: ${fmt(n.fo)}`);
  if (n.opacity !== 1) o.push(`opacity: ${fmt(n.opacity)}`);
  return `${pad}OPath([${n.ops.map((v, i) => (Number.isInteger(v) && isOp(n.ops, i) ? String(v) : fmt(v))).join(', ')}]${o.length ? ', ' + o.join(', ') : ''})`;
}
// Opcode positions: walk the list so integers that are coordinates still print as doubles.
function isOp(ops, idx) {
  let i = 0; const len = { 0: 3, 1: 3, 2: 5, 3: 7, 4: 1 };
  while (i < ops.length) { if (i === idx) return true; if (idx < i + len[ops[i]]) return false; i += len[ops[i]]; }
  return false;
}
const q = (s) => "'" + s + "'";

export function generate() {
  const OB = loadKit();
  const icons = OB.ICONS;
  const scenes = OB.SCENES;
  const spots = OB.SPOTS;
  const out = [];
  out.push('// No longer UNVERIFIED — verified by CI (tools/test/olive_art.test.mjs and client/test/ui/olive_art_test.dart).');
  out.push('// GENERATED by tools/gen-olive-icons.mjs from tools/design-reference/kit.js. DO NOT EDIT:');
  out.push('// a drift-guard test regenerates this file and fails if it differs. The kit icon set (IC), scene');
  out.push('// illustrations (OB.scene) and spot illustrations (OB.spot) as const data for olive_vector.dart.');
  out.push("import 'olive_vector.dart';");
  out.push('');
  out.push('/// Every kit icon name, as constants so a typo is a compile error: `OliveIcon(OliveIcons.chevR)`.');
  out.push('abstract final class OliveIcons {');
  for (const n of icons) out.push(`  static const String ${n} = '${n}';`);
  out.push(`  static const List<String> all = [${icons.map(q).join(', ')}];`);
  out.push('}');
  out.push('');
  out.push(`/// Scene illustration names (kit OB.SCENES).`);
  out.push(`const List<String> kOliveSceneNames = [${scenes.map(q).join(', ')}];`);
  out.push(`/// Spot illustration names (kit OB.SPOTS).`);
  out.push(`const List<String> kOliveSpotNames = [${spots.map(q).join(', ')}];`);
  out.push('');
  out.push('/// Icon geometry on the kit 24 grid. Strokes are drawn in the icon colour at the requested width.');
  out.push('const Map<String, List<ONode>> kOliveIconData = {');
  for (const n of icons) {
    const svg = OB.ico(n, 24, 1.8);
    const { nodes } = parseSvg(svg, { iconMode: true });
    out.push(`  '${n}': [`);
    out.push(nodes.map((x) => emitNode(x, 4)).join(',\n') + ',');
    out.push('  ],');
  }
  out.push('};');
  out.push('');
  out.push('/// Scene illustrations on a 300 x 150 canvas (draw with BoxFit.cover).');
  out.push('const Map<String, List<ONode>> kOliveSceneData = {');
  for (const n of scenes) {
    const svg = OB.scene(n, 300, 150);
    const { nodes, viewBox } = parseSvg(svg);
    if (viewBox.join(' ') !== '0 0 300 150') throw new Error('scene viewBox changed: ' + n);
    out.push(`  '${n}': [`);
    out.push(nodes.map((x) => emitNode(x, 4)).join(',\n') + ',');
    out.push('  ],');
  }
  out.push('};');
  out.push('');
  out.push('/// Spot illustrations on a 96 x 96 canvas, WITHOUT the plate (the widget draws that from the palette).');
  out.push('const Map<String, List<ONode>> kOliveSpotData = {');
  for (const n of spots) {
    const svg = OB.spot(n, 96, { plate: false });
    const { nodes, viewBox } = parseSvg(svg);
    if (viewBox.join(' ') !== '0 0 96 96') throw new Error('spot viewBox changed: ' + n);
    out.push(`  '${n}': [`);
    out.push(nodes.map((x) => emitNode(x, 4)).join(',\n') + ',');
    out.push('  ],');
  }
  out.push('};');
  out.push('');
  return out.join('\n');
}

if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('/tools/gen-olive-icons.mjs')) {
  const args = process.argv.slice(2);
  if (args[0] === '--print') {
    process.stdout.write(generate());
  } else {
    writeFileSync(OUT_PATH, generate());
    console.log('wrote', OUT_PATH);
  }
}
