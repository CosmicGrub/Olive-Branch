// Turns the LIVE prototype's per-age child homes into data the Flutter client is tested against.
//
//   docs/superpowers/mockups/live/mod-child.js   (the REFERENCE: BANDSET, TL, MORE, GROW and the four homes)
//        |  this file: reads the registry tables out of the source, then BOOTS the prototype headless
//        |  (tools/proto-headless.mjs), sets her age, renders the real child home and the More page for
//        |  every age 3 to 17, and records the tiles it actually drew (id, title, tier) in order.
//        v
//   scaffold/client/test/parity/vectors/child_home_bands.json
//
// Dart side: client/lib/child_home_bands.dart (kBandSet, kBandTiles, kMoreSet, kMoreLimit, kHomeLayout,
// kGrowPages) is asserted equal to this file by client/test/child_home_bands_test.dart, and
// tools/test/child_home_vectors.test.mjs fails if the committed file is stale, so neither side can drift.
//
// usage: node tools/gen-child-home-vectors.mjs            (writes the file)
//        node tools/gen-child-home-vectors.mjs --check    (exit 1 if the committed file is stale)
//        node tools/gen-child-home-vectors.mjs --print
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { bootPrototype, readSources } from './proto-headless.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
export const OUT = HERE + '../client/test/parity/vectors/child_home_bands.json';

/** The JS object/array literal that follows `anchor` in `src`, brace-matched, evaluated. */
function literalAfter(src, anchor) {
  const at = src.indexOf(anchor);
  if (at < 0) throw new Error('anchor not found in mod-child.js: ' + anchor);
  let i = at + anchor.length;
  const open = src[i], close = open === '{' ? '}' : ']';
  let depth = 0, inStr = null;
  const start = i;
  for (; i < src.length; i++) {
    const c = src[i];
    if (inStr) { if (c === '\\') i++; else if (c === inStr) inStr = null; continue; }
    if (c === '"' || c === "'") { inStr = c; continue; }
    if (c === open) depth++;
    else if (c === close && --depth === 0) { i++; break; }
  }
  // eslint-disable-next-line no-new-func
  return new Function('return ' + src.slice(start, i))();
}

const TILE_RE = /<button type="button" class="([^"]*)"[^>]*data-act="kid\.tile" data-arg="(\w+)" aria-label="([^"]*)"/g;
const tierOf = (cls) => (/\bhuge\b/.test(cls) ? 'huge' : /\bwide\b/.test(cls) ? 'hero' : /\bfeat\b/.test(cls) ? 'featured' : /\bkx-rowb\b/.test(cls) ? 'strip' : 'standard');

function tilesIn(html) {
  const out = [];
  for (const m of String(html).matchAll(TILE_RE)) out.push({ id: m[2], title: m[3].replace(/&amp;/g, '&'), tier: tierOf(m[1]) });
  return out;
}

export async function render() {
  const src = readSources().find((s) => s.file === 'mod-child.js').src;
  const TL = literalAfter(src, 'var TL=');
  const shelf = /TL\.shelf=(\{[^}]*\});/.exec(src);
  // eslint-disable-next-line no-new-func
  if (shelf) TL.shelf = new Function('return ' + shelf[1])();
  const BANDSET = literalAfter(src, 'var BANDSET=');
  const MORE = literalAfter(src, 'var MORE=');
  const GROW = literalAfter(src, 'var GROW=');
  const KEYS = literalAfter(src, 'var KEYS_GROW=');
  const lim = /ids=ids\.slice\(0,b==='t57'\?(\d+):(\d+)\)/.exec(src);
  if (!lim) throw new Error('More slice limit not found');
  const moreLimit = { t57: +lim[1], t812: +lim[2], t1317: +lim[2] };

  const P = await bootPrototype();
  const L = P.L;
  await P.settle(L.fastFamily(), 60000);
  for (const dev of ['g', 'k']) { const st = L.S.dev[dev].stack; L.screenDef(st[st.length - 1].id, dev).render(L.ctx(dev)); }
  const topRender = () => { const st = L.S.dev.k.stack; return L.screenDef(st[st.length - 1].id, 'k').render(L.ctx('k')); };

  const homes = {}, mores = {}, growBands = {};
  for (let age = 3; age <= 17; age++) {
    L.S.family.child.age = age; L.setAge(age); L.reroot('k', 'home');
    L.S.kid.hidden = {};
    let html = topRender();               // the first render notices the birthday (growCheck) and may draw the grow page
    if (L.S.kid.grow && L.S.kid.grow.state === 'ready') { growBands[age] = L.S.kid.grow.key; L.S.kid.grow.state = 'seen'; html = topRender(); }
    const home = tilesIn(html);
    L.S.family.child.birthday = null;
    const more = tilesIn(L.screenDef('k.more', 'k').render(L.ctx('k')));
    homes[age] = { band: L.S.kid.shown.band, tiles: home };
    mores[age] = more.map(({ id, title }) => ({ id, title }));
  }
  // The same More page for a child who has a birthday on file (the 'birthday' tile shows under 11).
  const moresWithBirthday = {};
  for (let age = 5; age <= 12; age++) {
    L.S.family.child.age = age; L.setAge(age); L.reroot('k', 'home');
    L.S.family.child.birthday = { m: 3, d: 14 };
    moresWithBirthday[age] = tilesIn(L.screenDef('k.more', 'k').render(L.ctx('k'))).map((t) => t.id);
  }
  if (P.errors.length) throw new Error('prototype errors: ' + P.errors.slice(0, 3).join(' | '));

  const doc = {
    note: 'Generated by tools/gen-child-home-vectors.mjs from docs/superpowers/mockups/live/mod-child.js. Do not edit.',
    tiles: TL, bandset: BANDSET, more: MORE, moreLimit, growKeys: KEYS, grow: GROW,
    homes, mores, moresWithBirthday, growBandAges: growBands,
  };
  return JSON.stringify(doc, null, 1) + '\n';
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const text = await render();
  if (process.argv.includes('--print')) process.stdout.write(text);
  else if (process.argv.includes('--check')) {
    const have = existsSync(OUT) ? readFileSync(OUT, 'utf8').replace(/\r\n/g, '\n') : '';
    if (have !== text) { console.error('child_home_bands.json is stale: run node tools/gen-child-home-vectors.mjs'); process.exit(1); }
    console.log('child_home_bands.json is current');
  } else { writeFileSync(OUT, text); console.log('wrote ' + OUT); }
}
