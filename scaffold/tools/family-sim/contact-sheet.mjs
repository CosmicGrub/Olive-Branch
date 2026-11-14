#!/usr/bin/env node
// Assemble the PNGs written by client/test/family_sim_contact_sheet_test.dart into ONE self-contained
// HTML contact sheet (images embedded as data URIs).
//   (cd client && flutter test -j 2 test/family_sim_contact_sheet_test.dart) && node tools/family-sim/contact-sheet.mjs [out.html]
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..', '..', 'client', 'build', 'family-sim-contact-sheet');
const OUT = process.argv[2] ?? join(HERE, 'out', 'contact-sheet.html');
if (!existsSync(join(SRC, 'manifest.json'))) { console.error('no manifest: run the flutter contact-sheet test first'); process.exit(2); }
const manifest = JSON.parse(readFileSync(join(SRC, 'manifest.json'), 'utf8'));
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const cards = manifest.map((m) => `<figure><img alt="${esc(m.title)}" src="data:image/png;base64,${readFileSync(join(SRC, m.file)).toString('base64')}"><figcaption><b>${esc(m.title)}</b><br>${esc(m.who)}</figcaption></figure>`).join('\n');
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Olive Real-Screen Contact Sheet</title>
<style>:root{--bg:#f6f4ec;--ink:#1f2a21;--line:#d9d5c4;--olive:#4a6b4f}@media(prefers-color-scheme:dark){:root{--bg:#141a15;--ink:#e8efe6;--line:#33403a;--olive:#8fb596}}
body{margin:0;padding:16px;background:var(--bg);color:var(--ink);font:15px/1.4 system-ui,sans-serif}h1{color:var(--olive);margin:0 0 4px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px;margin-top:14px}figure{margin:0;border:1px solid var(--line);border-radius:14px;padding:10px}
img{width:100%;height:auto;border-radius:8px;border:1px solid var(--line);background:#fff}figcaption{margin-top:6px;font-size:13px}</style></head>
<body><h1>Real-screen contact sheet</h1><p>The app's own screens, rendered by a Flutter widget test (not mock-ups) for synthetic families and ages from the simulation. Generated ${new Date().toISOString().slice(0, 10)}.</p>
<div class="grid">${cards}</div></body></html>`;
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, html);
console.log(`contact sheet: ${OUT} (${manifest.length} screens)`);
