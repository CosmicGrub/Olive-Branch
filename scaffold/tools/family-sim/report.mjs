#!/usr/bin/env node
// Build the self-contained final report page (embedded images + inline SVG charts) from a finished run.
//   node tools/family-sim/report.mjs <run-dir> [out.html] [--shots dir] [--sheet contact-sheet-dir]
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const run = process.argv[2]; if (!run) { console.error('usage: report.mjs <run-dir> [out.html]'); process.exit(2); }
const OUT = process.argv[3] && !process.argv[3].startsWith('--') ? process.argv[3] : join(run, 'report.html');
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const shotsDir = arg('shots', join(HERE, 'out', 'shots'));
const sheetDir = arg('sheet', join(HERE, '..', '..', 'client', 'build', 'family-sim-contact-sheet'));
const J = (f) => JSON.parse(readFileSync(join(run, f), 'utf8'));
const sum = J('summary.json'), lat = J('latency.json'), probes = J('probes.json'), gaps = J('gaps.json'), metrics = J('metrics.json'), fams = J('families.json');
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const h = sum.headline, iso = sum.isolation;

function chart(key, title, color, unit = '') {
  const pts = metrics.map((p) => p[key]).filter((v) => v != null); if (pts.length < 2) return '';
  const W = 520, H = 130, max = Math.max(...pts) * 1.1 || 1;
  const d = pts.map((v, i) => `${i ? 'L' : 'M'}${(i / (pts.length - 1) * W).toFixed(1)},${(H - 8 - v / max * (H - 16)).toFixed(1)}`).join(' ');
  return `<figure class="chart"><figcaption>${title} <span>last ${pts.at(-1)}${unit}, max ${Math.max(...pts)}${unit}</span></figcaption>
  <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${title}"><path d="${d}" fill="none" stroke="${color}" stroke-width="2"/></svg></figure>`;
}
const img = (file) => `data:${extname(file) === '.png' ? 'image/png' : 'image/jpeg'};base64,${readFileSync(file).toString('base64')}`;
const shots = existsSync(shotsDir) ? readdirSync(shotsDir).filter((f) => /\.(png|jpe?g)$/i.test(f)).sort() : [];
const sheet = existsSync(join(sheetDir, 'manifest.json')) ? JSON.parse(readFileSync(join(sheetDir, 'manifest.json'), 'utf8')) : [];

const latRows = Object.entries(lat).sort((a, b) => (b[1].p95 ?? 0) - (a[1].p95 ?? 0)).map(([k, v]) =>
  `<tr><td>${esc(k)}</td><td>${v.n}</td><td>${v.p50}</td><td>${v.p95}</td><td>${v.p99}</td><td>${v.max}</td><td>${esc(Object.entries(v.status ?? {}).map(([s, n]) => `${s}:${n}`).join(' '))}</td></tr>`).join('');
const missByRoute = {};
for (const m of probes.misses) { const k = m.route ?? m.name; (missByRoute[k] ??= { n: 0, ex: m }).n++; }
const missRows = Object.entries(missByRoute).map(([k, v]) => `<tr><td>${esc(k)}</td><td>${v.n}</td><td>${esc(v.ex.real ?? v.ex.status ?? '')}</td><td>${esc(v.ex.random ?? '')}</td><td>${esc(v.ex.evidence ?? '')}</td></tr>`).join('') || '<tr><td colspan="5">none</td></tr>';
const matrix = (() => {
  const n = fams.length; const cell = {}; for (const p of probes.pairs) cell[`${p.pair[0]}-${p.pair[1]}`] = p;
  let t = '<table class="mx"><tr><th></th>' + fams.map((f) => `<th>${f.n}</th>`).join('') + '</tr>';
  for (const a of fams) { t += `<tr><th>${a.n}</th>`; for (const b of fams) { const c = cell[`${a.n}-${b.n}`]; t += a.n === b.n ? '<td class="s"></td>' : `<td class="${c ? (c.missed ? 'bad' : 'ok') : ''}" title="${c ? `${c.blocked}/${c.total}` : ''}">${c ? (c.missed ? c.missed : '&#10003;') : ''}</td>`; } t += '</tr>'; }
  return t + '</table>';
})();
const noisy = sum.results.noisy, soak = sum.results.soak;
const tokenRows = probes.tokens.reduce((m, t) => { const k = t.name.replace(/family \d+ /, ''); (m[k] ??= { pass: 0, fail: 0 })[t.pass ? 'pass' : 'fail']++; return m; }, {});
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ten-Family Simulation Report</title>
<style>:root{--bg:#f6f4ec;--s:#fffdf7;--ink:#1f2a21;--mut:#5a665c;--line:#d9d5c4;--olive:#4a6b4f;--ok:#237a52;--okc:#dcf3e6;--bad:#b3322a;--badc:#fbe3e0;--warn:#8f6100;--warnc:#fcefcf}
@media(prefers-color-scheme:dark){:root{--bg:#141a15;--s:#1c241d;--ink:#e8efe6;--mut:#a3b0a4;--line:#33403a;--olive:#8fb596;--ok:#6ccf9d;--okc:#12301f;--bad:#f2a59d;--badc:#3a1a17;--warn:#ecc15c;--warnc:#34290c}}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Atkinson Hyperlegible",system-ui,sans-serif}main{max-width:1100px;margin:0 auto;padding:18px 16px 60px}
h1{color:var(--olive);margin:.2em 0}h2{color:var(--olive);margin-top:1.8em;border-bottom:1px solid var(--line);padding-bottom:4px}
.k{display:flex;flex-wrap:wrap;gap:10px}.k div{background:var(--s);border:1px solid var(--line);border-radius:12px;padding:8px 14px;min-width:130px}.k b{display:block;font-size:22px}.k span{font-size:12px;color:var(--mut)}
table{border-collapse:collapse;width:100%;font-size:13px;background:var(--s)}td,th{border:1px solid var(--line);padding:4px 7px;text-align:left;vertical-align:top}.wrap{overflow:auto}
table.mx{width:auto}table.mx td,table.mx th{text-align:center;min-width:30px}td.ok{background:var(--okc);color:var(--ok)}td.bad{background:var(--badc);color:var(--bad);font-weight:700}td.s{background:transparent}
.charts{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:12px}.chart{margin:0;background:var(--s);border:1px solid var(--line);border-radius:12px;padding:8px}.chart figcaption{font-weight:700;font-size:13px}.chart span{font-weight:400;color:var(--mut);margin-left:6px}svg{width:100%}
.gap{background:var(--warnc);border-left:5px solid var(--warn);padding:8px 12px;margin:8px 0;border-radius:8px}.gap code{font-size:12px;word-break:break-all}.fail{background:var(--badc);border-left:5px solid var(--bad);padding:8px 12px;margin:8px 0;border-radius:8px}
.shots{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:12px}.shots img{width:100%;border:1px solid var(--line);border-radius:10px}
.sheet{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}.sheet figure{margin:0;font-size:12px}.sheet img{width:100%;border:1px solid var(--line);border-radius:8px}
.pill{display:inline-block;padding:1px 9px;border-radius:99px;font-weight:700;font-size:12px}.pill.ok{background:var(--okc);color:var(--ok)}.pill.bad{background:var(--badc);color:var(--bad)}</style></head><body><main>
<h1>Ten-family simulation report</h1>
<p>${fams.length} synthetic families (1-2 guardians, 1-3 children aged 3-17, all four age bands) driven through the app's real server routes in an isolated throwaway stack. Run ${esc(sum.results.startedAt)}, ${h.durationSec} s, profile <code>${esc(sum.results.profile)}</code>.</p>
<div class="k"><div><b>${h.requests.toLocaleString()}</b><span>requests</span></div><div><b>${h.errors.fivexx}</b><span>5xx responses</span></div><div><b>${h.overall.p50} / ${h.overall.p95} / ${h.overall.p99}</b><span>p50 / p95 / p99 ms</span></div>
<div><b>${h.peak.rps}</b><span>peak req/s</span></div><div><b>${h.peak.serverRssMb} MB</b><span>peak server RSS</span></div><div><b>${h.peak.dbConns}</b><span>peak DB connections</span></div><div><b>${h.peak.serverCpu}%</b><span>peak server CPU</span></div>
<div><b>${h.stepsOk}/${h.stepsOk + h.stepsBad}</b><span>flow steps ok</span></div></div>

<h2>Isolation result <span class="pill ${h.isolation.misses ? 'bad' : 'ok'}">${h.isolation.misses ? h.isolation.misses + ' misses' : 'all blocked'}</span></h2>
<p>${iso.probesRun.toLocaleString()} probes: ${iso.routeSweep.total.toLocaleString()} route-sweep probes over ${iso.pairsRun} ordered family pairs (every route with <code>:childId</code>, attacker guardian and attacker child token, victim's REAL id vs a nonexistent id), ${iso.tokenProbes.total} token / pairing / invite / media / relay probes, ${iso.relayAndPairing.total} pairing-guess and websocket probes, ${iso.timing.total} timing comparisons (${iso.timing.flagged} flagged). A probe passes only if it is refused <em>and</em> the answer for a real foreign id is indistinguishable (status, body keys, error text) from the answer for a nonexistent id.</p>
<div class="wrap">${matrix}</div><p style="color:var(--mut);font-size:12px">Rows attack, columns are attacked. Tick = every probe refused uniformly; number = misses.</p>
<h3>Misses (grouped)</h3><div class="wrap"><table><tr><th>route / probe</th><th>count</th><th>real-id answer</th><th>random-id answer</th><th>evidence</th></tr>${missRows}</table></div>
<h3>Token, pairing, invite, media and relay probes</h3><div class="wrap"><table><tr><th>probe</th><th>pass</th><th>fail</th></tr>${Object.entries(tokenRows).map(([k, v]) => `<tr><td>${esc(k)}</td><td>${v.pass}</td><td>${v.fail}</td></tr>`).join('')}${[...probes.ws, ...probes.pairing].map((p) => `<tr><td>${esc(p.name)}${p.evidence ? ' <small>' + esc(p.evidence) + '</small>' : ''}</td><td>${p.pass ? 1 : 0}</td><td>${p.pass ? 0 : 1}</td></tr>`).join('')}</table></div>

<h2>Gaps in the onboarding / product chain</h2>
${gaps.gaps.map((g) => `<div class="gap"><b>${esc(g.id)}</b> ${esc(g.title)}<br><code>${esc((g.routes ?? []).join('  '))}</code><br><small>${esc(g.evidence)}</small></div>`).join('') || '<p>none</p>'}
<h2>Step failures</h2>
${(() => { const m = {}; for (const f of gaps.failures) { const k = `${f.id} ${f.route.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, ':id')} -> ${f.status}`; (m[k] ??= { n: 0, b: f.body }).n++; } return Object.entries(m).map(([k, v]) => `<div class="fail"><b>${v.n}x</b> ${esc(k)}<br><small>${esc(JSON.stringify(v.b)?.slice(0, 200))}</small></div>`).join('') || '<p>none</p>'; })()}

<h2>Performance</h2>
<div class="charts">${chart('p95', 'p95 latency (ms, rolling)', '#245f9c')}${chart('serverRssMb', 'server RSS (MB)', '#4a6b4f')}${chart('dbConns', 'DB connections', '#8f6100')}${chart('rps', 'requests / second', '#237a52')}${chart('serverCpu', 'server CPU %', '#b3322a')}</div>
<h3>Burst (all ten families at once)</h3><div class="wrap"><table><tr><th>round</th><th>ops</th><th>wall ms</th><th>req/s</th><th>p95 ms</th><th>5xx</th></tr>${(sum.results.burst ?? []).map((b) => `<tr><td>${b.round}</td><td>${b.ops}</td><td>${b.wallMs}</td><td>${b.rps}</td><td>${b.p95}</td><td>${b.bad}</td></tr>`).join('')}</table></div>
${noisy ? `<h3>Noisy neighbour (family ${noisy.noisyFamily} hammering)</h3><p>Other families: baseline p95 ${noisy.baseline.p95} ms over ${noisy.baseline.requests} requests; under attack p95 ${noisy.underAttack.p95} ms (x${noisy.victimP95Ratio}), ${noisy.underAttack.errors} errors. The hammering family made ${noisy.hammer.hammerOps.toLocaleString()} requests, ${noisy.hammer.hammer429.toLocaleString()} (${Math.round(noisy.hammer.hammer429 / Math.max(1, noisy.hammer.hammerOps) * 100)}%) were answered 429 by its own per-principal limiter. Starved: <b>${noisy.starved ? 'YES' : 'no'}</b>.</p>` : ''}
${soak ? `<h3>Soak</h3><p>${soak.secs} s of random activity from all families, ${soak.ops.toLocaleString()} operations.</p>` : ''}
<h3>Per-route latency (sorted by p95)</h3><div class="wrap"><table><tr><th>route</th><th>n</th><th>p50</th><th>p95</th><th>p99</th><th>max</th><th>statuses</th></tr>${latRows}</table></div>

<h2>The families</h2><div class="wrap"><table><tr><th>#</th><th>family</th><th>tz</th><th>shape</th><th>children</th><th>steps ok/bad</th></tr>${fams.map((f) => `<tr><td>${f.n}</td><td>${esc(f.name)}</td><td>${esc(f.tz)}</td><td>${f.guardians} guardian${f.guardians > 1 ? 's' : ''}${f.single ? ', single' : ''}${f.custody ? ', custody' : ''}${f.sitter ? ', sitter' : ''}</td><td>${f.kids.map((k) => `${esc(k.name)} ${k.age} (${k.band})`).join(', ')}</td><td>${f.ok}/${f.bad}</td></tr>`).join('')}</table></div>
${shots.length ? `<h2>Control room, key moments</h2><div class="shots">${shots.map((s) => `<figure style="margin:0"><img alt="${esc(s)}" src="${img(join(shotsDir, s))}"><figcaption>${esc(s.replace(/\.\w+$/, ''))}</figcaption></figure>`).join('')}</div>` : ''}
${sheet.length ? `<h2>Real-screen contact sheet</h2><p>The app's own screens, rendered by a Flutter widget test.</p><div class="sheet">${sheet.map((m) => `<figure><img alt="${esc(m.title)}" src="${img(join(sheetDir, m.file))}"><figcaption><b>${esc(m.title)}</b><br>${esc(m.who)}</figcaption></figure>`).join('')}</div>` : ''}
</main></body></html>`;
mkdirSync(dirname(OUT), { recursive: true }); writeFileSync(OUT, html);
console.log(`report: ${OUT} (${Math.round(html.length / 1024)} KB)`);
